#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# selftest.sh [WORKDIR]: host-side regression checks of the baseline's helpers. Touches no device and
# needs no root; Linux host (GNU dd, util-linux hexdump/sfdisk, gdisk's sgdisk, dosfstools,
# exfatprogs). What it cannot check is listed in README §7 (QEMU and hardware items).
#   1. every shell script parses with sh -n and dash -n; shellcheck findings (if installed) are printed
#   2. no dropbear command line passes -s, -g, -t, -w or -B (password logins must stay on)        [B2]
#   3. no .DS_Store / ._* in the tree that build.sh packs from                                       [B7]
#   4. usb-mount --plan on synthetic sticks: MBR FAT32, GPT ESP+FAT32, MBR exFAT, MBR ESP(0xEF)+FAT32,
#      FAT on the whole disk, protective MBR without GPT, extended-only MBR, a non-FAT partition
#   5. flash-kernel / flash-rootfs against plain files standing in for the MTDs (MTD_SYS, MTD_DEV):
#      every refusal is exit 4 with nothing written, "already installed" is exit 3, a dry run is 0   [B3]
#   6. build.sh's default ROOT_PASSWORD_HASH is sha512-crypt of 'baseline' (needs openssl)
#   7. stage_kernel.py --self-test (AES, layout, appended-DTB refusal, sysfs-like chip-ID reads)  [B1, B4]
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
W=${1:-$(mktemp -d /tmp/baseline-selftest.XXXXXX)}
mkdir -p "$W"
fails=0
pass() { printf '  %-74s ok\n' "$1"; }
fail() { printf '  %-74s FAIL\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; fails=$((fails + 1)); }
check() { # check NAME CMD...
    _n=$1
    shift
    if "$@" > "$W/out" 2>&1; then pass "$_n"; else fail "$_n" "$(tail -n 5 "$W/out")"; fi
}
have() { command -v "$1" > /dev/null 2>&1; }
for t in hexdump dd sha256sum truncate; do
    have "$t" || { echo "selftest: needs $t (Debian: bsdextrautils for hexdump)" >&2; exit 2; }
done

SCRIPTS=$(cd "$HERE" && for f in build.sh common/recipes/userspace.sh common/shared/* common/rootfs/init \
    common/rootfs/etc/init.d/rcS common/rootfs/etc/profile common/rootfs/usr/sbin/* arm-imx6ul/initramfs/* \
    arm-imx6ul/rootfs/etc/baseline/board-rcS.sh arm-imx6ul/rootfs/usr/sbin/* arm-imx6ul/board.env \
    common/usb-ids.conf common/ncm.conf common/versions.env common/tools/selftest.sh; do
    [ -f "$f" ] && [ ! -L "$f" ] && echo "$f"; done)

echo "1. syntax"
for f in $SCRIPTS; do
    check "sh -n $f" sh -n "$HERE/$f"
    have dash && check "dash -n $f" dash -n "$HERE/$f"
done
if have shellcheck; then
    # -s sh: POSIX; SC3045 (read -t, busybox ash), SC1090/SC1091 (sourced files on the unit) are expected
    (cd "$HERE" && shellcheck -s sh -f gcc -e SC1090,SC1091,SC3045 $SCRIPTS) > "$W/shellcheck.txt" 2>&1
    echo "  shellcheck: $(grep -c ': error:' "$W/shellcheck.txt") errors, $(grep -c ': warning:' "$W/shellcheck.txt") warnings ($W/shellcheck.txt)"
else
    echo "  shellcheck: not installed, skipped"
fi

echo "2. dropbear options"
# every line that RUNS dropbear (not comments, not the C header), then the options on it
runs=$(cd "$HERE" && grep -rn -E '^[[:space:]]*(if ! |exec )?dropbear( |$)' common arm-imx6ul build.sh)
bad=$(printf '%s\n' "$runs" | grep -E ' -[a-zA-Z]*[sgtwB][a-zA-Z]*( |$)' || true)
if [ -n "$runs" ] && [ -z "$bad" ]; then pass "dropbear runs without -s/-g/-t/-w/-B ($(printf '%s\n' "$runs" | wc -l) call site)"
else fail "dropbear option that disables a login method (or no call site found)" "${bad:-$runs}"; fi

echo "3. macOS metadata"
ds=$(find "$HERE" \( -name .DS_Store -o -name '._*' \) -print)
if [ -z "$ds" ]; then pass "no .DS_Store / ._* under $HERE"; else
    echo "  NOTE (not a failure: build.sh strips them from the rootfs and checks): $ds"; fi

echo "4. usb-mount --plan"
UM=$HERE/common/shared/usb-mount
if have sfdisk && have sgdisk && have mkfs.vfat && have mkfs.exfat; then
    I=$W/img
    rm -rf "$I"
    mkdir -p "$I"
    fsimg() { # fsimg FILE MiB TYPE
        rm -f "$1"
        truncate -s "${2}M" "$1"
        case $3 in
            fat32) mkfs.vfat -F 32 -s 1 -n DATA "$1" > /dev/null ;;
            fat16) mkfs.vfat -F 16 -n ESP "$1" > /dev/null ;;
            exfat) mkfs.exfat -L DATA "$1" > /dev/null ;;
        esac
    }
    put() { dd if="$2" of="$1" bs=512 seek="$3" conv=notrunc 2> /dev/null; } # put DISK FS LBA
    # MBR, FAT32 at 2048
    truncate -s 48M "$I/mbr-fat32.img"
    printf 'label: dos\nstart=2048, size=40M, type=c\n' | sfdisk -q "$I/mbr-fat32.img"
    fsimg "$I/p.img" 40 fat32 && put "$I/mbr-fat32.img" "$I/p.img" 2048
    # GPT: ESP (FAT32) first, data FAT32 second
    truncate -s 100M "$I/gpt-esp-fat32.img"
    sgdisk -n1:2048:+40M -t1:ef00 -n2:0:+40M -t2:0700 "$I/gpt-esp-fat32.img" > /dev/null
    fsimg "$I/p.img" 40 fat32 && put "$I/gpt-esp-fat32.img" "$I/p.img" 2048
    p2=$(sgdisk -i 2 "$I/gpt-esp-fat32.img" | sed -n 's/^First sector: \([0-9]*\).*/\1/p')
    fsimg "$I/p.img" 40 fat32 && put "$I/gpt-esp-fat32.img" "$I/p.img" "$p2"
    # MBR, exFAT (type 7)
    truncate -s 40M "$I/mbr-exfat.img"
    printf 'label: dos\nstart=2048, size=32M, type=7\n' | sfdisk -q "$I/mbr-exfat.img"
    fsimg "$I/p.img" 32 exfat && put "$I/mbr-exfat.img" "$I/p.img" 2048
    # MBR: ESP type 0xEF (FAT16) first, FAT32 data second
    truncate -s 64M "$I/mbr-esp-fat32.img"
    printf 'label: dos\nstart=2048, size=16M, type=ef\nstart=34816, size=40M, type=c\n' | sfdisk -q "$I/mbr-esp-fat32.img"
    fsimg "$I/p.img" 16 fat16 && put "$I/mbr-esp-fat32.img" "$I/p.img" 2048
    fsimg "$I/p.img" 40 fat32 && put "$I/mbr-esp-fat32.img" "$I/p.img" 34816
    # FAT on the whole disk
    fsimg "$I/whole-fat16.img" 16 fat16
    # protective MBR (0xEE) with no GPT header behind it
    truncate -s 8M "$I/protective-only.img"
    printf 'label: dos\nstart=1, size=16383, type=ee\n' | sfdisk -q "$I/protective-only.img" 2> /dev/null
    # extended container only (a logical FAT inside)
    truncate -s 48M "$I/mbr-extended.img"
    printf 'label: dos\nstart=2048, size=44M, type=5\nstart=4096, size=40M, type=c\n' | sfdisk -q "$I/mbr-extended.img"
    # a partition without FAT/exFAT
    truncate -s 16M "$I/mbr-nofs.img"
    printf 'label: dos\nstart=2048, size=8M, type=83\n' | sfdisk -q "$I/mbr-nofs.img"

    plan() { # plan IMG EXPECT_RC GREP...
        _img=$1 _rc=$2
        shift 2
        dash "$UM" --plan "$I/$_img" > "$W/plan.$_img" 2>&1
        _got=$?
        [ "$_got" = "$_rc" ] || { fail "plan $_img: exit $_got, wanted $_rc" "$(cat "$W/plan.$_img")"; return; }
        for _g in "$@"; do
            grep -q -- "$_g" "$W/plan.$_img" || { fail "plan $_img: no '$_g'" "$(cat "$W/plan.$_img")"; return; }
        done
        pass "plan $_img: $(grep -m1 'WOULD MOUNT' "$W/plan.$_img" | sed 's/.*WOULD MOUNT/WOULD MOUNT/; s/ read-write.*//' || true)"
    }
    plan mbr-fat32.img 0 "partition 1 at LBA 2048 (mbr:0c): fat32: WOULD MOUNT"
    plan gpt-esp-fat32.img 0 "partition 1 .*EFI System Partition, skipped" "partition 2 .*fat32: WOULD MOUNT"
    plan mbr-exfat.img 0 "partition 1 at LBA 2048 (mbr:07): exfat: WOULD MOUNT"
    plan mbr-esp-fat32.img 0 "partition 1 .*(mbr:ef): EFI System Partition, skipped" "partition 2 .*fat32: WOULD MOUNT"
    plan whole-fat16.img 0 "fat16 on the whole image"
    plan protective-only.img 1 "protective MBR (0xEE) but no GPT header"
    plan mbr-extended.img 1 "extended partition container, skipped" "judged on a device only"
    plan mbr-nofs.img 1 "no FAT/exFAT boot sector, skipped"
    echo "  (stick images kept in $I for the QEMU test)"
else
    echo "  SKIPPED: needs sfdisk, sgdisk, mkfs.vfat, mkfs.exfat"
fi

echo "5. flash helpers against stand-in MTDs"
F=$W/flash
rm -rf "$F"
mkdir -p "$F/sys" "$F/dev" "$F/lib" "$F/etc" "$F/run"
. "$HERE/arm-imx6ul/board.env"
# The helpers source fixed paths on the unit; the copies here point them into $F.
for f in flash-kernel flash-rootfs flash-lib.sh; do
    sed -e "s|/lib/baseline/|$F/lib/|g" -e "s|/etc/baseline/|$F/etc/|g" -e "s|/run/flash-|$F/run/flash-|g" \
        "$HERE/arm-imx6ul/initramfs/$f" > "$F/lib/$f"
done
cp "$HERE/common/shared/mtd.sh" "$F/lib/mtd.sh"
cp "$HERE/arm-imx6ul/board.env" "$F/etc/board.env"
mtd() { # mtd N NAME SIZE OFFSET
    mkdir -p "$F/sys/mtd$1"
    echo "$2" > "$F/sys/mtd$1/name"
    echo "$3" > "$F/sys/mtd$1/size"
    echo "$4" > "$F/sys/mtd$1/offset"
    echo 65536 > "$F/sys/mtd$1/erasesize"
}
rnd() { head -c "$1" /dev/urandom; }
ff() { head -c "$1" /dev/zero | tr '\0' '\377'; }
mtd 0 uboot 196608 0;               rnd 196608 > "$F/dev/mtd0"
mtd 1 env 65536 196608;             rnd 65536 > "$F/dev/mtd1"
mtd 2 kernel "$KERNEL_PART_SIZE" "$KERNEL_FLASH_OFFSET"
mtd 3 rootfs "$ROOTFS_PART_SIZE" 3670016; ff 1048576 > "$F/dev/mtd3"
mtd 5 bootstate 65536 16711680;     ff 65536 > "$F/dev/mtd5"
H=196608
rnd $H > "$F/h0"; rnd $H > "$F/h1"; rnd $H > "$F/s1"
rnd $((STAGING_PART_OFFSET - H)) > "$F/b1"; rnd $((STAGING_PART_OFFSET - H)) > "$F/b2"
tailff=$((KERNEL_PART_SIZE - STAGING_PART_OFFSET - H))
# image staged from the current partition: current head h0, new body b1, staged head s1
{ cat "$F/h0" "$F/b1" "$F/s1"; ff $tailff; } > "$F/img1"
{ cat "$F/h0" "$F/b1"; ff $((H + tailff)); } > "$F/img-nostage"
{ cat "$F/h0" "$F/b2"; ff $((H + tailff)); } > "$F/cur-old"
sha() { sha256sum "$1" | cut -d' ' -f1; }
fk() { # fk EXPECT NAME ARGS...: flash-kernel on stand-ins, exit status checked, partition unchanged
    _want=$1 _name=$2
    shift 2
    _before=$(sha "$F/dev/mtd2")
    MTD_SYS=$F/sys MTD_DEV=$F/dev sh "$F/lib/flash-kernel" "$@" > "$W/fk.out" 2>&1
    _rc=$?
    if [ "$_rc" = "$_want" ] && [ "$(sha "$F/dev/mtd2")" = "$_before" ]; then pass "flash-kernel $_name: exit $_rc"
    else fail "flash-kernel $_name: exit $_rc (wanted $_want)" "$(cat "$W/fk.out")"; fi
}
cp "$F/cur-old" "$F/dev/mtd2"
fk 0 "fresh install, --dry-run" --dry-run "$F/img1" "$(sha "$F/img1")"
grep -q "dry run: would write" "$W/fk.out" || fail "flash-kernel dry run says what it would write" "$(cat "$W/fk.out")"
fk 4 "wrong sha256 (nothing written)" "$F/img1" "$(sha "$F/img-nostage")"
fk 4 "no staged head" "$F/img-nostage" "$(sha "$F/img-nostage")"
fk 4 "short image" "$F/h0" "$(sha "$F/h0")"
# after a successful install: U-Boot rewrote the head (h1), the rest is img1
{ cat "$F/h1"; tail -c +$((H + 1)) "$F/img1"; } > "$F/dev/mtd2"
fk 3 "already installed, --if-changed (the B3 stale-stick case)" --if-changed "$F/img1" "$(sha "$F/img1")"
grep -q "already runs this kernel" "$W/fk.out" || fail "flash-kernel names the installed state" "$(cat "$W/fk.out")"
fk 3 "already installed, manual run" "$F/img1" "$(sha "$F/img1")"
# head AND body differ: staged from another dump / for another unit
{ cat "$F/h1" "$F/b2"; ff $((H + tailff)); } > "$F/dev/mtd2"
fk 4 "stale image (head and body differ)" --if-changed "$F/img1" "$(sha "$F/img1")"
grep -q "staged from another dump" "$W/fk.out" || fail "flash-kernel names the stale state" "$(cat "$W/fk.out")"
# partition already equal to the image
cp "$F/img1" "$F/dev/mtd2"
fk 3 "partition already holds the image, --if-changed" --if-changed "$F/img1" "$(sha "$F/img1")"
fk 0 "partition already holds the image, --dry-run (would erase env)" --dry-run "$F/img1" "$(sha "$F/img1")"
# env not where U-Boot keeps it
echo 131072 > "$F/sys/mtd1/offset"
fk 4 "env MTD at the wrong flash offset" --dry-run "$F/img1" "$(sha "$F/img1")"
echo 196608 > "$F/sys/mtd1/offset"
fk 2 "usage" "$F/img1"
# flash-rootfs refusals
printf 'hsqs' > "$F/rootfs.img"; head -c 4092 /dev/zero >> "$F/rootfs.img"
printf 'nope' > "$F/bad.img"; head -c 4092 /dev/zero >> "$F/bad.img"
fr() { _want=$1 _name=$2; shift 2
    MTD_SYS=$F/sys MTD_DEV=$F/dev sh "$F/lib/flash-rootfs" "$@" > "$W/fr.out" 2>&1
    _rc=$?
    if [ "$_rc" = "$_want" ]; then pass "flash-rootfs $_name: exit $_rc"; else fail "flash-rootfs $_name: exit $_rc (wanted $_want)" "$(cat "$W/fr.out")"; fi
}
fr 4 "no squashfs magic" "$F/bad.img" "$(sha "$F/bad.img")"
fr 4 "wrong sha256" "$F/rootfs.img" "$(sha "$F/bad.img")"
head -c 4096 "$F/rootfs.img" > "$F/dev/mtd3.new" && ff 1044480 >> "$F/dev/mtd3.new" && mv "$F/dev/mtd3.new" "$F/dev/mtd3"
fr 3 "already on flash, --if-changed" --if-changed "$F/rootfs.img" "$(sha "$F/rootfs.img")"

echo "6. default password hash"
if have openssl; then
    want=$(sed -n "s/^DEV_PASSWORD_HASH='\(.*\)'$/\1/p" "$HERE/build.sh")
    got=$(openssl passwd -6 -salt ccpabaseline baseline)
    if [ -n "$want" ] && [ "$want" = "$got" ]; then pass "DEV_PASSWORD_HASH = sha512-crypt('baseline')"; else fail "DEV_PASSWORD_HASH" "$want / $got"; fi
else
    echo "  SKIPPED: no openssl"
fi

echo "7. stage_kernel.py --self-test"
if python3 -I "$HERE/arm-imx6ul/tools/stage_kernel.py" --self-test > "$W/stage.txt" 2>&1; then
    pass "stage_kernel.py --self-test ($(grep -c ' ok$' "$W/stage.txt") checks)"
else
    fail "stage_kernel.py --self-test" "$(grep -v ' ok$' "$W/stage.txt")"
fi

echo "selftest: $([ "$fails" = 0 ] && echo PASS || echo "FAIL ($fails)") (work dir $W)"
[ "$fails" = 0 ]

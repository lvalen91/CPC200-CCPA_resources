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
#   7. stage_kernel.py --self-test (AES, layout, appended-DTB refusal, sysfs-like chip-ID reads,
#      the update env's second CRC)                                                       [B1, B4, B12]
#   8. radio, wifi-connect, wifi-scan, bt-scan against a stand-in sysfs/run and stub tools: module
#      load order, interface wording, the radio-down messages, wifi-connect's /run-only config and dry
#      run, the scan tables, bt-scan's LE enable and BR/EDR-only retry; nothing in the boot path starts a
#      radio                                                                           [B10, B11, B15-B18]
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
    arm-imx6ul/rootfs/etc/baseline/board-rcS.sh arm-imx6ul/rootfs/etc/baseline/udhcpc.sh \
    arm-imx6ul/rootfs/lib/baseline/radio-lib.sh arm-imx6ul/rootfs/usr/sbin/* arm-imx6ul/board.env \
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

echo "8. radio helpers against stand-ins (B10 module order, B11 wording, B15 wifi-connect, B16 wifi-scan, B17/B18 bt-scan)"
R=$W/radio
rm -rf "$R"
A=$HERE/arm-imx6ul/rootfs
mkdir -p "$R/bin" "$R/lib" "$R/etc" "$R/mod" "$R/run" "$R/sys0/class/net/usb0" "$R/sys/class/net/usb0" \
    "$R/sys/class/net/mlan0/phy80211" "$R/sys/class/regulator/regulator.1" "$R/sys/bus/sdio/devices/mmc0:0001:1" \
    "$R/sys/bus/platform/drivers/sdhci-esdhc-imx/2190000.mmc" "$R/sys/class/bluetooth"
cp "$A/lib/baseline/radio-lib.sh" "$R/lib/"
cp "$HERE/arm-imx6ul/board.env" "$R/etc/board.env"
for d in sys sys0; do printf '0x1003\n' > "$R/$d/class/net/usb0/flags"; echo up > "$R/$d/class/net/usb0/operstate"; echo 1 > "$R/$d/class/net/usb0/carrier"; done
printf '0x1003\n' > "$R/sys/class/net/mlan0/flags"
echo down > "$R/sys/class/net/mlan0/operstate"
echo 0 > "$R/sys/class/net/mlan0/carrier"
echo 02:00:00:00:00:01 > "$R/sys/class/net/mlan0/address"
echo wlan > "$R/sys/class/regulator/regulator.1/name"
echo enabled > "$R/sys/class/regulator/regulator.1/state"
echo 1 > "$R/sys/class/regulator/regulator.1/num_users"
echo 0x02df > "$R/sys/bus/sdio/devices/mmc0:0001:1/vendor"
echo 0x9159 > "$R/sys/bus/sdio/devices/mmc0:0001:1/device"
# modules.dep in kmod's form (every transitive dependency on the line); btnxpuart's line deliberately lists
# the most basic module FIRST, to show the loader does not depend on the order on a line
cat > "$R/mod/modules.dep" << 'EOF'
kernel/net/wireless/cfg80211.ko:
kernel/drivers/net/wireless/marvell/mwifiex/mwifiex.ko: kernel/net/wireless/cfg80211.ko
kernel/drivers/net/wireless/marvell/mwifiex/mwifiex_sdio.ko: kernel/drivers/net/wireless/marvell/mwifiex/mwifiex.ko kernel/net/wireless/cfg80211.ko
kernel/crypto/ecc.ko:
kernel/crypto/ecdh_generic.ko: kernel/crypto/ecc.ko
kernel/net/bluetooth/bluetooth.ko: kernel/crypto/ecdh_generic.ko kernel/crypto/ecc.ko
kernel/lib/crc8.ko:
kernel/drivers/bluetooth/btnxpuart.ko: kernel/crypto/ecc.ko kernel/lib/crc8.ko kernel/net/bluetooth/bluetooth.ko kernel/crypto/ecdh_generic.ko
kernel/drivers/mmc/core/mmc_core.ko:
kernel/drivers/mmc/host/cqhci.ko: kernel/drivers/mmc/core/mmc_core.ko
kernel/drivers/mmc/host/sdhci.ko: kernel/drivers/mmc/core/mmc_core.ko
kernel/drivers/mmc/host/sdhci-pltfm.ko: kernel/drivers/mmc/host/sdhci.ko kernel/drivers/mmc/core/mmc_core.ko
kernel/drivers/mmc/host/sdhci-esdhc-imx.ko: kernel/drivers/mmc/host/sdhci-pltfm.ko kernel/drivers/mmc/host/cqhci.ko kernel/drivers/mmc/host/sdhci.ko kernel/drivers/mmc/core/mmc_core.ko
EOF
# stubs: insmod refuses (like the kernel's "Unknown symbol") a module whose dependencies are not loaded
cat > "$R/bin/insmod" << EOF
#!/bin/sh
m=\${1##*/}; m=\${m%%.ko*}; m=\$(echo "\$m" | tr - _); shift
line=\$(awk -v m="\$m" '{ n=\$1; sub(/:\$/,"",n); sub(/.*\//,"",n); sub(/\.ko.*/,"",n); gsub(/-/,"_",n); if (n==m) { print; exit } }' "$R/mod/modules.dep")
for d in \${line#*:}; do d=\${d##*/}; d=\$(echo "\${d%%.ko*}" | tr - _)
    grep -q "^\$d " "$R/proc_modules" || { echo "\$m: Unknown symbol (needs \$d)" >> "$R/unknown.log"; exit 1; }; done
grep -q "^\$m " "$R/proc_modules" && exit 1
echo "\$m 16384 0 - Live 0x0" >> "$R/proc_modules"
echo "\$m\${*:+ \$*}" >> "$R/order.log"
EOF
cat > "$R/bin/iw" << 'EOF'
#!/bin/sh
case "$*" in
    *" link") echo "Not connected." ;;
    *" info") echo "Interface $2"; echo "	type managed" ;;
    *" scan"*) cat << 'SCAN'
BSS 02:11:22:33:44:01(on mlan0)
	freq: 2437.0
	signal: -71.00 dBm
	SSID: CafeOpen
	capability: ESS ShortSlotTime (0x0401)
BSS 02:11:22:33:44:02(on mlan0) -- associated
	freq: 5180
	signal: -42.00 dBm
	capability: ESS Privacy ShortSlotTime (0x0411)
	SSID: Home Net
	RSN:	 * Version: 1
		 * Group cipher: CCMP
		 * Pairwise ciphers: CCMP
		 * Authentication suites: PSK SAE
		 * Capabilities: 16-PTKSA-RC 1-GTKSA-RC MFP-capable (0x008c)
BSS 02:11:22:33:44:03(on mlan0)
	freq: 2412
	signal: -55.00 dBm
	capability: ESS Privacy (0x0011)
	SSID: Wpa3Only
	RSN:	 * Version: 1
		 * Authentication suites: SAE
BSS 02:11:22:33:44:04(on mlan0)
	freq: 2462
	signal: -80.00 dBm
	capability: ESS Privacy (0x0011)
	SSID:
	RSN:	 * Version: 1
		 * Authentication suites: PSK
	WMM:	 * Parameter version 1
		 * Authentication suites: SAE
BSS 02:11:22:33:44:05(on mlan0)
	freq: 5500
	signal: -60.00 dBm
	capability: ESS Privacy (0x0011)
	SSID: Corp
	RSN:	 * Version: 1
		 * Authentication suites: IEEE 802.1X
SCAN
        ;;
esac
EOF
cat > "$R/bin/ip" << EOF
#!/bin/sh
echo "ip \$*" >> "$R/ip.log"
case "\$*" in "route del"*) exit 1 ;; esac
case "\$*" in *"addr show dev"*) [ -s "$R/run/ipaddr" ] && echo "    inet \$(cat "$R/run/ipaddr") scope global \$5" ;; esac
exit 0
EOF
cat > "$R/bin/wpa_passphrase" << 'EOF'
#!/bin/sh
exec python3 -I -c '
import hashlib, sys
p = sys.stdin.readline().rstrip("\n")
print("network={\n\tssid=\"%s\"\n\t#psk=\"%s\"\n\tpsk=%s\n}" % (sys.argv[1], p,
      hashlib.pbkdf2_hmac("sha1", p.encode(), sys.argv[1].encode(), 4096, 32).hex()))' "$1"
EOF
cat > "$R/bin/wpa_supplicant" << EOF
#!/bin/sh
echo "wpa_supplicant \$*" >> "$R/daemons.log"
while [ \$# -gt 0 ]; do case \$1 in -P) pf=\$2; shift ;; -i) ifn=\$2; shift ;; esac; shift; done
sh -c 'sleep 60; :' wpa_supplicant > /dev/null 2>&1 &
echo \$! > "\$pf"
mkdir -p "$R/run/wpa_supplicant" && : > "$R/run/wpa_supplicant/\$ifn"
EOF
cat > "$R/bin/wpa_cli" << 'EOF'
#!/bin/sh
printf 'bssid=02:11:22:33:44:02\nfreq=5180\nssid=Home Net\nid=0\nmode=station\npairwise_cipher=CCMP\nkey_mgmt=WPA2-PSK\nwpa_state=COMPLETED\n'
EOF
cat > "$R/bin/udhcpc" << EOF
#!/bin/sh
echo "udhcpc \$*" >> "$R/daemons.log"
while [ \$# -gt 0 ]; do case \$1 in -p) pf=\$2; shift ;; -s) sc=\$2; shift ;; -i) ifn=\$2; shift ;; esac; shift; done
sh -c 'sleep 60; :' udhcpc > /dev/null 2>&1 &
echo \$! > "\$pf"
interface=\$ifn ip=192.168.1.50 mask=24 router=192.168.1.1 dns=192.168.1.1 RADIO_RUN="$R/run" sh "\$sc" bound > /dev/null
echo 192.168.1.50/24 > "$R/run/ipaddr"
EOF
# btmgmt stand-in, stateful in $R/bt: settings as the IW416 unit reports them after `radio up` ("powered
# br/edr", LE off), `le on` sets LE when "supported" has it, and find follows the kernel's rule (interleaved
# and LE-only need LE on: status 0x0b Rejected); $R/bt/reject refuses every find but -b
mkdir -p "$R/bt"
cat > "$R/bin/btmgmt" << EOF
#!/bin/sh
echo "btmgmt \$*" >> "$R/daemons.log"
cur=\$(cat "$R/bt/current" 2>/dev/null || echo "powered br/edr ")
sup=\$(cat "$R/bt/supported" 2>/dev/null || echo "powered connectable discoverable bondable ssp br/edr le secure-conn ")
case "\$*" in
    *" info")
        printf 'hci0:\tPrimary controller\n\taddr AA:BB:CC:DD:EE:FF version 9 manufacturer 37 class 0x000000\n'
        printf '\tsupported settings: %s\n\tcurrent settings: %s\n\tname \n' "\$sup" "\$cur"; exit 0 ;;
    *" le on")
        case " \$sup " in *" le "*) echo "\${cur}le " > "$R/bt/current"; echo "hci0 Set Low Energy complete, settings: \${cur}le "; exit 0 ;; esac
        echo "Set Low Energy for hci0 failed with status 0x0c (Not Supported)"; exit 1 ;;
    *" find -b") ;;
    *" find"*)
        [ -e "$R/bt/reject" ] && { echo "Unable to start discovery. status 0x0b (Rejected)"; exit 1; }
        case " \$cur " in *" le "*) ;; *) echo "Unable to start discovery. status 0x0b (Rejected)"; exit 1 ;; esac ;;
esac
printf 'Discovery started\nhci0 type 7 discovering on\n'
case "\$*" in *" find -b") ;; *)
printf 'hci0 dev_found: AA:BB:CC:00:00:01 type LE Random rssi -71 flags 0x0004 \nAD flags 0x06 \nname Tag One\n' ;; esac
printf 'hci0 dev_found: AA:BB:CC:00:00:02 type BR/EDR rssi -50 flags 0x0000 \nname Phone\n'
case "\$*" in *" find -b") ;; *)
printf 'hci0 dev_found: AA:BB:CC:00:00:01 type LE Random rssi -69 flags 0x0004 \nAD flags 0x06 \neir_len 12\n' ;; esac
printf 'hci0 type 7 discovering off\n'
EOF
printf '#!/bin/sh\necho "hci0: UP, bdaddr aa:bb:cc:dd:ee:ff, acl_mtu 1021:8, cmd_tx 1 evt_rx 1"\n' > "$R/bin/hciup"
printf '#!/bin/sh\nexit 0\n' > "$R/bin/usleep"
chmod 0755 "$R/bin/"*
for s in radio wifi-connect wifi-scan bt-scan; do cp "$A/usr/sbin/$s" "$R/$s"; done
cp "$A/etc/baseline/udhcpc.sh" "$R/udhcpc.sh"
: > "$R/proc_modules"
: > "$R/unknown.log"
: > "$R/order.log"
RXS=$R/sys
# the helpers run under dash where it exists (Debian), else sh (BusyBox ash on Alpine, the unit's shell)
RXSH=$(command -v dash || echo sh)
echo "  (helpers run with $RXSH)"
rx() { # rx SCRIPT ARGS...: a helper against the stand-ins (sysfs $RXS), output in $W/rx.out
    _rxs=$1
    shift
    env PATH="$R/bin:$PATH" RADIO_SYS="$RXS" RADIO_RUN="$R/run" RADIO_LIB="$R/lib" RADIO_ETC="$R/etc" \
        MODLOAD_DIR="$R/mod" MODLOAD_PROC="$R/proc_modules" WIFI_DHCP_SCRIPT="$R/udhcpc.sh" WIFI_TIMEOUT=3 \
        "$RXSH" "$R/$_rxs" "$@" > "$W/rx.out" 2>&1
}
has() { grep -q -- "$1" "$W/rx.out"; }
# B10: the stub refuses out-of-order loads, the loader never triggers that
"$R/bin/insmod" "$R/mod/kernel/drivers/net/wireless/marvell/mwifiex/mwifiex_sdio.ko"
if [ -s "$R/unknown.log" ]; then pass "B10 stand-in insmod refuses a module before its dependencies"; else fail "B10 stand-in insmod check"; fi
: > "$R/unknown.log"
env MODLOAD_DIR="$R/mod" MODLOAD_PROC="$R/proc_modules" PATH="$R/bin:$PATH" "$RXSH" -c ". '$R/lib/radio-lib.sh'
    mod_load mwifiex driver_mode=0x3 && mod_load mwifiex_sdio && mod_load btnxpuart && mod_load sdhci-esdhc-imx &&
    mod_load mwifiex driver_mode=0x1" > "$W/ml.out" 2>&1
want="cfg80211
mwifiex driver_mode=0x3
mwifiex_sdio
ecc
crc8
ecdh_generic
bluetooth
btnxpuart
mmc_core
cqhci
sdhci
sdhci_pltfm
sdhci_esdhc_imx"
if [ ! -s "$R/unknown.log" ] && [ "$(cat "$R/order.log")" = "$want" ]; then
    pass "B10 mod_load: dependencies first, parameters on the module, no out-of-order insmod"
else fail "B10 mod_load order" "$(cat "$R/order.log" "$R/unknown.log" "$W/ml.out")"; fi
grep -q "mwifiex is already loaded: driver_mode=0x1 not applied" "$W/ml.out" \
    && pass "B10 mod_load says a parameter of an already loaded module is not applied" || fail "B10 already-loaded note" "$(cat "$W/ml.out")"
# B11: radio status and radio up use one wording (admin state, carrier, operstate)
rx radio status
has "wireless interface mlan0: administratively up, no carrier (operstate down), 02:00:00:00:00:01" \
    && pass "B11 radio status: 'administratively up, no carrier (operstate down)'" || fail "B11 radio status wording" "$(cat "$W/rx.out")"
: > "$R/proc_modules"; : > "$R/order.log"
rx radio up
if has "Wi-Fi: mlan0 administratively up, no carrier (operstate down)" && ! grep -q "mlan0 up (" "$W/rx.out"; then
    pass "B11 radio up: the same wording, no bare 'mlan0 up'"; else fail "B11 radio up wording" "$(cat "$W/rx.out")"; fi
[ "$(cat "$R/order.log")" = "cfg80211
mwifiex
mwifiex_sdio" ] && [ ! -s "$R/unknown.log" ] && pass "B10 radio up (IW416 stand-in): cfg80211, mwifiex, mwifiex_sdio in that order" \
    || fail "B10 radio up load order" "$(cat "$R/order.log" "$R/unknown.log")"
printf '0x1002\n' > "$R/sys/class/net/mlan0/flags"
rx radio status
has "mlan0: administratively down, no carrier" && pass "B11 ifstate: flags without IFF_UP read 'administratively down'" || fail "B11 admin down" "$(cat "$W/rx.out")"
printf '0x1003\n' > "$R/sys/class/net/mlan0/flags"
# B15 wifi-connect
RXS=$R/sys0
rx wifi-connect HomeNet secret123; rc=$?
RXS=$R/sys
[ "$rc" = 1 ] && has "radio up" && pass "B15 wifi-connect without a wireless interface: exit 1, says 'radio up'" || fail "B15 no radio (exit $rc)" "$(cat "$W/rx.out")"
rx wifi-connect --dry-run -i fake0 HomeNet secret123; rc=$?
if [ "$rc" = 1 ] && has "NOTE: no interface fake0" && has "psk=<64 hex digits, not shown>" && has "would run: wpa_supplicant -B -i fake0 -D nl80211" \
   && ! has secret123 && [ -z "$(find "$R/run" -mindepth 1 2>/dev/null)" ]; then
    pass "B15 wifi-connect --dry-run -i fake0: plan printed, PSK masked, nothing written, exit 1 (would refuse)"
else fail "B15 dry run fake0 (exit $rc)" "$(cat "$W/rx.out"; find "$R/run")"; fi
rx wifi-connect --dry-run HomeNet secret123; rc=$?
[ "$rc" = 0 ] && has "interface mlan0" && pass "B15 wifi-connect --dry-run on the stand-in mlan0: exit 0" || fail "B15 dry run mlan0 (exit $rc)" "$(cat "$W/rx.out")"
rx wifi-connect --dry-run HomeNet short7x; rc=$?
[ "$rc" = 2 ] && has "8..63" && pass "B15 a 7-character passphrase is refused (exit 2)" || fail "B15 short passphrase (exit $rc)" "$(cat "$W/rx.out")"
rx wifi-connect --dry-run 0123456789abcdef0123456789abcdef0 secret123; rc=$?
[ "$rc" = 2 ] && has "1..32 bytes" && pass "B15 a 33-byte SSID is refused (exit 2)" || fail "B15 long SSID (exit $rc)" "$(cat "$W/rx.out")"
printf 'from-stdin-pass\n' | rx wifi-connect --dry-run HomeNet -; rc=$?
[ "$rc" = 0 ] && has "passphrase (15 characters)" && pass "B15 passphrase '-' read from stdin" || fail "B15 stdin passphrase (exit $rc)" "$(cat "$W/rx.out")"
rx wifi-connect --dry-run HomeNet 00112233445566778899aabbccddeeff00112233445566778899AABBCCDDEEFF; rc=$?
[ "$rc" = 0 ] && has "PSK given as 64 hex digits" && pass "B15 a 64-hex-digit PSK is taken as the PSK" || fail "B15 hex PSK (exit $rc)" "$(cat "$W/rx.out")"
rx wifi-connect "Home Net" secret123; rc=$?
C=$R/run/wifi/mlan0.conf
psk=$(python3 -I -c 'import hashlib; print(hashlib.pbkdf2_hmac("sha1", b"secret123", b"Home Net", 4096, 32).hex())')
if [ "$rc" = 0 ] && has "associated after" && has "wpa_state: COMPLETED" && has "IPv4: 192.168.1.50/24" \
   && grep -q "^	ssid=486f6d65204e6574$" "$C" && grep -q "^	psk=$psk$" "$C" && grep -q "key_mgmt=WPA-PSK$" "$C" \
   && [ "$(stat -c %a "$C")" = 600 ] && ! grep -rq secret123 "$R/run" \
   && grep -q "wpa_supplicant -B -i mlan0 -D nl80211 -c $C -P $R/run/wpa_supplicant-mlan0.pid -f $R/run/log/wpa_supplicant-mlan0.log" "$R/daemons.log" \
   && grep -q "udhcpc -i mlan0 -s $R/udhcpc.sh" "$R/daemons.log" && grep -q "nameserver 192.168.1.1" "$R/run/resolv.conf"; then
    pass "B15 wifi-connect: config 0600 in /run (hex SSID, derived PSK, no passphrase), daemons, DHCP, state"
else fail "B15 wifi-connect run (exit $rc)" "$(cat "$W/rx.out" "$C" "$R/daemons.log" 2>&1)"; fi
grep -q "ip route add default via 192.168.1.1 dev mlan0" "$R/ip.log" && ! grep -q "dev usb0" "$R/ip.log" \
    && pass "B15 udhcpc.sh: address and default route on mlan0 only, never usb0" || fail "B15 udhcpc.sh" "$(cat "$R/ip.log")"
rx wifi-connect --stop; rc=$?
if [ "$rc" = 0 ] && has "mlan0: stopped wpa_supplicant" && has "mlan0: stopped udhcpc" && [ ! -e "$C" ] \
   && [ -z "$(ls "$R/run/"*.pid 2>/dev/null)" ]; then pass "B15 wifi-connect --stop: both daemons stopped, config gone"
else fail "B15 --stop (exit $rc)" "$(cat "$W/rx.out")"; fi
bad=$(grep -v '^[[:space:]]*#' "$A/usr/sbin/wifi-connect" "$A/etc/baseline/udhcpc.sh" | grep -E '/dev/mtd|flashcp|flash_erase|nandwrite|persist|> */etc' || true)
[ -z "$bad" ] && pass "B15 wifi-connect / udhcpc.sh never touch flash or /etc" || fail "B15 flash/etc write" "$bad"
# B16 wifi-scan
RXS=$R/sys0
rx wifi-scan; rc=$?
RXS=$R/sys
[ "$rc" = 1 ] && has "radio up" && pass "B16 wifi-scan without a wireless interface: exit 1, says 'radio up'" || fail "B16 no radio (exit $rc)" "$(cat "$W/rx.out")"
rx wifi-scan; rc=$?
got=$(awk 'NR > 1 { print $1, $2, $4 }' "$W/rx.out" | tr '\n' ';')
if [ "$rc" = 0 ] && [ "$got" = "-42 5180 WPA2/WPA3;-55 2412 WPA3-SAE;-60 5500 802.1X;-71 2437 open;-80 2462 WPA2-PSK;" ] \
   && grep -q "Home Net$" "$W/rx.out" && grep -q "<hidden>$" "$W/rx.out"; then
    pass "B16 wifi-scan: strongest first, security classes, SSID with a space, hidden SSID"
else fail "B16 wifi-scan table (exit $rc)" "$(cat "$W/rx.out")"; fi
# B17 bt-scan
rx bt-scan; rc=$?
[ "$rc" = 1 ] && has "radio up" && pass "B17 bt-scan without an HCI device: exit 1, says 'radio up'" || fail "B17 no hci (exit $rc)" "$(cat "$W/rx.out")"
mkdir -p "$R/sys/class/bluetooth/hci0"
bt_log() { grep '^btmgmt ' "$R/daemons.log" | sed 's/^btmgmt //' | tr '\n' ';'; }
: > "$R/daemons.log"
rx bt-scan -t 5; rc=$?
if [ "$rc" = 0 ] && grep -q "^AA:BB:CC:00:00:01 LE-Random  *-69  *Tag One$" "$W/rx.out" && grep -q "^AA:BB:CC:00:00:02 BR/EDR  *-50  *Phone$" "$W/rx.out" \
   && [ "$(grep -c '^AA:BB' "$W/rx.out")" = 2 ] && [ "$(bt_log)" = "--index 0 info;--index 0 le on;--index 0 info;--index 0 --timeout 5 find;" ] \
   && has "LE was off (settings: powered br/edr); enabled it" && has "btmgmt find (BR/EDR and LE), at most 5 s"; then
    pass "B17/B18 bt-scan: LE off enabled first, find bounded by -t, one line per device, names kept"
else fail "B17/B18 bt-scan (exit $rc)" "$(cat "$W/rx.out" "$R/daemons.log")"; fi
: > "$R/daemons.log"
rx bt-scan -t 5; rc=$?
[ "$rc" = 0 ] && [ "$(bt_log)" = "--index 0 info;--index 0 --timeout 5 find;" ] && ! has "LE was off" \
    && pass "B18 bt-scan with LE already on: no 'le on', interleaved find" || fail "B18 LE on (exit $rc)" "$(cat "$W/rx.out" "$R/daemons.log")"
: > "$R/daemons.log"; touch "$R/bt/reject"
rx bt-scan -t 5; rc=$?
if [ "$rc" = 0 ] && has "BR/EDR and LE discovery refused (status 0x0b (Rejected)); retrying BR/EDR only" \
   && has "btmgmt find -b (BR/EDR only)" && grep -q "^AA:BB:CC:00:00:02 BR/EDR " "$W/rx.out" && ! grep -q "^AA:BB:CC:00:00:01" "$W/rx.out" \
   && ! has "did not start" && [ "$(bt_log)" = "--index 0 info;--index 0 --timeout 5 find;--index 0 --timeout 5 find -b;" ]; then
    pass "B18 bt-scan: an interleaved find refused (0x0b) is retried BR/EDR only, and says so"
else fail "B18 0x0b retry (exit $rc)" "$(cat "$W/rx.out" "$R/daemons.log")"; fi
rx bt-scan -t 5 -l; rc=$?
[ "$rc" = 1 ] && has "btmgmt: Unable to start discovery" && has "discovery did not start (LE only)" && ! has "retrying" \
    && pass "B18 bt-scan -l refused: no BR/EDR fallback, exit 1" || fail "B18 -l refused (exit $rc)" "$(cat "$W/rx.out")"
rm -f "$R/bt/reject"; echo "powered bondable ssp br/edr " > "$R/bt/supported"; echo "powered br/edr " > "$R/bt/current"
: > "$R/daemons.log"
rx bt-scan -t 5; rc=$?
[ "$rc" = 0 ] && has "hci0 has no LE (supported: powered bondable ssp br/edr): BR/EDR only" && has "btmgmt find -b (BR/EDR only)" \
    && [ "$(bt_log)" = "--index 0 info;--index 0 --timeout 5 find -b;" ] \
    && pass "B18 bt-scan on a controller without LE: no 'le on', BR/EDR only" || fail "B18 no LE (exit $rc)" "$(cat "$W/rx.out" "$R/daemons.log")"
echo "powered connectable bondable ssp br/edr le " > "$R/bt/supported"
: > "$R/daemons.log"
rx bt-scan -t 5 -b; rc=$?
[ "$rc" = 0 ] && [ "$(bt_log)" = "--index 0 --timeout 5 find -b;" ] && pass "B18 bt-scan -b: no settings read, no 'le on'" \
    || fail "B18 -b (exit $rc)" "$(cat "$W/rx.out" "$R/daemons.log")"
# radios stay off at boot: nothing in the boot path starts a radio, a radio tool or a module load
boot=$(cd "$HERE" && grep -nE '(^|[;&|[:space:]])(radio|radio-up|wifi-connect|wifi-scan|bt-scan|wpa_supplicant|btmgmt|hciconfig|hcitool|hciup|iw|insmod|modprobe)([[:space:]]|$)' \
    common/rootfs/init common/rootfs/etc/init.d/rcS common/rootfs/etc/inittab arm-imx6ul/rootfs/etc/baseline/board-rcS.sh \
    common/rootfs/etc/mdev.conf 2> /dev/null | grep -v ':[[:space:]]*#' || true)
[ -z "$boot" ] && pass "radios OFF at boot: no radio/Wi-Fi/BT tool or module load in init, rcS, inittab, mdev.conf" || fail "boot path starts a radio" "$boot"

echo "selftest: $([ "$fails" = 0 ] && echo PASS || echo "FAIL ($fails)") (work dir $W)"
[ "$fails" = 0 ]

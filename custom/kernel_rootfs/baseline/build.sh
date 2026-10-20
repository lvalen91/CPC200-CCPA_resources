#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# baseline/build.sh: the vanilla CCPA baseline (mainline kernel + recovery initramfs + squashfs rootfs).
# Structure derived from LIVI scripts/livi-link/arm/imx6ul/build.sh, common/kernel.sh,
# common/build-rootfs.sh and arm/build-userspace.sh (https://github.com/f-io/LIVI, GPL-3.0-or-later).
#
#   build.sh --dry-run [VAR=value ...] [steps]   print every step and command; runs, fetches, writes nothing
#   build.sh [VAR=value ...] [steps]             real build, Linux host only (e.g. a Lima VM)
#
# steps (default: fetch userspace kernel rootfs)
#   fetch      pinned tarballs (common/versions.env) into $TOP/src, each sha256-checked
#   userspace  musl, BusyBox full + recovery, dropbear, sftp-server, flash_erase, hciup [, exfatprogs]
#   kernel     linux + board patches + DTS + recovery initramfs: ONE zImage per kernel config, and one
#              image per radio DT = that zImage + its appended DTB ->
#              $TOP/out/<variant>/ccpa-baseline-<radio>.zimg (radio: none iw416 rtl8822cs rtl8822bs)
#   rootfs     squashfs for the same variant (its modules; one rootfs for every radio) ->
#              $TOP/out/<variant>/rootfs.img
#   measure    kernels nousb / recovery-usb-vfat / default-nossh / default: sizes, fail one over KERNEL_MAX
#
# variables (0|1 unless noted); variant names: default = RECOVERY_USB=1 RECOVERY_EXFAT=1 RECOVERY_SSH=1
#   BOARD=arm-imx6ul  TOP=/tmp/ccpa-baseline-build (never under ~/Documents)  JOBS=<n>  CROSS_COMPILE=<prefix>
#   RECOVERY_USB=1    USB storage in the recovery initramfs (forces USB_HOST=1, USB_VFAT_BUILTIN=1): one
#                     scan at recovery start, the first FAT32/exFAT data partition read-write at /mnt/usb
#   RECOVERY_EXFAT=1  exFAT built in (with RECOVERY_USB=1; else recovery reads FAT only)
#   RECOVERY_SSH=1    dropbear + sftp-server in the recovery initramfs (SSH/SCP/SFTP on the NCM address)
#   USB_HOST=0        usbotg1 as host for the rootfs; storage stack as rootfs modules (when RECOVERY_USB=0)
#   USB_VFAT_BUILTIN=0 storage stack + vfat built into the kernel instead
#   RADIO_MODULES=1   Wi-Fi/BT drivers as rootfs modules (never loaded at boot)  RADIO_FW=1  their firmware
#   RADIO_DT=all      all|none|iw416|rtl8822cs|rtl8822bs: which per-radio images the kernel step writes
#                     (the Bluetooth serdev node in the appended DTB; the zImage is the same for all)
#   MTD_UTILS=1       static flash_erase in the rootfs (needs MTD_UTILS_SHA256 pinned first)
#   EXFATPROGS=0      mkfs.exfat/fsck.exfat in the rootfs
#   ROOT_PASSWORD_HASH=<sha512-crypt>  root's password for SSH in recovery and rootfs; default: the
#                     documented DEV DEFAULT password 'baseline' (change it on the unit with passwd)
#   AUTHORIZED_KEYS=<file>  public keys baked into the rootfs (optional: password login works without)
#   SOURCE_DATE_EPOCH=<s>   reproducible timestamps (kernel, squashfs, release string)
#
# Output never contains unit identity: the kernel partition image for a unit is made afterwards on
# the host by arm-imx6ul/tools/stage_kernel.py from that unit's own backup.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DRY=0
STEPS=
for a in "$@"; do
    case $a in
        --dry-run) DRY=1 ;;
        -h | --help) sed -n '2,/^set -eu/p' "$0" | sed '$d'; exit 0 ;;
        BOARD=* | TOP=* | JOBS=* | CROSS_COMPILE=* | RECOVERY_USB=* | RECOVERY_EXFAT=* | RECOVERY_SSH=* | \
        USB_HOST=* | USB_VFAT_BUILTIN=* | RADIO_MODULES=* | RADIO_FW=* | RADIO_DT=* | MTD_UTILS=* | \
        EXFATPROGS=* | ROOT_PASSWORD_HASH=* | AUTHORIZED_KEYS=* | ALLOW_NO_SSH_KEYS=* | SOURCE_DATE_EPOCH=*)
            eval "${a%%=*}=\${a#*=}"
            export "${a%%=*}" ;;
        fetch | userspace | kernel | rootfs | measure) STEPS="$STEPS $a" ;;
        all) STEPS="$STEPS fetch userspace kernel rootfs" ;;
        *) echo "build.sh: unknown argument '$a' (--help)" >&2; exit 2 ;;
    esac
done
[ -n "$STEPS" ] || STEPS="fetch userspace kernel rootfs"

# The documented dev-board default password 'baseline' (sha512-crypt, fixed salt so builds are
# reproducible): `openssl passwd -6 -salt ccpabaseline baseline`. A DEV DEFAULT: change it on the unit
# with passwd (kept in the persist archive) or build with your own ROOT_PASSWORD_HASH.
DEV_PASSWORD_HASH='$6$ccpabaseline$aftqJ6/WGLuW3tRlRn8/0qxWZXbBFGlwicphA3fJELY5ZlqkodQoLWpT3Zi5e/I6A77DL5fZVht5ysnYkCgXR/'
: "${BOARD:=arm-imx6ul}" "${TOP:=/tmp/ccpa-baseline-build}"
: "${RECOVERY_USB:=1}" "${RECOVERY_EXFAT:=1}" "${RECOVERY_SSH:=1}" "${USB_HOST:=0}" "${USB_VFAT_BUILTIN:=0}"
: "${RADIO_MODULES:=1}" "${RADIO_FW:=1}" "${RADIO_DT:=all}" "${MTD_UTILS:=1}" "${EXFATPROGS:=0}"
: "${AUTHORIZED_KEYS:=}" "${ALLOW_NO_SSH_KEYS:=0}" "${ROOT_PASSWORD_HASH:=$DEV_PASSWORD_HASH}"
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

log() { printf '[%s-build] %s\n' "$BOARD" "$*"; }
note() { printf '\n== %s\n' "$*"; }
die() { printf '[%s-build] ERROR: %s\n' "$BOARD" "$*" >&2; exit 1; }
# x CMD...: run, or print under --dry-run. xsh 'shell string': the same for pipelines and cd.
x() { if [ "$DRY" = 1 ]; then printf '+ %s\n' "$*"; else "$@"; fi; }
xsh() { if [ "$DRY" = 1 ]; then printf '+ sh -c %s\n' "$1"; else sh -c "$1"; fi; }

for v in RECOVERY_USB RECOVERY_EXFAT RECOVERY_SSH USB_HOST USB_VFAT_BUILTIN RADIO_MODULES RADIO_FW MTD_UTILS \
         EXFATPROGS ALLOW_NO_SSH_KEYS; do
    eval "val=\$$v"
    case $val in 0 | 1) ;; *) die "$v must be 0 or 1, not '$val'" ;; esac
done
case $RADIO_DT in
    all) RADIOS="none iw416 rtl8822cs rtl8822bs" ;;
    none | iw416 | rtl8822cs | rtl8822bs) RADIOS=$RADIO_DT ;;
    *) die "RADIO_DT=$RADIO_DT: all|none|iw416|rtl8822cs|rtl8822bs" ;;
esac
# sha512-crypt only: $6$[rounds=N$]salt$hash, no ':' (it goes into a shadow line)
case $ROOT_PASSWORD_HASH in
    '$6$'*) ;;
    *) die "ROOT_PASSWORD_HASH must be sha512-crypt (\$6\$...), e.g. from: openssl passwd -6" ;;
esac
case $ROOT_PASSWORD_HASH in *[!./0-9A-Za-z\$=]*) die "ROOT_PASSWORD_HASH has characters sha512-crypt does not use" ;; esac
[ "${#ROOT_PASSWORD_HASH}" -ge 90 ] || die "ROOT_PASSWORD_HASH is too short for sha512-crypt"
case $TOP in "$HOME"/Documents*) die "TOP=$TOP is under ~/Documents (iCloud-synced; build output must live outside, see CLAUDE.md)" ;; esac
[ -d "$HERE/$BOARD" ] && [ -r "$HERE/$BOARD/board.env" ] || die "no board $BOARD in $HERE"

. "$HERE/common/versions.env"
. "$HERE/$BOARD/board.env"

if [ "$DRY" != 1 ]; then
    [ "$(uname -s)" = Linux ] || die "real builds run on a Linux host (Lima VM); --dry-run works anywhere"
    for t in make gcc "${CROSS_COMPILE}gcc" "${CROSS_COMPILE}strip" curl sha256sum tar xz bzip2 patch bc flex \
             bison perl file awk sed grep mksquashfs depmod; do
        command -v "$t" > /dev/null 2>&1 || die "missing build tool: $t"
    done
    # mtd-utils' configure stops without pkg-config even with every optional library switched off
    if [ "$MTD_UTILS" = 1 ] || [ "$EXFATPROGS" = 1 ]; then
        command -v pkg-config > /dev/null 2>&1 || die "missing build tool: pkg-config (mtd-utils/exfatprogs configure)"
    fi
fi

SRC=$TOP/src
KDIR=$TOP/linux-$KVER
DTS_DIR=$KDIR/arch/arm/boot/dts/nxp/imx
UBUILD=$TOP/userspace/build
UOUT=$TOP/userspace/out
export KBUILD_BUILD_USER=baseline KBUILD_BUILD_HOST=ccpa LOCALVERSION=
[ -n "${SOURCE_DATE_EPOCH:-}" ] && export KBUILD_BUILD_TIMESTAMP="@$SOURCE_DATE_EPOCH"

# Applets the recovery scripts call; the recovery BusyBox must provide each (checked on its busybox.links).
RECOVERY_NEEDS="sh cat dd echo printf test hexdump ifconfig kill ln ls mkdir mount umount mv chmod nc ps rm rmdir
setsid cttyhack sha256sum sleep stty switch_root sync telnetd udhcpd wc flashcp flash_eraseall reboot dmesg rx
readlink tar"

. "$HERE/common/recipes/userspace.sh"

# ------------------------------------------------------------------------------------------- variant
# V names the kernel CONFIG (and with it the recovery initramfs and the rootfs modules); the radio is
# not part of it: every radio image of a variant is the same zImage with another appended DTB.
derive_variant() {
    if [ "$RECOVERY_USB" = 1 ]; then
        USB_HOST=1
        USB_VFAT_BUILTIN=1
    fi
    if [ "$RECOVERY_USB" = 1 ] && [ "$RECOVERY_EXFAT" = 1 ]; then V=default
    elif [ "$RECOVERY_USB" = 1 ]; then V=recovery-usb-vfat
    elif [ "$USB_HOST" = 1 ] && [ "$USB_VFAT_BUILTIN" = 1 ]; then V=usb-host-vfat
    elif [ "$USB_HOST" = 1 ]; then V=usb-host
    else V=nousb
    fi
    [ "$RECOVERY_SSH" = 1 ] || V=$V-nossh
    [ "$RADIO_MODULES" = 1 ] || V=$V-noradio
    OUTV=$TOP/out/$V
    KOBJ=$TOP/kbuild/$V
}

# ------------------------------------------------------------------------------------------- fetch
fetch_pinned() { # name url sha256 file
    if [ -z "$3" ]; then
        if [ "$DRY" = 1 ]; then
            printf '+ REFUSE %s: no sha256 pinned in common/versions.env (verify the upstream signature, pin it)\n' "$1"
            return 0
        fi
        die "$1: no sha256 pinned in common/versions.env; verify upstream's signature and pin it"
    fi
    if [ "$DRY" = 1 ]; then
        printf '+ fetch %s -> %s (sha256 %s)\n' "$2" "$SRC/$4" "$3"
        return 0
    fi
    mkdir -p "$(dirname "$SRC/$4")"
    if [ -f "$SRC/$4" ] && echo "$3  $SRC/$4" | sha256sum -c --status; then
        return 0
    fi
    log "fetch $1"
    curl -fsSL "$2" -o "$SRC/$4.part" || { rm -f "$SRC/$4.part"; die "download of $1 failed"; }
    echo "$3  $SRC/$4.part" | sha256sum -c --status || { rm -f "$SRC/$4.part"; die "$1 does not match its pinned sha256"; }
    mv "$SRC/$4.part" "$SRC/$4"
}

fw_entries() {
    [ "$RADIO_MODULES" = 1 ] && [ "$RADIO_FW" = 1 ] || return 0
    printf '%s\n' "$FW_IW416" "$FW_RTL8822CS_WIFI" "$FW_RTL8822CS_BT" "$FW_RTL8822CS_BTCFG" "$FW_RTL8822BS_WIFI"
}

step_fetch() {
    note "fetch: pinned sources into $SRC"
    fetch_pinned linux "$KERNEL_URL" "$KERNEL_SHA256" "linux-$KVER.tar.xz"
    fetch_pinned musl "$MUSL_URL" "$MUSL_SHA256" "musl-$MUSL_VER.tar.gz"
    fetch_pinned busybox "$BUSYBOX_URL" "$BUSYBOX_SHA256" "busybox-$BUSYBOX_VER.tar.bz2"
    fetch_pinned dropbear "$DROPBEAR_URL" "$DROPBEAR_SHA256" "dropbear-$DROPBEAR_VER.tar.bz2"
    fetch_pinned openssh "$OPENSSH_URL" "$OPENSSH_SHA256" "openssh-$OPENSSH_VER.tar.gz"
    [ "$MTD_UTILS" = 1 ] && fetch_pinned mtd-utils "$MTD_UTILS_URL" "$MTD_UTILS_SHA256" "mtd-utils-$MTD_UTILS_VER.tar.bz2"
    [ "$EXFATPROGS" = 1 ] && fetch_pinned exfatprogs "$EXFATPROGS_URL" "$EXFATPROGS_SHA256" "exfatprogs-$EXFATPROGS_VER.tar.gz"
    fw_entries | while read -r path sha tag; do
        fetch_pinned "firmware $path" "$LINUX_FIRMWARE_URL/$path${tag:+?h=$tag}" "$sha" "firmware/$path"
    done
    if [ "$RADIO_MODULES" = 1 ] && [ "$RADIO_FW" = 1 ]; then
        fetch_pinned wireless-regdb "$REGDB_URL" "$REGDB_SHA256" "wireless-regdb-$REGDB_VER.tar.xz"
    fi
}

# ------------------------------------------------------------------------------------------- kernel
kernel_src() {
    if [ "$DRY" = 1 ] || [ ! -d "$KDIR" ]; then
        note "linux $KVER source -> $KDIR"
        untar "$SRC/linux-$KVER.tar.xz" "$KDIR"
    fi
    note "board patches ($BOARD/patches: bus clocks on the ULL, gadget without BSV wait, no charger detection, MX25L128 without SFDP)"
    if [ "$DRY" = 1 ]; then
        for p in "$HERE/$BOARD/patches/"*.patch; do printf '+ patch -p1 -N -d %s < %s\n' "$KDIR" "$p"; done
    else
        sum=$(cat "$HERE/$BOARD/patches/"*.patch | sha256sum | cut -d' ' -f1)
        stamp=$KDIR/.baseline-patches
        if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$sum" ]; then
            for p in "$HERE/$BOARD/patches/"*.patch; do
                (cd "$KDIR" && patch -p1 -N -r- -s < "$p") \
                    || (cd "$KDIR" && patch -p1 -R --dry-run -s < "$p" > /dev/null) \
                    || die "patch $(basename "$p") failed; remove $KDIR to start from a clean tree"
            done
            echo "$sum" > "$stamp"
        fi
    fi
    note "board DTS into $DTS_DIR, one top-level DTS per radio ($DTS_NAME-<radio>.dts)"
    x cp -f "$HERE/$BOARD/dts/$DTS_NAME.dts" "$HERE/$BOARD/dts/imx6ull-ccpa-usbhost.dtsi" "$DTS_DIR/"
    for r in none iw416 rtl8822cs rtl8822bs; do
        x cp -f "$HERE/$BOARD/dts/radio-$r.dtsi" "$DTS_DIR/imx6ull-ccpa-radio-$r.dtsi"
        xsh "printf '%s\\n' '// generated by baseline/build.sh: the board DTS plus the $r radio node' \
             '#include \"$DTS_NAME.dts\"' '#include \"imx6ull-ccpa-radio-$r.dtsi\"' > '$DTS_DIR/$DTS_NAME-$r.dts'"
        xsh "grep -q '$DTS_NAME-$r.dtb' '$DTS_DIR/Makefile' || echo 'dtb-\$(CONFIG_SOC_IMX6UL) += $DTS_NAME-$r.dtb' >> '$DTS_DIR/Makefile'"
    done
}

# shadow_default FILE: root's shadow line with ROOT_PASSWORD_HASH (written directly: the hash holds '$').
shadow_default() {
    printf 'root:%s::0:99999:7:::\n' "$ROOT_PASSWORD_HASH" > "$1"
    chmod 0600 "$1"
}

initramfs_list() { # writes $OUTV/initramfs.list
    I=$HERE/$BOARD/initramfs
    S=$HERE/common/shared
    R=$HERE/common/rootfs/etc
    L=$OUTV/initramfs.list
    note "recovery initramfs list -> $L"
    if [ "$DRY" = 1 ]; then
        printf '+ write %s: dirs, /dev/console, /dev/null, recovery busybox, init, reboot, flash-rootfs, flash-kernel,\n' "$L"
        printf '+   flash-lib.sh, mtd.sh, net-up, net-down, ocbm-identity, ocbm-banner, persist, board.env, usb-ids.conf,\n'
        printf '+   ncm.conf, /etc/baseline/recovery, /etc/baseline-release%s%s\n' \
            "$([ "$RECOVERY_SSH" = 1 ] && echo ', ssh-up, dropbearmulti (+dropbear dropbearkey scp dbclient), sftp-server, passwd/group/shells/profile, shadow.default, /etc/shadow -> /run/etc/shadow, /root/.ssh -> /run/ssh')" \
            "$([ "$RECOVERY_USB" = 1 ] && echo ', usb-mount, usb-update, /etc/baseline/recovery-usb, /mnt/usb')"
        printf '+ sh -n on every script in the list\n'
        return 0
    fi
    mkdir -p "$OUTV"
    : > "$OUTV/empty"
    shadow_default "$OUTV/shadow.default"
    {
        for d in /bin /sbin /usr /usr/bin /usr/sbin /usr/libexec /etc /etc/baseline /lib /lib/baseline /dev /proc \
                 /sys /mnt /mnt/root /run /var; do
            echo "dir $d 0755 0 0"
        done
        echo "dir /tmp 1777 0 0"
        echo "dir /root 0700 0 0"
        [ "$RECOVERY_USB" = 1 ] && echo "dir /mnt/usb 0755 0 0"
        echo "nod /dev/console 0600 0 0 c 5 1"
        echo "nod /dev/null 0666 0 0 c 1 3"
        echo "file /bin/busybox $UOUT/recovery/busybox 0755 0 0"
        echo "file /init $I/init 0755 0 0"
        echo "file /sbin/reboot $I/reboot 0755 0 0"
        echo "file /sbin/flash-rootfs $I/flash-rootfs 0755 0 0"
        echo "file /sbin/flash-kernel $I/flash-kernel 0755 0 0"
        echo "file /lib/baseline/flash-lib.sh $I/flash-lib.sh 0644 0 0"
        echo "file /lib/baseline/mtd.sh $S/mtd.sh 0644 0 0"
        for f in net-up net-down ocbm-identity ocbm-banner persist; do echo "file /sbin/$f $S/$f 0755 0 0"; done
        echo "file /etc/baseline/board.env $HERE/$BOARD/board.env 0644 0 0"
        echo "file /etc/baseline/usb-ids.conf $HERE/common/usb-ids.conf 0644 0 0"
        echo "file /etc/baseline/ncm.conf $HERE/common/ncm.conf 0644 0 0"
        echo "file /etc/baseline/recovery $OUTV/empty 0644 0 0"
        echo "file /etc/baseline-release $OUTV/release 0644 0 0"
        if [ "$RECOVERY_SSH" = 1 ]; then
            echo "file /sbin/ssh-up $S/ssh-up 0755 0 0"
            echo "file /usr/sbin/dropbearmulti $UOUT/usr/sbin/dropbearmulti 0755 0 0"
            echo "slink /usr/sbin/dropbear dropbearmulti 0777 0 0"
            for b in dropbearkey scp dbclient; do echo "slink /usr/bin/$b ../sbin/dropbearmulti 0777 0 0"; done
            echo "file /usr/libexec/sftp-server $UOUT/usr/libexec/sftp-server 0755 0 0"
            for f in passwd group shells profile; do echo "file /etc/$f $R/$f 0644 0 0"; done
            echo "file /etc/baseline/shadow.default $OUTV/shadow.default 0600 0 0"
            [ "$ROOT_PASSWORD_HASH" = "$DEV_PASSWORD_HASH" ] && echo "file /etc/baseline/dev-password $OUTV/empty 0644 0 0"
            echo "slink /etc/shadow /run/etc/shadow 0777 0 0"
            echo "slink /root/.ssh /run/ssh 0777 0 0"
        fi
        if [ "$RECOVERY_USB" = 1 ]; then
            echo "file /sbin/usb-mount $S/usb-mount 0755 0 0"
            echo "file /sbin/usb-update $I/usb-update 0755 0 0"
            echo "file /etc/baseline/recovery-usb $OUTV/empty 0644 0 0"
        fi
    } > "$L"
    # A script with a syntax error stops init before the ways in are up (LIVI check_initramfs_scripts).
    while read -r kind dst src _; do
        [ "$kind" = file ] || continue
        case $(head -c 2 "$src" 2>/dev/null) in '#!') ;; *) case $src in *.sh | *.env | *.conf) ;; *) continue ;; esac ;; esac
        head -c 4 "$src" | grep -q ELF && continue
        sh -n "$src" || die "syntax error in $src ($dst)"
    done < "$L"
}

release_string() {
    if [ "$DRY" = 1 ]; then echo "ccpa-baseline $V (date at build time)"; return 0; fi
    if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then d=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%dT%H%MZ); else d=$(date -u +%Y%m%dT%H%MZ); fi
    echo "ccpa-baseline $V linux-$KVER busybox-$BUSYBOX_VER dropbear-$DROPBEAR_VER $d"
}

# build_kernel: sets KERNEL_FITS=1|0 and KERNEL_SIZE; dies on anything but an oversize image.
build_kernel() {
    derive_variant
    note "kernel variant $V (RECOVERY_USB=$RECOVERY_USB RECOVERY_EXFAT=$RECOVERY_EXFAT RECOVERY_SSH=$RECOVERY_SSH USB_HOST=$USB_HOST USB_VFAT_BUILTIN=$USB_VFAT_BUILTIN RADIO_MODULES=$RADIO_MODULES), radio images: $RADIOS"
    if [ "$DRY" != 1 ]; then
        [ -x "$UOUT/recovery/busybox" ] || die "no recovery busybox at $UOUT/recovery, run the userspace step first"
        if [ "$RECOVERY_SSH" = 1 ]; then
            for b in usr/sbin/dropbearmulti usr/libexec/sftp-server; do
                [ -x "$UOUT/$b" ] || die "RECOVERY_SSH=1 needs $UOUT/$b, run the userspace step first"
            done
        fi
        for a in $RECOVERY_NEEDS; do
            grep -q "/$a\$" "$UOUT/recovery/busybox.links" || die "recovery busybox lacks '$a' (common/busybox/recovery.applets)"
        done
        mkdir -p "$OUTV" "$KOBJ"
        release_string > "$OUTV/release"
    else
        printf '+ check the recovery busybox.links provides: %s\n' "$(echo $RECOVERY_NEEDS)"
    fi
    kernel_src
    VD=$DTS_DIR/imx6ull-ccpa-variant.dtsi
    note "variant DT include -> $VD"
    xsh "{ echo '/* generated by baseline/build.sh for kernel variant $V (the radio node is in the per-radio top-level DTS) */';
           [ $USB_HOST = 1 ] && echo '#include \"imx6ull-ccpa-usbhost.dtsi\"'; true; } > '$VD'"
    initramfs_list
    K=$HERE/$BOARD/kernel
    STRICT="$K/base.fragment"
    [ "$RADIO_MODULES" = 1 ] && STRICT="$STRICT $K/radio-modules.fragment"
    [ "$USB_HOST" = 1 ] && STRICT="$STRICT $K/usb-host.fragment"
    [ "$USB_VFAT_BUILTIN" = 1 ] && STRICT="$STRICT $K/usb-vfat-builtin.fragment"
    [ "$RECOVERY_USB" = 1 ] && [ "$RECOVERY_EXFAT" = 1 ] && STRICT="$STRICT $K/exfat-builtin.fragment"
    STRICT="$STRICT $OUTV/initramfs.fragment"
    xsh "echo 'CONFIG_INITRAMFS_SOURCE=\"$OUTV/initramfs.list\"' > '$OUTV/initramfs.fragment'"
    note "kconfig: allnoconfig + $(echo "$STRICT $K/base-optional.fragment" | sed "s|$HERE/||g; s|$OUTV/||g")"
    # base-optional goes first so a strict fragment wins wherever both name a symbol.
    xsh "cd '$KDIR' && ARCH=$KARCH CROSS_COMPILE='$CROSS_COMPILE' scripts/kconfig/merge_config.sh -n -O '$KOBJ' \
         '$K/base-optional.fragment' $STRICT > '$OUTV/merge_config.log' 2>&1"
    x make -C "$KDIR" O="$KOBJ" ARCH="$KARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
    # shellcheck disable=SC2086
    kv_check "$KOBJ/.config" strict $STRICT || die "kernel config lost a requested value (above)"
    kv_check "$KOBJ/.config" warn "$K/base-optional.fragment"
    DTBS=
    for r in $RADIOS; do DTBS="$DTBS nxp/imx/$DTS_NAME-$r.dtb"; done
    # shellcheck disable=SC2086
    x make -C "$KDIR" O="$KOBJ" ARCH="$KARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" zImage modules $DTBS
    ZI=$KOBJ/arch/arm/boot/zImage
    x make -C "$KDIR" O="$KOBJ" ARCH="$KARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$OUTV/modules" \
        INSTALL_MOD_STRIP=1 DEPMOD="$(command -v depmod || echo depmod)" modules_install
    if [ "$DRY" = 1 ]; then
        for r in $RADIOS; do printf '+ cat zImage %s.dtb > %s\n' "$DTS_NAME-$r" "$OUTV/ccpa-baseline-$r.zimg"; done
        printf '+ check: size(zImage) + size(DTB) <= KERNEL_MAX %s B (0x302fd8) for each, else this variant fails\n' "$KERNEL_MAX"
        KERNEL_FITS=1
        KERNEL_SIZE=UNMEASURED
        return 0
    fi
    zs=$(($(wc -c < "$ZI")))
    KERNEL_FITS=1
    KERNEL_SIZE=0
    for r in $RADIOS; do
        DTB=$KOBJ/arch/arm/boot/dts/nxp/imx/$DTS_NAME-$r.dtb
        IMG=$OUTV/ccpa-baseline-$r.zimg
        cat "$ZI" "$DTB" > "$IMG"
        ds=$(($(wc -c < "$DTB")))
        is=$(($(wc -c < "$IMG")))
        log "variant $V radio $r: zImage $zs B + DTB $ds B = $is B of $KERNEL_MAX B U-Boot reads ($((KERNEL_MAX - is)) B spare)"
        sha256sum "$IMG" | sed "s|  .*|  ccpa-baseline-$r.zimg|" > "$IMG.sha256"
        [ "$is" -gt "$KERNEL_SIZE" ] && KERNEL_SIZE=$is
        [ "$is" -le "$KERNEL_MAX" ] || KERNEL_FITS=0
    done
}

step_kernel() {
    build_kernel
    [ "$KERNEL_FITS" = 1 ] || die "variant $V: image is $((KERNEL_SIZE - KERNEL_MAX)) B too large for the vendor U-Boot"
}

# measure: the cost of each recovery feature, one kernel config at a time (radio DT none only; the
# radio DTBs differ by a few hundred bytes, the kernel step prints them).
step_measure() {
    note "measure: kernels nousb, recovery-usb-vfat, default-nossh, default (UNMEASURED until this runs)"
    save="$RECOVERY_USB $RECOVERY_EXFAT $RECOVERY_SSH $USB_HOST $USB_VFAT_BUILTIN $RADIOS"
    report=
    fail=0
    for cfg in "0 0 1" "1 0 1" "1 1 0" "1 1 1"; do
        set -- $cfg
        RECOVERY_USB=$1 RECOVERY_EXFAT=$2 RECOVERY_SSH=$3 RADIOS=none
        set -- $save
        USB_HOST=$4 USB_VFAT_BUILTIN=$5
        build_kernel
        verdict=fits
        [ "$KERNEL_FITS" = 1 ] || { verdict="FAILS (over by $((KERNEL_SIZE - KERNEL_MAX)) B)"; fail=1; }
        [ "$DRY" = 1 ] && verdict="UNMEASURED (dry run)"
        report="$report
  $V: $KERNEL_SIZE B incl. DTB, cap $KERNEL_MAX B: $verdict"
    done
    set -- $save
    RECOVERY_USB=$1 RECOVERY_EXFAT=$2 RECOVERY_SSH=$3 USB_HOST=$4 USB_VFAT_BUILTIN=$5
    shift 5
    RADIOS=$*
    note "measure result:$report"
    [ "$fail" = 0 ] || die "a measured variant does not fit; do not ship it"
}

# ------------------------------------------------------------------------------------------- userspace
step_userspace() {
    note "userspace (static, $MUSL_TARGET) -> $UOUT"
    x mkdir -p "$UBUILD" "$UOUT/bin" "$UOUT/usr/sbin" "$UOUT/usr/libexec" "$UOUT/recovery"
    if [ "$DRY" = 1 ] || [ ! -d "$KDIR" ]; then untar "$SRC/linux-$KVER.tar.xz" "$KDIR"; fi
    build_musl
    build_busybox_full
    build_busybox_recovery
    build_dropbear
    build_sftp_server
    [ "$MTD_UTILS" = 1 ] && build_mtd_utils
    [ "$RADIO_MODULES" = 1 ] && build_hciup
    [ "$EXFATPROGS" = 1 ] && build_exfatprogs
    return 0
}

# ------------------------------------------------------------------------------------------- rootfs
step_rootfs() {
    derive_variant
    IMGR=$OUTV/rootfs.img
    note "rootfs squashfs for variant $V -> $IMGR"
    # Since 2026-10-20 SSH also takes root's password, so a rootfs without baked keys is usable;
    # ALLOW_NO_SSH_KEYS is accepted and no longer needed.
    [ -n "$AUTHORIZED_KEYS" ] || log "no AUTHORIZED_KEYS: SSH by password until keys are added (persist add-key FILE)"
    [ "$ROOT_PASSWORD_HASH" = "$DEV_PASSWORD_HASH" ] \
        && log "root password = the documented DEV DEFAULT 'baseline' (ROOT_PASSWORD_HASH not set): change it with passwd on the unit"
    if [ "$DRY" != 1 ]; then
        [ -x "$UOUT/bin/busybox" ] || die "no userspace at $UOUT, run the userspace step"
        [ -d "$OUTV/modules/lib/modules/$KVER" ] || die "no modules for variant $V, run the kernel step with the same variables"
        [ "$RADIO_MODULES" != 1 ] || [ -x "$UOUT/usr/sbin/hciup" ] || die "no hciup at $UOUT/usr/sbin, run the userspace step"
        if [ -n "$AUTHORIZED_KEYS" ]; then
            [ -r "$AUTHORIZED_KEYS" ] || die "cannot read AUTHORIZED_KEYS=$AUTHORIZED_KEYS"
            grep -q 'PRIVATE KEY' "$AUTHORIZED_KEYS" && die "AUTHORIZED_KEYS is a PRIVATE key; give the .pub"
            grep -Eqv '^(ssh-ed25519|ecdsa-sha2-|ssh-rsa|sk-ssh-ed25519@|sk-ecdsa-sha2-|#|$)' "$AUTHORIZED_KEYS" \
                && die "AUTHORIZED_KEYS has lines that are not OpenSSH public keys"
        fi
        [ -s "$OUTV/release" ] || release_string > "$OUTV/release"
    fi
    W=${WORK_DIR:-$TOP/rootfs-work-$V}
    x rm -rf "$W"
    x mkdir -p "$W/bin" "$W/sbin" "$W/lib/baseline" "$W/lib/modules" "$W/usr/bin" "$W/usr/sbin" "$W/usr/libexec" \
        "$W/etc/init.d" "$W/etc/baseline" "$W/dev" "$W/proc" "$W/sys" "$W/tmp" "$W/run" "$W/root" "$W/mnt/usb" "$W/var"
    x ln -s /proc/mounts "$W/etc/mtab"
    x ln -s /run/etc/shadow "$W/etc/shadow"
    x ln -s /run "$W/var/run"
    x ln -s /run/log "$W/var/log"
    x ln -s /tmp "$W/var/tmp"
    x ln -s /run/varlib "$W/var/lib"
    x ln -s /run/ssh "$W/root/.ssh"
    note "BusyBox $BUSYBOX_VER + its applet links (from busybox.links)"
    x cp "$UOUT/bin/busybox" "$W/bin/busybox"
    xsh "while read -r p; do d=\${p%/*}; case \$d in /bin) t=busybox ;; /sbin) t=../bin/busybox ;; /usr/bin|/usr/sbin) t=../../bin/busybox ;; *) continue ;; esac;
             [ -e '$W'\$p ] || ln -s \$t '$W'\$p; done < '$UOUT/bin/busybox.links'"
    note "dropbear multi-call + sftp-server [+ flash_erase] [+ exfatprogs]"
    x cp "$UOUT/usr/sbin/dropbearmulti" "$W/usr/sbin/dropbearmulti"
    x ln -s dropbearmulti "$W/usr/sbin/dropbear"
    for b in dbclient dropbearkey scp; do x ln -s ../sbin/dropbearmulti "$W/usr/bin/$b"; done
    x cp "$UOUT/usr/libexec/sftp-server" "$W/usr/libexec/sftp-server"
    [ "$MTD_UTILS" = 1 ] && x cp "$UOUT/usr/sbin/flash_erase" "$W/usr/sbin/flash_erase"
    [ "$RADIO_MODULES" = 1 ] && x cp "$UOUT/usr/sbin/hciup" "$W/usr/sbin/hciup"
    if [ "$EXFATPROGS" = 1 ]; then
        x cp "$UOUT/usr/sbin/mkfs.exfat" "$UOUT/usr/sbin/fsck.exfat" "$W/usr/sbin/"
    fi
    note "overlays: common/rootfs, $BOARD/rootfs, shared scripts, /etc/baseline (no .DS_Store / ._*)"
    x cp -R "$HERE/common/rootfs/." "$W/"
    [ -d "$HERE/$BOARD/rootfs" ] && x cp -R "$HERE/$BOARD/rootfs/." "$W/"
    # macOS Finder/AppleDouble files in a tree edited on the Mac must never reach the image (B7).
    xsh "find '$W' \( -name .DS_Store -o -name '._*' \) -exec rm -f {} +"
    for f in net-up net-down ocbm-identity ocbm-banner persist ssh-up usb-mount; do
        x cp "$HERE/common/shared/$f" "$W/usr/sbin/$f"
    done
    x cp "$HERE/common/shared/mtd.sh" "$W/lib/baseline/mtd.sh"
    x cp "$HERE/$BOARD/board.env" "$HERE/common/usb-ids.conf" "$HERE/common/ncm.conf" "$W/etc/baseline/"
    x cp "$OUTV/release" "$W/etc/baseline-release"
    if [ "$DRY" = 1 ]; then
        printf '+ write %s/etc/baseline/shadow.default (root:ROOT_PASSWORD_HASH), dev-password marker if the default\n' "$W"
    else
        shadow_default "$W/etc/baseline/shadow.default"
        [ "$ROOT_PASSWORD_HASH" = "$DEV_PASSWORD_HASH" ] && : > "$W/etc/baseline/dev-password"
    fi
    if [ -n "$AUTHORIZED_KEYS" ]; then
        x cp "$AUTHORIZED_KEYS" "$W/etc/baseline/authorized_keys"
        x chmod 0600 "$W/etc/baseline/authorized_keys"
    fi
    x chmod 0700 "$W/root"
    xsh "chmod 0755 '$W/init' '$W/etc/init.d/rcS' '$W'/usr/sbin/*"
    note "kernel modules of variant $V (radio + storage; nothing loads them at boot)"
    xsh "cp -R '$OUTV/modules/lib/modules/.' '$W/lib/modules/' && rm -f '$W'/lib/modules/*/build '$W'/lib/modules/*/source"
    if [ "$RADIO_MODULES" = 1 ] && [ "$RADIO_FW" = 1 ]; then
        note "radio firmware + regulatory.db (for the modules, never loaded at boot)"
        fw_entries | while read -r path sha tag; do
            x mkdir -p "$W/lib/firmware/$(dirname "$path")"
            x cp "$SRC/firmware/$path" "$W/lib/firmware/$path"
        done
        xsh "tar -xJf '$SRC/wireless-regdb-$REGDB_VER.tar.xz' -C '$TOP' && cp '$TOP/wireless-regdb-$REGDB_VER/regulatory.db' '$W/lib/firmware/'"
    fi
    note "checks: no .DS_Store/._* left, etc/mdev.conf present, every rootfs script parses"
    xsh "[ -z \"\$(find '$W' \( -name .DS_Store -o -name '._*' \) -print)\" ]" || die "a macOS metadata file is still in $W"
    xsh "[ -s '$W/etc/mdev.conf' ]" || die "no etc/mdev.conf: mdev's default rule would chmod every node in /dev"
    xsh "for s in '$W/init' '$W/etc/init.d/rcS' '$W/etc/profile' '$W'/etc/baseline/*.sh '$W'/etc/baseline/*.env '$W'/etc/baseline/*.conf '$W'/lib/baseline/*.sh; do
             [ -f \"\$s\" ] || continue; sh -n \"\$s\" || exit 1; done
         for s in '$W'/usr/sbin/*; do [ -f \"\$s\" ] && [ ! -L \"\$s\" ] || continue
             head -c 2 \"\$s\" | grep -q '#!' && { sh -n \"\$s\" || exit 1; }; done; true" || die "a rootfs script does not parse"
    note "mksquashfs (xz, all-root, no xattrs; LIVI's flags)"
    x rm -f "$IMGR"
    x mksquashfs "$W" "$IMGR" -comp xz -no-progress -all-root -no-xattrs -noappend
    if [ "$DRY" = 1 ]; then
        printf '+ check: size(rootfs.img) <= %s B (0xc60000) and a multiple of 4096\n' "$ROOTFS_PART_SIZE"
        printf '+ write %s.sha256\n' "$IMGR"
        return 0
    fi
    size=$(($(wc -c < "$IMGR")))
    [ "$size" -le "$ROOTFS_PART_SIZE" ] || die "rootfs is $size B, the partition $ROOTFS_PART_SIZE B"
    [ $((size % 4096)) -eq 0 ] || die "rootfs is $size B, not a multiple of 4 KiB (flash-rootfs refuses that)"
    sha256sum "$IMGR" | sed "s|  .*|  rootfs.img|" > "$IMGR.sha256"
    log "rootfs $size B of $ROOTFS_PART_SIZE B ($((ROOTFS_PART_SIZE - size)) B free), sha256 $(cut -d' ' -f1 "$IMGR.sha256")"
    x rm -rf "$W"
}

note "baseline build: board $BOARD, steps:$STEPS, TOP=$TOP$([ "$DRY" = 1 ] && echo ' (DRY RUN: nothing is executed, fetched or written)')"
for s in $STEPS; do
    "step_$s"
done
derive_variant
note "next (host, per unit; nothing here touches a device):
  1. python3 -I $HERE/$BOARD/tools/stage_kernel.py --mtd0 <uboot dump> --mtd1 <current kernel dump> \\
       --zimage $OUTV/ccpa-baseline-<radio>.zimg --unit-info <unit_info.txt> --out <kernel-part.img>
     (<radio>: none, or the unit's chip for its Bluetooth DT node: iw416 | rtl8822cs | rtl8822bs)
  2. recovery shell: flash-kernel <kernel-part.img|host:port> <sha256 printed by step 1>
  3. recovery shell: flash-rootfs <rootfs.img|host:port|/mnt/usb/rootfs.img> <sha256 from $OUTV/rootfs.img.sha256>
  host:port: python3 -I $HERE/common/tools/serve_once.py <file>   (see README, Install flow)"

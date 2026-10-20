# SPDX-License-Identifier: GPL-3.0-or-later
# Static userspace recipes for the baselines, sourced by baseline/build.sh (POSIX sh). Arch-neutral:
# the board supplies CROSS_COMPILE / MUSL_TARGET, or TARGET_CC for a userspace compiler of its own
# (the C2Air session builds with the vendor Andes GCC, not musl-gcc).
# The musl and BusyBox-rescue structure follows LIVI scripts/livi-link/arm/build-userspace.sh
# (https://github.com/f-io/LIVI, GPL-3.0-or-later): musl from source with its gcc wrapper, kernel UAPI
# headers installed into the musl sysroot, a second allnoconfig BusyBox for the recovery initramfs.
#
# Needs from build.sh: x, xsh, note, die, fetch_pinned, SRC, UBUILD (build dir), UOUT (output dir),
# JOBS, HERE (baseline/), KDIR (kernel source), KARCH, and the pins from common/versions.env.

# cfg_require SCRIPT OPT...: every --with/--without/--enable/--disable option must be known to SCRIPT.
cfg_require() {
    _script=$1
    shift
    [ "$DRY" = 1 ] && { printf '+ check %s --help knows: %s\n' "$_script" "$*"; return 0; }
    _help=$("$_script" --help 2>/dev/null) || die "$_script --help failed"
    for _o in "$@"; do
        _base=${_o%%=*}
        case $_base in
            --without-*) _alt=--with-${_base#--without-} ;;
            --with-*) _alt=--without-${_base#--with-} ;;
            --disable-*) _alt=--enable-${_base#--disable-} ;;
            --enable-*) _alt=--disable-${_base#--enable-} ;;
            *) _alt=$_base ;;
        esac
        printf '%s\n' "$_help" | grep -q -e "$_base" -e "$_alt" \
            || die "$_script has no option $_base any more: update common/recipes/userspace.sh"
    done
}

assert_static() {
    [ "$DRY" = 1 ] && { printf '+ check statically linked: %s\n' "$*"; return 0; }
    for _b in "$@"; do
        file "$_b" | grep -q 'statically linked' || die "$_b is not statically linked"
    done
}

untar() { # tarball dir
    x rm -rf "$2"
    x mkdir -p "$(dirname "$2")"
    x tar -xf "$1" -C "$(dirname "$2")"
}

build_musl() {
    MUSL_PREFIX=$UBUILD/musl-sysroot
    : "${TARGET_CC:=$MUSL_PREFIX/bin/musl-gcc}"
    if [ "$DRY" != 1 ] && [ -f "$MUSL_PREFIX/lib/libc.a" ]; then
        note "musl $MUSL_VER already in $MUSL_PREFIX"
    else
        note "musl $MUSL_VER -> $MUSL_PREFIX (static libc for every userspace binary)"
        untar "$SRC/musl-$MUSL_VER.tar.gz" "$UBUILD/musl-$MUSL_VER"
        xsh "cd '$UBUILD/musl-$MUSL_VER' && CC='${CROSS_COMPILE}gcc' CROSS_COMPILE='$CROSS_COMPILE' ./configure --prefix='$MUSL_PREFIX' --target='$MUSL_TARGET' --enable-wrapper=gcc > '$UBUILD/musl.log' 2>&1 && make -j$JOBS >> '$UBUILD/musl.log' 2>&1 && make install >> '$UBUILD/musl.log' 2>&1"
    fi
    note "kernel UAPI headers into the musl sysroot (musl ships none)"
    # Out of tree (O=): an in-tree headers_install leaves the source "not clean" and every later
    # O= kernel build then refuses to run.
    x make -C "$KDIR" O="$UBUILD/kernel-headers" ARCH="$KARCH" INSTALL_HDR_PATH="$MUSL_PREFIX" headers_install
}

# bb_merge CONFIG FRAGMENT: each symbol in FRAGMENT replaces its line in CONFIG.
bb_merge() {
    [ "$DRY" = 1 ] && { printf '+ merge %s into %s\n' "$2" "$1"; return 0; }
    awk '
        FNR == NR {
            if ($0 ~ /^CONFIG_[A-Z0-9_]+=/) { s = $0; sub(/=.*/, "", s); want[s] = $0 }
            else if ($0 ~ /^# CONFIG_[A-Z0-9_]+ is not set/) want[$2] = $0
            next
        }
        {
            s = ""
            if ($0 ~ /^CONFIG_/) { s = $0; sub(/=.*/, "", s) }
            else if ($0 ~ /^# CONFIG_[A-Z0-9_]+ is not set/) s = $2
            if (!(s in want)) print
        }
        END { for (s in want) print want[s] }' "$2" "$1" > "$1.new" && mv "$1.new" "$1"
}

# kv_check CONFIG MODE FRAGMENT...: the last value each FRAGMENT line asks for must be in CONFIG
# (unset = n). MODE strict fails, MODE warn only prints. Used for BusyBox and kernel configs alike.
kv_check() {
    _cfg=$1
    _mode=$2
    shift 2
    [ "$DRY" = 1 ] && { printf '+ check (%s) that %s holds every value of: %s\n' "$_mode" "$_cfg" "$*"; return 0; }
    awk -v cfg="$_cfg" -v mode="$_mode" '
        BEGIN {
            while ((getline l < cfg) > 0)
                if (l ~ /^CONFIG_/) { s = l; sub(/=.*/, "", s); v = l; sub(/^[^=]*=/, "", v); have[s] = v }
        }
        /^CONFIG_[A-Z0-9_]+=/ { s = $0; sub(/=.*/, "", s); v = $0; sub(/^[^=]*=/, "", v); want[s] = v; next }
        /^# CONFIG_[A-Z0-9_]+ is not set/ { want[$2] = "n" }
        END {
            for (s in want) {
                got = (s in have) ? have[s] : "n"
                if (got != want[s]) { print mode ": " s " wanted " want[s] ", got " got; bad = 1 }
            }
            exit (mode == "strict" ? bad : 0)
        }' "$@"
}

build_busybox_full() {
    _o=$UBUILD/busybox-full
    note "BusyBox $BUSYBOX_VER full (defconfig + common/busybox/full.fragment), static -> $UOUT/bin/busybox"
    # One pristine source tree, out-of-tree (O=) builds for the full and the recovery binary.
    untar "$SRC/busybox-$BUSYBOX_VER.tar.bz2" "$UBUILD/busybox-$BUSYBOX_VER"
    x rm -rf "$_o"
    x mkdir -p "$_o"
    xsh "make -C '$UBUILD/busybox-$BUSYBOX_VER' O='$_o' defconfig > '$UBUILD/busybox-full-defconfig.log' 2>&1"
    bb_merge "$_o/.config" "$HERE/common/busybox/full.fragment"
    xsh "yes '' | make -C '$_o' oldconfig > /dev/null"
    kv_check "$_o/.config" strict "$HERE/common/busybox/full.fragment" || die "BusyBox full config check failed"
    # busybox.links is its own target (Makefile.custom), not part of the default 'all'.
    xsh "make -C '$_o' -j$JOBS CROSS_COMPILE='$CROSS_COMPILE' CC='$TARGET_CC' busybox busybox.links > '$UBUILD/busybox-full.log' 2>&1"
    x mkdir -p "$UOUT/bin"
    x "${CROSS_COMPILE}strip" -o "$UOUT/bin/busybox" "$_o/busybox"
    x cp "$_o/busybox.links" "$UOUT/bin/busybox.links"
    assert_static "$UOUT/bin/busybox"
}

build_busybox_recovery() {
    _o=$UBUILD/busybox-recovery
    _list=$HERE/common/busybox/recovery.applets
    note "BusyBox $BUSYBOX_VER recovery (allnoconfig + common/busybox/recovery.applets), static -> $UOUT/recovery/busybox"
    x rm -rf "$_o"
    x mkdir -p "$_o" "$UOUT/recovery"
    xsh "make -C '$UBUILD/busybox-$BUSYBOX_VER' O='$_o' allnoconfig > '$UBUILD/busybox-recovery-allnoconfig.log' 2>&1"
    xsh "{ echo CONFIG_STATIC=y; echo '# CONFIG_SH_IS_NONE is not set';
           grep -v '^#' '$_list' | tr ' ' '\n' | grep . | sed 's/^/CONFIG_/; s/\$/=y/'; } > '$_o/recovery.fragment'"
    bb_merge "$_o/.config" "$_o/recovery.fragment"
    xsh "yes '' | make -C '$_o' oldconfig > /dev/null"
    kv_check "$_o/.config" strict "$_o/recovery.fragment" || die "BusyBox recovery config check failed"
    xsh "make -C '$_o' -j$JOBS CROSS_COMPILE='$CROSS_COMPILE' CC='$TARGET_CC' busybox busybox.links > '$UBUILD/busybox-recovery.log' 2>&1"
    x "${CROSS_COMPILE}strip" -o "$UOUT/recovery/busybox" "$_o/busybox"
    x cp "$_o/busybox.links" "$UOUT/recovery/busybox.links"
    assert_static "$UOUT/recovery/busybox"
}

build_dropbear() {
    _s=$UBUILD/dropbear-$DROPBEAR_VER
    note "dropbear $DROPBEAR_VER multi-call (dropbear dbclient dropbearkey scp), static, public-key + password server"
    untar "$SRC/dropbear-$DROPBEAR_VER.tar.bz2" "$_s"
    x cp "$HERE/common/dropbear/localoptions.h" "$_s/localoptions.h"
    # A macro dropbear does not know is silently ignored: every name must exist upstream.
    xsh "for n in \$(sed -n 's/^#define \\([A-Z0-9_]*\\).*/\\1/p' '$HERE/common/dropbear/localoptions.h'); do
            grep -q \"define \$n\\b\" '$_s/src/default_options.h' 2>/dev/null || grep -q \"define \$n\\b\" '$_s/default_options.h' 2>/dev/null \\
            || { echo \"localoptions.h: \$n is not a dropbear $DROPBEAR_VER option\"; exit 1; }
         done" || die "common/dropbear/localoptions.h names an option dropbear $DROPBEAR_VER does not have"
    set -- --host="$MUSL_TARGET" --enable-static --disable-zlib --disable-lastlog --disable-utmp \
        --disable-utmpx --disable-wtmp --disable-wtmpx --disable-pututline --disable-pututxline
    cfg_require "$_s/configure" "$@"
    xsh "cd '$_s' && ./configure $* CC='$TARGET_CC' > '$UBUILD/dropbear.log' 2>&1 &&
         make -j$JOBS PROGRAMS='dropbear dbclient dropbearkey scp' MULTI=1 >> '$UBUILD/dropbear.log' 2>&1"
    x mkdir -p "$UOUT/usr/sbin"
    x "${CROSS_COMPILE}strip" -o "$UOUT/usr/sbin/dropbearmulti" "$_s/dropbearmulti"
    assert_static "$UOUT/usr/sbin/dropbearmulti"
}

build_sftp_server() {
    _s=$UBUILD/openssh-$OPENSSH_VER
    note "OpenSSH $OPENSSH_VER sftp-server only, static, no OpenSSL/zlib (dropbear's SFTPSERVER_PATH)"
    untar "$SRC/openssh-$OPENSSH_VER.tar.gz" "$_s"
    set -- --host="$MUSL_TARGET" --without-openssl --without-zlib --without-pam --without-selinux \
        --without-kerberos5 --without-libedit --without-security-key-builtin --disable-strip \
        --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx
    cfg_require "$_s/configure" "$@"
    xsh "cd '$_s' && ./configure $* CC='$TARGET_CC' LDFLAGS=-static > '$UBUILD/openssh.log' 2>&1 &&
         make -j$JOBS sftp-server >> '$UBUILD/openssh.log' 2>&1"
    x mkdir -p "$UOUT/usr/libexec"
    x "${CROSS_COMPILE}strip" -o "$UOUT/usr/libexec/sftp-server" "$_s/sftp-server"
    assert_static "$UOUT/usr/libexec/sftp-server"
}

# hciup: the baseline's one-file HCI up/down tool (common/hciup/hciup.c), for `radio up`'s Bluetooth.
build_hciup() {
    note "hciup (common/hciup/hciup.c), static"
    x mkdir -p "$UBUILD/hciup" "$UOUT/usr/sbin"
    x "$TARGET_CC" -static -Os -Wall -Wextra -o "$UBUILD/hciup/hciup" "$HERE/common/hciup/hciup.c"
    x "${CROSS_COMPILE}strip" -o "$UOUT/usr/sbin/hciup" "$UBUILD/hciup/hciup"
    assert_static "$UOUT/usr/sbin/hciup"
}

# ----------------------------------------------------------------- radio tools (RADIO_TOOLS=1)
# Libraries only these tools use go to their own prefix, never into the musl sysroot.
RADIO_SYSROOT=${UBUILD:-}/radio-sysroot

build_libnl() {
    _s=$UBUILD/libnl-$LIBNL_VER
    note "libnl $LIBNL_VER, static libraries only (libnl-3 + libnl-genl-3 for iw and wpa_supplicant) -> $RADIO_SYSROOT"
    untar "$SRC/libnl-$LIBNL_VER.tar.gz" "$_s"
    set -- --host="$MUSL_TARGET" --prefix="$RADIO_SYSROOT" --disable-shared --enable-static --enable-cli=no --disable-debug
    cfg_require "$_s/configure" "$@"
    xsh "cd '$_s' && ./configure $* CC='$TARGET_CC' > '$UBUILD/libnl.log' 2>&1 &&
         make -j$JOBS >> '$UBUILD/libnl.log' 2>&1 && make install >> '$UBUILD/libnl.log' 2>&1"
}

build_iw() {
    _s=$UBUILD/iw-$IW_VER
    note "iw $IW_VER, static (libnl $LIBNL_VER) -> $UOUT/usr/sbin/iw"
    untar "$SRC/iw-$IW_VER.tar.xz" "$_s"
    # iw's Makefile asks pkg-config for libnl in $(shell ...): environment, not make variables. CFLAGS and
    # LDFLAGS through the environment too, so its own CFLAGS += lines still apply.
    xsh "cd '$_s' && PKG_CONFIG_LIBDIR='$RADIO_SYSROOT/lib/pkgconfig' PKG_CONFIG_PATH= CFLAGS='-Os' LDFLAGS=-static \
         make -j$JOBS CC='$TARGET_CC' > '$UBUILD/iw.log' 2>&1"
    x mkdir -p "$UOUT/usr/sbin"
    x "${CROSS_COMPILE}strip" -o "$UOUT/usr/sbin/iw" "$_s/iw"
    assert_static "$UOUT/usr/sbin/iw"
}

# wpa_supplicant + wpa_cli + wpa_passphrase: station only, WPA2-PSK, internal crypto, nl80211, the UNIX
# control socket; common/wpa_supplicant/wpa_supplicant.config says what is in and why WPA3 is not.
build_wpa_supplicant() {
    _s=$UBUILD/wpa_supplicant-$WPA_SUPPLICANT_VER
    note "wpa_supplicant $WPA_SUPPLICANT_VER (wpa_supplicant wpa_cli wpa_passphrase), static, nl80211, internal crypto"
    untar "$SRC/wpa_supplicant-$WPA_SUPPLICANT_VER.tar.gz" "$_s"
    x cp "$HERE/common/wpa_supplicant/wpa_supplicant.config" "$_s/wpa_supplicant/.config"
    xsh "printf '%s\\n' 'LIBS += -L$RADIO_SYSROOT/lib' >> '$_s/wpa_supplicant/.config'"
    # CFLAGS/LDFLAGS/EXTRALIBS from the environment: on the make command line they would replace the
    # Makefile's own CFLAGS += -DCONFIG_... lines. EXTRALIBS repeats -lnl-3 after -lnl-genl-3 (static
    # link order; the Makefile lists -lnl-3 first).
    xsh "cd '$_s/wpa_supplicant' && CFLAGS='-MMD -Os -Wall' LDFLAGS=-static EXTRALIBS='-lnl-3' \
         make -j$JOBS CC='$TARGET_CC' LIBNL_INC='$RADIO_SYSROOT/include/libnl3' V=1 \
         wpa_supplicant wpa_cli wpa_passphrase > '$UBUILD/wpa_supplicant.log' 2>&1"
    x mkdir -p "$UOUT/usr/sbin"
    for _b in wpa_supplicant wpa_cli wpa_passphrase; do
        x "${CROSS_COMPILE}strip" -o "$UOUT/usr/sbin/$_b" "$_s/wpa_supplicant/$_b"
    done
    assert_static "$UOUT/usr/sbin/wpa_supplicant" "$UOUT/usr/sbin/wpa_cli" "$UOUT/usr/sbin/wpa_passphrase"
    # The configuration that was built (no SAE, no D-Bus) is part of the record.
    xsh "grep -q -- '-DCONFIG_DRIVER_NL80211' '$UBUILD/wpa_supplicant.log' && ! grep -q -- '-DCONFIG_CTRL_IFACE_DBUS' '$UBUILD/wpa_supplicant.log'" \
        || die "wpa_supplicant was not built as configured (nl80211 on, D-Bus off): $UBUILD/wpa_supplicant.log"
}

# ncurses: only libtinfo (termcap/terminfo functions readline needs), no terminfo database on the unit:
# the entries for linux, vt100, xterm, xterm-256color and screen are compiled in (--with-fallbacks; the
# build host's tic/infocmp generate them). Any other TERM gets readline's dumb-terminal behaviour.
build_ncurses() {
    _s=$UBUILD/ncurses-$NCURSES_VER
    note "ncurses $NCURSES_VER libtinfo, static, built-in terminal entries (for readline -> btmgmt) -> $RADIO_SYSROOT"
    untar "$SRC/ncurses-$NCURSES_VER.tar.gz" "$_s"
    set -- --host="$MUSL_TARGET" --prefix="$RADIO_SYSROOT" --with-build-cc=gcc --without-shared --with-normal \
        --with-termlib --disable-widec --without-cxx --without-cxx-binding --without-ada --without-progs \
        --without-tests --without-manpages --disable-database --with-fallbacks=linux,vt100,xterm,xterm-256color,screen
    cfg_require "$_s/configure" "$@"
    xsh "cd '$_s' && ./configure $* CC='$TARGET_CC' > '$UBUILD/ncurses.log' 2>&1 &&
         make -j$JOBS libs >> '$UBUILD/ncurses.log' 2>&1 && make install.libs >> '$UBUILD/ncurses.log' 2>&1"
}

# readline_patch_file NNN: where fetch puts upstream patch NNN, relative to $SRC (readline-8.3-patches/readline83-NNN).
readline_patch_file() {
    echo "readline-$READLINE_VER-patches/readline$(echo "$READLINE_VER" | tr -d .)-$1"
}

build_readline() {
    _s=$UBUILD/readline-$READLINE_VER
    note "readline $READLINE_VER + upstream patches, static (for btmgmt's shell) -> $RADIO_SYSROOT"
    untar "$SRC/readline-$READLINE_VER.tar.gz" "$_s"
    # shellcheck disable=SC2086
    set -- $READLINE_PATCHES
    while [ $# -ge 2 ]; do
        xsh "cd '$_s' && patch -p0 -s < '$SRC/$(readline_patch_file "$1")'" || die "readline patch $1 does not apply"
        shift 2
    done
    set -- --host="$MUSL_TARGET" --prefix="$RADIO_SYSROOT" --disable-shared --enable-static
    cfg_require "$_s/configure" "$@"
    xsh "cd '$_s' && ./configure $* CC='$TARGET_CC' > '$UBUILD/readline.log' 2>&1 &&
         make -j$JOBS static >> '$UBUILD/readline.log' 2>&1 && make install-static >> '$UBUILD/readline.log' 2>&1"
}

# BlueZ: ONLY btmgmt (kernel management socket), hciconfig and hcitool (deprecated, raw HCI): no
# bluetoothd, no D-Bus, no GLib on the unit. configure requires GLib and D-Bus unconditionally
# (PKG_CHECK_MODULES in configure.ac), although these three tools use neither: the *_CFLAGS/*_LIBS
# variables satisfy the check, and their values are sentinels, so a GLib or D-Bus header or library
# reaching a build fails it instead of being linked. btmgmt's Makefile rule links BlueZ's GLib mainloop
# (src/libshared-glib.la); it is linked here against BlueZ's own non-GLib mainloop (src/libshared-mainloop.la,
# the one btmon and btattach use) instead. No source file is changed.
build_bluez_tools() {
    _s=$UBUILD/bluez-$BLUEZ_VER
    note "BlueZ $BLUEZ_VER btmgmt + hciconfig + hcitool, static, without GLib/D-Bus/bluetoothd -> $UOUT/usr/bin"
    untar "$SRC/bluez-$BLUEZ_VER.tar.xz" "$_s"
    set -- --host="$MUSL_TARGET" --prefix=/usr --disable-shared --enable-static --enable-deprecated \
        --disable-obex --disable-udev --disable-cups --disable-systemd --disable-manpages --disable-datafiles \
        --disable-monitor --with-dbusconfdir=/nonexistent --with-dbussystembusdir=/nonexistent \
        --with-dbussessionbusdir=/nonexistent
    cfg_require "$_s/configure" "$@"
    _ml='lib/libbluetooth-internal.la src/libshared-mainloop.la'
    xsh "cd '$_s' && GLIB_CFLAGS='-DBASELINE_NO_GLIB' GLIB_LIBS='-lbaseline-no-glib' \
         DBUS_CFLAGS='-DBASELINE_NO_DBUS' DBUS_LIBS='-lbaseline-no-dbus' \
         ./configure $* CC='$TARGET_CC' CPPFLAGS='-I$RADIO_SYSROOT/include' LDFLAGS='-L$RADIO_SYSROOT/lib' \
         > '$UBUILD/bluez.log' 2>&1 &&
         make -j$JOBS LDFLAGS='-L$RADIO_SYSROOT/lib -all-static' \
             tools_btmgmt_LDADD='$_ml -lreadline -ltinfo' tools_btmgmt_DEPENDENCIES='$_ml' \
             tools/btmgmt tools/hciconfig tools/hcitool >> '$UBUILD/bluez.log' 2>&1"
    xsh "! grep -E -- '-lbaseline-no-(glib|dbus)|glib\\.h|dbus/dbus\\.h' '$UBUILD/bluez.log'" \
        || die "a BlueZ tool reached for GLib or D-Bus: $UBUILD/bluez.log"
    x mkdir -p "$UOUT/usr/bin"
    for _b in btmgmt hciconfig hcitool; do
        x "${CROSS_COMPILE}strip" -o "$UOUT/usr/bin/$_b" "$_s/tools/$_b"
    done
    assert_static "$UOUT/usr/bin/btmgmt" "$UOUT/usr/bin/hciconfig" "$UOUT/usr/bin/hcitool"
}

build_mtd_utils() {
    _s=$UBUILD/mtd-utils-$MTD_UTILS_VER
    note "mtd-utils $MTD_UTILS_VER flash_erase only, static (BusyBox has flash_eraseall, not flash_erase)"
    untar "$SRC/mtd-utils-$MTD_UTILS_VER.tar.bz2" "$_s"
    set -- --host="$MUSL_TARGET" --without-jffs --without-ubifs --without-xattr --without-lzo \
        --without-zstd --without-crypto --without-tests
    cfg_require "$_s/configure" "$@"
    xsh "cd '$_s' && ./configure $* CC='$TARGET_CC' LDFLAGS=-static > '$UBUILD/mtd-utils.log' 2>&1 &&
         make -j$JOBS flash_erase >> '$UBUILD/mtd-utils.log' 2>&1"
    x "${CROSS_COMPILE}strip" -o "$UOUT/usr/sbin/flash_erase" "$_s/flash_erase"
    assert_static "$UOUT/usr/sbin/flash_erase"
}

build_exfatprogs() {
    _s=$UBUILD/exfatprogs-$EXFATPROGS_VER
    note "exfatprogs $EXFATPROGS_VER (mkfs.exfat, fsck.exfat), static, optional"
    # configure.ac requires libblkid (util-linux or e2fsprogs) via pkg-config, with no switch to drop
    # it; this recipe builds no static libblkid, so stop here instead of half-way through configure
    # (2026-10-20 build: "Package 'blkid' ... not found"). OPEN: pin + cross-build util-linux libblkid.
    [ "$DRY" = 1 ] || [ -n "${EXFAT_BLKID_PC:-}" ] \
        || die "EXFATPROGS=1 needs a static libblkid for $MUSL_TARGET (set EXFAT_BLKID_PC=<dir with blkid.pc>); the recipe does not build one yet"
    untar "$SRC/exfatprogs-$EXFATPROGS_VER.tar.gz" "$_s"
    cfg_require "$_s/configure" --host="$MUSL_TARGET"
    xsh "cd '$_s' && PKG_CONFIG_LIBDIR='${EXFAT_BLKID_PC:-}' ./configure --host='$MUSL_TARGET' CC='$TARGET_CC' LDFLAGS=-static > '$UBUILD/exfatprogs.log' 2>&1 &&
         make -j$JOBS >> '$UBUILD/exfatprogs.log' 2>&1"
    x "${CROSS_COMPILE}strip" -o "$UOUT/usr/sbin/mkfs.exfat" "$_s/mkfs/mkfs.exfat"
    x "${CROSS_COMPILE}strip" -o "$UOUT/usr/sbin/fsck.exfat" "$_s/fsck/fsck.exfat"
    assert_static "$UOUT/usr/sbin/mkfs.exfat" "$UOUT/usr/sbin/fsck.exfat"
}

# SPDX-License-Identifier: GPL-3.0-or-later
# Based on LIVI by Lasse Heitgres (https://github.com/f-io/LIVI)
# Modified 2026-10-19/20: partitions found by DT label; the bootstate marker as shell functions shared
# by init, the flash helpers and rcS.
# Sourced by the recovery init, its flash helpers and the rootfs rcS (installed as /lib/baseline/mtd.sh).
# MTD partitions are found by their DT label, never by number. The bootstate logic follows LIVI
# (scripts/livi-link/common/initramfs/init and common/rootfs/etc/init.d/rcS, GPL-3.0-or-later):
# the initramfs writes an 8-byte marker before it hands over to the rootfs, the rootfs erases it
# once its ways in are up, and a marker still present at the next boot keeps that boot in recovery.

# MTD_SYS / MTD_DEV replace /sys/class/mtd and /dev for the host self-test (common/tools/selftest.sh),
# which runs the flash helpers' refusal paths against plain files. Unset on a unit.
MTD_SYS=${MTD_SYS:-/sys/class/mtd}
MTD_DEV=${MTD_DEV:-/dev}

BOOT_MARK=CCPABOOT
BOOT_MARK_HEX=43435041424f4f54
ERASED8_HEX=ffffffffffffffff

# mtd_num LABEL: print N of /dev/mtdN whose name is LABEL (the mtdNro class entries are skipped).
mtd_num() {
    for _n in "$MTD_SYS"/mtd[0-9]*; do
        case ${_n##*/} in *ro) continue ;; esac
        [ "$(cat "$_n/name" 2>/dev/null)" = "$1" ] && { echo "${_n##*/mtd}"; return 0; }
    done
    return 1
}

mtd_attr() { cat "$MTD_SYS/mtd$1/$2" 2>/dev/null; }

# bootstate_read N: the first 8 bytes of /dev/mtdN as hex.
bootstate_read() { hexdump -v -n 8 -e '8/1 "%02x"' "$MTD_DEV/mtd$1" 2>/dev/null; }

bootstate_set() {
    _m=$(bootstate_read "$1")
    [ "$_m" = "$BOOT_MARK_HEX" ] && return 0
    [ "$_m" = "$ERASED8_HEX" ] || flash_eraseall -q "$MTD_DEV/mtd$1" || return 1
    printf '%s' "$BOOT_MARK" > "$MTD_DEV/mtd$1" || return 1
    [ "$(bootstate_read "$1")" = "$BOOT_MARK_HEX" ]
}

bootstate_clear() {
    [ "$(bootstate_read "$1")" = "$ERASED8_HEX" ] && return 0
    flash_eraseall -q "$MTD_DEV/mtd$1"
}

# SPDX-License-Identifier: GPL-3.0-or-later
# Sourced by the recovery init, its flash helpers and the rootfs rcS (installed as /lib/baseline/mtd.sh).
# MTD partitions are found by their DT label, never by number. The bootstate logic follows LIVI
# (scripts/livi-link/common/initramfs/init and common/rootfs/etc/init.d/rcS, GPL-3.0-or-later):
# the initramfs writes an 8-byte marker before it hands over to the rootfs, the rootfs erases it
# once its ways in are up, and a marker still present at the next boot keeps that boot in recovery.

BOOT_MARK=CCPABOOT
BOOT_MARK_HEX=43435041424f4f54
ERASED8_HEX=ffffffffffffffff

# mtd_num LABEL: print N of /dev/mtdN whose name is LABEL (the mtdNro class entries are skipped).
mtd_num() {
    for _n in /sys/class/mtd/mtd[0-9]*; do
        case ${_n##*/} in *ro) continue ;; esac
        [ "$(cat "$_n/name" 2>/dev/null)" = "$1" ] && { echo "${_n##*/mtd}"; return 0; }
    done
    return 1
}

mtd_attr() { cat "/sys/class/mtd/mtd$1/$2" 2>/dev/null; }

# bootstate_read N: the first 8 bytes of /dev/mtdN as hex.
bootstate_read() { hexdump -v -n 8 -e '8/1 "%02x"' "/dev/mtd$1" 2>/dev/null; }

bootstate_set() {
    _m=$(bootstate_read "$1")
    [ "$_m" = "$BOOT_MARK_HEX" ] && return 0
    [ "$_m" = "$ERASED8_HEX" ] || flash_eraseall -q "/dev/mtd$1" || return 1
    printf '%s' "$BOOT_MARK" > "/dev/mtd$1" || return 1
    [ "$(bootstate_read "$1")" = "$BOOT_MARK_HEX" ]
}

bootstate_clear() {
    [ "$(bootstate_read "$1")" = "$ERASED8_HEX" ] && return 0
    flash_eraseall -q "/dev/mtd$1"
}

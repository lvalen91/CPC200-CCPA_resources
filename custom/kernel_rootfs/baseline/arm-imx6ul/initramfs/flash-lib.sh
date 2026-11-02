# SPDX-License-Identifier: GPL-3.0-or-later
# Based on LIVI by Lasse Heitgres (https://github.com/f-io/LIVI)
# Modified 2026-10-19/20: the readback and erase steps are shell functions shared by the on-unit
# flash helpers.
# Shared by flash-rootfs and flash-kernel (installed as /lib/baseline/flash-lib.sh in the recovery
# initramfs). The verify-by-readback (dd | sha256sum) and erase-only-after-verify steps follow LIVI's
# provisioner (native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/boot.rs, GPL-3.0-or-later).
#
# Exit status of both helpers (usb-update and the self-test rely on it):
#   0  written and verified (flash-kernel: env erased too)
#   2  usage
#   3  nothing to do: the partition already holds the image (with --if-changed), or flash-kernel found
#      this kernel already installed (U-Boot converted its staged head); nothing was written
#   4  refused before anything was written (wrong sha256, size, magic, layout, stale or foreign image):
#      flash is untouched, powering off is safe
#   1  failed AFTER the write started: read the message (flash-kernel: DO NOT POWER OFF)
# LED (red): fast blink while a write runs, back to the recovery blink when done, solid on after a
# failure that happened after the write started.

# Long writes are started from telnet/ssh sessions; a closed session must not SIGHUP flashcp (RUNBOOK
# 2026-10-19: a flashcp was killed mid-write that way). SIG_IGN is inherited across exec.
trap '' HUP PIPE

STARTED=
LEDR=${LED_RED:-/sys/class/leds/red}

led() { # led timer ON OFF | led solid
    [ -w "$LEDR/trigger" ] || return 0
    if [ "$1" = solid ]; then
        echo none > "$LEDR/trigger"
        echo 1 > "$LEDR/brightness"
    else
        echo timer > "$LEDR/trigger"
        echo "$2" > "$LEDR/delay_on"
        echo "$3" > "$LEDR/delay_off"
    fi
} 2>/dev/null

say() { echo "$ME: $*"; echo "$ME: $*" >> "$LOG"; }
die() {
    if [ -n "$STARTED" ]; then
        echo "$ME: $*" >&2
        echo "$ME: FAILED: $*" >> "$LOG"
        led solid
        exit 1
    fi
    echo "$ME: $* (nothing written)" >&2
    echo "$ME: REFUSED: $* (nothing written)" >> "$LOG"
    exit 4
}
# started: from here on a failure is a failed write, not a refusal.
started() { STARTED=1; led timer 100 100; }
finished() { led timer 500 500; }

valid_sha() {
    [ "${#1}" -eq 64 ] || return 1
    case $1 in *[!0-9a-f]*) return 1 ;; esac
    return 0
}

sha_file() {
    # shellcheck disable=SC2046
    set -- $(sha256sum "$1" 2>/dev/null)
    echo "$1"
}

sha_stdin() {
    # shellcheck disable=SC2046
    set -- $(sha256sum)
    echo "$1"
}

fsize() { echo $(($(wc -c < "$1"))); }

mounted() {
    while read -r _dev _mnt _rest; do
        [ "$_dev" = "$1" ] && return 0
    done < /proc/mounts
    return 1
}

# fetch SRC DEST: SRC is a local file (used in place, e.g. /mnt/usb/rootfs.img) or host:port, which is
# PULLED with nc into DEST. Pull, not push: on 2026-10-19 four macOS nc pushes into busybox nc over NCM
# failed (the first left 146,432 B), while a pull from a host-side Python server did not (RUNBOOK).
fetch() {
    if [ -f "$1" ]; then
        echo "$1"
        return 0
    fi
    case $1 in
        *:*)
            _h=${1%:*}
            _p=${1##*:}
            case $_p in "" | *[!0-9]*) return 1 ;; esac
            say "pulling $_h:$_p into $2" >&2
            rm -f "$2"
            nc "$_h" "$_p" > "$2" || { rm -f "$2"; return 1; }
            echo "$2"
            return 0
            ;;
    esac
    return 1
}

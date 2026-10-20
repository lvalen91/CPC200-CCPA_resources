# SPDX-License-Identifier: GPL-3.0-or-later
# Shared by flash-rootfs and flash-kernel (installed as /lib/baseline/flash-lib.sh in the recovery
# initramfs). The verify-by-readback (dd | sha256sum) and erase-only-after-verify steps follow LIVI's
# provisioner (native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/boot.rs, GPL-3.0-or-later).

# Long writes are started from telnet sessions; a closed session must not SIGHUP flashcp (RUNBOOK
# 2026-10-19: a flashcp was killed mid-write that way). SIG_IGN is inherited across exec.
trap '' HUP PIPE

say() { echo "$ME: $*"; echo "$ME: $*" >> "$LOG"; }
die() { echo "$ME: $*" >&2; echo "$ME: FAILED: $*" >> "$LOG"; exit 1; }

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

# fetch SRC DEST: SRC is a local file (used in place) or host:port, which is PULLED with nc into
# DEST. Pull, not push: a macOS nc pushing into busybox nc over NCM truncated at ~146 KB three times
# (RUNBOOK 2026-10-19), a pull from a host-side server did not.
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

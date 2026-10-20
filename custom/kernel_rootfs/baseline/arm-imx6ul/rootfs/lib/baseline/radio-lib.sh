# SPDX-License-Identifier: GPL-3.0-or-later
# radio-lib.sh: sourced by radio, wifi-connect, wifi-scan and bt-scan (POSIX sh). One copy of what they
# share, so they describe the radio the same way.
#
#   wifs / hcis          wireless interfaces (those with phy80211) / HCI devices, from sysfs, never assumed
#   ifstate IF           "administratively up|down, carrier|no carrier (operstate X)" (B11)
#   radio_off_hint       what to say when there is no wireless interface or HCI device
#   mod_load NAME [P=V]  load a module AFTER every module it depends on, from the kernel's modules.dep (B10)
#
# Why mod_load and not `modprobe NAME` (B10): the rootfs BusyBox is built with MODPROBE_SMALL (the
# defconfig default), and that modprobe's first lookup in a process scans the module directory and
# insmods the module it is looking for AS SOON AS IT FINDS IT, before its dependencies (busybox 1.38.0
# modutils/modprobe-small.c fileAction: "It will attempt module load"); only when that fails does it
# load the dependencies and retry. The kernel logs one "Unknown symbol" line per missing symbol for the
# failed attempt: the burst seen on the IW416 unit for mwifiex_sdio and btnxpuart (2026-10-20). Loading
# every dependency first, each with insmod, makes that first attempt unnecessary.
#
# Test hooks (host self-test only; the unit uses the defaults): RADIO_SYS (/sys), RADIO_RUN (/run),
# MODLOAD_DIR (/lib/modules/<uname -r>), MODLOAD_PROC (/proc/modules).
SYS=${RADIO_SYS:-/sys}
RUN=${RADIO_RUN:-/run}
MODLOAD_DIR=${MODLOAD_DIR:-/lib/modules/$(uname -r)}
MODLOAD_PROC=${MODLOAD_PROC:-/proc/modules}

wifs() {
    for _w in "$SYS"/class/net/*; do
        [ -e "$_w/phy80211" ] && echo "${_w##*/}"
    done
    return 0
}

hcis() {
    for _h in "$SYS"/class/bluetooth/hci*; do
        [ -e "$_h" ] && echo "${_h##*/}"
    done
    return 0
}

# ifstate IF: the admin state is IFF_UP of the flags (what `ip link set up` sets), the carrier is the
# link (on Wi-Fi: associated), operstate the kernel's RFC 2863 summary of both. Carrier cannot be read
# while the interface is administratively down (EINVAL), which reads here as "no carrier".
ifstate() {
    _fl=$(cat "$SYS/class/net/$1/flags" 2>/dev/null)
    _ad="administratively down"
    [ -n "$_fl" ] && [ $((_fl & 1)) -eq 1 ] && _ad="administratively up"
    _ca="no carrier"
    [ "$(cat "$SYS/class/net/$1/carrier" 2>/dev/null)" = 1 ] && _ca=carrier
    echo "$_ad, $_ca (operstate $(cat "$SYS/class/net/$1/operstate" 2>/dev/null || echo unknown))"
}

radio_off_hint() {
    echo "the radios are OFF at boot; run 'radio up' first ('radio status' shows what is on)"
}

# mod_name PATH: kernel/drivers/.../mwifiex_sdio.ko -> mwifiex_sdio ('-' -> '_', as /proc/modules has it)
mod_name() {
    _mn=${1##*/}
    _mn=${_mn%%.ko*}
    echo "$_mn" | tr - _
}

mod_loaded() { grep -q "^$(echo "$1" | tr - _) " "$MODLOAD_PROC"; }

# mod_dep_line NAME: NAME's line of modules.dep ("path: dep-path dep-path ..."), empty if it has none.
mod_dep_line() {
    awk -v m="$1" '{ n = $1; sub(/:$/, "", n); sub(/.*\//, "", n); sub(/\.ko.*/, "", n); gsub(/-/, "_", n)
                     if (n == m) { print; exit } }' "$MODLOAD_DIR/modules.dep"
}

# mod_insmod PATH [PARAMS]: insmod, and a module that is there afterwards counts (a parallel load by
# the kernel's own request_module, e.g. cfg80211 for an nl80211 socket, makes insmod say "exists").
mod_insmod() {
    _mp=$1
    shift
    insmod "$MODLOAD_DIR/$_mp" "$@" || mod_loaded "$(mod_name "$_mp")"
}

mod_load() {
    _want=$(echo "$1" | tr - _)
    shift
    if mod_loaded "$_want"; then
        [ $# -gt 0 ] && echo "modload: $_want is already loaded: $* not applied (unload it first)"
        return 0
    fi
    [ -r "$MODLOAD_DIR/modules.dep" ] || { echo "modload: no $MODLOAD_DIR/modules.dep"; return 1; }
    _line=$(mod_dep_line "$_want")
    [ -n "$_line" ] || { echo "modload: $_want is not in $MODLOAD_DIR/modules.dep"; return 1; }
    _self=${_line%%:*}
    # The closure: modules.dep already lists every transitive dependency on the module's line; a module
    # is inserted only when every dependency on ITS OWN line is loaded, whatever the order on the line.
    _todo=${_line#*:}
    _pass=0
    while :; do
        case $_todo in *[!\ ]*) ;; *) break ;; esac
        _left=
        for _p in $_todo; do
            _n=$(mod_name "$_p")
            mod_loaded "$_n" && continue
            _ready=1
            _dl=$(mod_dep_line "$_n")
            for _d in ${_dl#*:}; do
                mod_loaded "$(mod_name "$_d")" && continue
                _ready=
                case " $_todo $_left " in *" $_d "*) ;; *) _left="$_left $_d" ;; esac
            done
            if [ -n "$_ready" ]; then
                mod_insmod "$_p" || { echo "modload: insmod $_n failed (dmesg)"; return 1; }
            else
                _left="$_left $_p"
            fi
        done
        _todo=$_left
        _pass=$((_pass + 1))
        # every pass loads a module or adds an unlisted dependency; modules.dep has no cycles
        [ "$_pass" -lt 30 ] || { echo "modload: cannot order the dependencies of $_want:$_todo"; return 1; }
    done
    mod_insmod "$_self" "$@" || { echo "modload: insmod $_want failed (dmesg)"; return 1; }
}

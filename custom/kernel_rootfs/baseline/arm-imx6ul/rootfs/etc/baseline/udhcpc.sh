#!/bin/sh
# shellcheck disable=SC2154 # interface, ip, mask, router, dns, domain: udhcpc's environment
# SPDX-License-Identifier: GPL-3.0-or-later
# udhcpc event script for wifi-connect (busybox udhcpc -s): configures ONLY the Wi-Fi interface udhcpc
# runs on, never usb0/NCM. RAM only: the address and route live in the kernel, DNS in /run/resolv.conf
# (/etc/resolv.conf links there). Variables from udhcpc: interface ip mask broadcast router dns domain.
RUN=${RADIO_RUN:-/run}
[ -n "${1:-}" ] && [ -n "${interface:-}" ] || exit 1
case $1 in
    deconfig)
        ip -4 addr flush dev "$interface"
        ip link set dev "$interface" up
        ;;
    bound | renew)
        ip -4 addr flush dev "$interface"
        ip addr add "$ip/${mask:-24}" ${broadcast:+broadcast "$broadcast"} dev "$interface" || exit 1
        if [ -n "${router:-}" ]; then
            while ip route del default dev "$interface" 2> /dev/null; do :; done
            for r in $router; do
                ip route add default via "$r" dev "$interface" metric 10 && break
            done
        fi
        if [ -n "${dns:-}" ]; then
            {
                echo "# udhcpc on $interface (wifi-connect)"
                [ -n "${domain:-}" ] && echo "search $domain"
                for d in $dns; do echo "nameserver $d"; done
            } > "$RUN/resolv.conf.$interface" && mv "$RUN/resolv.conf.$interface" "$RUN/resolv.conf"
        fi
        echo "udhcpc: $interface $1 $ip/${mask:-24}${router:+ via $router}"
        ;;
    leasefail | nak)
        echo "udhcpc: $interface $1"
        ;;
esac
exit 0

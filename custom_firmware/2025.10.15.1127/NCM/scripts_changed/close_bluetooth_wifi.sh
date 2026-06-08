#!/bin/sh
########################
# Copyright(c) 2014-2018 DongGuan HeWei Communication Technologies Co. Ltd.
# file    dbus_run.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    26Nov18
########################
EnsureProcessKill() {
    killall "$1"
    i=1
    while [ "$i" -le 60 ]
    do
        ProcNumber=`ps |grep -w "$1"|grep -v grep|wc -l`
        if [ "$ProcNumber" -le 0 ];then
           break
        else
           sleep 0.2
           killall "$1"
        fi
        i=$((i+1))
    done
}

#LOCK
LOCKFILE="/tmp/run_bluetooth_wifi_lock"
if [ -f "${LOCKFILE}" ]
  then
    exit
  else
    touch "${LOCKFILE}"
fi

#close wifi
echo "[close_bluetooth_wifi] closing wifi (p2p group remove, wlan0 down, stop hostapd/udhcpd)"
if [ -e /usr/sbin/wpa_cli ]; then
	test -e /tmp/bcmdhd.ko && useVirtualDev=1 || useVirtualDev=0
	if [ "$useVirtualDev" -eq 1 ]; then
		wpa_cli -i wlan0 list_network && (wpa_cli p2p_group_remove wlan0;sleep 0.1;iw dev sta0 interface add wlan0 type managed)
	else
		wpa_cli -i wlan0 list_network |grep CURRENT && wpa_cli -i wlan0 p2p_group_remove wlan0
	fi
fi
ifconfig wlan0 down
echo closed > /tmp/wifi_status
EnsureProcessKill hostapd
EnsureProcessKill udhcpd
echo "[close_bluetooth_wifi] wifi closed (hostapd/udhcpd stopped, wlan0 down)"

rm -f /tmp/wifi_connection_list
rm -f /tmp/.dhcp_record

#UNLOCK
if [ -f "${LOCKFILE}" ]
  then
    rm -rf "${LOCKFILE}"
fi

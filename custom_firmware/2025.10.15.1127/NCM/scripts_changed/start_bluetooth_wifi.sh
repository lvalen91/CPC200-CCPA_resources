#!/bin/sh
########################
# Copyright(c) 2014-2018 DongGuan HeWei Communication Technologies Co. Ltd.
# file    dbus_run.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    26Nov18
########################
# NCM-only guard: suppress the WiFi AP from EVERY caller (start_main_service:112,
# init_bluetooth_wifi:118's background block, ARMadb) when /script/ncm_only is set.
# ncm_wifi leaves this flag absent so custom_init.sh can still raise wifi as a backstop.
if [ -e /script/ncm_only ]; then
	echo "[start_bluetooth_wifi] ncm_only set -> WiFi AP suppressed"
	exit 0
fi
startprocess() {
    ProcNumber=`ps |grep -w "$1"|grep -v grep|wc -l`
    if [ "$ProcNumber" -le 0 ];then
        echo "[start_bluetooth_wifi] $1 start process";$2
        return 0
    else
    	echo "[start_bluetooth_wifi] $1 running"
    fi
    return 1
}

setBrandIp() {
    confPath="/etc/udhcpd.conf"
    brandIp=$1
    ip=${brandIp%.*}
	echo "[start_bluetooth_wifi] Set WLAN0 IP: $ip "
    ipCount=`grep -c "$ip.100" "$confPath" 2>/dev/null`
    if [ "${ipCount:-0}" -ne 0 ]; then
        echo "[start_bluetooth_wifi] Same IP, no need to reset"
        return 0
    else
        sed -i "s/192.168.*.100/${ip}.100/" $confPath
        sed -i "s/192.168.*.200/${ip}.200/" $confPath
        rm -f /var/lib/udhcpd.leases
    fi
}

#LOCK
LOCKFILE="/tmp/run_bluetooth_wifi_lock"
if [ -f "${LOCKFILE}" ]
  then
	echo "[start_bluetooth_wifi] run_bluetooth_wifi_lock, exit!"
    exit
  else
    touch "${LOCKFILE}"
fi

#wifi param
ssid="`cat /etc/wifi_name 2>/dev/null`"
passwd="`riddleBoxCfg -g WifiPassword`"

#config wifi channel
if [ -e /etc/wifi_use_24G ]; then
	riddleBoxCfg -s WiFiChannel 6
fi
wifi_channel=`riddleBoxCfg -g WiFiChannel`
case "$wifi_channel" in
	''|*[!0-9]*) wifi_channel=36 ;;
esac
freq=5180
if [ "$wifi_channel" -gt 15 ]; then
	freq=$((5000+wifi_channel*5))
else
	freq=$((2407+wifi_channel*5))
fi
echo "[start_bluetooth_wifi] config wifi channel: $wifi_channel, freq: $freq"
if [ "$wifi_channel" -ge 1 ] && [ "$wifi_channel" -le 14 ]; then
	echo "[start_bluetooth_wifi] 2.4G wifi"
	grep "^hw_mode=a" /etc/hostapd.conf && sed -i "s/^hw_mode=a/hw_mode=g/" /etc/hostapd.conf
elif [ "$wifi_channel" -ge 34 ] && [ "$wifi_channel" -le 165 ]; then
	echo "[start_bluetooth_wifi] 5G wifi"
	grep "^hw_mode=g" /etc/hostapd.conf && sed -i "s/^hw_mode=g/hw_mode=a/" /etc/hostapd.conf
else
	echo "[start_bluetooth_wifi] Default wifi channel 36"
	wifi_channel=36
	grep "^hw_mode=g" /etc/hostapd.conf && sed -i "s/^hw_mode=g/hw_mode=a/" /etc/hostapd.conf
fi
grep "^channel=${wifi_channel}$" /etc/hostapd.conf || sed -i "s/^channel=.*/channel=${wifi_channel}/" /etc/hostapd.conf
grep "^wpa_passphrase=${passwd}$" /etc/hostapd.conf || sed -i "s/^wpa_passphrase=.*/wpa_passphrase=${passwd}/" /etc/hostapd.conf

#check use ap or p2p, set p2p params
riddleBoxCfg -g WiFiP2PMode |grep 1 && mode=P2P || mode=AP
if [ $# -ge 1 ];then
	mode=$1
fi
if [ "$mode" = "P2P" ];then
	ssid="DIRECT-`cat /etc/wifi_name 2>/dev/null|sed 's/ //g'`"
fi
if [ $# -ge 2 ];then
	ssid=$2
fi
if [ $# -ge 3 ];then
	passwd=$3
fi
if [ $# -ge 4 ];then
	freq=$4
fi

#nxp wifi card only support STA+P2P, P2P interface not support AP
if [ -e /usr/sbin/wpa_supplicant ] && [ -e /tmp/moal.ko ] && [ "$mode" = "AP" ]; then
	echo "[start_bluetooth_wifi] Force change mode to P2P"
	mode=P2P
fi

curMode=AP
if [ -e /usr/sbin/wpa_cli ]; then
	wpa_cli -i wlan0 list_network |grep CURRENT && curMode=P2P
fi

#check mode changed
if [ "$mode" != "$curMode" ]; then
	echo "[start_bluetooth_wifi] Change WiFi mode from $curMode to $mode"
	rm -f "${LOCKFILE}"
	/script/close_bluetooth_wifi.sh
	touch "${LOCKFILE}"
fi

#start wifi
if [ "$mode" = "AP" ]; then
	test -e /tmp/bin/hostapd || cp /usr/sbin/hostapd /tmp/bin/hostapd
	startprocess hostapd 'hostapd /etc/hostapd.conf -B'
else
	echo "[start_bluetooth_wifi] Use P2P as AP"
	test -e /tmp/bin/wpa_cli || cp /usr/sbin/wpa_cli /tmp/bin/
	test -e /tmp/bcmdhd.ko && useVirtualDev=1 || useVirtualDev=0
	if [ "$useVirtualDev" -eq 1 ]; then
		wpa_cli -i wlan0 list_network || (iw dev wlan0 del;wpa_cli p2p_group_add "ssid=$ssid" "passphrase=$passwd" "freq=$freq")
	else
		wpa_cli -i wlan0 list_network |grep CURRENT || wpa_cli -i wlan0 p2p_group_add "ssid=$ssid" "passphrase=$passwd" "freq=$freq"
	fi
fi
rc=$?
if [ "$rc" = 0 ];then
echo opened >/tmp/wifi_status
fi

WLANIP=192.168.50.2
test -e /usr/sbin/ARMHiCar && WLANIP=192.168.43.1
#test -e /etc/box_ip && WLANIP=`cat /etc/box_ip`
BoxIp="`riddleBoxCfg -g BoxIp`"
if [ -n "$BoxIp" ]; then
	WLANIP=$BoxIp
fi
setBrandIp "$WLANIP"

echo 1 >/proc/sys/net/ipv6/conf/wlan0/disable_ipv6
ifconfig wlan0 "$WLANIP" netmask 255.255.255.0 mtu 1500 up
echo "[start_bluetooth_wifi] wlan0 addr=$(cat /sys/class/net/wlan0/address 2>/dev/null) ip set"

#ensure start uhhcpd
startprocess udhcpd 'udhcpd'

#ensure start mdnsd
#startprocess mdnsd 'mdnsd'

#UNLOCK
if [ -f "${LOCKFILE}" ]
  then
    rm -rf "${LOCKFILE}"
fi

#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    mount-SK.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################
if [ -e /sys/class/net/ncm0 ]; then
	if [ -e /sys/class/net/wlan0/address ]; then
		ifconfig ncm0 hw ether "$(cat /sys/class/net/wlan0/address | sed 's/00:e0:4c/c2:8e:30/')"
		echo "[start_ncm] ncm0 MAC=$(cat /sys/class/net/ncm0/address 2>/dev/null)"
	fi
	ifconfig ncm0 mtu 1500 up
	echo "[start_ncm] ncm0 up mtu1500"
fi
#ifconfig ncm0 192.168.50.2 netmask 255.255.255.0 mtu 1500 up
#udhcpd
#ipv6
#ifconfig ncm0 add 2001:db8:1111:2::1000/64
#dhcp6s ncm0

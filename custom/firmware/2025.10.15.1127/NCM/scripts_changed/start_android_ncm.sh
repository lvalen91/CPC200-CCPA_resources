#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    mount-SK.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################
killall adbd
killall mtp-server

echo 0 > /sys/class/android_usb_accessory/android0/enable
# HUAWEI ncm feature, some car use it
echo 239 > /sys/class/android_usb_accessory/android0/bDeviceClass
echo 2 > /sys/class/android_usb_accessory/android0/bDeviceSubClass
echo 1 > /sys/class/android_usb_accessory/android0/bDeviceProtocol
echo ncm > /sys/class/android_usb_accessory/android0/functions
echo 1 > /sys/class/android_usb_accessory/android0/enable
# read back the gadget state so a failed ncm bring-up is no longer silent
echo "[start_android_ncm] external gadget=ncm state=$(cat /sys/class/android_usb_accessory/android0/state 2>/dev/null)"

# hicar ip should be 192.168.66.x
if [ -e /sys/class/net/ncm1 ]; then
	ifconfig ncm1 192.168.66.2 netmask 255.255.255.0 mtu 1500 up
	echo "[start_android_ncm] ncm1 IP 192.168.66.2 up mtu1500"
fi

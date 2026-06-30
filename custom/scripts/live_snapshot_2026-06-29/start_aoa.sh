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

useZLP=$(riddleBoxCfg -g USBTransMode)
if [ -n "$useZLP" ] && [ "$useZLP" -eq 1 ]; then
	echo "[start_aoa] Open ZLP Mode"
	echo 1 > /sys/module/g_android_accessory/parameters/accZLP
fi

echo 0 > /sys/class/android_usb_accessory/android0/enable
#echo "Magic Communication Tec." > /sys/class/android_usb_accessory/android0/iManufacturer
#echo "Auto Box" > /sys/class/android_usb_accessory/android0/iProduct
echo 18d1 > /sys/class/android_usb_accessory/android0/idVendor
echo 2d00 > /sys/class/android_usb_accessory/android0/idProduct
echo accessory > /sys/class/android_usb_accessory/android0/functions
echo 1 > /sys/class/android_usb_accessory/android0/enable
# read back the gadget state so a failed AOA bring-up is no longer silent
echo "[start_aoa] AOA enabled VID=18d1 PID=2d00 state=$(cat /sys/class/android_usb_accessory/android0/state 2>/dev/null)"

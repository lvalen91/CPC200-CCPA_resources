#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    mount-SK.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################
echo 0 > /sys/class/android_usb/android0/enable
echo 239 > /sys/class/android_usb/android0/bDeviceClass
echo 2 > /sys/class/android_usb/android0/bDeviceSubClass
echo 1 > /sys/class/android_usb/android0/bDeviceProtocol
echo "Magic Communication Tec." > /sys/class/android_usb/android0/iManufacturer
echo "Auto Box" > /sys/class/android_usb/android0/iProduct
echo 08e4 > /sys/class/android_usb/android0/idVendor
echo 01c0 > /sys/class/android_usb/android0/idProduct
#echo accessory > /sys/class/android_usb/android0/functions
echo iap2,ncm > /sys/class/android_usb/android0/functions
echo 1 > /sys/class/android_usb/android0/enable
# read back the gadget state so a failed iap2,ncm bring-up is no longer silent
echo "[start_iap2_ncm] phone-side gadget=iap2,ncm VID=08e4 PID=01c0 state=$(cat /sys/class/android_usb/android0/state 2>/dev/null)"

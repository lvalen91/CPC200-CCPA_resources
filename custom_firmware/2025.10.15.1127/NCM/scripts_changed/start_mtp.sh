#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# brief
# author  Li Jian
# version 1.0.0
# date    2020Dec21
########################
df -h | grep /data/local/tmp || (mkdir -p /data/local/tmp && mount -t tmpfs -o size=2m tmpfs /data/local/tmp)
killall adbd
killall mtp-server
adbd&

mode=mtp,adb
setMode=$(riddleBoxCfg -g USBConnectedMode)
case $setMode in
	0)
		mode=mtp,adb
		;;
	1)
		mode=mtp
		;;
	2)
		mode=adb
		;;
esac
boxName=$(riddleBoxCfg -g CustomBoxName)
idVendor=$(riddleBoxCfg -g USBVID)
idProduct=$(riddleBoxCfg -g USBPID)
echo "[start_mtp] mtp device mode: $mode, name: $boxName"

lsmod | grep storage_common || insmod /tmp/storage_common.ko
lsmod | grep g_android_accessory || insmod /tmp/g_android_accessory.ko
echo 0 > /sys/class/android_usb_accessory/android0/enable
echo 0 > /sys/class/android_usb_accessory/android0/bDeviceClass
echo 0 > /sys/class/android_usb_accessory/android0/bDeviceSubClass
echo 0 > /sys/class/android_usb_accessory/android0/bDeviceProtocol
test -e /etc/device_serial && head -c 16 /etc/device_serial > /sys/class/android_usb_accessory/android0/iSerial
#echo 12d1 > /sys/class/android_usb_accessory/android0/idVendor  #huawei
#echo 0001 > /sys/class/android_usb_accessory/android0/idProduct
#echo 04e8 > /sys/class/android_usb_accessory/android0/idVendor  #samsung
#echo 6860 > /sys/class/android_usb_accessory/android0/idProduct
if [ -n "$idVendor" ]; then
	echo -n "$idVendor" > /sys/class/android_usb_accessory/android0/idVendor
else
	echo 12d1 > /sys/class/android_usb_accessory/android0/idVendor
fi
if [ -n "$idProduct" ]; then
	echo -n "$idProduct" > /sys/class/android_usb_accessory/android0/idProduct
else
	echo 0001 > /sys/class/android_usb_accessory/android0/idProduct
fi
if [ -n "$boxName" ]; then
	echo -n "$boxName" > /sys/class/android_usb_accessory/android0/iManufacturer
	echo -n "$boxName" > /sys/class/android_usb_accessory/android0/iProduct
fi

echo "$mode" > /sys/class/android_usb_accessory/android0/functions
echo 1 > /sys/class/android_usb_accessory/android0/enable
# read back the gadget state so a failed mtp bring-up is no longer silent
echo "[start_mtp] mtp enabled state=$(cat /sys/class/android_usb_accessory/android0/state 2>/dev/null)"

mtp-server&
sleep 0.1

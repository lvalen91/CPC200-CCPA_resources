#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    start_accessory_mass_storage.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################
if [ ! -e /tmp/ram_fat32.img ]; then
	echo 0 > /sys/class/android_usb_accessory/android0/enable

	echo "[start_accessory_mass_storage] creating 8MB RAM fat32 image at /tmp/ram_fat32.img"
	dd if=/dev/zero of=/tmp/ram_fat32.img bs=8M count=1
	mkfs.fat -s 128 -n APK /tmp/ram_fat32.img
	losetup /dev/loop1 /tmp/ram_fat32.img
	mkdir -p /tmp/UPAN
	echo "[start_accessory_mass_storage] mounting BoxHelper.apk image (/dev/loop1) -> /tmp/UPAN"
	mount /dev/loop1 /tmp/UPAN -t vfat -o utf8=1
	cp /etc/BoxHelper.apk /tmp/UPAN/; sync
	umount /tmp/UPAN
	echo 3 > /proc/sys/vm/drop_caches

	usb_dev_path=/dev/loop1
	echo "$usb_dev_path" > /sys/devices/soc0/soc.0/2100000.aips-bus/2184200.usb/ci_hdrc.1/gadget/lun0/file
	echo "$usb_dev_path" > /sys/devices/soc0/soc.1/2100000.aips-bus/2184200.usb/ci_hdrc.1/gadget/lun0/file
	echo 1 > /sys/class/android_usb_accessory/f_mass_storage/inquiry_string
	#test -e /etc/device_serial && cat /etc/device_serial > /sys/class/android_usb_accessory/android0/iSerial
	echo "[start_accessory_mass_storage] enabling accessory,mass_storage gadget"
	echo accessory,mass_storage > /sys/class/android_usb_accessory/android0/functions
	sleep 1
	echo 1 > /sys/class/android_usb_accessory/android0/enable
	echo "[start_accessory_mass_storage] gadget state: functions=$(cat /sys/class/android_usb_accessory/android0/functions) enable=$(cat /sys/class/android_usb_accessory/android0/enable)"
else
	echo "[start_accessory_mass_storage] Already in udisk mode, do nothing"
fi

exit 0

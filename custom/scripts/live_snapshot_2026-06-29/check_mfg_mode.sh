#!/bin/sh
########################
# Copyright(c) 2014-2024 DongGuan HeWei Communication Technologies Co. Ltd.
# file    check_mfg_mode.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    263月24
########################

mfgFile=/sys/module/libcomposite/parameters/mfgmode
test -e "$mfgFile" || exit 0
while true
do
	mfgMode=$(cat "$mfgFile" 2>/dev/null)
	if [ "$mfgMode" = 1 ]; then
		echo "[check_mfg_mode] Enter MFG Test Mode"
		touch /tmp/.AutomaticTestMode;touch /tmp/.AutoPlayResetAOA
		killall ARMadb-driver;killall colorLightDaemon
		killall fakeiOSDevice;killall fakeCarLifeDevice;killall fakeAADevice
		lsmod |grep g_iphone && (rmmod g_iphone;rmmod f_ptp;rmmod cdc_ncm;echo 0 > /sys/bus/platform/devices/ci_hdrc.1/inputs/b_bus_req)
		echo 0 > /sys/class/android_usb_accessory/android0/enable
		AutomaticTest  2>&1 | tee -a /tmp/AutoTest.log
	elif [ "$mfgMode" = 2 ]; then
		echo "[check_mfg_mode] Enter MFG Burn Mode"
		echo "[check_mfg_mode] BURN MODE requested: erasing /dev/mtd0 block0 then reboot"
		flash_erase /dev/mtd0 0 1 && reboot
	fi
	sleep 2
done

#!/bin/sh
########################
# Copyright(c) 2014-2020 DongGuan HeWei Communication Technologies Co. Ltd.
# file    init_bluetooth_wifi.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    28 920
########################

power_led_on() {
	if [ ! -e /sys/class/gpio/gpio2/value ]; then
		sync
		echo 2 > /sys/class/gpio/export;
		echo out > /sys/class/gpio/gpio2/direction;
		echo 0 >/sys/class/gpio/gpio2/value;
		echo "[init_bluetooth_wifi] Power Led On"
	fi
}

sdioCardID=`cat /sys/bus/sdio/devices/mmc0:0001:1/device 2>/dev/null`
echo "[init_bluetooth_wifi] BT WIFI Card Device ID: $sdioCardID"

test -e /sys/bus/sdio/devices/mmc0:0001:1/device && /script/attach_bluetooth.sh &
# (riddle-free) bluetoothDaemon is started by attach_bluetooth.sh; UseUartBLE gate dropped

test -e /usr/sbin/wpa_supplicant && supportStaMode=1 || supportStaMode=0

if [ "$sdioCardID" = "0xb822" ] || [ "$sdioCardID" = "0xc822" ]; then
	echo "[init_bluetooth_wifi] chip $sdioCardID (Realtek RTL8822BS/CS), loading WiFi module 88x2bs.ko/88x2cs.ko"
	if [ "$sdioCardID" = "0xc822" ];then
		test -e /tmp/rtl8822cs_rootfs.tar.gz && mv /tmp/rtl8822cs_rootfs.tar.gz /tmp/rtl8822_rootfs.tar.gz
	fi
	if [ -e /tmp/rtl8822_rootfs.tar.gz ]; then
		tar -xvf /tmp/rtl8822_rootfs.tar.gz -C /
	fi
	#8822cs open power led before load bluetooth to avoid crash
	power_led_on
	tar -xvf /lib/firmware/rtlbt/rtl8822_ko.tar.gz -C /tmp
	#insmod Wi-Fi module Driver
	test -e /tmp/88x2bs.ko && { insmod /tmp/88x2bs.ko if2name=sta0 && echo "[init_bluetooth_wifi] insmod 88x2bs.ko ok" || echo "[init_bluetooth_wifi] insmod 88x2bs.ko FAILED"; }
	test -e /tmp/88x2cs.ko && { insmod /tmp/88x2cs.ko if2name=sta0 && echo "[init_bluetooth_wifi] insmod 88x2cs.ko ok" || echo "[init_bluetooth_wifi] insmod 88x2cs.ko FAILED"; }
	#ifconfig wlan0 up;sleep 0.1;ifconfig wlan0 down;sleep 0.1
	set_wifi_mac
elif [ "$sdioCardID" = "0xb733" ]; then
	echo "[init_bluetooth_wifi] chip $sdioCardID (Realtek RTL8733BS), loading WiFi module 8733bs.ko"
	if [ -e /tmp/rtl8733_rootfs.tar.gz ]; then
		tar -xvf /tmp/rtl8733_rootfs.tar.gz -C /
	fi

	tar -xvf /lib/firmware/rtlbt/rtl8733_ko.tar.gz -C /tmp
	#insmod Wi-Fi module Driver
	test -e /tmp/8733bs.ko && { insmod /tmp/8733bs.ko if2name=sta0 rtw_channel_plan=0x76 && echo "[init_bluetooth_wifi] insmod 8733bs.ko ok" || echo "[init_bluetooth_wifi] insmod 8733bs.ko FAILED"; }
	ifconfig wlan0 up;sleep 0.1;ifconfig wlan0 down
	sleep 0.1;set_wifi_mac
elif [ "$sdioCardID" = "0x4354" ] || [ "$sdioCardID" = "0x4335" ]; then
	echo "[init_bluetooth_wifi] chip $sdioCardID (Broadcom BCM4354/4335), loading WiFi module bcmdhd.ko"
	bcmBTFirmware=bcm4350.hcd
	bcmWiFiFirmware=fw_bcm4354a1_ag_apsta.bin
	bcmWiFiConfig=nvram_bcm4354_m.txt
	if [ -e /tmp/bcm4354_rootfs.tar.gz ]; then
		tar -xvf /tmp/bcm4354_rootfs.tar.gz -C /
		if [ "$sdioCardID" = "0x4335" ]; then
			mv /lib/firmware/bcm/4335/* /lib/firmware/bcm/
		fi
		rm -rf /lib/firmware/bcm/4335
	fi
	tar -xvf /lib/firmware/bcm/bcm4354_ko.tar.gz -C /tmp
	#insmod Wi-Fi module Driver
	if [ "$supportStaMode" -eq 1 ]; then
		test -e /tmp/bcmdhd.ko && { insmod /tmp/bcmdhd.ko "firmware_path=/lib/firmware/bcm/$bcmWiFiFirmware" "nvram_path=/lib/firmware/bcm/$bcmWiFiConfig" iface_name=sta op_mode=5 && echo "[init_bluetooth_wifi] insmod bcmdhd.ko ok" || echo "[init_bluetooth_wifi] insmod bcmdhd.ko FAILED"; }
		wl vhtmode 0 # close 11ac
		ifconfig sta0 up;sleep 0.1;set_wifi_mac sta0
	else
		test -e /tmp/bcmdhd.ko && { insmod /tmp/bcmdhd.ko "firmware_path=/lib/firmware/bcm/$bcmWiFiFirmware" "nvram_path=/lib/firmware/bcm/$bcmWiFiConfig" && echo "[init_bluetooth_wifi] insmod bcmdhd.ko ok" || echo "[init_bluetooth_wifi] insmod bcmdhd.ko FAILED"; }
		wl vhtmode 0 # close 11ac
		ifconfig wlan0 up;sleep 0.1;set_wifi_mac
	fi
elif [ "$sdioCardID" = "0x4358" ] || [ "$sdioCardID" = "0xaa31" ]; then
	echo "[init_bluetooth_wifi] chip $sdioCardID (Broadcom BCM4358), loading WiFi module bcmdhd.ko"
	bcmWiFiFirmware=fw_bcm4358_ag_apsta.bin
	bcmWiFiConfig=nvram_4358.txt
	if [ -e /tmp/bcm4358_rootfs.tar.gz ]; then
		tar -xvf /tmp/bcm4358_rootfs.tar.gz -C /
	fi
	if [ -e /lib/firmware/bcm/4358_ant_num ]; then
		cat /lib/firmware/bcm/4358_ant_num |grep 1 && bcmWiFiConfig=nvram_4358_1_ant.txt
	fi
	echo "[init_bluetooth_wifi] 4358 nvram path: $bcmWiFiConfig"
	tar -xvf /lib/firmware/bcm/bcm4358_ko.tar.gz -C /tmp
	#insmod Wi-Fi module Driver
	if [ "$supportStaMode" -eq 1 ]; then
		test -e /tmp/bcmdhd.ko && { insmod /tmp/bcmdhd.ko "firmware_path=/lib/firmware/bcm/$bcmWiFiFirmware" "nvram_path=/lib/firmware/bcm/$bcmWiFiConfig" iface_name=sta op_mode=5 && echo "[init_bluetooth_wifi] insmod bcmdhd.ko ok" || echo "[init_bluetooth_wifi] insmod bcmdhd.ko FAILED"; }
		wl vhtmode 0 # close 11ac
		ifconfig sta0 up;sleep 0.1;set_wifi_mac sta0
	else
		test -e /tmp/bcmdhd.ko && { insmod /tmp/bcmdhd.ko "firmware_path=/lib/firmware/bcm/$bcmWiFiFirmware" "nvram_path=/lib/firmware/bcm/$bcmWiFiConfig" && echo "[init_bluetooth_wifi] insmod bcmdhd.ko ok" || echo "[init_bluetooth_wifi] insmod bcmdhd.ko FAILED"; }
		wl vhtmode 0 # close 11ac
		ifconfig wlan0 up;sleep 0.1;set_wifi_mac
	fi
elif [ "$sdioCardID" = "0x9149" ] || [ "$sdioCardID" = "0x9141" ]; then
	echo "[init_bluetooth_wifi] chip $sdioCardID (NXP SD8987), loading WiFi modules mlan.ko/moal.ko"
	nxpWiFiConfig=nxp/wifi_mod_para.conf
	if [ "$supportStaMode" -eq 1 ]; then
		nxpWiFiConfig=nxp/wifi_mod_para_apsta.conf
	fi
	if [ -e /tmp/sd8987_rootfs.tar.gz ]; then
		tar -xvf /tmp/sd8987_rootfs.tar.gz -C /
	fi
	tar -xvf /lib/firmware/nxp/sd8987_ko.tar.gz -C /tmp
	#insmod Wi-Fi module Driver
	test -e /tmp/mlan.ko && { insmod /tmp/mlan.ko && echo "[init_bluetooth_wifi] insmod mlan.ko ok" || echo "[init_bluetooth_wifi] insmod mlan.ko FAILED"; }
	test -e /tmp/moal.ko && { insmod /tmp/moal.ko "mod_para=$nxpWiFiConfig" && echo "[init_bluetooth_wifi] insmod moal.ko ok" || echo "[init_bluetooth_wifi] insmod moal.ko FAILED"; }
	#test -e /tmp/moal.ko && insmod /tmp/moal.ko fw_name=nxp/sdiouart8987_combo_v0.bin drv_mode=2 cal_data_cfg=none uap_name=wlan cfg80211_wext=0xf ps_mode=2 auto_ds=2
	set_wifi_mac
	if [ "$supportStaMode" -eq 0 ]; then
		#tx power is low when first start AP
		(sleep 4;hostapd /etc/hostapd.conf -B;sleep 0.2;killall -q hostapd;sleep 3;/script/start_bluetooth_wifi.sh;dmesg |grep "woal_request_fw failed" && reboot)&
	fi
elif [ "$sdioCardID" = "0x9159" ]; then
	echo "[init_bluetooth_wifi] chip $sdioCardID (NXP IW416), loading WiFi modules mlan.ko/moal.ko"
	nxpWiFiConfig=nxp/wifi_mod_para.conf
	if [ "$supportStaMode" -eq 1 ]; then
		nxpWiFiConfig=nxp/wifi_mod_para_p2psta.conf
	fi
	if [ -e /tmp/iw416_rootfs.tar.gz ]; then
		tar -xvf /tmp/iw416_rootfs.tar.gz -C /
	fi
	tar -xvf /lib/firmware/nxp/iw416_ko.tar.gz -C /tmp
	#insmod Wi-Fi module Driver
	test -e /tmp/mlan.ko && { insmod /tmp/mlan.ko && echo "[init_bluetooth_wifi] insmod mlan.ko ok" || echo "[init_bluetooth_wifi] insmod mlan.ko FAILED"; }
	test -e /tmp/moal.ko && { insmod /tmp/moal.ko "mod_para=$nxpWiFiConfig" && echo "[init_bluetooth_wifi] insmod moal.ko ok" || echo "[init_bluetooth_wifi] insmod moal.ko FAILED"; }
	set_wifi_mac
else
	echo "[init_bluetooth_wifi] unknown SDIO card ID: $sdioCardID"
fi

power_led_on

if [ "$supportStaMode" -eq 1 ]; then
	#rm -f /var/run/wpa_supplicant/*
	test -e /tmp/bcmdhd.ko && useVirtualDev=1 || useVirtualDev=0
	cp /usr/sbin/wpa_supplicant /tmp/bin/
	echo 1 >/proc/sys/net/ipv6/conf/sta0/disable_ipv6
	if [ "$useVirtualDev" -eq 1 ]; then
		wpa_supplicant -D nl80211 -i sta0 -c /etc/wpa_supplicant.conf -B
		lsmod |grep bcmdhd && iw dev sta0 interface add wlan0 type managed
	else
		wpa_supplicant -D nl80211 -i wlan0 -c /etc/p2p_supplicant.conf -N -i sta0 -D nl80211 -c /etc/wpa_supplicant.conf -B
	fi
	test -e /script/start_adb_debug_service.sh && /script/start_adb_debug_service.sh
fi

#force set custom bt or wifi name (riddle-free: name files are the source of truth)
test -e /etc/.custom_bluetooth_name && cp /etc/.custom_bluetooth_name /etc/bluetooth_name
test -e /etc/.custom_wifi_name && cp /etc/.custom_wifi_name /etc/wifi_name
test -e /script/get_best_wifi_channel.sh && /script/get_best_wifi_channel.sh

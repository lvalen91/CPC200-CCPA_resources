#!/bin/sh
########################
# Copyright(c) 2014-2020 DongGuan HeWei Communication Technologies Co. Ltd.
# file    attach_bluetooth.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    28 920
########################

attach_bluetooth() {
	echo "[attach_bluetooth] Start load Bluetooth"
	sdioCardID=`cat /sys/bus/sdio/devices/mmc0:0001:1/device 2>/dev/null`
	if [ "$sdioCardID" = "0xb822" ] || [ "$sdioCardID" = "0xc822" ] || [ "$sdioCardID" = "0xb733" ]; then
		#8822CS需要判断WiFi加载成功才加载蓝牙，否则启动wifi可能会失败
		if [ "$sdioCardID" = "0xc822" ]; then
			i=0
			while [ ! -e /sys/class/net/wlan0/address ]; do
				i=$((i+1))
				if [ "$i" -gt 120 ]; then
					echo "[attach_bluetooth] timeout waiting for wlan0 address (0xc822), continuing"
					break
				fi
				echo "[attach_bluetooth] Wait WiFi init finish..."
				sleep 0.1
			done
		fi
		#attach bluetooth module
		test -e /tmp/rtk_hci_uart.ko && insmod /tmp/rtk_hci_uart.ko
		if [ -e /usr/sbin/rtk_hciattach ]; then
			echo "[attach_bluetooth] invoking rtk_hciattach -s 115200 ttymxc2 rtk_h5"
			rtk_hciattach -s 115200 ttymxc2 rtk_h5
			# improve hfp voice quality
			hciconfig hci0 scomtu 240:32
		fi
	elif [ "$sdioCardID" = "0x4354" ] || [ "$sdioCardID" = "0x4335" ]; then
		bcmBTFirmware=bcm4350.hcd
		#attach bluetooth module
		test -e /tmp/hci_uart.ko && insmod /tmp/hci_uart.ko
		if [ -e /usr/sbin/brcm_patchram_plus ]; then
			bcmBTMac=`set_wifi_mac |sed "s/Setting Wi-Fi MAC address: 00:E0:4C/38:BA:B0/"`
			brcm_patchram_plus --patchram /lib/firmware/bcm/$bcmBTFirmware --baudrate 1000000 --use_baudrate_for_download --no2bytes --tosleep 200000 --bd_addr "$bcmBTMac" /dev/ttymxc2 --enable_hci &
			#wait brcm_patchram_plus finish, overtime 12 secoond
			sleep 6;hciconfig hci0 || (sleep 3;hciconfig hci0 || sleep 3)
		fi
	elif [ "$sdioCardID" = "0x4358" ] || [ "$sdioCardID" = "0xaa31" ]; then
		bcmBTFirmware=BCM4358A3.hcd
		test -e /tmp/hci_uart.ko && insmod /tmp/hci_uart.ko
		if [ -e /usr/sbin/brcm_patchram_plus ]; then
			bcmBTMac=`set_wifi_mac |sed "s/Setting Wi-Fi MAC address: 00:E0:4C/38:BA:B0/"`
			brcm_patchram_plus --patchram /lib/firmware/bcm/$bcmBTFirmware --baudrate 3000000 --use_baudrate_for_download --no2bytes --tosleep 200000 --bd_addr "$bcmBTMac" /dev/ttymxc2 --enable_hci &
			#wait brcm_patchram_plus finish, overtime 10 secoond
			sleep 4;hciconfig hci0 || (sleep 3;hciconfig hci0 || sleep 3)
			hciconfig hci0 up
			# improve hfp voice quality
			hciconfig hci0 scomtu 240:32
			# route sco data to hci
			hcitool -i hci0 cmd 0x3f 0x1c 0x01 0x02 0x00 0x00 0x00
		fi
	elif [ "$sdioCardID" = "0x9149" ] || [ "$sdioCardID" = "0x9141" ]; then
		#8987需要判断WiFi加载成功才加载蓝牙，否则会卡死
		i=0
		while [ ! -e /sys/class/net/wlan0/address ]; do
			i=$((i+1))
			if [ "$i" -gt 120 ]; then
				echo "[attach_bluetooth] timeout waiting for wlan0 address (8987), continuing"
				break
			fi
			echo "[attach_bluetooth] Wait WiFi init finish..."
			sleep 0.1
		done
		if [ -e /sys/class/net/wlan0/address ]; then
			#attach bluetooth module
			test -e /tmp/hci_uart.ko && insmod /tmp/hci_uart.ko
			if [ -e /usr/sbin/hciattach ]; then
				#hciattach /dev/ttymxc2 any 115200 flow
				#hciconfig hci0 up
				#hcitool cmd 0x3f 0x0009 0xc0 0xc6 0x2d 0x00
				#killall hciattach;sleep 2;rmmod hci_uart
				#lsmod |grep hci_uart && (sleep 2;rmmod hci_uart)
				#insmod /tmp/hci_uart.ko
				echo "[attach_bluetooth] invoking hciattach /dev/ttymxc2 any 3000000 flow (8987)"
				hciattach /dev/ttymxc2 any 3000000 flow
				hciconfig hci0 up
				hciconfig hci0 reset
				# improve hfp voice quality
				hciconfig hci0 scomtu 240:32
				# route sco data to hci
				hcitool -i hci0 cmd 0x3f 0x1d 0x00
			fi
		fi
	elif [ "$sdioCardID" = "0x9159" ]; then
		#attach bluetooth module
		test -e /tmp/hci_uart.ko && insmod /tmp/hci_uart.ko
		fw_loader_linux /dev/ttymxc2 115200 1 /lib/firmware/nxp/uartiw416_bt_v0.bin 3000000
		if [ -e /usr/sbin/hciattach ]; then
			echo "[attach_bluetooth] invoking hciattach /dev/ttymxc2 any 3000000 flow (iw416)"
			hciattach /dev/ttymxc2 any 3000000 flow
			hciconfig hci0 up
			cat /sys/class/bluetooth/hci0/address |grep "38:ba:b0" && configBurned=1 || configBurned=0
			if [ "$configBurned" -eq 0 ]; then
				echo "[attach_bluetooth] Set BT MAC for iw416"
				nxpBTMac=`set_wifi_mac |sed "s/Setting Wi-Fi MAC address: 00:E0:4C/38:BA:B0/"`
				BTMac=`echo "$nxpBTMac" |awk -F: '{print $6, $5, $4, $3, $2, $1}'`
				hcitool -i hci0 cmd 3f 61 00 01 02 1c 37 e0 1c 00 ff ff ff ff 01 8f 08 04 08 00 00 00 c0 c6 2d 00 $BTMac f0 00
				hciconfig hci0 reset
			fi
			# improve hfp voice quality
			hciconfig hci0 scomtu 240:32
			# route sco data to hci
			hcitool -i hci0 cmd 0x3f 0x1d 0x00
			# set ble power
			hcitool -i hci0 cmd 0x3F 0x00EE 0x01 0x02
			hcitool -i hci0 cmd 0x03 0x0003
			echo "[attach_bluetooth] Set ble power: 0x02"
		fi
	else
		echo "[attach_bluetooth] unknown SDIO card ID: $sdioCardID"
	fi
	echo "[attach_bluetooth] End load Bluetooth"
}

reset_bluetooth() {
	echo "[attach_bluetooth] Reset Bluetooth"
	test -e /usr/sbin/rtk_hciattach && killall rtk_hciattach
	test -e /usr/sbin/brcm_patchram_plus && killall brcm_patchram_plus
	test -e /usr/sbin/hciattach && killall hciattach
	lsmod |grep rtk_hci_uart && (sleep 2;rmmod rtk_hci_uart)
	lsmod |grep hci_uart && (sleep 2;rmmod hci_uart)
	echo 1 >/sys/class/gpio/gpio1/value;
	sleep 0.1
	echo 0 >/sys/class/gpio/gpio1/value;
}

cp /usr/sbin/bluetoothDaemon /tmp/bin/
bluetoothDaemon -n &

i=0
while ! ls /tmp/*hci_uart.ko >/dev/null 2>&1; do
	i=$((i+1))
	if [ "$i" -gt 120 ]; then
		echo "[attach_bluetooth] timeout waiting for BT driver decompress, continuing"
		break
	fi
	echo "[attach_bluetooth] Wait Bluetooth driver decompress..."
	sleep 0.1
done

attach_bluetooth
hciconfig hci0
rc=$?
tries=0
while [ "$rc" -ne 0 ]; do
	tries=$((tries+1))
	if [ "$tries" -gt 60 ]; then
		echo "[attach_bluetooth] hci0 still not up after $tries attempts, giving up"
		break
	fi
	reset_bluetooth
	attach_bluetooth
	hciconfig hci0
	rc=$?
done
echo "[attach_bluetooth] Attach Bluetooth success"
echo "[attach_bluetooth] hci0 up: $(cat /sys/class/bluetooth/hci0/address 2>/dev/null)"

touch /tmp/.hciattach_done

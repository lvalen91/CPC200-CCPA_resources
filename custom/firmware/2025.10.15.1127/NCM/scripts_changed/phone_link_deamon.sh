#!/bin/sh
########################
# Copyright(c) 2014-2022 DongGuan HeWei Communication Technologies Co. Ltd.
# file    phone_link_deamon.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    1111月22
########################

Usage() {
	echo "[phone_link_deamon] Usage: $0 CarPlay/AndroidAuto/HiCar/ICCOA/CarLife start/stop"
	exit 1
}

if [ $# -ne 2 ]; then
	Usage
fi

linktype=$1
action=$2

CheckPhoneLinkFile() {
	case $linktype in
		CarPlay)
			test -e /usr/sbin/AppleCarPlay  || exit 1
			;;
		AndroidAuto)
			test -e /usr/sbin/ARMAndroidAuto || exit 1
			;;
		HiCar)
			test -e /usr/sbin/ARMHiCar || exit 1
			;;
		ICCOA)
			test -e /usr/sbin/iccoa || exit 1
			;;
		CarLife)
			test -e /usr/sbin/CarLife || exit 1
			;;
	esac
}

CopyPhoneLinkFile() {
	tmpLibPath=/tmp/lib/
	tmpBinPath=/tmp/bin/
	case $linktype in
		CarPlay)
			test -e "$tmpBinPath/AppleCarPlay"  || (\
				cp /usr/sbin/AppleCarPlay "$tmpBinPath";\
				cp /usr/sbin/ARMiPhoneIAP2 "$tmpBinPath";\
				)
			;;
		AndroidAuto)
			test -e "$tmpBinPath/ARMAndroidAuto" || (\
				cp /usr/sbin/ARMAndroidAuto "$tmpBinPath";\
				cp /usr/sbin/hfpd "$tmpBinPath";\
				cp -d /usr/lib/libssl.so* "$tmpLibPath";\
				)
			;;
		HiCar)
			test -e "$tmpBinPath/ARMHiCar" || (\
				cp /usr/sbin/ARMHiCar "$tmpBinPath";\
				cp /usr/lib/libdmsdp* "$tmpLibPath";\
				cp /usr/lib/libHisightSink.so "$tmpLibPath";\
				cp /usr/lib/libHwDeviceAuthSDK.so "$tmpLibPath";\
				cp /usr/lib/libHwKeystoreSDK.so "$tmpLibPath";\
				cp /usr/lib/libmanagement.so "$tmpLibPath";\
				cp /usr/lib/libsecurec.so "$tmpLibPath";\
				cp /usr/lib/libauthagent.so "$tmpLibPath";\
				cp /usr/lib/libnearby.so "$tmpLibPath";\
				cp /usr/lib/libhicar.so "$tmpLibPath"\
				)
			;;
		ICCOA)
			test -e "$tmpBinPath/iccoa" || (\
				cp /usr/sbin/iccoa "$tmpBinPath";\
				cp -d /usr/lib/libcarlink.so "$tmpLibPath";\
				)
			;;
		CarLife)
			test -e "$tmpBinPath/CarLife" || (\
				cp /usr/sbin/CarLife "$tmpBinPath";\
				)
			;;
	esac
	sync
}

RunLinkProcess() {
	case $linktype in
		CarPlay)
			ARMiPhoneIAP2
			;;
		AndroidAuto)
			if [ -e /tmp/.bluetoothDaemon_init_done ]; then
				ps | grep -v grep | grep hfpd || hfpd -y -E -f &
			fi
			ARMAndroidAuto
			;;
		HiCar)
			ARMHiCar
			;;
		ICCOA)
			iccoa
			;;
		CarLife)
			CarLife
			;;
	esac
}

EndLinkProcess() {
	case $linktype in
		CarPlay)
			killall ARMiPhoneIAP2
			killall AppleCarPlay
			;;
		AndroidAuto)
			killall hfpd
			ps | grep -v grep | grep hfpd && sleep 1 # wait hfpd exited
			killall ARMAndroidAuto
			;;
		HiCar)
			killall ARMHiCar
			;;
		ICCOA)
			killall iccoa
			;;
		CarLife)
			killall CarLife
			;;
	esac
}


lockfile=/tmp/.${linktype}_daemon_started
exitfile=/tmp/.${linktype}_daemon_exited

# Iteration caps: hardening guards only. The values are far larger than any
# normal cross-process handshake needs, so the lock/exitfile protocol is
# unchanged for the normal case; they only stop a runaway infinite spin.
WAIT_EXIT_MAX=6000
RESTART_MAX=100000

WaitLinkDeamonExited() {
	_i=0
	while [ -e "$exitfile" ]
	do
		echo "[phone_link_deamon] Wait Link Daemon: ${linktype} Exit..."
		sleep 0.1
		EndLinkProcess
		_i=$((_i + 1))
		[ "$_i" -ge "$WAIT_EXIT_MAX" ] && break
	done
}

StartLinkDeamon() {
	CheckPhoneLinkFile
	# if now in exiting, stop exit
	test -e "$exitfile" && (rm -f "$exitfile";echo "[phone_link_deamon] Continue Run Link Daemon: $linktype")
	test -e "$lockfile" && exit 0
	touch "$lockfile"
	echo "[phone_link_deamon] Start Link Daemon: $linktype"
	# wait last StopLinkDeamon finish
	WaitLinkDeamonExited
	CopyPhoneLinkFile
	_n=0
	while [ -e "$lockfile" ]
	do
		if [ -e /sys/class/net/wlan0/address ] && [ ! -e /sys/class/bluetooth/hci0/address ]; then
			echo "[phone_link_deamon] Wait bt attached success when start phone link daemon"
		elif [ -e /tmp/update_status ] && [ "$(cat /tmp/update_status)" != '4' ]; then
			echo "[phone_link_deamon] Exit phone link daemon when update"
			rm -f "$lockfile"
			break
		else
			RunLinkProcess
		fi
		test -e "$exitfile" && break
		test -e "$lockfile" && sleep 1
		_n=$((_n + 1))
		[ "$_n" -ge "$RESTART_MAX" ] && break
	done
	echo "[phone_link_deamon] End Link Daemon: $linktype"
	rm -f "$exitfile"
	rm -f "$lockfile"
	exit 0
}

StopLinkDeamon() {
	if [ -e "$lockfile" ]; then
		echo "[phone_link_deamon] Stop Link Daemon: ${linktype}"
		touch "$exitfile"
		#rm -f $lockfile
		EndLinkProcess
		WaitLinkDeamonExited
	fi
	exit 0
}

RestartLinkDeamon() {
	if [ -e "$lockfile" ]; then
		echo "[phone_link_deamon] Restart Link Daemon: ${linktype}"
		EndLinkProcess
	fi
	exit 0
}

case $action in
	start)
		StartLinkDeamon
		;;
	stop)
		StopLinkDeamon
		;;
	restart)
		RestartLinkDeamon
		;;
	*)
		Usage
		;;
esac

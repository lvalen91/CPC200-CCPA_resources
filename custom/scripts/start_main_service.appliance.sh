#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    start_main_service.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################

runMainProcess() {
	processName=$1
	cp "/usr/sbin/$processName" /tmp/bin/

	if [ -e /tmp/UDiskPassThroughMode ]; then
		echo "[start_main_service] Not Start Main Process in UDiskPassThroughMode"
		return
	fi

	if [ -e /etc/log_com ]; then
		$processName 2>&1 | tee -a /tmp/userspace.log &
	elif [ -e /etc/log_file ]; then
		if [ "$ttylog" -eq 1 ]; then
			$processName &
		else
			$processName >> /tmp/userspace.log 2>&1 &
		fi
	else
		$processName >> /dev/null 2>&1 &
	fi
}

# ===== APPLIANCE GATE (additive) =====
# ncm_appliance: true when booting as a stripped NCM appliance (ncm_only or
# ncm_wifi). Used below to suppress the CarPlay/Android-Auto projection-adjacent
# daemons (mdnsd, boxNetworkService, boxHUDServer, colorLightDaemon) that are
# launched DIRECTLY here -- they bypass runMainProcess's UDiskPassThroughMode
# gate, so without this they run even after ARMadb is skipped. Reverting the
# flag (rm /script/ncm_only /script/ncm_wifi) restores full stock boot.
ncm_appliance() { [ -e /script/ncm_only ] || [ -e /script/ncm_wifi ]; }
# ===== end APPLIANCE GATE =====

#set date
date -s "2020-01-02 `date +%T`" &
#use /dev/urandom to avoid block call in openssl
rm -f /dev/random && ln -s /dev/urandom /dev/random &

#open kernel log timestamp
echo y > /sys/module/printk/parameters/time && echo 7 > /proc/sys/kernel/printk &

#run custom init shell
test -e /script/custom_init.sh && /script/custom_init.sh

#init gpio
/script/init_gpio.sh &

#copy bin and lib
if [ -e script/copy_to_tmp.sh ]; then
	/script/copy_to_tmp.sh
fi

cat /proc/cmdline | grep ttyLogFile && ttylog=1 || ttylog=0
if [ "$ttylog" -eq 1 ] && [ -e /etc/log_file ]; then
	rm -f /etc/log_com
	touch /tmp/ttyLog
	ln -s /tmp/ttyLog /tmp/userspace.log
fi

if [ -e /usr/sbin/riddleBoxCfg ]; then
	test -e /etc/riddle.conf || (echo "create riddle.conf from default config file";cp /etc/riddle_default.conf /etc/riddle.conf)
fi


# Must process tar file before LED Power ON
test -e /etc/boa/www/www.tar.gz && (mv /etc/boa/www/www.tar.gz /tmp/ && tar -xvf /tmp/www.tar.gz -C /etc/boa/www/)
#Start load Bluetooth related before main programs run
/script/init_bluetooth_wifi.sh
#Start load audio codec
/script/init_audio_codec.sh
#Check Auto Test Mode
/script/check_mfg_mode.sh &

if [ -e /usr/sbin/ARMadb-driver ]; then
	runMainProcess ARMadb-driver
fi


sleep 3

#Satrt led daemon
if ncm_appliance; then
	echo "[start_main_service] APPLIANCE: skip colorLightDaemon"
else
	test -e /usr/sbin/colorLightDaemon && colorLightDaemon &
fi

if ncm_appliance; then
	echo "[start_main_service] APPLIANCE: skip Carplay mdnsd"
else
	echo "[start_main_service] Start Carplay mdnsd"
	cp /usr/sbin/mdnsd /tmp/bin/
	mdnsd
fi

echo "[start_main_service] Start Carplay IAP2&NCM driver"
/script/start_iap2_ncm.sh

echo "[start_main_service] Start NCM network"
/script/start_ncm.sh

sleep 4
if ncm_appliance; then
	echo "[start_main_service] APPLIANCE: skip boxNetworkService"
else
	echo "[start_main_service] Start Box Network Service"
	boxNetworkService &
fi

echo "[start_main_service] Unzip boxImgTools"
unzip /usr/sbin/boxImgTools.zip -d /tmp/bin/ &

# delay start other service, make main service start quickly
sleep 6

if [ -e /usr/sbin/boa ]; then
	echo "[start_main_service] Web Server Service"
	cp /usr/sbin/boa /tmp/bin/
	#remove old version boa web, now new verson boa web support active
	test -e /etc/boa_old && rm -rf /etc/boa_old
	#copy cgi and www to tmp
	mkdir -p /tmp/boa; cp -r /etc/boa/www /tmp/boa/; cp -r /etc/boa/cgi-bin /tmp/boa/
	boa
	#auto start wifi after some time for ota upgrade (stock fallback). Skip it in NCM
	#modes: ncm_wifi -> custom_init.sh owns wifi; ncm_only -> wifi MUST stay off. This
	#removes a boot race where this line could win before custom_init's ncm udhcpd ran.
	if [ -e /script/ncm_only ] || [ -e /script/ncm_wifi ]; then :; else
		ps |grep udhcpd|grep -v grep || /script/start_bluetooth_wifi.sh
	fi
	#open boa web log when debug mode
	cat /proc/cmdline |grep ttymxc0 && (mkdir -p /tmp/boa/logs/ && ln -s /tmp/userspace.log /tmp/boa/logs/box.log)
fi

#Start boxHUDServer
if ncm_appliance; then
	echo "[start_main_service] APPLIANCE: skip boxHUDServer"
else
	test -e /usr/sbin/boxHUDServer && boxHUDServer &
fi

echo "[start_main_service] Save Log to UPAN"
test -e /script/check_udisk_log.sh && /script/check_udisk_log.sh &


echo 3 > /proc/sys/vm/drop_caches

# hwSecret&

if ncm_appliance; then
	echo "[start_main_service] APPLIANCE: skip cpu_UsageRate (riddle_top logger)"
else
	/script/cpu_UsageRate.sh &
fi
#check log size
/script/check_log_size.sh &

# ===== NCMONLY: persistent CDC-NCM USB-SSH at boot (additive; WiFi kept) =====
# Toggle: arms NCM-only iff /script/ncm_only exists; else boots stock CarPlay/AA.
# Additive (touches no existing line). UDiskPassThroughMode guard makes ARMadb's
# start_accessory.sh a no-op during the gadget bounce (eliminates the USB race).
(
  # Fallback arm: runs only if a flag is set AND custom_init.sh did NOT already
  # arm NCM early (no /tmp/ncm_early_armed marker). Neither flag = stock boot.
  { [ -e /script/ncm_only ] || [ -e /script/ncm_wifi ]; } || exit 0
  [ -e /tmp/ncm_early_armed ] && exit 0
  L=/tmp/ncm_boot.log
  echo "[ncm] late fallback arm (custom_init did not pre-arm) $(date)" > "$L"
  A=/sys/class/android_usb_accessory/android0
  # Path A: gate on the external gadget being established by ARMadb (state=CONFIGURED)
  # rather than waiting for wlan0 + 45s. The UDiskPassThroughMode guard below is the
  # real race protection (runtime-verified: it neutralizes ARMadb's accessory claim),
  # so a short settle suffices. NCM comes up ~40s after boot instead of ~80s.
  i=0
  while [ $i -lt 60 ]; do
    [ "$(cat $A/state 2>/dev/null)" = "CONFIGURED" ] && break
    i=$((i+1)); sleep 1
  done
  echo "[ncm] external gadget CONFIGURED after ${i}s; settling 10s" >> "$L"
  sleep 10
  touch /tmp/UDiskPassThroughMode
  sleep 2
  killall ARMadb-driver ARMiPhoneIAP2 fakeiOSDevice 2>/dev/null
  pkill -f phone_link_deamon 2>/dev/null
  sleep 1
  echo 0 > /sys/class/android_usb/android0/enable 2>/dev/null
  echo 0 > "$A/enable"
  echo 239 > "$A/bDeviceClass"; echo 2 > "$A/bDeviceSubClass"; echo 1 > "$A/bDeviceProtocol"
  echo ncm > "$A/functions"
  echo 1 > "$A/enable"
  sleep 2
  echo 0 > "$A/enable"; sleep 2; echo ncm > "$A/functions"; echo 1 > "$A/enable"
  sleep 2
  ifconfig ncm0 192.168.50.2 netmask 255.255.255.0 mtu 1500 up
  cat > /tmp/udhcpd_ncm.conf <<CFG
start 192.168.50.100
end 192.168.50.150
interface ncm0
opt subnet 255.255.255.0
opt lease 86400
lease_file /tmp/udhcpd_ncm.leases
pidfile /tmp/udhcpd_ncm.pid
max_leases 20
CFG
  touch /tmp/udhcpd_ncm.leases
  pkill -f udhcpd_ncm.conf 2>/dev/null; sleep 1
  busybox udhcpd -f /tmp/udhcpd_ncm.conf >/tmp/udhcpd_ncm.log 2>&1 &
  sleep 2
  if [ "$(cat $A/state)" != "CONFIGURED" ] || [ "$(cat $A/functions)" != "ncm" ]; then
    echo "[ncm] retry arm" >> "$L"
    echo 0 > "$A/enable"; sleep 2; echo ncm > "$A/functions"; echo 1 > "$A/enable"; sleep 2
    ifconfig ncm0 192.168.50.2 netmask 255.255.255.0 mtu 1500 up
  fi
  # KEEP /tmp/UDiskPassThroughMode set for this session: it makes ARMadb's
  # start_accessory.sh a no-op, so ARMadb cannot reclaim the external gadget
  # during its ~60s accessory burst. (Removing it early let ARMadb flip the
  # gadget back to accessory at ~T+46 and kill NCM.) The flag is volatile
  # (/tmp), cleared on reboot, and only set in NCM-only mode.
  echo "[ncm] armed functions=$(cat $A/functions) state=$(cat $A/state); guard kept" >> "$L"
) &
# ===== end NCMONLY =====

#!/bin/sh
########################
# custom_init.sh - early CDC-NCM bring-up. Runs at start_main_service.sh:42
# (before init_bluetooth_wifi / ARMadb). BACKGROUNDS all work and exit 0s
# immediately, so it can never block boot; if it fails, the late NCMONLY block
# still arms NCM. Toggle flags (in /script, persistent):
#   ncm_only  -> NCM-only appliance: ARMadb skipped, NO WiFi, NCM ~T+3s
#   ncm_wifi  -> NCM first (~T+3s) PLUS the WiFi AP raised as a backstop
#   neither   -> stock CarPlay/Android-Auto boot (this script just exits)
########################
[ -e /script/ncm_only ] || [ -e /script/ncm_wifi ] || exit 0
(
  L=/tmp/ncm_early.log
  export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/tmp/bin:$PATH
  echo "[ncm-early] start uptime=$(cut -d. -f1 /proc/uptime)s mode=$([ -e /script/ncm_wifi ] && echo ncm_wifi || echo ncm_only)" > "$L"
  # copy_to_tmp.sh (line 49) has not run yet -> stage the gadget modules ourselves
  [ -e /tmp/g_android_accessory.ko ] || { [ -e /script/ko.tar.gz ] && tar -xzf /script/ko.tar.gz -C /tmp 2>/dev/null; }
  # Setting UDiskPassThroughMode before line 74 makes runMainProcess SKIP ARMadb
  # (no projection, no accessory-clobber of our gadget). WiFi is raised explicitly below.
  touch /tmp/UDiskPassThroughMode
  grep -q storage_common /proc/modules || insmod /tmp/storage_common.ko 2>/dev/null
  grep -q g_android_accessory /proc/modules || insmod /tmp/g_android_accessory.ko 2>/dev/null
  A=/sys/class/android_usb_accessory/android0
  i=0; while [ ! -e "$A/enable" ] && [ "$i" -lt 50 ]; do i=$((i+1)); sleep 0.1; done
  [ -e "$A/enable" ] || { echo "[ncm-early] gadget sysfs never appeared; abort (late block arms)" >> "$L"; exit 0; }
  echo 0 > "$A/enable"
  echo 239 > "$A/bDeviceClass"; echo 2 > "$A/bDeviceSubClass"; echo 1 > "$A/bDeviceProtocol"
  echo ncm > "$A/functions"; echo 1 > "$A/enable"
  sleep 1
  # wlan0 not up yet (no MAC to derive) -> pin a fixed locally-administered MAC so
  # the host sees a STABLE interface across reboots (point-to-point USB; no L2 collision).
  [ -e /sys/class/net/ncm0 ] && ifconfig ncm0 hw ether c2:8e:30:53:48:01 2>/dev/null
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
  busybox udhcpd -f /tmp/udhcpd_ncm.conf >/tmp/udhcpd_ncm.log 2>&1 &
  touch /tmp/ncm_early_armed
  echo "[ncm-early] NCM armed uptime=$(cut -d. -f1 /proc/uptime)s functions=$(cat $A/functions) state=$(cat $A/state)" >> "$L"
  # WiFi backstop only in ncm_wifi mode (ARMadb is skipped, so we raise it ourselves
  # once init_bluetooth_wifi (line 67) has created wlan0).
  if [ -e /script/ncm_wifi ]; then
    j=0; while [ ! -e /sys/class/net/wlan0 ] && [ "$j" -lt 300 ]; do j=$((j+1)); sleep 0.1; done
    if [ -e /sys/class/net/wlan0 ]; then
      echo "[ncm-early] wlan0 present uptime=$(cut -d. -f1 /proc/uptime)s; raising WiFi AP" >> "$L"
      /script/start_bluetooth_wifi.sh >/tmp/sbw_early.log 2>&1
      echo "[ncm-early] WiFi AP raised uptime=$(cut -d. -f1 /proc/uptime)s wlan0=$(busybox ifconfig wlan0 2>/dev/null | grep -o 192.168.43.1)" >> "$L"
    else
      echo "[ncm-early] wlan0 never appeared; WiFi not raised (use NCM)" >> "$L"
    fi
  fi
) &
exit 0

#!/bin/sh
########################
# wlan_off.sh - on-demand WiFi teardown. Does NOT touch NCM (different udhcpd pidfile).
# Stops hostapd + the wlan0 udhcpd (by /var/run/udhcpd.pid), downs wlan0, unloads driver.
########################
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/tmp/bin:$PATH
killall hostapd 2>/dev/null
killall wpa_supplicant 2>/dev/null
# kill ONLY the wlan AP udhcpd (pidfile /var/run/udhcpd.pid); NCM's is /tmp/udhcpd_ncm.pid
[ -e /var/run/udhcpd.pid ] && kill "$(cat /var/run/udhcpd.pid)" 2>/dev/null
ifconfig wlan0 down 2>/dev/null
rm -f /tmp/run_bluetooth_wifi_lock /tmp/wifi_status
# release the driver (cheap to reload via wlan_on). Keep if BT is using the combo? BT is
# a separate UART/hci_uart path on IW416, independent of moal -> safe to unload moal/mlan.
grep -q "^moal " /proc/modules && { echo "[wlan_off] rmmod moal"; rmmod moal 2>/dev/null; }
grep -q "^mlan " /proc/modules && { echo "[wlan_off] rmmod mlan"; rmmod mlan 2>/dev/null; }
echo "[wlan_off] done; wlan0 $( [ -e /sys/class/net/wlan0 ] && echo present || echo gone )"

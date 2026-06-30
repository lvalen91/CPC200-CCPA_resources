#!/bin/sh
########################
# bt_off.sh - on-demand Bluetooth teardown. Stops hfpd/hcid/bluetoothDaemon/hciattach
# and unloads hci_uart. Does not affect NCM or WiFi.
########################
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/tmp/bin:$PATH
hciconfig hci0 down 2>/dev/null
killall hfpd hcid bluetoothDaemon hciattach 2>/dev/null
sleep 1
killall -9 hfpd hcid bluetoothDaemon hciattach 2>/dev/null
rm -f /tmp/.hciattach_done
grep -q "^hci_uart " /proc/modules && { echo "[bt_off] rmmod hci_uart"; rmmod hci_uart 2>/dev/null; }
echo "[bt_off] done; hci0 $( [ -e /sys/class/bluetooth/hci0 ] && echo present || echo gone )"

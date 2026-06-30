#!/bin/sh
########################
# bt_on.sh - on-demand Bluetooth bring-up (NXP IW416). Independent of WiFi.
# BT name = ccpa-<4 hex from WiFi MAC> (matches WiFi SSID). Forks bluetoothDaemon/hcid/hfpd.
########################
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/tmp/bin:$PATH
KO=/lib/firmware/nxp/iw416_ko.tar.gz

ID=$(set_wifi_mac 2>/dev/null | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -1)
SUF=$(echo "$ID" | sed 's/.*\(..\):\(..\)$/\1\2/' | tr 'A-F' 'a-f')
[ -n "$SUF" ] || SUF=$(cat /etc/serial_number 2>/dev/null | tr -cd '0-9a-fA-F' | tr 'A-F' 'a-f' | sed 's/.*\(....\)$/\1/')
NAME="ccpa-$SUF"

# set BT name BEFORE bluetoothDaemon starts so it advertises the right name.
# /etc/.custom_bluetooth_name is the flag bluetoothDaemon honors to apply a custom name
# (without it the daemon blanks the adapter name during init).
echo "$NAME" > /etc/.custom_bluetooth_name
echo "$NAME" > /etc/bluetooth_name
[ -e /etc/bluetooth/hcid.conf ] && sed -i "s/^\(\s*\)name \".*\";/\1name \"$NAME\";/" /etc/bluetooth/hcid.conf

if [ ! -e /tmp/hci_uart.ko ] && ! grep -q "^hci_uart " /proc/modules; then
	echo "[bt_on] staging hci_uart.ko"; tar -xf "$KO" -C /tmp 2>/dev/null
fi
if ps | grep -v grep | grep -q "[ /]bluetoothDaemon"; then
	echo "[bt_on] bluetoothDaemon already running"
else
	/script/attach_bluetooth.sh &
fi
# wait for hci0
i=0; while [ ! -e /sys/class/bluetooth/hci0 ] && [ "$i" -lt 150 ]; do i=$((i+1)); sleep 0.1; done
hciconfig hci0 2>&1 | grep -E "BD Address|UP RUNNING" || echo "[bt_on] hci0 not up yet"
# bluetoothDaemon blanks the adapter name during its init; assert AFTER it settles, retry
# until it sticks (handles the race where our set lands before the daemon's reset).
n=0
while [ "$n" -lt 10 ]; do
	hciconfig hci0 name "$NAME" 2>/dev/null
	sleep 0.5
	cur=$(hciconfig hci0 name 2>/dev/null | sed -n "s/.*Name: '\(.*\)'.*/\1/p")
	[ "$cur" = "$NAME" ] && break
	n=$((n+1))
done
echo "[bt_on] BT name=$NAME  hci0 now: '$cur'  (asserted after ${n} retries)"

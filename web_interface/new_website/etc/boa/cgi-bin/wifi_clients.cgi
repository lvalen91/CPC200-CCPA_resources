#!/bin/sh
# WiFi Clients CGI - List connected WiFi clients

echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Content-Type: application/json"
echo ""

# Try to get connected clients from various sources

# Method 1: Check wifi_connection_list file
if [ -f /tmp/wifi_connection_list ]; then
    count=$(wc -l < /tmp/wifi_connection_list)
    clients=$(cat /tmp/wifi_connection_list | while read line; do echo "\"$line\""; done | tr '\n' ',' | sed 's/,$//')
    echo "{\"count\":$count,\"clients\":[$clients]}"
    exit 0
fi

# Method 2: Try hostapd_cli
if command -v hostapd_cli >/dev/null 2>&1; then
    clients=$(hostapd_cli all_sta 2>/dev/null | grep -E '^[0-9a-fA-F:]{17}$' | while read mac; do echo "\"$mac\""; done | tr '\n' ',' | sed 's/,$//')
    if [ -n "$clients" ]; then
        count=$(echo "$clients" | tr ',' '\n' | wc -l)
        echo "{\"count\":$count,\"clients\":[$clients]}"
        exit 0
    fi
fi

# Method 3: Parse ARP table for wlan0 clients
if [ -f /proc/net/arp ]; then
    clients=$(awk '$6=="wlan0" && $1!="IP" {print "\"" $1 " (" $4 ")\""}' /proc/net/arp | tr '\n' ',' | sed 's/,$//')
    if [ -n "$clients" ]; then
        count=$(echo "$clients" | tr ',' '\n' | grep -c .)
        echo "{\"count\":$count,\"clients\":[$clients]}"
        exit 0
    fi
fi

# No clients found
echo "{\"count\":0,\"clients\":[]}"

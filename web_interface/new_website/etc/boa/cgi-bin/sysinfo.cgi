#!/bin/sh
# System information CGI - Returns JSON with CPU, memory, temp, uptime, network stats

echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Content-Type: application/json"
echo ""

# CPU usage (simple calculation from /proc/stat)
cpu=$(awk '/^cpu / {u=$2+$4; t=$2+$4+$5; if(t>0) print int(u*100/t); else print 0}' /proc/stat)

# Memory usage (percentage and MB values)
eval $(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{u=t-a; print "mem="int(u*100/t)" memTotal="int(t/1024)" memUsed="int(u/1024)" memAvail="int(a/1024)}' /proc/meminfo)

# CPU temperature (divide by 1000 for Celsius)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp=$((temp_raw / 1000))
else
    temp=0
fi

# Uptime in seconds
uptime=$(awk '{print int($1)}' /proc/uptime)

# Network stats (wlan0)
if [ -f /sys/class/net/wlan0/statistics/rx_bytes ]; then
    rx=$(cat /sys/class/net/wlan0/statistics/rx_bytes)
    tx=$(cat /sys/class/net/wlan0/statistics/tx_bytes)
else
    rx=0
    tx=0
fi

echo "{\"cpu\":$cpu,\"mem\":$mem,\"memTotal\":$memTotal,\"memUsed\":$memUsed,\"memAvail\":$memAvail,\"temp\":$temp,\"uptime\":$uptime,\"rx\":$rx,\"tx\":$tx}"

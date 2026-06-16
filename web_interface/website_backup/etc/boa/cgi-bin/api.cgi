#!/bin/sh
Q="$QUERY_STRING"
if [ "$Q" = "sysinfo" ]; then
  printf "Content-type: application/json\r\n\r\n"
  MEM=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{u=t-a;p=int(u*100/t);printf "{\"total\":%d,\"avail\":%d,\"used\":%d,\"pct\":%d}",t,a,u,p}' /proc/meminfo)
  LOAD=$(awk '{printf "\"%.2f %.2f %.2f\"",$1,$2,$3}' /proc/loadavg)
  UP=$(awk '{d=int($1/86400);h=int($1%86400/3600);m=int($1%3600/60);printf "\"%dd %dh %dm\"",d,h,m}' /proc/uptime)
  DTMP=$(df /tmp 2>/dev/null|awk 'NR==2{p=int($3*100/$2);printf "{\"total\":%d,\"used\":%d,\"avail\":%d,\"pct\":%d}",$2,$3,$4,p}')
  DROOT=$(df / 2>/dev/null|awk 'NR==2{p=int($3*100/$2);printf "{\"total\":%d,\"used\":%d,\"avail\":%d,\"pct\":%d}",$2,$3,$4,p}')
  TEMP=$(awk '{printf "%.1f",$1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
  FREQ=$(awk '{printf "%d",$1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
  CLIENTS=$(awk '/wlan0$/{printf "{\"ip\":\"%s\",\"mac\":\"%s\"},",$1,$4}' /proc/net/arp 2>/dev/null | sed 's/,$//')
  NETSTATS=$(awk '/wlan0:/{gsub("wlan0:","");printf "{\"rx\":%d,\"tx\":%d}",$1,$9}' /proc/net/dev 2>/dev/null || echo '{"rx":0,"tx":0}')
  OVERCOMMIT=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "0")
  printf '{"mem":%s,"load":%s,"uptime":%s,"disk_tmp":%s,"disk_root":%s,"cpu_temp":%s,"cpu_freq":%d,"wifi_clients":[%s],"net":%s,"overcommit":%d}\n' "$MEM" "$LOAD" "$UP" "$DTMP" "$DROOT" "$TEMP" "$FREQ" "$CLIENTS" "$NETSTATS" "$OVERCOMMIT"
elif [ "$Q" = "ttylog" ]; then
  printf "Content-type: text/plain\r\nContent-Disposition: attachment; filename=ttyLog.txt\r\n\r\n"
  cat /tmp/ttyLog 2>/dev/null || echo "ttyLog not found"
elif [ "$Q" = "dmesg" ]; then
  printf "Content-type: text/plain\r\nContent-Disposition: attachment; filename=dmesg.txt\r\n\r\n"
  dmesg 2>/dev/null || echo "dmesg not available"
elif [ "$Q" = "config" ]; then
  printf "Content-type: application/json\r\nContent-Disposition: attachment; filename=riddle.conf\r\n\r\n"
  cat /etc/riddle.conf 2>/dev/null || echo "{}"
elif [ "$Q" = "governor" ]; then
  printf "Content-type: application/json\r\n\r\n"
  CUR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
  AVAIL=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null || echo "")
  printf '{"current":"%s","available":"%s"}\n' "$CUR" "$AVAIL"
elif echo "$Q" | grep -q "^governor_set="; then
  printf "Content-type: application/json\r\n\r\n"
  GOV=$(echo "$Q" | sed 's/governor_set=//')
  if echo "$GOV" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null; then
    echo "$GOV" > /etc/cpu_governor
    printf '{"ok":1}\n'
  else
    printf '{"ok":0}\n'
  fi
elif echo "$Q" | grep -q "^overcommit_set="; then
  printf "Content-type: application/json\r\n\r\n"
  VAL=$(echo "$Q" | sed 's/overcommit_set=//')
  if echo "$VAL" > /proc/sys/vm/overcommit_memory 2>/dev/null; then
    echo "$VAL" > /etc/overcommit
    printf '{"ok":1}\n'
  else
    printf '{"ok":0}\n'
  fi
elif [ "$Q" = "restore" ]; then
  printf "Content-type: application/json\r\n\r\n"
  riddleBoxCfg --restoreOld 2>/dev/null && printf '{"ok":1}\n' || printf '{"ok":0}\n'
elif [ "$Q" = "reboot" ]; then
  printf "Content-type: application/json\r\n\r\n"
  printf '{"ok":1}\n'
  sync
  /sbin/reboot &
else
  printf "Content-type: application/json\r\n\r\n"
  printf '{"error":"unknown"}\n'
fi

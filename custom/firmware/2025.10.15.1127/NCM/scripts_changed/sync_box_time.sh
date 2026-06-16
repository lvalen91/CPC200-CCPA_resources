#!/bin/sh
#####################
# Copyright(c) 2014-2022 DongGuan HeWei Communication Technologies Co. Ltd.
# file    sync_box_time.sh
# brief   Set the system clock from a public US NTP server (by IP, no DNS).
#         System clock is kept in UTC -- no timezone offset is applied.
#         Bounded so it can never hang; needs an internet route to succeed.
# version 2.0.0  (NTP rewrite; replaces the curl www.paplink.cn HTTP-Date scrape)
#####################
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

# US public NTP servers, by IP (no DNS dependency):
#   129.6.15.28      time-a-g.nist.gov   (NIST, Gaithersburg MD)
#   132.163.96.1     time.nist.gov       (NIST anycast)
#   162.159.200.123  time.cloudflare.com (US anycast)
#   216.239.35.0     time.google.com
SERVERS="129.6.15.28 132.163.96.1 162.159.200.123 216.239.35.0"
PERTRY=8

# Fast-fail if there is no default route (e.g. NCM-only with no upstream) so we
# do not sit through every server's timeout when the internet is unreachable.
if ! awk 'NR>1 && $2=="00000000"{f=1} END{exit !f}' /proc/net/route 2>/dev/null; then
	echo "[sync_box_time] no default route; NTP unreachable, clock unchanged: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
	exit 1
fi

for s in $SERVERS; do
	echo "[sync_box_time] querying NTP $s (UTC) ..."
	if timeout "$PERTRY" ntpd -q -n -p "$s" >/dev/null 2>&1; then
		echo "[sync_box_time] clock set from $s -> $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
		exit 0
	fi
	echo "[sync_box_time] $s no response"
done

echo "[sync_box_time] all NTP servers unreachable; clock unchanged: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
exit 1

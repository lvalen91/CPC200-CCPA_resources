#!/bin/sh
if [ -e /sys/bus/platform/devices/ci_hdrc.0/inputs/a_suspend_req_inf ]; then
	echo "[start_hnp] requesting USB host-to-peripheral suspend (a_suspend_req_inf), then iphoneRoleSwitch"
	echo 1 > /sys/bus/platform/devices/ci_hdrc.0/inputs/a_suspend_req_inf && \
		test -e /script/iphoneRoleSwitch_test && /script/iphoneRoleSwitch_test 0x05ac 0x12a8
fi

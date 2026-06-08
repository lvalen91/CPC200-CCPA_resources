#!/bin/sh
########################
# Copyright(c) 2014-2023 DongGuan HeWei Communication Technologies Co. Ltd.
# file    output/rootfs/common/script/start_iphone.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    228月23
########################

interval=$(riddleBoxCfg -g HNPInterval)
serialNum=41de1cfe2e099bec5932187411378387653dbc63
test -e /etc/device_serial && serialNum=$(cat /etc/device_serial)

echo "[start_iphone] insmod iPhone: hnp_interval_ms=$interval serial=$serialNum"

[ -e /tmp/f_ptp.ko ] && { insmod /tmp/f_ptp.ko && echo "[start_iphone] insmod f_ptp.ko ok" || echo "[start_iphone] insmod f_ptp.ko FAILED"; }
[ -e /tmp/f_ptp_appledev.ko ] && { insmod /tmp/f_ptp_appledev.ko && echo "[start_iphone] insmod f_ptp_appledev.ko ok" || echo "[start_iphone] insmod f_ptp_appledev.ko FAILED"; }
[ -e /tmp/f_ptp_appledev2.ko ] && { insmod /tmp/f_ptp_appledev2.ko && echo "[start_iphone] insmod f_ptp_appledev2.ko ok" || echo "[start_iphone] insmod f_ptp_appledev2.ko FAILED"; }
[ -e /tmp/g_iphone.ko ] && { insmod /tmp/g_iphone.ko hnp_interval_ms="$interval" serial="$serialNum" && echo "[start_iphone] insmod g_iphone.ko ok" || echo "[start_iphone] insmod g_iphone.ko FAILED"; }

#!/bin/sh
########################
# Copyright(c) 2014-2018 DongGuan HeWei Communication Technologies Co. Ltd.
# file    dbus_run.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    26Nov18
########################
#load bluetooth
echo "[load_bluetooth_wifi] loading bluetooth (rtk_hciattach)"
test -e /usr/sbin/rtk_hciattach && { rtk_hciattach -s 115200 ttymxc2 rtk_h5 && echo "[load_bluetooth_wifi] rtk_hciattach ok" || echo "[load_bluetooth_wifi] rtk_hciattach FAILED"; }

#load wifi
echo "[load_bluetooth_wifi] loading wifi (88x2bs.ko)"
test -e /tmp/88x2bs.ko && { insmod /tmp/88x2bs.ko && echo "[load_bluetooth_wifi] insmod 88x2bs.ko ok" || echo "[load_bluetooth_wifi] insmod 88x2bs.ko FAILED"; }

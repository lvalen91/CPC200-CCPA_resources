#!/bin/sh
########################
# Copyright(c) 2014-2019 DongGuan HeWei Communication Technologies Co. Ltd.
# file    set_quick_charge_mode.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    10May19
########################
#reset BT
echo "[init_gpio] resetting BT gpio1"
[ -e /sys/class/gpio/gpio1 ] || echo 1 > /sys/class/gpio/export;
echo out > /sys/class/gpio/gpio1/direction;
echo 1 >/sys/class/gpio/gpio1/value;
sleep 0.1
echo 0 >/sys/class/gpio/gpio1/value;

#set quickly charge mode
[ -e /sys/class/gpio/gpio6 ] || echo 6 > /sys/class/gpio/export;
echo out > /sys/class/gpio/gpio6/direction;
[ -e /sys/class/gpio/gpio7 ] || echo 7 > /sys/class/gpio/export;
echo out > /sys/class/gpio/gpio7/direction;
echo 0 >/sys/class/gpio/gpio6/value;
sleep 0.1
echo 1 >/sys/class/gpio/gpio6/value;
echo 1 >/sys/class/gpio/gpio7/value;
echo "[init_gpio] quick-charge gpio6/7 set"

#Power LED ON
#echo 2 > /sys/class/gpio/export;
#echo out > /sys/class/gpio/gpio2/direction;
#echo 0 >/sys/class/gpio/gpio2/value;

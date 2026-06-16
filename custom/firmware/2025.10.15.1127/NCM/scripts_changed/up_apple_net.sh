#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    up_apple_net.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################
echo "[up_apple_net] bringing up eth2 / dhcp eth1"
killall -9 udhcpc
ifconfig eth2 up && udhcpc -i eth1 -T 1 -A 2 &

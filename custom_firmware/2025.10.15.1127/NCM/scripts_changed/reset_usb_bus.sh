#!/bin/sh
########################
# Copyright(c) 2014-2017 DongGuan HeWei Communication Technologies Co. Ltd.
# file    reset_usb_bus.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    23Feb17
########################
echo "[reset_usb_bus] resetting USB bus root hub /dev/bus/usb/001/001"
reset_usb /dev/bus/usb/001/001

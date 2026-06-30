#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    mount-gadgetfs.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    14Jul15
########################
#insmod  /lib/modules/3.4.79/kernel/drivers/usb/gadget/gadgetfs.ko
insmod gadgetfs 2>/dev/null && echo "[mount-gadgetfs] insmod gadgetfs ok" || echo "[mount-gadgetfs] insmod gadgetfs FAILED"
mkdir -p /dev/gadget
mount -t gadgetfs none /dev/gadget/ && echo "[mount-gadgetfs] mounted gadgetfs at /dev/gadget" || echo "[mount-gadgetfs] mount /dev/gadget FAILED"

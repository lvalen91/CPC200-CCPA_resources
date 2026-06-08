#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    mount-UPAN.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################
mkdir -p /mnt/UPAN
echo "[mount-UPAN] mount /dev/sda4 -> /mnt/UPAN"
mount -t vfat /dev/sda4 /mnt/UPAN && echo "[mount-UPAN] mounted ok" || echo "[mount-UPAN] mount FAILED"

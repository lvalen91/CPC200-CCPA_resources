#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    mount-TF.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    12Jul15
########################
mkdir -p /mnt/TF
echo "[mount-TF] mount /dev/mmcblk1p1 -> /mnt/TF"
mount -t vfat /dev/mmcblk1p1 /mnt/TF && echo "[mount-TF] mounted ok" || echo "[mount-TF] mount FAILED"

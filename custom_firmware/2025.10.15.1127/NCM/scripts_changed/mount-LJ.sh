#!/bin/sh
########################
# Copyright(c) 2014-2015 DongGuan HeWei Communication Technologies Co. Ltd.
# file    mount-LJ.sh
# brief
# author  LI JIAN
# version 1.0.0
# date    12Jul15
########################
mkdir -p /mnt/LJ
echo "[mount-LJ] mount 192.168.31.144:/home/lijian -> /mnt/LJ"
mount -t nfs -o nolock 192.168.31.144:/home/lijian /mnt/LJ && echo "[mount-LJ] mounted ok" || echo "[mount-LJ] mount FAILED"

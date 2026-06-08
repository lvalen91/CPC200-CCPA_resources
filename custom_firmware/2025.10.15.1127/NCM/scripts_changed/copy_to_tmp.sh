#!/bin/sh
########################
# Copyright(c) 2014-2019 DongGuan HeWei Communication Technologies Co. Ltd.
# file    init_hicar_lib.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    10May19
########################
#cp so and exe to tmp, save space of ROM for update
tmpLibPath=/tmp/lib/
tmpBinPath=/tmp/bin/
mkdir -p "$tmpLibPath"
mkdir -p "$tmpBinPath"


ls /usr/lib/libcrypto.so* >/dev/null 2>&1 && cp -d /usr/lib/libcrypto.so* "$tmpLibPath"
ls "$tmpLibPath"libcrypto.so* >/dev/null 2>&1 && echo "[copy_to_tmp] libcrypto.so copied to $tmpLibPath ok" || echo "[copy_to_tmp] libcrypto.so not present, copy skipped/FAILED"

test -e /usr/sbin/ARMadb-driver && cp /usr/sbin/ARMadb-driver "$tmpBinPath"
test -e "$tmpBinPath"ARMadb-driver && echo "[copy_to_tmp] ARMadb-driver copied to $tmpBinPath ok" || echo "[copy_to_tmp] ARMadb-driver not present, copy skipped/FAILED"

#tar decompress koS to /tmp
test -e /script/ko.tar.gz && tar -xvf /script/ko.tar.gz -C /tmp
test -e /script/ko.tar.gz && echo "[copy_to_tmp] extracted ko.tar.gz to /tmp" || echo "[copy_to_tmp] ko.tar.gz absent, nothing extracted"

#mv all wifibt rootfs tar file to tmp/
ls /*_rootfs.tar.gz && mv /*_rootfs.tar.gz /tmp/
ls /tmp/*_rootfs.tar.gz >/dev/null 2>&1 && echo "[copy_to_tmp] moved *_rootfs.tar.gz to /tmp ok" || echo "[copy_to_tmp] no *_rootfs.tar.gz to move"

#cp -d /usr/lib/lib*so* $tmpLibPath
#for file in `find /usr/sbin -type f`; do
#	cp $file $tmpBinPath
#done

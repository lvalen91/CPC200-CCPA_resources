#!/bin/sh
########################
# mount_usb.sh - mount the FAT32 USB staging device at /mnt/UPAN + prep staging dirs.
# Staging area to circumvent the tiny (12.5MB) rootfs: bin/ (run staged tools),
# lib/ (LD_LIBRARY_PATH'd staged .so), staging/ (data/logs/captures). vfat = exec OK,
# but NO symlinks/Unix-perms (reformat ext4 if those are needed).
# Idempotent. Handles cold-boot (stick already inserted; arg = seconds to wait for
# enumeration, default 12). mdev's udisk_insert.sh covers insert-after-boot.
########################
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/tmp/bin:$PATH
MP=/mnt/UPAN
WAIT="${1:-12}"
if mount | grep -q " $MP "; then echo "[mount_usb] already mounted"; mkdir -p "$MP/bin" "$MP/lib" "$MP/staging" 2>/dev/null; exit 0; fi
i=0; while [ ! -e /dev/sda1 ] && [ "$i" -lt "$WAIT" ]; do i=$((i+1)); sleep 1; done
[ -e /dev/sda1 ] || { echo "[mount_usb] no /dev/sda1 after ${WAIT}s (no stick) - skipping"; exit 1; }
mkdir -p "$MP"
mount /dev/sda1 "$MP" -t vfat -o utf8=1 || { echo "[mount_usb] mount failed"; exit 1; }
mkdir -p "$MP/bin" "$MP/lib" "$MP/staging"
echo "[mount_usb] /dev/sda1 -> $MP  ($(df -h "$MP" | awk 'NR==2{print $4}') free); staging: $MP/{bin,lib,staging}"

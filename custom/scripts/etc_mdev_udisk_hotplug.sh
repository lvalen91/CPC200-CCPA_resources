########################
# Copyright(c) 2014-2017 DongGuan HeWei Communication Technologies Co. Ltd.
# file    udisk_insert.sh
# brief   
# author  Shi Kai
# version 1.0.0
# date    03Jun17
########################
#!/bin/sh
echo "/dev/$MDEV $ACTION" >> /dev/console
case $ACTION in
	add)
		if [ ! -d /sys/block/*/$MDEV[0-9] ] ; then
			echo "no sda[0-9]" >> /dev/console
			mkdir -p /mnt/UPAN
			mount /dev/$MDEV /mnt/UPAN -t vfat -o utf8=1
			blkid /dev/$MDEV | awk '{print $3}' > /tmp/udisk_uuid
# OTA-removed #			/script/update_box.sh /dev/$MDEV >> /dev/console &
		fi
		;;
	remove)
		# Hardened (OTA removed): just unmount. No update_status reboot check, no
		# mass_storage gadget cleanup — appliance is NCM-only, so there is zero
		# latent reboot path on USB removal.
		umount -l /mnt/UPAN 2>/dev/null
		;;
esac




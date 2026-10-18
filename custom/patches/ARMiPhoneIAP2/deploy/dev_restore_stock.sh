#!/bin/bash
# Restore the FACTORY ARMiPhoneIAP2 (d933c9d5) to the adapter rootfs from the UPAN STOCK backup,
# to both /usr/sbin and /tmp/bin, then restart the iAP2 daemon. Reverses dev_deploy.sh.
set -e
HOST="${ADAPTER_HOST:?set ADAPTER_HOST to the adapter address}"
SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
SSH(){ sshpass -p '' ssh $SSHOPTS root@$HOST "$@"; }

SSH 'set -e; S=/mnt/UPAN/carlink_work/STOCK/ARMiPhoneIAP2.usr_sbin.factory.packed
  [ -f "$S" ] || { echo "MISSING stock backup $S"; exit 1; }
  cp -f "$S" /usr/sbin/ARMiPhoneIAP2
  cp -f "$S" /tmp/bin/ARMiPhoneIAP2
  chmod 755 /usr/sbin/ARMiPhoneIAP2 /tmp/bin/ARMiPhoneIAP2
  echo -n "restored md5 (expect d933c9d5...): "; md5sum /usr/sbin/ARMiPhoneIAP2 | cut -d" " -f1
  killall ARMiPhoneIAP2 2>/dev/null; echo "restarted"'

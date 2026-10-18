#!/bin/bash
# Fast-iteration deploy of a patched (UNPACKED) ARMiPhoneIAP2 directly to the adapter rootfs.
# Transfers -> packs on-device with modified_upx_arm -> installs to /usr/sbin AND /tmp/bin
# (the latter has PATH priority) -> restarts the iAP2 daemon. No carlink_macOS involvement.
#
# Usage: ./dev_deploy.sh <unpacked-patched-ELF>
# Prereq: carlink_macOS must NOT be pushing /tmp/bin/ARMiPhoneIAP2 (iap2PushEnabled=false),
#         and STOCK backup must exist at /mnt/UPAN/carlink_work/STOCK/.
set -e
PATCHED="${1:?usage: dev_deploy.sh <unpacked-patched-ELF>}"
HOST="${ADAPTER_HOST:?set ADAPTER_HOST to the adapter address}"
SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
SSH(){ sshpass -p '' ssh $SSHOPTS root@$HOST "$@"; }

echo "[1/4] transferring $(basename "$PATCHED") ($(wc -c < "$PATCHED") B) ..."
base64 < "$PATCHED" | SSH 'mkdir -p /mnt/UPAN/carlink_work/iter && base64 -d > /mnt/UPAN/carlink_work/iter/patched.unpacked'

echo "[2/4] packing on-device + installing ..."
SSH 'set -e; cd /mnt/UPAN/carlink_work/iter
  rm -f patched.packed
  /mnt/UPAN/carlink_work/upx_arm --best patched.unpacked -o patched.packed >/dev/null 2>&1
  cp -f patched.packed /usr/sbin/ARMiPhoneIAP2
  cp -f patched.packed /tmp/bin/ARMiPhoneIAP2
  chmod 755 /usr/sbin/ARMiPhoneIAP2 /tmp/bin/ARMiPhoneIAP2
  echo -n "  installed md5: "; md5sum /usr/sbin/ARMiPhoneIAP2 | cut -d" " -f1
  echo -n "  packed size:   "; wc -c < patched.packed'

echo "[3/4] restarting iAP2 daemon (killall -> phone_link respawns from /tmp/bin) ..."
SSH 'killall ARMiPhoneIAP2 2>/dev/null; sleep 1; echo "  killed; awaiting respawn on next phone-link handshake"'

echo "[4/4] done. Watch: ssh root@$HOST 'tail -f /tmp/ttyLog'"

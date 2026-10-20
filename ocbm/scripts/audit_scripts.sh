#!/bin/sh
echo "===================== SYNTAX CHECK (sh -n) ====================="
# mdev hooks: the ones an ACTIVE /etc/mdev.conf line names (usb_mount.sh once bootpath has rewired
# the sd rules, 2026-10-19; the stock udisk_*.sh on a unit it could not rewire). A unit is audited
# for the hooks it actually runs, a hook a live rule names but that is missing reports ERR, and a
# stock hook strip deleted is not reported at all.
MDEV_HOOKS=$(grep -v '^[[:space:]]*#' /etc/mdev.conf 2>/dev/null | grep -o '/etc/mdev/[^[:space:]]*\.sh' | sed 's#//*#/#g' | sort -u)
for f in /etc/init.d/rcS $MDEV_HOOKS /script/*.sh; do
  if sh -n "$f" 2>/tmp/e; then echo "  OK    $f"; else echo "  ERR>> $f : $(cat /tmp/e)"; fi
done
echo "  mdev.conf sd rules:"; grep -n '^sd' /etc/mdev.conf 2>/dev/null | sed 's/^/    /'
echo
echo "============ DEAD REFERENCES to removed components ============="
# things that no longer exist on this stripped box (g_iphone / f_ptp*: HeWei's Apple-gadget modules,
# filtered out of /script/ko.tar.gz by strip, 2026-10-19 - OCBM uses the built-in g_android):
PAT='g_iphone|f_ptp|ARMadb|AppleCarPlay|ARMiPhoneIAP2|ARMAndroidAuto|ARMHiCar|mdnsd|boxNetworkService|boxHUDServer|colorLightDaemon|boxImgTools|riddleBox|riddle_top|riddleBoxCfg|check_mfg_mode|check_log_size|init_bluetooth_wifi|close_bluetooth_wifi|start_iap2_ncm|cpu_UsageRate|check_udisk_log|fakeiOSDevice|fakeCarLife|fakeAADevice|AutomaticTest|hwSecret|/usr/sbin/boa|boa_old|wpa_supplicant|wpa_cli|brcm_patchram|rtk_hciattach|rtk_hci_uart|bcmdhd|88x2|8733bs|bcm4|BCM4'
for f in /etc/init.d/rcS $MDEV_HOOKS /script/*.sh; do
  m=$(grep -nE "$PAT" "$f" 2>/dev/null | grep -vE ':[[:space:]]*#')
  [ -n "$m" ] && { echo "--- $f ---"; echo "$m"; }
done
echo
echo "============ dangling file/script refs (test -e / call) ========"
for f in /script/*.sh /etc/init.d/rcS; do
  for ref in $(grep -oE '/script/[a-zA-Z0-9_]+\.sh|/usr/sbin/[a-zA-Z0-9_]+' "$f" 2>/dev/null | sort -u); do
    [ -e "$ref" ] || echo "  $f -> MISSING $ref"
  done
done
echo "AUDIT_DONE"

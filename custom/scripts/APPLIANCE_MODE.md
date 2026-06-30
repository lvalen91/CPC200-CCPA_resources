# NCM appliance mode (projection-stripped runtime)

Goal: run the CPC200-CCPA as a standalone POSIX appliance exposing only **NCM
(USB-CDC networking)** + **WLAN** + **Bluetooth**, with the CarPlay / Android-Auto
projection stack disabled. Reverse-engineered + validated live on a running unit
(SSH over NCM at `192.168.50.2`), then persisted across a reboot.

## Architecture finding
The projection stack is **pure userspace** and has zero hold on the base OS,
drivers, NCM gadget, or BT. Killing every projection daemon leaves NCM + BT + WiFi
fully functional. The stripping is therefore a userspace-removal exercise; no
kernel/driver changes are needed.

## Boot mode flags (in `/script`, persistent on jffs2)
- `ncm_only`  → NCM only, **no WiFi**, ARMadb skipped.
- `ncm_wifi`  → NCM **+ WiFi AP**, ARMadb skipped.  ← appliance default
- neither     → stock CarPlay/Android-Auto boot.

`custom_init.sh` arms NCM early (~T+3s) and, in `ncm_wifi`, raises the AP (~T+6s).
`UDiskPassThroughMode` makes `runMainProcess` skip `ARMadb-driver`.

## start_main_service.sh appliance gate (additive)
Added `ncm_appliance()` helper = true when `ncm_only` or `ncm_wifi` is set.
Used to skip the projection-adjacent daemons that are launched **directly**
(they bypass the `UDiskPassThroughMode` gate, so they ran even with ARMadb skipped):
`mdnsd`, `boxNetworkService`, `boxHUDServer`, `colorLightDaemon`, `cpu_UsageRate`
(spawns `riddle_top`). `boa` (web config UI) is intentionally kept.

Original is backed up on-device at `/script/start_main_service.sh.bak`; the modified
file is `start_main_service.appliance.sh` here. Revert = restore .bak and/or
`rm /script/ncm_wifi /script/ncm_only`.

## Validated boot result (uptime 28s, post-reboot)
- ncm_early.log: NCM armed @3s; WiFi AP raised @6s (192.168.43.1)
- projection daemons: ARMadb / mdnsd / boxNetworkService / boxHUDServer /
  colorLightDaemon / riddle_top / cpu_UsageRate = **all 0**
- kept: dropbear, bluetoothDaemon, hciattach, hcid, hfpd×2, dbus-daemon, udhcpd,
  hostapd, boa
- NCM `CONFIGURED` (ncm0 192.168.50.2); BT `hci0 UP RUNNING`;
  WiFi `wlan0 192.168.43.1 UP RUNNING`; ifaces: lo ncm0 ncm1 sit0 sta0 wlan0

## Gotchas
- SSH (dropbear) non-login `PATH=/usr/bin:/bin` — **no `/sbin`**. `reboot` is not
  found; use `/sbin/reboot` (→ busybox). A backgrounded `(sleep 1; reboot) &` over
  SSH is SIGHUP-killed when the session closes — call reboot synchronously.
- NXP WiFi (mlan/moal): when `wpa_supplicant` is present the AP path is forced to
  **P2P-GO** ("P2P interface not support AP"). This firmware ships no
  wpa_supplicant, so AP = plain `hostapd` on wlan0. True concurrent **hostapd-AP +
  STA** is therefore a Phase-C concern → likely needs the P2P-GO + STA model, and
  `wpa_supplicant` (+ `iw`) must be added (driver + sta0 + wpa_supplicant.conf
  already present; `init_bluetooth_wifi.sh` treats STA as optional via
  `supportStaMode`).

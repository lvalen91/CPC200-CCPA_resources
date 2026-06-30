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

## Live rootfs strip (Phase C, incremental + reboot-verified)
Method: delete projection files from the live rw jffs2, reboot, verify NCM+BT+WiFi,
then snapshot a restore-grade backup (raw mtd0/1/2 + rootfs.tar.gz + SHA256SUMS) to
`~/Downloads/ccpa_backups/<ts>_<label>/`. Backups + repo `nor_backup/` + SPI
programmer = full recovery.

- **Prep:** `riddleBoxCfg -s BoxIp 192.168.43.1` — pins the AP IP so it survives
  `ARMHiCar` removal (start_bluetooth_wifi.sh:144 used `test -e ARMHiCar` to pick
  192.168.43.1; with ARMHiCar gone the script's `BoxIp` override takes over).
- **Batch 1 — binaries (~1.6 MB):** rm ARMadb-driver, ARMAndroidAuto, AppleCarPlay,
  ARMiPhoneIAP2, ARMHiCar, ARMandroid_Mirror, usbmuxd, mdnsd, boxNetworkService,
  colorLightDaemon, AutomaticTest, hwSecret, riddle_top. Reboot OK (10.4→8.7 MB used).
- **Batch 2 — libraries (~1.3 MB):** rm libHisightSink, libHwDeviceAuthSDK,
  libHwKeystoreSDK, libdmsdp*, libnearby, libhicar, libauthagent, libdns_sd,
  libsecurec, libARMtool, libboxtrans, libmanagement, libfdk-aac*, libtinyalsa,
  libusb-1.0*. Reboot OK (8.7→7.4 MB used). Verified: all keep-daemons start (no
  lib-link failures), BT inquiry scan works (HFP audio uses kernel SCO/PCM, not
  userspace tinyalsa/fdk-aac).
- **Kept libs (/usr/lib):** libbluetooth, libdbus-1, libnl-3, libnl-genl-3, libxml2,
  libcrypto, libssl (held for wpa_supplicant), libz. **Dependency method:** union of
  `/proc/*/maps` (currently-loaded) + `strings <kept ELF> | grep '\.so'` (link/dlopen
  refs); remove only candidates referenced by no kept ELF.

- **Batch 3 — /lib dead weight (59 files):** removed unused glibc runtime libs
  (libcidn 181K, libitm, libgomp, libnss_nisplus/hesiod/db, libthread_db, libmemusage,
  libanl, libBrokenLocale, libSegFault, libpcprofile) + all build-time `.o`/`.la`/
  `.spec`/`-gdb.py` + unversioned dev `.so` linker scripts. Kept everything mapped +
  libnss_files/dns/compat/nis, libatomic, libssp, libz. No nsswitch.conf → glibc
  defaults (files dns), so the dropped nss backends are dead. Reboot OK (7.4→7.1 MB).
- **Batch 4 — dead scripts (18):** phone_link_deamon, start_iphone/aoa/mtp/hnp/
  android_ncm, start_accessory(+_mass_storage), mount-SK/LJ/TF/UPAN/gadgetfs,
  up_apple_net, start_mic_record, test_mic, reset_usb_bus, open_log. Verified the
  apparent "active" refs (start_accessory, mount-SK in start_ncm/iap2_ncm) were only
  vendor copy-paste comment headers; start_main_service.sh calls none of them.
- **OTA cluster removed** (user: not needed): update_box, update_box_ota,
  quickly_update, check_update, smart_copy, module_upgrade, getFuncModule,
  start_mass_storage, update_dtb, update_kernel. Neutralized the two mdev USB-insert
  hooks (`/etc/mdev/udisk_{insert,hotplug}.sh` `# OTA-removed #` the update_box call).
- **Batch 5 — web UI removed** (user: not needed): rm /usr/sbin/boa + /etc/boa
  (incl. cgi-bin/upload.cgi path-traversal surface). boa's `if [ -e /usr/sbin/boa ]`
  launch guard self-skips, so no script edit needed. Listeners now only SSH:22 +
  telnet:23 (no :80). Also removed `goto_burn_mode.sh` — **burn-mode is NOT a recovery
  path: it erases uboot and bricks the unit (SPI IC reflash required). There is no soft
  "flash" mode.** Removing the script eliminates that footgun.

Net: **10.4 MB → 6.9 MB used (5.6 MB free)**, projection + web UI + OTA + brick-trigger
all gone, appliance stable across 6 reboots. Final services: dropbear(+telnetd),
bluetoothDaemon/hcid/hfpd/hciattach/dbus (BT), hostapd (WiFi AP), udhcpd (NCM DHCP),
NCM gadget. NCM 192.168.50.2 @T+3s, WiFi-AP 192.168.43.1 @T+6s, BT hci0 UP RUNNING.

Restore points (raw mtd0/1/2 + rootfs.tar.gz + SHA256SUMS) in `~/Downloads/ccpa_backups/`:
baseline_appliance · batch1_bins · batch2_libs · batch3_libstrip ·
batch4_scripts_ota · batch5_boa_FINAL.

## On-demand model (NCM default; WLAN/BT brought up only when needed)
Default boot (`/script/ncm_only`) now brings up **only NCM + SSH** — no WiFi driver, no
BT. At rest the only loaded modules are `g_android_accessory` + `storage_common`; only
`dropbear` + `udhcpd` run. WLAN and BT are explicit, reversible operations:

| Script | Action |
|---|---|
| `wlan_on.sh [AP]` | insmod mlan/moal, set_wifi_mac, raise hostapd AP on wlan0 (192.168.43.1) |
| `wlan_off.sh` | stop hostapd, kill the AP's udhcpd **by /var/run/udhcpd.pid** (NOT killall — NCM's udhcpd uses /tmp/udhcpd_ncm.pid), wlan0 down, rmmod moal/mlan |
| `bt_on.sh` | stage hci_uart.ko, run attach_bluetooth.sh (fw_loader + hciattach + bluetoothDaemon→hcid/hfpd), hci0 up |
| `bt_off.sh` | kill hfpd/hcid/bluetoothDaemon/hciattach, rmmod hci_uart |

Implementation: `start_main_service.sh` skips `init_bluetooth_wifi.sh` under `ncm_only`.
`start_bluetooth_wifi.sh`'s ncm_only AP-suppression guard gained an `ONDEMAND_WIFI=1`
bypass that `wlan_on.sh` sets. On IW416, BT is a separate UART/hci_uart path independent
of the moal WiFi driver, so the two toggle fully independently. Verified: boot=NCM-only,
`wlan_on`/`bt_on` raise each, `wlan_off`/`bt_off` return to NCM-only — NCM/SSH never drop.

## Device-unique naming: ccpa-<id>
WiFi SSID **and** BT name = `ccpa-<last 2 octets of WiFi MAC>` (e.g. MAC 00:E0:4C:91:B0:DF
→ **`ccpa-b0df`**; serial last-4 is the fallback). `set_wifi_mac` reports the MAC even
with the driver unloaded, so the id is always derivable. Set in:
- AP SSID: `/etc/hostapd.conf` `ssid=` (the broadcast source for hostapd AP mode;
  start_bluetooth_wifi.sh only uses /etc/wifi_name for P2P) — `wlan_on.sh` rewrites it.
- BT: `/etc/.custom_bluetooth_name` (the flag bluetoothDaemon honors — without it the
  daemon **blanks** the adapter name during init) + `/etc/bluetooth_name` +
  `CustomBluetoothName` + hcid.conf. `bt_on.sh` also asserts `hciconfig hci0 name` with a
  post-settle retry loop (the daemon clears the name mid-init, so set-once races).

Residual scripts removed: `load_bluetooth_wifi.sh` (RTL-only), `cpu_UsageRate.sh`.

## riddle fully removed (config moved to static sources)
`riddleBoxCfg` + `riddle.conf` + `riddle_default.conf` deleted. It was load-bearing for
the WiFi AP (it sourced `WifiPassword` and `BoxIp`), so `start_bluetooth_wifi.sh` was
refactored to be riddle-free:
- passphrase + channel now read from `/etc/hostapd.conf` (single source of truth)
- `mode=AP` hardcoded (IW416 appliance; P2P needs wpa_supplicant)
- `WLANIP=192.168.43.1` hardcoded (override via `/etc/wifi_ip`); must not be the NCM subnet
- `wlan_on.sh`/`bt_on.sh` dropped their `riddleBoxCfg -s` calls; `init_bluetooth_wifi.sh`
  dropped the `UseUartBLE` gate (attach_bluetooth starts bluetoothDaemon) and the custom-
  name `-s` calls (name files are the source). `start_main_service.sh` dropped the
  riddle.conf-creation block. Verified riddle-free across reboot: AP 192.168.43.1 /
  ccpa-b0df / passphrase from hostapd.conf, BT ccpa-b0df.

## PATH standardized
`/etc/profile` PATH cleaned to a single canonical, ordered line:
`export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/tmp/bin` (was `/tmp/bin:$PATH:/usr/sbin:/sbin`
plus a redundant `PATH=$PATH`). This fixes **login/interactive shells and the boot
context** (rcS does `. /etc/profile`), so `reboot`/`ifconfig`/`insmod`/`hostapd` resolve
without a `/sbin` prefix. Original at `/etc/profile.bak`; copy in repo `etc_profile.appliance`.
**Limitation:** non-interactive `ssh host 'cmd'` sessions don't source profile — dropbear
uses a fixed `DEFAULT_PATH=/usr/bin:/bin` (changing it needs recompiling dropbear). So the
`/script/*.sh` keep self-setting PATH, and automation should pass PATH explicitly.

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

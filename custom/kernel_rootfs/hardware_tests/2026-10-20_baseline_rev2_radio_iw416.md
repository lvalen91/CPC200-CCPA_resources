# 2026-10-20 — baseline revision 2 `radio up` / `radio down` on the IW416 unit: power, detection, drivers, firmware, hci0

**Outcome:** on the baseline **revision 2** rootfs (ccpa_custom `5e90368`, the image flashed in
`2026-10-20_baseline_rev2_kernel_rootfs.md`), `radio up` powered the module, found the IW416 on SDIO, loaded both
drivers, brought the firmware up and got a Bluetooth controller to UP; `radio down` returned the unit to radios off.
Observed on the unit, 2026-10-20. Nothing was associated, scanned, paired or sent: the image carries no tools for that
(see "Not tested"). Times were not recorded.

Unit: the IW416 bench adapter (`../backups/20261019_IW416_ocbm_baseline_pre-livi/`), kernel image `-iw416`
(BT DT node `nxp,88w8987-bt`), rootfs `c424cd3c…`. The script is `../baseline/arm-imx6ul/rootfs/usr/sbin/radio` (line cites below are into it).

## Observed

| Step | Result |
|---|---|
| `radio status` before | radios off (as after the rootfs boot) |
| `radio up`: MMC host load → `reg_wlan` | `reg_wlan` switched on; SDIO card enumerated |
| SDIO ID | `0x02df:0x9159` (NXP IW416), read from the card's own sysfs `vendor`/`device` |
| Wi-Fi | `mwifiex_sdio` loaded; firmware: the combo file `mrvl/sdiouartiw416_combo_v0.bin` is the only Marvell file in the image, so it is the one loaded (INFERRED: no firmware filename was logged); `phy0` and `mlan0` appeared; `mlan0` administratively up, **operstate down** (no network joined) |
| Bluetooth | `btnxpuart` loaded, `"FW already running"` (the combo firmware had started the BT half); `hci0` **UP** with a BD address (address not recorded here) |
| `radio down` | back to radios off: only `usb0`, `lo`; no SDIO card. The kernel module `bluetooth` stays loaded (`radio down` does not remove it; why is not examined) |

Status by step: IW416 power switch (`reg_wlan`), SDIO detection, driver load (`mwifiex_sdio`, `btnxpuart`), firmware
start, `hci0` UP — **VERIFIED on hardware**. Everything else about the radios — **UNVERIFIED**.

## Found (all four addressed in revision 3; status updated 2026-10-20)

1. **`Unknown symbol` lines in `dmesg`.** Many "Unknown symbol" errors appear during `radio up`: `mwifiex_sdio` and
   `btnxpuart` are attempted before their dependencies are in, and the load then succeeds on retry. The end state is
   correct (interfaces, `hci0`). Cosmetic. The exact cause in the load path is INFERRED from the log order (the script
   uses `modprobe`, `radio:96,123,162`), not traced. **[2026-10-20: FIXED in revision 3 and VERIFIED on this unit.]**
   Cause traced to BusyBox MODPROBE_SMALL, which insmods a module before its dependencies; revision 3 loads each module
   after its `modules.dep` dependencies with `insmod` (B10). On the revision-3 rootfs `radio up` gave 0 `Unknown symbol`
   lines (`2026-10-20_baseline_rev3_rootfs_radio_iw416.md`).
2. **Wording.** `radio up` prints `Wi-Fi: mlan0 up` after `ip link set dev mlan0 up` succeeds (`radio:151`), while
   `radio status` prints the interface's `operstate` (`radio:86`), which is `down` without a carrier. Both are true
   (admin-up vs. no link); the messages should say which one they mean. **[2026-10-20: FIXED in revision 3 (B11) and
   VERIFIED on this unit:** `radio up` now prints "mlan0 administratively up, no carrier (operstate down)", the same
   wording as `radio status` (`2026-10-20_baseline_rev3_rootfs_radio_iw416.md`).]
3. **Tooling gap.** The baseline has no `iw`, `wpa_supplicant`, `hostapd`, `hcitool` or `bluetoothctl` (BusyBox has
   none of them; `hciup` only switches HCI up/down). Association, scanning, an AP, pairing and BT traffic cannot be
   tested on this image. Whether to add them is an owner decision, **pending**. **[2026-10-20: owner decision taken;
   revision 3 adds `iw`, `wpa_supplicant`/`wpa_cli`, `btmgmt`, `hciconfig`, `hcitool` and the `wifi-connect`,
   `wifi-scan`, `bt-scan` helpers. On the unit: Wi-Fi scan and Bluetooth discovery (after `btmgmt le on`) VERIFIED;
   association, pairing and AP (no `hostapd`) still untested.]**
4. (Already recorded) `mfi-probe` fails on `flock -w`; the fix in ccpa_custom `2796253` needs a rootfs rebuild and
   `flash-rootfs` (`2026-10-20_baseline_rev2_kernel_rootfs.md`). **[2026-10-20: in the revision-3 image (B13) and
   VERIFIED on this unit: DeviceVersion 0x03, certificate length 945 B.]**

## Not tested

Wi-Fi association, scan, AP mode (`MWIFIEX_DRIVER_MODE`), throughput; Bluetooth pairing or any traffic beyond the
controller's HCI init; whether the module is really unpowered with `reg_wlan` off (only "no SDIO card" was seen);
RTL8822CS and RTL8822BS (no such unit on the bench).

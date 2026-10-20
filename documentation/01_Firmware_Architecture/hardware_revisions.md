# CPC200-CCPA Hardware Revisions (A15W)

The CPC200-CCPA is a single **model** sold across multiple **hardware revisions**. Two
physical A15W units have been observed directly; they differ in `hwVersion`, manufacture
date (`MFD`), `UUID`, MAC **and WLAN silicon** (Rev A Realtek RTL8822CS, Rev B NXP/Marvell IW416, SDIO card id
`0x9159`), while sharing the same product type (A15W) and firmware build (`2025.10.15.1127`).

> Provenance (corrected 2026-10-20): Rev A (WR2C, uuid `651ede98…`) is the unit of the telemetry / box-info JSON
> captures (`device_identification.md`, `ARMAndroidAuto.md`) and of the full NOR dumps `../../flash_dumps/2025.10.15.1127/`
> and `../../flash_dumps/2025.02.25.1521/` (E4 in `../05_Security_Analysis/kernel_encryption.md`: their update
> environments decrypt with this uuid). It is a **Realtek RTL8822CS** unit: `../../flash_dumps/README.md` calls those
> dumps Realtek, their rootfs ships `rtl8822_ko.tar.gz` and `rtlbt/rtl8822cs_*` and no IW416 driver set, and
> `../../flash_dumps/2026.06.07.ncm/` (same mtd0/mtd1 bytes) is recorded as an RTL8822CS adapter. Rev B (WN16, uuid
> `692173ca…`) is the IW416 bench unit E1: the OCOTP words in `hardware_platform.md` § Unit-Specific OCOTP Fuse Values,
> the flash backups and hardware runs in `../../custom/kernel_rootfs/` and the 2026-10-19 kernel work are this unit's. It
> was also observed on a **GM Info 3.7 (gminfo37)** head unit, Feb 2026, and migrated here from that platform's research.
> This page said both units were IW416 and that Rev A was "the unit documented throughout the rest of this repo".
> Items not independently confirmed against this repo's own firmware dumps are marked **(observed, not dump-confirmed here)**.

## Observed revisions

| Field | Rev A (existing in this repo) | Rev B (newly migrated) |
|-------|-------------------------------|------------------------|
| productType | A15W | A15W |
| boxType | YA | YA |
| hwVersion | `YMA0-WR2C-0003` | `YMA0-WN16-0003` |
| MFD | `20240119` | `2025-02-25` (box JSON `MFD`) |
| UUID | `651ede982f0a99d7f9138131ec5819fe` | `692173ca1d16c1d7767bb8ecfefd6672` |
| MAC | — (not recorded) | `00:E0:4C:91:B0:DF` (OUI `00:E0:4C` matches repo) |
| WLAN silicon | Realtek RTL8822CS (dump rootfs: `rtl8822_ko.tar.gz`; corrected 2026-10-20, said IW416) | NXP/Marvell IW416 (SDIO `0x9159`) |
| Firmware build | `2025.10.15.1127` | `2025.10.15.1127` |

Cross-reference for the WR2C identity values: `02_Protocol_Reference/device_identification.md`
(hwVersion/MFD), `06_Reference/binary_analysis/ARMAndroidAuto.md` (telemetry box block).

## Rev B (WN16) firmware/WLAN details not yet present elsewhere in this repo

These were captured from the WN16 unit and are **not** otherwise documented in this repo.
They are consistent with the IW416 WLAN branch already described in
`custom/firmware/2025.10.15.1127/NCM/scripts_changed/init_bluetooth_wifi.sh` /
`attach_bluetooth.sh` (SDIO id `0x9159`, BT fw `nxp/uartiw416_bt_v0.bin`), but add the
specific WLAN firmware version string and the WLAN firmware blob name/size:

- **WLAN firmware version string:** `SDIW416---16.92.21.p119.11-MXM5X16437.p20-GPL-(FP92)`
  — (observed, not dump-confirmed here). This is the IW416 driver/firmware banner; this
  repo currently documents the IW416 kernel-module load (`mlan.ko`/`moal.ko`,
  `iw416_ko.tar.gz`) but not this version banner.
- **WLAN firmware blob:** `nxp/sdioiw416_wlan_v0.bin`, **425,896 bytes**
  — (observed, not dump-confirmed here). Naming follows the same NXP pattern as the
  commented `sdiouart8987_combo_v0.bin` reference in this repo's scripts; the IW416 branch
  in `init_bluetooth_wifi.sh` was not seen to name this blob explicitly, so treat the exact
  filename/size as a field observation pending confirmation against a WN16 flash dump.
- **BT firmware:** `nxp/uartiw416_bt_v0.bin` — already documented in this repo
  (`attach_bluetooth.sh`), confirmed identical on the WN16 unit.

> For the IW416 **radio capabilities** (PHY ceiling, SoftAP hostapd `ht_capab` support
> matrix, measured link behavior, channel guidance), see `wifi_iw416_capabilities.md`
> — live-verified on hardware including this WN16 unit (`wlan0` MAC `00:E0:4C:91:B0:DF`).

## Notes on values that differ from this repo's Rev A captures

The following Rev B values are **unit-specific** and are expected to differ from the Rev A
captures already in this repo (they are not contradictions):
`hwVersion`, `MFD`, `UUID`, and `MAC`. Any tooling that keys on these for a *single* unit
should treat them per-revision. WiFi channel behavior (default SoftAP ch36; WiFi-Direct
`p2p_oper_channel` 149; current-firmware example 161) is documented in
`version_comparison.md` / `web_settings_reference.md` and is firmware/mode-driven, not a
per-revision hardware difference.

# CPC200-CCPA backup (20260708_042628_vanilla_state)

State: **VANILLA** — the clean owned base. Stock projection stack (riddleBox) removed;
Carlinkit cruft/latent-trigger scripts deleted; all remaining scripts owned, **dead-code-free
and syntax-clean** (`sh -n` all pass, zero dead references, zero dangling refs); early
self-respawning UART console (`::sysinit` before rcS, 115200); radios on-demand (IW416
wlan_on/bt_on, slim scripts); NCM always-on. No backup files reside in rootfs.
Device: A15W "carlink", NXP i.MX6UL, kernel 3.14.52, sw 2025.10.15.1127, iAP2 `serialNumber` 2025.02.25.1521626a (a firmware build string, not a device serial;
`documentation/01_Firmware_Architecture/version_comparison.md`).

## Files
- CPC200-CCPA_full_nor_16MB.bin : complete 16MB SPI NOR image (flash @ 0x000000), mtd0+mtd1+mtd2 — **kept local, not in this repo** (see below)
- mtd0.bin (uboot,  256K)  @ 0x000000
- mtd1.bin (kernel, 3328K) @ 0x040000
- mtd2.bin (rootfs, 12800K)@ 0x380000 — **kept local, not in this repo**
- rootfs.tar.gz : live jffs2 rootfs contents (top-level dirs; excludes /proc /sys /dev /tmp) — **kept local, not in this repo**

**Removed from the repo 2026-10-20 (owner decision): the three images that hold the rootfs embed
device credentials** (dropbear private host keys, root password hashes, Wi-Fi configs). They were
`git rm`'d here; earlier commits still contain them. Byte-identical local copies, same sha256:

| File | sha256 | Local copy |
|---|---|---|
| `CPC200-CCPA_full_nor_16MB.bin` | `edd024536c6f71d8038aa1c9be7fe6379610ba9486636e655fe058300c9fc761` | `~/Documents/carlink/carlinkit_misc/ccpa_backups/_removed_from_repo_2026-10-20/CPC200-CCPA_resources/flash_dumps/CCPA_stripped/` |
| `mtd2.bin` | `4250029cdf1edac27e47e101fd06aacec7ff2b5b2658ccb78a50cdd9ea1e32ea` | same folder |
| `rootfs.tar.gz` | `32b48dc174e0b1cbaa2bf5680a99271afc8a75f502cf738e7d5407d2b7ea7800` | same folder |

The same 07-08 archive was also kept at `~/Documents/carlink/carlinkit_misc/ccpa_backups/20260708_042628_vanilla_state/`.
`mtd0.bin`, `mtd1.bin` and `manifest.txt` stay here (no rootfs). A restore needs the local copies.
- manifest.txt  : device state at backup time (process list, /script, /usr/sbin, gadget/radios)
- SHA256SUMS

## Notes
- mtd0 (uboot) and mtd1 (kernel) are **bit-identical** to prior backups (HAB-signed U-Boot and
  kernel untouched by this pass) — verified by sha256. Both partitions are writable, and a kernel
  can be replaced through U-Boot's staging path; only the first 192 KB (three 64 KB blocks) of the
  kernel are per-chip DCP-encrypted (OTPMK-derived key), the rest is plain zImage. See
  `documentation/05_Security_Analysis/kernel_encryption.md`. *Corrected 2026-10-19, reworded in
  place 2026-10-20:* this said "OTPMK-encrypted kernel" and "immutable".
- Same unit as the IW416 bench adapter: this folder's `mtd0.bin`/`mtd1.bin` are the copies of
  `custom/kernel_rootfs/backups/20261019_IW416_ocbm_baseline_pre-livi/` (that folder's own copies were
  removed 2026-10-20 as byte-identical; its `SHA256SUMS` points here).
- mtd2 (rootfs) is the vanilla owned base (this pass's endpoint).
- What changed from stock: removed check_mfg_mode/check_log_size/init_bluetooth_wifi/
  close_bluetooth_wifi/start_iap2_ncm + riddle.conf; slimmed attach_bluetooth (IW416-only) and
  start_bluetooth_wifi (AP-only, wlan0-DHCP bug fixed); rewrote start_main_service (242->~55 lines,
  all projection/vendor launches removed); added early_console.sh (Lever 1); ownership headers +
  dead-line removal across the retained scripts.

## SPI programmer restore (Macronix MX25L12835F, 16MB SOP8)
Write CPC200-CCPA_full_nor_16MB.bin to chip offset 0x000000 (full-chip erase+program+verify).
Or per-region: mtd0->0x0, mtd1->0x40000, mtd2->0x380000.
Both use the local copies above (`CPC200-CCPA_full_nor_16MB.bin`, `mtd2.bin`); only `mtd0.bin`/`mtd1.bin` are in this folder.

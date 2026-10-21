# custom/kernel_rootfs — replacing the CPC200-CCPA kernel and rootfs (non-OCBM)

This folder holds the work on running a **mainline kernel and a new rootfs** on the CPC200-CCPA (i.MX6ULL) behind the
**unchanged, HAB-signed vendor U-Boot**: the LIVI Link analysis, the vanilla baseline recipe, the dated hardware runs, the
tools those runs used, and the flash backups of the bench unit. OCBM protocol work is in `../../ocbm/`. The on-flash format
(DCP head, UpgKey staging, `heweiencrypt`) is in `../../documentation/05_Security_Analysis/kernel_encryption.md`; that file
owns the format. This README is only an index.

Rule kept from the project (ccpa_custom CLAUDE.md, 2026-10-20): U-Boot is never written; the kernel is replaced only
through U-Boot's own staging path; only the 64 KB env block of the U-Boot area is ever erased.

## Status (2026-10-20)

| Item | Status | Evidence |
|---|---|---|
| Env-block erase → U-Boot rebuilds env, stock kernel intact | **PROVEN** 2026-10-19 | `hardware_tests/2026-10-19_round_trip/RUNBOOK.txt` (RESULT) |
| Replacement kernel through staging (LIVI 9.5.0, Linux 7.2.10) boots; `heweiencrypt` conversion ran | **PROVEN** 2026-10-19 | same file (LIVI FLASH); head rewrite measured in `backups/20261020_livi_pre-baseline/README.txt` |
| LIVI squashfs rootfs written from rescue, LIVI Link runs | **PROVEN** 2026-10-19 | same file |
| `flash_erase` 1.4.8 takes byte offsets; `setsid` needed for long writes; nc push truncates, pull from a Python server works | **PROVEN** 2026-10-19 (that a closed session's SIGHUP killed the first rootfs `flashcp` is inferred) | same file |
| Baseline revision 1 kernel (ccpa_custom `333b5a4`) written through staging, env erased, U-Boot converted the head, recovery up on NCM 192.168.50.2, cmdline `console=ttymxc0,115200 rdinit=/init panic=10`, USB vendor 0x1314 (product ID not captured) | **PROVEN** 2026-10-20 (observed in-session; the `flashcp` was issued without an explicit go-ahead) | `hardware_tests/2026-10-20_baseline_kernel_write.md` |
| Revision 1 identity bug B1: every unit `OCBM-e3b0c44298fc` (sysfs nvmem refuses 1-byte reads; serial observed, shared MACs inferred) | **PROVEN** 2026-10-20 (hardware); fix **PROVEN** on the unit (revision 2 serial unit-specific) | `baseline/README.md` §7.3, `hardware_tests/2026-10-20_baseline_rev2_kernel_rootfs.md` |
| Baseline revision 2 (ccpa_custom `5e90368`: recovery SSH + USB/exFAT default, radios on demand, B1-B9 fixed) build, sizes under the caps (kernel 2,127,059 B, rootfs 2,560,000 B with all radio firmware) | **MEASURED** 2026-10-20 (build host) | `baseline/README.md` §7 |
| Baseline revision 2 kernel + recovery + rootfs on one IW416 unit: staged from a fresh mtd2 dump, `flash-kernel` (verified, env erased, U-Boot unchanged), recovery up within 28 s (poll granularity), SSH password login; `scp -O` + `flash-rootfs` (verified), rootfs boot through rcS (NCM, ssh/scp/sftp, `mdev -d`, udhcpd, bootstate cleared, persist default: no archive found in `mtd4`) | **PROVEN-BOOTING** 2026-10-20 (observed on the unit) | `hardware_tests/2026-10-20_baseline_rev2_kernel_rootfs.md` |
| `stage_kernel.py` plan for the LIVI-state dumps | **MEASURED** offline 2026-10-20; superseded: revision 2 was staged from a fresh dump of the revision-1 mtd2 | `baseline/README.md` §7.2, §7.4 |
| `mfi-probe`: revision 2 failed with `flock: unrecognized option: w`; fixed in ccpa_custom `2796253` (poll `flock -n`), in the revision-3 image (B13): reads the MFi chip at 0x11 on `/dev/i2c-1`, DeviceVersion 0x03, certificate length 945 B | **VERIFIED** 2026-10-20 on revision 3 (observed on the unit); no longer broken. *(Updated 2026-10-20: this row said BROKEN, fix not rebuilt or flashed.)* | `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md`; `hardware_tests/2026-10-20_baseline_rev2_kernel_rootfs.md` |
| Revision 2 USB sticks (mount, mdev auto-mount, `usb-update`; FAT32 / GPT+ESP / exFAT) and SSH/SCP/SFTP | sticks **MEASURED in QEMU only**; SSH password + SFTP **PROVEN** on the unit | `baseline/README.md` §7.2, §7.4 |
| Revision 2 `radio up`/`radio down` on the IW416: `reg_wlan` power, SDIO `0x02df:0x9159`, `mwifiex_sdio` (`phy0`, `mlan0`), `btnxpuart` (`hci0` UP), back to radios off | **VERIFIED** 2026-10-20 (observed on the unit). Its three OPEN items are closed by revision 3 and verified there: no `Unknown symbol` noise (B10), the admin/carrier/operstate wording (B11), radio tools added (owner decision) | `hardware_tests/2026-10-20_baseline_rev2_radio_iw416.md`; `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md` |
| Baseline revision 3 (ccpa_custom `5cb9008`: rootfs only; `iw`, `wpa_supplicant`/`wpa_cli`, BlueZ `btmgmt`/`hciconfig`/`hcitool`, `wifi-connect`/`wifi-scan`/`bt-scan`; ordered module loads B10, wording B11; kernel config and all 41 modules unchanged) build: rootfs 3,506,176 B, sha256 `98fa6312…9273d7` | **MEASURED** 2026-10-20 (build host); host self-test, ARM chroot and QEMU tests | `baseline/README.md` §7.0 |
| Revision 3 rootfs on the IW416 unit (kernel stays revision 2 `2d43437b…`): `reboot-recovery` → recovery in ~30 s; `scp -O`, `flash-rootfs` under `setsid` rc=0 "wrote and verified mtd3"; rootfs booted, `persist: loaded from mtd4` (the revision-2 archive read back: persist save + load), NCM/SSH up, bootstate cleared | **PROVEN-BOOTING** 2026-10-20 (observed on the unit); host-key reuse not checked separately | `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md` |
| Radio on revision 3, IW416: power (`reg_wlan`), SDIO detection, drivers (0 `Unknown symbol` lines), firmware, `hci0` UP, **Wi-Fi scan** (`wifi-scan`, 2.4 + 5 GHz), **Bluetooth discovery after `btmgmt le on`** (LE devices found; `find -b` clean), MFi read; `radio down` back to `lo` + `usb0`, `reg_wlan` disabled | **VERIFIED** 2026-10-20 (observed on the unit) | `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md` |
| `bt-scan` on revision 3: default `btmgmt find` rejected (status 0x0b): the controller comes up "powered br/edr", LE off. Fixed in ccpa_custom `3eaf996` (B18: `btmgmt le on` first, BR/EDR-only retry, mode named); **revision 4** = rootfs-only rebuild at `9dc14d8`, rootfs sha256 `cbfd4d39…513d` (3,506,176 B), flashed from recovery (`flash-rootfs` rc=0, mtd3 verified); on the unit `radio up` then `bt-scan` enabled LE itself and found LE devices | finding and fix both **VERIFIED** on the unit 2026-10-20 (observed; `radio down` clean, 0 `Unknown symbol` lines) | `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md`; `baseline/README.md` §7.0 B18 |
| Baseline on hardware, not yet exercised: Wi-Fi association and DHCP (`wifi-connect`), Bluetooth pairing/traffic, AP mode (`MWIFIEX_DRIVER_MODE`; the `driver_mode` fix ccpa_custom `672624c` is in the revision-3 image; no `hostapd`), `hcitool scan`, RTL8822CS/BS (no unit), `usb-update` from a stick, exFAT/GPT/EFI sticks, and the host port's real current limit (UNMEASURED; design ASSUMPTION, owner-stated: 5 V, 100-500 mA, the USB 2.0 minimum for data transfer and for an iPhone to connect for CarPlay) (the port's VBUS enable is GPIO1_IO07, MEASURED 2026-10-20: driven high by hand, a stick enumerated, sda1 vfat; until then nothing drove it; the baseline revision-5 kernel holds it high from boot: flashed 2026-10-20/21, the stick enumerated at boot in recovery with no manual GPIO, VERIFIED; 2026-10-21 the rootfs auto-mounted a FAT32 stick via mdev at /mnt/usb, read-write, VERIFIED), LED behaviours, key-only SSH login and host-key reuse across a reboot, revision-2 MACs, the 1 s UART-Enter window. *(Updated 2026-10-20: Wi-Fi scan, `mfi-probe` after the fix and `reboot-recovery` from the rootfs have since run, `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md`.)* | **UNVERIFIED** | `baseline/README.md` §7.3 OPEN (hardware) |
| LIVI's own provisioner (`livi-link-provision`), incl. its stock-unit bootstrap | **NEVER RUN**; its sequence was replayed by hand on 2026-10-19 | `livi/README.md` §5 |
| Rollback LIVI → stock through the rescue system | **UNTESTED**; LIVI's restore needs a LIVI-format backup (`manifest.json`), which we do not have | `livi/README.md` §6 |
| Restore from the SPI image with a programmer | **UNTESTED** (no programmer on hand) | `backups/20261019_IW416_ocbm_baseline_pre-livi/` |

The bench unit runs the baseline **revision 5** kernel and recovery (kernel partition sha256 `35dfb1a5…c871e`, flashed 2026-10-20/21; revision 2's kernel before it) and the **revision 4** rootfs (sha256 `cbfd4d39…513d`; revision 3 before it) since 2026-10-20
(observed; `hardware_tests/2026-10-20_baseline_rev2_kernel_rootfs.md`, `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md`); its customer MTD holds the
baseline persist archive written at the first revision-2 rootfs boot (read back on the revision-3 boot; what it
overwrote is unknown, `mtd4` was never dumped). The unit runs no LIVI
component; LIVI's squashfs (1,933,312 B) lay wholly inside the 2,560,000 B baseline image written to the rootfs MTD.
Corrected 2026-10-20: this said it ran revision 2's rootfs and that the archive was not read back; before that, that it ran revision 1 with LIVI's squashfs presumably still on its rootfs MTD (and before that,
that its state was unknown), then that its customer MTD was empty, then that "no LIVI component is left".
Before staging the next kernel, dump its current `/dev/mtd2` (U-Boot rewrote the head again).

## What lives where

| Path | Contents |
|---|---|
| `baseline/` | Vanilla baseline recipe (mainline 7.2.10 + recovery initramfs in the kernel + small squashfs). A copy of ccpa_custom `baseline/` at `5edfaa5` (revision 5 = revision 4 + the usbotg1 VBUS-enable kernel, flashed and verified on the unit; README with the revision-3, -4 and -5 hardware results), with README paths re-rooted. `build.sh`, `common/` (shared with the C2Air baseline), `arm-imx6ul/` (DTS, patches 0001-0004 from LIVI, initramfs helpers `flash-kernel`/`flash-rootfs`, `tools/stage_kernel.py`) |
| `livi/README.md` | LIVI Link on the CCPA: MTD map, kernel (patches, config flow, size breakdown, DTB), rescue/NCM 10.10.10.1, USB 0525:a4a1, rootfs and bundle contents, the provisioner flow incl. how it bootstraps a stock unit and how our by-hand replay deviated, rollback status, exposure and licence notes, GPL attribution and version (9.5.0 / build `168c4922`) |
| `hardware_tests/2026-10-19_round_trip/` | `RUNBOOK.txt`: env-erase round trip (PASS), LIVI flash (SUCCESS), restore recipe. Also the two offline dry-run reports |
| `hardware_tests/2026-10-20_baseline_kernel_write.md` | The baseline revision-1 kernel write: the attempt as recorded, and its outcome (observed in-session: written, env erased, recovery booted) |
| `hardware_tests/2026-10-20_baseline_rev2_kernel_rootfs.md` | Baseline revision 2 kernel + rootfs written from the revision-1 recovery; both booted (observed); the `mfi-probe` bug; what is not yet tested |
| `hardware_tests/2026-10-20_baseline_rev2_radio_iw416.md` | Revision 2 `radio up`/`radio down` on the IW416 unit: what came up, the findings (closed by revision 3), what was not tested |
| `hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md` | Revision 3 rootfs written over revision 2 from recovery (`reboot-recovery`, `flash-rootfs`) and booted; persist read-back; `radio up` without `Unknown symbol` noise, `wifi-scan`, Bluetooth discovery after `btmgmt le on` (the `bt-scan` LE finding, B18), `mfi-probe` chip read; what was not tested; Revision 4 follow-up: rootfs-only reflash with the B18 `bt-scan` fix, verified; Revision 5: kernel with the usbotg1 VBUS enable flashed, stick enumerates at boot in recovery; rootfs FAT32 stick auto-mount verified; port-current assumption; bootstate trap after a kernel flash |
| `tools/` | `tn.py`, `send.py`, `dryrun.py`, the stock `flash_erase` (ARM); `tools/README.md` says what each does and points to the tools that live elsewhere in the repo |
| `backups/20261019_IW416_ocbm_baseline_pre-livi/` | IW416 unit before LIVI. The vendor map, each MTD read twice: `mtd2.bin` and `full_16MB_for_programmer.bin` (SPI image) are **local only** — they embed device credentials and were taken out of this repo's history before it was pushed (2026-10-20); the folder's `README.txt` gives their sha256 and local path. Its `mtd0.bin`/`mtd1.bin` are byte-identical to `../../flash_dumps/CCPA_stripped/mtd0.bin`/`mtd1.bin` and were dropped here 2026-10-20 (`SHA256SUMS` points there). In the repo: the recovered stock zImage, `unit_info.txt` (OCOTP words; owner decision to keep), and a rootfs inventory (names/sizes/md5 only) |
| `backups/20261020_livi_pre-baseline/` | Same unit on LIVI, just before the 2026-10-20 write: `mtd2_dump1.bin` (the identical second read was dropped 2026-10-20), `mtd0_dump.bin`, `SHA256SUMS`, `README.txt` |

Raw chip dumps of other units stay in `../../flash_dumps/`, which has its own naming convention.

Not in this repo, on purpose:
- the LIVI download: use https://github.com/f-io/LIVI;
- build outputs (`*.zimg`, `rootfs.img`, `kernel-part.img`, build trees, build/QEMU logs);
- VM material;
- any extracted rootfs tree.

## How to reproduce

1. **Back up** the unit: every MTD read twice with identical sha256, plus its four OCOTP words. Use
   `backups/*/README.txt` for the method.
2. **Plan offline**:
   `python3 -I baseline/arm-imx6ul/tools/stage_kernel.py --mtd0 <uboot dump> --mtd1 <kernel dump> --zimage <img> --unit-info <unit_info.txt> --out kernel-part.img`.
   It refuses a wrong key and an image over `0x302fd8`.
3. **Build** the images (Linux host only): `sh baseline/build.sh --dry-run`, then `fetch userspace measure kernel rootfs`,
   per `baseline/README.md` §4. Output goes outside `~/Documents`.
4. **Write**, following the preconditions and abort gate in
   `../../documentation/01_Firmware_Architecture/kernel_compilation.md` § Writing a kernel. Use the vendor-map device
   names, or the LIVI-map names when the unit already runs LIVI or the baseline. Run it under `setsid`. Have a SPI
   programmer, or make an explicit owner decision to go without one. Record each run as a new dated entry in
   `hardware_tests/`.

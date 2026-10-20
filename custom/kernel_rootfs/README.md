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
| `flash_erase` 1.4.8 takes byte offsets; `setsid` needed for long writes; nc push truncates, pull works | **PROVEN** 2026-10-19 | same file |
| Baseline kernel + rootfs build, sizes under the caps | **MEASURED** 2026-10-20 (build host) | `baseline/README.md` §7 |
| Baseline boots to its recovery shell | **MEASURED in QEMU only** (`mcimx6ul-evk`, not the board) | `baseline/README.md` §7.2 |
| `stage_kernel.py` plan for the LIVI-state unit (head unchanged, 1,402,593 B headroom) | **MEASURED** offline 2026-10-20 | `hardware_tests/2026-10-20_baseline_kernel_write.md` |
| Baseline kernel partition write to the bench unit | **OPEN**: `flashcp` issued, outcome unconfirmed, env not erased, no reboot | `hardware_tests/2026-10-20_baseline_kernel_write.md` |
| Baseline on hardware (NCM, QSPI, OCOTP identity, rootfs boot, USB host) | **OPEN** | `baseline/README.md` §7 OPEN (hardware) |
| Rollback LIVI → stock through the rescue system | **UNTESTED** | `livi/README.md` §6 |
| Restore from the SPI image with a programmer | **UNTESTED** (no programmer on hand) | `backups/20261019_IW416_ocbm_baseline_pre-livi/` |

The bench unit's state at the time of writing is **unknown**. It ran LIVI, and a baseline kernel write may have changed
`/dev/mtd2`. Read `hardware_tests/2026-10-20_baseline_kernel_write.md` before you power-cycle it or touch it.

## What lives where

| Path | Contents |
|---|---|
| `baseline/` | Vanilla baseline recipe (mainline 7.2.10 + recovery initramfs in the kernel + minimal squashfs). A copy of ccpa_custom `baseline/` at `333b5a4`, with README paths re-rooted. `build.sh`, `common/` (shared with the C2Air baseline), `arm-imx6ul/` (DTS, patches 0001-0004 from LIVI, initramfs helpers `flash-kernel`/`flash-rootfs`, `tools/stage_kernel.py`) |
| `livi/README.md` | LIVI Link on the CCPA: MTD map, kernel size against the cap, rescue/NCM 10.10.10.1, USB 0525:a4a1, provisioner flow, rootfs, rollback status, GPL attribution and version (9.5.0 / build `168c4922`) |
| `hardware_tests/2026-10-19_round_trip/` | `RUNBOOK.txt`: env-erase round trip (PASS), LIVI flash (SUCCESS), restore recipe. Also the two offline dry-run reports |
| `hardware_tests/2026-10-20_baseline_kernel_write.md` | The OPEN baseline kernel write attempt and the read-only next step |
| `tools/` | `tn.py`, `send.py`, `dryrun.py`, the stock `flash_erase` (ARM); `tools/README.md` says what each does and points to the tools that live elsewhere in the repo |
| `backups/20261019_IW416_ocbm_baseline_pre-livi/` | IW416 unit before LIVI. The vendor map, each MTD read twice: `mtd0/1/2.bin`, `full_16MB_for_programmer.bin` (SPI image), the recovered stock zImage, `unit_info.txt` (OCOTP words; owner decision to keep), and a rootfs inventory (names/sizes/md5 only) |
| `backups/20261020_livi_pre-baseline/` | Same unit on LIVI, just before the 2026-10-20 write: `mtd2_dump1/2.bin` (identical), `mtd0_dump.bin`, `SHA256SUMS`, `README.txt` |

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

# LIVI Link on the CPC200-CCPA (i.MX6ULL) — analysis

LIVI Link is the dongle firmware of **LIVI** (https://github.com/f-io/LIVI, **GPL-3.0-or-later**, `LICENSE` and
`package.json` `"license"` there; dongle documentation: `LIVI-LINK.md` in that repository). Credit for the boot flow,
kernel staging, MTD map, rescue system and provisioner described here belongs to the LIVI authors. Nothing of LIVI is
copied into this repository; paths below are paths inside the LIVI repository.

Version analysed: LIVI **9.5.0**, firmware `imx6ul_iw416` **build `168c4922`** (`assets/livi-link/imx6ul_iw416/firmware.json`:
file `livi-link-imx6ull.lfwb`, 5,058,338 B, sha256 `8c55db5e89c6f187…`). `build` is `git rev-parse --short=8 HEAD` of the
LIVI tree that built it (`scripts/livi-link/version.sh:4`), so `168c4922` is a LIVI commit. The source read for this note was a
zip download without `.git`; that its tree equals commit `168c4922` is UNVERIFIED.

Status labels: **PROVEN** = run on the IW416 bench unit and recorded (`../hardware_tests/`); **SOURCE** = read in LIVI's code,
not executed by us; **OPEN/UNTESTED** = neither.

## 1. Flash map (LIVI DTB) — PROVEN

`scripts/livi-link/arm/imx6ul/imx6ull.dts:180-215`; the same map read live from `/proc/mtd` on 2026-10-19 and 2026-10-20.
The baseline (`../baseline/`) keeps it unchanged.

| LIVI MTD | Name | Flash range | Size | Notes |
|---|---|---|---|---|
| mtd0 | `uboot` (read-only) | 0x000000-0x02FFFF | 0x30000 | U-Boot, its signature, update block (update env at +0x20000) |
| mtd1 | `env` | 0x030000-0x03FFFF | 0x10000 | erasing it makes U-Boot convert the staged kernel head on the next boot |
| mtd2 | `kernel` | 0x040000-0x37FFFF | 0x340000 | DCP head 0x30000 + plain body; U-Boot reads 0x302fd8 B; staging blocks at +0x302fd8 |
| mtd3 | `rootfs` | 0x380000-0xFDFFFF | 0xc60000 | squashfs |
| mtd4 | `customer` | 0xFE0000-0xFEFFFF | 0x10000 | livid settings |
| mtd5 | `bootstate` | 0xFF0000-0xFFFFFF | 0x10000 | `LIVIBOOT` marker |

The vendor map is uboot 0x40000 / kernel 0x340000 / rootfs 0xc80000 (`../../../documentation/01_Firmware_Architecture/flash_layout.md`).
Kernel device is **mtd1 on vendor firmware, mtd2 under LIVI or the baseline**; the env block is inside vendor mtd0 at 0x30000.

## 2. Kernel — PROVEN

- Mainline Linux 7.2.10 (`uname`: `#1 PREEMPT Sat Oct 17 02:36:22 UTC 2026`), zImage with appended DTB (`ARM_APPENDED_DTB`,
  `scripts/livi-link/arm/imx6ul/build.sh:81`); cmdline `console=ttymxc0,115200 rdinit=/init mwifiex.driver_mode=2`.
- Size **3,124,994 B** against the cap **0x302fd8 = 3,157,976 B** (32,982 B spare): `KERNEL_MAX` `board.sh:38`, size check
  `build.sh:268-269`, measured in `../hardware_tests/2026-10-19_round_trip/livi_9.5.0_iw416_dryrun_report.txt`.
- Installed through the vendor U-Boot's own staging path (`heweiencrypt`): body in plain, head UpgKey-encrypted into the
  staging blocks, env erased. Format and key: `../../../documentation/05_Security_Analysis/kernel_encryption.md`.
  On-flash evidence (2026-10-20 dump vs stock): head 195,801 B rewritten, body/staging differ exactly as planned
  (`../backups/20261020_livi_pre-baseline/README.txt`).

## 3. Rescue initramfs (inside the kernel) — PROVEN for the network side

- PID 1 `scripts/livi-link/common/initramfs/init`: mounts the `rootfs` squashfs and `switch_root`s only if
  `/usr/bin/livid` is executable there (`init:37,57`); marks the rootfs boot with `printf LIVIBOOT` on `bootstate`
  (`init:53`), cleared by the rootfs `rcS` once it is up. A marked or unusable rootfs → rescue.
- Rescue network: `br0` 10.10.10.1/24, DHCP pool 10.10.10.100-199 (`init:66-69`), `telnetd` on :23 and :2323 (`init:4,76`),
  unauthenticated. Seen 2026-10-19 (`RUNBOOK.txt`): shell on :23/:2323, host got 10.10.10.100. `LIVI-LINK.md:87-89`: up to
  15 s until reachable.
- USB gadget (`scripts/livi-link/common/initramfs/net-up:14-22`): **0525:a4a1** NCM (0525:a4a7 for ACM), manufacturer
  `LIVI`, product `LIVI Link`, first UDC. Seen 2026-10-19: `0525:a4a1` "LIVI Link".
- Two NCM devices on one Mac both answering 10.10.10.1 (this CCPA and a C2Air on LIVI, 2026-10-20 bench): connect with the
  socket bound to one interface — `../tools/tn.py` with `BOUND_IF=<iface>`. That the C2Air uses the same address follows from
  the shared `scripts/livi-link/common/` (INFERRED) and was seen on the bench.

## 4. Rootfs — PROVEN

squashfs, xz, `-all-root -no-xattrs` (`scripts/livi-link/common/build-rootfs.sh:65`); `imx6ul_iw416` image **1,933,312 B**
(4 KiB multiple, fits 0xc60000; dry-run report). Running: `/dev/mtdblock3` squashfs ro, 1920 KB, 100 % used; services
livi-netd, httpd, ledd, mfid, wifid, btd, accessoryd + hostapd; http://10.10.10.1/ → 200 "LIVI Link"; :22 closed (`RUNBOOK.txt`).

## 5. Provisioner flow (`livi-link-provision`) — SOURCE; the vendor-unit sequence was replayed BY HAND on 2026-10-19

`native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/mod.rs:68-104` (`install`), from vendor firmware:

1. **Backup** every MTD to the host (`mtd.rs:102`; stored under `~/Library/Application Support/LIVI/backup/dongle-backup/`
   on macOS, `LIVI-LINK.md:44-46`).
2. **Plan** the kernel partition from the unit's dumps (`boot.rs:132` `prepare`; decrypts the update env with the unit's
   UpgKey, `imx6ul-uboot/src/lib.rs` `layout()`).
3. **Write kernel** partition, `sha256sum` it, **erase env** block only (`flash_erase <uboot dev> {ENV_BLOCK} 1` on the vendor map, `boot.rs:224`),
   check U-Boot unchanged, **reboot**, wait, check U-Boot rewrote env (`boot.rs:181-262`).
4. Require **rescue** (`mod.rs:90-94`: refuses otherwise).
5. **Write rootfs**: `flashcp`, `dd | sha256sum` check, **clear bootstate** with `flash_eraseall -q` (`boot.rs:57-126`).
6. Reboot into LIVI Link (`mod.rs:145-147`).

From a unit already on LIVI it first sets `LIVIBOOT` and reboots to rescue (`mod.rs:122-131`). The by-hand replay on
2026-10-19 used `flash_erase /dev/mtd1 0 0; cat img > /dev/mtd1` for step 3 and pulled the rootfs from the host because an
nc push truncated at ~146 KB (three times); the first rootfs `flashcp` was killed by SIGHUP when the telnet session
closed — run every long write under `setsid` and poll a log (`RUNBOOK.txt`).

## 6. Back to stock — UNTESTED

LIVI's own path: `back_to_stock` (`mod.rs:106-118`) → rescue → `restore.rs:133` `write` (vendor backup written back
from the rescue system), `LIVI-LINK.md:82-83`. Never run on our unit. The manual steps, written from the same map, are
owned by `../../../documentation/01_Firmware_Architecture/kernel_compilation.md` § Getting back from LIVI [UNTESTED] and
are not restated here; the SPI
image is `../backups/20261019_IW416_ocbm_baseline_pre-livi/full_16MB_for_programmer.bin` (no programmer restore has been run).

## 7. What the baseline changes

`../baseline/README.md` §6 (table "Changes against LIVI, and why"). It keeps LIVI's map, kernel version, board patches
0001-0004 and staging flow; it drops the radio, AP, web UI and daemons and moves the network to 192.168.50.2.

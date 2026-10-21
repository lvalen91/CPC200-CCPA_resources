# 2026-10-20 — baseline revision 3 rootfs on the IW416 unit: install, boot, radio tools, MFi read

**Outcome:** the baseline **revision 3** rootfs (ccpa_custom `5cb9008`) was written over revision 2 from the
recovery and booted; the revision-2 kernel stayed (revision 3 is rootfs-only: kernel config unchanged, all 41 modules
byte-identical, `../baseline/README.md` §7.0). On it, `radio up` loaded the IW416 drivers with no `Unknown symbol`
noise, `wifi-scan` listed networks on both bands, Bluetooth discovery worked once LE was switched on, and `mfi-probe`
read the MFi chip. Observed on the unit, 2026-10-20. One finding: `bt-scan`'s default find is rejected because the
controller comes up with LE off (fixed in the tree afterwards, B18; superseded by revision 4, which carries the fix and is verified, see "Revision 4 follow-up").

Unit: the IW416 bench adapter (`../backups/20261019_IW416_ocbm_baseline_pre-livi/`). Kernel: revision 2's `-iw416`
image (`2d43437ba38ad19bc94313cf576e2b95b91bbb91e28094498cdaa99c2c345c17`, unchanged). Rootfs written:
`rootfs.img` 3,506,176 B, sha256 `98fa6312a53d9f19f4a3282a93bddee5e01e2b0971d75bbc9da361b35a9273d7`. The previous
state of the unit is in `2026-10-20_baseline_rev2_kernel_rootfs.md` and `2026-10-20_baseline_rev2_radio_iw416.md`.
Scripts: `../baseline/arm-imx6ul/rootfs/usr/sbin/` (`radio`, `wifi-scan`, `bt-scan`, `mfi-probe`). No network name,
BSSID or Bluetooth address is recorded here.

## Install (`../baseline/README.md` §5 step 6)

| Step | Result |
|---|---|
| From the running revision-2 rootfs: `reboot-recovery` | recovery up in **~30 s**; `/etc/baseline/recovery` present (exists only in recovery), `/proc/cmdline` with `panic=10` |
| `scp -O rootfs.img` into recovery's `/tmp` | sha256 checked on the unit: the value above |
| `flash-rootfs /tmp/rootfs.img <sha256>` under `setsid` | rc=0, "wrote and verified mtd3"; bootstate cleared |
| `reboot` | **revision-3 rootfs booted** |

## Observed on the revision-3 rootfs

| Item | Result |
|---|---|
| rcS persist | `persist: loaded from mtd4`: the archive revision 2's first boot saved to the customer MTD survived a reboot (save and load **VERIFIED**; whether the host key in it was reused was not checked separately); `persist: root password = build default` |
| rcS rest | NCM and SSH up; bootstate cleared |
| New tools present | `iw`, `wpa_supplicant`, `wpa_cli`, `btmgmt`, `hciconfig`, `hcitool`, `wifi-connect`, `wifi-scan`, `bt-scan`, `mfi-probe`, `radio` |
| `radio up` | **0** `Unknown symbol` lines in `dmesg` (B10, dependency-ordered `insmod`); Wi-Fi line "mlan0 administratively up, no carrier (operstate down)" (B11 wording); `hci0` UP |
| `wifi-scan` | many networks listed, on 2.4 GHz and 5 GHz |
| `mfi-probe` | the MFi chip at 0x11 on `/dev/i2c-1`: DeviceVersion (reg 0x00) = 0x03, certificate length (reg 0x30) = 945 B. The revision-2 failure (`flock: unrecognized option: w`) is gone (B13, `flock -n` poll) |
| `bt-scan` (revision-3 script) | `btmgmt find` → `Unable to start discovery. status 0x0b (Rejected)`. The controller's settings after `radio up`: `powered br/edr` only, LE not enabled |
| `btmgmt le on`, then `btmgmt find` | LE devices found |
| `btmgmt find -b` (BR/EDR only) | discovery started and stopped cleanly; no devices in 14 s |
| `radio down` | back to `lo` and `usb0` only; `reg_wlan` disabled |

Status by step: rootfs-only install from recovery, `reboot-recovery` from the rootfs, persist archive save and load
across reboots, dependency-ordered module loads (B10), the interface wording (B11), Wi-Fi scan, Bluetooth discovery
**after `btmgmt le on`**, MFi chip read (DeviceVersion, certificate length), `radio down` — **VERIFIED on hardware**.

## Found

1. **`bt-scan`'s default find is rejected.** `radio up` leaves the controller "powered br/edr" (LE off), and the
   kernel refuses an interleaved (BR/EDR + LE) find then: status 0x0b. Fixed in ccpa_custom after revision 3 (B18,
   `../baseline/README.md` §7.0 and §2.5): unless `-b`, `bt-scan` reads `btmgmt info`, runs `btmgmt le on` when LE is
   off (BR/EDR only when the controller has no LE or LE does not come on; `-l` then exits 1), retries a refused
   interleaved find with `-b`, and names the mode that ran. Host self-test only at the time; **superseded by revision 4** (rebuilt, flashed, verified on the unit: "Revision 4 follow-up"). The workaround while on revision 3 was `btmgmt le on` before `bt-scan`, or `bt-scan -b`.

## Not tested

Wi-Fi association (`wifi-connect`) and DHCP over Wi-Fi; Bluetooth pairing or traffic; AP mode
(`MWIFIEX_DRIVER_MODE`); `hcitool scan`; USB sticks: GPT with an EFI system partition, GPT with the backup header at the true disk end, unpartitioned (superfloppy) sticks, hot-plug of exFAT sticks and `usb-update` from a stick (FAT32/exFAT x MBR/GPT single-partition since verified, Revision 5 below); LED behaviours; key-only SSH
login; host-key reuse from the persist archive; the 1 s UART-Enter window into recovery; (B18's `bt-scan`: superseded by revision 4, tested below);
RTL8822CS/BS (no such unit).

## Revision 4 follow-up (2026-10-20)

Rootfs-only rebuild of the revision-3 sources at ccpa_custom `9dc14d8` (includes the B18 `bt-scan` fix): `rootfs.img`
3,506,176 B (same size, 9,469,952 B free), sha256 `cbfd4d3943a1352ff2ef279f4800ed5efb2def933a2d1f884f425fd4705e513d`;
the image's `usr/sbin/bt-scan` equals the tree file. Kernel not rebuilt or reflashed (kernel partition unchanged). This
is the unit's current rootfs; the revision-3 sha above is its predecessor. Flashed from recovery (`reboot-recovery`,
`scp -O` to `/tmp`, `flash-rootfs`: wrote and verified mtd3, bootstate cleared, rc=0), reboot: the unit came back on
NCM with the new `/etc/baseline-release`.

`radio up`, then `bt-scan`: "LE was off (settings: powered br/edr); enabled it (`btmgmt le on`, on until `radio
down`)", then "`btmgmt find` (BR/EDR and LE), at most 15 s", then a device table with many LE devices (none recorded
here). **B18 VERIFIED on hardware.** `radio down` clean; 0 `Unknown symbol` dmesg lines. Revision 3 to revision 4
differs only by the `bt-scan` change (and the rootfs build stamp). Still untested: see "Not tested" above, minus B18.

## Revision 5 (2026-10-20/21): kernel with the usbotg1 VBUS enable

Kernel-only rebuild (ccpa_custom `4d706ab`, `../baseline/README.md` §7.0b): the DT gives usbotg1 a `vbus-supply`
(fixed regulator on GPIO1_IO07, on from boot). Before the flash, with the revision-2 kernel and the revision-4 rootfs,
driving GPIO1_IO07 high by sysfs made the female port enumerate a FAT32 stick (sda1); GPIO1_IO06 did nothing.

Staged with `stage_kernel.py` from two identical dumps of the old kernel partition (sha256
`58b20d776149fcb295fa42a278a29c5f7ada7499fb89f4201e166b6a1bc503d8`; head unchanged) and the `-iw416` image
(2,130,329 B, sha256 `3b79c5b62925482ff6a4b6d210d3e51e6a3746e5e9e99af79427e26ad4f25fdc`); staged partition sha256
`35dfb1a55292f079bbae397ef59e771ede05edddbfbc0b5e2f750204f17c871e` (the value now on the unit; the write was verified). From recovery: `NO_REBOOT=1 flash-kernel
<host>:<port> <sha256>` wrote and verified mtd2, erased the env, left U-Boot unchanged (sha256 `c60054ca…` before
and after); reboot. The unit came back in recovery at its NCM address with the new build stamp;
`/sys/class/regulator` shows `usb_otg1_vbus`; **the stick enumerated at boot with no manual GPIO** (3.9 GB disk, one
partition: **port VBUS VERIFIED on hardware**). Recovery auto-mounted it read-write, so a stick's contents are at risk
in recovery (remount read-only by hand if it must not change).

The kernel partition now holds `35dfb1a5…c871e` (revision 2's kernel `2d43437b…` and revision 1's are superseded);
the rootfs is still revision 4 (`cbfd4d39…513d`). 

### Rootfs follow-up (2026-10-21, IW416 unit, kernel revision 5 + rootfs revision 4)

Booted with a FAT32 stick (MBR, 3.75 GiB, one partition) plugged in: the stick enumerated at 1.1 s (usb 1-1,
high-speed), sda1 appeared at 2.4 s, mdev ran `usb-mount`: "usb-mount: /dev/sda1 (fat32, partition 1, mbr:0b) mounted
read-write at /mnt/usb"; the contents listed (19 top-level entries); no `Unknown symbol` dmesg lines. It mounts
read-write by default (the owner remounted it read-only by hand; nothing was written). **Rootfs mdev auto-mount of
FAT32 VERIFIED on hardware**, in recovery (earlier) and in the rootfs.

Boot-loop guard trap: after the kernel flash the guard still held the mark from the preceding `reboot-recovery`, so
the first plain `reboot` stayed in recovery until `flash_eraseall -q /dev/mtd5` cleared bootstate. `flash-rootfs`
clears it; `flash-kernel` does not (open item, documented in `../baseline/README.md` §7.0b).

Port current: ASSUMPTION (owner-stated design requirement, NOT measured): 5 V, 100-500 mA, the USB 2.0 minimum for
data transfer and for an iPhone to connect for CarPlay. The real limit remains unmeasured. Still untested: bootstate clearing in `flash-kernel`, LEDs, Wi-Fi association.

### USB stick layout matrix (2026-10-21, same unit and images)

Layout matrix (2026-10-21, kernel revision 5 + rootfs revision 4, IW416 unit, one 64 GB stick overwritten with four 200 MB single-partition images built on the Mac with hdiutil: FAT32/MBR (0x0b), FAT32/GPT, exFAT/MBR (0x07), exFAT/GPT; the GPT images carry one basic-data partition, a2a0d0eb-e5b9-3344-87c0-68b6b72699c7, NO EFI system partition, and their backup header sits at the image end, not the disk end). Per layout: image written from the host over nc to /dev/sda, readback sha256 of the first 200 MB matched, `blockdev --rereadpt`, partition node appeared, `usb-mount` classified it correctly (fat32 mbr:0b, fat32 gpt:a2a0..., exfat mbr:07, exfat gpt:a2a0...) and mounted it read-write (vfat resp. exfat kernel driver), an 8 MiB random write + drop_caches + read-back sha256 MATCHED, and `usb-mount -u` was clean. **FAT32 and exFAT x MBR and GPT (single data partition) VERIFIED on hardware.** Also: hot-plug of the 64 GB FAT32 stick auto-mounted via mdev; a `--rereadpt` also triggered an mdev auto-mount; throughput (rough, includes sha): 32 MiB write 8.6 MB/s then 20 MB/s, 32 MiB read-back ~5 s. NOT tested: GPT with an EFI system partition ahead of the data partition, GPT with the backup header at the true disk end, an unpartitioned (superfloppy) stick, hot-plug of exFAT sticks (only rereadpt-triggered mdev), `usb-update` from a stick, RTL units.

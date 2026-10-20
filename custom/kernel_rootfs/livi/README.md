# LIVI Link on the CPC200-CCPA (i.MX6ULL) — analysis

LIVI Link is the dongle firmware of **LIVI** (https://github.com/f-io/LIVI, **GPL-3.0-or-later**, `LICENSE` and
`package.json` `"license"` there; dongle documentation: `LIVI-LINK.md` in that repository). Credit for the boot flow,
kernel staging, MTD map, rescue system and provisioner described here belongs to the LIVI authors. Nothing of LIVI is
copied into `livi/`; paths below are paths inside the LIVI repository. Elsewhere in this repository `../baseline/` does
carry LIVI material: kernel patches 0001-0004 unchanged (a header added) and files derived from LIVI (`flash-kernel`,
`flash-rootfs`, `initramfs/init`, `tools/stage_kernel.py`, `dts/radio-*.dtsi` and others), each with a header naming its
LIVI source (`../baseline/README.md` §8). *(Corrected 2026-10-20: this said nothing of LIVI is copied into this repository.)*

Version analysed: LIVI **9.5.0**, firmware `imx6ul_iw416` **build `168c4922`** (`assets/livi-link/imx6ul_iw416/firmware.json`:
file `livi-link-imx6ull.lfwb`, 5,058,338 B, sha256 `8c55db5e89c6f187…`). `build` is `git rev-parse --short=8 HEAD` of the
LIVI tree that built it (`scripts/livi-link/version.sh:4`), so `168c4922` is a LIVI commit. The source read for this note was a
zip download without `.git`; that its tree equals commit `168c4922` is UNVERIFIED.

Status labels: **PROVEN** = run on the IW416 bench unit and recorded (`../hardware_tests/`); **SOURCE** = read in LIVI's code,
not executed by us; **IMAGE** = measured in the shipped 9.5.0 bundle (2026-10-20 analysis); **INFERRED**; **OPEN/UNTESTED**.

**The bench unit no longer runs LIVI** (2026-10-20): the baseline kernel replaced LIVI's on `mtd2`, the baseline rootfs
replaced LIVI's on `mtd3`, and the baseline rootfs's first boot saved its persist archive over whatever `customer` held (never dumped)
(`../hardware_tests/2026-10-20_baseline_*.md`). LIVI's state is kept only as the dump in `../backups/20261020_livi_pre-baseline/`
(kernel + uboot partitions; LIVI's rootfs and customer partitions were not dumped).

## 1. Flash map (LIVI DTB) — PROVEN

`scripts/livi-link/arm/imx6ul/imx6ull.dts:177-216`; the same map read live from `/proc/mtd` on 2026-10-19 and 2026-10-20.
The baseline (`../baseline/`) keeps it unchanged.

| LIVI MTD | Name | Flash range | Size | Notes |
|---|---|---|---|---|
| mtd0 | `uboot` (read-only) | 0x000000-0x02FFFF | 0x30000 | U-Boot, its signature, update block (update env at +0x20000) |
| mtd1 | `env` | 0x030000-0x03FFFF | 0x10000 | erasing it makes U-Boot convert the staged kernel head on the next boot |
| mtd2 | `kernel` | 0x040000-0x37FFFF | 0x340000 | DCP head 0x30000 + plain body; U-Boot reads 0x302fd8 B; staging blocks at +0x302fd8 |
| mtd3 | `rootfs` | 0x380000-0xFDFFFF | 0xc60000 | squashfs |
| mtd4 | `customer` | 0xFE0000-0xFEFFFF | 0x10000 | livid settings (an `LVCF` blob, IMAGE) |
| mtd5 | `bootstate` | 0xFF0000-0xFFFFFF | 0x10000 | `LIVIBOOT` marker |

The vendor map is uboot 0x40000 / kernel 0x340000 / rootfs 0xc80000 (`../../../documentation/01_Firmware_Architecture/flash_layout.md`).
Kernel device is **mtd1 on vendor firmware, mtd2 under LIVI or the baseline**; the env block is inside vendor mtd0 at 0x30000.

## 2. Kernel — PROVEN (boots); details SOURCE / IMAGE

- Mainline Linux 7.2.10 (`uname`: `#1 PREEMPT Sat Oct 17 02:36:22 UTC 2026`), zImage with appended DTB (`ARM_APPENDED_DTB`,
  `scripts/livi-link/arm/imx6ul/build.sh:81`); cmdline `console=ttymxc0,115200 rdinit=/init mwifiex.driver_mode=2`
  (`imx6ull-iw416.dtsi:10`; the board DTS alone has no `mwifiex.` argument, `imx6ull.dts:18`).
- **Patches** (`scripts/livi-link/arm/imx6ul/kernel-patches/`, SOURCE): 0001 `clk-imx6ul` moves the bus clocks only when
  `clk_on_imx6ul()` (the vendor U-Boot leaves them set up on the ULL); 0002 chipidea `imx6ul_usb_data` gets
  `CI_HDRC_FORCE_VBUS_ACTIVE_ALWAYS` (the gadget does not wait for B-session-valid); 0003 `phy-mxs-usb` charger detection
  returns `UNKNOWN_TYPE` at once (detection toggles D+/D-); 0004 `spi-nor/macronix` adds an `mx25l12805d` entry without
  SFDP (MX25L12805D/MX25L12835F); 0005/0006 mwifiex: uAP station RX-rate fields and the rate-info layout chosen by firmware
  major ≥ 15. The baseline carries 0001-0004 unchanged, not 0005/0006.
- **Config** (SOURCE): `make allnoconfig` (`build.sh:46`), `./scripts/config` enables (`build.sh:75` on), `olddefconfig`
  (`build.sh:214`), then a survival check of key symbols (`build.sh:216-219`). Built with Debian gcc 16.2.0 (IMAGE). The
  image has no `IKCONFIG`, so the exact `.config` is UNKNOWN. `WATCHDOG`, `WATCHDOG_HANDLE_BOOT_ENABLED` and `IMX2_WDT`
  are enabled (`build.sh:154-156`). The image **does contain the `imx6ul-pinctrl` driver** (IMAGE; an earlier baseline
  note said LIVI's config lacks `PINCTRL_IMX6UL`; that was wrong and is corrected in `../baseline/README.md` §6, §7.3 B8).
- **Size** (IMAGE): image 3,124,994 B = zImage 3,099,160 B + DTB 25,834 B, against the cap **0x302fd8 = 3,157,976 B**
  (32,982 B headroom): `KERNEL_MAX` `board.sh:38`, size check `build.sh:268-269`, measured also in
  `../hardware_tests/2026-10-19_round_trip/livi_9.5.0_iw416_dryrun_report.txt`. The XZ stream is 3,082,328 B and inflates to
  8,906,360 B: built-in initramfs 1,410,344 B + kernel 7,496,016 B. The initramfs carries the rescue BusyBox, **hostapd
  (659,712 B)**, the IW416 combo firmware and `regulatory.db` (`build.sh:30-40`; mwifiex is built in and loads its firmware
  from there, `board.sh:48-50`). The combo firmware is shipped twice: in the initramfs and in the rootfs (IMAGE).
- **DTB** (SOURCE + IMAGE): `usbotg2` `dr_mode = "peripheral"` (`imx6ull.dts:148-151`); `usbotg1` and the FECs stay at
  the SoC dtsi's `disabled`; `wdog1` is enabled by the SoC dtsi default (the board DTS does not touch it); no `panic=`
  in the bootargs. INFERRED: leaving the rescue shell (PID 1 is `exec setsid cttyhack sh`, `init:94`) panics the kernel,
  and without `panic=` it then hangs instead of rebooting.
- Installed through the vendor U-Boot's own staging path (`heweiencrypt`): body in plain, head UpgKey-encrypted into the
  staging blocks, env erased. Format and key: `../../../documentation/05_Security_Analysis/kernel_encryption.md`.
  On-flash evidence (2026-10-20 dump vs stock): head 195,801 B rewritten, body/staging differ exactly as planned
  (`../backups/20261020_livi_pre-baseline/README.txt`).
- OPEN: whether the vendor U-Boot arms WDOG1 before the kernel (it decides whether `WATCHDOG_HANDLE_BOOT_ENABLED` matters);
  the stock board's 74HC595 output expander (stock DT `can-3v3`) is not modelled in LIVI's DTS; the BT UART (`uart3`,
  `imx6ull.dts:139-145`) runs in PIO without SDMA (INFERRED: the `scripts/config` list in `build.sh` names no
  `IMX_SDMA`; not measured).

## 3. Rescue initramfs (inside the kernel) — PROVEN for the network side

- PID 1 `scripts/livi-link/common/initramfs/init`: mounts the `rootfs` squashfs and `switch_root`s only if
  `/usr/bin/livid` is executable there (`init:37,57`); marks the rootfs boot with `printf LIVIBOOT` on `bootstate`
  (`init:53`), cleared by the rootfs `rcS` once it is up. A marked or unusable rootfs → rescue.
- Rescue network: `br0` 10.10.10.1/24 (`init:62-66`), DHCP pool 10.10.10.100-199 (`init:67-73`), `telnetd -l /bin/sh` on
  :23 and :2323 (`init:75-76`), unauthenticated, plus the board's Wi-Fi AP (`board_rescue`, `init:77`;
  `scripts/livi-link/arm/imx6ul/initramfs/board.sh:6` runs `wifi-up`). Seen 2026-10-19 (`RUNBOOK.txt`): shell on
  :23/:2323, host got 10.10.10.100. `LIVI-LINK.md:87-89`: up to 15 s until reachable.
- USB gadget (`scripts/livi-link/common/initramfs/net-up:14-22`): **0525:a4a1** NCM (0525:a4a7 for ACM), manufacturer
  `LIVI`, product `LIVI Link`, first UDC. Seen 2026-10-19: `0525:a4a1` "LIVI Link". `net-up` writes **no iSerial** and no
  `dev_addr`/`host_addr` (SOURCE), so the NCM MACs are the kernel's random ones (INFERRED).
- Two NCM devices on one Mac both answering 10.10.10.1 (this CCPA and a C2Air on LIVI; first hit 2026-10-19 17:16 local): connect with the
  socket bound to one interface — `../tools/tn.py` with `BOUND_IF=<iface>`. That the C2Air uses the same address follows from
  the shared `scripts/livi-link/common/` (INFERRED) and was seen on the bench.

## 4. Rootfs — PROVEN (ran); contents IMAGE

- **Bundle** (SOURCE `native/livi-link/crates/livi-link-provision/src/dongle/lfwb.rs:6-9,31-56`; IMAGE): `LFWB` magic,
  8 B header, one 12 B descriptor per image (type, length, CRC32). 9.5.0 `imx6ul_iw416`: type 2 kernel 3,124,994 B
  (crc `44714489`), type 3 rootfs 1,933,312 B (crc `52ba8272`). One bundle per radio; the provisioner picks it by the SDIO
  device id (`0x9159` IW416, `0xc822` RTL8822CS, `0xb822` RTL8822BS; `imx6ul/mod.rs:23-40`). RTL8822BS images have no
  Bluetooth (`board.sh:66-70`).
- **squashfs** 4.0, xz, 128 KiB blocks, `-all-root -no-xattrs` (`scripts/livi-link/common/build-rootfs.sh:65`), 133 inodes,
  `bytes_used` 1,929,834, image 1,933,312 B (4 KiB multiple, fits 0xc60000). Contents (IMAGE unless marked): static musl
  1.2.5 (SOURCE: `MUSL_VER`, `scripts/livi-link/arm/build-userspace.sh:33`), BusyBox 1.36.1 (390 applets built in, 73
  symlinked; 82 symlinks in all with the 8 `livid` names and `/etc/mtab`), hostapd 2.10, `livid` (Rust multi-call, 8 names), 13 kernel modules, the
  IW416 combo firmware (403,148 B); no dropbear/ssh, no shared libc.
- **rcS** (`scripts/livi-link/common/rootfs/etc/init.d/rcS`): config from `customer` (`:10`), `br0` 10.10.10.1 with usb0
  (`:16-22`), netd/DHCP (`:24`), httpd :80 (`:26`), `telnetd -l /bin/sh -p 23` (`:30-31`), ledd, mfid (:5000), then
  **bootstate cleared (`:51-54`) before the radios start** (`livi-radio boot`, `:57`; wifid :5001, btd :5002, accessoryd
  :5003/:5004 in `usr/bin/livi-radio`). Running on 2026-10-19: `/dev/mtdblock3` squashfs ro, 1920 KB, 100 % used; services
  livi-netd, httpd, ledd, mfid, wifid, btd, accessoryd + hostapd; http://10.10.10.1/ → 200 "LIVI Link"; :22 and :2323
  closed (`RUNBOOK.txt`).

## 5. Provisioner (`livi-link-provision`) — SOURCE only; NEVER RUN by us

LIVI's provisioner (`native/livi-link/bin/livi-link-provision/` and
`native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/{mod,boot,mtd,shell,restore}.rs`, key and layout in
`native/livi-link/crates/imx6ul-uboot/src/lib.rs`) was **never executed** against our unit. We re-implemented its key and
staging in Python (`../tools/dryrun.py`, later `../baseline/arm-imx6ul/tools/stage_kernel.py`) and copied its sequence by
hand (§5.2).

### 5.1 How LIVI bootstraps and installs a **stock** unit (SOURCE)

1. **Way in.** It finds a stock dongle on USB (`bin/.../src/bootstrap.rs:53-69,174-187`), sends vendor message `0x01`
   (open) then `0x99` (send file) (`bootstrap.rs:8-9,195-206`) twice: `/script/livi-boot.sh` (= `scripts/bootstrap.sh`)
   and `/etc/profile` (LIVI's stand-in profile + the hook line `case "$0" in */rcS) sh /script/livi-boot.sh ;; esac`,
   `bootstrap.rs:11-16,44-47`). The user replugs (`main.rs:407-411`).
2. On that boot the stock rcS sources the profile (LIVI's comment, `bootstrap.sh:2`; not checked by us against stock rcS),
   and `livi-boot.sh` waits for `/tmp`, touches `/tmp/UDiskPassThroughMode` (the vendor's no-projection switch), unpacks
   `/script/ko.tar.gz`, `insmod`s `storage_common.ko` + `g_android_accessory.ko` if needed, reprograms
   `android_usb_accessory` to NCM (class 239/2/1, "LIVI Link"), and if `ncm0` appears kills `start_main_service.sh` and
   `ARMadb-driver`, sets a fixed MAC from LIVI's source and 10.10.10.1 with udhcpd; then `busybox telnetd -l /bin/sh -p 2323`
   (`bootstrap.sh:4-46`). Without NCM it falls back to the vendor Wi-Fi AP hosts (`bootstrap.rs:71`, `main.rs:569`).
3. It waits up to 60 × 2 s for :2323 (`main.rs:561-589`), then writes **LIVI's stand-in profile** (not the unit's original)
   back to `/etc/profile` and removes the hook (`main.rs:415-436`).
4. `install` (`imx6ul/mod.rs:68-104`) decides what runs from `/proc/mounts` (jffs2 = vendor, squashfs = LIVI, else rescue;
   `mod.rs:49-66`). Vendor path:
   - **Backup** every MTD: each pulled **once** with `nc -l -p 5610 < /dev/mtdN` on the unit and compared with the unit's
     own `sha256sum` (`mtd.rs:46-100`); `manifest.json` with model, firmware, `state` and per-file sha256 (`mtd.rs:102-154`).
   - **prepare** (`boot.rs:132-179`): `soc_id` must be i.MX6UL/ULL/ULZ; partitions must be the vendor's (uboot 256K +
     kernel) or LIVI's (uboot 192K, env 64K, kernel) (`boot.rs:265-284`); kernel erase size 64 KiB; fuses CFG0, CFG1,
     MAC0, MAC1 from `/sys/fsl_otp` or the nvmem file (`boot.rs:298-317`); UpgKey = their hex text (`lib.rs:48-49`);
     uboot and kernel pulled again; update env decrypted and checked (first CRC only, `lib.rs:87-120`); layout from
     `norboot`/`heweiencrypt`; partition image planned.
   - **install** (`boot.rs:181-263`): push the image to `/tmp` (`nc` 5610 + md5, `shell.rs:136-175`); write with
     `flash_erase … 0 0 && cat` if the unit has `flash_erase`, else `flashcp` (300 s); `sha256sum` readback; erase only
     the env block (vendor: `flash_erase <uboot> 0x30000 1`; LIVI map: `flash_erase <env> 0 0` if the unit has
     `flash_erase`, else `flash_eraseall -q`, `boot.rs:186-193`); re-pull uboot, its first
     0x30000 B must be unchanged and the env block all 0xFF; reboot `(sleep 1; sync; reboot; sleep 5; reboot -f)`; wait up
     to 30 s for it to go, up to **180 s** to return (`mod.rs:12,151-174`); env block must be non-0xFF again.
   - Require **rescue** (`mod.rs:90-94`).
   - **Rootfs** (`boot.rs:57-130`): ≤ partition, 4 KiB multiple, rescue only, `flashcp` present; old rootfs pulled as a
     backup; push; `flashcp` with a **600 s** timeout; `dd | sha256sum` (240 s); `flash_eraseall -q` bootstate.
   - **Reboot** into LIVI Link (`mod.rs:145-148`), wait for it (`main.rs:442`).
   From a unit already on LIVI it first writes `LIVIBOOT` and reboots to rescue (`mod.rs:122-143`), then rootfs before kernel.
5. INFERRED hazard (not tested): `install` checks for an env eraser only **after** the kernel write (`boot.rs:222-228`
   vs `196-220`). A vendor-map unit with `flashcp` but no `flash_erase` would get the new body under the old head and
   then an error, with the env not erased; a power cycle then finds no bootable kernel.

### 5.2 What we did instead (2026-10-19, by hand), and what that left unverified

- The unit was **not stock**: an OCBM unit reached over ssh, with no `flash_erase`/`flashcp` (we pushed the stock
  mtd-utils 1.4.8 `flash_erase`, `../tools/README.md`). No bootstrap step (5.1 steps 1-3) was involved.
- Backup: each MTD read **twice** with equal sha256 (`../backups/20261019_IW416_ocbm_baseline_pre-livi/README.txt`),
  not LIVI's single read; no LIVI `manifest.json` was written.
- Kernel: `flash_erase /dev/mtd1 0 0; cat img > /dev/mtd1; sync` (~20 s), sha256 checked; env erased with
  `flash_erase /dev/mtd0 196608 1`; uboot head checked unchanged (`RUNBOOK.txt`). **Not measured**: the second reset that
  LIVI expects after `heweiencrypt` (`boot.rs:246`), and the env block's non-0xFF state after the reboot was not rechecked
  for the LIVI flash (it was for the stock round trip).
- Rootfs: four `nc` pushes from the Mac failed: the first left 146,432 B, of the next three two left the same sha256 and
  one a different one (size unrecorded); three pulls from a macOS `nc -N -l` listener then gave 0 B each; a pull from a
  host Python server worked (root cause UNKNOWN; LIVI's own push with md5 check and retries was not tried). The first
  `flashcp`, started inside the telnet session, was gone part-way after the session closed (killed by SIGHUP: inferred;
  the process was found gone, not seen killed); rerun under `setsid`, rc=0, `dd | sha256sum` matched; bootstate erased.
- Never exercised: LIVI's rescue fallback after a failed rootfs boot, rollback to the OCBM/stock state (§6).
- Kernel write paths now proven on this hardware: `flash_erase` + `cat` (vendor map, 2026-10-19) and `flashcp` onto the
  LIVI-map `/dev/mtd2` (baseline revisions 1 and 2, 2026-10-20, rc=0 and sha256-verified, `../hardware_tests/`).

## 6. Back to stock — UNTESTED

LIVI's own path: `back_to_stock` (`mod.rs:106-120`) → rescue → `restore.rs:133` `write` (vendor backup written back
from the rescue system), `LIVI-LINK.md:82-83`. It writes the vendor rootfs across LIVI's rootfs+customer+bootstate, the
kernel, and the backed-up vendor **env block** back (`restore.rs:167-193`). It needs a backup directory of its own format:
`manifest.json` with `"state": "stock"`, `uboot.img`/`kernel.img`/`rootfs.img` at the vendor sizes with matching sha256,
a JFFS2 rootfs, and a uboot that decrypts with this unit's key (`restore.rs:26-76,100-130`). **We have no such backup**
(our dumps are `mtd*.bin` with `SHA256SUMS`); a hand-written manifest was not tried. Never run on our unit. The manual
steps, written from the same map, are owned by
`../../../documentation/01_Firmware_Architecture/kernel_compilation.md` § Getting back from LIVI [UNTESTED] and are not
restated here; the SPI image is `../backups/20261019_IW416_ocbm_baseline_pre-livi/full_16MB_for_programmer.bin` (no
programmer restore has been run). [2026-10-20: local only, not in this repo; it embeds device credentials. sha256 and location: `../backups/20261019_IW416_ocbm_baseline_pre-livi/README.txt`.]

## 7. What the baseline changes

`../baseline/README.md` §6 (table "Changes against LIVI, and why"). It keeps LIVI's map, kernel version, board patches
0001-0004 and staging flow; it drops the radio, AP, web UI and daemons and moves the network to 192.168.50.2.

## 8. Exposure and licence observations (SOURCE / IMAGE; nothing here was exploited or tested)

- Unauthenticated root shells: telnet :23 in the running system on `br0`, which bridges usb0 **and the Wi-Fi AP**
  (rcS `:14-31`); in rescue telnet :23 and :2323 plus an AP (§3). The default WPA2 passphrase is a fixed string in
  LIVI's public repo (`common/rootfs/etc/hostapd.conf:21`, `arm/imx6ul/initramfs/wifi-up:35`).
- Web UI on :80 without authentication, including `POST /api/flash` (`crates/livi-web/src/lib.rs:156-157`), which takes an
  LFWB and writes it to flash after these checks only: each image's CRC32, an MTD slot for its type, size ≤ slot, the
  slot's payload magic, and a successful `stage()` for staged slots (`lib.rs:283-351`); there is **no authentication**.
  The daemon listeners reported as filtered to the USB link (`iap2-mfi` `server.rs:88`, `livid` `wifid.rs:36`,
  `livi-btd` `linux.rs:66`, `livi-accessoryd` `server.rs:209`; which port each serves was not re-checked) accept through `livi_net::bridge::from_usb`
  (`native/livi-helperd/crates/livi-net/src/bridge.rs:7-41`): an application-level accept filter that keeps a peer only
  if it is loopback/local or its ARP entry is on `usb0` (or the bridge FDB puts its MAC on the `usb0` port), and drops
  the rest. It is not a firewall, and it was not tested (SOURCE).
- Persistence: livid settings in `customer` (`LVCF` blob). NCM gadget without iSerial and with random MACs (§3).
- Licences: the image ships no licence texts and no written source offer (IMAGE); `CREDITS.md` names none of BusyBox,
  hostapd, musl, libnl or the linux-firmware blobs (SOURCE, checked 2026-10-20).

# Vanilla CCPA baseline image (recipe)

> Copy of ccpa_custom `baseline/` at commit `333b5a4` (2026-10-20), placed here as `custom/kernel_rootfs/baseline/`.
> Path references in this README are re-rooted for this location; the other files are byte-identical to that commit.
> The recipe's working copy stays in ccpa_custom. Index: `../README.md`.

A minimal, vanilla image for the **CPC200-CCPA** (i.MX6ULL, 128 MiB RAM, 16 MiB QSPI NOR, HAB
closed, vendor U-Boot kept): mainline Linux with a **recovery initramfs built into the kernel**, and a
**minimal squashfs rootfs**. No radio, no MFi daemon, no web UI at boot. Built on the LIVI Link
recipe (https://github.com/f-io/LIVI, GPL-3.0-or-later; analysis in `../livi/README.md`), changed where listed below.

**Status (2026-10-20): built and QEMU-smoke-tested, never booted on a device.** One write of the staged kernel partition
to the LIVI bench unit was issued on 2026-10-20 and its outcome is unconfirmed (OPEN: `../hardware_tests/2026-10-20_baseline_kernel_write.md`). Every step
(`fetch userspace measure kernel rootfs`) ran for real in a Lima VM (Debian trixie chroot,
`CROSS_COMPILE=arm-linux-gnueabihf-`, gcc 14.2.0), clean from an empty `$TOP`, after the fixes listed
in §7.1. The images boot to the recovery UART shell on `qemu-system-arm -M mcimx6ul-evk`;
`stage_kernel.py` plans a kernel partition for the IW416 unit's stock dumps. Sizes in §7 are measured;
everything that needs the real board (NCM, QSPI, OCOTP, the rootfs boot, U-Boot near the cap) is not.

Shared with the parallel C2Air (riscv) baseline: `common/`. CCPA-only: `arm-imx6ul/`.

---

## 1. Proven facts this recipe stands on

Hardware-verified 2026-10-19 on the IW416 unit (`../hardware_tests/2026-10-19_round_trip/RUNBOOK.txt`; backup `../backups/20261019_IW416_ocbm_baseline_pre-livi/`):

| Fact | Consequence here |
|---|---|
| U-Boot reads the kernel from flash 0x40000, **0x302fd8 = 3,157,976 B** (env `norboot`) | hard cap for zImage + initramfs + appended DTB (`KERNEL_MAX`) |
| first three 64 KiB blocks are DCP-encrypted per chip, the rest is a plain zImage | a new kernel keeps the current encrypted head and stages the new head |
| staging: new head AES-128-CBC at kernel+0x302fd8, key‖IV = ASCII hex of OCOTP CFG0,CFG1,MAC0,MAC1 (key = first 16 chars, IV = last 16), CBC restarted with that IV per 64 KiB block | `arm-imx6ul/tools/stage_kernel.py` (host) |
| erase the 64 KiB env block (flash 0x30000) and reboot: U-Boot runs `heweiencrypt` (staging → 0x40000/50000/60000) and rewrites env | `flash-kernel` (recovery) |
| encrypted update env at mtd0+0x20000 | read by `stage_kernel.py` to get the unit's own layout |
| LIVI's mainline 7.2.10 kernel + squashfs booted this way | kernel pin 7.2.10, LIVI's 4 board patches, LIVI's partition map |
| partition map (LIVI DTS): uboot 0x30000, env 0x10000, kernel 0x340000, rootfs 0xc60000, customer 0x10000, bootstate 0x10000 | kept unchanged |
| mtd-utils 1.4.8 `flash_erase` takes BYTE offsets | noted for the vendor-firmware install path |
| long commands over telnet must survive the session closing (a `flashcp` was SIGHUPed mid-write) | the flash helpers ignore SIGHUP and log to `/run` |
| macOS `nc` pushing into busybox `nc` over NCM truncated at ~146 KB (3x); a pull from a host Python server worked | helpers PULL (`host:port`); `common/tools/serve_once.py` |

Found while writing this recipe (from files, not hardware):

- **The stock DTB is inside the update env**: offset 0x800 of the decrypted env (FDT magic, totalsize
  33,027 B). `norboot` copies 0xf800 B from 0x80800800 to 0x83000000 *before* it reads the kernel, then
  `bootz 0x80800000 - 0x83000000`. That is why no plain FDT shows up in mtd0 or the kernel image.
  It also means the vendor U-Boot always hands a kernel the *vendor* FDT plus vendor bootargs
  (`norargs`: `console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2 mtdparts=...`), so the baseline
  kernel **must** use its appended DTB and **must not** enable `ARM_ATAG_DTB_COMPAT` (both are in
  `kernel/base.fragment`).
- The stock DTB's `wlreg_on` regulator (GPIO1_IO05, enable-active-low) confirms LIVI's `reg_wlan` polarity.
- USB, the vendor boot log AND the stock DTB agree (details in `dts/imx6ull-ccpa-usbhost.dtsi`): both
  controllers `dr_mode = "otg"`, `disable-over-current`, **no vbus-supply**, no USB pinctrl, OTG1_ID pad
  not muxed; at boot ci_hdrc.0 read `fsm->id = 0` → `a_host`, and a USB stick enumerated (sda1, vfat).
- The NCM CFW gadget enumerates **0x1314:0x1520**, class 239/2/1 (on-box sysfs reads,
  ccpa_custom `scratchpad/ocbm_2026090*/trial.txt` line 4).

---

## 2. Design (owner decisions, implemented as set)

```
power on -> vendor HAB U-Boot (untouched) -> reads 0x302fd8 B @0x40000, decrypts the head
         -> mainline zImage + appended DTB (console=ttymxc0,115200 rdinit=/init panic=10)
         -> recovery initramfs /init (PID 1)
              pseudo fs, /run tmpfs, /run/ocbm identity
              'rootfs' MTD holds a squashfs with /etc/baseline-release, /init, /sbin/init?
              'bootstate' marker clear?   nobody pressed Enter on the UART within 1 s?
                 yes -> write marker, move /dev + /run, switch_root -> rootfs /init -> busybox init
                        rcS: NCM 192.168.50.2 + DHCP(.100) + dropbear key-only; if both up: clear marker
                 no  -> RECOVERY: red LED blinks; UART shell (respawned) + NCM telnetd on 192.168.50.2:23
                        (unauthenticated, rescue only); [RECOVERY_USB=1] usb-update last, quiet
```

- **Console**: UART pads, `ttymxc0` 115200. UART shell in both recovery and rootfs, unauthenticated
  (physical access to the pads is the credential).
- **NCM**: device 192.168.50.2/24, `udhcpd` hands the host exactly 192.168.50.100 (one-address pool;
  the host-side MAC is fixed per unit, so the lease is stable). Matches the old CCPA CFW and avoids
  10.10.10.1 (LIVI, C2Air). `common/ncm.conf`.
- **No radio at boot.** Wi-Fi/BT drivers are rootfs **modules** with their firmware, never loaded:
  no uevent helper, no mdev hotplug, no modalias loader; their only triggers are uevents. The module's
  power switch (GPIO1_IO05, `reg_wlan`) is muxed by the regulator node itself, so the regulator holds
  the module unpowered from the regulator's probe on (early in kernel init; before that the pin keeps
  the boot loader's state; the mux needs `PINCTRL_IMX6UL`) even though the SDIO host driver is never
  loaded (LIVI muxed that pin in the usdhc1 group, which is only applied when the MMC driver probes). No chipset is named
  in the DT unless `RADIO_DT=` selects one (default `none`) — per ccpa_custom CLAUDE.md "never hardcode a chipset".
- **MFi**: only `/dev/i2c-1`, address 0x11 (the `&i2c2` controller on the UART5 pads, numbered 1 by
  the imx6ul.dtsi aliases). No bridge daemon.
- **Rootfs**: static musl BusyBox 1.38.0 (defconfig + nearly everything), dropbear 2026.94 multi-call
  (dropbear/dbclient/dropbearkey/scp) **key-only**, static OpenSSH 10.6p1 `sftp-server`, static
  mtd-utils `flash_erase`, optional exfatprogs, radio modules + firmware. SSH host key and runtime-added
  keys persist in a tar archive on the `customer` MTD (`persist`). `reboot-recovery` sets the marker and
  reboots into recovery. `usb-mount` exists for USB host builds.

### 2.1 USB identity (`common/usb-ids.conf`, shared with the C2Air session)

One file, read by `common/shared/net-up` in both the recovery initramfs and the rootfs.

| Mode | VID:PID | Function | In the baseline |
|---|---|---|---|
| NCM (default) | 0x1314:0x1520, class 0xef/2/1 | `ncm.usb0` | yes |
| OCBM | 0x1314:0x2d00 | FunctionFS + ocbmd | ID listed only; `net-up ocbm` refuses |
| ACM debug | 0x1d6b:0x0104 | `acm.GS0` | recovery only (unauthenticated shell) |

- Strings: iManufacturer **"Magic Communication Tec."**, iProduct **"Auto Box"** (the stock
  g_android_accessory defaults the OCBM host apps match).
- **iSerial = "OCBM-" + first 12 hex of sha256(CFG0‖CFG1)**, the 8 raw bytes at offset 4 of
  `/sys/bus/nvmem/devices/imx-ocotp0/nvmem` (two little-endian words). Stable and unique per chip,
  and does not expose the raw fuse words. File-based serials (`/etc/serial_number`, `/etc/device_serial`,
  `manufacture_date` and its signature) are not real and are not used or preserved (owner correction).
- **NCM MACs** from the same hash: device `h[0:12]`, host `h[12:24]`, unicast + locally administered.
  MAC0/MAC1 are never used.
- The **raw chip ID** (`%08x%08x` of CFG0,CFG1) is written to `/run/ocbm/chip-id` (0400) and printed in
  the UART banner, the recovery telnetd issue text and after an SSH login (`/etc/profile`), never in a
  USB descriptor, mDNS or any pre-authentication network service (deliberately NOT dropbear `-b`).
  **Why it is guarded:** on this SoC that hex string *is* the AES key half of the kernel-staging UpgKey
  (key = hex(CFG0,CFG1), IV = hex(MAC0,MAC1)). The owner may later choose to expose the raw ID in the
  descriptor; the trade-off is that every host the box is plugged into then learns half of the key that
  protects (together with the MAC fuses, which are not secret either) the kernel-staging path.
- `stage_kernel.py --unit-info <file> --print-usb-identity` prints the serial and MACs a unit will use.
- **VID 0x1314 belongs to the original vendor (USB-IF assignment).** It is reused only for
  compatibility with the existing host apps and shared tooling. The clean alternative is a
  pid.codes allocation under VID 0x1209; with the single `usb-ids.conf` that is a one-file change.
- Consequence of 0x1314:0x1520: apps that speak the Carlinkit protocol match it (carlink_native filters
  0x1520/0x1521, ccpa_custom `ccpa/rootfs/script/ocbm_boot.sh:44-47`; the macOS app lists 0x1520 as legacy,
  `USBDeviceManager.swift:53-55`). The stock NCM CFW had the same identity; how those apps behave
  against a pure NCM gadget is UNVERIFIED. `riddle_default.conf` lists USBPID 1521
  (`../../docs/README.md:366-367`); that is the vendor's default config, not
  what the NCM CFW gadget was read enumerating.
- Not in the baseline (OCBM-phase item, provenance UNVERIFIED): the phone-facing gadget in
  ccpa_custom `tools/projection_up.sh:49-50` uses 0x08e4:0x01c0 with the same strings.

### 2.2 Recovery (inside the kernel image)

- Small separate static BusyBox (`common/busybox/recovery.applets`: allnoconfig + the owner's list:
  flashcp, flash_eraseall, dd, nandwrite/nanddump, sha256sum, md5sum, nc, hexdump, ls/cat/mount/umount/
  mkdir/sync/reboot, ifconfig/ip, udhcpd, i2cdetect/i2cget, plus what the scripts call). `build.sh`
  checks the built `busybox.links` against `RECOVERY_NEEDS`.
- `flash-rootfs <img|host:port> <sha256>`: refuses without a matching sha256, a squashfs magic, a 4 KiB
  multiple and a fit; skips if already there; sets the bootstate marker for the duration of the write;
  `flashcp`; verifies `dd | sha256sum`; clears bootstate. Never reboots. **An interrupted rootfs write
  is repairable** (the kernel and recovery live elsewhere; the marker keeps the next boot in recovery).
- `flash-kernel [--restore] <img|host:port> <sha256>`: takes the **host-staged partition image**
  (exactly 0x340000 B), refuses without a matching sha256, refuses an image whose first 192 KiB differ
  from this unit's current partition (staged from a stale dump or for another unit; `--restore` skips
  this for a raw backup of this unit), refuses an image without a staged head at +0x302fd8 (erasing env
  then would brick), checks the `env`/`kernel` MTDs are exactly at flash 0x30000/0x40000 with 64 KiB
  erase blocks, `flashcp`, verifies, `flash_eraseall` on `env` only, verifies env is erased and `uboot`
  unchanged, `reboot -f`. There is **no U-Boot write helper**; `uboot` is read-only in the DT.
- **Recovery cannot repair an interrupted write of its own kernel.** It lives in the partition it is
  writing. A power loss from the start of the kernel write until the env erase completes leaves the old
  encrypted head in front of the new body: no bootable kernel, no USB, **SPI programmer needed**
  (`full_16MB_for_programmer.bin` of that unit; the IW416 unit's is in `../backups/20261019_IW416_ocbm_baseline_pre-livi/`). LIVI's dry-run report estimates that window at
  22-54 s. A *failed* write with power still on is recoverable: recovery keeps running from RAM, retry
  or `--restore`.
- `reboot` in recovery is a wrapper for `reboot -f`: PID 1 is a script, and busybox `reboot` without
  `-f` only signals PID 1, which ignores it.
- Telnet is unauthenticated, bound to 192.168.50.2 only, and exists only in recovery.

### 2.3 USB storage variants and how to decide

| Variable | Kernel | DT | Recovery |
|---|---|---|---|
| default | no USB host | usbotg1 disabled | no USB |
| `USB_HOST=1` | USB core + EHCI + chipidea host built in; storage, vfat, exFAT, NLS as rootfs modules | `usbotg1 { dr_mode = "host"; disable-over-current; }`, no vbus-supply | no USB |
| `USB_VFAT_BUILTIN=1` | + SCSI/sd/usb-storage/vfat/NLS built in | same | no USB |
| `RECOVERY_USB=1` | forces the two above | same | `usb-update`: last, background, bounded (20 s wait), quiet (log in `/run/usb-update.log`), mounts read-only at `/mnt/usb`, looks for `ccpa-baseline/{rootfs.img,kernel-part.img}` + `.sha256`, runs the same helpers with `--if-changed` (a stick left plugged in cannot loop), reboots only if it wrote |
| `RECOVERY_EXFAT=1` | exFAT built in (recovery has no modules) | — | reads exFAT too |

**Owner rule: no USB in recovery if it increases the recovery init/complexity.** Hence
`RECOVERY_USB=0` by default. Decide with numbers: `build.sh fetch userspace measure` builds the kernel
with `RECOVERY_USB=0` and `=1`, prints both images (zImage + appended DTB) and **fails a variant over
0x302fd8**. Keep `RECOVERY_USB=1` only if it fits *and* the owner accepts the added init step.
**Measured 2026-10-20 (§7):** the USB stack costs **+143,004 B** (`RECOVERY_USB=1` 1,896,699 B vs
default 1,753,695 B), not the coordinator's +300-450 KB estimate; built-in exFAT adds another 22,160 B.
LIVI's image was 3,124,994 B (32,982 B spare); dropping built-in Wi-Fi/cfg80211/MMC/bridge, hostapd,
the IW416 firmware and regulatory.db makes the baseline default image 1,371,299 B smaller.
**Gating unknowns for any USB host variant:** whether VBUS on the female port is switched (by the GPIOs
`init_gpio.sh` calls "quick charge", gpio6/gpio7 on the vendor kernel) and its current limit.
First hardware test (documented, not run): boot a `USB_HOST=1` build with a stick plugged in, check
`dmesg` for enumeration; if nothing enumerates, repeat with gpio6/gpio7 driven (exported via sysfs)
high and low. Wired-CarPlay role swapping (dr_mode otg + the vendor's a_suspend_req_inf) stays out;
mainline chipidea would need `USB_OTG_FSM`/role-switch support for it. `dts/stock-usb-reference.dtsi`
restates the stock USB nodes in mainline labels (reference only, UNTESTED, not built).

---

## 3. Directory map

```
baseline/
  README.md                this file
  build.sh                 POSIX sh; --dry-run prints every step; real builds on Linux only
  common/                  shared with the C2Air baseline
    versions.env           version + sha256 pins (where each came from)
    usb-ids.conf ncm.conf  USB identity, NCM addressing
    busybox/full.fragment  rootfs BusyBox: defconfig + these
    busybox/recovery.applets  recovery BusyBox: allnoconfig + these
    dropbear/localoptions.h   key-only server, sftp path
    recipes/userspace.sh   musl, BusyBox x2, dropbear, sftp-server, flash_erase, exfatprogs
    shared/                used by recovery AND rootfs: net-up net-down ocbm-identity ocbm-banner mtd.sh
    rootfs/                skeleton: init, etc/{inittab,init.d/rcS,profile,passwd,group,shells,hostname},
                           usr/sbin/{ssh-up,persist,reboot-recovery,usb-mount}
    tools/serve_once.py    host: one-shot raw TCP file server for the helpers' host:port pulls
  arm-imx6ul/              CCPA only
    board.env              toolchain prefix, flash facts, chip-ID source, UDC match
    kernel/*.fragment      base (strict), base-optional (warn), radio-modules, usb-host,
                           usb-vfat-builtin, exfat-builtin
    dts/                   imx6ull-ccpa-baseline.dts, imx6ull-ccpa-usbhost.dtsi, radio-*.dtsi,
                           stock-usb-reference.dtsi (not built)
    patches/0001-0004      LIVI's board patches, unchanged
    initramfs/             init, reboot, flash-lib.sh, flash-rootfs, flash-kernel, usb-update
    rootfs/etc/baseline/board-rcS.sh   LED hooks
    tools/stage_kernel.py  host: kernel partition image for one unit + dry-run report + --self-test
```

---

## 4. Build order (run for real 2026-10-20, §7)

Real builds need a Linux host (the Lima VM): `make gcc ${CROSS_COMPILE}gcc curl sha256sum tar xz bzip2
patch bc flex bison perl file mksquashfs depmod`, plus `pkg-config` for mtd-utils. Output goes to
`TOP=/tmp/ccpa-baseline-build` (the script refuses anything under `~/Documents`, per ccpa_custom CLAUDE.md). No
toolchain is downloaded by the script. The measured build used a Debian trixie arm64 chroot inside the
Alpine `ccpa-build` VM (`apt install gcc-arm-linux-gnueabihf make bc bison flex libssl-dev libelf-dev
squashfs-tools cpio xz-utils bzip2 device-tree-compiler python3 curl file patch perl kmod pkgconf
qemu-system-arm`) and `CROSS_COMPILE=arm-linux-gnueabihf-` (board.env's default `arm-linux-gnu-` is
LIVI's Fedora name). That compiler emits Thumb-2 by default, which is why `ARM_THUMB` is in
`base.fragment`.

```
sh baseline/build.sh --dry-run                     # prints every step, touches nothing
sh baseline/build.sh fetch                         # pinned tarballs, sha256-checked
sh baseline/build.sh userspace                     # musl, BusyBox full+recovery, dropbear, sftp-server, flash_erase
sh baseline/build.sh measure                       # kernel with RECOVERY_USB=0 and =1, sizes, cap check
sh baseline/build.sh kernel                        # the chosen variant
sh baseline/build.sh AUTHORIZED_KEYS=~/.ssh/id_ed25519.pub rootfs
```

mtd-utils' `.asc` was verified and `MTD_UTILS_SHA256` pinned on 2026-10-20 (`common/versions.env`).
`EXFATPROGS=1` stops with an error: exfatprogs 1.4.3 needs a static libblkid the recipe does not build
(§7).

## 5. Install flow (per unit; host tool first, then the unit)

1. Back up the unit (all MTDs, read twice, identical sha256) and keep its `unit_info.txt` (the four
   OCOTP words) with the backup, never in the ccpa_custom repo. (This docs repo carries the IW416 unit's backup including its
   `unit_info.txt`, `../backups/20261019_IW416_ocbm_baseline_pre-livi/`, by owner decision 2026-10-20.)
2. Host: `python3 -I arm-imx6ul/tools/stage_kernel.py --mtd0 <uboot dump> --mtd1 <current kernel dump>
   --zimage $TOP/out/<variant>/ccpa-baseline.zimg --unit-info <unit_info.txt> --out kernel-part.img`.
   It decrypts the unit's update env with the unit's key (wrong key → refused), takes the layout from
   `norboot`/`heweiencrypt`, writes the partition image and prints the plan (`unchanged`, differing
   regions, headroom, sha256).
3. Write the kernel partition and erase env:
   - **from our recovery**: `flash-kernel <kernel-part.img|host:port> <sha256>`;
   - **from LIVI** (the bench unit's state since 2026-10-19; same partition map): what LIVI's own
     provisioner does, `flashcp img /dev/mtd2 && sha256sum /dev/mtd2`, then `flash_eraseall -q /dev/mtd1`
     (env), verify, `reboot -f`, all under `setsid`;
   - **from the vendor/OCBM system** (vendor map: env inside mtd0, kernel = mtd1): the RUNBOOK's (`../hardware_tests/2026-10-19_round_trip/`)
     LIVI procedure (push the stock-compatible `flash_erase` first, `../tools/flash_erase`; the unit has none),
     `flash_erase /dev/mtd1 0 0; cat img > /dev/mtd1; sha256sum /dev/mtd1`, then
     `flash_erase /dev/mtd0 196608 1` (byte offset, mtd-utils 1.4.8), reboot.
4. The new kernel boots into recovery (the old rootfs is not a baseline squashfs). There:
   `flash-rootfs <host>:5611 <sha256>` with `python3 -I common/tools/serve_once.py rootfs.img` on the
   host, then `reboot`.
5. Back to stock (UNTESTED): from recovery, flashcp the unit's `mtd2.bin` (`../backups/<unit>/`) split into its first 0xc60000
   B (rootfs), next 0x10000 (customer), last 0x10000 (bootstate) — `flash-rootfs` refuses JFFS2, so this
   is manual — then `flash-kernel --restore mtd1.bin <sha256>`. Or the SPI programmer image.

---

## 6. Changes against LIVI, and why

| LIVI | Baseline | Why |
|---|---|---|
| Wi-Fi driver, cfg80211, MMC/SDHCI, bridge built in; hostapd + firmware + regdb in the initramfs; Wi-Fi AP as a second way in | all modules in the rootfs, never loaded; no AP | owner: no radio at boot; frees image bytes |
| GPIO1_IO05 muxed in the usdhc1 group | muxed by `reg_wlan` itself | otherwise unmuxed when MMC is a module, radio power undefined |
| BT built-in pieces for the radio | serdev core only with `RADIO_MODULES=1` | radio optional |
| `mwifiex.driver_mode=2` in the IW416 dtsi's bootargs | dropped; `modprobe mwifiex driver_mode=2` | it replaced the whole bootargs (and our `panic=10`) |
| bootargs without `panic=` | `panic=10` | a rootfs-boot panic reboots into recovery via the bootstate marker instead of hanging |
| `RD_*` initrd decompressors at their defaults | off (`base-optional.fragment`) | the built-in initramfs is uncompressed inside an XZ image; size (UNMEASURED) |
| 10.10.10.1 on br0, two telnetds (:23, :2323) on all interfaces | 192.168.50.2, no bridge, one telnetd bound to the NCM address, recovery only; rootfs: dropbear key-only, no telnet | owner addressing; no unauthenticated network shell outside recovery |
| gadget 0525:a4a1 "LIVI Link", first UDC, random MACs | `usb-ids.conf`, UDC chosen by controller path, per-chip MACs, per-chip iSerial | owner identity decisions; a second UDC would otherwise steal NCM |
| initramfs binds the gadget (LINK_ONLY) and the rootfs bridges usb0 | the rootfs runs the same `net-up` itself; `/run` is moved across | rootfs independent of initramfs state |
| PID 1 `exec setsid cttyhack sh` | PID 1 respawns the UART shell | `exit` in that shell would kill init and panic |
| rootfs taken over if `/usr/bin/livid` exists | if `/etc/baseline-release`, `/init` and `/sbin/init` exist | our marker; a failed exec otherwise panics |
| `printf LIVIBOOT` marker | `CCPABOOT` marker, same logic (`common/shared/mtd.sh`) | do not confuse a LIVI boot state |
| provisioner on the host writes rootfs/kernel over the shell | on-device helpers that require the caller's sha256; kernel image still staged on the host | the key never needs to reach the unit |
| rescue BusyBox: brctl, vi, awk, sed, grep, xxd, pkill, killall, ... | owner's list + what the scripts call | smaller recovery |
| full BusyBox 1.36.1 defconfig, minus VT/console tools and tc | 1.38.0 defconfig + MTD/UBI tools, minus only what cannot build/work (PAM, SELinux, NFS/CIFS mount, tc, hwclock); VT tools kept | owner: as many applets as build static |
| module load order file, no modprobe | `make modules_install` + depmod, BusyBox modprobe | radio modules are loaded by hand, on demand |
| livid, its web UI, mfid, btd, accessoryd | none | owner: none at boot |
| kernel-patches 0005/0006 (mwifiex rate reporting) | not carried | radio is not part of the baseline; 0001-0004 carried unchanged |
| customer MTD: livid settings | persist tar (SSH host key, added keys) | stable host key with a read-only rootfs |
| allnoconfig without `PINCTRL_IMX6UL`, `NVMEM_SYSFS`, `ARM_THUMB` | all three in `base.fragment` | no pinctrl: every pinctrl-0 consumer (uart1, i2c, gpio banks, so also `reg_wlan` and the LEDs) keeps deferring (`drivers/pinctrl/devicetree.c` returns -EPROBE_DEFER when no pin controller driver exists and MODULES=y; QEMU: gpio-mxc -517, no console) and no DT pin muxing is applied; no nvmem file for the chip ID; Thumb userland is refused with ENOEXEC (found in QEMU, 2026-10-20) |

---

## 7. OPEN ITEMS / UNMEASURED / UNVERIFIED

MEASURED 2026-10-20 (clean build from an empty `$TOP`, linux 7.2.10 + patches 0001-0004, gcc 14.2.0
`arm-linux-gnueabihf-`, `RADIO_MODULES=1 RADIO_FW=1 RADIO_DT=none`, `JOBS=3`; the whole clean run took
6 min 53 s on 4 vCPUs):

| Image (kernel = zImage + appended DTB, cap 0x302fd8 = 3,157,976 B) | zImage | DTB | total | spare |
|---|---:|---:|---:|---:|
| default (`RECOVERY_USB=0`) | 1,727,840 | 25,855 | **1,753,695** | 1,404,281 |
| `USB_HOST=1` (storage stack as rootfs modules) | 1,797,584 | 25,883 | 1,823,467 | 1,334,509 |
| `RECOVERY_USB=1` (USB host + storage + vfat built in) | 1,870,816 | 25,883 | **1,896,699** | 1,261,277 |
| `RECOVERY_USB=1 RECOVERY_EXFAT=1` (exFAT built in) | 1,892,976 | 25,883 | 1,918,859 | 1,239,117 |

| Other | bytes |
|---|---:|
| recovery initramfs, uncompressed cpio inside the XZ kernel (default / `RECOVERY_USB=1`) | 301,568 / 305,152 |
| same cpio alone through `xz -9e` (an estimate of its share of the zImage) | 161,108 |
| recovery BusyBox (allnoconfig + `recovery.applets`, 48 links), static, stripped | 263,608 |
| full BusyBox (defconfig + `full.fragment`, 410 links), static, stripped | 984,580 |
| dropbearmulti (dropbear dbclient dropbearkey scp) | 330,160 |
| OpenSSH sftp-server | 197,840 |
| mtd-utils flash_erase | 66,840 |
| rootfs squashfs, default variant (cap 0xc60000 = 12,976,128) | **2,514,944** (10,461,184 free) |
| rootfs squashfs, `RECOVERY_USB=1` variant | 2,560,000 |
| rootfs content before compression: modules / radio firmware + regdb / everything else (default) | 3,404,825 / 836,886 / 1,618,678 |

- Deltas: USB stack +143,004 B (`RECOVERY_USB=1` vs default; the +300-450 KB estimate was 2-3x too
  high), built-in exFAT +22,160 B, `USB_HOST=1` +69,772 B. Against LIVI's 3,124,994 B the default is
  1,371,299 B smaller. The default image changed by +1,688 B on a rebuild of the same tree (new
  release timestamp and build number in the initramfs/version string): treat the last ~2 KB as noise.
- The individual effect of the `RD_*` decompressors and of each dropped LIVI component was not
  separated (no LIVI-config build was made).
- QEMU only (`mcimx6ul-evk`, not the board): `/init` starts at 1.20 s, of which ~1 s is the
  spi-nor probe timing out on QEMU's missing QSPI; recovery shell with 118,404 kB MemAvailable of
  125,036 kB. Boot time and RAM on the real CCPA remain UNMEASURED.

### 7.1 Changes from the dry run (2026-10-20 real build)

| What failed | Change | File |
|---|---|---|
| `busybox.links` missing after `make` (it is its own target in `Makefile.custom`) | make targets `busybox busybox.links`; defconfig/allnoconfig output to a log | `common/recipes/userspace.sh` |
| `headers_install` into the musl sysroot ran in-tree, then every `O=` kernel build stopped with "source tree is not clean" | `headers_install` with `O=$UBUILD/kernel-headers` | `common/recipes/userspace.sh` |
| mtd-utils 2.3.1 configure has no `--disable-tests` | `--without-tests` | `common/recipes/userspace.sh` |
| mtd-utils configure: "pkg-config not found" | build host needs pkg-config; `build.sh` checks for it when `MTD_UTILS=1`/`EXFATPROGS=1` | `build.sh`, §4 |
| exfatprogs 1.4.3 configure: "Package 'blkid' ... not found" (libblkid is mandatory) | `build_exfatprogs` refuses up front unless `EXFAT_BLKID_PC` points at a static libblkid's `.pc` dir; OPEN | `common/recipes/userspace.sh` |
| `MTD_CHAR` wanted y, got n: the symbol no longer exists (mtdchar.o is in `mtd-y`) | line replaced by a comment | `arm-imx6ul/kernel/base.fragment` |
| `USB_HOST=1`: `NLS` wanted m, got y (`USB_GADGET=y` selects `NLS`) | `CONFIG_NLS=m` dropped, codepages stay modules | `arm-imx6ul/kernel/usb-host.fragment` |
| QEMU: no console at all, gpio-mxc -517 (no pin controller driver) | `CONFIG_PINCTRL_IMX6UL=y` | `arm-imx6ul/kernel/base.fragment` |
| QEMU: "Failed to execute /init (error -8)": Thumb-entry busybox, kernel without `ARM_THUMB` | `CONFIG_ARM_THUMB=y` | `arm-imx6ul/kernel/base.fragment` |
| QEMU: "no .../imx-ocotp0/nvmem" although the device existed | `CONFIG_NVMEM_SYSFS=y` | `arm-imx6ul/kernel/base.fragment` |
| QEMU: "tmpfs: Unknown parameter 'nosuid'": recovery BusyBox `mount` without `-o` flag parsing (also needed for `-o move` before `switch_root`) | `FEATURE_MOUNT_FLAGS` | `common/busybox/recovery.applets` |
| QEMU: "can't create /run/ocbm/banner" when `ocbm-identity` fails | `mkdir -p /run/ocbm` before the banner | `arm-imx6ul/initramfs/init` |
| `MTD_UTILS_SHA256` empty | pinned after the `.asc` verified; signature status of every pin recorded | `common/versions.env` |

No DTS change and no patch change was needed: patches 0001-0004 are byte-identical to LIVI's below
their header and applied cleanly to 7.2.10; the DTS compiled without dtc warnings.

### 7.2 Smoke test and host tool (2026-10-20)

- QEMU `-M mcimx6ul-evk -m 128M -kernel ccpa-baseline.zimg` (appended DTB, no `-dtb`): default and
  `RECOVERY_USB=1` reach the recovery `/init`, print the banner and the UART shell prompt; the shell
  runs commands, `/run` is a nosuid,nodev tmpfs, `mount -o move` works, `reboot` restarts. With
  `RECOVERY_USB=1` and a QEMU `usb-storage` vfat stick on usbotg1 (`bus=usb-bus.0`), `usb-update`
  found `ccpa-baseline/` on `/dev/sda`, called `flash-rootfs`, which refused (no MTD) and nothing
  rebooted.
- QEMU cannot test: the USB gadget (its chipidea model has no device mode: "ci_hdrc.0: doesn't support
  gadget", so no UDC, no NCM, no telnetd), QSPI (no model; spi-nor probe -110, so no MTD, no rootfs
  boot, no bootstate, no flash helpers), OCOTP (unimplemented, reads zero; `ocbm-identity` correctly
  refuses an all-zero chip ID), the LEDs' and `reg_wlan`'s real pins, the vendor U-Boot path and its
  `heweiencrypt` staging. QEMU models an i.MX6UL, not the ULL.
- `stage_kernel.py` against the IW416 unit's stock `mtd0.bin`/`mtd1.bin` (vendor map, fuse words from
  that backup's `unit_info.txt`; `../backups/20261019_IW416_ocbm_baseline_pre-livi/`): update env decrypts (gzip and CRC OK), layout kernel_len 0x302fd8,
  staging at partition offset 0x302fd8, planned partition builds for both images with the first
  0x30000 B unchanged; an image 1 B over the cap is refused ("image is 3157977 bytes, this unit's
  U-Boot reads 3157976").

OPEN (hardware):
- female port (usbotg1): whether VBUS is switched (gpio6/gpio7 "quick charge"?), its current limit, and
  mainline chipidea host behaviour; gates every USB host variant (§2.3).
- whether the radio module really is unpowered with `reg_wlan` off on every SKU (polarity from LIVI and
  the stock DTB; the claim that it powers the module comes from LIVI's comment).
- the stock vendor U-Boot's tolerance of the new kernel's size near the cap (LIVI's image had 32,982 B
  spare; nothing closer has booted).

VERIFIED by the 2026-10-20 build (moved out of the list below):
- every Kconfig symbol of all fragments against 7.2.10, for the default, `USB_HOST=1`, `RECOVERY_USB=1`
  and `RECOVERY_USB=1 RECOVERY_EXFAT=1` variants (strict check passed, `GPIO_SYSFS_LEGACY` and `RD_*`
  stuck, no warning); every `localoptions.h` name against dropbear 2026.94; `PROGRAMS=... MULTI=1`
  yields `dropbearmulti`; the configure options of OpenSSH 10.6p1 and mtd-utils 2.3.1 (after the fix
  in §7.1); `make sftp-server` / `make flash_erase` build standalone, static (musl 1.2.5); all five
  binaries start under `qemu-arm` (`dropbear -V`, `dropbearkey -t ed25519`, `sftp-server -h`,
  `flash_erase --version`); BusyBox applet symbols of both lists;
- gpg signatures of linux, busybox, dropbear, OpenSSH, musl, mtd-utils, exfatprogs and wireless-regdb
  (keys and fingerprints in `common/versions.env`; keys fetched over HTTPS, no web of trust); the radio
  firmware blobs are hash-only;
- from 7.2.10 source: `/sys/class/mtd/mtdN/offset` exists for partitions (`drivers/mtd/mtdpart.c`,
  `DEVICE_ATTR_RO(offset)`); regulator-fixed requests its GPIO `GPIOD_OUT_LOW` (logical off) unless
  `regulator-boot-on` (`drivers/regulator/fixed.c`), i.e. off from regulator probe, not from kernel
  start (the pin keeps U-Boot's state until then).

UNVERIFIED (from reading, never executed):
- exfatprogs 1.4.3 (`EXFATPROGS=1`): needs a static libblkid (util-linux) that is not pinned or built;
- that `busybox --install -s` never replaces the shipped `/sbin/reboot` wrapper (QEMU: `reboot` in the
  recovery shell did restart, so the wrapper ran or `-f` was not needed); that busybox `reboot`
  without `-f` is ignored by a script PID 1 (kernel semantics + LIVI's `reboot; sleep 5; reboot -f`);
- the whole rootfs boot path (`switch_root`, rcS, dropbear, `persist`): QEMU has no QSPI, so no
  rootfs MTD;
- the `fsm->id = 1 -> b_peripheral` line in the vendor log names no controller, so which port it
  belongs to is not established;
- that dropbear 2026.94 still checks `/etc/shells` for the login shell (shipped anyway: the lesson from
  `tools/busybox_upgrade.sh`, ccpa_custom; copy in `../../../ocbm/scripts/`), and accepts root with password field `x` and no shadow for key login;
- that the macOS NCM driver uses the gadget's `host_addr` for the host interface (the single-address
  DHCP pool assumes a stable host MAC; a second client id waits at most `NCM_LEASE` = 600 s);
- the C2Air session is described to this recipe as glibc/Andes userspace, but that session's
  `docs/userspace-spec.md` says static musl via zig cc and warns to build BusyBox with the vendor GCC;
  `common/` assumes neither (recipes take `TARGET_CC`).

Known costs (by design): the bootstate block takes one erase per rootfs boot (rcS clears the marker; LIVI's scheme too); a
power cut in the first seconds of a rootfs boot, before rcS clears the marker, lands the next boot in
recovery once; `persist save` overwrites LIVI's `customer` data; a power loss during `persist save`
loses the archive (new host key).

Project rule note: ccpa_custom's CLAUDE.md (updated 2026-10-20, owner decision) now says the HAB-signed U-Boot is
never modified or written, while the kernel is replaceable: this baseline replaces the **kernel** by
the vendor U-Boot's own staging mechanism, as LIVI does; U-Boot itself is never written (only its
64 KB env block is erased).

---

## 8. Licensing and attribution

Files derived from LIVI (https://github.com/f-io/LIVI, GPL-3.0-or-later) carry a header naming the
LIVI source path. DTS files keep the GPL-2.0 SPDX tag of the LIVI file they derive from (kernel DT
sources). `etc/passwd` and `etc/group` are the same one-liners as LIVI's and carry no header (the
format has no comment syntax). The four kernel patches are LIVI's, unchanged, with a header that
`patch(1)` ignores. Everything else in `baseline/` is GPL-3.0-or-later.

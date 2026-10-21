# Vanilla CCPA baseline image (recipe)

> Copy of ccpa_custom `baseline/` at commit `f2a974b` (2026-10-20, revision 5 = revision 4 + the usbotg1 VBUS-enable kernel, flashed and verified on the unit, rootfs USB stick auto-mount verified, FAT32/exFAT x MBR/GPT stick matrix verified; README with the revision-3, revision-4 and revision-5 hardware results; rootfs sources unchanged since `9dc14d8`), placed here as `custom/kernel_rootfs/baseline/`.
> Path references in this README are re-rooted for this location; beyond that, this copy rewrites §5 step 5 to point at `kernel_compilation.md` and drops the owner-local `/Volumes` build/test log paths except the §7 artefact map. The other files are byte-identical to that commit.
> The recipe's working copy stays in ccpa_custom. Index: `../README.md`.

A minimal, vanilla image for the **CPC200-CCPA** (i.MX6ULL, 128 MiB RAM, 16 MiB QSPI NOR, HAB
closed, vendor U-Boot kept): mainline Linux with a **recovery initramfs built into the kernel** (UART,
telnet and SSH/SCP/SFTP over USB NCM, USB-stick flashing), and a **small busybox squashfs rootfs** for a
dev board / IoT box: SSH, USB auto-mount, LEDs, I2C tools for the MFi chip, Wi-Fi/BT brought up **on
demand only**, with station Wi-Fi and Bluetooth CLI tools (revision 3). No projection software, no MFi
daemon, no web UI. Built on the LIVI Link recipe
(https://github.com/f-io/LIVI, GPL-3.0-or-later; analysis in `../livi/README.md`), changed where listed below.

**Status (2026-10-20, revision 5).**
- **Revision 1 (ccpa_custom commit `333b5a4`) ran on hardware.** Observed in-session, 2026-10-20 (`../hardware_tests/2026-10-20_baseline_kernel_write.md`): its kernel (`default`
  variant of that revision, no USB) was staged for the IW416 bench unit and flashed: `flashcp` rc=0
  ("Verifying 3328/3328"), `/dev/mtd2` sha256 = the staged image, env (`/dev/mtd1`) erased with
  `flash_eraseall -q` (rc=0, read back all 0xFF), `mtd0` unchanged, reboot; U-Boot converted the staged head and
  **the recovery came up** on NCM at 192.168.50.2, `/proc/cmdline` `console=ttymxc0,115200 rdinit=/init
  panic=10`, USB vendor 0x1314 (the product ID was not captured). The `flashcp` was issued without an explicit
  go-ahead (the instruction then was "test on board"); the env erase and reboot followed the owner's "continue
  baseline work. env erase and reboot". The same boot exposed bug B1 (§7.3): the serial was
  `OCBM-e3b0c44298fc` (observed), the hash of an empty input, so every unit gets it; the MACs come from the
  same hash, so they are shared too (INFERRED, not read). (Corrected 2026-10-20: this line said "never flashed
  or run on a device", then called the run an owner report.)
- **Revision 2 (ccpa_custom commit `5e90368`)** fixes B1-B9 and adds recovery SSH, recovery USB (now the default) and
  the on-demand radio, LED and MFi tools. Built (clean, §7), host self-test (`common/tools/selftest.sh`)
  and QEMU smoke tests (§7.2), and **PROVEN-BOOTING on one IW416 unit, 2026-10-20**: kernel + recovery
  + rootfs written over revision 1 from its recovery, both boots observed (§7.4; record in
  `../hardware_tests/2026-10-20_baseline_rev2_kernel_rootfs.md`).
  (Corrected 2026-10-20: this line said "it has not been flashed".)
- **Revision 3 (this tree)**: a ROOTFS-ONLY revision. Radio tools: `iw`, `wpa_supplicant`/`wpa_cli`/
  `wpa_passphrase`, BlueZ `btmgmt`/`hciconfig`/`hcitool` (no bluetoothd, no D-Bus, no GLib) and the helpers
  `wifi-connect`, `wifi-scan`, `bt-scan` (§2.5); `radio` loads every module after its dependencies (B10, the
  `Unknown symbol` burst) and words interface state the same way in `up` and `status` (B11); the
  `mfi-probe` lock fix and `radio`'s `driver_mode` fix (ccpa_custom commits `2796253`, `672624c`) are now IN THE IMAGE
  (B13, B14); `stage_kernel.py` checks the update env's second CRC (B12). Built, host self-test, ARM chroot
  (qemu-user) and QEMU tests incl. a boot of the real rootfs image through recovery's `switch_root` (§7.0).
  **The kernel config is unchanged and all 41 modules are byte-identical to revision 2's**, so a unit on
  revision 2 keeps its kernel and takes only the new rootfs (§5 step 6). **The revision-3 rootfs runs on the
  IW416 unit since 2026-10-20** (rootfs only, over revision 2, kernel unchanged; §7.5; record in
  `../hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md`).
  (Updated 2026-10-20: this line said "Not flashed; nothing of revision 3 has run on hardware", and before
  revision 3 that the two fixes were in the tree only, not rebuilt.)
- **Revision 4 (2026-10-20, §7.0a)**: a rootfs-only rebuild of the revision-3 sources at ccpa_custom `9dc14d8`;
  the only change is `bt-scan` (B18: `btmgmt le on` before `btmgmt find`, BR/EDR-only retry of a refused find).
  Kernel not rebuilt or reflashed. **Runs on the IW416 unit since 2026-10-20** (rootfs sha256 `cbfd4d39…513d`);
  B18 VERIFIED on hardware. (Updated 2026-10-20: this bullet said the fix was "not in an image".)
- **Revision 5 (2026-10-20, §7.0b)**: a KERNEL-only rebuild; the only change is the DT: usbotg1 gets
  `vbus-supply` = a fixed regulator on GPIO1_IO07 (active high, on from boot, recovery included), the female
  port's VBUS enable MEASURED on the IW416 unit (§1). Kernel config and the 41 modules byte-identical to
  revision 3's; rootfs unchanged (revision 4's). Built, QEMU-booted, then **flashed to the IW416 unit and VERIFIED on
  hardware** (2026-10-20/21, §7.0b): the stick enumerated at boot in recovery with no manual GPIO. The unit's
  kernel partition now holds sha256 `35dfb1a5…c871e`; revision 2's kernel is superseded.
- **Radios on hardware (2026-10-20, IW416 only)**: revision 2: `radio up` powered `reg_wlan`, found SDIO
  0x02df:0x9159, loaded `mwifiex_sdio` (`phy0`, `mlan0` admin-up) and `btnxpuart` (`hci0` UP); `radio down`
  returned to radios off (§7.4). Revision 3 (§7.5): the same with **0 `Unknown symbol` lines** (B10) and the
  B11 wording; **`wifi-scan` VERIFIED** (2.4 and 5 GHz networks listed); **Bluetooth discovery VERIFIED after
  `btmgmt le on`** (LE devices found; the controller comes up "powered br/edr", LE off, and the default
  `btmgmt find` is rejected, status 0x0b: B18); **`mfi-probe` VERIFIED** (DeviceVersion 0x03, certificate
  length 945 B on `/dev/i2c-1` at 0x11). Revision 4 (§7.0a): `bt-scan` with the B18 fix VERIFIED (LE enabled by
  the script, devices found).
- **UNVERIFIED on hardware**: Wi-Fi association (`wifi-connect`, WPA2-PSK and open) and DHCP over Wi-Fi;
  any Bluetooth pairing or traffic; AP mode (`MWIFIEX_DRIVER_MODE`; no `hostapd`); WPA3 (not built, §2.5);
  `hcitool scan`; RTL8822CS/BS (no such unit); USB `usb-update` from a stick; GPT with an EFI system partition, GPT with the backup header at the true disk end, unpartitioned (superfloppy) sticks and
  hot-plug of exFAT sticks (FAT32/MBR enumeration in recovery, and rootfs mount, write and read-back of FAT32 and exFAT on MBR and GPT single-partition sticks, are VERIFIED, §7.0b); the port's real current limit (design ASSUMPTION, owner-stated, 5 V
  100-500 mA, not measured, §7.0b); `flash-kernel` clearing the bootstate mark (open item, §7.0b); LED behaviours; key-only SSH login and a host key reused
  across a reboot (the persist archive itself is read back across reboots, §7.5); the MACs of revision 2;
  the 1 s UART-Enter window into recovery. (`reboot-recovery` from the rootfs WORKED 2026-10-20, §7.5.)

Shared with the parallel C2Air (riscv) baseline: `common/`. CCPA-only: `arm-imx6ul/`.

---

## 1. Proven facts this recipe stands on

Hardware-verified 2026-10-19 on the IW416 unit (`../hardware_tests/2026-10-19_round_trip/RUNBOOK.txt`; backup `../backups/20261019_IW416_ocbm_baseline_pre-livi/`),
and 2026-10-20 (the revision-1 flash, observed in-session, see Status; revision 2 on the same unit, §7.4):

| Fact | Consequence here |
|---|---|
| U-Boot reads the kernel from flash 0x40000, **0x302fd8 = 3,157,976 B** (env `norboot`) | hard cap for zImage + initramfs + appended DTB (`KERNEL_MAX`) |
| first three 64 KiB blocks are DCP-encrypted per chip, the rest is a plain zImage | a new kernel keeps the current encrypted head and stages the new head |
| staging: new head AES-128-CBC at kernel+0x302fd8, key‖IV = ASCII hex of OCOTP CFG0,CFG1,MAC0,MAC1 (key = first 16 chars, IV = last 16), CBC restarted with that IV per 64 KiB block | `arm-imx6ul/tools/stage_kernel.py` (host) |
| erase the 64 KiB env block (flash 0x30000) and reboot: U-Boot runs `heweiencrypt` (staging → 0x40000/50000/60000) and rewrites env | `flash-kernel` (recovery) |
| `heweiencrypt` rewrites ONLY the three head blocks: after LIVI's install the partition's body and staging equal LIVI's plan, the head differs (`../backups/20261020_livi_pre-baseline/README.txt`) | `flash-kernel` recognises "already installed" (§2.2) |
| encrypted update env at mtd0+0x20000 | read by `stage_kernel.py` to get the unit's own layout |
| LIVI's mainline 7.2.10 kernel + squashfs booted this way (2026-10-19); the baseline's own kernel booted to its recovery this way (2026-10-20) | kernel pin 7.2.10, LIVI's 4 board patches, LIVI's partition map |
| partition map (LIVI DTS): uboot 0x30000, env 0x10000, kernel 0x340000, rootfs 0xc60000, customer 0x10000, bootstate 0x10000 | kept unchanged |
| mtd-utils 1.4.8 `flash_erase` takes BYTE offsets | noted for the vendor-firmware install path |
| long commands over telnet must survive the session closing (a `flashcp` started from a telnet session was found gone part-way after the session closed; SIGHUP is inferred, it was not seen killed) | the flash helpers ignore SIGHUP and log to `/run` |
| macOS `nc` pushing into busybox `nc` over NCM failed four times on 2026-10-19 (the first left 146,432 B; of the next three, two left the same sha256 and one a different one, size unrecorded); three pulls from a macOS `nc -N -l` listener gave 0 B; a pull from a host Python server worked. Root cause UNKNOWN (not diagnosed). LIVI's own provisioner does push (`nc -l` on the unit, md5 check and retry, `livi-link-provision` `imx6ul/shell.rs:136-175`), but it was never run here | helpers PULL (`host:port`); `common/tools/serve_once.py`; revision 2 also takes `scp -O` |
| `flashcp` onto the kernel partition (LIVI map `/dev/mtd2`): revision 1 by hand under `setsid` and revision 2 through `flash-kernel`, both rc=0 and sha256-verified (2026-10-20); the 2026-10-19 LIVI kernel went in by `flash_erase` + `cat` on the vendor map | `flash-kernel` writes with `flashcp` |
| sysfs nvmem answers a read shorter than the word size (4 B on imx-ocotp) with EINVAL (`drivers/nvmem/core.c` `bin_attr_nvmem_read`): revision 1's `dd bs=1` read nothing, every unit got `OCBM-e3b0c44298fc` (2026-10-20) | `ocbm-identity` reads whole words (B1); revision 2's serial on the unit is unit-specific (§7.4) |
| BusyBox 1.38.0 `flock` has no `-w` (on the unit, 2026-10-20: `flock: unrecognized option: w`; its options are `-s -x -u -n` and `-c`) | `mfi-probe` polls `flock -n` (50 x 200 ms) |
| `radio up` on the unit logged many `Unknown symbol` lines for `mwifiex_sdio` and `btnxpuart`, then loaded them (2026-10-20). Cause, VERIFIED from BusyBox 1.38.0 source (`modutils/modprobe-small.c` `fileAction`) and reproduced in QEMU: the rootfs `modprobe` is MODPROBE_SMALL (the defconfig default), whose first lookup insmods the requested module as soon as it finds it, before its dependencies, then loads those and retries (QEMU, revision-3 rootfs: `modprobe mwifiex_sdio` 70 lines, `modprobe btnxpuart` 2) | `radio` loads each module after its dependencies from `modules.dep` with `insmod` (`radio-lib.sh` `mod_load`, B10): 0 lines in QEMU for every radio module, and 0 in `radio up` on the IW416 unit (revision 3, §7.5) |
| The female port's VBUS enable is **GPIO1_IO07** (2026-10-20, revision-2 kernel without vbus-supply, revision-4 rootfs): no stick on usbotg1 (ci_hdrc.0, host) until sysfs gpio7 (gpiochip0 = 209c000.gpio = GPIO1) is driven high; then the port connects and sda1 (vfat) enumerates at once; back to input, the stick drops. GPIO1_IO06 high: no effect. The vendor's `init_gpio.sh` "quick charge" pins are sysfs gpio6/gpio7 on its 3.14 kernel, the same pins if bank 1 starts at 0 there (INFERRED) | revision 5: usbotg1 `vbus-supply` = `reg_usb_otg1_vbus` (regulator-fixed, GPIO1_IO07 active high, boot-on + always-on, pad mux only), `dts/imx6ull-ccpa-usbhost.dtsi`; **revision 5 VERIFIED on the unit** 2026-10-20/21 (§7.0b) |

Found while writing this recipe (from files, not hardware):

- **The stock DTB is inside the update env**: offset 0x800 of the decrypted env (FDT magic, totalsize
  33,027 B). `norboot` runs `cp 0x80800800 0x83000000 0xf800` (the count is in `cp` units: 4-byte words if this U-Boot's
  `cp` defaults to `.l` like upstream 2015.04, INFERRED in `kernel_encryption.md` because its help text is
  stripped, else bytes; the DTB is the first 33,027 B copied either way) *before* it reads the kernel, then
  `bootz 0x80800000 - 0x83000000`. That is why no plain FDT shows up in mtd0 or the kernel image.
  It also means the vendor U-Boot always hands a kernel the *vendor* FDT plus vendor bootargs
  (`norargs`: `console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2 mtdparts=...`), so the baseline
  kernel **must** use its appended DTB and **must not** enable `ARM_ATAG_DTB_COMPAT` (both are in
  `kernel/base.fragment`), and `stage_kernel.py` refuses an image without a complete appended DTB (B4).
- The stock DTB's `wlreg_on` regulator (GPIO1_IO05, enable-active-low) confirms LIVI's `reg_wlan` polarity.
- USB, the vendor boot log AND the stock DTB agree (details in `dts/imx6ull-ccpa-usbhost.dtsi`): both
  controllers `dr_mode = "otg"`, `disable-over-current`, **no vbus-supply** (the VBUS enable is GPIO1_IO07,
  outside the DT: MEASURED, table above), no USB pinctrl, OTG1_ID pad
  not muxed; at boot ci_hdrc.0 read `fsm->id = 0` → `a_host`, and a USB stick enumerated (sda1, vfat).
- The NCM CFW gadget enumerates **0x1314:0x1520**, class 239/2/1 (on-box sysfs reads,
  ccpa_custom `scratchpad/ocbm_2026090*/trial.txt` line 4).
- The `kernel_len`/staging offset 0x302fd8 is the 2025.10.15.1127 U-Boot env's; build 2025.02.25.1521
  uses **0x303080** (`../../../documentation/05_Security_Analysis/kernel_encryption.md`).
  `stage_kernel.py` reads each unit's own values; `board.env`'s 0x302fd8 is only the image budget (the
  smaller value fits both) and `flash-kernel`'s probe offset for "something is staged", which a staging
  at 0x303080 still satisfies. Precisely (`flash-kernel:99`, `board.env:25` `STAGING_PART_OFFSET`): the
  probe only refuses an image whose 192 KiB from partition offset 0x302fd8 are all 0xFF. On a 0x303080
  unit that window holds 196,440 B of the real staging, so a staged head passes; its first 168 B
  (0x302fd8-0x30307f) are kernel-body space there, so a non-0xFF byte in them would pass the probe with
  nothing staged (INFERRED from the code; no 0x303080 unit tested). The staged head's correctness rests
  on `stage_kernel.py`, not on this probe.
- `stage_kernel.py` checks BOTH CRC32s of the update env since revision 3 (B12): the first over
  `env[4:0x800]` and the second (little-endian) over `env[0:0xFFFC]` stored at `env[0xFFFC:]`
  (`kernel_encryption.md`), which also covers the vendor FDT at 0x800; a mismatch is refused. The second
  matched on three dumps of the IW416 unit (stock `mtd0.bin`, `full_16MB_for_programmer.bin`, the LIVI-state
  `mtd0_dump.bin`; 2026-10-20); no other unit's fuse words are on file. LIVI's `read_env`
  (`imx6ul-uboot/src/lib.rs:87-120`) checks neither the second CRC. (Corrected 2026-10-20: this said the
  second check was not added.)

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
                        rcS: mdev -d (USB sticks), NCM 192.168.50.2 + DHCP(.100) + dropbear (key or
                        password); if NCM and SSH are up: clear marker, red LED off
                 no  -> RECOVERY: red LED blinks; UART shell (respawned); on NCM 192.168.50.2:
                        telnetd :23 (unauthenticated, rescue only) + dropbear :22 (SSH/SCP/SFTP, key
                        or password); usb-update: one scan for a stick, mounted rw at /mnt/usb,
                        ccpa-baseline/ bundle flashed if it differs from flash
```

- **Console**: UART pads, `ttymxc0` 115200. UART shell in both recovery and rootfs, unauthenticated
  (physical access to the pads is the credential).
- **NCM**: device 192.168.50.2/24, `udhcpd` hands the host exactly 192.168.50.100 (one-address pool;
  the host-side MAC is fixed per unit, so the lease is stable). Matches the old CCPA CFW and avoids
  10.10.10.1 (LIVI, C2Air). `common/ncm.conf`. telnetd and dropbear bind to 192.168.50.2 only.
- **No radio at boot.** Wi-Fi/BT drivers and the MMC host are rootfs **modules** with their firmware;
  they load only by device modalias, and nothing acts on one: there is no uevent helper, and the
  rootfs's `mdev -d` (USB sticks only) has no `$MODALIAS` rule. The module's power switch (GPIO1_IO05,
  `reg_wlan`, the vmmc-supply of usdhc1) is muxed by the regulator node itself, so the regulator holds the
  module unpowered (rail not measured, §7.3) from the regulator's probe on (early in kernel init; before that the pin keeps the
  boot loader's state; the mux needs `PINCTRL_IMX6UL`). `radio up` (§2.5) powers it. The rootfs restores
  `kernel.modprobe` (B6): the kernel may then load protocol modules itself (the default rootfs's
  `modules.alias`, 97 lines: `net-pf-16-proto-16-family-nl80211` → cfg80211, `net-pf-31` → bluetooth,
  `tty-ldisc-15` → hci_uart, `bt-proto-3` → rfcomm, and crypto names, `crypto-*` plus bare `aes`, `ccm`,
  `gcm`, `ctr`, `ecb`, …, for the Wi-Fi ciphers). It has no `fs-*`/`nls_*` alias: vfat, exFAT and NLS are built
  into the default kernel; those requests only arise in modular `USB_HOST=1` builds. It never loads the MMC
  host or a chip driver: their aliases are only `of:` (48) and `sdio:` (12), for `btnxpuart`, `hci_uart`,
  `mwifiex_sdio`, `rtw88_8822bs`/`cs` and `sdhci_esdhc_imx` (VERIFIED in the revision-2 default rootfs's
  `modules.alias`, 2026-10-20; corrected the same day: this listed `fs-*`/`nls_*` and `platform:`/`serdev:`). No chipset is named in
  the DT unless the image is a radio one (§2.5), per ccpa_custom CLAUDE.md "never hardcode a chipset".
- **MFi**: only `/dev/i2c-1`, address 0x11 (the `&i2c2` controller on the UART5 pads, numbered 1 by
  the imx6ul.dtsi aliases); `mfi-probe` reads it (§2.4). No bridge daemon.
- **Rootfs** (§2.4): static musl BusyBox 1.38.0 (defconfig + nearly everything, 410 applets), dropbear
  2026.94 multi-call (dropbear/dbclient/dropbearkey/scp), static OpenSSH 10.6p1 `sftp-server`, static
  mtd-utils `flash_erase`, `hciup`, optional exfatprogs, radio modules + all known firmware, and (revision 3,
  `RADIO_TOOLS=1`) `iw`, `wpa_supplicant`/`wpa_cli`/`wpa_passphrase`, `btmgmt`, `hciconfig`, `hcitool`, never
  started at boot (§2.5).
- **SSH** (§2.6): recovery and rootfs, root by public key **or** password. The root password defaults
  to the documented **DEV DEFAULT `baseline`** (build variable `ROOT_PASSWORD_HASH`); change it with
  `passwd` in the rootfs.

### 2.1 USB identity (`common/usb-ids.conf`, shared with the C2Air session)

One file, read by `common/shared/net-up` in both the recovery initramfs and the rootfs.

| Mode | VID:PID | Function | In the baseline |
|---|---|---|---|
| NCM (default) | 0x1314:0x1520, class 0xef/2/1 | `ncm.usb0` | yes (enumerated on hardware 2026-10-20) |
| OCBM | 0x1314:0x2d00 | FunctionFS + ocbmd | ID listed only; `net-up ocbm` refuses |
| ACM debug | 0x1d6b:0x0104 | `acm.GS0` | recovery only (unauthenticated shell) |

- Strings: iManufacturer **"Magic Communication Tec."**, iProduct **"Auto Box"** (the stock
  g_android_accessory defaults the OCBM host apps match).
- **iSerial = "OCBM-" + first 12 hex of sha256(CFG0‖CFG1)**, the 8 raw bytes at offset 4 of
  `/sys/bus/nvmem/devices/imx-ocotp0/nvmem` (two little-endian words), read as **two whole 4-byte words**
  (`dd bs=4 skip=1 count=2`); an empty, short or all-zero read, or a hash equal to sha256(""), is refused
  and no identity is written (B1). Stable and unique per chip, and does not expose the raw fuse words.
  File-based serials (`/etc/serial_number`, `/etc/device_serial`, `manufacture_date` and its signature)
  are not real and are not used or preserved (owner correction).
- **A unit that ran revision 1 changes identity with revision 2**: from `OCBM-e3b0c44298fc` (everyone's)
  to its own serial and MACs. The host sees a new USB serial and a new NCM interface MAC; reconfigure
  the host side if it pinned either. `stage_kernel.py --unit-info <file> --print-usb-identity` prints
  what a unit will use.
- **NCM MACs** from the same hash: device `h[0:12]`, host `h[12:24]`, unicast + locally administered.
  MAC0/MAC1 are never used.
- The **raw chip ID** (`%08x%08x` of CFG0,CFG1) is written to `/run/ocbm/chip-id` (0400) and printed in
  the UART banner, the recovery telnetd issue text and after an SSH login (`/etc/profile`), never in a
  USB descriptor, mDNS or any pre-authentication network service (deliberately NOT dropbear `-b`).
  **Why it is guarded:** on this SoC that hex string *is* the AES key half of the kernel-staging UpgKey
  (key = hex(CFG0,CFG1), IV = hex(MAC0,MAC1)). The owner may later choose to expose the raw ID in the
  descriptor; the trade-off is that every host the box is plugged into then learns half of the key that
  protects (together with the MAC fuses, which are not secret either) the kernel-staging path.
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

### 2.2 Recovery (inside the kernel image): only what recovers the box

- **What is in it** (`build.sh` `initramfs_list`): a separate static BusyBox
  (`common/busybox/recovery.applets`: allnoconfig + the owner's list: flashcp, flash_eraseall, dd,
  nandwrite/nanddump, sha256sum, md5sum, nc, hexdump, ls/cat/mount/umount/mkdir/sync/reboot, ifconfig/ip,
  udhcpd, i2cdetect/i2cget, telnetd, plus what the scripts call, tar for the persist archive, 64-bit shell
  arithmetic; 49 applets; `build.sh` checks `busybox.links` against `RECOVERY_NEEDS`), the flash helpers,
  `usb-mount`/`usb-update`, `persist`/`ssh-up`, and with `RECOVERY_SSH=1` (default) dropbearmulti
  (dropbear, dropbearkey, scp, dbclient) + `sftp-server` + `/etc/{passwd,group,shells,profile}` and the
  default shadow line.
- **Ways in**: the UART shell (respawned); on NCM 192.168.50.2 telnet :23 (unauthenticated, rescue only;
  `nc` stays: it is the transport of the `host:port` pulls) and **SSH :22** (SSH, SCP incl. legacy
  `scp -O`, SFTP).
- **Recovery SSH keys, read-only** (`persist load` reads the `customer` MTD through its read-only
  `/dev/mtdNro` node; `persist save`/`add-key` refuse in recovery): option 1 = the rootfs's persist
  archive: its host key (same fingerprint as the rootfs), its copy of the rootfs's build-time keys
  (`authorized_keys.rootfs`), the keys added with `persist add-key`, and root's hash after `passwd`.
  Fallback when nothing is stored (erased or foreign `customer`, e.g. LIVI's data, or no MTD): an
  **ephemeral ed25519 host key in RAM** (fingerprint changes every recovery boot) and **password login**
  with the build default. Recovery never writes flash for SSH.
- `flash-rootfs <img|host:port|/mnt/usb/...> <sha256>`: refuses without a matching sha256, a squashfs
  magic, a 4 KiB multiple and a fit; skips if already there; sets the bootstate marker for the duration
  of the write; `flashcp`; verifies `dd | sha256sum`; clears bootstate. Never reboots. **An interrupted
  rootfs write is repairable** (the kernel and recovery live elsewhere; the marker keeps the next boot in
  recovery).
- `flash-kernel [--restore] [--if-changed] [--dry-run] <img|host:port> <sha256>`: takes the
  **host-staged partition image** (exactly 0x340000 B), refuses without a matching sha256, refuses an
  image whose first 192 KiB AND the rest differ from this unit's current partition (staged from a stale
  dump or for another unit; `--restore` skips this for a raw backup of this unit), refuses an image
  without a staged head at +0x302fd8 (erasing env then would brick), checks the `env`/`kernel` MTDs are
  exactly at flash 0x30000/0x40000 with 64 KiB erase blocks, `flashcp`, verifies, `flash_eraseall` on
  `env` only, verifies env is erased and `uboot` unchanged, `reboot -f`. **"Already installed"**: when
  everything after the first 192 KiB equals the image and only the head differs (what U-Boot's
  conversion leaves, §1), it writes and erases nothing and exits 3 (B3). `--dry-run` runs every check and
  says what it would do. There is **no U-Boot write helper**; `uboot` is read-only in the DT.
- **Exit status of both helpers** (`flash-lib.sh`): 0 written, 2 usage, 3 nothing to do, **4 refused
  before anything was written** (safe to power off), **1 failed after the write started** (read the
  message; for the kernel: DO NOT POWER OFF). Red LED: 100/100 ms blink while writing, back to 500/500
  when done, solid after a failed write.
- **Recovery cannot repair an interrupted write of its own kernel.** It lives in the partition it is
  writing. A power loss from the start of the kernel write until the env erase completes leaves the old
  encrypted head in front of the new body: no bootable kernel, no USB, **SPI programmer needed**
  (`full_16MB_for_programmer.bin` of that unit; the IW416 unit's is kept outside git, in
  `carlinkit_misc/ccpa_backups/20261019_IW416_ocbm_baseline_pre-livi/`, because it embeds device credentials;
  its sha256 and why it left:
  `../backups/20261019_IW416_ocbm_baseline_pre-livi/README.txt`). LIVI's dry-run report estimates that window at
  22-54 s, an estimate with no source given; on 2026-10-19 the erase + write of LIVI's kernel took ~20 s
  (RUNBOOK, Stage 1), the env erase came after it. A *failed* write with power still on is recoverable: recovery keeps running from RAM, retry
  or `--restore`.
- **USB** (`RECOVERY_USB=1`, default): vfat and exFAT built in, MBR and GPT built in (`MSDOS_PARTITION`,
  `EFI_PARTITION`). `usb-update` runs last, in the background, bounded and quiet (log
  `/run/usb-update.log`): `usb-mount --wait 20` mounts the **first suitable FAT12/16/32 or exFAT data partition
  read-write at /mnt/usb** and leaves it mounted for the shells (`flash-rootfs /mnt/usb/rootfs.img
  <sha256>`), skipping the EFI System Partition (GPT C12A7328-F81F-11D2-BA4B-00A0C93EC93B, MBR 0xEF) and
  reading a protective MBR (0xEE) as GPT (rules: header of `common/shared/usb-mount`, the ONE script
  recovery and rootfs share); then, if the stick has `ccpa-baseline/{rootfs.img,kernel-part.img}` +
  `.sha256`, the helpers run with `--if-changed`: exit 3 (already there / already installed) and 4
  (refused) are logged only, the console hears only about a write (B3); it reboots only if it wrote,
  after unmounting the stick. **Decision: one-shot scan + manual `usb-mount`, no poller.** Recovery
  keeps no resident process (owner rule: no new daemons), and a stick inserted mid-session is never
  flashed behind the operator's back: a poller would run the bundle step on hot insert during manual
  recovery work. A late stick: `usb-mount` (devtmpfs makes `/dev/sdX` without any helper).
- `reboot` in recovery is a wrapper for `reboot -f`: PID 1 is a script, and busybox `reboot` without
  `-f` only signals PID 1, which ignores it.

### 2.3 USB storage variants and how to decide

| Variable (default) | Kernel | DT | Recovery |
|---|---|---|---|
| `RECOVERY_USB=1` (default) | USB host + EHCI + chipidea host + SCSI/sd/usb-storage + vfat + NLS + MBR/GPT built in (forces `USB_HOST=1 USB_VFAT_BUILTIN=1`) | `usbotg1 { dr_mode = "host"; disable-over-current; vbus-supply = <&reg_usb_otg1_vbus>; }` (GPIO1_IO07, always on; revision 5) | `usb-mount` one-shot + `usb-update` |
| `RECOVERY_EXFAT=1` (default) | + exFAT built in (recovery has no modules) | — | reads exFAT too |
| `RECOVERY_SSH=1` (default) | — | — | dropbear + sftp-server in the cpio |
| `RECOVERY_USB=0 USB_HOST=1` | USB host built in; storage, vfat, exFAT, NLS codepages as rootfs modules | same | no USB |
| `RECOVERY_USB=0` (`nousb`) | no USB host | usbotg1 disabled | no USB |

Variant (= kernel config) names: `default` (RECOVERY_USB=1, EXFAT=1, SSH=1), `recovery-usb-vfat`,
`nousb`, `usb-host[-vfat]`, suffix `-nossh`, `-noradio`. **Owner decision 2026-10-20: RECOVERY_USB=1
and exFAT are the default.** Measured cost (§7): USB storage + vfat **+147,044 B**, exFAT **+23,792 B**,
recovery SSH **+201,144 B**; the default image is 2,127,059 B with 1,030,917 B spare under the cap.
The added init step is one background call (`usb-update`), no daemon.
**VBUS on the female port is switched by GPIO1_IO07** (MEASURED 2026-10-20, §1; sysfs gpio7 on mainline,
INFERRED to be the gpio7 `init_gpio.sh` calls "quick charge"; GPIO1_IO06 did nothing). Up to revision 4 nothing drove it, so no
stick enumerated; revision 5 holds it high from the regulator's probe in every USB host build
(`reg_usb_otg1_vbus`, `dts/imx6ull-ccpa-usbhost.dtsi`). Revision 5 is VERIFIED on the unit
(§7.0b: stick enumerated at boot in recovery, no manual GPIO). The rootfs path is VERIFIED too (2026-10-21: FAT32 stick auto-mounted read-write at /mnt/usb by the mdev `usb-mount`
rule; FAT32 and exFAT on MBR and GPT single-partition sticks, §7.0b). The port's current capability is an owner-stated design ASSUMPTION, not a measurement: 5 V, 100-500 mA (the
USB 2.0 minimum for data transfer and for an iPhone to connect for CarPlay); the real limit remains unmeasured. Wired-CarPlay role swapping (dr_mode otg + the vendor's
a_suspend_req_inf) stays out; mainline chipidea would need `USB_OTG_FSM`/role-switch support for it.
`dts/stock-usb-reference.dtsi` restates the stock USB nodes in mainline labels (reference only,
UNTESTED, not built).

### 2.4 Rootfs: a dev-board / IoT busybox box

- **BusyBox** full (410 applets) incl. the i2c tools (`i2cdetect i2cget i2cset i2cdump i2ctransfer`),
  `mdev`, `passwd` (sha512-crypt by default, `full.fragment`), MTD/UBI tools, `modprobe`/`depmod`.
- **SSH**: dropbear on 192.168.50.2:22 (`common/shared/ssh-up`, §2.6), SCP and SFTP.
- **USB sticks**: `mdev -d` (netlink, started by rcS; its start-up scan catches a stick that is already
  plugged in) runs `usb-mount --mdev` for every whole-disk `sd[a-z]` add/remove (`etc/mdev.conf`): the
  same MBR/GPT/ESP-skip rules as recovery, FAT12/16/32 or exFAT, read-write at `/mnt/usb`, lazy unmount on
  removal. `etc/mdev.conf` ends in a catch-all `!` rule (mdev neither creates, chmods nor unlinks any
  node; devtmpfs owns `/dev`) and has no `$MODALIAS` rule (no module loading). With `USB_HOST=1`
  modular builds rcS first loads the storage stack (`usb-mount --modules`).
- **LEDs** (§2.7): `led [red|blue on|off|blink|heartbeat]`.
- **MFi coprocessor**: `mfi-probe` (read-only): DeviceVersion (reg 0x00, 1 B; 0x03 on the IW416 unit
  per ccpa_custom `ccpa/carplayd/src/main.rs`) and the certificate length (reg 0x30, 2 B BE), with the access the
  project's daemons use (register write + repeated-start read, 5 tries 5 ms apart,
  ccpa_custom `crates/vendor/mfi-i2c-local/src/lib.rs`) under `/tmp/carplay_mfi.lock`. No control register, no
  challenge, no signing. The lock step polls `flock -n` up to ~10 s (BusyBox has no `flock -w`): in the
  revision-3 image (B13; in an ARM chroot it waited for a lock held 2 s and gave up after 11 s on one held
  14 s); the revision-2 rootfs failed there (`flock: unrecognized option: w`). **VERIFIED on the IW416 unit
  2026-10-20, revision 3** (§7.5): the chip at 0x11 on `/dev/i2c-1`, DeviceVersion 0x03, certificate length
  945 B. (Corrected 2026-10-20: this said the chip reads were UNVERIFIED on the board.)
- **Radios**: `radio up|down|status`, `radio-up`, `radio-down`; Wi-Fi `wifi-connect`, `wifi-scan`, `iw`,
  `wpa_cli`; Bluetooth `bt-scan`, `btmgmt`, `hciconfig`, `hcitool`, `hciup` (§2.5).
- **Passwords and keys**: `passwd` (wrapper in `/usr/sbin`: busybox passwd through the `/etc/shadow` →
  `/run/etc/shadow` link, then `persist save`), `persist add-key FILE`.
- **Persist archive** (`persist`, §2.6) on the `customer` MTD; `reboot-recovery` sets the bootstate
  marker and reboots into recovery.

### 2.5 Radios on demand: ONE rootfs and ONE kernel config for every radio

The kernel config, zImage, recovery initramfs and rootfs are the same for all three radios; **the only
per-radio part is the appended DTB**, i.e. whether `uart3` carries a Bluetooth serdev node. `build.sh`
builds one zImage per variant and writes `ccpa-baseline-<radio>.zimg` = that zImage + the DTB of
`imx6ull-ccpa-baseline-<radio>.dts` (the board DTS + `dts/radio-<radio>.dtsi`), for `RADIO_DT=all`
(default) or one radio. `ccpa-baseline-rtl8822bs.zimg` is byte-identical to `-none` (no BT node).

`radio up` (`arm-imx6ul/rootfs/usr/sbin/radio`): loads `sdhci-esdhc-imx`, whose probe switches `reg_wlan`
on (vmmc-supply; userspace has no other handle on that regulator) and enumerates the SDIO card; reads
the chip's own `/sys/bus/sdio/devices/*/{vendor,device}`; loads the matching driver; brings every
wireless interface up (driver names: `mlan0` on mwifiex, `wlan0` on rtw88; enumerated from
`/sys/class/net/*/phy80211`, never assumed) administratively up; with the matching DT node loads the BT driver and brings
`hci0` up with `hciup` (HCIDEVUP runs the controller's HCI init, so "UP" with a BD address means real HCI
round trips); prints what it did. `radio down` stops `wifi-connect`'s daemons, reverses the rest, prints the `reg_wlan` state (it does not
check it) and fails if an SDIO card is still present. Unknown chip: reported, nothing loaded (the module stays powered until `radio down`).
Every module is loaded after the modules it depends on, read from the kernel's own `modules.dep`, each with
`insmod` (`arm-imx6ul/rootfs/lib/baseline/radio-lib.sh` `mod_load`), never with BusyBox `modprobe` (B10, §1).
`radio up` and `radio status` describe a wireless interface the same way (B11): administrative state
(IFF_UP), carrier, operstate, e.g. `mlan0: administratively up, no carrier (operstate down)`, which is the
state until `wifi-connect` joins a network; `radio status` adds the association (`iw dev <if> link`) and
whether `wifi-connect`'s `wpa_supplicant` runs.

| SDIO vendor:device | Chip | Wi-Fi | Bluetooth | Image |
|---|---|---|---|---|
| 0x02df:0x9159 | NXP IW416 (SD8978) | `mwifiex_sdio`, `mrvl/sdiouartiw416_combo_v0.bin` (also starts BT); `MWIFIEX_DRIVER_MODE=0x3 radio up` for AP+station: `driver_mode` is a parameter of `mwifiex`, not `mwifiex_sdio` (`strings` of the shipped `mwifiex.ko`: `parm=driver_mode:station=0x1(default), ap-sta=0x3…`; `mwifiex_sdio.ko` has no `parm=`), so `radio` loads `mwifiex driver_mode=<n>` before `mwifiex_sdio`: in the revision-3 image (B14); the revision-2 rootfs on the unit still passes it to `mwifiex_sdio`. AP mode is UNVERIFIED (no `hostapd`, and wpa_supplicant is built without AP mode). (Corrected 2026-10-20.) | `btnxpuart` after the combo firmware ("FW already running" path), DT `nxp,88w8987-bt` | `-iw416` |
| 0x024c:0xc822 | Realtek RTL8822CS | `rtw88_8822cs`, `rtw88/rtw8822c_fw.bin` | `hci_uart` H5 + `btrtl`, `rtl_bt/rtl8822cs_fw.bin` + `rtl8822cs_config.bin`, DT `realtek,rtl8822cs-bt` | `-rtl8822cs` |
| 0x024c:0xb822 | Realtek RTL8822BS | `rtw88_8822bs`, `rtw88/rtw8822b_fw.bin` | none (LIVI: btrtl knows the 8822B over USB only; UNVERIFIED) | `-rtl8822bs` = `-none` |

All firmware is pinned in `common/versions.env` and in every rootfs (sizes §7), plus `regulatory.db`.
IDs and module names VERIFIED against 7.2.10 (`include/linux/mmc/sdio_ids.h`, the drivers' ID tables,
`modules.dep`); on the board the IW416 row up to `hci0` UP is VERIFIED (2026-10-20, §7.4), and with revision 3
also the ordered loads, the Wi-Fi scan and Bluetooth discovery after `btmgmt le on` (§7.5); the rest UNVERIFIED. **Bluetooth without the DT node** (the `-none` image
on a BT chip: `btattach`/`hciattach` on `/dev/ttymxc2`) is **UNVERIFIED** and not done by `radio` (the
image has no `btattach`/`hciattach`).

**Radio tools (revision 3; owner decision 2026-10-20; build variable `RADIO_TOOLS=1`, the default, forced
to 0 with `RADIO_MODULES=0`).** Static musl, pinned and signature-checked (`common/versions.env`), none
started at boot, none with D-Bus. The radios stay OFF at boot: `radio up` first; every helper says so when
there is no wireless interface or HCI device.

| Tool | Source | For | Bytes (stripped) |
|---|---|---|---:|
| `iw` | iw 6.17 on libnl 3.12.0 | nl80211: scan, link, dev/phy info, regulatory | 339,016 |
| `wpa_supplicant`, `wpa_cli`, `wpa_passphrase` | wpa_supplicant 2.12 (`common/wpa_supplicant/wpa_supplicant.config`) | station: WPA2-PSK, WPA-PSK, open; nl80211 driver; internal crypto; control socket in `/run/wpa_supplicant` | 662,032 / 133,312 / 67,136 |
| `btmgmt` | BlueZ 5.87, readline 8.3 (+ patches 001-006), ncurses 6.6 libtinfo | the kernel's Bluetooth management socket (info, power, find, pair, ...) without bluetoothd | 425,340 |
| `hciconfig`, `hcitool` | BlueZ 5.87 `--enable-deprecated` | raw HCI: device info, inquiry (`scan`), `lescan` | 198,072 / 199,784 |
| `wifi-connect`, `wifi-scan`, `bt-scan` | this tree, `arm-imx6ul/rootfs/usr/sbin` | the helpers below | scripts |

- `wifi-connect [-i IF] [--no-dhcp] [--dry-run] [--] <ssid> [psk|-]` (`--status`, `--stop`): writes
  `/run/wifi/<if>.conf` (0600: the SSID in hex and the PSK `wpa_passphrase` derives, never the passphrase,
  never flash), runs `wpa_supplicant -B -i <if> -D nl80211 -c ... -P /run/wpa_supplicant-<if>.pid -f
  /run/log/wpa_supplicant-<if>.log`, waits for `wpa_state=COMPLETED` (`WIFI_TIMEOUT`, 30 s; on a timeout it
  names WRONG_KEY / not found / rejected from the log), then `udhcpc` with `/etc/baseline/udhcpc.sh`
  (address, default route and `/run/resolv.conf` for that interface only, never `usb0`; `/etc/resolv.conf`
  links there), and prints the state. A passphrase `-` is read from stdin (out of `ps`). `--dry-run` prints
  the configuration with the PSK masked and the commands, and writes nothing. Nothing survives a reboot.
- `wifi-scan [-i IF] [-a]`: `iw dev <if> scan`, one line per BSS, strongest first: dBm, MHz, BSSID,
  security (open, WEP, WPA-PSK, WPA2-PSK, WPA2/WPA3 = joinable with WPA2-PSK, WPA3-SAE and 802.1X = not
  joinable here), SSID (`<hidden>`); `scan dump` (the last results) when the kernel is busy; `-a` raw.
- `bt-scan [-i hciN] [-t S] [-l|-b] [-r]`: `btmgmt --index N --timeout S find` under `timeout`, one line per
  device (address, type, RSSI, name); `hcitool scan` / `lescan` when there is no btmgmt; a DOWN controller
  is refused with the `radio up` hint. **LE (B18, in revision 4, hardware-verified §7.0a):** on the IW416 unit the
  controller comes up from `radio up` with settings "powered br/edr" (LE off), and the kernel rejects the
  default (interleaved) find: `Unable to start discovery. status 0x0b (Rejected)`; after `btmgmt le on` the
  same find found LE devices, and `find -b` ran cleanly (2026-10-20, revision-3 image, §7.5). So unless `-b`,
  `bt-scan` reads `btmgmt info` and, with LE off, runs `btmgmt le on` (LE then stays on until `radio down`); a
  controller without LE, or an LE that does not come on, gets a BR/EDR-only find (`-l`: exit 1); an
  interleaved find still refused (0x0b, or 0x0c Not Supported) is retried with `-b`. Each find prints its
  mode ("BR/EDR and LE", "LE only", "BR/EDR only"); exit 1 when discovery did not start.
- **Not provided, and why.** WPA3-SAE (and OWE, DPP): wpa_supplicant 2.12 implements the elliptic-curve
  primitives (`crypto_ec_*`) only in `src/crypto/crypto_openssl.c` and `crypto_wolfssl.c`; the internal crypto
  has none, so SAE would need a static OpenSSL or wolfSSL: not cheap, not built. Whether the IW416 firmware
  and mwifiex could do SAE at all is UNKNOWN. Also not built: 802.1X/EAP, WPS, P2P, AP mode (no `hostapd`;
  wpa_supplicant without `CONFIG_AP`), D-Bus control, `bluetoothctl`/`bluetoothd` (D-Bus + GLib), a pairing
  agent, `btattach`/`hciattach`. `key_mgmt` is plain `WPA-PSK` (with optional PMF); the SHA-256 variant is
  left out until a radio is seen doing it.
- **BlueZ without GLib or D-Bus** (`common/recipes/userspace.sh` `build_bluez_tools`): BlueZ's configure
  requires GLib and D-Bus unconditionally, although btmgmt, hciconfig and hcitool use neither. The
  `GLIB_*`/`DBUS_*` configure variables are sentinels (a `-lbaseline-no-glib` reaching a link would fail the
  build, and the recipe greps the log for it), and btmgmt, whose Makefile rule links BlueZ's GLib mainloop
  (`src/libshared-glib.la`), is linked against BlueZ's own non-GLib `src/libshared-mainloop.la` (the one
  btmon and btattach use); no source file is changed. VERIFIED: the link log names only
  `libshared-mainloop.la`; on the QEMU kernel `btmgmt info` answers over the mgmt socket and `hciconfig -a`
  lists the (QEMU-dead) `hci0` (§7.0). btmgmt's interactive shell knows the terminals linux, vt100, xterm,
  xterm-256color and screen (compiled into libtinfo; the unit has no terminfo database); any other `TERM`
  gets readline's dumb-terminal mode.

### 2.6 SSH, passwords and the persist archive

- dropbear is built with `DROPBEAR_SVR_PASSWORD_AUTH 1` (`common/dropbear/localoptions.h`) and run by
  `ssh-up` (shared by recovery and rootfs) as `dropbear -E -r <key> -p 192.168.50.2:22 -P ...`.
  Deliberately not passed: `-s`/`-g` (switch password logins off), `-t` (would require password AND
  key), `-w`, `-B`. VERIFIED from dropbear 2026.94 `svr-runopts.c` (with PASSWORD_AUTH 0 the build
  accepts and ignores `-s`, so revision 1's `-s` did not break `ssh-up`; with 1 it would have disabled
  passwords) and by logins in QEMU and in a qemu-user chroot (§7.2). `common/tools/selftest.sh` fails if a
  dropbear call site passes any of those options (B2).
- Passwords: `/etc/shadow` is a link to `/run/etc/shadow`, which `persist load` seeds from the archive's
  `shadow` (after `passwd`) or `/etc/baseline/shadow.default` = `root:<ROOT_PASSWORD_HASH>::0:99999:7:::`.
  **`ROOT_PASSWORD_HASH` defaults to sha512-crypt of `baseline`, a documented, well-known DEV DEFAULT
  password**: anyone who can reach the NCM link (the USB cable) can log in as root until it is changed.
  Change it on the unit with `passwd` (kept in the archive, used by the rootfs immediately and by
  recovery from its next boot), or build with your own (`openssl passwd -6`). The banners say when the
  default is in use. (Recovery's telnet is unauthenticated anyway; the password matters for the rootfs.)
- The archive (`persist`, a tar of `/run/persist` on the 64 KiB `customer` MTD): `dropbear_ed25519_host_key`
  (+ `.pub`), `authorized_keys` (`persist add-key`), `authorized_keys.rootfs` (ssh-up keeps a copy of the
  rootfs's build-time `AUTHORIZED_KEYS` there so recovery admits them too; refreshed when it changes),
  `shadow`. The rootfs writes it on first boot (new host key), on `passwd`, `persist add-key` and when the
  build-time keys change; recovery only reads it.
- `ssh-up` exits 0 only when dropbear runs; an unusable archived key is replaced (rootfs: new key +
  save; recovery: ephemeral), a failing `dropbearkey` falls back to `dropbear -R`; every reason goes to
  `/run/log/ssh-up.log` and rcS prints it on the console with "bootstate stays set" when SSH or NCM did not
  come up (B2): SSH problems can keep the next boot in recovery, but never silently.

### 2.7 LEDs (gpio-leds, pins and polarity from LIVI's DTS; UNVERIFIED on the board for the baseline)

| State | blue | red |
|---|---|---|
| kernel booting, recovery deciding | heartbeat (kernel alive) | on |
| recovery | heartbeat | blink 500/500 ms |
| recovery, a flash helper writing | heartbeat | blink 100/100 ms |
| recovery, a write failed after it started | heartbeat | on (solid) |
| rootfs, NCM + SSH up | heartbeat | off |
| rootfs, a way in not up (reason on the console, `/run/baseline/rcS.log`) | heartbeat | on |

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
    dropbear/localoptions.h   key + password server, sftp path
    hciup/hciup.c          HCI up/down/info for radio's Bluetooth (static, musl)
    wpa_supplicant/wpa_supplicant.config   station-only build configuration (what is in, why no WPA3)
    recipes/userspace.sh   musl, BusyBox x2, dropbear, sftp-server, flash_erase, hciup, exfatprogs; radio
                           tools: libnl, iw, wpa_supplicant, ncurses, readline, BlueZ btmgmt/hciconfig/hcitool
    shared/                used by recovery AND rootfs: net-up net-down ocbm-identity ocbm-banner mtd.sh
                           usb-mount ssh-up persist
    rootfs/                skeleton: init, etc/{inittab,init.d/rcS,profile,passwd,group,shells,hostname,
                           mdev.conf}, usr/sbin/{passwd,led,reboot-recovery}
    tools/serve_once.py    host: one-shot raw TCP file server for the helpers' host:port pulls
    tools/selftest.sh      host: regression checks (syntax, dropbear options, usb-mount plans,
                           flash helpers on stand-in MTDs, password hash, stage_kernel self-test, radio
                           helpers on a stand-in sysfs with stub tools)
  arm-imx6ul/              CCPA only
    board.env              toolchain prefix, flash facts (0x302fd8/0x303080 note), chip-ID source, UDC
                           match, LEDs, MFi bus/address, radio MMC host
    kernel/*.fragment      base (strict), base-optional (warn), radio-modules, usb-host,
                           usb-vfat-builtin, exfat-builtin
    dts/                   imx6ull-ccpa-baseline.dts, imx6ull-ccpa-usbhost.dtsi, radio-*.dtsi,
                           stock-usb-reference.dtsi (not built)
    patches/0001-0004      LIVI's board patches, unchanged
    initramfs/             init, reboot, flash-lib.sh, flash-rootfs, flash-kernel, usb-update
    rootfs/etc/baseline/board-rcS.sh   LED hooks
    rootfs/etc/baseline/udhcpc.sh      udhcpc event script for wifi-connect (Wi-Fi interface only, RAM)
    rootfs/lib/baseline/radio-lib.sh   shared by the radio scripts: interfaces, wording, mod_load
    rootfs/usr/sbin/       radio (+ radio-up, radio-down links), mfi-probe, wifi-connect, wifi-scan, bt-scan
    tools/stage_kernel.py  host: kernel partition image for one unit + dry-run report + --self-test
```

---

## 4. Build order (run for real 2026-10-20, §7)

Real builds need a Linux host (the Lima VM): `make gcc ${CROSS_COMPILE}gcc ${CROSS_COMPILE}strip curl sha256sum tar xz
bzip2 patch bc flex bison perl file awk sed grep mksquashfs depmod` (`build.sh`, the tool check after
sourcing `board.env`), plus `pkg-config` for mtd-utils and iw/libnl and `tic`/`infocmp` (Debian
`ncurses-bin`, generate ncurses' built-in terminal entries) for `RADIO_TOOLS=1`. Output goes to
`TOP=/tmp/ccpa-baseline-build` (the script refuses anything under `~/Documents`, per ccpa_custom CLAUDE.md). No
toolchain is downloaded by the script. The measured build used a Debian trixie arm64 chroot inside the
Alpine `ccpa-build` VM (`apt install gcc-arm-linux-gnueabihf make bc bison flex libssl-dev libelf-dev
squashfs-tools cpio xz-utils bzip2 device-tree-compiler python3 curl file patch perl kmod pkgconf
qemu-system-arm`; for `selftest.sh` also `bsdextrautils dosfstools exfatprogs fdisk gdisk shellcheck
openssl mtools`) and `CROSS_COMPILE=arm-linux-gnueabihf-` (board.env's default `arm-linux-gnu-` is
LIVI's Fedora name). That compiler emits Thumb-2 by default, which is why `ARM_THUMB` is in
`base.fragment`.

```
sh baseline/build.sh --dry-run                     # prints every step, touches nothing
sh baseline/build.sh fetch                         # pinned tarballs, sha256-checked
sh baseline/build.sh userspace                     # musl, BusyBox full+recovery, dropbear, sftp-server, flash_erase, hciup,
                                                   # RADIO_TOOLS: libnl, iw, wpa_supplicant, ncurses, readline, BlueZ tools
sh baseline/build.sh measure                       # kernels nousb, recovery-usb-vfat, default-nossh, default; cap check
sh baseline/build.sh kernel                        # the chosen variant, one image per radio DTB
sh baseline/build.sh [AUTHORIZED_KEYS=~/.ssh/id_ed25519.pub] [ROOT_PASSWORD_HASH='$6$...'] rootfs
sh baseline/common/tools/selftest.sh               # host regression checks (no device)
```

`AUTHORIZED_KEYS` is optional since revision 2 (password login works without; `ALLOW_NO_SSH_KEYS` is
accepted and no longer needed). mtd-utils' `.asc` was verified and `MTD_UTILS_SHA256` pinned on
2026-10-20 (`common/versions.env`). `EXFATPROGS=1` stops with an error: exfatprogs 1.4.3 needs a static
libblkid the recipe does not build (§7).

## 5. Install flow (per unit; host tool first, then the unit)

1. Back up the unit (all MTDs, read twice, identical sha256) and keep its `unit_info.txt` (the four
   OCOTP words) with the backup, never in the ccpa_custom repo. (This docs repo carries the IW416 unit's backup including its
   `unit_info.txt`, `../backups/20261019_IW416_ocbm_baseline_pre-livi/`, by owner decision 2026-10-20.)
2. Host: `python3 -I arm-imx6ul/tools/stage_kernel.py --mtd0 <uboot dump> --mtd1 <current kernel dump>
   --zimage $TOP/out/<variant>/ccpa-baseline-<radio>.zimg --unit-info <unit_info.txt> --out kernel-part.img`.
   It decrypts the unit's update env with the unit's key (wrong key → refused), takes the layout from
   `norboot`/`heweiencrypt`, refuses an image without a complete appended DTB, writes the partition
   image and prints the plan (`unchanged`, differing regions, headroom, sha256). The "current kernel
   dump" must be of the partition AS IT IS NOW: after any install (U-Boot rewrote the head) re-dump it;
   `flash-kernel` refuses a stale staging (exit 4, nothing written).
3. Write the kernel partition and erase env:
   - **from our recovery** (revision 1 or 2): `flash-kernel <kernel-part.img|host:port|/mnt/usb/...> <sha256>`
     (`--dry-run` first if in doubt). `flash-kernel` does NOT clear the bootstate mark: if recovery was entered with
     `reboot-recovery`, run `flash_eraseall -q /dev/mtd5` before the final `reboot`, or the next boot stays in recovery (§7.0b);
   - **from LIVI** (same partition map): what LIVI's own provisioner does, `flashcp img /dev/mtd2 &&
     sha256sum /dev/mtd2`, then `flash_eraseall -q /dev/mtd1` (env), verify, `reboot -f`, all under
     `setsid` (`flashcp` because LIVI's rescue has no `flash_erase`, `imx6ul/boot.rs:204-231`; the
     provisioner itself was never run by us: the 2026-10-20 revision-1 write was this sequence by hand);
   - **from the vendor/OCBM system** (vendor map: env inside mtd0, kernel = mtd1): the RUNBOOK's (`../hardware_tests/2026-10-19_round_trip/`)
     LIVI procedure (push the stock-compatible `flash_erase` first, `../tools/flash_erase`; the unit has none),
     `flash_erase /dev/mtd1 0 0; cat img > /dev/mtd1; sha256sum /dev/mtd1`, then
     `flash_erase /dev/mtd0 196608 1` (byte offset, mtd-utils 1.4.8), reboot.
4. The new kernel boots into recovery (unless the rootfs MTD already holds a baseline squashfs). There:
   `flash-rootfs <host>:5611 <sha256>` with `python3 -I common/tools/serve_once.py rootfs.img` on the
   host, or (revision 2) `scp -O rootfs.img root@192.168.50.2:/tmp/` then `flash-rootfs /tmp/rootfs.img
   <sha256>`, or a stick (`/mnt/usb/rootfs.img`, or the `ccpa-baseline/` bundle); then `reboot`.
5. Back to stock (UNTESTED): the steps (rootfs split and write first, kernel last, env erase, abort gate) are
   owned by `../../../documentation/01_Firmware_Architecture/kernel_compilation.md` § Getting back from LIVI;
   this recovery uses the same map. Run from here instead of LIVI's rescue, two things differ: `flash-rootfs`
   refuses JFFS2, so the stock `mtd2.bin` parts are written by hand with `flashcp`; the kernel step can be
   `flash-kernel --restore mtd1.bin <sha256>`. Or the SPI programmer image. The unit's files are in
   `../backups/<unit>/` (for the IW416 unit, `mtd1.bin` is `../../../flash_dumps/CCPA_stripped/mtd1.bin`).
6. **Revision 3 on a unit that runs revision 2: the rootfs only** (the kernel config is unchanged and the
   41 modules are byte-identical, §7.0, so the revision-2 kernel stayed; the unit has run revision 5's since 2026-10-21, §7.0b). `flash-rootfs` exists only in the
   recovery, and the rootfs MTD must not be written from the rootfs it runs, so: (a) into recovery from the
   running rootfs, `ssh root@192.168.50.2 reboot-recovery` (sets the bootstate mark, `reboot`; the next boot
   stays in recovery; WORKED on the IW416 unit 2026-10-20, recovery up in ~30 s, §7.5), or on the UART press Enter within 1 s of "switching in 1 s"
   (also UNVERIFIED); recovery is up when `ssh root@192.168.50.2 'test -e /etc/baseline/recovery && echo RECOVERY'`
   prints RECOVERY (that file exists only in recovery; the host key is the rootfs's when the persist archive
   is readable, else an ephemeral one); (b) `scp -O rootfs.img root@192.168.50.2:/tmp/` (into recovery's RAM: a copy made from
   the rootfs before the reboot is gone); (c) `ssh root@192.168.50.2 flash-rootfs /tmp/rootfs.img <sha256>`
   (exit 0 written and verified, 3 already there, 4 refused, nothing written); (d) `ssh root@192.168.50.2
   reboot` (flash-rootfs cleared the bootstate mark, so the new rootfs boots). Password `baseline` unless it
   was changed with `passwd` (recovery reads the archived hash). Steps (a)-(d) ran on the IW416 unit 2026-10-20 (`flash-rootfs`
   under `setsid`, rc=0; §7.5).

---

## 6. Changes against LIVI, and why

| LIVI | Baseline | Why |
|---|---|---|
| Wi-Fi driver, cfg80211, MMC/SDHCI, bridge built in; hostapd + firmware + regdb in the initramfs; Wi-Fi AP as a second way in | all modules in the rootfs, loaded only by `radio up`; no AP; station and Bluetooth CLI tools (revision 3), started by hand only | owner: no radio at boot; frees image bytes |
| GPIO1_IO05 muxed in the usdhc1 group | muxed by `reg_wlan` itself | otherwise unmuxed when MMC is a module, radio power undefined |
| BT built-in pieces for the radio | serdev core only with `RADIO_MODULES=1`; BT node only in the radio images | radio optional, one rootfs |
| one DTS per radio, one kernel per radio | one kernel config/zImage, one appended DTB per radio | the DTB is the only per-radio part |
| `mwifiex.driver_mode=2` in the IW416 dtsi's bootargs | dropped; `MWIFIEX_DRIVER_MODE=... radio up` | it replaced the whole bootargs (and our `panic=10`) |
| bootargs without `panic=` | `panic=10` | a rootfs-boot panic reboots into recovery via the bootstate marker instead of hanging |
| `RD_*` initrd decompressors at their defaults | off (`base-optional.fragment`) | the built-in initramfs is uncompressed inside an XZ image; size (UNMEASURED) |
| 10.10.10.1 on br0, two telnetds (:23, :2323) on all interfaces | 192.168.50.2, no bridge, one telnetd bound to the NCM address, recovery only; dropbear (key or password) in recovery and rootfs, bound to the NCM address; no telnet in the rootfs | owner addressing; no unauthenticated network shell outside recovery |
| gadget 0525:a4a1 "LIVI Link", first UDC, random MACs | `usb-ids.conf`, UDC chosen by controller path, per-chip MACs, per-chip iSerial | owner identity decisions; a second UDC would otherwise steal NCM |
| initramfs binds the gadget (LINK_ONLY) and the rootfs bridges usb0 | the rootfs runs the same `net-up` itself; `/run` is moved across | rootfs independent of initramfs state |
| PID 1 `exec setsid cttyhack sh` | PID 1 respawns the UART shell | `exit` in that shell would kill init and panic |
| rootfs taken over if `/usr/bin/livid` exists | if `/etc/baseline-release`, `/init` and `/sbin/init` exist | our marker; a failed exec otherwise panics |
| `printf LIVIBOOT` marker | `CCPABOOT` marker, same logic (`common/shared/mtd.sh`) | do not confuse a LIVI boot state |
| provisioner on the host writes rootfs/kernel over the shell | on-device helpers that require the caller's sha256; kernel image still staged on the host | the key never needs to reach the unit |
| rescue BusyBox: brctl, vi, awk, sed, grep, xxd, pkill, killall, ... | owner's list + what the scripts call | smaller recovery |
| full BusyBox 1.36.1 defconfig, minus VT/console tools and tc | 1.38.0 defconfig + MTD/UBI tools, minus only what cannot build/work (PAM, SELinux, NFS/CIFS mount, tc, hwclock); VT tools kept | owner: as many applets as build static |
| module load order file, no modprobe | `make modules_install` + depmod; `radio` inserts each module after its dependencies from `modules.dep` (B10); BusyBox modprobe only for the kernel's own requests (`kernel.modprobe`); `mdev -d` for sd* only, no modalias rule | radio modules are loaded on demand only; MODPROBE_SMALL tries a module before its dependencies (§1) |
| livid, its web UI, mfid, btd, accessoryd | none | owner: none at boot |
| kernel-patches 0005/0006 (mwifiex rate reporting) | not carried | radio is not part of the boot; 0001-0004 carried unchanged |
| customer MTD: livid settings | persist tar (SSH host key, keys, root's hash) | stable host key and password with a read-only rootfs |
| allnoconfig, then `scripts/config` enables, then `olddefconfig` (so `PINCTRL_IMX6UL`, `NVMEM_SYSFS`, `ARM_THUMB` arrive through their Kconfig defaults) | all three named in `base.fragment` | our `merge_config.sh -n` feeds the fragment into the allnoconfig pass, which answers every visible prompt not named with n, and `olddefconfig` keeps it (INFERRED from both flows; the review found `imx6ul-pinctrl` in LIVI's shipped Image). Without them: every pinctrl-0 consumer keeps deferring (`drivers/pinctrl/devicetree.c`, MODULES=y; QEMU: gpio-mxc -517, no console), no nvmem file for the chip ID, Thumb userland refused with ENOEXEC (QEMU 2026-10-20). (Corrected 2026-10-20: this row said LIVI's config lacks the three symbols.) |

---

## 7. OPEN ITEMS / MEASUREMENTS / VERIFICATION

**Artefact map (owner-local, NOT in git; added 2026-10-20).** Build outputs, QEMU logs and test harnesses of the
2026-10-20 session are under `/Volumes/stuff/virtual-machines/ccpa-baseline-build/20261020/` (point-in-time location,
check live): `rev2/` (`default`, `default-nossh`, `nousb`, `recovery-usb-vfat`, `logs`), `rev3/` (`default`, `logs`,
`test-harness`), `rev4/default/` (the rootfs-only image, `rootfs.img` sha256 `cbfd4d39…513d`), `rev5/` (`default` = the
kernel images, `logs`, `test-harness`). The top-level `default/`, `recovery-usb/`, `recovery-usb-exfat/`, `usb-host/`
and `logs/` beside them are earlier or variant trial builds and are not mapped to a revision here. What is on the
unit is only what §7.0a/§7.0b say (rootfs revision 4 `cbfd4d39…513d`, kernel revision 5 `35dfb1a5…c871e`).

### 7.0b Revision 5 (2026-10-20): kernel-only rebuild, usbotg1 VBUS enable (flashed and VERIFIED on the IW416 unit)

Rev 5 = rev 4 sources + `dts/imx6ull-ccpa-usbhost.dtsi`: `reg_usb_otg1_vbus` (regulator-fixed, `gpio1 7`
active high, `regulator-boot-on` + `regulator-always-on`, pinctrl group muxing GPIO1_IO07 to GPIO with
`IMX_NO_PAD_CTL`, i.e. the pad settings as measured) and `vbus-supply` on usbotg1 (§1, §2.3). No other pin
or GPIO consumer touches GPIO1_IO07 (the four DTBs: pad 0x78/0x304 in that group only; gpio1 consumers
2, 5, 7, 9). Built in the `ccpa-build` VM Debian chroot, `build.sh kernel` only (`TOP=/work/build3`, `JOBS=4`,
`arm-linux-gnueabihf-`); dtc: no warnings (kbuild and a standalone dtc 1.7.2 pass with default checks,
byte-identical DTBs). `.config` byte-identical to revision 3's, the 41 modules byte-identical (sha256),
initramfs cpio 864,768 B as before; rootfs not rebuilt (revision 4's stays).

| image (zImage 2,103,992 B + DTB) | DTB | total | spare under 3,157,976 | sha256 |
|---|---:|---:|---:|---|
| `-iw416` | 26,337 | 2,130,329 | 1,027,647 | `3b79c5b62925482ff6a4b6d210d3e51e6a3746e5e9e99af79427e26ad4f25fdc` |
| `-none` = `-rtl8822bs` | 26,256 | 2,130,248 | 1,027,728 | `d9bc8f90505e8c17828c8d2e314881e0e9eac963801553d6e5ee8cb858dba12b` |
| `-rtl8822cs` | 26,312 | 2,130,304 | 1,027,672 | `c8830310d9cfa0263f1261f54b1a0702d01af5812c0419dabe2577fc9bf6ef98` |

Against revision 3: DTB +373 B (`-iw416`), zImage +3,152 B with no code rebuilt (only the initramfs, whose
file mtimes and release stamp changed, and the version object): XZ noise (§7). Decompiled `-iw416` DTB:
`regulator-usb-otg1-vbus` (`gpio = <&gpio1 7 0>`, enable-active-high, boot-on, always-on) and
`usb@2184000` `vbus-supply` → it. QEMU `mcimx6ul-evk`, `-iw416` image: recovery shell reached in 2.3 s;
`/sys/class/regulator`: `usb_otg1_vbus enabled` (bound to `reg-fixed-voltage`), `wlan disabled`; ci_hdrc.0
EHCI host started; `flash-rootfs`/`flash-kernel --dry-run` usage paths as in revision 3. Copies, logs and
the harness are kept with the build VM, not in this repo.

**Flashed and verified on the IW416 unit (2026-10-20/21).** Before the flash (revision-2 kernel, revision-4
rootfs): driving GPIO1_IO07 high by sysfs made the female port enumerate a FAT32 stick (sda1); GPIO1_IO06 did
nothing (§1). The `-iw416` image above (2,130,329 B) was staged with `stage_kernel.py` from two identical dumps
of the old kernel partition (sha256 `58b20d776149fcb295fa42a278a29c5f7ada7499fb89f4201e166b6a1bc503d8`, head
unchanged); staged partition sha256 `35dfb1a55292f079bbae397ef59e771ede05edddbfbc0b5e2f750204f17c871e` (the value now on the unit; the write was verified). From
recovery on the unit: `NO_REBOOT=1 flash-kernel <host>:<port> <sha256>` wrote and verified mtd2, erased the env,
left U-Boot unchanged (mtd0 sha256 `c60054cafb6083761c64bceb96095d6731b86db57983558b8db9810d66807bca` before and after); reboot. The unit returned in recovery at its NCM
address with the new build stamp; `/sys/class/regulator` lists `usb_otg1_vbus`; **the stick enumerated at boot
with no manual GPIO** (3.9 GB disk, one partition) and the recovery auto-mounted it **read-write**, so a stick's
contents are at risk in recovery (remount read-only by hand if it must not change). The kernel partition now
holds `35dfb1a5…c871e`; revision 2's kernel is superseded. Rootfs on the unit stays revision 4 (`cbfd4d39…513d`).
Record: `../hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md`
("Revision 5"). Rootfs follow-up (2026-10-21, kernel revision 5 + rootfs revision 4, FAT32 stick, MBR,
3.75 GiB, one partition, plugged in at boot): the stick enumerated at 1.1 s (usb 1-1, high-speed), sda1 appeared at 2.4 s,
mdev ran `usb-mount`: "/dev/sda1 (fat32, partition 1, mbr:0b) mounted read-write at /mnt/usb"; the contents listed
(19 top-level entries); 0 `Unknown symbol` dmesg lines. It mounts READ-WRITE by default (the owner remounted it
read-only by hand; nothing was written). **Rootfs mdev auto-mount of FAT32 VERIFIED on hardware**, in recovery and in the
rootfs. Layout matrix (2026-10-21, kernel revision 5 + rootfs revision 4, IW416 unit, one 64 GB stick overwritten with four 200 MB single-partition images built on the Mac with hdiutil: FAT32/MBR (0x0b), FAT32/GPT, exFAT/MBR (0x07), exFAT/GPT; the GPT images carry one basic-data partition, a2a0d0eb-e5b9-3344-87c0-68b6b72699c7, NO EFI system partition, and their backup header sits at the image end, not the disk end). Per layout: image written from the host over nc to /dev/sda, readback sha256 of the first 200 MB matched, `blockdev --rereadpt`, partition node appeared, `usb-mount` classified it correctly (fat32 mbr:0b, fat32 gpt:a2a0..., exfat mbr:07, exfat gpt:a2a0...) and mounted it read-write (vfat resp. exfat kernel driver), an 8 MiB random write + drop_caches + read-back sha256 MATCHED, and `usb-mount -u` was clean. **FAT32 and exFAT x MBR and GPT (single data partition) VERIFIED on hardware.** Also: hot-plug of the 64 GB FAT32 stick auto-mounted via mdev; a `--rereadpt` also triggered an mdev auto-mount; throughput (rough, includes sha): 32 MiB write 8.6 MB/s then 20 MB/s, 32 MiB read-back ~5 s. NOT tested: GPT with an EFI system partition ahead of the data partition, GPT with the backup header at the true disk end, an unpartitioned (superfloppy) stick, hot-plug of exFAT sticks (only rereadpt-triggered mdev), `usb-update` from a stick, RTL units. Still untested elsewhere: LEDs; Wi-Fi association. Port current: ASSUMPTION (owner-stated, NOT measured): the port is treated as 5 V, 100-500 mA, the USB 2.0 minimum for data transfer and for an iPhone to connect for CarPlay; the real limit remains unmeasured.
**Boot-loop guard trap:** after the kernel flash the guard still held the mark set by the preceding `reboot-recovery`,
so the first plain `reboot` stayed in recovery until `flash_eraseall -q /dev/mtd5` (bootstate) cleared it.
`flash-rootfs` clears the mark, `flash-kernel` does not (it never touches bootstate): after a kernel flash made from
recovery that was entered via `reboot-recovery`, run `flash_eraseall -q /dev/mtd5` before the `reboot`. OPEN: make
`flash-kernel` clear it.

### 7.0a Revision 4 (2026-10-20): rootfs-only rebuild with the B18 `bt-scan` fix, flashed and verified

Rev 4 = rev 3 sources at ccpa_custom `9dc14d8`; the only difference is `bt-scan` (and the rootfs build stamp).
Built in the `ccpa-build` VM Debian chroot, `build.sh rootfs` only (`TOP=/work/build3`); the kernel was not
rebuilt or reflashed (the kernel partition kept revision 2's image until revision 5). `rootfs.img` 3,506,176 B (same size as
revision 3; 9,469,952 B free), sha256 `cbfd4d3943a1352ff2ef279f4800ed5efb2def933a2d1f884f425fd4705e513d`; the image's
`usr/sbin/bt-scan` equals the tree file. The image is kept with the build VM, not in this repo.
Flashed on the IW416 unit from recovery (`reboot-recovery`, `scp -O` to `/tmp`, `flash-rootfs`: wrote and
verified mtd3, bootstate cleared, rc=0; reboot): the unit returned at its NCM address with the new
`/etc/baseline-release`. Hardware: `radio up` then `bt-scan` reported that LE was off (settings "powered
br/edr") and enabled it (`btmgmt le on`, on until `radio down`), then ran `btmgmt find` (BR/EDR and LE, at most
15 s) and printed a device table (many LE devices; none recorded here): **B18 VERIFIED on hardware**.
`radio down` clean, 0 `Unknown symbol` dmesg lines. Record:
`../hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md` ("Revision 4 follow-up").

### 7.0 Revision 3 (2026-10-20): measured, tested, changed

Built from a clean `$TOP` (`/work/build3` in the Debian chroot of the `ccpa-build` VM; the older pinned
tarballs copied in, the new ones fetched by `build.sh fetch`, every sha256 checked), gcc 14.2.0
`arm-linux-gnueabihf-`, `JOBS=4`: `fetch userspace`, then `kernel rootfs`; the `rootfs` step was re-run
twice after script edits (the image below is the last); `measure` was not re-run (kernel config
unchanged). Images, logs and the test harness are kept with the build VM, not in this repo.

| | revision 2 | revision 3 |
|---|---:|---:|
| `default` zImage | 2,101,176 | 2,100,840 (-336 B: build number/timestamp, the noise §7 describes) |
| `-iw416` image (zImage + DTB) / spare under 0x302fd8 | 2,127,140 / 1,030,836 | 2,126,804 / 1,031,172 |
| kernel `.config` | — | identical but for `CONFIG_INITRAMFS_SOURCE`'s path |
| the four DTBs; the 41 modules and `modules.dep` | — | byte-identical (sha256 per file) |
| **rootfs squashfs** (cap 12,976,128) | 2,560,000 | **3,506,176** (9,469,952 free) |

sha256: **`rootfs.img` `98fa6312a53d9f19f4a3282a93bddee5e01e2b0971d75bbc9da361b35a9273d7`**; kernel images,
NOT needed on a revision-2 unit: `-iw416` `d0030180fd02fa305d55c58ec7119a7011ed781a888016ccb2e0acd456d8181a`,
`-none`/`-rtl8822bs` `0a257d32c2899925f0346c561307a9dae8a183e1a8b563e14ad702b9953d6874`, `-rtl8822cs`
`268c99dc1bf2dfa5eec49c94629df6bace5caa3d07c46aa1e7116e4ac99894f7` (revision 2's `-iw416`, the one the unit
ran until revision 5: `2d43437ba38ad19bc94313cf576e2b95b91bbb91e28094498cdaa99c2c345c17`). Tool sizes: §2.5 (7 binaries,
2,024,692 B uncompressed; `hciup` 66,796 B as before).

Tests (logs kept with the build VM):
- **Host self-test** (`common/tools/selftest.sh`): Debian chroot **118 checks PASS** (helpers under dash);
  Alpine VM host 74 PASS (helpers under BusyBox ash with BusyBox tools; stick images, openssl, shellcheck
  skipped there). shellcheck: 0 errors, 87 warnings (86 SC2034 for the sourced env/conf/lib files, 1 SC2154
  in build.sh's eval loop). New section 8, stand-in sysfs/run + stub tools: B10 (a stand-in `insmod` that
  refuses a module before its dependencies; `mod_load` order for mwifiex, btnxpuart and the sdhci stack,
  incl. a `modules.dep` line listing the most basic module first; `driver_mode` lands on mwifiex; the
  already-loaded note), B11 (`radio status` and `radio up` print the same wording; IFF_UP clear reads
  "administratively down"), B15 (`wifi-connect`: no radio → exit 1 with the `radio up` hint; `--dry-run` on a
  missing interface prints the plan with the PSK masked and writes nothing; a 7-character passphrase and a
  33-byte SSID are refused; a passphrase from stdin; a 64-hex PSK; a run with stub daemons: 0600 config in
  `/run` with the hex SSID and the PBKDF2 PSK (checked against Python's), the passphrase nowhere in `/run`,
  the exact `wpa_supplicant` and `udhcpc` command lines, `udhcpc.sh` touching the Wi-Fi interface only;
  `--stop`; no flash or `/etc` write in the code), B16 (`wifi-scan` on a canned iw 6.17 scan: order, the
  security classes, an SSID with a space, a hidden SSID), B17 (`bt-scan`: no HCI; a btmgmt stub with a
  repeated device; `-t` passed through), and nothing in init, rcS, inittab or mdev.conf starting a radio
  tool or loading a module. `stage_kernel.py --self-test` 50 checks (B12: a byte flipped in the FDT area, at
  0x800 and in the stored second CRC, each with the first CRC intact, refused, the message naming the
  second CRC).
- **ARM chroot** of the unpacked image (qemu-user; own network namespace with a dummy `fake0`; private tmpfs
  `/dev`; the VM kernel has no nl80211 and no Bluetooth): `iw version 6.17`, `wpa_supplicant v2.12`, `wpa_cli
  v2.12`, `btmgmt: 5.87`, `hcitool ... ver 5.87`, `btmgmt --help`; `wpa_passphrase` (stdin) = Python's PBKDF2;
  `iw dev` "Failed to connect to generic netlink", `btmgmt info` "Unable to open mgmt_socket", `hciconfig`
  "Address family not supported by protocol"; with no radio, `radio status`, `wifi-connect`, `wifi-scan`,
  `bt-scan` give the `radio up` hint (the last three exit 1); `wifi-connect --dry-run -i fake0`: "fake0 is not
  a wireless interface (no phy80211)", plan printed, `/run` untouched; the real `wpa_supplicant` started by
  `wifi-connect` (lo posing as wireless on a stand-in sysfs) took the command line and stopped at "nl80211:
  Failed to connect to generic netlink", which `wifi-connect` reported with the log (config 0600, no
  passphrase in it); `mfi-probe` waited 2 s for a lock held 2 s and gave up after 11 s on one held 14 s
  ("the MFi lock is busy"); image content `until flock -n 9` and `mod_load mwifiex driver_mode=`; every new
  script `sh -n` with the image's BusyBox.
- **QEMU** `mcimx6ul-evk`, revision 3's `-iw416` image: recovery as in revision 2 (no MTD in QEMU).
  **The real rootfs image booted in QEMU**: a TEST-ONLY kernel (revision 3's config + `CONFIG_MTD_PHRAM=y`,
  nothing else; never flashed) with the `-iw416` DTS + a `phram` MTD named `rootfs` over reserved RAM at
  0x87000000 that QEMU's loader fills with `rootfs.img`: recovery found the squashfs on `mtd0`, waited its
  1 s, ran `switch_root`; rcS ran (`mdev -d`; NCM failed: no UDC in QEMU; no chip identity: QEMU's OCOTP
  reads zero); `/` is `/dev/mtdblock0`, whose first 3,506,176 B hash to the image's sha256. In it: `radio
  status` (radios off); `radio up` (sdhci stack loaded; QEMU has no SDIO card: "no SDIO card enumerated in
  10 s"); `mod_load` of cfg80211, mwifiex, mwifiex_sdio, bluetooth, btnxpuart, hci_uart, rtw88_8822cs,
  rtw88_8822bs: **0 `Unknown symbol` lines** (32 modules loaded; btnxpuart printed "FW already running", then
  HCI timeouts: no controller behind QEMU's UART); `iw dev` rc 0 (no phy), `iw reg get` answers (nl80211 on
  the real kernel); `btmgmt info` "Index list with 0 items" (mgmt socket, no bluetoothd); `hciconfig -a`
  lists `hci0` DOWN; `wifi-connect`, `wifi-scan`: the `radio up` hint; `bt-scan`: "hci0 is down"; `radio down`:
  "radio off". **Control, same boot**: after `radio down`, BusyBox `modprobe mwifiex_sdio` logged 70 `Unknown
  symbol` lines and `modprobe btnxpuart` 2: the unit's burst, reproduced.
- `stage_kernel.py`, report only (no `--out`): the `-iw416` image against `/tmp/ccpa/mtd2_rev1_a.bin` (the
  IW416 unit's kernel partition in its REVISION-1 state, dumped before revision 2 went in) and the
  LIVI-state `mtd0_dump.bin`: both CRCs OK, kernel_len 0x302fd8, headroom 1,031,172 B, head unchanged against
  that dump, body 1,922,955 B and staging 195,832 B differ. STALE for the unit (revision 2's install rewrote
  the head; `flash-kernel` would refuse it, exit 4) and not needed: the kernel stays.
- Not testable in QEMU or the chroot: any radio hardware (no SDIO card, no BT controller, no nl80211 phy),
  association, DHCP over Wi-Fi, discovery, the UDC, real QSPI (phram is RAM), `reboot-recovery`.

CHANGES in revision 3:

| ID | Was | Now | Regression check |
|---|---|---|---|
| B10 | `radio` loaded with BusyBox `modprobe` (MODPROBE_SMALL): its first lookup insmods the module before its dependencies, then retries: the `Unknown symbol` burst on the unit | `mod_load` (`radio-lib.sh`): each module after the dependencies on its own `modules.dep` line, with insmod, whatever the order on the line | selftest stand-in insmod; QEMU 0 lines vs. 70 / 2 with `modprobe` |
| B11 | `radio up` printed `mlan0 up` (admin state), `radio status` operstate `down` | both print `administratively up|down, carrier|no carrier (operstate X)` (`ifstate`) | selftest |
| B12 | `stage_kernel.py` checked the env's first CRC only | both CRCs; a mismatch is refused | self-test (4 cases); three real dumps |
| B13 | `mfi-probe`'s `flock -n` poll was in the tree only | in the image | ARM chroot (locks held 2 s / 14 s) |
| B14 | `radio`'s `driver_mode` on `mwifiex` was in the tree only | in the image | image content; selftest |
| B15-B17 | no Wi-Fi/BT tools | iw, wpa_supplicant/wpa_cli/wpa_passphrase, btmgmt, hciconfig, hcitool; `wifi-connect`, `wifi-scan`, `bt-scan`; `/etc/resolv.conf` → `/run/resolv.conf` | selftest section 8, ARM chroot, QEMU |

AFTER revision 3 (in the revision-4 image, flashed on the unit 2026-10-20, §7.0a; the revision-3 image had the old
`bt-scan`):

| ID | Was | Now | Regression check |
|---|---|---|---|
| B18 | `bt-scan` ran `btmgmt find` as asked; on the IW416 unit (2026-10-20, §7.5) the controller is "powered br/edr" after `radio up` and the default find was rejected (`status 0x0b (Rejected)`) | unless `-b`: `btmgmt info`, then `btmgmt le on` when LE is off (unsupported or failed: BR/EDR only, `-l` exit 1); a refused interleaved find (0x0b/0x0c) is retried `-b`; each find names its mode; exit 1 when discovery did not start | selftest B17/B18 (stateful btmgmt stub following the kernel's rule: LE off enabled, LE already on, 0x0b retry, `-l` refused, no LE, `-b`): Debian chroot 123 checks PASS (helpers under dash), Alpine VM 79 PASS (BusyBox ash); shellcheck 0 errors, 87 warnings (unchanged); `dash -n`; **VERIFIED on hardware** 2026-10-20 (revision 4, §7.0a) |

MEASURED 2026-10-20, revision 2 (clean build from an empty `$TOP` except the pinned tarballs, linux
7.2.10 + patches 0001-0004, gcc 14.2.0 `arm-linux-gnueabihf-`, `RADIO_MODULES=1 RADIO_FW=1`:
`fetch userspace measure kernel rootfs`, run time and `JOBS` unrecorded; the rootfs was rebuilt from the final
tree after two comment/style fixes in `radio` (the rootfs tests below ran on that final image); build logs, images and test logs
are kept with the build VM, not in this repo):

| Kernel image (zImage + appended DTB, cap 0x302fd8 = 3,157,976 B) | zImage | DTB | total | spare |
|---|---:|---:|---:|---:|
| **`default`** (recovery USB + exFAT + SSH), `ccpa-baseline-none.zimg` | 2,101,176 | 25,883 | **2,127,059** | 1,030,917 |
| `default`, `-iw416` (BT node `nxp,88w8987-bt`) | 2,101,176 | 25,964 | 2,127,140 | 1,030,836 |
| `default`, `-rtl8822cs` (BT node `realtek,rtl8822cs-bt`) | 2,101,176 | 25,939 | 2,127,115 | 1,030,861 |
| `default`, `-rtl8822bs` (no BT node; byte-identical to `-none`) | 2,101,176 | 25,883 | 2,127,059 | 1,030,917 |
| measure: `nousb` (SSH, no USB) | 1,932,752 | 25,855 | 1,958,607 | 1,199,369 |
| measure: `recovery-usb-vfat` (SSH + USB, no exFAT) | 2,079,768 | 25,883 | 2,105,651 | 1,052,325 |
| measure: `default-nossh` (USB + exFAT, no SSH) | 1,902,416 | 25,883 | 1,928,299 | 1,229,677 |
| measure: `default` | 2,103,560 | 25,883 | 2,129,443 | 1,028,533 |

| Other | bytes |
|---|---:|
| recovery initramfs, uncompressed cpio inside the XZ kernel: `default` / `default-nossh` / `nousb` | 864,768 / 330,240 / 849,408 |
| recovery BusyBox (allnoconfig + `recovery.applets`, 49 links), static, stripped | 263,608 |
| full BusyBox (defconfig + `full.fragment`, 410 links), static, stripped | 984,580 |
| dropbearmulti (dropbear dbclient dropbearkey scp; password auth on) | 330,160 |
| OpenSSH sftp-server | 197,840 |
| mtd-utils flash_erase / hciup | 66,840 / 66,796 |
| **rootfs squashfs with ALL radio firmware** (cap 0xc60000 = 12,976,128), sha256 `c424cd3c...` | **2,560,000** (10,416,128 free) |
| rootfs content before compression: modules / radio firmware + regdb / everything else | 3,467,401 / 836,709 / 1,707,520 |
| firmware: IW416 combo / rtw8822c / rtw8822b / rtl8822cs BT + config / regulatory.db | 403,148 / 202,600 / 161,240 / 63,340 + 33 / 6,348 |

- Costs (measure builds, one config apart): USB storage + vfat in recovery +147,044 B; exFAT +23,792 B;
  recovery SSH (dropbear, sftp-server, passwd/shadow files) +201,144 B. The same `default` config built
  twice came out 2,384 B apart (2,129,443 in `measure`, 2,127,059 in `kernel`: new build number and
  release minute inside the XZ stream): treat the last ~2.5 KB of any delta as noise.
- Against revision 1 (§7.2 of ccpa_custom `333b5a4`; historical): its `default` (no USB, no SSH) was 1,753,695 B in
  that revision's measure build (the image flashed on 2026-10-20, a later build of the same config, was
  1,755,383 B: zImage 1,729,528 + DTB 25,855), its `RECOVERY_USB=1 RECOVERY_EXFAT=1` 1,918,859 B; revision
  2's `default-nossh` (the same features plus the new scripts, tar and 64-bit shell arithmetic) is
  1,928,299 B. LIVI's image was 3,124,994 B (zImage 3,099,160 + DTB 25,834; its built-in initramfs alone
  inflates to 1,410,344 B; `../livi/README.md`).
- The individual effect of the `RD_*` decompressors and of each dropped LIVI component was not
  separated (no LIVI-config build was made).
- QEMU only: boot time and RAM on the real CCPA remain UNMEASURED.

### 7.1 Changes from the dry run (2026-10-20 real build, revision 1)

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

Revision 2's build needed one fix of its own test tooling only (`selftest.sh`: hexdump is in Debian's
`bsdextrautils`; `sgdisk` has no `-q`). No DTS or patch change was needed in either revision; the
patches are byte-identical to LIVI's below their header.

### 7.2 Tests (2026-10-20, revision 2)

Host (`common/tools/selftest.sh` in the Debian chroot, 86 checks PASS; once more on the Alpine VM host,
whose `sh`/`dd`/`hexdump` are BusyBox: 47 checks PASS, stick images and openssl skipped there): every
script `sh -n` and `dash -n`; shellcheck 0 errors (66 warnings: 65 SC2034 for the sourced env/conf files,
1 SC2154 in build.sh's eval loop; the rest are notes); no dropbear call site with
`-s/-g/-t/-w/-B`; `usb-mount --plan` on 8 synthetic sticks (MBR FAT32, GPT ESP+FAT32 → partition 2, MBR
exFAT, MBR ESP 0xEF + FAT32 → partition 2, FAT on the whole disk, protective MBR without GPT → nothing,
extended-only, non-FAT → nothing); `flash-kernel`/`flash-rootfs` on plain files standing in for the MTDs:
fresh install `--dry-run` 0, wrong sha256 4, no staged head 4, short image 4, **already installed (only the
head differs) 3, also without `--if-changed`**, stale image (head and body differ) 4, partition already equal
3/`--dry-run` 0, env at the wrong flash offset 4, usage 2, the partition unchanged in every case;
flash-rootfs no magic 4, wrong sha256 4, already on flash 3; `DEV_PASSWORD_HASH` = `openssl passwd -6
-salt ccpabaseline baseline`; `stage_kernel.py --self-test` PASS (46 checks).
- **B1 regression check**: the self-test runs `ocbm-identity` (dash and sh) against a plain file AND
  through a `dd` that refuses sub-word reads of the nvmem file (the sysfs contract), asserts the serial/MACs
  equal `usb_identity()`, that the serial is not sha256("")'s, and that an empty source is refused with
  no serial written. Against revision 1's `ocbm-identity` the same self-test FAILS 6 checks (run
  2026-10-20); against this one it passes.
- **B4**: `stage_kernel.py` with the real zImage of this build without its DTB: refused (exit 2, "image has
  no appended DTB ... vendor U-Boot's own FDT would take over"); self-test cases for no and truncated DTB.

QEMU `-M mcimx6ul-evk -m 128M -kernel <image>` (appended DTB, no `-dtb`; QEMU models an i.MX6UL, not the
ULL), one emulated USB stick on usbotg1 (`-device usb-storage,bus=usb-bus.0`), harness feeding the UART
shell (logs kept with the build VM):
- `-none` + FAT32 stick (MBR): recovery reached; `usb-update` mounted `/dev/sda1` **vfat rw,noatime** at
  `/mnt/usb`, found the bundle, `flash-rootfs` refused (no MTD in QEMU: exit 4 "nothing written"), logged
  only, nothing on the console, no reboot; again by hand with the stick still in: same, calm; write to the
  stick, `usb-mount -u`, `usb-mount` again: OK. **B1 on a real kernel**: `dd bs=1 skip=4 count=8` of the
  sysfs nvmem file yields **0 bytes**, `bs=4 skip=1 count=2` **8 bytes**; `ocbm-identity` refuses QEMU's
  all-zero OCOTP. **SSH fallback** (no customer MTD): ephemeral host key, `persist load` seeds the default
  hash, `dbclient` password login with `baseline` OK, a wrong password refused, `persist save` refused in
  recovery. **SSH option 1** (`PERSIST_DEV=/mnt/usb/customer.tar`, an archive as the rootfs writes it):
  dropbear runs with the archived host key (fingerprint matches), key login with
  `authorized_keys.rootfs` OK, the archived password OK, `baseline` then refused; **SFTP** subsystem
  answers SSH_FXP_INIT with SSH_FXP_VERSION 3; legacy **SCP** (`scp -S dbclient`) copies a file.
  `ps`: `dropbear -E -r <key> -p 127.0.0.1:22 -P /run/dropbear.pid` (no `-s`).
- `-iw416` + GPT stick (ESP FAT32 + data FAT32, a marker file on each): `sda1 (gpt:28732ac1...): EFI
  System Partition, skipped`, **`/dev/sda2` mounted rw**, the marker reads "THIS IS THE DATA PARTITION".
- `-rtl8822cs` + exFAT stick (MBR type 7): `/dev/sda1` **exfat rw,noatime,iocharset=utf8** at `/mnt/usb`,
  write OK. The two radio DTBs boot to the same recovery (their BT drivers are rootfs modules).
- Rootfs userspace in a chroot of the unpacked squashfs through qemu-user (ARM binaries, own network
  namespace; not a boot: no rootfs `/init`, no MTD, no gadget, no mdev daemon): first `persist load` on an
  erased stand-in partition, `ssh-up` makes and saves a host key; password login; `passwd` (busybox,
  through the `/etc/shadow` link, sha512-crypt) + persist; new password OK, old refused; SFTP VERSION 3
  through dropbear; `persist add-key` + key login; simulated reboot (`/run` emptied, `persist load`): same
  host key, new password and added key still work; `usb-mount --plan` with the rootfs BusyBox gives the
  host self-test's verdicts on all 8 sticks; `mdev -s` with `etc/mdev.conf` on a private `/dev`: no
  parse error, 0 nodes created; `radio status`, `mfi-probe`, `led`, `hciup -i` report the missing
  hardware and exit.
- QEMU cannot test: the USB gadget (its chipidea model has no device mode, so no UDC, no NCM, no telnetd,
  and SSH was tested on 127.0.0.1), QSPI (no model: no MTD, no rootfs boot, no bootstate, no flash
  write), OCOTP (reads zero), the LEDs', `reg_wlan`'s and the radio module's real pins, the vendor U-Boot
  path and its `heweiencrypt` staging.
- `stage_kernel.py` (report only, no `--out`) for the IW416 unit's LIVI-state dumps
  (`../backups/20261020_livi_pre-baseline/mtd0_dump.bin`, `mtd2_dump1.bin`; fuse words from
  `../backups/20261019_IW416_ocbm_baseline_pre-livi/unit_info.txt`, not printed) and `ccpa-baseline-iw416.zimg`:
  update env decrypts (gzip + CRC OK, 15 variables), kernel_len 0x302fd8, staging partition offset
  0x302fd8, appended DTB at 0x200fb8 (25,964 B), headroom 1,030,836 B, head unchanged, body 2,917,106 B
  and staging 195,830 B differ. That plan went stale when the unit took revision 1 (U-Boot rewrote the
  head); for revision 2, `mtd2` was re-dumped and re-staged on 2026-10-20 (§7.4).

Revision 1's tests (QEMU boot of `default` and `RECOVERY_USB=1` to the recovery shell, `/run`
nosuid,nodev, `mount -o move`, `reboot`; `usb-update` finding a vfat bundle; `stage_kernel.py` against the
IW416 unit's stock `mtd0.bin`/`mtd1.bin` refusing an image 1 B over the cap) are in ccpa_custom commit `333b5a4`.

### 7.3 CHANGES in revision 2 (2026-10-20)

| ID | Was | Now | Regression check |
|---|---|---|---|
| B1 | `ocbm-identity` hashed `dd bs=1 skip=4 count=8` of the sysfs nvmem file; sysfs refuses sub-word reads, so every unit hashed nothing (CONFIRMED ON HARDWARE: `OCBM-e3b0c44298fc`; shared MACs INFERRED from the shared hash, not read) | one `dd bs=4` read of two words into a private file, length/zero/empty-hash checks, hash and hex from that file | self-test sysfs-like `dd`, QEMU real sysfs (0 vs 8 bytes); on the unit 2026-10-20 the serial is unit-specific (§7.4) |
| B2 | `ssh-up` ran `dropbear -s`: harmless with PASSWORD_AUTH 0 (2026.94 accepts and ignores it), it would disable password logins with 1 | no `-s/-g/-t/-w/-B`; `ssh-up` exits 0 iff dropbear runs, falls back (new/ephemeral key, `-R`); rcS prints the reason when bootstate stays set | selftest call-site check; QEMU and chroot logins |
| B3 | after a successful install a stick's (or file's) `kernel-part.img`, staged before it, failed the head check on every recovery boot and usb-update printed "DO NOT POWER OFF" | "already installed" (all but the head equal) = exit 3, nothing written; refusals = exit 4 "nothing written"; usb-update logs 3/4 only; DO NOT POWER OFF only after a started write | selftest stand-in MTDs (3, 4, 0) |
| B4 | `stage_kernel.py` only reported a missing appended DTB | refuses it (and a truncated one): the vendor FDT would take over, no console | self-test cases; real zImage refused |
| B5 | README: "never flashed" | revision 1 flashed 2026-10-20 (Status) | — |
| B6 | recovery `init` blanked `kernel.modprobe` for good (the sysctl survives switch_root) | rootfs `/init` writes `/sbin/modprobe` back; scope documented (§2) | `modules.alias` review (no MMC/radio alias the kernel can request) |
| B7 | `arm-imx6ul/rootfs/etc/.DS_Store` (and others) would be packed by `cp -R` | deleted; `build.sh` strips `.DS_Store`/`._*` from the rootfs work tree and fails if any remain | build check (a rootfs built from a copy with a planted `.DS_Store` and `._mdev.conf`: 0 in the image), selftest note |
| B8 | `base.fragment`/README: LIVI lacks `PINCTRL_IMX6UL` | the reason is our merge_config -n flow (§6); three symbols kept | — |
| B9 | stage_kernel/flash-kernel assumed 0x302fd8 silently | note in `board.env`, `flash-kernel`, `stage_kernel.py` (0x303080 on build 2025.02.25.1521) | — |
| — | recovery: UART + telnet only, USB opt-in vfat read-only | + SSH/SCP/SFTP (key from the archive or password), USB + exFAT default, MBR/GPT/ESP-aware mount rw at /mnt/usb, `flash-kernel --dry-run` | QEMU |
| — | rootfs: key-only SSH, manual `usb-mount`, no radio tooling | password + key, `passwd` persisted, mdev auto-mount, `led`, `mfi-probe`, `radio`, `hciup` | chroot |
| — | `RADIO_DT` built one kernel per radio | one zImage + one DTB per radio (`ccpa-baseline-<radio>.zimg`); variant `default` now = USB+exFAT+SSH, old default = `nousb` | build |
| — | `AUTHORIZED_KEYS` required | optional (password login) | build |
| — | `radio-iw416.dtsi` called mwifiex `driver_mode=2` "uap0 next to the station" | 2 = uAP only, 0x3 = AP + station (mwifiex `main.c`) | — |

OPEN (hardware; corrected 2026-10-20: this list said nothing had run on the board. What revision 2 has
proven there is in §7.4, revision 3 in §7.5; the rest stays here; revision 3 updates inline):
- revision 3 on the IW416 unit (flashed 2026-10-20, §7.5). DONE there: `radio up` with 0 `Unknown symbol`
  lines (B10), the B11 wording, `wifi-scan`, Bluetooth discovery after `btmgmt le on`, `mfi-probe`, `radio
  down`. Still OPEN: `wifi-connect <ssid> <psk>` against a WPA2-PSK network (and an open one), the DHCP lease,
  default route and DNS, `wifi-connect --stop`, `radio down` after it; `hcitool scan`; (B18's `bt-scan`:
  closed 2026-10-20, revision 4, §7.0a);
- (Closed 2026-10-20, §7.5: `mfi-probe` on the revision-3 image read DeviceVersion 0x03 and certificate
  length 945 B; the revision-2 `flock -w` failure is gone with B13.)
- revision 2 parts not yet exercised: the MACs, key-only SSH login and a host key reused across a reboot
  (the archive `persist save` wrote to the real `customer` MTD on revision 2's first boot WAS read back
  after reboots, `persist: loaded from mtd4`, §7.5; the host key in it was not compared), `usb-update` (mdev USB
  auto-mount of FAT32 is VERIFIED on the unit, 2026-10-21, §7.0b), the `/dev/mtdNro` read path, the restored `kernel.modprobe`, the 1 s
  UART-Enter window into recovery (`arm-imx6ul/initramfs/init:56-63`). (`reboot-recovery` from the rootfs
  WORKED 2026-10-20, §7.5.)
- `radio`'s `driver_mode` fix (§2.5: `mwifiex driver_mode=<n>` before `mwifiex_sdio`): in the revision-3
  image (B14), on the unit since 2026-10-20 (§7.5); AP mode itself is UNVERIFIED (no `hostapd`, wpa_supplicant without AP mode);
- female port (usbotg1): its real current limit (UNMEASURED; design ASSUMPTION, owner-stated: 5 V, 100-500 mA, §7.0b), and mainline chipidea host behaviour beyond enumeration and FAT32 auto-mount; the
  VBUS enable is GPIO1_IO07 (MEASURED 2026-10-20, §1; in the DT since revision 5, VERIFIED on the unit, §7.0b);
  (corrected 2026-10-20: this item asked whether VBUS is switched at all);
- whether the radio module really is unpowered with `reg_wlan` off on every SKU (polarity from LIVI and
  the stock DTB; the claim that it powers the module comes from LIVI's comment; on the IW416 unit `radio
  down` left no SDIO card, which shows the card gone, not the rail at 0 V), and the `radio` steps on
  RTL8822CS/BS (IW416 power, SDIO, drivers, firmware and `hci0` UP VERIFIED 2026-10-20, §7.4);
- from the IW416 radio test (2026-10-20): (a) the `Unknown symbol` burst during `radio up`: cause traced to
  BusyBox MODPROBE_SMALL (§1), fixed in revision 3 (B10), verified in QEMU and **on the unit (0 lines, §7.5)**;
  (b) `radio up`'s `mlan0 up` against `radio status`'s operstate `down`: reworded (B11), **verified on the
  unit** (§7.5); (c) the tooling gap: owner decision 2026-10-20, station Wi-Fi and Bluetooth CLI tools added
  (§2.5), scan and discovery verified on the unit; AP mode and pairing still have none (no `hostapd`, no
  agent);
- (Closed in revision 3, B12: `stage_kernel.py` checks the update env's second CRC32.) Still open:
  `flash-kernel`'s staged-head probe at 0x302fd8 is a probe, not a check of the staged head (§1), and no
  0x303080 unit has been tested;
- LED behaviours (the `blue`/`red` class devices exist, §7.4). (`mfi-probe`'s registers and repeated-start
  read: verified on the unit 2026-10-20, §7.5; not cross-checked with busybox `i2ctransfer`.)
- (Closed 2026-10-20, §7.4: the stock vendor U-Boot boots revision 2's larger kernel image, 1.03 MB under
  the cap.)

### 7.4 Hardware: revision 2 on the IW416 bench unit (2026-10-20)

Observed on the unit (record with every hash:
`../hardware_tests/2026-10-20_baseline_rev2_kernel_rootfs.md`):
- from revision 1's recovery: `mtd2` dumped twice, identical; `stage_kernel.py` head unchanged, headroom
  1,030,836 B; `flash-kernel <host>:5611 <sha256>` with `NO_REBOOT=1` wrote and verified `mtd2`, erased
  env, U-Boot unchanged; reboot: **revision-2 recovery up within 28 s** (the first ping poll, 28 s after the reboot command, answered) at 192.168.50.2, USB serial
  unit-specific (B1 fixed; revision 1 had `OCBM-e3b0c44298fc`), dropbear 2026.94 password login;
- `scp -O rootfs.img` (2,560,000 B, sha256 checked on the unit), `flash-rootfs` wrote and verified `mtd3`,
  cleared bootstate; reboot: **rootfs booted**, rcS finished (NCM 192.168.50.2, ssh/scp/sftp, `mdev -d`,
  udhcpd, bootstate cleared); persist: `persist load` found no baseline archive in `mtd4`, so the build's `ROOT_PASSWORD_HASH` applied; `sftp`
  ls; BusyBox v1.38.0 with 410 applets; MemAvailable ~114 MB; `/dev/i2c-0`, `/dev/i2c-1`; LEDs `blue`
  and `red` present; `radio status` reports the radios off;
- first rootfs boot: `persist load` found no baseline archive in `mtd4`, `ssh-up` made a host key and saved
  the archive there (`common/shared/ssh-up:61`), overwriting whatever `mtd4` held (prior contents unknown:
  `mtd4` was never dumped); the save was read back on the later revision-3 boot (`persist: loaded from
  mtd4`, §7.5; updated 2026-10-20, this said "not read back");
- `radio up` / `radio down` on the IW416 (record `2026-10-20_baseline_rev2_radio_iw416.md`, next to the
  record above): `reg_wlan` on, SDIO `0x02df:0x9159`, `mwifiex_sdio` (`phy0`, `mlan0` admin-up, operstate
  down, no association tried), `btnxpuart` ("FW already running", `hci0` UP with a BD address); `radio
  down`: only `usb0` and `lo` left, no SDIO card (module `bluetooth` stays loaded); OPEN items in §7.3;
- found: `mfi-probe` fails on `flock -w` (fixed in revision 3's image, B13, §7.0; verified on the unit, §7.5).
NOT yet tested: USB stick mount, key-only login and a saved key across a reboot, LED behaviours, Wi-Fi
association/scan/AP and Bluetooth pairing/traffic (no tools in the revision-2 image; revision 3 has the
station and CLI tools, §2.5; flashed later, §7.5), RTL8822CS/BS.

### 7.5 Hardware: revision 3 rootfs on the IW416 bench unit (2026-10-20)

Observed on the unit (record:
`../hardware_tests/2026-10-20_baseline_rev3_rootfs_radio_iw416.md`). Rootfs only; the
kernel was revision 2's `-iw416` (`2d43437b…`, §7.0; replaced by revision 5, §7.0b):
- from the revision-2 rootfs, `reboot-recovery`: **recovery up in ~30 s** (`/etc/baseline/recovery` present,
  `/proc/cmdline` with `panic=10`);
- `scp -O rootfs.img` (3,506,176 B, sha256 `98fa6312…9273d7` checked on the unit); `flash-rootfs` under
  `setsid`, rc=0, "wrote and verified mtd3", bootstate cleared; reboot: **revision-3 rootfs booted**: rcS
  `persist: loaded from mtd4` (the archive revision 2's first boot saved survived reboots: persist save and
  load VERIFIED; host-key reuse not checked separately), `persist: root password = build default`, NCM and
  SSH up, bootstate cleared; `iw`, `wpa_supplicant`, `wpa_cli`, `btmgmt`, `hciconfig`, `hcitool`,
  `wifi-connect`, `wifi-scan`, `bt-scan`, `mfi-probe`, `radio` present;
- `radio up`: **0 `Unknown symbol` lines in dmesg** (B10 VERIFIED on hardware); "mlan0 administratively up,
  no carrier (operstate down)" (B11 VERIFIED); `hci0` UP;
- `wifi-scan`: many networks on 2.4 and 5 GHz (VERIFIED; none recorded here);
- `mfi-probe`: the MFi chip at 0x11 on `/dev/i2c-1`, DeviceVersion (reg 0x00) 0x03, certificate length
  (reg 0x30) 945 B (VERIFIED; B13's `flock -n` loop works);
- `bt-scan` (the revision-3 script): `btmgmt find` gave `Unable to start discovery. status 0x0b (Rejected)`:
  the controller's settings after `radio up` are "powered br/edr", LE not enabled. `btmgmt le on`, then
  `btmgmt find`: LE devices found; `btmgmt find -b`: discovery started and stopped cleanly, no devices in
  14 s. Bluetooth discovery VERIFIED after `btmgmt le on`; `bt-scan` fixed in revision 4 (B18, §7.0, §7.0a);
- `radio down`: back to `lo` and `usb0` only, `reg_wlan` disabled.
NOT yet tested: Wi-Fi association and DHCP, Bluetooth pairing, AP mode, USB sticks (no `/dev/sd*`, no stick
plugged), LED behaviours, key-only SSH, the 1 s UART-Enter window. (B18's `bt-scan`: tested in revision 4, §7.0a.)

VERIFIED by the 2026-10-20 builds and tests:
- every Kconfig symbol of all fragments against 7.2.10 for the variants built (strict check passed, `RD_*`
  and `GPIO_SYSFS_LEGACY` as before); every `localoptions.h` name against dropbear 2026.94; `PROGRAMS=...
  MULTI=1` yields `dropbearmulti`; dropbear's shadow path (`HAVE_SHADOW_H`, `getspnam`, `crypt`, musl);
  the configure options of OpenSSH 10.6p1 and mtd-utils 2.3.1; all binaries static (musl 1.2.5);
- gpg signatures of linux, busybox, dropbear, OpenSSH, musl, mtd-utils, exfatprogs and wireless-regdb
  (keys and fingerprints in `common/versions.env`; keys fetched over HTTPS, no web of trust); the radio
  firmware blobs are hash-only;
- from 7.2.10 source: `/sys/class/mtd/mtdN/offset` exists for partitions (`drivers/mtd/mtdpart.c`);
  regulator-fixed requests its GPIO `GPIOD_OUT_LOW` (logical off) unless `regulator-boot-on`
  (`drivers/regulator/fixed.c`); the nvmem sysfs word-size rule (B1); the gendisk announces the disk's
  uevent after its partitions exist (`block/genhd.c`); the SDIO IDs and driver names of §2.5;
- busybox 1.38.0 source: `mdev -d` scans once at start, applies `!` without touching nodes, runs `*cmd`
  with ACTION/MDEV, requires a full regex match, and loads modules only through a `$MODALIAS` rule;
  `update_passwd` follows the `/etc/shadow` symlink (also exercised in the chroot);
- that `busybox --install -s` leaves the shipped `/sbin/reboot` wrapper alone (`libbb/appletlib.c`
  `install_links`: `symlink()`, EEXIST ignored), and that dropbear 2026.94 wants the login shell in
  `/etc/shells` and takes root's hash from `/etc/shadow` when the passwd field is `x` (source; logins in
  QEMU and the chroot).

UNVERIFIED (from reading, never executed):
- exfatprogs 1.4.3 (`EXFATPROGS=1`): needs a static libblkid (util-linux) that is not pinned or built;
- that busybox `reboot` without `-f` is ignored by a script PID 1 (kernel semantics + LIVI's
  `reboot; sleep 5; reboot -f`);
- the `fsm->id = 1 -> b_peripheral` line in the vendor log names no controller, so which port it
  belongs to is not established;
- MBR logical partitions in `usb-mount` are judged by boot-sector signature only on a device and not at
  all by `--plan` on an image (no test stick with a FAT logical partition was booted);
- that the macOS NCM driver uses the gadget's `host_addr` for the host interface (the single-address
  DHCP pool assumes a stable host MAC; a second client id waits at most `NCM_LEASE` = 600 s);
- the C2Air session is described to this recipe as glibc/Andes userspace, but that session's
  `docs/userspace-spec.md` says static musl via zig cc and warns to build BusyBox with the vendor GCC;
  `common/` assumes neither (recipes take `TARGET_CC`).

Known costs (by design): the bootstate block takes one erase per rootfs boot (rcS clears the marker;
LIVI's scheme too); a power cut in the first seconds of a rootfs boot, before rcS clears the marker, lands
the next boot in recovery once; `persist save` overwrites LIVI's `customer` data; a power loss during
`persist save` loses the archive (new host key, password back to the build default); a stick mounted
read-write and pulled without `usb-mount -u` is left with its FAT dirty bit set; the dev default password
admits anyone on the USB link until it is changed.

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
`patch(1)` ignores. `common/hciup/hciup.c` copies the HCI ioctl numbers and struct layouts from the
kernel headers (interface facts). Everything else in `baseline/` is GPL-3.0-or-later.

Third-party programs the revision-3 rootfs adds are built unmodified from the pinned upstream tarballs
under their own licences (each project's COPYING): iw (ISC-style), wpa_supplicant (BSD), libnl
(LGPL-2.1, linked statically into iw and wpa_supplicant), BlueZ tools (GPL-2.0-or-later), readline
(GPL-3.0-or-later, linked into btmgmt), ncurses (X11-style). A distributed image should come with those
sources (or an offer for them); `build.sh` with `common/versions.env` rebuilds every binary from them.

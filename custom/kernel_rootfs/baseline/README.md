# Vanilla CCPA baseline image (recipe)

> Copy of ccpa_custom `baseline/` at commit `5e90368` (2026-10-20, revision 2), placed here as `custom/kernel_rootfs/baseline/`.
> Path references in this README are re-rooted for this location; the other files are byte-identical to that commit.
> The recipe's working copy stays in ccpa_custom. Index: `../README.md`.

A minimal, vanilla image for the **CPC200-CCPA** (i.MX6ULL, 128 MiB RAM, 16 MiB QSPI NOR, HAB
closed, vendor U-Boot kept): mainline Linux with a **recovery initramfs built into the kernel** (UART,
telnet and SSH/SCP/SFTP over USB NCM, USB-stick flashing), and a **small busybox squashfs rootfs** for a
dev board / IoT box: SSH, USB auto-mount, LEDs, I2C tools for the MFi chip, Wi-Fi/BT brought up **on
demand only**. No projection software, no MFi daemon, no web UI. Built on the LIVI Link recipe
(https://github.com/f-io/LIVI, GPL-3.0-or-later; analysis in `../livi/README.md`), changed where listed below.

**Status (2026-10-20, revision 2).**
- **Revision 1 (ccpa_custom commit `333b5a4`) is on hardware.** Owner report, 2026-10-20 (`../hardware_tests/2026-10-20_baseline_kernel_write.md`): its kernel (`default`
  variant of that revision, no USB) was staged for the IW416 bench unit and flashed: `flashcp` rc=0, sha256
  verified, env erased, reboot; U-Boot converted the staged head and **the recovery came up** on NCM at
  192.168.50.2, `/proc/cmdline` `console=ttymxc0,115200 rdinit=/init panic=10`, the gadget enumerated as
  **1314:1520**. The same boot exposed bug B1 (§7.3): every unit had the serial `OCBM-e3b0c44298fc`
  and the same MACs. (Corrected 2026-10-20: this line said "never flashed or run on a device".)
- **Revision 2 (this tree)** fixes B1-B8 and adds recovery SSH, recovery USB (now the default) and the
  on-demand radio, LED and MFi tools. It is built (clean, §7), passes the host self-test
  (`common/tools/selftest.sh`) and QEMU smoke tests (§7.2); **it has not been flashed.**
- **UNVERIFIED on hardware** (both revisions): the rootfs boot path (switch_root, rcS, mdev, persist),
  SSH on the board, the USB host port, the radios, the LEDs, mfi-probe, the real OCOTP identity of
  revision 2.

Shared with the parallel C2Air (riscv) baseline: `common/`. CCPA-only: `arm-imx6ul/`.

---

## 1. Proven facts this recipe stands on

Hardware-verified 2026-10-19 on the IW416 unit (`../hardware_tests/2026-10-19_round_trip/RUNBOOK.txt`; backup `../backups/20261019_IW416_ocbm_baseline_pre-livi/`),
and 2026-10-20 (owner report of the revision-1 flash, see Status):

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
| long commands over telnet must survive the session closing (a `flashcp` was SIGHUPed mid-write) | the flash helpers ignore SIGHUP and log to `/run` |
| macOS `nc` pushing into busybox `nc` over NCM truncated at ~146 KB (3x); a pull from a host Python server worked | helpers PULL (`host:port`); `common/tools/serve_once.py` |
| sysfs nvmem answers a read shorter than the word size (4 B on imx-ocotp) with EINVAL (`drivers/nvmem/core.c` `bin_attr_nvmem_read`): revision 1's `dd bs=1` read nothing, every unit got `OCBM-e3b0c44298fc` (2026-10-20) | `ocbm-identity` reads whole words (B1) |

Found while writing this recipe (from files, not hardware):

- **The stock DTB is inside the update env**: offset 0x800 of the decrypted env (FDT magic, totalsize
  33,027 B). `norboot` copies 0xf800 B from 0x80800800 to 0x83000000 *before* it reads the kernel, then
  `bootz 0x80800000 - 0x83000000`. That is why no plain FDT shows up in mtd0 or the kernel image.
  It also means the vendor U-Boot always hands a kernel the *vendor* FDT plus vendor bootargs
  (`norargs`: `console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2 mtdparts=...`), so the baseline
  kernel **must** use its appended DTB and **must not** enable `ARM_ATAG_DTB_COMPAT` (both are in
  `kernel/base.fragment`), and `stage_kernel.py` refuses an image without a complete appended DTB (B4).
- The stock DTB's `wlreg_on` regulator (GPIO1_IO05, enable-active-low) confirms LIVI's `reg_wlan` polarity.
- USB, the vendor boot log AND the stock DTB agree (details in `dts/imx6ull-ccpa-usbhost.dtsi`): both
  controllers `dr_mode = "otg"`, `disable-over-current`, **no vbus-supply**, no USB pinctrl, OTG1_ID pad
  not muxed; at boot ci_hdrc.0 read `fsm->id = 0` → `a_host`, and a USB stick enumerated (sda1, vfat).
- The NCM CFW gadget enumerates **0x1314:0x1520**, class 239/2/1 (on-box sysfs reads,
  ccpa_custom `scratchpad/ocbm_2026090*/trial.txt` line 4).
- The `kernel_len`/staging offset 0x302fd8 is the 2025.10.15.1127 U-Boot env's; build 2025.02.25.1521
  uses **0x303080** (`../../../documentation/05_Security_Analysis/kernel_encryption.md`).
  `stage_kernel.py` reads each unit's own values; `board.env`'s 0x302fd8 is only the image budget (the
  smaller value fits both) and `flash-kernel`'s probe offset for "something is staged", which a staging
  at 0x303080 still satisfies.

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
  module unpowered from the regulator's probe on (early in kernel init; before that the pin keeps the
  boot loader's state; the mux needs `PINCTRL_IMX6UL`). `radio up` (§2.5) powers it. The rootfs restores
  `kernel.modprobe` (B6): the kernel may then load protocol/filesystem modules itself (in this build:
  `net-pf-16-proto-16-family-nl80211` → cfg80211, `net-pf-31` → bluetooth, `tty-ldisc-15` → hci_uart,
  `bt-proto-3` → rfcomm, `fs-*`/`nls_*`), never the MMC host or a chip driver: their aliases are only
  `of:`/`sdio:`/`platform:`/`serdev:` (VERIFIED in `modules.alias`, 2026-10-20). No chipset is named in
  the DT unless the image is a radio one (§2.5), per ccpa_custom CLAUDE.md "never hardcode a chipset".
- **MFi**: only `/dev/i2c-1`, address 0x11 (the `&i2c2` controller on the UART5 pads, numbered 1 by
  the imx6ul.dtsi aliases); `mfi-probe` reads it (§2.4). No bridge daemon.
- **Rootfs** (§2.4): static musl BusyBox 1.38.0 (defconfig + nearly everything, 410 applets), dropbear
  2026.94 multi-call (dropbear/dbclient/dropbearkey/scp), static OpenSSH 10.6p1 `sftp-server`, static
  mtd-utils `flash_erase`, `hciup`, optional exfatprogs, radio modules + all known firmware.
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
  (`full_16MB_for_programmer.bin` of that unit; the IW416 unit's is in `../backups/20261019_IW416_ocbm_baseline_pre-livi/`). LIVI's dry-run report estimates that window at
  22-54 s. A *failed* write with power still on is recoverable: recovery keeps running from RAM, retry
  or `--restore`.
- **USB** (`RECOVERY_USB=1`, default): vfat and exFAT built in, MBR and GPT built in (`MSDOS_PARTITION`,
  `EFI_PARTITION`). `usb-update` runs last, in the background, bounded and quiet (log
  `/run/usb-update.log`): `usb-mount --wait 20` mounts the **first suitable FAT32/exFAT data partition
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
| `RECOVERY_USB=1` (default) | USB host + EHCI + chipidea host + SCSI/sd/usb-storage + vfat + NLS + MBR/GPT built in (forces `USB_HOST=1 USB_VFAT_BUILTIN=1`) | `usbotg1 { dr_mode = "host"; disable-over-current; }`, no vbus-supply | `usb-mount` one-shot + `usb-update` |
| `RECOVERY_EXFAT=1` (default) | + exFAT built in (recovery has no modules) | — | reads exFAT too |
| `RECOVERY_SSH=1` (default) | — | — | dropbear + sftp-server in the cpio |
| `RECOVERY_USB=0 USB_HOST=1` | USB host built in; storage, vfat, exFAT, NLS codepages as rootfs modules | same | no USB |
| `RECOVERY_USB=0` (`nousb`) | no USB host | usbotg1 disabled | no USB |

Variant (= kernel config) names: `default` (RECOVERY_USB=1, EXFAT=1, SSH=1), `recovery-usb-vfat`,
`nousb`, `usb-host[-vfat]`, suffix `-nossh`, `-noradio`. **Owner decision 2026-10-20: RECOVERY_USB=1
and exFAT are the default.** Measured cost (§7): USB storage + vfat **+147,044 B**, exFAT **+23,792 B**,
recovery SSH **+201,144 B**; the default image is 2,127,059 B with 1,030,917 B spare under the cap.
The added init step is one background call (`usb-update`), no daemon.
**Gating unknowns for any USB host variant** (hardware, OPEN): whether VBUS on the female port is
switched (by the GPIOs `init_gpio.sh` calls "quick charge", gpio6/gpio7 on the vendor kernel) and its
current limit. First hardware test (documented, not run): boot with a stick plugged in, check `dmesg`
for enumeration and `/run/usb-update.log`; if nothing enumerates, repeat with gpio6/gpio7 driven
(exported via sysfs) high and low. Wired-CarPlay role swapping (dr_mode otg + the vendor's
a_suspend_req_inf) stays out; mainline chipidea would need `USB_OTG_FSM`/role-switch support for it.
`dts/stock-usb-reference.dtsi` restates the stock USB nodes in mainline labels (reference only,
UNTESTED, not built).

### 2.4 Rootfs: a dev-board / IoT busybox box

- **BusyBox** full (410 applets) incl. the i2c tools (`i2cdetect i2cget i2cset i2cdump i2ctransfer`),
  `mdev`, `passwd` (sha512-crypt by default, `full.fragment`), MTD/UBI tools, `modprobe`/`depmod`.
- **SSH**: dropbear on 192.168.50.2:22 (`common/shared/ssh-up`, §2.6), SCP and SFTP.
- **USB sticks**: `mdev -d` (netlink, started by rcS; its start-up scan catches a stick that is already
  plugged in) runs `usb-mount --mdev` for every whole-disk `sd[a-z]` add/remove (`etc/mdev.conf`): the
  same MBR/GPT/ESP-skip rules as recovery, FAT32/exFAT, read-write at `/mnt/usb`, lazy unmount on
  removal. `etc/mdev.conf` ends in a catch-all `!` rule (mdev neither creates, chmods nor unlinks any
  node; devtmpfs owns `/dev`) and has no `$MODALIAS` rule (no module loading). With `USB_HOST=1`
  modular builds rcS first loads the storage stack (`usb-mount --modules`).
- **LEDs** (§2.7): `led [red|blue on|off|blink|heartbeat]`.
- **MFi coprocessor**: `mfi-probe` (read-only): DeviceVersion (reg 0x00, 1 B; 0x03 on the IW416 unit
  per ccpa_custom `ccpa/carplayd/src/main.rs`) and the certificate length (reg 0x30, 2 B BE), with the access the
  project's daemons use (register write + repeated-start read, 5 tries 5 ms apart,
  ccpa_custom `crates/vendor/mfi-i2c-local/src/lib.rs`) under `/tmp/carplay_mfi.lock`. No control register, no
  challenge, no signing. UNVERIFIED on the board.
- **Radios**: `radio up|down|status`, `radio-up`, `radio-down` (§2.5).
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
`/sys/class/net/*/phy80211`, never assumed); with the matching DT node loads the BT driver and brings
`hci0` up with `hciup` (HCIDEVUP runs the controller's HCI init, so "UP" with a BD address means real HCI
round trips); prints what it did. `radio down` reverses it and checks that `reg_wlan` is off and no SDIO
card is left. Unknown chip: reported, nothing loaded (the module stays powered until `radio down`).

| SDIO vendor:device | Chip | Wi-Fi | Bluetooth | Image |
|---|---|---|---|---|
| 0x02df:0x9159 | NXP IW416 (SD8978) | `mwifiex_sdio`, `mrvl/sdiouartiw416_combo_v0.bin` (also starts BT); `MWIFIEX_DRIVER_MODE=0x3 radio up` for AP+station | `btnxpuart` after the combo firmware ("FW already running" path), DT `nxp,88w8987-bt` | `-iw416` |
| 0x024c:0xc822 | Realtek RTL8822CS | `rtw88_8822cs`, `rtw88/rtw8822c_fw.bin` | `hci_uart` H5 + `btrtl`, `rtl_bt/rtl8822cs_fw.bin` + `rtl8822cs_config.bin`, DT `realtek,rtl8822cs-bt` | `-rtl8822cs` |
| 0x024c:0xb822 | Realtek RTL8822BS | `rtw88_8822bs`, `rtw88/rtw8822b_fw.bin` | none (LIVI: btrtl knows the 8822B over USB only; UNVERIFIED) | `-rtl8822bs` = `-none` |

All firmware is pinned in `common/versions.env` and in every rootfs (sizes §7), plus `regulatory.db`.
IDs and module names VERIFIED against 7.2.10 (`include/linux/mmc/sdio_ids.h`, the drivers' ID tables,
`modules.dep`); everything on the board UNVERIFIED. **Bluetooth without the DT node** (the `-none` image
on a BT chip: `btattach`/`hciattach` on `/dev/ttymxc2`) is **UNVERIFIED** and not done by `radio`; BlueZ
is not in the baseline (`hciup` only switches HCI up/down). Busybox has no `iw`/`wpa_supplicant`: the
interfaces come up, joining or making a network needs tools the baseline does not carry.

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
    recipes/userspace.sh   musl, BusyBox x2, dropbear, sftp-server, flash_erase, hciup, exfatprogs
    shared/                used by recovery AND rootfs: net-up net-down ocbm-identity ocbm-banner mtd.sh
                           usb-mount ssh-up persist
    rootfs/                skeleton: init, etc/{inittab,init.d/rcS,profile,passwd,group,shells,hostname,
                           mdev.conf}, usr/sbin/{passwd,led,reboot-recovery}
    tools/serve_once.py    host: one-shot raw TCP file server for the helpers' host:port pulls
    tools/selftest.sh      host: regression checks (syntax, dropbear options, usb-mount plans,
                           flash helpers on stand-in MTDs, password hash, stage_kernel self-test)
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
    rootfs/usr/sbin/       radio (+ radio-up, radio-down links), mfi-probe
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
qemu-system-arm`; for `selftest.sh` also `bsdextrautils dosfstools exfatprogs fdisk gdisk shellcheck
openssl mtools`) and `CROSS_COMPILE=arm-linux-gnueabihf-` (board.env's default `arm-linux-gnu-` is
LIVI's Fedora name). That compiler emits Thumb-2 by default, which is why `ARM_THUMB` is in
`base.fragment`.

```
sh baseline/build.sh --dry-run                     # prints every step, touches nothing
sh baseline/build.sh fetch                         # pinned tarballs, sha256-checked
sh baseline/build.sh userspace                     # musl, BusyBox full+recovery, dropbear, sftp-server, flash_erase, hciup
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
     (`--dry-run` first if in doubt);
   - **from LIVI** (same partition map): what LIVI's own provisioner does, `flashcp img /dev/mtd2 &&
     sha256sum /dev/mtd2`, then `flash_eraseall -q /dev/mtd1` (env), verify, `reboot -f`, all under
     `setsid`;
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

---

## 6. Changes against LIVI, and why

| LIVI | Baseline | Why |
|---|---|---|
| Wi-Fi driver, cfg80211, MMC/SDHCI, bridge built in; hostapd + firmware + regdb in the initramfs; Wi-Fi AP as a second way in | all modules in the rootfs, loaded only by `radio up`; no AP | owner: no radio at boot; frees image bytes |
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
| module load order file, no modprobe | `make modules_install` + depmod, BusyBox modprobe; `mdev -d` for sd* only, no modalias rule | radio modules are loaded on demand only |
| livid, its web UI, mfid, btd, accessoryd | none | owner: none at boot |
| kernel-patches 0005/0006 (mwifiex rate reporting) | not carried | radio is not part of the boot; 0001-0004 carried unchanged |
| customer MTD: livid settings | persist tar (SSH host key, keys, root's hash) | stable host key and password with a read-only rootfs |
| allnoconfig, then `scripts/config` enables, then `olddefconfig` (so `PINCTRL_IMX6UL`, `NVMEM_SYSFS`, `ARM_THUMB` arrive through their Kconfig defaults) | all three named in `base.fragment` | our `merge_config.sh -n` feeds the fragment into the allnoconfig pass, which answers every visible prompt not named with n, and `olddefconfig` keeps it (INFERRED from both flows; the review found `imx6ul-pinctrl` in LIVI's shipped Image). Without them: every pinctrl-0 consumer keeps deferring (`drivers/pinctrl/devicetree.c`, MODULES=y; QEMU: gpio-mxc -517, no console), no nvmem file for the chip ID, Thumb userland refused with ENOEXEC (QEMU 2026-10-20). (Corrected 2026-10-20: this row said LIVI's config lacks the three symbols.) |

---

## 7. OPEN ITEMS / MEASUREMENTS / VERIFICATION

MEASURED 2026-10-20, revision 2 (clean build from an empty `$TOP` except the pinned tarballs, linux
7.2.10 + patches 0001-0004, gcc 14.2.0 `arm-linux-gnueabihf-`, `RADIO_MODULES=1 RADIO_FW=1`, `JOBS=4`:
`fetch userspace measure kernel rootfs` took 5 min 37 s on 4 vCPUs; the rootfs was rebuilt from the final
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
| rootfs content before compression: modules / radio firmware + regdb / everything else | 3,467,401 / 836,709 / 1,707,516 |
| firmware: IW416 combo / rtw8822c / rtw8822b / rtl8822cs BT + config / regulatory.db | 403,148 / 202,600 / 161,240 / 63,340 + 33 / 6,348 |

- Costs (measure builds, one config apart): USB storage + vfat in recovery +147,044 B; exFAT +23,792 B;
  recovery SSH (dropbear, sftp-server, passwd/shadow files) +201,144 B. The same `default` config built
  twice came out 2,384 B apart (2,129,443 in `measure`, 2,127,059 in `kernel`: new build number and
  release minute inside the XZ stream): treat the last ~2.5 KB of any delta as noise.
- Against revision 1 (§7.2 of ccpa_custom `333b5a4`): its `default` (no USB, no SSH) was 1,753,695 B, its
  `RECOVERY_USB=1 RECOVERY_EXFAT=1` 1,918,859 B; revision 2's `default-nossh` (the same features plus the
  new scripts, tar and 64-bit shell arithmetic) is 1,928,299 B. LIVI's image was 3,124,994 B.
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
  and staging 195,830 B differ. That plan is **stale for the unit today**: it now runs revision 1, whose
  head U-Boot rewrote; `flash-kernel` would refuse it (exit 4). Re-dump `mtd2` first (§5 step 2).

Revision 1's tests (QEMU boot of `default` and `RECOVERY_USB=1` to the recovery shell, `/run`
nosuid,nodev, `mount -o move`, `reboot`; `usb-update` finding a vfat bundle; `stage_kernel.py` against the
IW416 unit's stock `mtd0.bin`/`mtd1.bin` refusing an image 1 B over the cap) are in ccpa_custom commit `333b5a4`.

### 7.3 CHANGES in revision 2 (2026-10-20)

| ID | Was | Now | Regression check |
|---|---|---|---|
| B1 | `ocbm-identity` hashed `dd bs=1 skip=4 count=8` of the sysfs nvmem file; sysfs refuses sub-word reads, so every unit hashed nothing (CONFIRMED ON HARDWARE: `OCBM-e3b0c44298fc`, shared MACs) | one `dd bs=4` read of two words into a private file, length/zero/empty-hash checks, hash and hex from that file | self-test sysfs-like `dd`, QEMU real sysfs (0 vs 8 bytes) |
| B2 | `ssh-up` ran `dropbear -s`: harmless with PASSWORD_AUTH 0 (2026.94 accepts and ignores it), it would disable password logins with 1 | no `-s/-g/-t/-w/-B`; `ssh-up` exits 0 iff dropbear runs, falls back (new/ephemeral key, `-R`); rcS prints the reason when bootstate stays set | selftest call-site check; QEMU and chroot logins |
| B3 | after a successful install a stick's (or file's) `kernel-part.img`, staged before it, failed the head check on every recovery boot and usb-update printed "DO NOT POWER OFF" | "already installed" (all but the head equal) = exit 3, nothing written; refusals = exit 4 "nothing written"; usb-update logs 3/4 only; DO NOT POWER OFF only after a started write | selftest stand-in MTDs (3, 4, 0) |
| B4 | `stage_kernel.py` only reported a missing appended DTB | refuses it (and a truncated one): the vendor FDT would take over, no console | self-test cases; real zImage refused |
| B5 | README: "never flashed" | revision 1 flashed 2026-10-20 (Status) | — |
| B6 | recovery `init` blanked `kernel.modprobe` for good (the sysctl survives switch_root) | rootfs `/init` writes `/sbin/modprobe` back; scope documented (§2) | `modules.alias` review (no MMC/radio alias the kernel can request) |
| B7 | `arm-imx6ul/rootfs/etc/.DS_Store` (and others) would be packed by `cp -R` | deleted; `build.sh` strips `.DS_Store`/`._*` from the rootfs work tree and fails if any remain | build check (a rootfs built from a copy with a planted `.DS_Store` and `._mdev.conf`: 0 in the image), selftest note |
| B8 | `base.fragment`/README: LIVI lacks `PINCTRL_IMX6UL` | the reason is our merge_config -n flow (§6); three symbols kept | — |
| B8 | stage_kernel/flash-kernel assumed 0x302fd8 silently | note in `board.env`, `flash-kernel`, `stage_kernel.py` (0x303080 on build 2025.02.25.1521) | — |
| — | recovery: UART + telnet only, USB opt-in vfat read-only | + SSH/SCP/SFTP (key from the archive or password), USB + exFAT default, MBR/GPT/ESP-aware mount rw at /mnt/usb, `flash-kernel --dry-run` | QEMU |
| — | rootfs: key-only SSH, manual `usb-mount`, no radio tooling | password + key, `passwd` persisted, mdev auto-mount, `led`, `mfi-probe`, `radio`, `hciup` | chroot |
| — | `RADIO_DT` built one kernel per radio | one zImage + one DTB per radio (`ccpa-baseline-<radio>.zimg`); variant `default` now = USB+exFAT+SSH, old default = `nousb` | build |
| — | `AUTHORIZED_KEYS` required | optional (password login) | build |
| — | `radio-iw416.dtsi` called mwifiex `driver_mode=2` "uap0 next to the station" | 2 = uAP only, 0x3 = AP + station (mwifiex `main.c`) | — |

OPEN (hardware; nothing below has run on the board):
- revision 2 as a whole: the identity (iSerial/MACs from the real OCOTP), recovery SSH over NCM, the
  rootfs boot path (`switch_root`, rcS, `mdev -d`, `persist` on the real `customer` MTD, bootstate
  clearing), the `/dev/mtdNro` read path, the restored `kernel.modprobe`;
- female port (usbotg1): whether VBUS is switched (gpio6/gpio7 "quick charge"?), its current limit, and
  mainline chipidea host behaviour; gates every USB host feature (§2.3);
- whether the radio module really is unpowered with `reg_wlan` off on every SKU (polarity from LIVI and
  the stock DTB; the claim that it powers the module comes from LIVI's comment), and every `radio` step
  (SDIO enumeration, firmware loads, interfaces, HCI);
- LEDs, `mfi-probe` (registers and the repeated-start read are what the project's daemons use on this
  chip, not checked with busybox `i2ctransfer`);
- the stock vendor U-Boot with revision 2's larger image: 2,127,059-2,127,140 B, ~372 KB more than revision
  1's 1,755,383 B that booted, 1.03 MB under the cap (LIVI's 3,124,994 B, 32,982 B under it, booted too).

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

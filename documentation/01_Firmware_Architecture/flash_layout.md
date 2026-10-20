# CPC200-CCPA Flash Layout & Memory Map

**Purpose:** Document flash partition layout and memory mapping
**Analysis Date:** 2026-01-29; **corrected 2026-10-19** (the U-Boot environment that actually runs, kernel offset and encrypted extent, DTB location, mtd0 region map; evidence E1/E2/E3 as listed in `05_Security_Analysis/kernel_encryption.md`)
**Device:** Carlinkit A15W (Freescale i.MX6 UltraLite)

---

## Flash Partition Layout

### MTD Partitions (from `/proc/mtd`)

| Partition | Device | Offset | Size | Filesystem | Purpose |
|-----------|--------|--------|------|------------|---------|
| mtd0 | /dev/mtd0 | 0x000000 | 256KB | Raw | U-Boot bootloader |
| mtd1 | /dev/mtd1 | 0x040000 | 3328KB | Raw | Linux kernel (zImage; only its first 3 × 64 KB encrypted, plus 3 staging blocks — see Kernel Analysis) |
| mtd2 | /dev/mtd2 | 0x380000 | 12800KB | JFFS2 | Root filesystem |

**Total Flash:** 16MB QSPI NOR (21e0000.qspi)

> **[Added 2026-10-20]** The table above is the **vendor** map. A unit running LIVI's kernel, or the baseline kernel that keeps LIVI's DTB map, shows six MTDs instead: uboot `0x30000` (read-only), env `0x10000`, kernel `0x340000`, rootfs `0xc60000`, customer `0x10000`, bootstate `0x10000`. There the kernel is `/dev/mtd2` and the env block is `/dev/mtd1`. The map was read live on 2026-10-19 and 2026-10-20 and is listed in `custom/kernel_rootfs/livi/README.md` §1 and `kernel_compilation.md` § Getting back from LIVI.

> **Note (boot device):** This 3-partition layout (mtd0 uboot / mtd1 kernel / mtd2 rootfs) is the authoritative one; the running kernel boots with `root=/dev/mtdblock2`. There is no 4th MTD partition. **[Corrected 2026-10-19]** `root=/dev/mtdblock3` is not in the environment U-Boot runs: it comes from NXP 14x14-EVK template text inside the U-Boot image that U-Boot never uses as its environment. The environment it does run sets `root=/dev/mtdblock2` itself (see U-Boot Environment below).

### Boot Command Line

```
console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2
mtdparts=21e0000.qspi:256k(uboot),3328K(kernel),12800K(rootfs)
rootwait quiet rw
```

This captured cmdline (from `cmdline.txt`) is the authoritative record of what the kernel actually booted with — `console=ttyLogFile0`, `root=/dev/mtdblock2` — and matches the 3-partition MTD layout. **[Corrected 2026-10-19]** It is exactly what the live `norargs` builds. The `norargs` text in the env ends in a space, but `setenv` rejoins its arguments with single spaces, so `bootargs` has none: the captured cmdline is 137 characters plus a newline (138 B) and the `Kernel command line:` line in `custom/kernel_dumps/dmesg_boot.txt` ends in `rw` [VERIFIED; corrected 2026-10-19, an earlier revision of this note said "trailing space included"]. The `console=ttymxc0,115200 root=/dev/mtdblock3` values came from template text U-Boot does not run, not from an env that is overridden at boot [VERIFIED, E1].

### MTD Partition Flags (Write Permissions)

All three MTD partitions carry the same flag value:

| Partition | Flags | Decoded |
|-----------|-------|---------|
| mtd0 (uboot) | 0xc00 | MTD_WRITEABLE \| MTD_BIT_WRITEABLE |
| mtd1 (kernel) | 0xc00 | MTD_WRITEABLE \| MTD_BIT_WRITEABLE |
| mtd2 (rootfs) | 0xc00 | MTD_WRITEABLE \| MTD_BIT_WRITEABLE |

**All three partitions are Linux-writable from a running root shell — not just mtd2 (rootfs).** mtd0 (U-Boot) and mtd1 (kernel) carry the same writeable flags, so a root-level process can overwrite the signed bootloader and encrypted kernel from the live system.

The consequence is asymmetric and unforgiving: because the boot ROM enforces HAB signature verification on U-Boot and the kernel head is decrypted with per-chip key material, writing an unsigned U-Boot or an undecryptable kernel leaves a unit that does not boot. The vendor's factory burn mode uses this: its `check_mfg_mode.sh` runs `flash_erase /dev/mtd0 0 1 && reboot` on `mfgmode=2`, erasing the first U-Boot block (`ocbm/scripts/ncm_base_install.sh` notes). That this then puts the boot ROM into serial-download mode, i.e. works as an escape hatch, is **unconfirmed** [Corrected 2026-10-19: was stated as fact]; see the OWNER-REPORTED note below. See `secure_boot_hab.md` for the HAB enforcement details and brick/recovery consequences.

> **[Corrected 2026-10-19]**
> - A **new kernel can be written** through U-Boot's own staging path (`05_Security_Analysis/kernel_encryption.md` § On-Flash Kernel Format) [VERIFIED on hardware with LIVI's kernel]. The risk is a power cut between the start of the mtd1 erase and the end of the env-block erase. About 20 s was measured for `flash_erase` + `cat` + `sync` of mtd1 alone; the full window (also the `sha256sum` check and the env erase) was not timed, and the datasheet estimate for erase + program is 22–54 s. Preconditions and the abort gate: `kernel_compilation.md` § Writing a kernel.
> - A unit that does not boot is recoverable by writing a full 16 MB backup with a SPI-NOR programmer, because the signed U-Boot is unchanged [INFERRED; no programmer restore has been run].
> - [OWNER-REPORTED; the unit, the date and the port were not recorded] With the U-Boot block blank or erased, no boot-ROM serial-download device appeared on the USB port that was tested. The 2026-10-19 RUNBOOK runs never erased U-Boot. Whether the ROM uses the other port is [UNRESOLVED].
> - The old path `03_Security_Analysis/secure_boot_hab.md` was wrong; the file is in this folder.

### QSPI NOR Write/Erase Geometry

The flash is driven by the `fsl-quadspi` controller at `0x21e0000`:

| Property | Value |
|----------|-------|
| Flash type | SPI NOR |
| Write size | 1 byte (byte-addressable) |
| Erase block size | 65,536 bytes (64KB) |

The 64KB erase granularity matches the `erasesize` reported for all three partitions in `/proc/mtd`.

---

## U-Boot Analysis (mtd0.bin)

### Key Strings Found

| Offset | String | Purpose |
|--------|--------|---------|
| 0x1641e | `UPGkey: %s` | Upgrade key logging |
| 0x1643b | `do_decrypt_decompress ret=%d dstLen=%d` | Decryption function |
| 0x17483 | `heweiencrypt` | HeWei encryption marker |
| 0x16473 | `Can't start, Bad Keys.` | Key validation error |
| 0x1640d | `%08x%08x%08x%08x` | Formats CFG0/CFG1/MAC0/MAC1 into the UpgKey text (printed by `UPGkey: %s` next to it) — added 2026-10-19 [VERIFIED, E1] |
| 0x1b0f6 | `U-Boot 2015.04 (Feb 02 2023 - 23:26:24)` | Version banner — added 2026-10-19 [VERIFIED, E1] |

### mtd0 Region Map (added 2026-10-19) [VERIFIED, E1 `mtd0.bin`, E2 `AutoBox.img`]

| Range | Contents | Per unit? |
|---|---|---|
| `0x00000`–`0x00FFF` | Loaded by the boot ROM but **not** HAB-authenticated: NXP EVK template text (`0xc14`–`0xfe3`) and per-release data (`0x87C`–`0x916`) | No (per release) |
| `0x01000`–`0x20FFF` | **HAB-authenticated** U-Boot: IVT at `0x1000` (boot data start `0x877FE7D0` = file 0, length `0x22000`), U-Boot code. The CSF's Authenticate Data command has one block, start `0x877FF7D0` (= file `0x1000`), length `0x20000` | No — byte-identical to the vendor 2025.10.15.1127 `AutoBox.img` |
| `0x21000`–`0x21FFF` | CSF at `0x21000`–`0x21F37` (IVT CSF pointer `0x8781F7D0`), then `0xFF`; loaded (boot data ends at `0x21FFF`). The CSF's first Authenticate Data command (no data blocks) covers the CSF itself | No |
| `0x22000`–`0x2CFFF` | `0xFF` | — |
| `0x2D000`–`0x2FFFF` | Update environment payload, AES-128-CBC with the UpgKey; length word (LE, `0x3000`) in the last 4 bytes of the `0x20000` block | Yes |
| `0x30000`–`0x3FFFF` | Live environment block (64 KB), DCP-encrypted [DCP key INFERRED] | Yes |

The update payload and the env block are outside the loaded and the authenticated range, so HAB does not cover the environment. **[Corrected 2026-10-19]** This table had one row `0x00000`–`0x21FFF` "HAB-signed U-Boot image"; `0x0`–`0x21FFF` is what the boot ROM loads, and only `0x1000`–`0x20FFF` is authenticated [VERIFIED, E1 `mtd0.bin` IVT + CSF parse].

The `0x20000`–`0x2FFFF` erase block also holds the end of the authenticated U-Boot (`0x20000`–`0x20FFF`) and the CSF, so rewriting the update payload means erasing a block that belongs to the signed U-Boot.

### U-Boot Environment

**[Corrected 2026-10-19]** The environment documented here before (`bootdelay=0`, `norargs … root=/dev/mtdblock3`, `norboot … sf read 0x80800000 0x100000 0x4F0000; sf read 0x83000000 0x5F0000 0x10000`) is **not** what U-Boot runs. It was put together from two pieces of the U-Boot image [VERIFIED, E1]:

- U-Boot's built-in default environment at mtd0 `0x1611d`, which is only `bootdelay=0`, `baudrate=115200`, `loadaddr=0x80800000`. The bytes are VERIFIED; that this string list is U-Boot's `default_environment` is INFERRED from its layout.
- NXP 14x14-EVK template text at mtd0 `0xc14`–`0xfe3`: `bootcmd=run norboot; mmc dev 1; …`, `fdt_file=imx6ul-14x14-evk.dtb`, `norargs=… root=/dev/mtdblock3 … mtdparts=21e0000.qspi:1M(uboot),5056K(kernel),64K(dtb),10M(rootfs)`, `norboot=echo Booting from nor flash ...; … 0x100000 0x4F0000; … 0x5F0000 0x10000; …`. The `0x100000`/`0x4F0000`/`0x5F0000` values are that template's 1M/5056K/64K(dtb) partitioning, not this board's.

The environment that runs is the per-unit one. The env block (mtd0 `0x30000`) is DCP-encrypted. The same text, UpgKey-encrypted and gzipped, sits in the update payload (mtd0 `0x2D000`), which is the copy that can be read off-chip [VERIFIED, E1: decrypts, inflates to 64 KB, CRC32 over `env[4:0x800]` matches the stored word]. Its boot-relevant variables:

```
bootcmd=run norboot;
bootdelay=3
console=ttymxc0  baudrate=115200  stdin=serial  stdout=serial  stderr=serial
norargs=setenv bootargs console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2 mtdparts=21e0000.qspi:256k(uboot),3328K(kernel),12800K(rootfs) rootwait quiet rw
norboot=run norargs;sf probe 0;cp 0x80800800 0x83000000 0xf800;sf read 0x80800000 0x40000 0x302fd8;mm w 0x80800000 0x10000;mm w 0x80810000 0x10000;mm w 0x80820000 0x10000;bootz 0x80800000 - 0x83000000;
heweiencrypt=<converts the 3 kernel staging blocks into the DCP head, then rewrites the env block; full text in 05_Security_Analysis/kernel_encryption.md>
```

The full environment, the `mm` subcommands, the `heweiencrypt` conversion, the UpgKey derivation and the hardware tests are in `05_Security_Analysis/kernel_encryption.md` § On-Flash Kernel Format. That file is the single source for them.

> **Physical-pin corollary (verified live 2026-07-08):** **nothing prints on the `TX1`/`RX1` UART pins during U-Boot or kernel boot.** U-Boot itself is **2015.04**. The only thing that appears on the physical pins is the **post-boot Linux inittab shell (`ttymxc0::respawn`), a passwordless root shell at 9600 8N1** — not 115200. See `hardware_platform.md` § Serial Console (UART). **[Corrected 2026-10-19]** The cause was given as "U-Boot's saved env points the console at `ttyLogFile0`". It does not: `ttyLogFile0` appears only in the kernel bootargs, and the U-Boot console variables are `console=ttymxc0`, `stdout/stdin/stderr=serial`, `baudrate=115200` [VERIFIED, E1]. Why U-Boot prints nothing on the pins is [UNRESOLVED].

### Boot Process

**[Corrected 2026-10-19]** (was: kernel read from `0x100000`, "768 KB gap likely an encryption header", DTB read from flash `0x5F0000`). [VERIFIED, E1 environment; RAM placement of the env INFERRED]

1. The boot ROM loads the U-Boot image from QSPI mtd0 (`0x0`–`0x21FFF`) and HAB-authenticates `0x1000`–`0x20FFF` (one CSF block).
2. U-Boot loads its environment and runs `norboot`. If the env block is erased or invalid it uses the update environment and runs `heweiencrypt` first [INFERRED from the 2026-10-19 runs].
3. `cp 0x80800800 0x83000000 0xf800`: copies from env offset `0x800`, where the device tree (the first `0x8103` bytes) is stored, to `0x83000000` before the kernel load overwrites `0x80800000`. The count is `0xf800` units, `0x3E000` bytes if `cp` uses its upstream default `.l` [INFERRED; help strings stripped].
4. `sf read 0x80800000 0x40000 0x302fd8`: the kernel is read from the **start of mtd1** (`0x40000`). There is no gap and no header.
5. `mm w` × 3: the first three 64 KB blocks are DCP-decrypted in place. The rest of the kernel is plaintext on flash.
6. `bootz 0x80800000 - 0x83000000`.

Flash `0x5F0000` is inside mtd2 and holds JFFS2 nodes, not a DTB [VERIFIED, E1 `mtd2.bin`].

---

## Kernel Analysis (mtd1.bin)

| Property | Value |
|----------|-------|
| Location | mtd1 (/dev/mtd1) |
| Size | 3,407,872 bytes (3.3MB) |
| Flash Offset | 0x40000 (256KB from start) |
| zImage length | `0x302fd8` (3,157,976 B), from `norboot` (2025.10.15.1127 build; read it from the unit's env: 2025.02.25.1521 build #448 uses `0x303080`) |

**[Corrected 2026-10-19]** (was: "The kernel is encrypted"). Only the zImage head is encrypted [VERIFIED, E1]:

| mtd1 offset | Contents |
|---|---|
| `0x000000`–`0x02FFFF` | zImage head, DCP-encrypted (per-chip key) |
| `0x030000`–`0x302FD7` | zImage body, **plaintext** |
| `0x302FD8`–`0x332FD7` | 3 × 64 KB staging blocks: the same head, AES-128-CBC with the UpgKey (software-computable per-unit key) |
| `0x332FD8`–`0x33FFFF` | `0xFF` |

The image-encryption key used for `.img` updates is a different, static key. Format, keys and recovery are in `05_Security_Analysis/kernel_encryption.md` (the old path `03_Security_Analysis/` was wrong).

### Running Kernel Info

```
Linux version 3.14.52+g94d07bb (hcw@ubuntu) (gcc version 4.9.2 (GCC))
#12 SMP PREEMPT Fri Sep 26 16:45:10 CST 2025
```

---

## Memory Map (from running system)

### Physical Memory Layout

| Range | Size | Purpose |
|-------|------|---------|
| 0x80008000-0x8058b327 | ~5.7MB | Kernel code |
| 0x805c0000-0x806684c7 | ~0.6MB | Kernel data |

### Key I/O Regions

| Address | Device |
|---------|--------|
| 0x02020000 | UART1 / `ttymxc0` — serial console pads `TX1`/`RX1` (root shell, **9600 8N1**; see `hardware_platform.md` § Serial Console) |
| 0x02184000 | USB OTG |
| 0x02190000 | MMC/SD (mmc0) |
| 0x021e0000 | QSPI Flash |
| 0x02280000 | DCP (crypto engine) |

---

## Crypto Hardware

### MXS-DCP Engine

| Path | Purpose |
|------|---------|
| /sys/bus/platform/devices/2280000.crypto | DCP crypto accelerator |
| /sys/bus/platform/drivers/mxs-dcp | DCP driver |

### Available Crypto Algorithms (from `/proc/crypto`)

- stdrng (kernel RNG)
- michael_mic (TKIP MIC)
- ecb(arc4) (WEP)
- AES (via DCP hardware)

> **[Corrected 2026-10-19]** "via DCP hardware" is not supported. `secure_boot_hab.md` lists only software algorithms. A live check on 2026-10-19 saw only generic software ciphers in `/proc/crypto`, no AF_ALG, no `/dev/crypto`, and DCP interrupt count 0 [OBSERVED-NOT-RECORDED: not saved to a file; re-capture before relying on it]. `mxs-dcp` is bound but registers no algorithms.

---

## Kernel Symbols

**48,959 symbols extracted** from `/proc/kallsyms`

### Key Symbols

| Address | Symbol |
|---------|--------|
| 0x80008200 | `_stext` (kernel start) |
| 0x80008200 | `asm_do_IRQ` |
| 0x80008500 | `secondary_startup` |
| 0x80008700 | `do_one_initcall` |
| ... | (48,959 total) |

---

## Flash Dump Files

Dumped to `/mnt/UPAN/flash_dump/`:

| File | Size | Contents |
|------|------|----------|
| mtd0.bin | 256KB | U-Boot bootloader |
| mtd1.bin | 3.3MB | Kernel (first 3 × 64 KB encrypted; corrected 2026-10-19) |
| mtd2.bin | 12.5MB | JFFS2 rootfs |
| kallsyms_full.txt | ~2MB | Kernel symbols |
| cmdline.txt | 138B | Boot command line |
| cpuinfo.txt | 352B | CPU information |
| modules.txt | 187B | Loaded modules |

---

## Kernel Decryption Strategy

> **[Resolved 2026-10-19]** None of the options below was needed. The plaintext zImage comes from the kernel partition itself: decrypt the three staging blocks with the unit's UpgKey and prepend them to the plaintext body (recipe in `05_Security_Analysis/kernel_encryption.md`). Option 2's "/dev/mem blocked" premise was disproved on 2026-06-30 (RAM dump in the same file). The options are kept as history.

### Option 1: U-Boot Analysis
- Locate `do_decrypt_decompress` function
- Extract key from code or environment
- Replicate decryption algorithm

### Option 2: Runtime Extraction
- Requires `/dev/mem` access (currently blocked by CONFIG_STRICT_DEVMEM)
- Could use kernel module to bypass restriction
- Dump from physical address 0x80008000

### Option 3: JTAG
- i.MX6UL has JTAG interface
- Could halt CPU and dump RAM
- Requires hardware access

---

## References

- Device: Carlinkit A15W
- SoC: Freescale i.MX6 UltraLite
- Flash dump date: 2026-01-29
- Kernel version: 3.14.52+g94d07bb

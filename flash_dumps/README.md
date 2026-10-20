> [!CAUTION]
> #1. These dumps are from a A15W (CPC200-CCPA) Adapter with a Realtek Wifi Chipset. Therefor the dumps would should only work on other Realtek A15W adapters. Flashing to a non-Realtek Adapter will possibly result in a bricked adapter. Unable to complete its boot due to kernel failure. Backup your own SPI first just in case.

> [!CAUTION]
> #2 If you have the capability to use these dumps to rewrite the SPI, then I’ll assume you’re also capable of retrieving the necessary firmware blobs from the CFW-Recovery update image. And splicing/incorporating it into your own flash bin.

> [!CAUTION]
> uBoot+Kernel carry per-unit parts tied to the SoC fuses; rootfs can be interchanged. U-Boot is HAB-signed (shared SRK) with two per-unit encrypted environments; only the first 192 KB of the kernel are per-chip DCP-encrypted, the rest is plain zImage. A full foreign image does not boot, so keep the original device's uBoot+Kernel (or re-stage a kernel for the unit, `../documentation/05_Security_Analysis/kernel_encryption.md`). See U2air conversion for further details. *[Corrected 2026-10-20: this said "possible uBoot+Kernel signing based on SoC fuses"; the kernel is not signed or verified.]*

Reader: XGecu Pro T48
OS: Fedora
Program: minipro

Command use:
minipro -p 'MX25L12835F@SOP8' -r flash_dump.bin

History : 
Flash Dump and rootfs decryption of 2025.02.25.1521: Credit to https://github.com/ludwig-v/wireless-carplay-dongle-reverse-engineering/

2025.10
Firmware Key: AutoPlay9uPT4n17

---

## Contents

| Folder | Device | SoC | Notes |
|---|---|---|---|
| `2025.02.25.1521/` | A15W / CPC200-CCPA | NXP i.MX6UL (ARM) | full dump + rootfs zip + SSH image — **all three removed 2026-10-20, kept local** (see below) |
| `2025.10.15.1127/` | A15W / CPC200-CCPA | NXP i.MX6UL (ARM) | full dump **removed 2026-10-20, kept local**; its mtd0/mtd1 bytes are `2026.06.07.ncm/on-device_dd/mtd0.bin`/`mtd1.bin` |
| `2026.06.07.ncm/` | A15W / CPC200-CCPA | NXP i.MX6UL (ARM) | Realtek RTL8822CS unit, CDC-NCM mode; XGecu + on-device `dd`. Only `on-device_dd/mtd0.bin`/`mtd1.bin` remain; `mtd2.bin`, `full_spi_16mb.bin` and `XGecu_dump/A15W_rt8822cs_xgecu.bin` **removed 2026-10-20, kept local** |
| `c2air_v821_2026.05.14/` | **C2Air (VehiConn / `ly6239`)** | **Allwinner V821 (RISC-V)** | **Different platform — see below** |
| `CCPA_stripped/` | A15W / CPC200-CCPA | NXP i.MX6UL (ARM) | IW416 bench unit, 2026-07-08 vanilla state. Only `mtd0.bin`/`mtd1.bin`/`manifest.txt` remain; `mtd2.bin`, `rootfs.tar.gz`, `CPC200-CCPA_full_nor_16MB.bin` **removed 2026-10-20, kept local** ([`CCPA_stripped/RESTORE.md`](CCPA_stripped/RESTORE.md)) |

### Images removed 2026-10-20 (device credentials)

Every A15W image here that holds the JFFS2 rootfs (mtd2) embeds device credentials: dropbear private
host keys, root password hashes and the Wi-Fi configs. **Owner decision 2026-10-20: they are
`git rm`'d from the working tree** (earlier commits still contain them). mtd0/mtd1 dumps (no rootfs)
stay. Byte-identical local copies live under
`~/Documents/carlink/carlinkit_misc/ccpa_backups/_removed_from_repo_2026-10-20/CPC200-CCPA_resources/`
with the same relative paths and a `SHA256SUMS`; every restore or analysis that needs one of these
files uses that copy.

| Removed file | sha256 |
|---|---|
| `CCPA_stripped/rootfs.tar.gz` | `32b48dc174e0b1cbaa2bf5680a99271afc8a75f502cf738e7d5407d2b7ea7800` |
| `CCPA_stripped/mtd2.bin` | `4250029cdf1edac27e47e101fd06aacec7ff2b5b2658ccb78a50cdd9ea1e32ea` |
| `CCPA_stripped/CPC200-CCPA_full_nor_16MB.bin` | `edd024536c6f71d8038aa1c9be7fe6379610ba9486636e655fe058300c9fc761` |
| `2026.06.07.ncm/on-device_dd/mtd2.bin` | `20457d01671ef9b1028a8d2c4290a0242a899eafc92c2749559b76ee104c5c7f` |
| `2026.06.07.ncm/on-device_dd/full_spi_16mb.bin` | `44433c3aed13b0270d8ce9de277f5c485ddf9170985c606508e8c26ebd914c51` |
| `2026.06.07.ncm/XGecu_dump/A15W_rt8822cs_xgecu.bin` | `8b5672c61a70a155206b3929814545abb7b6ff28d299903e657143a38c5e7890` |
| `2025.02.25.1521/flash_dump_2025.02.25.1521.bin` | `79e09d626d815459ecc5820278f657027e149b127ca554584ecbee2f301c1ce7` |
| `2025.02.25.1521/A15W_2025.02.25.1521_SSH.bin` | `3e861955520d9af8b817536edfaa53e71770a577b80bd8903bfc403a642d5903` |
| `2025.02.25.1521/rootfs_2025.02.25.1521.zip` | `e59375f4d1b39107962d17311e215f80b494e313fe218d7a8228ee71558a2cc2` |
| `2025.10.15.1127/flash_dump_2025.10.15.1127.bin` | `106806d2b113b5212a68a84ab06fcfe2a524f08d3041ffff4dc9f2ff2f15d6cf` |

The C2Air dumps are not part of this removal (vendor squashfs defaults; open owner decision).

> [!CAUTION]
> **`c2air_v821_2026.05.14/` is NOT an A15W dump and the cautions above do not describe it.**
> It is Allwinner V821, **32-bit RISC-V**, Linux 5.4.220, Tina Linux 5.0, AIC8800 WiFi 6, ODM
> Liaoyuan. Different CPU instruction set from every other dump here. Nothing is cross-flashable
> in either direction, and the i.MX6UL fuse-signing caution in #3 above describes the NXP HAB
> chain, **not** this device's secure boot (which is uncharacterised).
>
> Read [`c2air_v821_2026.05.14/README.md`](c2air_v821_2026.05.14/README.md) first.
> Analysis: [`../documentation/01_Firmware_Architecture/c2air_v821_platform.md`](../documentation/01_Firmware_Architecture/c2air_v821_platform.md) ·
> [`../hardware/c2air_v821_spec.md`](../hardware/c2air_v821_spec.md)
>
> Dumped with `minipro -p 'XT25F128F@SOP8' -r flash_dump.bin` (XGecu T48, macOS), verified by two
> byte-identical reads.

> **Kernel/rootfs test-unit backups are kept separately.** The IW416 bench unit is the unit of [`CCPA_stripped/`](CCPA_stripped/): its 2026-10-19 vendor-map `mtd0.bin`/`mtd1.bin` backups are the same bytes as `CCPA_stripped/mtd0.bin`/`mtd1.bin` (sha256 `e62f62a9…`/`738af784…`), so they are kept only there. Its later `mtd2.bin` and the SPI image are local only since 2026-10-20 (they embed device credentials; sha256 and location in [`../custom/kernel_rootfs/backups/20261019_IW416_ocbm_baseline_pre-livi/README.txt`](../custom/kernel_rootfs/backups/20261019_IW416_ocbm_baseline_pre-livi/README.txt)); the LIVI-state dumps are in [`../custom/kernel_rootfs/backups/`](../custom/kernel_rootfs/backups/), each folder with its own `README.txt` and `SHA256SUMS`. *[Corrected 2026-10-20: this said none of that unit's backups are in this folder.]* The naming convention here does not apply to them.

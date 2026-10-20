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
| `2025.02.25.1521/` | A15W / CPC200-CCPA | NXP i.MX6UL (ARM) | + rootfs zip, SSH image |
| `2025.10.15.1127/` | A15W / CPC200-CCPA | NXP i.MX6UL (ARM) | |
| `2026.06.07.ncm/` | A15W / CPC200-CCPA | NXP i.MX6UL (ARM) | Realtek RTL8822CS unit, CDC-NCM mode; XGecu + on-device `dd` |
| `c2air_v821_2026.05.14/` | **C2Air (VehiConn / `ly6239`)** | **Allwinner V821 (RISC-V)** | **Different platform — see below** |

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

> **Kernel/rootfs test-unit backups are kept separately.** The IW416 bench unit is the unit of [`CCPA_stripped/`](CCPA_stripped/): its 2026-10-19 vendor-map `mtd0.bin`/`mtd1.bin` backups are the same bytes as `CCPA_stripped/mtd0.bin`/`mtd1.bin` (sha256 `e62f62a9…`/`738af784…`), so they are kept only there. Its later `mtd2.bin`, the SPI image and the LIVI-state dumps are in [`../custom/kernel_rootfs/backups/`](../custom/kernel_rootfs/backups/), each with its own `README.txt` and `SHA256SUMS`. *[Corrected 2026-10-20: this said none of that unit's backups are in this folder.]* The naming convention here does not apply to them.

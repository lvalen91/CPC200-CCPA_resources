# CPC200-CCPA Resources

Resources for the **Carlinkit / MagicBox CPC200-CCPA** (A15W) wireless
CarPlay / Android Auto adapter: stock & custom firmware, EEPROM flash dumps, the AutoKit app RE,
centralized documentation, and binary patches.

- **Manufacturer:** Carlinkit / MagicBox
- **Model:** CPC200-CCPA (A15W)

## Repository layout

| Path | Contents |
|---|---|
| **`carlinkit/`** | Vendor-original material (as shipped) |
| `carlinkit/autokit/` | AutoKit app RE — `original/` (decompiled, unpacked, old) + `reconstruction/` |
| `carlinkit/firmware_stock/` | Stock update images (`A15W_Update_*.img`) |
| **`custom/`** | Custom modifications |
| `custom/firmware/` | Custom firmware builds + recovery |
| `custom/scripts/` | Custom scripts / script changes |
| `custom/patches/` | Binary patches - WIP |
| `custom/docs/` | Custom-firmware docs (USB-NCM quick start, etc.) |
| `custom/kernel_rootfs/` | Mainline kernel + rootfs behind the stock signed U-Boot. Contains the LIVI Link analysis, the vanilla baseline recipe, dated hardware runs, tools and the bench unit's flash backups. Start at [`custom/kernel_rootfs/README.md`](custom/kernel_rootfs/README.md) |
| **`ocbm/`** | **OCBM protocol conversion** — tooling to take an adapter from stock Carlinkit firmware to an OCBM-default appliance, plus newer busybox/dropbear binaries and a full test run. **Requires the [NCM CFW image](custom/firmware/2025.10.15.1127/NCM/) to be installed first — read [`ocbm/README.md`](ocbm/README.md) before touching anything** |
| **`web_interface/`** | Replacement web UI for the adapter's Boa config server — vanilla-JS drop-in (~70 KB) + SSH installer + unpacked OEM backup; requires the SSH custom firmware. See [`documentation/01_Firmware_Architecture/web_interface.md`](documentation/01_Firmware_Architecture/web_interface.md) |
| **`flash_dumps/`** | Raw 16 MB SPI flash IC dumps, date-versioned (stock + post-custom `.ncm`), **plus two non-CCPA C2Air dumps — see below** |
| **`documentation/`** | Centralized research docs (numbered sections + `_evidence/`, `_index/`) |
| **`hardware/`** | Device reference: `cpc200-ccpa_spec.md`, `c2air_v821_spec.md`, `MX25L12835F_datasheet.pdf` (flash), `MFI337S3959_iPod_Auth_Coprocessor_2.0C_spec.pdf` (Apple MFi 2.0C auth-coprocessor spec), `photos/` |

> Repo origin/purpose: maintain a pair of firmware images (for updating) and an EEPROM flash dump
> taken after the update completes. That core remains under `carlinkit/firmware_stock/` + `flash_dumps/`.

## Hardware platform (on-hand device inspection)

- **SoC:** NXP i.MX6UL (ARM Cortex-A7, single core, 528 MHz) — *fake Atmel branding on package*
- **RAM:** Samsung K4B1G1646D-HCF8 (128 MB DDR3L-800)
- **Flash:** Macronix MX25L12835F (16 MB SPI NOR, SOP8) — datasheet in `hardware/`
- **Wireless:** Realtek RTL8822CS (WiFi 5 + BT 4.2 combo)

**Confirmed capabilities:** HW video decode (≤4096 px wide) · unlimited simultaneous audio ·
USB 2.0 (480 Mbps) · WiFi 5 2T2R (866 Mbps) · 123 MB RAM available after kernel overhead.

Full spec: [`hardware/cpc200-ccpa_spec.md`](hardware/cpc200-ccpa_spec.md).

The list above is one RTL8822CS unit. The CCPA is a family: NXP i.MX SoC (ARMv7) with differing radios
(RTL8822BS/CS, RTL8733BS, BCM4354/4335/4358, SD8987, IW416; `ocbm/README.md`) and a unit-dependent
flash part. The connected bench unit is an NXP IW416 (SDIO `02df:9159`). The SoC label (i.MX6UL vs
i.MX6ULL) is pending a DIGPROG read; this repo uses both (UNVERIFIED which).

### Recovery and auth

Repository state, 2026-10-28: this repository has uncommitted documentation and licence edits and a local-only history rewrite (`mtd2_dump1.bin` dropped; `mtd2_dump2.bin`, identical content, remains in commits `8836cca` to `9746e9f`; pre-rewrite bundle `/tmp/resources-pre-strip-20261028.bundle`). The `unit_info.txt` decision is pending. Nothing has been pushed.

- **CCPA:** no FEL, no U-Boot console, and no recovery except (a) a kernel-initramfs recovery boot
  such as LIVI's or this repo's baseline (`custom/kernel_rootfs/`) or (b) an SPI programmer. A firmware
  brick is otherwise permanent. MFi 2.0C coprocessor: DeviceVersion 0x03, 945 B certificate, 128 B RSA
  signature.
- **C2Air (Allwinner V821):** FEL by a physical power-on button; MFi 3.x coprocessor (DeviceVersion
  0x07, 608 B certificate, 64 B ECDSA signature; owner-supplied, not yet backed by a doc in this repo).
  The owner has one unit; OCBM has not been tested on the new baseline.
- OCBM is MFi-version agnostic.
- Update flow: the Carlinkit firmware accepts the update, then a recovery-capable boot image installs
  the OCBM baseline rootfs.

## Second platform: C2Air (Allwinner V821, RISC-V)

Two dumps in this repo (one unit, before and after repartition) are **not** a CPC200-CCPA and share no
lineage with the rest of the material. The owner has one C2Air unit. A "C2Air"-branded adapter turned
out to be a completely different design:

- **SoC:** Allwinner V821 (`sun300iw1p1`) — **32-bit RISC-V** (RV32IMAFDC + Andes `xv5`), not ARM
- **RAM:** 64 MB · **Flash:** XTX XT25F128F-W (16 MB SPI NOR, SOP8)
- **Wireless:** AICSemi AIC8800 — **WiFi 6 (802.11ax)**, 5 GHz
- **Firmware:** Linux 5.4.220 · musl · Tina Linux 5.0 / OpenWrt 21.02 · ODM **Liaoyuan**, not HeWei
- **CarPlay only** (`ly_link_type=cp`); HiCar DHCP config ships but is unused

Nothing is cross-flashable with the A15W in either direction — different instruction set. The
"2air" name is shared with the i.MX6UL `U2AC_AUTOKIT` documented elsewhere in this repo; they are
unrelated hardware. **Identify these adapters by SoC, not by box.**

- Dumps: [`flash_dumps/c2air_v821_2026.05.14/`](flash_dumps/c2air_v821_2026.05.14/) (stock) and
  [`flash_dumps/c2air_v821_2026-08-17_ocbm_baseline/`](flash_dumps/c2air_v821_2026-08-17_ocbm_baseline/) (after repartition, UDISK redacted)
- Analysis: [`documentation/01_Firmware_Architecture/c2air_v821_platform.md`](documentation/01_Firmware_Architecture/c2air_v821_platform.md)
- Hardware sheet: [`hardware/c2air_v821_spec.md`](hardware/c2air_v821_spec.md)

## License

MIT ([LICENSE](LICENSE)), except `custom/kernel_rootfs/baseline/` and `custom/kernel_rootfs/tools/dryrun.py`,
which are GPL-3.0-or-later (see `custom/kernel_rootfs/baseline/LICENSE`; its DTS files and kernel patches keep
GPL-2.0). Those files derive from LIVI (https://github.com/f-io/LIVI). `custom/kernel_rootfs/tools/flash_erase`
is a stock mtd-utils 1.4.8 binary (GPL-2.0), not covered by the MIT licence.

Based on LIVI by Lasse Heitgres (https://github.com/f-io/LIVI)

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
| **`flash_dumps/`** | Raw 16 MB SPI flash IC dumps, date-versioned (stock + post-custom `.ncm`) |
| **`documentation/`** | Centralized research docs (numbered sections + `_evidence/`, `_index/`) |
| **`hardware/`** | Device reference: `cpc200-ccpa_spec.md`, `MX25L12835F_datasheet.pdf`, `photos/` |

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

# CPC200-CCPA Secure Boot (HAB) & Signing Architecture

**Purpose:** Document the i.MX6UL High Assurance Boot (HAB) chain, OTP/SRK fuses, CSF signing-key eras, kernel encryption, and the AutoBox.img OTA U-Boot/kernel update path.
**Device:** Carlinkit A15W (Freescale i.MX6 UltraLite) and HeWei family (U2W, U2AW, U2AC, A15W, 2air)

> Scope note: This document covers the boot-ROM HAB chain and signing architecture. For the AES/ChaCha/MFi application-layer crypto stack see `crypto_stack.md`; for the flash partition map see `flash_layout.md` (which notes the encrypted kernel but does not cover HAB).

---

## OTP Fuses (Burned, Irreversible)

The i.MX6UL OCOTP fuse bank holds the burned SRK table hash, configuration words, lock word and MAC addresses. Representative read from an A15W unit:

```
SRK0=0x35799e07  SRK4=0xddf4d972
SRK1=0x3777df73  SRK5=0xade068b3
SRK2=0xf1f402d0  SRK6=0x79e7970b
SRK3=0xd57be823  SRK7=0xa30cdab2

LOCK=0x324003
CFG0=0x651ede98  CFG3=0xfc433f02  CFG5=0x8d0004a
CFG1=0x2f0a99d7  CFG4=0x0         CFG6=0x0
CFG2=0x7df100ce

MAC0=0xf9138131  MAC1=0xec5819fe
```

- **SRK0-7** are the SHA-256 hash of HeWei's RSA public-key (SRK) table, burned into OTP at manufacturing.
- **LOCK = 0x324003** applies selective fuse locking.
- `SEC_CONFIG` is set to **HAB Closed** (enforced) — the boot ROM rejects any image that does not verify against the burned SRK hash.
- CFG0/CFG1/MAC0/MAC1 are combined to derive the device UUID used by the OTA update API.

### SRK Fuses Are Byte-for-Byte Identical Across ALL HeWei Devices

Direct comparison of OTP fuse values across multiple devices and both brands (Carlinkit and AutoKit) shows the SRK table hash is **identical on every unit**:

```
                Carlinkit (Ludwig)   A15W (AutoKit)   2air (U2AC_AUTOKIT)  CPC200-CCPA (db2026.91)
SRK0            0x35799e07           0x35799e07       0x35799e07           0x35799e07     MATCH
SRK1            0x3777df73           0x3777df73       0x3777df73           0x3777df73     MATCH
SRK2            0xf1f402d0           0xf1f402d0       0xf1f402d0           0xf1f402d0     MATCH
SRK3            0xd57be823           0xd57be823       0xd57be823           0xd57be823     MATCH
SRK4            0xddf4d972           0xddf4d972       0xddf4d972           0xddf4d972     MATCH
SRK5            0xade068b3           0xade068b3       0xade068b3           0xade068b3     MATCH
SRK6            0x79e7970b           0x79e7970b       0x79e7970b           0x79e7970b     MATCH
SRK7            0xa30cdab2           0xa30cdab2       0xa30cdab2           0xa30cdab2     MATCH
LOCK            0x324003             0x324003         0x324003             0x324003       MATCH
MISC_CONF       —                    —                —                    0x40           HAB Closed
```

The CPC200-CCPA column was verified live 2026-06-30 via `/sys/fsl_otp/` (sysfs OCOTP interface; `devmem` hangs on this device). `MISC_CONF=0x40` confirms HAB Closed (SEC_CONFIG[1]=1). The 8 u-Boot hardcoded SRK constants in mtd0 are byte-for-byte identical to these burned fuse values — confirming u-Boot self-validates its own signing key at first boot.

**CPC200-CCPA unit-specific values (firmware db2026.91, read 2026-06-30):**

```
CFG0 = 0x692173ca   CFG3 = 0xfc433f02   LOCK = 0x324003
CFG1 = 0x1d16c1d7   CFG4 = 0x0          MISC_CONF = 0x40
CFG2 = 0x7df100ae   CFG5 = 0x08d0004a   FIELD_RETURN = 0x2
                    CFG6 = 0x0
MAC0 = 0x767bb8ec   MAC1 = 0xfefd6672
SW_GP2 = 0x0        SW_GP3 = 0x0        (DCP PAYLOAD words 2 and 3)
OTPMK0-7 = 0xbadabada  (hardware-masked; software reads always return sentinel)
```

Note: CFG0 and CFG1 are used as DCP descriptor PAYLOAD[0] and PAYLOAD[1] by u-Boot during kernel decryption — they are NOT the AES key. See `05_Security_Analysis/kernel_encryption.md`.

**Every HeWei device — U2W, U2AW, U2AC, A15W, 2air, in both Carlinkit and AutoKit branding — shares the same SRK table hash.** Consequences:

- The "brand" distinction (Carlinkit vs AutoKit) is **purely software, not cryptographic**. There is no HAB key difference between brands.
- A signed U-Boot from any HeWei device passes HAB on any other HeWei device (same burned SRK hash).
- HAB key mismatch is therefore **not** a valid explanation for cross-device boot failures (see kernel encryption below for the real per-chip barrier).

---

## CSF Signing-Key "Eras" Are Key Indices, Not Different Keys

The differing CSF certificate hashes seen across firmware versions are **different key indices within the same shared 4-key SRK table**, not different keys. The OTP SRK hash covers a 4-entry key table; the CSF (Command Sequence File) in each signed U-Boot selects which index is used.

| Era | CSF pointer | Notes |
|-----|-------------|-------|
| Era 2 | `0x8782A7D0` | Earlier key index |
| Era 3 | `0x8781F7D0` | Later key index (current) |

Because all four keys live under the one burned SRK hash, any era's signature verifies against the same OTP fuses. The era rotation changes which index is selected, not the trust anchor.

---

## AutoBox.img — U-Boot + Kernel ARE Updated via OTA

Earlier analysis assumed U-Boot and kernel could never be field-updated. This is **incorrect**. Every full firmware release ships `AutoBox.img`, a **3,670,016-byte** file that is the complete mtd0 + mtd1 region (signed U-Boot + encrypted kernel). It is written to flash during the update and the device reboots into the new boot chain, which passes HAB against the (universal) burned SRK fuses.

### Evidence of the era rotation (A15W firmware line)

| Firmware | AutoBox.img CSF | Notes |
|----------|-----------------|-------|
| 2022.04.25 | `0x8782A7D0` (era 2) | Older SRK index |
| 2022.11.19 | `0x8782A7D0` (era 2) | New kernel build, same key index |
| 2023.05.29 | `0x8781F7D0` (era 3) | **SRK index rotated era 2 → era 3** |
| 2023.09.27 | `0x8781F7D0` (era 3) | New kernel build |
| 2024.01.19 | `0x8781F7D0` (era 3) | OTA |
| 2025.02.25 | `0x8781F7D0` (era 3) | OTA |
| 2025.10.15 | `0x8781F7D0` (era 3) | OTA |

The SRK index rotated from era 2 to era 3 between firmware 2022.11 and 2023.05. Every release since has shipped a fresh AutoBox.img.

### U-Boot Code Is Identical Across Devices; Only the CSF/Cert Region Differs

Byte-level comparison of mtd0 between two A15W units on the same firmware:

```
0x000000 - 0x02C000:  U-Boot code        0 bytes differ        100% IDENTICAL
0x02D000 - 0x040000:  CSF / cert region  ~77,516 bytes differ  per-device
```

The U-Boot executable code is shipped generically and is identical across devices. Only the ~76 KB CSF certificate region (`0x02D000`–`0x040000`) is per-device — it holds cryptographic material written by U-Boot after it first boots on a new firmware. (Cross-device U-Boot builds otherwise differ only in a small ~89-byte block of per-device identity values, e.g. UUID/serial hashes derived from OTP fuses around offset `0x87D`.)

### Resulting layered model

- **SRK fuses:** burned once at manufacturing, identical across all devices, contain the hash of the 4-key table.
- **AutoBox.img:** generic signed U-Boot + encrypted kernel template, delivered with every full firmware update.
- **CSF region:** per-device certificate data, written by U-Boot after first boot on new firmware.

---

## Kernel Encryption — Per-Chip OTPMK Binding

The kernel (mtd1, 3328 KB) is **encrypted with a per-chip key derived from the OTPMK fuses** and is decrypted by U-Boot at boot time. Because the OTPMK is unique per silicon die, an encrypted kernel only decrypts on its own chip.

This is the true barrier to whole-flash transplants between devices, confirmed by experiment:

| Approach | Result |
|----------|--------|
| Full SPI dump from device A → device B | **Fails** — device B cannot decrypt device A's kernel |
| Hybrid (device B's own boot region + device A's rootfs) → device B | **Succeeds** — own kernel decrypts, foreign rootfs mounts |

Since HAB passes on any HeWei unit (shared SRK), the failure mode of a full-flash transplant is the **kernel decryption stage**, not HAB.

---

## Partition Portability Rules

| Partition | Offset | Size | Portable? | Reason |
|-----------|--------|------|-----------|--------|
| mtd0 (U-Boot) | 0x000000 | 256 KB | **No** | Per-device identity bytes + per-device CSF cert material |
| mtd1 (kernel) | 0x040000 | 3328 KB | **No** | Encrypted with per-chip OTPMK; only decrypts on its own silicon |
| mtd2 (rootfs) | 0x380000 | 12800 KB | **Yes** | Plain JFFS2, no signing or encryption |

mtd2 carries no signature check at the filesystem level; the only compatibility constraint on a swapped rootfs is kernel-module vermagic matching.

---

## i.MX6UL Security Peripherals (Boot ROM Domain)

The following security peripherals are present on the bus:

```
21bc000.ocotp-ctrl       — OTP Fuse Controller (read/write fuses)
21bc000.ocotp-fuse       — OTP Fuse interface
100000.caam-sm           — CAAM Secure Memory
20cc000.caam-snvs        — CAAM Secure Non-Volatile Storage
caam_secvio.3            — CAAM Security Violation Detector
20b0000.snvs             — Secure Non-Volatile Storage
20cc000.snvs-pwrkey      — SNVS Power Key (tamper detection)
20cc034.snvs-rtc-lp      — SNVS Real-Time Clock (no battery-backed RTC)
20d8000.src              — System Reset Controller (fsl,imx6ul-src)
21e0000.qspi             — QuadSPI NOR Flash Controller (fsl-quadspi)
```

QSPI flash characteristics: SPI NOR, 1-byte write granularity, 65,536-byte (64 KB) erase blocks.

### HAB Runs Entirely in the Boot ROM — No dmesg Visibility

HAB signature verification happens in the i.MX6UL boot ROM **before the kernel loads**. The kernel has no visibility into HAB state; there is **no HAB status logged in dmesg**. The SNVS tamper / power-key detection probes during boot, but no boot-chain verification result is exposed to Linux.

### CAAM Not Registered With the Linux Crypto API

The CAAM hardware crypto block is **not** registered with the Linux kernel crypto API. CAAM is used only by the boot ROM (HAB) and by HeWei's custom activation driver — not by the Linux crypto subsystem. The kernel crypto subsystem exposes only software algorithms (stdrng, michael_mic, ecb(arc4), software AES, SHA-224/256); there is no CAAM acceleration visible to Linux.

---

## Boot Chain Summary

```
i.MX6UL Boot ROM (HAB Closed)
  └─ reads signed U-Boot from QSPI mtd0
     └─ verifies IVT/DCD/CSF signature against burned SRK hash (OTP)   → PASS/BRICK
        └─ U-Boot runs, decrypts kernel (mtd1) using per-chip OTPMK key
           └─ writes per-device CSF/cert data to 0x02D000–0x040000 (first boot of new fw)
              └─ boots kernel, mounts JFFS2 rootfs (mtd2, unsigned/unencrypted)
```

- HAB anchor (SRK hash): universal across all HeWei devices.
- U-Boot code: generic/shared; per-device only in the CSF cert region and a small identity block.
- Kernel: per-chip encrypted (OTPMK) — the binding that prevents cross-device kernel transplant.
- Rootfs: portable.

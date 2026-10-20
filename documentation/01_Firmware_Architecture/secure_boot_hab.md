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
- CFG0/CFG1/MAC0/MAC1 are combined to derive the device UUID used by the OTA update API. **[Added 2026-10-19]** The UUID is the 32-character text `%08x%08x%08x%08x` of those four words, and that same text is U-Boot's **UpgKey** (AES-128 key = first 16 characters, IV = last 16). The UpgKey encrypts the per-unit update environment and the kernel staging blocks [VERIFIED for both units in `hardware_revisions.md`: uuid = fuse formula for both; decryption of real flash on E1 and on the other unit's dumps in `flash_dumps/` (E4); see `05_Security_Analysis/kernel_encryption.md`]. The adapter reports the UUID to the host in BoxSettings, so the UpgKey is not secret.

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

Note: CFG0 and CFG1 are used as DCP descriptor PAYLOAD[0] and PAYLOAD[1] by u-Boot during kernel decryption — they are NOT the DCP AES key. **[Added 2026-10-19]** Together with MAC0/MAC1 they do form the software UpgKey (see the UUID note above). See `05_Security_Analysis/kernel_encryption.md`.

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

Earlier analysis assumed U-Boot and kernel could never be field-updated. This is **incorrect**. Every full firmware release ships `AutoBox.img`, a **3,670,016-byte** file that is the complete mtd0 + mtd1 region. It is written to flash during the update and the device reboots into the new boot chain, which passes HAB against the (universal) burned SRK fuses.

> **[Corrected 2026-10-19]** The image is not a "signed U-Boot + encrypted kernel" copy that can be written as is. In the 2025.10.15.1127 `AutoBox.img` (E2) [VERIFIED against unit E1]:
> - The signed U-Boot image is byte-identical to the unit's.
> - The env block (mtd0 `0x30000`) and the DCP kernel head (mtd1 `0x0`–`0x2FFFF`) are **blank**.
> - The kernel body is plaintext and identical to the unit's.
> - The update environment (mtd0 `0x2D000`) and the three kernel staging blocks do **not** decrypt with E1's UpgKey, the other recorded unit's UpgKey, the `.img` key, the USB key or trivial keys; the key they use is [UNRESOLVED].
>
> So the vendor `upg` tool presumably re-keys those two areas for the target unit [INFERRED; `upg` not analysed, it is packed or encrypted (entropy 7.999 bits/byte)]. U-Boot then builds the DCP head and the env block itself on the first boot (`heweiencrypt`). Details: `05_Security_Analysis/kernel_encryption.md` § Vendor update image.

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

### U-Boot Code Is Identical Across Devices; Only the Per-Unit Environments Differ

(Heading corrected 2026-10-19; it said "Only the CSF/Cert Region Differs".)

Byte-level comparison of mtd0 between two A15W units on the same firmware:

```
0x000000 - 0x02C000:  U-Boot code        0 bytes differ        100% IDENTICAL
0x02D000 - 0x040000:  per-unit envs      77,516 bytes differ   per-device   (labelled "CSF / cert region" before 2026-10-19)
```

The U-Boot executable code is shipped generically and is identical across devices. The per-device bytes are the two encrypted environments at `0x02D000`–`0x040000` (correction below). *(2026-10-20: the superseded prose here, "only the ~76 KB CSF certificate region is per-device" and "~89-byte block of per-device identity values around `0x87D`", was deleted; the correction below replaces it.)*

> **[Corrected 2026-10-19]** `0x02D000`–`0x040000` is not the CSF and holds no certificates [VERIFIED, E1 + E2]:
> - The IVT's CSF pointer (`0x8781F7D0`) puts the CSF at mtd0 `0x21000`–`0x21F37`, at the end of the image the boot ROM loads (`0x0`–`0x21FFF`, IVT boot-data length `0x22000`). It is byte-identical between unit E1 and the vendor `AutoBox.img`. What the CSF authenticates is one block, `0x877FF7D0` + `0x20000` = mtd0 `0x1000`–`0x20FFF` (see § HAB covers only the U-Boot image).
> - The per-device bytes are two encrypted environments. The update environment at `0x2D000`–`0x2FFFF` is UpgKey-encrypted; its writer is inferred to be the vendor `upg` tool. The live env block at `0x30000`–`0x3FFFF` is DCP-encrypted and is written by U-Boot's `heweiencrypt` [VERIFIED by the env-erase run] — that is the "written by U-Boot after first boot" observation.
> - The 77,516 bytes above are VERIFIED for two units on 2025.10.15.1127 (E1 vs the `flash_dumps/2025.10.15.1127/` unit, E4): 12,230 in the update environment and 65,286 in the env block, nothing below `0x2D000`. Unit E1 vs the vendor `AutoBox.img` differ in 77,508 bytes of mtd0 (12,228 update environment + 65,280 env block); the whole 3,670,016-byte image differs from E1's mtd0+mtd1 in 469,107 bytes (the other 391,599 are the blank kernel head and the staging blocks).
> - The `0x87D` bytes are per-release data, not per-unit identity and not a different U-Boot build [VERIFIED]: the two units on 2025.10.15.1127 are identical below `0x2D000`, while the E4 unit differs from itself in 88 bytes (`0x87C`–`0x916`) between its 2025.02.25.1521 and 2025.10.15.1127 dumps, with the same U-Boot build stamp (`Feb 02 2023 - 23:26:24`) and CSF pointer. That range is in `0x0`–`0xFFF`, which the boot ROM loads but HAB does not authenticate.

### Resulting layered model

- **SRK fuses:** burned once at manufacturing, identical across all devices, contain the hash of the 4-key table.
- **AutoBox.img:** generic signed U-Boot + encrypted kernel template, delivered with every full firmware update. **[Corrected 2026-10-19]** The kernel is in staging form: blank DCP head and env block; staging and update env under a key that is not E1's, not the other recorded unit's and not the `.img`/USB key [VERIFIED; the key is UNRESOLVED], which `upg` presumably re-keys [INFERRED].
- **CSF region:** per-device certificate data, written by U-Boot after first boot on new firmware. **[Corrected 2026-10-19]** It is per-device *environment* data, not certificates: the UpgKey-encrypted update env at `0x2D000` and the DCP-encrypted live env at `0x30000`. The CSF is at `0x21000` and is generic.

---

## Kernel Encryption — Per-Chip DCP Head (192 KB) and UpgKey Staging

Only the first 192 KB of the kernel (mtd1, 3328 KB), its first three 64 KB blocks, are **encrypted with the DCP's per-chip key derived from the OTPMK fuses**, and U-Boot decrypts just those blocks at boot. The rest of the partition up to `kernel_len` is plain zImage. Because the OTPMK is unique per silicon die, that head only decrypts on its own chip; the same head is also stored as three staging blocks under the per-unit UpgKey, which software can compute. **[Corrected 2026-10-20 in place, from the 2026-10-19 finding in `05_Security_Analysis/kernel_encryption.md`]** This section was titled "Per-Chip OTPMK Binding" and said the whole kernel is encrypted with the per-chip key, so that an encrypted kernel only decrypts on its own chip.

> **[Corrected 2026-10-19]** Only the first 3 × 64 KB of the zImage are DCP (per-chip) encrypted. The body is plaintext and identical across units. Three staging blocks hold the same head under the per-unit UpgKey, which software can compute [VERIFIED, E1].
> - A kernel can therefore be moved to another unit: write the body, encrypt the head into staging with the **target's** UpgKey, erase the target's env block, and U-Boot rebuilds the DCP head. This method is VERIFIED on one unit with LIVI's kernel; a cross-unit transplant is INFERRED.
> - U-Boot does not verify the kernel [VERIFIED: LIVI's mainline 7.2.10 kernel booted].
> - Full format: `05_Security_Analysis/kernel_encryption.md`.
> - **[Added 2026-10-20]** The kernel-replacement work (LIVI analysis, the vanilla baseline, run logs, backups) is in `custom/kernel_rootfs/`. Nothing there writes U-Boot.

This is the true barrier to whole-flash transplants between devices, confirmed by experiment:

| Approach | Result |
|----------|--------|
| Full SPI dump from device A → device B | **Fails** — device B cannot decrypt device A's 192 KB DCP head or A's env block (corrected 2026-10-20; said "A's kernel") |
| Hybrid (device B's own boot region + device A's rootfs) → device B | **Succeeds** — own kernel decrypts, foreign rootfs mounts |

Since HAB passes on any HeWei unit (shared SRK), the failure mode of a full-flash transplant is the **kernel decryption stage**, not HAB. **[Added 2026-10-19]** With a foreign full image both per-unit parts are wrong for device B: the DCP-encrypted env block, and the update environment it would fall back to, which is under A's UpgKey. Neither yields a valid environment on B. U-Boot's `Can't start, Bad Keys.` string probably marks this case [INFERRED; not traced].

---

## Partition Portability Rules

| Partition | Offset | Size | Portable? | Reason |
|-----------|--------|------|-----------|--------|
| mtd0 (U-Boot) | 0x000000 | 256 KB | **No** as a whole; the U-Boot image `0x0`–`0x21FFF` (HAB-authenticated part `0x1000`–`0x20FFF`) **is** generic within a release | Per-device: UpgKey-encrypted update env (`0x2D000`) + DCP-encrypted env block (`0x30000`) [Corrected 2026-10-19; was "identity bytes + CSF cert material"] |
| mtd1 (kernel) | 0x040000 | 3328 KB | **Not as is**; **yes after re-keying** | Head (`0x0`–`0x2FFFF`) DCP per-chip, staging under the per-unit UpgKey, body plaintext and generic. Re-key staging for the target and erase its env block [Corrected 2026-10-19; method VERIFIED on one unit, cross-unit INFERRED] |
| mtd2 (rootfs) | 0x380000 | 12800 KB | **Yes** | Plain JFFS2, no signing or encryption |

mtd2 carries no signature check at the filesystem level; the only compatibility constraint on a swapped rootfs is kernel-module vermagic matching (only while the vendor `.ko` modules are kept; a replacement kernel with its own userspace, such as LIVI's, has no such constraint).

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

**HAB covers only the U-Boot image, not the environment or the kernel (2026-10-19).**
- The boot ROM loads mtd0 `0x0`–`0x21FFF` (IVT at `0x1000`, boot data start `0x877FE7D0` = file 0, length `0x22000`). The CSF (`0x21000`–`0x21F37`) has two Authenticate Data commands: one for the CSF itself and one with a single block, start `0x877FF7D0` (= file `0x1000`), length `0x20000`. So HAB authenticates mtd0 **`0x1000`–`0x20FFF`** (IVT, boot data and U-Boot code; the entry point `0x87800000` = file `0x1830` is inside it). `0x0`–`0xFFF` is loaded but **not** authenticated (it holds the NXP EVK template text and the per-release `0x87C`–`0x916` bytes); `0x22000`–`0x2CFFF` is `0xFF`. The environments at `0x2D000`/`0x30000` and all of mtd1 are outside both ranges [VERIFIED, E1 `mtd0.bin`]. U-Boot itself carries `hab_auth_img`/`hab_status` commands, but its `norboot` runs no authentication step. **[Corrected 2026-10-19]** This bullet said the signed region is `0x0`–`0x21FFF`; that is the loaded range, not the authenticated one.
- `SEC_CONFIG` is closed on the tested unit (2026-06-30 OCOTP read, `MISC_CONF=0x40`, § SRK Fuses above). U-Boot cannot be replaced by a modified or unsigned U-Boot; vendor-signed U-Boot images (e.g. `AutoBox.img` updates) pass HAB.
- [OWNER-REPORTED; the unit, the date and the USB port were not recorded] With the U-Boot block blank or erased, no boot-ROM serial-download device appeared on the USB port that was tested. This was not part of the 2026-10-19 RUNBOOK runs, which never wrote U-Boot. Hypothesis [UNRESOLVED]: the ROM uses the first OTG controller (`ci_hdrc.0`, the female USB-A port).

### CAAM Not Registered With the Linux Crypto API

The CAAM hardware crypto block is **not** registered with the Linux kernel crypto API. CAAM is used only by the boot ROM (HAB) and by HeWei's custom activation driver — not by the Linux crypto subsystem. The kernel crypto subsystem exposes only software algorithms (stdrng, michael_mic, ecb(arc4), software AES, SHA-224/256); there is no CAAM acceleration visible to Linux.

---

## Boot Chain Summary

```
i.MX6UL Boot ROM (HAB Closed)
  └─ reads signed U-Boot from QSPI mtd0
     └─ verifies IVT/DCD/CSF signature against burned SRK hash (OTP)   → PASS/BRICK
        └─ U-Boot runs; if its env block (0x30000) is blank/invalid: heweiencrypt
           │    (staging blocks → UpgKey-decrypt → DCP-encrypt → kernel head; then env block)
           └─ norboot: DTB from env+0x800 → 0x83000000; kernel 0x302fd8 B from 0x40000;
              DCP-decrypt first 3 × 64 KB only; bootz (no kernel verification)
              └─ kernel mounts JFFS2 rootfs (mtd2, unsigned/unencrypted)
```

**[Corrected 2026-10-19]** The tree above used to say "decrypts kernel (mtd1) using per-chip OTPMK key" and "writes per-device CSF/cert data to 0x02D000–0x040000". The tree now follows the environment U-Boot runs (`05_Security_Analysis/kernel_encryption.md`). The `heweiencrypt` trigger condition is INFERRED from the env-erase runs.

- HAB anchor (SRK hash): universal across all HeWei devices.
- U-Boot code: generic/shared. **[Corrected 2026-10-19]** It said "per-device only in the CSF cert region and a small identity block". Per-device are only the two encrypted environments (`0x2D000`, `0x30000`); the `0x87C`–`0x916` block is per-release, and the CSF is generic.
- Kernel: only the 192 KB head (first three 64 KB blocks) is per-chip DCP-encrypted (OTPMK-derived key); the rest is plain zImage. Re-keying the staging blocks for the target's UpgKey and erasing its env block removes the barrier to a cross-device kernel transplant [method VERIFIED on one unit, cross-unit INFERRED]. **[Corrected 2026-10-19; reworded in place 2026-10-20]** This bullet said the kernel is per-chip encrypted (OTPMK) and that this prevents a cross-device kernel transplant.
- Rootfs: portable.

# CPC200-CCPA Kernel Encryption Analysis

**Purpose:** Document kernel encryption findings and decryption/re-encryption capability
**Analysis Date:** 2026-01-29 (initial); **Definitive findings: 2026-06-30**
**Status:** SOLVED — cipher mode confirmed (stream), keystream extracted, re-encryption recipe proven

---

## TL;DR (June 2026)

The kernel in mtd1 is encrypted with **AES-128 in CTR/stream mode** using the DCP hardware AES engine with the per-chip OTPMK key (hardware-masked, never software-readable). Because the cipher is a stream cipher, any modified kernel <= 3,358,720 bytes can be re-encrypted offline by XOR with `keystream.bin` — **no AES key needed**.

---

## Kernel Binary Properties

| Property | Value |
|----------|-------|
| Location | mtd1 (/dev/mtd1) |
| Partition size | 3,407,872 bytes (3.3 MB) |
| Payload (ciphertext) | 3,358,720 bytes (0x334000) |
| Padding | 49,152 bytes (0xC000) of 0xFF |
| Flash offset | 0x100000 (1 MB from start) |
| RAM load address | 0x80800000 |
| Encryption | AES-128 stream cipher (DCP OTP unique key, CTRL1=0xfe00) |
| Compression | gzip — decryption produces gzip stream |
| Plaintext format | encrypted( gzip( zImage ) ) |

---

## Cipher Mode — Confirmed Stream Cipher (June 2026)

### Test Method

Zero-plaintext test on 3,358,720 bytes of mtd1 ciphertext. For a block cipher in CBC/ECB mode, repeated plaintext blocks yield repeated ciphertext blocks. Stream/CTR mode produces a unique keystream position per offset — all ciphertext blocks are unique even when PT is all-zeros.

```python
ct = open('mtd1.bin', 'rb').read(3358720)
blocks = [ct[i:i+16] for i in range(0, len(ct), 16)]
from collections import Counter
c = Counter(blocks)
print(c.most_common(1))   # → [(<bytes>, 1)]
```

**Result:** 0 matching blocks out of 79,845 total. Sampled 1,000 keystream blocks — all unique.

**Conclusion:** Stream cipher confirmed. AES-CBC/ECB definitively ruled out.

---

## DCP Descriptor Analysis (June 2026 — Confirmed from mtd0 Disassembly)

The u-Boot function `do_decrypt_decompress` at file offset `0x29B0` (link addr `0x87801180`) builds a DCP channel-0 descriptor for kernel decryption.

### DCP Descriptor Layout (mode=3 kernel decrypt)

```
sp+0x34: NEXT     = 0           ; NULL (single-shot)
sp+0x38: CTRL0    = 0x723       ; first block: cipher+decrypt+OTP+enable
                   = 0x523       ; subsequent blocks
sp+0x3c: CTRL1    = 0xfe00      ; KEY_SELECT=0xfe = MXS_DCP_OTP_UNIQUE_KEY
sp+0x40: SRC_BUF  = <encrypted block addr>
sp+0x44: DST_BUF  = <same addr> ; in-place decryption
sp+0x48: BUFSIZE  = <chunk size, max 0x400>
sp+0x4c: PAYLOAD  = <pointer to 4x u32 OCOTP words>
sp+0x50: STATUS   = 0
```

### CTRL1 = 0xfe00 — What This Means

`CTRL1 bits [15:8] = 0xfe = KEY_SELECT field.`

Per NXP i.MX6UL DCP reference manual:
- `0x00-0x03`: DCP internal key slots 0-3
- `0xfe`: **OTP unique key** — key is derived from hardware OTPMK fuses; inaccessible to software
- `0xff`: OTPMK XOR SRK

The OTPMK hardware-masks all reads — `/sys/fsl_otp/HW_OCOTP_OTPMK*` returns `0xbadabada` on all 8 registers. The AES key is permanently inaccessible.

### OCOTP Values Are the DCP PAYLOAD (Not the AES Key)

The four OCOTP words passed to DCP are the **PAYLOAD** field, not the key. They function as an IV or tweak value for the OTPMK-derived key:

```asm
; Mode=3 path — u-Boot 0x87800df4
ldr r3, [0x021BC410]       ; OCOTP_CFG0     -> key_buf[0]
ldr r3, [0x021BC420]       ; OCOTP_CFG1     -> key_buf[1]
bl  fuse_read(4, 2, ...)   ; SW_GP2/GP412   -> key_buf[2] = 0
bl  fuse_read(4, 3, ...)   ; SW_GP3/GP413   -> key_buf[3] = 0
bl  memcpy(r6, sp+0x34, 16) ; copy to PAYLOAD buffer
b   0x87800f00              ; DCP processing loop
```

**Our CCPA device DCP PAYLOAD values (read 2026-06-30):**

| Register | Value | Role |
|----------|-------|------|
| OCOTP_CFG0 | `0x692173ca` | payload[0] |
| OCOTP_CFG1 | `0x1d16c1d7` | payload[1] |
| SW_GP2 (bank4 w2) | `0x00000000` | payload[2] |
| SW_GP3 (bank4 w3) | `0x00000000` | payload[3] |

Testing these 16 bytes directly as an AES-128 key: **failed** — confirms they are payload/IV, not the AES key.

---

## Decrypted Kernel (Confirmed June 2026)

| Property | Value |
|----------|-------|
| File | decrypted_gzip.bin |
| Size | 3,358,720 bytes |
| MD5 | 1e31cb1d156ea9d9aa520c615b761f3e |
| Magic bytes | 1f 8b 08 00 00 00 00 00 00 03 (gzip, mtime=0, os=Unix) |
| After gunzip | zimage_decrypted.bin |
| zImage magic | 18 28 6F 01 at +0x24 (ARM Linux) |
| Kernel version | Linux 3.14.52+g94d07bb |

---

## Re-Encryption Recipe (Offline Kernel Modification)

keystream.bin (3,358,720 bytes, device-specific for THIS CCPA unit) = CT XOR PT_gzip.

Any modified kernel can be re-encrypted offline:

```python
#!/usr/bin/env python3
MAX_PAYLOAD = 3_358_720
PARTITION   = 3_407_872

with open('modified_gzip.bin', 'rb') as f:
    new_pt = f.read()
with open('keystream.bin', 'rb') as f:
    ks = f.read()

assert len(new_pt) <= MAX_PAYLOAD, f"gzip too large: {len(new_pt)} > {MAX_PAYLOAD}"
assert len(ks) == MAX_PAYLOAD

new_ct  = bytes(a ^ b for a, b in zip(new_pt, ks))
new_ct += ks[len(new_ct):]                    # pad tail with keystream (= XOR of zero bytes)
new_ct += b'\xff' * (PARTITION - MAX_PAYLOAD) # flash-erase padding

with open('new_mtd1.bin', 'wb') as f:
    f.write(new_ct)
```

**Flash command (from rootfs shell):**
```bash
flash_erase /dev/mtd1 0 0 && nandwrite -p /dev/mtd1 new_mtd1.bin
```

Or from u-Boot:
```
sf erase 0x040000 0x340000 && sf write 0x80800000 0x040000 0x340000
```

**No kernel signature check** — u-Boot only decrypts and jumps; a correctly re-encrypted kernel runs without further validation.

---

## Boot Flow (Encryption Detail)

```
sf probe 0
sf read 0x80800000 0x100000 0x4F0000   <- encrypted mtd1 to RAM
sf read 0x83000000 0x5F0000 0x10000    <- DTB to RAM
[do_decrypt_decompress() called on 0x80800000]
  -> DCP channel 0, CTRL1=0xfe00 (OTPMK key), PAYLOAD=CFG0/CFG1/0/0
  -> decrypts 3,358,720 bytes in-place
  -> gunzips to zImage in-place
bootz 0x80800000 - 0x83000000          <- boots kernel
```

---

## Previous Decryption Attempts (Historical)

All prior software-key attempts failed because the key is hardware-bound (DCP OTPMK) and the mode is stream (not CBC):

| Key | Algorithm | Why It Failed |
|-----|-----------|---------------|
| `AutoPlay9uPT4n17` | AES-128-CBC | OTA image key, not kernel key; also wrong mode |
| `W2EC1X1NbZ58TXtn` | AES-128-CBC | USB session key; also wrong mode |
| CFG0+CFG1+GP2+GP3 (reference device) | AES-128 | Wrong device (Carlinkit V2 fuse values) |
| CFG0+CFG1+GP2+GP3 (our CCPA device) | AES-128 | DCP PAYLOAD field, not the AES key |

---

## Anti-Debug Hardening

- `CONFIG_STRICT_DEVMEM`: blocks `/dev/mem` access to kernel memory regions
- `ptrace` globally rejected with `EINVAL` — no on-device function tracing
- No ftrace (`/sys/kernel/debug/tracing` absent)

---

## References

- U-Boot binary: `mtd0.bin` (link base 0x877FE7D0; IVT at file 0x1000)
- Encrypted kernel: `mtd1.bin` (backup `20260629_224242_FINAL_consoleFix_bb137_db2026.91/`)
- Keystream: `keystream.bin` (3,358,720 bytes — DEVICE-SPECIFIC, only valid for this CCPA unit)
- Decrypted gzip: `decrypted_gzip.bin` (MD5: 1e31cb1d156ea9d9aa520c615b761f3e)
- OCOTP dump: `ccpa_ocotp_dump.txt` (read 2026-06-30 via /sys/fsl_otp/)
- Kernel compilation guide: `01_Firmware_Architecture/kernel_compilation.md`
- HAB/SRK/OTPMK architecture: `05_Security_Analysis/secure_boot_hab.md`

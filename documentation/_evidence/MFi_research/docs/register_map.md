# MFi 2.0C Register Map — Verified

Apple MFi Authentication Coprocessor 2.0C, lower bank. Verified live against the CPC200-CCPA chip at `/dev/i2c-1:0x11` on 2026-05-13.

The chip is a single I²C slave with byte-addressable registers. Some are 1 byte, some return multi-byte data when read after setting the internal address pointer.

| Reg | Size | Direction | Description | Observed on this chip |
|---|---|---|---|---|
| `0x00` | 1 | R | DeviceVersion (`0x03` = MFi 2.0C lower bank) | `0x03` |
| `0x01` | 1 | R | Firmware revision | `0x01` |
| `0x02` | 1 | R | AuthProtoMajor | `0x02` |
| `0x03` | 1 | R | AuthProtoMinor | `0x00` (→ "AuthProto 2.0") |
| `0x04` | 1 | R | DeviceID byte 0 | `0x00` |
| `0x05` | 1 | R | DeviceID byte 1 (also documented as ErrorCode in some sources) | `0xff` (unmapped or empty) |
| `0x06` | 1 | R | DeviceID byte 2 | `0xff` |
| `0x07` | 1 | R | DeviceID byte 3 | `0xff` |
| `0x10` | 1 | R/W | AuthControlStatus — **write `0x01` to trigger signing**; poll **bit 4** for completion | toggles during sign |
| `0x11` | 2 | R | ChallengeResponseLen (big-endian u16) | `0x00 0x80` = 128 after sign |
| `0x12` | N | R | ChallengeResponse data (`N` = ChallengeResponseLen, 128 for RSA-1024) | 128 bytes |
| `0x20` | 2 | W | ChallengeDataLen (big-endian u16) — write before challenge data | `0x00 0x14` = 20 for standard challenge |
| `0x21` | N | W | ChallengeData (`N` = ChallengeDataLen) | 20 bytes typical |
| `0x30` | 2 | R | AccessoryCertLen (big-endian u16) | `0x03 0xb1` = 945 |
| `0x31` | N | R | AccessoryCertData — `N` = AccessoryCertLen; **single i2ctransfer burst of 945 bytes works on 2.0C**, no paging needed despite docs/clients (incl. mossyhub's `mfi_auth_daemon.c`) implementing 3-page fallback | full 945 returned in one transfer |
| `0x32` | — | R | Cert page 2 (only used if chip requires paging) | not exercised |
| `0x33` | — | R | Cert page 3 (only used if chip requires paging) | not exercised |
| `0x40` | 1 | R | SelfTestStatus (MFi 3.0 register; on 2.0C lower bank, reads unmapped) | `0xff` |

## Reading examples (i2c-tools on the adapter)

```bash
# Identity probe
i2cget -y 1 0x11 0x00                          # → 0x03 (DeviceVersion)
i2cget -y 1 0x11 0x01                          # → 0x01 (Firmware)
i2cget -y 1 0x11 0x02                          # → 0x02 (Proto major)
i2cget -y 1 0x11 0x03                          # → 0x00 (Proto minor)

# Cert length (BE u16)
i2ctransfer -y 1 w1@0x11 0x30 r2@0x11          # → 0x03 0xb1 = 945

# Cert dump (single burst)
i2ctransfer -y 1 w1@0x11 0x31 r945@0x11        # → 945 hex bytes
```

## Sign roundtrip sequence

```bash
# 1. Write challenge length (BE u16) to reg 0x20
i2ctransfer -y 1 w3@0x11 0x20 0x00 0x14         # length = 20

# 2. Write challenge data (20 bytes) to reg 0x21
i2ctransfer -y 1 w21@0x11 0x21 <20 hex bytes>

# 3. Trigger sign — write 0x01 to reg 0x10
i2cset -y 1 0x11 0x10 0x01

# 4. Poll bit 4 of reg 0x10 — chip NACKs reads while signing (~750 ms for RSA-1024)
busybox usleep 100000                            # initial settle
n=0
while [ $n -lt 200 ]; do
    s=$(i2cget -y 1 0x11 0x10 2>/dev/null) && [ "$((s & 0x10))" -ne 0 ] && break
    busybox usleep 10000
    n=$((n+1))
done

# 5. Read response length (BE u16)
i2ctransfer -y 1 w1@0x11 0x11 r2@0x11           # → 0x00 0x80 = 128

# 6. Read signature (128 bytes for RSA-1024)
i2ctransfer -y 1 w1@0x11 0x12 r128@0x11
```

## Gotchas

- **Reading a single byte from reg `0x31` via `i2cget` partially starts a cert paging operation** that confuses subsequent full-cert `i2ctransfer` calls. Always dump the cert via a single `i2ctransfer w1+r945` before any single-byte reads of `0x30`–`0x33`.
- **The chip NACKs reads while it's busy signing.** Polling loops must catch the NACK (i.e. `i2cget` returning a non-zero exit) and silently retry, not exit on first failure. Total signing time is ~750 ms.
- `/tmp/mfi_i2c_addr` is written by AppleCarPlay after it negotiates with the chip; if absent, the chip hasn't been queried this boot. Doesn't block manual queries.
- **The chip signs the 20-byte challenge as if it were a SHA-1 digest already** — it doesn't compute SHA-1 over the challenge. See `build_and_verify.md` for verify command.
- **Bus contention with `ARMiPhoneIAP2` and `AppleCarPlay`.** The firmware uses `/tmp/.mfi_auth_lock` to arbitrate. Our scripts ignore this lock; the first probe sometimes returns junk (e.g. `0xa6` for DeviceVersion) if it lands on top of the firmware's transaction. Retry-on-retry recovers cleanly. Stopping the daemons (`killall ARMiPhoneIAP2 AppleCarPlay`) eliminates contention if needed.

## Firmware symbolic names (from `firmware_internals.md`)

The Carlinkit firmware's binary string table uses these names for the same registers:

| Firmware symbol | Address | Our name in this doc |
|---|---|---|
| `MFI_AUTH_COP_REG_ADDR_DEV_ID` | `0x04` | DeviceID byte 0 |
| `MFI_AUTH_COP_REG_ADDR_ERR_CODE` | `0x05` | ErrorCode (reads `0xff` unmapped here) |
| `MFI_AUTH_COP_REG_ADDR_AUTH_CTRL_AND_STATUS` | `0x10` | AuthControlStatus |
| `MFI_AUTH_COP_REG_ADDR_SIGNATURE_LEN` | `0x11` | ChallengeResponseLen |
| `MFI_AUTH_COP_REG_ADDR_SIGNATURE_DATA` | `0x12` | ChallengeResponse |
| `MFI_AUTH_COP_REG_ADDR_CHALLENGE_LEN` | `0x20` | ChallengeDataLen |
| `MFI_AUTH_COP_REG_ADDR_CHALLENGE_DATA` | `0x21` | ChallengeData |
| `MFI_AUTH_COP_REG_ADDR_ACC_CERT_LEN` | `0x30` | AccessoryCertLen |
| `MFI_AUTH_COP_REG_ADDR_ACC_CERT_DATA_BASE` | `0x31`+ | AccessoryCertData (pages) |

These confirm the chip implements the published MFi 2.0C spec exactly. Function call chain in the firmware: `APSMFiPlatform_CopyCertificate` (cert read) and `APSMFiPlatform_CreateSignature` (sign) → `mfi_auth_processchallenge` (low-level sequence) → I²C writes via `_DoI2C` against the Linux `/dev/i2c-1` device file. See `firmware_internals.md` for the full call structure and the `/dev/mem`-based GPIO mechanism that controls the chip's reset line.

# Findings

## Headline 1: there is a real hardware MFi chip on the I²C bus

Confirmed live on 2026-05-13 against the user's CPC200-CCPA adapter at 192.168.43.1. Evidence:

1. **I²C bus scan** locates a chip at `/dev/i2c-1:0x11` — the canonical address strap for an Apple MFi 2.0C authentication coprocessor.
2. **Register reads** return values consistent with the MFi 2.0C lower-bank protocol:
   - DeviceVersion = `0x03`
   - FirmwareVersion = `0x01`
   - AuthProto major/minor = `2.0`
3. **Certificate read** returns 945 bytes of well-formed PKCS#7 SignedData containing an X.509 certificate issued by `Apple iPod Accessories Certificate Authority`, valid 2007-12-27 → 2015-12-27, Subject CN `IPA_3333AA071227AA02AA0011AA003045`, RSA-1024 public key, signed with SHA-1.
4. **Live signature roundtrip** — wrote a random 20-byte challenge, triggered the chip, read back a 128-byte RSA signature, verified successfully against the chip's own cert public key using `openssl pkeyutl -verify -pkeyopt digest:sha1 -pkeyopt rsa_padding_mode:pkcs1`. **Only a chip possessing the matching RSA private key can produce this signature.**

## Headline 2: pure software emulation is ruled out

A reasonable hypothesis: maybe there's no real chip and a kernel module synthesizes I²C responses (like the parallel-port dongle emulators of the 90s). Evidence against, from `firmware_internals.md`:

| Observation | Inconsistent with software emulation |
|---|---|
| Firmware opens `/dev/i2c-1` via standard Linux i2c-dev | A custom emulator would expose its own API, not require the firmware to go through kernel i2c-master |
| Function `mfi_auth_setupgpio` exists and is called | Emulators don't need GPIO setup |
| Firmware mmaps `/dev/mem` and accesses GPIO2 controller registers (base `0x020A0000`) directly — 74 raw byte references in `ARMiPhoneIAP2` | Hardware-specific register-level driving; no emulator needs this |
| Retry-on-NACK error paths (`MFi auth read register 0x%02X failed (try %d)`) | Software emulators don't NACK |
| Cross-process lock file `/tmp/.mfi_auth_lock` | Software emulator could serialize requests internally; the lock only makes sense for sharing a real bus |
| Address-fallback probe (`mfi get version failed, mfi ic is not from APPLE, use other addr`) | Strap-selected hardware addresses; emulator would hardcode |
| No custom kernel modules registered as i2c slaves; standard `imx-i2c` driver only | A stub kernel module would appear in `/proc/modules` and `/sys/bus/i2c/drivers/` — we checked; none present |

The chip is hardware. Whether the silicon is genuine Apple or third-party clone is a separate question — see Headline 3.

## Headline 3: Carlinkit's adapter fleet shares one MFi credential set

A second physical adapter (Carlinkit u2air — different product line from CCPA but circuit-wise identical; the user has previously cross-flashed CCPA firmware images onto u2air units and had them work) was dumped at `dumps/adapter2-20260513-180307/`. Result:

**Bit-for-bit identical `chip.img` across both adapters.** Zero-byte diff in `cmp -l`. All SHA-256s match. Same cert serial, same Subject CN, same RSA public key, and **the same 128-byte RSA signature for the same fixed challenge** — proving both chips hold the same RSA private key (RSA PKCS#1 v1.5 is deterministic; identical input + identical key ⇒ identical output).

Apple's MFi program design issues each licensed accessory chip a uniquely-keyed cert+key pair fused into silicon at the factory. Two physically distinct units holding the same private key means one of:

| Possibility | Consistent with evidence? |
|---|---|
| Two genuine Apple chips happen to share identity | No — Apple doesn't issue duplicates; never observed in 18+ years of MFi |
| The same physical chip in both adapters | No — user confirmed swap |
| **Clone silicon programmed with leaked Apple-issued credentials** | **Yes** — explains the shared key, the cross-product-line match, and the DeviceID register pattern (see below) |
| Apple-licensed silicon with deliberately duplicate keys | Vanishingly unlikely; violates Apple's program structure |

The clone hypothesis is also supported by DeviceID registers `0x04-0x07` reading `0x00 0xff 0xff 0xff` on both — genuine Apple chips would each have a distinct DeviceID, but clone silicon often doesn't bother populating per-chip identity bytes.

The cross-flash-EEPROM observation also fits: both boards have functionally interchangeable MFi chips (same credentials), so the firmware image, which expects exactly those credentials, works against either chip.

## What this contradicts

The prior assumption (recorded in `CarPlay_Pi_AAOS_Feasibility.md` §3.4 and §6, dated 2026-04-04) was that the CPC200-CCPA has no physical MFi coprocessor and relies on software-emulated credentials from `/var/lib/lockdown/`. That assumption is **empirically wrong on this hardware**:

- The chip is physically present on the I²C bus and responds to the standard MFi 2.0C register protocol.
- The firmware's `[mfi_auth] mfi get version failed, mfi ic is not from APPLE, use other addr` log line — previously thought to be dead code — is the firmware actively probing the bus, trying one address (`0x10`), failing, and falling back to `0x11`. The tty log capture at `cpc200_ccpa_firmware_binaries/analysis/adapter_ttylog_aa_nav_20260315.txt:473` shows this happening at session init.
- The files at `/var/lib/lockdown/common.cert` and `/var/lib/lockdown/root_key.pem` are the iOS **host-pairing identity** used by the adapter's `lockdownd` daemon when acting as a USB host to iPhones. They are not MFi accessory credentials. Different protocol layer.

That said, the prior plan's broader intuition — "Carlinkit is doing something with shared leaked Apple credentials" — was directionally correct. Just the storage location was wrong: the credentials are on the chip silicon, not in the files at `/var/lib/lockdown/`.

## Implication for the Pi feasibility plan

The plan's "software-only MFi via software-substituted `common.cert` + `root_key.pem`" path (section 6.2) will not authenticate to a real iPhone. Replacement paths:

| Path | Approach | Trade-offs |
|---|---|---|
| A | Add a genuine MFi IC to the Pi BOM (~$15 gray-market 2.0C QFN-16, or proper MFI343S00177 3.0) on the Pi's I²C bus. Reimplement `MFiPlatform_*` functions to talk to it via the verified register sequence in `register_map.md`. | Keeps "no external dongle" promise. Adds 1 IC. ~80 lines of platform glue C. |
| B | Run mossyhub's `mfi_auth_daemon` on a rooted CPC200 sitting on the same WiFi network. Pi's MFi functions become TCP clients on port 5290. | Does not meet the no-dongle goal. Useful for prototyping. |
| C | Use leaked credentials extracted from somewhere. | No reliable working source against current iOS. Not recommended. |

## Implication for cross-adapter cloning analysis

Apple issues each MFi accessory chip a unique cert and unique RSA keypair. This means:

- Different adapters with the same physical hardware (same model, same firmware) should have **different** chip certs.
- Same SHA-256 of `cert.der` across adapters indicates either the same physical chip dumped twice, or cloned/shared credentials.

The fingerprint workflow in `../README.md` is designed exactly to answer this question. Run `mfi_dump.sh` on each adapter, then `mfi_compare.sh` across the dumps to see whether each chip is independently Apple-issued or whether credentials are shared.

## Baseline dump

The current adapter's dump at `dumps/adapter1-20260513-175905/` serves as the comparison baseline.

| | |
|---|---|
| `chip.img` SHA-256 | `aa5aac09c9270ffaa2f199228bcd38100216736e790125f58a88cf1cbcb4e244` |
| `cert.der` SHA-256 | `0cfe6773bd4c7ab364c77b75fe6df5056aea16607740112a3dfa5d435ad4f0a1` |
| `pubkey.pem` SHA-256 | `ad4b6d40e4e248242d8d55c19ee3bf5fb1f473cdbbd54f900c24ccabdf11d4bc` |
| `sig.bin` SHA-256 | `90725e846d12a73318c9778ab89758ddbc4fc7859ace11e3e1f4ec2cf125a7d9` |
| Subject CN | `IPA_3333AA071227AA02AA0011AA003045` |
| Chip serial | `33:33:AA:07:12:27:AA:02:AA:00:11:AA:00:30:45` |
| Signature verifies | yes |

## Second-adapter comparison: identical credentials confirmed (2026-05-13)

A second physical Carlinkit adapter — **marketed as the Carlinkit "u2air", a different product line from the CCPA but circuit-wise identical** (the user has previously cross-flashed CCPA EEPROM images onto u2air units and had them work) — was dumped at `dumps/adapter2-20260513-180307/`. Result:

**Bit-for-bit identical `chip.img` across both adapters.** Zero-byte diff in `cmp -l`. All SHA-256s match. Same cert serial, same Subject CN, same RSA public key, and **the same 128-byte RSA signature for the same fixed challenge** — proving both chips hold the same RSA private key (RSA PKCS#1 v1.5 is deterministic; identical input + identical key ⇒ identical output).

This means the Carlinkit CPC200-CCPA fleet is using a **shared MFi credential set** across physical units:

- The cert (`IPA_3333AA071227AA02AA0011AA003045`) was originally issued by Apple to one MFi-licensed accessory and has been duplicated across multiple production units.
- The matching RSA private key has likewise been duplicated.
- Genuine Apple MFi 2.0C silicon can't hold a key it wasn't manufactured with, so the chips here are most likely **third-party (clone) silicon programmed with the leaked Apple-issued credentials** — running the same I²C register protocol as a real MFi 2.0C, responding identically to the iPhone's challenge-response handshake.
- DeviceID bytes at regs `0x04-0x07` reading `0x00 0xff 0xff 0xff` on both (where genuine Apple chips would each have unique DeviceIDs) further supports the clone hypothesis.

### Practical consequence

Any Carlinkit CPC200-CCPA adapter in your fleet should be expected to produce the **same `chip.img`** as this baseline. Tooling that targets one's MFi chip targets all of them.

This also rehabilitates the prior "software-emulated MFi" intuition partially: Carlinkit's MFi auth IS based on a leaked Apple credential set, just one that has been burned into chip silicon rather than stored as files at `/var/lib/lockdown/`. The functional pattern is "all units share one cert+key from a single Apple-issued chip." For research/RE purposes, this means characterising the MFi authentication path on one unit applies to all of them.

### Lockdown-files-removed test: chip is independent of those files (2026-05-13)

To rule out the "firmware emulates MFi by reading from `/var/lib/lockdown/`" theory definitively, we:

1. Captured a 945-byte cert read from chip reg 0x31 *with* `/var/lib/lockdown/common.cert` and `root_key.pem` in place.
2. Moved both files to `.bak` (renamed away, fully removed from their expected paths).
3. Re-read the chip cert via i2ctransfer. **Result: byte-identical to the read with files in place.** `diff` returns empty.
4. Restored the files (SHA-256s confirm exact restoration).

This proves the chip is the source of the MFi cert and is not driven by file contents.

Additional supporting data:

| File / source | Size | SHA-256 | Purpose |
|---|---|---|---|
| `/var/lib/lockdown/common.cert` | 7612 B | `c493f5dc...` | iOS host-pairing identity (lockdownd) |
| `/var/lib/lockdown/root_key.pem` | 1675 B | `89c854fe...` | RSA-2048 private key for lockdownd |
| MFi chip cert (from reg 0x31) | 945 B | `0cfe6773...` | Apple-issued MFi 2.0C cert |
| MFi chip pubkey | RSA-1024 | — | Embedded in the 945-byte cert above |

Three completely different files, different sizes, different key sizes (RSA-2048 vs RSA-1024). The lockdown files are the iOS host-pairing identity used when the adapter acts as a USB host to an iPhone (via `lockdownd` protocol — what a Mac uses for iTunes pairing). The MFi cert is a different protocol layer for accessory authentication and lives on the chip. They are independent.

### What this still doesn't enable

The private RSA key remains inside the chip silicon and is not extractable over I²C. **A Pi running pure software MFi (no chip) still cannot authenticate against a real iPhone** unless it has the matching private key — which we don't have in software form, only in working signing form via the chip. Paths forward remain:

1. Use any one of these cloned-credential CPC200 adapters as a network-attached MFi signing service (mossyhub's `mfi_auth_daemon` pattern at TCP port 5290).
2. Source genuine MFi silicon for the Pi (different cert+key, but Apple-licensed and unique per chip).
3. Side-channel or fault-injection extraction of the shared private key from one of these clone chips — see `ic_security_analysis.md` for in-system and bench paths.

## Considerations for any follow-up work

These are decisions we'd want to make on subsequent sessions, captured here so they don't get re-derived:

### Tooling location

- Cross-toolchain is `armv7-unknown-linux-musleabihf` (brew, messense tap). Glibc-based toolchains fail with "kernel too old" against the CCPA's Linux 3.14 — patching the ELF `.note.ABI-tag` does NOT bypass this; the check is in glibc's startup code, not the static note. Must use musl.
- The five compiled binaries (`i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, `i2ctransfer`) are checked in at `bin/`. Each is ~67 KB statically linked.
- `bin/` binaries are pushed to `<adapter>:/tmp/` per session because `/tmp` is volatile. For persistent tools, write to `/usr/sbin/` on the adapter (rootfs is writable on this firmware) — but that survives reboots, which may not be desirable for stealth or cleanup.

### Volatile vs persistent state

| Path | Volatile? | Notes |
|---|---|---|
| `/tmp/i2c*` (our pushed tools) | yes (RAM) | Re-push after each reboot |
| `/tmp/mfi_i2c_addr` | yes | Firmware re-creates on first MFi access |
| `/tmp/.mfi_auth_lock` | yes | Per-session mutex |
| `/var/lib/lockdown/*.cert` and `*.pem` | no (rootfs) | Survived reboot in our tests. Restored cleanly after the lockdown-files-removed test. |
| Chip-resident state | no (silicon) | Cert, key, DeviceID baked in. Not erasable from software. |

### What an in-firmware dump cannot answer

- Whether the silicon is genuine Apple or clone — requires decap.
- The private key — requires side-channel/fault-injection analysis (`ic_security_analysis.md`).
- Which i.MX6UL GPIO2 pin controls the chip's reset — requires live trace or disassembly (`ic_security_analysis.md` § "Finding the MFi reset GPIO").

### What software-only analysis could still achieve

| Analysis class | Reachable from software? |
|---|---|
| Protocol-level dump (cert, sig, register snapshot) | ✓ Done — see `chip.img` |
| GPIO-based reset glitch + Bellcore-style fault analysis | ✓ Feasible once pin is known |
| PMIC undervolt glitch | ✓ Feasible if PMIC output identification is clean |
| Timing side-channel | △ Marginal — Linux scheduling noise floor is poor |
| Power analysis (SPA/DPA) | ✗ No on-board ADC |
| EM analysis | ✗ No antenna/SDR |
| Decap inspection | ✗ Requires physical destruction |

The fault-injection path (glitch RESET during sign, collect partial signatures, Bellcore analysis against CRT-RSA) is the most promising software-only key-extraction angle. Whether it works depends on whether the clone silicon uses CRT-RSA (likely — it's the standard implementation for small chips) and how robust its fault-detection is (clones are typically weaker than Apple's reference).

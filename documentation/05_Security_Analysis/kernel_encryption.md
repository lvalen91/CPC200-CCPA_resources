# CPC200-CCPA Kernel Encryption Analysis

**Purpose:** Document kernel encryption findings and decryption/re-encryption capability
**Analysis Date:** 2026-01-29 (initial); 2026-06-30 morning session (cipher-mode claim, later found wrong); 2026-06-30 evening session (corrected via fresh disassembly + live DCP register work); **2026-06-30 night session (plaintext kernel actually recovered, via a different route)**
**Status:** **Plaintext kernel recovered.** Cipher mode and register map were confirmed via disassembly cross-checked against the real Linux `mxs-dcp.c` driver source, but live re-derivation via a userspace DCP trigger was never made to work reliably (see "Live DCP Attempts" below). That whole approach turned out to be unnecessary: u-Boot already decrypts the kernel into RAM once, every boot, before jumping to it — so the plaintext just has to be read back out of the running system's physical memory, no crypto engine needed. Done, see "Breakthrough" section below. Artifacts in `custom/kernel_dumps/`.

---

## TL;DR (2026-06-30 night)

**The plaintext kernel has been extracted, from live RAM, no DCP register access required.** u-Boot decrypts mtd1 into RAM and jumps to it once per boot; the resulting running kernel's `.text`/`.data` sit at a fixed, `/proc/iomem`-documented physical address for the entire uptime of the device. Reading that range with a plain `dd if=/dev/mem` yields the exact decrypted, decompressed kernel bytes — banner string, ~43k `/proc/kallsyms` symbols, and real ARM opcodes all confirmed. See "Breakthrough" below for the full method and caveats (this is the linked, resident image at its final address, not a byte-identical copy of any zImage/Image file that once existed on flash — see caveats before using it to rebuild a flashable image).

The kernel in mtd1 is encrypted with **AES-128-CBC** (not stream/CTR — the earlier same-day doc revision was wrong, see "Corrected Finding" below) using the DCP hardware AES engine's **`OTP_KEY`** mode (`KEY_SELECT=0xfe`, i.e. `DCP_PAES_KEY_UNIQUE` in mainline Linux's naming — a per-chip key derived from OTPMK fuses, never software-readable). The 16-byte IV is `OCOTP_CFG0 ‖ OCOTP_CFG1 ‖ SW_GP2 ‖ SW_GP3`, all of which ARE readable (`/sys/fsl_otp/`) and device-specific but not secret. This is all still true and still the reason the DCP-register route is hard — it's just no longer the only way to get the plaintext.

**The 2026-06-30 morning doc revision claiming "AES-128 CTR/stream, keystream.bin XOR recipe, SOLVED" was incorrect.** No `keystream.bin` or `decrypted_gzip.bin` from that session ever existed on disk (checked exhaustively — repo, device, home directory); the claim was apparently generated without the backing artifacts surviving, and the "zero repeated 16-byte block" test used to justify "stream cipher" doesn't actually distinguish CBC from CTR when the plaintext is gzip-compressed data (gzip output essentially never repeats a 16-byte block regardless of cipher mode). Disassembly-derived register values point at CBC, not CTR — see below.

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
| Encryption | AES-128-CBC, DCP `OTP_KEY` mode (KEY_SELECT=0xfe, "UNIQUE" key) |
| Compression | gzip — decryption is expected to produce a gzip stream |
| Plaintext format (expected) | encrypted( gzip( zImage ) ) — **not yet confirmed live**, see below |

---

## Corrected Finding: Cipher Mode Is CBC, Not Stream/CTR (2026-06-30 evening)

Re-disassembled `mtd0.bin` from scratch (Capstone, Thumb-2, base `0x877FE7D0`) around `do_decrypt_decompress` (file offset `0x29B0`, link addr `0x87801180`) and its worker at `0x87800df4`, independent of the morning session's notes, then cross-checked every register/bit assumption against the **real, current mainline Linux `drivers/crypto/mxs-dcp.c` and `include/linux/stmp_device.h`** (fetched live from `torvalds/linux`, not from memory).

### DCP Descriptor Layout (mode=3 kernel decrypt) — struct matches Linux's `struct dcp_dma_desc` exactly

```
+0x00: next        = 0            ; NULL (single descriptor, no chain)
+0x04: control0    = 0x723        ; first block (CIPHER_INIT set)
                    = 0x523        ; continuation blocks (no CIPHER_INIT)
+0x08: control1    = 0xfe10       ; KEY_SELECT=0xfe (bits[15:8]) | CIPHER_MODE_CBC (bit4=0x10) | CIPHER_SELECT_AES128 (0x0)
+0x0C: source       = <ciphertext addr>
+0x10: destination  = <same addr>  ; in-place
+0x14: size         = <byte count> ; NOT limited to 0x400 — a single descriptor covers the whole 3,358,720-byte transfer in u-Boot's real call
+0x18: payload      = <ptr to 16-byte IV buffer: OCOTP_CFG0 ‖ CFG1 ‖ SW_GP2 ‖ SW_GP3>
+0x1C: status       = 0
```

### Where the earlier doc went wrong

- It wrote `CTRL1 = 0xfe00`. The actual value, confirmed twice independently from the disassembly literal pool, is **`0xfe10`**. The extra nibble (bit4, `MXS_DCP_CONTROL1_CIPHER_MODE_CBC`) is the whole ballgame: 0xfe00 has no mode bits set (=ECB), 0xfe10 explicitly selects CBC.
- `CONTROL0 = 0x723` also encodes **`CIPHER_ENCRYPT`** (bit8, `1<<8`) — i.e. u-Boot's kernel-recovery routine runs the DCP block's "encrypt" datapath, not "decrypt". This looks backwards for a function literally named `do_decrypt_decompress`, but it's not a contradiction: HeWei's build tooling most likely produced the flashed ciphertext using the AES **decrypt** datapath in the first place (a legitimate, if unusual, choice — Encrypt_K and Decrypt_K are exact inverses of each other for the same key regardless of which one is arbitrarily labeled "encrypt"), so recovering the original data at boot correctly uses the opposite datapath. This bit **must** be set exactly as disassembled — u-Boot boots successfully every single time using this literal value, so it is definitionally correct for this device.
- The "zero-block dedup ⇒ stream cipher" test in the prior write-up is not valid evidence either way for CBC vs CTR, given gzip-compressed plaintext.
- `PAYLOAD` is a 16-byte **IV**, not "key or tweak material" as vaguely stated before. Confirmed against `mxs-dcp.c`: when a referenced/OTP key is used, `desc->payload` points at exactly 16 bytes (`aes_key + AES_KEYSIZE_128`, i.e. the IV half of a would-be 32-byte key+IV buffer) — this matches the CFG0/CFG1/GP2/GP3 layout exactly.

### Register Map (physical, confirmed via u-Boot disassembly + `mxs-dcp.c`/`stmp_device.h`)

```
DCP_BASE            = 0x02280000    (confirmed live via /proc/iomem: "crypto@2280000")
  CTRL              = +0x00         (bit31=SFTRST, bit30=CLKGATE; +0x04=SET alias, +0x08=CLR alias — STMP "SCT" addressing)
  STAT               = +0x10         (bits[3:0] = per-channel IRQ pending; +0x18 = its own CLR alias)
  CHANNELCTRL        = +0x20         (bitmask of enabled channels, 0xff = all 8)
  CONTEXT            = +0x50         (context-switch buffer ptr; driver deliberately sets 0xffff0000, an illegal/ROM address, since context switching is unused)
  CH0CMDPTR          = +0x100        (physical address of the descriptor to run on channel 0)
  CH0SEMA            = +0x110        (write N to kick off N queued descriptors)
  CH0STAT            = +0x120        (per-channel status; nonzero low byte = real error — NOT the same as the descriptor's own .status field)
  CH0STAT_CLR        = +0x128        (CLR alias of CH0STAT — must be cleared before EVERY submission, confirmed from mxs_dcp_start_dma())
```

**Bug found in this session's tooling, not the hardware:** earlier attempts cleared the *global* `STAT_CLR` (0x18) before each descriptor but never the *per-channel* `CH0STAT_CLR` (0x128), which is what the real driver's `mxs_dcp_start_dma()` actually does. This produced non-deterministic, size-independent flakiness (identical sizes sometimes completed, sometimes timed out) that looked like a race condition — it was cleaner once fixed but did not fully resolve the trigger issue (see below).

### Reset Sequence — also corrected

DCP (and every other "mxs"-family Freescale/NXP IP block) uses **STMP-style Set/Clear/Toggle register aliasing**: for any base register at offset `N`, `N+4` is a SET-only alias (OR) and `N+8` is a CLR-only alias (AND-NOT) — this is `lib/stmp_device.c`'s `stmp_reset_block()`, used verbatim by `mxs-dcp.c`'s `probe()`. An ad-hoc plain read/write-based reset (assert SFTRST, clear SFTRST, clear CLKGATE via direct `CTRL=` writes) is NOT equivalent and was replaced with a faithful port of the real `stmp_reset_block()` (poll-clear SFTRST → clear CLKGATE via CLR alias → set SFTRST via SET alias → poll CLKGATE-becomes-set → poll-clear SFTRST → poll-clear CLKGATE). See `custom/tools/dcp_decrypt.c` in this repo.

---

## Live DCP Attempts (2026-06-30 evening, on the `db2026.91` test unit, 192.168.50.2)

Built a small static ARM/musl tool (`custom/tools/dcp_decrypt.c`, cross-compiled in the `ccpa-build` Lima VM) that drives the DCP registers directly from Linux userspace via `/dev/mem`, using OCRAM (`0x00905000`–`0x0091ffff`, NOT part of the "System RAM" resource so not blocked by `CONFIG_STRICT_DEVMEM`) as the descriptor/payload/data scratch buffer.

**What's confirmed:**
- `/dev/mem` MMIO access to both the DCP register block and OCRAM works fine (read AND write), for both the single-word `busybox devmem` tool and our own `mmap()`-based tool. Bulk `dd`-based access to the *same* OCRAM addresses fails with `EFAULT` ("Bad address") — `dd` goes through the char-device `read()/write()` syscalls, which apply a stricter `devmem_is_allowed()`/`pfn_valid()` check than the `mmap()` path does. **Always use mmap, not dd, for /dev/mem bulk transfer on this kernel.**
- Real AES transforms genuinely execute (output ≠ input, not a passthrough) for a range of chunk sizes, and `CH0STAT` reads back `0` (no hardware-reported error) on completion.
- Output for the first bytes of the real mtd1 ciphertext does **not** start with the gzip magic (`1f 8b`) under the register values above, so either something is still subtly wrong, or a fresh/cold DCP channel needs some additional priming step not yet identified.
- The completion-detection race is real and reproducible: identical inputs sometimes complete in a handful of poll spins and sometimes never signal completion within a multi-second poll window, even after adding proper `dsb()` barriers and the correct `CH0STAT_CLR` clear-before-trigger step.
- **A tight retry-with-full-hardware-reset loop (asserting SFTRST/CLKGATE repeatedly on every timeout, in a busy-poll with no CPU yield) wedged the device once** — SSH/ICMP became unresponsive for several minutes; USB-level enumeration (`system_profiler`/`ioreg` still showed "Auto Box" on the bus) suggested a watchdog-triggered reboot rather than a hard hang, most likely because the busy-poll starved the single Cortex-A7 core long enough to prevent whatever kicks the hardware watchdog. **Recovered fully via a physical power-cycle — no flash was ever written (mtd0/mtd1/mtd2 untouched throughout), so this was a soft/recoverable hang, not damage.** Post-recovery the device booted clean with identical DCP baseline register values.
- Re-tested with a single properly-sourced reset (real `stmp_reset_block()` port, run once or even twice at startup) and a single bounded, CPU-yielding poll per chunk (abort cleanly on timeout, no further hardware touches) — this is **safe** (confirmed: two clean timeouts in a row caused zero device disruption) but the underlying trigger **still does not reliably complete on a freshly-booted channel**. The chunk sizes that appeared to "work" earlier in the session only ever succeeded after many prior (broken) attempts had already run against the channel — this now looks less like confirmation the technique works and more like an artifact of leftover/stale hardware state from the earlier buggy retry storm. **Do not trust the earlier "real transformation, CH0STAT=0" observations as proof of correctness** until reproduced from a clean boot.

**Open questions for next attempt:**
1. Is there a required OCOTP "shadow reload" or similar priming step between cold boot and the DCP being able to use `OTP_KEY` mode from a *second* invocation (u-Boot's own one-time use at boot clearly works — this may be a "works once per power-cycle" hardware quirk, or purely a bug in the userspace port still).
2. Consider capturing the *actual* register write sequence and timing via a logic analyzer / JTAG trace of u-Boot's own decrypt at boot, rather than continuing to guess from static disassembly + generic Linux driver source (which targets a similar but not necessarily byte-identical DCP revision).
3. Rather than fighting the completion race from Linux post-boot, consider patching u-Boot itself (already established as flashable, see `firmware_encryption.md`/`secure_boot_hab.md`) to dump the decrypted buffer to a UART/USB path immediately after its own successful `do_decrypt_decompress()` call, before `bootz`. This sidesteps the whole "replicate the trigger from Linux" problem since u-Boot demonstrably gets it right every boot.
4. `custom/tools/dcp_decrypt.c` in this repo has the current state of the tool (safe version, no retry storm) — pick up from there rather than re-deriving the register map.

---

## Breakthrough: Plaintext Kernel Recovered via Direct RAM Read (2026-06-30 night)

After the DCP register trigger repeatedly failed to complete reliably from Linux userspace (see above), stepped back from "replicate u-Boot's decrypt" to "u-Boot already ran the decrypt — go read the result." u-Boot decrypts mtd1 into RAM and jumps into it exactly once per boot; the running kernel's code and data then sit at a fixed physical address for the rest of that boot's uptime, and Linux itself documents exactly where in `/proc/iomem`:

```
80000000-87ffffff : System RAM
  80008000-8058b327 : Kernel code
  805c0000-806684c7 : Kernel data
```

No DCP involvement needed — this is just reading already-decrypted bytes back out of RAM.

### Method

```
ssh root@192.168.50.2 'dd if=/dev/mem bs=4096 skip=524296 count=2048' > kernel_ram_dump_0x80008000.bin
```

(`skip=524296` = `0x80008000 / 4096`; `count=2048` = 8 MiB, i.e. `0x80008000`–`0x80808000`, comfortably covering both the "Kernel code" and "Kernel data" ranges plus the gap between them.) Streamed straight over the SSH pipe to the Mac rather than writing to the device — root's `/` had only 6.2 MB free, but this never touched flash either way.

Also pulled `/proc/kallsyms` (42,960 entries — full symbol table, name→physical address) and the first 60 lines of `dmesg` for boot-time context.

### Verification

- `strings` on the dump surfaces `Linux version 3.14.52+g94d07bb (hcw@ubuntu) (gcc version 4.9.2 (GCC) ) #12 SMP PREEMPT Fri Sep 26 16:45:10 CST 2025` — the exact banner reported live by `/proc/version` on the same boot — plus dozens of real i.MX6/ARM kernel symbol name strings (`mxc_restart`, `imx6q_pm_pu_power_on`, `vfp_single_add`, etc).
- First bytes decode as plausible ARM32 instruction encodings (condition-code nibble `e` = "always" on nearly every 4-byte word), not random/encrypted-looking bytes.
- `/proc/kallsyms`'s first real symbol, `_stext` at `80008200`, is 0x200 into the dump — consistent with the standard short ARM Linux boot-stub header occupying the first 0x200 bytes before `_stext`.
- Byte histogram: 74% non-zero, no long zero-run padding pattern — consistent with real packed code+data, not an unmapped/faulted region silently reading as zeros.

### Caveats — what this is and isn't

- This is the **linked, resident kernel image at its final run address** (post zImage self-decompression), not a byte-identical copy of the zImage or raw Image that once sat in a bootloader staging buffer. It's missing the self-extracting decompressor stub and the original compressed wrapper. It **is** the real `.text`/`.data` content, which is what matters for reading code, finding strings/functions, and diffing against a stock reference build.
- It reflects the *current running state*, not necessarily the pristine flashed image — e.g. any runtime relocation, but for this architecture kernel .text/.data are not self-modifying in the general case, so this should match the flashed content closely modulo re-relocatable sections (`.init`, freed after boot, may already be gone from the "Kernel code" range's tail — the reported range shrinks as init sections are reclaimed by the buddy allocator, which likely explains why the code range's actual conservative-hexdump extent is smaller than the original zImage would suggest).
- To turn this into something reflashable (a modified mtd1), still need to reconstruct a bootable image format (raw `Image` or self-decompressing `zImage`) using this dump + `kallsyms_running.txt` as the byte/symbol-accurate reference, and would still need either (a) a way to write a *new* encrypted mtd1 image u-Boot will accept (requires driving the DCP **encrypt** path, still unsolved live), or (b) patching u-Boot to skip/bypass the decrypt step for a plain unencrypted replacement kernel (see `secure_boot_hab.md` for HAB constraints on modifying u-Boot itself). The read-side secrecy problem — "what does the real kernel contain" — is fully solved; the write-side problem (flashing a modified kernel back) is not addressed by this technique and remains open.

### Artifacts (this repo, `custom/kernel_dumps/`)

| File | Contents |
|------|----------|
| `kernel_ram_dump_0x80008000.bin` | 8 MiB raw dump, physical `0x80008000`–`0x80808000` (covers `/proc/iomem`'s Kernel code + Kernel data ranges and the gap between) |
| `kallsyms_running.txt` | Full `/proc/kallsyms` (42,960 symbols) — address→name map for the dump above |
| `dmesg_boot.txt` | First 60 lines of `dmesg` from the same boot, for cross-reference |

Device state at capture time: `db2026.91` test unit, 192.168.50.2, uptime 21 min (clean boot after the earlier DCP-experiment recovery), `/proc/cmdline`: `console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2 mtdparts=21e0000.qspi:256k(uboot),3328K(kernel),12800K(rootfs) rootwait quiet rw`.

---

## Previous Decryption Attempts (Historical, still valid)

| Key | Algorithm | Why It Failed |
|-----|-----------|---------------|
| `AutoPlay9uPT4n17` | AES-128-CBC | OTA image key, not kernel key |
| `W2EC1X1NbZ58TXtn` | AES-128-CBC | USB session key, not kernel key |
| CFG0+CFG1+GP2+GP3 (reference device) | AES-128 | Wrong device (Carlinkit V2 fuse values) |
| CFG0+CFG1+GP2+GP3 (our CCPA device, as literal AES key) | AES-128 | This is the IV (DCP `PAYLOAD` field), not the AES key — the key is hardware-only (`OTP_KEY`/`KEY_SELECT=0xfe`) and never touches software in any form |

---

## Anti-Debug Hardening

- `CONFIG_STRICT_DEVMEM` claim **needs re-verification** — an earlier note here said reads at `0x80800000` (the pre-decompression staging address) succeeded via `mmap()` but failed via `dd`'s read()/write() path. That doesn't hold universally: plain `dd if=/dev/mem` against `0x80008000`–`0x80808000` (the live "Kernel code"/"Kernel data" range from `/proc/iomem`) worked with **zero errors**, no `mmap()` needed (see "Breakthrough" above). Either this kernel doesn't actually have `CONFIG_STRICT_DEVMEM` enabled (never confirmed directly — `/proc/config.gz` isn't present on this build), or the restriction (if any) is finer-grained than "System RAM" and doesn't cover the specific reserved kernel-code/data sub-ranges. Don't assume `dd` is blocked on System RAM without testing the exact address first.
- `ptrace` globally rejected with `EINVAL` — no on-device function tracing
- No ftrace (`/sys/kernel/debug/tracing` absent)

---

## References

- U-Boot binary: `mtd0.bin` (link base 0x877FE7D0; IVT at file 0x1000; IVT self-check confirms this base)
- Encrypted kernel: `mtd1.bin` (backup `20260629_224242_FINAL_consoleFix_bb137_db2026.91/`)
- OCOTP live values (2026-06-30, re-verified via both `/sys/fsl_otp/` and direct `/dev/mem` MMIO read of `0x021bc410`/`0x021bc420`): CFG0=`0x692173ca`, CFG1=`0x1d16c1d7`, SW_GP2=`0x0`, SW_GP3=`0x0`
- Live DCP driver tool: `custom/tools/dcp_decrypt.c` (current safe version — single reset, single attempt per chunk, no retry storm)
- Plaintext kernel (recovered via direct RAM read, not DCP): `custom/kernel_dumps/kernel_ram_dump_0x80008000.bin`, `kallsyms_running.txt`, `dmesg_boot.txt`
- Authoritative register/bit reference used to correct this doc: `torvalds/linux` `drivers/crypto/mxs-dcp.c`, `include/soc/fsl/dcp.h`, `include/linux/stmp_device.h`, `lib/stmp_device.c`
- Kernel compilation guide: `01_Firmware_Architecture/kernel_compilation.md`
- HAB/SRK/OTPMK architecture: `05_Security_Analysis/secure_boot_hab.md`

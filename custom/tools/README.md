# custom/tools

On-device diagnostic/RE tools built for the CCPA, cross-compiled static ARM/musl
via the `ccpa-build` Lima VM (`zig cc -target arm-linux-musleabihf -static`).

## dcp_decrypt.c

Drives the i.MX6ULL DCP crypto engine directly via `/dev/mem` from Linux
userspace, replicating u-Boot's `do_decrypt_decompress()` kernel-decrypt path.
See `documentation/05_Security_Analysis/kernel_encryption.md` ("Live DCP
Attempts") for full context, what's confirmed, and what's still broken before
picking this back up.

*Note 2026-10-19:* this tool is not needed to read or write the kernel any more. Only the first
3 × 64 KB of the kernel are DCP-encrypted, and the same bytes sit in the kernel partition's
staging blocks under a software key (see the 2026-10-19 section of `kernel_encryption.md`).
The tool itself takes any length (`<total_len>` on the command line) and checks no magic; it was
the 2026-06-30 attempts that fed it the whole mtd1 region and looked for gzip magic in the
output, neither of which matches the real format (corrected 2026-10-19; this note first said the
tool did both).

Build:
```
zig cc -target arm-linux-musleabihf -static -O2 -o dcp_decrypt dcp_decrypt.c
strip dcp_decrypt
```

Usage:
```
./dcp_decrypt <ocotp_cfg0_hex> <ocotp_cfg1_hex> <total_len> [chunk_size] < ciphertext > plaintext
```

Current state: single clean hardware reset at startup (real `stmp_reset_block()`
port), one bounded/CPU-yielding attempt per chunk, aborts immediately on
timeout — deliberately has NO retry-with-hardware-reset loop, because an
earlier version that looped resets on every timeout wedged the test unit for
several minutes (recovered via power-cycle, no flash damage). Do not
reintroduce a reset-retry loop without a stronger reason to believe it's safe.

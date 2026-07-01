# custom/tools

On-device diagnostic/RE tools built for the CCPA, cross-compiled static ARM/musl
via the `ccpa-build` Lima VM (`zig cc -target arm-linux-musleabihf -static`).

## dcp_decrypt.c

Drives the i.MX6ULL DCP crypto engine directly via `/dev/mem` from Linux
userspace, replicating u-Boot's `do_decrypt_decompress()` kernel-decrypt path.
See `documentation/05_Security_Analysis/kernel_encryption.md` ("Live DCP
Attempts") for full context, what's confirmed, and what's still broken before
picking this back up.

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

# Carlinkit .img Firmware Format Analysis

## Overview

This document details the reverse engineering of the Carlinkit firmware update `.img` format, specifically for the A15W model. The format uses AES-128-CBC encryption to protect a gzip-compressed tar archive.

## File Format

```
+------------------------------------------------------------------+
|                    AES-128-CBC Encrypted Data                     |
|                   (block-aligned, 16-byte blocks)                 |
+------------------------------------------------------------------+
|  Unencrypted Remainder (0-15 bytes if file size % 16 != 0)       |
+------------------------------------------------------------------+
```

**Decrypted Contents:**
```
.img (encrypted) → .tar.gz (gzip compressed) → tar archive containing:
├── etc/
│   ├── init.d/rcS
│   ├── boa/cgi-bin/
│   ├── software_version
│   └── ...
├── lib/
├── script/
├── tmp/
│   ├── once.sh        (pre-update script)
│   ├── finish.sh      (post-update script)
│   └── remove_unnecessary_file.sh
└── usr/
    └── lib/
```

## Encryption Details

### A15W Model

| Property | Value |
|----------|-------|
| Algorithm | AES-128-CBC |
| Key | `AutoPlay9uPT4n17` |
| IV | `AutoPlay9uPT4n17` |
| Key (hex) | `4175746f506c617939755054346e3137` |
| Block Size | 16 bytes |
| Padding | None - last partial block left unencrypted |

### Other Known Model Keys

| Model | Key | Source |
|-------|-----|--------|
| U2W | `CarPlay5KBP6ClJv` | ludwig-v repo |
| U2AW | `CarPlayBbnF6ecFP` | ludwig-v repo |
| U2AC | `CarPlayiHXF1o74i` | ludwig-v repo |
| HWFS modules | `8e15c895KBP6ClJv` | ludwig-v repo |
| **A15W** | `AutoPlay9uPT4n17` | **Extracted from ARMimg_maker** |

### Key Extraction Method

The A15W key was extracted by:

1. Unpacking `ARMimg_maker` using ludwig-v's modified UPX:
   ```bash
   # On the adapter (ARM device)
   /path/to/modified/upx -d /usr/sbin/ARMimg_maker -o /tmp/ARMimg_maker_unpacked
   ```

2. Searching for 16-character alphanumeric strings:
   ```bash
   strings ARMimg_maker_unpacked | grep -E "^[A-Za-z0-9]{16}$"
   ```

3. The key `AutoPlay9uPT4n17` was identified as the only candidate matching the expected pattern.

## Decryption Process

### Using OpenSSL

```bash
AES_KEY="AutoPlay9uPT4n17"
KEY_HEX=$(printf "%s" "$AES_KEY" | od -A n -t x1 | tr -d ' \n')
IV_HEX="$KEY_HEX"

# Calculate block alignment
FILESIZE=$(stat -f %z input.img)  # macOS
# FILESIZE=$(stat -c%s input.img)  # Linux
TRUNCATED=$((FILESIZE - (FILESIZE % 16)))
REMAINDER=$((FILESIZE % 16))

# Decrypt block-aligned portion
head -c $TRUNCATED input.img > temp_enc.bin
openssl enc -d -aes-128-cbc -nopad -K "$KEY_HEX" -iv "$IV_HEX" \
    -in temp_enc.bin -out output.tar.gz

# Append unencrypted remainder
if [ $REMAINDER -gt 0 ]; then
    tail -c $REMAINDER input.img >> output.tar.gz
fi

rm temp_enc.bin
```

### Verification

```bash
# Check for gzip magic bytes (1f 8b)
xxd output.tar.gz | head -1
# Expected: 00000000: 1f8b 0800 ...

# Verify gzip integrity
gunzip -t output.tar.gz

# Extract contents
tar -xzf output.tar.gz -C ./extracted/
```

## Encryption Process

To create a custom `.img` from a modified `tar.gz`:

```bash
AES_KEY="AutoPlay9uPT4n17"
KEY_HEX=$(printf "%s" "$AES_KEY" | od -A n -t x1 | tr -d ' \n')
IV_HEX="$KEY_HEX"

FILESIZE=$(stat -f %z input.tar.gz)
TRUNCATED=$((FILESIZE - (FILESIZE % 16)))
REMAINDER=$((FILESIZE % 16))

# Encrypt block-aligned portion
head -c $TRUNCATED input.tar.gz > temp_plain.bin
openssl enc -e -aes-128-cbc -nopad -K "$KEY_HEX" -iv "$IV_HEX" \
    -in temp_plain.bin -out output.img

# Append unencrypted remainder
if [ $REMAINDER -gt 0 ]; then
    tail -c $REMAINDER input.tar.gz >> output.img
fi

rm temp_plain.bin
```

## ARMimg_maker Binary Analysis

### Location
- Original: `/usr/sbin/ARMimg_maker`
- Size: 21,056 bytes (packed)
- Unpacked: 37,696 bytes

### Packing
- Packed with modified UPX (Carlinkit-specific)
- Standard UPX cannot unpack it
- Requires ludwig-v's modified UPX binary (ARM)

### Key Strings (from unpacked binary)
```
AutoPlay9uPT4n17          # AES key
AES_encrypt               # OpenSSL function
AES_decrypt               # OpenSSL function
AES for ARMv4, CRYPTOGAMS by <appro@openssl.org>
./update.tar.gz           # Output filename
/proc/self/exe
```

### Behavior
1. Reads `.img` file from command line argument
2. Decrypts using AES-128-CBC with hardcoded key
3. Writes decrypted data to `./update.tar.gz` in current directory

## Firmware Update Flow

```
USB/OTA Download
      │
      ▼
/tmp/A15W_Update.img
      │
      ▼ (ARMimg_maker)
/tmp/update.tar.gz
      │
      ▼ (tar -xzf)
/tmp/update/
├── etc/
├── lib/
├── script/
├── tmp/once.sh
└── usr/
      │
      ▼ (once.sh runs)
Files copied to rootfs
      │
      ▼ (finish.sh runs)
Update complete, reboot
```

## Creating Custom Firmware

### Step 1: Decrypt Official Firmware
```bash
./FirmwareA15W.sh decrypt A15W_Update.img firmware.tar.gz
```

### Step 2: Extract
```bash
mkdir custom_firmware
tar -xzf firmware.tar.gz -C custom_firmware
```

### Step 3: Modify
```bash
# Example: Ensure dropbear stays enabled
sed -i 's/^#dropbear/dropbear/' custom_firmware/etc/init.d/rcS

# Example: Add custom script
cp my_script.sh custom_firmware/script/
```

### Step 4: Repack
```bash
cd custom_firmware
tar -czf ../custom.tar.gz .
cd ..
```

### Step 5: Encrypt
```bash
./FirmwareA15W.sh encrypt custom.tar.gz A15W_Update.img
```

### Step 6: Deploy
```bash
# Copy to USB drive
cp A15W_Update.img /Volumes/USB_DRIVE/

# Or SCP to adapter's USB mount
scp A15W_Update.img root@192.168.43.1:/mnt/UPAN/
```

## Security Considerations

- The encryption key is hardcoded in `ARMimg_maker`
- Same key used for both encryption and IV (weak)
- No signature verification on firmware packages
- Custom firmware can be created and deployed without restriction
- The adapter will accept any properly encrypted `.img` file

## Files

| File | Description |
|------|-------------|
| `A15W_Update.img` | Original encrypted firmware |
| `A15W_decrypted.tar.gz` | Decrypted firmware archive |
| `A15W_extracted/` | Extracted firmware contents |
| `ARMimg_maker` | Original packed binary |
| `ARMimg_maker_unpacked` | Unpacked binary (key extracted from here) |
| `FirmwareA15W.sh` | Encrypt/decrypt script |

## References

- ludwig-v reverse engineering repo: Contains modified UPX and other model keys
- `PROTOCOL_ANALYSIS.md`: USB protocol documentation
- `CONFIG_KEYS_REFERENCE.md`: Configuration key documentation
- `SESSION_HANDOFF.md`: Project overview and status

---

*Analysis completed: 2026-01-14*
*Firmware version analyzed: 2025.10.15.1127*
*Target device: Carlinkit A15W*

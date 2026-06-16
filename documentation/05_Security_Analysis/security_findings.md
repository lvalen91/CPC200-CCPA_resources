# CPC200-CCPA Security Vulnerabilities

**Purpose:** Security findings from reverse engineering — authorized research documentation
**Last Updated:** 2026-02-19 (Added: api.cgi unauthenticated endpoints, SSH/telnet no-auth, WiFi default passphrase, OTA no-signature, CGI 777 perms, weak entropy)

---

## Summary of Findings

| Category | Severity | Status |
|----------|----------|--------|
| Command Injection via BoxSettings | CRITICAL | Binary + live verified Jan 2026 |
| Hardcoded Encryption Keys | HIGH | Binary verified |
| No Firmware Signature Verification | HIGH | Binary verified |
| Arbitrary File Write (SendFile 0x99) | HIGH | Binary + live verified Jan 2026 |
| Init Script Writable | HIGH | Live verified Jan 2026 |
| Unauthenticated Web CGI (api.cgi) | HIGH | Live verified Feb 2026 |
| SSH Root — No Password | CRITICAL | Live verified Feb 2026 |
| Telnet — No Authentication | CRITICAL | Live verified Feb 2026 |
| WiFi Default Passphrase | HIGH | Live verified Feb 2026 |
| OTA — No Signature Verification | HIGH | Binary verified Feb 2026 |
| CGI Files World-Writable | HIGH | Live verified Feb 2026 |
| Weak Entropy Source | MEDIUM | Live verified Feb 2026 |
| Debug Commands (0x88) | MEDIUM | Binary verified |
| Connection Timeout / DoS Vector | LOW | Confirmed |
| Expired MFi Certificate | LOW | Confirmed functional |
| Custom Init Hook | INFO | Confirmed |
| Anti-Debug Hardening | INFO | Confirmed |

---

## 0. Command Injection via BoxSettings (CRITICAL) — Binary Verified Jan 2026

### Finding

The firmware constructs shell commands using `popen()` and `/bin/sh`, inserting values from the BoxSettings JSON message (`wifiName`, `btName`, `oemIconLabel`) directly into the command string without sanitization. Shell metacharacters in these fields are interpreted by `/bin/sh`.

### Vulnerable Code Paths

**WiFi SSID field (`wifiName`):**
```c
sed -i "s/^ssid=.*/ssid=%s/" /etc/hostapd.conf
```

**Bluetooth name field (`btName`):**
```c
sed -i "s/name .*;/name \"%s\";/" /etc/bluetooth/hcid.conf
```

**OEM icon label field (`oemIconLabel`):**
```c
sed -i "s/^.*oemIconLabel = .*/oemIconLabel = %s/" <target_file>
```

### Other `popen()` Call Sites in Binary

The binary contains 50+ hardcoded shell command templates executed via `popen()`:

| Command Pattern | Trigger | User-Controlled Input |
|-----------------|---------|----------------------|
| `sed -i "s/ssid=.*/ssid=%s/"` | BoxSettings `wifiName` | Yes |
| `sed -i "s/name .*/name \"%s\";"` | BoxSettings `btName` | Yes |
| `killall AppleCarPlay; AppleCarPlay --width %d --height %d --fps %d` | Open message | Integers only |
| `tar -xvf %s -C /tmp` | hwfs.tar.gz upload | Path only |
| `/script/phone_link_deamon.sh %s start` | Phone connection | Hardcoded |
| `echo -n %s > /etc/box_product_type` | BoxSettings | Possibly |

### Impact

- All firmware processes run as root (only user on system)
- No sandboxing — full filesystem access
- Injection in `wifiName`/`btName` fields allows arbitrary command execution as root
- When injection is used, the sed command fails, so the SSID/name is not actually updated; a second clean BoxSettings message is needed to set the intended value

### Live Testing (Jan 2026)

Three payloads were live-tested and confirmed on hardware via USB. All executed as root. Specific payloads omitted from this document; results confirmed: file creation, password change, config modification.

### Mitigations Required

1. Sanitize all user inputs — strip or escape shell metacharacters before inserting into command strings
2. Replace `popen()` with `execv()`-family calls to avoid shell interpretation entirely
3. Whitelist allowable characters for name fields (alphanumeric + limited set)
4. Run firmware processes as a non-root user where possible
5. Enforce input length limits

---

## 1. Hardcoded Encryption Keys

### USB Encryption Keys

| Item | Value | Algorithm |
|------|-------|-----------|
| SessionToken key | `W2EC1X1NbZ58TXtn` | AES-128-CBC |
| Protocol payload key | `SkBRDy3gmrw1ieH0` | AES-128-CFB128 |

**Location:** Embedded in ARMadb-driver binary (visible after UPX unpacking). All adapters share the same keys.

**Note:** Both keys have been identified across firmware versions; context of use differs. See `crypto_stack.md` for the full encryption system analysis.

**Risk:** USB traffic can be decrypted by any party who has extracted the key from any unit.

### Firmware Encryption Key (A15W)

| Item | Value | Algorithm |
|------|-------|-----------|
| Firmware image key | `AutoPlay9uPT4n17` | AES-128-CBC |

**Location:** ARMimg_maker binary (strings extraction).

**Risk:** Firmware images can be decrypted, modified, re-encrypted, and deployed.

---

## 2. No Firmware Signature Verification

### Finding

The firmware update process:
1. Decrypts `.img` using the hardcoded key
2. Extracts tar.gz contents
3. Executes `once.sh` from the extracted archive
4. Copies files to rootfs
5. **No signature verification at any step**

### Impact

Custom firmware can be created by decrypting official firmware, modifying contents, re-encrypting with the known key, and deploying via USB drive, SendFile (0x99), or OTA. See section 8d for the OTA path.

---

## 3. Arbitrary File Write — SendFile (0x99) — Binary Verified Jan 2026

### Protocol Format

```
Message Type: 0x99 (SendFile)
Payload:
  [4 bytes] path length
  [N bytes] file path (null-terminated)
  [4 bytes] content length
  [M bytes] file content
```

### Path Validation: None (Binary Verified)

| Check | Status | Evidence |
|-------|--------|----------|
| Path whitelist | None | No `strncmp("/tmp/")` or prefix check in binary |
| Path traversal filter | None | No `../` sanitization |
| File extension filter | None | Any extension accepted |
| Size limit | Exists | Firmware logs `UPLOAD FILE Length Error!!!`; exact limit unknown |

### Filesystem Writability (SSH/Telnet Verified)

| Path | Writable | Notes |
|------|----------|-------|
| `/tmp/*` | Yes | tmpfs, RAM-backed (~50–80 MB) |
| `/etc/*` | Yes | Persistent flash — **not** read-only squashfs |
| `/script/*` | Yes | Startup scripts |
| `/usr/*` | Likely | Depends on flash partition |
| `/mnt/UPAN/*` | Yes | USB drive mount point |

**Binary evidence of /etc writability:**
```bash
cp /tmp/carlogo.png /etc/boa/images/carlogo.png
cp /etc/riddle_default.conf /etc/riddle.conf
rm -f /etc/riddle.conf
echo -n %s > /etc/box_product_type
sed -i "s/..." /etc/bluetooth/hcid.conf
```

### Notable Target Paths

| Path | Effect |
|------|--------|
| `/tmp/*` | Session-only persistence |
| `/etc/riddle.conf` | Persistent configuration override |
| `/script/custom_init.sh` | Executes at every boot (see §10) |
| `/tmp/hwfs.tar.gz` | Automatically extracted by firmware (`tar -xvf ... -C /tmp`) |
| `/tmp/*Update.img` | Triggers firmware update path |

### Capability: Binary Upload (Live Tested Jan 2026)

SendFile accepts arbitrary binary content. The adapter architecture is armv7l (ARM 32-bit). `/tmp` has ~52 MB free (tmpfs). `/usr/sbin` is writable. SendFile combined with the command injection path allows uploading and executing additional tooling.

For files exceeding the SendFile size limit, the firmware auto-extracts `/tmp/hwfs.tar.gz`, enabling multi-file payloads in a single message.

---

## 4. Debug Commands (CMD_DEBUG_TEST — 0x88)

| Value | Action |
|-------|--------|
| 1 | Opens `/tmp/userspace.log`, runs `/script/open_log.sh` |
| 2 | Reads log file, sends contents to host |
| 3 | Enables persistent debug mode flag |

**Risk:** Debug mode exposes system logs that may contain session data, connection details, and internal state. No authentication required to invoke.

---

## 5. Expired MFi Certificate

### Certificate Details

| Property | Value |
|----------|-------|
| Source | Hardware MFi 2.0C coprocessor — I²C `/dev/i2c-1:0x11`, register `0x31` (not a file) |
| Format | 945-byte PKCS#7 SignedData wrapping an X.509 certificate |
| Issuer | `Apple iPod Accessories Certificate Authority` (CA-issued, not self-signed) |
| Subject CN | `IPA_3333AA071227AA02AA0011AA003045` |
| Public key | RSA-1024 |
| Signature algorithm | SHA-1 with RSA |
| Validity | 2007-12-27 → 2015-12-27 (expired; iOS does not reject it) |
| Status | Functional |

### Clarification: `/var/lib/lockdown/` files are iOS host-pairing credentials, NOT MFi

The files under `/var/lib/lockdown/` are the adapter's iOS USB host-pairing identity used by `usbmuxd`/`lockdownd` when the adapter acts as a USB host to an iPhone — not MFi accessory credentials:

| Path | Size | Content |
|------|------|---------|
| `/var/lib/lockdown/common.cert` | 7612 B | plist `HostCertificate`/`RootCertificate` |
| `/var/lib/lockdown/root_key.pem` | 1675 B | RSA-2048 private key |
| `/Library/Keychains/default.keychain` | — | AirPlay pairing-identity store |

The actual MFi accessory credentials reside on the hardware MFi coprocessor at `/dev/i2c-1:0x11`, register `0x31`. Confirmed by test: chip cert is byte-identical with lockdown files renamed away. See `_evidence/MFi_research/docs/findings.md`.

### Additional Finding: Shared Credential Set

Two physically distinct Carlinkit units returned a bit-for-bit identical chip image — same cert serial, same RSA-1024 public key, same 128-byte signature for the same challenge. This indicates a **shared/cloned Apple-issued credential set** burned across the fleet rather than per-unit credentials. The private key is not extractable over I²C.

### Risk

- No certificate revocation checking on the expired MFi cert
- `root_key.pem` is a plaintext, world-readable RSA-2048 host-pairing private key stored without protection

---

## 6. Format String Exposure

### Locations in Binary

| Address | Trigger | Concern |
|---------|---------|---------|
| 0x1c0e4 | param_2 == 0x66 | Unknown command path |
| 0x1c0f4 | param_2 == 0 | State transition |
| 0x1c108 | param_2 == 1 | Format string with USB params |

**Risk:** Potential format string vulnerability if user-controlled data reaches these call sites. Requires further analysis to confirm exploitability.

---

## 7. D-Bus Interface Exposure

### Service: `org.riddle`

Available interfaces (accessible if shell access is obtained):

- `org.riddle.BluetoothControl` — including `AutoConnect` method
- `org.riddle.HUDCommand`
- `org.riddle.AudioSignal`

---

## 8. Weak WiFi Configuration (Live Verified Feb 2026)

| Parameter | Value |
|-----------|-------|
| Default passphrase | `12345678` |
| WPA mode | WPA2-PSK |
| Default SSID | `carlink` (configurable via BoxSettings) |

**Risk:** The default passphrase is trivially guessable. Combined with the unauthenticated api.cgi and no-auth SSH/telnet (§8b), any party within WiFi range can gain full administrative access without credentials.

---

## 8b. SSH/Telnet — No Authentication (Live Verified Feb 2026)

### Finding

Both SSH and telnet daemons start at boot with no password required for root login:

```bash
# /etc/init.d/rcS
dropbear                                    # SSH on port 22
/bin/busybox telnetd -l /bin/sh -p 23 &   # Telnet on port 23
```

| Service | Port | Authentication | Access Level |
|---------|------|----------------|--------------|
| SSH (dropbear) | 22 | None — root with empty password | Full root shell |
| Telnet | 23 | None — direct `/bin/sh` | Full root shell |

---

## 8c. Unauthenticated Web CGI — api.cgi (Live Verified Feb 2026)

The adapter runs Boa web server v0.94 on port 80. `/etc/boa/cgi-bin/api.cgi` (3,421-byte shell script) exposes administrative endpoints without authentication:

| Endpoint | Action |
|----------|--------|
| `?sysinfo` | JSON: memory, load, uptime, disk, CPU temp/freq, WiFi clients |
| `?ttylog` | Download `/tmp/ttyLog` (serial debug log) |
| `?dmesg` | Download kernel ring buffer |
| `?config` | Download `/etc/riddle.conf` (full device configuration) |
| `?governor_set=X` | Write CPU governor setting |
| `?overcommit_set=X` | Write VM overcommit policy |
| `?restore` | Factory reset via `riddleBoxCfg --restoreOld` |
| `?reboot` | Reboot device |

### Binary CGIs

`server.cgi` (48,744 B) and `upload.cgi` (35,916 B) are UPX-packed binaries that require MD5-HMAC authentication. Both HMAC keys live in **`server.cgi`** (at VMAs `0x1f59c` and `0x212d4`); neither key string appears in `upload.cgi`'s image, so upload.cgi likely shares the mechanism rather than embedding the keys:
- HMAC key 1: `HweL*@M@JEYUnvPw9G36MVB9X6u@2qxK`
- HMAC key 2: `Y4HH7BRvY*7!NSGaoMF@sIZ9bz#yNkBT`

**Risk:** The shell-script api.cgi endpoints give full administrative control — factory reset, reboot, config dump — to any client on the WiFi network with no credentials required.

---

## 8d. OTA Firmware — No Signature Verification (Binary Verified Feb 2026)

### Finding

From `/script/update_box_ota.sh`:

1. OTA image decoded by `ARMimg_maker` (`.img` → tar.gz → extract to rootfs)
2. HWFS images decoded by `hwfsTools`
3. **No signature verification** — MD5 integrity check only
4. Final step: `cp -r /tmp/update/* /` — direct rootfs overwrite

**Risk:** Any party who can deliver a firmware file (USB drive, SendFile 0x99, or WiFi) can deploy arbitrary firmware using the known encryption key (`AutoPlay9uPT4n17` for A15W).

---

## 8e. CGI Files World-Writable (Live Verified Feb 2026)

CGI files at `/etc/boa/cgi-bin/` have permissions `777`.

**Risk:** Any write access to the device (via SendFile, injection, or shell) allows replacing CGI scripts with modified versions that persist across reboots.

---

## 8f. Weak Entropy Source (Live Verified Feb 2026)

### Finding

Boot script replaces `/dev/random` with a symlink to `/dev/urandom`:

```bash
rm -f /dev/random
ln -s /dev/urandom /dev/random
```

**Risk:** All cryptographic operations using `/dev/random` (key generation, nonces) receive non-blocking pseudo-random data rather than hardware entropy. On this embedded platform with limited entropy sources, this weakens cryptographic guarantees.

---

## 9. Connection Timeout — DoS Vector

The heartbeat timeout is **15,000 ms**, hardcoded in the firmware binary (not configurable via riddleBoxCfg). A USB-connected client that establishes a session and stops sending heartbeats will cause the adapter to reset the connection after 15 seconds; repeated cycling keeps the adapter in a reconnection loop.

See `01_Firmware_Architecture/heartbeat_analysis.md` for complete timing analysis.

---

## 10. Custom Init Hook — Persistence Vector

The firmware executes `/script/custom_init.sh` at boot if the file exists:

```bash
# start_main_service.sh
test -e /script/custom_init.sh && /script/custom_init.sh
```

**Intended use:** Enabling SSH, custom configuration, development purposes.

**Risk:** Any write access that creates this file results in arbitrary code execution on every subsequent boot without further intervention. Combined with §3 (SendFile) or §0 (command injection), this provides persistent access.

---

## 11. Anti-Debug Hardening (INFO)

The kernel rejects all `ptrace` requests with `EINVAL` (kernel-wide) and ships no ftrace (`/sys/kernel/debug/tracing` absent). This blocks on-device syscall tracing, I²C tracing, and function tracing — deliberate anti-RE hardening. See `kernel_encryption.md` → "Anti-Debug: ptrace and ftrace Disabled".

---

## Attack Surface Summary

### Local (USB connection required)

| Vector | Mechanism |
|--------|-----------|
| Firmware replacement | Decrypt → modify → re-encrypt → deploy via USB or SendFile |
| Arbitrary file write | SendFile (0x99) with no path validation |
| Configuration injection | BoxSettings fields passed unsanitized to shell commands |
| Debug log extraction | CMD_DEBUG_TEST (0x88) |
| Persistent code execution | Write `/script/custom_init.sh` via SendFile or injection |

### Remote (WiFi access required)

| Vector | Mechanism |
|--------|-----------|
| Full root shell | SSH port 22 or telnet port 23 — no authentication |
| Administrative control | api.cgi — unauthenticated factory reset, reboot, config dump |
| Traffic decryption | USB encryption uses known hardcoded keys |

---

## Mitigations

### For Researchers

- Use in an isolated network environment
- Monitor adapter traffic for anomalies
- Factory reset after testing

### For Manufacturers

1. Replace hardcoded keys with per-device keys provisioned at manufacture
2. Implement firmware signature verification (e.g., ECDSA over the firmware image)
3. Sanitize all user-controlled strings before use in shell command templates; prefer `execv()` over `popen()`
4. Require authentication on api.cgi and all administrative web endpoints
5. Set SSH/telnet to require a non-empty password; disable telnet in production builds
6. Change the default WiFi passphrase to a per-unit random value
7. Remove or restrict debug command support (0x88) in production builds
8. Restore proper `/dev/random` entropy source

---

## Disclosure

This documentation supports authorized security research for the purpose of:
- Understanding CarPlay/Android Auto adapter internals
- Developing compatible open-source implementations
- Educational documentation of embedded device security

**References:** Firmware binary analysis on 2025.10 firmware using Ghidra 12.0 and radare2.

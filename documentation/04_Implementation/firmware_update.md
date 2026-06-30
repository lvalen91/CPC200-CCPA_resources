# CPC200-CCPA Firmware Update Mechanism

**Status:** Documented from binary analysis
**Source:** ARMadb-driver_unpacked binary analysis (January 2026)
**Purpose:** Host application guide for pushing and triggering firmware updates

---

## Overview

The CPC200-CCPA adapter supports firmware updates through multiple channels:
1. **USB Protocol (Host App)** - SendFile message (0x99) + auto-detection
2. **USB Storage** - Auto-scan for update images on mounted drives
3. **Web Interface** - HTTP upload via server.cgi

This document focuses on **Method 1: USB Protocol from Host Application**.

---

## Method 1: USB Protocol Firmware Update

### Step 1: Push Firmware Image via SendFile (0x99)

The host application sends the firmware image using the **SendFile** message type (0x99).

#### SendFile Message Format

```
USB Header (16 bytes):
+------------------+------------------+------------------+------------------+
|   0x55AA55AA     |   PayloadLen     |   0x00000099     |   0xFFFFFF66     |
|   (magic)        |   (see below)    |   (type=153)     |   (type check)   |
+------------------+------------------+------------------+------------------+

Payload Structure:
+----------+-------------------+------------+-------------------+
| PathLen  | FilePath          | ContentLen | FileContent       |
| (4B LE)  | (N bytes + null)  | (4B LE)    | (M bytes)         |
+----------+-------------------+------------+-------------------+
```

| Field | Offset | Size | Description |
|-------|--------|------|-------------|
| pathLen | 0x00 | 4 | Length of file path string (excluding null) |
| filePath | 0x04 | N+1 | Null-terminated file path (absolute path on adapter) |
| contentLen | 0x04+N+1 | 4 | Length of file content in bytes |
| content | 0x04+N+5 | M | Raw file content bytes |

**Total payload length:** `4 + (N+1) + 4 + M = N + M + 9`

**Staging:** the firmware buffers each `SendFile` upload through `/tmp/uploadFileTmp` before
moving it to the destination path given in the payload.

#### Update Image Naming Convention

The firmware auto-detects update images by checking for **"Update.img"** in the filename:

```c
// From binary analysis @ 0x1e084
if (strstr(filename, "Update.img") != NULL) {
    // Triggers OTA update
    system("/script/update_box_ota.sh <path> &");
}
```

**Recommended paths:**
- `/tmp/<model>_Update.img` - Standard update path
- `/tmp/CPC200_Update.img` - Example for CPC200 model

### Step 2: Trigger Update Execution

Once the file is written, the firmware **automatically** triggers the update if:
1. The filename contains "Update.img"
2. The file is accessible at the written path

**Alternative trigger methods:**

#### Method A: Automatic (Recommended)
Simply name your file with `*_Update.img` pattern - update triggers automatically upon file write completion.

#### Method B: Via D-Bus (if available)
```bash
# From HUD command strings
HUDComand_A_UploadFile  # Triggers file processing
```

#### Method C: Via Reboot
After pushing the file, trigger a reboot:
- Send `kRiddleHUDComand_A_Reboot` via D-Bus
- Or wait for connection timeout (15 seconds without heartbeat)

---

## Complete Host App Implementation

### Pseudocode: Push Firmware Update

```python
def push_firmware_update(usb_device, firmware_path, firmware_data):
    """
    Push a firmware update to the CPC200-CCPA adapter.

    Args:
        usb_device: Open USB device handle
        firmware_path: Destination path on adapter (e.g., "/tmp/CPC200_Update.img")
        firmware_data: Raw firmware image bytes
    """

    # 1. Build SendFile payload
    path_bytes = firmware_path.encode('utf-8') + b'\x00'  # Null-terminated
    path_len = len(firmware_path)  # Exclude null terminator
    content_len = len(firmware_data)

    payload = struct.pack('<I', path_len)          # 4 bytes: path length
    payload += path_bytes                           # N+1 bytes: path + null
    payload += struct.pack('<I', content_len)      # 4 bytes: content length
    payload += firmware_data                        # M bytes: file content

    # 2. Build USB header
    magic = 0x55AA55AA
    msg_type = 0x99  # SendFile
    type_check = msg_type ^ 0xFFFFFFFF

    header = struct.pack('<IIII', magic, len(payload), msg_type, type_check)

    # 3. Send message
    message = header + payload
    usb_device.bulk_write(ENDPOINT_OUT, message)

    # 4. Wait for update to start (firmware auto-detects "Update.img" pattern)
    # Update executes: /script/update_box_ota.sh /tmp/CPC200_Update.img &

    return True
```

### Example: TypeScript/Node.js Implementation

```typescript
interface SendFileMessage {
  path: string;
  content: Buffer;
}

function buildSendFileMessage(file: SendFileMessage): Buffer {
  const pathBuffer = Buffer.from(file.path + '\0', 'utf8');
  const pathLen = file.path.length;
  const contentLen = file.content.length;

  // Payload
  const payload = Buffer.alloc(4 + pathBuffer.length + 4 + contentLen);
  let offset = 0;

  payload.writeUInt32LE(pathLen, offset);           offset += 4;
  pathBuffer.copy(payload, offset);                  offset += pathBuffer.length;
  payload.writeUInt32LE(contentLen, offset);        offset += 4;
  file.content.copy(payload, offset);

  // Header
  const header = Buffer.alloc(16);
  header.writeUInt32LE(0x55AA55AA, 0);              // Magic
  header.writeUInt32LE(payload.length, 4);          // Length
  header.writeUInt32LE(0x99, 8);                    // Type (SendFile)
  header.writeUInt32LE(0xFFFFFF66, 12);             // Type check

  return Buffer.concat([header, payload]);
}

async function pushFirmwareUpdate(device: UsbDevice, firmwareData: Buffer): Promise<void> {
  const message = buildSendFileMessage({
    path: '/tmp/CPC200_Update.img',
    content: firmwareData
  });

  await device.bulkWrite(message);

  // Firmware auto-triggers update when it sees "Update.img" in path
  console.log('Firmware update pushed - adapter will auto-start update');
}
```

---

## Update Process Flow (Firmware Side)

### Detection Logic (fcn.0001d2fe @ 0x1e080)

```
1. File received via SendFile (0x99) handler
2. strstr(filename, "Update.img") check @ 0x1e084
3. If match found:
   - Log: "Is Update Img: %s" @ 0x1e0a0
   - Execute: sprintf(cmd, "/script/update_box_ota.sh %s &", path)
   - system(cmd) @ 0x1e0ac (the Binary Analysis References table cites 0x1e0a8 for this call; the two differ by 4 bytes — one is likely the sprintf argument-setup and the other the system() branch, exact address pending disassembly)
4. Update script runs in background
```

### Update Script Execution

**Script:** `/script/update_box_ota.sh <path>`

**Progress tracking files:**
| File | Purpose |
|------|---------|
| `/tmp/update_status` | Status code (version-dependent: 0-4 legacy pre-2025, 5-7 current firmware — see Status codes below) |
| `/tmp/update_progress` | Progress percentage |
| `/tmp/update_error` | Error message if failed |
| `/var/log/box_update.log` | Detailed update log |
| `/data/update/software_version` | Installed version after success |

**Status codes (firmware 2025.10.15 — from `update_box_ota.sh`):**
| Code | Meaning |
|------|---------|
| 5 | Decompressing/extracting |
| 6 | Success/complete |
| 7 | Error/failed |

> **Note:** Older firmware (pre-2025) used status codes 0-4 (0=starting, 1=downloading, 2=verifying, 3=installing, 4=complete). Current firmware (2025.10.15) uses codes 5, 6, 7 as shown above.

### Post-Update Reboot

```bash
# From firmware strings @ 0x6da34
echo "Save last log when reboot" > /var/log/box_last_reboot.log
dmesg | tail -n 2000 >> /var/log/box_last_reboot.log
tail -n 2000 /tmp/userspace.log >> /var/log/box_last_reboot.log
sync;sleep 1;reboot
```

**Note:** When manually rebooting via SSH, use `busybox reboot` instead of `reboot`. The `reboot` command may not work directly on some busybox configurations. The firmware's internal reboot script works because it's executed in a different shell context.

---

## Alternative Update Paths

### HiCar/Hewei Rootfs Update

The firmware also checks for `.hwfs` extension:

```c
// @ 0x1e0bc
if (strstr(filename, ".hwfs") != NULL) {
    // Different update path for Hewei rootfs
    // Uses decryption key "8e15c895KBP6ClJv" @ 0x1e0d4
}
```

### Registration Image

```
/mnt/UPAN/Auto_Box_Reg.img  - Auto-registration image
```

---

## Monitoring Update Progress

### Via USB Protocol

The adapter does not send update status via USB protocol. Monitor progress by:

1. **Re-read status files** via SendFile reverse (read not supported)
2. **Wait for reconnection** - adapter reboots after successful update
3. **Request SoftwareVersion (0xCC)** after reconnection to verify new version

### Via Web Interface

Poll `server.cgi` endpoints:
```
GET /cgi-bin/server.cgi?action=boxUpdateStatus
Response: {"err":0, "progress":75, "failReason":0}
```

---

## Configuration Options

### riddle.conf Settings

| Key | Default | Description |
|-----|---------|-------------|
| `AutoUpdate` | 0 | Enable automatic update checking |
| `IgnoreUpdateVersion` | 0 | Skip version comparison (force update) |

### Set via BoxSettings (0x19)

```json
{
  "autoUpdate": true
}
```

---

## Security Considerations

### No Signature Verification

**WARNING:** Based on binary analysis, the firmware does **not** appear to perform cryptographic signature verification on update images. This means:

1. Any file matching `*Update.img` pattern will be processed
2. Update script executes with root privileges
3. Malicious updates could be pushed if USB access is compromised

### Path Traversal

SendFile (0x99) allows writing to **any path** on the adapter filesystem:
- `/etc/` - Configuration files
- `/tmp/` - Temporary files (update images)
- `/script/` - Executable scripts

---

## Binary Analysis References

| Component | Address | Purpose |
|-----------|---------|---------|
| Update handler | `fcn.0001d2fe` | Main update detection function |
| strstr check | `0x1e084` | "Update.img" pattern match |
| OTA script call | `0x1e0a8` | `/script/update_box_ota.sh` execution (Detection Logic flow above cites 0x1e0ac for the system() call; 4-byte discrepancy unverified pending disassembly) |
| Log message | `0x1e0a0` | "Is Update Img: %s" |
| Reboot command | `0x6db00` | `sync;sleep 1;reboot` |

### Key Strings (Firmware Addresses)

| Address | String |
|---------|--------|
| `0x5c8ad` | `Is Update Img: %s` |
| `0x5c8c0` | `/script/update_box_ota.sh %s &` |
| `0x6e8a2` | `/tmp/update_progress` |
| `0x6e8b7` | `/tmp/update_error` |
| `0x6e8c9` | `/data/update/software_version` |
| `0x6dbb3` | `cat /etc/riddle.conf >> %s` |
| `0x6da34` | `Reboot box reason: %s` |

---

## Summary: Minimum Steps for Host App Update

1. **Read firmware image file** into memory
2. **Construct SendFile message** with path `/tmp/<model>_Update.img`
3. **Send via USB bulk transfer** to adapter
4. **Wait ~30 seconds** for update + reboot
5. **Reconnect and verify** via SoftwareVersion (0xCC) message

The adapter handles everything else automatically once the correctly-named file is written.

---

## Server-Side OTA API & Host-Mediated Architecture

**Source:** Protocol/server analysis (api.paplink.cn), correlated against firmware behavior

### The Adapter Has No Internet

The adapter itself **never contacts any update server** — it has no internet access in normal operation. The entire OTA flow is mediated by an external host application. The on-device mechanism documented above (SendFile 0x99 → `update_box_ota.sh`) is only the final delivery step; the check and download happen off-device.

**A15W (CPC200-CCPA) — Via Host App:**
```
LIVI / AutoKit PC app
  → Reads adapter's BoxSettings (UUID, MFD, productType, version) over USB
  → Calls api.paplink.cn/a/upgrade/checkBox with those credentials
  → Downloads .img from api.paplink.cn/a/upgrade/down
  → Pushes .img to adapter via USB SendFile (msg type 0x99) → /tmp/<model>_Update.img
  → ARMadb-driver detects file, runs /script/update_box_ota.sh
```

### Two Distinct OTA APIs

There are two separate update APIs in the HeWei ecosystem. The older web-UI endpoint is decommissioned; the app-driven API is active.

| | Old web-UI API (U2W era) | Active app API (A15W) |
|---|---|---|
| **Check URL** | `www.paplink.cn/server.php?action=checkBoxUpdateByCustomerBoxType` | `api.paplink.cn/a/upgrade/checkBox` or `check2Box` |
| **Method** | GET (browser JavaScript) | POST (app native code) |
| **Parameters** | CustomerType, BoxType, uuid, fileName, curVer | lang, code, appVer, ver, uuid, mfd, fwn, model |
| **MFD used?** | No (not in URL params) | Yes (batch gate) |
| **Download** | `www.paplink.cn/server.php?action=downfile` | `api.paplink.cn/a/upgrade/down` with JWT |
| **Status** | **server.php returns HTTP 404** (decommissioned) | **Active** |

The old `www.paplink.cn/server.php` endpoint is now dead (404). However, direct download paths under `www.paplink.cn/mnt/downloads/` still resolve.

### API Endpoints (api.paplink.cn)

**Check for updates (ARMHiCar binary):**
```
POST http://api.paplink.cn/a/upgrade/check2Box
Content-Type: application/x-www-form-urlencoded

Parameters:
  lang=0              Language
  uuid=<device UUID>  From OTP fuses (CFG0+CFG1+MAC0+MAC1)
  mfd=<YYYYMMDD>      Manufacture date
  ptype=<product>     e.g., "A15W", "U2W_AUTOKIT"
  cbrand=             Car brand (optional)
  cmodel=             Car model (optional)
  cyear=0             Car year (optional)
  ver=<current fw>    e.g., "2025.10.15.1127"
  fwn=<filename>      e.g., "A15W_Update.img"
```

**Check for updates (LIVI app):**
```
POST http://api.paplink.cn/a/upgrade/checkBox
Parameters: lang, code, appVer, ver, uuid, mfd, fwn, model
```

**Download firmware:**
```
POST http://api.paplink.cn/a/upgrade/down
Headers: Authorization: <JWT token>, OS: Android, User-Agent: LIVI
Parameters: same as check + id=<update id>
```

### Response Structure

```json
{
  "err": 0,
  "token": "<JWT with UUID + expiry>",
  "ver": "2025.10.15.1127",
  "size": "11342661",
  "path": "20251017/IuSttKFZ_A15W_Update_2025.10.15.1127.img",
  "id": "504a1fe17bab6a9af946e2e735057098",
  "notes": "...",
  "forced": 0,
  "rollback": {"ver": "2025.02.25.1521", "path": "...", "size": 12585685}
}
```

### MFD as Hardware-Batch Gate

The `mfd` (manufacture date) parameter acts as a **hardware batch filter**. Devices manufactured before a certain date are excluded from newer firmware channels, so older hardware never receives an incompatible AutoBox.img (signed U-Boot+kernel):

```
For A15W with a given UUID:
  MFD=20220101 → NO update available
  MFD=20230101 → NO update available
  MFD=20240101 → ✅ Updates available
  MFD=20250101 → ✅ Updates available
```

This ensures the server only delivers firmware compatible with the device's hardware revision and SRK key index. Devices too old for a given firmware channel simply receive no update.

### Sequential Update Model

Updates are **sequential** — the server offers one step at a time, not a direct jump to the latest version. Each check returns the next version in the chain for that device's MFD; after applying it, the device must check again to obtain the following step.

> **Note:** This section documents the protocol and server-side architecture only. The on-device delivery and execution path (SendFile 0x99 staging, `update_box_ota.sh`, progress files) is covered in the sections above.

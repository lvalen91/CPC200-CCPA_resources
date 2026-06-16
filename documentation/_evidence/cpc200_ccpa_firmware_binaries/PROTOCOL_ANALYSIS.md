# Carlinkit USB Protocol Analysis

## Overview

This document details the complete USB protocol used by Carlinkit wireless CarPlay/Android Auto adapters, derived from reverse engineering of firmware binaries.

## Protocol Header Format

```
+------------------+------------------+------------------+------------------+
|   Magic (4B)     |   Length (4B)    |   Type (4B)      | Type Check (4B)  |
+------------------+------------------+------------------+------------------+
|                              Payload (N bytes)                           |
+--------------------------------------------------------------------------+
```

- **Magic**: `0x55AA55AA` (little-endian)
- **Length**: Payload size in bytes (little-endian uint32)
- **Type**: Message type ID (little-endian uint32)
- **Type Check**: `Type XOR 0xFFFFFFFF` (validation)
- **Total header**: 16 bytes

## Message Types

### Documented Types (Pi-carplay)

| Type | Hex | Name | Direction | Description |
|------|-----|------|-----------|-------------|
| 1 | 0x01 | Open | OUT | Initialize connection with resolution/format |
| 2 | 0x02 | Plugged | IN | Phone connected notification |
| 3 | 0x03 | Phase | IN | Connection phase update |
| 4 | 0x04 | Unplugged | IN | Phone disconnected |
| 5 | 0x05 | Touch | OUT | Single touch event |
| 6 | 0x06 | VideoData | IN | H.264 video frame |
| 7 | 0x07 | AudioData | IN/OUT | PCM audio data |
| 8 | 0x08 | Command | BOTH | Control commands |
| 9 | 0x09 | LogoType | OUT | Set logo type |
| 10 | 0x0A | BluetoothAddress | IN | Box BT address |
| 12 | 0x0C | BluetoothPIN | IN | Pairing PIN |
| 13 | 0x0D | BluetoothDeviceName | IN | BT device name |
| 14 | 0x0E | WifiDeviceName | IN | WiFi SSID |
| 15 | 0x0F | DisconnectPhone | OUT | Force disconnect |
| 18 | 0x12 | BluetoothPairedList | IN | Paired device list |
| 20 | 0x14 | ManufacturerInfo | IN | OEM info |
| 21 | 0x15 | CloseDongle | OUT | Shutdown adapter |
| 23 | 0x17 | MultiTouch | OUT | Multi-touch events |
| 24 | 0x18 | HiCarLink | IN | HiCar connection URL |
| 25 | 0x19 | BoxSettings | BOTH | Configuration JSON |
| 35 | 0x23 | PeerBluetoothAddress | IN | Peer BT connecting |
| 36 | 0x24 | PeerBluetoothAddressAlt | IN | Peer BT connected |
| 37 | 0x25 | UiHidePeerInfo | IN | Hide peer info |
| 38 | 0x26 | UiBringToForeground | IN | Bring UI forward |
| 42 | 0x2A | MediaData | IN | Alternative media |
| 153 | 0x99 | SendFile | OUT | Write file to path |
| 170 | 0xAA | HeartBeat | OUT | Keep-alive (15s timeout, see below) |
| 204 | 0xCC | SoftwareVersion | IN | Firmware version |

### Undocumented Types (from firmware)

| Type | Hex | Suspected Purpose |
|------|-----|-------------------|
| 11 | 0x0B | HiCar DevList JSON (fcn.00018850) |
| 16 | 0x10 | Unknown |
| 17 | 0x11 | Unknown |
| 19 | 0x13 | Unknown |
| 22 | 0x16 | Unknown |
| 26 | 0x1A | Unknown |
| 27 | 0x1B | Encryption control |
| **30** | **0x1E** | **RemoteCxCy - Display resolution (fcn.0001af48 @ 0x1afb0)** |
| 31 | 0x1F | Unknown |
| 32 | 0x20 | Unknown |
| 33 | 0x21 | Unknown |
| 34 | 0x22 | Unknown |
| 40 | 0x28 | Unknown |
| 41 | 0x29 | Unknown |
| 43 | 0x2B | Unknown |
| 119 | 0x77 | Debug/Test |
| 136 | 0x88 | Debug mode enable |
| **161** | **0xA1** | **ExtendedMfgInfo - Extended OEM data (fcn.00018628, fcn.000186ba)** |
| 187 | 0xBB | Box status JSON |
| 205 | 0xCD | Unknown |
| 206 | 0xCE | Unknown |
| **240** | **0xF0** | **RemoteDisplay - Display parameters (fcn.0001af48 @ 0x1af96)** |
| 253 | 0xFD | Error/reset related |
| 255 | 0xFF | Error or special control |

### Adapter-to-Host Message Senders (Binary Analysis - Jan 2026)

| Function | Address | Message Types Sent |
|----------|---------|-------------------|
| fcn.00018628 | `0x18628` | 0x06, 0x09, 0x0B, 0x0D, 0xA1 |
| fcn.000186ba | `0x186ba` | 0x14 (ManufacturerInfo), 0xA1 |
| fcn.00018850 | `0x18850` | 0x06, 0x0B (HiCar DevList) |
| fcn.0001af48 | `0x1af48` | 0x01, 0x1E, 0xF0 |
| fcn.00017340 | `0x17340` | Generic sender (21 call sites)

## Message Payloads

### Open (0x01)
```
+--------+--------+--------+--------+--------+--------+--------+
| Width  | Height |  FPS   | Format | PktMax | iBoxVer| PhMode |
| (4B)   | (4B)   | (4B)   | (4B)   | (4B)   | (4B)   | (4B)   |
+--------+--------+--------+--------+--------+--------+--------+
```

### BoxSettings (0x19)
JSON payload with fields:
```json
{
  "mediaDelay": 300,
  "syncTime": 1234567890,
  "androidAutoSizeW": 1920,
  "androidAutoSizeH": 720,
  "WiFiChannel": 36,
  "wifiChannel": 36,
  "mediaSound": 1,
  "callQuality": 1,
  "autoPlay": false,
  "autoConn": true,
  "wifiName": "carlink",
  "btName": "carlink",
  "boxName": "carlink",
  "OemName": "carlink"
}
```

**Field Mapping to riddle.conf:**
| JSON Field | riddle.conf |
|------------|-------------|
| mediaDelay | MediaLatency |
| autoConn | NeedAutoConnect |
| wifiName | CustomWifiName |
| androidAutoSizeW | AndroidAutoWidth |
| androidAutoSizeH | AndroidAutoHeight |
| boxName | CustomBoxName |
| mediaSound | MediaQuality |
| WiFiChannel | WiFiChannel |

### SendFile (0x99)
```
+----------+------------+------------+----------+
| NameLen  | FileName   | ContentLen | Content  |
| (4B)     | (N+1 bytes)| (4B)       | (M bytes)|
+----------+------------+------------+----------+
```
- FileName is null-terminated ASCII
- Can write to any path on the adapter filesystem

### Command (0x08)
```
+------------+
| CommandID  |
| (4B)       |
+------------+
```

Command IDs (from CommandMapping):
- 1: startRecordAudio
- 2: stopRecordAudio
- 3: requestHostUI
- 5: siri
- 7: mic (car)
- 15: boxMic
- 16/17: nightMode on/off
- 22/23: audioTransfer on/off
- 24/25: wifi24g/wifi5g
- 100-114: Navigation buttons
- 200-205: Media buttons
- 300/301: Phone accept/reject
- 500/501: Video focus
- 1000-1012: WiFi/BT commands

### RemoteCxCy (0x1E) - Adapter to Host
Display resolution broadcast from adapter. Sent by `fcn.0001af48` at `0x1afb0`.

**Log string:** `Accessory_fd::BroadCastRemoteCxCy : %d  %d` (at `0x5c20d`)

```
+--------+--------+
| Width  | Height |
| (4B)   | (4B)   |
+--------+--------+
```

- **Width (Cx)**: Display width in pixels (little-endian uint32)
- **Height (Cy)**: Display height in pixels (little-endian uint32)
- **Total payload**: 8 bytes

### RemoteDisplay (0xF0) - Adapter to Host
Remote display parameters. Sent by `fcn.0001af48` at `0x1af96`.

```
+--------------------------------------------------------------------------+
|                    Display Parameters (28 bytes)                         |
+--------------------------------------------------------------------------+
```

- **Payload size**: 28 bytes (0x1c) - from `movs r3, 0x1c` at `0x1af9a`
- **Source**: Data structure at runtime address `0x11d00c`
- **Fields**: Unknown - requires runtime analysis or protocol capture

### ExtendedMfgInfo (0xA1) - Adapter to Host
Extended manufacturer/OEM information. Sent by `fcn.000186ba` at `0x186c8`.

```
+--------------------------------------------------------------------------+
|                    Extended OEM Data (12 bytes)                          |
+--------------------------------------------------------------------------+
```

- **Payload size**: 12 bytes (0xc) - from `movs r2, 0xc` at `0x186ca`
- **Trigger**: Sent when internal state value == 0x14 (20)
- **Related to**: ManufacturerInfo (0x14) - both sent by same caller

### HiCar DevList (0x0B) - Adapter to Host
HiCar device list. Sent by `fcn.00018850` at `0x1888e`.

```
+--------------------------------------------------------------------------+
|                    Device List Data (32 bytes)                           |
+--------------------------------------------------------------------------+
```

- **Payload size**: 32 bytes (0x20) - from `movs r2, 0x20` at `0x18890`
- **Contains**: "DevList" and "type" fields (string references at `0x7e2fc`, `0x7e8f7`)

### JSON Payload Formats (Binary String Analysis)

**Phone Link Info** (address `0x5be16`):
```json
{
  "MDLinkType": "%s",
  "MDModel": "%s",
  "MDOSVersion": "%s",
  "MDLinkVersion": "%s",
  "btMacAddr": "%s",
  "btName": "%s",
  "cpuTemp": %d
}
```
- **MD**: Mobile Device prefix
- **cpuTemp**: Adapter CPU temperature (integer)

**Box Info** (address `0x5c2ce`):
```json
{
  "uuid": "%s",
  "MFD": "%s",
  "boxType": "%s",
  "OemName": "%s",
  "productType": "%s",
  "HiCar": %d,
  "hwVersion": "%s",
  "WiFiChannel": %d,
  "CusCode": "%s",
  "DevList": %s,
  "ChannelList": "%s"
}
```
- **MFD**: Manufacturer Date
- **HiCar**: HiCar capability flag (integer)
- **DevList**: Nested JSON array (not quoted)

## Encryption

The firmware uses **AES-128-CFB** encryption for certain message types. From `FUN_00018244`:

- Encryption applies to payload data
- Key derived from counter + XOR table
- IV is 16 bytes initialized to zeros
- Not all message types are encrypted

Types that appear to skip encryption:
- 0x01-0x07 (basic control)
- 0x1B, 0x23, 0x25, 0x26

## Key Functions (from binary analysis)

| Function | Address | Purpose |
|----------|---------|---------|
| FUN_00018244 | 0x18244 | Message encryption/validation handler |
| FUN_00018e2c | 0x18e2c | Main message dispatcher |
| FUN_00066190 | 0x66190 | riddle.conf config writer |
| FUN_00062e1c | 0x62e1c | Message buffer init |
| FUN_00062f34 | 0x62f34 | Message buffer populate |
| FUN_00062ec6 | 0x62ec6 | Message buffer resize |
| FUN_00017340 | 0x17340 | Message sender |
| FUN_00018088 | 0x18088 | Message pre-processor |
| FUN_00065178 | 0x65178 | JSON field extractor |

## Message Dispatcher Flow

```
USB Bulk Transfer → FUN_00018088 (validate header)
                  → FUN_00018244 (decrypt if needed)
                  → FUN_00018e2c (dispatch by type)
                      ├── Type 0x01: Initialize connection
                      ├── Type 0x07: Audio routing (switch on subtype)
                      ├── Type 0x08: Command dispatcher
                      ├── Type 0x19: BoxSettings JSON parser
                      ├── Type 0x99: SendFile file writer
                      └── ... other handlers
```

## System Calls in Firmware

The firmware contains several `system()` calls that execute shell commands:

| Location | Trigger | Purpose |
|----------|---------|---------|
| 0x1c0e4 | param_2 == 0x66 | Unknown command (possibly factory reset) |
| 0x1c0f4 | param_2 == 0 | State transition command |
| 0x1c108 | param_2 == 1 | Format string command with USB params |

Also found: `posix_spawn()` at 0x37338 for launching subprocesses.

## Injection Points

### 1. SendFile (0x99)
Can write arbitrary files to adapter filesystem:
```typescript
new SendFile(Buffer.from('#!/bin/sh\nriddleBoxCfg FastConnect 1'), '/tmp/config.sh')
```

**Potential execution vectors:**
- `/tmp/` directory for temporary scripts
- `/data/` directory for persistent storage
- Overwriting existing shell scripts called by firmware

### 2. BoxSettings (0x19)
The BoxSettings handler parses JSON and writes known fields to riddle.conf via FUN_00066190. Field mapping is hardcoded - unknown fields are ignored. However, timing attacks on the JSON parser could potentially be explored.

### 3. Command (0x08) Extensions
The Command message dispatcher handles IDs up to 1012. Undocumented ranges:
- 0-100: System commands (partially documented)
- 100-114: Navigation
- 200-205: Media
- 300-301: Phone
- 500-501: Video focus
- 1000-1012: WiFi/BT commands
- **1013+**: Untested - may trigger unexpected behavior

### 4. Undocumented Message Types
The following message types are handled by firmware but not documented in Pi-carplay:

| Type | Hex | Analysis Notes |
|------|-----|----------------|
| 11 | 0x0B | Appears in encryption bypass list - may be internal |
| 16 | 0x10 | Unknown |
| 17 | 0x11 | Unknown |
| 19 | 0x13 | Unknown |
| 22 | 0x16 | Unknown |
| 26 | 0x1A | Unknown |
| 27 | 0x1B | Encryption control - skips encryption in FUN_00018244 |
| 30-34 | 0x1E-0x22 | Unknown batch - possibly extended status |
| 40-41 | 0x28-0x29 | Unknown pair |
| 43 | 0x2B | Unknown |
| 119 | 0x77 | Debug/Test - in same group as 0x88 |
| 136 | 0x88 | Debug/Test - may enable diagnostic mode |
| 187 | 0xBB | Possibly box status response |
| 205-206 | 0xCD-0xCE | Near SoftwareVersion (0xCC) - extended version info? |
| 253 | 0xFD | Near 0xFF - possibly error/reset related |
| 255 | 0xFF | Error or special control message |

### 5. D-Bus Interface Injection
The firmware uses D-Bus (`org.riddle`) for inter-process communication. If SSH/serial access is available:
```bash
dbus-send --system --dest=org.riddle /RiddleBluetoothService \
  org.riddle.BluetoothControl.AutoConnect
```

## Internal Commands (from strings)

```
CMD_CARPLAY_MODE_CHANGE
CMD_SET_BLUETOOTH_PIN_CODE
CMD_BOX_WIFI_NAME
CMD_MANUAL_DISCONNECT_PHONE
CMD_CARPLAY_AirPlayModeChanges
CMD_BLUETOOTH_ONLINE_LIST
CMD_CAR_MANUFACTURER_INFO
CMD_STOP_PHONE_CONNECTION
CMD_CAMERA_FRAME
CMD_MULTI_TOUCH
CMD_CONNECTION_URL
CMD_BOX_INFO
CMD_PAY_RESULT
CMD_ACK
CMD_DEBUG_TEST
CMD_UPDATE
CMD_APP_SET_BOX_CONFIG
CMD_ENABLE_CRYPT
```

## Additional Protocol Features

### HUD Commands (D-Bus)
Internal D-Bus interface at `org.riddle`:
- HUDComand_A_HeartBeat
- HUDComand_A_ResetUSB
- HUDComand_A_UploadFile
- HUDComand_B_BoxSoftwareVersion
- HUDComand_D_BluetoothName
- kRiddleHUDComand_A_Reboot
- kRiddleHUDComand_CommissionSetting

### Audio Signals
- kRiddleAudioSignal_MEDIA_START/STOP
- kRiddleAudioSignal_ALERT_START/STOP
- kRiddleAudioSignal_PHONECALL_Incoming

## HeartBeat Timeout Mechanism (Firmware Analysis)

The firmware implements a connection supervision watchdog that monitors heartbeat messages.

### Timeout Constants (from binary at 0x21112)

| Timeout | Value | Hex | Effect |
|---------|-------|-----|--------|
| Host No Response | 15,000 ms | `0x3a98` | Connection reset |
| Send to Host | 4,500 ms | `0x1194` | Connection reset |

### Expected Heartbeat Interval

**The firmware does not mandate a specific send interval.** It enforces a maximum gap of **15 seconds** between heartbeat messages. If no heartbeat is received within this window, the firmware logs:

```
Host No Response, we will reset connection!!!
```

And resets the USB connection.

**Recommended interval:** 2000ms (2 seconds) - provides 7+ heartbeats within the timeout window.

### Configuration

| Key | Default | Location |
|-----|---------|----------|
| `SendHeartBeat` | 1 (enabled) | `/etc/riddle.conf` |
| `HNPInterval` | - | Config table 0x713b0 |

Setting `SendHeartBeat=0` disables outbound heartbeat emission but the timeout monitoring continues - the host must still send heartbeats to prevent connection reset.

## Binary Files Analyzed

| File | Size (unpacked) | Purpose |
|------|-----------------|---------|
| ARMadb-driver | 469KB | Main USB protocol handler |
| ARMiPhoneIAP2 | 494KB | iPhone IAP2 protocol |
| ARMHiCar | 132KB | Huawei HiCar handler |
| ARMandroid_Mirror | 106KB | Android mirroring |
| riddleBoxCfg | 45KB | Configuration CLI |
| server.cgi | 74KB | Web UI backend |

## Tools Used

- ludwig-v modified UPX (custom Carlinkit unpacker)
- Ghidra 12.0 (decompilation)
- radare2 (disassembly)
- strings (string extraction)

## References

- https://github.com/ludwig-v/wireless-carplay-dongle-reverse-engineering
- Pi-carplay source code
- Direct firmware analysis

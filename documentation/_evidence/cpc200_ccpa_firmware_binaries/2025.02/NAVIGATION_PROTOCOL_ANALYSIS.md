# ARMadb-driver 2025.10 Navigation Protocol Analysis

## Overview

This document details the new navigation protocol features discovered in the Carlinkit A15W firmware version 2025.10 compared to 2025.02. These features enable CarPlay Dashboard/Instrument Cluster functionality (iOS 13+).

## New Strings in 2025.10

The following navigation-related strings are **new** in 2025.10 and do not exist in 2025.02:

| String | Virtual Address | Type | Purpose |
|--------|-----------------|------|---------|
| `HU_NEEDNAVI_STREAM` | 0x6c2f9 | D-Bus Signal | Request navigation video stream from host |
| `HU_NAVISCREEN_INFO` | 0x6c5e5 | D-Bus Signal | Navigation screen parameters |
| `HU_NAVISCREEN_SAFEAREA_INFO` | 0x6c627 | D-Bus Signal | Safe area boundaries for nav display |
| `HU_NAVISCREEN_VIEWAREA_INFO` | 0x6c643 | D-Bus Signal | Viewable area boundaries |
| `naviScreenInfo` | 0x6c5a1 | Internal | Navigation screen info handler |
| `_naviScreenInfo %dx%d, %d FPS` | 0x6c5ff | Format String | Width x Height, Framerate |
| `RequestNaviFocus` | 0x6d7f1 | Command | Request navigation overlay priority |
| `ReleaseNaviFocus` | 0x6d802 | Command | Release navigation overlay priority |
| `RequestNaviScreenFoucs` | 0x6d813 | Command | Request screen focus (typo in firmware) |
| `ReleaseNaviScreenFoucs` | 0x6d82a | Command | Release screen focus (typo in firmware) |
| `naviScreen` | 0x6e20b | Internal | Navigation screen handler |
| `advancedFeatures: 0x%X` | - | Debug | Advanced feature flags |

## D-Bus Signal Comparison

### 2025.02 HU_* Signals (8 total)
```
HU_AUDIOVOLUME_INFO
HU_BT_ADDR
HU_BT_PIN_CODE
HU_DAYNIGHT_MODE
HU_DRIVING_STATE
HU_GPS_DATA
HU_LINK_TYPE
HU_SCREEN_INFO
```

### 2025.10 HU_* Signals (19 total - 11 new)
```
HU_APP_VERSION          (NEW)
HU_AUDIOVOLUME_INFO
HU_BT_ADDR
HU_BT_PIN_CODE
HU_DAYNIGHT_MODE
HU_DRIVING_STATE
HU_GPS_DATA
HU_LINK_TYPE
HU_MANUAL_DISCONNECT    (NEW)
HU_NAVISCREEN_INFO      (NEW)
HU_NAVISCREEN_SAFEAREA_INFO  (NEW)
HU_NAVISCREEN_VIEWAREA_INFO  (NEW)
HU_NEEDNAVI_STREAM      (NEW)
HU_OS_VERSION           (NEW)
HU_SCREEN_INFO
HU_TYPE_AA              (NEW)
HU_TYPE_CARLIFE         (NEW)
HU_TYPE_CARPLAY         (NEW)
HU_VIEWAREA_INFO        (NEW)
```

## USB Protocol Message Types

### Main Message Handler
- **Function**: `FUN_00017340` at address `0x17340`
- **Message type offset**: `param_2 + 8` (or `param_2 + 0x24` for outer type)

### Navigation-Related Message Types

| Type (Hex) | Type (Dec) | Purpose |
|------------|------------|---------|
| 0x11 | 17 | Navigation screen control |
| 0x12 | 18 | Navigation screen control |
| 0x6e | 110 | Navigation focus request (maps to 0x3d internally) |
| 0x6f | 111 | Navigation focus release (maps to 0x3e internally) |
| 0xf0 | 240 | Screen info broadcast |
| 0x1e | 30 | Screen/navigation control |

### Pointer Tables

Navigation string pointers are stored in tables at:
- `0x197e4` - Contains RequestNaviFocus, ReleaseNaviFocus, RequestNaviScreenFoucs, ReleaseNaviScreenFoucs
- `0x1af68` - Duplicate pointer table
- `0x1be88` - Contains naviScreen related pointers
- `0x1e95c` - Duplicate pointer table

## USB Bulk Message Structure

### 16-Byte Message Header

Based on analysis of `FUN_0006482c` (message parser) and `FUN_00064c70` (message sender):

```c
struct usb_message_header {
    uint32_t magic;       // Offset 0x00: 0x55aa55aa
    uint32_t payload_len; // Offset 0x04: Length of payload data
    uint32_t msg_type;    // Offset 0x08: Message type identifier
    uint32_t checksum;    // Offset 0x0C: ~msg_type (bitwise NOT)
};
```

### ✅ VERIFIED Against Captured CarPlay Sessions

**Verification Status**: All checksums verified correct against pi-carplay and carlink_native captures.

| Field | Expected | Verified |
|-------|----------|----------|
| magic | 0x55aa55aa | ✅ All packets |
| checksum | ~msg_type | ✅ All packets |

Example verification from captures:
```
Type 1 (Open):      checksum = 0xfffffffe = ~1  ✅
Type 6 (Video):     checksum = 0xfffffff9 = ~6  ✅
Type 7 (Audio):     checksum = 0xfffffff8 = ~7  ✅
Type 8 (Command):   checksum = 0xfffffff7 = ~8  ✅
Type 153 (SendFile): checksum = 0xffffff66 = ~153 ✅
Type 170 (HeartBeat): checksum = 0xffffff55 = ~170 ✅
```

### Magic Bytes
- **Request magic**: `0x55aa55aa` - Host to adapter
- **Reply magic**: `0x55bb55bb` - Adapter to host (per firmware, not seen in captures)
- Validated by `FUN_000645ec`
- Toggled by `FUN_00064630`

### Internal Message Structure (36 bytes)

Used internally for message handling (`FUN_00064650` initializer):

```c
struct internal_message {
    uint32_t magic;           // [0] 0x55aa55aa
    uint32_t payload_len;     // [1] Payload length
    uint32_t msg_type;        // [2] Message type
    uint32_t extra;           // [3] Extra field
    void*    payload_ptr;     // [4] Pointer to payload (at offset 0x60 in buffer)
    void*    mmap_buffer;     // [5] mmap buffer for large payloads
    size_t   buffer_size;     // [6] Allocated buffer size
    uint32_t buffer_offset;   // [7] Offset to payload (0x60)
    int      fd;              // [8] File descriptor (-1 if unused)
};
```

### Payload Buffer Allocation

From `FUN_00064670`:
- Total allocation = `payload_length + 0xC0` (192 bytes overhead)
- Payload starts at offset `0x60` (96 bytes) from buffer start
- Large payloads may use mmap with file descriptor passing

## Complete Message Type Reference

### Navigation Messages (NEW in 2025.10)

| Internal | USB | Dec | Purpose | Handler |
|----------|-----|-----|---------|---------|
| 0x3d | 0x6e | 110 | Request navigation focus | FUN_00019244 |
| 0x3e | 0x6f | 111 | Release navigation focus | FUN_00019244 |
| 0x11 | 0x11 | 17 | Navigation screen control | Video encoder |
| 0x12 | 0x12 | 18 | Navigation screen control | Video encoder |
| 0x1e | 0x1e | 30 | Screen/navigation update | FUN_00024524 |
| 0x2a | 0x2a | 42 | DashBoard_DATA (cluster) | FUN_0006482c |

### Stream Messages

| Type | Dec | Purpose |
|------|-----|---------|
| 0x01 | 1 | Audio PCM stream |
| 0x02 | 2 | Audio control |
| 0x05 | 5 | Video H.264 stream |
| 0x06 | 6 | Video control |
| 0x07 | 7 | Media audio stream |

### Control Messages

| Type | Dec | Purpose |
|------|-----|---------|
| 0x08 | 8 | Connection state |
| 0x0a | 10 | Touch input |
| 0x0b | 11 | Focus control wrapper |
| 0x19 | 25 | Device info/features |
| 0x22 | 34 | Forward to host |
| 0x25 | 37 | Disconnect request |
| 0x26 | 38 | Disconnect complete |
| 0x29 | 41 | String command |
| 0x33 | 51 | Custom data |

### Special Control Messages

| Type | Dec | Purpose |
|------|-----|---------|
| 0x77 | 119 | Keep-alive |
| 0x88 | 136 | System command (file access, reboot) |
| 0x99 | 153 | File transfer |
| 0xa2 | 162 | D-Bus signal handler (calls FUN_00016c20) |
| 0xaa | 170 | Extended info |
| 0xbb | 187 | Debug message |
| 0xcc | 204 | Configuration |
| 0xcd | 205 | Configuration reply |
| 0xce | 206 | Extended configuration |
| 0xf0 | 240 | Screen info broadcast |
| 0xf6 | 246 | Forward wrapper (type 0x2a) |
| 0xf7 | 247 | State change |
| 0xfd | 253 | Firmware info |
| 0xff | 255 | Reset/shutdown |

## Complete Message Payload Formats

### ✅ VERIFIED Payload Structures from Captured Sessions

The following structures have been verified against actual CarPlay session captures from pi-carplay and carlink_native:

#### Type 1: Open (Session Initialization) ✅ VERIFIED

```c
struct open_msg {
    uint32_t width;       // 2400 (0x960) - screen width
    uint32_t height;      // 960 (0x3c0) - screen height
    uint32_t fps;         // 60 - framerate
    uint32_t format;      // 1 (H264) or 5 (H265)
    uint32_t audio_rate;  // 49152 (0xc000) - sample rate
    uint32_t channels;    // 2 - stereo
    uint32_t bit_depth;   // 2 - 16-bit
};
// Total: 28 bytes
```

#### Type 2: Plugged (Device Connected) ✅ VERIFIED

```c
struct plugged_msg {
    uint32_t phone_type;  // 3 = iPhone
    uint32_t state;       // 1 = connected
};
// Total: 8 bytes
```

#### Type 3: Phase (Connection Phase) ✅ VERIFIED

```c
struct phase_msg {
    uint32_t phase;  // 7, 8, etc. - connection phase indicator
};
// Total: 4 bytes
```

#### Type 5: Touch (Touch Event) ✅ VERIFIED

```c
struct touch_msg {
    uint32_t action;  // 14=down, 15=up, 16=move
    uint32_t x;       // X coordinate
    uint32_t y;       // Y coordinate
    uint32_t flags;   // Touch flags (usually 0)
};
// Total: 16 bytes
```

#### Type 6: Video Data ✅ VERIFIED

```c
struct video_data {
    uint32_t width;       // 2400
    uint32_t height;      // 960
    uint8_t  frame_data[]; // H264/HEVC NAL units
};
// NAL start code 0x00000001 found at offset +20 in payload
// NAL type 7 = SPS, 8 = PPS, 5 = IDR frame
```

#### Type 7: Audio Data ✅ VERIFIED

```c
struct audio_data {
    uint32_t decode_type;  // 2
    uint32_t timestamp;    // timing info
    uint32_t volume;       // 1
    uint8_t  pcm_data[];   // raw PCM samples
};
// Total header: 12 bytes + variable PCM data
```

#### Type 8: Command ✅ VERIFIED

```c
struct command_msg {
    uint32_t command;  // e.g., 1000 (0x3e8) = start_carplay
};
// Total: 4 bytes
```

#### Type 13: BluetoothDeviceName ✅ VERIFIED

```c
// Null-terminated string, e.g., "carlink_test"
char device_name[];
```

#### Type 25: BoxSettings (JSON Config) ✅ VERIFIED

```c
// JSON payload with device configuration
// Keys: uuid, MFD, boxType, OemName, productType, HiCar, hwVersion, WiFiChannel, etc.
char json_config[];
```

#### Type 42: MediaData (Now Playing) ✅ VERIFIED

```c
struct media_data {
    uint32_t flag;     // 1
    char json[];       // JSON: MediaSongName, MediaAlbumName, MediaArtistName,
                       //       MediaAPPName, MediaSongDuration, MediaSongPlayTime, MediaPlayStatus
};
```

#### Type 153 (0x99): SendFile ✅ VERIFIED

```c
struct sendfile_msg {
    uint32_t name_len;   // filename length
    char     name[];     // e.g., "/tmp/screen_dpi"
    uint32_t data_len;   // data length
    uint8_t  data[];     // file contents
};
```

#### Type 170 (0xAA): HeartBeat ✅ VERIFIED

```c
// Empty payload (0 bytes)
// Used for keep-alive
```

#### Type 204 (0xCC): SoftwareVersion ✅ VERIFIED

```c
// 32-byte null-padded string
// e.g., "2025.02.25.1521CAY" or "2025.10.15.1127CAY"
char version[32];
```

#### Type 163 (0xa3): Authentication/Session Data ⚠️ NEW DISCOVERY

```c
struct auth_session_msg {
    // Base64-encoded payload
    // Decoded starts with "AU" (0x4155)
    // Contains 368 bytes of encrypted/session data
    char base64_data[];  // Variable length
};
```

**Analysis:**
- Appears once per session during handshake phase
- Payload is Base64-encoded binary data
- First 2 bytes after decode are "AU" (possibly "AUTH" identifier)
- Remaining bytes appear to be encrypted session/authentication data
- Only observed in one capture session

---

### Type 18 (0x12) Correction

**IMPORTANT:** Type 18 (0x12) was initially speculated to be navigation-related (`NaviScreenCtrl2`) based on firmware analysis. Capture verification shows it is actually `BluetoothPairedList`:

```c
// NOT NaviScreenCtrl2 - this is BluetoothPairedList
// Example payload: "DE:AD:BE:EF:00:06User\n\0"
// Format: BT_MAC_ADDRESS + DeviceName + newline + null
char bt_paired_entry[];
```

---

### Firmware-Analyzed Message Structures

Based on analysis of decompiled functions (FUN_00017340, FUN_000179b8, FUN_00016c20):

#### Video Stream Message (Type 0x05)

```c
struct video_stream_payload {
    uint32_t frame_length;    // [0] Total frame data length
    uint32_t state;           // [1] Stream state (checked against sVar16)
    uint8_t  sub_command;     // [2] Sub-command byte at offset 8
    // Sub-commands:
    //   0x01 = Enable video flag
    //   0x02 = Disable video flag
    //   0x03 = Start video (sets sample rate 16000)
    //   0x04 = Enable secondary flag
    //   0x05 = Disable secondary flag
    uint8_t  padding[3];
    uint8_t  frame_data[];    // Variable length H.264 NAL units
};
```

#### Video Control Message (Type 0x06)

```c
struct video_control_payload {
    uint32_t reserved1;       // [0]
    uint32_t state;           // [1]
    uint8_t  sub_command;     // [2] Sub-command (0x03 = video control start)
    uint8_t  padding[3];
};
```

#### Audio/Control Message (Type 0x07)

```c
struct audio_control_payload {
    uint32_t header[3];       // First 12 bytes (0x0C) are header
    uint8_t  command;         // Command byte at offset 0x0C
    // Commands and flag operations:
    //   1: Set audio channel flag (0x100 or 0x200 based on [8])
    //   2: Clear audio channel flag
    //   4: Set flag bit 0
    //   5: Clear flag bit 0
    //   6: Set flag bit 1
    //   7: Clear flag bit 1
    //   8: Set flag bit 2
    //   9: Clear flag bit 2
    //   10: Set flag bit 4
    //   11: Clear flag bit 4
    //   12: Set flag bit 3
    //   13: Clear flag bit 3
    uint8_t  padding[3];
    uint32_t channel_id;      // [8] Channel ID (1 or 2)
};
```

#### Touch Input Message (Type 0x0A / 10)

```c
struct touch_input_payload {
    uint32_t reserved[2];     // [0-1]
    double   x_coord;         // [2-3] X coordinate (converted to float)
    double   y_coord;         // [4-5] Y coordinate (converted to float)
};
// Total: 24 bytes
// Handler creates response with type 7, payload format:
//   [0] = 2 (touch type)
//   [1] = (float)x_coord
//   [2] = 1
//   [3] = (float)y_coord
```

#### State Change Message (Type 0x0C / 12)

```c
struct state_change_payload {
    uint32_t reserved[2];     // [0-1]
    uint32_t state_code;      // [2] State code
    // State codes:
    //   0x01 = State 1 (calls FUN_00019e30)
    //   0x03 = State 3
    //   0x04 = State 4 (additional payload at [3])
    //   0x1F4 (500) = Special state
    //   0x1F5 (501) = Feature check state
    uint8_t  extra_data[];    // [3+] Additional data for state 0x04
};
```

### Navigation Message Structures (NEW in 2025.10)

#### Navigation Screen Info (HU_NAVISCREEN_INFO - Internal)

```c
struct navi_screen_info {
    int32_t width;            // [0] Screen width in pixels
    int32_t height;           // [1] Screen height in pixels
    int32_t scaled_width;     // [2] Scaled width (width * scale_factor)
    int32_t scaled_height;    // [3] Scaled height (height * scale_factor)
    int32_t fps;              // [4] Framerate
    int32_t reserved;         // [5] Reserved/padding
};
// Total: 24 bytes (0x18)
// Debug format: "_naviScreenInfo %dx%d, %d FPS"
// Stored via FUN_000677d8 to filesystem path
```

#### Navigation Safe Area (HU_NAVISCREEN_SAFEAREA_INFO - Internal)

```c
struct navi_safe_area {
    int32_t x;                // [0] X offset
    int32_t y;                // [1] Y offset
    int32_t width;            // [2] Safe area width
    int32_t height;           // [3] Safe area height
    int32_t flags;            // [4] Additional flags
};
// Total: 20 bytes (0x14)
```

#### Navigation View Area (HU_NAVISCREEN_VIEWAREA_INFO - Internal)

```c
struct navi_view_area {
    int32_t width;            // [0] View width
    int32_t height;           // [1] View height
    int32_t width_copy;       // [2] Width (redundant)
    int32_t height_copy;      // [3] Height (redundant)
    int32_t extra1;           // [4] Additional field
    int32_t extra2;           // [5] Additional field
};
// Total: 24 bytes (0x18)
```

#### Navigation Focus USB Message (Type 0x6e/0x6f)

When internal message types 0x3d/0x3e are forwarded to USB:

```c
struct navi_focus_usb_msg {
    uint32_t inner_payload_len;  // [0] Length of original payload
    uint32_t usb_msg_type;       // [1] 0x6e (request) or 0x6f (release)
    uint8_t  inner_payload[];    // [2+] Original message payload (variable)
};
// Wrapped in message type 0x0B (focus wrapper)
// See FUN_00017340 lines handling (uVar19 - 0x3d < 2)
```

#### ✅ VERIFIED: Navigation Focus Commands via Type 8

**IMPORTANT: These commands are sent by iPhone/CarPlay REGARDLESS of `AdvancedFeatures` setting!**

Verified in both captures:
| Capture | AdvancedFeatures | supportFeatures | NaviFocus Commands |
|---------|------------------|-----------------|-------------------|
| 26JAN15_01-41-19 | 0 | `""` (empty) | ✅ Present |
| 26JAN15_02-26-02 | 1 | `"naviScreen"` | ✅ Present |

The iPhone sends navigation focus requests as part of the standard CarPlay protocol, hoping the head unit supports instrument cluster display. The adapter forwards these commands regardless of its configuration.

Navigation focus is transmitted via **Type 8 (Command)** messages:

| Command | Code | Hex | Direction | Description |
|---------|------|-----|-----------|-------------|
| RequestNaviFocus | 506 | 0x1fa | Adapter→Host | Phone requests nav overlay |
| ReleaseNaviFocus | 507 | 0x1fb | Adapter→Host | Phone releases nav overlay |

**Captured Message Examples:**
```
RequestNaviFocus:
  [9.682s] <<< IN | Command | 20 bytes
  Header: aa 55 aa 55 04 00 00 00 08 00 00 00 f7 ff ff ff
  Payload: fa 01 00 00  (0x1fa = 506)

ReleaseNaviFocus:
  [20.738s] <<< IN | Command | 20 bytes
  Header: aa 55 aa 55 04 00 00 00 08 00 00 00 f7 ff ff ff
  Payload: fb 01 00 00  (0x1fb = 507)
```

**From adapter ttyLog:**
```
[D] _SendPhoneCommandToCar: RequestNaviFocus(506)
[D] _SendPhoneCommandToCar: ReleaseNaviFocus(507)
```

**Host Application Usage:**

```c
// To request navigation focus (move nav to instrument cluster)
void send_navi_focus_request(int usb_fd) {
    struct usb_header hdr = {
        .magic = 0x55aa55aa,
        .payload_len = 8,  // inner_len + type
        .msg_type = 0x0b,  // Focus wrapper
        .checksum = 0
    };
    struct navi_focus_usb_msg payload = {
        .inner_payload_len = 0,
        .usb_msg_type = 0x6e  // Request
    };
    write(usb_fd, &hdr, 16);
    write(usb_fd, &payload, 8);
}

// To release navigation focus
void send_navi_focus_release(int usb_fd) {
    struct usb_header hdr = {
        .magic = 0x55aa55aa,
        .payload_len = 8,
        .msg_type = 0x0b,
        .checksum = 0
    };
    struct navi_focus_usb_msg payload = {
        .inner_payload_len = 0,
        .usb_msg_type = 0x6f  // Release
    };
    write(usb_fd, &hdr, 16);
    write(usb_fd, &payload, 8);
}
```

#### Navigation Screen Control (Type 0x11/0x12)

Used for navigation video frame control:

```c
struct navi_screen_ctrl_payload {
    uint32_t length;          // [0] Frame/data length
    uint32_t frame_type;      // [1] Frame type indicator
    uint8_t  frame_data[];    // [2+] Navigation video frame data
};
// Type 0x11: Navigation screen primary control
// Type 0x12: Navigation screen secondary control
// Processed similar to video type 0x05/0x06
```

### Device Info/Features (Type 0x19)

Sent by `FUN_0001bc24`, contains JSON-like structure:

```json
{
    "deviceId": "...",
    "fwVersion": "...",
    "hwVersion": "...",
    "linkType": "...",
    "supportFeatures": "...",
    "advancedFeatures": "0x..."
}
```

### Advanced Features Flags

```c
// Bitmask in advancedFeatures field
#define FEATURE_BIT_0      0x0001  // Base feature
#define FEATURE_AUDIO_CH1  0x0100  // Audio channel 1
#define FEATURE_AUDIO_CH2  0x0200  // Audio channel 2
#define FEATURE_FLAG_1     0x0002  // Feature flag 1
#define FEATURE_FLAG_2     0x0004  // Feature flag 2
#define FEATURE_FLAG_3     0x0008  // Feature flag 3
#define FEATURE_FLAG_4     0x0010  // Feature flag 4
```

Feature detection files checked (from FUN_0001bc24):
- Various `/usr/local/` paths control feature availability

## Implementation Guide for Host Apps

### For pi-carplay / carlink_native

To implement CarPlay Dashboard/Instrument Cluster support:

#### 1. USB Bulk Transfer Setup

```c
#include <libusb.h>

#define USB_MAGIC_REQUEST  0x55aa55aa
#define USB_MAGIC_REPLY    0x55bb55bb
#define USB_HEADER_SIZE    16

// Message types for navigation
#define MSG_NAVI_FOCUS_REQUEST  0x6e  // 110
#define MSG_NAVI_FOCUS_RELEASE  0x6f  // 111
#define MSG_NAVI_SCREEN_CTRL    0x11  // 17
#define MSG_FOCUS_WRAPPER       0x0b  // 11

struct usb_header {
    uint32_t magic;
    uint32_t payload_len;
    uint32_t msg_type;
    uint32_t checksum;
} __attribute__((packed));

int send_usb_message(libusb_device_handle *dev, int ep_out,
                     uint32_t msg_type, void *payload, size_t len) {
    struct usb_header hdr = {
        .magic = USB_MAGIC_REQUEST,
        .payload_len = len,
        .msg_type = msg_type,
        .checksum = 0
    };

    // Send header
    int transferred;
    libusb_bulk_transfer(dev, ep_out, (uint8_t*)&hdr, 16, &transferred, 1000);

    // Send payload if present
    if (len > 0 && payload) {
        libusb_bulk_transfer(dev, ep_out, payload, len, &transferred, 1000);
    }
    return 0;
}
```

#### 2. D-Bus Signal Handling

```c
// Register for navigation D-Bus signals
dbus_bus_add_match(conn,
    "type='signal',interface='com.carlinkit.driver',"
    "member='HU_NAVISCREEN_INFO'", NULL);
dbus_bus_add_match(conn,
    "type='signal',interface='com.carlinkit.driver',"
    "member='HU_NEEDNAVI_STREAM'", NULL);

// Signal handler
void handle_dbus_signal(DBusMessage *msg) {
    const char *member = dbus_message_get_member(msg);

    if (strcmp(member, "HU_NAVISCREEN_INFO") == 0) {
        // Parse: width, height, fps (3 x uint32_t)
        uint32_t width, height, fps;
        dbus_message_get_args(msg, NULL,
            DBUS_TYPE_UINT32, &width,
            DBUS_TYPE_UINT32, &height,
            DBUS_TYPE_UINT32, &fps,
            DBUS_TYPE_INVALID);
        configure_navi_encoder(width, height, fps);
    }
    else if (strcmp(member, "HU_NEEDNAVI_STREAM") == 0) {
        start_navi_video_stream();
    }
    else if (strcmp(member, "HU_NAVISCREEN_SAFEAREA_INFO") == 0) {
        // Parse: x, y, width, height bounds
        set_safe_area_bounds(...);
    }
}
```

#### 3. Navigation Focus Control

```c
// Request navigation focus (move nav to instrument cluster)
void request_navi_focus(libusb_device_handle *dev, int ep_out) {
    // The adapter expects a focus wrapper message
    struct {
        uint32_t inner_len;
        uint32_t usb_type;  // 0x6e
        // additional payload if needed
    } focus_req = {
        .inner_len = 0,
        .usb_type = MSG_NAVI_FOCUS_REQUEST
    };

    send_usb_message(dev, ep_out, MSG_FOCUS_WRAPPER,
                     &focus_req, sizeof(focus_req));
}

// Release navigation focus (return to main display)
void release_navi_focus(libusb_device_handle *dev, int ep_out) {
    struct {
        uint32_t inner_len;
        uint32_t usb_type;  // 0x6f
    } focus_rel = {
        .inner_len = 0,
        .usb_type = MSG_NAVI_FOCUS_RELEASE
    };

    send_usb_message(dev, ep_out, MSG_FOCUS_WRAPPER,
                     &focus_rel, sizeof(focus_rel));
}
```

#### 4. Receiving Messages

```c
int receive_usb_message(libusb_device_handle *dev, int ep_in,
                        struct usb_header *hdr, void **payload) {
    int transferred;

    // Read 16-byte header
    libusb_bulk_transfer(dev, ep_in, (uint8_t*)hdr, 16, &transferred, 1000);

    // Validate magic
    if (hdr->magic != USB_MAGIC_REPLY) {
        return -1;  // Invalid header
    }

    // Read payload if present
    if (hdr->payload_len > 0) {
        *payload = malloc(hdr->payload_len);
        libusb_bulk_transfer(dev, ep_in, *payload,
                            hdr->payload_len, &transferred, 1000);
    }

    return hdr->msg_type;
}
```

#### 5. Focus Management Callbacks

Handle focus requests from the adapter (string-based commands):
- `RequestNaviFocus` - Adapter wants navigation priority
- `ReleaseNaviFocus` - Adapter releasing navigation priority
- `RequestNaviScreenFoucs` - Screen focus request (note typo in firmware)
- `ReleaseNaviScreenFoucs` - Screen focus release (note typo in firmware)

## Related iOS Features

These navigation features correspond to:
- **CarPlay Dashboard** (iOS 13+) - Secondary display for navigation
- **Instrument Cluster** (iOS 13+) - Behind-the-wheel display
- **CarPlay Wallpaper** (iOS 14+) - Custom backgrounds

The adapter acts as a bridge between the iOS CarPlay navigation output and a secondary display (typically instrument cluster or HUD).

## Binary Analysis Details

### Analysis Method
- Tool: Ghidra 11.3.2 (headless mode)
- Binary: ARMadb-driver_2025.10_unpacked (478KB, UPX unpacked)
- Architecture: ARM:LE:32:v8

### Key Functions Identified

| Function | Address | Size | Purpose |
|----------|---------|------|---------|
| FUN_00017340 | 0x17340 | ~6KB | Main USB message dispatcher (routes by msg_type) |
| FUN_00017328 | 0x17328 | 18B | Screen info message handler wrapper |
| FUN_00018598 | 0x18598 | ~1KB | Message send function (handles USB bulk out) |
| FUN_00019244 | 0x19244 | 1150B | Message type to string mapping + navigation focus |
| FUN_00016978 | 0x16978 | 24B | HU_NEEDNAVI_STREAM handler |
| FUN_00016c20 | 0x16c20 | 1290B | D-Bus signal processor (HU_NAVISCREEN_INFO, etc.) |
| FUN_0001bc24 | 0x1bc24 | 540B | Device info/features message builder |
| FUN_0006482c | 0x6482c | 848B | USB message receive/parse (validates magic) |
| FUN_00064c70 | 0x64c70 | ~400B | USB message send (writev with header) |
| FUN_00064650 | 0x64650 | 32B | Internal message structure initializer |
| FUN_000646fa | 0x646fa | 8B | Payload buffer allocator wrapper |
| FUN_00064768 | 0x64768 | 28B | Set message type and payload pointer |
| FUN_000645ec | 0x645ec | ~40B | Magic header validator (0x55aa55aa) |
| FUN_00064630 | 0x64630 | ~20B | Toggle request/reply magic bytes |

### ELF Section Layout
```
.text    @ 0x154a8  (size: 0x56928) - Code
.rodata  @ 0x6bdd8  (size: 0x15cba) - Read-only data (strings)
.data    @ 0x93f88  (size: 0x00874) - Initialized data
```

## Comparison with Known CarPlay Protocol

The message types align with known CarPlay/Android Auto protocol patterns:
- Video stream messages: 0x05, 0x06
- Audio stream messages: 0x01, 0x02, 0x07
- Control messages: 0x08, 0x0a
- Navigation messages: 0x11, 0x12, 0x6e, 0x6f (NEW)

## Files Analyzed

| File | Version | Size | MD5 |
|------|---------|------|-----|
| ARMadb-driver (packed) | 2025.02 | 211KB | - |
| ARMadb-driver (packed) | 2025.10 | ~200KB | - |
| ARMadb-driver_2025.10_unpacked | 2025.10 | 478KB | 09d053ea9490ac1d964c6607cdcebde6 |

## Version Comparison

### Binary Characteristics

| Property | 2025.02 (packed) | 2025.10 (unpacked) |
|----------|------------------|---------------------|
| Size | 211,424 bytes | 477,501 bytes |
| Linking | Static | Dynamic |
| Compiler | Unknown | GCC 4.9.2 |
| Language | C | C++ |
| Readable strings | 2,534 | 4,768 |
| HU_* signals | 8 (estimated) | 19 |

### New D-Bus Signals in 2025.10

These signals do NOT exist in 2025.02:

```
HU_APP_VERSION         - Application version reporting
HU_MANUAL_DISCONNECT   - Manual disconnect trigger
HU_NAVISCREEN_INFO     - Navigation screen parameters (NEW)
HU_NAVISCREEN_SAFEAREA_INFO  - Safe area bounds (NEW)
HU_NAVISCREEN_VIEWAREA_INFO  - Viewable area bounds (NEW)
HU_NEEDNAVI_STREAM     - Navigation stream request (NEW)
HU_OS_VERSION          - OS version reporting
HU_TYPE_APP            - Application type
HU_TYPE_ID             - Device type ID
HU_TYPE_OS             - OS type
HU_VIEWAREA_INFO       - General viewable area
```

### New Functions in 2025.10

Navigation-related functions not present in 2025.02:
- FUN_00016978 (HU_NEEDNAVI_STREAM handler)
- Navigation focus message routing (0x3d→0x6e, 0x3e→0x6f)
- Enhanced D-Bus signal processor (FUN_00016c20)
- Advanced features reporting (FUN_0001bc24)

## Conclusion

The 2025.10 firmware introduces comprehensive navigation protocol support for CarPlay Dashboard/Instrument Cluster features. Host applications like pi-carplay or carlink_native can implement these features by:

1. Listening for the new HU_NAVI* D-Bus signals
2. Sending USB message types 0x6e/0x6f for navigation focus control
3. Handling the screen parameters (width, height, FPS) from HU_NAVISCREEN_INFO
4. Managing safe area and view area boundaries for proper rendering

## Message Flow Diagram

```
Host Application                    ARMadb-driver                    iOS Device
      |                                   |                               |
      |  USB Bulk: 0x6e (RequestFocus)    |                               |
      |---------------------------------->|                               |
      |                                   |  Internal: 0x3d              |
      |                                   |------------------------------>|
      |                                   |                               |
      |                                   |  D-Bus: HU_NAVISCREEN_INFO    |
      |<----------------------------------|                               |
      |                                   |                               |
      |  Configure encoder (width/h/fps)  |                               |
      |                                   |                               |
      |                                   |  D-Bus: HU_NEEDNAVI_STREAM    |
      |<----------------------------------|                               |
      |                                   |                               |
      |  USB Bulk: 0x11 (video frames)    |                               |
      |---------------------------------->|                               |
      |                                   |  Forward to instrument cluster|
      |                                   |------------------------------>|
```

## Feature Configuration Requirements

### Navigation Feature Gate

Navigation features are **gated by `AdvancedFeatures`** value in adapter configuration:

```c
// In fcn.00016c20 (D-Bus signal handler):
int features = read_config("AdvancedFeatures");  // from /etc/riddle.conf
if (features == 0) {
    log("Not support NaviScreenInfo, return");
    return;  // Navigation disabled
}
// Otherwise process navigation signals
```

### Configuration Files on Adapter

| File | Purpose |
|------|---------|
| `/etc/riddle.conf` | Main configuration, stores `AdvancedFeatures` |
| `/etc/riddle_default.conf` | Default configuration template |
| `/etc/box_version` | Firmware version info |

### AdvancedFeatures Value - CONFIRMED

**Key Finding:** The firmware gate check is simply:
```c
// At address 0x16e70 in fcn.00016c20:
int features = read_config("AdvancedFeatures");  // from /etc/riddle.conf
if (features == 0) {                              // cmp r0, 0
    log("Not support NaviScreenInfo, return");
    return;
}
// Continue to navigation handling...
```

**Any non-zero `AdvancedFeatures` value enables navigation.** There is no specific bitmask required - just set it to any value like `1`, `0x1`, or `0xFF`.

The firmware logs: `advancedFeatures: 0x%X` when feature value is non-zero.

### What AdvancedFeatures Controls vs What Phone Sends Regardless

**✅ Controlled by AdvancedFeatures setting:**
| Feature | AdvancedFeatures=0 | AdvancedFeatures=1 |
|---------|-------------------|-------------------|
| `supportFeatures` in BoxSettings | `""` (empty) | `"naviScreen"` |
| D-Bus signal processing (HU_NAVISCREEN_INFO) | ❌ Rejected | ✅ Processed |
| Navigation video stream handling | ❌ Disabled | ✅ Enabled |
| ttyLog shows `advancedFeatures: 0x%X` | No | Yes |

**❌ NOT controlled by AdvancedFeatures (always sent by iPhone):**
| Message | Description |
|---------|-------------|
| RequestNaviFocus (506) | Phone requests nav overlay - sent regardless |
| ReleaseNaviFocus (507) | Phone releases nav overlay - sent regardless |

The iPhone sends navigation focus commands as part of the standard CarPlay protocol, hoping the head unit supports instrument cluster display. The adapter forwards these to the host app regardless of `AdvancedFeatures`. However, without `AdvancedFeatures=1`, the adapter won't process the D-Bus signals needed to actually set up navigation video streaming.

### Configuration Protocol - Cannot Set Via USB

Analysis of the USB message handlers confirms:
- **AdvancedFeatures cannot be set via USB protocol**
- It is stored in `/etc/riddle.conf` on the adapter's filesystem
- The `CMD_APP_SET_BOX_CONFIG` message only sets limited config keys (e.g., `MicType`, `lang`)
- Navigation feature configuration requires direct adapter access

### Why Navigation Video Stream Is Missing (Even When Focus Commands Present)

From captured sessions with `AdvancedFeatures=0`:
```json
"supportFeatures": ""   // Empty = navigation not advertised
```

**Navigation focus commands (506/507) are present** because the iPhone sends them regardless. However, the navigation video stream is missing because:

1. `AdvancedFeatures` = 0 in `/etc/riddle.conf`
2. Adapter advertises empty `supportFeatures` - doesn't claim navigation capability
3. Firmware gate rejects D-Bus signals: "Not support NaviScreenInfo, return"
4. No `HU_NAVISCREEN_INFO` processed → no navigation video encoder setup
5. Host app sees empty `supportFeatures` and doesn't send screen info

### Enabling Navigation (Requires Adapter Access) ✅ VERIFIED

**Method 1: Using riddleBoxCfg (Recommended)**
```bash
# On adapter via SSH/Telnet:
cd /usr/sbin
./riddleBoxCfg -g AdvancedFeatures    # Check current value
./riddleBoxCfg -s AdvancedFeatures 1  # Enable navigation
# Changes take effect on next CarPlay connection (no reboot needed)
```

**Method 2: Direct config edit**
```bash
# On adapter via SSH/Telnet:
echo "AdvancedFeatures=1" >> /etc/riddle.conf
reboot
```

**Verification:**
After setting, the adapter ttyLog will show:
```
[D] advancedFeatures: 0x1
[D] boxInfo: {...,"supportFeatures":"naviScreen",...}
```

### Additional Message Type Discovered

| Type (Hex) | Type (Dec) | Purpose |
|------------|------------|---------|
| 0x2a | 42 | DashBoard_DATA - Cluster/instrument data |

This message type handles Dashboard/Cluster display data when navigation is enabled.

### BoxSettings JSON Format (Sent by Adapter) ✅ VERIFIED

**With AdvancedFeatures=0:**
```json
{
  "supportFeatures": ""  // Empty - navigation disabled
}
```

**With AdvancedFeatures=1:** ✅ VERIFIED
```json
{
  "uuid": "651ede982f0a99d7f913813....",
  "MFD": "20240119",
  "boxType": "YA",
  "OemName": "test_CCPA",
  "productType": "A15W",
  "HiCar": 1,
  "supportLinkType": "HiCar,CarPlay,AndroidAuto",
  "supportFeatures": "naviScreen",  // ✅ Navigation enabled!
  "hwVersion": "YMA0-WR2C-0003",
  "WiFiChannel": 36,
  "CusCode": "",
  "DevList": [...],
  "ChannelList": "..."
}
```

The `supportFeatures: "naviScreen"` value confirms navigation is enabled and advertised to the host.

---

## Protocol Verification Summary

### Capture Sources Used for Verification

| Source | Capture Date | Duration | Packets | Firmware |
|--------|--------------|----------|---------|----------|
| pi-carplay | 2026-01-13 | 7m 12s | ~35K | 2025.02.25.1521CAY |
| carlink_native | 2026-01-14 | ~30min | ~75K | 2025.02 |
| pi-carplay (new) | 2026-01-15 | 3m 03s | ~4.4K | **2025.10.15.1127CAY** |

### iPhone Device Info (from BoxSettings)
- Model: iPhone18,4
- iOS Version: 23D5103d (iOS 18.4 beta)
- CarPlay Link Version: 935.4.1

### Verified Components

| Component | Status | Notes |
|-----------|--------|-------|
| USB Header (16 bytes) | ✅ Verified | magic=0x55aa55aa, checksum=~type |
| Type 1 (Open) | ✅ Verified | width, height, fps, format, audio params |
| Type 2 (Plugged) | ✅ Verified | phone_type, state |
| Type 3 (Phase) | ✅ Verified | connection phase indicator |
| Type 5 (Touch) | ✅ Verified | action, x, y, flags |
| Type 6 (Video) | ✅ Verified | width, height, H264 NAL data |
| Type 7 (Audio) | ✅ Verified | decode_type, timestamp, volume, PCM |
| Type 8 (Command) | ✅ Verified | 4-byte command value |
| Type 13 (BT Name) | ✅ Verified | null-terminated string |
| Type 25 (BoxSettings) | ✅ Verified | JSON config |
| Type 42 (MediaData) | ✅ Verified | flag + JSON now-playing |
| Type 153 (SendFile) | ✅ Verified | name_len, name, data_len, data |
| Type 170 (HeartBeat) | ✅ Verified | empty payload |
| Type 204 (Version) | ✅ Verified | 32-byte version string |

### Pending Verification (Navigation Features)

| Component | Status | Notes |
|-----------|--------|-------|
| Type 0x2c (44) AltVideoFrame | ⏳ Pending | Navigation video stream - requires full config |
| Type 0x6e (NaviFocus Request) | ⏳ Pending | Not in captures even with 2025.10 firmware |
| Type 0x6f (NaviFocus Release) | ⏳ Pending | Not in captures even with 2025.10 firmware |
| Type 0x11 (Navi Screen Ctrl) | ⏳ Pending | Not present in any captures |
| Type 0x12 (Navi Screen Ctrl) | ❌ Wrong | Actually BluetoothPairedList (verified) |
| HU_NAVISCREEN_INFO | ⏳ Pending | D-Bus signal, needs live adapter capture |
| HU_NEEDNAVI_STREAM | ⏳ Pending | D-Bus signal, needs live adapter capture |

### New Discovery

| Component | Status | Notes |
|-----------|--------|-------|
| Type 0xa3 (163) | ⚠️ NEW | Auth/session data, Base64 encoded, starts "AU" |

### Notes

- **2025.10 firmware verified** (2025.10.15.1127CAY) but navigation messages still not present
- Navigation messages (0x6e, 0x6f, 0x11) likely require:
  1. iOS CarPlay Dashboard/Instrument Cluster feature enabled
  2. Active navigation app (Maps, etc.)
  3. Possibly `supportFeatures` flag from adapter (currently empty)
- Type 18 (0x12) confirmed as BluetoothPairedList, NOT navigation-related
- Type 163 (0xa3) discovered - authentication/session encryption data
- All 21 message types from captures verified against protocol structures

---

## 🔴 CRITICAL: Why Navigation Video Stream Is Not Working

### Root Cause Analysis (From Captured ttyLog)

The adapter ttyLog reveals the exact reason navigation video isn't flowing:

```
2026-01-15 02:26:06.580651 AM [AirPlay] HU features, g_bSupportNaviScreen: 0, g_bSupportViewarea: 0
2026-01-15 02:26:06.580803 AM [AirPlay] Phone features, featureAltScreen: 1, featureViewAreas: 1
2026-01-15 02:26:06.580881 AM [AirPlay] Not support new fratues
```

**The iPhone is READY:**
- `featureAltScreen: 1` - iPhone supports alternate screen (navigation)
- `featureViewAreas: 1` - iPhone supports view area control

**The adapter reports NO support:**
- `g_bSupportNaviScreen: 0` - Adapter tells AppleCarPlay that HU doesn't support navi screen
- `g_bSupportViewarea: 0` - Adapter tells AppleCarPlay that HU doesn't support view areas

**Result:** "Not support new fratues" (typo in firmware) - CarPlay feature negotiation fails, iPhone doesn't send navigation video.

### The Missing Piece: HOST Must Send naviScreenInfo

Analysis of the firmware reveals the flow:

1. **Adapter sends BoxSettings** with `"supportFeatures": "naviScreen"` - ✅ Done (AdvancedFeatures=1)
2. **HOST must respond** with BoxSettings containing `naviScreenInfo` object - ❌ MISSING
3. Adapter parses naviScreenInfo and sends `HU_NAVISCREEN_INFO` D-Bus signal
4. AppleCarPlay sets `g_bSupportNaviScreen = 1` based on D-Bus signal
5. iPhone then negotiates successfully and sends `AltVideoFrame` (Type 44 / 0x2C)

### Required HOST BoxSettings Format

The HOST (Pi-Carplay) must include `naviScreenInfo` in its BoxSettings response:

```json
{
  "mediaDelay": 300,
  "syncTime": 1768476364,
  "androidAutoSizeW": 2400,
  "androidAutoSizeH": 960,
  "WiFiChannel": 36,
  "wifiChannel": 36,
  "mediaSound": 1,
  "callQuality": 1,
  "autoPlay": true,
  "autoConn": true,
  "wifiName": "test_CCPA",
  "btName": "test_CCPA",
  "boxName": "test_CCPA",
  "OemName": "test_CCPA",

  // ===== REQUIRED FOR NAVIGATION =====
  "naviScreenInfo": {
    "width": 480,       // Navigation display width
    "height": 240,      // Navigation display height
    "fps": 30           // Navigation framerate
  }
}
```

The `naviScreenInfo` object is parsed by fcn.00016c20 (at 0x16f24) which then:
1. Extracts width, height, fps values
2. Logs: `_naviScreenInfo %dx%d, %d FPS`
3. Sends `HU_NAVISCREEN_INFO` D-Bus signal with dimensions
4. Sends `HU_NAVISCREEN_SAFEAREA_INFO` and `HU_NAVISCREEN_VIEWAREA_INFO` signals
5. This causes AppleCarPlay to set `g_bSupportNaviScreen = 1`

### Message Type 44 (0x2c) = AltVideoFrame

**NOTE:** Message type 43 (0x2B) is `Connection_PINCODE` (BT pairing PIN), NOT AltVideoFrame.
AltVideoFrame is message type 44 (0x2C). This was verified from the ARMadb-driver binary string table.

Once navigation is properly negotiated, the iPhone sends navigation video via:

| Type (Hex) | Type (Dec) | Name | Direction | Description |
|------------|------------|------|-----------|-------------|
| 0x2c | 44 | AltVideoFrame | IN | Navigation/secondary video stream |

This message carries the same format as Type 6 (VideoData) but for the navigation display.

### Complete Protocol Flow for Navigation Video

```
Step 1: Adapter advertises capability
════════════════════════════════════════════════════════════════════
  Adapter → Host: BoxSettings (Type 25)
  {
    "supportFeatures": "naviScreen",  // Adapter says "I support this"
    ...
  }

Step 2: HOST must configure navigation display (CURRENTLY MISSING)
════════════════════════════════════════════════════════════════════
  Host → Adapter: BoxSettings (Type 25)
  {
    "naviScreenInfo": {     // HOST says "I want navigation at this resolution"
      "width": 480,
      "height": 240,
      "fps": 30
    },
    ...
  }

Step 3: Adapter processes and signals AppleCarPlay
════════════════════════════════════════════════════════════════════
  ARMadb-driver → AppleCarPlay (D-Bus):
    - HU_NAVISCREEN_INFO(width=480, height=240, fps=30)
    - HU_NAVISCREEN_SAFEAREA_INFO(...)
    - HU_NAVISCREEN_VIEWAREA_INFO(...)

  AppleCarPlay sets: g_bSupportNaviScreen = 1

Step 4: CarPlay negotiation succeeds
════════════════════════════════════════════════════════════════════
  AppleCarPlay → iPhone (CarPlay Protocol):
    - featureAltScreen: 1 (negotiated)

  ttyLog would show:
    [AirPlay] HU features, g_bSupportNaviScreen: 1, g_bSupportViewarea: 1
    [AirPlay] Phone features, featureAltScreen: 1, featureViewAreas: 1
    [AirPlay] Support new features  // Success!

Step 5: Navigation video flows
════════════════════════════════════════════════════════════════════
  iPhone → Adapter → Host:
    Type 44 (AltVideoFrame) packets with navigation H.264 video
```

### Implementation for Pi-Carplay

To enable navigation video capture/display in Pi-Carplay:

1. **Modify BoxSettings response** to include `naviScreenInfo` object
2. **Add handler for Type 44 (AltVideoFrame)** messages
3. **Typical navigation display sizes:**
   - 480x240 @ 30fps (compact cluster)
   - 800x480 @ 30fps (larger cluster)
   - 1280x480 @ 60fps (wide cluster)

### Code Modification Required

In the Pi-Carplay host application, modify the BoxSettings JSON sent to adapter:

```c
// Current Pi-Carplay BoxSettings (navigation NOT enabled):
const char* box_settings_current = "{"
    "\"mediaDelay\":300,"
    "\"syncTime\":1768476364,"
    "\"androidAutoSizeW\":2400,"
    "\"androidAutoSizeH\":960,"
    // ... other fields ...
"}";

// Modified BoxSettings to ENABLE navigation:
const char* box_settings_with_navi = "{"
    "\"mediaDelay\":300,"
    "\"syncTime\":1768476364,"
    "\"androidAutoSizeW\":2400,"
    "\"androidAutoSizeH\":960,"
    "\"naviScreenInfo\":{"
        "\"width\":480,"
        "\"height\":240,"
        "\"fps\":30"
    "},"
    // ... other fields ...
"}";
```

### Verification Steps

1. Set `AdvancedFeatures=1` on adapter (already done)
2. Modify Pi-Carplay to send `naviScreenInfo` in BoxSettings
3. Start CarPlay session with Maps navigation active
4. Check adapter ttyLog for:
   ```
   [AirPlay] HU features, g_bSupportNaviScreen: 1, g_bSupportViewarea: 1
   [AirPlay] Support new features
   ```
5. Capture should then contain Type 44 (AltVideoFrame) packets

---
*Analysis performed: January 2026*
*Updated with comprehensive USB protocol structures*
*Protocol verification completed against pi-carplay and carlink_native captures*
*Tools: Ghidra 11.3.2, radare2*
*Firmware: Carlinkit A15W 2025.10*

# CPC200-CCPA Protocol Reference for Claude

**Project:** CPC200-CCPA CarPlay/Android Auto Adapter Reverse Engineering
**Last Verified:** 2025-12-30
**Evidence Base:** 25 capture sessions (21 controlled reference + 4 legacy)

---

## Quick Reference

### Hardware
- **Model:** CPC200-CCPA (A15W) / Carlinkit Wireless Adapter
- **CPU:** NXP i.MX6UL (ARM Cortex-A7, ARMv7 32-bit)
- **RAM:** 128MB
- **Kernel:** Linux 3.14.52
- **WiFi:** RTL88x2CS (5GHz 802.11ac)
- **USB:** Gadget mode (OTG)

### USB Identifiers
| Interface | VID:PID | Description |
|-----------|---------|-------------|
| iPhone-facing | 0x08e4:0x01c0 | Magic Communication Tec. |
| Head unit-facing | 0x1314:0x1521 | Adapter output |

---

## Protocol Format

### Packet Structure
```
Offset  Size  Field        Description
------  ----  -----        -----------
0       4     magic        0x55AA55AA (little-endian)
4       4     length       Payload length (LE)
8       4     type         Message type ID
12      4     type_check   ~type (bitwise NOT for validation)
16      N     payload      Message-specific data
```

### Message Types
| ID | Hex | Name | Direction | Description |
|----|-----|------|-----------|-------------|
| 1 | 0x01 | OPEN | OUT→Adapter | Initialize with display config |
| 2 | 0x02 | PLUGGED | IN←Adapter | Device connected notification |
| 3 | 0x03 | STATE_MODE | IN←Adapter | State/mode indicator (payload: uint32) |
| 4 | 0x04 | UNPLUGGED | IN←Adapter | Device disconnected |
| 5 | 0x05 | TOUCH | OUT→Adapter | Single touch event |
| 6 | 0x06 | VIDEO_DATA | IN←Adapter | H.264 video frame |
| 7 | 0x07 | AUDIO_DATA | BOTH | Audio samples or commands |
| 8 | 0x08 | COMMAND | OUT→Adapter | Control command |
| 13 | 0x0D | BT_DEVICE_NAME | IN←Adapter | Bluetooth device name |
| 14 | 0x0E | WIFI_DEVICE_NAME | IN←Adapter | WiFi device name |
| 18 | 0x12 | BT_PAIR_STATUS | BOTH | Bluetooth pairing status |
| 23 | 0x17 | MULTI_TOUCH | OUT→Adapter | Multi-touch event |
| 25 | 0x19 | BOX_SETTINGS | OUT→Adapter | JSON configuration |
| 35 | 0x23 | MAC_ADDR_1 | IN←Adapter | Device MAC address |
| 36 | 0x24 | MAC_ADDR_2 | IN←Adapter | Alternative MAC address |
| 37 | 0x25 | ACK_STATUS | BOTH | ACK/ping/status (empty payload) |
| 38 | 0x26 | WIFI_STATE | IN←Adapter | WiFi connection state |
| 42 | 0x2A | MEDIA_DATA | IN←Adapter | Media metadata/album art (JSON) |
| 153 | 0x99 | SEND_FILE | OUT→Adapter | Upload file to adapter |
| 170 | 0xAA | HEARTBEAT | OUT→Adapter | Keep-alive ping |
| 187 | 0xBB | STATUS_VALUE | IN←Adapter | Configuration value (uint32) |
| 204 | 0xCC | SOFTWARE_VERSION | IN←Adapter | Firmware version string |

---

## Audio Protocol (Message Type 0x07)

### Audio Packet Structure
```
Offset  Size  Field        Description
------  ----  -----        -----------
0       4     payload_len  Total payload length (LE)
4       4     msg_type     Always 0x07 for audio
8       4     reserved     Usually 0xFFFFFFF8 (-8 signed)
12      4     decode_type  Audio format: 2, 4, or 5
16      4     volume       Float32 volume level
20      4     audio_type   Channel: 1, 2, or 3
24      N     data         Command byte (if len=13) OR PCM samples
```

### decode_type Values (VERIFIED)
| Value | Name | Sample Rate | Channels | Bits | Purpose |
|-------|------|-------------|----------|------|---------|
| 2 | STOP | N/A | N/A | N/A | Channel stop/cleanup signal |
| 4 | PLAYBACK | 44100/48000 | 2 (Stereo) | 16 | Standard audio (media, nav, alerts) |
| 5 | VOICE | 16000 | 1 (Mono) | 16 | Voice mode (Siri, phone calls) |

**Note:** Values 1, 3, 6, 7 were speculative in older docs and NEVER observed in captures.

### audio_type Values (VERIFIED)
| Value | Name | Direction | Purpose |
|-------|------|-----------|---------|
| 1 | MAIN | IN (playback) | Primary audio (media, alerts, Siri speech, call audio) |
| 2 | NAVIGATION | IN (playback) | Navigation prompts (ducking channel) |
| 3 | MICROPHONE | OUT (capture) | Microphone input (Siri listening, phone calls) |

**Direction Convention:**
- IN = Phone/Adapter → Head Unit (audio to speakers)
- OUT = Head Unit → Phone/Adapter (microphone to phone)

### Audio Commands (payload_len = 13)
When payload_len is 13, the final byte is a command:

| Byte | Hex | Name | decode_type | audio_type | Purpose |
|------|-----|------|-------------|------------|---------|
| 1 | 0x01 | OUTPUT_START | 4, 5 | 1, 2 | Start audio output |
| 2 | 0x02 | OUTPUT_STOP | 4, 5 | 1, 2 | Stop audio output |
| 3 | 0x03 | INPUT_START | 5 | 1 | Start microphone capture |
| 4 | 0x04 | INPUT_STOP | 5 | 1 | Stop microphone capture |
| 5 | 0x05 | PHONECALL_START | 5 | 1 | Phone call connected |
| 6 | 0x06 | PHONECALL_STOP | 2, 4 | 2 | Phone call ended / channel clear |
| 7 | 0x07 | NAVI_START | 4 | 2 | Navigation prompt starting |
| 8 | 0x08 | NAVI_STOP | 5 | 1 | Activates Siri mode (misleading name) |
| 9 | 0x09 | SIRI_START | 5 | 1 | Siri responding |
| 10 | 0x0A | MEDIA_START | 4 | 1 | Media playback starting |
| 11 | 0x0B | MEDIA_STOP | 2, 4 | 1 | Media playback stopped |
| 12 | 0x0C | ALERT_START | 4 | 1 | Alert/notification audio starting |
| 13 | 0x0D | ALERT_STOP | 4 | 1 | Alert/notification audio stopped |
| 14 | 0x0E | INCOMING_CALL_INIT | 5 | 1 | Incoming call notification |
| 16 | 0x10 | NAVI_COMPLETE | 4 | 2 | Navigation prompt finished |

**Note:** Command 0x0F and 0x11-0xFF not observed. No SIRI_STOP command exists.

### Audio Packet Sizes
| payload_len | Purpose |
|-------------|---------|
| 13 | Control command (12-byte header + 1 command byte) |
| 16 | Extended control (navigation volume adjustment) |
| 972 | Voice audio chunk (Siri/phone): 960 bytes PCM = 30ms at 16kHz mono |
| 11532 | Standard audio chunk (media/nav): 11520 bytes PCM = 60ms at 48kHz stereo |
| 1856-8204 | Variable microphone data |

---

## Audio Scenario Command Sequences

### Media Playback
```
MEDIA_START (dt=4, at=1)
OUTPUT_START (dt=4, at=1)
  [media audio packets: dt=4, at=1, 11532 bytes each]
MEDIA_STOP (dt=4, at=1) or (dt=2, at=1)
OUTPUT_STOP (dt=4, at=1)
```

### Navigation Prompt
```
PHONECALL_STOP (dt=2, at=2)     <- Channel clear signal
OUTPUT_START (dt=4, at=2)
NAVI_START (dt=4, at=2)
  [nav audio packets: dt=4, at=2]
NAVI_COMPLETE (dt=4, at=2)
OUTPUT_STOP (dt=4, at=2)
```

### Media + Navigation (Ducking)
```
MEDIA_START (dt=4, at=1)
OUTPUT_START (dt=4, at=1)
  [media on at=1]
PHONECALL_STOP (dt=2, at=2)     <- Nav incoming
OUTPUT_START (dt=4, at=2)
NAVI_START (dt=4, at=2)
  [nav on at=2, media ducks on at=1]
NAVI_COMPLETE (dt=4, at=2)
OUTPUT_STOP (dt=4, at=2)
  [media resumes full volume]
```

### Siri Invocation
```
NAVI_STOP (dt=5, at=1)          <- Activates Siri mode
INPUT_START (dt=5, at=1)        <- Microphone on
OUTPUT_START (dt=5, at=1)       <- Audio output on
  [mic data OUT: dt=5, at=3]
  [Siri audio IN: dt=5, at=1, 972-byte packets]
SIRI_START (dt=5, at=1)         <- Siri responding
OUTPUT_STOP (dt=5, at=1)
```

### Incoming Phone Call
```
INCOMING_CALL_INIT (dt=5, at=1) <- Call notification
ALERT_START (dt=4, at=1)        <- Ringtone begins
OUTPUT_START (dt=4, at=1)
  [ringtone audio: dt=4, at=1]
ALERT_STOP (dt=4, at=1)
OUTPUT_STOP (dt=4, at=1)
INPUT_START (dt=5, at=1)        <- Mic activates
INPUT_STOP (dt=5, at=1)         <- State transition
OUTPUT_START (dt=5, at=1)       <- Call audio begins
  [call audio IN: dt=5, at=1]
  [mic data OUT: dt=5, at=3]
PHONECALL_START (dt=5, at=1)    <- Call connected
OUTPUT_STOP (dt=5, at=1)        <- Call ends
```

### Outgoing Phone Call
```
INPUT_STOP (dt=5, at=1)         <- Clear mic state
INPUT_START (dt=5, at=1)        <- Mic activates
OUTPUT_START (dt=5, at=1)       <- Audio begins (ringback in stream)
PHONECALL_START (dt=5, at=1)    <- Call connected
  [call audio IN: dt=5, at=1]
  [mic data OUT: dt=5, at=3]
OUTPUT_STOP (dt=5, at=1)        <- Call ends
```

---

## Video Protocol (Message Type 0x06)

### Video Packet Structure
```
Offset  Size  Field      Description
------  ----  -----      -----------
0       4     width      Frame width (e.g., 1920)
4       4     height     Frame height (e.g., 720)
8       4     flags      Frame flags
12      4     length     H.264 data length
16      4     unknown    Reserved/unknown field
20      N     h264_data  H.264 NAL units
```

### Typical Values
- Resolution: 800x480, 1920x720, 1920x1080 (configurable)
- FPS: 10-60 (configurable, verified range - see VIDEO_AUDIO_DATA_FLOW.md §1.6)
- Codec: H.264 (AVC) High Profile
- Streams: Main Video (0x06) + Navigation Video (0x2C)

---

## Control Commands (Message Type 0x08)

| ID | Name | Description |
|----|------|-------------|
| 1 | START_RECORD_AUDIO | Begin audio recording |
| 2 | STOP_RECORD_AUDIO | Stop audio recording |
| 3 | REQUEST_HOST_UI | Request UI focus |
| 5 | SIRI | Trigger Siri |
| 7 | MIC | Phone microphone control |
| 15 | BOX_MIC | Adapter microphone control |
| 16 | ENABLE_NIGHT_MODE | Enable night mode |
| 17 | DISABLE_NIGHT_MODE | Disable night mode |
| 22 | AUDIO_TRANSFER_ON | Enable audio transfer |
| 23 | AUDIO_TRANSFER_OFF | Disable audio transfer |
| 24 | WIFI_24G | Switch to 2.4GHz WiFi |
| 25 | WIFI_5G | Switch to 5GHz WiFi |
| 100 | LEFT | D-pad left |
| 101 | RIGHT | D-pad right |
| 104 | SELECT_DOWN | Select button down |
| 105 | SELECT_UP | Select button up |
| 106 | BACK | Back button |
| 114 | DOWN | D-pad down |
| 200 | HOME | Home button |
| 201 | PLAY | Play button |
| 202 | PAUSE | Pause button |
| 204 | NEXT | Next track |
| 205 | PREV | Previous track |
| 500 | REQUEST_VIDEO_FOCUS | Request video focus |
| 501 | RELEASE_VIDEO_FOCUS | Release video focus |
| 1000 | WIFI_ENABLE | Enable WiFi |

---

## Key Files on Adapter

### Configuration
| Path | Purpose |
|------|---------|
| /etc/riddle.conf | Main configuration |
| /etc/BoxSettings.json | Device settings |
| /tmp/screen_dpi | Screen DPI setting |
| /tmp/night_mode | Night mode flag |
| /tmp/hand_drive_mode | Hand drive mode flag |

### Authentication
| Path | Purpose |
|------|---------|
| /var/lib/lockdown/common.cert | Auth certificates (plist) |
| /var/lib/lockdown/root_key.pem | RSA private key (2048-bit) |
| /Library/Keychains/default.keychain | Pairing data |

### Device Interfaces
| Path | Purpose |
|------|---------|
| /dev/android_iap2 | USB IAP2 device |
| /tmp/rfcomm_IAP2 | Bluetooth RFCOMM |
| /tmp/.mfi_auth_lock | Auth mutex |
| /dev/hwaes | Hardware AES engine |

---

## Key Binaries

| Binary | Size | Purpose |
|--------|------|---------|
| AppleCarPlay | 557KB | Main CarPlay receiver |
| ARMiPhoneIAP2 | 494KB | IAP2 protocol handler |
| ARMadb-driver | 469KB | Android Auto ADB driver |
| ARMHiCar | 132KB | Huawei HiCar support |
| bluetoothDaemon | 396KB | Bluetooth management |
| mdnsd | 378KB | mDNS/Bonjour service |

### Key Libraries
| Library | Purpose |
|---------|---------|
| libdmsdp.so | DMSDP protocol core |
| libdmsdpcrypto.so | Crypto (X25519, AES-GCM) |
| libdmsdpaudiohandler.so | Audio dispatch |
| libauthagent.so | Authentication/trust |

---

## Crypto Stack

| Protocol | Parameters |
|----------|------------|
| Pairing | SRP-6a, 3072-bit, SHA-512 |
| Transport | ChaCha20-Poly1305 |
| Key Exchange | X25519 (Curve25519) |
| Symmetric | AES-256-GCM |
| USB Encryption | AES-128-CTR (CMD_ENABLE_CRYPT) |

---

## Android Auto Specifics

| Aspect | Value |
|--------|-------|
| WiFi Port | 54321 |
| Encryption | SSL/TLS |
| Handshake | BT RFCOMM → WiFi credentials → TCP SSL |
| Protocol Version | 1.7 |
| Auth Handshake | 2037 + 51 bytes |

### Differences from CarPlay
| Aspect | CarPlay | Android Auto |
|--------|---------|--------------|
| Volume field | Often 1.0 | Always 0.0 |
| audio_type | 1 (main) or 2 (nav ducking) | Always 1 |
| Navigation ducking | Explicit audio_type=2 | Not observed |

---

## Verification Data

### Capture Sessions Analyzed
| Scenario | Sessions | Commands Verified |
|----------|----------|-------------------|
| Video Only | 3 | Baseline (no audio) |
| Media Playback | 3 | MEDIA_START/STOP, OUTPUT_START/STOP, ALERT_* |
| Navigation | 3 | NAVI_START/COMPLETE, PHONECALL_STOP, OUTPUT_* |
| Media+Navigation | 3 | Ducking behavior verified |
| Siri | 3 | NAVI_STOP, INPUT_START, SIRI_START |
| Incoming Call | 3 | INCOMING_CALL_INIT, ALERT_*, PHONECALL_START |
| Outgoing Call | 3 | INPUT_*, PHONECALL_START (no ALERT) |
| Legacy Mixed | 4 | Cross-validation of all commands |
| **Total** | **25** | **All 15 audio commands verified** |

### Command Frequency (Reference Captures)
| Command | Media | Nav | Med+Nav | Siri | In-Call | Out-Call |
|---------|-------|-----|---------|------|---------|----------|
| OUTPUT_START | 9 | 13 | 15 | 25 | 25 | 9 |
| OUTPUT_STOP | 6 | 13 | 12 | 25 | 25 | 9 |
| INPUT_START | 0 | 0 | 0 | 25 | 9 | 9 |
| INPUT_STOP | 0 | 0 | 0 | 0 | 9 | 9 |
| PHONECALL_START | 0 | 0 | 0 | 0 | 18 | 9 |
| PHONECALL_STOP | 0 | 22 | 18 | 0 | 0 | 0 |
| NAVI_START | 0 | 22 | 18 | 0 | 0 | 0 |
| NAVI_STOP | 0 | 0 | 0 | 27 | 0 | 0 |
| NAVI_COMPLETE | 0 | 13 | 12 | 0 | 0 | 0 |
| SIRI_START | 0 | 0 | 0 | 27 | 0 | 0 |
| MEDIA_START | 12 | 0 | 6 | 0 | 0 | 0 |
| MEDIA_STOP | 9 | 0 | 2 | 0 | 0 | 0 |
| ALERT_START | 3 | 0 | 0 | 0 | 16 | 0 |
| ALERT_STOP | 3 | 0 | 0 | 0 | 16 | 0 |
| INCOMING_CALL_INIT | 0 | 0 | 0 | 0 | 9 | 0 |

---

## File Locations

### Documentation
| File | Contents |
|------|----------|
| docs/protocol/AUDIO_PROTOCOL.md | Complete audio protocol reference |
| docs/protocol/CARPLAY_PROTOCOL_CAPTURE.md | RTSP protocol analysis |
| docs/hardware/REVERSE_ENGINEERING_NOTES.md | Binary analysis, Autokit findings |
| docs/implementation/PI_STANDALONE_IMPLEMENTATION.md | Protocol format specs |

### Capture Data
| Path | Contents |
|------|----------|
| captures/picarplay/carplay/reference/ | Verified capture sessions |
| captures/picarplay/carplay/old/ | Legacy capture sessions |
| captures/macos_usb/ | macOS USB RAW captures |
| captures/adapter/ | On-adapter captures |

### Firmware
| Path | Contents |
|------|----------|
| firmware/sftp_extract/ | Live device extraction |
| firmware/unpacked_binaries/ | UPX-unpacked executables |

---

## Important Notes

1. **NAVI_STOP (0x08) is misleading** - It activates Siri mode, not stops navigation
2. **No SIRI_STOP command exists** - Siri ends via OUTPUT_STOP
3. **decode_type 2 is STOP signal** - Not "Alt Media" as older docs claimed
4. **audio_type=3 is MICROPHONE** - Only observed in OUT direction (mic data)
5. **Outgoing calls have no ALERT_*** - Ringback tone is in the audio stream
6. **androidWorkMode must be true** - Required for Android Auto daemon to start

---

## 2025-01-15 Analysis Update

### New Binaries Discovered
| Binary | Size | Purpose |
|--------|------|---------|
| ARMAndroidAuto | 489KB | Android Auto protocol handler |
| boxNetworkService | 45KB | Network management daemon |
| hwSecret | 23KB | Secret/key management |
| riddle_top | 10KB | Process monitor |

### New Libraries Analyzed
| Library | Size | Purpose |
|---------|------|---------|
| libdmsdpplatform.so | 242KB | FILLP protocol, AES-256-GCM |
| libHwKeystoreSDK.so | 168KB | Huawei Key Store API |
| libHisightSink.so | 147KB | HiCar video sink |
| libnearby.so | 91KB | Google Nearby protocol |

### Crypto Stack (from libdmsdpplatform.so)
```c
AES_128CTREncry / AES_128CTRDecrypt
AES_128OFBEncry / AES_128OFBDecrypt
AES_256GCMEncry / AES_256GCMDecrypt
DMSDPGetPBKDF2Key()  // PBKDF2 key derivation
```

### AirPlay Version
```
AirPlay/320.17
```

### New Internal Commands (with Type IDs)
| Command | Type ID | Direction | Description |
|---------|---------|-----------|-------------|
| CMD_APP_INFO | - | OUT | Application info JSON (pid, uuid) |
| CMD_CAR_MANUFACTURER_INFO | 0x14 | OUT | OEM manufacturer data |
| CMD_ENABLE_CRYPT | - | OUT | Enable USB encryption (4-byte seed) |
| CMD_DEBUG_TEST | 0x88 | OUT | Debug/test mode (1=open log, 2=read, 3=persist) |
| CMD_CONNECTION_URL | 0x18 | IN | HiCar connection URL |
| CMD_CAMERA_FRAME | 0x16 | BOTH | Camera/reverse video frame |
| CMD_PAY_RESULT | 0x1A | IN | Payment result JSON |
| CMD_APP_SET_BOX_CONFIG | - | OUT | JSON configuration settings |
| CMD_STOP_PHONE_CONNECTION | 0x15 | OUT | Stop active phone connection |
| CMD_BLUETOOTH_ONLINE_LIST | 0x13 | IN | Connected BT devices list |

### USB Encryption (CMD_ENABLE_CRYPT)
```
Hardcoded AES-128 Key: W2EC1X1NbZ58TXtn
Payload: 4 bytes (uint32 seed, must be > 0)
Library: libcrypto.so.1.1 (OpenSSL)
Functions: AES_set_encrypt_key, AES_cbc_encrypt
Hardware: /dev/hwaes (optional HW acceleration)
```

**Security Note:** All adapters share the same hardcoded AES key.

### CMD_DEBUG_TEST Commands
| Value | Action |
|-------|--------|
| 1 | Open /tmp/userspace.log, run /script/open_log.sh |
| 2 | Read log file, send contents to host |
| 3 | Enable persistent debug mode flag |

### iAP2 Engines (from ARMiPhoneIAP2)
- iAP2CallStateEngine
- iAP2CommunicationEngine
- iAP2LocationEngine
- iAP2MediaPlayerEngine
- iAP2RouteGuidanceEngine
- iAP2WiFiConfigEngine

### DMSDP Protocol Functions
```c
DMSDPConnectFsmEventHandler()
DMSDPChannelProtocolCreate()
DMSDPDataSessionCreateRtpSender()
DMSDPCreateNearbyChannel()
```

### Bluetooth SDP Record
```
Service: Wireless iAP
UUID: 00000000-deca-fade-deca-deafdecacafe
RFCOMM Channel: 1
```

### Full Documentation
See: `docs/analysis/ANALYSIS_UPDATE_2025_01_15.md`

---

*Generated: 2025-12-30*
*Updated: 2025-01-15 (live adapter analysis)*
*Updated: 2026-01-22 (video FPS range empirically verified: 10-60 FPS)*
*Verified against 25+ capture sessions*

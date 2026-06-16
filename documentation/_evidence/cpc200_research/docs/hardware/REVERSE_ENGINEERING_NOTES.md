# CPC200-CCPA Adapter Reverse Engineering Documentation

**Date:** 2025-12-27
**Adapter Model:** CPC200-CCPA (Carlinkit Wireless CarPlay/Android Auto)
**Hardware:** iMX6UL ARM Cortex-A7, Linux 3.14.52

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Hardware Architecture](#hardware-architecture)
3. [Software Architecture](#software-architecture)
4. [Authentication System](#authentication-system)
5. [Protocol Stack](#protocol-stack)
6. [USB Gadget Implementation](#usb-gadget-implementation)
7. [IAP2 Protocol](#iap2-protocol)
8. [CarPlay/AirPlay Implementation](#carplayairplay-implementation)
9. [Crypto Implementation](#crypto-implementation)
10. [mDNS Services](#mdns-services)
11. [Key Files and Paths](#key-files-and-paths)
12. [Raspberry Pi Port Guide](#raspberry-pi-port-guide)
13. [Open Questions](#open-questions)

---

## Executive Summary

The CPC200-CCPA is a wireless CarPlay/Android Auto adapter that:

- **Does NOT contain an MFi hardware chip** - Authentication is entirely software-based
- Uses **self-signed certificates** with absurd validity dates (year 3911-3921)
- Implements a **"FakeCarPlayDevice"** architecture (per source code paths)
- Uses **MiddleMan proxy pattern** to bridge iPhone and head unit
- Can be potentially replicated on Raspberry Pi 4/5

### Key Discovery

The adapter's source code was developed by "Hewei" (Huawei-related) under the project name:
```
/home/sky/Hewei/HiCarPackage/HeweiPackTools/FakeCarPlayDevice/
```

---

## Hardware Architecture

### SoC
- **Processor:** NXP i.MX6UL (ARM Cortex-A7)
- **Architecture:** ARMv7, 32-bit
- **Kernel:** Linux 3.14.52+g94d07bb SMP

### Key Hardware Interfaces
- USB OTG (gadget mode for iPhone connection)
- WiFi (RTL88x2CS - Realtek)
- Bluetooth (RTK HCI UART - Realtek)
- Hardware AES engine (`/dev/hwaes`) - Used for binary encryption

### Kernel Modules
| Module | Purpose |
|--------|---------|
| `g_iphone.ko` | IAP2 USB gadget driver |
| `f_ptp_appledev.ko` | PTP Apple device function |
| `f_ptp_appledev2.ko` | Alternative PTP function |
| `g_android_accessory.ko` | Android AOA gadget |
| `88x2cs.ko` | Realtek WiFi driver |
| `rtk_hci_uart.ko` | Realtek Bluetooth HCI |
| `cdc_ncm.ko` | USB NCM networking |

---

## Software Architecture

### Main Binaries (Unpacked)

| Binary | Size | Purpose |
|--------|------|---------|
| `AppleCarPlay.unpacked` | 557KB | Main CarPlay receiver |
| `ARMiPhoneIAP2.unpacked` | 494KB | IAP2 protocol handler |
| `ARMadb-driver.unpacked` | 469KB | Android Auto ADB driver |
| `ARMHiCar.unpacked` | 132KB | Huawei HiCar support |
| `bluetoothDaemon.unpacked` | 396KB | Bluetooth management |
| `mdnsd.unpacked` | 378KB | mDNS/Bonjour service |

### Key Libraries (Full Symbols Available)

| Library | Size | Purpose |
|---------|------|---------|
| `libdmsdp.so` | 184KB | DMSDP protocol core |
| `libdmsdpcrypto.so` | 80KB | X25519, AES-GCM, SHA256 |
| `libauthagent.so` | 44KB | Authentication/trust |
| `libnearby.so` | 92KB | Device discovery |
| `libdmsdpdvinterface.so` | - | Device interface |
| `libdmsdpaudiohandler.so` | - | Audio streaming |
| `libdmsdpcamerahandler.so` | - | Camera/video |
| `libARMtool.so` | - | Utility functions |
| `libboxtrans.so` | - | Box transport |
| `libhicar.so` | - | HiCar protocol |
| `libHwDeviceAuthSDK.so` | - | Huawei device auth |
| `libHwKeystoreSDK.so` | - | Huawei keystore |

### Binary Protection

All main binaries were UPX-packed with:
- Modified magic bytes: `0x22552255` (vs standard `0x21585055`)
- Hardware AES encryption via `/dev/hwaes`
- Required patched UPX from ludwig-v repo to unpack
- Must run unpacker ON the device (hardware key is device-bound)

---

## Authentication System

### Certificate Structure

Location: `/var/lib/lockdown/common.cert`

Format: Apple plist containing base64-encoded:
- `HostPrivateKey` - 2048-bit RSA private key
- `HostCertificate` - Self-signed X.509 certificate
- `RootPrivateKey` - Root CA private key
- `RootCertificate` - Root CA certificate

### Certificate Details

```
Issuer: (empty - self-signed)
Validity:
    Not Before: Jun  1 06:02:03 3911 GMT
    Not After : May 28 06:02:03 3921 GMT
Public Key: RSA 2048-bit
Signature: SHA1withRSA
Key Usage: Digital Signature, Key Encipherment
CA: FALSE
```

### Root Key (Plaintext!)

Location: `/var/lib/lockdown/root_key.pem`
- Standard PEM format
- 2048-bit RSA
- No encryption/passphrase

### Authentication APIs

```c
// From libauthagent.so
GetAuthagentInstance()
DestroyAuthagent()
RefreshPinAuth()
ListTrustPhones()
DelTrustPhones()
IsTrustPhones()
is_trust_peer()
list_trust_peers()
delete_local_auth_info()
```

### MFi Authentication Lock

Software mutex via lock file:
```
/tmp/.mfi_auth_lock
```

Commands found in binary:
```sh
rm -f /tmp/.mfi_auth_lock
touch /tmp/.mfi_auth_lock
wait mfi_auth_lock...
```

---

## Protocol Stack

### DMSDP (Device Media Streaming Data Protocol)

Proprietary protocol with these components:

#### Core Functions (from libdmsdp.so)
```c
DMSDPInitial()                    // Initialize protocol
DMSDPServiceStart()               // Start service
DMSDPServiceStop()                // Stop service
DMSDPConnectSendData()            // Send binary data
DMSDPConnectSendBinaryData()      // Send raw binary
DMSDPNetworkSessionSendCrypto()   // Encrypted transmission
DMSDPDataSessionNewSession()      // Create session
DMSDPDataSessionSendCtrlMsg()     // Control messages
DMSDPCreateRtpReceiver()          // RTP receive
DMSDPCreateRtpSender()            // RTP send
```

#### Service Types
```c
DMSDPLoadAudioService()           // Audio streaming
DMSDPLoadCameraService()          // Video streaming
DMSDPLoadGpsService()             // GPS data
```

#### Channel Functions
```c
DMSDPChannelProtocolCreate()
DMSDPChannelGetDeviceType()
DMSDPChannelGetDeviceState()
DMSDPChannelGetBusinessID()
DMSDPChannelMakeNotifyMsg()
DMSDPChannelHandleMsg()
DMSDPNearbyChannelSendData()
```

---

## USB Gadget Implementation

### Kernel Module: g_iphone.ko

#### Module Parameters
```
idVendor=ushort       # USB Vendor ID
idProduct=ushort      # USB Product ID
iProduct=charp        # Product string
iManufacturer=charp   # Manufacturer string
iSerialNumber=charp   # Serial number string
serial=charp          # Device serial
bcdDevice=ushort      # Device version (BCD)
hnp_interval_ms=int   # HNP interval for role switch
```

#### Device Strings
```
Manufacturer: Apple Inc.
Product: PTP + Apple Mobile Device
         PTP + Apple Mobile Device + Apple USB Ethernet
```

#### IAP2 Functions
```c
iap2_read()           // Read from host (432 bytes)
iap2_write()          // Write to host (592 bytes)
iap2_ioctl()          // Control commands (112 bytes)
iap2_open()           // Open session
```

### Kernel Module: f_ptp_appledev.ko

#### USB Descriptors
```c
fs_source_desc              // Full-speed source endpoint
fs_sink_desc                // Full-speed sink endpoint
fs_int_source_desc          // Full-speed interrupt
source_sink_intf_appleusb_alt0  // Interface alt setting
hs_source_desc              // High-speed source
hs_sink_desc                // High-speed sink
```

#### Function Name
```
alias=usbfunc:PTP_APPLEDEV
```

---

## IAP2 Protocol

### Source Files (from binary strings)
```
Sources/ARMiPhoneIAP2/CarPlayiAP2main.cpp
Sources/ARMiPhoneIAP2/HudiAP2Server.cpp
Sources/ARMiPhoneIAP2/HudiAP2Medium_BT.cpp
Sources/ARMiPhoneIAP2/HudiAP2Medium_USB.cpp
Sources/ARMiPhoneIAP2/HudiAP2Session_CarPlay.cpp
Sources/iAP2PacketUtil.c
Sources/iAP2IdentifyEngine.cpp
Sources/iAP2MediaPlayerEngine.cpp
Sources/iAP2Sesson_FileTransfer.cpp
Sources/iAP2UpdateEntity.cpp
Sources/iAP2Engine.cpp
```

### Class Hierarchy
```cpp
CCarPlay_MiddleManInterface_iAP2InternalUse  // Main interface
CNoAirPlay_MiddleManInterface                 // Non-AirPlay fallback
CHudiAP2Server                                // IAP2 server
CiAP2Session                                  // Session management
CHudiAP2Medium                                // Transport base
CHudiAP2Medium_USB                            // USB transport
CHudiAP2Medium_BT                             // Bluetooth transport
CHudiAP2Medium_WiFi                           // WiFi transport
```

### Message IDs
```c
kIAP2IdentifyInfoMsgID          // Device identification
kIAP2IdentifyRejectedMsgID      // Rejection response
kIAP2DeviceLanguageUpdateMsgID  // Language update
DeviceTimeUpdateMsgID           // Time sync
kIAP2CarPlayStartSession        // CarPlay session start
```

### Link Parameters Format
```
linkVersion: %d
maxOutstandingPackets: %d
cumulativeAckTimeout: %d
maxRetrans: %d
maxCumulativeAck: %d
maxRecvPacketLen: %d
retransTimeout: %d
```

### Device Paths
```
/dev/android_iap2         # USB IAP2 gadget device
/tmp/rfcomm_IAP2          # Bluetooth RFCOMM socket
```

---

## CarPlay/AirPlay Implementation

### Log Categories
```c
gLogCategory_AirPlayReceiverCore
gLogCategory_AirPlayReceiverServer
gLogCategory_AirPlayReceiverPlatform
gLogCategory_AirPlayReceiverEvents
gLogCategory_AirPlayReceiverStats
gLogCategory_AirPlayReceiverSessionScreenCore
gLogCategory_AirPlayReceiverSessionScreenFrames
gLogCategory_AirPlayPairServer
gLogCategory_AirPlayNTPClientCore
gLogCategory_AirPlayNTPClientStat
gLogCategory_AirPlayJitterBuffer
gLogCategory_CarPlayControlClient
gLogCategory_CarPlayDemoApp
gLogCategory_ScreenStream
gLogCategory_Screen
gLogCategory_AudioStream
gLogCategory_Pairing
gLogCategory_NetTransportChaCha20Poly1305
```

### Core Functions
```c
AirPlayReceiverServerSetProperty()
AirPlayReceiverServerControl()
AirPlayReceiverServerPlatformCopyProperty()
CarPlayControlClientStart()
CarPlayControlClientEventCallback()
CarPlayBonjourServiceCreate()
_CarPlayControllerCreate()
_CarPlayControllerActivateService()
_CarPlayControllerDeactivateService()
_CarPlayBonjourServiceResolveAddress()
_CarPlayControlClientSendCommand()
_CarPlayControlClientBrowseCallback()
```

### Pairing Endpoints
```
/pair-setup
/pair-verify
```

### HomeKit Integration
```c
_HandlePairVerifyHomeKitCompletion()
_requestProcessPairSetupHomeKit()
_requestProcessPairVerifyHomeKit()
```

---

## Crypto Implementation

### From libdmsdpcrypto.so

#### Key Exchange
```c
X25519()                        // Curve25519 DH
X25519_keypair()                // Generate keypair
X25519_public_from_private()    // Derive public key
```

#### Symmetric Encryption
```c
EVP_aes_128_gcm()              // AES-128-GCM
EVP_aes_256_gcm()              // AES-256-GCM
EVP_aes_128_cbc()              // AES-128-CBC
EVP_aes_256_cbc()              // AES-256-CBC
EVP_aes_128_ctr()              // AES-128-CTR
EVP_aes_256_ctr()              // AES-256-CTR
EVP_aes_128_ofb()              // AES-128-OFB
EVP_aes_256_ofb()              // AES-256-OFB
```

#### Hashing
```c
SHA256_Init()
SHA256_Update()
SHA256_Final()
```

#### Random
```c
RAND_bytes()
```

### From AppleCarPlay Binary

#### SRP (Secure Remote Password)
```c
kSRPParameters_3072_SHA512      // 3072-bit prime, SHA-512
kSRPHashDescriptor_SHA512
"SRP-6a client (tjw)"
"SRP-6a server (tjw)"
"SRP-6 server (tjw)"
```

#### Transport Encryption
```c
NetTransportChaCha20Poly1305
gLogCategory_NetTransportChaCha20Poly1305
```

#### Pairing Keys
```
Pair-Verify-ECDH-Salt
Pair-Verify-ECDH-Info
```

### From libauthagent.so

```c
PKCS5_PBKDF2_HMAC()            // Key derivation
EVP_aes_128_gcm()              // Encryption
EVP_aes_256_gcm()              // Encryption
```

---

## mDNS Services

### Service Types Advertised
```
_carplay-ctrl._tcp    # CarPlay control channel
_raop._tcp            # Remote Audio Output (AirPlay)
_airplay._tcp         # AirPlay discovery
_hap._tcp             # HomeKit Accessory Protocol
_mfi-config._tcp      # MFi configuration
_airport._tcp         # AirPort discovery
```

### Bonjour Functions
```c
DNSServiceReconfirmRecord()
TXTRecordGetBytesPtr()
TXTRecordGetValuePtr()
CarPlayBonjourServiceCreate()
_CarPlayBonjourServiceResolveAddress()
```

---

## Key Files and Paths

### Configuration
```
/etc/airplay.conf           # AirPlay configuration
/etc/box_name               # Device name
/etc/BoxSettings.json       # Box settings (OemName, etc.)
/etc/bluetooth/             # Bluetooth configuration
/etc/boa/images/carlogo.png # Car logo image
/etc/icon_*.png             # CarPlay icons
```

### Runtime State
```
/tmp/iphone_work_mode       # Current iPhone mode
/tmp/bluetooth_status       # BT connection state
/tmp/wifi_status            # WiFi state
/tmp/charge_mode            # Charging mode
/tmp/.mfi_auth_lock         # MFi auth mutex
/tmp/iap2transportnotify    # IAP2 transport state
/tmp/rfcomm_IAP2            # BT RFCOMM socket
```

### Authentication
```
/var/lib/lockdown/common.cert   # Certificates (plist)
/var/lib/lockdown/root_key.pem  # Root private key
/Library/Keychains/             # Keychain data
```

### Bluetooth
```
/etc/bluetooth/temp/addressme   # Local BT address
/etc/bluetooth/temp/addressit   # Remote BT address
```

### Logs
```
/tmp/userspace.log             # Application log
/tmp/ttyLog                    # Serial log
```

---

## Raspberry Pi Port Guide

### Hardware Requirements

| Component | Requirement |
|-----------|-------------|
| Pi Model | Pi 4 or Pi 5 (USB OTG capable) |
| USB | USB-C port in OTG/gadget mode |
| WiFi | Built-in or USB adapter |
| Bluetooth | Built-in or USB adapter |
| Storage | 8GB+ microSD |

### Software Components Needed

#### 1. USB Gadget (ConfigFS)
```sh
# Enable dwc2 overlay for OTG
dtoverlay=dwc2

# Load modules
modprobe libcomposite
modprobe usb_f_fs

# Create gadget via ConfigFS
mkdir /sys/kernel/config/usb_gadget/carplay
cd /sys/kernel/config/usb_gadget/carplay
echo 0x05ac > idVendor   # Apple VID
echo 0x12a8 > idProduct  # Apple PID (example)
```

#### 2. mDNS (Avahi)
```sh
apt install avahi-daemon
# Configure services for _raop._tcp, _carplay-ctrl._tcp
```

#### 3. Crypto Libraries
```sh
apt install libsodium-dev  # ChaCha20-Poly1305, X25519
apt install libssl-dev     # AES, SHA, SRP
```

#### 4. SRP-6a Implementation
- Use libsrp6a or implement per RFC 5054
- Parameters: 3072-bit prime, SHA-512

#### 5. AirPlay Receiver
- Adapt shairport-sync or UxPlay
- Implement CarPlay-specific extensions

#### 6. IAP2 Protocol Stack
- Implement based on RE findings
- Use libimobiledevice as reference

### Implementation Priority

1. **USB Gadget** - Emulate Apple device
2. **mDNS Services** - Device discovery
3. **SRP Pairing** - Authentication
4. **IAP2 Handler** - Protocol layer
5. **CarPlay Session** - Screen/audio streaming

---

## Current Focus (Dec 2025)

### Primary Goal: Protocol Command Discovery

**Objective**: Identify all undocumented message types and audio commands in the 0x55AA55AA protocol.

**Method**: Multi-source capture and analysis
- Adapter strace/memory dumps → `capture_scripts/adapter/raw_capture.sh`
- Pi-Carplay USB logs → `~/.pi-carplay/usb-logs/`
- Binary analysis → `analysis/analyze_binaries.py`
- Unified processing → `analysis/process_all_captures.py`

**Known Gaps**:
| Range | Status |
|-------|--------|
| Message Types 0x01-0xAA | 12 documented, unknown count undocumented |
| Audio Commands 0x01-0x10 | 16 documented, 0x0F and 0x11+ unknown |

### Key Binaries for Command Dispatch

| Binary | Function | Purpose |
|--------|----------|---------|
| `libdmsdp.so` | `DMSDPChannelHandleMsg` | Main message dispatcher |
| `libdmsdp.so` | `DMSDPChannelDealGlbCommand` | Global command handler |
| `libdmsdpaudiohandler.so` | `AudioBusinessControl` | Audio command dispatch |
| `AppleCarPlay.unpacked` | `_requestProcessCommand` | CarPlay control |

### Data Collection Pipeline

```
Adapter (lightweight) ──► Mac (processing)
     │                         │
     ├── strace raw hex        ├── Parse protocol magic
     ├── memory dumps          ├── Extract unknown values
     ├── usbmon packets        ├── Binary symbol analysis
     └── state snapshots       └── Generate findings
```

---

## Capture Analysis Findings (Dec 2025)

### Media Playback Capture (2025-12-29)

**Source**: Pi-Carplay USB capture + Adapter state snapshot

#### Message Types Found

| Type | Name | Count | Status |
|------|------|-------|--------|
| 0x01 | OPEN | 2 | ✅ Known |
| 0x02 | PLUGGED | 1 | ✅ Known |
| 0x03 | **UNKNOWN** | 2 | ❓ NEW - payload: uint32 (7, 8) |
| 0x05 | TOUCH | 28 | ✅ Known |
| 0x07 | AUDIO_DATA | 408 | ✅ Known |
| 0x08 | COMMAND | 16 | ✅ Known |
| 0x0D | BT_DEVICE_NAME | 1 | ✅ Known |
| 0x0E | WIFI_DEVICE_NAME | 1 | ✅ Known |
| 0x12 | BT_PAIR_STATUS | 2 | ✅ Known |
| 0x19 | BOX_SETTINGS | 5 | ✅ Known |
| 0x23 | **UNKNOWN** | 2 | ❓ NEW - payload: MAC address string |
| 0x24 | **UNKNOWN** | 1 | ❓ NEW - payload: MAC address string |
| 0x25 | **UNKNOWN** | 2 | ❓ NEW - empty payload (ACK?) |
| 0x26 | WIFI_STATE | 1 | ✅ Known |
| 0x2A | MEDIA_DATA | 66 | ✅ Known |
| 0x99 | SEND_FILE | 6 | ✅ Known |
| 0xAA | HEARTBEAT | 24 | ✅ Known |
| 0xBB | **UNKNOWN** | 1 | ❓ NEW - payload: uint32 (4) |
| 0xCC | SOFTWARE_VERSION | 1 | ✅ Known |

#### Newly Discovered Message Types

| Type | Hex | Payload | Likely Purpose |
|------|-----|---------|----------------|
| 0x03 | `03` | `07000000`, `08000000` | State/mode indicator? Values 7,8 |
| 0x23 | `23` | MAC addr string | Device address notification |
| 0x24 | `24` | MAC addr string | Alternative address type |
| 0x25 | `25` | Empty (len=0) | ACK/ping/status |
| 0xBB | `BB` | `04000000` | Configuration/status value |

#### Audio Commands - Complete Analysis (All 4 Scenarios)

| Cmd | Name | decode_types | audio_types | Scenarios |
|-----|------|--------------|-------------|-----------|
| 0x01 | OUTPUT_START | 4, 5 | 1, 2 | all |
| 0x02 | OUTPUT_STOP | 4, 5 | 1, 2 | nav, phone, siri |
| 0x03 | INPUT_START | 5 | 1 | phone, siri |
| 0x04 | INPUT_STOP | 5 | 1 | phone |
| 0x05 | PHONECALL_START | 5 | 1 | phone |
| 0x06 | PHONECALL_STOP | 2, 4 | 2 | nav |
| 0x07 | NAVI_START | 4 | 2 | nav |
| 0x08 | NAVI_STOP | 5 | 1 | siri |
| 0x09 | SIRI_START | 5 | 1 | siri |
| 0x0A | MEDIA_START | 4 | 1 | media, siri |
| 0x0B | MEDIA_STOP | 2, 4 | 1 | nav, phone, siri |
| 0x0C | ALERT_START | 4 | 1 | phone |
| 0x0D | ALERT_STOP | 4 | 1 | phone |
| 0x0E | INCOMING_CALL_INIT | 5 | 1 | phone |
| 0x10 | NAVI_COMPLETE | 4 | 2 | nav |

#### decode_type Semantics (VERIFIED Dec 2025)

| Value | Meaning | Sample Rate | Channels | Used By |
|-------|---------|-------------|----------|---------|
| 2 | Stop/cleanup | N/A | N/A | MEDIA_STOP, PHONECALL_STOP |
| 4 | Standard playback | 44.1/48 kHz | Stereo | MEDIA, NAVI, ALERT, OUTPUT |
| 5 | Voice/telephony | 16 kHz | Mono | SIRI, PHONECALL, INPUT |

**Note**: Previous definitions mapping decode_type to specific sample rates (1-7) were speculative and incorrect. Only values 2, 4, and 5 have been observed in actual captures.

#### audio_type Semantics (VERIFIED Dec 2025)

| Value | Meaning | Direction | Used By |
|-------|---------|-----------|---------|
| 1 | Main audio channel | IN | Media, alerts, Siri speech, phone call audio |
| 2 | Navigation channel (ducking) | IN | NAVI_START, NAVI_COMPLETE, nav OUTPUT |
| 3 | Microphone input | OUT | Siri listening, phone call mic |

**Note**: audio_type=3 was discovered through controlled capture analysis (Dec 2025). It only appears in OUT direction packets containing microphone PCM data.

**Conclusion**: All 15 audio commands (0x01-0x0E, 0x10) are now documented and verified through 21 controlled capture sessions across 7 scenarios. See `docs/protocol/AUDIO_PROTOCOL.md` for complete reference.

---

## Open Questions

### Active Investigation

1. **New Message Types (from capture)**
   - 0x03: State indicator? Seen with values 7, 8
   - 0x23/0x24: MAC address messages - what triggers them?
   - 0x25: Empty payload ACK - what does it acknowledge?
   - 0xBB: Status with value 4 - meaning unknown

2. **DMSDP Opcodes**
   - Complete command list needed
   - `DMSDPChannelHandleMsg` switch table analysis required

3. **Command Dispatch Tables**
   - Compiled into switch statements
   - Need radare2/Ghidra analysis of key functions

### Planned: Autokit Encryption Session (Requires RPi + Android + Autokit APK)

**Objective**: Capture adapter-side logs during Autokit session to understand encryption handshake.

**Setup Required**:
- Raspberry Pi running Android (LineageOS or similar)
- Official Autokit APK installed
- SSH access to adapter for ttyLog capture

**Commands Autokit Sends (that open source doesn't)**:

| Command | Purpose | Investigation Goal |
|---------|---------|-------------------|
| `CMD_APP_INFO` | Full app identification (version, uuid, huid) | Enables richer BOX_INFO response |
| `CMD_ENABLE_CRYPT` | Enable USB encryption with seed | Understand key derivation |
| `CMD_CAR_MANUFACTURER_INFO` | OEM identification | What features does this unlock? |
| Icon uploads (102KB) | Car logo for CarPlay UI | Optional branding |

**Encryption Details to Capture**:
```
CMD_ENABLE_CRYPT: <seed_value>  (e.g., 1829253497)

Algorithm: AES-128-CTR (from libdmsdp.so)
Functions:
  - DMSDPNetworkSessionStartCrypto()
  - DMSDPCryptoEncryptData() / DMSDPCryptoDecryptData()
  - g_dmsdpCryptoAlgAes128Ctr
```

**Capture Plan**:
1. Start `tail -f /dev/ttyFIQ0` or equivalent ttyLog on adapter
2. Connect RPi with Autokit to adapter
3. Capture full session including:
   - CMD_APP_INFO JSON payload
   - CMD_ENABLE_CRYPT seed value
   - CMD_BOX_INFO full response (with GNSS, Dashboard, etc.)
   - Any encrypted packet patterns in strace

**Key Questions**:
- How is the seed transformed into AES key?
- Does encryption affect video/audio latency?
- What additional CMD_BOX_INFO fields appear?
- Is `GNSSCapability: 7` used for anything?

**BOX_TMP_DATA_AUDIO_TYPE Bitmask** (from Autokit session):
| Value | Meaning |
|-------|---------|
| 0x0001 | Phone call active |
| 0x0002 | Navigation (ducking) |
| 0x0004 | Siri active |
| 0x0100 | Media stopped |
| 0x0110 | Media playing |
| 0x0401 | Phone + mic recording |
| 0x0504 | Siri + output active |

---

## Autokit Session Analysis (Dec 2025)

**Session Date**: 2025-12-29
**Setup**: Raspberry Pi running Android + Autokit APK → CPC200-CCPA adapter
**Captures**: `captures/adapter/ttyLog/`, `captures/adapter/autokit_andoirdAuto_fresh_paring_*/`

### Encryption Handshake (CMD_ENABLE_CRYPT)

Autokit sends encryption seeds during initialization:

| Session | Seed Value | Hex |
|---------|------------|-----|
| CarPlay Fresh Pair | 1829253497 | `6D009C89` |
| Android Auto Session | Various | Session-dependent |

**Key Derivation**: Seed → AES-128-CTR key via `DMSDPNetworkSessionStartCrypto()`

### Protocol Commands Discovered

| Command | Purpose | Payload Example |
|---------|---------|-----------------|
| `CMD_APP_INFO` | App identification | `{version, uuid, huid}` |
| `CMD_ENABLE_CRYPT` | Enable USB encryption | Uint32 seed |
| `CMD_CAR_MANUFACTURER_INFO` | OEM data | 8 bytes |
| `CMD_APP_SET_BOX_CONFIG` | Configuration push | JSON payload |

### PhoneCommand IDs (from ttyLog)

| ID | Name | Context |
|----|------|---------|
| 500 | PH_CMD_500 | Unknown |
| 501 | PH_CMD_501 | Unknown |
| 502 | PH_CMD_502 | Unknown |
| 507 | PH_CMD_507 | Unknown |

---

## Android Auto Protocol Findings

### Connection Architecture

```
Phone ←─BT─→ Adapter (AAP RFCOMM) ──WiFi handoff──→ Port 54321 (SSL/TLS)
```

### Key Log Sequences

**Bluetooth AAP Discovery**:
```
Bluetooth StartListen AAP!!!
BoxRFCOMMService write data, dataLen: 52, channel:2
```

**WiFi Handoff** (Port 54321):
```
[ANDROID_AUTO] TCP server started: 54321
SSLCreate OK
SSL_accept OK, sslfd: 9
```

### AudioWorkMode / iPhoneWorkMode

| Mode | Value | Daemon Started |
|------|-------|----------------|
| iPhoneWorkMode | 0 | CarPlay |
| AndroidWorkMode | 1 | Android Auto (`AndroidAuto` daemon) |

**Transition Log**:
```
OnAndroidWorkModeChanged: 0 → 1
Start Link Deamon: AndroidAuto
```

---

## Android Auto Fresh Pairing Investigation

### The Problem

Open-source projects (Carlink, Pi-Carplay) can connect to Android phones **only after** the adapter has been paired via Autokit first. Fresh/initial pairing fails.

### Symptoms

1. ✅ Phone sees adapter in Bluetooth scan
2. ✅ Bluetooth SSP pairing prompt appears
3. ✅ Pairing completes successfully
4. ❌ **Android Auto session does NOT start**

### Root Cause Analysis

**Adapter-side pairing acceptance** (from ttyLog):
```
RiddleBluetoothService_Interface_Control: 4096  ← SSP pairing request
RiddleBluetoothService_Interface_Control: 8192  ← Auto-accept
BondingCreated, accept! AAP  ← Pairing successful
```

**The gap**: After pairing, the adapter must:
1. Start RFCOMM listener (`Bluetooth StartListen AAP!!!`)
2. Exchange WiFi credentials via `BoxRFCOMMService`
3. Initiate TCP connection to phone port 54321
4. Complete SSL/TLS handshake

### AndroidWorkMode File Upload

**What Autokit does**:
```
UPLOAD FILE: /etc/android_work_mode, 4 byte
```
This triggers: `OnAndroidWorkModeChanged: 0 → 1`

**What Pi-Carplay does**: Sends `androidWorkMode` via `SendBoolean()` to `FileAddress.ANDROID_WORK_MODE = '/etc/android_work_mode'` **BUT only if explicitly enabled in config**.

### AndroidWorkMode Dynamic Toggle Behavior

**Key Discovery**: Autokit dynamically toggles `AndroidWorkMode` - it's NOT a one-time setting.

| Event | Who Does It | AndroidWorkMode |
|-------|-------------|-----------------|
| App connects | **Autokit sends** file upload | `0 → 1` |
| Phone disconnects | **Firmware resets** automatically | `1 → 0` |
| App reconnects | **Autokit sends** file upload again | `0 → 1` |

**Evidence from ttyLog** (`adapter_tty_143842_29DEC25.log`):
```
Line 56:  OnAndroidWorkModeChanged: 1 0    ← Reset at session start
Line 225: UPLOAD FILE: /etc/android_work_mode
Line 230: OnAndroidWorkModeChanged: 0 1    ← Enabled
Line 890: OnAndroidWorkModeChanged: 1 0    ← Reset on disconnect
Line 1080: UPLOAD FILE: /etc/android_work_mode
Line 1085: OnAndroidWorkModeChanged: 0 1   ← Re-enabled
```

**Implication**: The adapter firmware automatically resets `AndroidWorkMode` to 0 when a phone disconnects. Any host app (Autokit, Pi-Carplay) must re-send `android_work_mode=1` on **every** connection to enable the Android Auto daemon.

### Pi-Carplay `androidWorkMode` Analysis

**File**: `/Users/zeno/Downloads/misc/pi-carplay-4.1.3/src/main/carplay/driver/DongleDriver.ts`

**Critical Finding**: `androidWorkMode` is **NOT enabled by default**.

```typescript
// Line 30 - Optional parameter
export type DongleConfig = {
  androidWorkMode?: boolean  // ← OPTIONAL, defaults to undefined
  // ...
}

// Lines 55-81 - DEFAULT_CONFIG
export const DEFAULT_CONFIG: DongleConfig = {
  width: 800,
  height: 480,
  fps: 60,
  // ... androidWorkMode is MISSING
}

// Lines 231-232 - Only sent if truthy
if (cfg.androidWorkMode)
  messages.push(new SendBoolean(cfg.androidWorkMode, FileAddress.ANDROID_WORK_MODE))
```

**Impact**: With default config, Pi-Carplay **never** sends the `android_work_mode` file, leaving the adapter in CarPlay-only mode.

### Hypothesis: Missing Initialization Steps

Even with `androidWorkMode: true`, Pi-Carplay may be missing:

1. **CMD_ENABLE_CRYPT** - Encryption handshake
2. **CMD_APP_INFO** - Full app identification
3. **Timing/ordering** of initialization commands

### riddle.conf State After Autokit

**File**: `captures/adapter/autokit_andoirdAuto_fresh_paring_20251230_074618/state/riddle.conf`

```json
{
  "AndroidWorkMode": 1,
  "DevList": [{
    "id": "DE:AD:BE:EF:00:06",
    "name": "User",
    "type": "CarPlay"
  }],
  "LastConnectedDevice": "DE:AD:BE:EF:00:06"
}
```

Note: `AndroidWorkMode` persists as `1` in riddle.conf after Autokit sets it.

### Fresh Pairing Test Results (Dec 2025)

**Test Setup**:
- Adapter reset (empty `DevList: []`)
- Pi-Carplay with `androidWorkMode: true` enabled
- Pixel 10 phone (attempted to clear Bluetooth/AA saved data)

**Results**:

| Step | Status | Evidence |
|------|--------|----------|
| Adapter DevList empty | ✅ Confirmed | `DevList : []` in ttyLog |
| SSP pairing prompt | ✅ Appeared | `passkey=845100` |
| BondingCreated | ✅ Success | `BondingCreated DE:AD:BE:EF:00:07` |
| AAP RFCOMM accept | ✅ Success | `accept! AAP` |
| Android Auto auth | ✅ Success | `Auth completed.` (2037+51 bytes) |
| Session started | ✅ Success | `Discovery: Google Pixel 10` |

**Caveat - Android Caching Issue**:

The Pixel phone **initiated** the connection (`hci accept conn req` = incoming), suggesting it may have retained cached data despite clearing Bluetooth/AA settings. Android does not reliably clear:
- Bluetooth link keys
- Android Auto saved car data
- Connection history

**Conclusion**:
- Pi-Carplay with `androidWorkMode: true` **CAN** complete Android Auto pairing
- Whether it works for a phone that has **truly never** seen the adapter remains unconfirmed
- Android's caching behavior prevents definitive "fresh pairing" testing without root access

### Remaining Investigation

1. ~~Test Pi-Carplay with explicit `androidWorkMode: true`~~ ✅ Done
2. Capture `CMD_APP_INFO` payload from Autokit (for completeness)
3. Test with a phone that has **never** connected to this adapter MAC address

---

## Pi-Carplay Android Auto Session Capture (Dec 2025)

**Session Date**: 2025-12-29/30
**Setup**: Pi-Carplay (modified with `androidWorkMode: true`) → CPC200-CCPA → Pixel 10
**Note**: Used existing Autokit pairing, not fresh pairing

### Session Initialization

**CMD_BOX_INFO sent by Pi-Carplay**:
```json
{
  "mediaDelay": 300,
  "syncTime": 1767055652,
  "androidAutoSizeW": 800,
  "androidAutoSizeH": 480,
  "WiFiChannel": 36,
  "mediaSound": 1,
  "callQuality": 1,
  "autoPlay": false,
  "autoConn": true,
  "wifiName": "carlink_test",
  "btName": "carlink_test"
}
```

### Android Auto Protocol Details

**Protocol Version**: 1.7

**Connection Sequence**:
```
1. Bluetooth RFCOMM connect (AAP service)
2. Auth handshake (2037 + 51 bytes)
3. Discovery: device name, brand, icons
4. Video/Audio channel setup
5. Audio focus requests
```

**Key Log Entries**:
```
[AndroidAutoEntity]: version response, version: 1.7, status: 0
[AndroidAutoEntity]: Begin handshake.
[AndroidAutoEntity]: Handshake, size: 2037
[AndroidAutoEntity]: Auth completed.
[AndroidAutoEntity]: Discovery request, device name: Android, brand: Google Pixel 10
```

### Audio Commands (Android Auto)

**Format**: Same 13-byte payload as CarPlay

| Payload Hex | decode | vol | audio | cmd | Meaning |
|-------------|--------|-----|-------|-----|---------|
| `02 00 00 00 00 00 00 00 01 00 00 00 0b` | 2 | 0.0 | 1 | 0x0B | MEDIA_STOP |
| `04 00 00 00 00 00 00 00 01 00 00 00 0a` | 4 | 0.0 | 1 | 0x0A | MEDIA_START |
| `04 00 00 00 00 00 00 00 01 00 00 00 01` | 4 | 0.0 | 1 | 0x01 | OUTPUT_START |
| `04 00 00 00 00 00 00 00 01 00 00 00 02` | 4 | 0.0 | 1 | 0x02 | OUTPUT_STOP |
| `05 00 00 00 00 00 00 00 01 00 00 00 01` | 5 | 0.0 | 1 | 0x01 | OUTPUT_START (mic) |
| `05 00 00 00 00 00 00 00 01 00 00 00 08` | 5 | 0.0 | 1 | 0x08 | NAVI_STOP (mic) |

**Key Differences from CarPlay**:
| Aspect | CarPlay | Android Auto |
|--------|---------|--------------|
| Volume field | Often 1.0 (`3f800000`) | Always 0.0 (`00000000`) |
| audio_type | 1 (main) or 2 (navi ducking) | Always 1 (main only) |
| Command IDs | 0x01-0x0E, 0x10 | Same IDs observed |
| Navigation ducking | Explicit audio_type=2 | Not observed |

### Video Format (Android Auto)

**Same 20-byte header as CarPlay**:
```
Offset 0-3:   Width (LE)    - 0x0320 = 800
Offset 4-7:   Height (LE)   - 0x01e0 = 480
Offset 8-11:  Format/flags  - 0x03
Offset 12-19: Timestamp + padding
Offset 20+:   H.264 NAL data
```

**H.264 Codec Info** (from first I-frame):
```
SPS NAL: 67 42 40 1f - Profile: Baseline, Level: 3.1
PPS NAL: 68 ca 8f 20
```

### MediaData Format (Android Auto)

**Song/Album Info** (subtype 0x01):
```json
{
  "MediaAPPName": "YouTube Music",
  "MediaSongName": "Poltergeist - LOLNEIN",
  "MediaArtistName": "LOLNEIN",
  "MediaAlbumName": "LOLNEIN",
  "MediaSongDuration": 171000,
  "MediaSongPlayTime": 0
}
```

**Album Art** (subtype 0x02): PNG format, ~39KB

### Audio Focus Types

From ttyLog:
```
[AndroidAutoEntity]: requested audio focus, type: 1  ← Media
[AndroidAutoEntity]: requested audio focus, type: 4  ← System/UI sounds
[AndroidAutoEntity]: audio focus state: 1            ← Focus granted
[AndroidAutoEntity]: audio focus state: 3            ← Focus transient
```

### Protocol Comparison Summary

| Feature | CarPlay | Android Auto |
|---------|---------|--------------|
| Transport | USB/WiFi (RTSP) | BT RFCOMM + WiFi |
| Auth | IAP2 + SRP | Handshake (2037+51 bytes) |
| Protocol version | N/A | 1.7 |
| Video codec | H.264 | H.264 |
| Video header | 20 bytes | 20 bytes (identical) |
| Audio commands | 13-byte payload | 13-byte payload (same) |
| Audio ducking | audio_type=2 | Not observed |
| Volume control | In packet | Always 0.0 |
| MediaData | JSON + artwork | JSON + artwork (same) |
| Message types | 0x55AA55AA | 0x55AA55AA (same) |

---

### Completed

1. ✅ **IAP2 Packet Format** - Documented in protocol tables
2. ✅ **USB Descriptors** - Extracted from gadget config
3. ✅ **Network Capture** - RTSP handshakes captured
4. ✅ **Video Format** - H.264 with 20-byte header documented
5. ✅ **Message Types** - 5 new types identified (0x03, 0x23, 0x24, 0x25, 0xBB)
6. ✅ **Audio Commands** - All 15 commands (0x01-0x0E, 0x10) documented
7. ✅ **decode_type Semantics** - 2=stop, 4=standard playback, 5=voice/telephony
8. ✅ **audio_type Semantics** - 1=main, 2=navigation (ducking), 3=microphone (OUT)
9. ✅ **Autokit Session Capture** - Encryption seeds, protocol commands documented
10. ✅ **Android Auto Protocol** - WiFi handoff on port 54321, SSL/TLS
11. ✅ **Pi-Carplay androidWorkMode** - NOT enabled by default in DEFAULT_CONFIG
12. ✅ **Pi-Carplay AA Session** - Audio/video/config captured and compared to CarPlay
13. ✅ **AA Protocol Version** - Version 1.7 with 2037+51 byte handshake
14. ✅ **AA vs CarPlay Comparison** - Same video header (20 bytes), same audio commands (13 bytes)

### Data Collection Methods

| Method | Script | Output |
|--------|--------|--------|
| Adapter strace | `adapter/raw_capture.sh` | Syscall hex data |
| Pi-Carplay USB | Manual run | `~/.pi-carplay/usb-logs/` |
| Binary analysis | `analyze_binaries.py` | Constants, symbols |
| Memory scan | `process_all_captures.py` | Protocol messages |

---

## Tools Used

- **radare2** (`/opt/homebrew/bin/r2`) - Binary analysis
- **strings** - String extraction
- **file** - Binary identification
- **openssl** - Certificate parsing
- **hexdump** - Binary inspection
- **Patched UPX** (ludwig-v) - Binary unpacking

---

## References

- ludwig-v/wireless-carplay-dongle-reverse-engineering
- libimobiledevice project
- shairport-sync (AirPlay)
- UxPlay (AirPlay mirroring)
- node-carplay

---

## File Inventory

### Extracted from Device

```
/Users/zeno/Downloads/adapter/
├── unpacked/
│   ├── AppleCarPlay.unpacked      (557KB)
│   ├── ARMiPhoneIAP2.unpacked     (494KB)
│   ├── ARMadb-driver.unpacked     (469KB)
│   ├── ARMHiCar.unpacked          (132KB)
│   ├── bluetoothDaemon.unpacked   (396KB)
│   ├── mdnsd.unpacked             (378KB)
│   └── lib/                       (all .so files)
├── memdump/
│   ├── *_exe                      (memory dumps)
│   └── *_maps.txt                 (memory maps)
├── sftp_extract_rootfs/
│   ├── usr/lib/                   (libraries)
│   ├── var/lib/lockdown/          (certificates)
│   └── tmp/*.ko                   (kernel modules)
└── github_extracted_rootfs/       (firmware extract)
```

---

*Document generated: 2025-12-27*
*Analysis by: Claude Code (Opus 4.5)*

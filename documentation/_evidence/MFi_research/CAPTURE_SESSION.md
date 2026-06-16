# CPC200-CCPA — Live CarPlay Pairing Capture Session

**Live working doc.** Survives context compaction; any session can resume from here.

- **Status:** ✅ COMPLETE — capture run + fully analysed. See `capture/carplay-20260521-101016/ANALYSIS.md`.
- **Started:** 2026-05-21   **Last updated:** 2026-05-21
- **Companion docs:** `README.md`, `docs/findings.md`, `docs/register_map.md`, `docs/firmware_internals.md`, `docs/ic_security_analysis.md`, `docs/build_and_verify.md`

---

## 1. Objective

Capture the raw communication of a **fresh wireless CarPlay pairing** between an iPhone and the
CPC200-CCPA adapter, across simultaneous streams, so the iAP2 handshake + MFi authentication +
AirPlay bring-up can be analysed offline.

---

## 2. Capture architecture (as built)

| Stream | Tool | What it gets |
|---|---|---|
| **WiFi / IP** | `pktcap` → `wifi.pcap` | AF_PACKET on `wlan0`; AirPlay/RTSP, mDNS, the whole iPhone↔adapter IP flow |
| **Bluetooth HCI** | `hcicap` → `bt.pcap` | kernel HCI monitor channel; the iAP2-over-RFCOMM handshake **incl. MFi auth** |
| **Firmware log** | `tail`/`cp` → `ttyLog.txt` / `ttyLog.full` | `/tmp/ttyLog` runtime events, incl. the firmware's own MFi log lines |

All three are standard formats: `wifi.pcap` = pcap DLT_EN10MB, `bt.pcap` = pcap
DLT_BLUETOOTH_HCI_H4_WITH_PHDR (201) — both open directly in Wireshark.

### MFi authentication coverage — important

A register-level **MFi I2C trace is NOT captured**, by necessity:
- This firmware's **kernel rejects `ptrace` with `EINVAL`** for every request, kernel-wide
  (verified: fails even attaching to a self-spawned `sleep`; no yama; nothing else tracing the
  target). Carlinkit anti-RE hardening (consistent with their known "blocked strace").
- There is **no ftrace** (`/sys/kernel/debug/tracing` absent) → no i2c tracepoints.
- So `/dev/i2c-1` cannot be snooped in-place. The `ptrace`-based `i2cspy` tool was built and
  works as code but cannot run here — kept as a documented artifact (`src/i2cspy.c`, `bin/i2cspy`).

**MFi auth is still captured** — the cryptographic material rides the wire:
- The **945-byte cert, 20-byte challenge and 128-byte RSA signature** travel over Bluetooth
  RFCOMM inside **iAP2 messages `0xAA00`–`0xAA05`** → present in `bt.pcap`.
- The firmware prints MFi events to `ttyLog` (`mfi ic is from APPLE`, `Cache MFI CERT ...`).
- The chip itself is static and already fully dumped — see `dumps/`, `docs/register_map.md`.

The only un-captured detail is SoC↔chip register *timing*, and that register protocol is already
fully reverse-engineered in `docs/register_map.md`. Optional way to get a live register trace:
an `LD_PRELOAD` ioctl/read/write shim, which needs `ARMiPhoneIAP2` restarted with the preload
set (more invasive — not done; available on request).

---

## 3. Environment

### Adapter (CPC200-CCPA / A15W)
- **SSH:** `sshpass -p '' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no root@192.168.43.1`
  (Mac must be joined to the adapter's WiFi AP. Never use `BatchMode=yes`.)
- i.MX6UL Cortex-A7 ARMv7-A hard-float, 128 MB RAM, Linux **3.14.52** (custom Carlinkit build).
- rootfs 12.5 MB @ 89% — do not write there. `/tmp` = tmpfs (volatile). **`/mnt/UPAN`** = 14 GB
  USB stick = work + deploy area. Capture dir: `/mnt/UPAN/cap/`, outputs in `/mnt/UPAN/cap/out/`.
- WiFi `wlan0` (Marvell mwifiex; adapter is the AP). BT `hci0`. MFi chip `/dev/i2c-1` addr 0x11.
- CarPlay daemons run from `/tmp/bin/`; `AppleCarPlay` spawns only when an iPhone connects.

### Mac
- arm64, macOS 26.5. Tools: `brew`, `lima`, `qemu`, `clang`, `sshpass`, `tcpdump`.
- Cross-toolchain: **`armv7-unknown-linux-musleabihf`** (musl, messense brew tap) — musl is
  required (glibc toolchains fail "kernel too old" on Linux 3.14).
- lima VM `cpc200build` (Ubuntu 25.10 aarch64) is up — available for heavy autotools builds;
  not needed for the current tools (all single-file, built directly with the musl gcc).
- **Working dir:** `/Users/zeno/Documents/carlink/MFi_research/`

---

## 4. Build & run plan

- [x] **P0** Read prior MFi research
- [x] **P1** Install `armv7-unknown-linux-musleabihf` toolchain
- [x] **P2** lima VM up (kept available; not on the critical path)
- [x] **P3** Build capture tools — `pktcap`, `hcicap` (musl-static ARMv7) — built & verified
- [x] **P4** `i2cspy` written/built — but unusable (kernel blocks ptrace); shelved
- [x] **P5** Capture orchestration — `src/cap_adapter.sh` + `run_capture.sh`
- [x] **P6** Deploy to `/mnt/UPAN/cap/` + smoke-test — wifi/bt/ttyLog all verified
- [x] **P7** Run full capture during a fresh CarPlay pairing — `capture/carplay-20260521-101016/`
- [x] **P8** Retrieve & analyse — `capture/carplay-20260521-101016/ANALYSIS.md`

---

## 5. How to run a capture

From the Mac, in this directory:

```bash
./run_capture.sh            # adapter defaults to 192.168.43.1
```

It deploys the tools, offers to clear the adapter pairing record (for a true fresh pair-setup),
starts all streams, waits for you to do the pairing, then stops and pulls everything to
`capture/carplay-<timestamp>/`.

**For a fresh pair-setup** (not a cached re-verify):
1. Let `run_capture.sh` clear `/Library/Keychains/default.keychain` (answer `y`), AND
2. On the iPhone: Settings → General → CarPlay → select this car → **Forget This Car**.
3. Then initiate wireless CarPlay from the iPhone when the script prompts.

Manual control (if not using `run_capture.sh`):
`ssh root@192.168.43.1 /mnt/UPAN/cap/cap_adapter.sh start | stop | status`

---

## 6. Tools & files

| File | Role |
|---|---|
| `src/pktcap.c` → `bin/pktcap` | AF_PACKET → pcap (WiFi) |
| `src/hcicap.c` → `bin/hcicap` | HCI monitor channel → pcap DLT 201 (Bluetooth) |
| `src/i2cspy.c` → `bin/i2cspy` | ptrace MFi-I2C tracer — built, but kernel blocks ptrace; shelved |
| `src/cap_adapter.sh` | runs on the adapter; start/stop the 3 streams (setsid-detached) |
| `run_capture.sh` | Mac-side orchestrator: deploy → start → (pairing) → stop → retrieve |
| `bin/i2c{detect,dump,get,set,transfer}` | prior i2c-tools (musl-static) — chip interrogation |
| `mfi_dump.sh` / `mfi_compare.sh` / `push_tools.sh` | prior MFi chip-dump tooling |

Capture output → `capture/carplay-<timestamp>/` (Mac).
Adapter-side staging → `192.168.43.1:/mnt/UPAN/cap/`.

---

## 7. How to resume this session

1. Read this file, then `README.md` + `docs/` here.
2. Re-join the adapter WiFi AP; re-establish SSH (§3).
3. Checkboxes in §4 show progress; in-conversation `TaskList` mirrors it.
4. If P7 not done: run `./run_capture.sh`. If done: captures are in `capture/`; do P8 analysis.

---

## 8. Progress log

### 2026-05-21
- Read all prior MFi research. Recon: adapter has AF_PACKET + HCI raw/monitor sockets;
  **no ftrace**; WiFi is Marvell; `/mnt/UPAN` is the work area.
- Installed musl toolchain; brought up lima VM `cpc200build`.
- Wrote + cross-built `pktcap`, `hcicap`, `i2cspy` (musl-static ARMv7).
- **Finding: kernel blocks `ptrace` (EINVAL, kernel-wide).** `i2cspy` cannot run → shelved.
  Pivoted MFi capture to the BT stream (iAP2 0xAA0x) + ttyLog.
- `hcicap` v1 (HCI_CHANNEL_RAW) was flaky → rewrote on HCI_CHANNEL_MONITOR (reliable).
- Wrote `cap_adapter.sh` (setsid-detached, 3 streams) + `run_capture.sh`.
- Deployed to `/mnt/UPAN/cap/`; smoke-test passed: wifi.pcap 105 pkts, bt.pcap 68 HCI pkts,
  ttyLog captured. Pipeline ready.
- Ran a full capture during a fresh wireless CarPlay pairing (adapter keychain cleared first):
  `capture/carplay-20260521-101016/` — wifi.pcap 9 MB/10,544 pkts, bt.pcap 666 HCI pkts,
  ttyLog 1,468 lines. Pairing succeeded; CarPlay went active.
- Analysed — full handshake decoded → `capture/carplay-20260521-101016/ANALYSIS.md`. Resolved:
  RTSP port = **5000**; wireless CarPlay does `/pair-setup`×3 + `/pair-verify`×2 (HomeKit) on
  the AirPlay channel; **no FairPlay**; MFi chip exercised **twice** (iAP2 `0xAA0x` + AirPlay
  auth-setup). Captured the 20-byte challenge, both 128-byte signatures, the 945-byte cert.
- **SESSION COMPLETE.**
- Added §9 — head-unit capability configuration & advertisement engineering reference
  (derived from `carplay-20260521-101016` + binary RE + on-device struct dump).

---

# 9. Head-unit capability configuration & advertisement — engineering reference

How the head-unit / vehicle capabilities (resolution, FPS, audio, input devices, drive side,
GPS/cluster) are configured on the adapter and advertised to the iPhone. Two stages:
**host app → adapter** (USB `0x55AA55AA` bulk protocol), then **adapter → iPhone** (iAP2, then
AirPlay). Evidence: capture `carplay-20260521-101016/ttyLog.txt` + `ARMadb-driver`,
`AppleCarPlay`, `ARMiPhoneIAP2` binary RE + live struct dump (2026-05-21).

```
Carlink app ──USB 0x55AA55AA──▶ ARMadb-driver ──▶ /etc/riddle.conf + /etc/RiddleBoxData/HU_*
                                                        │  MiddleMan IPC (AF_UNIX, RiddleLinktype)
                          ┌─────────────────────────────┴───────────────┐
                   ARMiPhoneIAP2  ── iAP2 0x1D01 over BT RFCOMM      AppleCarPlay ── AirPlay SETUP
                          ▼                                                 ▼      over RTSP :5000
                   iPhone: transports / vehicle / msg-IDs      iPhone: display geometry / audio / HID
```

## 9.1 Stage 1 — host app → adapter

### 9.1.1 `Open` message — USB type `0x01`

16-byte USB frame header `[magic 0x55AA55AA][length 0x0000001C][type 0x00000001][check 0xFFFFFFFE]`
followed by a **28-byte payload, 7 × uint32 little-endian**:

| Offset | Field | Capture value |
|--------|-------|---------------|
| 0x00 | `width` | 2400 |
| 0x04 | `height` | 960 |
| 0x08 | `fps` | 60  (← `riddleBoxCfg CustomFrameRate`) |
| 0x0C | `format` | video format ID — `1` = basic IDR, `5` = full H.264 / aggressive IDR |
| 0x10 | `packetMax` | max packet size (e.g. 0xC000) |
| 0x14 | `boxVersion` | protocol version (2) |
| 0x18 | `phoneMode` | iPhone work mode — `2` = CarPlay |

- Handler: `ARMadb-driver` `ProceessCmdOpen` (`fcn.00021cb0`, entry `0x22098`); debug fmt `@0x5e67f`.
- Re-sent every session (not persistent).
- **Side effect:** the handler compares Open `width`/`height` to the stored `HU_VIEWAREA_INFO`;
  if they differ it **auto-rewrites `HU_VIEWAREA_INFO` full-screen**. It does NOT touch
  `HU_SAFEAREA_INFO`. It then broadcasts the *phone's* resolution back to the host as type `0x1E`
  (`RemoteCxCy`).
- Live evidence: `ttyLog.txt:64` `[iAP2] Recv start linkParam: 2400, 960, 60, 2`;
  `ttyLog.txt:821` `recv CarPlay size info:2400x960`.

### 9.1.2 `BoxSettings` message — USB type `0x19` (JSON)

Header `[magic][length][type 0x19][check 0xFFFFFFE6]` + JSON body. Parsed by `ARMadb-driver`
`FUN_00016c20` (dispatched from `FUN_0001dd98`; same parser serves cmd `0xA2`
`CMD_APP_SET_BOX_CONFIG`). Generic path `FUN_0001658c` walks a **29-entry field→key table
@ `0x93f90`**: cJSON string → `SetBoxConfigStr`, number → `SetBoxConfig` → `/etc/riddle.conf`.

| # | JSON field | riddle.conf key | Capability effect |
|---|---|---|---|
| 0 | `btName` | CustomBluetoothName | BT name (⚠ popen cmd-injection) |
| 1 | `wifiName` | CustomWifiName | WiFi SSID (⚠ cmd-injection) |
| 2 | `fps` | CustomFrameRate | → `Open` fps field |
| 3 | `gps` | HudGPSSwitch | GPS/dashboard enable |
| 4 | `lang` | BoxConfig_UI_Lang | UI language |
| 5 | `bgMode` | BackgroundMode | connection-UI visibility |
| 6 | `syncMode` | iAP2TransMode | iAP2 framing mode |
| 7 | `startDelay` | BoxConfig_DelayStart | USB init delay |
| 8 | `mediaDelay` | MediaLatency | audio buffer ms |
| 9 | `mediaSound` | MediaQuality | 0=44.1 kHz, 1=48 kHz PCM |
| 10 | `autoConn` | NeedAutoConnect | auto-reconnect |
| 11 | `androidWorkMode` | AndroidWorkMode | also `fwrite /etc/android_work_mode` (0..5) |
| 12 | `drivePosition` | CarDrivePosition | 0=LHD, 1=RHD |
| 13 | `echoDelay` | EchoLatency | WebRTC AEC delay |
| 14 | `androidAutoSizeW` | AndroidAutoWidth | AA video width |
| 15 | `androidAutoSizeH` | AndroidAutoHeight | AA video height |
| 16 | `screenPhysicalW` | ScreenPhysicalW | physical mm → CarPlay DPI |
| 17 | `screenPhysicalH` | ScreenPhysicalH | physical mm → CarPlay DPI |
| 18 | `brand` | CarBrand | OEM brand (special handler `FUN_00068218`: rewrites airplay.conf + logo) |
| 19 | `ScreenDPI` | ScreenDPI | CarPlay render density |
| 20 | `boxName` | CustomBoxName | device display name |
| 21 | `WiFiChannel` | WiFiChannel | adapter AP channel (→ `0x5703 WifiConfigInfo`) |
| 22 | `UseBTPhone` | UseBTPhone | route calls via BT-HFP |
| 23 | `HiCarConnectMode` | HiCarConnectMode | HiCar mode |
| 24 | `GNSSCapability` | GNSSCapability | GPS capability advertised |
| 25 | `AutoResetUSB` | AutoResetUSB | USB reset on disconnect |
| 26 | `DashboardInfo` | DashboardInfo | cluster/dashboard capability bitmask |
| 27 | `DayNightMode` | DayNightMode | day/night mode |
| 28 | `DockPosition` | DuckPosition (fw typo) | copies `HU_SCREEN_INFO` → `HU_VIEWAREA_INFO` |

**Special handlers** (intercepted before the table, NOT stored in riddle.conf):

| JSON field | Target | Mechanism |
|---|---|---|
| `syncTime` | system clock | `settimeofday(val + 28800)` — hardcoded UTC+8 |
| `mediaVol`/`callVol`/`speechVol`/`ringVol`/`navVol`/`otherVol` | `HU_AUDIOVOLUME_INFO[0..5]` | shared memory |
| `naviScreenInfo{width,height,fps}` | `HU_NAVISCREEN_INFO` (24 B) | shared memory — enables CarPlay nav/cluster video (USB type `0x2C`) |
| `naviScreenInfo.safearea{width,height,x,y,outside}` | `HU_NAVISCREEN_SAFEAREA_INFO` (20 B) + `HU_NAVISCREEN_VIEWAREA_INFO` (24 B) | shared memory |

**There is no BoxSettings field for the main-screen SafeArea** — `HU_SAFEAREA_INFO` is only
settable via `SendFile` (§9.1.3) or SSH.

### 9.1.3 `SendFile` message — USB type `0x99`

Frame `[magic][length][type 0x99][check 0xFFFFFF66]` + `[pathLen u32-LE][path NUL-term][contentLen u32-LE][content]`.
Staging file `/tmp/uploadFileTmp`; runs as root, no path whitelist. Capability-relevant targets:

- Flat files: `/tmp/screen_dpi`, `/tmp/screen_fps`, `/tmp/screen_size`, `/tmp/night_mode`,
  `/tmp/hand_drive_mode`, `/tmp/charge_mode`, `/tmp/carplay_mode`, `/tmp/iphone_work_mode`,
  `/etc/android_work_mode`, `/tmp/carlogo.png`.
- The binary geometry structs under `/etc/RiddleBoxData/` (see §9.1.4).

### 9.1.4 `HU_*` geometry structs — on-device dump (2026-05-21, post-capture)

All `uint32` little-endian. **Verified bytes from the live adapter:**

```
HU_SCREEN_INFO    24 B :  60 09 00 00  c0 03 00 00  00 00 00 00  00 00 00 00  3c 00 00 00  a0 00 00 00
                          [ width=2400, height=960, 0, 0, fps=60, dpi=160 ]

HU_VIEWAREA_INFO  24 B :  60 09 00 00  c0 03 00 00  60 09 00 00  c0 03 00 00  00 00 00 00  00 00 00 00
                          [ width=2400, height=960, width=2400, height=960, originX=0, originY=0 ]
                          (0x00/0x04 = view-area size — the field _CopyDisplayDescriptions reads;
                           0x08/0x0C empirically duplicate the dimensions on this unit;
                           0x10/0x14 = origin, 0,0 = full-screen)

HU_SAFEAREA_INFO  20 B :  60 09 00 00  c0 03 00 00  00 00 00 00  00 00 00 00  00 00 00 00
                          [ width=2400, height=960, originX=0, originY=0, drawUIOutsideSafeArea=0 ]
```

`drawUIOutsideSafeArea = 0` → hard crop (black outside SafeArea); `= 1` → wallpaper fills the
full ViewArea, interactive UI stays inside SafeArea.

### 9.1.5 `riddleBoxCfg` — persistent store

`/etc/riddle.conf` (JSON key:value), factory backup `/etc/riddle_default.conf`, CLI
`riddleBoxCfg <Key> [Value]`. Keys that change what the iPhone is told about the head unit:
`CustomFrameRate`, `VideoResolutionWidth`/`Height`, `OriginalResolution`, `ScreenDPI`,
`ScreenPhysicalW`/`H`, `CarBrand`, `WiFiChannel`, `CarDrivePosition`, `DayNightMode`,
`GNSSCapability`, `DashboardInfo`, `AdvancedFeatures` (→ `g_bSupportNaviScreen`).
**This unit's live values:** `DashboardInfo:5`, `GNSSCapability:3`, `CarDrivePosition:0`
(all other capability keys absent → firmware defaults).

`DashboardInfo` is a bitmask gating the iAP2 capability engines: **bit0 = media-player,
bit1 = vehicle-status, bit2 = route-guidance**. `5` = `0b101` → media-player + route-guidance
enabled, vehicle-status OFF — matches the capture (a `routeGuidanceDisplayComponent` appears,
no `vehicleStatusComponent`).

### 9.1.6 IPC: `ARMadb-driver` → CarPlay daemons

`ARMadb-driver` is the USB protocol handler ("MiddleManServer"). The CarPlay daemons connect
back as MiddleMan clients over an abstract-namespace AF_UNIX socket, tagged with a
`RiddleLinktype` (CarPlay = 3). Live: `ttyLog.txt:362` `pid:388 CarPlay(3) connected, fd=11`.
`AppleCarPlay` / `ARMiPhoneIAP2` read most config not over the socket but directly from
`/etc/riddle.conf` and the `/etc/RiddleBoxData/HU_*` files at session init.

## 9.2 Stage 2a — iAP2 `IdentificationInformation` (msg `0x1D01`), over Bluetooth

Built by `ARMiPhoneIAP2` `CiAP2IdentifyEngine` (+ nested `CiAP2UpdateEntity_group_*` builders),
emitted by `iAP2Engine::Send_changes("IdentifyInfo", 0x1D01)`. Sent over BT RFCOMM **before WiFi
exists**. **Carries no resolution** — it advertises transports, vehicle identity, supported
message IDs.

### 9.2.1 Wire framing

iAP2 data frame: `FF 5A | len(u16-BE) | ctrl | seq | ack | sessID | hdr-cksum`, then session
payload `40 40 | payloadLen(u16-BE) | <msgID u16-BE> | <TLV params…>`.
Each parameter is a TLV: **`[length u16-BE][param-id u16-BE][payload]`**, where `length`
includes the 4-byte TLV header.

Captured `0x1D01` frame (`ttyLog.txt:333`, BT pass, 275-byte frame / 265-byte msg payload):
```
ff 5a 01 13 40 2a b5 01 73   40 40 01 09 1d 01   00 0c 00 00 43 61 72 4c 69 6e 6b ...
└FF5A┘ └len┘ c  s  a  S  ck   └sess┘ └plen┘└msg┘  └len┘└id ┘└──"CarLink"──┘
                                       =0x1D01    =0x0C =0   (TLV: param 0 "name")
```

### 9.2.2 Component table (captured payload, `ttyLog.txt:145-330`)

| param id | friendlyName | type | captured value |
|---|---|---|---|
| 0 | name | utf8 | `CarLink` |
| 1 | modelIdentifier | utf8 | `Magic-Car-Link-1.00` |
| 2 | manufacturer | utf8 | `Magic Tec.` |
| 3 | serialNumber | utf8 | `2025.02.25.1521626a` |
| 4 | firmwareVersion | utf8 | `1.0.0` |
| 5 | hardwareVersion | utf8 | `1.0.0` |
| 6 | messagesSentByAccessory | blob (u16 list) | BT pass: `5703` |
| 7 | messagesReceivedFromDevice | blob (u16 list) | BT pass: `4E0A 4E0B 5702 4E0D 4E0E` |
| 8 | powerProvidingCapability | uint8 | `2` |
| 9 | maximumCurrentDrawnFromDevice | uint16 | `0` |
| 12 | currentLanguage | utf8 | `en` |
| 13 | supportedLanguage | utf8 | `en` |
| 17 | **bluetoothTransportComponent** | group | id 0 `=1`; id 1 `IAP2-Bluetooth`; id 2 `transportSupportsiAP2Connection`(none); id 3 BT MAC `DE:AD:BE:EF:00:04` |
| 20 | **vehicleInformationComponent** | group | id 0 identifier `=1`; id 1 name `CarLink`; id 2 engineType `=0`; id 6 displayName `CarLink` |
| 24 | **wirelessCarPlayTransportComponent** | group | id 0 transportComponentIdentifier `=2`; id 1 `IAP2-Wireless`; id 2 `transportSupportsiAP2Connection`(none); id 4 **`transportSupportsCarPlay`(none)** |
| 30 | routeGuidanceDisplayComponent | group | *(WiFi re-identify pass only)* id 0 identifier `=42`; id 1 `RouteGuidance` |

**The single field that enables wireless CarPlay** is `transportSupportsCarPlay` — param id 4
inside component 24. It is an iAP2 **"none"-type** parameter: a 4-byte TLV `[00 04][00 04]` with
no payload — its *presence* is the boolean flag.

### 9.2.3 BT pass vs WiFi re-identify

After WiFi handover the adapter re-identifies (`bMediumTypeIsBT_` flips 1→0). The WiFi pass
sends **16 components** (vs 14): adds `routeGuidanceDisplayComponent` (id 30) and a larger
message set — `messagesSentByAccessory` = `5703 4154 4156 5000 5002 FFFB 5200 5203`,
`messagesReceivedFromDevice` adds `4155 5001 FFFA FFFC 5201 5202`. The route-guidance /
media-player / location engines are gated by `DashboardInfo` (§9.1.5).

## 9.3 Stage 2b — AirPlay session SETUP, over WiFi/RTSP — **carries the resolution**

Built by `AppleCarPlay` after WiFi handover. RTSP control on TCP port **5000**.

### 9.3.1 Screen + HID registration (`ttyLog.txt:354-361`)

`AppleCarPlay` registers the display + input devices into the AirPlay receiver at startup:
```
kScreenProperty_MaxFPS : 60
[Screen] Registered screen e5f7a68d-7b0f-4305-984b-974f677a150b  2400 x 960, 60 FPS
[HID]    Registered HID "MultiTouchScreen", c2262755-32c1-4d23-8539-89b47ef7b1d1
[HID]    Registered HID "My Knob",          486370a2-7cca-467c-9a2d-2e0d39bf7619
[HID]    Registered HID "Music Control",    35fa46b3-5664-4c6b-8fe9-29f6196daa43
[HID]    Registered HID "PhoneControl",     85bcc603-9558-4fa8-a5a6-2b273b097952
```
The screen UUID is reused as the `viewAreas.uuid` and the video-stream UUID.

### 9.3.2 `viewAreas` / `displayInfo` plist — THE resolution descriptor (`ttyLog.txt:620-686`)

```
displayInfo = [ {
    type            : 110          ← 110 = main-screen descriptor (111 = alt / cluster)
    uuid            : "e5f7a68d-7b0f-4305-984b-974f677a150b"
    widthPixels     : 2400     ★ horizontal resolution the iPhone renders to
    heightPixels    : 960      ★ vertical resolution the iPhone renders to
    maxFPS          : 60
    widthPhysical   : 0            mm; 0 ⇒ iPhone derives DPI itself
    heightPhysical  : 0
    features        : 10           display feature bitmask
    primaryInputDevice : 0         0 = touch (MultiTouchScreen) is primary
    initialViewArea : 0
    adjacentViewAreas : []
    viewAreas : [ {
        widthPixels  : 2400   heightPixels : 960
        originXPixels : 0     originYPixels : 0
        viewAreaStatusBarEdge   : 0
        viewAreaTransitionControl : false
        safeArea : {
            widthPixels  : 2400   heightPixels : 960
            originXPixels : 0     originYPixels : 0
            drawUIOutsideSafeArea : false
        }
    } ]
} ]
```

### 9.3.3 `WifiAudioFormats` array (`ttyLog.txt:570-615`)

Each entry `{ audioType, type, audioInputFormats, audioOutputFormats }`. `type`: **100 = main
audio, 101 = alt audio, 102 = media audio**. The format fields are single-bit selectors:

| value | bit | codec / format |
|---|---|---|
| `0x10` (16) | 4 | PCM 16-bit, 16 kHz mono — mic / telephony input |
| `0x8000` (32768) | 15 | PCM 16-bit, 48 kHz stereo — "compatibility" output |
| `0x8010` (32784) | 4+15 | PCM 16 kHz-mono + 48 kHz-stereo combined |
| `0x800000` (8388608) | 23 | **AAC-LC 48 kHz stereo** — media (the `type:102` stream) |
| `0x2000000` (33554432) | 25 | **AAC-ELD 48 kHz stereo** — alert / alt-audio |
| `0x4000000` (67108864) | 26 | **AAC-ELD 48 kHz stereo** — default / telephony / speechRecognition (duplex) |

Captured array: `compatibility/100 in=0x10 out=0x8010`, `compatibility/101 out=0x8000`,
`alert/100 out=0x2000000`, `default/100 in+out=0x4000000`, `telephony/100 in+out=0x4000000`,
`speechRecognition/100 in+out=0x4000000`, `default/101 out=0x2000000`, `media/102 out=0x800000`.

### 9.3.4 Session-setup request / response (`ttyLog.txt:522-567`)

- **iPhone → adapter** request carries the iPhone's own `features` array
  (`uiContext, viewAreas, cornerMasks, focusTransfer, h.264Level5.1, mainBuffered, altScreen,
  enhancedSiri, hevc, vehicleStateProtocol, sessionManagement, videoPlayback, logTransfer,
  iAPChannel`), `model: iPhone18,4`, `osVersion: 26.5`, `sourceVersion: 950.7.1`, `timingPort`,
  `deviceID`, `macAddress`. Firmware extracts `featureViewAreas` / `featureAltScreen`
  (`ttyLog.txt:559`).
- **adapter → iPhone** response: `{ eventPort: 59615, timingPort: 43140, enabledFeatures: ["viewAreas"] }`.
  **`enabledFeatures` = the intersection of HU capability and iPhone `features`** — here only
  `viewAreas` (NaviScreen excluded because `g_bSupportNaviScreen = 0`).

## 9.4 Resolution path, end to end

> The iPhone renders to `viewAreas.widthPixels`/`heightPixels`, which `AppleCarPlay`'s
> `_CopyDisplayDescriptions` (`fcn.0001c0b4`) copies from `uint32[0]`/`uint32[1]` of
> `/etc/RiddleBoxData/HU_VIEWAREA_INFO`.

```
host app Open(0x01) w/h ─▶ ARMadb-driver ProceessCmdOpen ─▶ auto-writes HU_VIEWAREA_INFO
   (or host SendFile(0x99) writes HU_VIEWAREA_INFO / HU_SAFEAREA_INFO directly)
                                       │
AppleCarPlay._CopyDisplayDescriptions ─┘  reads HU_VIEWAREA_INFO (24 B) + HU_SAFEAREA_INFO (20 B)
   gate: iPhone.featureViewAreas  AND  g_bSupportViewarea
                                       ▼
   AirPlay SETUP  viewAreas{ widthPixels, heightPixels, safeArea{…} }  ─▶ iPhone
```

- iAP2 `0x1D01` carries **no** resolution.
- `widthPhysical`/`heightPhysical` (DPI) are a separate path: `riddleBoxCfg ScreenPhysicalW/H`
  → `AppleCarPlay FUN_0001604c` → `GetBoxConfig` → `FUN_0004fefa`. Both 0 here → iPhone derives DPI.
- `g_bSupportViewarea` is set at `AppleCarPlay` init from the validity of the `HU_VIEWAREA_INFO`
  file content (not from a config key). `g_bSupportNaviScreen` ← `riddleBoxCfg AdvancedFeatures`.

## 9.5 Firmware function map

| Structure | Binary | Function | Reads |
|---|---|---|---|
| iAP2 `0x1D01` payload | `ARMiPhoneIAP2` | `CiAP2IdentifyEngine` + `CiAP2UpdateEntity_group_*`; `iAP2Engine::Send_changes` | cached `IdentifyInfo` dict (fails → defaults); `DashboardInfo` gates engines |
| `viewAreas`/`displayInfo` (resolution) | `AppleCarPlay` | `_CopyDisplayDescriptions` (`fcn.0001c0b4`, ~2112 B) | `HU_VIEWAREA_INFO` (24 B), `HU_SAFEAREA_INFO` (20 B); `g_bSupportViewarea`; phone `featureViewAreas` |
| `widthPhysical`/`heightPhysical` | `AppleCarPlay` | `FUN_0001604c` → `GetBoxConfig` → `FUN_0004fefa` | `ScreenPhysicalW`/`H` |
| screen + HID registration | `AppleCarPlay` | `CarPlayDemoApp` startup | `kScreenProperty_MaxFPS`; generated UUIDs |
| `WifiAudioFormats` | `AppleCarPlay` | `_getWifiAudioLatencies` / HUDinfo path | `HUDinfo.plist` (empty → defaults) |
| `enabledFeatures` (SETUP resp) | `AppleCarPlay` | AirPlay session-setup handler | `g_bSupportViewarea`/`g_bSupportNaviScreen` ∩ phone `features` |
| `Open` (0x01) handler | `ARMadb-driver` | `ProceessCmdOpen` (`fcn.00021cb0` / `0x22098`) | USB payload; rewrites `HU_VIEWAREA_INFO` |
| `BoxSettings` (0x19) parser | `ARMadb-driver` | `FUN_00016c20` → `FUN_0001658c`, table `@0x93f90` | JSON body → `/etc/riddle.conf` |

## 9.6 Evidence index (`carplay-20260521-101016/ttyLog.txt`)

| Item | Lines |
|---|---|
| `Open` params arrive from host | 64, 821 |
| iAP2 `0x1D01` identify payload (BT pass) | 145-330 ; on-wire hex 333 |
| iAP2 `0x1D01` re-identify (WiFi pass) | 854-1075 |
| screen + HID registration | 354-361 |
| iPhone session-setup request (`features`, model) | 522-556 |
| adapter session-setup response (`enabledFeatures`) | 560-567 |
| `WifiAudioFormats` | 570-615 |
| `viewAreasArray` / `Car displayInfo` | 620-686 |
| MiddleMan `CarPlay(3) connected` | 362 |

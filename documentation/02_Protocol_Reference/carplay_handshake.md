# Wireless CarPlay End-to-End Handshake

**Status:** VERIFIED — live capture `carplay-20260521-101016` (2026-05-21): full fresh wireless
CarPlay pairing captured across three simultaneous streams (Bluetooth HCI pcap, WiFi pcap,
firmware ttyLog), with the adapter pairing record cleared beforehand to force a true
`pair-setup`.
**Adapter:** CPC200-CCPA / A15W, AirPlay/AirTunes 320.17, firmware `2025.02.25` (the genuine
CCPA release running on the captured unit; other docs cite the `2025.10.15.1127` release —
both are real CPC200-CCPA firmware versions, not a contradiction).
**iPhone:** iPhone18,4, iOS 26.5 (build 23F77), AirPlay 950.7.1.
**Consolidated from:** `_evidence/MFi_research/CAPTURE_SESSION.md` §9, `capture/carplay-20260521-101016/ANALYSIS.md`.

---

## Overview

A wireless CarPlay session is brought up in two transport stages:

1. **Bluetooth RFCOMM** — the entire iAP2 link bring-up, identification, MFi authentication and
   WiFi credential handover run over the iAP2 accessory profile bound to `/dev/rfcomm0`.
2. **WiFi** — after the iPhone joins the adapter's WPA2 SoftAP, the AirPlay session (RTSP
   control on TCP 5000, then HomeKit pair-setup / pair-verify, then encrypted media streams)
   runs entirely over IP.

The MFi coprocessor (a **real Apple MFi auth IC** on `/dev/i2c-1`, 7-bit address `0x11` /
8-bit `0x22`) is exercised **twice** per pairing — once in the iAP2 stage, once in the AirPlay
stage. There is **no FairPlay** (`/fp-setup`) layer and **no `/auth-setup` endpoint** on this
firmware.

```
iAP2/BT :  ff55 probe -> ff5a link-sync -> identify(0x1D00/01/02)
           -> MFi auth(0xAA00..0xAA05) -> WiFi handover(0x5702/0x5703 + 0x4E0A/0B/0D/0E)
WiFi    :  AppleCarPlay start -> mDNS _airplay._tcp -> RTSP:5000
           -> /pair-setup x3 (HomeKit SRP) -> /pair-verify x2 (Curve25519)
           -> [MFi chip RSA sign again] -> AirPlay session
```

---

## Handshake Phases (A–G)

### Phase A — Bluetooth + iAP2 link

| Step | Direction | Event |
|------|-----------|-------|
| A1 | — | BT Classic connects; RFCOMM channel for the `IAP2` accessory profile accepted → `/dev/rfcomm0` |
| A2 | iPhone → adapter | iAP2 link probe `ff 55 02 00 ee 10` |
| A3 | adapter → iPhone | iAP2 link-sync `ff 5a` |

Negotiated link parameters: linkVersion 1, maxOutstandingPackets 127, maxRecvPacketLen 2048
(adapter) / 65535 (iPhone), retransmit timeout 2000 ms.

### Phase B — iAP2 identification

| Step | Direction | iAP2 message | Content |
|------|-----------|--------------|---------|
| B1 | iPhone → adapter | `0x1D00 StartIdentify` | begin identification |
| B2 | adapter → iPhone | `0x1D01 IdentificationInformation` (263 B) | name `CarLink`, model `Magic-Car-Link-1.00`, manufacturer `Magic Tec.`; advertises `wirelessCarPlayTransportComponent` / `transportSupportsCarPlay`; supports `5703 WifiConfigInfo`, `5702 ReqWifiConfig`, `4E0D WirelessCarPlayUpdateMsg`; `bWireLess_=1`, `bMediumTypeIsBT_=1` |
| B3 | iPhone → adapter | `0x1D02 IdentifyAccept` | identification accepted → firmware `OnCarPlayPhase 100` |

`0x1D01` carries **no resolution** — resolution is negotiated later, over AirPlay (Phase E).
TLV format and the full component table are documented in `device_identification.md`.

### Phase C — MFi authentication over iAP2

| Step | Direction | iAP2 message | Content |
|------|-----------|--------------|---------|
| C1 | iPhone → adapter | `0xAA00 ReqAuthCert` | request accessory certificate |
| C2 | adapter → iPhone | `0xAA01` Accessory Certificate (945 B) | PKCS#7 SignedData, served from in-process cache |
| C3 | iPhone → adapter | `0xAA02 ReqChallenge` | 20-byte challenge |
| C4 | — | — | adapter drives the **MFi chip** on `/dev/i2c-1`: writes `MFI_AUTH_COP_REG_ADDR_AUTH_CTRL_AND_STATUS` (reg 0x10), polls (~1.6 s — chip NACKs while signing), reads `…_SIGNATURE_LEN` = 128, then `…_SIGNATURE_DATA` |
| C5 | adapter → iPhone | `0xAA03` Challenge Response | 128-byte RSA-1024 signature |
| C6 | iPhone → adapter | `0xAA05 AuthSuccess` | iPhone accepted the signature |

### Phase D — WiFi credential handover

| Step | Direction | iAP2 message | Content |
|------|-----------|--------------|---------|
| D1 | iPhone → adapter | `0x5702 ReqWifiConfig` | request WiFi credentials |
| D2 | adapter → iPhone | `0x5703 WifiConfigInfo` | `ssid=CarLink`, `passphrase=12345678`, security type `2`, channel `0x24` (36) |
| D3 | iPhone → adapter | `0x4E0A DeviceLanguageUpdate` | language `en` |
| D4 | iPhone → adapter | `0x4E0B DeviceTimeUpdate` | iPhone clock |
| D5 | iPhone → adapter | `0x4E0D WirelessCarPlayUpdateMsg` | `status:1` |
| D6 | iPhone → adapter | `0x4E0E TransportNotify` | iPhone BT MAC `DE:AD:BE:EF:00:06` + transport id `<transport-id>` |
| D7 | — | — | iPhone associates to `wlan0` (HostMlme assoc + EAPOL/WPA), DHCP → `192.168.43.x` |
| D8 | — | — | BT iAP2 torn down (`kAirPlayCommand_DisableBluetooth`); `ARMiPhoneIAP2` receives `SIGTERM` |

### Phase E — AirPlay bring-up over WiFi

| Step | Direction | Event |
|------|-----------|-------|
| E1 | — | `AppleCarPlay` (`CarPlayDemoApp`) starts — **AirPlay 320.17** |
| E2 | — | Registers screen `2400×960 @ 60 FPS` (uuid `e5f7a68d-…`) + HID devices `MultiTouchScreen`, `My Knob`, `Music Control`, `PhoneControl` |
| E3 | adapter | Advertises Bonjour **`_airplay._tcp` on TCP port 5000** (TXT `deviceid=DE:AD:BE:EF:00:01`, `features=0x44440B80,0x61`, `srcvers=320.17`) |
| E4 | adapter | Browses, finds the iPhone's `User._carplay-ctrl._tcp` (`srcvers=950.7.1`), resolves `User.local. :49372`, connects out to it |

### Phase F — AirPlay pairing (RTSP on port 5000)

| Step | Direction | Event |
|------|-----------|-------|
| F1 | iPhone ↔ adapter | **3× `POST /pair-setup`** — `X-Apple-HKP: 0` (HomeKit pair-setup, M1–M6 over 3 round-trips). ttyLog: `Control pair-setup HK, type 0` ×3 |
| F2 | iPhone ↔ adapter | **2× `POST /pair-verify`** — `X-Apple-HKP: 2`, `X-Apple-PD: 1` (Curve25519). ttyLog: `pair-verify 1`, `pair-verify 2`, `Control pair-verify HK done`, `_HandlePairVerifyHomeKitCompletion` |
| F3 | — | Adapter performs a **second MFi chip signature** — `MFi auth create signature` → `MFi get addr: 22 from cache file` → 128-byte signature (the AirPlay-layer MFi step) |

No separate `/fp-setup` or `/auth-setup` RTSP endpoint is involved — the AirPlay-side MFi
material is carried within the pairing exchange.

### Phase G — Session active

| Step | Event |
|------|-------|
| G1 | `AirPlay session started` with `192.168.43.x:49374`. Negotiated: eventPort 59615, timingPort 43140↔62206, `enabledFeatures:[viewAreas]` |
| G2 | Streaming connections open on ephemeral ports `:49376` (~5,400 pkts, video) and `:49346` (~3,000 pkts, audio). iPhone advertised `hevc` + `h.264Level5.1` (this is the iPhone's advertised *maximum* codec capability during negotiation; the level actually negotiated/used for this session is H.264 Level 5.0 / `level_idc=50` per `video_protocol.md`) |
| G3 | Firmware phases: `OnCarPlayPhase 100 → 1 → 103`; `Modes changed: screen controller`; `RequestVideoFocus(500)` forwarded to the host |

---

## MFi Authentication Detail

The MFi coprocessor is a **real Apple MFi auth IC** (`/dev/i2c-1`, 7-bit addr `0x11` /
8-bit `0x22`) and is exercised **twice per pairing**.

### Captured artifacts

| Artifact | Size | Value / location |
|----------|------|------------------|
| `0xAA01` Accessory Certificate | 945 bytes | PKCS#7 SignedData (`30 82 03 ad 06 09 2a 86 48 86 f7 0d 01 07 02 …`). Subject serial `33 33 AA 07 12 27 AA 02 AA 00 11 AA 00 30 45` → `IPA_3333AA071227AA02AA0011AA003045` |
| `0xAA02` Challenge | 20 bytes | `75 6c a1 9a df c9 c9 be 29 30 fb dc cf b8 e2 18 a0 73 cc 3a` |
| `0xAA03` Challenge Response | 128 bytes | RSA-1024 signature (iAP2/BT stage) |
| AirPlay-layer MFi signature | 128 bytes | second signature, generated after `pair-verify` |

The cert serial is **identical to the chip statically dumped** in the MFi research corpus
(`dumps/`, `docs/register_map.md`). The two 128-byte signatures differ (different inputs); the
certificate is the same. This is consistent with deterministic RSA PKCS#1 v1.5 signing.

### Why two MFi exercises

- **iAP2 stage (Phase C):** the iAP2 `0xAA0x` challenge-response gates the Bluetooth side of
  the link. The iPhone sends a 20-byte challenge; the adapter has the chip sign it.
- **AirPlay stage (Phase F):** after HomeKit `pair-verify`, `AppleCarPlay` invokes
  `MFi auth create signature`, having the chip sign again — the AirPlay-layer MFi step.

No FairPlay layer exists on this firmware.

---

## Versions, Ports & Network

| Item | Value |
|------|-------|
| RTSP / AirPlay control port | TCP **5000** (adapter advertises `_airplay._tcp` here) |
| AirPlay version — adapter | **320.17** (AirPlay / AirTunes) |
| AirPlay version — iPhone | **950.7.1** |
| Stream sockets | ephemeral high ports — observed `:49376` (video), `:49346` (audio) |
| AirPlay session params | eventPort 59615, timingPort 43140 |
| Adapter SoftAP | `192.168.43.1`, 5 GHz ch 36; iPhone DHCP → `192.168.43.x` |
| Adapter deviceid (mDNS) | `DE:AD:BE:EF:00:01` (`features=0x44440B80,0x61`) |

There is **no fixed 7000/7001** for video/audio — those ports are ephemeral and negotiated per
session in the AirPlay SETUP response.

---

## Conflicts Resolved (vs. prior RE corpus)

| Question | Resolution from capture `carplay-20260521-101016` |
|----------|---------------------------------------------------|
| RTSP control port — 5000 or 7000? | **5000** — `_airplay._tcp` registered on 5000; iPhone connects `:49374 → :5000` |
| Does wireless CarPlay do `/pair-setup` (SRP)? | **Yes** — 3× `POST /pair-setup` (HKP:0) + 2× `POST /pair-verify` (HKP:2) on the AirPlay channel, *in addition to* the iAP2 MFi auth |
| Is FairPlay (`/fp-setup`) used? | **No** — no `/fp-setup` or `/auth-setup` endpoint anywhere in the capture |
| MFi: real chip? how many times? | Real chip, **exercised twice** per pairing — iAP2 `0xAA0x` challenge (BT) + AirPlay-layer `MFi auth create signature` (WiFi) |
| Is there a PIN on the adapter? | **No** — the adapter has no screen; pair-setup is transparent, user trust is the iPhone-side "Use This Car" prompt |

---

## Related Documentation

- `wireless_carplay.md` — Wireless CarPlay protocol reference, iAP2 + MFi handshake summary
- `device_identification.md` — iAP2 identification (`0x1D00/0x1D01/0x1D02`) TLV format
- `usb_protocol.md` — host↔adapter USB framing (distinct from the AirPlay/WiFi side)
- `inbound_session_sequence.md` — USB-side session sequence (the Phase 3→4 window)
- `_evidence/MFi_research/CAPTURE_SESSION.md` §9 — head-unit capability config & advertisement
- `_evidence/MFi_research/capture/carplay-20260521-101016/ANALYSIS.md` — raw capture analysis

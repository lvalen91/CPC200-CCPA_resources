# CarPlay Pairing Capture — Analysis

**Capture:** `carplay-20260521-101016`  ·  **Date:** 2026-05-21  ·  **Adapter:** CPC200-CCPA @ 192.168.43.1

A complete fresh wireless CarPlay pairing, captured across three simultaneous streams while the
adapter pairing record (`/Library/Keychains/default.keychain`) was cleared beforehand to force a
full `pair-setup`.

## 1. Files

| File | Size | Contents |
|---|---|---|
| `wifi.pcap` | 9.0 MB / 10,544 pkts | AF_PACKET `wlan0` — AirPlay/RTSP, mDNS, video+audio streams |
| `bt.pcap` | 9.9 KB / 666 pkts | HCI monitor channel — iAP2-over-RFCOMM handshake + MFi auth |
| `ttyLog.txt` / `.full` | 94 KB / 143 KB | firmware runtime log — narrates the whole handshake incl. MFi |

Note on timestamps: the adapter boots with its clock at 2020-01-02; `sync_box_time.sh` corrects
it to real time (`2026-05-21 10:09`) mid-handshake. Both appear in `ttyLog`; ordering is intact.

## 2. Peers

| | |
|---|---|
| iPhone | "User", **iPhone18,4**, iOS **26.5** (build 23F77), AirPlay **950.7.1** |
| iPhone BT MAC | `DE:AD:BE:EF:00:06`   ·  WiFi MAC (randomised) `DE:AD:BE:EF:00:09` |
| Adapter | name `CarLink`, model `Magic-Car-Link-1.00`, AirPlay/AirTunes **320.17**, fw `2025.02.25` |
| Adapter deviceid | `DE:AD:BE:EF:00:01`  (mDNS `features=0x44440B80,0x61`, `srcvers=320.17`) |
| Network | adapter AP `192.168.43.1`, 5 GHz ch 36; iPhone DHCP → `192.168.43.125` |

## 3. The complete handshake (ordered)

### Phase A — Bluetooth + iAP2 link  (`bt.pcap`, `ttyLog`)
1. BT classic connects; RFCOMM channel for `IAP2` accepted → `/dev/rfcomm0`.
2. iAP2 link: `ff 55 02 00 ee 10` probe → `ff 5a` link-sync. Negotiated: linkVersion 1,
   maxOutstandingPackets 127, maxRecvPacketLen 2048(box)/65535(phone), retransTimeout 2000 ms.

### Phase B — iAP2 identification
3. iPhone → `0x1D00 StartIdentify`.
4. Adapter → `0x1D01 IdentificationInformation` (263 B): name `CarLink`, model
   `Magic-Car-Link-1.00`, manufacturer `Magic Tec.`, advertises `wirelessCarPlayTransportComponent`
   / `transportSupportsCarPlay` and message support incl. `5703 WifiConfigInfo`,
   `5702 ReqWifiConfig`, `4E0D WirelessCarPlayUpdateMsg`. `bWireLess_=1, bMediumTypeIsBT_=1`.
5. iPhone → `0x1D02 IdentifyAccept`.  → firmware `OnCarPlayPhase 100`.

### Phase C — MFi authentication over iAP2  (see §4)
6. iPhone → `0xAA00 ReqAuthCert` → adapter → `0xAA01` 945-byte cert.
7. iPhone → `0xAA02 ReqChallenge` (20-byte challenge) → adapter drives the **MFi chip** →
   `0xAA03` 128-byte RSA signature.
8. iPhone → `0xAA05 AuthSuccess`.

### Phase D — WiFi credential handover
9. iPhone → `0x5702 ReqWifiConfig` → adapter → `0x5703 WifiConfigInfo`:
   `ssid=CarLink`, `passphrase=12345678`, security type `2`, channel `0x24` (36).
10. iPhone → `0x4E0A DeviceLanguageUpdate` (en), `0x4E0B DeviceTimeUpdate`,
    `0x4E0D WirelessCarPlayUpdateMsg status:1`, `0x4E0E TransportNotify`
    (carries iPhone BT MAC `DE:AD:BE:EF:00:06` + transport id `000081500001343C2EC0401C`).
11. iPhone associates to `wlan0` (HostMlme assoc + EAPOL/WPA), DHCP → `192.168.43.125`.
    BT iAP2 then torn down (`kAirPlayCommand_DisableBluetooth`); `ARMiPhoneIAP2` gets SIGTERM.

### Phase E — AirPlay bring-up over WiFi  (`wifi.pcap`, `ttyLog`)
12. `AppleCarPlay` (`CarPlayDemoApp`) starts — **AirPlay 320.17**. Registers screen
    `2400×960 @ 60 FPS` (uuid `e5f7a68d-…`) and HID devices `MultiTouchScreen`, `My Knob`,
    `Music Control`, `PhoneControl`.
13. Adapter advertises Bonjour **`_airplay._tcp` on TCP port 5000**.
14. Adapter browses, finds the iPhone's `User._carplay-ctrl._tcp` (`srcvers=950.7.1`),
    resolves `User.local. :49372`, and connects out to it.

### Phase F — AirPlay pairing  (RTSP on port 5000)
15. **3× `POST /pair-setup`** — `X-Apple-HKP: 0` (HomeKit pair-setup, M1-M6 over 3 round-trips).
    ttyLog: `Control pair-setup HK, type 0` ×3.
16. **2× `POST /pair-verify`** — `X-Apple-HKP: 2`, `X-Apple-PD: 1`. ttyLog: `pair-verify 1`,
    `pair-verify 2`, `Control pair-verify HK done`, `_HandlePairVerifyHomeKitCompletion`.
17. Adapter performs a **second MFi chip signature** — `MFi auth create signature` →
    `MFi get addr: 22 from cache file` → 128-byte signature (the AirPlay-layer / auth-setup MFi
    step). No separate `/fp-setup` or `/auth-setup` RTSP endpoint was observed — the AirPlay-side
    MFi material is carried within the pairing exchange.

### Phase G — Session active
18. `AirPlay session started` with `192.168.43.125:49374`. Negotiated: eventPort 59615,
    timingPort 43140↔62206, `enabledFeatures:[viewAreas]`.
19. Streaming connections open on `:49376` (~5,400 pkts) and `:49346` (~3,000 pkts) — video +
    audio. iPhone advertised `hevc` + `h.264Level5.1`.
20. Firmware phases: `OnCarPlayPhase 100 → 1 → 103`. `Modes changed: screen controller`,
    `RequestVideoFocus(500)` forwarded to the host.

## 4. MFi authentication — captured raw data

The MFi coprocessor is exercised **twice per pairing**.

### 4a. iAP2 challenge-response (Phase C, over Bluetooth RFCOMM)

- **`0xAA01` Accessory Certificate** — 945 bytes, PKCS#7 SignedData (`30 82 03 ad 06 09 2a 86 48
  86 f7 0d 01 07 02 …`). Subject serial **`33 33 AA 07 12 27 AA 02 AA 00 11 AA 00 30 45`** —
  i.e. `IPA_3333AA071227AA02AA0011AA003045`, **identical to the chip dumped in `dumps/` /
  `docs/register_map.md`**. Served from the firmware's in-process cache
  (`get certData 945 byte from cache`).
- **`0xAA02` Challenge** (iPhone → adapter, 20 bytes):
  `75 6c a1 9a df c9 c9 be 29 30 fb dc cf b8 e2 18 a0 73 cc 3a`
- Firmware drives the chip: `mfi_auth_processchallenge` → writes
  `MFI_AUTH_COP_REG_ADDR_AUTH_CTRL_AND_STATUS` (reg 0x10), polls (~1.6 s — chip NACKs while
  signing), reads `…_SIGNATURE_LEN` = 128, then `…_SIGNATURE_DATA`.
- **`0xAA03` Challenge Response** (adapter → iPhone, 128-byte RSA-1024 signature):
  `65 27 e3 43 c1 a2 73 9e ca 4b 8f a6 0f bf 5f 15 c3 17 d0 22 7d 4d d2 5d 5f 83 5c 4a a5 87
   7d 52 38 68 a5 5c bc 58 9a a4 ea 8e 48 05 af a7 db 67 89 ba 56 60 fa 92 27 2d 07 9b 93 c6
   ff 9e f0 27 3f 6a a0 67 24 86 a5 97 14 1a b5 f5 dc 3c 6a a1 0d b2 c1 0f 41 6b aa a8 8d 20
   9d 22 19 00 5d 23 7a 7e 6f 76 68 6a 7d b1 96 d4 13 32 22`
- **`0xAA05 AuthSuccess`** — iPhone accepted the signature.

### 4b. AirPlay-layer MFi signature (Phase F, after pair-verify)

`MFi auth create signature` (chip @ I2C 8-bit addr `0x22` = 7-bit `0x11`) → 128-byte signature:
```
acaed1a9 e0714efc 023cf625 ae396775 3745890e 2b379b6f 6c1dbf06 b37cd188
fcde558b 9afe5e0d e994e6c7 eb809a7d 5f78f679 257f76fa b846f54c bc438506
3a001fd4 41af2e39 40e35fe5 f26e1f87 155bd0ff 405cd497 9908d1de dc7392ad
3724aa4b c87360a3 c954c89c fa14d4a4 4773a8f1 4be66ed3 31db3d6a c3c3b30b
```
The two signatures differ (different inputs); the cert is the same. Consistent with the prior
static dumps and with deterministic RSA PKCS#1 v1.5.

## 5. Conflicts resolved (vs. the prior RE corpus)

| Question | Resolution from this capture |
|---|---|
| RTSP control port — 5000 or 7000? | **5000** — `_airplay._tcp` registered on 5000; iPhone connects `:49374→:5000`. |
| Does wireless CarPlay do `/pair-setup` (SRP)? | **Yes** — 3× `POST /pair-setup` (HKP:0, HomeKit pairing) + 2× `POST /pair-verify` (HKP:2), on the AirPlay channel, *in addition to* the iAP2 MFi auth. |
| Is FairPlay (`/fp-setup`) used? | **No** — no `/fp-setup` or `/auth-setup` endpoint anywhere in the capture. |
| MFi: real chip? how many times? | Real chip, **exercised twice** per pairing — iAP2 `0xAA0x` challenge (BT) + AirPlay-layer `MFi auth create signature` (WiFi). |

## 6. Auth-pathway summary

```
iAP2/BT :  ReqAuthCert(0xAA00) -> Cert(0xAA01,945B) -> ReqChallenge(0xAA02,20B)
           -> [MFi chip RSA sign] -> ChallengeResponse(0xAA03,128B) -> AuthSuccess(0xAA05)
WiFi    :  RTSP:5000  /pair-setup x3 (HomeKit SRP)  ->  /pair-verify x2 (Curve25519)
           -> [MFi chip RSA sign again] -> session keys -> AirPlay session
```

iAP2 MFi auth gates the BT side; HomeKit pair-setup/pair-verify + the second MFi signature
secure the AirPlay side. No FairPlay layer on this firmware.

## 7. Raw artifact index

| Artifact | Location |
|---|---|
| iAP2 link/identify/MFi messages (full hex) | `ttyLog.txt` lines ~127-401 (`DataIn`/`DataOut`) |
| `0xAA02` challenge | `ttyLog.txt:347` |
| `0xAA03` 128-byte signature | `ttyLog.txt:388` |
| `0xAA01` cert (serial) | `ttyLog.txt:344` |
| AirPlay-layer MFi signature | `ttyLog.txt:507-516` |
| WiFi creds `0x5703` | `ttyLog.txt:401` |
| AirPlay session params | `ttyLog.txt:522-708` |
| RTSP `/pair-setup` ×3, `/pair-verify` ×2 | `wifi.pcap` TCP port 5000 |
| Video/audio streams | `wifi.pcap` TCP `:49376`, `:49346` |

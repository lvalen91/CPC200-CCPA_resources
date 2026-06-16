# iAP2 Message Catalog — CPC200-CCPA

Wire-format field semantics for the iAP2 messages the adapter parses from the iPhone: **RouteGuidance**
(`0x5201`/`0x5202`, host carlink_native) and **Telephony** — CallState (`0x4155`) and Communication
(`0x4158`), host carlink_macOS. The **binary-patch mechanism** that forwards these raw frames to the
host (`_iap2`/`_iap2m`/`_callraw`/`_commraw`) is documented separately in
[`../04_Implementation/iap2_binary_patches.md`](../04_Implementation/iap2_binary_patches.md); this
doc is the "what the fields mean" reference.

**Status:** RouteGuidance VERIFIED against 567 historic + 56 live frames + ARMiPhoneIAP2 binary RE +
Apple R14G17 SDK; Telephony device-verified 2026-06-14/15.
**Consolidated from:** Apple CarPlay Communication Plug-In SDK R14G17 (2017, iOS 10.3.3), firmware
binary analysis, live USB captures (2026-05-28), iAP2 raw-passthrough patch verification (2026-06).
**Firmware reference:** patched ARMiPhoneIAP2 binary (deployed CCPA `/usr/sbin`, see versionCode 133).
**Host consumers:** carlink_native versionCode 136+ (`Iap2StateParser.kt`, `Iap2RouteParser.kt`) for
nav; carlink_macOS (`IAP2CallStateDecoder.swift`) for telephony.
**Last Updated:** 2026-06-15

---

## Source authority

| Source | Role |
|---|---|
| **iOS 26.5 IPSW (build 23F77, iPhone18,4) — `AccessoryNavigation.framework`** | **Authoritative.** `+[ACCNavigationRouteGuidanceUpdateInfo keyForType:]` at `0x226ac5f74` with jump table at `0x226ac61e8` defines the complete integer→SDK-name map for all 26 fields. Recovered 2026-05-28 via `ipsw extract --dyld` + `ipsw class-dump` + `ipsw dyld disass`. |
| Apple CarPlay Communication Plug-In SDK R14G17 (2017, iOS 10.3.3) | Original Apple-published spec. Covers fields 0x01-0x0f + 0x13. Modern iOS adds 0x10-0x1a (lane guidance, EV battery, timezone, stop type) per the iOS 26 analysis. Naming refresh: `VisibleInApp` → `BeingShownInApp`. |
| the (offline) ARMiPhoneIAP2 binary-RE notes — deferred, not yet integrated | ARMiPhoneIAP2 binary RE. Older AIS revision — labels 0x0d/0x0e inverted vs modern iOS. String table at rodata 0x74da7-0x74efa verified, but field-ID assignments deferred to iOS 26 source above. |
| `../06_Reference/key_binaries.md` `CiAP2RouteGuidanceEngine` section | Higher-level firmware RE summary. |
| `app/src/main/kotlin/com/carlink/navigation/Iap2RouteParser.kt` | Production 0x5202 (route plan) parser. |
| `app/src/main/kotlin/com/carlink/navigation/Iap2StateParser.kt` | Production 0x5201 (per-tick state + cursor) parser. Added in versionCode 136 for Bug A fix. |

### Public sources searched (2026-05-28) — no public documentation of the modern RouteGuidance wire format

| Resource | Result |
|---|---|
| [45clouds/WirelessCarPlay `iap2.pdf`](https://github.com/45clouds/WirelessCarPlay/blob/master/iap2.pdf) | Base iAP2 only, pre-dates RouteGuidance |
| [yif-hong/Apple-MFI-AIS-R29 (GitHub)](https://github.com/yif-hong/Apple-MFI-Accessory-Interface-Specification) | R29 RE port in progress; RouteGuidance chapter not yet committed (only Bluetooth.md as of 2026-05-28) |
| AIS R29 mirrors (Scribd) | Paywalled, also pre-RouteGuidance-extensions |
| Apple Developer / WWDC 2016/2023 sessions | Describe RouteGuidance feature behavior, never name wire fields |
| [wiomoc — Exploring Apple's MFI protocol iAP2](https://wiomoc.de/misc/posts/mfi_iap.html) | Transport/auth layer, no navigation |

Apple's modern AIS chapters covering navigation are NDA-protected. The firmware RE doc + our live captures are currently the most authoritative source for the wire format.

---

## Three-layer pipeline

```
iPhone (iAP2 RouteGuidance source)
    │ sends 21-field 0x5201 every ~1s + 0x5202 route plan on load/reroute
    ▼
CPC200-CCPA adapter
    │ stock firmware: strips 16 of 21 fields → forwards ~5 fields as named NaviJSON keys
    │ patched ARMiPhoneIAP2 v5 (deployed /usr/sbin, survives reboot):
    │   ALSO attaches raw 0x5201/0x5202 hex as _iap2 / _iap2m NaviJSON fields
    ▼
NaviJSON envelope (USB MediaType=NAVI_JSON, sub-type 200)
    │ ~5 named keys + _iap2 (raw 0x5201 hex) + _iap2m (raw 0x5202 hex on route load)
    ▼
carlink_native host app
    • Named keys: read in NavigationStateManager.onNaviJson
    • _iap2m: parsed by Iap2RouteParser.kt → ComposedIconStore.populateFromIap2m
    • _iap2: parsed by Iap2StateParser.kt → NavigationStateManager.setLastIap2State
```

---

## NaviJSON envelope keys

Top-level JSON map sent over USB MediaType=NAVI_JSON. 21 distinct key-combinations observed across captures:

| Combination | Trigger |
|---|---|
| `[_iap2]` | bare per-tick state ping |
| `[NaviRemainDistance, _iap2]` | distance-changed tick |
| `[NaviStatus, _iap2]` | status-changed tick |
| `[NaviStatus, NaviRemainDistance, _iap2]` | both changed |
| `[_iap2, _iap2m]` | route load |
| `[NaviRemainDistance, _iap2, _iap2m]` | reroute-with-distance |
| `[NaviStatus, NaviTimeToDestination, NaviDestinationName, NaviDistanceToDestination, NaviAPPName, _iap2]` | route-start packet |
| `[NaviTimeToDestination, NaviDistanceToDestination, _iap2]` | ETA update |
| `[NaviManeuverType, NaviOrderType]` | bare maneuver burst |
| `[NaviManeuverType, NaviOrderType, NaviRoadName]` | maneuver burst + road |
| `[NaviRoadName, NaviOrderType, NaviRoundaboutExit, NaviManeuverType]` | roundabout burst |
| `[NaviRoadName, NaviOrderType, NaviTurnAngle, NaviManeuverType]` | turn burst with angle |
| `[NaviRoadName, NaviOrderType, NaviTurnAngle, NaviTurnSide, NaviManeuverType]` | full turn burst |

Named NaviJSON keys (mirror subset of iAP2 fields):

| Key | Type | Mirrors iAP2 field |
|---|---|---|
| `NaviStatus` | float→int | 0x5201 field 0x0001 `RouteGuidanceState` |
| `NaviAPPName` | string | 0x5201 extension field 0x0013 |
| `NaviDestinationName` | string | 0x5201 extension field 0x0004 |
| `NaviRemainDistance` | float→int meters | 0x5201 field 0x000a `DistanceToNextManeuver` |
| `NaviTimeToDestination` | float→int seconds | 0x5201 field 0x0006 `TimeRemainingToDestination` |
| `NaviDistanceToDestination` | float→int meters | 0x5201 field 0x0007 `DistanceRemaining` |
| `NaviManeuverType` | int (CPManeuverType) | 0x5202 field 0x0003 |
| `NaviRoadName` | string | 0x5202 field 0x0002 (instruction_text), NOT 0x0004 (post_road) |
| `NaviTurnSide` | int | 0x5202 driving-side derivative |
| `NaviTurnAngle` | int (enum, not degrees) | 0x5202 derivative |
| `NaviRoundaboutExit` | int (1-19) | 0x5202 derivative |
| `NaviOrderType` | int (16=roundabout, 6=turn, others) | Apple's burst-sequence enum, UNDER-UTILIZED by host app |
| `_iap2` | hex string | raw 0x5201 frame — parsed by `Iap2StateParser` since versionCode 136 |
| `_iap2m` | hex string | raw 0x5202 burst — parsed by `Iap2RouteParser` |

---

## Wire format

```
<sync:0x4040> <len_be:2> <type_be:2> <KVPs...> <trailer:1B>
```

Each KVP: `<entry_len_be:2> <field_id_be:2> <value:entry_len-4>`

`len_be` = total frame bytes − 1 (excludes one sync byte). Trailer is one zero byte.

Multiple 0x5202 frames in a single `_iap2m` are simply concatenated; parser walks them via sync-search until the buffer is exhausted.

---

## 0x5201 RouteGuidanceUpdate — 21 fields (per-tick, ~1Hz)

SDK-authoritative names from `CiAP2RouteGuidanceEngine.RouteGuidanceState` struct:

| field_id | SDK name | Type | Lens seen | Cardinality (567 frames) | Notes |
|---|---|---|---|---|---|
| 0x0000 | (header marker) | u16 BE | 2 | 1 | Always `0x002a`. First parameter / set start. |
| 0x0001 | `RouteGuidanceState` | u8 enum | 1 | 4 | Values 0/1/2/6. Likely `inactive`/`active`/`paused`/?. |
| 0x0002 | `ManeuverState` | u8 enum | 1 | 3 | Values 1/2/3. Internal maneuver lifecycle. |
| 0x0003 | `CurrentRoadName` | UTF-8 | varies | 28 | Road user is PHYSICALLY ON now. Distinct from `NaviRoadName` which is where the NEXT turn LEADS. |
| 0x0004 | (DestinationName extension) | UTF-8 | varies | 5 | Post-2017 addition. Mirrors `NaviDestinationName`. |
| 0x0005 | `EstimatedTimeOfArrival` | u64 BE | 8 | 38 | Unix seconds at arrival. |
| 0x0006 | `TimeRemainingToDestination` | u64 BE | 8 | 33 | Seconds. Mirrors `NaviTimeToDestination`. |
| 0x0007 | `DistanceRemaining` | u32 BE | 4 | 537 | Meters to destination. Mirrors `NaviDistanceToDestination`. |
| 0x0008 | `DistanceRemainingDisplayStr` | UTF-8 | 2-4 | 109 | "1.7", "350". |
| 0x0009 | `DistanceRemainingDisplayUnits` | u8 enum | 1 | 2 | 1=mi/km, 4=ft/m. |
| 0x000a | `DistanceToNextManeuver` | u32 BE | 4 | 445 | Meters to next turn. Mirrors `NaviRemainDistance`. |
| 0x000b | `DistanceToNextManeuverDisplayStr` | UTF-8 | 2-4 | 74 | |
| 0x000c | `DistanceToNextManeuverDisplayUnits` | u8 enum | 1 | 3 | 1/2/4. |
| 0x000d | `RouteGuidanceManeuverCurrentList` | packed u16 BE | 2 or 4 | 27 | **CURSOR.** len=4 → `(currentIdx, nextIdx)` pair. len=2 → `(nextIdx)` only at depart/arrival. The signal Bug A v1–v5 tried to infer; v6.1 reads it directly. **ID-shift caveat:** the firmware RE doc (2026-03-17) maps this ID to `RouteGuidanceManeuverItems(group)` with `ManeuverCurrentList` at 0x000e — sample value=1 in their capture. Our 2026-05-28 captures show 0x000d carrying the (cur,next) pair behavior and 0x000e holding a constant equal to route length (Park Way=16). Two plausible interpretations: (a) Apple shifted IDs between iOS versions and the SDK names migrated to new positions; (b) the firmware RE author labeled by table position rather than empirical behavior. Either way the SDK string-table entries `"RouteGuidanceManeuverCurrentList"` (rodata 0x74ea0) and `"RouteGuidanceManeuverCount"` (rodata 0x74ec1) both exist in `ARMiPhoneIAP2`, so both names are valid SDK identifiers regardless of which wire ID currently carries them. v6.1's parser is empirically correct (10 V6_FIRED, 0 LAG across Park Way + Alaska). Recommend a Ghidra pass on the patched binary to settle the ID-position question. |
| 0x000e | `ManeuverCount` | u16 BE | 2 | 6 | Total maneuvers in current route. Park Way=16, Alaska=15. See ID-shift caveat in 0x000d row. |
| 0x000f | `RouteGuidanceVisibleInApp` | u8 bool | 1 | 1 | Always 1 in captures. |
| 0x0010 | `LaneGuidanceCurrentIndex` | u16 BE | 2 | 1 | Always 0 in current captures (no lane-guidance active). Verified via iOS 26.5 IPSW analysis 2026-05-28. |
| 0x0011 | `LaneGuidanceTotalCount` | u16 BE | 2 | 1 | Always 0 in current captures. Total lane-guidance slots in current route. |
| 0x0012 | `LaneGuidanceShowing` | u8 bool | 1 | 1 | Always 0 in current captures. Boolean: whether lane guidance is currently visible. |
| 0x0013 | `SourceName` (AppName) | UTF-8 | 11 | 1 | "Apple Maps". Mirrors `NaviAPPName`. |
| 0x0014 | `SourceSupportsRouteGuidance` | u8 bool | 1 | 1 | Always 1 — the navigation source (iPhone Maps) inherently supports route guidance. |

**Fields 0x0010–0x0014 — RESOLVED 2026-05-28 via iOS 26.5 IPSW analysis:**

All four previously-unknown fields recovered authoritatively. Source: `+[ACCNavigationRouteGuidanceUpdateInfo keyForType:]` in `/System/Library/PrivateFrameworks/AccessoryNavigation.framework/AccessoryNavigation` (iOS 26.5 build 23F77, iPhone18,4). Method address `0x226ac5f74`, jump table `0x226ac61e8`. Disassembly traced each integer-case to its `_ACCNav_RGUpdate_*` string-literal symbol.

Constants explained:
- `LaneGuidanceCurrentIndex/TotalCount/Showing` = 0 because the captured routes (Park Way, Alaska) didn't have Apple Maps lane guidance overlays active. Driving an interstate with multi-lane exit decisions would surface non-zero values.
- `SourceSupportsRouteGuidance` = 1 always: iPhone is the navigation source and inherently supports route guidance.

### Additional fields Apple supports (NOT yet captured — IDs 0x15–0x1a)

The `keyForType:` switch reveals 6 more fields the iOS 26 SDK supports that haven't appeared in our captures:

| Wire ID | iOS 26 SDK Name | Conditions to capture |
|---|---|---|
| 0x15 | `DestinationTimeZoneOffsetMinutes` | Drive a cross-time-zone route |
| 0x16 | `StopType` | Multi-stop route with via points |
| 0x17 | `ChargingStationInfoList` | EV vehicle profile + route through chargers |
| 0x18 | `ArrivalBatteryLevel` | EV vehicle |
| 0x19 | `DepartureBatteryLevel` | EV vehicle |
| 0x1a | `FinalWaypointBatteryLevel` | EV vehicle multi-stop |

Total RouteGuidanceUpdate fields supported by modern iOS: **26** (vs 21 we observed). Our v6.1 parser silently ignores any unhandled ID, so these extensions are forward-compatible.

---

## 0x5202 RouteGuidanceManeuverUpdate — 13 fields (per-maneuver, route-plan burst)

iOS 26 SDK-authoritative names from `+[ACCNavigationManeuverUpdateInfo keyForType:]` at `0x226ac77ec` with jump table at `0x226ac72fc`:

| field_id | iOS 26 SDK Name | Type | Notes |
|---|---|---|---|
| 0x0000 | (header marker / DisplayComponentID) | u16 BE | Always `0x002a` |
| 0x0001 | `Index` (maneuver_index) | u16 BE | 0-based, contiguous within burst |
| 0x0002 | `ManeuverDescription` | UTF-8 | Apple's spoken announcement |
| 0x0003 | `ManeuverType` | u8 | CPManeuverType enum 0-53. See `../06_Reference/maneuver_types.md`. |
| 0x0004 | `AfterManeuverRoadName` | UTF-8 | Post-maneuver road name, can be empty |
| 0x0005 | `DistanceBetweenManeuver` | u32 BE | Distance to THIS maneuver from prior (meters) |
| 0x0006 | `DistanceBetweenManeuverDisplayString` | UTF-8 | "30", "0.2" |
| 0x0007 | `DistanceBetweenManeuverDisplayUnits` | u8 | 1=mi/km, 4=ft/m |
| 0x0008 | `DrivingSide` | u8 | 0=RHD, 1=LHD, 2=other observed |
| 0x0009 | `JunctionType` | u8 | Intersection / Y-fork / etc. 0 observed across captures |
| 0x000a | `JunctionElementAngle` | i16 BE | **Multi-occurrence** per junction (one per spoke arm) |
| 0x000b | `JunctionElementExitAngle` | i16 BE | Signed degrees |
| 0x000c | `LinkedLaneGuidanceInfo` 🆕 | (group) | Links maneuver to a lane-guidance display block — not yet captured |
| 0x000d | `ExitInfo` 🆕 | (group) | Highway exit info (exit number, side) — not yet captured |

Adapter parser note: `iAP2UpdateEntity.cpp:314 ASSERT "dict"` historically dropped `JunctionElement*` group data because the legacy adapter parser doesn't handle iAP2 dictionary types. The raw 0x5202 hex in `_iap2m` bypasses this — `Iap2RouteParser.kt` parses multi-occurrence field 0x000a correctly host-side.

Fields `LinkedLaneGuidanceInfo` (0x0c) and `ExitInfo` (0x0d) are iOS 26 additions that require the adapter to advertise corresponding capability flags during component registration (see [SDK Delta doc](iap2_sdk_delta_r14g17_to_ios26.md)).

---

## Per-step NaviJSON burst keys

Apple emits these when ManeuverIdx advances on the iPhone. The carlink_native NavigationStateManager uses these as the "burst pair" detection mechanism (BURST_THRESHOLD_MS = 50ms):

| Key | Type | Notes |
|---|---|---|
| `NaviManeuverType` | int (CPManeuverType) | Direct |
| `NaviOrderType` | int | Apple's burst-sequence enum. 16=roundabout context, 6=turn context. App ignores currently. |
| `NaviRoadName` | string | Where the NEXT turn LEADS (matches `ManeuverDescription` more often than `AfterManeuverRoadName`) |
| `NaviTurnSide` | int | Driving side / left-right |
| `NaviTurnAngle` | int | Enum (NOT degrees) |
| `NaviRoundaboutExit` | int | 1-19 |
| `NaviJunctionType` | int | Documented in firmware but never observed in any forwarded message |

---

## Maneuver type extensions discovered 2026-05-28

The following CPManeuverType integers were observed in Apple Maps emissions but absent from prior carlink_native dispatch:

| mt | Meaning |
|---|---|
| 14 | "<Road>" / "<N> <Hwy>" — generic continue-on-road |
| 24 | "On your left: <landmark>" — arrival approach left |
| 25 | "On your right: <landmark>" — arrival approach right |
| 29 | "<road> to <destination>" — post-roundabout multi-direction |
| 30 | "<road>" in roundabout context — roundabout take-Nth-exit |
| 49 | slight left |
| 50 | slight right |

All 7 are dispatched by current `ManeuverMapper.kt` and `ManeuverComposer.kt`. Caution: do NOT assume the remaining 47 unobserved integers are non-driver modes — these 7 were found by surprise from new routes, more may surface.

---

## Telephony — CallState (`0x4155`) and Communication (`0x4158`)

The adapter's `ARMiPhoneIAP2` also parses Apple's iAP2 **telephony** streams. The stock firmware
forwards only a stripped CallState subset (subtype-100 JSON) and forwards no Communication data at
all (its Communication engine is dormant). The raw frames are recovered by the CALL and COMM
binary patches as MetaData **subtype-100 `_callraw`** and **subtype-101 `_commraw`** respectively —
see [`../04_Implementation/iap2_binary_patches.md`](../04_Implementation/iap2_binary_patches.md) for
the patch mechanism and [`usb_protocol.md`](usb_protocol.md) for the subtype map.

### Telephony message-id family (device-verified from `/tmp/ttyLog` + binary)

| id | message | direction | notes |
|---|---|---|---|
| `0x4154` | StartCallStateUpdate | accessory→phone | subscribe |
| `0x4155` | **CallStateUpdate** | phone→accessory | call data (subtype-100 path) |
| `0x4156` | StopCallStateUpdate | accessory→phone | |
| `0x4157` | StartCommunicationUpdate | accessory→phone | subscribe (stock never sends it — see COMM patch) |
| `0x4158` | **CommunicationUpdate** | phone→accessory | telephony status (subtype-101 path) |
| `0x4159` | StopCommunicationUpdate | accessory→phone | |

> **Correction:** the `0x57xx` family is **WiFi/config** (`0x5702`/`0x5703` WifiConfigInfo), **not**
> telephony. Earlier notes that hooked `0x2b84c` / `0x5702` for "comm" were targeting the WiFi
> handler; the real CommunicationUpdate is `0x4158`.

### `0x4155` CallStateUpdate — parameter map

Frame: `4040 <len BE> 4155` then params `<len BE><id BE><value>` (same KVP framing as RouteGuidance,
iAP2 message at frame offset 9). For ordinary 1:1 calls **iOS sends exactly these 5 flat params,
never more** (device-verified across cellular + FaceTime, in/out, answered/missed/declined):

| id | field | type | notes |
|---|---|---|---|
| 0 | RemoteID | string | E.164 number |
| 1 | DisplayName | string | contact name, or formatted number if unresolved |
| 2 | CallStatus | u8 enum | see enum below |
| 3 | CallDirection | u8 | `1` incoming · `2` outgoing |
| 4 | CallUUID | string | **real**, sent by the phone, == the stock `CallID` (not the firmware's fabricated fallback) |

**CallStatus enum (corrected):** `0` ended/idle · `1` dialing (outgoing) · `2` ringing (incoming) ·
`3` connecting (brief post-answer step) · `4` **active** (long-lived; observed persisting ~71 s on a
live call). Lifecycles: incoming-answered `2→3→4→0`, outgoing `1→4→0`, missed/declined `2→0` (no
answer). *(Supersedes the earlier "3=connected, 4=disconnecting" — that was wrong; also corrected in
[`usb_protocol.md`](usb_protocol.md).)*

The firmware parser *can* also hold ids `6 AddressBookID · 7 Label · 8 Service · 9 IsConferenced ·
10 ConferenceGroup · 11 DisconnectReason` (struct offsets `+0xe8…+0x188`), but **iOS does not put
them on `0x4155` for normal 1:1 calls** regardless of subscription. There is **no explicit "missed"
flag**; the "Missed" recents entry and voicemail badge seen in CarPlay are **rendered by iOS into the
H.264 video stream (pixels)**, not sent as telephony data. The voicemail/missed counts, signal, mute,
call-count and FaceTime-vs-cellular type are carried by `0x4158` (below).

### `0x4158` CommunicationUpdate — parameter map

Recovered only after the COMM patch enables the dormant Communication engine (the iPhone then streams
`0x4158` after the patched `StartCommunicationUpdate(0x4157)`). Frame: `4040 <len BE> 4158` then
params `<len BE><id BE><value>`. Field map is **dual-confirmed** against two independent shipping
wireless-CarPlay middleware stacks (Cinemo/Nme x86-64 + aarch64) and the Apple R14G17 SDK; every
property is optional (iOS includes one only when it has a value):

| id | field | type |
|---|---|---|
| 0 | SignalStrength | u8 |
| 1 | RegistrationStatus | u8 |
| 2 | AirplaneMode | bool |
| 3 | *(unsupported / skipped)* | — |
| 4 | Carrier / ProviderName | string |
| 9 | MuteStatus | bool |
| 0x0A | CurrentCallCount | u8 |
| 0x0B | NewVoicemailCount | u8 |
| 5–8, 0x0C–0x11 | telephony/FaceTime capability flags (CellularSupported, TelephonyEnabled, FaceTimeAudio/Video, InitiateCall/EndAndAccept/HoldAndAccept/Swap/Merge/Hold availability) | bool |

The subscribe request (`0x4157`) carries one empty parameter per requested id
`{0,1,2,4,5,6,7,8,9,A,B,C,D,E,F,10,11}` (id 3 deliberately skipped). Host-decoded live examples:
`signal=1 reg=4 carrier=AT&T mute=false calls=0 voicemail=0`, and an airplane-toggle delta
`signal=0 reg=1 airplane=true carrier="Airplane Mode"`.

---

## Implementation references (in this repo)

| File | Role |
|---|---|
| `app/src/main/kotlin/com/carlink/navigation/Iap2StateParser.kt` | Parses 0x5201 (`_iap2`) into `Iap2RouteGuidanceState`. Versioncode 136+. |
| `app/src/main/kotlin/com/carlink/navigation/Iap2RouteParser.kt` | Parses 0x5202 (`_iap2m`) into `Iap2RouteData`. |
| `app/src/main/kotlin/com/carlink/navigation/Iap2ManeuverData.kt` | Data class for per-maneuver route plan entry. |
| `app/src/main/kotlin/com/carlink/navigation/NavigationStateManager.kt` | Reads parsed state; v6.1 cursor body authoritative on field 0x000d. v5 fallback for len=2 frames. |
| `app/src/main/kotlin/com/carlink/CarlinkManager.kt` (~line 2512) | Dispatches `_iap2` to `Iap2StateParser.parse()` → `setLastIap2State()` before `onNaviJson`. |
| `app/src/main/kotlin/com/carlink/navigation/compose/ComposedIconStore.kt` | Consumes parsed route plan, pre-composes icons. |

---

## Related documentation

- `../04_Implementation/iap2_binary_patches.md` — the NAV/CALL/COMM raw-passthrough patch mechanism (code cave, hooks, deploy gate) that forwards `_iap2`/`_iap2m`/`_callraw`/`_commraw`
- `../06_Reference/key_binaries.md` — Full ARMiPhoneIAP2 binary RE including all 9 iAP2 engines
- `usb_protocol.md` — Outer USB envelope (0x55AA55AA magic, 16-byte header, MediaType=NAVI_JSON sub-type 200 routing)
- `command_ids.md` — Adapter command surface
- `wireless_carplay.md` — CarPlay session lifecycle (PLUGGED → Phase progression → iAP2 active)
- Memory: [[carlink_iap2_host_parsing_gap]] — Why host parsing was missing and how v6.1 closed it
- Memory: [[carlink_bug_a_cluster_ahead]] — Bug A history (SOLVED via field 0x000d parsing)
- Apple SDK source: `documents/reference/.../AppleCarPlay_CommunicationPlugIn_IntegrationGuide.txt` (R14G17, 2017)

# External Landscape Survey — Open-Source Wireless CarPlay Receivers

**Compiled:** 2026-06-23
**Method:** Authenticated GitHub sweep (full `45clouds/WirelessCarPlay` fork network +
issue threads + GitHub-wide repo/code search) and an authenticated GitLab global search.
**Scope:** Who else is building a *dongle-free* wireless-CarPlay **receiver** (the Pi/Linux
"head unit" role), and has anyone gotten past the stage where our own work stalls.

> **Calibration (repo rule):** A result is treated as REAL only where a public artifact
> (committed code, shipping package, or captured trace) proves it. Forum claims with no
> shared artifact are marked **CLAIM**. This mirrors the discipline in the firmware docs.

---

## 0. Why this matters — where *our* stack actually stalls

On the last Linux-workstation test, using the **CCPA-as-NCM MFi oracle** for authentication:

- **MFi/iAP2 authentication SUCCEEDS** — the iPhone accepts the host and **registers it as a
  CarPlay device.** This half is solved for us.
- **The failure is later:** during **CarPlay session negotiation and the BT→Wi-Fi
  switchover**, iOS **ends the session before any A/V can be received/confirmed.** We never
  get to a sustained video/audio stream.

So the open question this survey answers is **not** "how to do MFi" (we have that) — it is
**"who has a *verified, sustained* post-auth CarPlay session we can diff our negotiation and
hand-over against."** That reframes which projects are valuable to us (see §4).

---

## 1. `45clouds/WirelessCarPlay` fork network — definitive verdict

`45clouds/WirelessCarPlay` is the open mirror of Apple's **AccessorySDK (R14G17 / v320.17)** —
the same SDK source our Pi-side receiver work is built on. It has ~1,017★ and **175 forks**.

**Full divergence sweep (every fork, authenticated):** only **3 forks carry *any* original
commit**; all others are passive mirrors.

| Fork | Ahead / Behind | What the commits actually change | Verdict |
|---|---|---|---|
| **signalius** (9★, Jan 2026) | +5 / 0 | **Port/compile fixes only**: 1-line tweaks to `MFiServerPlatformLinux.c`, `AirPlayReceiverPOSIX.c`, `airplayutil.c`, plus `compile_rpi5.sh` scripts and `+66` lines in the `AppStub` example. Gets it building on **Pi 5 / Debian Trixie 13.3** and the **MFi 3959 / "CP2.0" chip answering on `/dev/i2c-1`**. | Author's own words: *"still not working out of the box… cannot stream anything to the HeadUnit."* Pursuing the **bridge** (phone→Pi→car-USB) direction, not the receiver. |
| **demianzenkov** (2★, 2023) | +3 / +3 | Got `AppStub.c` to **compile** (math-lib fix). | No connection. |
| **trouble-bao** | +2 / 0 | README edits only. | Nothing. |

**Takeaway:** the entire 45clouds lineage tops out at *"compiles on a Pi + the MFi chip
responds."* That is **behind** where we already are (we have a committed
BT→Wi-Fi→`AuthSuccess` handover). No fork has a sustained session.

---

## 2. The 45clouds issue threads — 6 years of claims vs. artifacts

~28 issues, ~150 comments (2020–2026). Pattern: lots of help-seeking, two recurring
"it works" claims, **none with shared code**.

- **`hbouhadji`** (#1, 2022; active again #26, 2025): **CLAIM** of a working **Pi 4 wireless
  receiver** — but only via a **jailbroken iPhone** + reversing/patching the iOS-side MFi
  auth binaries + hand-rolled BT/hotspot scripts. *No PoC ever posted.* Says real MFi
  hardware would remove the jailbreak need but "didn't pursue."
- **`mcr-ksh`** (#1, 2022): **CLAIM** "works with a custom PCB and MFI chip." No artifact.
- **`tr1fled`** (#26/#28, 2025–26): **CLAIM** of a working receiver "with help from some
  people"; all collaboration moved to Discord (`@haumeium` → `@longpax`). No public code.

**MFi consensus across all threads = exactly our hardware finding:** you need the genuine
Apple coprocessor — part **`MFI337S3959` ("CP2.0")**, sourceable on AliExpress or desoldered
from a dongle — talking I²C through `AccessorySDK/Support/MFiServerPlatformLinux.c`
(`kMFiAuthDevicePath "/dev/i2c-1"`). The recurring **MITM idea** ("proxy the car head unit's
own MFi auth through the Pi") was raised repeatedly and **concluded infeasible** by the
community. Our **CCPA-as-NCM remote oracle is the most advanced realization** of "use a real
chip remotely" anywhere in this ecosystem — and needs neither a jailbreak nor soldering.

---

## 3. Wider GitHub landscape (outside the 45clouds lineage)

GitHub-wide repo + code search. Four buckets:

**A. Dongle-based receivers** (consume a CPC200/Carlinkit — *not* dongle-free; same family as
node-CarPlay / pi-carplay):
- `harrylepotter/carplay-receiver` (401★) — pycarplay fork, Linux, mpv A/V output.
- `mzyy94/gocarplay` (55★) — Go dongle library.
- `marcraft2/tesla-carplay` (146★) — dongle + WebSocket video to the Tesla browser.
- `Laptopmini/PorschePi` (31★) — RPi head unit, OpenAuto Pro + CarPlay plugin (dongle).

**B. Bridge / USB-gadget approach** (Pi between phone and car — the signalius/U2W direction):
- `kgalvan/VelosterPlay` — *explicitly* the "Pi presents as wired CarPlay via USB gadget mode
  + transparently proxy the head unit's MFi auth" architecture, built on node-CarPlay.
  **Status: "Phase 1 — initial setup"** (not working). Confirms the MITM/bridge route remains
  unproven by anyone publicly.

**C. The one publicly-working software receiver — `amineross/showcase`** → see §4.

**D. OEM head-unit-side RE** (surfaced via a `wirelessCarPlayTransportComponent` code search;
useful as additional diff targets, none is a dongle-free Pi receiver):
- `luka-dev/mib2q-carplay-rgi` (VW MIB2Q), `suburbazine/hyundai-meego` +
  `xx979xx/hyundai_meego_system` (Hyundai), `HaToan/carplay-wifi-extractor`,
  `EthanArbuckle/iPhone18-3_26.1_23B85_Restore` (iOS-side strings).
- *(Sanity check: the same search also returned our own `lvalen91/CPC200-CCPA_resources`,
  confirming the query hits the right cluster.)*

---

## 4. `amineross/showcase` — the verified-session reference (most valuable find)

[`amineross/showcase`](https://github.com/amineross/showcase) (100★, May 2026) is a
**publicly-working software wireless-CarPlay receiver**, shipping as a Sileo/Cydia package
with a [protocol write-up](https://aminerostane.com/articles/showcase). It turns a
**jailbroken cellular iPad** into the
receiver: the iPhone pairs over BT, joins the iPad's hotspot, streams CarPlay, and the iPad
renders it.

**How it handles each layer:**
- **Auth (MFi bypass):** *not* an MFi chip. It extracts a **BAA leaf certificate** (Apple's
  *internal* CA, reverse-engineered from **Apple's CarPlay Simulator**) and presents that —
  *"the iPhone walks the chain, sees an Apple signature at the root, and accepts the iPad as a
  real car."* (This realizes the `JJTech0130` BAA speculation from 45clouds issue #15.)
- **Bluetooth:** replaces iOS `bluetoothd` with **BTstack** (`BTdaemon` + `libBTstack.dylib`),
  a user-space raw-HCI stack, so it can advertise as a CarPlay accessory.
- **Handover:** standard CarPlay flow — BT pair → iPhone hands Wi-Fi creds → both move to a
  private network (hotspot creds pre-configured).
- **A/V:** **video works fully** (H.264 decoded on the iPad GPU); **audio incomplete**
  (still routed from the iPhone, author "still digging into this").

**Why it matters to *us* (the reframing):**
We **cannot use its auth path** — it requires the receiver to *be* an Apple device with a
jailbreak, and we have no jailbroken iPhone. **Its value is the half we are stuck on (§0):**
it demonstrates a **verified, sustained post-auth CarPlay session** — exactly the
**negotiation + BT→Wi-Fi switchover** stage where iOS currently tears our session down.
Even though it sidesteps MFi, *it still had to perform the same session handshake correctly.*

**Action when we reach the negotiation-debug phase:** read the Showcase protocol write-up and
(if obtainable) inspect its session setup for the **order and content of the post-auth control
messages, the mode/stream declarations, and the precise Wi-Fi hand-over sequence** — diff our
negotiation against a setup that is known to *not* get torn down. Pair this with our genuine
CCPA reference captures (`flash_dumps`/session traces) for a two-sided diff.

---

## 5. GitLab — effectively empty (authenticated global search)

Authenticated `glab` global search for `wireless carplay`, `carplay receiver`,
`carplay raspberry`, `carplay mfi` → **no results.** The CarPlay-RE community is on GitHub
(plus Chinese forums/CSDN), not GitLab. One adjacent, genuinely useful tool surfaced under
`iap2`:

- **`schaefer-services/linux_iap2-analyser`** (GitLab, updated 2026-06-20) — *"Bluetooth
  Protocol Analyzer for Raspberry Pi 4B"*: BT Classic (SDP/L2CAP/RFCOMM), BLE / Apple Core
  Bluetooth manufacturer-data parsing, **iAP2 packet parsing + handshake description**, **MFi
  auth-flow analysis + certificate inspection**, and External Accessory (EA) session
  analysis. A ready-made **diagnostic** for our exact BT/iAP2/MFi layer — worth evaluating as
  an instrument for the negotiation-stage debugging in §4.

*(Tooling note: `gh` is GitHub-only; GitLab requires `glab` or the GitLab REST/GraphQL API.
Both are installed and authenticated as of this survey.)*

---

## 6. Net conclusion & new leads to track

**Net:** No one publicly has a committed, working, **dongle-free, non-Apple-hardware**
CarPlay receiver. The only public "it works" (`amineross/showcase`) wins by running on a
jailbroken Apple device. Our CCPA-NCM-oracle path remains the most viable route to a true
Pi-native receiver — and our blocker (post-auth session teardown) is the same wall the entire
field hits; the field just mostly stops *before* auth, where we are already past.

**New leads not previously tracked in our docs:**
1. **[`amineross/showcase`](https://github.com/amineross/showcase) + its
   [protocol write-up](https://aminerostane.com/articles/showcase)** — verified-session
   reference for the negotiation / Wi-Fi-handover stage (§4). *Highest value for our current
   blocker.*
2. **`schaefer-services/linux_iap2-analyser`** (GitLab) — RPi BT/iAP2/MFi/EA analyzer tool.
3. **`BertoldVdb/WACResearch`** — cited repeatedly as the BT + Wi-Fi/WAC handover starting
   point.
4. **Part `MFI337S3959` / "CP2.0"** — the exact MFi chip the community standardized on (we
   already drive the genuine chip via the CCPA oracle; recorded here for completeness).
5. **OEM head-unit RE repos** (§3.D) — extra diff targets for control-plane behavior.

**Already in our orbit (for reference):** `ludwig-v/wireless-carplay-dongle-reverse-engineering`,
`wiomoc.de/.../mfi_iap.html`, `f-io/pi-carplay`, `rhysmorgan134/node-CarPlay`,
`electric-monk/pycarplay`.

---

## 7. Second sweep — GitHub MFi part-number + CarPlay-project search (2026-06-23)

A targeted GitHub code/repo search on the known MFi part numbers and broad CarPlay terms (GitLab
re-checked, still empty bar Mazda/Carlinkit dongle noise). New, not previously tracked:

### 7.1 MFi hardware — directly relevant to a dedicated-chip build

- **[`signalius/MFI_Chip_Rpi_Hat`](https://github.com/signalius/MFI_Chip_Rpi_Hat)** (KiCad,
  GPLv3) — an **open-source Raspberry Pi HAT PCB** for the MFi coprocessor over **I²C**, tested on
  **Pi 5 and Zero 2 W**, with USB-C OTG power, and **JLCPCB gerbers included** (orderable as-is).
  Carries **two parts on one board**: `U1 = MFI343S00177` (UDFN-8 2×3 mm) and
  `U2 = MFI337S3959` (WSON-8 2.5×2.5 mm). I²C pull-ups 4k7, USB-C CC 5k1. Ships a Python i²c
  cert/challenge reader (`app_cert_reading/auth.py`) and **four decoded sample certs**. This is
  the most actionable artifact for putting a real chip on a Pi (our stage 3).
- **THE KEY HARDWARE INSIGHT — the two chip generations are cryptographically different:**
  | | `MFI337S3959` (2.0C) | `MFI343S00177` (3.0) |
  |---|---|---|
  | Algorithm | **RSA-1024 / SHA-1** | **ECDSA P-256 / SHA-256** |
  | Issuer CA | "Apple iPod Accessories CA" | "Apple Accessories CA – 00000002" |
  | Cert validity | 2015 → **2022 (expired, still accepted)** | 2022 → **2049** |
  | Challenge size | **20 bytes** | **32 bytes** |
  | Our status | this is what the **CCPA has**; we drive it via the NCM oracle | newer part; **not** what the AccessorySDK RSA path expects |

  Implication for the stage-3 purchase: the **3959** is the safe choice (matches our proven CCPA
  path and the AccessorySDK's 20-byte/RSA `MFiServerPlatformLinux.c` flow), even though its cert
  expired in 2022 — current iOS still accepts it (we've proven this). The **00177** is future-proof
  (valid to 2049) but uses ECDSA + a 32-byte challenge, so it would need the newer SDK auth path.

### 7.2 Independent confirmation of our oracle architecture

- **[`cvetaevvitaliy/carplay`](https://github.com/cvetaevvitaliy/carplay)** (28★, C) — a standalone
  Linux CarPlay receiver built on an **older `R11B` AccessorySDK** (a different era from our
  R14G17) + `mDNSResponder-567`. Its **`auth.c` is our exact pattern**: read the MFi chip over i²c
  and expose it as a **TCP oracle (port 5196)** — `cmd 0` = read cert, `cmd 1` = challenge →
  response. We do the same over TCP 5290 to the CCPA. Independent validation that the
  networked-MFi-oracle design is sound.
- **Canonical MFi i²c register map** (agreed by `signalius/auth.py`, `cvetaevvitaliy/auth.c`, and
  the AccessorySDK `MFiServerPlatformLinux.c`): i²c addr `0x10`/`0x11`; regs `0x10`=status (write
  `0x01` to start; success when `& 0xF0 == 0x10`), `0x11/0x12`=response len/data, `0x20/0x21`=
  challenge len/data, `0x30/0x31`=certificate len/data (cert read in 128-byte chunks).
- **[`xueming1988/test1`](https://github.com/xueming1988/test1)** — bundles **MapleSDK** +
  `mfi_airplay` + `AirPlayAudioPOSIXReceiver/Platform_NetBSD_Pi`; another AccessorySDK variant for
  a Pi. Reference mirrors: `maaiika/Carplay`, `Amoystyle/hao31.zhang`.
- **[`HaToan/carplay-wifi-extractor`](https://github.com/HaToan/carplay-wifi-extractor)** (Python,
  asyncio) — *deep-read 2026-06-23.* A clean, modern, pure-software **iAP2 stack**: link layer
  (`ff 55`/`ff 5a` SYN/NEGO/ACK + CRC, `link_layer.py`), BlueZ RFCOMM + BLE transport, full
  **Control Session Message** codecs (start marker `0x4040`; header `>HHH`; TLV params `>HH`), and
  a **switchable software/hardware MFi** module (`mfi_auth_coprocessor.py`, same `0x10/0x11/0x12/
  0x20/0x21/0x30/0x31` map — 4th independent confirmation). Its CSM defs match our `iap2_link.c`
  exactly: `0x5703` WiFi config (`ssid`=1, `passphrase`=2, `security`=3, `channel`=4), `0x4E0D`
  WirelessCarPlayUpdate, `0x4E0E` DeviceTransportIdentifier, EAP session `0xEA00/01/03`.
  **Value to us:** the cleanest readable iAP2/CSM/TLV reference to cross-check our BT-phase
  encoders; plus a novel **client mode** that emulates an iPhone to *extract a real car's WiFi
  credentials* (a diagnostic tool). **Scope limit:** like e46 it covers the iAP2/handoff phase
  (which we've solved) and **stops at WiFi handoff — it does not implement the AirPlay/RTSP
  receiver**, so it does not address our post-auth teardown. *(Per project instruction, the CVE/
  attack-surface blog referenced by this repo was deliberately not investigated.)*

### 7.2a AirPlay-receiver layer — the only OSS project at our blocked layer

- **[`rednblkx/AirLib`](https://github.com/rednblkx/AirLib)** (C++, boost::asio) — *deep-read
  2026-06-23.* The **only** open-source project found that sits at the **AirPlay/CarPlay receiver
  layer** itself (where our session tears down), rather than the iAP2/auth/handoff side. Clean,
  modern: `APServer`(/info+RTSP), `APSession`, `APSessionScreen`, `APTimeSync`, `eventConnection`,
  `keepAliveManager`, SRP/MFiSAP/TLV8, plistcpp, GStreamer example. Dongle-free; needs MFi hardware
  (which we have via the oracle). Author `rednblkx` is a credible Apple-protocol RE dev
  (HomeKey-ESP32 982★, HAP libs, a `UxPlay-CP` fork).
  **⚠️ Experimental ("partial CarPlay", low stars) — NOT a verified-sustaining session like the
  CCPA capture or Showcase. Use as a structural cross-check / parts bin, not ground truth.**
  Useful concrete items it yields:
  - **Architecture** (matches the SDK): control SETUP allocates timing+keepAlive+event ports;
    screen SETUP *requires* timing already initialized, derives the screen key, returns `dataPort`;
    RECORD starts the event-channel thread.
  - **Screen-stream key derivation:** HKDF salt `"DataStream-Salt<streamConnectionID>"`, info
    `"DataStream-Output-Encryption-Key"`, 32 B — exact strings to verify a receiver's screen key.
  - **Fullest modes/constraint model:** `ResourceConstraint{ANYTIME=100, USER_INITIATED=500,
    NEVER=1000}` + `permanentEntity` per resource.
  - **Divergence worth noting:** AirLib does **not** block RECORD-200 on timing completion (async
    timing) — the opposite of Showcase's hard gate; a weak third data point on that question.

### 7.3 Active SBC CarPlay peers (same goal, different hardware)

- **[`zhongyuanluo-cmd/e46-smart-dash`](https://github.com/zhongyuanluo-cmd/e46-smart-dash)**
  (RK3566 + Qt6, C++, updated 2026-06-20) — BMW E46 smart dash with **wireless CarPlay**, and
  committed docs `参考 - carplay实现` (impl) + **`参考 - mfi芯片debug`** (MFi-chip debug) + a
  `memories/repo`. Very active, sophisticated. **★ ADOPTED AS A SUPPORTED ONGOING SOURCE**
  (re-check as testing progresses). *Deep-read 2026-06-23:* independently reached our exact
  architecture; carries Apple's official **`MFI337S3959` spec PDF** + the full CP 2.0C register
  map (folded into `_evidence/MFi_research/docs/register_map.md`), a practical MFi-chip bring-up/
  debug guide, and names `HaToan/carplay-wifi-extractor` as its porting base (over 45clouds). It
  is strong on the iAP2/MFi/handshake + hardware side (our solved half) and only covers the
  post-auth AirPlay session at a high level — so it aids **stages 2–3 (real-chip bring-up)**, not
  the current teardown blocker.
- **[`nikit6000/QDPlay`](https://github.com/nikit6000/QDPlay)** (12★, C, 2025) — "CarPlay → QDLink
  bridge"; bridges the CarPlay video stream to QDLink-equipped head units. References the MFi part.

### 7.4 Dongle-based receivers (broader ecosystem; mostly our known cluster)

- **[`niellun/FastCarPlay`](https://github.com/niellun/FastCarPlay)** (112★, 2026) — Linux
  CarPlay+AA receiver for Carlinkit dongles; a newer alternative to pi-carplay / node-CarPlay.
- **[`okcar-os/android`](https://github.com/okcar-os/android)** (1028★) — LineageOS/Android-13
  in-car OS that talks to head units via the CarPlay protocol (runs on Android phones).
- `Veyron2K/Carlinkit-CPC200-Autokit-Reverse-Engineering` (67★), `segfly/carlinkit-modding` (27★),
  `Henkru/cplay2air-wifi-passphrase-patch` (16★) — Carlinkit/CPC200 RE & modding.

### 7.5 Updated leads

- **`MFI343S00177`** added as a known part (ECDSA/SHA-256, valid to 2049) alongside
  `MFI337S3959`/"CP2.0".
- **`signalius/MFI_Chip_Rpi_Hat`** = ready-to-order open hardware for stage 3.
- **`cvetaevvitaliy/carplay` `auth.c`** = reference i²c-MFi TCP-oracle (validates our design) + an
  older `R11B` SDK to diff protocol evolution against.
- **`HaToan/carplay-wifi-extractor`** = cleanest pure-Python iAP2/CSM/link-layer reference + an
  iPhone-emulating client to extract a real car's WiFi creds (diagnostic). Cross-check for our
  BT-phase encoders; does not cover the AirPlay receiver.
- **`zhongyuanluo-cmd/e46-smart-dash`** = ADOPTED supported ongoing source (official chip spec +
  bring-up guide + impl research); re-poll as testing progresses.
- **`rednblkx/AirLib`** = only OSS project at the AirPlay-receiver layer (our blocked layer);
  experimental, structural cross-check only. Yields exact screen-key salt/info + fullest modes
  model. Mine author `rednblkx`'s org for HAP/pairing-crypto references if needed.
- GitLab remains effectively empty for CarPlay (confirmed twice).

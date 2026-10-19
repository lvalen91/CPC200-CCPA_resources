# iAP2 Raw-Passthrough Binary Patches (ARMiPhoneIAP2)

**What this is:** three reverse-engineered binary patches to the adapter's `ARMiPhoneIAP2`
daemon that recover rich iAP2 data the stock firmware parses but discards before it reaches the
host. All three use the same technique — an ARM trampoline in a code cave that captures the
**original raw iAP2 frame** and forwards it hex-encoded as one extra JSON key — so the host
re-parses the full TLV itself instead of re-implementing Apple's parsers.

**Artifacts** (builders, patched binaries, deploy scripts): `../../custom/patches/README.md`.

**Status:** NAV v5 — working/production (host carlink_native). NAV v6 (= v5 + ExitInfo "P1", §4.1) —
device-verified 2026-10-19 with the carlink_macOS log-only probe, **not shipped by any app yet**. CALL — device-verified (host
carlink_macOS). COMM — device-verified end-to-end + host-decoded (host carlink_macOS).
All on board A15W, firmware `2025.10.15.1127CAY` (NXP i.MX6UL ARMv7, kernel 3.14.52, jffs2 rootfs);
the v6 test ran on firmware `2025.12.29.1746CAY` of the same board.
*Last updated 2026-10-19 (NAV v6 / ExitInfo added; §4.1).*

> **Privacy:** real call captures contain genuine numbers/names/UUIDs. Never reproduce that PII;
> the worked example below uses the established placeholder (`Jenny` / `+15558675309`).

---

## 1. Why a binary patch is needed — the "strip" problem

`ARMiPhoneIAP2` is the userspace daemon that speaks Apple's **iAP2** session protocol to the
iPhone. It registers a set of engines (NowPlaying, RouteGuidance, CallState, Communication,
Location, …), subscribes to the matching iAP2 streams, parses every field into a struct, then a
serializer copies **only a handful of fields** into the JSON it broadcasts to the host over the
16-byte-header USB protocol (see `../02_Protocol_Reference/usb_protocol.md`). Everything else the
iPhone sent is dropped before it leaves the adapter.

This is a **parse-then-discard** pattern, and it cannot be fixed from the host: the host never
receives the dropped bytes. The fix has to be **on the adapter, inside `ARMiPhoneIAP2`, before
the serializer runs.**

Examples of what gets stripped:
- **RouteGuidance** (`0x5201`): iOS sends ~21–26 fields (roads, ETA, maneuver cursor, lane
  guidance); the stock NaviJSON exposes ~5. The maneuver cursor `0x000d` in particular is dropped
  — exactly what an external instrument-cluster nav renderer needs.
- **RouteGuidance ExitInfo** (`0x5202` id 13): the stock accessory never asks for it (its
  `StartRouteGuidanceUpdates` `0x5200` omits the `SupportsExitInfo` selector), so the phone never sends it —
  nothing is stripped; the request itself is missing. Fixed by NAV v6 (§4.1).
- **CallState** (`0x4155`): the stock subtype-100 JSON exposes only `CallStatus / CallDirection /
  CallName / CallNumber / CallID`. The parser can also hold AddressBookID, Label, Service,
  IsConferenced, ConferenceGroup, DisconnectReason — dropped by the serializer.
- **Communication** (`0x4158`): voicemail/missed counts, signal strength, registration status,
  carrier, mute, current-call-count, FaceTime capabilities. The stock firmware never forwards any
  of it — and, as it turns out, never even subscribes to it (the engine is dormant; see §6).

## 2. The core idea — raw passthrough via a code cave

Rather than re-implement Apple's parsers or re-emit individual fields (fragile: needs VFP for
numbers, one accessor call per field, large crash surface), each patch does **raw passthrough**:

> Capture the **original raw iAP2 frame** the engine received, hex-encode it, and append it as a
> single extra JSON key to the message the firmware already broadcasts. The host then parses the
> full iAP2 TLV itself.

This is minimal (a few hundred bytes of ARM), complete (forwards 100% of what the phone sent,
including fields nobody has reverse-engineered yet), and robust (it rides the firmware's existing,
proven broadcast path).

---

## 3. Shared method (applies to all three patches)

### 3.1 The code cave

`ARMiPhoneIAP2` is a **non-PIE** ELF (load base `0x10000`, so **VMA = file offset + 0x10000**).
There is a **1224-byte zero-filled gap** between the end of the R-X (executable) LOAD segment and
the next page boundary:

```
file 0x76b38 .. 0x77000   (VMA 0x86b38 .. 0x87000)   = 0x4C8 = 1224 bytes, all zero
```

Trampolines are written into that gap. The R-X LOAD program header's `p_filesz`/`p_memsz` are
extended to cover the cave so it is mapped **executable**. Scratch variables live in `.bss`
(extend the RW LOAD `p_memsz`; the loader zero-fills it). No new segments and no file growth
beyond the segment-size fields, so the modified UPX re-packs it cleanly.

> Note: an earlier internal estimate put the cave at "1944 bytes @ `0x86868`". That figure was
> wrong; the device-verified cave is **1224 bytes at file `0x76b38` / VMA `0x86b38`**.

### 3.2 Hooking model

A hook overwrites one 4-byte ARM instruction at a chosen site with a branch into the cave:
- `b cave` (no link) when the cave will **replay the displaced instruction and continue** (used
  for a function-entry `push`).
- `bl cave` (link) when the cave must **run, then return** to the instruction after the hook
  (used for a mid-function `blx`); the cave ends by executing the displaced instruction and
  `pop {…,pc}` / `bx lr` back.

AAPCS matters: callees preserve `r4–r11`, so a trampoline can rely on the cJSON-object register
surviving across `malloc`/`cJSON_*`/`free`. Keep the stack 8-byte aligned at every external call.
Re-derive/verify every hook's displaced bytes from the binary with a disassembler before applying
— each builder asserts the stock bytes, cave-zero, and segment sizes before writing the ELF.

### 3.3 Build → repack → deploy pipeline

```
factory packed /usr/sbin/ARMiPhoneIAP2  (UPX-LZMA, md5 d933c9d5, 181648 B)
        │  modified UPX (ARM) -d
        ▼
ARMiPhoneIAP2.unpacked  (ELF32 ARM, non-PIE, 494244 B, md5 f1e1a0aa; VMA = file_off + 0x10000)
        │  builder — assemble trampolines, write into the cave, extend phdr filesz/memsz,
        │            install hooks (asserts guard stock bytes, cave-zero, sizes)
        ▼
ARMiPhoneIAP2.<patch>.patched  (same 494244 B; static-verified by disassembly)
        │  modified UPX (ARM) --best   (run ON the adapter — see below)
        ▼
ARMiPhoneIAP2.<patch>.packed  (self-extracting; deployed to the device)
```

- **Disassembler** (e.g. capstone) — derive/verify hook bytes and frame layout, and self-check the
  assembled trampolines before writing the ELF. (Trampolines are hand-encoded and
  disassembler-verified because the prebuilt keystone assembler wheel fails to load on Apple
  Silicon.)
- **The repacker** is a Carlinkit-modified UPX 3.96 that round-trips this firmware's packing. It is
  a **32-bit ARM-Linux ELF**, so it **cannot run on macOS** — run it natively **on the adapter**
  (correct arch) over SSH, using a USB stick or `/tmp` as the working area, or in a Linux VM with
  32-bit ARM user emulation. Round-trip check: `--best` then `-d` must reproduce the patched ELF
  **byte-for-byte** before trusting the pack.
- Patching is done off the **static unpack** (no live `/proc/PID/mem` dump needed): the on-disk
  binary is UPX-packed and the running image is its unpacked form, so static-patch + repack the
  verified unpack.

### 3.4 The deploy gate (why deploys behave the way they do)

`ARMiPhoneIAP2` is **not** staged at boot — it is staged lazily when a phone connects, by the
phone-link daemon. The gate (from the device) is:

```sh
CopyPhoneLinkFile() {            # CarPlay case
    test -e /tmp/bin/AppleCarPlay || ( \
        cp /usr/sbin/AppleCarPlay  /tmp/bin/ ; \
        cp /usr/sbin/ARMiPhoneIAP2 /tmp/bin/ )
}
RunLinkProcess()  { ARMiPhoneIAP2 ; }                 # exec from PATH (/tmp/bin first)
EndLinkProcess()  { killall ARMiPhoneIAP2 ; killall AppleCarPlay ; }   # on disconnect
```

The gate tests for **`/tmp/bin/AppleCarPlay`**, *not* for `ARMiPhoneIAP2`. When AppleCarPlay is
absent it copies **both** factory binaries from `/usr/sbin` into `/tmp/bin`. `RunLinkProcess`
execs `ARMiPhoneIAP2` from `PATH` (which has `/tmp/bin` first), and the link loop re-execs it each
session while the lockfile exists.

**Firmware SendFile (USB type `0x99`)** is the host→adapter deploy channel: it writes an arbitrary
file to the adapter filesystem **as root**, via write-temp + atomic `rename(2)` (a running daemon
keeps its current inode; the new file is picked up on the next exec). Received files land
**executable** (the driver carries a `chmod`/`0777` mode), so the host need not send a separate
chmod.

### 3.5 Two deploy strategies

| | **A. `/tmp/bin` push (non-persistent)** | **B. `/usr/sbin` persistent** |
|---|---|---|
| Mechanism | host SendFiles (`0x99`) the patched binary to `/tmp/bin/ARMiPhoneIAP2` | `cp` the repacked binary over `/usr/sbin/ARMiPhoneIAP2` (rootfs is jffs2-rw) |
| Cold-boot session 1 | **STOCK** — `/tmp/bin/AppleCarPlay` doesn't exist yet, so the factory `cp` overwrites the pushed binary | **PATCHED** — factory `cp` copies *our* `/usr/sbin` binary into `/tmp/bin` |
| Session 2+ | PATCHED — once `AppleCarPlay` exists the factory `cp` is skipped, so the host-staged binary survives. Host must **re-stage between sessions** (on UNPLUGGED / every init) | PATCHED every session, no host-timing dependency |
| Revert | reboot → factory (tmpfs wiped) — near-zero brick risk | restore the factory backup (md5 `d933c9d5`); a reboot does **not** revert |
| Used by | the CALL patch (carlink_macOS), historically | the NAV patch (carlink_native); also used for COMM dev-iteration |

If both are present, the persistent `/usr/sbin` copy wins the gate.

### 3.6 Safety / rollback

- **Recovery on a bad binary is guaranteed:** dropbear SSH starts in `rcS` **before**
  `start_main_service.sh`, so even a non-loading `ARMiPhoneIAP2` only breaks CarPlay connect — you
  keep a root shell to restore the factory backup.
- A bad UPX pack is rejected by the loader (CarPlay won't connect) — non-bricking. Always
  round-trip-verify the pack (`--best` then `-d` reproduces the patched ELF) before deploying.
- Append the new key **before** the firmware serializes/broadcasts, and have the cave return the
  original serializer's `r0`, so the stock keys are never broken.

---

## 4. NAV patch — RouteGuidance `0x5201`/`0x5202` → NaviJSON `_iap2` / `_iap2m`

**Host:** carlink_native (Android Automotive). **Status:** v5 working, in production (the build
carlink_native ships); v6 = v5 + ExitInfo is device-verified but not shipped (§4.1). **Deploy (v5):**
persistent `/usr/sbin` (strategy B). Field semantics: see
`../02_Protocol_Reference/iap2_message_catalog.md`.

### What it forwards
- The raw `0x5201` RouteGuidanceUpdate frame → NaviJSON key **`_iap2`** (hex).
- The raw `0x5202` maneuver burst → NaviJSON key **`_iap2m`** (hex).

The host decodes the hex TLV and reads the 26 RouteGuidance ParameterIDs directly — including the
maneuver cursor `0x000d` the stock firmware drops, retiring five iterations of heuristic inference.

### Design — two trampolines, two hooks
| hook VMA | stock bytes | replaced with | role |
|---|---|---|---|
| `0x2d1c8` | `f0 43 2d e9` (`push {r4-r9,lr}`) | `b stage1` | capture |
| `0x2d454` | `5d fd ff eb` (`bl …`) | `bl stage2` | emit |

- **Stage 1 (capture, entry hook `0x2d1c8`):** replays the displaced `push`, identifies the frame
  subtype from `[r1+0xd]`/`[r1+0xe]`, reads the BE length from `[r1+2..3]`, and copies the session
  payload (from offset 9, `len-9` bytes) into a **64 KB `.bss` ring buffer at `0x9A000`**, tracking
  a running length in globals at `0x99E00+`, then branches back.
- **Stage 2 (emit, hook `0x2d454`):** hex-encodes the captured buffer and attaches it to the
  outgoing NaviJSON cJSON object (`cJSON_AddStringToObject`), then runs the displaced call and
  returns. `0x5201` → `_iap2`; the settled `0x5202` burst → `_iap2m`.

Scratch: globals at `0x99E00` (running/captured length + emit-state trackers); 64 KB burst buffer
at `0x9A000`; RW LOAD `p_memsz` extended to `0x14000` so both are zero-mapped.

### Hard-won lessons
- **v4 OOM (fixed in v5):** v4 re-broadcast the 64 KB buffer as `_iap2m` on **every** `0x5201`
  (~1/s) → ~96 KB/s of JSON → the adapter ran out of memory and the host froze. **v5 emits once per
  route-calc:** track `cur` vs `prev` running length, emit only when the burst has *settled*
  (`cur == prev > 0`), then zero the counters so each burst reuses the buffer from offset 0.
  **Standing precedent: never emit a large buffer on a high-frequency message without a settle/dedup
  gate.**
- **The `0x5202` red-black-tree race (a real limitation):** an alternate hook that read the maneuver
  list from the firmware's internal tree crashed on a rebalancer race (concurrent writer). The
  shipped design avoids that path. *(This race does NOT apply to the call/comm patches — those use
  flat fixed-offset containers, no tree.)*

### 4.1 NAV v6 = v5 + P1 (ExitInfo) — device-verified 2026-10-19, not shipped

**What it adds:** one extra hook ("P1") so the accessory's `StartRouteGuidanceUpdates` (`0x5200`) asks
the phone for ExitInfo. Everything else is v5. Artifacts: `production/ARMiPhoneIAP2.nav_v6.{patched,packed}`,
builder `build_v6.py` (see `../../custom/patches/README.md`).

**Why a selector, not a capability flag.** Apple's spec: `0x5200` selector id 3 `SupportsExitInfo`
(empty) "must be included to receive ExitInfo in RouteGuidanceManeuverInformation"; `0x5202` id 13
`ExitInfo` (utf8) is "only sent if SupportsExitInfo is included". The stock `StartGuidanceItems`
constructor (`0x2db80`) emits only ids 0 (ComponentID), 1 (SourceName), 2 (SourceSupportsRouteGuidance).
The three selector entities are embedded sub-objects at fixed offsets in a fixed-size heap object with
an embedded `std::map`; adding id 3 there means resizing that object and fighting the HUD value-clear
path, so P1 instead appends the TLV to the **already-built wire frame** and lets the firmware's own
finalizer recompute lengths/checksums (all checksums and the `FF 5A` start marker are computed *after*
the send call, so only the two length fields need adjusting).

**Bytes** (VMA = file + 0x10000):

| item | VMA (file) | stock -> v6 |
|---|---|---|
| P1 hook, in the generic iAP2 sender `0x2f7c4` | `0x2f914` (`0x1f914`) | `19 95 ff eb` (`bl 0x14d80`) -> `0f 5d 01 eb` (`bl 0x86d58`) |
| P1 stub, 124 B, in the cave right after v5's stage1 | `0x86d58` (`0x76d58`) | zeros -> stub |
| R-X LOAD (`ph3`) filesz/memsz | | `0x76d58` -> `0x76dd4` |

Stub logic (no stack use; `lr` already set by the `bl`, `r0`/`r1` untouched): if
`BE16(buf[0xd..0xe]) == 0x5200`, append `00 04 00 03` (length 4, id 3, empty) at `buf+9+msglen`,
`msglen += 4`, `linklen += 4`, then `b 0x14d80`, which returns into the sender exactly as the original
call did. The `+0x49`-byte slack of the sender's `malloc(bodylen+0x49)` holds the 4 extra bytes.

**Composition with v5:** v6 differs from `nav_v5.patched` by 123 bytes: the `ph3` size, the hook, the
stub. v5 stage1/stage2, both v5 hooks (`0x2d1c8`, `0x2d454`) and `ph4` (memsz `0x14000`) are
byte-identical (`build_v6.py` asserts this when `ARMiPhoneIAP2.v5.patched` is present). Cave used
`0x76b38..0x76dd4` (668 B); **556 B left**. No CALL/COMM hooks: those remain a separate build (§7).

**Device results (stock CPC200, board A15W, firmware `2025.12.29.1746CAY`).** Method: iPhone-side
capture (`idevicesyslog -p accessoryd -p carkitd`), where `accessoryd` logs each iAP2 frame's payload
as hex; plus the macOS host's `[EXITINFO_PROBE]` log, which decodes the forwarded `_iap2m`.

| check | control (NOT a v5 run on this unit; see note) | v6 (stock unit) |
|---|---|---|
| accessory `0x5200` params | ids 0-2 (from disassembly of the stock declaration, `0x2db80`) | ids [0,1,2,3] (24 B payload) |
| `0x5202` burst | 13 maneuvers, ids 0..11 only (from the OCBM-accessory run below, not this box) | 20 maneuvers, ids 0..11 plus id 13 on exactly one maneuver |
| id 13 content (raw wire bytes) | n/a | utf8 text of the form `Exit <n>` |
| host probe | n/a | frames=20, `ExitInfo(0x000d)=PRESENT(x1)` |
| reject / crash / session | n/a | no `0x1D03` reject, no crash, session reached streaming |

(The control column is NOT a measured stock-v5 run: no v5 capture on this unit is recorded. Its burst comes from the earlier OCBM-accessory test; the routes differ, so only the id set is comparable.)
An independent Rust OCBM accessory (different unit/firmware, ccpa_custom ledger R-49-9) sending the same selector also received ExitInfo, so the gate is
iOS behaviour, not firmware-specific. Note this corrects the older "capability advertised at
identification" model in `../02_Protocol_Reference/iap2_sdk_delta_r14g17_to_ios26.md` §6 for ExitInfo.

**Packing gotchas (v6 pack, 2026-10-19):** the box has no UPX tool and no `scp` binary (`sftp-server`
exists, so macOS `scp` in SFTP mode works). Copy `modified_upx_arm` (Linux ARM ELF) to the box `/tmp`,
and `chmod +x` the **input** file too, else `CantPackException: file not executable`.
`modified_upx_arm --best -o v6.packed ARMiPhoneIAP2.v6.patched` gave 494244 -> 233996 B (47.34%); `-d`
reproduced the patched ELF byte-for-byte.

**Deploy used for the test:** strategy A, via the carlink_macOS host push (SendFile `0x99` of the packed
file to `/tmp/bin/ARMiPhoneIAP2` at init, push flag enabled). Nothing was written to flash; `/tmp` is
tmpfs, so a reboot restores the factory binary (rollback = reboot). It took effect on the **first**
CarPlay session after a box reboot into the default protocol mode on this unit, which differs from the
strategy-A cold-boot row in §3.5; the reason is not established (UNVERIFIED, single unit). The host app
can only claim the box in default mode; stock NCM maintenance mode is the flag file `/script/ncm_only`
(+ reboot), and `rm /script/ncm_only` + `busybox reboot` returns to default.

**Status of consumers:** carlink_native ships the **v5** asset and its `Iap2RouteParser`/`Iap2ManeuverData`
do not parse `0x5202` id 13; carlink_macOS only has the log-only probe (no nav decoder/UI). So v6 is
proven on the wire and in the probe, but not delivered to any user-facing app.

**UNVERIFIED:** off-ramp exit types (maneuver types 8/22/23); selectors 4/5 (timezone / EV — only
inferred to gate `0x5201` ids 21+); lane guidance (`0x5204`) on the stock binary — it neither declares
nor handles it, and a lane patch ("P2 / next NAV patch, not built") exists only as the researched plan in §4.2; persistence of v6 beyond `/tmp`
(strategy B never tried); other iOS versions and other firmware builds; whether the on-box factory
binary of `2025.12.29.1746CAY` is identical to the `2025.10.15` one `build_v6.py` asserts against (the
hook applied and ran, but its md5 was not recorded). Raw frame logs are not archived in this repo.

### 4.2 P2 / next NAV patch, not built — `0x5204` lane guidance (researched plan, offline analysis only; unverified on hardware)

**Status:** plan only. Nothing is built or scheduled and no version is assigned. Basis: offline disassembly of
`ARMiPhoneIAP2.unpacked` plus a bounded unicorn run of the stock parser on a synthetic `0x5204` frame; no device run.
Base = NAV v6 (§4.1). VMA = file + `0x10000`. The earlier idea of appending `0x5204` frames into the `_iap2m` buffer
is withdrawn (see forwarding below).

**Declaration is a runtime vector insert, not a static table.** Registration fn `0x2cbf4` registers received ids with
`bl 0x1ff7c` at `0x2cc10` (`0x5201`) and `0x2cc1c` (`0x5202`) and sent ids via `0x1ff74` at `0x2cc28` (`0x5200`) and a
tail-`b` at `0x2cc38` (`0x5203`); r0 = manager, r1 = id. `0x1ff7c` is `add r0,#0x138; b 0x1ed84`, where `0x1ed84` is
`std::vector<u16>::push_back`, so appending `0x5204` is a clean insert; the Identify blob is serialized from these
vectors, so length and checksum recompute downstream (the same finalizer family P1 relies on). Mechanism: redirect the
`bl` at `0x2cc1c` (bytes `d6 cc ff eb`) to a ~32 B cave stub, `regstub`: `push {r4,lr}; mov r4,r0; bl 0x1ff7c` (r1 =
`0x5202` still live); `mov r0,r4; movw r1,#0x5204; pop {r4,lr}; b 0x1ff7c`. The required send for `0x5204` (`0x5200`)
is already in Identify param 6, and `0x5204` has no Start/Stop, so no pairing is needed. The Rust OCBM accessory
declares it the same way (param 7) and received `0x5204` live with NO Identify param 30 sub 8.

**Registration alone does not route.** The inbound demux `0x18b10` is a hardcoded id search; its `0x520x` arm at
`0x18c2c` (`sub r3,r4,#0x5200; sub r3,#1; cmp r3,#1; bls 0x1917c; b 0x1919c`) sends only `0x5201`/`0x5202` to the
engine (`0x1917c` calls vtable[8] = `virtual_8` `0x2d1c8` on a fixed engine pointer; no per-id table). A `0x5204` falls
to `0x1919c` (verbose log, then cleanup): a safe silent drop. Even if it reached `virtual_8`, the switch at `0x2d1e0`
sends index 4 to default `0x2da04`, a harmless no-op. Widening the compare at `0x18c34` (`cmp r3,#1` -> `#3`) would
route it but touches the NAV hot path (and admits inbound `0x5203`), so it is not chosen. **Chosen (Design B):** hook
`0x18c40` (`b 0x1919c`, bytes `55 01 00 ea`) -> `bl lane_stub`; r4 = msgid and r6 = raw packet are live there. If
r4 == `0x5204`, `lane_stub` copies BE16(`[r6+2..3]`) - 9 bytes from r6+9 into a lane buffer and bumps a lane-cur
counter, then `b 0x1919c`. Stage1, `virtual_8` and the dispatcher range stay byte-identical to v6, and the `0x2d0fc`
map-insert re-entrancy zone is never entered for `0x5204`. The 556 B left in the cave is expected to suffice; if not,
extend the R-X p_filesz/p_memsz toward `0x77000` (not assembled; size is an estimate).

**Forwarding: a NEW NaviJSON key `_iap2l`, not `_iap2m`.** carlink_native reads `_iap2`/`_iap2m` by explicit key
(`CarlinkManager.kt`; unknown keys are ignored), and its `Iap2RouteParser` stops the whole burst parse at the first
frame that is not `52 02`, so mixing lane frames into `_iap2m` would truncate maneuver parsing. `_iap2l` uses the same
framing as the `0x5202` capture (`40 40 <sesslen BE> 52 04 <TLVs> <cksum>`, linklen-9 bytes from offset 9). Stage2 gains a
second block cloned from the `_iap2m` one: its own settle gate (lane-cur vs lane-prev), `cJSON_AddStringToObject(obj,
"_iap2l", hex)` and a cap. bss: lane buffer at `0xAB000` (RW p_memsz `0x14000` -> `0x15000`, memsz only), cap `0x1000`
(a burst is 5-9 messages of <=123 B, ~1.1 KB), counters at GLOBAL+`0x124`/`+0x128` (in the unreferenced scratch
`0x991A0..0x99F5F`). Stage2 runs on every `0x5201` (~1 Hz) and the lane burst completes ~0.3 s after `0x5202`, so it
settles within two stage2 passes. v5 stage2 leaves sp = 4 mod 8 at libc calls (latent); the new block must push an
even register count. Host work (new code in both apps): an `Iap2LaneParser` with recursive TLV decode, because `0x5204`
id 2 `LaneInformation` is a nested group (sub0 Index u16, sub1 LaneStatus enum, sub2 LaneAngle int16 [0+], sub3
LaneAngleHighlight) and the existing parsers are flat. carlink_macOS has no nav decoder/UI (log-only probe);
carlink_native needs an `_iap2l` branch in `CarlinkManager.kt` plus a new parser (do not extend `Iap2RouteParser`).
On the OCBM box a route start carried 5-9 `0x5204` messages (54-123 B bodies) and `0x5202` id 12
(LinkedLaneGuidanceInformation) was never present, so lane records are tied to maneuvers only by the host's own index logic.

**iOS side.** Declaring `0x5204` in param 7 is sufficient per the OCBM live result. `0x5200` needs no lane selector
(selectors 0-5 = component / SourceName / SourceSupportsRouteGuidance / SupportsExitInfo / DestinationTimeZoneOffsetMinutes
/ EVChargeInfo); P1's selector 3 is unrelated. The stock param-30 writer `0x21400` sets sub 6 (maneuver storage
capacity) = 0 and has no sub 7/8, so maneuvers already arrive individually. Identify param 30 sub 8
(MaxLaneGuidanceStorageCapacity) is UNKNOWN: Apple's note says it must be included, yet OCBM received `0x5204`
without it. Start without it; it is the only fallback (two heap `uint16` entities via `0x20624`; nontrivial).

**Risks.** (a) An Identify reject (`0x1D03`) is unrecoverable for the session (params 6/7 cannot be stripped, a retry is
byte-identical). The OCBM wired+tunnel `extended` declaration including `0x5204` was accepted, so the risk is lower than
the wireless param-6 growth precedent, but it is UNKNOWN for this binary; the declare-only stage is the gate. (b) Crash
on an unrouted `0x5204`: ruled out statically (`0x1919c` and `0x2da04` both return cleanly). (c) Memory growth (v4 OOM
precedent): bounded by the settle gate and the `0x1000` cap. (d) The `0x5202` map-insert race is UNVERIFIED in the
docs; the capture hook sits before any map insert. Rollback: a host push to `/tmp/bin` reverts on reboot; a
persistent `/usr/sbin` install would need the factory backup (md5 `d933c9d5`) plus reboot; dropbear starts before the
main service; `/script/ncm_only` is the maintenance mode.

**Staged plan** (each stage host-pushable via the existing carlink_macOS init push; reverts on reboot):

| Stage | Change | Accept | Fail |
|---|---|---|---|
| 0 declare-only | `regstub` at `0x2cc1c` only; no host change (the box drops `0x5204`) | iPhone-side capture (`idevicesyslog -p accessoryd -p carkitd`, whose `LOG;` lines include the accessory `0x1D01` Identify) shows `0x5204` in the declared received list and a `0x1D02` accept (not `0x1D03`), and `0x5204` frames appear on the wire after a route starts | `0x1D03`: static declaration is dead for this binary; test sub 8, else abandon |
| 1 capture + forward | `lane_stub` at `0x18c40`, stage2 `_iap2l` block, RW p_memsz `0x15000` | host log shows `_iap2l` hex; `Iap2LaneParser` decodes id 1 index and the id 2 group on a multi-lane route | no `_iap2l` though Stage 0 saw `0x5204`: capture-hook bug (emulate first) |
| 2 host render | `Iap2LaneParser` in carlink_native, `_iap2l` decoder in carlink_macOS | host-defined | n/a |

**Emulation.** Done: parser `0x17f48` on a synthetic `0x5204` link frame gives msgid `0x5204`, param area at pkt+15
(PASS); the routing decision is a constant fold. Proposed once stubs exist: run `regstub` under unicorn with a fake
manager and r1 = `0x5202`, asserting the received list gets {`0x5202`, `0x5204`} and the manager pointer survives; run
`lane_stub` on `0x5204` vs non-`0x5204` frames, asserting linklen-9 bytes are copied and other frames reach `0x1919c` untouched.

**Remaining UNKNOWNs (cheapest experiment):** U1 wired `0x1D01` accept of a param-7 `0x5204` on this binary (Stage 0);
U2 whether sub 8 is needed (only if Stage 0 shows accept but no `0x5204`); U3 lane-burst volume and interleave
(observe `_iap2l`/`_iap2m` lengths at Stage 1); U4 repack: `modified_upx_arm` is a Linux ARM ELF, so packing runs on
the box as for v6; an unpacked-file host push is untested.

---

## 5. CALL patch — CallStateUpdate `0x4155` → MetaData subtype-100 `_callraw`

**Host:** carlink_macOS. **Status:** device-verified 2026-06-14. **Deploy:** `/tmp/bin` push
(strategy A; re-staged on UNPLUGGED). Field semantics: see
`../02_Protocol_Reference/iap2_message_catalog.md`.

### Why
carlink_macOS can present a real in-car phone UI, so it wants the full call record. The goal:
forward the **entire raw iAP2 CallStateUpdate** so the host gets the *real* CallUUID and any other
fields the phone sends, instead of the stock 5-key subtype-100 JSON.

### Frame layout (verified from the binary)
- `ARMiPhoneIAP2` receives a 9-byte iAP2 **link** header; the **total frame length** is the
  big-endian u16 at frame `[2..3]`; the iAP2 **message** starts at **offset 9**.
- iAP2 message: `[0..1]=40 40` marker, `[2..3]=u16 BE length`, `[4..5]=u16 BE message id`
  (`0x4155` = CallStateUpdate), `[6..]` = parameters.
- Each parameter: `[0..1]=u16 BE length (incl. 4-byte header)`, `[2..3]=u16 BE id`, `[4..]=payload`.
- → forward **`len-9` bytes from `frame+9`** (the iAP2 message). Same convention as the nav patch.

### Design — two trampolines, two hooks
| hook VMA | stock bytes | replaced with | role |
|---|---|---|---|
| `0x296cc` | `f0 40 2d e9` (`push {r4-r7,lr}`) | `b stage1` | capture |
| `0x29960` | `5a ff 00 fa` (`blx 0x696d0` = `cJSON_PrintUnformatted`) | `bl stage2` | emit |

- **Stage 1 (capture, entry hook `0x296cc`):** replays the displaced `push {r4-r7,lr}`, saves `r1`
  (raw frame ptr) to `.bss[0x9A000]` and the BE length from `[r1+2],[r1+3]` to `.bss[0x9A004]`, then
  `b 0x296d0`. The function reloads r4–r7 before use, so clobbering them is safe. (Stage 1 runs on
  every dispatch but is only *consumed* on the `0x4155` serialize path in the same invocation, so
  the saved pointer is never stale.)
- **Stage 2 (emit, hook `0x29960`):** if a pointer is saved, `malloc(2*(len-9)+1)`, hex-encode the
  `len-9` payload bytes from `frame+9`, `cJSON_AddStringToObject(r5, "_callraw", hex)` (r5 = the call
  cJSON object created at `0x29864`), `free`, clear the pointer; then run the **displaced** `blx`
  with `r0=r5` and `pop {…,pc}` back. The existing firmware tail ships the now-enriched JSON under
  subtype 100 unchanged.

Memory map: stage2 (204 B) @ file `0x76b38`/VMA `0x86b38`, stage1 (36 B) @ `0x86c10` (16-aligned);
R-X LOAD filesz/memsz `0x76b38 → 0x76c34`; 8-byte scratch at `.bss 0x9A000` (beyond the original
bss end `0x99f60`, so it cannot collide with any program global); RW LOAD `p_memsz 0x2f60 → 0x3010`.

### Why this is lower-risk than the nav patch
Capture and emit are in the **same function/invocation** (no cross-invocation `.bss` handoff, no
64 KB buffer, no settle logic); CallState uses **flat fixed-offset containers** (no red-black-tree
race); one small frame malloc'd+freed each time (the v4-style OOM is structurally impossible); the
call handler already calls the broadcast path natively (IPC proven).

### Host integration (carlink_macOS) — the critical parse fix
The subtype-100 content is **NUL-terminated** (cJSON output + adapter padding), and `JSONSerialization`
rejects trailing bytes, so the stock parse failed **silently** and the call path never ran. Trim to
the first NUL before parsing (`Data(content.prefix(while: { $0 != 0 }))`). The host then DFS-walks
the `_callraw` TLV (nesting-tolerant) and logs **only** ids/lengths/enum values, never PII.

### The empirical `0x4155` model (device-verified, authoritative)
For ordinary 1:1 calls this iOS sends **exactly 5 flat params, never more**:

| id | field | notes |
|---|---|---|
| 0 | RemoteID | E.164 number (string) |
| 1 | DisplayName | contact name, or formatted number if unresolved |
| 2 | CallStatus | `0` ended · `1` dialing(out) · `2` ringing(in) · `3` connecting(brief) · `4` **active**(long-lived) |
| 3 | CallDirection | `1` incoming · `2` outgoing |
| 4 | CallUUID | **real**, sent by the phone, == the stock `CallID` (not the firmware's fabricated fallback) |

> **CallStatus enum correction:** `4` is the long-lived **active** state (observed persisting ~71 s
> on a live call); `0` is the end; `3` is a brief post-answer "connecting" step. Earlier notes that
> said "3=connected, 4=disconnecting" were wrong and are corrected here and in
> `../02_Protocol_Reference/usb_protocol.md`.

Verified across cellular + FaceTime, incoming/outgoing, missed/answered/declined, short (3-digit
code) and long numbers, 0:03–1:11 durations, zero decode errors, no daemon crash. The extra parser
fields (AddressBookID 6, Label 7, Service 8, IsConferenced 9, ConferenceGroup 10, DisconnectReason
11) are **not** present on `0x4155` for normal 1:1 calls regardless of subscription — for those calls
the stock binary already forwards everything the phone sends. The patch's proven value: complete
passthrough as a guarantee, recovery of the real CallUUID, and a verified ground-truth frame model.
Richer telephony (voicemail/missed counts, signal, mute, carrier, FaceTime-vs-cellular type) lives on
the **Communication** message, not `0x4155` — see §6.

### Worked example (placeholder data — NOT real)
An incoming ringing call from contact "Jenny" at +1 (555) 867-5309:
```
_callraw (illustrative hex):
  4040 0054 4155                          marker · len=0x54 · msgid 0x4155 (CallStateUpdate)
  0011 0000  2b 3135353538363735333039 00 id0 RemoteID     = "+15558675309"
  000a 0001  4a 656e6e79 00               id1 DisplayName   = "Jenny"
  0005 0002  02                           id2 CallStatus    = 2 (ringing)
  0005 0003  01                           id3 CallDirection = 1 (incoming)
  0029 0004  "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" 00      id4 CallUUID
host subtype-100 JSON:
  {"CallStatus":2,"CallDirection":1,"CallID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
   "CallName":"Jenny","CallNumber":"+15558675309","_callraw":"4040…"}
```

### Where "missed" and "voicemail" actually are
There is **no explicit "missed" flag** in `0x4155` (a missed call is `2→0` with no answer,
host-inferred). The **"Missed" recents entry and voicemail badge seen in CarPlay are rendered by iOS
into the H.264 video stream (pixels), not sent as telephony data.** The voicemail/missed **counts**,
signal, mute, call-count and FaceTime-vs-cellular type are carried by the **CommunicationUpdate**
message (§6).

---

## 6. COMM patch — enabling the dormant Communication engine → subtype-101 `_commraw`

**Host:** carlink_macOS. **Status:** device-verified end-to-end + host-decoded 2026-06-15. **Deploy:**
direct rootfs (`/usr/sbin` + `/tmp/bin`). Field semantics: see
`../02_Protocol_Reference/iap2_message_catalog.md`.

This is the hardest of the three. Unlike nav/call (where the engine runs and only the serializer
strips data), the **Communication engine never runs at all** on stock firmware — so a passthrough
hook has nothing to forward until the engine is first *enabled*.

### 6.1 The datastore-poison trap (hard operational rule)

`ARMiPhoneIAP2` reads config datastores from `/etc/RiddleBoxData/` (bplists: `AIEIPIEREngines.datastore`
listing engines to keep, and `<Engine>Items_Usablity` listing each engine's subscribed iAP2 param
ids). It is tempting to enable Communication by editing these files. **Do not.**

> **HARD RULE: never add Communication to any `/etc/RiddleBoxData/` datastore.** Device-verified:
> an offline bplist edit (adding `iAP2CommunicationEngine`, and/or a hand-made
> `CommunicationItems_Usablility`) **breaks the datastore signature**, so
> `ReadCFValue_FromSystem(IdentifyInfo)` fails (`kSignatureErr`) → the accessory sends no valid
> IdentifyInfo → **the iPhone withholds ALL update messages** (no NowPlaying `0x5001`, no
> CallStateUpdate `0x4155`) — media AND telephony metadata go completely dark, while CarPlay A/V,
> touch and UI keep working (so it looks like a binary/host bug). Reverting *only* the datastore to
> factory + reboot restores everything.

Two corollaries learned the hard way:
- The datastore is **persistent (jffs2)** and untouched by binary swaps/reboots, so swapping the
  daemon never changes the symptom — isolate by reverting the datastore.
- The daemon **rewrites `CallStateItems_Usablity` back to stock (ids 0–4) on every connect**
  (`SetBoxStableData`), so expanding it by file-edit does not persist anyway.
- Reliable host signal: the `[◀ RX] METADATA subtype=N` count (1=media, 100=call, 101=comm). **Zero
  across the board = datastore poison.**

Communication must be enabled **purely in the binary**, and any comm experiment must be validated to
**not regress media/call metadata** (watch for subtype-1 after every change).

### 6.2 Verified root cause (why comm is dormant)

Established by disassembly cross-checked against the live daemon console log `/tmp/ttyLog`:

1. **The comm engine object is datastore-gated build-then-destroy.** In factory `0x15ee4` each engine
   is built, then a per-engine gate looks its name up in `AIEIPIEREngines.datastore` and **destroys
   it if absent**. For comm (`0x16120`–`0x161a8`): build (`operator_new(0x4c4)`, ctor `0x29468`,
   singleton `[0x9859c]`) → lookup `iAP2CommunicationEngine` (`0x16168 bl 0x2f1a8`) → **not found**
   in the factory 4-engine list → `0x1617c bhs 0x16194` taken → destructs comm + `str 0,[0x9859c]`.
   Runtime proof: `[0x9859c] = NULL` (the only null engine).
2. **The recv handler `0x2846c` is never invoked.** The dispatcher's recv route (`0x18ff8 → 0x1917c`)
   does `ldr r0,[0x9859c]; cmp 0; beq skip` — it **null-gates on the comm singleton at dispatch
   time**. So even hooking the handler is futile.
3. **The subscribe entity is deselected.** The ctor (`0x28e48`) fully builds the comm subscribe
   entity (`comm+0x268`, 17 children for ids `0,1,2,4..0x11`) but then **deselects** them
   (`child[+4]=0`), so the serializer `0x1e5e8` returns NULL and the connect-time `0x4157` send bails.

Net: **the engine is never given a capability-advertise / prime step.** Config cannot fix it (there
is no `DashboardInfo` bit for comm), and the datastore path is actively destructive (§6.1). **A
binary patch is required.**

### 6.3 The working patch — three mods, NO datastore edits

Layered onto the call patch. Cross-validated against two independent shipping wireless-CarPlay
head-unit middleware stacks (Cinemo/Nme — x86-64 and aarch64 builds) and the Apple R14G17 SDK: the
advertise is just SupportedMessages (already done — runtime IdentifyInfo lists `4157`/`4159`
sent-by-accessory, `4158` received), and the missing step is simply emitting a well-formed
`StartCommunicationUpdate(0x4157)` after identify. The reference stacks build `0x4157` with one
empty parameter per requested id `{0,1,2,4,5,6,7,8,9,A,B,C,D,E,F,10,11}` (id 3 skipped) and there is
**no SKU/wireless gate** on the `0x4158` receive path.

| # | mod | site | effect |
|---|---|---|---|
| 1 | **force-construct** | NOP `0x1617c` (`04 00 00 2a` → `00 00 a0 e1`) | the build-then-destroy gate falls through; comm is **kept + registered** (vtable[0x10]=`0x283a0` inserts recv ids `0x4157/0x4158/0x4159`), `[0x9859c]` non-null |
| 2 | **subscribe** | hook `0x285b0` (was `bl 0x1c96c`; `r5`=comm entity) | trampoline sets `[entity+4]=1` (dirty) + calls `0x1e2a0(entity,1)` to **re-select all 17 children** + returns `r0=0`, then falls through to `0x285a0` which transmits **`StartCommunicationUpdate(0x4157)`** |
| 3 | **forward** | hook `0x18ff8` (dispatcher's `0x4158` case, `r6`=raw frame, *before* the null-gate; displaced `ldr r3,[0x193ac]`) | hex-encode payload (`frame+9`, `totallen-9`), `BroadCast` as MetaData **subtype-101 `_commraw`**, then replay the displaced load + `b 0x1917c` |

Mod 3 hooks the **dispatcher**, not the recv handler `0x2846c` — because (per §6.2 step 2) the
handler is never reached.

Cave layout (file `0x76b38`–`0x76d10`): call stage2 `0x86b38`, call stage1 `0x86c10`, commfwd
`0x86c40` (176 B), commsub `0x86cf0` (32 B); R-X LOAD filesz/memsz → `0x76d10`; RW LOAD memsz `0x3010`.

### 6.4 Device-verified results (2026-06-15)
- `Send_changes:StartCommunicationUpdate(0x4157), msgLen:72` sent.
- iPhone streamed **`0x4158` CommunicationUpdate** mid-session (stable, no teardown), e.g.
  `SignalStrength=2`, `RegistrationStatus=4`, `Carrier="AT&T"`, `CurrentCallCount=1`,
  `NewVoicemailCount=0`; host received the matching **subtype-101 `_commraw`** frames.
- **No poison:** subtype-1 (media) + subtype-100 (call `_callraw`) kept flowing; datastore stayed
  factory-clean; no IdentifyInfo `kSignatureErr`.
- Host-decoded into named fields (`CommStatus`, all-optional/delta-safe), e.g.
  `signal=1 reg=4 carrier=AT&T mute=false calls=0 voicemail=0`, plus an airplane-toggle delta
  `signal=0 reg=1 airplane=true carrier="Airplane Mode"`.

The `0x4158` field map is in `../02_Protocol_Reference/iap2_message_catalog.md`.

---

## 7. Combining patches into one binary

All three share the **same code cave** and would otherwise collide in `.bss`:
- Cave budget: nav (~536 B) + call (~240 B) + comm (~208 B) ≈ 1 KB < 1224 B → fits.
- **bss conflict:** the call/comm scratch is at `0x9A000`, which is exactly where the nav patch puts
  its 64 KB burst buffer. To combine, move the call/comm scratch (e.g. to `0x99D00`, still within the
  nav-extended bss) and keep nav's `0x9A000` buffer + `p_memsz 0x14000`.
- Install all hooks and extend the R-X `p_filesz`/`p_memsz` to cover the combined cave.

In practice each host needs only one patch (carlink_native → nav; carlink_macOS → call+comm), so a
fully combined nav+call+comm build has not been required. The only composition built so far is NAV v5 +
P1 (§4.1), which uses the cave up to file `0x76dd4` (556 B left); a full nav+call+comm build would need
to fit call+comm (~450 B by the figures above) into that remainder — arithmetic only, UNVERIFIED. The P2 plan
(§4.2) would also draw on that remainder and adds `0x1000` B of bss at `0xAB000`; no combined budget has been computed.

---

## 8. Related documentation
- `../02_Protocol_Reference/iap2_message_catalog.md` — field semantics: RouteGuidance (`0x5200`/`0x5201`/
  `0x5202`), CallState (`0x4155`), CommunicationUpdate (`0x4158`), and the `0x4154`–`0x4159`
  telephony message-id family.
- `../02_Protocol_Reference/usb_protocol.md` — the outer USB envelope and the MetaData (`0x2A`)
  subtype map (1=media, 100=call `_callraw`, 101=comm `_commraw`, 200=NaviJSON).
- `../06_Reference/binary_analysis/key_binaries.md` — full ARMiPhoneIAP2 engine/dispatch RE.
- `../01_Firmware_Architecture/hardware_platform.md` — SoC/rootfs context, deploy surface.
- `../02_Protocol_Reference/carkit_ios26_master.md` §6 — capability-unlock patch recipes (uses the
  same cave + toolchain).

# USB Zero Length Packet (ZLP) Bug — CPC200-CCPA

## Status: Confirmed (AA + CarPlay), Fix Identified, Untested

**Date**: 2026-03-15 (AA); 2026-06-21 (CarPlay confirmation — see "CarPlay Confirmation" below)
**Firmware**: 2025.10.15.1127CAY (AA); 2025.12.29.1746 (CarPlay capture)
**Affected**: **Both** Android Auto and CarPlay. The root cause is protocol-agnostic (the adapter→host write path is the same `g_android_accessory` gadget for both). The two protocols differ only in *how the failure surfaces* — AA dies as a silent write-stall; CarPlay surfaces as a host-app recovery loop. The earlier "CarPlay survives" claim was **under-tested** and is corrected below.

## Summary

The adapter's USB bulk write path does not send a Zero Length Packet (ZLP) when the transfer size is an exact multiple of the USB max packet size (512 bytes for High-Speed bulk). Per USB 2.0 spec, a ZLP is required to signal transfer completion in this case. Without it, the host's USB driver hangs waiting for more data, killing the adapter-to-host data path.

## Symptoms

- Stable AA session dies instantly when album art or other metadata with a 512-aligned payload size is sent
- Adapter log shows: `_SendDataToCar iSize: NNNN, may need send ZLP`
- Host app receives 0 bytes from that point forward
- Adapter can still READ from USB (processes OPEN, heartbeats) but cannot WRITE
- Only recovers after an observed ~60-70s, when the adapter's write-stall reset path triggers `Reset Accessory!!`. This ~60-70s is the recovery latency on the write-stall path; it is distinct from the 15,000 ms (`0x3a98`) heartbeat-receive "Host No Response" watchdog documented in heartbeat_analysis.md / configuration.md, which does not fire here because the adapter can still READ heartbeats. The periodic reset watchdog is **~15,000 ms** (`0x3a98`); there is **no separate ~60 s reset timer**. `Host No Response` is event-driven (fires on connection teardown / `ClosedByPeer`), and the ~60–70 s figure is a multi-cycle disconnect→recovery span (~4× the 15 s period), not a single watchdog.

## Reproduction

Reliable trigger: play "WHERE IS MY HUSBAND!" by RAYE on YouTube Music via Android Auto.

- YT Music serves album art at exactly 113,148 bytes
- Adapter adds 4-byte protocol header → 113,152 bytes = 221 × 512
- Session dies within 1 second of the metadata transfer
- Reproduced 3/3 times with the same song

Counter-test: same song on Apple Music via AA serves art at 113,846 bytes (not a 512 multiple) — session survives.

~~Counter-test: same song on CarPlay — session survives despite identical ZLP warnings.~~ **CORRECTED 2026-06-21:** CarPlay does **not** survive. The original counter-test simply never produced a *large (>16 KB) 512-aligned* transfer on CarPlay; when one occurs, CarPlay fails too — see "CarPlay Confirmation & Corrected Failure Model" below. Note that CarPlay failure manifests differently from AA (a host-app recovery loop rather than a silent stall), which is why it was initially mistaken for tolerance.

## Root Cause — Two Layers

### Layer 1: Userspace (`ARMadb-driver`)

Function `_SendDataToCar` at address `0x18598` detects the ZLP condition but only logs it:

```arm
0x18a58: ubfx  r2, r3, #0, #9    ; r2 = size % 512
0x18a5c: cmp   r2, #0            ; exact multiple?
0x18a5e: bne   #0x18a4e          ; no → normal send
0x18a60: movs  r0, #5            ; yes → WARN log level
0x18a64: ldr   r2, ="...may need send ZLP"
0x18a66: bl    BoxLog            ; log the warning
0x18a6a: b     #0x18a4e          ; FALL THROUGH — no ZLP sent
```

The developer detected the condition (the string says "may need send ZLP") but never implemented the actual ZLP send. The unconditional branch at `0x18a6a` goes to the same send path as the non-ZLP case.

### Layer 2: Kernel Module (`g_android_accessory.ko`)

The kernel module has a `accZLP` boolean parameter (added between firmware 2023.05.29 and 2023.09.27):

```
parm=accZLP:accessory send ZLP when tx_packet_size divide exactly ep_maxpacket
parmtype=accZLP:bool
```

In `acc_write()` at offset `0x464c`:
- When `accZLP=1`: sets `req->zero = 1` via `bfi` instruction (bit field insert on bit 1 of USB request flags)
- When `accZLP=0` (default): clears bit 1 via `bfc` (bit field clear)

The kernel logs confirm: `acc_write: size 113152, accZLP 0` — the infrastructure exists but is disabled.

**The module is always loaded without the parameter:**
```sh
insmod /tmp/g_android_accessory.ko    # accZLP defaults to false
```

No firmware version observed here passes `accZLP=1` — the module is loaded via `start_accessory.sh`/`insmod` without the parameter. (configuration.md documents a `USBTransMode` config key whose consumer `start_aoa.sh` is said to write the `accZLP` sysfs node, but that path is inert: it has no observed runtime effect on `accZLP`, which the kernel module keeps at 0.)

## CarPlay Confirmation & Corrected Failure Model (2026-06-21)

Captured on firmware **2025.12.29.1746**, wireless **CarPlay** session.
Evidence: `_evidence/cpc200_research/carplay_zlp_20260621/` (excerpts) — original full log
`cpc200_20260621_074312.log`, SHA-256 `7f3555d7…c99a3f`.

### The fatal transfer (CarPlay path)

The fatal payload is **album artwork delivered over iAP2 File Transfer**, then forwarded to the
head unit — the *same* "artwork + 4-byte header → 512 multiple" mechanism as the AA case, just
via CarPlay/iAP2 instead of Android Auto:

```
08:14:10.195 [CiAP2Session_FileTransfer] iPhoneToBox ##### sign=Sign_Setup, fileTransferIdentifer=132, size=143868
08:14:10.245 [ARMadb-driver] _SendDataToCar iSize: 143872, may need send ZLP
[220.430225]  acc_write: size 12800, accZLP 0
```

- iPhone artwork file = **143,868 bytes** → adapter prepends its **4-byte header** → **143,872 = 281 × 512** (large + exactly 512-aligned).
- Kernel chunking: `143872 = 8 × 16384 + 12800`. The **final** kernel write is **12,800 = 25 × 512** — *also* 512-aligned (`acc_write: size 12800, accZLP 0`), so the terminating USB request needs a ZLP and never gets one. This is exactly the ">16 KB AND 512-aligned → final request aligned → fatal" condition.
- `accZLP 0` on all 408 ZLP events in the capture / zero `accZLP 1` → the fix is not enabled in this firmware.

**Direct counter-evidence (byte-size lottery confirmed):** later in the same log, an artwork
transfer of `size=85837` (+4 = 85,841, **not** a 512 multiple) forwards cleanly with no churn.
Whether a given track is fatal depends purely on `(artwork_bytes + 4) % 512 == 0 && > 16 KB`.
This explains the field observation that the *same song* fails in one playlist but not alone or in
another: only the exact artwork bytes pushed at that transition determine alignment.

### The failure is NOT an instant data-path death — it is a host-app recovery loop

This is the key correction to the AA-era model. On CarPlay the log shows:

- **No adapter-side stall detection** — between the 143872 write (`08:14:10.245`) and the disconnect (`08:14:13.927`) the adapter logs no timeout, no write-fail, no `Reset Accessory!!`.
- **The read path stays fully alive** — `NowPlaying 0x5001` messages keep streaming continuously (`…10.26, 10.57, 11.15, 11.65, 12.11, 12.57, 13.03, 13.49`) right up to the disconnect. Only the single artwork **write** is stuck.
- **The disconnect originates on the host/app side** — `OnRead: CMD_MANUAL_DISCONNECT_PHONE(15)` shows the adapter *receiving* the command. It is the **host application's recovery watchdog** firing because its bulk-IN read of the 143872 transfer never completes — not a deliberate teardown and not a real disconnect.
- On reconnect the iPhone re-sends the same now-playing artwork → re-stalls → recovery fires again. Result: a **~15 s reconnect loop with no recovery** while that artwork is on screen.

Cycle timing (consistent across the episode): artwork write → ~3.7 s host-side read stall → `CMD_MANUAL_DISCONNECT_PHONE` → `无线 CarPlay 退出` → reconnect → repeat ~14.7 s later.

| 143872 sent | host recovery disconnect | stall→teardown |
|---|---|---|
| 08:14:10.245 | 08:14:13.927 | 3.68 s |
| 08:14:25.188 | 08:14:28.939 | 3.75 s |
| 08:14:39.853 | 08:14:43.580 | 3.73 s |

Two churn episodes in the capture: **08:14:10–08:20:32** and **09:23:25–09:28:39**.

### Recovery overload (why "just change the recovery" is the wrong primary fix)

The host app's recovery routine (`disconnect phone → rescan → reconnect`) is **overloaded**: it
serves both a *genuine* phone/adapter disconnect (link truly gone — recovery is correct and
required) and this *ZLP transfer-stall* (link fine, one write stuck — recovery is wrong and
futile). Relaxing or disabling that routine to mask the ZLP case would also blunt genuine-disconnect
recovery. The two are distinguishable:

| Signal | ZLP transfer-stall (this event) | Genuine disconnect |
|---|---|---|
| Other channels (NowPlaying / heartbeat) | **still flowing** | go silent |
| USB enumeration | intact | device removed |
| BT/Wi-Fi link layer | up (no `bluez RemoteDeviceDisconnected`, no `mDNS` reset) | teardown logged |
| Failing read | **one** bulk-IN hung at a 512-aligned length | read returns EOF/error |

A true disconnect kills **all** channels; the ZLP stall kills only the **one in-flight write**
while every other channel stays live. Fix priority therefore is: **(1)** eliminate the stall at the
source (`accZLP=1`) so recovery never wrongly fires and the genuine-disconnect path is untouched;
**(2)** host-side, honor the 16-byte `0x55AA55AA` length header so the reader never waits on a ZLP;
**(3)** only if neither is possible, make recovery *discriminate* (per the table) and do a targeted
endpoint recovery for transfer-stalls — never relax the shared full-disconnect path.

## Proposed Fix (Untested)

### Option A: Runtime (temporary, lost on reboot)

```sh
echo 1 > /sys/module/g_android_accessory/parameters/accZLP
```

Requires verifying the sysfs parameter is writable (permissions `0644` or `0200`).

### Option B: Boot script (persistent)

Modify the script that loads the module (likely `start_accessory.sh` or sourced from `start_main_service.sh`):

```sh
# Before:
insmod /tmp/g_android_accessory.ko

# After:
insmod /tmp/g_android_accessory.ko accZLP=1
```

### Option C: riddleBoxCfg (not applicable)

On the evidence here, `riddleBoxCfg` does not control USB transport parameters and the ZLP fix is kernel-module-level only. (configuration.md's `USBTransMode`→`start_aoa.sh`→`accZLP` path is inert and has no observed runtime effect.)

## Testing Plan

1. Verify sysfs writability: `cat /sys/module/g_android_accessory/parameters/accZLP` (expect `N` or `0`)
2. Enable at runtime: `echo 1 > /sys/module/g_android_accessory/parameters/accZLP`
3. Verify: `cat /sys/module/g_android_accessory/parameters/accZLP` (expect `Y` or `1`)
4. Play "WHERE IS MY HUSBAND!" by RAYE on YouTube Music via AA — should survive
5. Monitor adapter log: `_SendDataToCar iSize: 113152, may need send ZLP` should still appear, but `acc_write: size NNNN, accZLP 1` should show `accZLP 1` and the session should not die
6. Stress test with multiple song changes to hit various ZLP-boundary sizes
7. If successful, modify boot script for persistence

## ZLP Size Distribution (from test sessions)

Sizes observed hitting ZLP boundary (all multiples of 512):

| Size | Occurrences | Source | Fatal (AA)? |
|------|------------|--------|-------------|
| 1024 | ~142 | Heartbeat/small commands | No |
| 1536 | ~11 | Commands | No |
| 2048 | 2 | Commands | Sometimes |
| 2560 | 2 | Commands | No |
| 3072 | 3 | Commands | No |
| 5120 | 7 | Media data | No |
| 5632 | 1 | Media data | No |
| 6144 | 2 | Media data | No |
| 113152 | 3+ | Album art (YT Music, AA) | **Yes — always** |
| 129536 | 3+ | Album art (YT Music, AA) | **Yes — always** |
| 143872 | 24 | Album art (iAP2 FileTransfer, **CarPlay**) | **Yes — always** (host-recovery loop) |

> The 143872 row is from the 2026-06-21 CarPlay capture (`281 × 512`; artwork `143868` + 4-byte header). Same log: a `85837`-byte artwork (`+4 = 85841`, not 512-aligned) forwarded cleanly — confirming alignment, not size, is the trigger.

Small ZLP-boundary transfers survive (likely because the kernel's internal 16KB chunking produces non-aligned final chunks). Large transfers (>16KB) that are 512-aligned are always fatal because the final USB request is also aligned.

## Files Referenced

- Binary: `ARMadb-driver (2025.10 firmware, UPX-unpacked)`
- Kernel module: extracted from `A15W_extracted/script/ko.tar.gz` → `g_android_accessory.ko`
- Boot script: `start_accessory.sh` (inside firmware image)
- CarPlay capture (2026-06-21): `_evidence/cpc200_research/carplay_zlp_20260621/` — `capture_header.txt`, `excerpt_first_cycle_08-14.txt`, `zlp_disconnect_timeline.txt`. Original full log `cpc200_20260621_074312.log` (75,648 lines, SHA-256 `7f3555d70ab17b1efe279808072c1334e663e1a2e3ab825f82cc273431c99a3f`), firmware 2025.12.29.1746.

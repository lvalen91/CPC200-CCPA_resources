# CarPlay ZLP capture — 2026-06-21

Evidence for the CarPlay confirmation of the USB Zero-Length-Packet bug. See
[`01_Firmware_Architecture/usb_zlp_bug.md`](../../../01_Firmware_Architecture/usb_zlp_bug.md)
§ "CarPlay Confirmation & Corrected Failure Model".

- **Device/firmware:** CPC200-CCPA, Software Version **2025.12.29.1746**, wireless CarPlay.
- **Original log:** `cpc200_20260621_074312.log` (75,648 lines, 5,477,446 bytes,
  SHA-256 `7f3555d70ab17b1efe279808072c1334e663e1a2e3ab825f82cc273431c99a3f`).
  Full log lives in the reviewer's capture tree; only excerpts are imported here.

## Files

| File | Lines | What it shows |
|---|---:|---|
| `capture_header.txt` | 6 | Capture-start config banner + firmware/kernel version. |
| `excerpt_first_cycle_08-14.txt` | 57 | Verbatim first churn cycle (log lines 3899–3955): iAP2 FileTransfer artwork `size=143868` → `_SendDataToCar iSize: 143872, may need send ZLP` → `acc_write: size 12800, accZLP 0`, NowPlaying still flowing, then host-issued `CMD_MANUAL_DISCONNECT_PHONE`. |
| `zlp_disconnect_timeline.txt` | 195 | Every `iSize: 143872` send, `fileTransferIdentifer=132` artwork, `acc_write: size 12800`, `CMD_MANUAL_DISCONNECT_PHONE`, and `无线 CarPlay 退出` line across the whole log. |

## Key facts

- Fatal payload: album artwork over iAP2 File Transfer, `143868` bytes + 4-byte header = **143,872 = 281 × 512** (large + 512-aligned). Final kernel chunk **12,800 = 25 × 512**, also aligned → no ZLP → host bulk-IN never completes.
- `accZLP 0` on all 408 ZLP events; **zero** `accZLP 1` (fix not enabled).
- Failure = **host-app recovery loop**, not a silent stall: adapter read path stays alive (NowPlaying keeps flowing); the host issues `CMD_MANUAL_DISCONNECT_PHONE` ~3.7 s after the stalled write; reconnect re-sends the same artwork → repeats every ~14.7 s.
- Two churn episodes: **08:14:10–08:20:32** and **09:23:25–09:28:39**.
- Counter-evidence: a later `85837`-byte artwork (`+4 = 85841`, not 512-aligned) forwarded cleanly — alignment, not size, is the trigger.

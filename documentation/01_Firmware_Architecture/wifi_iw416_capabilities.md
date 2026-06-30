# CPC200-CCPA (A15W) WiFi Radio Capabilities — NXP/Marvell IW416

Radio/PHY capabilities, SoftAP (hostapd) support matrix, and measured link behavior of the
**NXP/Marvell IW416** WLAN silicon used on the A15W. Complements the firmware-blob/identity
facts in `hardware_revisions.md`; this doc focuses on **what the radio can and cannot do**.

> Provenance: **live-verified on hardware 2026-06-23** via root SSH on two A15W units —
> over the WiFi AP path (`192.168.43.1`) and over USB CDC-NCM (`192.168.50.2`, see
> `../CPC200-CCPA_SSH_over_USB_NCM.md`). Unit with `wlan0` MAC `00:E0:4C:91:B0:DF` is
> **Rev B (WN16)** per `hardware_revisions.md`, `software_version` `2025.10.15`. A second
> unit (MAC `00:E0:4C:D2:23:61`) ran `software_version` **`2025.12.29`** — newer than the
> `2025.10.15.1127` build documented elsewhere; treat as an additional observed point.
> hostapd capability verdicts below were obtained by applying each option live and observing
> whether hostapd (`v2.7`) reaches `AP-ENABLED` or refuses to start.

> **Hardware variant note:** the A15W ships in (at least) **two distinct WLAN variants** that
> are **not** capability-interchangeable: **Realtek RTL88x2CS** (5 GHz **802.11ac** — per
> `hardware_platform.md` / `02_Protocol_Reference/wireless_carplay.md`) and **NXP/Marvell
> IW416** (**802.11n** — this doc). Both are genuine A15W hardware. **This document covers
> only the IW416 variant;** both units verified here are IW416. An RTL88x2CS A15W also exists
> but was not on hand for profiling — its PHY (11ac, likely wider channels / higher MCS) and
> hostapd `ht_capab` matrix will differ and must be profiled separately. Identify the variant
> at runtime: IW416 → `mlan`/`moal` modules, `/proc/mwlan`, SDIO id `0x9159`, fw banner
> `SDIW416---…`; RTL → Realtek `rtl88x2cs`/cfg80211 stack instead.

---

## 1. Silicon & driver

| Item | Value |
|---|---|
| WLAN chip | **NXP/Marvell IW416** (SDIO), combo WiFi+BT, **1×1** (single spatial stream) |
| SDIO card id / type | `0x9159` / `card_type 0x108` (`SDIW416`) |
| Kernel driver | out-of-tree NXP **`mlan.ko` + `moal.ko`** (GPL), from `/script/ko.tar.gz` → `iw416_ko.tar.gz` |
| Control planes | nl80211 (hostapd `driver=nl80211`) **and** WEXT (`cfg80211_wext=0xf`) |
| WLAN firmware blob | `nxp/sdioiw416_wlan_v0.bin` (**425,896 bytes**) |
| TX power table | `nxp/txpower_iw416.bin` (cal `WlanCalData_ext.conf`) |
| BT firmware | `nxp/uartiw416_bt_v0.bin` (via `hci_uart`) |
| WLAN fw banner | `SDIW416---16.92.21.p119.11-MXM5X16437.p20-GPL-(FP92)`; `firmware_major_version=16.92.21` |
| Driver params | `wifi_mod_para.conf`: `drv_mode=3` (STA+uAP+WFD), `ps_mode=2`, `auto_ds=2`, `cal_data_cfg=none`, `uap_name=wlan`, `sta_name=sta`, `txpwrlimit_cfg=nxp/txpower_iw416.bin` |
| Virtual interfaces | `wlan0` (uAP/SoftAP), `sta0` (station), WiFi-Direct/`p2p` (`wfd_name` commented) |

## 2. PHY capabilities

| Capability | Support |
|---|---|
| PHY modes | **802.11 a/b/g/n** only |
| 802.11ac (VHT) | ❌ not supported |
| 802.11ax (HE) | ❌ not supported — kernel logs `fw doesn't support 11ax` (`CMD_RESP cmd 0x112 error, result=0x2`) |
| Spatial streams | **1×1 (NSS1)** — no MIMO/STBC diversity |
| Channel widths | HT20, **HT40** |
| Short Guard Interval | SGI-20, SGI-40 |
| Top observed rate | **HT MCS7, BW40, SGI** (≈150 Mbps PHY — the 1×1 11n ceiling) |
| Bands | 2.4 GHz (`hw_mode=g`) and 5 GHz (`hw_mode=a`) — SoftAP defaults to 5 GHz ch36 |

## 3. SoftAP (hostapd) `ht_capab` / option support matrix — live-tested

hostapd validates `ht_capab` flags against the driver's advertised HT capabilities and
**refuses to start** if an unsupported flag is set (a rejected flag can wedge `wlan0` — see §6).

| hostapd setting | Verdict | Notes |
|---|---|---|
| `[SHORT-GI-20]` `[SHORT-GI-40]` `[HT40+]` | ✅ supported | stock config |
| `[LDPC]` | ❌ **unsupported** | hostapd refuses to start; driver doesn't advertise LDPC |
| `[MAX-AMSDU-7935]` | ❌ **unsupported** | hostapd refuses to start |
| `[TX-STBC]` / `[RX-STBC*]` | ❌ expected unsupported | 1×1 radio — not separately tested |
| `multicast_to_unicast=1` | ⚠️ **inert** | hostapd accepts, but driver logs `nl80211: multicast to unicast not supported on interface wlan0` → no-op |
| `uapsd_advertisement_enabled=1` | ✅ supported | reaches `AP-ENABLED`; low value (only helps power-saving clients — a CarPlay phone is typically charging) |
| `auth_algs=1` (Open-only) | ✅ supported & effective | cleaner than stock `auth_algs=3` (drops dead WEP/shared-key path) |

**Implication:** there is **no `ht_capab`/hostapd tweak that meaningfully improves** this radio.
It is already at its 1×1 11n ceiling. A real throughput/robustness upgrade is **hardware** —
the **Realtek RTL88x2CS (11ac) A15W variant** (see variant note above) — not configuration.

## 4. Stock SoftAP config & channel control

Default `/etc/hostapd.conf`: `hw_mode=a`, `channel=36`, `ht_capab=[SHORT-GI-20][SHORT-GI-40][HT40+]`,
`country_code=US`, `wmm_enabled=1`, WPA2-PSK (`wpa=3` mixed in stock; pass `12345678`).

- **Channel** is owned by `riddleBoxCfg -g WiFiChannel` (unset → default **36**).
  `start_bluetooth_wifi.sh` auto-sets `hw_mode` (`a` for ch 34–165, `g` for 1–14) and rewrites
  the `channel=` / `wpa_passphrase=` lines on every AP start — so set channel via `riddleBoxCfg`,
  not by hand-editing hostapd.conf.
- **Use non-DFS channels for CarPlay.** US non-DFS: UNII-1 **36/40/44/48**, UNII-3
  **149/153/157/161/165**. DFS (52–144) imposes a 60 s CAC startup blackout + radar-vacate
  dropouts — bad for a fast-boot automotive link. Valid HT40+ non-DFS primaries: **36, 44, 149, 157**.

## 5. Measured link behavior (bench, high SNR)

Single client = lima `wifibox` VM's RTL8832BU dongle (the only station available); SNR 42–50 dB,
bench-close. Representative of *no-regression + relative* behavior, **not** real CarPlay AV quality.

| Metric | Value |
|---|---|
| Negotiated rate | all **HT MCS7 / BW40 / SGI** |
| HTTP download throughput | ~9 MB/s (**~76 Mbps**) |
| Idle latency / jitter / loss | 2.9 ms / 0.4 ms / **0%** |
| Errors at high SNR | **0** retries, 0 FCS, 0 ack-failures (pristine) |
| Latency under saturating download | avg ~4 ms, **max ~43 ms** (downlink bufferbloat); 0% loss |

The bufferbloat spike appears only under a *saturating bulk transfer*; paced CarPlay AV likely
never hits it, and it is not tunable on this embedded stack.

## 6. Telemetry & operational notes

- **Driver telemetry:** `/proc/mwlan/adapter0/{wlan0,sta0}/{info,debug,histogram/wlan-ant0,log}`
  and `/proc/net/wireless`. `info` gives media_state, byte/pkt counters, `failed_count`,
  `ack_failure_count`, `fcs_error_count`. `histogram/wlan-ant0` decodes a rate-index → MCS/BW/GI
  table plus an SNR histogram (best WiFi-layer signal on this box — there is **no `iw`/`iwlist`/
  `mlanutl`/`wpa_cli`** present).
- **hostapd respawn watchdog:** `boxNetworkService` restarts hostapd ~1 s after it dies (resilient,
  but races A/B config tests). To test hostapd cleanly: `killall -STOP boxNetworkService`, run
  foreground `hostapd -t /etc/hostapd.conf` (reaches `AP-ENABLED` or prints the exact error),
  then `killall -CONT boxNetworkService`.
- **Recover a wedged `wlan0`** (after a rejected `ht_capab`): `killall hostapd; ifconfig wlan0 down;
  ifconfig wlan0 up; /script/start_bluetooth_wifi.sh`.

## 7. Cross-references
- `hardware_revisions.md` — IW416 SDIO id, firmware blob/version, per-revision identity (Rev A/B).
- `../CPC200-CCPA_SSH_over_USB_NCM.md` — root SSH over USB-NCM (the out-of-band path used here).
- `../02_Protocol_Reference/wireless_carplay.md` — wireless CarPlay protocol over this AP (describes the RTL88x2CS/11ac variant; see variant note §intro).
- `hardware_platform.md` — platform overview (documents the RTL88x2CS variant; IW416 is the other variant — see variant note §intro).

# CPC200-CCPA Replacement Web Interface

**Version:** 1.0
**Created:** 2026-01-20
**Compatible Firmware:** 2025.10.x
**Device:** CPC200-CCPA (A15W)

## Overview

A minimal, lightweight replacement for the OEM Vue.js web interface. This replacement is 90% smaller while providing full feature parity plus additional features.

| Metric | OEM | Replacement |
|--------|-----|-------------|
| Total Size | ~712 KB | ~70 KB |
| Framework | Vue.js 2.x | Vanilla JS |
| Dependencies | 15+ | 0 |
| Languages | 6 | 1 (English) |

## Features

### Settings (Full Parity + Restored Hidden Settings)
- **Audio:** Media Delay, Audio Quality, Echo Delay, Nav Volume, Mic Type*, Audio Source*
- **Video:** Screen DPI, Display Size, Bit Rate, Mouse Mode*, Knob Mode*, Background Mode*, Improved Fluency*
- **Connection:** Auto Connect, Auto Play, Fast Connect*, WiFi Channel, Start Delay, GPS*, USB Passthrough*, Advanced Features*
- **Identity:** WiFi Name, Bluetooth Name, Box Name, Custom Car Logo

*Settings marked with * were hidden in OEM 2025.10 but are now restored*

### Additional Features (Not in OEM)
- **Live System Stats** - Auto-refresh every 2 seconds via BoxMonitor API
- **CPU Governor Control** - Switch between ondemand/performance/powersave
- **Log Downloads** - dmesg, userspace logs, riddle.conf
- **WiFi Client List** - View connected devices
- **Memory Details** - Shows used/total MB, not just percentage
- **WiFi Throughput** - Real-time RX/TX rates + totals
- **Factory Reset with Restart Prompt** - Prompts to restart device after factory reset

### Excluded Features
- Multi-language support (English only)
- Firmware Update page
- Feedback/Bug Report page

## File Manifest

### Web Files (14 files, ~70 KB total)

| File | Target Location | Permissions | Size | Description |
|------|-----------------|-------------|------|-------------|
| index.html | /etc/boa/www/ | 644 | 24 KB | Main single-page application |
| css/style.css | /etc/boa/www/css/ | 644 | 6.5 KB | Dark theme stylesheet |
| js/api.js | /etc/boa/www/js/ | 644 | 9 KB | API wrapper with MD5 signing |
| js/app.js | /etc/boa/www/js/ | 644 | 23 KB | Application logic |

### CGI Scripts (9 files)

| File | Target Location | Permissions | Size | Description |
|------|-----------------|-------------|------|-------------|
| server.cgi | /etc/boa/cgi-bin/ | 755 | 48 KB | OEM API backend (required) |
| upload.cgi | /etc/boa/cgi-bin/ | 755 | 36 KB | OEM upload handler (required) |
| config.cgi | /etc/boa/cgi-bin/ | 755 | 1 KB | Extended settings via riddleBoxCfg |
| sysinfo.cgi | /etc/boa/cgi-bin/ | 755 | 1.2 KB | System stats (CPU, mem, temp) |
| governor.cgi | /etc/boa/cgi-bin/ | 755 | 1 KB | CPU governor control |
| logs.cgi | /etc/boa/cgi-bin/ | 755 | 1.3 KB | Log file downloads |
| wifi_clients.cgi | /etc/boa/cgi-bin/ | 755 | 1.4 KB | Connected WiFi clients |
| restart.cgi | /etc/boa/cgi-bin/ | 755 | 0.5 KB | Device restart |
| streamstats.cgi | /etc/boa/cgi-bin/ | 755 | 1.4 KB | Live statistics streaming |

## Folder Structure

```
new_website/
└── etc/
    └── boa/
        ├── www/
        │   ├── index.html      # Main entry point
        │   ├── css/
        │   │   └── style.css   # Dark theme
        │   └── js/
        │       ├── api.js      # API wrapper + MD5
        │       └── app.js      # Application logic
        └── cgi-bin/
            ├── server.cgi      # OEM API backend (required)
            ├── upload.cgi      # OEM upload handler (required)
            ├── config.cgi      # Extended settings query
            ├── sysinfo.cgi     # System stats
            ├── governor.cgi    # CPU governor
            ├── logs.cgi        # Log downloads
            ├── wifi_clients.cgi # WiFi clients
            ├── restart.cgi     # Device restart
            └── streamstats.cgi # Live stats
```

## Installation

### Using the Install Script (Recommended)

```bash
# Install new website (removes OEM, installs replacement)
./cpc200_website.sh install 192.168.43.1

# Restore OEM website
./cpc200_website.sh restore 192.168.43.1
```

### Manual Installation

```bash
# SSH to adapter
ssh root@192.168.43.1

# Extract to root filesystem
cd /mnt/UPAN
tar -xzf new_website.tar.gz -C /

# The Boa server will automatically use files from /etc/boa/
# on next reboot, or you can restart Boa manually
```

## API Endpoints

### OEM Endpoints (server.cgi)

| Command | Description |
|---------|-------------|
| `infos` | Get settings, device info, paired devices |
| `set` | Set configuration parameter |
| `reset` | Reset to previous config |
| `resetApp` | Factory reset (restore defaults) |
| `restart` | Reboot device |
| `BoxMonitor` | Real-time system stats |

### Custom Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/cgi-bin/config.cgi` | GET | Extended settings via riddleBoxCfg |
| `/cgi-bin/sysinfo.cgi` | GET | System stats (CPU, mem, temp, uptime) |
| `/cgi-bin/governor.cgi` | GET/POST | CPU governor control |
| `/cgi-bin/logs.cgi?type=X` | GET | Download logs (dmesg/userspace/config) |
| `/cgi-bin/wifi_clients.cgi` | GET | Connected WiFi clients |
| `/cgi-bin/restart.cgi` | POST | Restart device |

## Data Sources

The web interface queries settings from two sources:

1. **server.cgi `infos` command** - Returns 13 basic settings
2. **config.cgi** - Returns 11 extended settings via `riddleBoxCfg -g`

This dual-source approach is required because the OEM `infos` API doesn't return all settings.

## Notes

### Settings Marked with *
Settings marked with `*` in the UI may be overridden by the host app (CarPlay/Android Auto head unit) via USB protocol messages.

### Devices Tab
The Devices tab shows **saved/paired wireless devices** from `DevList`, not the currently active USB connection. This is the same behavior as the OEM website. The currently active connection (CarPlay/Android Auto) is shown on the Dashboard via `BoxMonitor.MDLinkType`.

### Known Firmware Bugs
- **CallQuality**: Removed from UI. Firmware bug (CallQuality doesn't update VoiceQuality), and VoiceQuality itself has no effect on CarPlay — iPhone controls audio format via AirPlay (always 16kHz WB). Only relevant for AA HFP Bluetooth codec negotiation.
- **AutoPlauMusic**: Firmware uses typo "Plau" instead of "Play"

### Security
- Input sanitization applied to text fields
- No external dependencies or CDN resources
- All code runs locally on the adapter

## Changelog

### v1.1 (2026-01-22)
- Factory reset now prompts for device restart after completion
- Added `doRestart()` helper for programmatic restart without confirmation
- Clarified Devices tab shows saved/paired devices only (same as OEM behavior)

### v1.0 (2026-01-20)
- Initial release
- Full settings parity with OEM
- Restored 10 hidden settings
- Added live system stats
- Added CPU governor control
- Added log downloads
- Added WiFi client list
- 90% size reduction from OEM

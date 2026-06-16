# CPC200-CCPA OEM Website Backup

**Created:** 2026-01-20
**Firmware Version:** 2025.10.15.1127
**Device:** CPC200-CCPA (A15W)

## Overview

This backup contains the original OEM web interface files from the CPC200-CCPA wireless CarPlay/Android Auto adapter. These files can be used to restore the factory web interface if needed.

## Storage Locations

### Persistent Storage (survives reboot)
- `/etc/boa/` - Main configuration and web files

### Runtime Storage (tmpfs - recreated on boot)
- `/tmp/boa/www` - Web document root (copied from /etc/boa/www on boot)
- `/tmp/boa/cgi-bin` - CGI scripts (copied from /etc/boa/cgi-bin on boot)

## File Manifest

### Configuration Files

| File | Location | Permissions | Executable | Size | Description |
|------|----------|-------------|------------|------|-------------|
| boa.conf | /etc/boa/ | 750 | No | 10 KB | Boa web server configuration |

### CGI Scripts

| File | Location | Permissions | Executable | Size | Description |
|------|----------|-------------|------------|------|-------------|
| server.cgi | /etc/boa/cgi-bin/ | 755 | Yes | 48 KB | Main API backend (UPX-packed ARM ELF) |
| upload.cgi | /etc/boa/cgi-bin/ | 755 | Yes | 36 KB | File upload handler (UPX-packed ARM ELF) |
| api.cgi | /etc/boa/cgi-bin/ | 777 | Yes | 3.4 KB | Legacy API script |

### HTML Files

| File | Location | Permissions | Executable | Size | Description |
|------|----------|-------------|------------|------|-------------|
| index.html | /etc/boa/www/ | 777 | Yes | 6.6 KB | Main Vue.js SPA entry point |
| advanced.html | /etc/boa/www/ | 755 | Yes | 43 KB | Advanced settings page |
| favicon.png | /etc/boa/www/ | 666 | No | 7.2 KB | Site favicon |

### JavaScript Files (Vue.js Application)

| File | Location | Permissions | Size | Description |
|------|----------|-------------|------|-------------|
| PublicV2.*.js.gz | /etc/boa/www/js/ | 666 | 13 KB | Main Vue.js application |
| chunk-vendors.*.js.gz | /etc/boa/www/js/ | 666 | 132 KB | Third-party libraries |
| chunk-cd071940.*.js.gz | /etc/boa/www/js/ | 666 | 15 KB | Settings page chunk |
| chunk-34badab5.*.js.gz | /etc/boa/www/js/ | 666 | 16 KB | Feedback page chunk |
| chunk-28e9b581.*.js.gz | /etc/boa/www/js/ | 666 | 14 KB | Activation page chunk |
| chunk-c5b13f76.*.js.gz | /etc/boa/www/js/ | 666 | 9 KB | Device management chunk |
| chunk-4404cf19.*.js.gz | /etc/boa/www/js/ | 666 | 6 KB | Dashboard chunk |
| chunk-481f29b2.*.js.gz | /etc/boa/www/js/ | 666 | 3 KB | Box info chunk |
| chunk-69cdecda.*.js.gz | /etc/boa/www/js/ | 666 | 2 KB | Help page chunk |
| (+ 41 smaller chunks) | /etc/boa/www/js/ | 666 | various | Lazy-loaded route chunks |

### Language Files

| File | Location | Permissions | Size | Language |
|------|----------|-------------|------|----------|
| en-*.js.gz | /etc/boa/www/lang/ | 666 | 4.5 KB | English |
| zh-*.js.gz | /etc/boa/www/lang/ | 666 | 4.5 KB | Chinese (Simplified) |
| tw-*.js.gz | /etc/boa/www/lang/ | 666 | 4.5 KB | Chinese (Traditional) |
| ko-*.js.gz | /etc/boa/www/lang/ | 666 | 3.8 KB | Korean |
| ru-*.js.gz | /etc/boa/www/lang/ | 666 | 6.1 KB | Russian |
| hu-*.js.gz | /etc/boa/www/lang/ | 666 | 3.7 KB | Hungarian |

### CSS Stylesheets

| File | Location | Permissions | Size | Description |
|------|----------|-------------|------|-------------|
| chunk-vendors.*.css.gz | /etc/boa/www/static/css/ | 666 | 30 KB | Vendor styles |
| PublicV2.*.css.gz | /etc/boa/www/static/css/ | 666 | 0.5 KB | Main app styles |
| (+ 11 chunk CSS files) | /etc/boa/www/static/css/ | 666 | various | Component styles |

### Images

| File | Location | Permissions | Size | Description |
|------|----------|-------------|------|-------------|
| carlogo.png | /etc/boa/images/ | 640 | 34 KB | Default car logo |
| PublicV2.*.png | /etc/boa/www/static/img/ | 666 | 7.2 KB | App icon |
| (+ 33 SVG icons) | /etc/boa/www/static/img/ | 666 | various | UI icons |

## Total Size

- **111 files**
- **~578 KB** (compressed with gzip)
- **~712 KB** when extracted to /tmp/boa/

## Folder Structure

```
website_backup/
└── etc/
    └── boa/
        ├── boa.conf                    # Web server config
        ├── cgi-bin/
        │   ├── api.cgi                 # Legacy API
        │   ├── server.cgi              # Main API backend
        │   └── upload.cgi              # File upload handler
        ├── images/
        │   └── carlogo.png             # Default car logo
        └── www/
            ├── index.html              # Main entry point
            ├── advanced.html           # Advanced settings
            ├── favicon.png             # Site icon
            ├── js/                     # Vue.js chunks (50 files)
            ├── lang/                   # Language packs (6 files)
            └── static/
                ├── css/                # Stylesheets (13 files)
                └── img/                # Icons (34 files)
```

## Restore Instructions

To restore the OEM website:

```bash
# From adapter shell
cd /mnt/UPAN/website_backup
tar -xzf ../website_backup.tar.gz -C /

# Or use the install script
./cpc200_website.sh restore <adapter_ip>
```

## Notes

- All `.gz` files are gzip-compressed and served directly by Boa
- CGI binaries are UPX-packed ARM ELF executables
- The web server (Boa) automatically copies files from /etc/boa to /tmp/boa on boot
- Files in /tmp/boa are lost on reboot (tmpfs)

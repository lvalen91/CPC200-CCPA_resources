These files are a backup of one of my adapters.

Specifically this in CDC-NCM mode at backup. This will not initialize correctly as other adapters for Projection.

This adapter has ssh available via NCM at 192.168.50.2 and also in the normal WIFI network at 192.168.43.1

The trigger file is /script/ncm_only
it's presence at boot will kill and prevent the normal services and enable ncm via USB. Remove that file and restart the adapter for 'normal' operations. Or place that file for ncm-only.

These backsup are limited to matching adapters, their uboot is keyed specifically at production, there is documented research on this. And the rootfs needs the correct WLAN firmware to boot properly.

This backup is from a Realtek, RTL8822CS adapter.

**Removed 2026-10-20 (owner decision): `on-device_dd/mtd2.bin`, `on-device_dd/full_spi_16mb.bin` and
`XGecu_dump/A15W_rt8822cs_xgecu.bin`** — each holds this unit's JFFS2 rootfs, which embeds device
credentials (dropbear private host keys, root password hash, Wi-Fi config). Only `on-device_dd/mtd0.bin`
and `mtd1.bin` stay in the repo (earlier commits still contain the removed files). Byte-identical local
copies: `~/Documents/carlink/carlinkit_misc/ccpa_backups/_removed_from_repo_2026-10-20/CPC200-CCPA_resources/flash_dumps/2026.06.07.ncm/`
(sha256 in `../README.md`, "Images removed 2026-10-20"). A restore uses those copies.

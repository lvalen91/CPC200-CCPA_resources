These files are a backup of one of my adapters.

Specifically this in CDC-NCM mode at backup. This will not initialize correctly as other adapters for Projection.

This adapter has ssh available via NCM at 192.168.50.2 and also in the normal WIFI network at 192.168.43.1

The trigger file is /script/ncm_only
it's presence at boot will kill and prevent the normal services and enable ncm via USB. Remove that file and restart the adapter for 'normal' operations. Or place that file for ncm-only.

These backsup are limited to matching adapters, their uboot is keyed specifically at production, there is documented research on this. And the rootfs needs the correct WLAN firmware to boot properly.

This backup is from a Realtek, RTL8822CS adapter.

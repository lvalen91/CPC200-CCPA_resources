You must be on 2025.10.15.1127 with the SSH minimal CFW.

This NCM CFW was built on that adapter SW state. Any deviation and assume failure and adapter brick-state.

Purpose of this CFW is to add a clean switch for adapters NCM over its USB connection, killing Projection support while in that mode. Makes use of a new trigger file that must be placed in /script/

ncm_only   NCM over USB only. Projection and the WiFi AP stay down.
ncm_wifi   NCM over USB plus the normal WiFi AP is raised as a fallback.

A simple 'touch /script/ncm_only' for example while connected via SSH will trigger it on the next adapter boot. Remove the file created and the adapter boots into its normal Projection operational state. With neither file present the adapter behaves stock.

This is not specific to a WLAN chipset. Its been tested on RTL and IW adapters.

While the adapter is configured for NCM, SSH is available via USB at 192.168.50.2 with a blank root password. In ncm_wifi mode SSH is also reachable over the WiFi AP at 192.168.43.1. NCM comes up at about 3 seconds into boot, before WLAN/BT.

This ncm update img replaces the majority of the /script files. Most were simple rewrites for cleaner layout. Some were specifically to change the bootup to allow this to work. The img is a file overlay only, it does not touch uboot or the kernel.

This build also replaces two boot files under /etc. Both are boot critical, so test one recoverable adapter first.

/etc/init.d/rcS    Dead code removed, boot ordering corrected so devpts is mounted before the ssh daemons, and a couple of broken TCP sysctls fixed (removed tcp_tw_recycle, re-enabled SACK; the vendor buffer sizes were left as is). No chipset or board specific code.

/etc/inittab       Adds a passwordless root shell on the serial console ttymxc0 at 115200 8N1. Bluetooth always uses ttymxc2 so ttymxc0 is free on every variant. This is an always on root console on the pins, intended for bench and recovery. The kernel console is a write only log device, so the pins are otherwise silent.

sync_box_time.sh was rewritten to use public US NTP servers by IP (NIST, Cloudflare, Google) in place of the old curl to www.paplink.cn. The system clock is kept in UTC, no timezone offset. It needs an internet route to succeed, which NCM by itself does not provide, so it only sets time when the adapter has an upstream. It fails fast and never blocks boot when there is no route. There is no battery backed RTC, so time is not held across a cold power cycle.

custom_init.sh uses a fixed generic NCM MAC, c2:8e:30:53:48:01, so the same image is safe to flash on any unit.

Deploy: copy A15W_NCM_Update.img to a FAT32 USB drive, rename it to A15W_Update.img, plug into the adapter on its own power, wait for the LED to finish, then remove the drive and power cycle. Then SSH in and touch the trigger file you want.

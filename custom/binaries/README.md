# Custom static-musl ARMv7 binaries (CPC200-CCPA, IW416)

Built for: ARMv7 Cortex-A7 (i.MX6UL), kernel 3.14.52, glibc 2.20 on device.
Method: static-musl via `zig cc -target arm-linux-musleabihf -static` (zig 0.13.0) in an
Alpine aarch64 Lima VM. Static = zero glibc/kernel-version dependency; static-PIE verified
to exec on kernel 3.14. No packing (live SSH replace; jffs2 compresses).

## dropbear-2026.91-static-musl-armv7  (dropbearmulti, 404K, stripped)
- Upgrades stock dropbear v2020.81 -> v2026.91 (CVE fixes).
- MULTI build: server + dropbearkey + dbclient + scp + dropbearconvert (dispatch by argv0).
- localoptions.h override: `#define DEFAULT_PATH "/usr/sbin:/usr/bin:/sbin:/bin"`
  -> fixes the non-interactive `ssh host cmd` PATH gap (dropbear's stock default was /usr/bin:/bin).
- Installed on device as /usr/sbin/dropbear (argv0=dropbear => server). rcS launches bare `dropbear`,
  loads default /etc/dropbear/dropbear_{ed25519,ecdsa,rsa}_host_key. Verified serving :22.

Build recipe: configure --host=arm-linux-musleabihf, CC="zig cc -target arm-linux-musleabihf",
AR="zig ar", RANLIB="zig ranlib", CFLAGS="-Os -ffunction-sections -fdata-sections",
LDFLAGS="-static -s -Wl,--gc-sections", --disable-zlib --disable-{lastlog,utmp,utmpx,wtmp,pututline,pututxline},
make MULTI=1 PROGRAMS="dropbear dropbearkey dbclient scp dropbearconvert".

## busybox-1.37.0-static-musl-armv7  (978K, stripped, 402 applets)
- Upgrades stock busybox v1.32.1 -> v1.37.0.
- Built FROM SOURCE in an armv7 Alpine chroot (qemu-user, binfmt F-flag) inside the
  aarch64 Lima VM -> native Alpine musl gcc 15.2.0 (zig-cc failed on busybox Kbuild).
- defconfig + CONFIG_STATIC=y; disabled CONFIG_{TC,PAM,WERROR,SHA1_HWACCEL,SHA256_HWACCEL}
  (HWACCEL are x86 SHA-NI -> undeclared on ARM; TC needs tc headers). Needs apk linux-headers.
- Parity vs stock 350 applets: superset (402); only tc+nuke absent (both unused).
- BEHAVIOR DELTA: this build's `ps` lacks `-w` (stock 1.32.1 had it); `ps -l` still works.
  Appliance scripts updated to plain `ps`. Watch for `ps -w` in any future scripts.
- Installed as /bin/busybox via stage+atomic-rename (can't overwrite running PID1 binary:
  ETXTBSY). Verified boot with 1.37 as init/PID1; NCM/WLAN/BT/dropbear all OK.

# CPC200-CCPA Custom Kernel Compilation

**Purpose:** Feasibility analysis and build guide for compiling a custom/updated Linux kernel for the CPC200-CCPA (i.MX6ULL)
**Date:** 2026-06-30
**Status:** Feasibility confirmed; full workflow documented

---

## TL;DR

| Goal | Feasibility | Hard Constraint |
|------|-------------|-----------------|
| Patch existing zImage binary | **Yes** — easiest path | Re-encrypt with keystream.bin |
| Recompile same kernel (3.14.52) from NXP BSP | **Yes** — straightforward | Module vermagic must match |
| Compile newer kernel (5.x / 6.x) | **Yes** to compile; **No** to run fully | Binary-only .ko files in rootfs won't load |
| Custom u-Boot | **No** | HAB Closed; need Hewei's HAB signing key |

---

## What Cannot Be Changed: u-Boot

The i.MX6ULL boot ROM verifies u-Boot against the SRK hash burned in OCOTP (HAB Closed, MISC_CONF=0x40). The SRK signing key is Hewei's RSA private key — not public, not extractable. Any modified or self-compiled u-Boot will be rejected at the boot ROM stage and the device will not boot.

**u-Boot modification is a dead end without Hewei's signing key.**

---

## What Can Be Changed: Kernel and Rootfs

U-Boot does **not** sign or verify the kernel. It only:
1. Decrypts mtd1 with the per-chip OTPMK key (DCP stream cipher)
2. Gunzips the result
3. Jumps to the zImage entry point

Any correctly re-encrypted kernel (using `keystream.bin`) will run. See `05_Security_Analysis/kernel_encryption.md` for the re-encryption recipe.

Rootfs (mtd2) is plain JFFS2 with no crypto or signing at all — freely modifiable.

---

## Path 1: Binary Patch the Existing Kernel (Recommended for Small Changes)

For small fixes (disable a check, patch a syscall, change a flag), the existing decrypted zImage can be patched in-place.

```bash
# Step 1: Decrypt
python3 -c "
ct = open('mtd1.bin','rb').read(3358720)
ks = open('keystream.bin','rb').read()
open('decrypted_gzip.bin','wb').write(bytes(a^b for a,b in zip(ct,ks)))
"

# Step 2: Decompress
gunzip -c decrypted_gzip.bin > zimage_decrypted.bin

# Step 3: Patch zimage_decrypted.bin with hex editor or binary patch

# Step 4: Re-compress
gzip -9 -c zimage_patched.bin > modified_gzip.bin

# Step 5: Re-encrypt
python3 reencrypt.py   # see kernel_encryption.md

# Step 6: Flash
flash_erase /dev/mtd1 0 0 && nandwrite -p /dev/mtd1 new_mtd1.bin
```

Size constraint: `modified_gzip.bin` must be <= 3,358,720 bytes.

---

## Path 2: Recompile the Same Kernel Version (Linux 3.14.52)

### NXP BSP Source

The device runs `Linux 3.14.52+g94d07bb`. The commit `94d07bb` is in NXP's `linux-imx` repository:

```bash
git clone https://github.com/nxp-imx/linux-imx
cd linux-imx
git checkout imx_3.14.52_1.1.0_ga   # or search for commit 94d07bb
```

If the exact commit exists, this gives source identical to the running kernel, eliminating the vermagic problem.

### Toolchain

| Parameter | Value |
|-----------|-------|
| Architecture | ARMv7 (Cortex-A7, hard-float) |
| Toolchain prefix | `arm-linux-gnueabihf-` |
| Recommended | Linaro GCC 7.x or crosstool-ng arm-cortex_a7-linux-gnueabihf |

```bash
export CROSS_COMPILE=arm-linux-gnueabihf-
export ARCH=arm
```

### Getting the Kernel Config

**From the live device** (preferred — exact config that produced the running kernel):
```bash
ssh root@192.168.50.2 'zcat /proc/config.gz' > .config
```
(Only works if `CONFIG_IKCONFIG=y` and `CONFIG_IKCONFIG_PROC=y` — likely enabled given it is an embedded development kernel.)

**From the decrypted binary** (fallback):
```bash
scripts/extract-ikconfig zimage_decrypted.bin > .config
```

### Build

```bash
make oldconfig
make -j$(nproc) LOADADDR=0x80008000 zImage
# Output: arch/arm/boot/zImage
gzip -9 -c arch/arm/boot/zImage > new_gzip.bin
```

### Module Vermagic

If you compile with the exact same source at the exact same commit + config, the vermagic string will match the rootfs `.ko` files and existing modules will load. Any deviation in config or source = new vermagic = all binary `.ko` files refuse to load.

Binary-only modules in rootfs that CANNOT be recompiled:
- `g_iphone.ko` — USB iAP2 gadget driver
- `f_ptp_appledev.ko` / `f_ptp_appledev2.ko` — PTP Apple device function
- `g_android_accessory.ko` — AOA gadget
- WiFi driver (RTL88x2CS or IW416 depending on variant)

**If vermagic mismatches, these modules refuse to load and the device will not function.**

---

## Path 3: Newer Kernel (5.x / 6.x) — Research Use Only

NXP maintains `linux-imx` with LTS branches (`lf-6.1.y`, `lf-5.15.y`) supporting i.MX6ULL. A newer kernel will boot if:
1. A correct Device Tree Blob (DTB) exists for the CCPA board
2. Required drivers are compiled in (not as modules): RTL8822CS or IW416 WiFi, USB OTG, SPI NOR, audio codec (WM8960/WM8978/AC6966)
3. Re-encrypted correctly with keystream.bin

**Critical blocker:** All proprietary binary `.ko` files in the rootfs are tied to kernel 3.14.52 vermagic. They will not load under any other kernel version. The device will boot but lose CarPlay/Android Auto functionality (USB iAP2 gadget, WiFi).

**Mitigations (not trivial):**
- Replace all binary modules with open-source equivalents where they exist (RTL8822CS driver exists in-tree since 5.10; IW416 driver exists via NXP SDK)
- The custom `g_iphone.ko` USB gadget has no public source — would need RE and reimplementation

This path is realistic only if the goal is to run a completely different stack (e.g., pure open-source CarPlay implementation) and the original firmware functionality is not needed.

---

## Device Tree (DTB)

The DTB is stored at flash offset 0x5F0000 (u-Boot reads it with `sf read 0x83000000 0x5F0000 0x10000`).

To extract the current DTB:
```bash
# From live device
dd if=/dev/mtdblock4 of=ccpa.dtb bs=512    # adjust mtd number
# OR from u-Boot backup image at offset 0x5F0000 in full flash dump
dd if=full_flash.bin of=ccpa.dtb bs=1 skip=$((0x5F0000)) count=65536

# Decompile to DTS
dtc -I dtb -O dts ccpa.dtb -o ccpa.dts
```

The DTS must be updated to match target kernel version if switching kernels.

---

## Full Workflow (Compile + Deploy)

```
1. Get kernel source    git clone nxp-imx/linux-imx; git checkout imx_3.14.52_1.1.0_ga
2. Get config           ssh root@device 'zcat /proc/config.gz' > .config
3. Modify as needed     make menuconfig
4. Compile              ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- make -j8 zImage
5. Compress             gzip -9 arch/arm/boot/zImage -c > new_gzip.bin
6. Re-encrypt           python3 reencrypt.py  (from kernel_encryption.md)
7. Flash                flash_erase /dev/mtd1 0 0 && nandwrite -p /dev/mtd1 new_mtd1.bin
8. Boot                 reboot (or power cycle)
```

---

## Summary Table

| Modification | Requires | Blocker |
|---|---|---|
| Binary patch (small change) | keystream.bin | Size constraint (≤3,358,720B gzip) |
| Same kernel recompile | NXP BSP source + exact config | Module vermagic |
| Different kernel config | NXP BSP source | Module vermagic → binary .ko broken |
| Newer kernel (5.x/6.x) | NXP BSP + DTB + open drivers | All binary .ko broken; g_iphone.ko has no OS source |
| Custom u-Boot | Hewei HAB signing key | HAB Closed → impossible without key |

---

## References

- NXP linux-imx BSP: `https://github.com/nxp-imx/linux-imx`
- Re-encryption recipe: `05_Security_Analysis/kernel_encryption.md`
- HAB/SRK/OTPMK architecture: `01_Firmware_Architecture/secure_boot_hab.md`
- Flash layout: `01_Firmware_Architecture/flash_layout.md`
- Hardware platform (SoC, toolchain): `01_Firmware_Architecture/hardware_platform.md`

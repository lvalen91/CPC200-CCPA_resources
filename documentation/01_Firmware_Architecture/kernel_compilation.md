# CPC200-CCPA Custom Kernel Compilation

**Purpose:** Feasibility analysis and build guide for compiling a custom/updated Linux kernel for the CPC200-CCPA (i.MX6ULL)
**Date:** 2026-06-30; **corrected 2026-10-19** (real on-flash format; staging-block write path; Path 3 proven on hardware)
**Status:** Feasibility confirmed. **A replacement kernel has been booted on hardware** (LIVI 9.5.0, mainline Linux 7.2.10, 2026-10-19). The `keystream.bin` recipe that used to be here was never real and is removed. Evidence E1/E2/E3 and labels as defined in `05_Security_Analysis/kernel_encryption.md`. **[Added 2026-10-20]** All kernel/rootfs replacement work is in `custom/kernel_rootfs/`: the E1 backup, the run logs (`hardware_tests/`), the tools, the LIVI analysis (`livi/README.md`) and the vanilla baseline recipe (`baseline/`). The baseline has been built and booted in QEMU only. Its first hardware write, on 2026-10-20, is OPEN.

---

## TL;DR

| Goal | Feasibility | Hard Constraint |
|------|-------------|-----------------|
| Patch existing zImage binary | **Yes** — easiest path | Recover the zImage from the staging blocks, patch, stage it back (UpgKey); zImage ≤ `0x302fd8` B |
| Recompile same kernel (3.14.52) from NXP BSP | **Yes** — straightforward | Module vermagic must match (only matters if the vendor `.ko` files are kept) |
| Compile newer kernel | **Yes — proven on hardware 2026-10-19** (LIVI 9.5.0, Linux 7.2.10) | The vendor binary-only `.ko` files won't load; the replacement must bring its own drivers/userspace |
| Custom u-Boot | **No** | HAB Closed; need Hewei's HAB signing key |

> **[Corrected 2026-10-19]** The first row's constraint was "Re-encrypt with keystream.bin". There is no keystream: that recipe was retracted on 2026-06-30 (`kernel_encryption.md`) but stayed in this file until now.

---

## What Cannot Be Changed: u-Boot

The i.MX6ULL boot ROM verifies u-Boot against the SRK hash burned in OCOTP (HAB Closed, MISC_CONF=0x40). The SRK signing key is Hewei's RSA private key — not public, not extractable. Any modified or self-compiled u-Boot will be rejected at the boot ROM stage and the device will not boot.

**u-Boot modification is a dead end without Hewei's signing key.**

---

## What Can Be Changed: Kernel and Rootfs

U-Boot does **not** sign or verify the kernel [VERIFIED 2026-10-19: a mainline kernel built by a third party booted]. **[Corrected 2026-10-19]** It does not "decrypt mtd1 with a DCP stream cipher and gunzip it". Its `norboot`:
1. reads `0x302fd8` bytes from flash `0x40000` to `0x80800000`;
2. DCP-decrypts (AES-128-CBC, per-chip key) the **first three 64 KB blocks** in place — the rest is plaintext on flash;
3. `bootz`es the zImage, which decompresses itself (U-Boot gunzips nothing).

No one can produce a DCP-encrypted head off-chip. U-Boot makes it, though: `heweiencrypt` takes the head from three **staging blocks** (partition offset `0x302fd8`) encrypted with the software-computable per-unit **UpgKey**. It re-encrypts them with the DCP key and writes them to the head when the env block (mtd0 `0x30000`) has been erased. Format, key derivation, recovery recipe and hardware runs: `05_Security_Analysis/kernel_encryption.md` § On-Flash Kernel Format.

### Writing a kernel (method used on 2026-10-19; same plan as LIVI's `imx6ul-uboot::kernel_partition`)

**[Corrected 2026-10-19]** The first version of these steps had no preconditions and no abort gate. Both are part of the procedure now; the steps themselves are the ones run on E1.

**Preconditions.** Check every one before step 4. If any fails, stop.
- A full backup of mtd0, mtd1 and mtd2, each read twice with equal sha256 (E1 was made this way).
- Re-hash the live `/dev/mtd0` and `/dev/mtd1` and compare them with the dumps the plan was built from. On any difference, stop and rebuild the plan from fresh dumps.
- `/proc/mtd` shows the **vendor** map: `mtd0` `uboot` 256K, `mtd1` `kernel` 3328K, `mtd2` `rootfs` 12800K (sizes `00040000`/`00340000`/`00c80000`). On a unit that already runs LIVI's kernel, `/dev/mtd0` is a 192K read-only `uboot`, `/dev/mtd1` is the 64 KB `env` partition and the kernel is `/dev/mtd2`, so the commands below would hit the wrong partitions; see § Getting back from LIVI instead.
- The update environment decrypted with the unit's UpgKey passes the gzip and CRC32 checks (recipe in `05_Security_Analysis/kernel_encryption.md`). If it does not, the key is wrong: STOP. Staging blocks encrypted with a wrong key become a garbage head when U-Boot converts them.
- Wall power, with nothing else on the supply.
- A SPI-NOR programmer and clip on hand with the 16 MB backup, or an explicit decision to go ahead without one. The 2026-10-19 runs had none; without one, a power cut or a bad write in the window below leaves a unit that cannot be recovered until a programmer is found.
- Run long writes detached from the login session, e.g. `setsid sh -c '…' > /tmp/w.log 2>&1 &`, and poll the log. A closed SSH/telnet session sends SIGHUP to its children; on 2026-10-19 this killed a `flashcp` mid-write (E1 `RUNBOOK.txt`).

**Steps.**
1. From the unit's own dumps, decrypt the update environment (mtd0 `0x2D000`, UpgKey) and read `kernel_len` from `norboot`'s `sf read 0x80800000 0x40000 <len>`. Read the staging offset from `heweiencrypt`'s first `sf read`. Both are build-specific (`0x302fd8` on 2025.10.15.1127, `0x303080` on 2025.02.25.1521).
2. Check the new zImage: magic `0x016f2818` at `+0x24`, length > `0x30000`, length ≤ `kernel_len`.
3. Build the new mtd1 image:
   - start from all `0xFF` at the partition size;
   - copy the **current** DCP head (`[0, 0x30000)`) unchanged;
   - write `zImage[0x30000:]` at `0x30000`;
   - write `zImage[0:0x30000]` at the staging offset, each 64 KB block AES-128-CBC encrypted on its own with the UpgKey, CBC restarted with the same IV per block.
4. Write the image (detached, see above): `flash_erase /dev/mtd1 0 0 && cat new_mtd1.bin > /dev/mtd1 && sync`. Verify `sha256sum /dev/mtd1` against the plan.
5. Erase the env block: `flash_erase /dev/mtd0 196608 1` (mtd-utils 1.4.8 takes byte offsets). Check that mtd0 `[0,0x30000)` is unchanged.
6. **Abort gate, before any reboot.**
   - `dd if=/dev/mtd0 bs=65536 skip=3 count=1 2>/dev/null | sha256sum` must print `71189f7fb6aed638640078fba3a35fda6c39c8962e74dcc75935aac948da9063` (64 KB of `0xFF`).
   - `sha256sum /dev/mtd1` must equal the plan.
   - If either fails, **do not reboot.** The running kernel is in RAM and keeps working. Write the backed-up `mtd1.bin` back (`flash_erase /dev/mtd1 0 0 && cat mtd1.bin > /dev/mtd1 && sync`) and check its sha256 against the backup before doing anything else. The stock mtd1 boots with the unit's original env block (normal operation) and with an erased one (round-trip run, `05_Security_Analysis/kernel_encryption.md`) [VERIFIED]; with a partly erased env block it is expected to fall back to the update environment [INFERRED].
7. Reboot. U-Boot runs `heweiencrypt`, writes the new head and a new env block, and boots the new kernel.

A power cut between the start of step 4 and the end of step 5 leaves the old head on the new body. That unit only recovers with a SPI programmer. About 20 s was measured for `flash_erase` + `cat` + `sync` of mtd1 alone; the rest of that window (the `sha256sum` check and the env erase) was not timed, and the datasheet estimate for erase + program is 22–54 s (`05_Security_Analysis/kernel_encryption.md` § Hardware runs). The stock vendor rootfs ships `flash_erase` as a dynamically linked binary. The OCBM rootfs on the test unit had neither `flash_erase` nor `flashcp`, so the stock binary was copied to `/tmp` (E1 `RUNBOOK.txt`). On SPI NOR use `cat`/`flashcp`, not `nandwrite`.

### Getting back from LIVI to the stock kernel [UNTESTED]

Nothing in this section has been run. `RUNBOOK.txt` (`custom/kernel_rootfs/hardware_tests/2026-10-19_round_trip/`) records the rollback through LIVI's rescue system as not yet tested; the alternative is writing the full 16 MB backup with a SPI programmer. It only works with the **same unit's** backup, because the DCP head in `mtd1.bin` is per chip.

LIVI's MTD map (E3 `scripts/livi-link/arm/imx6ul/imx6ull.dts`; the same map was seen live on 2026-10-19):

| LIVI device | Name | Flash range | Vendor equivalent |
|---|---|---|---|
| `/dev/mtd0` | `uboot` (read-only) | `0x000000`–`0x02FFFF` | mtd0 without the env block |
| `/dev/mtd1` | `env` | `0x030000`–`0x03FFFF` | mtd0 env block |
| `/dev/mtd2` | `kernel` | `0x040000`–`0x37FFFF` | mtd1 |
| `/dev/mtd3` | `rootfs` | `0x380000`–`0xFDFFFF` | mtd2, first `0xc60000` B |
| `/dev/mtd4` | `customer` | `0xFE0000`–`0xFEFFFF` | mtd2, next `0x10000` B |
| `/dev/mtd5` | `bootstate` | `0xFF0000`–`0xFFFFFF` | mtd2, last `0x10000` B |

1. Work from LIVI's rescue initramfs, not from LIVI Link running on its mounted squashfs. LIVI's own provisioning refuses to write the rootfs partition unless it runs in rescue (E3 `boot.rs`).
2. Check that `/proc/mtd` shows exactly the map above and that the backup `mtd1.bin`/`mtd2.bin` match their recorded sha256. **[Added 2026-10-20]** On the IW416 bench unit, first read `/tmp/fc.log` and `sha256sum /dev/mtd2`. A baseline kernel write to that partition was issued on 2026-10-20 and its outcome is OPEN (`custom/kernel_rootfs/hardware_tests/2026-10-20_baseline_kernel_write.md`). The LIVI-state partition is `custom/kernel_rootfs/backups/20261020_livi_pre-baseline/mtd2_dump1.bin` (`c58710c5…`). Same preconditions as above: wall power, programmer or an explicit decision, `setsid` for every write. Fetch files by pulling them from the host; pushing with `nc` truncated three times on 2026-10-19 (`RUNBOOK.txt`).
3. Rootfs first. Split the backup `mtd2.bin` into `0xc60000` + `0x10000` + `0x10000` bytes (`dd bs=65536`, counts 198, 1, 1) and write the parts with `flashcp -v` to `/dev/mtd3`, `/dev/mtd4`, `/dev/mtd5`; check each by sha256. LIVI's kernel, and the rescue initramfs inside it, is still on flash at this point, so this step can be repeated if it fails [INFERRED].
4. Kernel last: `flashcp -v mtd1.bin /dev/mtd2`, then check `sha256sum /dev/mtd2` against the backup `mtd1.bin`.
5. Erase the env partition (`flash_eraseall /dev/mtd1`), as the RUNBOOK restore note says, so U-Boot rebuilds it from the update environment.
6. Abort gate as above, with LIVI's device names: `/dev/mtd1` reads as 64 KB of `0xFF` and `/dev/mtd2` equals the backup `mtd1.bin`. Only then reboot. The unit should come up on the stock kernel and the vendor/OCBM rootfs with the vendor MTD map again.

Rootfs (mtd2) is plain JFFS2 with no crypto or signing at all — freely modifiable.

---

## Path 1: Binary Patch the Existing Kernel (Recommended for Small Changes)

For small fixes (disable a check, patch a syscall, change a flag), the stock zImage can be patched.

**[Corrected 2026-10-19]** The old recipe XORed mtd1 with a `keystream.bin`, gunzipped, re-gzipped and re-encrypted with `reencrypt.py`. None of those files ever existed and the cipher is not a stream cipher; that recipe is removed. The working path:

1. **Recover** the exact flashed zImage from the unit's own staging blocks (recipe in `05_Security_Analysis/kernel_encryption.md`; reproduced the stock build on E1, sha256 `35014617e11d455e…`).
2. **Patch.** The zImage is a decompressor stub plus a gzip payload (at `0x400f` in the stock build, inflating to `0x5e8b6c` bytes). Patch code in the inflated image, then re-gzip it into the payload. That changes the payload's length, so the zImage has to be rebuilt; the simpler route is to rebuild from source (Path 2) with the same config.
3. **Stage** the result as in "Writing a kernel" above.

Size constraint: the zImage must be ≤ `kernel_len` (`0x302fd8` = 3,157,976 B on 2025.10.15.1127), because U-Boot reads exactly that much and the staging blocks start there. It was "≤ 3,358,720 bytes" before 2026-10-19, which was wrong.

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
(Only works if `CONFIG_IKCONFIG=y` and `CONFIG_IKCONFIG_PROC=y`.) **[Corrected 2026-10-19]** Neither is available: `/proc/config.gz` is absent (`kernel_encryption.md` § Anti-Debug), and the recovered stock zImage's inflated image has no `IKCFG_ST` marker [VERIFIED, E1]. The config has to be reconstructed, for example from the NXP `imx_v7_defconfig` plus the symbols in `custom/kernel_dumps/kallsyms_running.txt`.

**From the decrypted binary** (fallback; **[2026-10-19]** yields nothing for the stock build, see above):
```bash
scripts/extract-ikconfig zimage_recovered.bin > .config
```

The banner of the stock build names its compiler: `gcc version 4.9.2 (GCC)` [VERIFIED, E1].

### Build

```bash
make oldconfig
make -j$(nproc) LOADADDR=0x80008000 zImage
# Output: arch/arm/boot/zImage — stage this file as is (no extra gzip; U-Boot does not gunzip) [Corrected 2026-10-19]
```

### Module Vermagic

If you compile with the exact same source at the exact same commit + config, the vermagic string will match the rootfs `.ko` files and existing modules will load. Any deviation in config or source = new vermagic = all binary `.ko` files refuse to load.

Binary-only modules in rootfs that CANNOT be recompiled:
- `g_iphone.ko` — USB iAP2 gadget driver
- `f_ptp_appledev.ko` / `f_ptp_appledev2.ko` — PTP Apple device function
- `g_android_accessory.ko` — AOA gadget
- WiFi driver (RTL88x2CS or IW416 depending on variant)

**If vermagic mismatches, these modules refuse to load and the device will not function** — as long as the device is meant to run the vendor userspace with these modules. Vermagic is irrelevant to a kernel that does not load them (Path 3).

---

## Path 3: Newer Kernel — PROVEN on hardware (2026-10-19)

**[Corrected 2026-10-19]** This path was "research use only". It is now **proven**: LIVI 9.5.0 `imx6ul_iw416` (mainline Linux 7.2.10, GPL) was staged with the method above on an IW416 unit. It booted into its rescue initramfs with its own MTD map, then ran LIVI Link after its squashfs rootfs was written [VERIFIED, E1 `RUNBOOK.txt`].
- Its zImage is 3,124,994 B, 32,982 B under the stock `0x302fd8` limit.
- It carries its own DTB appended to the zImage (`CONFIG_ARM_APPENDED_DTB`, E3 `build.sh`), so it does not depend on the stock DTB U-Boot passes.
- Module vermagic only matters if the vendor `.ko` files are kept; LIVI replaces the whole userspace.
- **[Added 2026-10-20]** A vanilla recipe on the same path is `custom/kernel_rootfs/baseline/`. It uses mainline 7.2.10 with LIVI's patches 0001-0004 and LIVI's MTD map, and adds a recovery initramfs in the kernel and a minimal squashfs. Default image 1,753,695 B, so 1,404,281 B spare under `0x302fd8`. It is MEASURED on the build host and QEMU only, not booted on the board. The 2026-10-20 hardware write is OPEN.

NXP maintains `linux-imx` with LTS branches (`lf-6.1.y`, `lf-5.15.y`) supporting i.MX6ULL, and mainline supports the SoC directly. A newer kernel will boot if:
1. A correct Device Tree Blob (DTB) exists for the CCPA board. Either append it to the zImage, or accept the stock one U-Boot passes at `0x83000000`: the NXP 14x14-EVK tree stored in the U-Boot environment, written for 3.14 bindings.
2. Required drivers are compiled in (not as modules): RTL8822CS or IW416 WiFi, USB OTG, SPI NOR, audio codec (WM8960/WM8978/AC6966)
3. ~~Re-encrypted correctly with keystream.bin~~ Staged through the UpgKey staging blocks, and the zImage is ≤ `0x302fd8` B [Corrected 2026-10-19]

**Critical blocker (for keeping the vendor userspace):** All proprietary binary `.ko` files in the rootfs are tied to kernel 3.14.52 vermagic. They will not load under any other kernel version. The device will boot but lose CarPlay/Android Auto functionality (USB iAP2 gadget, WiFi). This does not block a replacement stack that brings its own drivers (LIVI, above).

**Mitigations (not trivial):**
- Replace all binary modules with open-source equivalents where they exist (RTL8822CS driver exists in-tree since 5.10; IW416 driver exists via NXP SDK)
- The custom `g_iphone.ko` USB gadget has no public source — would need RE and reimplementation

This path is realistic only if the goal is to run a completely different stack (e.g., pure open-source CarPlay implementation) and the original firmware functionality is not needed.

---

## Device Tree (DTB)

**[Corrected 2026-10-19]** The DTB is **not** at flash `0x5F0000`. That offset and `sf read 0x83000000 0x5F0000 0x10000` come from NXP EVK template text U-Boot does not run. In the stock flash `0x5F0000` is inside the rootfs and holds JFFS2 nodes. There is no `mtdblock4`.

The stock DTB is stored **inside the 64 KB U-Boot environment, at offset `0x800`**, and `norboot`'s `cp 0x80800800 0x83000000 0xf800` hands it to the kernel [VERIFIED, E1]:
- FDT `totalsize` 33,027 B.
- `model = "Freescale i.MX6 UltraLite 14x14 EVK Board"`.
- `/memory` 512 MiB (the EVK value; the running kernel sees 128 MiB).

To extract it, decrypt and inflate the update environment with the unit's UpgKey, then take bytes from `0x800` (recipe in `05_Security_Analysis/kernel_encryption.md`):

```bash
dd if=env.bin of=ccpa.dtb bs=2048 skip=1      # env.bin = the inflated 64 KB environment
dtc -I dtb -O dts ccpa.dtb -o ccpa.dts
```

The DTS must be updated to match target kernel version if switching kernels.

---

## Full Workflow (Compile + Deploy)

```
1. Get kernel source    git clone nxp-imx/linux-imx; git checkout imx_3.14.52_1.1.0_ga   (or mainline / another stack)
2. Get config           reconstruct it (no /proc/config.gz, no embedded config in the stock build)
3. Modify as needed     make menuconfig
4. Compile              ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- make -j8 zImage   (≤ 0x302fd8 B)
5. Plan mtd1            current DCP head + zImage body + UpgKey-encrypted staging head (see "Writing a kernel")
6. Preconditions        backups read twice; live mtd0/mtd1 == planned-from dumps; vendor /proc/mtd map; env decrypts (gzip + CRC);
                        wall power; programmer on hand or an explicit decision; setsid for writes (see "Writing a kernel")
7. Flash                flash_erase /dev/mtd1 0 0 && cat new_mtd1.bin > /dev/mtd1 && sync; sha256sum /dev/mtd1 == plan
8. Trigger conversion   flash_erase /dev/mtd0 196608 1   (env block only)
9. Abort gate           env block = 64 KB of 0xFF and mtd1 sha256 == plan, else DO NOT REBOOT: restore mtd1.bin, verify
10. Boot                reboot — U-Boot's heweiencrypt writes the DCP head and a new env, then boots
```

**[Corrected 2026-10-19]** The old steps 5 to 7 were: gzip the zImage, "re-encrypt" with `reencrypt.py`, `nandwrite` to mtd1. That would not boot: no such script exists, U-Boot does not gunzip, and the head cannot be DCP-encrypted off-chip. The flash steps (now 6 to 10) also gained the preconditions and the abort gate on 2026-10-19.

---

## Summary Table

| Modification | Requires | Blocker |
|---|---|---|
| Binary patch (small change) | Unit's UpgKey (= its `uuid`) + staging recovery | zImage ≤ `0x302fd8` B [Corrected 2026-10-19; was "keystream.bin, ≤3,358,720B gzip"] |
| Same kernel recompile | NXP BSP source + reconstructed config | Module vermagic (vendor userspace only) |
| Different kernel config | NXP BSP source | Module vermagic → binary .ko broken (vendor userspace only) |
| Newer kernel | Kernel + DTB (appended) + own drivers/userspace | **Proven 2026-10-19 (LIVI, 7.2.10)**; vendor .ko broken; g_iphone.ko has no OS source |
| Custom u-Boot | Hewei HAB signing key | HAB Closed → impossible without key |

---

## References

- NXP linux-imx BSP: `https://github.com/nxp-imx/linux-imx`
- On-flash kernel format, UpgKey, staging recovery/write recipe: `05_Security_Analysis/kernel_encryption.md`
- LIVI's implementation of the same plan (GPL-3.0-or-later): `native/livi-link/crates/imx6ul-uboot/src/lib.rs`, `native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/boot.rs`
- HAB/SRK/OTPMK architecture: `01_Firmware_Architecture/secure_boot_hab.md`
- Flash layout: `01_Firmware_Architecture/flash_layout.md`
- Hardware platform (SoC, toolchain): `01_Firmware_Architecture/hardware_platform.md`

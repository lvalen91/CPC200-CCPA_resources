# CPC200-CCPA Kernel Encryption Analysis

**Purpose:** Document kernel encryption findings and decryption/re-encryption capability
**Analysis Date:** 2026-01-29 (initial); 2026-06-30 morning session (cipher-mode claim, later found wrong); 2026-06-30 evening session (corrected via fresh disassembly + live DCP register work); 2026-06-30 night session (plaintext kernel recovered from RAM); **2026-10-19 (on-flash format decoded from the U-Boot environment: only the first 3 × 64 KB of the kernel are encrypted; plaintext recovered from flash; replacement kernel booted on hardware)**
**Status:** **Solved in both directions (2026-10-19).** The stock kernel on flash is a plain ARM zImage whose first three 64 KB blocks are DCP-encrypted; a second copy of those three blocks, encrypted with a software-computable per-unit key (U-Boot's `UPGkey`), sits behind the kernel as "staging". Decrypting the staging blocks gives the exact flashed zImage, and writing new staging blocks plus erasing the U-Boot environment block makes U-Boot itself re-encrypt a new kernel head with the DCP key on the next boot. No DCP access from Linux is needed for either direction. The earlier RAM-dump route (2026-06-30 night) and the userspace DCP attempts (2026-06-30 evening) are kept below as history; their "write side is unsolved" conclusion is superseded.

Labels used in the 2026-10-19 material: **[VERIFIED]** = reproduced from the cited files or recorded hardware run; **[OWNER-REPORTED]** = stated by the owner, not reproduced; **[OBSERVED-NOT-RECORDED]** = seen live during the 2026-10-19 work but not saved to any file; **[INFERRED]** = follows from the evidence but was not tested directly; **[UNTESTED]** = a procedure that has not been run; **[UNRESOLVED]** = open.

**Evidence for the 2026-10-19 material** (unit = the OCBM IW416 bench adapter, stock U-Boot 2015.04 + stock kernel 3.14.52 #12):

- **E1** — backup `custom/kernel_rootfs/backups/20261019_IW416_ocbm_baseline_pre-livi/` (in this repo since 2026-10-20; run logs and dry-run files in `custom/kernel_rootfs/hardware_tests/2026-10-19_round_trip/`, `dryrun.py` in `custom/kernel_rootfs/tools/`): `mtd0.bin`, `mtd1.bin`, `mtd2.bin`, `stock_zImage_recovered_3.14.52_build12.bin` (sha256 `35014617e11d455e…`), `round_trip/RUNBOOK.txt` (hardware run log), `round_trip/dryrun.py`, `round_trip/dryrun_report.txt`, `round_trip/livi_9.5.0_iw416_dryrun_report.txt`. **[Corrected 2026-10-19]** This entry said E1 is "not in this repo". Its `mtd0.bin` and `mtd1.bin` are: they have the same sha256 as `flash_dumps/CCPA_stripped/mtd0.bin` and `mtd1.bin`, and the same bytes are the first `0x380000` bytes of `flash_dumps/CCPA_stripped/CPC200-CCPA_full_nor_16MB.bin` and of `nor_backup/full_nor.bin` [VERIFIED]. Only `mtd2.bin` (a later rootfs), the run logs, the dry-run files and the recovered zImage are local. The zImage can be rebuilt from the tracked dumps with the recipe below. **[Corrected 2026-10-20]** All of E1, `unit_info.txt` included, is now tracked under `custom/kernel_rootfs/` (paths above). The sentence before this one describes the 2026-10-19 state. **[Corrected 2026-10-20, later]** E1's `mtd0.bin` and `mtd1.bin` were then removed from the backup folder as byte-identical duplicates; E1's copies are `flash_dumps/CCPA_stripped/mtd0.bin` (`e62f62a9…`) and `mtd1.bin` (`738af784…`), and the folder's `SHA256SUMS` points there.
- **E2** — `carlinkit/firmware_stock/A15W_Update_2025.10.15.1127.img` (this repo), decrypted with the image key in `01_Firmware_Architecture/firmware_encryption.md`: `tmp/AutoBox.img`, `tmp/upg`, `tmp/once.sh`, `tmp/finish.sh`.
- **E3** — LIVI (GPL-3.0-or-later, external): `native/livi-link/crates/imx6ul-uboot/src/lib.rs`, `native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/boot.rs`, `scripts/livi-link/arm/imx6ul/build.sh`, `scripts/livi-link/arm/imx6ul/imx6ull.dts`. Read, not copied.
- **E4** (added 2026-10-19) — a second unit's full NOR dumps in this repo: `flash_dumps/2025.10.15.1127/flash_dump_2025.10.15.1127.bin` and `flash_dumps/2025.02.25.1521/flash_dump_2025.02.25.1521.bin` (`flash_dumps/2026.06.07.ncm/` has the same mtd0/mtd1 bytes as the 2025.10.15.1127 dump). Their update environments and staging blocks decrypt with the `uuid` listed as Rev A in `01_Firmware_Architecture/hardware_revisions.md`; E1's decrypt with the one listed as Rev B [VERIFIED]. **[Resolved 2026-10-20]** `flash_dumps/README.md` calls these dumps Realtek, and they are: their rootfs ships `rtl8822_ko.tar.gz` and no IW416 driver set, so the E4 unit (Rev A) is an RTL8822CS unit. `hardware_revisions.md` listed Rev A as IW416 and as the unit documented in the rest of the repo; it is corrected there: E1 is Rev B, the IW416 unit whose OCOTP words are in `hardware_platform.md`.

---

## TL;DR (2026-10-19)

1. **The kernel is not encrypted as a whole.** [VERIFIED, E1] U-Boot reads `0x302fd8` bytes (3,157,976 B; this length is build-specific, see Kernel partition layout) from flash `0x40000` (the start of mtd1, not `0x100000`) to RAM `0x80800000` and decrypts **only the first three 64 KB blocks** in place (`mm w 0x80800000/0x80810000/0x80820000 0x10000`) before `bootz`. Everything from mtd1 offset `0x30000` to `0x302fd8` is plaintext zImage and is byte-identical to the recovered zImage.
2. **The plaintext head is also stored behind the kernel, under a key software can compute.** [VERIFIED, E1] Three 64 KB "staging" blocks at mtd1 offset `0x302fd8` (flash `0x342fd8`/`0x352fd8`/`0x362fd8`) hold the zImage head, AES-128-CBC encrypted with the **UpgKey**. Each block is encrypted on its own, restarting CBC from the same IV (one continuous CBC stream over the 192 KB does *not* reproduce the flash bytes).
3. **UpgKey** = the 32 ASCII characters `printf("%08x%08x%08x%08x", CFG0, CFG1, MAC0, MAC1)` of the OCOTP words CFG0, CFG1, MAC0, MAC1 (nvmem words 1, 2, 0x22, 0x23). AES key = the first 16 characters as bytes, IV = the last 16. [VERIFIED, E1 + E3 `lib.rs` `UpgKey::new`] U-Boot carries the format string `%08x%08x%08x%08x` at mtd0 `0x1640d`, right before `UPGkey: %s` at `0x1641e`.
4. **The UpgKey text is the adapter's `uuid`.** [VERIFIED for the two units recorded in this repo] The `UUID` values in `01_Firmware_Architecture/hardware_revisions.md` equal the `%08x` concatenation of the matching unit's CFG0/CFG1/MAC0/MAC1 (one checked against E1's fuse words, one against the representative fuse read in `01_Firmware_Architecture/secure_boot_hab.md`). That the text actually decrypts a unit's update environment and staging blocks is also VERIFIED on both units: E1, and the other unit's dumps (E4). The adapter sends that string to the host in BoxSettings `uuid` (`02_Protocol_Reference/device_identification.md`, Adapter → Host), so any connected host learns the key. It is not a secret.
5. **Recovery of the plaintext stock kernel from flash:** decrypt the three staging blocks with the unit's UpgKey and prepend them to mtd1 `[0x30000, kernel_len)`. On E1 this gives a zImage with magic `0x016f2818` at `+0x24`, a gzip payload at `0x400f` that inflates to `0x5e8b6c` bytes and contains `Linux version 3.14.52+g94d07bb (hcw@ubuntu) (gcc version 4.9.2 (GCC) ) #12 SMP PREEMPT Fri Sep 26 16:45:10 CST 2025`. Re-encrypting that head reproduces the staging bytes exactly. [VERIFIED, E1]
6. **Writing a new kernel works without DCP access.** [VERIFIED, E1 `RUNBOOK.txt`] LIVI 9.5.0's mainline 7.2.10 zImage was staged this way on the unit (body written in plain, head written UpgKey-encrypted into staging, old DCP head left in place), the environment block was erased, and U-Boot booted the new kernel. U-Boot does not verify the kernel.

The DCP-key details from 2026-06-30 (AES-128-CBC, `KEY_SELECT=0xfe` unique key) still describe how the **head** is encrypted; they were not re-verified on 2026-10-19.

---

## On-Flash Kernel Format and the U-Boot Conversion Path (2026-10-19)

### The environment U-Boot actually runs

The U-Boot partition (mtd0, 256 KB) has two per-unit areas past the HAB-loaded U-Boot image (`0x0`–`0x21FFF`) (map in `01_Firmware_Architecture/flash_layout.md`):

| mtd0 range | Contents | Key |
|---|---|---|
| `0x2D000`–`0x2FFFF` (tail of the "update block" `0x20000`–`0x2FFFF`) | Update environment: payload length in the block's last 4 bytes (little-endian; `0x3000` on E1), payload = `block[0x10000-len:]` | UpgKey, AES-128-CBC [VERIFIED, E1] |
| `0x30000`–`0x3FFFF` ("env block") | Live environment, 64 KB, entropy 7.997 bits/byte, no plaintext | DCP unique key [INFERRED from `heweiencrypt`'s `mm m` step; cannot be decrypted off-chip] |

The update payload decrypts to a gzip stream that inflates to exactly 64 KB: a U-Boot environment whose first 4 bytes are a CRC32 (little-endian) over `env[4:0x800]`, with the variables in `env[4:0x800]` [VERIFIED, E1 and E4: CRC matches; same parser as E3 `read_env`]. A second CRC32 (little-endian) over `env[0:0xFFFC]` sits in `env[0xFFFC:0x10000]` [VERIFIED, E1 and E4].

What the decrypted `0x3000`-byte payload holds after the gzip stream [VERIFIED, E1]: the stream is 8,391 B, then 3,881 zero bytes, then 16 bytes that are the decryption of the payload's last cipher block, whose last 4 bytes on flash are the raw length word itself. That is why `heweiencrypt` gunzips only `0x2ff0` bytes (`mm z 0x80810000 0x2ff0 …`), and why `gzip` run over the whole decrypted payload reports trailing garbage. (E4's 2025.02.25.1521 payload: 8,393 B stream, 3,879 zero bytes, same layout.)

The variables that matter:

```
bootcmd=run norboot;
bootdelay=3
console=ttymxc0   baudrate=115200   stdin=serial   stdout=serial   stderr=serial
loadaddr=0x80800000
norargs=setenv bootargs console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2
        mtdparts=21e0000.qspi:256k(uboot),3328K(kernel),12800K(rootfs) rootwait quiet rw
norboot=run norargs; sf probe 0; cp 0x80800800 0x83000000 0xf800;
        sf read 0x80800000 0x40000 0x302fd8;
        mm w 0x80800000 0x10000; mm w 0x80810000 0x10000; mm w 0x80820000 0x10000;
        bootz 0x80800000 - 0x83000000
heweiencrypt=sf probe 0;
        sf read 0x80800000 0x342fd8 0x10000; mm d 0x80800000 0x10000; mm m 0x80800000 0x10000; sf update 0x80800000 0x40000 0x10000;
        sf read 0x80800000 0x352fd8 0x10000; mm d …; mm m …; sf update 0x80800000 0x50000 0x10000;
        sf read 0x80800000 0x362fd8 0x10000; mm d …; mm m …; sf update 0x80800000 0x60000 0x10000;
        sf probe 0; sf read 0x80810000 0x2d000 0x3000; mm d 0x80810000 0x3000;
        mm z 0x80810000 0x2ff0 0x80800000 0x10000; mm m 0x80800000 0x10000; sf update 0x80800000 0x30000 0x10000;
heweiencryptfinal=
```

(wrapped for reading; `…` repeats the same address and length.) `norargs` builds exactly the kernel command line captured live (`console=ttyLogFile0 root=/dev/mtdblock2 …`). The `bootdelay=0` / `root=/dev/mtdblock3` / `sf read … 0x100000` / DTB-from-`0x5F0000` environment documented before 2026-10-19 is **not** this environment: it is U-Boot's built-in default plus NXP 14x14-EVK template text left in the image. See `flash_layout.md` § U-Boot Environment.

**`mm` subcommands** (HeWei's, not upstream U-Boot):

| Command | Meaning | Label |
|---|---|---|
| `mm d <addr> <len>` | AES-128-CBC decrypt with the UpgKey | [VERIFIED by equivalence: the same software decrypt of the same flash bytes gives the zImage head and the gzip env] |
| `mm m <addr> <len>` | encrypt with the DCP unique (OTP) key | [INFERRED: its output on flash is not UpgKey-decryptable, and `mm w` undoes it at boot] |
| `mm w <addr> <len>` | decrypt in place with the DCP unique key | [INFERRED: `norboot` boots a head that only the DCP can decrypt; matches the 2026-06-30 disassembly below] |
| `mm z <src> <srclen> <dst> <dstlen>` | gunzip | [INFERRED: the decrypted update payload is gzip and the result is the 64 KB env] |
| `mm u <addr> …` | UNKNOWN | The U-Boot binary builds the strings `mm d 0x` and `mm u 0x` side by side (mtd0 `0x17490` and `0x17498`, right after `heweiencrypt` at `0x17483`) [VERIFIED, E1]; no environment seen uses `mm u`, and its meaning was not traced |

### The stock device tree is inside the environment

The 64 KB environment carries a flattened device tree at offset `0x800` [VERIFIED, E1]: FDT magic `0xd00dfeed`, version 17, `totalsize` `0x8103` (33,027 B, so it ends at env `0x8902`), then `0xFF` padding up to `0xFFFB`, then the second CRC32 at `0xFFFC`–`0xFFFF` (see above) [VERIFIED, E1 and E4]. `norboot`'s `cp 0x80800800 0x83000000 0xf800` copies from `env+0x800` to the DTB address, **before** the kernel is read over `0x80800000` [INFERRED that the live environment sits at RAM `0x80800000` when `norboot` runs; `heweiencrypt` builds the env image at that address]. The count `0xf800` is in units, not bytes: upstream U-Boot 2015.04 `cp` defaults to `.l` (4-byte) units, which would make it `0x3E000` bytes, reaching past the 64 KB env [INFERRED: this U-Boot's `cp` help strings are stripped, only `cp` / `memory copy` remain]. Either way the DTB is the first `0x8103` bytes of what is copied, and the kernel reads its size from the FDT header. This replaces the earlier claim that the DTB is read from flash `0x5F0000` (in the stock flash that offset is inside mtd2, and its 64 KB holds JFFS2 nodes: magic `0x1985` from its first byte, 107 times [VERIFIED, E1 `mtd2.bin`]) and resolves the "no FDT in the kernel, mtd0 or mtd1" search: the FDT is only visible after decrypting and inflating the update payload.

Decompiled with `dtc` [VERIFIED, E1]: `model = "Freescale i.MX6 UltraLite 14x14 EVK Board"`, `compatible = "fsl,imx6ul-14x14-evk", "fsl,imx6ull"`; `/memory` `reg = <0x80000000 0x20000000>` (512 MiB, the EVK value; the running system reports 128 MiB of System RAM, see the `/proc/iomem` capture below); QSPI child `micronix,mx25l12805d` with no partition nodes (partitions come from `mtdparts=` in bootargs); `crypto@2280000` `fsl,imx6ull-dcp`; both `usb@02184000` and `usb@02184200` `dr_mode = "otg"`.

### Kernel partition layout

| mtd1 range | Flash | Contents | Label |
|---|---|---|---|
| `0x000000`–`0x02FFFF` | `0x040000`–`0x06FFFF` | zImage head, DCP-encrypted (the word at `+0x24` is not the zImage magic) | [VERIFIED it is not plaintext; DCP key INFERRED] |
| `0x030000`–`0x302FD7` | `0x070000`–`0x342FD7` | zImage body, **plaintext**, byte-identical to the recovered zImage | [VERIFIED, E1] |
| `0x302FD8`–`0x332FD7` | `0x342FD8`–`0x372FD7` | Staging: zImage head, UpgKey AES-128-CBC, CBC restarted per 64 KB block | [VERIFIED, E1] |
| `0x332FD8`–`0x33FFFF` | `0x372FD8`–`0x37FFFF` | `0xFF` | [VERIFIED, E1] |

The kernel length (`0x302fd8`) and the staging offset come from `norboot` and `heweiencrypt` on the unit; they are build-specific, so read them from the unit's own environment rather than hard-coding them (E3 `lib.rs` `layout()` does this). Staging starts right where the kernel ends (`0x40000 + 0x302fd8 = 0x342fd8`). Example of a different value [VERIFIED, E4]: on 2025.02.25.1521 (kernel `3.14.52+g94d07bb (sky@sky-vmware-1604) … #448 SMP PREEMPT Tue Feb 25 15:18:24 CST 2025`) `kernel_len` is `0x303080`, and staging again starts at partition offset `kernel_len` (flash `0x343080`). 2025.10.15.1127 (#12) uses `0x302fd8` on both E1 and E4.

A replacement zImage must fit in `0x302fd8` bytes, because U-Boot reads exactly that much and the staging blocks start there. LIVI 9.5.0 `imx6ul_iw416` is 3,124,994 B, 32,982 B spare [VERIFIED, E1 `livi_9.5.0_iw416_dryrun_report.txt`].

### `heweiencrypt`: staging → head, run by U-Boot

`heweiencrypt` (environment above) turns staging into a bootable head: for each of the three blocks it reads staging, decrypts with the UpgKey (`mm d`), re-encrypts with the DCP unique key (`mm m`) and writes the result over the matching head block. It then rebuilds the live environment from the update payload (`mm d`, `mm z`, `mm m`) and writes it to the env block (mtd0 `0x30000`), last.

What starts it: with the env block erased, U-Boot came back up and the env block was rewritten [VERIFIED, E1 `RUNBOOK.txt`, both runs below]. That U-Boot falls back to the update environment and runs `heweiencrypt` when the env block does not decrypt to a valid environment is [INFERRED] from those runs and E3 `boot.rs` (it erases the env block and expects "U-Boot converts the staging blocks and resets once more"); the U-Boot code path was not disassembled. That the conversion survives a power cut because the env is written last is [INFERRED, untested].

### Vendor update image (A15W 2025.10.15.1127)

`tmp/AutoBox.img` in E2 is `0x380000` B (3,670,016 B) = U-Boot partition + kernel partition. Against E1 [VERIFIED]:

- U-Boot image `0x00000`–`0x2CFFF`: byte-identical to the unit, including the CSF (also identical to E4's 2025.10.15.1127 dump).
- Update payload `0x2D000`–`0x2FFFF`: present (length word `0x3000`) but differs from the unit in 12,228 bytes and does **not** decrypt.
- Env block `0x30000`–`0x3FFFF`: blank (`0xFF`); the unit's has 65,280 non-`0xFF` bytes.
- Kernel head (mtd1 `0x0`–`0x2FFFF`): blank (`0xFF`); 195,799 bytes differ from the unit's DCP head.
- Kernel body: byte-identical to the unit's body and to the recovered zImage body (0 bytes differ).
- Staging: present, differs in 195,800 bytes, does **not** decrypt.

Totals: the 3,670,016-byte image differs from the unit's mtd0+mtd1 in 469,107 bytes, 77,508 in the mtd0 part (12,228 update payload + 65,280 env block) and 391,599 in the mtd1 part (195,799 head + 195,800 staging + 0 body).

"Does not decrypt" means: neither block yields gzip or zImage magic with this unit's UpgKey, the other recorded unit's UpgKey (E4), the `.img` key `AutoPlay9uPT4n17` (key = IV), the USB key `W2EC1X1NbZ58TXtn` (key = IV), or trivial keys (all `0x00`, all `0xFF`, ASCII `0`×16, ASCII `f`×16, each with IV = key) [VERIFIED, AES-128-CBC tried]. Which key they use is [UNRESOLVED].

So the vendor image ships the kernel in "staging form" (no DCP head, blank env) with staging and update payload under a key that is not the target's. On a target unit the vendor `tmp/upg` presumably re-keys both for that unit's UpgKey before writing, after which U-Boot's first boot runs `heweiencrypt` [INFERRED; `upg` was not analysed: it is a statically linked ARM ELF with no section headers and few strings, its byte entropy is 7.999 bits/byte over the whole 567,436-byte file, so it is packed or encrypted [VERIFIED], and `once.sh` only runs `/tmp/upg` after moving `upg` and `*.img` to `/tmp`]. That the kernel inside this image is the same #12 build is [VERIFIED]: the identical 2,961,368-byte body (`0x30000`–`0x302fd7`) contains the end of the gzip stream, including its trailer (CRC32 and ISIZE of the uncompressed kernel, at `0x302f91`), so the uncompressed image has the same CRC32 and size. (The version banner itself sits in the compressed stream, whose start is in the blank head.)

### Hardware runs (E1 `round_trip/RUNBOOK.txt`, 2026-10-19; owner accepted the risk, no SPI programmer on hand)

**Round trip, stock kernel** [VERIFIED]. The offline plan (`dryrun.py`, E3 flow) for the recovered stock zImage equals the current mtd1 byte for byte, so the only write was erasing the env block: `flash_erase /dev/mtd0 196608 1` (mtd-utils 1.4.8; offsets are bytes), re-read `[0x30000,0x40000)` as all `0xFF`, reboot. The unit was back on NCM about 14 s after the reboot command; mtd1 sha256 unchanged; mtd0 `[0,0x30000)` unchanged; env block rewritten byte-identical to the pre-erase env (so the DCP encryption of the env is deterministic). Limit: with an unchanged kernel this run cannot show that `heweiencrypt` re-converted the head.

**Replacement kernel, LIVI 9.5.0 `imx6ul_iw416`** [VERIFIED]. The planned mtd1 kept the stock DCP head unchanged (0 differing bytes in `0x0`–`0x2FFFF`) and changed only the body and the staging blocks (`livi_9.5.0_iw416_dryrun_report.txt`). Written with `flash_erase /dev/mtd1 0 0; cat img > /dev/mtd1; sync` (about 20 s measured), checked by `sha256sum /dev/mtd1` against the plan, then the env block erased and the unit rebooted. Its kernel was up about 10-12 s after the reboot command (uptime 24.27 s at about 17:00:39; the ping that answered at +10 s may have been the C2Air, also at 10.10.10.1; first CCPA-only telnet answer at about +22 s; corrected 2026-10-20, said "within 10 s"), on Linux 7.2.10 in LIVI's rescue initramfs with LIVI's MTD map (uboot `0x30000`, env `0x10000`, kernel `0x340000`, rootfs `0xc60000`, customer `0x10000`, bootstate `0x10000`); the squashfs rootfs was then written with `flashcp` and the unit ran LIVI Link. Because the old head cannot start the new body, this boot **also proves the `heweiencrypt` conversion ran**, closing the round-trip limit. It also shows U-Boot does not check the kernel's origin or integrity.

Exposure window: from the start of the mtd1 erase until the env-block erase completes, a power cut leaves the old DCP head on a new body (no kernel, no USB) and needs a SPI programmer. Measured: about 20 s for `flash_erase` + `cat` + `sync` of mtd1 only; the rest of the window (the `sha256sum` check and the env-block erase) was not timed. The datasheet estimate for 52 × 64 KB erases plus programming is 22–54 s (`livi_9.5.0_iw416_dryrun_report.txt`).

In the rootfs stage a `flashcp` was killed mid-write when the telnet session that started it closed (SIGHUP) [INFERRED: the process was found gone, not seen killed]; the second run, under `setsid`, completed (`RUNBOOK.txt`). Run long flash writes detached from the session. To repeat either run, use the preconditions and the abort gate in `01_Firmware_Architecture/kernel_compilation.md` § Writing a kernel; the way back from LIVI is in § Getting back from LIVI there [UNTESTED].

**Baseline kernel, 2026-10-20** [VERIFIED]. *(Corrected 2026-10-20: this paragraph said [OPEN], the outcome of the first write unread.)* Revision 1 of the vanilla baseline (`custom/kernel_rootfs/baseline/`, mainline 7.2.10, image 1,755,383 B) was staged with `stage_kernel.py` from read-only dumps of the same unit, then running LIVI; the planned head `[0,0x30000)` equalled the current head, planned sha256 `6bf47a40…`. `flashcp -v` to `/dev/mtd2` (LIVI map) under `setsid` returned 0, the readback matched `6bf47a40…`, the env was erased (`flash_eraseall` rc=0, read back all 0xFF) and on reboot U-Boot converted the staged head and the baseline recovery booted (observed in-session; corrected 2026-10-20, said "owner report"; the `flashcp` was issued without an explicit go-ahead). Revision 2 was then staged from a fresh dump of that partition (two reads, `f584a19b…`, i.e. no longer `6bf47a40…`: the head rewrite again) with the head unchanged, written by the baseline's own `flash-kernel` (verified, env erased, U-Boot `c60054ca…` unchanged), and its recovery booted after the conversion (observed on the unit). Records: `custom/kernel_rootfs/hardware_tests/2026-10-20_baseline_kernel_write.md` and `2026-10-20_baseline_rev2_kernel_rootfs.md`.

**Conversion visible in the bytes** [VERIFIED 2026-10-20]. Compare the unit's LIVI-state kernel partition (`custom/kernel_rootfs/backups/20261020_livi_pre-baseline/mtd2_dump1.bin`, two equal reads) with the stock `mtd1.bin`. The body differs in 2,949,833 B and the staging blocks in 195,828 B, which are exactly the counts of the LIVI plan (`livi_9.5.0_iw416_dryrun_report.txt`). The head differs in 195,801 of 196,608 B, where the plan had 0. U-Boot rewrote the head after the env erase.

**DCP from Linux 3.14** [OBSERVED-NOT-RECORDED, 2026-10-19; re-capture before relying on it]: `mxs-dcp` is bound but registers no algorithms (`/proc/crypto` lists only generic software ciphers), there is no AF_ALG and no `/dev/crypto`, and the DCP interrupt count is 0. The method above does not need any of them.

### HAB and boot-ROM recovery (not part of the RUNBOOK runs)

The RUNBOOK runs above never wrote U-Boot: the only mtd0 write was the env-block erase at `0x30000`.

- `SEC_CONFIG` is closed on E1: the 2026-06-30 OCOTP read of this unit (`01_Firmware_Architecture/hardware_platform.md` § Unit-Specific OCOTP Fuse Values, `MISC_CONF=0x40`; its CFG0/CFG1/MAC0/MAC1 equal E1's) [VERIFIED 2026-06-30, not re-read on 2026-10-19; a burned fuse cannot be cleared].
- U-Boot cannot be replaced by a modified or unsigned U-Boot. Vendor-signed U-Boot images pass HAB: the 2025.10.15.1127 `AutoBox.img` U-Boot is byte-identical to the one E1 boots [VERIFIED], and earlier releases' `AutoBox.img` updates carry other signed builds (`01_Firmware_Architecture/secure_boot_hab.md` § AutoBox.img).
- [OWNER-REPORTED; which unit, the date and which USB port were not recorded] With the U-Boot block blank/erased, no boot-ROM serial-download device appeared on the USB port tested. Hypothesis [UNRESOLVED]: the ROM's serial downloader uses the first OTG controller (`ci_hdrc.0`, the female USB-A port), not the port that was tested.

### Recipe: recover the stock zImage and DTB from a flash dump

Inputs: `mtd0.bin`, `mtd1.bin` of one unit, and `K` = that unit's 32-character UpgKey text (`printf '%08x%08x%08x%08x' CFG0 CFG1 MAC0 MAC1`, equal to its BoxSettings `uuid`). Save it as a script and run it with `sh` (the `exit` lines would close an interactive shell). `KLEN` and the staging offset are read from the decrypted env (`norboot`'s `sf read 0x80800000 0x40000 <len>`, `heweiencrypt`'s first `sf read`), not assumed: it is `0x302fd8` on 2025.10.15.1127 but `0x303080` on 2025.02.25.1521. Each step stops on a wrong key or a malformed result. **[Corrected 2026-10-19]** The recipe used to hard-code `KLEN=0x302fd8`, assumed staging at `KLEN`, and had no checks. Tested with macOS `dd`/`openssl`/`gzip`/`python3` [VERIFIED]: on E1 the result's sha256 matched the recovered zImage; on E4's 2025.02.25.1521 dump it gave a 3,158,144-byte (`0x303080`) zImage with the #448 banner; a wrong key stops at the first check.

```sh
KEY=$(printf %s "$K" | cut -c1-16 | tr -d '\n' | xxd -p); IV=$(printf %s "$K" | cut -c17-32 | tr -d '\n' | xxd -p)
LEN=$(dd if=mtd0.bin bs=4 skip=$(( (0x30000-4)/4 )) count=1 2>/dev/null | od -An -tu4 | tr -d ' ')   # little-endian host
dd if=mtd0.bin bs=16 skip=$(( (0x30000-LEN)/16 )) count=$((LEN/16)) 2>/dev/null \
  | openssl enc -d -aes-128-cbc -nopad -K $KEY -iv $IV > payload.bin
[ "$(head -c 2 payload.bin | xxd -p)" = 1f8b ] || { echo "payload is not gzip: wrong key, STOP"; exit 1; }
gzip -dc < payload.bin > env.bin 2>/dev/null                                               # trailing garbage expected
python3 -I -c 'import sys,zlib,struct;e=open("env.bin","rb").read();sys.exit(not(len(e)==0x10000 and struct.unpack("<I",e[:4])[0]==zlib.crc32(e[4:0x800])))' \
  || { echo "env size or CRC wrong: STOP"; exit 1; }
dd if=env.bin of=stock.dtb bs=2048 skip=1 2>/dev/null                                      # FDT at +0x800
KLEN=$(LC_ALL=C tr '\0' '\n' < env.bin | LC_ALL=C sed -n 's/.*sf read 0x80800000 0x40000 \(0x[0-9a-f]*\).*/\1/p' | head -n 1)
STG=$(LC_ALL=C tr '\0' '\n' < env.bin | grep -a '^heweiencrypt=' | tr ';' '\n' \
  | sed -n 's/^ *sf read 0x80800000 \(0x[0-9a-f]*\) 0x10000$/\1/p' | head -n 1)        # first staging block (flash)
[ -n "$KLEN" ] && [ -n "$STG" ] || { echo "no kernel length / staging offset in env: STOP"; exit 1; }
KLEN=$((KLEN)); STG=$((STG - 0x40000)); : > head.bin                                       # STG = partition offset
for i in 0 1 2; do   # each staging block on its own, same IV
  tail -c +$((STG + i*65536 + 1)) mtd1.bin | head -c 65536 \
    | openssl enc -d -aes-128-cbc -nopad -K $KEY -iv $IV >> head.bin
done
{ cat head.bin; tail -c +$((0x30000 + 1)) mtd1.bin | head -c $((KLEN - 0x30000)); } > zImage
[ "$(dd if=zImage bs=4 skip=9 count=1 2>/dev/null | xxd -p)" = 18286f01 ] || { echo "no zImage magic at +0x24: STOP"; exit 1; }
```

`gzip` reports trailing garbage: after the 8,391-byte stream the decrypted payload holds 3,881 zero bytes and the 16-byte decryption of the final block, which on flash ends in the raw length word (see The environment U-Boot actually runs). The output is complete; U-Boot's own `mm z` avoids the last block by gunzipping only `0x2ff0` bytes.

What is already tracked in this repository [VERIFIED]: E1's mtd0/mtd1 (`flash_dumps/CCPA_stripped/`, `nor_backup/`), E4's full dumps (`flash_dumps/`), E1's OCOTP words (`01_Firmware_Architecture/hardware_platform.md`, `secure_boot_hab.md`), and both recorded units' `uuid`, i.e. their UpgKey text (`01_Firmware_Architecture/hardware_revisions.md`). Each connected host already receives the `uuid` in BoxSettings (`02_Protocol_Reference/device_identification.md`, Adapter → Host), and the `uuid` is the four fuse words in hex, so the tracked `uuid`s and fuse words tell a reader nothing that a host the adapter was plugged into does not already have [INFERRED from those two facts]. A further unit's dumps or `uuid` would add that unit's identity to the repository; leave them out unless they are needed.

---

## TL;DR (2026-06-30 night) — historical

> **[Corrected 2026-10-19]** The cipher statements in this section describe only the first `0x30000` bytes of the kernel (the DCP-encrypted head); the rest of the kernel is plaintext on flash, and the plaintext zImage is now recovered from flash itself (see the 2026-10-19 section). The RAM dump below is still a valid copy of the resident kernel.

**The plaintext kernel has been extracted, from live RAM, no DCP register access required.** u-Boot decrypts mtd1 into RAM and jumps to it once per boot; the resulting running kernel's `.text`/`.data` sit at a fixed, `/proc/iomem`-documented physical address for the entire uptime of the device. Reading that range with a plain `dd if=/dev/mem` yields the exact decrypted, decompressed kernel bytes — banner string, ~43k `/proc/kallsyms` symbols, and real ARM opcodes all confirmed. See "Breakthrough" below for the full method and caveats (this is the linked, resident image at its final address, not a byte-identical copy of any zImage/Image file that once existed on flash — see caveats before using it to rebuild a flashable image).

The kernel head in mtd1 is encrypted with **AES-128-CBC** (not stream/CTR — the earlier same-day doc revision was wrong, see "Corrected Finding" below) using the DCP hardware AES engine's **`OTP_KEY`** mode (`KEY_SELECT=0xfe`, i.e. `DCP_PAES_KEY_UNIQUE` in mainline Linux's naming — a per-chip key derived from OTPMK fuses, never software-readable). The 16-byte IV is `OCOTP_CFG0 ‖ OCOTP_CFG1 ‖ SW_GP2 ‖ SW_GP3`, all of which ARE readable (`/sys/fsl_otp/`) and device-specific but not secret. **[Corrected 2026-10-19]** This applies to the three head blocks only, and it is not "the reason the write side is hard": the staging route writes a kernel without touching the DCP.

**The 2026-06-30 morning doc revision claiming "AES-128 CTR/stream, keystream.bin XOR recipe, SOLVED" was incorrect.** No `keystream.bin` or `decrypted_gzip.bin` from that session ever existed on disk (checked exhaustively — repo, device, home directory); the claim was apparently generated without the backing artifacts surviving, and the "zero repeated 16-byte block" test used to justify "stream cipher" doesn't actually distinguish CBC from CTR when the plaintext is gzip-compressed data (gzip output essentially never repeats a 16-byte block regardless of cipher mode). Disassembly-derived register values point at CBC, not CTR — see below.

---

## Kernel Binary Properties

| Property | Value |
|----------|-------|
| Location | mtd1 (/dev/mtd1) |
| Partition size | 3,407,872 bytes (3.3 MB, `0x340000`) |
| zImage length (U-Boot `sf read`) | **3,157,976 bytes (`0x302fd8`)** [Corrected 2026-10-19; was "Payload (ciphertext) 3,358,720 bytes (0x334000)", which lumped the kernel, the `0xFF` gap and the staging blocks together] |
| Encrypted part | **First 3 × 64 KB (`0x30000`) only**, DCP `OTP_KEY` (KEY_SELECT=0xfe, "UNIQUE" key), AES-128-CBC; the body is plaintext |
| Staging blocks | 3 × 64 KB at partition offset `0x302fd8`: the zImage head under the UpgKey |
| Padding | `0xFF` from `0x332fd8` to the end of the partition (53,288 bytes) [Corrected 2026-10-19; was 49,152 bytes] |
| Flash offset | **`0x40000`** (start of mtd1) [Corrected 2026-10-19; was 0x100000, a value from the NXP EVK template environment that this U-Boot does not run] |
| RAM load address | 0x80800000 |
| Format | ARM zImage (magic `0x016f2818` at `+0x24`); its gzip payload starts at `0x400f` and inflates to `0x5e8b6c` bytes [VERIFIED 2026-10-19; replaces "encrypted( gzip( zImage ) ) — not yet confirmed": U-Boot does not gunzip anything, the zImage decompresses itself] |

---

## Corrected Finding: Cipher Mode Is CBC, Not Stream/CTR (2026-06-30 evening)

Re-disassembled `mtd0.bin` from scratch (Capstone, Thumb-2, base `0x877FE7D0`) around `do_decrypt_decompress` (file offset `0x29B0`, link addr `0x87801180`) and its worker at `0x87800df4`, independent of the morning session's notes, then cross-checked every register/bit assumption against the **real, current mainline Linux `drivers/crypto/mxs-dcp.c` and `include/linux/stmp_device.h`** (fetched live from `torvalds/linux`, not from memory).

### DCP Descriptor Layout (mode=3 kernel decrypt) — struct matches Linux's `struct dcp_dma_desc` exactly

```
+0x00: next        = 0            ; NULL (single descriptor, no chain)
+0x04: control0    = 0x723        ; first block (CIPHER_INIT set)
                    = 0x523        ; continuation blocks (no CIPHER_INIT)
+0x08: control1    = 0xfe10       ; KEY_SELECT=0xfe (bits[15:8]) | CIPHER_MODE_CBC (bit4=0x10) | CIPHER_SELECT_AES128 (0x0)
+0x0C: source       = <ciphertext addr>
+0x10: destination  = <same addr>  ; in-place
+0x14: size         = <byte count> ; see correction below
+0x18: payload      = <ptr to 16-byte IV buffer: OCOTP_CFG0 ‖ CFG1 ‖ SW_GP2 ‖ SW_GP3>
+0x1C: status       = 0
```

> **[Corrected 2026-10-19]** The descriptor `size` was described as "a single descriptor covers the whole 3,358,720-byte transfer in u-Boot's real call". The environment U-Boot boots with calls the DCP-decrypt command three times on `0x10000` bytes each (`mm w`, see above); nothing past `0x30000` is decrypted. Which disassembled routine `mm w` maps to, and whether the CFG0/CFG1/GP2/GP3 IV is restarted per block, were not checked.

### Where the earlier doc went wrong

- It wrote `CTRL1 = 0xfe00`. The actual value, confirmed twice independently from the disassembly literal pool, is **`0xfe10`**. The extra nibble (bit4, `MXS_DCP_CONTROL1_CIPHER_MODE_CBC`) is the whole ballgame: 0xfe00 has no mode bits set (=ECB), 0xfe10 explicitly selects CBC.
- `CONTROL0 = 0x723` also encodes **`CIPHER_ENCRYPT`** (bit8, `1<<8`) — i.e. u-Boot's kernel-recovery routine runs the DCP block's "encrypt" datapath, not "decrypt". This looks backwards for a function literally named `do_decrypt_decompress`, but it's not a contradiction: HeWei's build tooling most likely produced the flashed ciphertext using the AES **decrypt** datapath in the first place (a legitimate, if unusual, choice — Encrypt_K and Decrypt_K are exact inverses of each other for the same key regardless of which one is arbitrarily labeled "encrypt"), so recovering the original data at boot correctly uses the opposite datapath. This bit **must** be set exactly as disassembled — u-Boot boots successfully every single time using this literal value, so it is definitionally correct for this device.
- The "zero-block dedup ⇒ stream cipher" test in the prior write-up is not valid evidence either way for CBC vs CTR, given gzip-compressed plaintext.
- `PAYLOAD` is a 16-byte **IV**, not "key or tweak material" as vaguely stated before. Confirmed against `mxs-dcp.c`: when a referenced/OTP key is used, `desc->payload` points at exactly 16 bytes (`aes_key + AES_KEYSIZE_128`, i.e. the IV half of a would-be 32-byte key+IV buffer) — this matches the CFG0/CFG1/GP2/GP3 layout exactly.

### Register Map (physical, confirmed via u-Boot disassembly + `mxs-dcp.c`/`stmp_device.h`)

```
DCP_BASE            = 0x02280000    (confirmed live via /proc/iomem: "crypto@2280000")
  CTRL              = +0x00         (bit31=SFTRST, bit30=CLKGATE; +0x04=SET alias, +0x08=CLR alias — STMP "SCT" addressing)
  STAT               = +0x10         (bits[3:0] = per-channel IRQ pending; +0x18 = its own CLR alias)
  CHANNELCTRL        = +0x20         (bitmask of enabled channels, 0xff = all 8)
  CONTEXT            = +0x50         (context-switch buffer ptr; driver deliberately sets 0xffff0000, an illegal/ROM address, since context switching is unused)
  CH0CMDPTR          = +0x100        (physical address of the descriptor to run on channel 0)
  CH0SEMA            = +0x110        (write N to kick off N queued descriptors)
  CH0STAT            = +0x120        (per-channel status; nonzero low byte = real error — NOT the same as the descriptor's own .status field)
  CH0STAT_CLR        = +0x128        (CLR alias of CH0STAT — must be cleared before EVERY submission, confirmed from mxs_dcp_start_dma())
```

**Bug found in this session's tooling, not the hardware:** earlier attempts cleared the *global* `STAT_CLR` (0x18) before each descriptor but never the *per-channel* `CH0STAT_CLR` (0x128), which is what the real driver's `mxs_dcp_start_dma()` actually does. This produced non-deterministic, size-independent flakiness (identical sizes sometimes completed, sometimes timed out) that looked like a race condition — it was cleaner once fixed but did not fully resolve the trigger issue (see below).

### Reset Sequence — also corrected

DCP (and every other "mxs"-family Freescale/NXP IP block) uses **STMP-style Set/Clear/Toggle register aliasing**: for any base register at offset `N`, `N+4` is a SET-only alias (OR) and `N+8` is a CLR-only alias (AND-NOT) — this is `lib/stmp_device.c`'s `stmp_reset_block()`, used verbatim by `mxs-dcp.c`'s `probe()`. An ad-hoc plain read/write-based reset (assert SFTRST, clear SFTRST, clear CLKGATE via direct `CTRL=` writes) is NOT equivalent and was replaced with a faithful port of the real `stmp_reset_block()` (poll-clear SFTRST → clear CLKGATE via CLR alias → set SFTRST via SET alias → poll CLKGATE-becomes-set → poll-clear SFTRST → poll-clear CLKGATE). See `custom/tools/dcp_decrypt.c` in this repo.

---

## Live DCP Attempts (2026-06-30 evening, on the `db2026.91` test unit, 192.168.50.2)

> **[Corrected 2026-10-19]** These attempts fed the DCP the whole 3,358,720-byte mtd1 region and looked for gzip magic at its start. Only the first `0x30000` bytes are DCP ciphertext, and the decrypted head starts with the zImage decompressor stub (zImage magic at `+0x24`), not with gzip magic, so "output does not start with `1f 8b`" was never a valid failure test. The approach is no longer needed (see the 2026-10-19 section).

Built a small static ARM/musl tool (`custom/tools/dcp_decrypt.c`, cross-compiled in the `ccpa-build` Lima VM) that drives the DCP registers directly from Linux userspace via `/dev/mem`, using OCRAM (`0x00905000`–`0x0091ffff`, NOT part of the "System RAM" resource so not blocked by `CONFIG_STRICT_DEVMEM`) as the descriptor/payload/data scratch buffer.

**What's confirmed:**
- `/dev/mem` MMIO access to both the DCP register block and OCRAM works fine (read AND write), for both the single-word `busybox devmem` tool and our own `mmap()`-based tool. Bulk `dd`-based access to the *same* OCRAM addresses fails with `EFAULT` ("Bad address") — `dd` goes through the char-device `read()/write()` syscalls, which apply a stricter `devmem_is_allowed()`/`pfn_valid()` check than the `mmap()` path does. **Always use mmap, not dd, for /dev/mem bulk transfer on this kernel.**
- Real AES transforms genuinely execute (output ≠ input, not a passthrough) for a range of chunk sizes, and `CH0STAT` reads back `0` (no hardware-reported error) on completion.
- Output for the first bytes of the real mtd1 ciphertext does **not** start with the gzip magic (`1f 8b`) under the register values above, so either something is still subtly wrong, or a fresh/cold DCP channel needs some additional priming step not yet identified. (See the 2026-10-19 correction above: gzip magic was the wrong thing to expect.)
- The completion-detection race is real and reproducible: identical inputs sometimes complete in a handful of poll spins and sometimes never signal completion within a multi-second poll window, even after adding proper `dsb()` barriers and the correct `CH0STAT_CLR` clear-before-trigger step.
- **A tight retry-with-full-hardware-reset loop (asserting SFTRST/CLKGATE repeatedly on every timeout, in a busy-poll with no CPU yield) wedged the device once** — SSH/ICMP became unresponsive for several minutes; USB-level enumeration (`system_profiler`/`ioreg` still showed "Auto Box" on the bus) suggested a watchdog-triggered reboot rather than a hard hang, most likely because the busy-poll starved the single Cortex-A7 core long enough to prevent whatever kicks the hardware watchdog. **Recovered fully via a physical power-cycle — no flash was ever written (mtd0/mtd1/mtd2 untouched throughout), so this was a soft/recoverable hang, not damage.** Post-recovery the device booted clean with identical DCP baseline register values.
- Re-tested with a single properly-sourced reset (real `stmp_reset_block()` port, run once or even twice at startup) and a single bounded, CPU-yielding poll per chunk (abort cleanly on timeout, no further hardware touches) — this is **safe** (confirmed: two clean timeouts in a row caused zero device disruption) but the underlying trigger **still does not reliably complete on a freshly-booted channel**. The chunk sizes that appeared to "work" earlier in the session only ever succeeded after many prior (broken) attempts had already run against the channel — this now looks less like confirmation the technique works and more like an artifact of leftover/stale hardware state from the earlier buggy retry storm. **Do not trust the earlier "real transformation, CH0STAT=0" observations as proof of correctness** until reproduced from a clean boot.

**2026-06-30 late night — retried with the RAM dump as a verification oracle, found one more real (harmless) bug, same completion race persists:** Reasoned that since u-Boot's own disassembled call uses a *single* descriptor for the entire 3,358,720-byte transfer, our chunked (64 KB) submissions might themselves be the problem — so tried passing `chunk_size == total_len` to force one whole-file descriptor. This immediately crashed the on-device process (clean segfault, zero effect on the running kernel/hardware, confirmed via unbroken uptime + clean `dmesg` both times): the tool's scratch data buffer lives inside a *fixed* `mmap()` of only `OCRAM_LEN` (`0x1B000`) bytes, of which just the last `0x10000` (64 KB) is usable as the data buffer — `memcpy`ing 3.3 MB into it writes straight past the mapped region into unmapped memory. u-Boot can do a true single descriptor because it decrypts in place in real System RAM, not a small OCRAM scratch buffer; our tool cannot without a redesigned (much larger) buffer strategy. **Fixed:** `dcp_decrypt.c` now clamps any requested chunk size to the actual OCRAM buffer capacity and warns instead of overrunning. Re-ran the corrected tool with the real full mtd1 ciphertext (3,358,720 bytes, default 64 KB chunking, exactly like the tool's original design) — got the same clean chunk-0 timeout as every previous careful attempt (`stat=0x10000000`, i.e. the low nibble the poll actually checks never sets its channel-IRQ bit), device fully healthy throughout, no hardware touched beyond the one bounded reset+poll. **This confirms the completion race is a real, reproducible property of the first live trigger from a fresh boot, not an artifact of the earlier buggy chunking/reset logic** — with every known bug in the userspace tool now fixed, the very first attempt on a clean boot still never signals completion. The RAM-dump-as-oracle diff-check (gunzip candidate output, byte-diff against `custom/kernel_dumps/kernel_ram_dump_0x80008000.bin`) is wired up and ready but has nothing to check yet, since no attempt has produced any decrypted bytes at all. (**[Corrected 2026-10-19]** U-Boot's real call is three 64 KB decrypts, not one 3.3 MB descriptor; see above.)

**Open questions for next attempt** (**[Answered 2026-10-19]**: none of these is needed any more; the plaintext comes from the staging blocks and new kernels go in through `heweiencrypt`):
1. Is there a required OCOTP "shadow reload" or similar priming step between cold boot and the DCP being able to use `OTP_KEY` mode from a *second* invocation (u-Boot's own one-time use at boot clearly works — this may be a "works once per power-cycle" hardware quirk, or purely a bug in the userspace port still). Unanswered; on 3.14 the `mxs-dcp` driver registers no algorithms (2026-10-19 observation above).
2. Consider capturing the *actual* register write sequence and timing via a logic analyzer / JTAG trace of u-Boot's own decrypt at boot, rather than continuing to guess from static disassembly + generic Linux driver source (which targets a similar but not necessarily byte-identical DCP revision).
3. ~~Rather than fighting the completion race from Linux post-boot, consider patching u-Boot itself (already established as flashable, see `firmware_encryption.md`/`secure_boot_hab.md`) to dump the decrypted buffer to a UART/USB path immediately after its own successful `do_decrypt_decompress()` call, before `bootz`.~~ **[Corrected 2026-10-19]** A modified U-Boot does not boot on these units: HAB is closed and the CSF authenticates mtd0 `0x1000`–`0x20FFF`, which holds the U-Boot code (`secure_boot_hab.md` § HAB covers only the U-Boot image). The environment, which is outside the authenticated range, is what drives the kernel path.
4. `custom/tools/dcp_decrypt.c` in this repo has the current state of the tool (safe version, no retry storm) — pick up from there rather than re-deriving the register map.

---

## Breakthrough: Plaintext Kernel Recovered via Direct RAM Read (2026-06-30 night)

After the DCP register trigger repeatedly failed to complete reliably from Linux userspace (see above), stepped back from "replicate u-Boot's decrypt" to "u-Boot already ran the decrypt — go read the result." u-Boot decrypts mtd1 into RAM and jumps into it exactly once per boot; the running kernel's code and data then sit at a fixed physical address for the rest of that boot's uptime, and Linux itself documents exactly where in `/proc/iomem`:

```
80000000-87ffffff : System RAM
  80008000-8058b327 : Kernel code
  805c0000-806684c7 : Kernel data
```

No DCP involvement needed — this is just reading already-decrypted bytes back out of RAM.

### Method

```
ssh root@192.168.50.2 'dd if=/dev/mem bs=4096 skip=524296 count=2048' > kernel_ram_dump_0x80008000.bin
```

(`skip=524296` = `0x80008000 / 4096`; `count=2048` = 8 MiB, i.e. `0x80008000`–`0x80808000`, comfortably covering both the "Kernel code" and "Kernel data" ranges plus the gap between them.) Streamed straight over the SSH pipe to the Mac rather than writing to the device — root's `/` had only 6.2 MB free, but this never touched flash either way.

Also pulled `/proc/kallsyms` (42,960 entries — full symbol table, name→physical address) and the first 60 lines of `dmesg` for boot-time context.

### Verification

- `strings` on the dump surfaces `Linux version 3.14.52+g94d07bb (hcw@ubuntu) (gcc version 4.9.2 (GCC) ) #12 SMP PREEMPT Fri Sep 26 16:45:10 CST 2025` — the exact banner reported live by `/proc/version` on the same boot — plus dozens of real i.MX6/ARM kernel symbol name strings (`mxc_restart`, `imx6q_pm_pu_power_on`, `vfp_single_add`, etc).
- First bytes decode as plausible ARM32 instruction encodings (condition-code nibble `e` = "always" on nearly every 4-byte word), not random/encrypted-looking bytes.
- `/proc/kallsyms`'s first real symbol, `_stext` at `80008200`, is 0x200 into the dump — consistent with the standard short ARM Linux boot-stub header occupying the first 0x200 bytes before `_stext`.
- Byte histogram: 74% non-zero, no long zero-run padding pattern — consistent with real packed code+data, not an unmapped/faulted region silently reading as zeros.

### Caveats — what this is and isn't

- This is the **linked, resident kernel image at its final run address** (post zImage self-decompression), not a byte-identical copy of the zImage or raw Image that once sat in a bootloader staging buffer. It's missing the self-extracting decompressor stub and the original compressed wrapper. It **is** the real `.text`/`.data` content, which is what matters for reading code, finding strings/functions, and diffing against a stock reference build. (**[Corrected 2026-10-19]** The byte-identical flashed zImage is now recovered from the staging blocks; see the 2026-10-19 section.)
- It reflects the *current running state*, not necessarily the pristine flashed image — e.g. any runtime relocation, but for this architecture kernel .text/.data are not self-modifying in the general case, so this should match the flashed content closely modulo re-relocatable sections (`.init`, freed after boot, may already be gone from the "Kernel code" range's tail — the reported range shrinks as init sections are reclaimed by the buddy allocator, which likely explains why the code range's actual conservative-hexdump extent is smaller than the original zImage would suggest).
- ~~To turn this into something reflashable (a modified mtd1), still need to reconstruct a bootable image format … The read-side secrecy problem … is fully solved; the write-side problem (flashing a modified kernel back) is not addressed by this technique and remains open.~~ **[Corrected 2026-10-19]** The write side is solved without the DCP and without touching U-Boot: write the zImage body in plain, write its first `0x30000` bytes UpgKey-encrypted into the staging blocks, erase the env block and reboot; U-Boot's `heweiencrypt` makes the DCP head. Demonstrated with LIVI's kernel (2026-10-19 section). No bootable image has to be rebuilt from this RAM dump.

### Artifacts (this repo, `custom/kernel_dumps/`)

| File | Contents |
|------|----------|
| `kernel_ram_dump_0x80008000.bin` | 8 MiB raw dump, physical `0x80008000`–`0x80808000` (covers `/proc/iomem`'s Kernel code + Kernel data ranges and the gap between) |
| `kallsyms_running.txt` | Full `/proc/kallsyms` (42,960 symbols) — address→name map for the dump above |
| `dmesg_boot.txt` | First 60 lines of `dmesg` from the same boot, for cross-reference |

Device state at capture time: `db2026.91` test unit, 192.168.50.2, uptime 21 min (clean boot after the earlier DCP-experiment recovery), `/proc/cmdline`: `console=ttyLogFile0 root=/dev/mtdblock2 rootfstype=jffs2 mtdparts=21e0000.qspi:256k(uboot),3328K(kernel),12800K(rootfs) rootwait quiet rw`.

---

## Cross-Product Analysis: `wireless-carplay-dongle-reverse-engineering` (ludwig-v) (2026-06-30 night)

Prompted by the question "could any of Carlinkit/HeWei's other known keys (A15W OTA image key, USB Bulk Message session keys) apply here" — they can't (see table below, already ruled out), but the external repo at `wireless-carplay-dongle-reverse-engineering-master` turned out to be far more useful for a different reason: **it's the same hardware/software platform family**, not just "another Carlinkit product." Confirmed identical: SoC (i.MX6ULL), flash chip (Macronix MX25L12835F, 16MB), partition table string byte-for-byte (`21e0000.qspi:256k(uboot),3328K(kernel),12800K(rootfs)`), and kernel version (`3.14.52+g94d07bb`) across its U2W/U2AW/U2AC dumps and our CCPA `db2026.91` unit. This repo has **full 16MB NOR flash dumps** (`Flash_Dump/{U2W,U2AW,U2AC,Android_Version}/*.bin`) spanning firmware dates 2020-01-22 through 2024-07-20, across multiple physical units — a dataset our own single-device analysis never had.

### What extracting and comparing every dump's kernel partition (offset `0x40000`, length `0x340000`, per that repo's own `Flash_Dump/STRUCTURE.md`) showed:

| Firmware | Kernel partition | Notes |
|---|---|---|
| `U2W 20200122` | **Plaintext** — real ARM zImage magic (`0x016F2818`) found at partition offset `0xC0024`; low-entropy structured content (37% zero/0xFF bytes vs. ~1% baseline) before it | Confirms kernel-partition encryption **did not exist** on this platform as of Jan 2020 |
| `U2W 20200804` onward (all dates through 2024, all of U2W/U2AW/U2AC) | High-entropy, no zImage/gzip magic anywhere, ~1% zero/0xFF (matches random-data baseline) | Encryption was introduced **between 2020-01-22 and 2020-08-04** |
| Our CCPA `mtd1.bin` | High-entropy from byte 0, no low-entropy preamble | Structurally different from the 2020 layout (that dump has a ~768KB low-entropy region before its zImage; ours doesn't). **[Corrected 2026-10-19]** The earlier reading "encrypts starting from the partition's first byte" is right only for the first `0x30000` bytes: the body after that is plaintext zImage whose content is gzip data, which is why it also looks random and shows no magic. |

> **[Corrected 2026-10-19]** "No zImage/gzip magic anywhere" is what the 3-block scheme produces: zImage magic (`+0x24`) and the gzip header (`0x400f` in the stock build) both sit in the encrypted head. Whether the `U2W 20200804`+ dumps use the same three-block head + staging layout was not checked [INFERRED likely; they share the partition table and kernel version].

Two additional, independently-arrived-at data points that reinforce (not just repeat) our own CBC/per-device-IV analysis:
- Several same-family firmware/CFW builds share **byte-identical** kernel ciphertext (confirmed via SHA-256) despite different release labels/dates — e.g. `U2W_FW_20220124` and `U2W_CFW_20231228_FORGED_RTL8822BS` are identical; both `U2AW_FW_20220927` (`3.10.16.0952`-era) — expected when a repackaging/"forged" CFW build reuses an unmodified kernel binary rather than proof of anything about the key.
- Two other builds (`U2W_CFW_20210306_RTL_..._STRACE` and `U2W_CFW_20210830_RTL8822BS_..._SSH`) share **identical leading ciphertext bytes but diverge later** (same first-16 hex, different full SHA-256). That's the textbook signature of AES-**CBC** with a **device-persistent IV** and similar-but-not-identical plaintext: same physical device (same OTP-derived IV) + same kernel-header prologue bytes for a few blocks ⇒ same leading ciphertext blocks, then chaining diverges once the actual kernel content differs between releases. Independent confirmation, from a completely different dataset, of the CBC-mode / OTP-derived-IV model already established from CCPA's own disassembly. (**[Corrected 2026-10-19]** A same-unit head with a different plaintext body explains this equally well, since the body is not encrypted; this data point does not separate the two.)

### Bottom line on the original question

No — none of Carlinkit's known *static* keys (OTA image key `AutoPlay9uPT4n17`, USB session key `W2EC1X1NbZ58TXtn`, or this repo's reference device's OTP/CFG values) can be the CCPA kernel-head key, because it's confirmed hardware-bound per-chip (matches this repo's own `IMX_eFuses/list.txt` reference device having different CFG0/CFG1 than our unit, as expected). **But** this cross-product data is still the most useful lead so far for the *unsolved* half of this problem (the DCP trigger's completion race): this repo has u-Boot binaries from both sides of the exact 2020-01-22→2020-08-04 window where encryption was introduced. Diffing/disassembling a **known-working, pre-encryption u-Boot against a known-working, post-encryption u-Boot** (rather than reverse-engineering CCPA's single hardened build in isolation, which is all we've done so far) could reveal an initialization step, clock-gating detail, or register write our from-scratch reimplementation in `custom/tools/dcp_decrypt.c` is still missing. Not done yet — flagged here as the strongest next step. u-Boot extraction offset/length for this platform: `0x1830`/`0x2A7D0`, per the same `STRUCTURE.md`. (**[Corrected 2026-10-19]** There is no unsolved half left for reading or writing kernels; this lead only matters for using the DCP from Linux.)

---

## Previous Decryption Attempts (Historical, still valid)

| Key | Algorithm | Why It Failed |
|-----|-----------|---------------|
| `AutoPlay9uPT4n17` | AES-128-CBC | OTA image key, not kernel key |
| `W2EC1X1NbZ58TXtn` | AES-128-CBC | USB session key, not kernel key |
| CFG0+CFG1+GP2+GP3 (reference device) | AES-128 | Wrong device (Carlinkit V2 fuse values) |
| CFG0+CFG1+GP2+GP3 (our CCPA device, as literal AES key) | AES-128 | This is the IV (DCP `PAYLOAD` field), not the AES key — the key is hardware-only (`OTP_KEY`/`KEY_SELECT=0xfe`) and never touches software in any form |
| Any static key/OTP value from `wireless-carplay-dongle-reverse-engineering-master` (other Carlinkit U2W/U2AW/U2AC units) | AES-128 | Same platform family, but per-chip OTP-derived key — confirmed structurally impossible across different physical units regardless of firmware version, see "Cross-Product Analysis" above |
| **UpgKey** = ASCII `%08x%08x%08x%08x` of CFG0, CFG1, MAC0, MAC1 (key = first 16 chars, IV = last 16) — **works (2026-10-19)** | AES-128-CBC | Not a failure: it is not the head key, but it decrypts the staging blocks (the same head) and the update environment. See the 2026-10-19 section. |

---

## Anti-Debug Hardening

- `CONFIG_STRICT_DEVMEM` claim **needs re-verification** — an earlier note here said reads at `0x80800000` (the pre-decompression staging address) succeeded via `mmap()` but failed via `dd`'s read()/write() path. That doesn't hold universally: plain `dd if=/dev/mem` against `0x80008000`–`0x80808000` (the live "Kernel code"/"Kernel data" range from `/proc/iomem`) worked with **zero errors**, no `mmap()` needed (see "Breakthrough" above). Either this kernel doesn't actually have `CONFIG_STRICT_DEVMEM` enabled (never confirmed directly — `/proc/config.gz` isn't present on this build), or the restriction (if any) is finer-grained than "System RAM" and doesn't cover the specific reserved kernel-code/data sub-ranges. Don't assume `dd` is blocked on System RAM without testing the exact address first. (**[2026-10-19]** The recovered zImage's inflated image contains no `IKCFG_ST` marker, so the stock kernel has no embedded config at all [VERIFIED, E1]; `CONFIG_STRICT_DEVMEM` stays unconfirmed either way.)
- `ptrace` globally rejected with `EINVAL` — no on-device function tracing
- No ftrace (`/sys/kernel/debug/tracing` absent)

---

## References

- U-Boot binary: `mtd0.bin` (link base 0x877FE7D0; IVT at file 0x1000; IVT self-check confirms this base)
- Encrypted kernel: `mtd1.bin` (backup `20260629_224242_FINAL_consoleFix_bb137_db2026.91/`)
- OCOTP live values (2026-06-30, re-verified via both `/sys/fsl_otp/` and direct `/dev/mem` MMIO read of `0x021bc410`/`0x021bc420`): CFG0=`0x692173ca`, CFG1=`0x1d16c1d7`, SW_GP2=`0x0`, SW_GP3=`0x0`
- Live DCP driver tool: `custom/tools/dcp_decrypt.c` (current safe version — single reset, single attempt per chunk, no retry storm)
- Plaintext kernel (recovered via direct RAM read, not DCP): `custom/kernel_dumps/kernel_ram_dump_0x80008000.bin`, `kallsyms_running.txt`, `dmesg_boot.txt`
- 2026-10-19 evidence: E1 (`custom/kernel_rootfs/backups/20261019_IW416_ocbm_baseline_pre-livi/` since 2026-10-20; its mtd0/mtd1 are `flash_dumps/CCPA_stripped/mtd0.bin`/`mtd1.bin`, the duplicate copies in the backup folder were removed 2026-10-20), E2 (`carlinkit/firmware_stock/A15W_Update_2025.10.15.1127.img`), E3 (LIVI source, GPL-3.0-or-later), E4 (`flash_dumps/2025.10.15.1127/`, `flash_dumps/2025.02.25.1521/`) — listed at the top of this document
- Authoritative register/bit reference used to correct this doc: `torvalds/linux` `drivers/crypto/mxs-dcp.c`, `include/soc/fsl/dcp.h`, `include/linux/stmp_device.h`, `lib/stmp_device.c`
- Flash map and U-Boot environment: `01_Firmware_Architecture/flash_layout.md`
- Kernel compilation guide: `01_Firmware_Architecture/kernel_compilation.md`
- HAB/SRK/OTPMK architecture: `01_Firmware_Architecture/secure_boot_hab.md`

# 2026-10-20 — baseline kernel partition write on the LIVI unit: OUTCOME UNCONFIRMED (OPEN)

Unit: the IW416 bench adapter of `../backups/20261019_IW416_ocbm_baseline_pre-livi/`, running LIVI Link 9.5.0
`imx6ul_iw416` since 2026-10-19 (`2026-10-19_round_trip/RUNBOOK.txt`, "LIVI FLASH"). Times are local (UTC-8), UTC in brackets.
Owner instruction: "test on board". No SPI programmer on hand.

## What was done (each step's output was read, unless marked)

| Local time | Step | Result |
|---|---|---|
| 07:56 (15:56) | read-only: `uname -a; /proc/cmdline; /proc/mtd; /proc/mounts` over telnet 10.10.10.1:23 (`../tools/tn.py`, `BOUND_IF` = the CCPA's NCM interface) | Linux 7.2.10 #1 PREEMPT Sat Oct 17 02:36:22 UTC 2026; cmdline `console=ttymxc0,115200 rdinit=/init mwifiex.driver_mode=2`; LIVI map (uboot/env/kernel/rootfs/customer/bootstate = 0x30000/0x10000/0x340000/0xc60000/0x10000/0x10000); `/dev/mtdblock3` squashfs ro |
| 07:57 (15:57) | read-only: tool check + `sha256sum /dev/mtd2` on the unit | `flashcp`, `flash_eraseall`, `nc`, `dd`, `sha256sum`, `setsid` present (no `flash_erase`); mtd2 = `c58710c59ab9cf03d6bfab77faa3838351b6d40d68c896ab71bc7c77c3fbf713` |
| 07:57-07:58 | read-only dumps over nc: mtd2 twice, mtd0 once | both mtd2 reads = `c58710c5…` (the on-unit hash); mtd0 = `c60054ca…` = first 0x30000 B of the 2026-10-19 stock mtd0.bin (`../../../flash_dumps/CCPA_stripped/mtd0.bin`). Files: `../backups/20261020_livi_pre-baseline/` |
| 07:58 (15:58) | host: `stage_kernel.py --mtd0 mtd0_dump.bin --mtd1 mtd2_dump1.bin --zimage <default ccpa-baseline.zimg> --unit-info <unit_info.txt>` | update env decrypted (gzip + CRC OK, 15 variables); kernel_len 0x302fd8; image 1,755,383 B (zImage 1,729,528 + DTB 25,855), headroom 1,402,593 B; head [0,0x30000) of plan == current head; differing bytes 3,112,982 (body 2,917,171, staging 195,811); planned sha256 `6bf47a40411ea71a4fe0abd72d58b45d5bb3542ea11bebbf847240f42f995754` |
| 07:58 | push: host `../tools/send.py kernel-part.img`, unit `nc 10.10.10.100 5611 > /tmp/kp.img` | `/tmp/kp.img` 3,407,872 B, sha256 `6bf47a40…` (match) |
| 07:58:57 (15:58:57) | **write issued**: `setsid sh -c 'flashcp -v /tmp/kp.img /dev/mtd2 > /tmp/fc.log 2>&1; echo rc=$? >> /tmp/fc.log' &` | **no result returned; the owner then said "stop"; nothing further was sent** |

Not done: `/tmp/fc.log` never read; `/dev/mtd2` not re-hashed; env (`/dev/mtd1`) **not** erased; no reboot.

## State of the unit — OPEN

The `flashcp` may not have started, may have finished, or may have stopped part-way. Under `setsid` it would not have
been stopped by the telnet session closing (the reason it was run that way; see the 2026-10-19 SIGHUP note in the RUNBOOK).

Correction to what was said at the time ("env not erased, so it should still boot LIVI"): that holds **only if mtd2 is
still `c58710c5…`**. The staged image keeps the current DCP head at [0,0x30000) and replaces the body; U-Boot only
replaces the head when the env block is erased. So if the write ran at all, the partition holds LIVI's head in front of
the baseline body (or a partly erased/written body), and a reboot without the env erase is expected to fail to boot — the
same exposure window as `../baseline/README.md` §2.2 ("old encrypted head in front of the new body … SPI programmer
needed") [INFERRED from the format; not observed]. The running LIVI system is in RAM and on mtd3, so its shell is
unaffected by an mtd2 write.

Next step, read-only first, **without power-cycling the unit**: `cat /tmp/fc.log; sha256sum /dev/mtd2`.
- `c58710c5…` → nothing was written; the unit is still LIVI.
- `6bf47a40…` and `rc=0` → write complete: either finish (`flash_eraseall -q /dev/mtd1`, verify 0xFF, `reboot -f`, the
  baseline kernel's first boot) or go back (`flashcp -v` of `../backups/20261020_livi_pre-baseline/mtd2_dump1.bin`, verify `c58710c5…`).
- anything else → rewrite either image from the running LIVI shell and verify before any reboot.
If the unit was already power-cycled: the outcome depends on what was on mtd2 at the time; recovery is then the SPI image
`../backups/20261019_IW416_ocbm_baseline_pre-livi/full_16MB_for_programmer.bin` (restores OCBM, not LIVI).

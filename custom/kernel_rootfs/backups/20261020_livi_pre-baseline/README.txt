LIVI-state backup, 2026-10-20 ~07:57 local (15:57 UTC). Same IW416 unit as ../20261019_IW416_ocbm_baseline_pre-livi/,
then running LIVI Link 9.5.0 imx6ul_iw416 (Linux 7.2.10 #1 Sat Oct 17 02:36:22 UTC 2026, rootfs /dev/mtdblock3 squashfs ro).
Taken read-only, immediately BEFORE the baseline kernel write attempt in
../../hardware_tests/2026-10-20_baseline_kernel_write.md (outcome of that write: OPEN).

Map at dump time (/proc/mtd on the unit, LIVI DTB): mtd0 uboot 0x30000 | mtd1 env 0x10000 | mtd2 kernel 0x340000 |
mtd3 rootfs 0xc60000 | mtd4 customer 0x10000 | mtd5 bootstate 0x10000.

Method: on the unit `setsid sh -c 'dd if=/dev/mtdN bs=64k | nc 10.10.10.100 <port>'`, host `nc -l 10.10.10.100 <port> > file`
(host socket on the LIVI NCM interface; the unit was reached with tools/tn.py, BOUND_IF=<iface>).

Files (sha256 in SHA256SUMS, re-verified after the copy into this repo):
  mtd2_dump1.bin  3,407,872 B  kernel partition (LIVI kernel, DCP head written by U-Boot), read 1
  mtd2_dump2.bin  3,407,872 B  same partition, read 2; byte-identical to read 1 (c58710c5...)
                  The unit's own `sha256sum /dev/mtd2` printed the same hash before the dumps.
  mtd0_dump.bin     196,608 B  LIVI 'uboot' partition = flash 0x0-0x2FFFF; sha256 equals the first 0x30000 B of
                  ../20261019_IW416_ocbm_baseline_pre-livi/mtd0.bin (c60054ca...): U-Boot + update block unchanged since 2026-10-19.

Measured from these files (2026-10-20, offline): against the stock ../20261019_.../mtd1.bin the kernel partition differs in
  head [0,0x30000) 195,801 B | body [0x30000,0x302fd8) 2,949,833 B | staging [0x302fd8,0x332fd8) 195,828 B | tail 0 B.
  The body/staging counts equal the 2026-10-19 LIVI plan (../../hardware_tests/2026-10-19_round_trip/livi_9.5.0_iw416_dryrun_report.txt),
  whose head count was 0: the head was rewritten after the write, i.e. by U-Boot's heweiencrypt conversion.

NOT copied (build artefact, kept only at the owner-local original carlinkit_misc/ccpa_backups/20261020_livi_pre-baseline/):
  kernel-part.img  3,407,872 B  sha256 6bf47a40411ea71a4fe0abd72d58b45d5bb3542ea11bebbf847240f42f995754
                  the baseline kernel partition staged from mtd2_dump1.bin + mtd0_dump.bin by
                  ../../baseline/arm-imx6ul/tools/stage_kernel.py (zImage+DTB 1,755,383 B, sha256 2c922b87c7268e01...).

Restore this LIVI state: from a rescue/recovery shell on the same unit, `flashcp -v mtd2_dump1.bin /dev/mtd2`, check
`sha256sum /dev/mtd2` == c58710c5..., then reboot. An env erase is not needed: the head in this dump is already U-Boot's
own DCP output for this chip (INFERRED from the format in documentation/05_Security_Analysis/kernel_encryption.md). UNTESTED.

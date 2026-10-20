# 2026-10-20 — baseline revision 2 kernel + rootfs on the IW416 unit: BOTH BOOTED

**Outcome:** the baseline **revision 2** (ccpa_custom `5e90368`) kernel, its recovery and its squashfs rootfs were
written over revision 1 from revision 1's own recovery, and both came up: the revision-2 recovery, then the rootfs.
Everything below was observed on the real unit. One bug found (`mfi-probe`, below); fixed in ccpa_custom `2796253`,
not yet rebuilt or flashed. The radio test is recorded in `2026-10-20_baseline_rev2_radio_iw416.md`.

Unit: the IW416 bench adapter of `../backups/20261019_IW416_ocbm_baseline_pre-livi/`, running baseline revision 1
since `2026-10-20_baseline_kernel_write.md`. Map: the LIVI map (mtd0 uboot, mtd1 env, mtd2 kernel, mtd3 rootfs,
mtd4 customer, mtd5 bootstate). Times are not recorded.

## Kernel (from the revision-1 recovery)

| Step | Result |
|---|---|
| dump the old kernel partition (`mtd2`, revision 1 after U-Boot's head conversion), twice | both `f584a19bbf35162b58cf5e91ef44ccdfecbbc3015cd79c9a4f1a42d0f3dbbc4e` (differs from the `6bf47a40…` written for revision 1, consistent with U-Boot's head rewrite) |
| host: `stage_kernel.py` on that dump | head unchanged (planned head = current head), headroom 1,030,836 B; planned sha256 `f9651725b4b59a91933477537891188dd3164c6ee65c69e17a2b556be01fe6e9` |
| unit: `NO_REBOOT=1 flash-kernel 192.168.50.100:5611 <sha256>` (pull from the host) | `mtd2` written and verified, env erased, U-Boot sha256 `c60054cafb6083761c64bceb96095d6731b86db57983558b8db9810d66807bca` unchanged (= the 2026-10-19/20 backups) |
| reboot | **revision-2 recovery up in ~28 s** on NCM at 192.168.50.2 |
| USB serial | `OCBM-<12 hex>`, unit-specific (not repeated here: the no-device-serials rule). Revision 1 had the empty-input hash `OCBM-e3b0c44298fc` on this unit (bug B1, confirmed on hardware); B1 is fixed |
| SSH | dropbear 2026.94, password login OK in recovery. Key login not tested |

## Rootfs (from the revision-2 recovery)

| Step | Result |
|---|---|
| host: `scp -O rootfs.img root@192.168.50.2:/tmp/` | OK; 2,560,000 B, sha256 `c424cd3c7be6febcebec449f3c5407a16cb21db058a201cee16f35d2e25c2f59`, checked on the unit |
| unit: `flash-rootfs` | `mtd3` written and verified, bootstate cleared |
| reboot | **rootfs booted**; rcS finished: NCM 192.168.50.2, ssh/scp/sftp, `mdev -d`, udhcpd, bootstate cleared |
| persist | `persist load` found no baseline archive in `mtd4`, so the default password from the build's `ROOT_PASSWORD_HASH` applied; `ssh-up` then made a host key and saved the archive to `mtd4` (`../baseline/common/shared/ssh-up:61`), overwriting LIVI's customer data. *(Corrected 2026-10-20: this row said only "`mtd4` empty".)* |
| checks | `sftp` ls OK; BusyBox v1.38.0, 410 applets; MemAvailable ~114 MB; `/dev/i2c-0`, `/dev/i2c-1`; LEDs `blue` and `red` present; `radio status` reports the radios off |

## Found

- `mfi-probe`: `flock: unrecognized option: w`. BusyBox 1.38.0 `flock` takes `-s -x -u -n` and `-c`, no `-w`, so the
  probe fails before any I2C read. Fixed in ccpa_custom `2796253` (poll `flock -n`, 50 x 200 ms, same message on
  timeout). Needs a rootfs rebuild and `flash-rootfs`; **not yet rebuilt or flashed**. An audit of every on-unit script
  of the baseline against the full and recovery BusyBox configs found no other unsupported applet option.

## NOT yet tested

USB stick mount (and `mdev` auto-mount, `usb-update`), key-only SSH login and a saved key or host key read back
across a reboot, LED behaviours (`led ...`), `mfi-probe` after the fix, the MACs. (`radio up`/`radio down` have
since run: `2026-10-20_baseline_rev2_radio_iw416.md`.)

## State of the unit after this run

Baseline revision 2 kernel + recovery (`mtd2`; its head converted by U-Boot, so `mtd2` no longer equals `f9651725…`
[INFERRED from the revision-1 result above]) and revision 2 rootfs (first 2,560,000 B of `mtd3` = `c424cd3c…`). `mtd4` (customer)
holds the baseline persist archive written at the first rootfs boot (no longer LIVI's data). The unit runs no LIVI component.
To stage another kernel, dump `mtd2` again first.

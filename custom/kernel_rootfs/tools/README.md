# Host and on-unit tools used for the kernel/rootfs runs

Run the Python tools with `python3 -I`. They talk to a unit over USB-NCM and write nothing on the host except the file
you name. Long commands on the unit must run under `setsid sh -c '…' > /tmp/x.log 2>&1 &`, with the log polled
afterwards. A closed telnet session SIGHUPs its children; on 2026-10-19 a `flashcp` started in one was found gone part-way after the
session closed (SIGHUP inferred, not seen; `../hardware_tests/2026-10-19_round_trip/RUNBOOK.txt`).

| File | Use |
|---|---|
| `tn.py` | `python3 -I tn.py <host> <port> '<cmd>' [drain_s]`: one command over telnet, answers IAC negotiation, prints the output. **`BOUND_IF=<iface>`** pins the socket to one interface (macOS `IP_BOUND_IF`). You need it when two NCM devices both answer at 10.10.10.1 (a LIVI CCPA and a LIVI C2Air on one Mac, first hit 2026-10-19 17:16 local). |
| `send.py` | `python3 -I send.py <file>`: one-shot TCP server on **10.10.10.100:5611** (address hard-coded: LIVI's first DHCP lease). The unit pulls the file with `nc 10.10.10.100 5611 > /tmp/f`. On 2026-10-19, pulling from it worked; four pushes with macOS `nc` failed (the first left 146,432 B) and pulls from a macOS `nc -N -l` listener gave 0 B. |
| `dryrun.py` | `python3 -I dryrun.py <mtd0.bin> <mtd1.bin> <zImage> CFG0 CFG1 MAC0 MAC1`: offline plan of LIVI's kernel staging against a vendor-map backup. It produced `../hardware_tests/2026-10-19_round_trip/*dryrun_report.txt`. Files only. Superseded for new work by `../baseline/arm-imx6ul/tools/stage_kernel.py`, whose header comment names this file at its old owner-local path. The two implement the same update-env/staging layout (decrypt the update env with the UpgKey, take `kernel_len` and the staging offsets from `norboot`/`heweiencrypt`, keep the DCP head, write the body in the clear, UpgKey-encrypt the new head into staging). `stage_kernel.py` is the maintained one; `dryrun.py` stays as run and is not merged into it. |
| `flash_erase` | stock mtd-utils 1.4.8 ARM binary, dynamically linked (glibc), 25,628 B, sha256 `437e1b7f411592861192d775fba4d121f6cc61bbba3c067f976201f7de5726bf`. Push it to `/tmp` on vendor/OCBM rootfs units, which ship no `flash_erase`/`flashcp`. Offsets are **bytes**: `flash_erase /dev/mtd0 196608 1` erases the env block. |

Also in this repo (not duplicated here):
- `../baseline/arm-imx6ul/tools/stage_kernel.py`: host, stages a kernel partition for one unit (`--self-test`, `-h`).
- `../baseline/common/tools/serve_once.py`: host, one-shot file server for the baseline recovery helpers' `host:port` pulls.
- `../../scripts/etc_mdev_usb_mount.sh`: the mdev USB hook. It is byte-identical to ccpa_custom `ccpa/rootfs/etc/mdev/usb_mount.sh`.
- `../../../ocbm/scripts/{ncm_base_install.sh,audit_scripts.sh,busybox_upgrade.sh,dropbear_upgrade.sh}`: synced 2026-10-20
  to ccpa_custom `tools/` at commit `7e104ee`, the working copies. The earlier sync had missed the `ko.tar.gz` Apple-gadget
  filter (`KO_DROP`/`KO_NEED`) and still carried an absolute home path in `busybox_upgrade.sh`, and `dropbear_upgrade.sh`
  here kept one in its `SRC_TAR` default until 2026-10-20 (now `$HOME`, as in ccpa_custom). The corrected mtd1 comment of
  `ncm_base_install.sh` ("WHAT IS NEVER TOUCHED": only the first 192 KB are per-chip; read for backup, never written) went
  back to ccpa_custom in `672624c`; these four files are byte-identical to ccpa_custom `tools/` at `672624c`.

`tn.py`, `send.py` and `dryrun.py` are byte-identical to the copies used in the runs, under `/tmp/rt/` and the
backup's `round_trip/host_tools/`.

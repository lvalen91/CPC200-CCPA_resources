# Host and on-unit tools used for the kernel/rootfs runs

Run the Python tools with `python3 -I`. They talk to a unit over USB-NCM and write nothing on the host except the file
you name. Long commands on the unit must run under `setsid sh -c '…' > /tmp/x.log 2>&1 &`, with the log polled
afterwards. A closed telnet session SIGHUPs its children, and on 2026-10-19 that killed a `flashcp` part-way through
(`../hardware_tests/2026-10-19_round_trip/RUNBOOK.txt`).

| File | Use |
|---|---|
| `tn.py` | `python3 -I tn.py <host> <port> '<cmd>' [drain_s]`: one command over telnet, answers IAC negotiation, prints the output. **`BOUND_IF=<iface>`** pins the socket to one interface (macOS `IP_BOUND_IF`). You need it when two NCM devices both answer at 10.10.10.1 (a LIVI CCPA and a LIVI C2Air on one Mac, 2026-10-20). |
| `send.py` | `python3 -I send.py <file>`: one-shot TCP server on **10.10.10.100:5611** (address hard-coded: LIVI's first DHCP lease). The unit pulls the file with `nc 10.10.10.100 5611 > /tmp/f`. On 2026-10-19, pulling worked and pushing with macOS `nc` truncated at about 146 KB. |
| `dryrun.py` | `python3 -I dryrun.py <mtd0.bin> <mtd1.bin> <zImage> CFG0 CFG1 MAC0 MAC1`: offline plan of LIVI's kernel staging against a vendor-map backup. It produced `../hardware_tests/2026-10-19_round_trip/*dryrun_report.txt`. Files only. Superseded for new work by `../baseline/arm-imx6ul/tools/stage_kernel.py`, whose header comment names this file at its old owner-local path. |
| `flash_erase` | stock mtd-utils 1.4.8 ARM binary, dynamically linked (glibc), 25,628 B, sha256 `437e1b7f411592861192d775fba4d121f6cc61bbba3c067f976201f7de5726bf`. Push it to `/tmp` on vendor/OCBM rootfs units, which ship no `flash_erase`/`flashcp`. Offsets are **bytes**: `flash_erase /dev/mtd0 196608 1` erases the env block. |

Also in this repo (not duplicated here):
- `../baseline/arm-imx6ul/tools/stage_kernel.py`: host, stages a kernel partition for one unit (`--self-test`, `-h`).
- `../baseline/common/tools/serve_once.py`: host, one-shot file server for the baseline recovery helpers' `host:port` pulls.
- `../../scripts/etc_mdev_usb_mount.sh`: the mdev USB hook. It is byte-identical to ccpa_custom `ccpa/rootfs/etc/mdev/usb_mount.sh`.
- `../../../ocbm/scripts/{ncm_base_install.sh,audit_scripts.sh,busybox_upgrade.sh}`: synced 2026-10-20 to ccpa_custom
  `tools/` at commit `7e104ee`, the working copies. The earlier sync had missed the `ko.tar.gz` Apple-gadget filter
  (`KO_DROP`/`KO_NEED`) and still carried an absolute home path in `busybox_upgrade.sh`.

`tn.py`, `send.py` and `dryrun.py` are byte-identical to the copies used in the runs, under `/tmp/rt/` and the
backup's `round_trip/host_tools/`.

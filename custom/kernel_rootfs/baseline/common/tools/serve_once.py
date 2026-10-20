#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Serve one file over raw TCP to the first client, then exit. Host side, stdlib only.

The recovery helpers PULL images (`flash-rootfs 192.168.50.100:5611 <sha256>` runs
`nc 192.168.50.100 5611 > /tmp/rootfs.img` on the unit) because a macOS nc PUSHING into busybox nc
over NCM failed four times on 2026-10-19 (the first left 146,432 B; pulls from a macOS `nc -l` listener gave
0 B), while a pull from a host-side Python server did not
(ccpa_backups/20261019_IW416_ocbm_baseline_pre-livi/round_trip/RUNBOOK.txt).

  python3 -I serve_once.py FILE [--bind 192.168.50.100] [--port 5611]
"""
import argparse
import hashlib
import socket
import sys


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--bind", default="192.168.50.100", help="host address on the NCM link")
    ap.add_argument("--port", type=int, default=5611)
    a = ap.parse_args(argv)
    data = open(a.file, "rb").read()
    print("%s: %d bytes, sha256 %s" % (a.file, len(data), hashlib.sha256(data).hexdigest()))
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((a.bind, a.port))
    s.listen(1)
    print("waiting on %s:%d (on the unit: <helper> %s:%d <sha256>)" % (a.bind, a.port, a.bind, a.port))
    c, peer = s.accept()
    try:
        c.sendall(data)
        c.shutdown(socket.SHUT_WR)
        print("sent %d bytes to %s:%d" % (len(data), peer[0], peer[1]))
    finally:
        c.close()
        s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

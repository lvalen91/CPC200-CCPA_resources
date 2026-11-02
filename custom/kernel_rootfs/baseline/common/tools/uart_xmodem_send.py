#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# uart_xmodem_send.py PORT FILE REMOTE_PATH [--baud 115200] [--check]: push FILE to the unit over its UART
# console with XMODEM-1K/CRC, the recovery initramfs's `rx` (BusyBox; README §2.2 "rescue extras").
# Host side, no dependencies. Types `rx REMOTE_PATH` on the console, waits for rx's 'C' (CRC mode),
# sends 1024-byte STX blocks (the final one padded with 0x1A: rx writes the padding too, so the
# receiver file is rounded up to 1 KiB; `--check` prints the sha256 of the first len(FILE) bytes on
# the unit and compares, which is what flash-rootfs/flash-kernel also expect: pass them the exact
# size with `dd bs=... count=...`, or let --check truncate with the printed command).
# Why not base64 over the console: the recovery BusyBox has neither base64 nor gunzip; XMODEM has a
# per-block CRC and retransmission, which the bare console stream has not. ~9 KB/s at 115200.
import argparse, hashlib, os, select, sys, termios, time

SOH, STX, EOT, ACK, NAK, CAN, CRCCHR, PAD = 0x01, 0x02, 0x04, 0x06, 0x15, 0x18, ord("C"), 0x1A


def crc16(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def open_port(path, baud):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    t = termios.tcgetattr(fd)
    t[0] = 0                      # iflag: no XON/XOFF, no CR/LF translation, no parity marking
    t[1] = 0                      # oflag: raw
    t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    t[3] = 0                      # lflag: no echo, no canonical
    t[4] = t[5] = getattr(termios, "B%d" % baud)
    t[6][termios.VMIN] = 0
    t[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, t)
    os.set_blocking(fd, False)
    return fd


def read_avail(fd, timeout):
    r, _, _ = select.select([fd], [], [], timeout)
    if not r:
        return b""
    try:
        return os.read(fd, 65536)
    except BlockingIOError:
        return b""


def write_all(fd, data):
    off = 0
    while off < len(data):
        _, w, _ = select.select([], [fd], [], 5)
        if not w:
            raise SystemExit("port not writable for 5 s")
        try:
            off += os.write(fd, data[off:])
        except BlockingIOError:
            pass


def wait_byte(fd, wanted, timeout):
    """Wait for one of `wanted` control bytes; returns it or None. Other bytes (console echo) are skipped."""
    end = time.time() + timeout
    while time.time() < end:
        d = read_avail(fd, 0.2)
        for b in d:
            if b in wanted:
                return b
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("file")
    ap.add_argument("remote")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--check", action="store_true", help="sha256 the first len(FILE) bytes on the unit afterwards")
    ap.add_argument("--no-cmd", action="store_true", help="do not type the rx command (rx already waiting)")
    a = ap.parse_args()
    data = open(a.file, "rb").read()
    size = len(data)
    sha = hashlib.sha256(data).hexdigest()
    fd = open_port(a.port, a.baud)
    t0 = time.time()
    if not a.no_cmd:
        write_all(fd, b"\r")
        time.sleep(0.3)
        read_avail(fd, 0.2)
        write_all(fd, ("rx %s\r" % a.remote).encode())
    # rx announces CRC mode with 'C' (checksum mode with NAK); honour either
    hs = wait_byte(fd, (CRCCHR, NAK), 20)
    if hs is None:
        raise SystemExit("no handshake from rx within 20 s (is the console free and at a prompt?)")
    crc_mode = hs == CRCCHR
    print("[xmodem] %s -> %s: %d bytes, %s mode, 1K blocks" % (a.file, a.remote, size, "CRC" if crc_mode else "checksum"))
    blk = 1
    off = 0
    retries = 0
    while off < size:
        chunk = data[off:off + 1024]
        if len(chunk) < 1024:
            chunk = chunk + bytes([PAD]) * (1024 - len(chunk))
        pkt = bytes([STX, blk & 0xFF, 0xFF - (blk & 0xFF)]) + chunk
        if crc_mode:
            c = crc16(chunk)
            pkt += bytes([c >> 8, c & 0xFF])
        else:
            pkt += bytes([sum(chunk) & 0xFF])
        for attempt in range(10):
            write_all(fd, pkt)
            r = wait_byte(fd, (ACK, NAK, CAN, CRCCHR), 10)
            if r == ACK:
                break
            if r == CAN:
                raise SystemExit("receiver cancelled at block %d" % blk)
            retries += 1
            if attempt == 9:
                raise SystemExit("block %d: no ACK after 10 tries" % blk)
        off += 1024
        blk += 1
        if blk % 64 == 0 or off >= size:
            done = min(off, size)
            el = time.time() - t0
            sys.stdout.write("\r[xmodem] %d/%d bytes (%.0f%%) %.1f KB/s retries=%d" % (done, size, 100.0 * done / size, done / 1024 / max(el, 1e-3), retries))
            sys.stdout.flush()
    for attempt in range(10):
        write_all(fd, bytes([EOT]))
        if wait_byte(fd, (ACK,), 5) == ACK:
            break
    print("\n[xmodem] sent in %.1f s, %d retries; file sha256 %s (receiver file is padded to %d bytes)" % (time.time() - t0, retries, sha, ((size + 1023) // 1024) * 1024))
    if a.check:
        time.sleep(0.5)
        read_avail(fd, 0.5)
        cmd = "dd if=%s bs=4096 count=%d 2>/dev/null | sha256sum\r" % (a.remote, (size + 4095) // 4096) if size % 4096 == 0 else \
              "head -c %d %s | sha256sum\r" % (size, a.remote)
        write_all(fd, cmd.encode())
        buf = b""
        end = time.time() + 60
        while time.time() < end and sha.encode() not in buf:
            buf += read_avail(fd, 0.5)
        ok = sha.encode() in buf
        print("[xmodem] unit sha256 of the first %d bytes %s" % (size, "MATCHES" if ok else "NOT seen (output: %r)" % buf[-200:]))
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

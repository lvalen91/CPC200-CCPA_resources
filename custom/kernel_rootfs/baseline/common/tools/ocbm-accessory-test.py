#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# ocbm-accessory-test.py BINARY WORKDIR: host-side test of common/ocbm-accessory (selftest.sh step 9).
# Runs the relay in its -T test mode, where an AF_UNIX datagram socket stands in for the FunctionFS
# bulk endpoints (one datagram = one USB transfer, an empty datagram = a ZLP) and this script is the
# "host"; the "ocbmd" side is this same script in --child mode, started by the relay through the
# device link it provides. Checks, each against the behaviour ocbmd and the OCBM hosts rely on:
#   1. the device link is a symlink to a pty slave whose line discipline is RAW (no ICANON/ECHO/ISIG/
#      OPOST/ICRNL/IXON/IXOFF), so every byte value passes; the child is not given a controlling tty
#   2. host -> device: three transfers (all 256 byte values x4, "\r\n\x03\x11\x13", 16384 random bytes)
#      arrive on the slave byte-exact and in order (stream semantics, no translation, no loss)
#   3. device -> host: a 1024-byte write ends in a ZLP (a wMaxPacketSize multiple), a 100-byte write
#      does not; a 70,000-byte write arrives complete, and every ZLP follows a 512-multiple datagram
#   4. duplex: 1 MiB host -> device echoed back by the child -> host, byte-exact (flow control both ways)
#   5. the child's exit ends its pty generation: a new slave, a new child, the link updated
#   6. SIGUSR1 (= USB DISABLE) hangs the child up (EOF/EIO on the slave) and a new generation follows;
#      bytes written by the device while disabled are dropped, not queued; SIGUSR2 (= ENABLE) resumes
#   7. the relay refuses to replace a device path that is a regular file (never a real node)
#   8. a lone full-size host packet (512 B, no short packet, no ZLP — the 496-byte-payload OCBM frame) is
#      delivered at once and echoed (then terminated by a ZLP); with `-r 16384` (the stock-like request
#      size) the same packet is NOT delivered until a short packet follows: the hang seen on hardware 2026-10-30
# Host -> device datagrams are USB PACKETS (<= 512 B; a transfer is split, no ZLP, like libusb);
# device -> host datagrams are USB transfers. Linux only (ptmx, AF_UNIX datagram pairs). Exit 0 = all pass.
import os, random, select, signal, socket, stat, subprocess, sys, termios, time

XFER = 16384
MPS = 512


def send_xfer(sock, data):
    """One USB bulk transfer as the hosts send it: wMaxPacketSize packets, no ZLP (libusb/IOKit)."""
    for off in range(0, len(data), MPS):
        sock.send(data[off:off + MPS])
    if not data:
        sock.send(b"")


def child_main(dev, log):
    """Stand-in for ocbmd: open the link read-write, report, then echo until hung up."""
    fd = os.open(dev, os.O_RDWR | os.O_NONBLOCK)  # no O_NOCTTY on purpose, like ocbmd
    with open(log, "a") as f:
        t = termios.tcgetattr(fd)
        iflag, oflag, cflag, lflag = t[0], t[1], t[2], t[3]
        bad = []
        for name, word, flag in (("ICANON", lflag, termios.ICANON), ("ECHO", lflag, termios.ECHO),
                                 ("ISIG", lflag, termios.ISIG), ("IEXTEN", lflag, termios.IEXTEN),
                                 ("OPOST", oflag, termios.OPOST), ("ICRNL", iflag, termios.ICRNL),
                                 ("IXON", iflag, termios.IXON), ("IXOFF", iflag, termios.IXOFF),
                                 ("ISTRIP", iflag, termios.ISTRIP), ("INLCR", iflag, termios.INLCR),
                                 ("IGNCR", iflag, termios.IGNCR)):
            if word & flag:
                bad.append(name)
        # a controlling tty would make /dev/tty openable
        try:
            os.close(os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY))
            ctty = "ctty=YES"
        except OSError:
            ctty = "ctty=no"
        f.write("spawn pid=%d link=%s termios=%s %s\n" % (os.getpid(), os.readlink(dev), ",".join(bad) or "raw", ctty))
        f.flush()
        # phase 1: wait for the host's three transfers (exact total 1024 + 5 + 16384 bytes), record them
        want = 1024 + 5 + XFER
        got = bytearray()
        deadline = time.time() + 5
        while len(got) < want and time.time() < deadline:
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try:
                    got += os.read(fd, 65536)
                except BlockingIOError:
                    pass
        with open(log + ".rx", "wb") as rx:
            rx.write(bytes(got))
        f.write("rx %d bytes\n" % len(got))
        f.flush()
        # phase 2: device -> host writes on the host's cue (one byte 'G')
        cue = wait_byte(fd, 5)
        f.write("cue %r\n" % cue)
        f.flush()
        random.seed(7)
        blobs = [bytes(range(256)) * 4, b"x" * 100, bytes(random.getrandbits(8) for _ in range(70000))]
        with open(log + ".tx", "wb") as tx:
            for b in blobs:
                tx.write(b)
        for b in blobs:
            write_all(fd, b)
            time.sleep(0.4)  # burst separation for the host's measurement
        # phase 3: echo everything back until hangup (EIO/EOF) or the host's 'Q'
        f.write("echo\n")
        f.flush()
        echoed = 0
        pending = bytearray()
        hup = "none"
        while True:
            r, w, _ = select.select([fd], [fd] if pending else [], [], 1.0)
            if r:
                try:
                    d = os.read(fd, 65536)
                except BlockingIOError:
                    d = None
                except OSError as e:
                    hup = "read:%s" % e.errno
                    break
                if d == b"":
                    hup = "eof"
                    break
                if d:
                    if d == b"Q" and not pending:
                        break
                    pending += d
            if w and pending:
                try:
                    n = os.write(fd, pending)
                except BlockingIOError:
                    n = 0
                except OSError as e:
                    hup = "write:%s" % e.errno
                    break
                echoed += n
                del pending[:n]
        f.write("exit echoed=%d hup=%s\n" % (echoed, hup))
    os._exit(0)


def wait_byte(fd, secs):
    deadline = time.time() + secs
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                return os.read(fd, 1)
            except BlockingIOError:
                pass
    return b""


def write_all(fd, data):
    off = 0
    while off < len(data):
        _, w, _ = select.select([], [fd], [], 5)
        if not w:
            raise SystemExit("child: slave not writable for 5 s")
        try:
            off += os.write(fd, data[off:])
        except BlockingIOError:
            pass


# ------------------------------------------------------------------------------------------- host
fails = 0


def check(name, ok, detail=""):
    global fails
    print("  %-74s %s" % (name, "ok" if ok else "FAIL"))
    if not ok:
        fails += 1
        if detail:
            print("      " + detail.replace("\n", "\n      "))


def recv_burst(sock, quiet=0.3, limit=10):
    """Datagrams until `quiet` seconds of silence; returns the list (empty datagram = ZLP)."""
    out = []
    deadline = time.time() + limit
    while time.time() < deadline:
        r, _, _ = select.select([sock], [], [], quiet)
        if not r:
            break
        out.append(sock.recv(65536))
    return out


def zlp_rule(datagrams):
    """Every empty datagram follows a non-empty one whose length is a 512-multiple."""
    prev = None
    for d in datagrams:
        if d == b"" and (prev is None or prev == b"" or len(prev) % 512 != 0):
            return False
        prev = d
    return True


def host_main(binary, work):
    os.makedirs(work, exist_ok=True)
    sockpath = os.path.join(work, "host.sock")
    dev = os.path.join(work, "usb_accessory")
    log = os.path.join(work, "child.log")
    pidfile = os.path.join(work, "relay.pid")
    for p in (sockpath, sockpath + ".dev", dev, log, log + ".rx", log + ".tx", pidfile):
        try:
            os.unlink(p)
        except OSError:
            pass
    host = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    host.bind(sockpath)
    relay_log = open(os.path.join(work, "relay.log"), "w")
    relay = subprocess.Popen([binary, "-T", sockpath, "-d", dev, "-p", pidfile, "-v", "--",
                              sys.executable, "-I", os.path.abspath(__file__), "--child", dev, log],
                             stdout=relay_log, stderr=relay_log)
    try:
        for _ in range(50):
            if os.path.exists(sockpath + ".dev") and os.path.islink(dev):
                break
            time.sleep(0.1)
        host.connect(sockpath + ".dev")
        # 1. link + raw termios + no ctty (from the child's first log line)
        line = wait_log(log, "spawn ", 5)
        tgt = os.readlink(dev) if os.path.islink(dev) else "?"
        check("1 device link is a symlink to a pty slave (%s)" % tgt, tgt.startswith("/dev/pts/"))
        check("1 slave line discipline raw, child has no controlling tty", "termios=raw ctty=no" in line, line)
        # 2. host -> device
        random.seed(3)
        d1 = bytes(range(256)) * 4
        d2 = b"\r\n\x03\x11\x13"
        d3 = bytes(random.getrandbits(8) for _ in range(XFER))
        for d in (d1, d2, d3):
            send_xfer(host, d)
        wait_log(log, "rx ", 6)
        time.sleep(0.2)
        rx = open(log + ".rx", "rb").read() if os.path.exists(log + ".rx") else b""
        check("2 host->device: 1024 B (all byte values) + CR LF ETX XON XOFF + 16384 B, byte-exact in order",
              rx == d1 + d2 + d3, "got %d bytes, expected %d" % (len(rx), len(d1 + d2 + d3)))
        # 3. device -> host: cue the child, then three bursts
        send_xfer(host, b"G")
        wait_log(log, "cue ", 5)
        b1 = recv_burst(host)
        b2 = recv_burst(host)
        b3 = recv_burst(host)
        tx = open(log + ".tx", "rb").read()
        j1, j2, j3 = b"".join(b1), b"".join(b2), b"".join(b3)
        check("3 device->host 1024 B: data then a ZLP (wMaxPacketSize multiple terminates with a short packet)",
              j1 == tx[:1024] and b1 and b1[-1] == b"" and zlp_rule(b1), "datagrams %r" % [len(x) for x in b1])
        check("3 device->host 100 B: data, no ZLP", j2 == tx[1024:1124] and b2 and b2[-1] != b"" and zlp_rule(b2),
              "datagrams %r" % [len(x) for x in b2])
        check("3 device->host 70000 B: complete, <= 16384 B per transfer, ZLPs only after 512-multiples",
              j3 == tx[1124:] and all(len(x) <= XFER for x in b3) and zlp_rule(b3),
              "got %d bytes in %d datagrams" % (len(j3), len(b3)))
        # 4. duplex echo, 1 MiB
        random.seed(11)
        blob = bytes(random.getrandbits(8) for _ in range(1 << 20))
        back = bytearray()
        off = 0
        t0 = time.time()
        while (off < len(blob) or len(back) < len(blob)) and time.time() - t0 < 60:
            r, w, _ = select.select([host], [host] if off < len(blob) else [], [], 0.5)
            if w and off < len(blob):
                send_xfer(host, blob[off:off + XFER])
                off += XFER
            if r:
                back += host.recv(65536)
        check("4 duplex: 1 MiB host->device echoed back byte-exact (%.1f MB/s)" % (len(back) / 1e6 / max(time.time() - t0, 1e-3)),
              bytes(back) == blob, "echoed %d of %d bytes" % (len(back), len(blob)))
        # 8. a lone full-size packet: a 512-byte frame must arrive and be echoed at once (ZLP after)
        one = bytes(range(256)) * 2
        t8 = time.time()
        send_xfer(host, one)
        back8 = recv_burst(host, quiet=0.3, limit=3)
        check("8 a lone 512-byte host packet (no short packet) is delivered and echoed within 1 s, then a ZLP (%.2f s)" % (time.time() - t8),
              b"".join(back8) == one and back8[-1] == b"" and time.time() - t8 < 1.5, "datagrams %r" % [len(x) for x in back8])
        # 5. child exit -> new generation
        first_pid = int(line.split("pid=")[1].split()[0])
        send_xfer(host, b"Q")
        line2 = wait_log(log, "spawn ", 6, skip=1)
        tgt2 = os.readlink(dev) if os.path.islink(dev) else "?"
        pid2 = int(line2.split("pid=")[1].split()[0]) if "pid=" in line2 else -1
        check("5 child exit ends the generation: new child (pid %d -> %d), link -> %s" % (first_pid, pid2, tgt2),
              pid2 > 0 and pid2 != first_pid and tgt2.startswith("/dev/pts/"), line2)
        # the new child expects phase 1 again: feed it, cue it, swallow its bursts
        for d in (d1, d2, d3):
            send_xfer(host, d)
        wait_log(log, "rx ", 6, skip=1)
        send_xfer(host, b"G")
        wait_log(log, "cue ", 5, skip=1)
        recv_burst(host, limit=6)
        recv_burst(host, limit=6)
        recv_burst(host, limit=6)
        # 6. DISABLE hangs the child up; its bytes are dropped while disabled; ENABLE resumes
        exits_before = count_log(log, "exit ")
        relay.send_signal(signal.SIGUSR1)
        wait_log(log, "exit ", 6, skip=exits_before)
        ex = [l for l in open(log).read().splitlines() if l.startswith("exit ")][-1]
        line3 = wait_log(log, "spawn ", 6, skip=2)
        check("6 SIGUSR1 (USB DISABLE): the child is hung up (%s) and a new generation starts" % ex.split("hup=")[-1],
              ("hup=read:5" in ex or "hup=eof" in ex or "hup=write:5" in ex) and "pid=" in line3, ex + "\n" + line3)
        for d in (d1, d2, d3):
            send_xfer(host, d)
        wait_log(log, "rx ", 6, skip=2)
        send_xfer(host, b"G")
        wait_log(log, "cue ", 5, skip=2)
        wait_log(log, "echo", 8, skip=2)  # the child has written all three bursts into the disabled relay
        dropped = recv_burst(host, quiet=0.5, limit=3)
        check("6 while disabled, device->host bytes are dropped (nothing reaches the host)", dropped == [],
              "got %d datagrams" % len(dropped))
        relay.send_signal(signal.SIGUSR2)
        time.sleep(0.5)
        send_xfer(host, b"ping-after-enable")
        echo = recv_burst(host, limit=5)
        check("6 SIGUSR2 (ENABLE): traffic flows again", b"".join(echo) == b"ping-after-enable", repr(echo))
    finally:
        relay.terminate()
        try:
            relay.wait(5)
        except subprocess.TimeoutExpired:
            relay.kill()
        relay_log.close()
        host.close()
    check("relay exits 0 on SIGTERM and removes its pid file", relay.returncode == 0 and not os.path.exists(pidfile),
          "rc=%r" % relay.returncode)
    # 8b. the same lone packet against `-r 16384`: not delivered until a short packet follows
    sock3 = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sp3 = os.path.join(work, "host3.sock")
    dev3 = os.path.join(work, "usb_accessory_r")
    log3 = os.path.join(work, "child3.log")
    for q in (sp3, sp3 + ".dev", dev3, log3, log3 + ".rx"):
        try:
            os.unlink(q)
        except OSError:
            pass
    sock3.bind(sp3)
    rl3 = open(os.path.join(work, "relay3.log"), "w")
    relay3 = subprocess.Popen([binary, "-T", sp3, "-d", dev3, "-r", "16384", "-v", "-v", "--",
                               sys.executable, "-I", os.path.abspath(__file__), "--child", dev3, log3],
                              stdout=rl3, stderr=rl3)
    try:
        for _ in range(50):
            if os.path.exists(sp3 + ".dev") and os.path.islink(dev3):
                break
            time.sleep(0.1)
        sock3.connect(sp3 + ".dev")
        wait_log(log3, "spawn ", 5)
        send_xfer(sock3, one)                      # 512 B: one full packet, nothing else
        time.sleep(1.5)
        rl3.flush()
        outs_before = count_log(os.path.join(work, "relay3.log"), "ocbm-accessory: OUT ")
        send_xfer(sock3, d2)                       # a 5-byte short packet completes the pending request
        send_xfer(sock3, bytes(16384 + 1024 - 512 - 5))  # the rest of phase 1's budget so the child logs rx
        wait_log(log3, "rx ", 8)
        rl3.flush()
        rxb = open(log3 + ".rx", "rb").read() if os.path.exists(log3 + ".rx") else b""
        check("8b with -r 16384 (the stock-like request) the lone 512-byte packet is held until a short packet follows, then arrives intact",
              outs_before == 0 and rxb[:512] == one, "relay OUT reads before the short packet=%d, bytes=%d" % (outs_before, len(rxb)))
    finally:
        relay3.terminate()
        try:
            relay3.wait(5)
        except subprocess.TimeoutExpired:
            relay3.kill()
        rl3.close()
        sock3.close()
    # 7. refuses a regular file at the device path
    reg = os.path.join(work, "regular_node")
    open(reg, "w").close()
    sock2 = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sp2 = os.path.join(work, "host2.sock")
    try:
        os.unlink(sp2)
    except OSError:
        pass
    sock2.bind(sp2)
    r = subprocess.run([binary, "-T", sp2, "-d", reg], capture_output=True, text=True, timeout=10)
    check("7 refuses to replace a regular file at the device path (exit %d)" % r.returncode,
          r.returncode != 0 and "not a symlink" in r.stderr and stat.S_ISREG(os.stat(reg).st_mode), r.stderr.strip())
    sock2.close()
    return fails


def wait_log(log, prefix, secs, skip=0):
    deadline = time.time() + secs
    while time.time() < deadline:
        if os.path.exists(log):
            lines = [l for l in open(log).read().splitlines() if l.startswith(prefix)]
            if len(lines) > skip:
                return lines[skip]
        time.sleep(0.05)
    return ""


def count_log(log, prefix):
    if not os.path.exists(log):
        return 0
    return len([l for l in open(log).read().splitlines() if l.startswith(prefix)])


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--child":
        child_main(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3:
        n = host_main(sys.argv[1], sys.argv[2])
        print("ocbm-accessory-test: %s" % ("PASS" if n == 0 else "FAIL (%d)" % n))
        sys.exit(1 if n else 0)
    else:
        sys.exit("usage: ocbm-accessory-test.py BINARY WORKDIR")

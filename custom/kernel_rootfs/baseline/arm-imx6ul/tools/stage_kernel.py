#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Based on LIVI by Lasse Heitgres (https://github.com/f-io/LIVI)
# Modified 2026-10-19/20: the changes against LIVI are stated in this header.
#
# Derived from LIVI (https://github.com/f-io/LIVI, GPL-3.0-or-later), local copy:
#   native/livi-link/crates/imx6ul-uboot/src/lib.rs          (read_env, layout, kernel_partition, tests)
#   native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/boot.rs  (prepare: unchanged flag)
# and from our offline reproduction of it:
#   carlinkit_misc/ccpa_backups/20261019_IW416_ocbm_baseline_pre-livi/round_trip/dryrun.py
# Changes: Python port, pure-Python AES-128 (the key never appears on a command line), fuse words
# read from a file (never from argv, never printed), an image without a complete appended DTB is
# refused, --self-test.
"""Stage a kernel image for the CPC200-CCPA (i.MX6ULL) vendor U-Boot. Host side, files only.

The vendor U-Boot reads 0x302fd8 bytes from flash 0x40000; the first three 64 KiB blocks are
DCP-encrypted per chip. A new kernel is installed by writing it in the clear from 0x70000 on,
keeping the current (encrypted) head, and staging the new head AES-128-CBC encrypted with the
unit's UpgKey in the three blocks after kernel_len. Erasing the U-Boot env block then makes U-Boot
run `heweiencrypt`, which converts the staged head into the DCP head and rewrites the env.

This tool reads a dump of the uboot partition (for the encrypted update environment at +0x20000),
a dump of the current kernel partition, the new image (zImage with the DTB appended) and the four
OCOTP words (CFG0 CFG1 MAC0 MAC1), and writes the planned kernel partition image plus a report.
It touches no device. Run it with `python3 -I`.

  stage_kernel.py --mtd0 uboot.bin --mtd1 kernel.bin --zimage new.zimg --unit-info unit_info.txt \\
                  [--out planned.bin] [--expect-planned-sha256 HEX]
  stage_kernel.py --full full_16MB.bin --zimage ... --ocotp-nvmem nvmem.bin ...
  stage_kernel.py --unit-info unit_info.txt --print-usb-identity
  stage_kernel.py --self-test
"""
import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

ERASE = 0x10000
UPDATE_BLOCK = 0x20000
ENV_BLOCK = 0x30000
KERNEL = 0x40000
HEAD = 3 * ERASE
ENV_SIZE = 0x10000
ENV_VARS_END = 0x800
ENV_CRC2_AT = ENV_SIZE - 4  # second CRC32 of the update env, over env[0:0xFFFC]
ZIMAGE_MAGIC = 0x016F2818
FDT_MAGIC = 0xD00DFEED
LOAD = 0x80800000
KERNEL_PART = 0x340000      # "kernel" partition size in the vendor map and in ours
# What the vendor U-Boot reads on the units read so far (build 2025.10.15.1127). NOT universal: build
# 2025.02.25.1521 reads 0x303080 and stages at partition offset 0x303080 (CPC200-CCPA_resources
# documentation/05_Security_Analysis/kernel_encryption.md). This tool always takes kernel_len and the
# staging offset from the unit's own update env (layout()); KERNEL_MAX is only the baseline's image
# budget, which board.env (KERNEL_MAX, STAGING_PART_OFFSET) and flash-kernel's staged-head probe share.
KERNEL_MAX = 0x302FD8


class StageError(Exception):
    pass


# --------------------------------------------------------------------------- AES-128 (FIPS-197)

def _xtime(a):
    a <<= 1
    return (a ^ 0x11B) if a & 0x100 else a


def _gmul(a, b):
    r = 0
    while b:
        if b & 1:
            r ^= a
        a = _xtime(a)
        b >>= 1
    return r


def _build_sbox():
    sbox = [0] * 256
    inv = [0] * 256
    for x in range(256):
        y = 1
        if x == 0:
            y = 0
        else:
            # x^254 is the multiplicative inverse in GF(2^8)
            e, base = 254, x
            while e:
                if e & 1:
                    y = _gmul(y, base)
                base = _gmul(base, base)
                e >>= 1
        s = y
        for i in range(1, 5):
            s ^= ((y << i) | (y >> (8 - i))) & 0xFF
        s ^= 0x63
        sbox[x] = s
        inv[s] = x
    return sbox, inv


SBOX, INV_SBOX = _build_sbox()
M2 = [_gmul(x, 2) for x in range(256)]
M3 = [_gmul(x, 3) for x in range(256)]
M9 = [_gmul(x, 9) for x in range(256)]
M11 = [_gmul(x, 11) for x in range(256)]
M13 = [_gmul(x, 13) for x in range(256)]
M14 = [_gmul(x, 14) for x in range(256)]
# state byte i = row (i % 4), column (i // 4); ShiftRows moves row r left by r
SHIFT = [(i % 4) + 4 * (((i // 4) + (i % 4)) % 4) for i in range(16)]
INV_SHIFT = [0] * 16
for _i, _j in enumerate(SHIFT):
    INV_SHIFT[_j] = _i


class AES128:
    def __init__(self, key):
        if len(key) != 16:
            raise ValueError("AES-128 needs a 16-byte key")
        w = [list(key[i:i + 4]) for i in range(0, 16, 4)]
        rcon = 1
        for i in range(4, 44):
            t = list(w[i - 1])
            if i % 4 == 0:
                t = t[1:] + t[:1]
                t = [SBOX[b] for b in t]
                t[0] ^= rcon
                rcon = _xtime(rcon)
            w.append([w[i - 4][j] ^ t[j] for j in range(4)])
        self.rk = [sum(w[4 * r:4 * r + 4], []) for r in range(11)]

    def encrypt_block(self, block):
        rk = self.rk
        s = [b ^ k for b, k in zip(block, rk[0])]
        for rnd in range(1, 11):
            s = [SBOX[s[SHIFT[i]]] for i in range(16)]
            if rnd != 10:
                m = []
                for c in range(0, 16, 4):
                    a0, a1, a2, a3 = s[c], s[c + 1], s[c + 2], s[c + 3]
                    m += [M2[a0] ^ M3[a1] ^ a2 ^ a3, a0 ^ M2[a1] ^ M3[a2] ^ a3,
                          a0 ^ a1 ^ M2[a2] ^ M3[a3], M3[a0] ^ a1 ^ a2 ^ M2[a3]]
                s = m
            s = [b ^ k for b, k in zip(s, rk[rnd])]
        return bytes(s)

    def decrypt_block(self, block):
        rk = self.rk
        s = [b ^ k for b, k in zip(block, rk[10])]
        for rnd in range(9, -1, -1):
            s = [INV_SBOX[s[INV_SHIFT[i]]] for i in range(16)]
            s = [b ^ k for b, k in zip(s, rk[rnd])]
            if rnd != 0:
                m = []
                for c in range(0, 16, 4):
                    a0, a1, a2, a3 = s[c], s[c + 1], s[c + 2], s[c + 3]
                    m += [M14[a0] ^ M11[a1] ^ M13[a2] ^ M9[a3], M9[a0] ^ M14[a1] ^ M11[a2] ^ M13[a3],
                          M13[a0] ^ M9[a1] ^ M14[a2] ^ M11[a3], M11[a0] ^ M13[a1] ^ M9[a2] ^ M14[a3]]
                s = m
        return bytes(s)


def cbc_encrypt(aes, iv, data):
    if len(data) % 16:
        raise ValueError("CBC data is not a multiple of 16 bytes")
    out = bytearray()
    prev = iv
    for i in range(0, len(data), 16):
        blk = aes.encrypt_block(bytes(a ^ b for a, b in zip(data[i:i + 16], prev)))
        out += blk
        prev = blk
    return bytes(out)


def cbc_decrypt(aes, iv, data):
    if len(data) % 16:
        raise ValueError("CBC data is not a multiple of 16 bytes")
    out = bytearray()
    prev = iv
    for i in range(0, len(data), 16):
        c = data[i:i + 16]
        out += bytes(a ^ b for a, b in zip(aes.decrypt_block(c), prev))
        prev = c
    return bytes(out)


# --------------------------------------------------------------------------- UpgKey / fuses

class UpgKey:
    """key || IV = ASCII hex of OCOTP CFG0, CFG1, MAC0, MAC1 (lib.rs UpgKey::new)."""

    def __init__(self, cfg0, cfg1, mac0, mac1):
        text = ("%08x%08x%08x%08x" % (cfg0, cfg1, mac0, mac1)).encode()
        self.key, self.iv = text[:16], text[16:]
        self._aes = AES128(self.key)

    # Every 64 KiB block (and the env payload) is its own CBC stream starting at the same IV,
    # exactly as kernel_partition() calls key.encrypt(block) per block.
    def encrypt(self, data):
        return cbc_encrypt(self._aes, self.iv, data)

    def decrypt(self, data):
        return cbc_decrypt(self._aes, self.iv, data)


FUSE_LINE = re.compile(r"^0x([0-9a-fA-F]{8})$")


def fuses_from_unit_info(path):
    """unit_info.txt from the backup: exactly four lines '0x%08x' = CFG0 CFG1 MAC0 MAC1, in order."""
    words = []
    with open(path, "r", encoding="ascii", errors="replace") as f:
        for line in f:
            m = FUSE_LINE.match(line.strip())
            if m:
                words.append(int(m.group(1), 16))
    if len(words) != 4:
        raise StageError("%s: expected exactly 4 lines of the form 0x%%08x (CFG0 CFG1 MAC0 MAC1), "
                         "found %d" % (path, len(words)))
    return tuple(words)


def fuses_from_ocotp(nvmem):
    """Raw /sys/bus/nvmem/devices/imx-ocotp0/nvmem dump: words 1, 2, 0x22, 0x23 (lib.rs from_ocotp)."""
    if len(nvmem) < 0x24 * 4:
        raise StageError("OCOTP dump is %d bytes, too short for MAC1 (word 0x23)" % len(nvmem))
    w = lambda i: struct.unpack_from("<I", nvmem, i * 4)[0]
    return (w(1), w(2), w(0x22), w(0x23))


def usb_identity(cfg0, cfg1):
    """iSerial and NCM MACs as common/shared/ocbm-identity derives them on the device.

    Input is CFG0||CFG1 as the 8 raw bytes nvmem holds at offset 4 (two little-endian words).
    The raw words are never exposed: they are the first half of the UpgKey text.
    """
    h = hashlib.sha256(struct.pack("<II", cfg0, cfg1)).hexdigest()

    def mac(hx):
        b = bytearray.fromhex(hx)
        b[0] = (b[0] & 0xFC) | 0x02   # unicast, locally administered
        return ":".join("%02x" % x for x in b)
    return {"serial": "OCBM-" + h[:12], "dev_addr": mac(h[0:12]), "host_addr": mac(h[12:24])}


# --------------------------------------------------------------------------- update env + layout

def read_env(block, key):
    if len(block) != ERASE:
        raise StageError("update block is %d bytes, not %d" % (len(block), ERASE))
    n = struct.unpack("<I", block[ERASE - 4:])[0]
    if n == 0 or n > ERASE or n % 16:
        raise StageError("update block holds no environment (length word %#x)" % n)
    payload = key.decrypt(block[ERASE - n:])
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    try:
        env = d.decompress(payload, ENV_SIZE + 1)
    except zlib.error as e:
        raise StageError("update environment does not unpack with this unit's key: %s" % e)
    if not d.eof:
        raise StageError("update environment does not unpack with this unit's key (truncated gzip)")
    if len(env) != ENV_SIZE:
        raise StageError("update environment is %#x bytes, not %#x" % (len(env), ENV_SIZE))
    if zlib.crc32(env[4:ENV_VARS_END]) != struct.unpack("<I", env[:4])[0]:
        raise StageError("update environment fails its CRC")
    # The second CRC32 (little-endian, at 0xFFFC) covers env[0:0xFFFC]: the first CRC, the variables AND
    # the vendor FDT at 0x800 that norboot hands every kernel (kernel_encryption.md; it matched on the
    # three units' dumps read so far). Hard check since revision 3 (B12).
    if zlib.crc32(env[:ENV_CRC2_AT]) != struct.unpack("<I", env[ENV_CRC2_AT:])[0]:
        raise StageError("update environment fails its second CRC (over env[0:%#x], stored at %#x)"
                         % (ENV_CRC2_AT, ENV_CRC2_AT))
    return env


def env_vars(env):
    out = {}
    for v in env[4:ENV_VARS_END].split(b"\0"):
        if not v:
            break
        k, sep, x = v.decode("latin-1").partition("=")
        if sep:
            out.setdefault(k, x)
    return out


def _commands(script):
    return [c.split() for c in script.split(";") if c.split()]


def _hex(s):
    if not s.startswith("0x"):
        return None
    try:
        return int(s[2:], 16)
    except ValueError:
        return None


def layout(env, kernel_part):
    v = env_vars(env)
    if "norboot" not in v:
        raise StageError("no norboot in the update environment")
    norboot = _commands(v["norboot"])
    kl = None
    for c in norboot:
        if len(c) == 5 and c[:2] == ["sf", "read"] and _hex(c[2]) == LOAD and c[3] == "0x40000":
            kl = _hex(c[4])
            if kl is not None:
                break
    if kl is None:
        raise StageError("norboot does not read the kernel from 0x40000")
    head = [_hex(c[2]) for c in norboot if len(c) == 4 and c[:2] == ["mm", "w"] and c[3] == "0x10000"]
    if head != [LOAD, LOAD + ERASE, LOAD + 2 * ERASE]:
        raise StageError("norboot does not decrypt exactly the first three blocks")
    if "heweiencrypt" not in v:
        raise StageError("no heweiencrypt in the update environment")
    frm = None
    pairs = []
    for c in _commands(v["heweiencrypt"]):
        if len(c) == 5 and c[:2] == ["sf", "read"] and _hex(c[2]) == LOAD and c[4] == "0x10000":
            frm = _hex(c[3])
        elif len(c) == 5 and c[:2] == ["sf", "update"] and _hex(c[2]) == LOAD and c[4] == "0x10000":
            dst = _hex(c[3])
            if frm is not None and dst is not None:
                pairs.append((frm, dst))
            frm = None
    if not pairs:
        raise StageError("heweiencrypt converts no kernel blocks")
    staging = pairs[0][0]
    expected = [(staging + i * ERASE, KERNEL + i * ERASE) for i in range(3)]
    if [p for p in pairs if p[1] != ENV_BLOCK] != expected:
        raise StageError("heweiencrypt does not convert three consecutive staging blocks")
    if kl <= HEAD or staging < KERNEL + kl or staging + HEAD > KERNEL + kernel_part:
        raise StageError("kernel %#x and staging at %#x do not fit the kernel partition" % (kl, staging))
    return {"kernel_len": kl, "staging": staging, "pairs": pairs}


def zimage_info(z):
    if len(z) <= HEAD or len(z) < 0x30 or struct.unpack_from("<I", z, 0x24)[0] != ZIMAGE_MAGIC:
        raise StageError("not an ARM zImage")
    start, end = struct.unpack_from("<II", z, 0x28)
    zlen = end - start
    info = {"size": len(z), "zimage_len": zlen, "dtb_at": None, "dtb_size": None}
    if 0 < zlen < len(z) and len(z) - zlen >= 8 and struct.unpack_from(">I", z, zlen)[0] == FDT_MAGIC:
        info["dtb_at"] = zlen
        info["dtb_size"] = struct.unpack_from(">I", z, zlen + 4)[0]
    return info


def require_dtb(z):
    """The image must END in a complete appended DTB: without one the kernel takes the FDT the vendor
    U-Boot passes (norboot copies it from its update env), whose bootargs say console=ttyLogFile0 and
    whose partition map is the vendor's: no UART console, no recovery, nothing to reach the unit with."""
    zi = zimage_info(z)
    if zi["dtb_at"] is None:
        raise StageError("image has no appended DTB (no FDT magic right after the zImage): the vendor "
                         "U-Boot's own FDT would take over (console=ttyLogFile0, vendor partitions), "
                         "so the unit would come up without a console or recovery. Use build.sh's "
                         "ccpa-baseline-<radio>.zimg (zImage + DTB)")
    if zi["dtb_size"] < 0x28 or zi["dtb_at"] + zi["dtb_size"] > len(z):
        raise StageError("appended DTB is truncated (totalsize %d, %d bytes present)"
                         % (zi["dtb_size"], len(z) - zi["dtb_at"]))
    return zi


def kernel_partition(current, z, lay, key):
    require_dtb(z)
    if len(z) > lay["kernel_len"]:
        raise StageError("image is %d bytes, this unit's U-Boot reads %d" % (len(z), lay["kernel_len"]))
    so = lay["staging"] - KERNEL
    if so + HEAD > len(current):
        raise StageError("staging blocks lie outside the kernel partition")
    part = bytearray(b"\xff" * len(current))
    part[:HEAD] = current[:HEAD]
    part[HEAD:len(z)] = z[HEAD:]
    for i in range(3):
        part[so + i * ERASE:so + (i + 1) * ERASE] = key.encrypt(z[i * ERASE:(i + 1) * ERASE])
    return bytes(part)


# --------------------------------------------------------------------------- report / CLI

def sha(b):
    return hashlib.sha256(b).hexdigest()


def plan(mtd0, cur, z, fuses, out=sys.stdout):
    p = lambda *a: print(*a, file=out)
    if len(mtd0) not in (0x30000, 0x40000):
        raise StageError("uboot dump is %#x bytes; expected 0x40000 (vendor map) or 0x30000 (ours)" % len(mtd0))
    if len(cur) != KERNEL_PART:
        raise StageError("kernel dump is %#x bytes, not %#x" % (len(cur), KERNEL_PART))
    key = UpgKey(*fuses)
    env = read_env(mtd0[UPDATE_BLOCK:UPDATE_BLOCK + ERASE], key)
    p("update env: decrypted with this unit's key, gzip OK, both CRCs OK (%d variables)" % len(env_vars(env)))
    lay = layout(env, len(cur))
    so = lay["staging"] - KERNEL
    p("layout: kernel_len=%#x staging=%#x (partition offset %#x) convert pairs=%s"
      % (lay["kernel_len"], lay["staging"], so, [(hex(a), hex(b)) for a, b in lay["pairs"]]))
    zi = require_dtb(z)
    p("image: %d bytes sha256 %s; zImage proper %d bytes; appended DTB at %#x, totalsize %d"
      % (len(z), sha(z), zi["zimage_len"], zi["dtb_at"], zi["dtb_size"]))
    p("headroom under kernel_len: %d bytes" % (lay["kernel_len"] - len(z)))
    if lay["kernel_len"] != KERNEL_MAX:
        p("NOTE: this unit's U-Boot reads %#x, not the %#x the baseline budget assumes" % (lay["kernel_len"], KERNEL_MAX))
    part = kernel_partition(cur, z, lay, key)
    unchanged = part == cur
    p("plan.unchanged (kernel partition already holds this): %s" % unchanged)
    if not unchanged:
        regions = {"head(0..0x2ffff)": 0, "body": 0, "staging": 0, "tail/other": 0}
        first = last = None
        for i in range(len(cur)):
            if part[i] != cur[i]:
                first = i if first is None else first
                last = i
                if i < HEAD:
                    regions["head(0..0x2ffff)"] += 1
                elif i < lay["kernel_len"]:
                    regions["body"] += 1
                elif so <= i < so + HEAD:
                    regions["staging"] += 1
                else:
                    regions["tail/other"] += 1
        p("differing bytes: %d first at %#x last at %#x %s" % (sum(regions.values()), first, last, regions))
    if len(mtd0) >= ENV_BLOCK + ERASE:
        envblk = mtd0[ENV_BLOCK:ENV_BLOCK + ERASE]
        nff = sum(1 for b in envblk if b != 0xFF)
        p("uboot dump env block @%#x: %s" % (ENV_BLOCK, "all 0xFF" if nff == 0 else "holds data (%d non-FF bytes)" % nff))
    p("head [0,0x30000) of the plan == head of the current kernel dump: %s (flash-kernel checks this on the unit)"
      % (part[:HEAD] == cur[:HEAD]))
    p("sha256(current kernel) = %s" % sha(cur))
    p("sha256(planned kernel) = %s" % sha(part))
    return part, unchanged


def self_test():
    fails = []

    def check(name, cond):
        print("  %-62s %s" % (name, "ok" if cond else "FAIL"))
        if not cond:
            fails.append(name)

    def raises(fn):
        try:
            fn()
        except (StageError, ValueError):
            return True
        return False

    print("self-test (synthetic data only, no unit identity)")
    # FIPS-197 C.1 and SP 800-38A F.2.1/F.2.2
    a = AES128(bytes.fromhex("000102030405060708090a0b0c0d0e0f"))
    ct = a.encrypt_block(bytes.fromhex("00112233445566778899aabbccddeeff"))
    check("AES-128 FIPS-197 C.1 encrypt", ct.hex() == "69c4e0d86a7b0430d8cdb78070b4c55a")
    check("AES-128 FIPS-197 C.1 decrypt", a.decrypt_block(ct).hex() == "00112233445566778899aabbccddeeff")
    k = AES128(bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c"))
    iv = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    pt = bytes.fromhex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51")
    c = cbc_encrypt(k, iv, pt)
    check("CBC SP800-38A F.2.1 (two blocks)", c.hex() == "7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2")
    check("CBC SP800-38A F.2.2 decrypt", cbc_decrypt(k, iv, c) == pt)

    FUSES = (0x0123ABCD, 0x89EF4567, 0xDEADBEEF, 1)    # LIVI's test constants, not a unit
    key = UpgKey(*FUSES)
    check("UpgKey is the fuse words in hex", key.key == b"0123abcd89ef4567" and key.iv == b"deadbeef00000001")
    nv = bytearray(0x100)
    for wi, val in ((1, FUSES[0]), (2, FUSES[1]), (0x22, FUSES[2]), (0x23, FUSES[3])):
        struct.pack_into("<I", nv, wi * 4, val)
    check("fuses read from OCOTP words 1,2,0x22,0x23", fuses_from_ocotp(bytes(nv)) == FUSES)
    check("short OCOTP dump refused", raises(lambda: fuses_from_ocotp(bytes(nv[:0x88]))))

    tmp = tempfile.mkdtemp(prefix="stage_kernel_selftest_")
    try:
        ui = os.path.join(tmp, "unit_info.txt")
        with open(ui, "w") as f:
            f.write("dev:    size   erasesize  name\nmtd0: 00040000 00010000 \"uboot\"\n")
            f.write("".join("0x%08x\n" % w for w in FUSES))
        check("unit_info parser: four 0x%08x lines", fuses_from_unit_info(ui) == FUSES)
        with open(ui, "a") as f:
            f.write("0x00000000\n")
        check("unit_info parser refuses five words", raises(lambda: fuses_from_unit_info(ui)))

        # ocbm-identity (device-side shell) must agree with usb_identity()
        idscript = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                 "..", "..", "common", "shared", "ocbm-identity"))
        shells = [s for s in ("dash", "sh") if shutil.which(s)]
        tools = all(shutil.which(t) for t in ("sha256sum", "hexdump", "dd"))
        want = usb_identity(FUSES[0], FUSES[1])
        if os.path.exists(idscript) and shells and tools:
            nvf = os.path.join(tmp, "nvmem")
            with open(nvf, "wb") as f:
                f.write(bytes(nv))
            # A sysfs-like nvmem: the kernel answers a read shorter than the 4-byte word with EINVAL
            # (drivers/nvmem/core.c bin_attr_nvmem_read). A plain file does not, which is how the
            # dd bs=1 bug passed this test and shipped (hardware 2026-10-20: every unit
            # OCBM-e3b0c44298fc). This dd stands in for that file: it refuses bs/ibs that are not
            # whole words for OCBM_NVMEM and passes everything else to the real dd.
            shim = os.path.join(tmp, "sysfs-bin")
            os.mkdir(shim)
            realdd = shutil.which("dd")
            with open(os.path.join(shim, "dd"), "w") as f:
                f.write("#!/bin/sh\n"
                        "nv=; small=\n"
                        "for a in \"$@\"; do case $a in\n"
                        "  if=%s) nv=1 ;;\n"
                        "  bs=* | ibs=*) v=${a#*=}; case $v in *[!0-9]*) small=1 ;; *) [ $((v %% 4)) -eq 0 ] && [ \"$v\" -ge 4 ] || small=1 ;; esac ;;\n"
                        "esac; done\n"
                        "if [ -n \"$nv\" ] && [ -n \"$small\" ]; then echo 'dd: error reading: Invalid argument' >&2; exit 1; fi\n"
                        "exec %s \"$@\"\n" % (nvf, realdd))
            os.chmod(os.path.join(shim, "dd"), 0o755)
            empty_sha_serial = "OCBM-" + hashlib.sha256(b"").hexdigest()[:12]
            for shname in shells:
                for label, path in (("plain file", os.environ.get("PATH", "")),
                                    ("sysfs-like word reads", shim + os.pathsep + os.environ.get("PATH", ""))):
                    run = os.path.join(tmp, "run-%s-%d" % (shname, len(label)))
                    env = dict(os.environ, OCBM_NVMEM=nvf, OCBM_CHIPID_OFFSET="4", OCBM_RUN=run, PATH=path)
                    r = subprocess.run([shname, idscript], env=env, capture_output=True, text=True)
                    got = {}
                    for n in ("serial", "dev_addr", "host_addr", "chip-id"):
                        pth = os.path.join(run, n)
                        got[n] = open(pth).read().strip() if os.path.exists(pth) else None
                    check("ocbm-identity under %s, %s: serial/MACs match" % (shname, label),
                          r.returncode == 0 and all(got[n] == want[n] for n in ("serial", "dev_addr", "host_addr")))
                    check("ocbm-identity under %s, %s: not sha256(\"\")" % (shname, label),
                          got["serial"] not in (None, empty_sha_serial))
                    check("ocbm-identity under %s, %s: chip-id is CFG0,CFG1 %%08x%%08x" % (shname, label),
                          got["chip-id"] == "%08x%08x" % (FUSES[0], FUSES[1]))
                # A source that yields nothing must be refused loudly, writing no identity.
                emptyf = os.path.join(tmp, "nvmem-empty")
                open(emptyf, "wb").close()
                run = os.path.join(tmp, "run-empty-" + shname)
                r = subprocess.run([shname, idscript], capture_output=True, text=True,
                                   env=dict(os.environ, OCBM_NVMEM=emptyf, OCBM_RUN=run))
                check("ocbm-identity under %s refuses an empty read (no serial written)" % shname,
                      r.returncode != 0 and not os.path.exists(os.path.join(run, "serial")) and "read 0 of 8" in r.stderr)
        else:
            print("  ocbm-identity cross-check SKIPPED (script, dash/sh, sha256sum, hexdump or dd missing)")
        mm = usb_identity(FUSES[0], FUSES[1])
        check("serial shape OCBM-<12 hex>, MACs locally administered unicast",
              re.fullmatch(r"OCBM-[0-9a-f]{12}", mm["serial"]) is not None
              and all((int(m[:2], 16) & 3) == 2 for m in (mm["dev_addr"], mm["host_addr"])))
        check("serial does not contain the raw fuse words",
              "%08x" % FUSES[0] not in mm["serial"] and "%08x" % FUSES[1] not in mm["serial"])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    def env_with(vars_):
        env = bytearray(ENV_SIZE)
        text = "\0".join(vars_).encode()
        env[4:4 + len(text)] = text
        env[0x800:0x804] = struct.pack(">I", 0xD00DFEED)
        env[0x804:ENV_CRC2_AT] = b"\xff" * (ENV_CRC2_AT - 0x804)
        env[:4] = struct.pack("<I", zlib.crc32(bytes(env[4:ENV_VARS_END])))
        env[ENV_CRC2_AT:] = struct.pack("<I", zlib.crc32(bytes(env[:ENV_CRC2_AT])))
        return bytes(env)

    def update_block(env, k_):
        co = zlib.compressobj(9, zlib.DEFLATED, 16 + zlib.MAX_WBITS)
        payload = bytearray(co.compress(env) + co.flush())
        payload += b"\0" * (-len(payload) % 0x1000)
        payload = bytearray(k_.encrypt(bytes(payload)))
        blk = bytearray(b"\x5a" * ERASE)
        blk[ERASE - len(payload):] = payload
        blk[ERASE - 4:] = struct.pack("<I", len(payload))
        return bytes(blk)

    def vendor_env(kl):
        norboot = ["run norargs", "sf probe 0", "cp 0x80800800 0x83000000 0xf800",
                   "sf read 0x80800000 0x40000 %#x" % kl, "mm w 0x80800000 0x10000",
                   "mm w 0x80810000 0x10000", "mm w 0x80820000 0x10000", "bootz 0x80800000 - 0x83000000"]
        hewei = ["sf probe 0"]
        for i in range(3):
            hewei += ["sf read 0x80800000 %#x 0x10000" % (KERNEL + kl + i * ERASE), "mm d 0x80800000 0x10000",
                      "mm m 0x80800000 0x10000", "sf update 0x80800000 %#x  0x10000" % (KERNEL + i * ERASE)]
        hewei += [" sf probe 0", "sf read 0x80810000 0x2d000 0x3000", "mm d 0x80810000 0x3000",
                  "mm z 0x80810000 0x2ff0 0x80800000 0x10000", "mm m 0x80800000 0x10000",
                  "sf update 0x80800000 0x30000  0x10000"]
        return env_with(["bootdelay=3", "norboot=%s;" % ";".join(norboot), "heweiencrypt=%s;" % ";".join(hewei)])

    DTB = struct.pack(">II", FDT_MAGIC, 0x40) + bytes(0x38)

    def zimage(n, dtb=DTB):
        zz = bytearray(((i * 7 + i // 251) & 0xFF) for i in range(n))
        struct.pack_into("<I", zz, 0x24, ZIMAGE_MAGIC)
        struct.pack_into("<II", zz, 0x28, 0, n)
        return bytes(zz) + dtb

    venv = vendor_env(0x302FD8)
    check("update env unpacks and checks its CRC", read_env(update_block(venv, key), key) == venv)
    bad = bytearray(venv)
    bad[0x10] ^= 1
    check("corrupted env fails its CRC", raises(lambda: read_env(update_block(bytes(bad), key), key)))
    # B12: a byte outside the first CRC's range (the FDT area) or a wrong stored second CRC is refused,
    # with the first CRC still right
    for at, what in ((0x9000, "FDT area"), (ENV_CRC2_AT, "stored second CRC"), (0x800, "FDT magic")):
        bad2 = bytearray(venv)
        bad2[at] ^= 0x40
        check("env with a bad byte in the %s fails the second CRC (first CRC intact)" % what,
              zlib.crc32(bytes(bad2[4:ENV_VARS_END])) == struct.unpack("<I", bytes(bad2[:4]))[0]
              and raises(lambda: read_env(update_block(bytes(bad2), key), key)))
    try:
        read_env(update_block(bytes(bad2), key), key)
        msg2 = ""
    except StageError as e:
        msg2 = str(e)
    check("the refusal names the second CRC", "second CRC" in msg2)
    other = UpgKey(FUSES[0], FUSES[1], FUSES[2], 2)
    check("wrong key is refused", raises(lambda: read_env(update_block(venv, key), other)))
    lay = layout(venv, KERNEL_PART)
    check("layout from norboot + heweiencrypt", (lay["kernel_len"], lay["staging"]) == (0x302FD8, 0x342FD8))
    check("layout outside the partition refused", raises(lambda: layout(venv, 0x320000)))
    check("norboot without kernel read refused", raises(lambda: layout(env_with(["norboot=bootz 0x80800000"]), KERNEL_PART)))

    cur = bytes((i % 13) for i in range(KERNEL_PART))
    z = zimage(0x2F0001)
    lay2 = {"kernel_len": 0x300000, "staging": 0x340000, "pairs": []}
    part = kernel_partition(cur, z, lay2, key)
    check("head kept from current", part[:HEAD] == cur[:HEAD])
    check("body is the zImage after the head", part[HEAD:len(z)] == z[HEAD:])
    check("gap after the zImage is 0xFF", set(part[len(z):0x300000]) == {0xFF})
    staged = b"".join(key.decrypt(part[0x300000 + i * ERASE:0x300000 + (i + 1) * ERASE]) for i in range(3))
    check("staged blocks decrypt (fresh IV per 64 KiB) to the zImage head", staged == z[:HEAD])
    check("after the staging blocks is 0xFF", set(part[0x330000:]) == {0xFF})
    check("zImage U-Boot would cut off is refused",
          raises(lambda: kernel_partition(cur, zimage(0x100001), {"kernel_len": 0x100000, "staging": 0x140000}, key)))
    check("non-zImage refused", raises(lambda: kernel_partition(cur, bytes(0x100000), lay2, key)))
    check("image without an appended DTB refused (vendor FDT would take over)",
          raises(lambda: kernel_partition(cur, zimage(0x2F0001, b""), lay2, key)))
    check("image with a truncated appended DTB refused",
          raises(lambda: kernel_partition(cur, zimage(0x2F0001, DTB[:0x20]), lay2, key)))

    uboot = bytearray(b"\x5a" * 0x40000)
    uboot[UPDATE_BLOCK:UPDATE_BLOCK + ERASE] = update_block(venv, key)
    zd = zimage(0x2F0001)
    sink = open(os.devnull, "w")
    try:
        p1, unch = plan(bytes(uboot), cur, zd, FUSES, out=sink)
        check("plan() from a uboot dump equals kernel_partition()",
              p1 == kernel_partition(cur, zd, layout(venv, KERNEL_PART), key) and not unch)
        check("plan() is a fixed point (re-staging the planned partition: unchanged)",
              plan(bytes(uboot), p1, zd, FUSES, out=sink)[1])
        check("appended DTB detected", zimage_info(zd)["dtb_at"] == 0x2F0001)
        check("plan() refuses another unit's key", raises(lambda: plan(bytes(uboot), cur, zd, (1, 2, 3, 4), out=sink)))
        check("plan() refuses an image without an appended DTB",
              raises(lambda: plan(bytes(uboot), cur, zimage(0x2F0001, b""), FUSES, out=sink)))
    finally:
        sink.close()

    if shutil.which("openssl"):
        r = subprocess.run(["openssl", "enc", "-aes-128-cbc", "-nopad", "-K", "2b7e151628aed2a6abf7158809cf4f3c",
                            "-iv", "000102030405060708090a0b0c0d0e0f"], input=pt, capture_output=True)
        check("pure-Python CBC == openssl CLI (test vector key)", r.returncode == 0 and r.stdout == c)
    print("self-test: %s" % ("PASS" if not fails else "FAIL (%d): %s" % (len(fails), ", ".join(fails))))
    return 0 if not fails else 1


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mtd0", help="dump of the uboot partition (0x40000 vendor map or 0x30000 ours)")
    ap.add_argument("--mtd1", help="dump of the CURRENT kernel partition (0x340000)")
    ap.add_argument("--full", help="16 MiB whole-chip dump instead of --mtd0/--mtd1")
    ap.add_argument("--zimage", help="new image: zImage with the DTB appended")
    ap.add_argument("--unit-info", help="file with exactly four lines 0x%%08x: CFG0 CFG1 MAC0 MAC1")
    ap.add_argument("--ocotp-nvmem", help="raw dump of /sys/bus/nvmem/devices/imx-ocotp0/nvmem")
    ap.add_argument("--out", help="write the planned kernel partition image here")
    ap.add_argument("--expect-planned-sha256", help="fail unless the planned partition has this sha256")
    ap.add_argument("--print-usb-identity", action="store_true",
                    help="print the iSerial and NCM MACs the device derives (no flashing data needed)")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args(argv)
    if a.self_test:
        return self_test()
    try:
        if bool(a.unit_info) == bool(a.ocotp_nvmem):
            raise StageError("give exactly one of --unit-info / --ocotp-nvmem")
        if a.unit_info:
            fuses = fuses_from_unit_info(a.unit_info)
            src = a.unit_info
        else:
            fuses = fuses_from_ocotp(open(a.ocotp_nvmem, "rb").read())
            src = a.ocotp_nvmem
        print("fuses: 4 OCOTP words read from %s (values not printed)" % src)
        if a.print_usb_identity:
            ident = usb_identity(fuses[0], fuses[1])
            for k_ in ("serial", "dev_addr", "host_addr"):
                print("%s = %s" % (k_, ident[k_]))
            return 0
        if a.full:
            if a.mtd0 or a.mtd1:
                raise StageError("--full replaces --mtd0/--mtd1")
            full = open(a.full, "rb").read()
            if len(full) != 0x1000000:
                raise StageError("--full dump is %d bytes, not 16 MiB" % len(full))
            mtd0, cur = full[:KERNEL], full[KERNEL:KERNEL + KERNEL_PART]
        else:
            if not (a.mtd0 and a.mtd1):
                raise StageError("need --mtd0 and --mtd1 (or --full)")
            mtd0, cur = open(a.mtd0, "rb").read(), open(a.mtd1, "rb").read()
        if not a.zimage:
            raise StageError("need --zimage")
        z = open(a.zimage, "rb").read()
        part, _ = plan(mtd0, cur, z, fuses)
        if a.expect_planned_sha256 and sha(part) != a.expect_planned_sha256.lower():
            raise StageError("planned sha256 %s != expected %s" % (sha(part), a.expect_planned_sha256))
        if a.out:
            tmp = a.out + ".tmp"
            with open(tmp, "wb") as f:
                f.write(part)
            os.replace(tmp, a.out)
            print("wrote %s (%d bytes); on the unit: flash-kernel <image> %s" % (a.out, len(part), sha(part)))
        return 0
    except (StageError, OSError) as e:
        print("stage_kernel: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

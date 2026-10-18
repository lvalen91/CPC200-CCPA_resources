#!/usr/bin/env python3
"""Locate the decompressor stub + map the packer container of ARMiPhoneIAP2.packed."""
import math, struct
from collections import Counter

data = open('ARMiPhoneIAP2.packed', 'rb').read()
N = len(data)

def ent(b):
    if not b:
        return 0.0
    c = Counter(b); n = len(b)
    return -sum((v/n) * math.log2(v/n) for v in c.values())

def arm_ratio(b):
    """fraction of 4-byte words with top nibble 0xE (ARM 'always' cond) — code heuristic"""
    if len(b) < 4:
        return 0.0
    w = len(b) // 4
    cnt = sum(1 for i in range(0, w*4, 4) if (b[i+3] & 0xF0) == 0xE0)
    return cnt / w

print(f"=== ARMiPhoneIAP2.packed : {N} bytes (0x{N:x}) ===\n")

W = 512
line = ''
for i in range(0, N, W):
    e = ent(data[i:i+W])
    line += ' ' if e > 7.5 else '.' if e > 6.0 else ':' if e > 4.0 else '#'
print(f"entropy map, {W}B/cell  (' '>7.5 compressed  '.'6-7.5  ':'4-6  '#'<4 code-ish):")
for j in range(0, len(line), 64):
    print(f"  0x{j*W:06x}  {line[j:j+64]}")

print("\nlow-entropy regions (<=7.0 — candidate plaintext stub / headers):")
i = 0
while i < N:
    if ent(data[i:i+W]) <= 7.0:
        s = i
        while i < N and ent(data[i:i+W]) <= 7.0:
            i += W
        seg = data[s:min(i, N)]
        print(f"  0x{s:06x}-0x{min(i,N):06x}  {len(seg):6d}B  ent={ent(seg):.2f}  arm_code_ratio={arm_ratio(seg):.2f}")
    else:
        i += W

eo = 0x3aebc - 0x10000
print(f"\nELF entry 0x3aebc -> file offset 0x{eo:x}")
print(f"  arm_code_ratio of 0x{eo:x}..+256 = {arm_ratio(data[eo:eo+256]):.2f}")
print(f"  first 32B at entry: {data[eo:eo+32].hex()}")

def dump(off, length, label):
    off = max(0, off)
    print(f"\n=== {label}  (file 0x{off:x}, {length}B) ===")
    for i in range(off, min(off+length, N), 16):
        row = data[i:i+16]
        hx = ' '.join(f'{b:02x}' for b in row)
        ws = ' '.join(f'{struct.unpack_from("<I", data, i+k)[0]:08x}'
                       for k in range(0, 16, 4) if i+k+4 <= N)
        txt = ''.join(chr(b) if 32 <= b < 127 else '.' for b in row)
        print(f"  {i:06x}: {hx:<47} |{txt:<16}| {ws}")

dump(0x80, 0x70, "HEAD container area (after ELF hdr + 3 phdrs)")
dump(N - 0x60, 0x60, "TAIL container area")

# scan for every 55 22 55 22 marker
marks = [i for i in range(N-3) if data[i:i+4] == b'\x55\x22\x55\x22']
print(f"\n'55 22 55 22' markers at: {[hex(m) for m in marks]}")

#!/usr/bin/env python3
"""
build_persist.py -- persistent on-disk patch of the UNPACKED ARMiPhoneIAP2.

Input : ARMiPhoneIAP2.unpacked (494244 B, md5 f1e1a0aa..., from modified_upx_arm -d)
Output: ARMiPhoneIAP2.patched  (same size; ready for modified_upx_arm --best repack)

The proven Trial-3 trampolines, rebased into the file-backed inter-segment gap:
  Stage 2 @ vaddr 0x86b38 (file 0x76b38)  -- 0x5201 _iap2 + 0x5202 burst _iap2m
  Stage 1 @ vaddr 0x86c80 (file 0x76c80)  -- append-the-burst capture
ph3 (R-X LOAD, file 0..0x76b38) is extended by 496 B to 0x76d28 so the
trampolines become file-backed executable code.  Hooks: B@0x2d1c8 -> Stage1,
BL@0x2d454 -> Stage2.  .bss buffers 0x99200/0x99E00 auto-zero at load.
"""
import struct, hashlib

# ---- addresses in the unpacked binary (== decompressed runtime image) ----
MALLOC   = 0x134e8
FREE     = 0x12f18
SEND_NAV = 0x2c9d0
CJSON    = 0x69b35          # cJSON_AddStringToObject | 1 (Thumb)
GLOBAL   = 0x00099E00       # globals base: +0x110/+0x114/+0x118
BURST    = 0x00099200       # 0x5202 burst buffer (cap 0x700)
RET      = 0x0002d1cc       # virtual_8, instruction after prologue

STAGE2_BASE = 0x86b38       # file 0x76b38
STAGE1_BASE = 0x86c80       # file 0x76c80
HOOK1_VA    = 0x2d1c8       # virtual_8 entry
HOOKA_VA    = 0x2d454       # Hook A

def w(v): return struct.pack('<I', v & 0xFFFFFFFF)
def bl_off(frm, to): return ((to - (frm + 8)) >> 2) & 0x00FFFFFF

# ============================ STAGE 2 (328 B) ============================
def build_stage2(B):
    def A(o): return B + o
    c = bytearray()
    c += w(0xE92D4FF0)                                  # 00 push {r4-r11,lr}
    c += w(0xE1A0B000)                                  # 04 mov r11,r0
    c += w(0xE59FA104)                                  # 08 ldr r10,[pc,#0x104]
    c += w(0xE59F7104)                                  # 0C ldr r7,[pc,#0x104]
    c += w(0xE59A8110)                                  # 10 ldr r8,[r10,#0x110]
    c += w(0xE3580000)                                  # 14 cmp r8,#0
    c += w(0x0A000000 | bl_off(A(0x18), A(0x8C)))       # 18 beq check_5202
    c += w(0xE59A9114)                                  # 1C ldr r9,[r10,#0x114]
    c += w(0xE2884009)                                  # 20 add r4,r8,#9
    c += w(0xE2495009)                                  # 24 sub r5,r9,#9
    c += w(0xE1A00085)                                  # 28 mov r0,r5,lsl#1
    c += w(0xE2800004)                                  # 2C add r0,r0,#4
    c += w(0xEB000000 | bl_off(A(0x30), MALLOC))        # 30 bl malloc
    c += w(0xE1A06000)                                  # 34 mov r6,r0
    c += w(0xE1A00004)                                  # 38 mov r0,r4
    c += w(0xE1A01005)                                  # 3C mov r1,r5
    c += w(0xE1A02006)                                  # 40 mov r2,r6
    c += w(0xE4D03001)                                  # 44 ldrb r3,[r0],#1
    c += w(0xE1A04223)                                  # 48 mov r4,r3,lsr#4
    c += w(0xE7D74004)                                  # 4C ldrb r4,[r7,r4]
    c += w(0xE4C24001)                                  # 50 strb r4,[r2],#1
    c += w(0xE203400F)                                  # 54 and r4,r3,#0xF
    c += w(0xE7D74004)                                  # 58 ldrb r4,[r7,r4]
    c += w(0xE4C24001)                                  # 5C strb r4,[r2],#1
    c += w(0xE2511001)                                  # 60 subs r1,r1,#1
    c += w(0xCA000000 | bl_off(A(0x64), A(0x44)))       # 64 bgt loop_5201
    c += w(0xE3A03000)                                  # 68 mov r3,#0
    c += w(0xE5C23000)                                  # 6C strb r3,[r2]
    c += w(0xE1A0000B)                                  # 70 mov r0,r11
    c += w(0xE59F10A0)                                  # 74 ldr r1,[pc,#0xA0]
    c += w(0xE1A02006)                                  # 78 mov r2,r6
    c += w(0xE59F30A0)                                  # 7C ldr r3,[pc,#0xA0]
    c += w(0xE12FFF33)                                  # 80 blx r3
    c += w(0xE1A00006)                                  # 84 mov r0,r6
    c += w(0xEB000000 | bl_off(A(0x88), FREE))          # 88 bl free
    c += w(0xE59A5118)                                  # 8C ldr r5,[r10,#0x118]
    c += w(0xE3550000)                                  # 90 cmp r5,#0
    c += w(0x0A000000 | bl_off(A(0x94), A(0xFC)))       # 94 beq do_send
    c += w(0xE1A00085)                                  # 98 mov r0,r5,lsl#1
    c += w(0xE2800004)                                  # 9C add r0,r0,#4
    c += w(0xEB000000 | bl_off(A(0xA0), MALLOC))        # A0 bl malloc
    c += w(0xE1A06000)                                  # A4 mov r6,r0
    c += w(0xE24A0C0C)                                  # A8 sub r0,r10,#0xC00  (-> 0x99200)
    c += w(0xE1A01005)                                  # AC mov r1,r5
    c += w(0xE1A02006)                                  # B0 mov r2,r6
    c += w(0xE4D03001)                                  # B4 ldrb r3,[r0],#1
    c += w(0xE1A04223)                                  # B8 mov r4,r3,lsr#4
    c += w(0xE7D74004)                                  # BC ldrb r4,[r7,r4]
    c += w(0xE4C24001)                                  # C0 strb r4,[r2],#1
    c += w(0xE203400F)                                  # C4 and r4,r3,#0xF
    c += w(0xE7D74004)                                  # C8 ldrb r4,[r7,r4]
    c += w(0xE4C24001)                                  # CC strb r4,[r2],#1
    c += w(0xE2511001)                                  # D0 subs r1,r1,#1
    c += w(0xCA000000 | bl_off(A(0xD4), A(0xB4)))       # D4 bgt loop_5202
    c += w(0xE3A03000)                                  # D8 mov r3,#0
    c += w(0xE5C23000)                                  # DC strb r3,[r2]
    c += w(0xE1A0000B)                                  # E0 mov r0,r11
    c += w(0xE59F1034)                                  # E4 ldr r1,[pc,#0x34]
    c += w(0xE1A02006)                                  # E8 mov r2,r6
    c += w(0xE59F3030)                                  # EC ldr r3,[pc,#0x30]
    c += w(0xE12FFF33)                                  # F0 blx r3
    c += w(0xE1A00006)                                  # F4 mov r0,r6
    c += w(0xEB000000 | bl_off(A(0xF8), FREE))          # F8 bl free
    c += w(0xE1A0000B)                                  # FC mov r0,r11
    c += w(0xEB000000 | bl_off(A(0x100), SEND_NAV))     # 100 bl _SendNaviJSON
    c += w(0xE3A00000)                                  # 104 mov r0,#0
    c += w(0xE58A0110)                                  # 108 str r0,[r10,#0x110]
    c += w(0xE58A0114)                                  # 10C str r0,[r10,#0x114]
    c += w(0xE8BD8FF0)                                  # 110 pop {r4-r11,pc}
    c += w(GLOBAL)                                      # 114 pool: globals base
    c += w(A(0x128))                                    # 118 pool: hex table
    c += w(A(0x138))                                    # 11C pool: "_iap2"
    c += w(A(0x13E))                                    # 120 pool: "_iap2m"
    c += w(CJSON)                                       # 124 pool: cJSON_AddString
    c += b"0123456789abcdef"                            # 128
    c += b"_iap2\x00"                                   # 138
    c += b"_iap2m\x00"                                  # 13E
    while len(c) % 4:
        c.append(0)
    assert len(c) == 0x148, f"stage2 {len(c):#x}"
    return bytes(c)

# ============================ STAGE 1 (168 B) ============================
def build_stage1(B):
    RETv = RET
    POOL_GLOB, POOL_BURST = 0xA0, 0xA4
    def br(cond, at, to):
        a = B + at
        t = (B + to) if to >= 0 else RETv
        return (cond << 24) | (((t - (a + 8)) >> 2) & 0xFFFFFF)
    def ldr_pc(rd, at, pool):
        imm = pool - (at + 8)
        assert 0 <= imm < 4096 and imm % 4 == 0
        return 0xE59F0000 | (rd << 12) | imm
    LAYOUT = [
     (0x00, 0xE5D1C00D), (0x04, 0xE35C0052), (0x08, ('b',0x1A,0x98)),
     (0x0C, 0xE5D1C00E), (0x10, 0xE35C0001), (0x14, ('b',0x0A,0x24)),
     (0x18, 0xE35C0002), (0x1C, ('b',0x0A,0x44)), (0x20, ('b',0xEA,0x98)),
     (0x24, ldr_pc(12,0x24,POOL_GLOB)), (0x28, 0xE58C1110), (0x2C, 0xE92D43F0),
     (0x30, 0xE5D14002), (0x34, 0xE5D15003), (0x38, 0xE1854404),
     (0x3C, 0xE58C4114), (0x40, ('b',0xEA,-1)),
     (0x44, 0xE92D43F0), (0x48, ldr_pc(12,0x48,POOL_GLOB)), (0x4C, 0xE59C4118),
     (0x50, 0xE5D15002), (0x54, 0xE5D16003), (0x58, 0xE1865405),
     (0x5C, 0xE2455009), (0x60, 0xE3550000), (0x64, ('b',0xDA,0x94)),
     (0x68, 0xE0848005), (0x6C, 0xE3580C07), (0x70, ('b',0xCA,0x94)),
     (0x74, ldr_pc(6,0x74,POOL_BURST)), (0x78, 0xE0866004), (0x7C, 0xE2817009),
     (0x80, 0xE4D79001), (0x84, 0xE4C69001), (0x88, 0xE2555001),
     (0x8C, ('b',0xCA,0x80)), (0x90, 0xE58C8118), (0x94, ('b',0xEA,-1)),
     (0x98, 0xE92D43F0), (0x9C, ('b',0xEA,-1)),
     (0xA0, GLOBAL), (0xA4, BURST),
    ]
    c = bytearray()
    for off, enc in LAYOUT:
        assert off == len(c), f"stage1 gap {off:#x}"
        c += w(enc if isinstance(enc, int) else br(enc[1], off, enc[2]))
    assert len(c) == 0xA8, f"stage1 {len(c):#x}"
    return bytes(c)

# ============================ ELF PATCH ============================
s2 = build_stage2(STAGE2_BASE)
s1 = build_stage1(STAGE1_BASE)
open('stage2_persist.bin','wb').write(s2)
open('stage1_persist.bin','wb').write(s1)

elf = bytearray(open('ARMiPhoneIAP2.unpacked','rb').read())
assert len(elf) == 494244, f"unpacked size {len(elf)}"

# find ph3: LOAD, R+X, file offset 0
phoff, = struct.unpack_from('<I', elf, 0x1c)
phnum, = struct.unpack_from('<H', elf, 0x2c)
ph3 = None
for i in range(phnum):
    o = phoff + i*32
    t, off, va, pa, fs, ms, fl, al = struct.unpack_from('<8I', elf, o)
    if t == 1 and fl == 5 and off == 0:
        ph3 = (o, off, va, fs, ms)
assert ph3, "RX LOAD not found"
ph3_o, ph3_off, ph3_va, ph3_fs, ph3_ms = ph3
assert ph3_fs == 0x76b38 and ph3_ms == 0x76b38, f"ph3 size {ph3_fs:#x}"

S2_FOFF = STAGE2_BASE - 0x10000      # 0x76b38
S1_FOFF = STAGE1_BASE - 0x10000      # 0x76c80
NEW_END = S1_FOFF + len(s1)          # 0x76d28
H1_FOFF = HOOK1_VA - 0x10000         # 0x1d1c8
HA_FOFF = HOOKA_VA - 0x10000         # 0x1d454

# sanity: stock bytes at hook sites; trampoline region currently free
assert elf[H1_FOFF:H1_FOFF+4] == bytes.fromhex('f0432de9'), "Hook1 not stock"
assert elf[HA_FOFF:HA_FOFF+4] == bytes.fromhex('5dfdffeb'), "HookA not stock"
gap = elf[S2_FOFF:0x77000]
assert set(gap) <= {0}, f"inter-segment gap not all-zero ({sum(b!=0 for b in gap)} nonzero)"
assert NEW_END <= 0x77000, "trampolines overflow the gap"

# write trampolines
elf[S2_FOFF:S2_FOFF+len(s2)] = s2
elf[S1_FOFF:S1_FOFF+len(s1)] = s1
# extend ph3 filesz + memsz
struct.pack_into('<I', elf, ph3_o + 0x10, NEW_END)   # p_filesz
struct.pack_into('<I', elf, ph3_o + 0x14, NEW_END)   # p_memsz
# hooks
hook1 = 0xEA000000 | (((STAGE1_BASE - (HOOK1_VA + 8)) >> 2) & 0xFFFFFF)
hooka = 0xEB000000 | (((STAGE2_BASE - (HOOKA_VA + 8)) >> 2) & 0xFFFFFF)
elf[H1_FOFF:H1_FOFF+4] = w(hook1)
elf[HA_FOFF:HA_FOFF+4] = w(hooka)

assert len(elf) == 494244, "file size changed"
open('ARMiPhoneIAP2.patched','wb').write(elf)

# ============================ VERIFY ============================
v = open('ARMiPhoneIAP2.patched','rb').read()
t,off,va,fs,ms,fl,al = struct.unpack_from('<I', v, ph3_o)[0], *struct.unpack_from('<6I', v, ph3_o+4)
print("=== build_persist ===")
print(f"stage2 {len(s2)}B @0x{STAGE2_BASE:x}  md5 {hashlib.md5(s2).hexdigest()}")
print(f"stage1 {len(s1)}B @0x{STAGE1_BASE:x}  md5 {hashlib.md5(s1).hexdigest()}")
print(f"ph3 after patch: filesz=0x{fs:x} memsz=0x{ms:x}  (was 0x76b38, now 0x{NEW_END:x})")
print(f"Hook1 @0x{H1_FOFF:x} = {v[H1_FOFF:H1_FOFF+4].hex()}  (B  0x2d1c8->0x{STAGE1_BASE:x})")
print(f"HookA @0x{HA_FOFF:x} = {v[HA_FOFF:HA_FOFF+4].hex()}  (BL 0x2d454->0x{STAGE2_BASE:x})")
print(f"stage2[0]@0x{S2_FOFF:x} = {v[S2_FOFF:S2_FOFF+4].hex()}   stage1[0]@0x{S1_FOFF:x} = {v[S1_FOFF:S1_FOFF+4].hex()}")
print(f"patched size {len(v)}  md5 {hashlib.md5(v).hexdigest()}")
print("\nstage1 hex:")
for i in range(0,len(s1),16):
    print("  %04x: %s" % (i,' '.join('%02x'%b for b in s1[i:i+16])))
print("stage2 hex:")
for i in range(0,len(s2),16):
    print("  %04x: %s" % (i,' '.join('%02x'%b for b in s2[i:i+16])))

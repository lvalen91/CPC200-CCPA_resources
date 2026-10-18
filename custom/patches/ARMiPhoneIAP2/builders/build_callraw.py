#!/usr/bin/env python3
"""
build_callraw.py -- CALL-ENRICHMENT raw-passthrough patch for ARMiPhoneIAP2.

Forwards the WHOLE raw iAP2 CallStateUpdate (0x4155) message as one hex JSON
key "_callraw" appended to the subtype-100 CallState JSON -- exactly the way the
nav patch forwards "_iap2". The host (carlink_macOS CallManager) parses the full
iAP2 TLV, so the adapter no longer strips call/telephony fields.

Frame layout (verified from parser 0x17f48 + dispatcher 0x296cc):
  [0..1]  FF 5A link SOP
  [2..3]  total frame length, BE
  [4..8]  control/seq/ack/session/hdr-cksum  (9-byte link header)
  [9..a]  40 40  iAP2 message start marker
  [b..c]  message length BE
  [d..e]  message id BE  (0x4155 = CallStateUpdate)
  [f..]   parameters (TLV)
=> forward (len-9) bytes from frame+9  (matches nav "offset 9, len-9").

Two trampolines in the inter-segment code cave (file 0x76b38 / VMA 0x86b38):
  Stage 1  (hook 0x296cc, replaces `push {r4-r7,lr}`):
     run displaced push; save r1 + BE-len to bss GLOBAL; b 0x296d0.
  Stage 2  (hook 0x29960, replaces `blx 0x696d0` cJSON_PrintUnformatted):
     if ptr set: hex-encode payload, cJSON_AddStringToObject(r5,"_callraw",hex),
     free, clear ptr; then run displaced blx 0x696d0 and return r0 to 0x29964.

Scratch GLOBAL = fresh bss at 0x9A000 (LOAD1 memsz extended; collision-free,
beyond the program's original bss end 0x99f60). No new rodata constants beyond
the cave's own "_callraw" key + hex table.
"""
import struct, hashlib
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CS_MODE_THUMB

# ---- absolute targets in the binary (VMA = file_offset + 0x10000) ----
MALLOC   = 0x134e8       # bl  (ARM)   -- confirmed @0x29978
FREE     = 0x12f18       # bl  (ARM)   -- confirmed @0x299a8
ADDSTR   = 0x69b35       # blx r3      -- cJSON_AddStringToObject (thumb, 0x69b34|1)
PRINT    = 0x696d0       # blx (imm)   -- cJSON_PrintUnformatted (thumb), displaced
GLOBAL   = 0x9A000       # scratch bss: [+0]=frame ptr  [+4]=BE total len
HOOK1_VA = 0x296cc       # dispatcher entry: push {r4-r7,lr} = f0 40 2d e9
HOOK2_VA = 0x29960       # serialize: blx 0x696d0          = 5a ff 00 fa
RET1_VA  = 0x296d0       # instruction after the displaced push

def w(v): return struct.pack('<I', v & 0xFFFFFFFF)
def b_imm(frm, to):   return 0xEA000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def bl_imm(frm, to):  return 0xEB000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def beq_imm(frm, to): return 0x0A000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def ble_imm(frm, to): return 0xDA000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def bgt_imm(frm, to): return 0xCA000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def blx_imm(frm, to):
    d = to-(frm+8); return 0xFA000000 | (((d>>1)&1)<<24) | ((d>>2)&0xFFFFFF)
def ldr_pc(rd, at, pool):
    imm = pool-(at+8); assert 0 <= imm < 4096 and imm % 4 == 0, f"ldr_pc {imm:#x}"
    return 0xE59F0000 | (rd<<12) | imm

# ============================ STAGE 2 ============================
def build_stage2(B):
    POOL = 0xA0
    c = bytearray()
    def emit(words):
        for x in words: c.extend(w(x))
    A = lambda o: B+o
    # 0x00
    emit([0xE92D47F0])                          # push {r4,r5,r6,r7,r8,r9,r10,lr}
    c.extend(w(ldr_pc(8, 0x04, POOL+0x00)))     # 04 ldr r8,=GLOBAL
    emit([0xE5984000])                          # 08 ldr r4,[r8]      frame ptr
    emit([0xE3540000])                          # 0C cmp r4,#0
    c.extend(w(beq_imm(A(0x10), A(0x94))))      # 10 beq .done
    emit([0xE5980004])                          # 14 ldr r0,[r8,#4]   len
    emit([0xE2507009])                          # 18 subs r7,r0,#9    payload len
    c.extend(w(ble_imm(A(0x1C), A(0x8C))))      # 1C ble .clear
    emit([0xE2846009])                          # 20 add r6,r4,#9     src
    emit([0xE1A00087])                          # 24 mov r0,r7,lsl#1
    emit([0xE2800001])                          # 28 add r0,r0,#1
    c.extend(w(bl_imm(A(0x2C), MALLOC)))        # 2C bl malloc
    emit([0xE3500000])                          # 30 cmp r0,#0
    c.extend(w(beq_imm(A(0x34), A(0x8C))))      # 34 beq .clear
    emit([0xE1A04000])                          # 38 mov r4,r0        dst buf
    c.extend(w(ldr_pc(9, 0x3C, POOL+0x04)))     # 3C ldr r9,=hextab
    emit([0xE1A02004])                          # 40 mov r2,r4        write ptr
    # loop @0x44
    emit([0xE4D63001])                          # 44 ldrb r3,[r6],#1
    emit([0xE1A00223])                          # 48 mov r0,r3,lsr#4
    emit([0xE7D90000])                          # 4C ldrb r0,[r9,r0]
    emit([0xE4C20001])                          # 50 strb r0,[r2],#1
    emit([0xE203000F])                          # 54 and r0,r3,#0xf
    emit([0xE7D90000])                          # 58 ldrb r0,[r9,r0]
    emit([0xE4C20001])                          # 5C strb r0,[r2],#1
    emit([0xE2577001])                          # 60 subs r7,r7,#1
    c.extend(w(bgt_imm(A(0x64), A(0x44))))      # 64 bgt loop
    emit([0xE3A03000])                          # 68 mov r3,#0
    emit([0xE5C23000])                          # 6C strb r3,[r2]     NUL term
    emit([0xE1A00005])                          # 70 mov r0,r5        obj
    c.extend(w(ldr_pc(1, 0x74, POOL+0x08)))     # 74 ldr r1,=key
    emit([0xE1A02004])                          # 78 mov r2,r4        hex buf
    c.extend(w(ldr_pc(3, 0x7C, POOL+0x0C)))     # 7C ldr r3,=ADDSTR
    emit([0xE12FFF33])                          # 80 blx r3
    emit([0xE1A00004])                          # 84 mov r0,r4
    c.extend(w(bl_imm(A(0x88), FREE)))          # 88 bl free
    # .clear @0x8C
    emit([0xE3A03000])                          # 8C mov r3,#0
    emit([0xE5883000])                          # 90 str r3,[r8]      clear ptr
    # .done @0x94
    emit([0xE1A00005])                          # 94 mov r0,r5        obj for Print
    c.extend(w(blx_imm(A(0x98), PRINT)))        # 98 blx PrintUnformatted (displaced)
    emit([0xE8BD87F0])                          # 9C pop {r4,r5,r6,r7,r8,r9,r10,pc}
    assert len(c) == POOL, f"stage2 code {len(c):#x} != {POOL:#x}"
    # ---- literal pool @0xA0 ----
    emit([GLOBAL])                              # A0
    emit([B+0xB0])                              # A4 hextab ptr
    emit([B+0xC0])                              # A8 key ptr
    emit([ADDSTR])                              # AC
    c.extend(b"0123456789abcdef")               # B0..C0
    c.extend(b"_callraw\x00")                   # C0..C9
    while len(c) % 4: c.append(0)
    assert len(c) == 0xCC, f"stage2 size {len(c):#x}"
    return bytes(c)

# ============================ STAGE 1 ============================
def build_stage1(B):
    POOL = 0x20
    c = bytearray()
    A = lambda o: B+o
    def emit(words):
        for x in words: c.extend(w(x))
    emit([0xE92D40F0])                          # 00 push {r4,r5,r6,r7,lr}  (displaced)
    c.extend(w(ldr_pc(4, 0x04, POOL)))          # 04 ldr r4,=GLOBAL
    emit([0xE5841000])                          # 08 str r1,[r4]       frame ptr
    emit([0xE5D15002])                          # 0C ldrb r5,[r1,#2]   len hi
    emit([0xE5D16003])                          # 10 ldrb r6,[r1,#3]   len lo
    emit([0xE1865405])                          # 14 orr r5,r6,r5,lsl#8 BE len
    emit([0xE5845004])                          # 18 str r5,[r4,#4]
    c.extend(w(b_imm(A(0x1C), RET1_VA)))        # 1C b 0x296d0
    assert len(c) == POOL
    emit([GLOBAL])                              # 20 pool
    assert len(c) == 0x24
    return bytes(c)

# ============================ ELF PATCH ============================
S2_FOFF = 0x76b38
STAGE2_VA = 0x10000 + S2_FOFF
s2 = build_stage2(STAGE2_VA)
S1_FOFF = (S2_FOFF + len(s2) + 0xF) & ~0xF
STAGE1_VA = 0x10000 + S1_FOFF
s1 = build_stage1(STAGE1_VA)
END_FOFF = S1_FOFF + len(s1)
assert END_FOFF <= 0x77000, f"cave overflow {END_FOFF:#x}"

elf = bytearray(open('ARMiPhoneIAP2.unpacked', 'rb').read())
assert len(elf) == 494244
assert hashlib.md5(elf).hexdigest() == 'f1e1a0aa4d7fa6e639048c93475af9df'

# program headers
phoff, = struct.unpack_from('<I', elf, 0x1c)
phnum, = struct.unpack_from('<H', elf, 0x2c)
ph_rx = ph_rw = None
for i in range(phnum):
    o = phoff + i*32
    t, off, va, pa, fs, ms, fl, al = struct.unpack_from('<8I', elf, o)
    if t == 1 and fl == 5 and off == 0: ph_rx = o
    if t == 1 and fl == 6:              ph_rw = o
assert ph_rx is not None and ph_rw is not None
# guard: factory state
assert struct.unpack_from('<I', elf, ph_rx+0x10)[0] == 0x76b38, "LOAD0 filesz changed"
assert struct.unpack_from('<I', elf, ph_rw+0x08)[0] == 0x97000, "LOAD1 vaddr changed"
H1 = HOOK1_VA-0x10000; H2 = HOOK2_VA-0x10000
assert elf[H1:H1+4] == bytes.fromhex('f0402de9'), "hook1 bytes"
assert elf[H2:H2+4] == bytes.fromhex('5aff00fa'), "hook2 bytes"
assert set(elf[S2_FOFF:0x77000]) <= {0}, "cave not zero"

# write trampolines
elf[S2_FOFF:S2_FOFF+len(s2)] = s2
elf[S1_FOFF:S1_FOFF+len(s1)] = s1
# extend LOAD0 (R-X) to map the cave executable
struct.pack_into('<I', elf, ph_rx+0x10, END_FOFF)   # filesz
struct.pack_into('<I', elf, ph_rx+0x14, END_FOFF)   # memsz
# extend LOAD1 (RW) bss to cover GLOBAL=0x9A000 (+8). va=0x97000 -> need >=0x3008
NEW_RW_MEMSZ = 0x3010
struct.pack_into('<I', elf, ph_rw+0x14, NEW_RW_MEMSZ)
# install hooks
struct.pack_into('<I', elf, H1, b_imm(HOOK1_VA, STAGE1_VA))   # b stage1
struct.pack_into('<I', elf, H2, bl_imm(HOOK2_VA, STAGE2_VA))  # bl stage2
assert len(elf) == 494244

open('stage2_callraw.bin', 'wb').write(s2)
open('stage1_callraw.bin', 'wb').write(s1)
open('ARMiPhoneIAP2.callraw.patched', 'wb').write(elf)

# ============================ SELF-VERIFY (disassemble) ============================
print(f"stage2  {len(s2)} B @ {STAGE2_VA:#x}")
print(f"stage1  {len(s1)} B @ {STAGE1_VA:#x}  (END_FOFF {END_FOFF:#x})")
print(f"LOAD0 filesz/memsz -> {END_FOFF:#x} ; LOAD1 memsz -> {NEW_RW_MEMSZ:#x} (bss_end {0x97000+NEW_RW_MEMSZ:#x})")
print(f"hook1 @{H1:#x} = {elf[H1:H1+4].hex()}  (b {STAGE1_VA:#x})")
print(f"hook2 @{H2:#x} = {elf[H2:H2+4].hex()}  (bl {STAGE2_VA:#x})")
print(f"patched md5 {hashlib.md5(bytes(elf)).hexdigest()}")
md = Cs(CS_ARCH_ARM, CS_MODE_ARM)
for nm, blob, base in [("STAGE2", s2, STAGE2_VA), ("STAGE1", s1, STAGE1_VA)]:
    print(f"\n=== {nm} @ {base:#x} ===")
    code = blob[:(0xA0 if nm == "STAGE2" else 0x20)]
    for ins in md.disasm(code, base):
        print(f"  {ins.address:#x}: {ins.mnemonic:<9}{ins.op_str}")

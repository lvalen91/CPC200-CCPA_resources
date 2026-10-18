#!/usr/bin/env python3
"""
build_commraw.py -- Phase-2 COMMUNICATION-forward patch, layered ON TOP of the
call-enrichment patch (combined binary).

Forwards the raw iAP2 CommunicationUpdate (0x5702) frame to the host as a NEW
MetaData subtype-101 message whose content is the raw frame hex (host key
`_commraw`). Surfaces telephony extras the stock firmware never broadcasts
(NewVoicemailCount, missed/registration, SignalStrength, MuteStatus,
CurrentCallCount, CarrierName, FaceTime capability, …).

Handler (verified, 0x2b84c):
  push {r0-r6,lr}; mov r5,r0; mov r0,r1; bl 0x17f48(parse); movw r3,#0x5702; cmp;
  bne ... ; parses/logs locally — NO cJSON, NO BroadCast.
  r1 at entry = raw frame ptr (9-byte link header; total len = BE [2..3]; iAP2
  message at offset 9; msg id at [0xd..0xe] BE).

Single ENTRY hook: replace `push {r0-r6,lr}` (E92D407F) with `b commstage`.
commstage replays the push, saves r0/r1/r7-r9/lr, and IF [r1+0xd..0xe]==0x5702 AND a
cheap additive checksum of the payload differs from the last-seen (change-guard ->
no flood from repeated identical status frames): malloc(2*paylen+5), write 4-byte
subtype-101 header, hex-encode (len-9) bytes from frame+9, BroadCast, free; then
restores regs and `b 0x2b850` to continue the handler unchanged.

BroadCast 0x66e20 = THUMB (blx, as the CallState tail does at 0x299a0).
malloc 0x134e8 / free 0x12f18 = ARM (bl).
Base: ARMiPhoneIAP2.callraw.patched (md5 78c42712) -> ARMiPhoneIAP2.combined.patched.
"""
import struct, hashlib
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM

MALLOC=0x134e8; FREE=0x12f18; BROADCAST=0x66e20
GUARD=0x9A010
HOOK_VA=0x2b84c; RET_VA=0x2b850
STOCK_PUSH=bytes.fromhex('7f402de9')   # push {r0-r6,lr}

def w(v): return struct.pack('<I', v & 0xFFFFFFFF)
def cb(cond,frm,to): return (cond<<24)|(((to-(frm+8))>>2)&0xFFFFFF)
def b_imm(frm,to):   return cb(0xEA,frm,to)
def bl_imm(frm,to):  return cb(0xEB,frm,to)
def beq_imm(frm,to): return cb(0x0A,frm,to)
def bne_imm(frm,to): return cb(0x1A,frm,to)
def ble_imm(frm,to): return cb(0xDA,frm,to)
def bgt_imm(frm,to): return cb(0xCA,frm,to)
def blx_imm(frm,to):
    d=to-(frm+8); return 0xFA000000|(((d>>1)&1)<<24)|((d>>2)&0xFFFFFF)
def ldr_pc(rd,at,pool):
    imm=pool-(at+8); assert 0<=imm<4096 and imm%4==0, f"ldr_pc {imm:#x}"
    return 0xE59F0000|(rd<<12)|imm

def build_commstage(B):
    A=lambda o:B+o
    POOL=0xE0
    c=bytearray()
    def E(*words):
        for x in words: c.extend(w(x))
    E(0xE92D407F)                                  # 00 push {r0-r6,lr}     displaced
    E(0xE92D4383)                                  # 04 push {r0,r1,r7,r8,r9,lr}
    E(0xE1A07001)                                  # 08 mov  r7,r1          frame
    E(0xE5D7200D)                                  # 0C ldrb r2,[r7,#0xd]
    E(0xE5D7300E)                                  # 10 ldrb r3,[r7,#0xe]
    E(0xE1832402)                                  # 14 orr  r2,r3,r2,lsl#8 msgid
    E(0xE3053702)                                  # 18 movw r3,#0x5702
    E(0xE1520003)                                  # 1C cmp  r2,r3
    c.extend(w(bne_imm(A(0x20),A(0xD8))))          # 20 bne  .restore
    E(0xE5D72002)                                  # 24 ldrb r2,[r7,#2]
    E(0xE5D73003)                                  # 28 ldrb r3,[r7,#3]
    E(0xE1838402)                                  # 2C orr  r8,r3,r2,lsl#8 total len
    E(0xE2588009)                                  # 30 subs r8,r8,#9       paylen
    c.extend(w(ble_imm(A(0x34),A(0xD8))))          # 34 ble  .restore
    E(0xE2873009)                                  # 38 add  r3,r7,#9       ck src
    E(0xE1A02008)                                  # 3C mov  r2,r8          count
    E(0xE3A01000)                                  # 40 mov  r1,#0          sum
    E(0xE4D30001)                                  # 44 ldrb r0,[r3],#1   (.ck)
    E(0xE0811000)                                  # 48 add  r1,r1,r0
    E(0xE2522001)                                  # 4C subs r2,r2,#1
    c.extend(w(bgt_imm(A(0x50),A(0x44))))          # 50 bgt  .ck
    c.extend(w(ldr_pc(0,0x54,POOL+0)))             # 54 ldr  r0,=GUARD
    E(0xE5902000)                                  # 58 ldr  r2,[r0]
    E(0xE1510002)                                  # 5C cmp  r1,r2
    c.extend(w(beq_imm(A(0x60),A(0xD8))))          # 60 beq  .restore  (unchanged)
    E(0xE5801000)                                  # 64 str  r1,[r0]    store ck
    E(0xE1A00088)                                  # 68 mov  r0,r8,lsl#1
    E(0xE2800005)                                  # 6C add  r0,r0,#5
    c.extend(w(bl_imm(A(0x70),MALLOC)))            # 70 bl   malloc
    E(0xE3500000)                                  # 74 cmp  r0,#0
    c.extend(w(beq_imm(A(0x78),A(0xD8))))          # 78 beq  .restore
    E(0xE1A09000)                                  # 7C mov  r9,r0       buf
    E(0xE3A02065)                                  # 80 mov  r2,#0x65     subtype 101
    E(0xE4802004)                                  # 84 str  r2,[r0],#4   header
    E(0xE2873009)                                  # 88 add  r3,r7,#9     hex src
    E(0xE1A02008)                                  # 8C mov  r2,r8        count
    c.extend(w(ldr_pc(6,0x90,POOL+4)))             # 90 ldr  r6,=hextab
    E(0xE4D31001)                                  # 94 ldrb r1,[r3],#1  (.hx)
    E(0xE1A04221)                                  # 98 lsr  r4,r1,#4
    E(0xE7D64004)                                  # 9C ldrb r4,[r6,r4]
    E(0xE4C04001)                                  # A0 strb r4,[r0],#1
    E(0xE201400F)                                  # A4 and  r4,r1,#0xf
    E(0xE7D64004)                                  # A8 ldrb r4,[r6,r4]
    E(0xE4C04001)                                  # AC strb r4,[r0],#1
    E(0xE2522001)                                  # B0 subs r2,r2,#1
    c.extend(w(bgt_imm(A(0xB4),A(0x94))))          # B4 bgt  .hx
    E(0xE3A04000)                                  # B8 mov  r4,#0
    E(0xE5C04000)                                  # BC strb r4,[r0]      NUL
    E(0xE1A00009)                                  # C0 mov  r0,r9        buf
    E(0xE1A01088)                                  # C4 mov  r1,r8,lsl#1
    E(0xE2811005)                                  # C8 add  r1,r1,#5     total len
    c.extend(w(blx_imm(A(0xCC),BROADCAST)))        # CC blx  BroadCast
    E(0xE1A00009)                                  # D0 mov  r0,r9
    c.extend(w(bl_imm(A(0xD4),FREE)))              # D4 bl   free
    E(0xE8BD4383)                                  # D8 pop {r0,r1,r7,r8,r9,lr}  (.restore)
    c.extend(w(b_imm(A(0xDC),RET_VA)))             # DC b   0x2b850
    assert len(c)==POOL, f"comm code {len(c):#x} != {POOL:#x}"
    E(GUARD)                                       # E0 pool0
    E(B+0xE8)                                      # E4 pool1 hextab ptr
    c.extend(b"0123456789abcdef")                  # E8..F8
    while len(c)%4: c.append(0)
    assert len(c)==0xF8, f"comm size {len(c):#x}"
    return bytes(c)

# ===== ELF patch (layer onto the call-patched binary) =====
elf=bytearray(open('ARMiPhoneIAP2.callraw.patched','rb').read())
assert len(elf)==494244
assert hashlib.md5(elf).hexdigest()=='78c42712f08f14cb67f0da30dd8c030e', "base must be the call-patched ELF"

phoff,=struct.unpack_from('<I',elf,0x1c); phnum,=struct.unpack_from('<H',elf,0x2c)
ph_rx=ph_rw=None
for i in range(phnum):
    o=phoff+i*32
    t,off,va,pa,fs,ms,fl,al=struct.unpack_from('<8I',elf,o)
    if t==1 and fl==5 and off==0: ph_rx=o
    if t==1 and fl==6:            ph_rw=o
rx_filesz=struct.unpack_from('<I',elf,ph_rx+0x10)[0]
rw_memsz =struct.unpack_from('<I',elf,ph_rw+0x14)[0]
assert rx_filesz==0x76c34, f"unexpected call-patch R-X end {rx_filesz:#x}"
assert rw_memsz ==0x3010,  f"unexpected call-patch RW memsz {rw_memsz:#x}"

S_FOFF=(rx_filesz+0xF)&~0xF                  # 0x76c40
STAGE_VA=0x10000+S_FOFF
stage=build_commstage(STAGE_VA)
END_FOFF=S_FOFF+len(stage)
assert END_FOFF<=0x77000, f"cave overflow {END_FOFF:#x}"
# cave must still be zero where we write (incl the 0x76c34..0x76c40 align pad)
assert set(elf[rx_filesz:0x77000])<= {0}, "cave not zero"
H=HOOK_VA-0x10000
assert elf[H:H+4]==STOCK_PUSH, f"comm hook bytes {elf[H:H+4].hex()}"

elf[S_FOFF:S_FOFF+len(stage)]=stage
struct.pack_into('<I',elf,ph_rx+0x10,END_FOFF)   # R-X filesz
struct.pack_into('<I',elf,ph_rx+0x14,END_FOFF)   # R-X memsz
struct.pack_into('<I',elf,ph_rw+0x14,0x3020)     # RW memsz (covers GUARD 0x9A010+4)
struct.pack_into('<I',elf,H,b_imm(HOOK_VA,STAGE_VA))  # b commstage
assert len(elf)==494244
open('stage_commraw.bin','wb').write(stage)
open('ARMiPhoneIAP2.combined.patched','wb').write(elf)

print(f"commstage {len(stage)} B @ {STAGE_VA:#x} (file {S_FOFF:#x}); END {END_FOFF:#x}")
print(f"R-X filesz/memsz -> {END_FOFF:#x} ; RW memsz -> 0x3020")
print(f"comm hook @{H:#x} = {elf[H:H+4].hex()} (b {STAGE_VA:#x})")
print(f"combined md5 {hashlib.md5(bytes(elf)).hexdigest()}")
# self-verify
md=Cs(CS_ARCH_ARM,CS_MODE_ARM)
print(f"\n=== COMMSTAGE @ {STAGE_VA:#x} ===")
for ins in md.disasm(stage[:0xE0], STAGE_VA):
    print(f"  {ins.address:#x}: {ins.mnemonic:<8}{ins.op_str}")

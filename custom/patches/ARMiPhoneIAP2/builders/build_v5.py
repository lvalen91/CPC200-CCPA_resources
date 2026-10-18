#!/usr/bin/env python3
"""
build_v5.py -- persistent patch v5: 64 KB capture + EMIT-ONCE-PER-BURST.

v4 captured fine but re-broadcast the burst as _iap2m on every 0x5201 (~1/s) ->
with the 64 KB buffer that was ~96 KB/s -> adapter OOM + host freeze.

v5 keeps v4's capture verbatim (Stage 1 identical; 64 KB buffer at 0x9A000 in
extended .bss) and rewrites only Stage 2's emit:

  Stage 2 check_5202 -- "wait for settle, emit once":
    cur  = [0x99F18]  (running burst length, written by Stage 1)
    prev = [0x99F20]  (spare global, tracks last-seen cur)
    cur == 0          -> no burst            -> skip _iap2m
    cur != prev       -> burst still arriving -> save prev=cur, skip _iap2m
    cur == prev (>0)  -> burst settled        -> emit _iap2m ONCE, then
                                                 zero 0x99F18 AND 0x99F20

Result: _iap2m emitted exactly once per route-calc (not every second); no
mid-burst split (waits one cycle for arrival to finish); no accumulation
(zeroing 0x99F18 makes each burst reuse the buffer from offset 0).
"""
import struct, hashlib

MALLOC=0x134e8; FREE=0x12f18; SEND_NAV=0x2c9d0; CJSON=0x69b35
GLOBAL=0x00099E00; BURST=0x0009A000; RET=0x0002d1cc
HOOK1_VA=0x2d1c8; HOOKA_VA=0x2d454

def w(v): return struct.pack('<I', v & 0xFFFFFFFF)
def bl_off(frm,to): return ((to-(frm+8))>>2)&0x00FFFFFF

# ===================== STAGE 2 v5 (368 B) =====================
def build_stage2(B):
    def A(o): return B+o
    POOL=0x13C
    def pcrel(at,idx):
        imm=(POOL+4*idx)-(at+8)
        assert 0<=imm<4096 and imm%4==0, f"pcrel@{at:#x}={imm:#x}"
        return imm
    c=bytearray()
    c+=w(0xE92D4FF0)                              # 00 push {r4-r11,lr}
    c+=w(0xE1A0B000)                              # 04 mov r11,r0
    c+=w(0xE59FA000|pcrel(0x08,0))                # 08 ldr r10,[pc] GLOBAL
    c+=w(0xE59F7000|pcrel(0x0C,1))                # 0C ldr r7,[pc] hex_table
    c+=w(0xE59A8110)                              # 10 ldr r8,[r10,#0x110]
    c+=w(0xE3580000)                              # 14 cmp r8,#0
    c+=w(0x0A000000|bl_off(A(0x18),A(0x8C)))      # 18 beq check_5202
    c+=w(0xE59A9114)                              # 1C ldr r9,[r10,#0x114]
    c+=w(0xE2884009)                              # 20 add r4,r8,#9
    c+=w(0xE2495009)                              # 24 sub r5,r9,#9
    c+=w(0xE1A00085)                              # 28 mov r0,r5,lsl#1
    c+=w(0xE2800004)                              # 2C add r0,r0,#4
    c+=w(0xEB000000|bl_off(A(0x30),MALLOC))       # 30 bl malloc
    c+=w(0xE1A06000)                              # 34 mov r6,r0
    c+=w(0xE1A00004)                              # 38 mov r0,r4
    c+=w(0xE1A01005)                              # 3C mov r1,r5
    c+=w(0xE1A02006)                              # 40 mov r2,r6
    c+=w(0xE4D03001)                              # 44 ldrb r3,[r0],#1
    c+=w(0xE1A04223)                              # 48 mov r4,r3,lsr#4
    c+=w(0xE7D74004)                              # 4C ldrb r4,[r7,r4]
    c+=w(0xE4C24001)                              # 50 strb r4,[r2],#1
    c+=w(0xE203400F)                              # 54 and r4,r3,#0xF
    c+=w(0xE7D74004)                              # 58 ldrb r4,[r7,r4]
    c+=w(0xE4C24001)                              # 5C strb r4,[r2],#1
    c+=w(0xE2511001)                              # 60 subs r1,r1,#1
    c+=w(0xCA000000|bl_off(A(0x64),A(0x44)))      # 64 bgt loop_5201
    c+=w(0xE3A03000)                              # 68 mov r3,#0
    c+=w(0xE5C23000)                              # 6C strb r3,[r2]
    c+=w(0xE1A0000B)                              # 70 mov r0,r11
    c+=w(0xE59F1000|pcrel(0x74,2))                # 74 ldr r1,[pc] "_iap2"
    c+=w(0xE1A02006)                              # 78 mov r2,r6
    c+=w(0xE59F3000|pcrel(0x7C,4))                # 7C ldr r3,[pc] cJSON
    c+=w(0xE12FFF33)                              # 80 blx r3
    c+=w(0xE1A00006)                              # 84 mov r0,r6
    c+=w(0xEB000000|bl_off(A(0x88),FREE))         # 88 bl free
    # ---- check_5202 @0x8C : wait-for-settle ----
    c+=w(0xE59A5118)                              # 8C ldr r5,[r10,#0x118]  cur
    c+=w(0xE3550000)                              # 90 cmp r5,#0
    c+=w(0x0A000000|bl_off(A(0x94),A(0x124)))     # 94 beq do_send  (no burst)
    c+=w(0xE59A4120)                              # 98 ldr r4,[r10,#0x120]  prev
    c+=w(0xE1550004)                              # 9C cmp r5,r4
    c+=w(0x0A000000|bl_off(A(0xA0),A(0xAC)))      # A0 beq do_emit  (settled)
    c+=w(0xE58A5120)                              # A4 str r5,[r10,#0x120]  prev=cur
    c+=w(0xEA000000|bl_off(A(0xA8),A(0x124)))     # A8 b do_send    (still arriving)
    # ---- do_emit @0xAC ----
    c+=w(0xE3550A0C)                              # AC cmp r5,#0xC000   emit cap 48K
    c+=w(0x83A05A0C)                              # B0 movhi r5,#0xC000
    c+=w(0xE1A00085)                              # B4 mov r0,r5,lsl#1
    c+=w(0xE2800004)                              # B8 add r0,r0,#4
    c+=w(0xEB000000|bl_off(A(0xBC),MALLOC))       # BC bl malloc
    c+=w(0xE1A06000)                              # C0 mov r6,r0
    c+=w(0xE28A0C02)                              # C4 add r0,r10,#0x200  src 0x9A000
    c+=w(0xE1A01005)                              # C8 mov r1,r5
    c+=w(0xE1A02006)                              # CC mov r2,r6
    c+=w(0xE4D03001)                              # D0 ldrb r3,[r0],#1
    c+=w(0xE1A04223)                              # D4 mov r4,r3,lsr#4
    c+=w(0xE7D74004)                              # D8 ldrb r4,[r7,r4]
    c+=w(0xE4C24001)                              # DC strb r4,[r2],#1
    c+=w(0xE203400F)                              # E0 and r4,r3,#0xF
    c+=w(0xE7D74004)                              # E4 ldrb r4,[r7,r4]
    c+=w(0xE4C24001)                              # E8 strb r4,[r2],#1
    c+=w(0xE2511001)                              # EC subs r1,r1,#1
    c+=w(0xCA000000|bl_off(A(0xF0),A(0xD0)))      # F0 bgt loop_5202
    c+=w(0xE3A03000)                              # F4 mov r3,#0
    c+=w(0xE5C23000)                              # F8 strb r3,[r2]
    c+=w(0xE1A0000B)                              # FC mov r0,r11
    c+=w(0xE59F1000|pcrel(0x100,3))               # 100 ldr r1,[pc] "_iap2m"
    c+=w(0xE1A02006)                              # 104 mov r2,r6
    c+=w(0xE59F3000|pcrel(0x108,4))               # 108 ldr r3,[pc] cJSON
    c+=w(0xE12FFF33)                              # 10C blx r3
    c+=w(0xE1A00006)                              # 110 mov r0,r6
    c+=w(0xEB000000|bl_off(A(0x114),FREE))        # 114 bl free
    c+=w(0xE3A03000)                              # 118 mov r3,#0
    c+=w(0xE58A3118)                              # 11C str r3,[r10,#0x118]  reset cur
    c+=w(0xE58A3120)                              # 120 str r3,[r10,#0x120]  reset prev
    # ---- do_send @0x124 ----
    c+=w(0xE1A0000B)                              # 124 mov r0,r11
    c+=w(0xEB000000|bl_off(A(0x128),SEND_NAV))    # 128 bl _SendNaviJSON
    c+=w(0xE3A00000)                              # 12C mov r0,#0
    c+=w(0xE58A0110)                              # 130 str r0,[r10,#0x110]
    c+=w(0xE58A0114)                              # 134 str r0,[r10,#0x114]
    c+=w(0xE8BD8FF0)                              # 138 pop {r4-r11,pc}
    assert len(c)==POOL, f"stage2 code {len(c):#x}!={POOL:#x}"
    c+=w(GLOBAL)                                  # 13C pool0
    c+=w(A(0x150))                                # 140 pool1 hex_table
    c+=w(A(0x160))                                # 144 pool2 "_iap2"
    c+=w(A(0x166))                                # 148 pool3 "_iap2m"
    c+=w(CJSON)                                   # 14C pool4
    c+=b"0123456789abcdef"                        # 150
    c+=b"_iap2\x00"                               # 160
    c+=b"_iap2m\x00"                              # 166
    while len(c)%4: c.append(0)
    assert len(c)==0x170, f"stage2 size {len(c):#x}"
    return bytes(c)

# ===================== STAGE 1 v5 (168 B, identical to v4) =====================
def build_stage1(B):
    def br(cond,at,to):
        a=B+at; t=(B+to) if to>=0 else RET
        return (cond<<24)|(((t-(a+8))>>2)&0xFFFFFF)
    def ldr_pc(rd,at,pool):
        imm=pool-(at+8); assert 0<=imm<4096 and imm%4==0
        return 0xE59F0000|(rd<<12)|imm
    PG,PB=0xA0,0xA4
    LAYOUT=[
     (0x00,0xE5D1C00D),(0x04,0xE35C0052),(0x08,('b',0x1A,0x98)),
     (0x0C,0xE5D1C00E),(0x10,0xE35C0001),(0x14,('b',0x0A,0x24)),
     (0x18,0xE35C0002),(0x1C,('b',0x0A,0x44)),(0x20,('b',0xEA,0x98)),
     (0x24,ldr_pc(12,0x24,PG)),(0x28,0xE58C1110),(0x2C,0xE92D43F0),
     (0x30,0xE5D14002),(0x34,0xE5D15003),(0x38,0xE1854404),(0x3C,0xE58C4114),
     (0x40,('b',0xEA,-1)),
     (0x44,0xE92D43F0),(0x48,ldr_pc(12,0x48,PG)),(0x4C,0xE59C4118),
     (0x50,0xE5D15002),(0x54,0xE5D16003),(0x58,0xE1865405),(0x5C,0xE2455009),
     (0x60,0xE3550000),(0x64,('b',0xDA,0x94)),(0x68,0xE0848005),
     (0x6C,0xE3580801),(0x70,('b',0xCA,0x94)),(0x74,ldr_pc(6,0x74,PB)),
     (0x78,0xE0866004),(0x7C,0xE2817009),
     (0x80,0xE4D79001),(0x84,0xE4C69001),(0x88,0xE2555001),(0x8C,('b',0xCA,0x80)),
     (0x90,0xE58C8118),(0x94,('b',0xEA,-1)),(0x98,0xE92D43F0),(0x9C,('b',0xEA,-1)),
     (0xA0,GLOBAL),(0xA4,BURST),
    ]
    c=bytearray()
    for off,enc in LAYOUT:
        assert off==len(c)
        c+=w(enc if isinstance(enc,int) else br(enc[1],off,enc[2]))
    assert len(c)==0xA8
    return bytes(c)

# ===================== ELF PATCH =====================
S2_FOFF=0x76b38
STAGE2_BASE=0x10000+S2_FOFF
s2=build_stage2(STAGE2_BASE)
S1_FOFF=(S2_FOFF+len(s2)+0xF)&~0xF
STAGE1_BASE=0x10000+S1_FOFF
s1=build_stage1(STAGE1_BASE)
END_FOFF=S1_FOFF+len(s1)
assert END_FOFF<=0x77000, f"trampolines overflow gap ({END_FOFF:#x})"
open('stage2_v5.bin','wb').write(s2)
open('stage1_v5.bin','wb').write(s1)

elf=bytearray(open('ARMiPhoneIAP2.unpacked','rb').read())
assert len(elf)==494244
phoff,=struct.unpack_from('<I',elf,0x1c); phnum,=struct.unpack_from('<H',elf,0x2c)
ph_rx=ph_rw=None
for i in range(phnum):
    o=phoff+i*32
    t,off,va,pa,fs,ms,fl,al=struct.unpack_from('<8I',elf,o)
    if t==1 and fl==5 and off==0: ph_rx=(o,fs)
    if t==1 and fl==6:            ph_rw=(o,)
assert ph_rx and ph_rw and ph_rx[1]==0x76b38
H1=HOOK1_VA-0x10000; HA=HOOKA_VA-0x10000
assert elf[H1:H1+4]==bytes.fromhex('f0432de9') and elf[HA:HA+4]==bytes.fromhex('5dfdffeb')
assert set(elf[S2_FOFF:0x77000])<= {0}, "gap not zero"
elf[S2_FOFF:S2_FOFF+len(s2)]=s2
elf[S1_FOFF:S1_FOFF+len(s1)]=s1
struct.pack_into('<I',elf,ph_rx[0]+0x10,END_FOFF)        # ph3 filesz
struct.pack_into('<I',elf,ph_rx[0]+0x14,END_FOFF)        # ph3 memsz
struct.pack_into('<I',elf,ph_rw[0]+0x14,0x14000)         # ph4 memsz -> 64KB .bss
hook1=0xEA000000|(((STAGE1_BASE-(HOOK1_VA+8))>>2)&0xFFFFFF)
hooka=0xEB000000|(((STAGE2_BASE-(HOOKA_VA+8))>>2)&0xFFFFFF)
elf[H1:H1+4]=w(hook1); elf[HA:HA+4]=w(hooka)
assert len(elf)==494244
open('ARMiPhoneIAP2.v5.patched','wb').write(elf)

print(f"stage2_v5  {len(s2)} B  @0x{STAGE2_BASE:x}  md5 {hashlib.md5(s2).hexdigest()}")
print(f"stage1_v5  {len(s1)} B  @0x{STAGE1_BASE:x}  md5 {hashlib.md5(s1).hexdigest()}")
print(f"ph3 filesz/memsz -> 0x{END_FOFF:x} ; ph4 memsz -> 0x14000")
print(f"Hook1 @0x{H1:x} = {w(hook1).hex()}  HookA @0x{HA:x} = {w(hooka).hex()}")
print(f"ARMiPhoneIAP2.v5.patched  {len(elf)} B  md5 {hashlib.md5(bytes(elf)).hexdigest()}")
for nm,b in [("stage2_v5",s2),("stage1_v5",s1)]:
    print(f"{nm} hex:")
    for i in range(0,len(b),16):
        print("  %04x: %s"%(i,' '.join('%02x'%x for x in b[i:i+16])))

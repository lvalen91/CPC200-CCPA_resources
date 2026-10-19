#!/usr/bin/env python3
"""
build_v6.py -- COMBINED patch: NAV v5 (RouteGuidance -> _iap2/_iap2m) + P1 (ExitInfo).

P1 makes the stock box request Apple's ExitInfo. iAP2 StartRouteGuidanceUpdates
(0x5200) carries selector params; the stock StartGuidanceItems ctor (0x2db80) emits
only id0 (ComponentID) + id1 (SourceName) + id2 (SourceSupportsRouteGuidance). Apple
only sends 0x5202 id13 ExitInfo if selector id3 SupportsExitInfo (empty TLV) is present.

Design A (wire-level append), NOT the builder (design B). The three selector entities
are EMBEDDED sub-objects at fixed offsets (this+0x38/+0x58/+0x78) inside a fixed-size
heap object with an embedded std::map; adding id3 there means resizing the object and
fighting fixed offsets + the HUD value-clear path -> fragile. Instead we append the TLV
to the already-built wire frame in the generic iAP2 sender, and let the firmware's own
finalizer recompute every length/checksum.

Sender 0x2f7c4: builds the link frame into buf = malloc(bodylen+0x49) (73 B slack).
  0x18264        -> buf[4]=control, buf[6]=ack, buf[7]=sessionID
  0x17e94 (0x5200 takes this container path, container id == 0xffff):
        buf[9]=buf[0xa]=0x40 ; buf[0xb..0xc]=msglen(BE)=container_len+2 ;
        buf[0xd..0xe]=msgid(BE) ; params copied to buf+0xf
  0x17a2c        -> buf[2..3]=linklen(BE)=msglen+0xa
  then bl 0x14d80 (@0x2f914) -> 0x14ba4 -> 0x17b14 writes FF 5A, header cksum buf[8]
        over buf[0..7], and payload cksum over buf[9..9+msglen-1]. ALL checksums/FF5A
        are computed AFTER the send call, so modifying the frame + the two length
        fields BEFORE the send call makes the finalizer produce a valid frame with
        zero checksum math on our side.

P1 hook: replace `bl 0x14d80` (@0x2f914, bytes 1995ffeb) with `bl p1stub`.
P1 stub (in the cave, after v5's trampolines): if msgid(buf[0xd..0xe])==0x5200, append
  `00 04 00 03` (empty TLV, length 4, id 3) at buf+9+msglen, msglen+=4, linklen+=4;
  then `b 0x14d80`. lr already = 0x2f918 (set by our bl), r0=sb/r1=buf unchanged, so
  0x14d80 returns into the sender exactly as the original call did. No stack use.

Composes with v5: distinct hook site (0x2f914) and a 3rd cave stub placed right after
v5's stage1 (0x76d58). v5's stage2/stage1/hooks/ph4 are reproduced byte-for-byte and
asserted equal to ARMiPhoneIAP2.v5.patched.
"""
import struct, hashlib

# ===================== v5 constants (verbatim from build_v5.py) =====================
MALLOC=0x134e8; FREE=0x12f18; SEND_NAV=0x2c9d0; CJSON=0x69b35
GLOBAL=0x00099E00; BURST=0x0009A000; RET=0x0002d1cc
HOOK1_VA=0x2d1c8; HOOKA_VA=0x2d454

def w(v): return struct.pack('<I', v & 0xFFFFFFFF)
def bl_off(frm,to): return ((to-(frm+8))>>2)&0x00FFFFFF

# ===================== STAGE 2 v5 (368 B) -- verbatim from build_v5.py ===============
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

# ===================== STAGE 1 v5 (168 B) -- verbatim from build_v5.py ==============
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

# ===================== P1 stub (ExitInfo selector append) ===========================
P1_HOOK_VA=0x2f914     # the `bl 0x14d80` send call in the iAP2 sender 0x2f7c4
SEND=0x14d80           # iAP2 link send (-> 0x14ba4 -> FF5A + checksums in 0x17b14)

def build_p1(B):
    # fixed-offset ARM words; two branches computed from B via bl_off (B cancels for bne)
    c=bytearray()
    c+=w(0xE5D1200D)                              # 00 ldrb r2,[r1,#0xd]   msgid hi
    c+=w(0xE5D1300E)                              # 04 ldrb r3,[r1,#0xe]   msgid lo
    c+=w(0xE1832402)                              # 08 orr r2,r3,r2,lsl#8  r2=msgid
    c+=w(0xE3053200)                              # 0C movw r3,#0x5200
    c+=w(0xE1520003)                              # 10 cmp r2,r3
    c+=w(0x1A000000|bl_off(B+0x14,B+0x78))        # 14 bne DONE
    c+=w(0xE5D1200B)                              # 18 ldrb r2,[r1,#0xb]   msglen hi
    c+=w(0xE5D1300C)                              # 1C ldrb r3,[r1,#0xc]   msglen lo
    c+=w(0xE1832402)                              # 20 orr r2,r3,r2,lsl#8  r2=msglen
    c+=w(0xE081C002)                              # 24 add ip,r1,r2
    c+=w(0xE28CC009)                              # 28 add ip,ip,#9        ip=buf+9+msglen (end of params)
    c+=w(0xE3A03000)                              # 2C mov r3,#0
    c+=w(0xE4CC3001)                              # 30 strb r3,[ip],#1     00
    c+=w(0xE3A03004)                              # 34 mov r3,#4
    c+=w(0xE4CC3001)                              # 38 strb r3,[ip],#1     04  (TLV length=4)
    c+=w(0xE3A03000)                              # 3C mov r3,#0
    c+=w(0xE4CC3001)                              # 40 strb r3,[ip],#1     00
    c+=w(0xE3A03003)                              # 44 mov r3,#3
    c+=w(0xE4CC3001)                              # 48 strb r3,[ip],#1     03  (TLV id=3)
    c+=w(0xE2822004)                              # 4C add r2,r2,#4        msglen+=4
    c+=w(0xE1A03422)                              # 50 mov r3,r2,lsr#8
    c+=w(0xE5C1300B)                              # 54 strb r3,[r1,#0xb]   msglen hi
    c+=w(0xE5C1200C)                              # 58 strb r2,[r1,#0xc]   msglen lo
    c+=w(0xE5D12002)                              # 5C ldrb r2,[r1,#2]     linklen hi
    c+=w(0xE5D13003)                              # 60 ldrb r3,[r1,#3]     linklen lo
    c+=w(0xE1832402)                              # 64 orr r2,r3,r2,lsl#8  r2=linklen
    c+=w(0xE2822004)                              # 68 add r2,r2,#4        linklen+=4
    c+=w(0xE1A03422)                              # 6C mov r3,r2,lsr#8
    c+=w(0xE5C13002)                              # 70 strb r3,[r1,#2]     linklen hi
    c+=w(0xE5C12003)                              # 74 strb r2,[r1,#3]     linklen lo
    assert len(c)==0x78, f"p1 code {len(c):#x}"
    c+=w(0xEA000000|bl_off(B+0x78,SEND))          # 78 DONE: b 0x14d80
    assert len(c)==0x7C, f"p1 size {len(c):#x}"
    return bytes(c)

# ===================== ELF PATCH =====================
S2_FOFF=0x76b38
STAGE2_BASE=0x10000+S2_FOFF
s2=build_stage2(STAGE2_BASE)
S1_FOFF=(S2_FOFF+len(s2)+0xF)&~0xF
STAGE1_BASE=0x10000+S1_FOFF
s1=build_stage1(STAGE1_BASE)
V5_END_FOFF=S1_FOFF+len(s1)                       # 0x76d58 == v5 ph3 end
assert V5_END_FOFF==0x76d58, f"{V5_END_FOFF:#x}"

P1_FOFF=(V5_END_FOFF+0x3)&~0x3                     # 4-byte align (already aligned)
P1_BASE=0x10000+P1_FOFF
p1=build_p1(P1_BASE)
END_FOFF=P1_FOFF+len(p1)
assert END_FOFF<=0x77000, f"trampolines overflow gap ({END_FOFF:#x})"

open('stage2_v6.bin','wb').write(s2)
open('stage1_v6.bin','wb').write(s1)
open('p1_v6.bin','wb').write(p1)

elf=bytearray(open('ARMiPhoneIAP2.unpacked','rb').read())
assert len(elf)==494244
assert hashlib.md5(bytes(elf)).hexdigest().startswith('f1e1a0aa'), "stock md5 mismatch"
phoff,=struct.unpack_from('<I',elf,0x1c); phnum,=struct.unpack_from('<H',elf,0x2c)
ph_rx=ph_rw=None
for i in range(phnum):
    o=phoff+i*32
    t,off,va,pa,fs,ms,fl,al=struct.unpack_from('<8I',elf,o)
    if t==1 and fl==5 and off==0: ph_rx=(o,fs)
    if t==1 and fl==6:            ph_rw=(o,)
assert ph_rx and ph_rw and ph_rx[1]==0x76b38

# --- stock-byte asserts (v5 hooks + P1 hook site + zero cave) ---
H1=HOOK1_VA-0x10000; HA=HOOKA_VA-0x10000; HP=P1_HOOK_VA-0x10000
assert elf[H1:H1+4]==bytes.fromhex('f0432de9'), "stock hook1 changed"
assert elf[HA:HA+4]==bytes.fromhex('5dfdffeb'), "stock hookA changed"
assert elf[HP:HP+4]==bytes.fromhex('1995ffeb'), "stock P1 hook site (bl 0x14d80) changed"
assert set(elf[S2_FOFF:0x77000])<= {0}, "cave gap not zero"

# --- write v5 trampolines ---
elf[S2_FOFF:S2_FOFF+len(s2)]=s2
elf[S1_FOFF:S1_FOFF+len(s1)]=s1
# --- write P1 stub ---
elf[P1_FOFF:P1_FOFF+len(p1)]=p1
# --- segment sizes: ph3 R-X filesz/memsz -> END_FOFF ; ph4 RW memsz -> 0x14000 (v5) ---
struct.pack_into('<I',elf,ph_rx[0]+0x10,END_FOFF)
struct.pack_into('<I',elf,ph_rx[0]+0x14,END_FOFF)
struct.pack_into('<I',elf,ph_rw[0]+0x14,0x14000)
# --- hooks ---
hook1=0xEA000000|(((STAGE1_BASE-(HOOK1_VA+8))>>2)&0xFFFFFF)   # b stage1
hooka=0xEB000000|(((STAGE2_BASE-(HOOKA_VA+8))>>2)&0xFFFFFF)   # bl stage2
hookp=0xEB000000|(((P1_BASE   -(P1_HOOK_VA+8))>>2)&0xFFFFFF)  # bl p1stub
elf[H1:H1+4]=w(hook1); elf[HA:HA+4]=w(hooka); elf[HP:HP+4]=w(hookp)
assert len(elf)==494244
open('ARMiPhoneIAP2.v6.patched','wb').write(elf)

# --- PROOF: v5 region must be byte-identical to the shipped v5.patched ---
try:
    v5=open('ARMiPhoneIAP2.v5.patched','rb').read()
    # everything v5 touched must match: v5 hooks, cave [0x76b38..0x76d58), ph4 memsz.
    assert elf[H1:H1+4]==v5[H1:H1+4]
    assert elf[HA:HA+4]==v5[HA:HA+4]
    assert bytes(elf[S2_FOFF:V5_END_FOFF])==v5[S2_FOFF:V5_END_FOFF]
    assert struct.unpack_from('<I',bytes(elf),ph_rw[0]+0x14)==struct.unpack_from('<I',v5,ph_rw[0]+0x14)
    print("v5 intactness: PASS (v5 hooks, cave 0x76b38..0x76d58, ph4 memsz == v5.patched)")
except FileNotFoundError:
    print("v5 intactness: SKIP (v5.patched not present)")

print(f"stage2_v6  {len(s2)} B  @0x{STAGE2_BASE:x}  md5 {hashlib.md5(s2).hexdigest()}")
print(f"stage1_v6  {len(s1)} B  @0x{STAGE1_BASE:x}  md5 {hashlib.md5(s1).hexdigest()}")
print(f"p1_v6      {len(p1)} B  @0x{P1_BASE:x}  md5 {hashlib.md5(p1).hexdigest()}")
print(f"ph3 filesz/memsz -> 0x{END_FOFF:x} ; ph4 memsz -> 0x14000 ; cave left {0x77000-END_FOFF} B")
print(f"Hook1 @0x{H1:x}={w(hook1).hex()}  HookA @0x{HA:x}={w(hooka).hex()}  HookP1 @0x{HP:x}={w(hookp).hex()}")
print(f"ARMiPhoneIAP2.v6.patched  {len(elf)} B  md5 {hashlib.md5(bytes(elf)).hexdigest()}")
print("p1_v6 hex:")
for i in range(0,len(p1),16):
    print("  %04x: %s"%(i,' '.join('%02x'%x for x in p1[i:i+16])))

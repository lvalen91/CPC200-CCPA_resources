#!/usr/bin/env python3
"""
build_commtest.py -- CALL patch (_callraw) + COMMUNICATION engine-enable (WORKING, device-verified
2026-06-15). Output: ARMiPhoneIAP2.commenable.patched (md5 dc87d77e). NO datastore edits.

Built from factory ARMiPhoneIAP2.unpacked (md5 f1e1a0aa, = live /usr/sbin daemon). Trampolines in the
inter-segment code cave (file 0x76b38 / VMA 0x86b38). Full writeup: 10_comm_enabled_working.md.

  [CALL, proven]  Stage1 @0x296cc + Stage2 @0x29960  -> forwards raw 0x4155 as _callraw.

  [COMM force-construct]  NOP @0x1617c (ENABLE_COMM_CONSTRUCT). The comm engine is DATASTORE-GATED:
     factory builds it then 0x158bc destroys+nulls [0x9859c] if its name is absent from
     AIEIPIEREngines.datastore. NOPing the keep/destroy gate keeps comm built + registered (0x283a0
     registers recv 0x4157/8/9). (Editing the datastore instead = bplist-signature poison; never do it.)

  [COMM subscribe]  hook 0x285b0 (ENABLE_COMM_SUBSCRIBE; was bl 0x1c96c, return unused for comm;
     r5=comm subscribe entity comm+0x268). 0x1e2a0(entity,1) re-selects the 17 prebuilt children +
     sets dirty + returns r0=0 -> existing sender 0x285a0 transmits StartCommunicationUpdate(0x4157).

  [COMM forward]  hook 0x18ff8 (the DISPATCHER's 0x4158 case; r6=raw frame). The comm recv handler
     0x2846c is NEVER invoked (recv route 0x1917c null-gates on the comm singleton), so forward at the
     dispatcher: hex-encode payload -> MetaData subtype-101 _commraw -> BroadCast; replay displaced
     ldr r3,=0x9859c + b 0x1917c. Host (IAP2CallStateDecoder.commStatus) decodes named fields.

RESULT: 0x4157 sent, iPhone streams 0x4158 (SignalStrength/RegStatus/Carrier/CallCount/Voicemail/Mute),
host gets subtype-101 _commraw + named decode, media+call intact, no poison. Flags ENABLE_FORCE_SEND
(old Mod1, abandoned) kept for reference.
"""
import struct, hashlib
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM

# ---- shared targets (VMA = file_offset + 0x10000) ----
MALLOC   = 0x134e8
FREE     = 0x12f18
ADDSTR   = 0x69b35       # cJSON_AddStringToObject (thumb 0x69b34|1)
PRINT    = 0x696d0       # cJSON_PrintUnformatted (thumb), displaced by call stage2
BROADCAST= 0x66e20       # BroadCast(payload, len) -- thumb, blx
GLOBAL   = 0x9A000       # call scratch bss: [+0]=frame ptr [+4]=BE len
COMM_SING= 0x9859c       # *(0x9859c) = comm engine `this`
COMM_DIRTY_OFF = 0x26c   # entity = this+0x268 ; dirty flag at entity+4 = this+0x26c

# call hooks
C_HOOK1=0x296cc; C_HOOK2=0x29960; C_RET1=0x296d0
# comm hooks
# Forwarder hooks the DISPATCHER's 0x4158 case @0x18ff8 (NOT the comm engine handler 0x2846c, which
# is never invoked because the recv path 0x1917c null-gates on the comm singleton). At 0x18ff8:
# r6 = raw iAP2 frame (live), and we're already in the 0x4158 case. Displaced instr = ldr r3,[0x193ac]
# (=load const 0x9859c); we replay it as ldr r3,=0x9859c then b 0x1917c (the original 0x18ffc target).
M_FWD_HOOK=0x18ff8; DISP_RET=0x1917c       # displaced: ldr r3,[0x193ac]=0x9859c (ac339fe5)
M_START_HOOK=0x148fc; START_WRAP=0x285dc   # displaced bl 0x285dc

def w(v): return struct.pack('<I', v & 0xFFFFFFFF)
def b_imm(frm, to):   return 0xEA000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def bl_imm(frm, to):  return 0xEB000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def beq_imm(frm, to): return 0x0A000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def bne_imm(frm, to): return 0x1A000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def ble_imm(frm, to): return 0xDA000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def bgt_imm(frm, to): return 0xCA000000 | (((to-(frm+8))>>2) & 0xFFFFFF)
def blx_imm(frm, to):
    d = to-(frm+8); return 0xFA000000 | (((d>>1)&1)<<24) | ((d>>2)&0xFFFFFF)
def ldr_pc(rd, at, pool):
    imm = pool-(at+8); assert 0 <= imm < 4096 and imm % 4 == 0, f"ldr_pc {imm:#x}"
    return 0xE59F0000 | (rd<<12) | imm

# ===================== CALL STAGE 2 (verbatim from build_callraw) =====================
def build_call_stage2(B):
    POOL=0xA0; c=bytearray(); A=lambda o:B+o
    def emit(ws):
        for x in ws: c.extend(w(x))
    emit([0xE92D47F0]); c.extend(w(ldr_pc(8,0x04,POOL+0x00)))
    emit([0xE5984000,0xE3540000]); c.extend(w(beq_imm(A(0x10),A(0x94))))
    emit([0xE5980004,0xE2507009]); c.extend(w(ble_imm(A(0x1C),A(0x8C))))
    emit([0xE2846009,0xE1A00087,0xE2800001]); c.extend(w(bl_imm(A(0x2C),MALLOC)))
    emit([0xE3500000]); c.extend(w(beq_imm(A(0x34),A(0x8C))))
    emit([0xE1A04000]); c.extend(w(ldr_pc(9,0x3C,POOL+0x04))); emit([0xE1A02004])
    emit([0xE4D63001,0xE1A00223,0xE7D90000,0xE4C20001,0xE203000F,0xE7D90000,0xE4C20001,0xE2577001])
    c.extend(w(bgt_imm(A(0x64),A(0x44))))
    emit([0xE3A03000,0xE5C23000,0xE1A00005]); c.extend(w(ldr_pc(1,0x74,POOL+0x08)))
    emit([0xE1A02004]); c.extend(w(ldr_pc(3,0x7C,POOL+0x0C))); emit([0xE12FFF33,0xE1A00004])
    c.extend(w(bl_imm(A(0x88),FREE)))
    emit([0xE3A03000,0xE5883000,0xE1A00005]); c.extend(w(blx_imm(A(0x98),PRINT)))
    emit([0xE8BD87F0])
    assert len(c)==POOL, f"call stage2 {len(c):#x}"
    emit([GLOBAL,B+0xB0,B+0xC0,ADDSTR]); c.extend(b"0123456789abcdef"); c.extend(b"_callraw\x00")
    while len(c)%4: c.append(0)
    assert len(c)==0xCC, f"call stage2 size {len(c):#x}"
    return bytes(c)

# ===================== CALL STAGE 1 (verbatim) =====================
def build_call_stage1(B):
    POOL=0x20; c=bytearray(); A=lambda o:B+o
    def emit(ws):
        for x in ws: c.extend(w(x))
    emit([0xE92D40F0]); c.extend(w(ldr_pc(4,0x04,POOL)))
    emit([0xE5841000,0xE5D15002,0xE5D16003,0xE1865405,0xE5845004])
    c.extend(w(b_imm(A(0x1C),C_RET1)))
    assert len(c)==POOL; emit([GLOBAL]); assert len(c)==0x24
    return bytes(c)

# ===================== COMM Mod 2: forwarder (hook 0x18ff8 = dispatcher 0x4158 case) =====================
# At 0x18ff8: r6 = raw iAP2 frame (FF5A link hdr), already in the 0x4158 case (no msgid check needed).
# Hex-encode payload (frame+9, totallen-9) -> MetaData subtype-101 _commraw -> BroadCast. Then replay
# the displaced 'ldr r3,[=0x9859c]' and b 0x1917c (the original recv-route, which null-gates on comm).
def build_commfwd(B):
    POOL=0x98; c=bytearray(); A=lambda o:B+o
    def emit(ws):
        for x in ws: c.extend(w(x))
    emit([0xE92D41FF])                          # 00 push {r0-r8,lr}
    emit([0xE1A07006])                          # 04 mov r7,r6            r7 = raw frame
    emit([0xE5D74002,0xE5D75003,0xE1854404])    # 08 ldrb r4,[r7,2]; 0C ldrb r5,[r7,3]; 10 orr r4=totallen BE
    emit([0xE2544009]); c.extend(w(ble_imm(A(0x18),A(0x8C))))   # 14 subs r4,#9 ; 18 ble .ret
    emit([0xE1A00084,0xE2800005])               # 1C mov r0,r4,lsl#1 ; 20 add r0,#5
    c.extend(w(bl_imm(A(0x24),MALLOC)))         # 24 bl malloc
    emit([0xE3500000]); c.extend(w(beq_imm(A(0x2C),A(0x8C))))   # 28 cmp ; 2C beq .ret
    emit([0xE1A06000,0xE3A02065,0xE4802004,0xE2873009,0xE1A02004])  # 30 buf;34 hdr0x65;38 str;3C src=frame+9;40 count
    c.extend(w(ldr_pc(1,0x44,POOL+0x00)))       # 44 ldr r1,=hextab
    emit([0xE4D35001,0xE1A08225,0xE7D18008,0xE4C08001,0xE205800F,0xE7D18008,0xE4C08001,0xE2522001])  # 48 hx loop
    c.extend(w(bgt_imm(A(0x68),A(0x48))))       # 68 bgt .hx
    emit([0xE3A05000,0xE5C05000,0xE1A00006,0xE1A01084,0xE2811005])  # 6C NUL;74 r0=buf;78 r1=2*len+5
    c.extend(w(blx_imm(A(0x80),BROADCAST)))     # 80 blx BroadCast
    emit([0xE1A00006]); c.extend(w(bl_imm(A(0x88),FREE)))       # 84 r0=buf ; 88 bl free
    emit([0xE8BD41FF])                          # 8C .ret pop {r0-r8,lr}  (restores r6=frame)
    c.extend(w(ldr_pc(3,0x90,POOL+0x04)))       # 90 ldr r3,=COMM_SING (replay displaced)
    c.extend(w(b_imm(A(0x94),DISP_RET)))        # 94 b 0x1917c (original recv-route)
    assert len(c)==POOL, f"commfwd code {len(c):#x} != {POOL:#x}"
    emit([B+0xA0])                              # 98 hextab ptr
    emit([COMM_SING])                           # 9C COMM_SING (0x9859c) for the replayed ldr r3
    c.extend(b"0123456789abcdef")               # A0..B0
    while len(c)%4: c.append(0)
    assert len(c)==0xB0, f"commfwd size {len(c):#x}"
    return bytes(c)

# ===================== COMM Mod 1: force-send (hook 0x148fc) =====================
def build_commstart(B):
    POOL=0x1C; c=bytearray(); A=lambda o:B+o
    def emit(ws):
        for x in ws: c.extend(w(x))
    c.extend(w(ldr_pc(0,0x00,POOL)))            # 00 ldr r0,=COMM_SING
    emit([0xE5900000])                          # 04 ldr r0,[r0]   engine this
    emit([0xE3500000]); c.extend(w(beq_imm(A(0x08),A(0x18))))   # 08 cmp ; 0C beq .skip
    emit([0xE3A03001])                          # 10 mov r3,#1
    emit([0xE5803000 | COMM_DIRTY_OFF])         # 14 str r3,[r0,#0x26c]
    c.extend(w(b_imm(A(0x18),START_WRAP)))      # 18 .skip b 0x285dc
    assert len(c)==POOL, f"commstart code {len(c):#x}"
    emit([COMM_SING])                           # 1C pool
    assert len(c)==0x20
    return bytes(c)

# ============================ ELF PATCH ============================
S2_FOFF=0x76b38; S2_VA=0x10000+S2_FOFF
cs2=build_call_stage2(S2_VA)
S1_FOFF=(S2_FOFF+len(cs2)+0xF)&~0xF; S1_VA=0x10000+S1_FOFF
cs1=build_call_stage1(S1_VA)
# Mod1 (commstart force-send, ENABLE_FORCE_SEND) was insufficient -> DISABLED.
# Mod3 (ENABLE_COMM_SUBSCRIBE, Option A) is the real comm enable: re-select the 17 comm
# subscribe children (already built+populated by ctor 0x28e48 but deselected by 0x1e2a0(e,0))
# so the existing sender 0x285a0 transmits StartCommunicationUpdate(0x4157). See cinemo_reference.
ENABLE_FORCE_SEND=False
ENABLE_COMM_SUBSCRIBE=True
# ---- Mod3 comm subscribe-select trampoline (hook 0x285b0 = bl 0x1c96c, return unused for comm) ----
SUBSEL_FN=0x1e2a0      # 0x1e2a0(entity, flag): sets child[+4]=flag for ALL children
SUB_HOOK=0x285b0; SUB_RET=0x285b4
def build_commsub(B):
    c=bytearray(); A=lambda o:B+o
    def emit(ws):
        for x in ws: c.extend(w(x))
    emit([0xE92D4010])                    # 00 push {r4,lr}
    emit([0xE3A03001])                    # 04 mov r3,1
    emit([0xE5853004])                    # 08 str r3,[r5,4]   entity dirty (idempotent/robust)
    emit([0xE1A00005])                    # 0C mov r0,r5        r0 = comm entity (this+0x268)
    emit([0xE3A01001])                    # 10 mov r1,1
    c.extend(w(bl_imm(A(0x14),SUBSEL_FN)))# 14 bl 0x1e2a0       select ALL children (child[+4]=1)
    emit([0xE3A00000])                    # 18 mov r0,0         return 0 (so r4=0 -> skip 0x2fb64 free)
    emit([0xE8BD8010])                    # 1C pop {r4,pc}      -> 0x285b4 (existing 0x4157 sender)
    assert len(c)==0x20, f"commsub size {len(c):#x}"
    return bytes(c)

CF_FOFF=(S1_FOFF+len(cs1)+0xF)&~0xF; CF_VA=0x10000+CF_FOFF
cf=build_commfwd(CF_VA)
CS_FOFF=CS_VA=0; cst=b''               # force-send (Mod1) disabled
_nxt=CF_FOFF+len(cf)
if ENABLE_COMM_SUBSCRIBE:
    CSUB_FOFF=(_nxt+0xF)&~0xF; CSUB_VA=0x10000+CSUB_FOFF
    csub=build_commsub(CSUB_VA)
    _nxt=CSUB_FOFF+len(csub)
else:
    CSUB_FOFF=CSUB_VA=0; csub=b''
END_FOFF=_nxt
assert END_FOFF<=0x77000, f"cave overflow {END_FOFF:#x}"

elf=bytearray(open('ARMiPhoneIAP2.unpacked','rb').read())
assert len(elf)==494244
assert hashlib.md5(elf).hexdigest()=='f1e1a0aa4d7fa6e639048c93475af9df', "wrong base binary"

phoff,=struct.unpack_from('<I',elf,0x1c); phnum,=struct.unpack_from('<H',elf,0x2c)
ph_rx=ph_rw=None
for i in range(phnum):
    o=phoff+i*32; t,off,va,pa,fs,ms,fl,al=struct.unpack_from('<8I',elf,o)
    if t==1 and fl==5 and off==0: ph_rx=o
    if t==1 and fl==6:            ph_rw=o
assert ph_rx and ph_rw
assert struct.unpack_from('<I',elf,ph_rx+0x10)[0]==0x76b38, "LOAD0 filesz changed"
assert struct.unpack_from('<I',elf,ph_rw+0x08)[0]==0x97000, "LOAD1 vaddr changed"

def foff(va): return va-0x10000
# guard original bytes at every hook
assert elf[foff(C_HOOK1):foff(C_HOOK1)+4]==bytes.fromhex('f0402de9'), "call hook1 bytes"
assert elf[foff(C_HOOK2):foff(C_HOOK2)+4]==bytes.fromhex('5aff00fa'), "call hook2 bytes"
assert elf[foff(M_FWD_HOOK):foff(M_FWD_HOOK)+4]==bytes.fromhex('ac339fe5'), "commfwd hook bytes (ldr r3,[0x193ac] @0x18ff8)"
if ENABLE_FORCE_SEND:
    assert elf[foff(M_START_HOOK):foff(M_START_HOOK)+4]==bytes.fromhex('364f00eb'), "commstart hook bytes (bl 0x285dc)"
if ENABLE_COMM_SUBSCRIBE:
    assert elf[foff(SUB_HOOK):foff(SUB_HOOK)+4]==bytes.fromhex('edd0ffeb'), "commsub hook bytes (bl 0x1c96c)"
assert set(elf[S2_FOFF:0x77000])<={0}, "cave not zero"

# write trampolines
elf[S2_FOFF:S2_FOFF+len(cs2)]=cs2
elf[S1_FOFF:S1_FOFF+len(cs1)]=cs1
elf[CF_FOFF:CF_FOFF+len(cf)]=cf
if ENABLE_FORCE_SEND:
    elf[CS_FOFF:CS_FOFF+len(cst)]=cst
if ENABLE_COMM_SUBSCRIBE:
    elf[CSUB_FOFF:CSUB_FOFF+len(csub)]=csub
# extend segments
struct.pack_into('<I',elf,ph_rx+0x10,END_FOFF)   # LOAD0 filesz
struct.pack_into('<I',elf,ph_rx+0x14,END_FOFF)   # LOAD0 memsz
struct.pack_into('<I',elf,ph_rw+0x14,0x3010)     # LOAD1 memsz (bss covers GLOBAL+8)
# install hooks
struct.pack_into('<I',elf,foff(C_HOOK1),   b_imm(C_HOOK1,  S1_VA))     # b call_stage1
struct.pack_into('<I',elf,foff(C_HOOK2),   bl_imm(C_HOOK2, S2_VA))     # bl call_stage2
struct.pack_into('<I',elf,foff(M_FWD_HOOK),b_imm(M_FWD_HOOK,CF_VA))    # b commfwd
if ENABLE_FORCE_SEND:
    struct.pack_into('<I',elf,foff(M_START_HOOK),bl_imm(M_START_HOOK,CS_VA))  # bl commstart
if ENABLE_COMM_SUBSCRIBE:
    struct.pack_into('<I',elf,foff(SUB_HOOK),bl_imm(SUB_HOOK,CSUB_VA))        # bl commsub (was bl 0x1c96c)

# ---- Mod4 (ENABLE_COMM_CONSTRUCT): force comm engine to be KEPT (not datastore-destroyed) ----
# RUNTIME-PROVEN: factory 0x15ee4 builds comm, then per-engine gate 0x1617c (bhs 0x16194) runs a
# datastore name-lookup (0x2f1a8 over dictAll); comm absent -> sl=0 -> branch -> 0x158bc destructs
# comm + str 0,[0x9859c] (the NULL). NOP the bhs so comm falls through to register(0x283a0)+keep.
# No datastore edit -> bplist signature intact -> avoids the offline-edit poison. Triple-verified.
ENABLE_COMM_CONSTRUCT=True
COMM_KEEP_BHS=0x1617c
if ENABLE_COMM_CONSTRUCT:
    assert elf[foff(COMM_KEEP_BHS):foff(COMM_KEEP_BHS)+4]==bytes.fromhex('0400002a'), "comm keep bhs bytes (bhs 0x16194)"
    struct.pack_into('<I',elf,foff(COMM_KEEP_BHS),0xE1A00000)   # NOP -> always KEEP+REGISTER comm

assert len(elf)==494244

OUTNAME=('ARMiPhoneIAP2.commenable.patched' if ENABLE_COMM_CONSTRUCT else
         ('ARMiPhoneIAP2.commsub.patched' if ENABLE_COMM_SUBSCRIBE else 'ARMiPhoneIAP2.callfwd.patched'))
open(OUTNAME,'wb').write(elf)

print(f"OUTPUT: {OUTNAME}")
print(f"call  stage2 {len(cs2)} B @ {S2_VA:#x}")
print(f"call  stage1 {len(cs1)} B @ {S1_VA:#x}")
print(f"comm  fwd    {len(cf)} B @ {CF_VA:#x}  (hook 0x18ff8 dispatcher 0x4158 -> _commraw)")
print(f"comm  sub    {len(csub) if ENABLE_COMM_SUBSCRIBE else 0} B @ {CSUB_VA:#x}  (hook 0x285b0 -> select 17 children -> emit 0x4157)  END_FOFF {END_FOFF:#x}")
print(f"LOAD0 filesz/memsz -> {END_FOFF:#x} ; LOAD1 memsz -> 0x3010")
print(f"hooks: 0x296cc={elf[foff(C_HOOK1):foff(C_HOOK1)+4].hex()} 0x29960={elf[foff(C_HOOK2):foff(C_HOOK2)+4].hex()} "
      f"0x18ff8={elf[foff(M_FWD_HOOK):foff(M_FWD_HOOK)+4].hex()} 0x285b0={elf[foff(SUB_HOOK):foff(SUB_HOOK)+4].hex()}")
print(f"patched md5 {hashlib.md5(bytes(elf)).hexdigest()}")
md=Cs(CS_ARCH_ARM,CS_MODE_ARM)
for nm,blob,base,clen in [("COMMFWD",cf,CF_VA,0x98),("COMMSUB",csub,CSUB_VA,0x20)]:
    print(f"\n=== {nm} @ {base:#x} ===")
    for ins in md.disasm(blob[:clen], base):
        print(f"  {ins.address:#x}: {ins.mnemonic:<8}{ins.op_str}")

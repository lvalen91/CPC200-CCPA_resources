#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Python port of f-io/LIVI imx6ul kernel staging plan (Rust): native/livi-link/crates/imx6ul-uboot/src/lib.rs
# and native/livi-link/crates/livi-link-provision/src/dongle/arm/imx6ul/boot.rs (https://github.com/f-io/LIVI,
# GPL-3.0-or-later), read at 9.5.0.
# Based on LIVI by Lasse Heitgres (https://github.com/f-io/LIVI)
# Modified 2026-10-19/20: ported to Python as an offline dry run against flash backups (AES through openssl,
# files only, nothing written to a unit).
"""Offline dry run of LIVI's `imx6ul kernel <zImage>` plan against a flash backup. Reads files only."""
import sys,subprocess,struct,zlib,hashlib
ERASE=0x10000; UPDATE=0x20000; ENVB=0x30000; KERNEL=0x40000; HEAD=3*ERASE; LOAD=0x80800000; MAGIC=0x016f2818
mtd0=open(sys.argv[1],'rb').read(); cur=open(sys.argv[2],'rb').read(); z=open(sys.argv[3],'rb').read()
cfg=[int(x,16) for x in sys.argv[4:8]]
t=("%08x%08x%08x%08x"%tuple(cfg)).encode(); key,iv=t[:16],t[16:]
def cbc(b,d=False): return subprocess.run(['openssl','enc','-d' if d else '-e','-aes-128-cbc','-nopad','-K',key.hex(),'-iv',iv.hex()],input=b,capture_output=True,check=True).stdout
# read_env
blk=mtd0[UPDATE:UPDATE+ERASE]; n=struct.unpack('<I',blk[-4:])[0]
assert 0<n<=ERASE and n%16==0
env=zlib.decompressobj(31).decompress(cbc(blk[ERASE-n:],True)); assert len(env)==0x10000
assert zlib.crc32(env[4:0x800])==struct.unpack('<I',env[:4])[0]
v={}
for s in env[4:0x800].split(b'\0'):
    if not s: break
    k,_,x=s.decode('latin1').partition('='); v[k]=x
cmds=lambda s:[c.split() for c in s.split(';') if c.split()]
h=lambda s:int(s,16)
kl=next(h(c[4]) for c in cmds(v['norboot']) if c[:2]==['sf','read'] and h(c[2])==LOAD and c[3]=='0x40000')
assert [h(c[2]) for c in cmds(v['norboot']) if c[:2]==['mm','w']]==[LOAD,LOAD+ERASE,LOAD+2*ERASE]
frm=None;pairs=[]
for c in cmds(v['heweiencrypt']):
    if c[:2]==['sf','read'] and h(c[2])==LOAD and c[4]=='0x10000': frm=h(c[3])
    if c[:2]==['sf','update'] and h(c[2])==LOAD and c[4]=='0x10000' and frm is not None: pairs.append((frm,h(c[3]))); frm=None
staging=pairs[0][0]
exp=[(staging+i*ERASE,KERNEL+i*ERASE) for i in range(3)]
assert [p for p in pairs if p[1]!=ENVB]==exp, pairs
assert kl>HEAD and staging>=KERNEL+kl and staging+HEAD<=KERNEL+len(cur)
print("layout: kernel_len=%#x staging=%#x (partition offset %#x) convert pairs=%s"%(kl,staging,staging-KERNEL,[(hex(a),hex(b)) for a,b in pairs]))
assert len(z)>HEAD and z[0x24:0x28]==struct.pack('<I',MAGIC) and len(z)<=kl
so=staging-KERNEL
part=bytearray(b'\xff'*len(cur)); part[:HEAD]=cur[:HEAD]; part[HEAD:len(z)]=z[HEAD:]
part[so:so+HEAD]=b''.join(cbc(z[i*ERASE:(i+1)*ERASE]) for i in range(3))
unchanged = bytes(part)==cur
print("zImage: %d bytes sha256 %s"%(len(z),hashlib.sha256(z).hexdigest()[:16]))
print("plan.unchanged (kernel partition already holds this):",unchanged)
if not unchanged:
    diff=[i for i in range(len(cur)) if part[i]!=cur[i]]
    print("differing bytes:",len(diff),"first at %#x last at %#x"%(diff[0],diff[-1]))
    regions={"head(0..0x2ffff)":0,"body":0,"staging":0,"tail/other":0}
    for i in diff:
        regions["head(0..0x2ffff)" if i<HEAD else "body" if i<kl else "staging" if so<=i<so+HEAD else "tail/other"]+=1
    print(regions)
envblk=mtd0[ENVB:ENVB+ERASE]
print("mtd0 env block @%#x: %s; U-Boot+update block (first %#x bytes) is untouched by the flow"%(ENVB,"all 0xFF" if set(envblk)=={255} else "holds data (%d non-FF bytes)"%sum(1 for b in envblk if b!=255),ENVB))
print("sha256(current mtd1) =",hashlib.sha256(cur).hexdigest())
print("sha256(planned mtd1) =",hashlib.sha256(bytes(part)).hexdigest())

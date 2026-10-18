#!/usr/bin/env python3
"""Decode an appended 0x5202 RouteGuidanceManeuverUpdate burst (stage1_v3)."""
import sys

data = bytes.fromhex(open(sys.argv[1]).read().split()[0] if len(sys.argv) > 1
                     else sys.stdin.read().strip())

IDS = {0:'ComponentID', 1:'ManeuverListIndex', 2:'ManeuverDescription',
       3:'ManeuverType', 4:'AfterManeuverRoadName', 5:'DistanceBetweenManeuver',
       6:'DistanceDisplayStr', 7:'DistanceDisplayUnits', 8:'DrivingSide',
       9:'JunctionType', 0x0a:'JunctionElementAngle', 0x0b:'JunctionElementExitAngle'}
STR = {2, 4, 6}

def s16(v): return v - 0x10000 if v >= 0x8000 else v

off, n, roundabouts = 0, 0, 0
while off < len(data) - 5:
    if data[off] != 0x40 or data[off+1] != 0x40:
        off += 1
        continue
    L = (data[off+2] << 8) | data[off+3]
    msg = data[off:off+L+1]
    if len(msg) < 6:
        break
    p, fields = 6, {}
    parts = []
    while p + 4 <= len(msg):
        tl = (msg[p] << 8) | msg[p+1]
        tid = (msg[p+2] << 8) | msg[p+3]
        if tl < 4 or p + tl > len(msg):
            break
        val = msg[p+4:p+tl]
        fields.setdefault(tid, []).append(val)
        p += tl
    jt = int.from_bytes(fields.get(9, [b'\x00'])[0] or b'\x00', 'big')
    idx = int.from_bytes(fields.get(1, [b'\x00'])[0] or b'\x00', 'big')
    desc = fields.get(2, [b''])[0].split(b'\x00')[0].decode('ascii', 'replace')
    mtype = int.from_bytes(fields.get(3, [b'\x00'])[0] or b'\x00', 'big')
    road = fields.get(4, [b''])[0].split(b'\x00')[0].decode('ascii', 'replace')
    dist = int.from_bytes(fields.get(5, [b'\x00'])[0] or b'\x00', 'big')
    dstr = fields.get(6, [b''])[0].split(b'\x00')[0].decode('ascii', 'replace')
    angs = [s16(int.from_bytes(v, 'big')) for v in fields.get(0x0a, [])]
    exit_ang = [s16(int.from_bytes(v, 'big')) for v in fields.get(0x0b, [])]
    flag = '  <<< ROUNDABOUT' if jt == 1 else ''
    if jt == 1:
        roundabouts += 1
    print(f"[{idx:2d}] type={mtype:<3d} jct={jt}  {desc!r}{flag}")
    print(f"     after='{road}'  dist={dist} ({dstr})  "
          f"elemAngles={angs}  exitAngle={exit_ang}")
    off += L + 1
    n += 1

print(f"\n{n} maneuvers decoded, {roundabouts} roundabout(s), {len(data)} bytes")

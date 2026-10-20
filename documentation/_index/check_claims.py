#!/usr/bin/env python3
"""Check the claims ledgers in documentation/_index/claims/ against the current docs.

Usage: python3 -I documentation/_index/check_claims.py [REPO_ROOT] [GID_FILTER]

REPO_ROOT defaults to the repository that contains this script. For every claim it checks
that the file exists, that the quote (whitespace-normalised) appears at its source_lines
(the line range plus as many lines as the quote has), and that claim_count and gid
uniqueness hold. "quote moved" = the quote is in the file but not at source_lines;
"quote not found" = the quote is nowhere in the file. GID_FILTER prints only problems
whose gid contains that string. Exit status 1 if any problem is found. Stdlib only.
"""
import glob
import json
import os
import re
import sys
from collections import Counter


def norm(s):
    return re.sub(r'\s+', ' ', s)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(here))
    flt = sys.argv[2] if len(sys.argv) > 2 else None
    doc = os.path.join(root, 'documentation')
    tot = 0
    bad = []
    for f in sorted(glob.glob(os.path.join(doc, '_index/claims/*.json'))):
        with open(f, encoding='utf-8') as fh:
            j = json.load(fh)
        cl = j['claims']
        if j.get('claim_count') != len(cl):
            bad.append((os.path.basename(f), 'claim_count %s != %d' % (j.get('claim_count'), len(cl))))
        gids = [c['gid'] for c in cl]
        if len(set(gids)) != len(gids):
            bad.append((os.path.basename(f), 'dup gid'))
        cache = {}
        for c in cl:
            tot += 1
            p = os.path.join(doc, c['file'])
            if not os.path.exists(p):
                p2 = os.path.join(root, c['file'])
                p = p2 if os.path.exists(p2) else p
            if not os.path.exists(p):
                bad.append((c['gid'], 'missing file'))
                continue
            if p not in cache:
                with open(p, encoding='utf-8', errors='replace') as fh:
                    cache[p] = fh.read().split('\n')
            lines = cache[p]
            q = norm(c.get('quote') or '')
            nums = [int(x) for x in re.findall(r'\d+', str(c.get('source_lines') or ''))]
            if not q:
                bad.append((c['gid'], 'no quote'))
                continue
            if nums:
                a, b = min(nums), max(nums)
                span = (c.get('quote') or '').count('\n') + 1
                seg = norm(' '.join(lines[max(0, a - 1):b + span]))
                if q in seg:
                    continue
                if q in norm('\n'.join(lines)):
                    bad.append((c['gid'], 'quote moved (lines %s)' % c.get('source_lines')))
                    continue
            bad.append((c['gid'], 'quote not found'))
    print('claims', tot, 'problems', len(bad))
    print(Counter(b[1].split(' (')[0] for b in bad))
    by_file = Counter(b[0].split('#')[0] for b in bad)
    for name, n in sorted(by_file.items()):
        print('  %5d  %s' % (n, name))
    for b in bad:
        if flt is not None and flt in b[0]:
            print(b)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())

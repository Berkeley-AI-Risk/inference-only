#!/usr/bin/env python3
"""Offline full-array check of a blank or baseline-preserving SWIC install.

The result is for that stated layout. It does not certify preservation of an
unrecorded factory/configuration region. --baseline checks preservation of every
other captured byte. Preserve complete independent backups beforehand.
"""
from pathlib import Path
import argparse,hashlib,json
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--plan',type=Path,required=True);p.add_argument('--readback',type=Path,required=True)
p.add_argument('--baseline',type=Path,help='Preserve all bytes outside the fixed writes from this complete pre-install backup')
a=p.parse_args();plan=json.loads(a.plan.read_text())
if a.readback.stat().st_size!=16777216:raise SystemExit('Readback must be the complete 16 MiB array')
actual=a.readback.read_bytes();expected=bytearray(b'\xff'*16777216)
if a.baseline:
    if a.baseline.stat().st_size!=16777216:raise SystemExit('Baseline must be the complete 16 MiB array')
    expected=bytearray(a.baseline.read_bytes())
intervals=[]
for r in plan['writes']:
    data=(a.plan.parent/r['file']).read_bytes()
    if len(data)!=r['bytes'] or hashlib.sha256(data).hexdigest()!=r['sha256']:raise SystemExit('Prepared data changed')
    start=r['address'];end=start+len(data)
    if not 0<=start<end<=len(expected) or any(start<b and end>a for a,b in intervals):raise SystemExit('Invalid/overlapping flash plan')
    intervals.append((start,end));expected[start:end]=data
if actual!=expected:
    first=next(i for i,(x,y) in enumerate(zip(actual,expected)) if x!=y)
    raise SystemExit(f'Full-array mismatch at 0x{first:06x}')
print(json.dumps({'result':'PASS','bytes':len(actual),'sha256':hashlib.sha256(actual).hexdigest(),
    'layout':'preserved baseline outside model and padded signed-admission slot' if a.baseline else 'erased outside model and padded signed-admission slot',
    'baseline_sha256':hashlib.sha256(a.baseline.read_bytes()).hexdigest() if a.baseline else None},indent=2))

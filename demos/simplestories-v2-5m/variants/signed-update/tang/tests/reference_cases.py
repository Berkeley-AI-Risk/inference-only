#!/usr/bin/env python3
"""Independent published vectors plus adversarial package tests; no training."""
import argparse
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su


def rfc_test_case(text):
    section=text[text.index('   Test Case 1 Public Key\n'):text.index('   Test Case 2 Private Key\n')]
    parts=[]
    for line in section.splitlines():
        m=re.match(r'^\s*(?:(?:levels|LMS type|LMOTS type|I|K|Message|Nspk|q|C|y\[\d+\]|path\[\d+\])\s+)?([0-9a-f]{4,})(?=\s*(?:#|\||$))',line)
        if m:parts.append(bytes.fromhex(m.group(1)))
    blob=b''.join(parts)
    public_key=blob[4:60]
    msg_start=60
    # The RFC message terminates with the two bytes period/newline.
    msg_end=blob.index(b'.\n',msg_start)+2
    message=blob[msg_start:msg_end]
    hss=blob[msg_end:]
    assert hss[:4]==su.U32(1)
    first=hss[4:4+su.SIG_BYTES]
    child=hss[4+su.SIG_BYTES:4+su.SIG_BYTES+56]
    final=hss[4+su.SIG_BYTES+56:]
    assert len(final)==su.SIG_BYTES,(len(final),len(blob))
    return [(public_key,child,first),(child,message,final)]


def main():
    p=argparse.ArgumentParser()
    p.add_argument('demo',type=Path,help='canonical SimpleStories demo directory')
    p.add_argument('--output',type=Path,default=ROOT/'evidence/generated')
    args=p.parse_args()
    out=args.output;out.mkdir(parents=True,exist_ok=True)
    results=[];vectors=[]
    def vector(name,key,msg,sig,expected):
        assert su.lms_verify(key,msg,sig)==expected,name
        vectors.append({'name':name,'key':key.hex(),'message':msg.hex(),
                        'signature':sig.hex(),'expected':expected})
    fixture=json.loads((ROOT/'tests/rfc8554-case1.json').read_text())
    published=[tuple(bytes.fromhex(v[k]) for k in ('key','message','signature')) for v in fixture['vectors']]
    for i,(key,msg,sig) in enumerate(published):
        vector('rfc8554-case1-'+str(i),key,msg,sig,True)
        changed=bytes([msg[0]^1])+msg[1:]
        vector('rfc8554-message-mutation-'+str(i),key,changed,sig,False)
    authorities=[su.DemoAuthority(i) for i in range(3)]
    keys=[a.public_key for a in authorities]
    image=(args.demo/'assets/board1-real-semantic-image2048.bin').read_bytes()
    metadata=bytes.fromhex(''.join((args.demo/'hardware/project/metadata192.memh').read_text().split()))
    changed_metadata=bytes([metadata[0]^1])+metadata[1:]
    metadata_image=bytearray(image)
    metadata_image[211920*32+7*4+2]^=1  # matching native expanded metadata byte
    for version,data,meta in [(1,image,metadata),(2,bytes([image[0]^1])+image[1:],metadata),
                              (3,bytes(metadata_image),changed_metadata)]:
        pkg=su.make_package(data,meta,version,authorities[:2],[version-1]*2)
        info=su.verify_package(pkg,keys)
        (out/f'model-{version}.swic').write_bytes(pkg)
        (out/f'model-{version}.boot').write_bytes(pkg[:-su.IMAGE_BYTES])
        for slot in range(2):
            at=132+slot*(4+su.SIG_BYTES)
            vector(f'demo-{version}-authority-{slot}',keys[slot],pkg[:128],pkg[at+4:at+4+su.SIG_BYTES],True)
        results.append({'test':f'valid-model-{version}','result':'PASS',**info})
    pkg=(out/'model-1.swic').read_bytes()
    payload_at=132+2*(4+su.SIG_BYTES)
    def mutation(name,offset,value=None):
        b=bytearray(pkg)
        b[offset]=b[offset]^1 if value is None else value
        return name,bytes(b)
    bad=[('empty',b''),('truncated',pkg[:-1]),('oversized',pkg+b'\0'),
         mutation('domain',0),mutation('geometry',16),mutation('reserved',104),
         mutation('policy',63),mutation('manifest-root',72),
         mutation('one-signer',131,1),mutation('zero-signers',131,0),
         mutation('four-signers',131,4),mutation('unknown-signer',135,3),
         mutation('duplicate-signer',132+4+su.SIG_BYTES+3,0),
         mutation('signature-chain',132+4+40),mutation('signature-path',132+4+1132),
         mutation('image-hash',payload_at),mutation('page-table',payload_at+32),
         mutation('metadata',payload_at+32+su.PAGES*32),mutation('image',len(pkg)-1)]
    for name,b in bad:
        try:su.verify_package(b,keys)
        except su.Reject as e:results.append({'test':name,'result':'REJECTED','reason':str(e)})
        else:raise AssertionError('accepted '+name)
    # This variant intentionally permits an older valid signed model on reboot.
    assert su.verify_package(pkg,keys)['version']==1
    results.append({'test':'valid-signed-rollback-is-permitted','result':'PASS'})
    # Verify exact digest table compatibility with the existing native ROM.
    native=bytes.fromhex(''.join((args.demo/'hardware/project/digests32.memh').read_text().split()))
    assert native==su.digest_table(image)
    results.append({'test':'all-1774-native-page-digests','result':'PASS'})
    # Exercise durable reservation and refusal to continue with corrupt state.
    state=out/'temporary-demo-state.json'
    if state.exists():state.unlink()
    assert su.reserve_demo_leaves(state,2)==[0,0]
    assert su.reserve_demo_leaves(state,2)==[1,1]
    state.write_text('broken')
    try:su.reserve_demo_leaves(state,2)
    except json.JSONDecodeError:pass
    else:raise AssertionError('corrupt signer state accepted')
    state.unlink()
    results.append({'test':'signer-reserves-before-use-and-corrupt-state-rejected','result':'PASS'})
    (out/'lms-vectors.json').write_text(json.dumps(vectors,indent=2)+'\n')
    (out/'reference-results.json').write_text(json.dumps(results,indent=2)+'\n')
    (out/'public-keys.json').write_text(json.dumps([k.hex() for k in keys],indent=2)+'\n')
    print(json.dumps({'reference_cases':len(results),'lms_vectors':len(vectors),'output':str(out)},indent=2))


if __name__=='__main__':main()

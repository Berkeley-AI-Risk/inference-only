#!/usr/bin/env python3
"""Local HTTP revocation demo with real signed SimpleStories packages.

Uses a controlled software clock to demonstrate expiry quickly. It does not
measure wall time, run FPGA hardware, or generate model tokens.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import threading
from urllib.request import Request, urlopen
from urllib.error import HTTPError

sys.path.insert(0,str(Path(__file__).resolve().parent))
from home_auth import BootDevice, Reject, policy_for, su
from home_server import make_server


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--demo-root',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    image=(a.demo_root/'assets/board1-real-semantic-image2048.bin').read_bytes()
    metadata=bytes.fromhex(''.join((a.demo_root/'hardware/project/metadata192.memh').read_text().split()))
    changed=bytearray(image);changed[0]^=1
    authorities=[su.DemoAuthority(i) for i in range(3)]
    packages=[su.make_package(value,metadata,1,authorities[:2],[q,q])
              for q,value in enumerate([image,bytes(changed)])]
    keys=[v.public_key for v in authorities]
    records=[su.verify_package(pkg,keys) for pkg in packages]
    roots=[bytes.fromhex(v['model_root']) for v in records]
    policy=a.output/'policy.json';policy.write_text(json.dumps(policy_for(roots),indent=2)+'\n')
    server=make_server(policy,a.output/'signer-state.json')
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    now=[0.0]
    device=BootDevice(server.home.public_key,clock=lambda:now[0],timeout=10,lease=60)
    events=[]

    def record(event):
        events.append({'software_time':now[0],'event':event})

    def authorize(request):
        req=Request(f'http://127.0.0.1:{server.server_port}/authorize',data=request,
                    headers={'Content-Type':'application/octet-stream'})
        with urlopen(req,timeout=5) as response:return response.read()

    try:
        request=device.boot_package(packages[0],keys)
        device.accept(authorize(request));assert device.require_inference()==roots[0]
        record('model A authenticated and authorized')
        now[0]=45
        device.accept(authorize(device.renew()));assert device.require_inference()==roots[0]
        record('model A authorization renewed with a fresh nonce')
        policy.write_text(json.dumps(policy_for([roots[1]]),indent=2)+'\n')
        record('home-base policy revokes A; B remains approved')
        now[0]=90
        try:authorize(device.renew())
        except HTTPError as error:
            assert error.code==403;record('home base refuses renewal for A')
        else:raise AssertionError('revoked model obtained renewal')
        assert device.require_inference()==roots[0]
        record('existing A lease remains valid before its deadline')
        now[0]=105
        try:device.require_inference()
        except Reject:record('A is disabled at lease expiry')
        else:raise AssertionError('expired authorization remained usable')
        device.accept(authorize(device.boot_package(packages[1],keys)))
        assert device.require_inference()==roots[1]
        record('distinct signed model B authenticates and receives authorization')
        result={'result':'PASS','PUBLIC_DEMO_KEYS':True,'time_source':'controlled software clock',
                'nonce_source':'secrets.token_bytes: operating-system CSPRNG',
                'executes_model_tokens':False,'models':records,'events':events,
                'input_image_sha256':hashlib.sha256(image).hexdigest()}
        (a.output/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2))
    finally:
        server.shutdown();server.server_close();thread.join()


if __name__=='__main__':main()

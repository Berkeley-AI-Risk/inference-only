#!/usr/bin/env python3
"""Verify a signed demonstration package and create an allowlist; no hardware access."""
from pathlib import Path
import argparse,json,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'reference'))
import home_auth as h
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--policy',type=Path,required=True)
a=p.parse_args();assert not a.policy.exists(),'Preserve existing policy; replace it atomically to change a running service'
keys=[h.su.DemoAuthority(i).public_key for i in range(3)]
info=h.su.verify_package(a.package.read_bytes(),keys)
root=info['model_root'];a.policy.parent.mkdir(parents=True,exist_ok=True)
a.policy.write_text(json.dumps(h.policy_for([bytes.fromhex(root)]),indent=2)+'\n')
print(json.dumps({'device':h.DEVICE_ID.hex(),'model_root':root,'policy':str(a.policy)}))

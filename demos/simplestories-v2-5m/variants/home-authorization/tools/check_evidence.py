#!/usr/bin/env python3
"""Check the packaged physical campaign and exact source/artifact identities offline."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
def verify(target=ROOT,capture=None):
 target=Path(target);capture=Path(capture)if capture else target/'evidence/repair-board-2026-11-05'
 identity=json.loads((target/'SOURCE-IDENTITY.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 for name,digest in identity['native_inputs'].items():assert sha(target/'hardware'/name)==digest,name
 assert sha(target/'prebuilt/home_product.fs')==identity['prebuilt_sha256']
 with tempfile.TemporaryDirectory(prefix='home-evidence-audit-')as work:
  output=Path(work)/'AUDIT.json'
  command=[sys.executable,'-I','-B',str(target/'integration/audit_board.py'),'--campaign',str(capture),'--build',str(target/'evidence/repair-native-2026-11-05'),'--reference',str(capture/'common-reference.json'),'--output',str(output),'--restored-image',str(capture/'restored-original.fs.gz')]
  result=subprocess.run(command,capture_output=True,text=True)
  if result.returncode:raise ValueError('Physical evidence audit failed: '+result.stdout+result.stderr)
  checked=json.loads(output.read_text())
 assert checked==json.loads((capture/'EVIDENCE-AUDIT.json').read_text()),'Saved physical evidence audit differs'
 return checked
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path);a=p.parse_args();checked=verify()
 if a.output:
  assert not a.output.exists();a.output.write_text(json.dumps(checked,indent=2)+'\n')
 print(json.dumps({k:v for k,v in checked.items()if k!='source_hashes'}))

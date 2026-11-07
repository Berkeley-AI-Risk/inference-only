"""Read-only selected input integrity for one output-directory replay."""
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent
CONFIG=json.loads((HERE/'CONFIG.json').read_text())
CHECKOUT=Path(CONFIG['repository']);DEMO=Path(CONFIG['demo'])
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    inputs=json.loads((HERE/'SOURCE-INPUTS.json').read_text())
    for name,row in inputs['files'].items():
        p=CHECKOUT/name
        if p.is_symlink() or not p.is_file() or p.stat().st_size!=row['bytes'] or sha(p)!=row['sha256']:
            raise ValueError('Pinned public input differs: '+name)
    print('PASS_SELECTED_SOURCE_INPUTS',len(inputs['files']),flush=True)
if __name__=='__main__':main()

"""Check the complete frozen packet or freshly compile and replay both proofs.

Python orchestrates Yosys, Z3 and Icarus Verilog. It is not a proof assistant.
The proof statements are the native transition systems, declarative SMT plans
and readable THEOREM.md files. Unknown, timeout or a changed query fails closed.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE=Path(__file__).resolve().parent
MODEL=HERE.parent.parent
sys.path.insert(0,str(HERE))


def sha(raw):return hashlib.sha256(raw).hexdigest()
def load(path):return json.loads(path.read_text())


def check_packet():
    packet=load(HERE/'PACKAGE.json')
    for name,want in packet['files'].items():
        p=HERE/name
        if not p.is_file() or p.is_symlink():raise ValueError('Missing/linked packet member: '+name)
        raw=p.read_bytes()
        if dict(bytes=len(raw),sha256=sha(raw))!=want:raise ValueError('Packet bytes changed: '+name)
    # Bind each full cache compiler source to the production module bodies.
    for manifest_name,folder,order in [
        ('model-operands/SOURCES.json','model-operands/project',['bank.sv','sha.sv']),
        ('model-operands/SERVICE-SOURCES.json','model-operands/service-project',['bank.sv','sha.sv','service.sv'])]:
        manifest=load(HERE/manifest_name);bodies=[]
        from prepare import modules,verify_inventory
        verify_inventory()
        for name,row in manifest['sources'].items():
            raw=(MODEL/row['model_source']).read_bytes()
            if sha(raw)!=row['sha256']:raise ValueError('Cache source identity changed: '+name)
        for name in order:
            defs=modules((MODEL/manifest['sources'][name]['model_source']).read_text())
            bodies.extend(defs[m] for m in manifest['sources'][name]['modules'])
        exact='`undef FORMAL\n`default_nettype none\n'+'\n\n'.join(bodies)+'\n'
        if (HERE/folder/'native.sv').read_text()!=exact:raise ValueError('Cache compiler source differs from production modules')
        for name,digest in manifest.get('tables',{}).items():
            if sha((MODEL/'hardware/project'/name).read_bytes())!=digest or sha((HERE/folder/name).read_bytes())!=digest:
                raise ValueError('Cache table identity changed')
    caller=(MODEL/'hardware/project/uart_core.sv').read_text()
    if '#(.AUTH_BANKS(4)) u_machine' not in caller:raise ValueError('Four-bank production caller changed')
    return packet


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--recorded-only',action='store_true')
    ap.add_argument('--out',type=Path)
    args=ap.parse_args();packet=check_packet()
    if args.out and args.out.exists():raise ValueError('--out must be a new directory')
    if not args.recorded_only and not args.out:raise ValueError('Fresh reproduction requires --out')
    temporary=tempfile.TemporaryDirectory(prefix='native-values-') if args.out is None else None
    out=Path(temporary.name) if temporary else args.out.resolve()
    out.mkdir(parents=True,exist_ok=True)
    try:
        proof=out/'model/formal/native-component-values'
        proof.mkdir(parents=True)
        for name in [*packet['files'],'PACKAGE.json']:
            p=proof/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(HERE/name,p)
        # A self-contained rehearsal: only declared production inputs are
        # copied, and the private development workspace is never consulted.
        sources=set()
        for name in ['SOURCES.json','model-operands/SOURCES.json','model-operands/SERVICE-SOURCES.json']:
            value=load(HERE/name)
            sources.update(row['model_source'] for row in value.get('files',value.get('sources',{})).values())
        sources.update(['hardware/project/metadata192.memh','hardware/project/digests32.memh',
                        'assets/board1-real-semantic-image2048.bin'])
        for name in sources:
            p=out/'model'/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(MODEL/name,p)
        identities=load(HERE/'QUERY-IDENTITIES.json')
        if len(identities['queries'])!=136:raise ValueError('Incomplete query census')
        for row in identities['queries']:
            path=proof/row['path'];raw=gzip.decompress(path.with_suffix('.smt2.gz').read_bytes())
            if sha(raw)!=row['sha256']:raise ValueError('Frozen exact query changed')
            path.write_bytes(raw)
        # Each verifier separately regenerates and compares every query,
        # validates acyclic imports/case coverage and original raw replies.
        for script in ['verify.py','model-operands/verify.py']:
            command=[sys.executable,'-B',str(proof/script)]
            if args.recorded_only:command+=['--validate-only']
            subprocess.run(command,check=True)
        if not args.recorded_only:
            # RMSNorm's verifier checks complete saved finite transcripts;
            # also rerun all 13 native roles and both actual-only defects.
            (proof/'witnesses').rename(proof/'recorded-witnesses')
            jobs=[['--case','native','--role',str(r)] for r in range(13)]
            jobs += [['--case',kind,'--role','12'] for kind in ['stale-state','wrong-operand']]
            def witness(arguments):
                cp=subprocess.run([sys.executable,'-B',str(proof/'witness.py'),*arguments],capture_output=True,text=True)
                if cp.returncode:raise ValueError('Finite RMSNorm control failed: '+cp.stdout+cp.stderr)
            with ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(witness,jobs))
            subprocess.run([sys.executable,'-B',str(proof/'validate_witnesses.py')],check=True)
        for script in ['check_model_rom.py','check_model_tables.py']:
            subprocess.run([sys.executable,'-B',str(proof/script)],check=True)
        result=dict(passed=True,recorded_only=args.recorded_only,engine_queries=136,
                    expected_unsat=135,expected_sat=1,fresh_source_recompiled=not args.recorded_only,
                    operating_controls_rerun=not args.recorded_only,
                    upstream_raw_read_contract_discharged=False,whole_machine_theorem=False)
        (out/'RESULT.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
        print(json.dumps(result))
    finally:
        if temporary:temporary.cleanup()


if __name__=='__main__':main()

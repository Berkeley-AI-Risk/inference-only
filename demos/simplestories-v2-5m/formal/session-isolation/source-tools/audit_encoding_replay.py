"""Re-encode pinned RTLIL and require exact equality with each selected model.

Checking a model hash alone does not check how it was obtained. This audit
replays the finite-memory lowering and state encoding, without rerunning the
solver searches or changing their frozen receipts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);jobs=[]
    for variant,original,interface in [
        ('baseline','attention-clear-baseline-r2','attention-interface-baseline-r1'),
        ('protected','attention-clear-kv-protected-r2','attention-interface-protected-r1')]:
        derived=HERE/'runs'/interface
        cert=json.loads((derived/'rechecked-parent-certificate.json').read_text())
        for row in cert['part_results']:
            part=Path(row['path']);d=json.loads((part/'FINISHED.json').read_text())
            jobs.append((variant+'-'+part.name,HERE/'runs'/original,part/'model.smt2'if d['state_encoding']=='bitvector'else
                HERE/'runs'/original/'design.smt2',d['state_encoding'],d['exact_finite_memories_mapped'],d['rtlil_sha256'],d['model_sha256'],True))
        d=json.loads((derived/'FINISHED.json').read_text())
        source=HERE/'runs'/('attention-all-inputs-baseline-r1'if variant=='baseline'else'attention-all-inputs-protected-r1')
        jobs.append((variant+'-interfaces',source,derived/'model.smt2','bitvector',True,d['rtlil_sha256'],d['model_sha256'],False))
    part=HERE/'runs/exp-session-valid-r1-z3';d=json.loads((part/'FINISHED.json').read_text())
    jobs.append(('exp',HERE/'runs/exp-session-valid-r1',part/'model.smt2','bitvector',d['exact_finite_memories_mapped'],d['rtlil_sha256'],d['model_sha256'],True))
    part=HERE/'runs/elementwise-relevant-ready-r2-z3';d=json.loads((part/'FINISHED.json').read_text())
    jobs.append(('elementwise',HERE/'runs/elementwise-relevant-ready-r2',part/'model.smt2','bitvector',
        d['exact_finite_memories_mapped'],d['rtlil_sha256'],d['model_sha256'],True))
    rows={}
    for name,source,model,encoding,mapped,rtl_hash,model_hash,serialize_json in jobs:
        rtl=(source/'elaborated.il').read_bytes()
        if sha(rtl)!=rtl_hash or sha(model.read_bytes())!=model_hash:raise ValueError('Frozen model/input changed')
        target=out/name;target.mkdir();(target/'elaborated.il').write_bytes(rtl)
        recipe=('read_rtlil elaborated.il\n'+('memory_map\ndffunmap\nopt_clean\n'if mapped else'')+
            ('write_json encoded.json\n'if serialize_json else'')+
            'write_smt2 '+('-stbv 'if encoding=='bitvector'else'')+'-wires model.smt2\n')
        (target/'encode.ys').write_text(recipe)
        with(target/'yosys.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=target,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or not(target/'model.smt2').exists():raise ValueError('Encoding replay failed')
        actual=sha((target/'model.smt2').read_bytes())
        if actual!=model_hash:raise ValueError('Replayed SMT model differs: '+name)
        rows[name]=dict(source_run=str(source),source_rtlil_sha256=rtl_hash,original_model=str(model),
            exact_model_sha256=actual,replay_log_sha256=sha((target/'yosys.log').read_bytes()),
            replay_recipe_sha256=sha(recipe.encode()),state_encoding=encoding,finite_memories_mapped=mapped)
    result=dict(exact_encoding_replay_passed=True,models=rows,runner_sha256=sha(Path(__file__).read_bytes()))
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    (HERE/'ENCODING-REPLAY.json').write_text(json.dumps(dict(result,receipt=str(out/'FINISHED.json')),indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(exact_encoding_replay_passed=True,model_records=len(rows))))


if __name__=='__main__':main()

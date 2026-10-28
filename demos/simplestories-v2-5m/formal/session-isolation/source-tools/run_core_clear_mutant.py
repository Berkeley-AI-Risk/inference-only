"""Detect a real premature CLEAR-to-IDLE branch in the connected native core.

The hypothetical change is confined to a frozen proof copy. Full native shell
RAMs remain. A concrete healthy command/late-reply trace exercises the bug.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from record_progress import sha


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45);args=ap.parse_args()
    prior=HERE/'runs/core-model-drain-r2';inp=json.loads((prior/'INPUTS.json').read_text())
    trace=HERE/'runs/core-cover-trace-r2';cover=json.loads((trace/'FINISHED.json').read_text())
    if not cover['passed']or cover['source_inputs_sha256']!=sha((prior/'INPUTS.json').read_bytes()):
        raise ValueError('Healthy full-native-RAM trace not qualified')
    files={}
    for name,row in inp['files'].items():
        raw=(prior/name).read_bytes()
        if sha(raw)!=row['sha256']:raise ValueError('Changed positive source')
        files[name]=raw
    shell=files['shell.sv'].decode()
    pattern=r'if\s*\(!embed_busy\s*&&\s*!rms_busy\s*&&\s*!argmax_busy\s*&&\s*!private_layer_busy_i\)'
    matches=list(re.finditer(pattern,shell))
    if len(matches)!=1:raise ValueError('Actual CLEAR drain wait is not unique')
    before=matches[0][0];after="if (1'b1)"
    shell=shell.replace(before,after,1);files['shell.sv']=shell.encode()
    files['clear-wait-mutation.json']=json.dumps(dict(before=before,after=after,
        native_module='board1_context2048_token_shell',native_state='ST_CLEAR_DRAIN',
        full_native_RAMs=True,implementation_files_changed=False),indent=2).encode()
    files['mutant-runner.py']=Path(__file__).read_bytes()
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top=inp['top'],
        reset_constraints=(trace/'cover.smtc').read_text(),
        assertions=inp['assertion_cells'],covers=inp['cover_cells'],binding=dict(inp['binding'],
            mutation='Premature native CLEAR_DRAIN release without waiting for embedding/semantic drain.',
            positive_trace_receipt_sha256=sha((trace/'FINISHED.json').read_bytes())),
        cuts=inp['internal_cuts'],depth=22,induction_depth=1,cover_depth=22,timeout=args.timeout,
        mutant='premature-native-clear-idle',source_list=inp['compile_sources'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        constraint_scope_description='Concrete healthy runtime trace applies to this BMC sensitivity experiment only; no unbounded induction is requested.',
        scope='Hypothetical actual shell CLEAR_DRAIN wait removal inside the full connected native core with native shell RAMs. A real accepted model read remains queued when the shell releases IDLE. Bounded checks must detect lost ownership/premature readiness under the same healthy input trace that reaches the unmodified core barrier. Production sources/images unchanged.')


if __name__=='__main__':raise SystemExit(main())

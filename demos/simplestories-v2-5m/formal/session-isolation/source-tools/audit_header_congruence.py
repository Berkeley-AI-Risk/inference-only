"""Check that the actual header validator is a fixed stateless function.

Equal inputs to the same finite combinational circuit imply equal output.
This checks that the native cone has only the named header input dependencies,
no storage, no arbitrary cells and no vendor/child boundary in that cone.
It proves congruence, not correctness of the validation policy itself.
"""
import argparse
import json
from pathlib import Path
import subprocess

from record_progress import sha

TOP='board1_shared_projection_scale_group_adapter'
INPUTS={'group_layer_i','group_job_i','group_index_i','group_valid_lanes_i',
    'group_row_exponent_i','group_row_multiplier_i','activation_exponent_i'}
PURE={'$add','$sub','$mul','$lt','$le','$ge','$gt','$eq','$ne','$eqx','$nex',
    '$logic_and','$logic_or','$logic_not','$and','$or','$xor','$xnor','$not',
    '$mux','$pmux','$reduce_or','$reduce_and','$reduce_bool','$reduce_xor','$reduce_xnor',
    '$pos','$neg','$sshl','$sshr','$shl','$shr','$shift','$shiftx','$concat','$slice'}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();run=args.run.resolve();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    inputs=json.loads((run/'INPUTS.json').read_text());manifest={}
    for name,row in inputs['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Frozen adapter input changed')
        manifest[str(run/name)]=row['sha256']
    manifest[str(run/'INPUTS.json')]=sha((run/'INPUTS.json').read_bytes())
    if inputs['binding']['concrete_module']!=TOP:raise ValueError('Wrong native controller')
    source=(run/'adapter.sv').read_bytes();(out/'adapter.sv').write_bytes(source)
    recipe='read_verilog -formal -sv -nosynthesis -D SYNTHESIS adapter.sv\nhierarchy -check -top '+TOP+'\nprep -top '+TOP+' -flatten\nmemory_map -rom-only\nopt -full\nwrite_json cone.json\n'
    (out/'cone.ys').write_text(recipe)
    with(out/'yosys.log').open('w')as log:cp=subprocess.run(['yosys','-Q','cone.ys'],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Header cone elaboration failed')
    g=json.loads((out/'cone.json').read_text())['modules'][TOP]
    roots={b:name for name,p in g['ports'].items()if p['direction']=='input'for b in p['bits']if isinstance(b,int)}
    drivers={}
    for name,cell in g['cells'].items():
        for port,bits in cell['connections'].items():
            if cell['port_directions'][port]!='output':continue
            for b in bits:
                if isinstance(b,int):drivers.setdefault(b,set()).add(name)
    dependencies=set();visited=set();active=set();cells=set()
    def visit(bit):
        if isinstance(bit,str):
            if bit not in('0','1'):raise ValueError('Unknown bit in immutable header function')
            return
        if bit in visited:return
        if bit in active:raise ValueError('Combinational cycle in header cone')
        if bit in roots:
            dependencies.add(roots[bit]);visited.add(bit);return
        owners=drivers.get(bit,set())
        if len(owners)!=1:raise ValueError('Missing or multiple header-cone drivers')
        name=next(iter(owners));cell=g['cells'][name]
        if cell['type']not in PURE:raise ValueError('Header depends on storage or an unreviewed primitive: '+cell['type'])
        active.add(bit);cells.add(name)
        for port,bits in cell['connections'].items():
            if cell['port_directions'][port]=='input':
                for b in bits:visit(b)
        active.remove(bit);visited.add(bit)
    output=g['netnames']['header_protocol_error']['bits']
    if len(output)!=1:raise ValueError('Header validator output width changed')
    visit(output[0])
    if dependencies!=INPUTS:raise ValueError('Native header dependency set differs: '+repr(dependencies))
    cell_records={name:g['cells'][name]for name in sorted(cells)}
    result=dict(stateless_native_header_congruence_checked=True,
        source_adapter_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),
        production_source_sha256=sha((run/'production-adapter.sv').read_bytes()),
        formal_source_sha256=sha(source),dependencies={name:len(g['ports'][name]['bits'])for name in sorted(dependencies)},
        cone_cells=len(cells),cone_cell_types=sorted({r['type']for r in cell_records.values()}),
        mutable_or_opaque_cone_cells=0,
        statement='The identical source-bound finite combinational header circuit has no storage or unobserved input dependency. Matching these seven complete native inputs implies matching validation output; the relation needs this only while group_valid_i is true.',
        numerical_validation_policy_correctness_claimed=False,whole_device_theorem=False,
        source_manifest=manifest,cone_json_sha256=sha((out/'cone.json').read_bytes()),
        recipe_sha256=sha(recipe.encode()),log_sha256=sha((out/'yosys.log').read_bytes()),
        runner_sha256=sha(Path(__file__).read_bytes()))
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in('stateless_native_header_congruence_checked','cone_cells','mutable_or_opaque_cone_cells')}))


if __name__=='__main__':main()

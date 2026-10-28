"""Check connected-cluster source wiring, finite stores and exact joint query.

Replay the finite-memory encoding and reconstruct the complete base/induction
queries. No source result is credited just from a successful solver exit code.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from record_progress import audit, sha
from run_attention_ownership import HERE, load
from run_projection_relational import instance_con
from run_service_relational import width
from join_parent_conclusions import checked_query, query_templates, template_text


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',required=True);ap.add_argument('--part',required=True)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    run=HERE/'runs'/args.run;part=HERE/'runs'/args.part
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    manifest={}
    def pin(path,digest=None):
        raw=path.read_bytes();actual=sha(raw)
        if digest is not None and actual!=digest:raise ValueError('Changed proof artifact: '+str(path))
        manifest[str(path.resolve())]=actual;return raw
    inp=json.loads(pin(run/'INPUTS.json'));base=json.loads(pin(run/'FINISHED.json'))
    p=json.loads(pin(part/'FINISHED.json'));serial=inp['binding']['serial'];top=inp['top']
    for n,row in inp['files'].items():
        if len(pin(run/n,row['sha256']))!=row['bytes']:raise ValueError('Source byte count changed')
    if(inp['assumption_cells']or inp['observer_constants']!=1 or inp['binding']['initial_hard_reset']or
        inp['binding']['tile_reply_cuts']or inp['changed_production_parameters']):
        raise ValueError('Unexpected assumptions, reset policy or functional tile cuts')
    if inp['reset_constraints']!='Only base/cover states 0 and 1 are constrained; no reset constraints in induction.':
        raise ValueError('Unexpected state constraints')
    constraints=pin(run/'reset.smtc').decode()
    if constraints!='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n':
        raise ValueError('Physical reset or extra entry assumption introduced')
    refs=inp['binding']['component_model_receipts']
    for relative,row in refs.items():
        pin(HERE/relative/'INPUTS.json',row['INPUTS']);pin(HERE/relative/'FINISHED.json',row['FINISHED'])
    original=pin(run/'production-cluster.sv').decode();wrapper=pin(run/'wrapper.sv').decode()
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    tileports=parser.ports(pin(run/'tile.sv').decode())
    actual=instance_con(original,'board1_projection_tile16','u_tile')
    recorded=inp['binding']['actual_child_connections']
    if set(recorded)!={n for n,(di,_)in tileports.items()if di=='input'and not n.startswith('f_')}:
        raise ValueError('Missing native child input')
    for n,row in recorded.items():
        if row['expression']!=actual[n]:raise ValueError('Actual native child connection differs')
    public=parser.ports(wrapper)
    if any(n.startswith('f_tile_')for n,(di,_)in public.items()if di=='input'):
        raise ValueError('A complete tile reply is still free')
    for copy in('a','b'):
        parent=instance_con(wrapper,'board1_clustered_projection_scale2','u_'+copy)
        for lane in range(4):
            con=instance_con(wrapper,'board1_projection_tile16','u_'+copy+'_tile'+str(lane))
            for n,(di,shape)in tileports.items():
                if n.startswith('f_'):continue
                if di=='input':
                    expected='clk'if n=='clk'else'rst_n'if n=='reset_n'else copy+'_'+recorded[n]['tap']+'['+str(lane*width(shape))+' +:'+str(width(shape))+']'
                else:expected=copy+'_tile'+str(lane)+'_'+n
                if con[n]!=expected:raise ValueError('Functional tile wiring differs: '+copy+str(lane)+'.'+n)
            if con['f_rel_join_i']!='f_joined'or con['f_observed_lane_i']!='f_row[3:0]':
                raise ValueError('Tile observer does not share the common epoch and nondriving row')
        for port in('dot_o','multiplier_o','exponent_o','done_o','fault_o'):
            n='f_tile_'+port+'_i';expected=copy+'_'+n
            assignment='assign '+expected+'={'+','.join(copy+'_tile'+str(i)+'_'+port for i in reversed(range(4)))+'};'
            if parent[n]!=expected or assignment not in wrapper:raise ValueError('Tile reply is not concretely connected')
    graph=json.loads(pin(run/'elaborated.json'))['modules'][top];memories={}
    for copy in('a','b'):
        for lane in range(4):
            for name,bits in [('multiplier_q',16),('exponent_q',8)]+([('g_lane[0].accumulator_q',35)]if serial else[]):
                key='u_'+copy+'_tile'+str(lane)+'.'+name;cell=graph['cells'].get(key)
                if not cell or cell['type']!='$mem_v2':raise ValueError('Native independent memory absent')
                params=cell['parameters']
                if int(params['SIZE'],2)!=16 or int(params['WIDTH'],2)!=bits or any(b in'01'for b in params['INIT']):
                    raise ValueError('Native memory resized or initialized')
                memories[key]=dict(words=16,width=bits,initialization='independent arbitrary')
    if len(memories)!=(24 if serial else 16):raise ValueError('Native store census differs')
    if p['source_inputs_sha256']!=sha(pin(run/'INPUTS.json'))or p['base_constraint_text']!=constraints:
        raise ValueError('Joint step uses different source/entry conditions')
    expected_labels={'base','joint-induction'}if p.get('joint_complete_invariant_step')else{'base'}|set(p.get('conclusion_groups',{}))
    if (not p['passed']or not p['complete_conclusion_inventory']or
        not p['prior_state_joint_invariants_only']or p['current_state_extra_assumptions']or
        not(p.get('joint_complete_invariant_step')or p.get('conclusion_groups'))or
        set(p['results'])!=expected_labels):
        raise ValueError('Complete connected induction is not closed')
    model=pin(part/'model.smt2',p['model_sha256']).decode()
    expected=query_templates(model,p,top,inp['assertion_cells'],compact=True)
    for name,row in p['results'].items():
        if checked_query(part/(name+'.smt2'),row)!=template_text(expected[name]).encode():raise ValueError('Changed induction premise or target')
        raw=pin(part/(name+'.log'),row['reply_sha256']).decode()
        answers=[l for l in raw.splitlines()if l in('sat','unsat','unknown')]
        if not row['passed']or row['exit']or answers!=['sat','unsat']or'(error 'in raw:raise ValueError('Invalid joint solver receipt')
        pin(part/row['query_artifact'],row['query_artifact_sha256'])
    cover=base['results']['z3-cover']
    if not cover['passed']:raise ValueError('Missing current-epoch and unequal-old-store reachability')
    pin(run/'z3-cover.log',cover['log_sha256']);pin(run/'z3-cover.smt2',cover['query_sha256'])
    for name,h in cover['traces'].items():pin(run/name,h)
    replay=out/'encoding-replay';replay.mkdir();rtl=pin(run/'elaborated.il',p['rtlil_sha256'])
    (replay/'elaborated.il').write_bytes(rtl)
    recipe='read_rtlil elaborated.il\nmemory_map\ndffunmap\nopt_clean\nwrite_json encoded.json\nwrite_smt2 -stbv -wires model.smt2\n'
    (replay/'encode.ys').write_text(recipe)
    with(replay/'yosys.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=replay,stdout=log,stderr=subprocess.STDOUT,timeout=45)
    if cp.returncode or pin(replay/'model.smt2')!=model.encode():raise ValueError('Finite-memory encoding replay differs')
    pin(replay/'encode.ys');pin(replay/'yosys.log')
    # Freeze the evolving campaign roster inside this immutable receipt.
    # Later added components must not invalidate an earlier source binding.
    frozen_joins=out/'source-instantiation-bindings.json'
    frozen_joins.write_bytes((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes())
    joins=json.loads(pin(frozen_joins))
    variants=joins['proof_module_joins'][args.run]['active_variant_source_joins']
    if set(variants)!=({'kv-protected','encrypted-memory'}if serial else{'baseline','seeded-sampling'}):
        raise ValueError('Connected proof is not bound to both current native source classes')
    receipt=audit(args.run,'connected native cluster')
    if receipt['status']!='proved_component':raise ValueError('Ledger has not checked the complete lane')
    result=dict(connected_native_cluster_proof_checked=True,assertions=inp['assertion_cells'],
        variants=variants,native_memories=memories,primitive_contracts=inp['internal_cuts'],
        tile_replies_concrete=True,initial_hard_reset=False,encoding_replay_exact=True,
        whole_device_session_theorem=False,artifact_manifest=manifest,scope=inp['scope'],
        checker_sha256=sha(Path(__file__).read_bytes()))
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in('connected_native_cluster_proof_checked','assertions','variants')}))


if __name__=='__main__':main()

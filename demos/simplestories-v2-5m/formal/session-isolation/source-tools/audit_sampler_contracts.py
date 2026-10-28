"""Join native sampler memory histories and concrete arithmetic/controller proof."""
import argparse
import json
from pathlib import Path

from record_progress import audit, sha
from run_attention_ownership import HERE
from audit_semantic_permissions import dense
from audit_proof_instantiations import body


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    parent=HERE/'runs/sampler-parent-clear-r3';memory=HERE/'runs/sampler-clear-ownership-r5'
    receipts={p.name:audit(p.name,'actual sampler history/controller prerequisite')for p in(parent,memory)}
    if any(r['status']!='proved_component'for r in receipts.values()):raise ValueError('Sampler prerequisite incomplete')
    pi=json.loads((parent/'INPUTS.json').read_text());mi=json.loads((memory/'INPUTS.json').read_text())
    if pi['binding']['initial_hard_reset']or mi['binding']['initial_hard_reset']or pi['assumption_cells']or mi['assumption_cells']:
        raise ValueError('Unexpected reset/assumption policy')
    for name,pfile in [('board1_seeded_head_selector','production-selector.sv'),('board1_fixed_head_argmax','production-argmax.sv')]:
        if body((parent/pfile).read_bytes(),name)!=body((memory/('production-'+name+'.sv')).read_bytes(),name):
            raise ValueError('Native sampler/child source differs')
    if (parent/'production-compare.sv').read_bytes()!=(memory/'production-board1_fixed_head_logit_greater.sv').read_bytes():
        raise ValueError('Native comparator source differs')
    pb=pi['binding'];mb=mi['binding']
    if pb['selector_native_bits']!=770 or pb['child_native_bits']!=166 or sum(pb['sequential_fields'].values())!=655:
        raise ValueError('Native sampler/greedy state accounting changed')
    if sum(pb['child_sequential_fields'].values())!=166:raise ValueError('Greedy state bits omitted')
    if not mb['all_native_children_retained']or not mb['common_nondriving_clear_epoch']:
        raise ValueError('Actual child history is detached from the sampler epoch')
    histories=pb['registered_histories']
    if set(histories)!={'logit','rom','mass'}or sum(r['bits']for r in histories.values())!=115:
        raise ValueError('Incomplete registered sampler histories')
    full=dense((memory/'board1_seeded_head_selector.sv').read_text())
    source=dense((parent/'selector.sv').read_text());wrapper=dense((parent/'wrapper.sv').read_text())
    for name,row in histories.items():
        statement=dense('if(state_q=='+row['phase']+')'+row['register']+'<='+row['array']+'['+row['address']+'];')
        if statement not in full or statement in source:raise ValueError('Native registered read differs')
        if 'assign'+row['register']+'=f_ram_'+name+'_i;'not in source:raise ValueError('Wrong registered read seam')
        if pb['operand_coupling_predicates']['f_ram_'+name+'_i']!='a_f_live_'+name+'_o':
            raise ValueError('Registered reply is matched without its current read owner')
        phase={'logit':3,'rom':6,'mass':11}[name]
        for copy in('a','b'):
            permission='if(!clear_i&&!'+copy+'_f_fatal_o&&'+copy+'_f_state_state_q_o=='+str(phase)+')assert('+copy+'_f_live_'+name+'_o);'
            if permission not in wrapper:raise ValueError('Sampling consumption lacks fresh read permission')
    graph=json.loads((memory/'elaborated.json').read_text())['modules']['native_sampler_clear']
    stores={}
    for name,words,bits in [('logits',4019,52),('mass',4019,31),('exponential',4097,32)]:
        cell=graph['cells'].get('u_native.'+name)
        if not cell or cell['type']!='$mem_v2':raise ValueError('Native full-size sampler memory absent')
        params=cell['parameters']
        if int(params['SIZE'],2)!=words or int(params['WIDTH'],2)!=bits:raise ValueError('Sampler array resized')
        if name!='exponential'and any(b in'01'for b in params['INIT']):raise ValueError('Old mutable memory initialized by harness')
        stores[name]=dict(words=words,width=bits,initialization='native immutable asset'if name=='exponential'else'arbitrary old payload')
    for name in('logit','mass'):
        if 'assert(a_f_write_'+name+'_o==b_f_write_'+name+'_o);'not in wrapper:raise ValueError('Logical current write enable not compared')
        for suffix in('address','data'):
            if 'if(a_f_write_'+name+'_o)assert(a_f_write_'+name+'_'+suffix+'_o==b_f_write_'+name+'_'+suffix+'_o);'not in wrapper:
                raise ValueError('Logical current write port not compared')
    if 'if(a_f_rom_read_o)assert(a_f_rom_address_o==b_f_rom_address_o);'not in wrapper:
        raise ValueError('Immutable ROM address not compared')
    if dense(pb['memory_write_ports']['logit']['enable'])!='row_fire&&!greedy_mode&&row_index_i<4019&&f_child_row_legal_o':
        raise ValueError('Logical current-head write qualification differs')
    if 'assignf_child_row_legal_o=row_legal;'not in dense((parent/'argmax.sv').read_text()):
        raise ValueError('Logical write qualification is not the real greedy row check')
    entry='a_f_state_seed_q_o==b_f_state_seed_q_o&&a_f_state_temperature_q_o==b_f_state_temperature_q_o'
    if entry not in wrapper:raise ValueError('Authorized current configuration not held fixed')
    joins_raw=(HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()
    joins=json.loads(joins_raw)
    for p in(parent,memory):
        if joins['proof_module_joins'][p.name]['active_variant_source_joins']!=['seeded-sampling']:
            raise ValueError('Sampler scope is not bound to current seeded image')
    (out/'source-instantiation-bindings.json').write_bytes(joins_raw)
    result=dict(specific_sampler_memory_permissions_joined=True,receipts=receipts,native_stores=stores,
        native_selector_bits=770,native_greedy_bits=166,registered_history_bits=115,
        concrete_arithmetic_and_greedy_child=True,physical_reset_required=False,
        fully_concrete_memory_solver_proof=False,whole_device_session_theorem=False,
        scope='Exact native current-head logical logit/mass writes, complete memory histories, registered sampling read permissions and immutable ROM addresses joined to the concrete sampler/PRNG/controller correspondence. Same authorized current seed/temperature at healthy CLEAR; malformed discarded fault paths do not supply logical head data. Enclosing device/shell drain remains separate.',
        checker_sha256=sha(Path(__file__).read_bytes()),instantiation_bindings_sha256=sha(joins_raw))
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    (HERE/'SAMPLER-CONTRACT-JOIN.json').write_text(json.dumps(dict(result,receipt=str(out/'FINISHED.json')),indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(specific_sampler_memory_permissions_joined=True,native_mutable_rows=8038,whole_device_session_theorem=False)))


if __name__=='__main__':main()

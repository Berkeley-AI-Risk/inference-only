"""Join exact native shell memories, read permissions and controller receipts.

This audits specific history/permission joins. The numerical children and
completed enclosing device drain remain separate composition obligations.
"""
import json
from pathlib import Path

from record_progress import audit, sha
from run_attention_ownership import HERE, load
from run_projection_relational import instance_con
from audit_semantic_permissions import dense
from audit_proof_instantiations import body


def main():
    cases={
        'greedy':('shell-parent-clear-r4','shell-memory-clear-r1',{'baseline','kv-protected','encrypted-memory'}),
        'seeded':('shell-parent-seeded-clear-r1','shell-memory-seeded-clear-r1',{'seeded-sampling'}),
    }
    joins=json.loads((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_text())
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    results={}
    for kind,(parent_name,memory_name,expected_variants)in cases.items():
        parent=HERE/'runs'/parent_name;memory=HERE/'runs'/memory_name
        receipts={name:audit(name,'native shell history/controller prerequisite')for name in(parent_name,memory_name)}
        if any(r['status']!='proved_component'for r in receipts.values()):raise ValueError('Incomplete shell prerequisite')
        pi=json.loads((parent/'INPUTS.json').read_text());mi=json.loads((memory/'INPUTS.json').read_text())
        if pi['binding']['initial_hard_reset']or mi['binding']['initial_hard_reset']:raise ValueError('Shell prerequisite uses boot reset')
        original=(parent/'production-shell.sv').read_bytes()
        if original!=(memory/'production-shell.sv').read_bytes():raise ValueError('Memory and controller sources differ')
        raw=original.decode();source=dense((parent/'shell.sv').read_text());full=dense((memory/'shell.sv').read_text())
        wrapper=dense((parent/'wrapper.sv').read_text())
        monitor=dense((memory/'monitor.inc.sv').read_text())
        geometries={n:(2049,12)if n=='token_tape_q'else(256,16)for n in('token_tape_q','embedding_mem_q','layer5_mem_q','final_norm_mem_q')}
        for name,(words,bits)in geometries.items():
            if name+'[0:'+str(words-1)+']'not in full:raise ValueError('Native shell array geometry changed')
        if pi['binding']['native_sequential_bits']!=197 or sum(pi['binding']['sequential_fields'].values())!=137:
            raise ValueError('Native scalar/registered history accounting differs')
        histories=pi['binding']['registered_memory_histories']
        if set(histories)!={'tape','embedding','layer','norm'}or sum(r['bits']for r in histories.values())!=60:
            raise ValueError('Incomplete native registered-history inventory')
        for name,row in histories.items():
            read=dense('if('+row['read']+')'+row['register']+' <= '+row['memory']+'['+row['address']+'];')
            if read not in full or read in source or dense('assign '+row['register']+'=f_ram_'+name+'_i;')not in source:
                raise ValueError('Native registered memory-history seam differs')
            if pi['binding']['reply_coupling_predicates']['f_ram_'+name+'_i']!='a_f_live_'+name+'_o':
                raise ValueError('Registered reply is coupled under a different owner')
            if name!='tape':
                leaf={'embedding':'embedding','layer':'layer','norm':'norm'}[name]
                for required in('if('+row['new']+')beginf_'+leaf+'_owned<=0;',
                    'if('+row['read']+')beginf_'+leaf+'_read_live<=1;'):
                    if dense(required)not in monitor:raise ValueError('Native vector history epoch/read writer differs')
            permission={'tape':2,'embedding':7,'layer':13,'norm':19}[name]
            for copy in('a','b'):
                required='if(!clear_i&&!'+copy+'_f_state_fail_q_o&&'+copy+'_f_state_state_q_o=='+str(permission)+')assert('+copy+'_f_live_'+name+'_o);'
                if required not in wrapper:raise ValueError('Actual consuming phase lacks fresh registered read permission')
        for name in('append','generated','embedding','layer','norm'):
            if 'assert(a_f_write_'+name+'_o==b_f_write_'+name+'_o);'not in wrapper:raise ValueError('Actual RAM write enable not compared')
            for suffix in('address','data'):
                if 'if(a_f_write_'+name+'_o)assert(a_f_write_'+name+'_'+suffix+'_o==b_f_write_'+name+'_'+suffix+'_o);'not in wrapper:
                    raise ValueError('Actual RAM write port not compared')
        child_rows={}
        for instance,rows in pi['binding']['actual_child_inputs'].items():
            module=next(r['module']for r in pi['internal_cuts']if r.get('instance')==instance)
            native=(parent/('production-child-'+module+'.sv')).read_bytes()
            con=instance_con(raw,module,instance);declared=parser.ports(body(native,module).decode())
            if set(rows)!={n for n,(di,_)in declared.items()if di=='input'}:raise ValueError('Missing actual numerical child input')
            for n,row in rows.items():
                if row['expression']!=con[n]:raise ValueError('Native shell-child connection differs')
                if row['kind']=='admission_equality':
                    tap=row['tap']
                    if 'if(a_'+tap+'_when)assert(a_'+tap+'==b_'+tap+');'not in wrapper:
                        raise ValueError('Actual child data admission not compared')
            child_rows[instance]=dict(module=module,native_module_sha256=sha(body(native,module)),inputs=len(rows))
        variants=set(joins['proof_module_joins'][parent_name]['active_variant_source_joins'])
        variants.intersection_update(joins['proof_module_joins'][memory_name]['active_variant_source_joins'])
        if variants!=expected_variants:raise ValueError('Native shell source-class association differs')
        results[kind]=dict(variants=sorted(variants),receipts=receipts,native_register_bits=197,
            directly_compared_scalar_bits=137,registered_history_bits=60,native_memories=geometries,
            native_child_inputs=child_rows,registered_history_permissions_joined=True,
            numerical_child_contracts_composed=False,enclosing_completed_drain_composed=False)
    result=dict(specific_shell_memory_and_read_permissions_joined=True,classes=results,
        assembled_shell_solver_proof=False,whole_device_session_theorem=False,
        instantiation_bindings_sha256=sha((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()),
        remaining=['Embedding/group-stream and numerical service/semantic child reply composition.',
            'Seeded sampler current-configuration/PRNG and RAM histories at winner publication.',
            'Completed device CLEAR/drain, pending endpoint queues and full mutable-state signoff.'],
        checker_sha256=sha(Path(__file__).read_bytes()))
    (HERE/'SHELL-CONTRACT-JOIN.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(specific_shell_memory_and_read_permissions_joined=True,source_classes=2,whole_device_session_theorem=False)))


if __name__=='__main__':main()

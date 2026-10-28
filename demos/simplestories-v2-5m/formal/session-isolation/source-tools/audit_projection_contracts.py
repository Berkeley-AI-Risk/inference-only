"""Bind projection RAM/header/reader/buffer contracts to actual native wiring.

This checks specific source/receipt prerequisites. It is not an automatically
assembled service theorem, and it does not discharge top-level drain entry or
the numerical adapter/cluster contracts.
"""
import json
from pathlib import Path
import re

from record_progress import audit, sha
from run_attention_ownership import HERE, load
from run_projection_relational import instance_con
from audit_semantic_permissions import dense
from audit_proof_instantiations import body


def main():
    names={
        'parent':'projection-parent-clear-r9','protocol':'projection-stream-join-r6',
        'activation':'service-projection-clear-r1','header':'group-stream-ownership-clear-r1',
        'reader':'metadata-reader-clear-r1','width':'weight-width-adapter-r1','beat':'weight-beat-register-r1',
    }
    receipts={k:audit(n,'projection history/reader prerequisite')for k,n in names.items()}
    if any(r['status']!='proved_component'for r in receipts.values()):raise ValueError('Incomplete projection prerequisite')
    runs={k:HERE/'runs'/n for k,n in names.items()}
    inputs={k:json.loads((p/'INPUTS.json').read_text())for k,p in runs.items()}
    for k in('parent','protocol','activation'):
        if(runs[k]/'production-service.sv').read_bytes()!=(runs['parent']/'production-service.sv').read_bytes():
            raise ValueError('Actual projection-job sources differ')
    stream_module='board1_fixed_group_ddr_stream';reader_module='board1_fixed_projection_metadata_reader'
    native_stream=(runs['parent']/'production-stream.sv').read_bytes()
    if body(native_stream,stream_module)!=body((runs['header']/('production-'+stream_module+'.sv')).read_bytes(),stream_module):
        raise ValueError('Header RAM source differs')
    if body((runs['parent']/('production-child-'+reader_module+'.sv')).read_bytes(),reader_module)!=body((runs['reader']/'production-reader.sv').read_bytes(),reader_module):
        raise ValueError('Metadata reader source differs')
    for kind,module in [('width','board1_private_ddr256_to_w640'),('beat','board1_private_weight_beat_register')]:
        if body((runs['parent']/('production-child-'+module+'.sv')).read_bytes(),module)!=body((runs[kind]/'production-buffer.sv').read_bytes(),module):
            raise ValueError('Native buffer source differs')
        if not inputs[kind]['binding']['local_cancellation_reset']:raise ValueError('Buffer proof requires a different reset')
    if any(inputs[k]['binding'].get('initial_hard_reset',True)for k in('parent','protocol','activation','header','reader')):
        raise ValueError('A fresh-session prerequisite still assumes hard reset')
    parent=dense((runs['parent']/'service.sv').read_text())
    full=dense((runs['activation']/'service.sv').read_text())
    geometry='activation_memory_q[0:MAX_COLUMNS-1]'
    if geometry not in parent or geometry not in full or 'localparamintegerMAX_COLUMNS=682;'not in full:
        raise ValueError('Native activation geometry differs')
    read='if(activation_store_read)activation_q<=activation_memory_q[activation_store_read_address];'
    if read not in full or read in parent or 'assignactivation_q=f_ram_reply_i;'not in parent:
        raise ValueError('Registered activation-history seam differs')
    coupling=inputs['parent']['binding']['reply_coupling_predicates']
    if coupling['f_ram_reply_i']!='a_f_rel_job_ram_live_o':raise ValueError('Fresh activation coupling guard differs')
    update='if(!reset_n||clear_i||f_new_start)beginf_owned<=0;f_read_live<=0;f_read_target<=0;end'
    if update not in parent or update not in full:raise ValueError('Read-history cancellation epochs differ')
    for flag in('f_header_exponents_i','f_header_multipliers_i'):
        if coupling[flag]!='a_f_rel_stream_state_q_o==3':raise ValueError('Packed header coupling differs')
    monitor=dense((runs['header']/'storage-monitor.inc.sv').read_text())
    for required in('if(group_valid_o)beginassert(metadata_count_q==valid_lanes_q);',
        'if(f_metadata_owned)assert({row_exponent_q[f_metadata_row],row_multiplier_q[f_metadata_row]}==f_metadata_shadow);'):
        if required not in monitor:raise ValueError('Published metadata history/ownership condition absent')
    if 'row_exponent_q[0:63]'not in dense(native_stream.decode())or'row_multiplier_q[0:63]'not in dense(native_stream.decode()):
        raise ValueError('Full native metadata arrays changed')
    wrapper=dense((runs['parent']/'wrapper.sv').read_text())
    for enable,fields in [('f_memory_write_o',['f_memory_write_address_o','f_memory_write_data_o']),
        ('f_memory_read_o',['f_memory_read_address_o']),('f_metadata_write_o',['f_metadata_write_address_o','f_metadata_write_data_o'])]:
        if 'assert(a_'+enable+'==b_'+enable+');'not in wrapper:raise ValueError('Memory enable equality absent')
        for name in fields:
            if 'if(a_'+enable+')assert(a_'+name+'==b_'+name+');'not in wrapper:raise ValueError('Memory port value equality absent')
    con=instance_con(native_stream.decode(),reader_module,'u_metadata_reader')
    manifest=inputs['parent']['binding']['actual_child_inputs']['stream.u_metadata_reader']['inputs']
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    declared=parser.ports(body((runs['reader']/'production-reader.sv').read_bytes(),reader_module).decode())
    if set(manifest)!={k for k,(direction,_)in declared.items()if direction=='input'}:raise ValueError('Incomplete metadata-reader input inventory')
    for port,row in manifest.items():
        if row['expression']!=con[port]:raise ValueError('Actual reader input binding differs')
    for data in('fixed_layer_i','fixed_job_i','fixed_group_i'):
        if manifest[data]['guard']!=con['start_valid_i']:raise ValueError('Reader descriptor admission guard differs')
    for kind,module,instance in [('width','board1_private_ddr256_to_w640','u_width_adapter'),('beat','board1_private_weight_beat_register','u_weight_beat_register')]:
        con=instance_con(native_stream.decode(),module,instance)
        if con['reset_n']!='adapter_reset_n':raise ValueError('Native local cancellation wire differs')
        row=inputs['parent']['binding']['actual_child_inputs']['stream.'+instance]['inputs']['reset_n']
        if row['expression']!='adapter_reset_n'or row['guard']!='1':raise ValueError('Local cancellation reset was not compared')
    if 'wireadapter_reset_n=reset_n&&!clear_i&&(state_q==ST_WEIGHT);'not in dense(native_stream.decode()):
        raise ValueError('Actual cancellation derivation differs')
    joins=json.loads((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_text())
    variants={'baseline','seeded-sampling','kv-protected','encrypted-memory'}
    for name in names.values():variants.intersection_update(joins['proof_module_joins'][name]['active_variant_source_joins'])
    if len(variants)!=4:raise ValueError('Projection history prerequisites do not bind all current images')
    result=dict(specific_projection_history_and_reader_contracts_joined=True,variants=sorted(variants),
        parent_assertions=inputs['parent']['assertion_cells'],protocol_assertions=inputs['protocol']['assertion_cells'],
        reader_assertions=inputs['reader']['assertion_cells'],native_control_bits=207,
        activation_registered_history_bits=16,native_activation_words=682,native_activation_word_bits=16,
        native_metadata_rows=64,native_metadata_row_bits=24,
        proof_receipts=receipts,instantiation_binding_sha256=sha((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()),
        assembled_service_solver_proof=False,session_milestone_complete=False,
        remaining=['Numerical packed-header adapter and clustered arithmetic state contracts.',
            'Top-level completed CLEAR/drain must establish every nested prerequisite entry condition.',
            'Token-shell publication and the full device mutable-state/composition audit.'],
        scope='Source/receipt join of exact native activation/header histories, matched actual memory ports, concrete metadata-reader relation and local-cancellation weight buffers. This is not an automatically assembled temporal service theorem.',
        checker_sha256=sha(Path(__file__).read_bytes()))
    (HERE/'PROJECTION-CONTRACT-JOIN.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in('specific_projection_history_and_reader_contracts_joined','parent_assertions','reader_assertions','session_milestone_complete')}))


if __name__=='__main__':main()

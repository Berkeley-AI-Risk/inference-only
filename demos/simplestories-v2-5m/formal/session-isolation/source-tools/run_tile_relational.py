"""Native full sixteen-lane projection tile relation under caller permissions.

No hard reset is assumed. Logical kill/begin cancels payload authority. The
actual caller must establish accepted first-beat, slice-spacing and drained-read
permissions. Complete MAC replies are the stated recurrence/congruence seam.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap
from run_semantic_relational import erase_checks
from run_service_relational import synthesis_text

TOP='board1_projection_tile16'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args();binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    original=(native/'project/cluster-tile.sv').read_bytes()
    found=re.findall(r'^module '+TOP+r'\b[\s\S]*?^endmodule\b',original.decode(),re.M)
    if len(found)!=1:raise ValueError('Actual native tile definition not unique')
    source=found[0];serial='logic slice_busy_q'in source
    width=26 if serial else 768
    pattern=r'        board1_w10_a16_mul_exact u_mul\s*\([\s\S]*?\);'if serial else r'        board1_projection_dsp_accumulator u_mac\([\s\S]*?\);'
    match=re.search(pattern,source)
    if not match:raise ValueError('Actual MAC instance changed')
    source=source[:match.start()]+('        assign product=f_mac_reply_i;'if serial else'        assign accumulated=f_mac_reply_i[lane*48 +:48];')+source[match.end():]
    owner_name='serial-cluster-ownership-clear-r1'if serial else'cluster-ownership-clear-r1'
    prior=HERE/'runs'/owner_name
    monitor=(prior/'tile-monitor.inc.sv').read_text()
    # Native-parent permission assertions remain conditional on the caller's
    # actual accepted protocol. Its temporal epoch/ownership observers remain.
    for line in [
        '        if(f_parent_drain_i)assert(!accept_i);\n',
        '        if((slice_busy_q && beat_last_q) || (op_valid_q && op_last_q) ||\n           (product_valid_q && product_last_q))assert(f_parent_drain_i);\n']:
        if line in monitor:monitor=monitor.replace(line,'')
    monitor=monitor.replace('if(reset_n && !kill_i && !begin_i && f_clear_seen_i)',
        'if(reset_n && f_rel_join_i && f_rel_permission && !kill_i && !begin_i)')
    if 'f_parent_drain_i'in monitor or 'f_clear_seen_i'in monitor:raise ValueError('Unreviewed parent-only observer dependency')
    # Use an explicitly grouped form to avoid any dependence on textual OR/AND precedence.
    protocol='(!accept_i || (f_rel_descriptor_owned && (f_first_seen || first_i)))'+(
        ' && (!accept_i || !slice_busy_q) && (!read_i || (!slice_busy_q && !op_valid_q && !product_valid_q && (&f_acc_mask))) && (!accept_i || !((slice_busy_q && beat_last_q) || (op_valid_q && op_last_q) || (product_valid_q && product_last_q)))'
        if serial else' && (!read_i || f_acc_owned)')
    extra=f',\n    input wire [{width-1}:0] f_mac_reply_i,\n    input wire [3:0] f_observed_lane_i,\n    input wire f_rel_join_i,\n    output wire f_acc_owned_o,f_first_seen_o'+(',f_busy_o,f_drained_o,\n    output wire [3:0] f_slice_o'if serial else'')+'\n'
    source=source.replace('\n);',extra+');',1)
    ghosts='''
    reg f_rel_descriptor_owned;
    reg [15:0] f_rel_metadata_mask;
    reg f_rel_dot_target;
    wire f_rel_permission='''+protocol+''';
    always @(posedge clk)begin
        if(!reset_n || kill_i || begin_i)begin
            f_rel_descriptor_owned<=reset_n && begin_i;
            f_rel_metadata_mask<=0;f_rel_dot_target<=0;
        end else begin
            if(metadata_write_i)f_rel_metadata_mask[metadata_lane_i]<=1;
            if(read_i)f_rel_dot_target<=read_lane_i==f_observed_lane_i && '''+('f_acc_mask[f_observed_lane_i]'if serial else'f_acc_owned')+''';
        end
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\n'+ghosts+'\nendmodule',1)
    census_name={'baseline':'native-hierarchy-r1','seeded-sampling':'native-hierarchy-seeded-sampling-r1',
        'kv-protected':'native-hierarchy-kv-protected-r1','encrypted-memory':'native-hierarchy-encrypted-memory-r4'}[args.variant]
    census=HERE/'runs'/census_name
    c=json.loads((census/'CENSUS.json').read_text());graph=json.loads((census/'hierarchy.json').read_text())['modules']
    rows=[r for r in c['instances']if r['original_module']==TOP]
    if len(rows)!=4 or len({r['module']for r in rows})!=1:raise ValueError('Actual four-tile state class differs')
    g=graph[rows[0]['module']]
    qbits={b for cell in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',cell['type'])for b in cell['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(found[0])))
    fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and qbits.intersection(g['netnames'][n]['bits'])}
    observed={b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}
    lowered={'weight_q':dict(words=1 if serial else 16,width=10)}
    if serial:lowered['product_q']=dict(words=1,width=26)
    for name,row in lowered.items():
        chunks=[g['netnames'].get(name+'['+str(i)+']',{}).get('bits',[])for i in range(row['words'])]
        bits=[b for chunk in chunks for b in chunk]
        if any(len(chunk)!=row['width']for chunk in chunks)or len(set(bits))!=row['words']*row['width']:
            raise ValueError('Native lowered array geometry changed: '+name)
        observed.update(b for b in bits if isinstance(b,int))
    if not qbits.issubset(observed):raise ValueError('Uninventoried native tile scalar state')
    relations={n:'1'for n in fields}
    for n,condition in [('activation_q','f_operands_owned'if not serial else'f_tail_owned'),
        ('valid_lanes_q','f_rel_descriptor_owned'),('weight_tail_q','f_tail_owned'),
        ('op_first_q','1'),('op_last_q','op_valid_q'),('product_first_q','1'),
        ('product_last_q','product_valid_q'),('op_group_q','op_valid_q'),('product_group_q','product_valid_q'),
        ('beat_first_q','slice_busy_q'),('beat_last_q','slice_busy_q'),('slice_q','slice_busy_q'),
        ('dot_o','f_rel_dot_target'),('multiplier_o','f_read_target'),('exponent_o','f_read_target')]:
        if n in relations:relations[n]=condition
    taps={**{'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()},
        **{'f_when_'+n+'_o':('',condition)for n,condition in relations.items()},
        'f_descriptor_owned_o':('','f_rel_descriptor_owned'),
        'f_permission_o':('','f_rel_permission'),
        'f_metadata_mask_o':('[15:0] ','f_rel_metadata_mask'),
        'f_metadata_owned_o':('','f_metadata_owned'),
        'f_dot_target_o':('','f_rel_dot_target'),'f_metadata_target_o':('','f_read_target'),
        'f_operands_owned_o':('','f_operands_owned'),'f_product_owned_o':('','f_product_owned'),
    }
    if serial:
        taps.update(f_acc_mask_o=('[15:0] ','f_acc_mask'),f_tail_owned_o=('','f_tail_owned'),
            f_weight_word_o=('[9:0] ','weight_q[0]'),f_product_word_o=('[25:0] ','product_q[0]'))
    else:
        for lane in range(16):taps['f_weight_'+str(lane)+'_o']=('[9:0] ','weight_q['+str(lane)+']')
    for lane in range(16):
        taps['f_metadata_'+str(lane)+'_o']=('[23:0] ','{multiplier_q['+str(lane)+'],exponent_q['+str(lane)+']}')
        if serial:taps['f_accumulator_'+str(lane)+'_o']=('[34:0] ','g_lane[0].accumulator_q['+str(lane)+']')
    source=tap(source,taps);ports=parser.ports(source)
    coupling={'valid_lanes_i':'begin_i','last_i':'accept_i',
        'activation_i':'accept_i','weights_i':'accept_i','metadata_lane_i':'metadata_write_i',
        'metadata_multiplier_i':'metadata_write_i','metadata_exponent_i':'metadata_write_i','read_lane_i':'read_i',
        'f_mac_reply_i':'a_f_operands_owned_o'if serial else'a_f_acc_owned_o'}
    lines=['module tile_parent_relational(',',\n'.join(
        ['    input wire '+sh+('rst_n'if n=='reset_n'else n)for n,(di,sh)in ports.items()if di=='input'and n not in('f_observed_lane_i','f_rel_join_i')]+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');',
        '    (* anyconst *)reg[3:0]f_word;reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        con=[]
        for n,(di,_)in ports.items():
            value=('rst_n'if n=='reset_n'else n)if di=='input'else copy+'_'+n
            if n=='f_rel_join_i':value='f_joined'
            if n=='f_observed_lane_i':value='f_word'
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    '+TOP+' u_'+copy+'('+','.join(con)+');')
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(kill_i || begin_i)f_joined<=1;else if(!a_f_permission_o || !b_f_permission_o)f_joined<=0;',
        '    always @*if(rst_n && f_joined && a_f_permission_o && b_f_permission_o)begin',
        '        assert(a_f_descriptor_owned_o==b_f_descriptor_owned_o);',
        '        assert(a_f_metadata_mask_o==b_f_metadata_mask_o);',
        '        assert(a_f_metadata_owned_o==a_f_metadata_mask_o[f_word]);',
        '        assert(b_f_metadata_owned_o==b_f_metadata_mask_o[f_word]);',
        '        assert(a_f_operands_owned_o==b_f_operands_owned_o);',
        '        assert(a_f_product_owned_o==b_f_product_owned_o);',
        '        assert(a_f_acc_owned_o==b_f_acc_owned_o);',
        '        assert(a_f_dot_target_o==b_f_dot_target_o);assert(a_f_metadata_target_o==b_f_metadata_target_o);']
    for n in fields:
        lines+=['        assert(a_f_when_'+n+'_o==b_f_when_'+n+'_o);',
            '        if(a_f_when_'+n+'_o)assert(a_f_state_'+n+'_o==b_f_state_'+n+'_o);']
    for lane in range(16):
        lines.append('        if(a_f_metadata_mask_o['+str(lane)+'])assert(a_f_metadata_'+str(lane)+'_o==b_f_metadata_'+str(lane)+'_o);')
        if serial:
            lines.append('        if(a_f_acc_mask_o['+str(lane)+'])assert(a_f_accumulator_'+str(lane)+'_o==b_f_accumulator_'+str(lane)+'_o);')
        else:lines.append('        if(a_f_operands_owned_o)assert(a_f_weight_'+str(lane)+'_o==b_f_weight_'+str(lane)+'_o);')
    if serial:
        lines+=['        assert(a_f_acc_mask_o==b_f_acc_mask_o);assert(a_f_tail_owned_o==b_f_tail_owned_o);',
            '        if(a_f_operands_owned_o)assert(a_f_tail_owned_o);',
            '        if(b_f_operands_owned_o)assert(b_f_tail_owned_o);',
            '        if(a_f_operands_owned_o)assert(a_f_weight_word_o==b_f_weight_word_o);',
            '        if(a_f_product_owned_o)assert(a_f_product_word_o==b_f_product_word_o);']
    lines+=['        assert(a_done_o==b_done_o);assert(a_fault_o==b_fault_o);',
        '        if(a_f_dot_target_o)assert(a_dot_o==b_dot_o);',
        '        if(a_f_metadata_target_o)begin assert(a_multiplier_o==b_multiplier_o);assert(a_exponent_o==b_exponent_o);end',
        '    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_dot_o!=b_dot_o);',
        '        cover(rst_n && !f_joined && a_f_metadata_0_o!=b_f_metadata_0_o);',
        '        cover(rst_n && f_joined && a_f_permission_o && accept_i);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-tile.sv':original,'tile.sv':('`undef FORMAL\n'+source).encode(),
        'wrapper.sv':wrapper.encode(),'tile-monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes(),
        'native-state-census.json':json.dumps(g,indent=2,sort_keys=True).encode()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='tile_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert(')+2*monitor.count('assert('),covers=3,observer_constants=1,
        binding=dict(native_join=binding,variant=args.variant,concrete_module=TOP,initial_hard_reset=False,
            native_scalar_bits=len(qbits),sequential_fields=fields,per_field_relation=relations,
            lowered_register_arrays=lowered,
            operand_coupling_predicates=coupling,caller_permissions=protocol,serial=serial,
            source_ownership_run=owner_name,all_sixteen_metadata_rows_observed=True,
            complete_native_mac_reply_contract=True),cuts=[dict(module='board1_w10_a16_mul_exact'if serial else'board1_projection_dsp_accumulator',
                instances=1 if serial else 16,replacement='f_mac_reply_i',
                contract='Stateless product congruence at matched operands'if serial else'Owned registered-MAC recurrence equality after first overwrite')],
        depth=3,induction_depth=3,cover_depth=10,timeout=args.timeout,
        source_list=['tile.sv','wrapper.sv'],map_literal_roms=True,optimize_full=True,
        expected_memories=6 if serial else 4,
        primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Conditional actual native full sixteen-lane tile correspondence after logical kill/begin without hard reset. Actual scalar state, all sixteen metadata words and captured operands/accumulators observed under their ownership. Caller first-beat, slice-spacing and drained-read permissions required. Native MAC recurrence/stateless product contract remains explicit; no parent or whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())

"""Native sampler and concrete greedy-child correspondence after healthy CLEAR.

The current authorized seed/temperature match at entry; old PRNG and transient
payloads are independent. The three registered logit/ROM/mass replies are exact
history seams. Arithmetic and the complete greedy comparator remain concrete.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance
from run_service_relational import synthesis_text
from audit_proof_instantiations import body


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args();prior=HERE/'runs/sampler-clear-ownership-r5'
    pi=json.loads((prior/'INPUTS.json').read_text());binding=pi['binding']['native_join']
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    top='board1_seeded_head_selector';child_name='board1_fixed_head_argmax'
    original=(prior/('production-'+top+'.sv')).read_bytes();raw=body(original,top).decode();source=raw
    child_original=(prior/('production-'+child_name+'.sv')).read_bytes();child=body(child_original,child_name).decode()
    census=HERE/'runs/native-hierarchy-seeded-sampling-r1'
    c=json.loads((census/'CENSUS.json').read_text());graphs=json.loads((census/'hierarchy.json').read_text())['modules']
    def fields_for(name,source):
        rows=[r for r in c['instances']if r['original_module']==name]
        if not rows:raise ValueError('Native numerical sampler module absent')
        g=graphs[rows[0]['module']]
        q={b for cell in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe)',cell['type'])for b in cell['connections']['Q']if isinstance(b,int)}
        assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(source)))
        fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and q.intersection(g['netnames'][n]['bits'])}
        if not q.issubset({b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}):raise ValueError('Native state census incomplete')
        return fields,len(q)
    fields,native_bits=fields_for(top,raw);child_fields,child_bits=fields_for(child_name,child)
    child_taps={'f_child_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in child_fields.items()}
    child_taps['f_child_row_legal_o']=('','row_legal')
    child=tap(child,child_taps)
    source=extend_instance(source,'u_original_argmax',{n:n for n in child_taps})
    ghosts=['    wire '+shape+n+';'for n,(shape,_)in child_taps.items()]
    taps={n:(shape,n)for n,(shape,_)in child_taps.items()}
    histories={
        'logit':dict(register='row_read_q',array='logits',address='cursor_q',phase='ROW_READ',bits=52),
        'rom':dict(register='lut_read_q',array='exponential',address="{1'b0,lut_index_q[11:0]}",phase='LUT_READ',bits=32),
        'mass':dict(register='weight_read_q',array='mass',address='cursor_q',phase='CDF_READ',bits=31),
    }
    cuts=[];coupling={};relations={n:'1'for n in fields}
    for name,row in histories.items():
        before='if (state_q == '+row['phase']+') '+row['register']+' <= '+row['array']+'['+row['address']+'];'
        if source.count(before)!=1:raise ValueError('Native registered sampler read changed')
        source=source.replace(before,'begin end',1)
        port='f_ram_'+name+'_i'
        source=source.replace('\n);',',\n    input wire ['+str(row['bits']-1)+':0] '+port+'\n);',1)
        ghosts+=['    reg f_live_'+name+';',
            '    always @(posedge clk)if(!reset_n || clear_i || f_fatal || start_fire || f_accept)f_live_'+name+'<=0;else if(state_q=='+row['phase']+')f_live_'+name+'<=1;',
            '    assign '+row['register']+'='+port+';']
        taps['f_live_'+name+'_o']=('','f_live_'+name)
        coupling[port]='a_f_live_'+name+'_o';fields.pop(row['register']);relations.pop(row['register'])
        cuts.append(dict(kind='native_registered_history',**row,replacement=port))
    # The ROM read has its own matched immutable-history seam. No detached,
    # unused copy of its asset is used as a solver premise.
    declaration='    initial $readmemh(EXP_FILE, exponential);'
    if source.count(declaration)!=1:raise ValueError('Native ROM initialization changed')
    source=source.replace(declaration,'',1)
    ghosts+='''
    reg [12:0] f_rows;
    reg f_zero_owned;
    wire f_fatal=fail_q || greedy_fault || upstream_fail_closed_i || (state_q!=IDLE && !model_locked_i);
    wire f_accept=!f_fatal && !clear_i && state_q==IDLE && settings_valid_i && settings_ready_o && settings_empty_boundary_i && settings_temperature_i<=3;
    always @(posedge clk)begin
        if(!reset_n || clear_i || f_fatal || start_fire || f_accept)begin f_rows<=0;f_zero_owned<=0;end
        else if(row_fire)begin f_rows<=f_rows+1'b1;if(row_index_i==0)f_zero_owned<=1;end
    end
'''.splitlines()
    relations.update(zero_exponent_q='f_zero_owned',maximum_q='state_q>=ROW_READ && state_q<=WINNER',
        gap_q='state_q==INDEX',lut_index_q='state_q==LUT_READ || state_q==STORE',
        product_q='state_q==RNG_OUT || state_q==MULTIPLY',multiply_bit_q='state_q==MULTIPLY',
        target_q='state_q>=CDF_READ && state_q<=WINNER',sampled_token_q='state_q==WINNER')
    taps.update({'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()})
    taps.update({'f_when_'+n+'_o':('',predicate)for n,predicate in relations.items()})
    taps.update(f_rows_o=('[12:0] ','f_rows'),f_zero_owned_o=('','f_zero_owned'),f_fatal_o=('','f_fatal'),
        f_greedy_fault_o=('','greedy_fault'),f_greedy_valid_o=('','greedy_winner_valid'))
    memory_writes={
        'logit':dict(enable='row_fire && !greedy_mode && row_index_i<4019 && f_child_row_legal_o',
            address='row_index_i[11:0]',data='align_logit(row_scaled_raw_i,$signed({row_source_exponent_i[7],row_source_exponent_i}),row_index_i==0 ? $signed({row_source_exponent_i[7],row_source_exponent_i}) : zero_exponent_q)',bits=52),
        'mass':dict(enable='state_q==STORE && live && !invalid_lut',address='cursor_q',data='next_weight',bits=31),
    }
    for name,row in memory_writes.items():
        taps.update({'f_write_'+name+'_o':('',row['enable']),
            'f_write_'+name+'_address_o':('[11:0] ',row['address']),
            'f_write_'+name+'_data_o':('['+str(row['bits']-1)+':0] ',row['data'])})
    taps.update(f_rom_read_o=('','state_q==LUT_READ'),f_rom_address_o=('[12:0] ',"{1'b0,lut_index_q[11:0]}"))
    source=source.replace('\nendmodule','\n'+'\n'.join(ghosts)+'\nendmodule',1);source=tap(source,taps)
    ports=parser.ports(source)
    coupling.update(settings_temperature_i='settings_valid_i',settings_seed_i='settings_valid_i',
        row_index_i='row_valid_i',row_scaled_raw_i='row_valid_i',row_source_exponent_i='row_valid_i',row_last_i='row_valid_i',
        winner_ready_i='a_winner_valid_o')
    lines=['module sampler_parent_relational(',',\n'.join(
        ['    input wire '+sh+n for n,(di,sh)in ports.items()if di=='input']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');','    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        con=[]
        for n,(di,_)in ports.items():
            value=n if di=='input'else copy+'_'+n
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    '+top+' u_'+copy+'('+','.join(con)+');')
    lines+=['    always @(posedge clk)if(!reset_n)f_joined<=0;else if(clear_i)f_joined<=model_locked_i && !upstream_fail_closed_i && !a_f_state_fail_q_o && !b_f_state_fail_q_o && !a_f_greedy_fault_o && !b_f_greedy_fault_o && a_f_state_seed_q_o==b_f_state_seed_q_o && a_f_state_temperature_q_o==b_f_state_temperature_q_o;',
        '    always @*if(reset_n && f_joined)begin']
    for n in fields:lines+=['        assert(a_f_when_'+n+'_o==b_f_when_'+n+'_o);',
        '        if(a_f_when_'+n+'_o)assert(a_f_state_'+n+'_o==b_f_state_'+n+'_o);']
    for n in child_fields:
        guard='a_f_child_state_state_q_o==4'if n.startswith('pending_')else'1'
        lines.append('        if('+guard+')assert(a_f_child_state_'+n+'_o==b_f_child_state_'+n+'_o);')
    for name in histories:lines.append('        assert(a_f_live_'+name+'_o==b_f_live_'+name+'_o);')
    lines+=['        assert(a_f_rows_o==b_f_rows_o);assert(a_f_zero_owned_o==b_f_zero_owned_o);']
    for name in memory_writes:
        lines.append('        assert(a_f_write_'+name+'_o==b_f_write_'+name+'_o);')
        for suffix in('address','data'):
            lines.append('        if(a_f_write_'+name+'_o)assert(a_f_write_'+name+'_'+suffix+'_o==b_f_write_'+name+'_'+suffix+'_o);')
    lines+=['        assert(a_f_rom_read_o==b_f_rom_read_o);',
        '        if(a_f_rom_read_o)assert(a_f_rom_address_o==b_f_rom_address_o);']
    for copy in('a','b'):
        state=copy+'_f_state_state_q_o';child_state=copy+'_f_child_state_state_q_o';rows=copy+'_f_rows_o'
        lines+=['        assert('+state+'<=12 || '+state+'==31);',
            '        assert('+child_state+'<=4);',
            '        assert('+copy+'_f_child_state_expected_row_q_o<=4018);',
            '        assert('+rows+'<=4019);',
            '        if(!'+copy+'_f_fatal_o && '+rows+'!=0)assert('+copy+'_f_zero_owned_o);',
            '        if(!'+copy+'_f_fatal_o && '+state+'==1)begin',
            '            assert('+copy+'_f_state_cursor_q_o==0);',
            '            assert('+child_state+'==1 || '+child_state+'==2 || '+child_state+'==4);',
            '            if('+child_state+'==1)assert('+rows+'=='+copy+'_f_child_state_expected_row_q_o);',
            '            if('+child_state+'==4)assert('+rows+'=={1\'b0,'+copy+'_f_child_state_expected_row_q_o}+14\'d1);',
            '            if('+child_state+'==2)assert('+rows+'==4019);','        end',
            '        if(!'+copy+'_f_fatal_o && '+state+'>=2 && '+state+'<=12)begin',
            '            assert('+rows+'==4019);assert('+copy+'_f_zero_owned_o);',
            '            assert('+copy+'_f_state_temperature_q_o!=0);',
            '            assert('+copy+'_f_state_cursor_q_o<=4018);','        end']
        for name,phase in [('logit',3),('rom',6),('mass',11)]:
            lines.append('        if(!clear_i && !'+copy+'_f_fatal_o && '+state+'=='+str(phase)+')assert('+copy+'_f_live_'+name+'_o);')
    for n,(di,_)in ports.items():
        if di=='output'and not n.startswith('f_'):lines.append('        assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(reset_n && !f_joined && a_f_state_rng_lo_q_o!=b_f_state_rng_lo_q_o);',
        '        cover(reset_n && f_joined && a_row_ready_o && row_valid_i && row_index_i==1);','    end','endmodule']
    wrapper='\n'.join(lines)+'\n';files={'selector.sv':('`undef FORMAL\n'+source).encode(),
        'argmax.sv':('`undef FORMAL\n'+child).encode(),
        'compare.sv':(prior/'production-board1_fixed_head_logit_greater.sv').read_bytes(),
        'production-selector.sv':original,'production-argmax.sv':child_original,
        'production-compare.sv':(prior/'production-board1_fixed_head_logit_greater.sv').read_bytes(),
        'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='sampler_parent_relational',
        reset_constraints='initial\nassume (= [reset_n] true)\nstate 1\nassume (= [reset_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant='seeded-sampling',
            initial_hard_reset=False,concrete_hierarchy_modules=[top,child_name,'board1_fixed_head_logit_greater','board1_fixed_head_compare52_tree'],
            selector_native_bits=native_bits,child_native_bits=child_bits,sequential_fields=fields,
            child_sequential_fields=child_fields,per_field_relation=relations,registered_histories=histories,
            memory_write_ports=memory_writes,logical_logit_write_qualification='Actual greedy row_legal; malformed raw writes cannot lead to healthy sampling reads',
            operand_coupling_predicates=coupling,entry_policy='Healthy model-locked CLEAR, with identical currently authorized retained seed/temperature; old PRNG/transient state arbitrary'),
        cuts=cuts,depth=3,induction_depth=3,cover_depth=10,timeout=args.timeout,
        source_list=['selector.sv','argmax.sv','compare.sv','wrapper.sv'],expected_memories=0,
        primary_only=True,optimize_full=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Native seeded selector plus concrete greedy/comparator hierarchy after healthy CLEAR with the same authorized seed/temperature and no initial hard reset. PRNG rewind/current state, all native scalar storage under phase ownership and every output compared; complete arithmetic retained. Three registered logit/mass/immutable-ROM history contracts remain explicit. Not numerical distribution correctness or a whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())

"""Native numerical-service RAM ownership and actual read-data history."""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load

CASES={
    'rms':('project/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_vector_rmsnorm_service.sv',
           'board1_fixed_vector_rmsnorm_service',5),
    'projection':('project/fpga/token_only_model0_ddr_board1/fixed_group_projection_scale_integration0/rtl/board1_fixed_group_projection_scale_job.sv',
                  'board1_fixed_group_projection_scale_job',2),
    'normalizer':('project/normalizer_pipeline.sv','board1_fixed_vector_normalizer',1),
}


def boundaries(source,definitions,parser):
    replacements=[];free=[];cuts=[];files={}
    for match in re.finditer(r'^\s+(board1_\w+)\s+',source,re.M):
        module=match[1];cursor=match.end()
        if module not in definitions:continue
        if source[cursor]=='#':
            opening=source.index('(',cursor);cursor=opening+1;nesting=1
            while nesting:nesting+=(source[cursor]=='(')-(source[cursor]==')');cursor+=1
        after=re.match(r'\s*(u_\w+)\s*\(',source[cursor:])
        if not after:raise ValueError('Instance header changed')
        instance=after[1];end=cursor+after.end();nesting=1
        while nesting:nesting+=(source[end]=='(')-(source[end]==')');end+=1
        if source[end]!=';':raise ValueError('Instance terminator changed')
        before=source[match.start():end+1];child,relative,raw=definitions[module]
        files['production-child-'+module+'.sv']=raw;assignments=[]
        for port,(direction,shape)in parser.ports(child).items():
            if direction!='output':continue
            found=re.findall(r'\.'+re.escape(port)+r'\s*\(([^()]*)\)',before)
            if len(found)!=1:raise ValueError('Child output changed '+instance+'.'+port)
            value=found[0].strip()
            if not value:continue
            if not re.fullmatch(r'\w+',value):raise ValueError('Non-simple child output '+value)
            name='f_child_'+instance+'_'+port
            free.append('    input wire '+shape+name);assignments.append('    assign '+value+'='+name+';')
            cuts.append(dict(instance=instance,module=module,port=port,expression=value,
                             shape=shape,source=relative,replacement=name,assumptions=[]))
        replacements.append((before,'\n'+'\n'.join(assignments)))
    for before,after in replacements:
        if source.count(before)!=1:raise ValueError('Nonunique instance')
        source=source.replace(before,after,1)
    source=source.replace('\n);',',\n'+',\n'.join(free)+'\n);',1)
    return source,files,cuts,len(replacements)


def monitor_for(kind):
    if kind=='rms':
        address,width,words=8,16,256
        memory,read_data='vector_mem_q','vector_read_q'
        write,write_address,write_data='vector_write_enable','input_row_index_i','input_mantissa_i'
        read,read_address='vector_read_enable','lane_index_q'
        reset='rst_n';newstart='start_valid_i && start_ready_o'
        active='state_q!=ST_IDLE && state_q!=ST_CAPTURE && state_q!=ST_FAULT'
        capture='state_q==ST_CAPTURE';cursor='capture_index_q';bound="9'd256"
        extra='''
            assert(state_q<=ST_FAULT);
            if(vector_read_enable)assert(f_owned);
            assert(selector_q<=12);
            if(state_q>=ST_DIV_ISSUE && state_q<=ST_RAW_ISSUE)begin
                assert(f_rom_live);assert(f_rom_tag==rom_address);
            end
        '''
    elif kind=='normalizer':
        address,width,words=10,58,682
        memory,read_data='record_mem_q','record_read_q'
        write,write_address,write_data='record_write_enable','input_row_index_i','{input_source_exponent_i,input_raw_i}'
        read,read_address='record_read_enable','scan_index_q'
        reset='rst_n';newstart='start_valid_i && start_ready_o'
        active='state_q!=ST_IDLE && state_q!=ST_CAPTURE && state_q!=ST_FAULT'
        capture='state_q==ST_CAPTURE';cursor='capture_index_q';bound='rows_q'
        extra='''
            if(state_q!=ST_IDLE && state_q!=ST_FAULT)begin
                assert(rows_q==128 || rows_q==256 || rows_q==682);
                assert(capture_index_q<rows_q);
                if(state_q!=ST_CAPTURE)assert(scan_index_q<rows_q);
            end
            if(state_q==ST_RESULT)begin
                assert(result_row_index_o==scan_index_q);
                assert(result_last_o==(scan_index_q==rows_q-1'b1));
            end
            if(record_read_enable)begin
                assert(scan_index_q<rows_q);if(f_address<rows_q)assert(f_owned);
            end
        '''
    else:
        address,width,words=10,16,682
        memory,read_data='activation_memory_q','activation_q'
        write,write_address,write_data='activation_store_write','activation_count_q','activation_i'
        read,read_address='activation_store_read','activation_store_read_address'
        reset='reset_n';newstart='start_valid_i && start_ready_o'
        active='state_q==JOB_GROUP_START || state_q==JOB_GROUP_RUN || state_q==JOB_DONE'
        capture='state_q==JOB_LOAD';cursor='activation_count_q';bound='columns_q'
        extra='''
            if(state_q==JOB_LOAD || state_q==JOB_GROUP_START || state_q==JOB_GROUP_RUN || state_q==JOB_DONE)begin
                assert(columns_q==128 || columns_q==256 || columns_q==682);
                assert(activation_count_q<columns_q);assert(column_q<columns_q);
            end
            if(state_q==JOB_GROUP_START || state_q==JOB_GROUP_RUN || state_q==JOB_DONE)assert(f_read_live);
            if(state_q==JOB_LOAD)assert(column_q==0);
            if(activation_store_read && (state_q==JOB_GROUP_RUN ||
                (activation_store_write && activation_expected_last)))begin
                assert(activation_store_read_address<columns_q);
                if(activation_store_read_address==f_address)assert(f_owned);
            end
            if(state_q==JOB_GROUP_RUN && weight_transfer && !weight_protocol_error)begin
                assert(f_read_live);
            end
        '''
    common=f'''
    (* anyconst *) reg [{address-1}:0] f_address;
    reg f_owned,f_read_live,f_read_target;
    reg [{address-1}:0] f_read_tag;
    reg [{width-1}:0] f_shadow,f_read_shadow;
    wire f_new_start={newstart};
    always @(posedge clk)begin
        if(!{reset} || clear_i || f_new_start)begin f_owned<=0;f_read_live<=0;f_read_target<=0;end
        else begin
            if({write} && {write_address}==f_address)begin f_owned<=1;f_shadow<={write_data};end
            if({read})begin
                f_read_live<=1;f_read_tag<={read_address};
                f_read_target<=({read_address}==f_address)&&f_owned;f_read_shadow<=f_shadow;
            end
        end
    end
    always @*if({reset} && !clear_i)begin
        if(f_owned && f_address<{words})assert({memory}[f_address]==f_shadow);
        if(f_read_target && f_address<{words})assert({read_data}==f_read_shadow);
        if(!{'integrated_fail'if kind=='projection'else'range_fault_o'})begin
            if(({capture}) && f_address<{cursor})assert(f_owned);
            if(({active}) && f_address<{bound})assert(f_owned);
{extra}
        end
        cover(({capture}) && {cursor}==2);
    end
'''
    if kind=='rms':
        common+='''
    reg f_rom_live;
    reg [11:0] f_rom_tag;
    always @(posedge clk)begin
        if(!rst_n || clear_i || f_new_start)f_rom_live<=0;
        else if(state_q==ST_LANE_READ && rom_address<3328)begin
            f_rom_live<=1;f_rom_tag<=rom_address;
        end
    end
'''
    return common


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--kind',choices=CASES,required=True)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    ap.add_argument('--mutant',choices=('drop-first-write',))
    ap.add_argument('--clear-entry',action='store_true')
    ap.add_argument('--primary-only',action='store_true')
    ap.add_argument('--solver-memory-mib',type=int,default=0)
    args=ap.parse_args()
    if args.solver_memory_mib and(not args.primary_only or args.solver_memory_mib<1):
        raise ValueError('A positive Z3 memory cap requires primary-only mode')
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    relative,top,census=CASES[args.kind];original=(native/relative).read_bytes()
    found=re.findall(r'^module '+top+r'\b[\s\S]*?^endmodule',original.decode(),re.M)
    if len(found)!=1:raise ValueError('Native service not unique')
    definitions={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw.decode(),re.M):
            if m[1]in definitions and definitions[m[1]][0]!=m[0]:raise ValueError('Ambiguous child')
            definitions[m[1]]=(m[0],name,raw)
    source,files,cuts,count=boundaries(found[0],definitions,parser)
    if count!=census:raise ValueError('Native child census changed '+str(count))
    if args.mutant:
        enable,index={'rms':('vector_write_enable','input_row_index_i'),
            'normalizer':('record_write_enable','input_row_index_i'),
            'projection':('activation_store_write','activation_count_q')}[args.kind]
        before='if ('+enable+')'
        if source.count(before)!=1:raise ValueError('Native RAM mutation site changed')
        source=source.replace(before,'if ('+enable+' && '+index+'!=0)',1)
    monitor=monitor_for(args.kind)
    if args.clear_entry:
        reset='reset_n'if args.kind=='projection'else'rst_n'
        monitor=monitor.replace('always @*if('+reset+' && !clear_i)',
            'always @*if('+reset+' && !clear_i && f_completed_clear)')
        monitor+='\n    reg f_completed_clear=0;\n    always @(posedge clk)if(!'+reset+')f_completed_clear<=0;else if(clear_i)f_completed_clear<=1;\n'
        monitor=monitor.replace('cover((', 'cover(f_completed_clear && (')
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    ports=parser.ports(source);reset='reset_n'if args.kind=='projection'else'rst_n'
    wrapper='module native_service_memory(\n'+',\n'.join('    '+direction+' wire '+shape+
        ('rst_n'if name==reset else name)for name,(direction,shape)in ports.items())+'\n);\n'
    wrapper+='    '+top+(' #(.ADDR_W(19))'if args.kind=='projection'else'')+' u_native('+','.join(
        '.'+n+'('+('rst_n'if n==reset else n)+')'for n in ports)+');\nendmodule\n'
    files.update({'production-service.sv':original,'service.sv':('`undef FORMAL\n'+source+'\n').encode(),
                  'monitor.inc.sv':monitor.encode(),'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_service_memory',
        reset_constraints=('initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n'if args.clear_entry else
            'initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'),
        assertions=monitor.count('assert('),covers=1,observer_constants=1,expected_memories=1,
        binding=dict(native_join=binding,variant=args.variant,production_path=relative,service=args.kind,
            initial_hard_reset=not args.clear_entry),cuts=cuts,
        depth=7 if args.mutant else 4,induction_depth=3,cover_depth=10,timeout=args.timeout,mutant=args.mutant,
        source_list=['service.sv','wrapper.sv'],optimize_full=True,
        map_literal_roms=True,
        primary_only=args.primary_only,
        solver_cli={s:['--unroll']+(['-S','-memory:'+str(args.solver_memory_mib)]if s=='z3'and args.solver_memory_mib else[])for s in ('z3','cvc5')},
        scope='Actual numerical-service control plus full native RAM and registered read-data history. Current-job initialization before permitted use; each complete child output unrestricted. No numerical-service correctness or complete session theorem.')


if __name__=='__main__':raise SystemExit(main())

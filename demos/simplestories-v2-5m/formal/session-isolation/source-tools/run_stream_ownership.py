"""Native group metadata storage, all reachable reader/buffer children retained."""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load

TOP='board1_fixed_group_ddr_stream'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=40)
    ap.add_argument('--mutant',action='store_true')
    ap.add_argument('--kind',choices=('group-stream','lookup'),default='group-stream')
    ap.add_argument('--clear-entry',action='store_true')
    ap.add_argument('--primary-only',action='store_true')
    ap.add_argument('--solver-memory-mib',type=int,default=0)
    args=ap.parse_args();builder=load('addresses',HERE.parent/'authentication-access/run_model_addresses.py')
    if args.solver_memory_mib and(not args.primary_only or args.solver_memory_mib<1):
        raise ValueError('A positive Z3 memory cap requires primary-only mode')
    files,binding,assertions,covers=builder.derive(args.package,args.variant,args.kind)
    if args.clear_entry:
        # The separate native address proofs retain their boot-reset scope.
        # This new scope checks fresh storage histories after CLEAR; it does
        # not require unused retained addresses to be initialized by CLEAR.
        removed=[]
        for name,data in list(files.items()):
            if not name.endswith('address-monitor.inc.sv'):continue
            targets=[n+'.sv'for n in binding['isolated_native_modules']if data in files[n+'.sv']]
            if len(targets)!=1 or files[targets[0]].count(data)!=1:raise ValueError('Original address observer not unique')
            files[targets[0]]=files[targets[0]].replace(data,b'',1)
            assertions-=data.decode().count('assert(');covers-=data.decode().count('cover(');removed.append(name)
        if assertions or covers:raise ValueError('Unreviewed original property inventory')
        binding.update(initial_hard_reset=False,removed_address_only_observers=removed,
            new_scope=('Native fresh lookup request/accepted-word history after CLEAR; existing boot-scoped address theorems remain separate'if args.kind=='lookup'else
                'Native fresh metadata storage and captured-word history after CLEAR; existing boot-scoped address theorems remain separate'))
    top=builder.ROOTS[args.kind]
    monitor='''
    (* anyconst *) reg [5:0] f_metadata_row;
    reg f_metadata_owned;
    reg [23:0] f_metadata_shadow;
    always @(posedge clk)begin
        if(!reset_n || clear_i || (start_valid_i && start_ready_o))f_metadata_owned<=0;
        else if(metadata_transfer && metadata_count_q[5:0]==f_metadata_row)begin
            f_metadata_owned<=1;
            f_metadata_shadow<={meta_exponent,meta_multiplier};
        end
    end
    always @*if(reset_n && !clear_i)begin
        if(f_metadata_owned)assert({row_exponent_q[f_metadata_row],row_multiplier_q[f_metadata_row]}==f_metadata_shadow);
        if(!fail_closed_o)begin
            assert(metadata_count_q<=64);
            if(state_q==ST_META_START || state_q==ST_META_RUN || state_q==ST_HEADER ||
               state_q==ST_WEIGHT || state_q==ST_DONE)begin
                assert(valid_lanes_q==42 || valid_lanes_q==51 || valid_lanes_q==64);
                assert(metadata_count_q<=valid_lanes_q);
            end
            if({1'b0,f_metadata_row}<metadata_count_q)assert(f_metadata_owned);
            if(group_valid_o)begin
                assert(metadata_count_q==valid_lanes_q);
                if({1'b0,f_metadata_row}<valid_lanes_q)begin
                    assert(f_metadata_owned);
                    assert({group_row_exponent_o[f_metadata_row*8 +:8],
                            group_row_multiplier_o[f_metadata_row*16 +:16]}==f_metadata_shadow);
                end else begin
                    assert(group_row_exponent_o[f_metadata_row*8 +:8]==0);
                    assert(group_row_multiplier_o[f_metadata_row*16 +:16]==0);
                end
            end
        end
        cover(state_q==ST_META_RUN && metadata_count_q==2);
    end
'''
    if args.kind=='lookup':monitor=(HERE/'lookup-history-monitor.inc.sv').read_text()
    completed_clear='\n    reg f_completed_clear=0;\n    always @(posedge clk)if(!reset_n)f_completed_clear<=0;else if(clear_i)f_completed_clear<=1;\n'
    if args.clear_entry:
        monitor=monitor.replace('if(reset_n && !clear_i','if(reset_n && f_completed_clear && !clear_i')+completed_clear
    word_monitor=''
    if args.kind=='group-stream':
        word_monitor=(HERE/'metadata-word-history-monitor.inc.sv').read_text()
        if args.clear_entry:
            word_monitor=word_monitor.replace('if(reset_n && !clear_i && !fail_closed_o)',
                'if(reset_n && !clear_i && !fail_closed_o && f_completed_clear)')+completed_clear
        child='board1_fixed_projection_metadata_reader.sv'
        files[child]=files[child].replace(b'\nendmodule',b'\n'+word_monitor.encode()+b'\nendmodule',1)
        files['word-history-monitor.inc.sv']=word_monitor.encode()
    # No functional logic or child instance is replaced in this scope.
    name=top+'.sv';files[name]=files[name].replace(b'\nendmodule',b'\n'+monitor.encode()+b'\nendmodule',1)
    if args.mutant:
        before=b'row_multiplier_q[metadata_count_q[5:0]] <= meta_multiplier;'
        after=b"row_multiplier_q[metadata_count_q[5:0]] <= metadata_count_q==0 ? 16'd0 : meta_multiplier;"
        if files[name].count(before)!=1:raise ValueError('Actual metadata mutation site changed')
        files[name]=files[name].replace(before,after,1)
    files['storage-monitor.inc.sv']=monitor.encode();files['storage-runner.py']=Path(__file__).read_bytes()
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_model_addresses',
        reset_constraints=('initial\nassume (= [reset_n] true)\nstate 1\nassume (= [reset_n] true)\n'if args.clear_entry else
            'initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n'),
        assertions=assertions+monitor.count('assert(')+word_monitor.count('assert('),covers=covers+monitor.count('cover('),observer_constants=monitor.count('(* anyconst *)'),
        binding=binding,cuts=[],depth=12 if args.mutant else 6,induction_depth=4,cover_depth=30,timeout=args.timeout,
        mutant='corrupt-metadata-row-zero'if args.mutant else None,
        source_list=[n+'.sv'for n in binding['isolated_native_modules']]+['wrapper.sv'],
        map_literal_roms=True,optimize_full=True,primary_only=args.primary_only,
        solver_cli={s:['--unroll']+(['-S','-memory:'+str(args.solver_memory_mib)]if s=='z3'and args.solver_memory_mib else[])for s in('z3','cvc5')},
        scope=('Actual native semantic lookup: current request/address/lane ownership, fresh accepted response data history and CLEAR-drain isolation; all address logic retained and private memory replies arbitrary.'if args.kind=='lookup'else
            'Actual native group metadata stream with every reachable metadata/address/weight-buffer child retained. Every live published metadata row has current-job write ownership and exact stored history; invalid header rows are zero. Metadata reader emission comes from its fresh captured current word. Native dimensions/address provenance retained, external model replies arbitrary.')+' Does not establish whole-device session isolation or numerical correctness.')


if __name__=='__main__':raise SystemExit(main())

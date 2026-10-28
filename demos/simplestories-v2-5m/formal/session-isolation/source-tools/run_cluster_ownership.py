"""Ownership in the actual instantiated clustered projection and four tiles.

Retains all tile payload/metadata stores, parent pipeline and native dimensions.
Only complete native MAC replies are free. Properties establish initialization
and authority at the MAC/tile/pipeline boundaries, not vendor DSP semantics.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load

TOP='board1_clustered_projection_scale2'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    ap.add_argument('--clear-entry',action='store_true')
    ap.add_argument('--primary-only',action='store_true')
    ap.add_argument('--solver-memory-mib',type=int,default=0)
    ap.add_argument('--tile-permissions',action='store_true')
    ap.add_argument('--tile-replies',action='store_true')
    args=ap.parse_args()
    if args.solver_memory_mib and(not args.primary_only or args.solver_memory_mib<1):
        raise ValueError('A positive Z3 memory cap requires primary-only mode')
    if args.tile_permissions and not args.clear_entry:raise ValueError('Caller-permission joins require the reviewed CLEAR entry')
    if args.tile_replies and not args.tile_permissions:raise ValueError('Reply ownership requires the tile permission join')
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    raw=(native/'project/cluster-engine.sv').read_bytes();tile_raw=(native/'project/cluster-tile.sv').read_bytes()
    source=raw.decode();tiles=tile_raw.decode()
    serial='logic slice_busy_q' in tiles
    lane_reply_width=26 if serial else 768
    before=re.search(r'        board1_w10_a16_mul_exact u_mul\s*\([\s\S]*?\);'if serial else
                     r'        board1_projection_dsp_accumulator u_mac\([\s\S]*?\);',tiles)
    if before is None:raise ValueError('Native tile MAC instance changed')
    tiles=tiles[:before.start()]+('        assign product=f_mac_reply_i;'if serial else
                                '        assign accumulated=f_mac_reply_i[lane*48 +:48];')+tiles[before.end():]
    tiles=tiles.replace('\n);',f',\n    input wire [{lane_reply_width-1}:0] f_mac_reply_i,\n    input wire [3:0] f_observed_lane_i,'+
        ('\n    input wire f_parent_drain_i,'if serial else'')+'\n    output wire f_acc_owned_o,f_first_seen_o'+(',f_busy_o,f_drained_o,\n    output wire [3:0] f_slice_o'if serial else'')+'\n);',1)
    tile_monitor='''
    reg f_operands_owned,f_product_owned,f_acc_owned,f_first_seen;
    reg f_metadata_owned,f_read_target;
    reg [23:0] f_metadata_shadow,f_read_shadow;
    assign f_acc_owned_o=f_acc_owned;
    assign f_first_seen_o=f_first_seen;
    always @(posedge clk)begin
        if(!reset_n || kill_i || begin_i)begin
            f_operands_owned<=0;f_product_owned<=0;f_acc_owned<=0;f_first_seen<=0;
            f_metadata_owned<=0;f_read_target<=0;
        end else begin
            if(accept_i)begin f_operands_owned<=1;f_first_seen<=1;end
            if(op_valid_q)f_product_owned<=f_operands_owned;
            if(product_valid_q)f_acc_owned<=f_product_owned && (product_first_q || f_acc_owned);
            if(metadata_write_i && metadata_lane_i==f_observed_lane_i)begin
                f_metadata_owned<=1;f_metadata_shadow<={metadata_multiplier_i,metadata_exponent_i};end
            if(read_i)begin
                f_read_target<=(read_lane_i==f_observed_lane_i)&&f_metadata_owned;
                f_read_shadow<=f_metadata_shadow;
            end
        end
    end
    always @*if(reset_n && !kill_i && !begin_i)begin
        assert(f_first_seen==f_operands_owned);
        if(f_product_owned)assert(f_first_seen);
        if(f_first_seen)assert(f_acc_owned || (op_valid_q && op_first_q) || (product_valid_q && product_first_q));
        if(accept_i && !f_first_seen)assert(first_i);
        if(op_valid_q)begin
            assert(f_operands_owned);
            if(!op_first_q)assert(f_acc_owned || (product_valid_q && product_first_q));
        end
        if(product_valid_q)begin
            assert(f_product_owned);if(!product_first_q)assert(f_acc_owned);
        end
        if(acc_result_valid_q)assert(f_acc_owned);
        if(done_o)begin assert(acc_result_valid_q);assert(f_acc_owned);end
        if(read_i)assert(f_acc_owned);
        if(f_metadata_owned)assert({multiplier_q[f_observed_lane_i],exponent_q[f_observed_lane_i]}==f_metadata_shadow);
        if(f_read_target)assert({multiplier_o,exponent_o}==f_read_shadow);
    end
'''
    if serial:tile_monitor=(HERE/'serial-tile-monitor.inc.sv').read_text()
    if args.clear_entry:
        tile_monitor=tile_monitor.replace('if(reset_n && !kill_i && !begin_i)',
            'if(reset_n && !kill_i && !begin_i && f_clear_seen_i)')
        tiles=tiles.replace('\n);',',\n    input wire f_clear_seen_i\n);',1)
    permission_receipt=None
    if args.tile_permissions:
        from record_progress import audit
        name='tile-parent-serial-r1'if serial else'tile-parent-parallel-r2'
        permission_receipt=audit(name,'actual tile relation prerequisite')
        if permission_receipt['status']!='proved_component':raise ValueError('Native tile relation incomplete')
        proof=HERE/'runs'/name;pi=json.loads((proof/'INPUTS.json').read_text())
        if(proof/'production-tile.sv').read_bytes()!=tile_raw:raise ValueError('Caller and child tile sources differ')
        protocol=pi['binding']['caller_permissions']
        tiles=tiles.replace('\n);',',\n    input wire f_parent_epoch_i\n);',1)
        tile_monitor+='''
    reg f_rel_descriptor_owned;
    wire f_rel_permission='''+protocol+''';
    always @(posedge clk)if(!reset_n || kill_i || begin_i)
        f_rel_descriptor_owned<=reset_n && begin_i;
    always @*if(reset_n && f_clear_seen_i)begin
        assert(f_rel_permission);
        if(f_parent_epoch_i && !kill_i && !begin_i)assert(f_rel_descriptor_owned);
    end
'''
    if args.tile_replies:
        tiles=tiles.replace('\n);',',\n    output wire f_metadata_owned_o,f_metadata_target_o,f_dot_target_o\n);',1)
        tile_monitor+='\n    assign f_metadata_owned_o=f_metadata_owned;\n    assign f_metadata_target_o=f_read_target;\n'
        if serial:tile_monitor+='    assign f_dot_target_o=f_dot_read_target;\n'
        else:tile_monitor+='''
    reg f_rel_dot_target;
    assign f_dot_target_o=f_rel_dot_target;
    always @(posedge clk)if(!reset_n || kill_i || begin_i)f_rel_dot_target<=0;
        else if(read_i)f_rel_dot_target<=read_lane_i==f_observed_lane_i && f_acc_owned;
'''
    # Insert into only the actual tile, not the other modules in its file.
    tiles=tiles.replace('\nendmodule','\n'+tile_monitor+'\nendmodule',1)
    source=source.replace('\n);',f',\n    input wire [{4*lane_reply_width-1}:0] f_mac_reply_i\n);',1)
    old='.clk(clk), .reset_n(reset_n), .kill_i(kill),'
    if source.count(old)!=1:raise ValueError('Actual tile connection changed')
    source=source.replace(old,old+f'\n            .f_mac_reply_i(f_mac_reply_i[tile*{lane_reply_width} +:{lane_reply_width}]),\n            .f_observed_lane_i(f_row[3:0]),.f_acc_owned_o(f_tile_acc_owned[tile]),\n            .f_first_seen_o(f_tile_first_seen[tile]),'+
        ('\n            .f_busy_o(f_tile_busy[tile]),.f_drained_o(f_tile_drained[tile]),.f_slice_o(f_tile_slice[tile*4 +:4]),.f_parent_drain_i(state_q==DRAIN || state_q==EMIT || state_q==DONE),'if serial else''),1)
    if args.clear_entry:
        source=source.replace('.f_mac_reply_i(f_mac_reply_i[tile*',
            '.f_clear_seen_i(f_completed_clear),\n            .f_mac_reply_i(f_mac_reply_i[tile*',1)
    if args.tile_permissions:
        source=source.replace('.f_clear_seen_i(f_completed_clear),',
            '.f_clear_seen_i(f_completed_clear),.f_parent_epoch_i(state_q!=IDLE && state_q!=FAIL),',1)
    if args.tile_replies:
        source=source.replace('.f_first_seen_o(f_tile_first_seen[tile]),',
            '.f_first_seen_o(f_tile_first_seen[tile]),\n            .f_metadata_owned_o(f_tile_md_owned[tile]),.f_metadata_target_o(f_tile_md_target[tile]),.f_dot_target_o(f_tile_dot_target[tile]),',1)
    monitor='''
    (* anyconst *) reg [5:0] f_row;
    reg f_metadata_owned,f_started,f_have_weight;
    reg [3:0] f_pipe_owned;
    wire [3:0] f_tile_acc_owned,f_tile_first_seen;
    always @(posedge clk)begin
        if(!reset_n || clear_i || start_fire)begin
            f_metadata_owned<=0;f_have_weight<=0;f_pipe_owned<=0;
        end else begin
            if(metadata_fire && !metadata_error && metadata_count_q[5:0]==f_row)f_metadata_owned<=1;
            if(weight_fire)f_have_weight<=1;
            if(control_error)f_pipe_owned<=0;
            else if(advance)f_pipe_owned<={f_pipe_owned[2:0],issue};
        end
        if(!reset_n || clear_i)f_started<=0;else if(start_fire && descriptor_ok)f_started<=1;
    end
    always @*if(reset_n && !clear_i && !fail_q && !upstream_fail_closed_i)begin
        assert(state_q==IDLE || state_q==META || state_q==WEIGHTS || state_q==DRAIN || state_q==EMIT || state_q==DONE || state_q==FAIL);
        if(state_q!=IDLE && state_q!=FAIL)begin
            assert(f_started);assert(valid_lanes_q==42 || valid_lanes_q==51 || valid_lanes_q==64);
            assert(columns_q==256 || columns_q==682);
            assert(metadata_count_q<valid_lanes_q);assert(column_q<columns_q);
        end
        if(state_q==META && {1'b0,f_row}<metadata_count_q)assert(f_metadata_owned);
        if(state_q==META)begin assert(column_q==0);assert(!f_have_weight);assert(f_tile_first_seen==0);end
        if(state_q==WEIGHTS || state_q==DRAIN || state_q==EMIT || state_q==DONE)begin
            if({1'b0,f_row}<valid_lanes_q)assert(f_metadata_owned);
            assert(f_tile_first_seen=={4{f_have_weight}});
        end
        if(state_q==WEIGHTS && !f_have_weight)assert(column_q==0);
        if(state_q==EMIT || state_q==DONE)assert(&f_tile_acc_owned);
        assert(scale_valid_q==f_pipe_owned);
        if(issue)begin assert(issue_count_q<valid_lanes_q);assert(&f_tile_acc_owned);end
        if(scale_valid_q[0])assert({1'b0,row_pipe_q[0]}<valid_lanes_q);
        if(scale_valid_q[1])assert({1'b0,row_pipe_q[1]}<valid_lanes_q);
        if(scale_valid_q[2])assert({1'b0,row_pipe_q[2]}<valid_lanes_q);
        if(scale_valid_q[3])assert({1'b0,row_pipe_q[3]}<valid_lanes_q);
        if(result_valid_o)begin assert(f_pipe_owned[3]);assert(result_row_index_o==row_base+row_pipe_q[3]);end
        cover(state_q==META && metadata_count_q==2);
    end
'''
    if serial:
        monitor=monitor.replace('wire [3:0] f_tile_acc_owned,f_tile_first_seen;',
            'wire [3:0] f_tile_acc_owned,f_tile_first_seen,f_tile_busy,f_tile_drained;\n    wire [15:0] f_tile_slice;')
        monitor=monitor.replace('        assert(scale_valid_q==f_pipe_owned);',
            "        assert(f_tile_busy==((weight_pause_q!=0)?4'hf:4'h0));\n        if(state_q==EMIT || state_q==DONE)assert(&f_tile_drained);\n        assert(scale_valid_q==f_pipe_owned);")
        monitor=monitor.replace('        assert(scale_valid_q==f_pipe_owned);',
            '\n'.join("        if(f_tile_busy["+str(i)+"])assert({1'b0,weight_pause_q}+{1'b0,f_tile_slice["+str(i*4)+" +:4]}==5'd16);"for i in range(4))+
            '\n        assert(scale_valid_q==f_pipe_owned);')
    if args.clear_entry:
        monitor=monitor.replace('if(reset_n && !clear_i && !fail_q && !upstream_fail_closed_i)',
            'if(reset_n && f_completed_clear && !clear_i && !fail_q && !upstream_fail_closed_i)')
        monitor+='\n    reg f_completed_clear=0;\n    always @(posedge clk)if(!reset_n)f_completed_clear<=0;else if(clear_i)f_completed_clear<=1;\n'
    if args.tile_replies:
        monitor+='\n    wire [3:0] f_tile_md_owned,f_tile_md_target,f_tile_dot_target;\n'
        extra='''
        if(state_q==META || state_q==WEIGHTS || state_q==DRAIN)assert(scale_valid_q==0);
        if({1'b0,f_row}<valid_lanes_q && (state_q==WEIGHTS || state_q==DRAIN || state_q==EMIT || state_q==DONE ||
            (state_q==META && {1'b0,f_row}<metadata_count_q)))assert(f_tile_md_owned[f_row[5:4]]);
        if(scale_valid_q[0] && state_q==EMIT && row_pipe_q[0]==f_row)begin
            assert(selected_tile_q==f_row[5:4]);
            assert(f_tile_md_target[selected_tile_q]);
            assert(f_tile_dot_target[selected_tile_q]);
        end
'''
        site='        assert(scale_valid_q==f_pipe_owned);'
        if monitor.count(site)!=1:raise ValueError('Actual ownership assertion insertion site changed')
        monitor=monitor.replace(site,extra+site,1)
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    ports=parser.ports(source)
    wrapper='module native_cluster_ownership(\n'+',\n'.join('    '+d+' wire '+s+('rst_n'if n=='reset_n'else n)
        for n,(d,s)in ports.items())+'\n);\n'+TOP+' u_native('+','.join('.'+n+'('+('rst_n'if n=='reset_n'else n)+')'for n in ports)+');\nendmodule\n'
    files={'production-cluster.sv':raw,'production-tile.sv':tile_raw,
        'cluster.sv':('`undef FORMAL\n'+source).encode(),'tile.sv':('`undef FORMAL\n'+tiles).encode(),
        'wrapper.sv':wrapper.encode(),'parent-monitor.inc.sv':monitor.encode(),
        'tile-monitor.inc.sv':tile_monitor.encode(),'runner.py':Path(__file__).read_bytes()}
    cuts=[dict(module='board1_w10_a16_mul_exact'if serial else'board1_projection_dsp_accumulator',
        instances=4 if serial else 64,output='product_o'if serial else'accumulator_o',
        replacement='f_mac_reply_i',assumptions=[],scope='Complete native MAC replies unrestricted; no vendor recurrence semantics assumed for ownership checks')]
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_cluster_ownership',
        reset_constraints=('initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n'if args.clear_entry else
            'initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'),
        assertions=monitor.count('assert(')+4*tile_monitor.count('assert('),covers=1,observer_constants=1,
        binding=dict(native_join=binding,variant=args.variant,production_paths=['project/cluster-engine.sv','project/cluster-tile.sv'],
            projection_architecture='serialized sixteen-context tiles'if serial else'parallel registered native MAC tiles',
            initial_hard_reset=not args.clear_entry,
            native_tile_caller_permissions=permission_receipt,
            selected_tile_registered_reply_ownership=args.tile_replies,
            native_top_census='HIERARCHY-BINDINGS.json'),cuts=cuts,depth=4,induction_depth=4,cover_depth=8,
        timeout=args.timeout,source_list=['cluster.sv','tile.sv','wrapper.sv'],map_literal_roms=True,optimize_full=True,
        primary_only=args.primary_only,
        solver_cli={s:['--unroll']+(['-S','-memory:'+str(args.solver_memory_mib)]if s=='z3'and args.solver_memory_mib else[])for s in ('z3','cvc5')},
        scope='Actual instantiated native clustered projection and all four16-lane tiles. Current-job metadata ownership, resetless operand/product/accumulator authority, first-overwrite before reuse, and stalled output-pipeline ownership. Complete native MAC replies unrestricted; physical vendor DSP recurrence semantics are a separate boundary. Not a numerical or whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())

"""Two complete native cluster controllers and all eight native tiles.

Only registered MAC recurrence and audited stateless multiplier congruence
remain contracts. Tile replies and metadata/accumulator memories are concrete.
The frozen component models supply nondriving observers; all connections to
functional child ports come from the actual native instance connection taps.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap


def digest(raw):
    import hashlib
    return hashlib.sha256(raw).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--serial',action='store_true')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=35)
    args=ap.parse_args();serial=args.serial
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    parent=HERE/'runs'/('cluster-parent-serial-r2'if serial else'cluster-parent-parallel-r4')
    child=HERE/'runs'/('tile-parent-serial-r2'if serial else'tile-parent-parallel-r3')
    caller=HERE/'runs'/('serial-cluster-reply-ownership-r1'if serial else'cluster-reply-ownership-r2')
    pi=json.loads((parent/'INPUTS.json').read_text());ti=json.loads((child/'INPUTS.json').read_text())
    if (parent/'production-tile.sv').read_bytes()!=(child/'production-tile.sv').read_bytes():
        raise ValueError('Native parent/tile source mismatch')
    for name in('production-cluster.sv','production-tile.sv'):
        if (parent/name).read_bytes()!=(caller/name).read_bytes():
            raise ValueError('Native caller/parent source mismatch')
    cluster=(parent/'cluster.sv').read_text();tile=(child/'tile.sv').read_text()
    # Add the proved unilateral caller histories to the actual controller.
    owner=(caller/'cluster.sv').read_text()
    monitor=owner[owner.index('    (* anyconst *) reg [5:0] f_row;'):owner.index('\nendmodule',owner.index('    (* anyconst *) reg [5:0] f_row;'))]
    monitor=monitor.replace('    (* anyconst *) reg [5:0] f_row;','    wire [5:0] f_row=f_observed_row_i;')
    monitor=re.sub(r'\s*cover\(state_q==META && metadata_count_q==2\);','',monitor)
    # Use the common post-CLEAR observer, without an independently initialized
    # history flag in each controller.
    monitor=monitor.replace('    reg f_completed_clear=0;\n    always @(posedge clk)if(!reset_n)f_completed_clear<=0;else if(clear_i)f_completed_clear<=1;',
        '    wire f_completed_clear=f_join_i;')
    names=['f_tile_acc_owned','f_tile_first_seen','f_tile_md_owned','f_tile_md_target','f_tile_dot_target']
    if serial:names+=['f_tile_busy','f_tile_drained','f_tile_slice']
    cluster=cluster.replace('\n);',',\n    input wire f_join_i,\n    input wire [5:0] f_observed_row_i,\n'+',\n'.join(
        '    input wire ['+('15'if n=='f_tile_slice'else'3')+':0] '+n+'_i'for n in names)+'\n);',1)
    for n in names:monitor+='\n    assign '+n+'='+n+'_i;'
    cluster=cluster.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    # A full mask, rather than only the selected symbolic observer word, owns
    # registered metadata reads. All 16 real words remain independent memories.
    ghost='''
    reg f_full_read_owned,f_full_dot_owned;
    always @(posedge clk)if(!reset_n || kill_i || begin_i)begin
        f_full_read_owned<=0;f_full_dot_owned<=0;
    end else if(read_i)begin
        f_full_read_owned<=f_rel_metadata_mask[read_lane_i];
        f_full_dot_owned<=F_ACCUMULATOR_OWNER;
    end
'''
    ghost=ghost.replace('F_ACCUMULATOR_OWNER','f_acc_mask[read_lane_i]'if serial else'f_acc_owned')
    if serial:
        ghost+='''
    // The first accepted beat creates operand-valid before product-valid.
    // Keep this native phase fact explicit to close one-step mask induction.
    always @*if(reset_n && f_rel_join_i && !kill_i && !begin_i && f_first_seen && f_age==0)
        assert(!product_valid_q);
'''
    tile=tile.replace('\nendmodule','\n'+ghost+'\nendmodule',1)
    tile=tap(tile,{'f_full_read_owned_o':('','f_full_read_owned'),
        'f_full_dot_owned_o':('','f_full_dot_owned')})
    for port in ('multiplier','exponent'):
        before='assign f_when_'+port+'_o_o=f_read_target;'
        if tile.count(before)!=1:raise ValueError('Native metadata read observer changed')
        tile=tile.replace(before,'assign f_when_'+port+'_o_o=f_full_read_owned;')
    before='assign f_when_dot_o_o=f_rel_dot_target;'
    if tile.count(before)!=1:raise ValueError('Native dot read observer changed')
    tile=tile.replace(before,'assign f_when_dot_o_o=f_full_dot_owned;')
    cp=parser.ports(cluster);tp=parser.ports(tile)
    cuts=pi['internal_cuts'];tile_replies=pi['binding']['tile_reply_coupling']
    coupling={n:p for n,p in pi['binding']['operand_coupling_predicates'].items()if n not in tile_replies}
    lines=['module assembled_cluster_relational(',',\n'.join(
        ['    input wire '+sh+('rst_n'if n=='reset_n'else n)for n,(di,sh)in cp.items()
         if di=='input'and n not in tile_replies and n not in('f_join_i','f_observed_row_i')and not n.startswith('f_tile_')]+
        ['    input wire '+cp[n][1]+'discarded_'+n for n in coupling]+
        ['    input wire ['+str((26 if serial else 768)*4-1)+':0] f_mac_reply_i',
         '    input wire ['+str((26 if serial else 768)*4-1)+':0] discarded_mac_reply_i']),');',
        '    reg f_joined=0;(* anyconst *)reg[5:0] f_row;']
    for copy in('a','b'):
        for n,(di,sh)in cp.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        for n in tile_replies:lines.append('    wire '+cp[n][1]+copy+'_'+n+';')
        for lane in range(4):
            for n,(di,sh)in tp.items():
                if di=='output':lines.append('    wire '+sh+copy+'_tile'+str(lane)+'_'+n+';')
        for n in names:
            port={'f_tile_acc_owned':'f_acc_owned_o','f_tile_first_seen':'f_first_seen_o',
                'f_tile_md_owned':'f_metadata_owned_o','f_tile_md_target':'f_metadata_target_o',
                'f_tile_dot_target':'f_dot_target_o','f_tile_busy':'f_busy_o',
                'f_tile_drained':'f_drained_o','f_tile_slice':'f_slice_o'}[n]
            lines.append('    wire ['+('15'if n=='f_tile_slice'else'3')+':0] '+copy+'_'+n+'={'+','.join(copy+'_tile'+str(lane)+'_'+port for lane in reversed(range(4)))+'};')
        con=[]
        for n,(di,_)in cp.items():
            value=('rst_n'if n=='reset_n'else n)if di=='input'else copy+'_'+n
            if n in tile_replies:value=copy+'_'+n
            elif n=='f_join_i':value='f_joined'
            elif n=='f_observed_row_i':value='f_row'
            elif n.endswith('_i')and n[:-2]in names:value=copy+'_'+n[:-2]
            elif copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    board1_clustered_projection_scale2 u_'+copy+'('+','.join(con)+');')
        for lane in range(4):
            prefix=copy+'_tile'+str(lane)+'_';con=[]
            for n,(di,_)in tp.items():
                if di=='output':value=prefix+n
                elif n=='clk':value='clk'
                elif n=='reset_n':value='rst_n'
                elif n=='f_rel_join_i':value='f_joined'
                elif n=='f_observed_lane_i':value='f_row[3:0]'
                elif n=='f_mac_reply_i':
                    w=26 if serial else 768;part='['+str(lane*w)+' +:'+str(w)+']'
                    value='f_mac_reply_i'+part
                    if copy=='b':value='(a_tile'+str(lane)+('_f_operands_owned_o'if serial else'_f_acc_owned_o')+' ? '+value+' : discarded_mac_reply_i'+part+')'
                else:
                    spec=pi['binding']['actual_tile_inputs'][n];w=spec['width']
                    value=copy+'_'+spec['tap']+'['+str(lane*w)+' +:'+str(w)+']'
                con.append('.'+n+'('+value+')')
            lines.append('    board1_projection_tile16 u_'+copy+'_tile'+str(lane)+'('+','.join(con)+');')
        for n,row in tile_replies.items():
            port=n[len('f_tile_'):-2]
            lines.append('    assign '+copy+'_'+n+'={'+','.join(copy+'_tile'+str(lane)+'_'+port for lane in reversed(range(4)))+'};')
    # Retain the exact parent induction conclusions; no tile output equality
    # assumption is inserted. Their actual connected values must prove them.
    pw=(parent/'wrapper.sv').read_text()
    body=pw[pw.index('    always @*if(rst_n && f_joined)begin'):pw.index('    always @(posedge clk)begin',pw.index('    always @*if(rst_n && f_joined)begin'))]
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=1;',body]
    tw=(child/'wrapper.sv').read_text()
    body=tw[tw.index('    always @*if(rst_n && f_joined &&'):tw.index('    always @(posedge clk)begin',tw.index('    always @*if(rst_n && f_joined &&'))]
    body=body.replace('if(a_f_metadata_target_o)begin','if(a_f_full_read_owned_o)begin')
    body=body.replace('if(a_f_dot_target_o)assert(a_dot_o==b_dot_o);',
        'if(a_f_full_dot_owned_o)assert(a_dot_o==b_dot_o);')
    body=body.replace('    end\n','        assert(a_f_full_read_owned_o==b_f_full_read_owned_o);\n    end\n')
    body=body.replace('    end\n','        assert(a_f_full_dot_owned_o==b_f_full_dot_owned_o);\n    end\n')
    for lane in range(4):
        scope=re.sub(r'\b([ab])_(\w+)',lambda m:m[1]+'_tile'+str(lane)+'_'+m[2],body).replace('f_word','f_row[3:0]')
        lines.append(scope)
    lines+=['    always @*if(rst_n && f_joined)begin']
    for copy in('a','b'):
        active=copy+'_f_state_state_q_o'
        for lane in range(4):
            prefix=copy+'_tile'+str(lane)+'_'
            lines+=['        assert('+prefix+'f_permission_o);',
                '        if('+active+'>=1 && '+active+'<=5 && !'+copy+'_f_input_tile_kill_i_o['+str(lane)+'] && !'+copy+'_f_input_tile_begin_i_o['+str(lane)+'])assert('+prefix+'f_descriptor_owned_o);']
            if serial:
                # Restore the actual caller's tail/drain invariant, which the
                # conditional standalone tile correctly treated as a premise.
                tail='('+prefix+'f_state_slice_busy_q_o && '+prefix+'f_state_beat_last_q_o) || ('+prefix+'f_state_op_valid_q_o && '+prefix+'f_state_op_last_q_o) || ('+prefix+'f_state_product_valid_q_o && '+prefix+'f_state_product_last_q_o)'
                guard='!'+copy+'_f_input_tile_kill_i_o['+str(lane)+'] && !'+copy+'_f_input_tile_begin_i_o['+str(lane)+']'
                lines.append('        if('+guard+' && ('+tail+'))assert('+active+'==3);')
            for word in range(16):
                row=lane*16+word
                cond='('+active+'==1 && '+copy+'_f_state_metadata_count_q_o>'+str(row)+') || ('+active+'>=2 && '+active+'<=5 && '+copy+'_f_state_valid_lanes_q_o>'+str(row)+')'
                lines.append('        if(!clear_i && !upstream_fail_closed_i && !'+copy+'_f_state_fail_q_o && ('+cond+'))assert('+prefix+'f_metadata_mask_o['+str(word)+']);')
            guard=copy+'_f_live_o && '+active+'==4 && '+copy+'_f_state_scale_valid_q_o[0] && '+copy+'_f_state_selected_tile_q_o=='+str(lane)
            lines.append('        if('+guard+')assert('+prefix+'f_full_read_owned_o);')
            lines.append('        if('+guard+')assert('+prefix+'f_full_dot_owned_o);')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_tile0_f_metadata_0_o!=b_tile0_f_metadata_0_o);',
        '        cover(rst_n && f_joined && a_metadata_ready_o && metadata_valid_i);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    refs={str(p.relative_to(HERE)):{'INPUTS':digest((p/'INPUTS.json').read_bytes()),'FINISHED':digest((p/'FINISHED.json').read_bytes())}for p in(parent,child,caller)}
    files={'cluster.sv':cluster.encode(),'tile.sv':tile.encode(),'wrapper.sv':wrapper.encode(),
        'production-cluster.sv':(parent/'production-cluster.sv').read_bytes(),
        'production-tile.sv':(parent/'production-tile.sv').read_bytes(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='assembled_cluster_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert(')+2*cluster.count('assert(')+8*tile.count('assert('),
        covers=2,observer_constants=1,binding=dict(native_join=pi['binding']['native_join'],
            variant=pi['binding']['variant'],serial=serial,initial_hard_reset=False,
            component_model_receipts=refs,actual_child_connections=pi['binding']['actual_tile_inputs'],
            source_observers_only=True,tile_reply_cuts=False,native_four_tile_geometry=True),
        scope='Connected native numerical cluster, all four full-size tiles, independent old metadata and serialized accumulators, after logical CLEAR without hard reset. Actual registered tile replies are concrete. Only recorded MAC recurrence and audited stateless multiplier congruence remain explicit primitive contracts. No complete projection service, token-publication or whole-device theorem.',
        cuts=[c for c in cuts if c['module']!='board1_projection_tile16']+ti['internal_cuts'],
        depth=3,induction_depth=3,cover_depth=8,timeout=args.timeout,
        source_list=['cluster.sv','tile.sv','wrapper.sv'],expected_memories=24 if serial else 16,
        map_literal_roms=True,optimize_full=True,primary_only=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']})


if __name__=='__main__':raise SystemExit(main())

"""Join actual semantic, elementwise and normalizer job controllers.

Keep numerical-product, shifter and registered record-RAM outputs unrestricted.
Keep all other complete semantic children unrestricted. No numerical, protocol
or data-equality assumption constrains those boundaries. Prove the real LUT
request cannot outlive its SiLU stage while the semantic parent remains healthy.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load


def instance(raw,name):
    m=re.search(r'^    board1_\w+\s+(?:#\([^\n]*\)\s+)?'+name+r'\s*\(',raw,re.M)
    if m is None:raise ValueError('Actual instance absent: '+name)
    end=m.end();level=1
    while level:level+=(raw[end]=='(')-(raw[end]==')');end+=1
    if raw[end]!=';':raise ValueError('Instance terminator changed')
    return raw[m.start():end+1]


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=20)
    ap.add_argument('--mutant',choices=('unowned-idle-lut-request',))
    args=ap.parse_args()
    builder=load('datapath',HERE.parent/'authentication-access/run_datapath_access.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    files,binding,cuts,access=builder.derive(args.package,args.variant)
    original=files['production-datapath.sv'].decode();source=files['datapath.sv'].decode()
    retained={'u_elementwise_lane','u_normalizer'}
    for row in cuts:
        if row['instance']not in retained:continue
        before='    assign '+row['expression']+' = '+row['replacement']+';'
        if source.count(before)!=1:raise ValueError('Complete child cut changed')
        source=source.replace(before,'',1)
        before='    input wire '+row['shape']+row['replacement']
        # Every such port is an interior member of the appended input list.
        if source.count(before+',\n')!=1:raise ValueError('Child input-list position changed')
        source=source.replace(before+',\n','',1)
    normalizer=HERE/'runs/normalizer-parent-ready-clear-r1'
    elementwise=HERE/'runs/elementwise-relevant-ready-r2'
    for path in (normalizer,elementwise):
        meta=json.loads((path/'INPUTS.json').read_text())
        for filename,row in meta['files'].items():
            if filename in('service.sv','scalar.sv')or filename.startswith('production-'):
                raw=(path/filename).read_bytes()
                import hashlib
                if hashlib.sha256(raw).hexdigest()!=row['sha256']:raise ValueError('Frozen controller projection changed')
    service=(normalizer/'service.sv').read_bytes()
    native_norm=files['production-child-board1_fixed_vector_normalizer.sv']
    if native_norm!=(normalizer/'production-service.sv').read_bytes():raise ValueError('Normalizer source class mismatch')
    service_ports=parser.ports(service.decode())
    native_ports=parser.ports(re.search(r'^module board1_fixed_vector_normalizer\b[\s\S]*?^endmodule',native_norm.decode(),re.M)[0])
    additions=[];connect=[];numerical_seams=[]
    for port,(direction,shape)in service_ports.items():
        if port in native_ports or direction!='input':continue
        name='f_nested_normalizer_'+port
        additions.append('    input wire '+shape+name);connect.append('.'+port+'('+name+')')
        numerical_seams.append(dict(module='board1_fixed_vector_normalizer',port=port,source='normalizer-parent-ready-clear-r1',replacement=name,assumptions=[]))
    protocol_wires=[]
    for field,alias in [('state_q','f_norm_state'),('rows_q','f_norm_rows'),('capture_index_q','f_norm_capture')]:
        port='f_rel_state_'+field+'_o'
        direction,shape=service_ports[port]
        if direction!='output':raise ValueError('Normalizer observation is not an output')
        protocol_wires.append('    wire '+shape+alias+';');connect.append('.'+port+'('+alias+')')
    block=instance(original,'u_normalizer')
    block=block[:-2]+',\n        '+',\n        '.join(connect)+'\n    );'
    core_raw=files['production-child-board1_fixed_elementwise_lane_core.sv']
    core=re.search(r'^module board1_fixed_elementwise_lane_core\b[\s\S]*?^endmodule',core_raw.decode(),re.M)[0]
    core=core.replace('\n);',',\n    input wire [31:0] f_numeric_product_i,\n    output wire [3:0] f_protocol_state_o\n);',1)
    end=core.index('\n    );',core.index('u_fixed_elementwise_product_compact_lane'))
    core=core[:end]+',\n        .f_numeric_product_i(f_numeric_product_i),\n        .f_state_state_q_o(f_protocol_state_o)'+core[end:]
    element_block=instance(original,'u_elementwise_lane')
    element_block=element_block[:-2]+',\n        .f_numeric_product_i(f_nested_elementwise_product_i),\n        .f_protocol_state_o(f_lane_state)\n    );'
    protocol_wires.append('    wire [3:0] f_lane_state;')
    additions.append('    input wire [31:0] f_nested_elementwise_product_i')
    source=source.replace('\n);',',\n'+',\n'.join(additions)+'\n);',1)
    source=source.replace('\nendmodule','\n'+'\n'.join(protocol_wires)+'\n'+block+'\n'+element_block+'\nendmodule',1)
    guarded_access=access.replace('if (rst_n) begin','if (rst_n && f_completed_clear) begin')
    if guarded_access==access:raise ValueError('Access observer guard changed')
    source=source.replace(access,guarded_access)
    monitor=(HERE/'semantic-scratch-monitor.inc.sv').read_text()+'\n'+(HERE/'semantic-metadata-monitor.inc.sv').read_text()
    monitor=monitor.replace('always @*if(rst_n && !clear_i && !fault_q)',
        'always @*if(rst_n && !clear_i && !fault_q && f_completed_clear)')
    monitor+='''
    reg f_completed_clear=0;
    reg f_elem_inflight;
    reg [2:0] f_elem_operation;
    reg f_gate_read_seen;
    always @(posedge clk)if(!rst_n)f_completed_clear<=0;else if(clear_i)f_completed_clear<=1;
    always @(posedge clk)begin
        if(!rst_n || clear_i)f_gate_read_seen<=0;else if(scratch_read_enable)f_gate_read_seen<=1;
        if(!rst_n || clear_i)f_elem_inflight<=0;
        else begin
            if(lane_request_valid && lane_request_ready)begin
                f_elem_inflight<=1;f_elem_operation<=lane_operation;
            end else if(lane_result_fire)f_elem_inflight<=0;
        end
    end
    always @*if(rst_n && f_completed_clear && !fault_q && !clear_i && !child_fault)begin
        if(engine_state_q!=E_IDLE || f_elem_inflight || f_lane_state!=0 || f_norm_state!=0)
            assert(lock_seen_q);
    end
    always @*if(rst_n && f_completed_clear && !clear_i)begin
        if(f_silu_owned)assert(f_gate_read_seen);
        if(f_lane_state==5 || f_lane_state==6 || f_lane_state==7 || f_lane_state==13 || f_lane_state==14)begin
            assert(f_elem_inflight);assert(f_elem_operation==2);
        end
        if(f_elem_inflight && f_elem_operation==2)begin
            assert(current_stage_q==STAGE_SILU_MUL);assert(f_silu_owned);
        end
        if(lane_lut_response_q && f_lane_state==6)assert(f_silu_owned);
        if(lane_lut_request)assert(f_gate_read_seen);
    end
    always @*if(rst_n && f_completed_clear && !fault_q && !clear_i &&
               model_lock_i && !upstream_fault_i && !child_fault)begin
        if(engine_state_q!=E_PROJ && engine_state_q!=E_ROPE && engine_state_q!=E_ELEM)
            assert(f_norm_state==0);
        if(norm_done_seen_q)assert(f_norm_state==0);
        if((engine_state_q==E_PROJ || engine_state_q==E_ROPE || engine_state_q==E_ELEM) && !norm_start_seen_q)begin
            assert(f_norm_state==0);assert(!norm_done_seen_q);
        end
        if(engine_state_q==E_ELEM && !norm_start_seen_q)begin
            assert(f_norm_state==0);assert(!input_done_q);
            assert(elem_phase_q==EL_NORM_START);assert(elem_index_q==0);
            assert(!output_done_q);assert(!norm_done_seen_q);
        end
        if(f_lane_state==5 || f_lane_state==6 || f_lane_state==7 || f_lane_state==13 || f_lane_state==14)begin
            assert(f_elem_inflight);assert(f_elem_operation==2);
        end
        if(f_elem_inflight && f_elem_operation==2)begin
            assert(engine_state_q==E_ELEM);assert(current_stage_q==STAGE_SILU_MUL);
            assert(!input_done_q);assert(norm_start_seen_q);assert(f_norm_state==1);
            assert(elem_phase_q==EL_LANE_WAIT);
        end
        if(engine_state_q==E_ELEM && current_stage_q==STAGE_SILU_MUL && elem_phase_q==EL_LANE_REQ)begin
            assert(silu_value_valid_q);assert(f_silu_owned);
        end
        if(engine_state_q==E_ELEM && (elem_phase_q==EL_LOOK_REQ || elem_phase_q==EL_LOOK_WAIT))begin
            assert(current_stage_q==STAGE_SILU_MUL);assert(f_gate_read_seen);
        end
        if(engine_state_q==E_ELEM && current_stage_q==STAGE_SILU_MUL &&
           (elem_phase_q==EL_LANE_REQ || elem_phase_q==EL_LANE_WAIT || elem_phase_q==EL_NORM_WAIT))
            assert(f_gate_read_seen);
        if(engine_state_q==E_ELEM && norm_start_seen_q)begin
            assert(f_norm_rows==((current_stage_q==STAGE_SILU_MUL)?682:256));
            if(!input_done_q)begin
                assert(f_norm_state==1);assert(f_norm_capture==elem_index_q);
                assert(!output_done_q);assert(!norm_done_seen_q);
            end
            if(input_done_q)begin
                assert(elem_phase_q==EL_NORM_WAIT);
                assert(elem_index_q==((current_stage_q==STAGE_SILU_MUL)?681:255));
            end
        end
        if(lane_lut_request)begin
            assert(engine_state_q==E_ELEM);
            assert(current_stage_q==STAGE_SILU_MUL);
        end
        if(lane_lut_response_q)begin
            assert(current_stage_q==STAGE_SILU_MUL);
            assert(f_silu_owned);
        end
        cover(engine_state_q==E_IDLE && norm_start_ready && lane_request_ready);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    ports=parser.ports(source)
    wrapper='module joined_lut_protocol(\n'+',\n'.join('    '+d+' wire '+sh+n for n,(d,sh)in ports.items())+'\n);\n'
    wrapper+='    '+builder.TOP+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    compact=(elementwise/'scalar.sv').read_bytes()
    if args.mutant:
        before=b'(state_q == ST_SILU_REQ);'
        if compact.count(before)!=1:raise ValueError('Actual LUT request mutation site changed')
        compact=compact.replace(before,b'((state_q == ST_SILU_REQ) || (state_q == ST_IDLE));',1)
    files.update({'datapath.sv':source.encode(),'wrapper.sv':wrapper.encode(),'normalizer-control.sv':service,
        'elementwise-control.sv':compact,'elementwise-core.sv':('`undef FORMAL\n'+core+'\n').encode(),
        'production-elementwise-compact.sv':(elementwise/'production-scalar.sv').read_bytes(),
        'joined-monitor.inc.sv':monitor.encode(),'join-runner.py':Path(__file__).read_bytes(),
        'normalizer-input-receipt.json':(normalizer/'INPUTS.json').read_bytes(),
        'elementwise-input-receipt.json':(elementwise/'INPUTS.json').read_bytes()})
    binding.update(initial_hard_reset=False,retained_actual_children=sorted(retained),
        numerical_control_scope='Actual compact lane and normalizer FSM, acceptance, row counters and output sequencing; whole numerical shifter/product and record-RAM read payloads remain free')
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='joined_lut_protocol',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=access.count('assert(')+monitor.count('assert('),covers=access.count('cover(')+monitor.count('cover('),
        observer_constants=2,binding=binding,cuts=[r for r in cuts if r['instance']not in retained]+numerical_seams+
            [dict(module='board1_fixed_elementwise_product_dsp',replacement='f_nested_elementwise_product_i',assumptions=[])],
        depth=3,induction_depth=2,cover_depth=12,timeout=args.timeout,mutant=args.mutant,
        source_list=['datapath.sv','normalizer-control.sv','elementwise-control.sv','elementwise-core.sv','wrapper.sv'],
        expected_memories=0,optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Actual semantic/compact-elementwise/normalizer control join. After CLEAR, LUT request/response ownership while healthy. Numerical results, record-RAM reads and other whole children unrestricted. No numerical or whole-device session theorem.')


if __name__=='__main__':raise SystemExit(main())

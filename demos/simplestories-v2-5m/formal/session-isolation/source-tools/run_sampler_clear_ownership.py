"""Native seeded sampler RAM/registered-read ownership after resetless CLEAR.

All 4,019 logits/mass rows, immutable exponential asset, arithmetic and actual
greedy child remain. No sampling-distribution or PRNG-quality theorem is made.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import extend_instance


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=30)
    args=ap.parse_args();binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(HERE.parents[1]/'fpga-demo/public-release','seeded-sampling')
    modules={};files={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw.decode(),re.M):modules[m[1]]=(m[0],name,raw)
    selected=[]
    def visit(name):
        if name in selected:return
        selected.append(name);text=modules[name][0]
        for other in modules:
            if other!=name and re.search(r'\b'+re.escape(other)+r'\s+(?:#\([\s\S]*?\)\s+)?u_\w+\s*\(',text):visit(other)
    visit('board1_seeded_head_selector')
    bodies={}
    for name in selected:
        text,path,raw=modules[name];files['production-'+name+'.sv']=raw;bodies[name]=text
    public=HERE.parents[1]/'fpga-demo/public-release/demos/simplestories-v2-5m/formal/current-seeded-sampling'
    child_monitor=(public/'argmax-row-ownership-monitor.inc.sv').read_text()
    parent_monitor=(public/'sampler-buffer-monitor.inc.sv').read_text()
    completed='''
    reg f_completed_clear=0;
    always @(posedge clk)if(!reset_n)f_completed_clear<=0;else if(clear_i)f_completed_clear<=1;
'''
    child_monitor=child_monitor.replace('if (reset_n)','if (reset_n && f_completed_clear)')+completed
    child_monitor=child_monitor.replace(completed,'\n    wire f_completed_clear=f_parent_clear_seen_i;\n')
    # A pre-existing sticky terminal fault can outrank CLEAR and retain an
    # unused old row counter. Bound that native field only while live.
    bound='        assert(expected_row_q <= 4018);\n'
    if child_monitor.count(bound)!=1:raise ValueError('Argmax bound observer changed')
    child_monitor=child_monitor.replace(bound,'',1).replace(
        'if (!fail_closed_o && model_locked_i && !clear_i) begin',
        'if (!fail_closed_o && model_locked_i && !clear_i) begin\n'+bound,1)
    parent_monitor=parent_monitor.replace('if (reset_n)','if (reset_n && f_completed_clear)')+completed
    child=bodies['board1_fixed_head_argmax']
    child=child.replace('\n);',',\n    output wire [12:0] f_observed_rows_o,\n    input wire f_parent_clear_seen_i\n);',1)
    child=child.replace('\nendmodule','\n'+child_monitor+'\nendmodule',1)
    parent=bodies['board1_seeded_head_selector']
    parent=extend_instance(parent,'u_original_argmax',{'f_observed_rows_o':'f_child_rows',
        'f_parent_clear_seen_i':'f_completed_clear'})
    declarations='''
    wire [12:0] f_child_rows;
    wire f_fatal=fail_q || greedy_fault || upstream_fail_closed_i || (state_q!=IDLE && !model_locked_i);
    wire f_offer=!f_fatal && !clear_i && state_q==IDLE && settings_valid_i && settings_ready_o;
    wire f_accept=f_offer && settings_empty_boundary_i && settings_temperature_i<=3;
'''
    reads='''
    reg f_logit_read_live,f_mass_read_live,f_logit_read_target,f_mass_read_target;
    reg [11:0] f_logit_read_tag,f_mass_read_tag;
    reg signed [51:0] f_logit_read_shadow;
    reg [30:0] f_mass_read_shadow;
    always @(posedge clk)begin
        if(!reset_n || clear_i || f_fatal || start_fire || f_accept)begin
            f_logit_read_live<=0;f_mass_read_live<=0;f_logit_read_target<=0;f_mass_read_target<=0;
        end else begin
            if(state_q==ROW_READ)begin
                f_logit_read_live<=1;f_logit_read_tag<=cursor_q;
                f_logit_read_target<=cursor_q==f_buffer_slot && f_logit_owned;
                f_logit_read_shadow<=f_logit_value;
            end
            if(state_q==CDF_READ)begin
                f_mass_read_live<=1;f_mass_read_tag<=cursor_q;
                f_mass_read_target<=cursor_q==f_buffer_slot && f_mass_owned;
                f_mass_read_shadow<=f_mass_value;
            end
        end
    end
    always @*if(reset_n && f_completed_clear)begin
        if(f_buffer_slot<4019 && f_logit_read_target)assert(row_read_q==f_logit_read_shadow);
        if(f_buffer_slot<4019 && f_mass_read_target)assert(weight_read_q==f_mass_read_shadow);
    end
    always @*if(reset_n && f_completed_clear && f_buffer_healthy)begin
        if(state_q>=ROW_READ && state_q<=WINNER)assert(cursor_q<=4018);
        if(state_q==GAP)begin
            assert(f_logit_read_live);assert(f_logit_read_tag==cursor_q);
            if(cursor_q==f_buffer_slot)assert(f_logit_read_target);
        end
        if(state_q==CDF_CHECK)begin
            assert(f_mass_read_live);assert(f_mass_read_tag==cursor_q);
            if(cursor_q==f_buffer_slot)assert(f_mass_read_target);
        end
    end
    always @(posedge clk)begin
        cover(reset_n && f_completed_clear && row_fire && row_index_i==1 && !greedy_mode);
        cover(reset_n && f_completed_clear && f_buffer_slot==0 && !f_logit_owned && logits[0]!=0);
    end
'''
    parent=parent.replace('\nendmodule','\n'+declarations+'\n'+parent_monitor+'\n'+reads+'\nendmodule',1)
    bodies.update(board1_seeded_head_selector=parent,board1_fixed_head_argmax=child)
    for name,text in bodies.items():files[name+'.sv']=('`undef FORMAL\n'+text+'\n').encode()
    roms=[n for n in binding['distributed_inputs']if n.endswith('/exp_neg_q30.memh')]
    if len(roms)!=1:raise ValueError('Native sampler exponential asset not unique')
    relative=roms[0][len('project/'):]
    files[relative]=(native/roms[0]).read_bytes()
    ports=parser.ports(parent)
    wrapper='module native_sampler_clear(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    board1_seeded_head_selector u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files.update({'wrapper.sv':wrapper.encode(),'parent-monitor.inc.sv':(declarations+parent_monitor+reads).encode(),
        'child-monitor.inc.sv':child_monitor.encode(),'runner.py':Path(__file__).read_bytes()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_sampler_clear',
        reset_constraints='initial\nassume (= [reset_n] true)\nstate 1\nassume (= [reset_n] true)\n',
        assertions=parent_monitor.count('assert(')+child_monitor.count('assert(')+reads.count('assert('),
        covers=2,observer_constants=1,binding=dict(native_join=binding,variant='seeded-sampling',
            initial_hard_reset=False,concrete_module='board1_seeded_head_selector',
            all_native_children_retained=True,native_logit_rows=4019,native_mass_rows=4019,native_rom_words=4097,
            concrete_hierarchy_modules=selected,
            common_nondriving_clear_epoch=True,
            current_authorized_settings_and_prng_not_a_numerical_distribution_theorem=True),
        cuts=[],depth=3,induction_depth=4,cover_depth=8,timeout=args.timeout,
        source_list=[n+'.sv'for n in selected]+['wrapper.sv'],expected_memories=3,
        primary_only=True,optimize_full=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual full native seeded selector and greedy child after logical CLEAR without hard reset. All 4019-row logits/mass arrays and immutable 4097-word exponential asset retained; current row writes, mass-pass ownership and registered-read capture before consumption checked. Authorized retained settings/PRNG numerical correspondence and whole-device composition remain separate.')


if __name__=='__main__':raise SystemExit(main())

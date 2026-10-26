"""Actual dual-clock transport plus both real FIFOs, with no internal cuts.

Prove checked admission and physical field/range restrictions together with
the per-entry FIFO ownership/payload properties. This does not prove the boot
authenticator, vendor DDR implementation or full machine execution epochs.
"""
import argparse
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
MUTATIONS={
    'invert-physical-operation':('wire physical_write = request_m_data[275];',
        'wire physical_write = !request_m_data[275];'),
    'flip-physical-address-bit':("assign app_addr_o = {7'd0,request_m_data[274:256],3'b000};",
        "assign app_addr_o = {7'd0,request_m_data[274:256],3'b000} ^ 29'd8;"),
    'flip-physical-write-data-bit':('assign app_wr_data_o = request_m_data[255:0];',
        "assign app_wr_data_o = request_m_data[255:0] ^ 256'd1;"),
}


def load(name):
    spec=importlib.util.spec_from_file_location('_transport_'+name,HERE/(name+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


def verify_fifo_lemma_inputs(lemma,variant,original_fifo,original_transport,monitor,common):
    names={
        'baseline':('fifo-commands-r5','fifo-returns-r1'),
        'seeded-sampling':('fifo-commands-r5','fifo-returns-r1'),
        'kv-protected':('fifo-kv-protected-commands-r1','fifo-kv-protected-returns-r1'),
        'encrypted-memory':('fifo-encrypted-memory-commands-r2','fifo-encrypted-memory-returns-r2'),
    }
    rows={r['run']:r for r in lemma['runs']if not r['mutant']};origins=[]
    for name in names[variant]:
        if name not in rows:raise ValueError('Required independently proved FIFO premise is missing')
        record=rows[name];run=HERE/'runs'/name
        raw=(run/'INPUTS.json').read_bytes();finished=(run/'FINISHED.json').read_bytes()
        if (not record['primary_unbounded_safety']or common.sha(raw)!=record['inputs_sha256']or
                common.sha(finished)!=record['finished_sha256']):
            raise ValueError('FIFO premise proof identity changed')
        inp=json.loads(raw)
        if inp['assumption_cells']!=0 or inp['internal_cuts']:
            raise ValueError('FIFO premise has an undischarged assumption/cut')
        if (run/'monitor.inc.sv').read_text()!=monitor:
            raise ValueError('Assumed FIFO invariant body differs from its proved body')
        if ((run/'production-fifo.sv').read_bytes()!=original_fifo or
                (run/'production-transport.sv').read_bytes()!=original_transport):
            raise ValueError('FIFO premise native module or reset/parameter context changed')
        origins.append(dict(run=name,inputs_sha256=record['inputs_sha256'],
            finished_sha256=record['finished_sha256'],invariant_template_sha256=common.sha(monitor.encode())))
    return origins


def render_policy_monitor(limit):
    return f'''
    generate if (WIDTH == 276 && ADDR_BITS == 5) begin: f_command_region
        always_comb begin
            if (source_push) assert(s_data_i[274:256] < 19'd{limit});
            if (f_slot_written_q) assert(f_last_payload_q[274:256] < 19'd{limit});
            if (m_valid_o) assert(m_data_o[274:256] < 19'd{limit});
        end
        for (genvar row=0;row<DEPTH;row=row+1) begin: f_owned_word
            wire [ADDR_BITS-1:0] offset = ADDR_BITS'(row) - f_rseq_q[ADDR_BITS-1:0];
            always_comb if ({{1'b0,offset}} < f_used)
                assert(memory_q[row][274:256] < 19'd{limit});
        end
    end endgenerate
'''


def render_parent_monitor(limit,field_identity=False):
    result=f'''
    always_comb begin
        assert(core_release_q == 0 || core_release_q == 1 || core_release_q == 3 || core_release_q == 7);
        assert(app_release_q == 0 || app_release_q == 1 || app_release_q == 3 || app_release_q == 7);
        if (enqueue) assert(core_cmd_i == 0 || core_cmd_i == 1);
        if (enqueue) assert(core_addr_i[28:22] == 0 && core_addr_i[2:0] == 0 && core_addr_i[21:3] < 19'd{limit});
        if (enqueue && core_cmd_i == 0) assert(core_wr_en_i && core_wr_end_i && core_wr_mask_i == 0);
        if (enqueue && core_cmd_i == 1) assert(!core_wr_en_i && !core_wr_end_i);
        if (core_stop_i) assert(!enqueue);
        if (core_fault_o) assert(!core_cmd_ready_o);
        if (app_cmd_en_o) assert(app_reset_n && app_good_q && controller_good && !app_fault_q && app_cmd_ready_i);
        if (app_wr_en_o) assert(app_cmd_en_o && app_wr_ready_i && app_wr_end_o && app_cmd_o == 0);
        assert(app_wr_mask_o == 0 && !app_burst_o && !app_self_refresh_o && !app_refresh_o);
        if (app_cmd_en_o) assert(app_cmd_o == 0 || app_cmd_o == 1);
        if (app_cmd_en_o) assert(app_addr_o[28:22] == 0 && app_addr_o[2:0] == 0 && app_addr_o[21:3] < 19'd{limit});
        if (core_rd_valid_o) assert(core_reset_n && response_m_valid);
        if (core_rd_valid_o) assert(core_rd_data_o == response_m_data[255:0]);
        if (core_rd_valid_o) assert(core_rd_end_o == response_m_data[256]);
        cover(app_cmd_en_o && app_cmd_o == 0 && app_wr_en_o);
        cover(app_cmd_en_o && app_cmd_o == 1);
        cover(core_rd_valid_o && core_rd_end_o);
    end
'''
    if field_identity:
        fields='''
        assert(core_write == (core_cmd_i == 0));
        assert(core_read == (core_cmd_i == 1));
        if (app_cmd_en_o) assert((app_cmd_o == 0) == request_m_data[275]);
        if (app_cmd_en_o) assert(app_addr_o == {7'd0,request_m_data[274:256],3'b000});
        if (app_wr_en_o) assert(app_wr_data_o == request_m_data[255:0]);
'''
        result=result.replace('        cover(app_cmd_en_o && app_cmd_o == 0 && app_wr_en_o);',
            fields+'        cover(app_cmd_en_o && app_cmd_o == 0 && app_wr_en_o);')
    return result


def render_mutant_stimulus(mutant,steps=28):
    write=mutant=='flip-physical-write-data-bit'
    text="initial\nassume (= [u_commands.f_slot] (_ bv0 5))\nassume (= [u_returns.f_slot] (_ bv0 6))\n"
    for step in range(steps):
        text+=f'state {step}\n'
        values=dict(core_clk_i=bool(step%2),app_clk_i=bool(step%2),
            core_reset_n_i=step>=2,app_reset_n_i=step>=2,core_stop_i=False,
            controller_pll_lock_i=step>=2,controller_calibrated_i=step>=2,
            app_cmd_ready_i=True,app_wr_ready_i=True,core_burst_i=False,
            core_self_refresh_i=False,core_refresh_i=False,app_rd_valid_i=False,app_rd_end_i=False)
        for name,value in values.items():text+=f'assume (= [{name}] {str(value).lower()})\n'
        text+=f'assume (= [core_cmd_i] (_ bv{0 if write else 1} 3))\n'
        text+='assume (= [core_addr_i] (_ bv0 29))\nassume (= [core_wr_data_i] (_ bv0 256))\n'
        text+='assume (= [core_wr_mask_i] (_ bv0 32))\nassume (= [app_rd_data_i] (_ bv0 256))\n'
        text+='assume (= [core_cmd_en_i] [core_cmd_ready_o])\n'
        for name in ('core_wr_en_i','core_wr_end_i'):
            text+=f'assume (= [{name}] {"[core_cmd_ready_o]"if write else"false"})\n'
    return text


def main():
    common,fifo,engine=load('run_handoff'),load('run_fifo'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),default='baseline')
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=120)
    parser.add_argument('--secondary-base-only',action='store_true')
    parser.add_argument('--use-proven-fifo-lemmas',action='store_true')
    parser.add_argument('--mutant',choices=tuple(MUTATIONS))
    parser.add_argument('--directed-mutant',action='store_true')
    args=parser.parse_args()
    if args.directed_mutant and not args.mutant:parser.error('--directed-mutant is only a counterexample stimulus, never a positive proof restriction')
    pin,root,bound=common.binding(args.package,args.variant)
    original_fifo=(root/'project/fifo.sv').read_bytes()
    original_transport=(root/'project/thin_transport.sv').read_bytes()
    _,_,module,_=fifo.channel_binding(original_transport,'commands')
    if fifo.channel_binding(original_transport,'returns')[2]!=module:
        raise ValueError('Unreviewed mixed FIFO module composition')
    base_monitor=(HERE/'fifo-monitor.inc.sv').read_text()
    # Component full-capacity goals are already checked separately. The real
    # transport caps outstanding reads below return-FIFO capacity; asserting
    # that it can fill that FIFO would ask for unreachable system behavior.
    monitor='\n'.join(line for line in base_monitor.splitlines()if not line.strip().startswith('cover('))+'\n'
    lemma_raw=None
    lemma_origins=[]
    if args.use_proven_fifo_lemmas:
        lemma_path=HERE/'audit-probes/fifo-source-audit-r7-all-variants/FINISHED.json'
        lemma_raw=lemma_path.read_bytes();lemma=json.loads(lemma_raw)
        if not lemma['passed']or lemma['current_native_source_and_image_joins'].get(args.variant)!=bound:
            raise ValueError('Proved FIFO lemma source/image scope does not match this transport')
        lemma_origins=verify_fifo_lemma_inputs(lemma,args.variant,original_fifo,original_transport,base_monitor,common)
        # Only the 26 previously proved FIFO invariants change proof role.
        # Production logic, the new range properties and parent properties
        # are unchanged. No new external input assumption is introduced.
        if monitor.count('assert(')!=12:
            # The ordered-pair loop contributes 15 cells from one statement;
            # the eleven remaining statements give 26 after elaboration.
            raise ValueError('Proved FIFO invariant source inventory changed')
        monitor=monitor.replace('assert(','assume(')
    limit=pin['kv_limit']
    policy=render_policy_monitor(limit)
    source=original_fifo.decode();start=source.index('module '+module+' #(')
    end=source.index('\nendmodule',start)
    source='`undef FORMAL\n'+source[:end]+'\n'+monitor+policy+source[end:]
    parent_monitor=render_parent_monitor(limit,field_identity=True)
    parent=original_transport.decode()
    if args.mutant:
        old,new=MUTATIONS[args.mutant]
        if parent.count(old)!=1:raise ValueError('Transport mutation site changed')
        parent=parent.replace(old,new)
    if parent.count('\nendmodule')!=1:raise ValueError('Transport boundary changed')
    parent='`undef FORMAL\n'+parent.replace('\nendmodule','\n'+parent_monitor+'\nendmodule')
    files={'fifo.sv':source.encode(),'transport.sv':parent.encode(),
        'production-fifo.sv':original_fifo,'production-transport.sv':original_transport,
        'fifo-monitor.inc.sv':monitor.encode(),'policy-monitor.inc.sv':policy.encode(),
        'parent-monitor.inc.sv':parent_monitor.encode(),'runner.py':Path(__file__).read_bytes(),
        'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),'SOURCES.json':(HERE/'SOURCES.json').read_bytes()}
    # Two 26-assertion FIFO monitors, 35 command word/range assertions,
    # twenty-one parent assertions, including reset supports and exact fields.
    count=(0 if args.use_proven_fifo_lemmas else 26*2)+35+21
    registers=module.endswith('_block')
    bound=dict(bound,actual_fifo_module=module,command_geometry={'width':276,'depth':32},
        response_geometry={'width':257,'depth':64},physical_word_limit=limit,
        field_identity_assertions=5,
        production_transport_sha256=common.sha(original_transport),production_fifo_sha256=common.sha(original_fifo))
    if lemma_raw is not None:
        files['discharged-fifo-lemma-audit.json']=lemma_raw
        bound['fifo_lemma_audit_sha256']=common.sha(lemma_raw)
        bound['internal_lemma_assumption_cells']=52
        bound['discharged_fifo_lemma_origins']=lemma_origins
    reset=('initial\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n'
        'state 1\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n')
    if args.directed_mutant:
        reset+=render_mutant_stimulus(args.mutant)
        bound['directed_negative_probe']=True
    scope=('Actual transport and both actual FIFOs with arbitrary independent clocks, external '
        'requests, controller status and read returns. No internal cuts. Checked source admission, '
        'per-entry sequence/payload preservation, fixed physical field encoding and word-range bound. '
        'No boot/runtime lock authenticity, cryptographic, physical CDC/skew, vendor-DDR or whole-machine theorem.')
    if args.use_proven_fifo_lemmas:
        scope+=' Compositional mode: 52 internal FIFO invariant assumptions are discharged by the exact native, parameter-specific source-bound FIFO proofs; all 56 new parent/range/field assertions remain obligations. No external protocol assumption or internal RTL cut is added.'
    if args.directed_mutant:
        scope+=' Negative probe only: fixed legal ready-qualified source traffic and explicit clock/reset/controller stimulus constrain this counterexample search. This supplies a failure witness, not an unrestricted safety theorem.'
    raise SystemExit(engine.check(args.run,files,top='board1_thin_ddr_app_transport',
        reset_constraints=reset,assertions=count,covers=3,binding=bound,scope=scope,cuts=[],
        depth=28 if args.mutant else 12,induction_depth=4,cover_depth=36,timeout=args.timeout,mutant=args.mutant,
        observer_constants=2,expected_memories=0 if registers else 2,
        expected_register_memories={
            'u_commands.memory_q':{'width':276,'size':32},
            'u_returns.memory_q':{'width':257,'size':64}}if registers else None,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},multiclock=True,
        secondary_base_only=args.secondary_base_only,
        expected_assumptions=52 if args.use_proven_fifo_lemmas else 0,
        constraint_scope_description='Directed negative probe: initial reset plus 28 states of explicit input stimulus; no induction requested.'if args.directed_mutant else None))


if __name__=='__main__':main()

"""Actual full-size transport: close model-write exclusion through queues.

Uses two independently proved source guarantees and 52 independently proved
FIFO invariant cells. Every production transport/FIFO gate, data path, reset
and native parameter remains. No new external protocol promise is accepted.
The complete source/clock/reset discharge still needs a composition audit.
"""
import argparse
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
TOP='board1_thin_ddr_app_transport'
VIEW='board1_transport_fifo_epoch_view'
MUTATION=("assign app_addr_o = {7'd0,request_m_data[274:256],3'b000};",
    "assign app_addr_o = physical_write ? 29'd0 : {7'd0,request_m_data[274:256],3'b000};")


def load(name):
    spec=importlib.util.spec_from_file_location('_transport_epoch_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def source_guarantees(package,variant,common):
    path=HERE/'audit-probes/boot-memory-path-source-audit-r2-complete-contracts/FINISHED.json'
    raw=path.read_bytes();ledger=json.loads(raw)
    if not ledger['passed']or not ledger['complete_source_contracts']:raise ValueError('Complete source-contract audit missing')
    lookup='baseline'if variant=='seeded-sampling'else variant
    row=next(r for r in ledger['runs']if r['kind']=='memory'and r['variant']==lookup and not r['mutant'])
    run=HERE/'runs'/row['run'];inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes()
    if (not row['both_solver_unbounded_safety']or not row['unconditional_lock_requires_source_reset_read_and_response']or
        common.sha(inp_raw)!=row['inputs_sha256']or common.sha(fin_raw)!=row['finished_sha256']):
        raise ValueError('Source guarantee proof identity changed')
    inp=json.loads(inp_raw);_,root,bound=common.binding(package,variant)
    if variant=='seeded-sampling':
        if ledger['seeded_identical_source_join']!=bound:raise ValueError('Seeded source join changed')
    elif any(inp['binding'].get(k)!=v for k,v in bound.items()):raise ValueError('Source guarantees belong to another native image')
    for local,record in inp['binding']['production_sources'].items():
        if common.sha((root/record['path']).read_bytes())!=record['sha256']or(run/('production-'+local)).read_bytes()!=(root/record['path']).read_bytes():
            raise ValueError('Source guarantee production logic changed')
    reset_path=HERE/'audit-probes/reset-correspondence-source-audit-r1/FINISHED.json';reset_raw=reset_path.read_bytes();reset=json.loads(reset_raw)
    if not reset['passed']or reset['native_joins'][variant]!=bound:raise ValueError('Actual native reset correspondence changed')
    return raw,reset_raw,dict(run=row['run'],inputs_sha256=row['inputs_sha256'],finished_sha256=row['finished_sha256'],
        source_audit_sha256=common.sha(raw),reset_audit_sha256=common.sha(reset_raw))


def cover_stimulus(steps=144,*,negative=False):
    text='initial\nassume (= [u_commands.f_slot] (_ bv0 5))\nassume (= [u_returns.f_slot] (_ bv0 6))\n'
    for step in range(steps):
        text+=f'state {step}\n'
        values=dict(core_clk_i=bool((step//(1 if negative else 4))%2),app_clk_i=bool(step%2),
            core_reset_n_i=step>=2,app_reset_n_i=step>=2,core_stop_i=False,
            controller_pll_lock_i=step>=2,controller_calibrated_i=step>=2,
            app_cmd_ready_i=True,app_wr_ready_i=True,core_burst_i=False,core_self_refresh_i=False,core_refresh_i=False,
            app_rd_end_i=True)
        for name,value in values.items():text+='assume (= ['+name+'] '+str(value).lower()+')\n'
        phase='[f_source_return_seen_q]'
        cmd='(ite '+phase+' (_ bv0 3) (_ bv'+str(0 if step<(16 if negative else 48)else 1)+' 3))'
        text+='assume (= [core_cmd_i] '+cmd+')\n'
        text+='assume (= [core_addr_i] (ite '+phase+' (_ bv1816576 29) (_ bv0 29)))\n'
        text+='assume (= [core_cmd_en_i] [core_cmd_ready_o])\n'
        text+='assume (= [core_wr_en_i] (and [core_cmd_ready_o] (= [core_cmd_i] (_ bv0 3))))\n'
        text+='assume (= [core_wr_end_i] [core_wr_en_i])\n'
        text+='assume (= [app_rd_valid_i] (distinct [physical_reads_q] (_ bv0 6)))\n'
        text+='assume (= [f_formal_runtime_locked_i] '+phase+')\n'
        for name,width in [('core_wr_data_i',256),('core_wr_mask_i',32),('app_rd_data_i',256)]:
            text+='assume (= ['+name+'] (_ bv0 '+str(width)+'))\n'
    return text


def instrument(original_fifo,original_transport,lemmas,fifo_epoch,parent_monitor,parent_epoch,*,mutant=False):
    fifo,transport=load('run_fifo'),load('run_transport');once=load('audit_transport').once
    _,_,module,_=fifo.channel_binding(original_transport,'commands')
    if fifo.channel_binding(original_transport,'returns')[2]!=module:raise ValueError('Mixed unreviewed transport FIFO modules')
    source=original_fifo.decode();start=source.index('module '+module+' #(');end=source.index('\nendmodule',start)+len('\nendmodule')
    view=source[start:end];view=once(view,'module '+module+' #(','module '+VIEW+' #(')
    view=once(view,'\n);',',\n    input wire f_source_read_seen_i,f_physical_read_seen_i\n);')
    view=once(view,'\nendmodule','\n'+lemmas+fifo_epoch+'\nendmodule')
    parent=original_transport.decode()
    if mutant:parent=once(parent,*MUTATION)
    # Only module identities change; exact native instance parameters/ports
    # remain. The original generic FIFO can separately retain other contexts.
    parent=parent.replace(module+' #(',VIEW+' #(')
    if parent.count(VIEW+' #(')!=2:raise ValueError('Unexpected number of actual transport FIFO instances')
    parent=once(parent,'\n);',',\n    input wire f_formal_runtime_locked_i\n);')
    parent=once(parent,'.m_empty_o(), .m_protocol_fault_o(request_m_fault));',
        '.m_empty_o(), .m_protocol_fault_o(request_m_fault),\n        .f_source_read_seen_i(f_source_read_seen_q),.f_physical_read_seen_i(f_physical_read_seen_q));')
    parent=once(parent,'.m_empty_o(), .m_protocol_fault_o(response_m_fault));',
        '.m_empty_o(), .m_protocol_fault_o(response_m_fault),\n        .f_source_read_seen_i(f_source_read_seen_q),.f_physical_read_seen_i(f_physical_read_seen_q));')
    parent=once(parent,'\nendmodule','\n'+parent_monitor+parent_epoch+'\nendmodule')
    return {'fifo-view.sv':b'`undef FORMAL\n'+view.encode(),'transport.sv':b'`undef FORMAL\n'+parent.encode()},module


def main():
    common,transport,engine=load('run_handoff'),load('run_transport'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),default='baseline')
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=120)
    parser.add_argument('--induction-depth',type=int,default=8)
    parser.add_argument('--mutant',choices=('redirect-physical-writes-to-model',))
    parser.add_argument('--compact-cover',action='store_true',help='Use a shorter 1:1 clock stimulus for component reachability only')
    args=parser.parse_args();pin,root,bound=common.binding(args.package,args.variant)
    original_fifo=(root/'project/fifo.sv').read_bytes();original_transport=(root/'project/thin_transport.sv').read_bytes()
    source_audit,reset_audit,source_origin=source_guarantees(args.package,args.variant,common)
    raw=(HERE/'audit-probes/transport-source-audit-r3-checked/fifo-premise-recheck/FINISHED.json').read_bytes();ledger=json.loads(raw)
    if not ledger['passed']or ledger['current_native_source_and_image_joins'][args.variant]!=bound:raise ValueError('FIFO premise native/image scope changed')
    base=(HERE/'fifo-monitor.inc.sv').read_text()
    origins=transport.verify_fifo_lemma_inputs(ledger,args.variant,original_fifo,original_transport,base,common)
    lemmas='\n'.join(s for s in base.splitlines()if not s.strip().startswith('cover('))+'\n';lemmas=lemmas.replace('assert(','assume(')
    policy=transport.render_policy_monitor(pin['kv_limit'])
    fifo_epoch=(HERE/'transport-epoch-fifo-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    parent_monitor=transport.render_parent_monitor(pin['kv_limit'],field_identity=True)
    parent_epoch=(HERE/'transport-epoch-parent-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    files,module=instrument(original_fifo,original_transport,lemmas+policy,fifo_epoch,parent_monitor,parent_epoch,mutant=bool(args.mutant))
    files.update({'production-fifo.sv':original_fifo,'production-transport.sv':original_transport,
        'fifo-lemmas.inc.sv':lemmas.encode(),'fifo-policy.inc.sv':policy.encode(),'fifo-epoch.inc.sv':fifo_epoch.encode(),
        'parent-monitor.inc.sv':parent_monitor.encode(),'parent-epoch.inc.sv':parent_epoch.encode(),
        'discharged-fifo-lemma-audit.json':raw,'discharged-source-audit.json':source_audit,
        'discharged-reset-audit.json':reset_audit,'runner.py':Path(__file__).read_bytes(),
        'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),'SOURCES.json':(HERE/'SOURCES.json').read_bytes()})
    binding=dict(bound,variant=args.variant,actual_fifo_module=module,formal_fifo_view_module=VIEW,
        production_fifo_sha256=common.sha(original_fifo),production_transport_sha256=common.sha(original_transport),
        fifo_lemma_origins=origins,source_guarantee_origin=source_origin,
        source_guarantee_assumption_cells=2,independently_proved_internal_fifo_assumption_cells=52,
        command_geometry={'width':276,'depth':32},return_geometry={'width':257,'depth':64},
        external_unproved_protocol_assumptions=[],new_epoch_property_cells=49,
        directed_negative_probe=bool(args.mutant),compact_cover=args.compact_cover)
    scope=('Actual native full-size transport and both FIFO bodies under arbitrary independent clocks. '
        '52 FIFO invariant cells are independently proved for the exact native parameters/reset context. '
        'Two source-contract cells are independently proved on the actual complete memory path with '
        'four unrestricted authenticator scalar outputs; native clock/reset correspondence is separately '
        'proved. No new client protocol promise, fairness, internal RTL cut or geometry reduction. '
        'Targets no model-region physical command writes after observed runtime LOCK until common hard '
        'reset, including old queued work. Whole composition credit still requires source/contract '
        'substitution audit. No vendor DDR/persistence, physical CDC, SHA, image attestation or numerical '
        'whole-machine theorem. Directed component COVER is not full fixed-model boot reachability.')
    reset='initial\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\nstate 1\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n'
    if args.mutant:reset+=cover_stimulus(80,negative=True)
    registers=module.endswith('_block')
    raise SystemExit(engine.check(args.run,files,top=TOP,reset_constraints=reset,
        assertions=105,covers=4,binding=binding,scope=scope,cuts=[],depth=80 if args.mutant else 12,induction_depth=args.induction_depth,
        cover_depth=80 if args.compact_cover else 144,
        cover_constraints=cover_stimulus(80,negative=True)if args.compact_cover else cover_stimulus(),timeout=args.timeout,
        mutant=args.mutant,
        observer_constants=2,expected_assumptions=54,expected_memories=0 if registers else 2,
        expected_register_memories={
            'u_commands.memory_q':{'width':276,'size':32},
            'u_returns.memory_q':{'width':257,'size':64}}if registers else None,
        source_list=['fifo-view.sv','transport.sv'],solver_cli={s:['--unroll']for s in ('z3','cvc5')},multiclock=True))


if __name__=='__main__':main()

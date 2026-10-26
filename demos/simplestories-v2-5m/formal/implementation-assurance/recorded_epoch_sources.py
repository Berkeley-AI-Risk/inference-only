"""Recover new boot/reset/transport instrumentation without compiler tools.

This checks recorded bytes and reversible source construction. It does not
reproduce compilation, execute a solver or establish a fresh theorem.
"""
import importlib.util
import json
from pathlib import Path


def load(work,name):
    spec=importlib.util.spec_from_file_location('_recorded_epoch_'+name,work/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def need(condition,message):
    if not condition:raise ValueError(message)


def recover(work,package,index,closure):
    common,boundary,wrapper,memory,observer,epoch,transport,reset,query=map(lambda n:load(work,n),
        ('run_handoff','run_boot_boundary','run_boot_wrapper','run_memory_path','audit_boot_boundary',
         'run_transport_epoch','run_transport','run_reset_correspondence','audit_fifo'))
    sha=query.sha
    bindings={v:common.binding(package,v)for v in ('baseline','kv-protected','encrypted-memory','seeded-sampling')}
    fresh={k:json.loads((work/('audit-probes/transport-epoch-source-audit-r6-complete/'+k+'-premise-recheck/FINISHED.json')).read_bytes())for k in ('fifo','source','reset','top')}
    joins=[]
    for item in index['runs']:
        kind=item['kind']
        if kind not in ('boot-boundary','boot-path','reset-correspondence','transport-epoch'):continue
        run=work/'runs'/item['run'];inp=json.loads((run/'INPUTS.json').read_bytes());mutant=item['mutant']
        if kind=='reset-correspondence':
            reference=None
            for variant,(_,root,bound)in bindings.items():
                need(inp['binding']['native_joins'][variant]==bound,'Native reset/image join changed')
                native={n:(root/p).read_bytes()for n,p in {'top.sv':'project/top.sv','memory.sv':'project/booted_memory.sv','transport.sv':'project/thin_transport.sv'}.items()}
                derived=reset.derive(native)
                if reference is not None:need(derived==reference,'Native reset fragments differ across images')
                reference=derived
            source,fragments,connections=reference
            need((run/'reset.sv').read_text()==source and inp['assumption_cells']==0 and not inp['internal_cuts'],'Native reset proof model changed')
            for name,text in fragments.items():need((run/('native-fragment-'+name)).read_text()==text,'Native reset fragment changed')
            need(inp['binding']['actual_clock_reset_connections']==connections,'Native reset bindings changed')
            continue
        if kind=='boot-boundary':
            original=None
            for variant,(_,root,bound)in bindings.items():
                need(inp['binding']['native_joins'][variant]==bound,'Boot boundary native/image join changed')
                sources={n:(root/p).read_bytes()for n,p in boundary.SOURCES.items()}
                if original is not None:need(sources==original,'Native boot boundary differs across images')
                original=sources
            for name,raw in original.items():need((run/('production-'+name)).read_bytes()==raw,'Native boot boundary source changed')
            boot=(work/'boot-order-monitor.inc.sv').read_text();parent=(work/'boot-boundary-monitor.inc.sv').read_text()
            need((run/'boot-monitor.inc.sv').read_text()==boot and(run/'parent-monitor.inc.sv').read_text()==parent,'Boot boundary monitor changed')
            observer.observer_writes_only(boot);observer.observer_writes_only(parent)
            native=dict(original)
            if mutant:
                name,before,after=boundary.MUTATIONS[mutant]
                native[name]=boundary.once(native[name].decode(),before,after).encode()
            expected=boundary.instrument(native,boot,parent)
            need(all((run/n).read_bytes()==raw for n,raw in expected.items()),'Boot boundary instrumentation changed production logic')
            need(inp['assumption_cells']==0 and not inp['internal_cuts']and not inp['changed_production_parameters'],'Boot boundary abstraction changed')
            continue
        variant=inp['binding']['variant'];pin,root,bound=bindings[variant]
        need(all(inp['binding'].get(k)==v for k,v in bound.items()),'Native image association changed')
        if kind=='boot-path':
            inner='memory'if inp['binding'].get('complete_source_contract')else'wrapper'
            paths=dict(boundary.SOURCES,**{'wrapper.sv':wrapper.WRAPPER,'async-fifo.sv':'project/fifo.sv'})
            if inner=='memory':paths.update({'handoff.sv':'project/handoff.sv','memory.sv':'project/booted_memory.sv'})
            original={n:(root/p).read_bytes()for n,p in paths.items()}
            need(inp['binding']['production_sources']=={n:dict(path=paths[n],sha256=sha(r))for n,r in original.items()},'Source-path production inventory changed')
            for name,raw in original.items():need((run/('production-'+name)).read_bytes()==raw,'Source-path native body changed')
            auth=(root/wrapper.AUTH).read_bytes()
            need((run/'production-auth.sv').read_bytes()==auth and inp['binding']['authentication_source_sha256']==sha(auth),'Authenticator provenance changed')
            cuts=[dict(r,instance=('u_boot.'if inner=='memory'else'')+'u_sole_readback_auth',replacement='unrestricted module input '+r['input'])for r in wrapper.AUTH_CUTS]
            need(inp['internal_cuts']==cuts and inp['binding']['authenticator_outputs_arbitrary']==cuts,'Source-path four scalar cuts changed')
            boot=wrapper.multiclock_boot_monitor((work/'boot-order-monitor.inc.sv').read_text())
            bmon=(work/'boot-boundary-monitor.inc.sv').read_text();wmon=(work/'boot-wrapper-monitor.inc.sv').read_text()
            monitors={'boot-monitor.inc.sv':boot,'boundary-monitor.inc.sv':bmon,'wrapper-monitor.inc.sv':wmon};native=dict(original)
            if mutant:
                before,after=wrapper.MUTATIONS[mutant];native['wrapper.sv']=boundary.once(native['wrapper.sv'].decode(),before,after).encode()
            if inner=='wrapper':expected,auth_instance=wrapper.instrument(native,boot,bmon,wmon)
            else:
                hmon=(work/'handoff-path-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
                pmon=(work/'memory-path-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))+'\n'+(work/'memory-source-contract.inc.sv').read_text()
                monitors.update({'handoff-monitor.inc.sv':hmon,'parent-monitor.inc.sv':pmon})
                expected,auth_instance=memory.instrument(native,boot,bmon,wmon,hmon,pmon)
            for name,text in monitors.items():
                need((run/name).read_text()==text,'Source-path monitor changed');observer.observer_writes_only(text)
            need(all((run/n).read_bytes()==raw for n,raw in expected.items()),'Source-path observer/cut reversal failed')
            need((run/'cut-auth-instance.sv.txt').read_text()==auth_instance and inp['assumption_cells']==0,'Source-path auth boundary changed')
            continue
        original=(root/'project/fifo.sv').read_bytes();parent=(root/'project/thin_transport.sv').read_bytes()
        need((run/'production-fifo.sv').read_bytes()==original and(run/'production-transport.sv').read_bytes()==parent,'Epoch production sources changed')
        ledger=json.loads((run/'discharged-fifo-lemma-audit.json').read_bytes());template=(work/'fifo-monitor.inc.sv').read_text()
        origins=transport.verify_fifo_lemma_inputs(ledger,variant,original,parent,template,common)
        need(origins==inp['binding']['fifo_lemma_origins'],'Epoch FIFO premise discharge changed')
        lemmas=('\n'.join(s for s in template.splitlines()if not s.strip().startswith('cover('))+'\n').replace('assert(','assume(')
        policy=transport.render_policy_monitor(pin['kv_limit'])
        fmon=(work/'transport-epoch-fifo-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
        pmon=transport.render_parent_monitor(pin['kv_limit'],field_identity=True)
        pphase=(work/'transport-epoch-parent-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
        expected,_=epoch.instrument(original,parent,lemmas+policy,fmon,pmon,pphase,mutant=bool(mutant))
        need(all((run/n).read_bytes()==raw for n,raw in expected.items()),'Epoch instrumentation changed native production logic')
        need(inp['assumption_cells']==54 and not inp['internal_cuts']and not inp['changed_production_parameters'],'Epoch abstraction changed')
        source_raw,reset_raw,origin=epoch.source_guarantees(package,variant,common)
        need((run/'discharged-source-audit.json').read_bytes()==source_raw and(run/'discharged-reset-audit.json').read_bytes()==reset_raw and inp['binding']['source_guarantee_origin']==origin,'Epoch source/reset premise discharge changed')
        joins.append(load(work,'audit_transport_epoch').contract_join(run,variant,package,fresh['source'],fresh['reset'],fresh['top']))
    need(closure['actual_source_to_physical_write_epoch_composed']and len(joins)==4,'Recorded physical epoch closure incomplete')
    return dict(current_new_source_instrumentation_recovered=True,new_epoch_run_source_joins=len(joins),
        compiler_or_solver_executed=False,recorded_temporal_composition_binding_checked=True)

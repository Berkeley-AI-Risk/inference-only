"""Check native staging observations, RAM geometry and full-epoch simulation joins."""
import argparse
import json
from pathlib import Path

from record_progress import audit, sha
from run_attention_ownership import HERE
from audit_proof_instantiations import body
from audit_model_drain import observer_only
from run_kv_session_drain import TOP


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--runs',nargs='+',required=True)
    ap.add_argument('--simulation',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    manifest={};results={}
    def pin(path,digest=None):
        raw=path.read_bytes();h=sha(raw)
        if digest is not None and h!=digest:raise ValueError('Source artifact changed')
        manifest[str(path.resolve())]=h;return raw
    joins_raw=(HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes();joins=json.loads(joins_raw)
    (out/'instantiation-bindings.json').write_bytes(joins_raw);pin(out/'instantiation-bindings.json')
    simulation=args.simulation.resolve();sim=json.loads(pin(simulation/'FINISHED.json'))
    if not sim['passed']or sim['reset_between_epochs']or not sim['physical_boot_reset_used']:
        raise ValueError('Full-stage simulation entry/result differs')
    pin(simulation/'runner.py',sim['runner_sha256'])
    for variant,case in sim['cases'].items():
        if not case['passed']or any(r['exit']for r in case['commands']):raise ValueError('Incomplete simulation case')
        for name,row in case['files'].items():pin(simulation/variant/name,row['sha256'])
        for name,row in zip(('compile.log','sim.log'),case['commands']):pin(simulation/variant/name,row['log_sha256'])
    for name in args.runs:
        run=HERE/'runs'/name;receipt=audit(name,'Current-epoch native K/V staging ownership')
        if receipt['status']!='proved_component':raise ValueError('Staging proof is not closed')
        inp=json.loads(pin(run/'INPUTS.json'));pin(run/'FINISHED.json');b=inp['binding']
        if inp['mutant']or inp['assumption_cells']or inp['observer_constants']!=1 or inp['internal_cuts']or b['initial_hard_reset']:
            raise ValueError('Unexpected assumptions, reset or cuts')
        for filename,row in inp['files'].items():pin(run/filename,row['sha256'])
        monitor=(run/'staging-owner-monitor.inc.sv').read_text();observer_only(monitor)
        actual=(run/(TOP+'.sv')).read_text();original=body((run/('production-'+TOP+'.sv')).read_bytes(),TOP).decode()
        observation=(run/'staging-owner-observation.inc.sv').read_text()
        baseline=b['variant']=='baseline';banks=8 if baseline else 16;size=32 if baseline else 8
        cached='cached-row-monitor.inc.sv'in inp['files']
        typed_write='typed-write-history-monitor.inc.sv'in inp['files']
        restored=actual
        if typed_write:
            if not baseline or not cached:raise ValueError('Unexpected typed-write source class')
            wm=(run/'typed-write-history-monitor.inc.sv').read_text();observer_only(wm)
            if restored.count(wm)!=1:raise ValueError('Typed-write observation is not removable')
            restored=restored.replace('\n'+wm+'\n','\n',1)
        if cached:
            if not baseline:raise ValueError('Unexpected committed-kind cache source class')
            cm=(run/'cached-row-monitor.inc.sv').read_text();observer_only(cm)
            co=(run/'cached-row-observation.inc.sv').read_text()
            if co!="assign f_cached_words[bank*32 +:32]=words[{2'b00,f_cache_word}];"or restored.count(cm)!=1 or restored.count(co)!=1:
                raise ValueError('Cached-row observation changed')
            restored=restored.replace('\n        '+co,'',1).replace('\n'+cm+'\n','\n',1)
        expected=("assign f_staged_pairs[bank*32 +:32]=words[5'd8+{1'b0,f_coordinate[6:3]}];"if baseline else
            'assign f_staged_pairs[lane*32 +:32]=memory[f_coordinate[6:4]];')
        if observation!=expected or actual.count(observation)!=1 or actual.count(monitor)!=1:
            raise ValueError('Native symbolic observation differs')
        restored=restored.replace('\n        '+observation,'',1).replace('\n'+monitor+'\n','\n',1)
        if restored!='`undef FORMAL\n'+original+'\n':raise ValueError('Observer removal changes production body')
        mapper='board1_context2048_typed_address_mapper'
        if (run/(mapper+'.sv')).read_text()!='`undef FORMAL\n'+body((run/('production-'+mapper+'.sv')).read_bytes(),mapper).decode()+'\n':
            raise ValueError('Native mapper differs')
        for module in b['isolated_native_modules']:
            if pin(run/('production-'+module+'.sv'))!=pin(simulation/b['variant']/(module+'.sv')):
                raise ValueError('Simulation and proof production files differ')
        graph=json.loads(pin(run/'elaborated.json'))['modules'][inp['top']];memories={}
        for n,c in graph['cells'].items():
            if c['type']!='$mem_v2':continue
            geometry={k:int(c['parameters'][k],2)for k in ('WIDTH','SIZE','ABITS','RD_PORTS','WR_PORTS')}
            if geometry!=dict(WIDTH=32,SIZE=size,ABITS=5 if baseline else 3,RD_PORTS=3 if cached else 2,WR_PORTS=1):
                raise ValueError('Full RAM or observation geometry differs')
            memories[n]=geometry
        if len(memories)!=banks:raise ValueError('Native bank count differs')
        variants=joins['proof_module_joins'][name]['active_variant_source_joins']
        if variants!=(['baseline','seeded-sampling']if baseline else['encrypted-memory','kv-protected']):
            raise ValueError('Native source-class join differs')
        results[name]=dict(receipt=receipt,active_variants=variants,full_memories=memories,
            symbolic_coordinate_bits=7,stage_coordinate_count=128,physical_reset_required=False,
            cached_row_full_fill_and_actual_RAM_history=cached,
            staging_registered_read_to_typed_write_history=typed_write,
            full_stage_reachability_supplement='Behavioral native simulation uses initial boot reset, retains payload through ordinary CLEAR, and fully checks the next stage. Short formal covers exercise fresh BEGIN and coordinate zero; they do not cover all 128 uploads.')
    checker=out/'checker.py';checker.write_bytes(Path(__file__).read_bytes());pin(checker)
    result=dict(native_kv_staging_source_join_passed=True,cases=results,simulation=str(simulation/'FINISHED.json'),
        artifact_manifest=manifest,whole_device_session_theorem=False,full_KV_payload_correspondence=False,
        scope='After logical CLEAR, current staging writers own all used coordinates and exponent metadata, with full native RAMs retained and symbolic actual-bit history. Exact source matches full-epoch simulation in both architectures. Committed-cache and assembly/output correspondence, guard/outer transport and whole-device composition remain separate.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(native_kv_staging_source_join_passed=True,scopes=len(results),
        source_classes=len({tuple(r['active_variants'])for r in results.values()}),whole_device_session_theorem=False)))


if __name__=='__main__':main()

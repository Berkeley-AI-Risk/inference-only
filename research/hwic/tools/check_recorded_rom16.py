"""Check archived finite-corpus receipts. Does not execute RTL or prove silicon behavior."""
from pathlib import Path
import hashlib,json,types

def module(name):
    path=Path(__file__).resolve().with_name(name+'.py')
    m=types.ModuleType(name);m.__file__=str(path)
    exec(compile(path.read_bytes(),str(path),'exec'),m.__dict__)
    return m

def verify(directory):
    directory=Path(directory)
    record=json.loads((directory/'results.json').read_bytes())
    assert record['schema']=='hwic.recorded-mapped-rom16-regression.v1'
    checks=module('rom16_log_checks')
    normal=[];wrong=[]
    for row in record['replays']:
        name=row['excerpt_file']
        assert Path(name).name==name
        raw=(directory/name).read_bytes()
        assert dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())==row['excerpt_identity']
        parser=checks.positive_log if row['kind']=='normal' else checks.wrong_log
        parsed=parser(raw.decode())
        assert parsed==row['parsed_excerpt']
        if row['kind']=='normal':
            assert row['actual_signed_native_exit']==0
            normal.append((row['seed'],parsed))
        else:
            assert row['kind']=='wrong' and row['seed']==1 and row['actual_signed_native_exit']==1
            assert parsed['actual_first_assertion']==record['negative']['actual_first_assertion']
            wrong.append(parsed)
    assert [seed for seed,_ in normal]==[1,17,20261028,2147483646] and len(wrong)==1
    assert sum(p['rows'] for _,p in normal)==record['positive']['checked_output_rows']==68544
    assert sum(p['replays'] for _,p in normal)==record['positive']['vector_replays']==264
    stages=record['recorded_native_stages']
    expected=['rom16.normal.generate','rom16.normal.make']
    expected+=['rom16.normal.replay.seed'+str(s) for s,_ in normal]
    expected+=['rom16.wrong.generate','rom16.wrong.make','rom16.wrong.replay.seed1']
    assert [r['stage_id'] for r in stages]==expected
    assert [r['actual_signed_native_exit'] for r in stages]==[0]*8+[1]
    assert all(r['resource_clean_and_observed_group_drained'] for r in stages)
    assert [r['expected_negative'] for r in stages]==[False]*8+[True]
    cpu=sum(r['native_wait4_CPU_user_seconds']+r['native_wait4_CPU_system_seconds'] for r in stages)
    assert abs(cpu-record['accounting']['disjoint_direct_native_wait4_CPU_seconds'])<1e-6
    assert not record['limitations']['ASIC_clock_area_power_DRC_LVS_or_foundry_qualification']
    assert not record['limitations']['full_model_or_new_spatial_candidate_regression_completed_by_this_campaign']
    return dict(recorded_positive_seeds=len(normal),recorded_rows=68544,recorded_vectors=264,
                recorded_faults=len(wrong),native_hardware_run_performed_by_this_checker=False)

if __name__=='__main__':
    print(json.dumps(verify(Path(__file__).resolve().parents[1]/'evidence/rom16-2026-11-03'),sort_keys=True))


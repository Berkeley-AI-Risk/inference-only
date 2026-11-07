#!/usr/bin/env python3
"""Check selected S-AWIC source, timing, proof and physical evidence offline."""

if not __debug__:
    raise SystemExit("Verification requires Python assertions; do not use -O or -OO")
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/'demos/simplestories-v2-5m'
VARIANTS=MODEL/'variants'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text())


def check_home_selection_metadata(repository, model, timing, replacement):
    """Keep a historical pass attached to its image, separately from selection."""
    root_home=repository['demonstrations']['simplestories-v2-5m']['home_authorization']
    model_home=model['variants']['home-authorization']
    recorded=model_home['physical_model_replacement']
    selected=timing['bitstream_sha256'];captured=replacement['fpga_image_sha256']
    passed=replacement['result']=='PASS';same=selected==captured
    for aggregate in [root_home,model_home]:
        assert aggregate['selected_image_sha256']==selected
        assert aggregate['reported_core_fmax_mhz']==timing['reported_core_fmax_mhz']
    assert root_home['physical_model_replacement_campaign_passed']==passed
    assert root_home['physical_model_replacement_campaign_image_sha256']==captured
    assert root_home['physical_model_replacement_selected_image_passed']==(passed and same)
    assert recorded['image_sha256']==captured and recorded['passed']==passed
    assert recorded['applies_to_selected_image']==same
    assert model_home['physical_model_replacement_selected_image_passed']==(passed and same)
    return dict(recorded_image_sha256=captured,selected_image_sha256=selected,
                recorded_pass=passed,selected_image_pass=passed and same)


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    return value


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();out=a.output.resolve();assert not out.exists();out.mkdir(parents=True)
    rows=[]
    for rel,stem,home in [('signed-update/tang','swic_product',False),('home-authorization','home_product',True)]:
        target=VARIANTS/rel;identity=read(target/'SOURCE-IDENTITY.json')
        native=target/'evidence/repair-native-2026-11-05'
        pins=read(native/'INPUTS.json');result=read(native/'RESULT.json');review=read(native/'REVIEW.json')
        assert result['exit_code']==0 and result['inputs_sha256']==sha(native/'INPUTS.json')
        assert result['tool_sha256']=='76b24d18ec9785be73de6e9e98866bbd7bec330aff67d1fa8462f71f79b5f72c'
        nonvendor={n:h for n,h in pins.items()if not n.startswith('project/official/')}
        assert identity['native_inputs']==nonvendor
        for name,pin in nonvendor.items():assert sha(target/'hardware'/name)==pin,name
        dependencies=read(MODEL/'VENDOR-DEPENDENCIES.json')['downloads']
        for name,record in dependencies.items():assert pins['project/official/'+name]==record['sha256']
        assert identity['prebuilt_sha256']==review['sha256']==sha(target/f'prebuilt/{stem}.fs')
        assert review['result']=='COMPILED_SOURCE_BOUND'and review['nominal_core_hz']==25000000
        timing=read(native/'TIMING-REVIEW.json')if home else review
        report=native/f'{stem}.tr'
        assert timing['timing_report_sha256']==sha(report)
        assert timing['functional_board_test_allowed']
        frequency=timing['reported_core_fmax_mhz']if home else timing['reported_core_fmax_MHz']
        assert frequency>=25
        for clock in ['board_clk50','memory_clk400','app_clk100','trusted_clk12p5','inference_clk25']:
            for kind in ['setup','hold']:
                r=timing['real_clock_setup_hold_summary'][clock][kind]
                assert r['tns']==0 and r['violated_endpoints']==0
        if home:
            assert timing['bitstream_sha256']==review['sha256']
            assert timing['startup_reset_removal_violations']==timing['accepted_synchronizer_entry_exceptions']==[]
            assert review['phase_qualified_startup_reset_source_and_mapping_checked']
            assert review['wrapper_routes_physical_nonce']and not review['physical_source_simulation_mode']
            assert review['reported_logic_latches']==21
            metadata=check_home_selection_metadata(read(ROOT/'MANIFEST.json'),read(MODEL/'MANIFEST.json'),
                timing,read(target/'evidence/model-replacement-v2/RESULT.json'))
        capture=target/'evidence/repair-board-2026-11-05'
        if home:
            checked=module('selected_home_evidence',target/'tools/check_evidence.py').verify(target,capture)
            assert checked['valid_grants']==8 and checked['distinct_nonces']==10
            assert checked['restored_baseline_verified']
        else:
            checked=module('selected_signed_evidence',target/'tools/check_common_speed.py').verify(target,capture)
            assert checked==read(capture/'RAW-REVIEW.json')
            assert read(capture/'RESTORED.json')['result']=='PASS'
        assert checked['result']=='PASS'
        rows.append(dict(variant=rel,result='PASS',native_nonvendor_inputs=len(nonvendor),reported_fmax_MHz=frequency,
            bitstream_sha256=review['sha256'],physical_evidence_rechecked=True))
        if home:rows[-1]['replacement_image_scope']=metadata
    commands=[
        ['demos/simplestories-v2-5m/variants/home-authorization/tools/check_model_replacement.py'],
        ['demos/simplestories-v2-5m/variants/signed-update/formal/page-consistency/check_recorded.py'],
        ['demos/simplestories-v2-5m/variants/signed-update/formal/stream-assembly/check_recorded.py'],
        ['demos/simplestories-v2-5m/variants/signed-update/tang/tests/check_consistency_evidence.py'],
        ['demos/simplestories-v2-5m/variants/home-authorization/formal/authorization-control/check_composition.py','--out',str(out/'authorization-control')]]
    for i,args in enumerate(commands):
        with(out/f'check-{i}.log').open('w')as log:r=subprocess.run([sys.executable,'-I','-S','-B',*args],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        assert r.returncode==0,args[0]
    result=dict(result='PASS',variants=rows,page_controller_formal_jobs=2,stream_equivalence_configurations=5,
        conditional_authorization_control_jobs=12,recorded_only=True,hardware_access=False,
        whole_machine_theorem=False,physical_entropy_certification=False,production_timing_certification=False)
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))


if __name__=='__main__':main()

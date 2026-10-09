#!/usr/bin/env python3
"""Check the current speed images and their sanitized physical measurements.

Offline arithmetic/source association only. The private exporter replays the
raw UART records; this public checker does not repeat that replay, attest the
loaded FPGA, or certify physical security or DDR timing.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGES = {
    'kv-protected':'72d5a54e06ed2017e653122f3daecf073f239a917b79f24d1e7b886d68a21a2f',
    'encrypted-memory':'865e74e692d5978815fe921f11e4fa1b8e2c080401a8be05508dd9775823aecc',
}
CASE_ORDER = {
    'kv-protected':['around128','prefix128','prefix512','around128','prefix2047','prefix2048'],
    'encrypted-memory':['around128','fox128','help64','moon64','prefix128','prefix512','prefix1024','prefix2047'],
}


def need(ok, why):
    if not ok: raise ValueError(why)


def close(a,b):
    need(type(a) in (int,float) and math.isfinite(a) and a>0 and
         math.isclose(a,b,rel_tol=1e-10,abs_tol=1e-10),'Incorrect measurement arithmetic')


def validate(data, references):
    need(data['schema']=='tang-speed-release-board-summary-v1'
         and data['measured_on_physical_board'] is True
         and data['raw_transcripts_independently_rechecked'] is True
         and data['public_summary_replays_private_transcripts'] is False
         and data['restoration_checked'] is True and data['model_input_positions']==2048,
         'Wrong measured-evidence scope')
    for key in ('timing_qualified','physical_security_qualified','configuration_independently_attested'):
        need(data[key] is False,'Unsupported physical qualification')
    need(set(data['variants'])==set(IMAGES),'Wrong variant selection')
    total = 0
    for variant,group in data['variants'].items():
        rows = group['cases']
        need([r['case'] for r in rows]==CASE_ORDER[variant],'Missing or reordered board cases')
        need(group['full_context_board_test_of_this_image'] is True,
             'Full-context evidence overstated or lost')
        outputs = 0
        for row in rows:
            name = row['case']; ref = references[name]
            need(row['prompt_tokens']==ref['prompt_tokens'] and row['generated_tokens']==ref['generated_tokens'],
                 'Different fixed-integer reference tokens')
            need(row['image_sha256']==IMAGES[variant] and row['clear_replay_outputs']==12,
                 'Wrong measured image or missing CLEAR/replay')
            times = row['step_seconds']; n = len(row['generated_tokens'])
            need(len(times)==n and n>=1 and all(type(t) in (int,float) and math.isfinite(t) and t>0 for t in times),
                 'Invalid measured duration census')
            close(row['first_step_seconds'],times[0])
            if n>1: close(row['cached_tokens_per_second'],(n-1)/sum(times[1:]))
            else: need(row['cached_tokens_per_second'] is None,'No cached rate exists for a single reply')
            if variant=='kv-protected':
                need(row['raw_frame_negative_controls_rejected']==4,'Incomplete negative controls')
                if name=='around128': close(row['first_six_tokens_per_second'],6/sum(times[:6]))
                else: need(row['first_six_tokens_per_second'] is None,'Unexpected short-test claim')
            else:
                value = row['max_wall_monotonic_discrepancy_seconds']
                need(type(value) in (int,float) and math.isfinite(value) and 0<=value<1,'Inconsistent measurement clocks')
            for key in ('source_receipt_sha256','private_uart_sha256'):
                h = row[key]
                need(isinstance(h,str) and len(h)==64 and all(c in '0123456789abcdef' for c in h),'Invalid evidence hash')
            outputs += n
        need(group['reference_matching_outputs']==outputs==(391 if variant=='kv-protected' else 522),
             'Incorrect output census')
        if variant=='kv-protected': close(group['short_test_tokens_per_second'],rows[0]['first_six_tokens_per_second'])
        else:
            short = group['short_test_step_seconds']
            need(len(short)==6 and all(type(t) in (int,float) and math.isfinite(t) and t>0 for t in short),
                 'Invalid encrypted short-test durations')
            close(group['short_test_tokens_per_second'],6/sum(short))
        total += outputs
    return dict(passed=True,variants=2,main_case_outputs=total,
        current_kv_full_context_board_test=True,current_encrypted_full_context_board_test=True,
        private_raw_transcripts_replayed=False,timing_qualified=False,physical_security_qualified=False)


def validate_replay(package, replay):
    expected_path = package/'formal/kv-integrity/expected.json'
    expected = json.loads(expected_path.read_bytes())
    need(replay['schema']=='tang-speed-release-replay-v1' and replay['passed'] is True
         and replay['both_solvers_complete'] is True
         and replay['assertions']==dict(history=221,parent=325,attention=34)
         and replay['solver_queries']==dict(history=446,parent=672,attention=72)
         and replay['negative_controls_detected']==4 and replay['induction_fault_controls_detected']==23
         and replay['audit_regression_tests']==44 and replay['fault_audit_regression_tests']==8,
         'Incomplete recorded proof replay')
    for key in ('whole_machine_refinement','guard_attention_joint_theorem',
                'sha_compression_correctness_proved','encrypted_variant_formally_verified',
                'hardware_access','network_access'):
        need(replay[key] is False,'Unsupported replay qualification')
    need(replay['protected_image_sha256']==IMAGES['kv-protected']
         and replay['protected_hardware_inputs_sha256']=='cfff67c4559b290287ea0c024f4782154fc0c27aa62bb3b264b2e5bf472ed7b2'
         and replay['published_expected_sha256']==hashlib.sha256(expected_path.read_bytes()).hexdigest(),
         'Wrong proof image or expectations')
    sources = {**expected['production_sources'],**expected['verification_sources'],**expected['replay_sources']}
    need(replay['proof_sources']==sources,'Wrong proof source census')
    for name,h in sources.items():
        need(hashlib.sha256((package/name).read_bytes()).hexdigest()==h,'Changed proof source')
    need(set(replay['stages'])==set(expected['recorded_results']),'Wrong proof stages')
    for stage,row in replay['stages'].items():
        recorded = expected['recorded_results'][stage]
        need(row=={k:recorded[k] for k in ('finished_receipt_sha256','assertions','solver_queries')},
             'Different recorded solver receipt')
    guard = replay['guard_full_geometry']
    need(guard['passed'] is True and guard['commands']==275913 and guard['engine']=='verilator'
         and guard['cancellation_cases']==dict(write=10,read=13,tag_groups=4)
         and guard['watchdog'] is True and guard['collision'] is True
         and len(guard['source_sha256'])==8,'Incomplete recorded guard simulation')
    for name,h in guard['source_sha256'].items():
        need(hashlib.sha256((package/name).read_bytes()).hexdigest()==h,'Changed guard source')
    return dict(recorded_proof_replay_checked=True,recorded_guard_commands=275913,
                solver_execution_repeated_by_this_check=False)


def check(package):
    package = Path(package)
    data = json.loads((package/'evidence/speed-2026-10-02/board.json').read_bytes())
    references = json.loads((package/'evidence/encrypted-memory/broad-board.json').read_bytes())['reference_cases']
    # The established full reference set also covers the two long prompts not
    # duplicated in tests/reference-cases.json. Never invent replacement outputs.
    canonical = (json.dumps(references,sort_keys=True,separators=(',',':'))+'\n').encode()
    need(hashlib.sha256(canonical).hexdigest()=='00e4e7ef40f965b3c5a0fbf035ce2ee01b4bd85c187a3cfd2e91c0ad124e2a6f',
         'Changed established integer references')
    current_references = json.loads((package/'evidence/read-window/references.json').read_bytes())
    need(all(references[n] == r for n,r in current_references.items() if n in references),
         'Different repeated integer reference')
    references.update(current_references)
    result = validate(data,references)
    replay = json.loads((package/'evidence/speed-2026-10-02/replay.json').read_bytes())
    result.update(validate_replay(package,replay))
    native = json.loads((package/'evidence/speed-2026-10-02/native.json').read_bytes())
    need(native['schema']=='tang-speed-release-native-summary-v1'
         and native['inference_clock_mhz']==25 and native['raw_vendor_reports_bundled'] is False
         and set(native['variants'])==set(IMAGES),'Wrong native summary')
    counts = {'kv-protected':93,'encrypted-memory':100}
    margins = {'kv-protected':(0.228,0.116,152,10),'encrypted-memory':(0.084,0.144,161,2)}
    multiplier_counts = {'kv-protected':73,'encrypted-memory':65}
    for variant,row in native['variants'].items():
        setup,hold,ns,nh = margins[variant]
        need(row['image_sha256']==IMAGES[variant] and row['hardware_inputs']==counts[variant]
             and row['route_completed'] is True and row['source_inputs_unchanged'] is True
             and row['timing_qualified'] is False and row['physical_security_qualified'] is False,
             'Wrong native build scope')
        close(row['inference_setup_slack_ns'],setup); close(row['inference_hold_slack_ns'],hold)
        need(row['global_violated_endpoints']==dict(setup=ns,hold=nh),'Wrong remaining timing violations')
        need(row['resources']['MULTALU27X18']==multiplier_counts[variant] and row['resources']['MULT12X12']==3,
             'Wrong mapped multiplier census')
        built = json.loads((package/('prebuilt/'+variant+'/BUILD.json')).read_bytes())
        need(built['original_build_receipt_sha256']==row['native_receipt_sha256'],
             'Native summary and build record differ')
    spec = importlib.util.spec_from_file_location('current_speed_release_inventory',package/'tools/verify_release.py')
    verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
    result['release_inventory'] = verifier.verify(package)
    for variant,h in IMAGES.items():
        built = json.loads((package/('prebuilt/'+variant+'/BUILD.json')).read_bytes())
        need(built['image_sha256']==h and built['timing_qualified'] is False,'Measured and selected images differ')
    return result


if __name__=='__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(p.parse_args().package),indent=2))

"""Offline checks of the September leaf-speed builds and historical evidence.

Checks reconstructed source identities, revision history and saved arithmetic.
Both images have since been replaced; these checks retain their original scope.
Does not run hardware, replay private raw logs, or establish timing/security.
"""
import hashlib
import importlib.util
import json
import math
from pathlib import Path, PurePosixPath

IMAGES = {
    'baseline': '44a7fb18131e07bdb39ccdead1083f8224822a44a2ec36f1455e2d12acb566ed',
    'kv-protected': 'e22079c855cdf6cfb983c73850db15b1b5010f0511fa62f98f3d040ae0654ea2',
}
PREFIX = 'evidence/leaf-speed/'
TOOL_SHA256 = '1a2497e6752a4561b64f620e0aa68ae5da599b118f8d723ca70c491f6688678e'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def read(path): return json.loads(path.read_bytes())
def require(ok, message):
    if not ok: raise ValueError(message)
def close(a, b):
    require(math.isfinite(a) and math.isfinite(b) and math.isclose(a,b,rel_tol=1e-10,abs_tol=1e-10),
            'Inconsistent leaf-speed measurement arithmetic')


def restore_revision(raw, change):
    """Recover old bytes only through an explicit exact reversible patch."""
    require(sha(raw) == change['after_sha256'],'Changed selected source')
    lines = raw.decode().splitlines(keepends=True); boundary = len(lines)
    for edit in reversed(change['reverse_edits']):
        start,end = edit['start'],edit['end']
        require(type(start) is int and type(end) is int and 0 <= start <= end <= boundary,
                'Invalid revision edit range')
        require(lines[start:end] == edit['after'],'Changed revision edit bytes')
        lines[start:end] = edit['before']; boundary = start
    result = ''.join(lines).encode()
    require(sha(result) == change['before_sha256'],'Historical reconstruction failed')
    return result



def pre_encrypted_bytes(package, name, raw):
    path = Path(package)/'tools/encrypted_memory_history.py'
    spec = importlib.util.spec_from_file_location('encrypted_history',path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.previous_bytes(package,name,raw)


def before_speed(package, name, raw):
    spec = importlib.util.spec_from_file_location('speed_history',Path(package)/'tools/speed_release_history.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.previous_bytes(package,name,raw)


def before_speed_digest(package, name, raw):
    spec = importlib.util.spec_from_file_location('speed_history',Path(package)/'tools/speed_release_history.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.previous_digest(package,name,raw)

def historical_source_bytes(package, name, raw):
    """Return the pre-leaf source for checking explicitly historical records."""
    raw = pre_encrypted_bytes(package,name,raw)
    record = read(Path(package)/PREFIX/'source-revision.json')
    require(record['schema'] == 'leaf-speed-source-revision-v1','Wrong revision record')
    change = record['changes'].get(name)
    return restore_revision(raw,change) if change else raw


def check_physical(data):
    require(data['schema'] == 'leaf-speed-physical-v1' and data['image_sha256'] == IMAGES,
            'Wrong selected physical images')
    for key in ('timing_qualified','configuration_independently_attested','physical_corruption_injection_tested','flash_modified'):
        require(data[key] is False,'Unsupported physical claim')
    expected = {'known1':(1,8),'known8':(8,8),'around128':(1,128),
                'prefix128':(128,128),'prefix512':(512,4),'prefix2047':(2047,2)}
    require(set(data['variants']) == set(IMAGES),'Missing physical variant')
    outputs = 0
    for variant,cases in data['variants'].items():
        require(set(cases) == set(expected),'Missing measured workload')
        for name,row in cases.items():
            prompt,count=expected[name]
            require(row['passed'] is True and row['image_sha256']==IMAGES[variant],'Wrong case image/result')
            require(row['prompt_token_count']==prompt and len(row['prompt_tokens'])==prompt
                    and len(row['generated_tokens'])==count and len(row['step_seconds'])==count,
                    'Wrong case dimensions')
            require(row['maximum_occupied_tape']==prompt+count and row['final_clear_acknowledged'] is True,
                    'Wrong tape/CLEAR result')
            require(row['clock_audit_passed'] is True and row['negative_controls_rejected']==4,
                    'Unusable or unaudited measurement')
            require(all(type(t) is int and 0<=t<4019 for t in row['prompt_tokens']+row['generated_tokens']),
                    'Invalid token')
            require(all(math.isfinite(t) and t>0 for t in row['step_seconds']),'Invalid elapsed time')
            close(row['first_step_seconds'],row['step_seconds'][0])
            close(row['last_step_seconds'],row['step_seconds'][-1])
            close(row['cached_command_tokens_per_second'],(count-1)/sum(row['step_seconds'][1:]))
            close(row['cached_stream_tokens_per_second'],(count-1)/row['cached_stream_seconds'])
            require(row['first_append_to_first_reply_seconds']>=row['first_step_seconds'],
                    'Invalid upload-inclusive latency')
            known=[200,15,103,157]
            require(row['all_generated_tokens']==known+row['generated_tokens']+known+known,
                    'Wrong surrounding CLEAR/replay outputs')
            outputs += len(row['all_generated_tokens'])
    for name in expected:
        a,b=(data['variants'][v][name] for v in IMAGES)
        require(a['prompt_tokens']==b['prompt_tokens'] and a['generated_tokens']==b['generated_tokens'],
                'Unmatched baseline/protected workload')
    return outputs


def check_host_timing(data, physical):
    require(data['schema']=='leaf-speed-host-timing-v1', 'Wrong host-timing schema')
    require(data['firmware_cause_established'] is False and
            data['fixed_delay_correction_applied'] is False, 'Unsupported timing interpretation')
    close(data['approximate_reply_interval_seconds'], 0.017)
    experiment=data['latency_setting_experiment']
    require(experiment['latency_improved'] is False and
            experiment['image_is_preceding_protected_build'] is True and
            experiment['image_sha256']=='f51dfaa1f84be585db990f1037f5ae9d328b9064f2e26fc514ae41f9a7bcb324',
            'Wrong latency-experiment outcome or image')
    require(experiment['raw_log_bundled'] is False and
            experiment['ioctl_argument_units_not_assumed'] is True, 'Wrong experiment scope')
    require(len(experiment['phases'])==3 and
            all(p['append_count']==32 and 16<p['median_append_ms']<18 for p in experiment['phases']),
            'Wrong latency observations')
    simulated=data['simulated_short_step']
    require(simulated['before_core_cycles']==3511002 and simulated['after_core_cycles']==3309125 and
            simulated['harness_and_logs_bundled'] is False, 'Wrong private simulation scope')
    close(simulated['fractional_cycle_reduction'], (3511002-3309125)/3511002)
    require(set(data['full_context'])==set(IMAGES), 'Missing interval comparison')
    for variant, row in data['full_context'].items():
        source=physical['variants'][variant]['prefix2047']
        close(row['cached_step_seconds'], source['last_step_seconds'])
        close(row['step_only_tokens_per_second'], 1/source['last_step_seconds'])
        close(row['streaming_seconds'], source['cached_stream_seconds'])
        close(row['streaming_tokens_per_second'], source['cached_stream_tokens_per_second'])
        close(row['extra_interval_seconds'], source['cached_stream_seconds']-source['last_step_seconds'])
        require(row['includes_rejected_append'] is True and
                row['raw_log_sha256']==source['raw_log_sha256'], 'Wrong interval provenance')


def check_build_provenance(record, tool):
    require(record['route_completed'] is True, 'Route completion not recorded')
    require(tool['tool_sha256']==TOOL_SHA256 and
            tool['tool_version']=='V1.9.11.03 Education (81398)' and
            tool['tool_executable']=='IDE/bin/gw_sh', 'Wrong recorded build tool')
    require(tool['build_driver_sha256']=='3554b262836ae77c5e5b96cfb29bb494fe2111d8d895f4e25b0e5c9b8e385c9c' and
            tool['build_runner_sha256']=='08e356693c0154ed362df6cc96d9dae0376747a082a1bab93c3bd85caefd79f2',
            'Wrong tool-identity provenance')


def check_rehearsal(package,data):
    require(data['passed'] is True and data['reference_matching_outputs']==136,
            'Incomplete selected app rehearsal')
    require(set(data['trials'])==set(IMAGES),'Missing selected app version')
    require(all(data[k] is False for k in ('flash_modified','timing_qualified',
        'actual_browser_interaction','configuration_independently_attested')),'Unsupported rehearsal claim')
    reference=read(Path(package)/'tests/reference-cases.json')['fox128']
    for variant,r in data['trials'].items():
        require(r['passed'] is True and r['image_sha256']==IMAGES[variant]
            and r['qualification_generated_tokens']==4 and r['ui_generated_tokens']==64,'Wrong app image/output count')
        for key in ('physical_uart','headless_ui_interaction','displayed_metrics_match',
                    'variant_label_checked','final_clear_acknowledged','connection_released'):
            require(r[key] is True,'Missing real app check')
        require(r['mocked_controller_or_transport'] is False,'Mocked physical rehearsal')
        require([x['label'] for x in r['cases']]==['cold','warm-1','warm-2','reopened'],'Wrong app lifecycle')
        for row in r['cases']:
            require(row['commands']==26 and row['generated_tokens']==reference['generated_tokens'][:16]
                and row['final_clear_acknowledged'] is True,'Wrong app outputs/CLEAR')
            require(row['reused'] is row['label'].startswith('warm'),'Wrong retained-connection evidence')
        for name,digest in r['host_sources'].items():
            require(name.startswith('host-app/') and '..' not in PurePosixPath(name).parts,'Unsafe host evidence path')
            require(sha(pre_encrypted_bytes(package,name,(Path(package)/name).read_bytes()))==digest,'Changed rehearsed host')
    return 136


def check_replay(package,replay):
    require(replay['passed'] is True and replay['whole_machine_refinement'] is False,'Wrong replay claim')
    require(replay['token_shell_assertions']==48 and replay['token_shell_complete_second_solver'] is True
        and replay['protected_assertions']=={'history':221,'parent':325,'attention':34}
        and replay['protected_complete_second_solver'] is True,'Incomplete solver record')
    connected=replay['connected_shell']
    require(connected['primary_assertions']==134 and connected['secondary_base'] is True
        and connected['unresolved_conclusions'] in ([],[39])
        and connected['secondary_conclusions']==134-len(connected['unresolved_conclusions'])
        and connected['complete_second_solver'] is (not connected['unresolved_conclusions']),
        'Incomplete or overstated connected proof')
    require(connected['source_structure_audit_passed'] is True
        and connected['selected_generated_sources_and_queries_match'] is True
        and connected['serial_scenarios']==13 and connected['simulation_fault_controls']==5
        and connected['actual_memories']==17 and connected['private_service_output_cuts']==37,
        'Missing connected source/control checks')
    require(set(replay['model_cases'])=={'zero','stalled','corrupt-boot','corrupt-runtime'}
        and all(r['passed'] is True for r in replay['model_cases'].values()),'Incomplete model replay')
    components=replay['additional_component_replays']
    require({n:r['assertions'] for n,r in components.items()}=={
        'public-commands':60,'kv-epoch':59,'page-bank':37,'uart-frames':None}
        and all(r['passed'] is True for r in components.values()),'Incomplete component replays')
    require({'formal/composed-shell/run_proof.py','formal/composed-shell/expected.json',
        'formal/token-shell/sources.json','formal/kv-integrity/expected.json',
        'simulation/model/expected.json','hardware/project/candidate.sv'}.issubset(replay['source_sha256']),
        'Missing replay source bindings')
    for name,digest in replay['source_sha256'].items():
        require(not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts,'Unsafe replay source')
        require(before_speed_digest(package,name,(Path(package)/name).read_bytes())==digest,'Changed historical replay source')


def check(package):
    package=Path(package)
    physical=read(package/PREFIX/'physical.json')
    outputs=check_physical(physical)
    check_host_timing(read(package/PREFIX/'host-timing.json'), physical)
    reference=read(package/'tests/reference-cases.json')
    for cases in physical['variants'].values():
        for name in ('around128','prefix128','prefix512'):
            require(cases[name]['prompt_tokens']==reference[name]['prompt_tokens'] and
                cases[name]['generated_tokens'][:len(reference[name]['generated_tokens'])]==reference[name]['generated_tokens'],
                'Wrong published integer-reference outputs')
        require(cases['known1']['prompt_tokens']==[378] and
            cases['known1']['generated_tokens']==reference['around128']['generated_tokens'][:8],
            'Wrong short integer-reference case')
        require(cases['known8']['prompt_tokens']==[378]+reference['around128']['generated_tokens'][:7] and
            cases['known8']['generated_tokens']==reference['around128']['generated_tokens'][7:15],
            'Wrong eight-token integer-reference case')
    revision=read(package/PREFIX/'source-revision.json')
    require(revision['schema']=='leaf-speed-source-revision-v1','Wrong revision schema')
    require(len(revision['changes'])==10,'Incomplete hardware/host revision chain')
    for name,change in revision['changes'].items():
        relative=PurePosixPath(name)
        require(not relative.is_absolute() and '..' not in relative.parts,'Unsafe revision path')
        restore_revision(pre_encrypted_bytes(package,name,(package/name).read_bytes()),change)
    native=read(package/PREFIX/'native.json')
    tool=read(package/PREFIX/'tool-provenance.json')
    require(set(tool['variants'])==set(IMAGES), 'Missing tool provenance')
    require(set(native['variants'])==set(IMAGES) and native['timing_qualified'] is False,'Wrong native scope')
    for variant,record in native['variants'].items():
        prebuilt='inference' if variant=='baseline' else 'kv-protected'
        check_build_provenance(record, tool)
        receipt_name='prebuilt/'+prebuilt+'/BUILD.json'
        receipt_raw=before_speed(package,receipt_name,(package/receipt_name).read_bytes())
        receipt=json.loads(receipt_raw)
        provenance=tool['variants'][variant]
        require(provenance['build_receipt']==receipt_name and
            provenance['build_receipt_sha256']==sha(receipt_raw) and
            provenance['image_sha256']==receipt['image_sha256']==IMAGES[variant] and
            provenance['original_build_receipt_sha256']==receipt['original_build_receipt_sha256'] and
            provenance['stdout_sha256']==receipt['stdout_sha256'], 'Changed build-provenance association')
        require(record['image_sha256']==IMAGES[variant] and record['endpoint_census_complete'] is True,
                'Incomplete native identity/census')
        require(record['nonvendor_screen_clear'] is True and record['timing_qualified'] is False,
                'Wrong timing scope')
        require(record['global_violated_endpoints']==({'setup':145,'hold':10} if variant=='baseline'
                    else {'setup':178,'hold':2}),'Unexpected selected timing result')
        require(record['mapped_multiplier_primitives']=={'MULTALU27X18':73,'MULT12X12':3},'Changed multiplier census')
        root='hardware/project/' if variant=='baseline' else 'variants/kv-protected/hardware/project/'
        for name,digest in record['production_sha256'].items():
            require(sha(before_speed(package,root+name,(package/root/name).read_bytes()))==digest,'Changed historical production source')
    metrics=read(package/PREFIX/'baseline-metrics.json')
    require(metrics['image_sha256']==IMAGES['baseline'],'Wrong capacity measurement image')
    for name,row in metrics['metrics'].items():
        observed=physical['variants']['baseline'][name]
        require(row['last_step_seconds']==observed['last_step_seconds'] and
                row['first_step_seconds_including_prompt_evaluation']==observed['first_step_seconds'],
                'Capacity input not the selected measurement')
    replay=read(package/PREFIX/'release-replay.json')
    check_replay(package,replay)
    rehearsed=check_rehearsal(package,read(package/PREFIX/'release-rehearsal.json'))
    return dict(passed=True,variants=2,measured_cases=12,reference_matching_outputs=outputs,
        selected_app_reference_matching_outputs=rehearsed,packaged_model_replays=4,
        additional_component_replays=4,
        source_revision_files=10,hardware_access=False,network_access=False,timing_qualified=False,
        scope=__doc__)


if __name__=='__main__':print(json.dumps(check(Path(__file__).resolve().parents[1]),indent=2,sort_keys=True))

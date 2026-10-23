#!/usr/bin/env python3
"""Check recorded seeded full-context frames against exact model goldens, offline.

This validates an archived finite FPGA campaign. To recompute the numerical
reference, use reference/seeded-sampling/run_reference.py separately. No device,
network, solver or numerical model is invoked by this checker.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
RECORD='evidence/seeded-sampling/full-context.json'
ARCHIVE_SHA='fa268181bd5866e6676a79a3b592401caf68262eeba04b64e236e2ac098104de'
INDEX_SHA='a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b'
SOURCE_PLAN_SHA='877e6ad7842e532013ee07e6529279e23910ee1ca3a5c40a38948d1ba39cab62'
SOURCE_RUNNER_SHA='3f242804a33431b36044c2c1b404f807990f3a1a02769277d43341ce56140294'
SOURCE_FINISHED_SHA='5949ab455e5c9db4e88dea77e09e1522168bc9903713728772c8eabd1a2e5565'
SOURCE_CONTINUATION_SHA='6272862d7311c5b73766b9a31f9668ee70b25c7eecfae7f51b490367122779bf'
CONTINUATION_CANONICAL_SHA='51a62cd583f25ff0f0dd8b9a61b234a4f3082c3d6d061c88a7e69079ef8a2f65'
PRIOR_PLAN_SHA='5f1095ad5826e33f6f65542d3f6a4346bc091bf23eeb3203bc1d9fa3da23e7cd'
PRIOR_FAILED_SHA='66a1d0cff8a757aad2125a78430b691e5907d0d79eef4b52e18287b224d14a8c'
PRIOR_PARTIAL_UART_SHA='cf867745761b074ac5952845d02bbf551f1698a957a3709255cab1a44b19cac8'
ORIGINAL_RUNNER_SHA='fa7f64d4fa1d0abf266aeffe5e47a70a6f69b313f00ec5c233a717345bdec926'
RETAINED_LABELS=['prefix128-t0-seed-a','prefix512-t0-seed-a','prefix2047-t0-seed-a']
PIN_SCOPE='38 continuation/original runners, transport, references, retained captures, prior failure and selected image files; not all 91 native inputs.'
CAPTURE_GROUPS=dict(retained_completed_original_cases=3,new_continuation_cases=13,incomplete_prior_cases_credited=0)
FAILURE_PROVENANCE=dict(failure_type='BrokenPipeError',case='prefix2048-t0-seed-a',
    source_plan_sha256=PRIOR_PLAN_SHA,source_failed_receipt_sha256=PRIOR_FAILED_SHA,
    source_partial_uart_sha256=PRIOR_PARTIAL_UART_SHA,source_runner_sha256=ORIGINAL_RUNNER_SHA,
    last_verified_response_kind=129,last_verified_token=15,last_verified_operation='long-step-1',
    final_clear_acknowledged_before_failure=False,incomplete_trial_credited=False,
    original_files_preserved=True,manual_continuation_after_investigation=True,partial_wire_is_provenance_only=True,
    scope='Host output pipe failed after the reference-matching first STEP. The incomplete case lacks final CLEAR/recovery and is rerun in full from initial CLEAR.')
IMAGE_SHA='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
INPUTS_SHA='26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831'
MODEL_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
TEMPS=('0','0.5','1','2')
SEED='0x99aabbccddeeff001122334455667788'
CASES={'prefix128':(128,128),'prefix512':(512,4),'prefix2047':(2047,2),'prefix2048':(2048,1)}

def need(ok,message):
    if not ok:raise ValueError(message)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def fields(value,names):need(type(value)is dict and set(value)==set(names.split()),'Unexpected context evidence fields')
def valid_digest(value):need(type(value)is str and re.fullmatch('[0-9a-f]{64}',value),'Invalid context origin digest')
def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def crc8(raw):
    value=0
    for byte in raw:
        value^=byte
        for _ in range(8):value=((value<<1)^(7 if value&128 else 0))&255
    return value
def frame(body):return (body+bytes((crc8(body),))).hex()
def legacy(opcode,operand=0):return frame(bytes((0xa5,opcode,operand&255,operand>>8)))
def reply(kind,operand=0):return frame(bytes((0x5a,kind,operand&255,operand>>8)))
def settings(code):return frame(bytes((0xa5,3,code))+int(SEED,0).to_bytes(16,'little'))
def positive(value):
    need(type(value)in(int,float) and math.isfinite(value) and value>0,'Invalid elapsed time')

def commands(reference,known,code):
    rows=[]
    def add(label,opcode,kind,operand=0,expected=0):rows.append((label,legacy(opcode,operand),kind,expected))
    def probe(label):
        add(label+'-clear',2,0x82);add(label+'-empty-step',1,0xc1);add(label+'-append',0,0x80,378)
        for i,token in enumerate(known):add(label+f'-step-{i+1}',1,0x81,expected=token)
    add('initial-clear',2,0x82);rows.append(('settings',settings(code),0x83,code))
    probe('before');add('long-clear',2,0x82)
    for i,token in enumerate(reference['prompt_tokens']):add(f'prompt-{i+1}',0,0x80,token)
    tape=len(reference['prompt_tokens'])
    for i,token in enumerate(reference['generated_tokens']):
        if tape==2048:add('input-limit-append-rejected',0,0xc0,378)
        add(f'long-step-{i+1}',1,0x81,expected=token);tape+=1
    if tape==2049:add('final-slot-append-rejected',0,0xc0,378);add('final-slot-step-rejected',1,0xc1)
    probe('after-1');probe('after-2');add('final-clear',2,0x82)
    return rows

def read_golden(package,name,index):
    need(name in index['files'] and '/'not in name,'Unknown reference path')
    raw=(package/'reference/seeded-sampling/goldens'/name).read_bytes()
    need(index['files'][name]==dict(bytes=len(raw),sha256=sha(raw)),'Changed golden bytes')
    row=json.loads(raw)
    need(row['schema']=='seeded-exact-model-golden-v1' and row['model_image_sha256']==MODEL_SHA,'Wrong reference model')
    return row,sha(raw)

def validate(data,package=ROOT):
    package=Path(package)
    fields(data,'schema passed cases source_finished_sha256 source_plan_sha256 source_runner_sha256 '
        'source_continuation_sha256 continuation investigated_failure capture_groups reference_source_audit '
        'campaign_pinned_file_count campaign_pin_scope final_greedy_wire final_greedy_source_uart_sha256 '
        'final_restoration_commands image_sha256 physical_fpga flash_modified configuration_independently_attested '
        'timing_qualified security_certified final_empty_greedy usb_released automatic_retries '
        'per_command_deadline_seconds oracle_replayed_by_archive_checker long_reference_outputs '
        'clear_replay_outputs total_reference_outputs hardware_inputs_sha256 model_image_sha256 '
        'all_four_temperatures_baseline_prompt_matrix_passed')
    need(data['schema']=='seeded-full-context-public-v2' and data['passed']is True,'Incomplete context record')
    need(data['image_sha256']==IMAGE_SHA and data['hardware_inputs_sha256']==INPUTS_SHA
         and data['model_image_sha256']==MODEL_SHA,'Changed circuit or model')
    need(all(data[k]is True for k in ('physical_fpga','final_empty_greedy','usb_released',
         'all_four_temperatures_baseline_prompt_matrix_passed')),'Missing physical campaign result')
    need(all(data[k]is False for k in ('flash_modified','configuration_independently_attested',
         'timing_qualified','security_certified','automatic_retries','oracle_replayed_by_archive_checker')),
         'Unsupported qualification claim')
    need(data['per_command_deadline_seconds']==3600,'Changed timeout scope')
    valid_digest(data['source_finished_sha256'])
    need(data['source_plan_sha256']==SOURCE_PLAN_SHA and data['source_runner_sha256']==SOURCE_RUNNER_SHA
         and data['source_continuation_sha256']==SOURCE_CONTINUATION_SHA,'Changed continuation capture provenance')
    if SOURCE_FINISHED_SHA is not None:
        need(data['source_finished_sha256']==SOURCE_FINISHED_SHA,'Changed physical completion provenance')
    need(data['campaign_pinned_file_count']==38 and data['campaign_pin_scope']==PIN_SCOPE,
         'Changed runtime source-pin scope')
    need(data['capture_groups']==CAPTURE_GROUPS and data['investigated_failure']==FAILURE_PROVENANCE,
         'Retained/new case census or preserved host-failure scope differs')
    continuation=data['continuation']
    need(sha(canonical(continuation))==CONTINUATION_CANONICAL_SHA,'Original continuation/audit record changed')
    need(continuation['schema']=='context-host-output-failure-continuation-v1'
         and continuation['prior_plan_sha256']==PRIOR_PLAN_SHA
         and continuation['prior_failed_sha256']==PRIOR_FAILED_SHA
         and continuation['prior_incomplete_uart_sha256']==PRIOR_PARTIAL_UART_SHA
         and continuation['prior_runner_sha256']==ORIGINAL_RUNNER_SHA
         and continuation['retained_complete_case_labels']==RETAINED_LABELS
         and continuation['incomplete_prior_case_credited']is False
         and continuation['remaining_cases_rerun_from_initial_clear']==13
         and continuation['failure_type']=='BrokenPipeError'
         and continuation['flash_modified']is False and continuation['automatic_retries']is False,
         'Unsupported continuation or prior-failure claim')
    need(data['final_restoration_commands']==3,'Changed final restoration census')
    need(data['reference_source_audit']=={
        'around-20261023-v1':dict(inputs_sha256='9dd0239a065dd5a6968d83fa28b932216e4b51b2d4f164f71b89591c51a7d9fa',
                                 checked_source_and_rom_files=18),
        'prefix-20261023-v1':dict(inputs_sha256='881f5b97ae2d99a82b1fef50d8051d7dfe29419a7cedd5c94a454d09f7f39cea',
                                 checked_source_and_rom_files=18)},'Original oracle source/ROM audit differs')
    need(re.fullmatch('[0-9a-f]{64}',data['final_greedy_source_uart_sha256'])is not None,
         'Invalid final restoration capture digest')
    need((data['long_reference_outputs'],data['clear_replay_outputs'],data['total_reference_outputs'])==(540,192,732),
         'Output census differs')
    baseline=json.loads((package/'evidence/read-window/references.json').read_bytes())
    index_raw=(package/'reference/seeded-sampling/goldens/INDEX.json').read_bytes()
    need(sha(index_raw)==INDEX_SHA,'Reference index bytes changed')
    index=json.loads(index_raw)
    need(index['cases']==48 and index['outputs']==2136,'Reference index differs')
    need(len(data['cases'])==16,'Missing context/temperature combination')
    total_commands=0
    for number,case in enumerate(data['cases']):
        fields(case,'label case temperature seed prompt_tokens generated_tokens all_generated_tokens_match_independent_reference '
            'source_reference_sha256 commands first_step_seconds cached_step_seconds clear_replay_tokens '
            'settings_applied_once replays_without_settings input_limit_append_rejected final_slot_append_and_step_rejected '
            'maximum_occupied_tape final_clear_acknowledged image_sha256 passed source_uart_sha256 reference_path '
            'reference_sha256 wire capture_origin capture_runner_sha256 source_case_receipt_sha256')
        code,which=divmod(number,4);name=list(CASES)[which];n,m=CASES[name]
        filename=f'{name}-t{code}-seed-a.json'
        reference,digest=read_golden(package,filename,index)
        known,_=read_golden(package,f'around128-t{code}-seed-a.json',index)
        need(known['case']=='around128' and known['temperature']==TEMPS[code] and known['seed']==SEED
             and known['prompt_tokens']==[378] and len(known['generated_tokens'])==128,
             'Recovery-probe reference dimensions/settings differ')
        need(reference['case']==name and reference['temperature']==TEMPS[code] and reference['seed']==SEED
             and reference['prompt_tokens']==baseline[name]['prompt_tokens']
             and len(reference['prompt_tokens'])==n and len(reference['generated_tokens'])==m,
             'Reference dimensions or exact baseline prompt differ')
        if code==0:need(reference['generated_tokens']==baseline[name]['generated_tokens'],'Greedy baseline differs')
        expected_runner=ORIGINAL_RUNNER_SHA if number<3 else SOURCE_RUNNER_SHA
        expected_origin='retained_completed_original_case'if number<3 else'new_continuation_case'
        need(case['capture_runner_sha256']==expected_runner and case['capture_origin']==expected_origin,
             'Per-case capture runner or retained/new origin differs')
        valid_digest(case['source_case_receipt_sha256']);valid_digest(case['source_uart_sha256'])
        if number<3:
            audit=continuation['prior_rechecks'][number]
            need(audit['case']==case['label'] and audit['physical_case_receipt_sha256']==case['source_case_receipt_sha256']
                 and audit['physical_uart_sha256']==case['source_uart_sha256'] and audit['passed']is True
                 and audit['raw_tx_rx_operation_sequence_verified']is True and audit['all_raw_crc_and_tokens_match']is True
                 and audit['final_clear_acknowledged']is True and audit['hardware_access']is False,
                 'Retained original case is not bound to its independent complete-case audit')
        need(case['label']==f'{name}-t{code}-seed-a' and case['case']==name
             and case['temperature']==TEMPS[code] and case['seed']==SEED,'Case order/settings differ')
        need(case['prompt_tokens']==reference['prompt_tokens'] and case['generated_tokens']==reference['generated_tokens'],
             'Observed tokens differ from independent reference')
        need(case['reference_path']=='reference/seeded-sampling/goldens/'+filename and case['reference_sha256']==digest
             and case['source_reference_sha256']==reference['source_reference_receipt_sha256'],
             'Reference provenance differs')
        need(case['image_sha256']==IMAGE_SHA and all(case[k]is True for k in ('passed',
             'all_generated_tokens_match_independent_reference','settings_applied_once','replays_without_settings',
             'final_clear_acknowledged')),'Missing exact reference/replay/CLEAR result')
        need(case['clear_replay_tokens']==12 and case['maximum_occupied_tape']==n+m
             and case['input_limit_append_rejected']is(n>=2047)
             and case['final_slot_append_and_step_rejected']is(n>=2047),'Boundary/replay scope differs')
        plan=commands(reference,known['generated_tokens'][:4],code)
        need(case['commands']==len(plan) and len(case['wire'])==3*len(plan)+1,'Wire census differs')
        previous=-1;durations=[]
        for i,(operation,tx,kind,operand)in enumerate(plan):
            triple=case['wire'][3*i:3*i+3]
            for seq,row in enumerate(triple,3*i+1):
                fields(row,'event operation frame_hex sequence elapsed_ns'if row['event']in('tx','rx')else
                       'event operation response_kind operand seconds sequence elapsed_ns')
                ns=row['elapsed_ns']
                need(type(ns)is int and ns>previous and (seq!=1 or ns==0) and row['sequence']==seq,'Invalid wire timeline')
                previous=ns
                need(row['operation']==operation,'Command order differs')
            sent,received,completed=triple
            need(sent['event']=='tx' and sent['frame_hex']==tx and received['event']=='rx'
                 and received['frame_hex']==reply(kind,operand),'Wire frame/CRC/rejection/token differs')
            need(completed['event']=='operation' and completed['response_kind']==kind and completed['operand']==operand,
                 'Reported command result differs')
            positive(completed['seconds'])
            need(abs(completed['seconds']-(completed['elapsed_ns']-sent['elapsed_ns'])/1e9)<.02,
                 'Duration disagrees with independent timeline')
            need(completed['seconds']<3600,'Command exceeded recorded deadline')
            if operation.startswith('long-step-'):durations.append(completed['seconds'])
        quiet=case['wire'][-1]
        need(quiet==dict(event='wire_quiet',operation='final-clear-drain',requested_seconds=.1,buffered_hex='',
             sequence=3*len(plan)+1,elapsed_ns=quiet['elapsed_ns'])
             and quiet['elapsed_ns']-previous>=90_000_000,'Missing final quiet/drain observation')
        need(case['first_step_seconds']==durations[0] and case['cached_step_seconds']==durations[1:],
             'First/cached token timing differs')
        total_commands+=len(plan)
    need(total_commands==19904,'Total command census differs')
    final=data['final_greedy_wire']
    final_plan=[('clear',legacy(2),0x82),
                ('settings',frame(bytes((0xa5,3,0))+bytes(16)),0x83),
                ('clear',legacy(2),0x82)]
    need(len(final)==10,'Final restoration wire census differs')
    previous=-1
    for i,(operation,tx,kind)in enumerate(final_plan):
        sent,received,completed=final[3*i:3*i+3]
        for seq,row in enumerate((sent,received,completed),3*i+1):
            fields(row,'event operation frame_hex sequence elapsed_ns'if row['event']in('tx','rx')else
                   'event operation response_kind operand seconds sequence elapsed_ns')
            need(row['sequence']==seq and type(row['elapsed_ns'])is int and row['elapsed_ns']>previous
                 and (seq!=1 or row['elapsed_ns']==0) and row['operation']==operation,
                 'Final restoration order/timeline differs')
            previous=row['elapsed_ns']
        need(sent['event']=='tx' and sent['frame_hex']==tx and received['event']=='rx'
             and received['frame_hex']==reply(kind) and completed['event']=='operation'
             and completed['response_kind']==kind and completed['operand']==0,
             'Final greedy SETTINGS/CLEAR frame differs')
        positive(completed['seconds'])
        need(abs(completed['seconds']-(completed['elapsed_ns']-sent['elapsed_ns'])/1e9)<.02,
             'Final restoration duration differs')
    quiet=final[-1]
    need(quiet==dict(event='wire_quiet',operation='final-clear-drain',requested_seconds=.1,buffered_hex='',
         sequence=10,elapsed_ns=quiet['elapsed_ns']) and quiet['elapsed_ns']-previous>=90_000_000,
         'Final restoration quiet/drain differs')
    return dict(passed=True,physical_cases=16,commands=total_commands,long_reference_outputs=540,
                clear_replay_outputs=192,total_reference_outputs=732,final_restoration_commands=3,temperatures=list(TEMPS),
                retained_completed_original_cases=3,new_continuation_cases=13,incomplete_prior_cases_credited=0,
                full_context_campaign_passed=True,hardware_access=False,oracle_replayed=False,
                timing_qualified=False,physical_configuration_attested=False)

def check(package=ROOT):
    need(all(type(pin)is str and re.fullmatch('[0-9a-f]{64}',pin)for pin in
         (ARCHIVE_SHA,SOURCE_FINISHED_SHA,SOURCE_PLAN_SHA,SOURCE_RUNNER_SHA,SOURCE_CONTINUATION_SHA)),
         'No completed physical context continuation has been pinned yet')
    package=Path(package);raw=(package/RECORD).read_bytes()
    result=validate(json.loads(raw),package)
    need(sha(raw)==ARCHIVE_SHA,'Frozen context archive changed')
    inputs=json.loads((package/'host-app/hardware-inputs-seeded-sampling.json').read_bytes())
    need(len(inputs)==91 and sha(canonical(inputs))==INPUTS_SHA,'Native inventory changed')
    for name,digest in inputs.items():
        path=package/'variants/seeded-sampling/hardware'/name
        if name.startswith('project/official/')and not path.exists():continue
        need(path.is_file() and not path.is_symlink() and sha(path.read_bytes())==digest,'Native input changed')
    for name,digest in [('prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs',IMAGE_SHA),
                        ('assets/board1-real-semantic-image2048.bin',MODEL_SHA)]:
        need(sha((package/name).read_bytes())==digest,'Image/model asset changed')
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(parser.parse_args().package),indent=2,sort_keys=True))

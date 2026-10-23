"""Synthetic full-context/continuation evidence mutations, without FPGA access.

All wire traces here are made in memory and never written as physical results.
The real archive/completion hash gate must remain closed until actual completion.
"""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('context_evidence_checker',HERE/'check_seeded_context.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
PACKAGE=HERE.parent
CONTINUATION=json.loads('{"automatic_retries":false,"failure_type":"BrokenPipeError","flash_modified":false,"incomplete_prior_case_credited":false,"prior_failed_sha256":"66a1d0cff8a757aad2125a78430b691e5907d0d79eef4b52e18287b224d14a8c","prior_incomplete_uart_sha256":"cf867745761b074ac5952845d02bbf551f1698a957a3709255cab1a44b19cac8","prior_plan_sha256":"5f1095ad5826e33f6f65542d3f6a4346bc091bf23eeb3203bc1d9fa3da23e7cd","prior_rechecks":[{"all_raw_crc_and_tokens_match":true,"audited_utc":"2026-10-23T06:31:37.778070+00:00","capacity_boundary_checked":false,"case":"prefix128-t0-seed-a","commands":281,"final_clear_acknowledged":true,"hardware_access":false,"long_outputs_compared":128,"passed":true,"physical_case_receipt_sha256":"55c2cf064164a24a7f53a4cceee075b7657595b8ee08518a4f778b123e279775","physical_configuration_attested":false,"physical_uart_sha256":"c9d616e88f920b54f93128c4911a4b6ba0a5f3b758087e1d7ad8f215701f4277","prompt_tokens":128,"public_comparator_sha256":"6cfa3906007dbcfa1f49e5f79ad2a622ba402cb6e6435d15ca4fa5a23ca64e27","public_reference_path":"reference/seeded-sampling/goldens/prefix128-t0-seed-a.json","public_reference_sha256":"e8e13774ee692ce2a7c233f8553508194f1a677436f2f4e454879a8afc6dba6a","raw_tx_rx_operation_sequence_verified":true,"recovery_outputs_compared":12,"replay_without_settings":true,"schema":"independent-live-context-case-audit-v1","scope":"This completed case only; no overall campaign pass inferred.","settings_applied_once":true},{"all_raw_crc_and_tokens_match":true,"audited_utc":"2026-10-23T06:31:37.787856+00:00","capacity_boundary_checked":false,"case":"prefix512-t0-seed-a","commands":541,"final_clear_acknowledged":true,"hardware_access":false,"long_outputs_compared":4,"passed":true,"physical_case_receipt_sha256":"d83312310f48fba177ec797c862d20914ebe2184e58fcfc01b78c49c647d8fdc","physical_configuration_attested":false,"physical_uart_sha256":"99029154a4800f9a43e6236c095a6db089a98ef9f4302db9fc55bf75632df7dd","prompt_tokens":512,"public_comparator_sha256":"6cfa3906007dbcfa1f49e5f79ad2a622ba402cb6e6435d15ca4fa5a23ca64e27","public_reference_path":"reference/seeded-sampling/goldens/prefix512-t0-seed-a.json","public_reference_sha256":"e27b7312917709dbc18f2b897da4cf3ac88e2a9188fdec2797d949a280f502f5","raw_tx_rx_operation_sequence_verified":true,"recovery_outputs_compared":12,"replay_without_settings":true,"schema":"independent-live-context-case-audit-v1","scope":"This completed case only; no overall campaign pass inferred.","settings_applied_once":true},{"all_raw_crc_and_tokens_match":true,"audited_utc":"2026-10-23T06:31:37.822079+00:00","capacity_boundary_checked":true,"case":"prefix2047-t0-seed-a","commands":2077,"final_clear_acknowledged":true,"hardware_access":false,"long_outputs_compared":2,"passed":true,"physical_case_receipt_sha256":"676531209d70562c18cca275841b9e54f465cc94b72380e20409d955302cef9a","physical_configuration_attested":false,"physical_uart_sha256":"2c040c94d305dfc4a8b42938703d3ad200d1aa12f305573dd3bce2e21616a64d","prompt_tokens":2047,"public_comparator_sha256":"6cfa3906007dbcfa1f49e5f79ad2a622ba402cb6e6435d15ca4fa5a23ca64e27","public_reference_path":"reference/seeded-sampling/goldens/prefix2047-t0-seed-a.json","public_reference_sha256":"76206692eb418e29428166cdd0d3f64b3e8a3f25103fefb9159a54dd05da2271","raw_tx_rx_operation_sequence_verified":true,"recovery_outputs_compared":12,"replay_without_settings":true,"schema":"independent-live-context-case-audit-v1","scope":"This completed case only; no overall campaign pass inferred.","settings_applied_once":true}],"prior_runner_sha256":"fa7f64d4fa1d0abf266aeffe5e47a70a6f69b313f00ec5c233a717345bdec926","remaining_cases_rerun_from_initial_clear":13,"retained_complete_case_labels":["prefix128-t0-seed-a","prefix512-t0-seed-a","prefix2047-t0-seed-a"],"schema":"context-host-output-failure-continuation-v1"}')


def frame(body):
    value=0
    for byte in body:
        value^=byte
        for _ in range(8):value=((value<<1)^7)&255 if value&128 else(value<<1)&255
    return(body+bytes((value,))).hex()
def tx(op,operand=0):return frame(bytes((0xa5,op,operand&255,operand>>8)))
def rx(kind,operand=0):return frame(bytes((0x5a,kind,operand&255,operand>>8)))
def setting(code,seed=int(c.SEED,16)):return frame(bytes((0xa5,3,code))+seed.to_bytes(16,'little'))


def contract_commands(prompt,outputs,known,code):
    # This independently spells out the fixed physical qualification contract.
    rows=[]
    def add(label,op,kind,operand=0,expected=0):rows.append((label,tx(op,operand),kind,expected))
    def replay(label):
        add(label+'-clear',2,0x82);add(label+'-empty-step',1,0xc1);add(label+'-append',0,0x80,378)
        for i,token in enumerate(known):add(f'{label}-step-{i+1}',1,0x81,expected=token)
    add('initial-clear',2,0x82);rows.append(('settings',setting(code),0x83,code));replay('before');add('long-clear',2,0x82)
    for i,token in enumerate(prompt):add(f'prompt-{i+1}',0,0x80,token)
    occupied=len(prompt)
    for i,token in enumerate(outputs):
        if occupied==2048:add('input-limit-append-rejected',0,0xc0,378)
        add(f'long-step-{i+1}',1,0x81,expected=token);occupied+=1
    if occupied==2049:add('final-slot-append-rejected',0,0xc0,378);add('final-slot-step-rejected',1,0xc1)
    replay('after-1');replay('after-2');add('final-clear',2,0x82)
    return rows


def synthetic_wire(commands):
    rows=[];ns=-100_000
    for operation,request,kind,operand in commands:
        ns+=100_000;rows.append(dict(event='tx',operation=operation,frame_hex=request,elapsed_ns=ns))
        ns+=20_000_000;rows.append(dict(event='rx',operation=operation,frame_hex=rx(kind,operand),elapsed_ns=ns))
        ns+=100_000;rows.append(dict(event='operation',operation=operation,response_kind=kind,operand=operand,
                                   seconds=.0201,elapsed_ns=ns))
    ns+=100_000_000;rows.append(dict(event='wire_quiet',operation='final-clear-drain',requested_seconds=.1,
                                   buffered_hex='',elapsed_ns=ns))
    for i,row in enumerate(rows,1):row['sequence']=i
    return rows


def synthetic():
    index=json.loads((PACKAGE/'reference/seeded-sampling/goldens/INDEX.json').read_bytes());cases=[]
    for code,temperature in enumerate(('0','0.5','1','2')):
        around=json.loads((PACKAGE/f'reference/seeded-sampling/goldens/around128-t{code}-seed-a.json').read_bytes())
        for name,n,m in(('prefix128',128,128),('prefix512',512,4),('prefix2047',2047,2),('prefix2048',2048,1)):
            number=len(cases);filename=f'{name}-t{code}-seed-a.json';path='reference/seeded-sampling/goldens/'+filename
            ref=json.loads((PACKAGE/path).read_bytes());commands=contract_commands(ref['prompt_tokens'],ref['generated_tokens'],around['generated_tokens'][:4],code)
            audit=CONTINUATION['prior_rechecks'][number]if number<3 else None
            cases.append(dict(label=f'{name}-t{code}-seed-a',case=name,temperature=temperature,seed=c.SEED,
                prompt_tokens=ref['prompt_tokens'],generated_tokens=ref['generated_tokens'],
                all_generated_tokens_match_independent_reference=True,
                source_reference_sha256=ref['source_reference_receipt_sha256'],commands=len(commands),
                first_step_seconds=.0201,cached_step_seconds=[.0201]*(m-1),clear_replay_tokens=12,
                settings_applied_once=True,replays_without_settings=True,input_limit_append_rejected=n>=2047,
                final_slot_append_and_step_rejected=n>=2047,maximum_occupied_tape=n+m,final_clear_acknowledged=True,
                image_sha256=c.IMAGE_SHA,passed=True,
                source_uart_sha256=audit['physical_uart_sha256']if audit else f'{number+100:064x}',
                source_case_receipt_sha256=audit['physical_case_receipt_sha256']if audit else f'{number+200:064x}',
                reference_path=path,reference_sha256=index['files'][filename]['sha256'],wire=synthetic_wire(commands),
                capture_origin='retained_completed_original_case'if number<3 else'new_continuation_case',
                capture_runner_sha256=c.ORIGINAL_RUNNER_SHA if number<3 else c.SOURCE_RUNNER_SHA))
    return dict(schema='seeded-full-context-public-v2',passed=True,cases=cases,
        source_finished_sha256=c.SOURCE_FINISHED_SHA or'f'*64,source_plan_sha256=c.SOURCE_PLAN_SHA,
        source_runner_sha256=c.SOURCE_RUNNER_SHA,source_continuation_sha256=c.SOURCE_CONTINUATION_SHA,
        continuation=copy.deepcopy(CONTINUATION),investigated_failure=dict(c.FAILURE_PROVENANCE),capture_groups=dict(c.CAPTURE_GROUPS),
        reference_source_audit={
            'around-20261023-v1':dict(inputs_sha256='9dd0239a065dd5a6968d83fa28b932216e4b51b2d4f164f71b89591c51a7d9fa',checked_source_and_rom_files=18),
            'prefix-20261023-v1':dict(inputs_sha256='881f5b97ae2d99a82b1fef50d8051d7dfe29419a7cedd5c94a454d09f7f39cea',checked_source_and_rom_files=18)},
        campaign_pinned_file_count=38,campaign_pin_scope=c.PIN_SCOPE,
        final_greedy_wire=synthetic_wire([('clear',tx(2),0x82,0),('settings',setting(0,0),0x83,0),('clear',tx(2),0x82,0)]),
        final_greedy_source_uart_sha256='e'*64,final_restoration_commands=3,image_sha256=c.IMAGE_SHA,
        physical_fpga=True,flash_modified=False,configuration_independently_attested=False,timing_qualified=False,
        security_certified=False,final_empty_greedy=True,usb_released=True,automatic_retries=False,
        per_command_deadline_seconds=3600,oracle_replayed_by_archive_checker=False,long_reference_outputs=540,
        clear_replay_outputs=192,total_reference_outputs=732,hardware_inputs_sha256=c.INPUTS_SHA,
        model_image_sha256=c.MODEL_SHA,all_four_temperatures_baseline_prompt_matrix_passed=True)


class ContextEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.base=synthetic()

    def test_complete_synthetic_contract_preserves_three_original_and_thirteen_new_cases(self):
        result=c.validate(copy.deepcopy(self.base),PACKAGE)
        self.assertEqual((result['commands'],result['total_reference_outputs']),(19904,732))
        self.assertEqual((result['retained_completed_original_cases'],result['new_continuation_cases']),(3,13))
        self.assertEqual(result['incomplete_prior_cases_credited'],0)
        self.assertFalse(result['hardware_access'])

    def test_real_archive_gate_refuses_before_physical_completion_pins(self):
        for missing in('ARCHIVE_SHA','SOURCE_FINISHED_SHA','SOURCE_PLAN_SHA','SOURCE_RUNNER_SHA','SOURCE_CONTINUATION_SHA'):
            pins={name:'0'*64 for name in('ARCHIVE_SHA','SOURCE_FINISHED_SHA','SOURCE_PLAN_SHA','SOURCE_RUNNER_SHA','SOURCE_CONTINUATION_SHA')}
            pins[missing]=None
            with self.subTest(missing=missing),patch.multiple(c,**pins),patch.object(Path,'read_bytes',side_effect=AssertionError('no archive I/O before gate')):
                with self.assertRaisesRegex(ValueError,'No completed physical context'):c.check(PACKAGE)

    def test_retained_new_and_failed_attempt_provenance_mutations_are_rejected(self):
        for mutation in('plan','runner','continuation-hash','completion','old-as-new','new-as-old','old-runner',
            'new-runner','old-case-receipt','old-raw','old-audit','partial-credited','failure-hidden','failure-token',
            'failure-wire-proof','new-count','runtime-count','oracle-source-count','private-field'):
            with self.subTest(mutation=mutation):
                data=copy.deepcopy(self.base)
                if mutation=='plan':data['source_plan_sha256']='0'*64
                elif mutation=='runner':data['source_runner_sha256']=c.ORIGINAL_RUNNER_SHA
                elif mutation=='continuation-hash':data['source_continuation_sha256']='0'*64
                elif mutation=='completion':data['source_finished_sha256']='0'*64
                elif mutation=='old-as-new':data['cases'][0]['capture_origin']='new_continuation_case'
                elif mutation=='new-as-old':data['cases'][3]['capture_origin']='retained_completed_original_case'
                elif mutation=='old-runner':data['cases'][0]['capture_runner_sha256']=c.SOURCE_RUNNER_SHA
                elif mutation=='new-runner':data['cases'][3]['capture_runner_sha256']=c.ORIGINAL_RUNNER_SHA
                elif mutation=='old-case-receipt':data['cases'][2]['source_case_receipt_sha256']='0'*64
                elif mutation=='old-raw':data['cases'][2]['source_uart_sha256']='0'*64
                elif mutation=='old-audit':data['continuation']['prior_rechecks'][0]['hardware_access']=True
                elif mutation=='partial-credited':data['continuation']['incomplete_prior_case_credited']=True
                elif mutation=='failure-hidden':data['investigated_failure']['failure_type']='none'
                elif mutation=='failure-token':data['investigated_failure']['last_verified_token']=16
                elif mutation=='failure-wire-proof':data['investigated_failure']['partial_wire_is_provenance_only']=False
                elif mutation=='new-count':data['capture_groups']['new_continuation_cases']=16
                elif mutation=='runtime-count':data['campaign_pinned_file_count']=91
                elif mutation=='oracle-source-count':data['reference_source_audit']['prefix-20261023-v1']['checked_source_and_rom_files']=17
                else:data['user_private_path']='/private/synthetic-not-a-real-path'
                with patch.object(c,'SOURCE_FINISHED_SHA',self.base['source_finished_sha256']):
                    with self.assertRaises(ValueError):c.validate(data,PACKAGE)

    def test_wire_cdf_reference_replay_and_capacity_mutations_are_rejected(self):
        for mutation in('token','seed','temperature','crc','capacity-append','capacity-step','missing-replay',
            'replay-settings','partial-case','extra-frame','nan','over-deadline','timeline','quiet',
            'final-greedy','unknown-row-field'):
            with self.subTest(mutation=mutation):
                data=copy.deepcopy(self.base);case=data['cases'][9];wire=case['wire']
                def row(event,label,rows=wire):return next(x for x in rows if x['event']==event and x['operation']==label)
                if mutation=='token':row('rx','long-step-2')['frame_hex']=rx(0x81,2)
                elif mutation=='seed':row('tx','settings')['frame_hex']=setting(2,int(c.SEED,16)^(1<<100))
                elif mutation=='temperature':row('tx','settings')['frame_hex']=setting(3)
                elif mutation=='crc':row('rx','long-step-1')['frame_hex']=rx(0x81,case['generated_tokens'][0])[:-2]+'00'
                elif mutation=='capacity-append':row('rx','input-limit-append-rejected',data['cases'][15]['wire'])['frame_hex']=rx(0x80)
                elif mutation=='capacity-step':row('rx','final-slot-step-rejected',data['cases'][15]['wire'])['frame_hex']=rx(0x81,15)
                elif mutation=='missing-replay':wire.pop(next(i for i,x in enumerate(wire)if x['operation']=='after-1-step-4'))
                elif mutation=='replay-settings':row('tx','after-1-clear')['frame_hex']=setting(2)
                elif mutation=='partial-case':data['cases'][3]['wire']=data['cases'][3]['wire'][:3*2059]
                elif mutation=='extra-frame':wire.append(copy.deepcopy(wire[-1]))
                elif mutation=='nan':row('operation','long-step-1')['seconds']=float('nan')
                elif mutation=='over-deadline':row('operation','long-step-1')['seconds']=3600
                elif mutation=='timeline':row('operation','long-step-1')['elapsed_ns']=0
                elif mutation=='quiet':wire[-1]['elapsed_ns']=wire[-2]['elapsed_ns']+50_000_000
                elif mutation=='final-greedy':data['final_greedy_wire'][3]['frame_hex']=setting(2)
                else:row('rx','long-step-1')['internal_read_edge_observed']=True
                with self.assertRaises(ValueError):c.validate(data,PACKAGE)


if __name__=='__main__':unittest.main(verbosity=2)

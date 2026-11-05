#!/usr/bin/env python3
"""Audit saved physical-test frames, grants, reference tokens and restoration."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import home_auth as h


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def crc(data):
    value=0
    for byte in data:
        value^=byte
        for _ in range(8):value=((value<<1)^0x07)&255 if value&128 else (value<<1)&255
    return value


def audit_common(c,benchmark,reference,review,reference_path):
    assert benchmark['passed'] and benchmark['timestamp_boundary']=='generation_loop_validated_reply'
    identity=benchmark['identity'];assert identity['fpga_image_sha256']==review['sha256']
    assert identity['clock_hz']==review['nominal_core_hz']
    assert identity['reference_sha256']==sha(reference_path)
    assert identity['model_image_sha256']==reference['image_sha256']
    assert identity['collector_sha256']==sha(c/'COMMON-COLLECTOR.py')
    assert reference['prompt_tokens']==[378] and reference['decoding']=='greedy'
    expected=reference['generated_tokens'];assert len(expected)==128
    assert len(benchmark['cases'])==2
    files=['COMMON-SPEED.json','COMMON-COLLECTOR.py','common-reference.json']
    durations=[];raw_hashes=[]
    for case in benchmark['cases']:
        assert case['prompt_tokens']==[378] and case['generated_tokens']==case['expected_tokens']==expected
        assert case['decoding']=='greedy' and case['temperature']==0
        assert case['clear_before'] and case['final_clear_acknowledged'] and case['feedback_dependent']
        assert not case['stop_at_eos'] and not case['observer_writes_during_trial']
        name=case['raw_capture'];assert Path(name).name==name
        raw_path=c/name;assert sha(raw_path)==case['raw_capture_sha256'];files.append(name);raw_hashes.append(sha(raw_path))
        raw=json.loads(raw_path.read_text());assert raw['timestamp_boundary']==benchmark['timestamp_boundary']
        events=raw['events'];assert len(events)==131
        ops=[(2,0,0),(0,378,0)]+[(1,0,t) for t in expected]+[(2,0,0)]
        prior=None
        for e,(op,token,wanted) in zip(events,ops):
            request=bytes.fromhex(e['request_hex']);response=bytes.fromhex(e['response_hex'])
            assert request[:4]==bytes([0xa5,op,token&255,token>>8]) and crc(request[:4])==request[4]
            assert response[:4]==bytes([0x5a,0x80+op,wanted&255,wanted>>8]) and crc(response[:4])==response[4]
            assert e['opcode']==op and e['input_token']==token and e['output_token']==wanted
            start=e['request_monotonic_ns'];end=e['validated_return_monotonic_ns'];assert start<=end
            if prior is not None:assert prior<=start
            prior=end
        outputs=events[2:130];origin=case['trial_started_monotonic_ns']
        assert case['reply_monotonic_ns']==[e['validated_return_monotonic_ns'] for e in outputs]
        elapsed=[(e['validated_return_monotonic_ns']-origin)/1e9 for e in outputs]
        steps=[(e['validated_return_monotonic_ns']-e['request_monotonic_ns'])/1e9 for e in outputs]
        assert case['reply_elapsed_seconds']==elapsed and case['step_seconds']==steps
        assert case['first_step_seconds']==steps[0] and case['cached_command_seconds']==steps[1:]
        durations.append(elapsed[-1]-elapsed[0])
    assert len(set(raw_hashes))==2
    elapsed=sum(durations);assert elapsed>0 and benchmark['counted_cached_outputs']==254
    assert benchmark['cached_host_seconds']==elapsed
    assert abs(benchmark['cached_tokens_per_second']-254/elapsed)<1e-9
    return elapsed,benchmark['cached_tokens_per_second'],files


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--campaign',type=Path,required=True)
    p.add_argument('--build',type=Path,required=True)
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--candidate',type=Path,default=ROOT/'prebuilt/home_product.fs')
    p.add_argument('--restored-image',type=Path,default=ROOT.parent/'signed-update/tang/prebuilt/swic_product.fs')
    a=p.parse_args();assert not a.output.exists()
    c=a.campaign
    result=json.loads((c/'RESULT.json').read_text())
    restored=json.loads((c/'RESTORED.json').read_text())
    common=(c/'COMMON-SPEED.json').exists()
    benchmark=json.loads((c/('COMMON-SPEED.json' if common else 'BENCHMARK.json')).read_text())
    recovery=json.loads((c/'RECOVERY.json').read_text())
    reference=json.loads(a.reference.read_text())
    review=json.loads((a.build/'REVIEW.json').read_text())
    assert result['result']==restored['result']=='PASS'
    if not common:assert benchmark['result']==reference['result']=='PASS'
    assert not (c/'FAILURE.json').exists()
    assert result['reconfiguration_fresh_nonce'] and result['old_grant_replay_blocked']
    assert not result['flash_write'] and not restored['flash_write'] and not recovery['flash_write']
    assert recovery['candidate_sha256']==review['sha256']==sha(a.candidate)
    assert recovery['review_sha256']==sha(a.build/'REVIEW.json')
    assert recovery['timing_review_sha256']==sha(a.build/'TIMING-REVIEW.json')
    assert recovery['simulation_qualification_sha256']==sha(a.build/'SIMULATION-QUALIFICATION.json')
    events=json.loads((c/'TRANSCRIPT.json').read_text())
    journal=[json.loads(line) for line in (c/'EVENTS.jsonl').read_text().splitlines()]
    assert events==journal, 'Final transcript differs from live event journal'
    assert all(events[i]['time']<=events[i+1]['time'] for i in range(len(events)-1))
    homes=[e for e in events if e['event']=='home-request']
    replies=[e for e in events if e['event']=='token-reply']
    replays=[e for e in events if e['event']=='old-grant-replay']
    assert len(replays)==1
    assert len({e['nonce'] for e in homes})==len(homes)==result['fresh_nonces']
    key=h.su.DemoAuthority(h.HOME_AUTHORITY).public_key
    for e in homes:
        request=bytes.fromhex(e['request_hex']);fields=h.parse_request(request)
        assert all(e[k]==v for k,v in fields.items())
        assert fields['device']==h.DEVICE_ID.hex() and fields['model_root']==recovery['model_root']
        if e['decision']=='approved':
            grant=bytes.fromhex(e['grant_hex'])
            assert len(grant)==h.GRANT_BYTES and grant[:128]==request
            assert h.su.lms_verify(key,request,grant[128:])
        else:assert e['decision']=='denied' and 'grant_hex' not in e
    approved=[e for e in homes if e['decision']=='approved']
    denied=[e for e in homes if e['decision']=='denied']
    assert len(approved)==result['approved_turns']>=2
    assert len(denied)==result['denied_turns']>=2
    leaf_indices=[int.from_bytes(bytes.fromhex(e['grant_hex'])[128:132],'big')for e in approved]
    assert len(set(leaf_indices))==len(leaf_indices),'LMS signing leaf reused within this campaign'
    assert max(e['time'] for e in approved)<min(e['time'] for e in denied)
    assert replays[0]['old_nonce']==approved[0]['nonce']
    assert replays[0]['fresh_nonce']==denied[-1]['nonce']!=approved[0]['nonce']
    for e in replies:
        raw=bytes.fromhex(e['frame_hex'])
        assert len(raw)==5 and raw[0]==0x5a and crc(raw[:4])==raw[4]
        assert raw[1]==e['status'] and int.from_bytes(raw[2:4],'little')==e['token']
        assert e['status'] in [0x80,0x81,0x82]
        assert e['time']>approved[0]['time'], 'Response before initial approval'
        assert e['time']<denied[0]['time'], 'Token response after deauthorization'
    step_events=[e for e in replies if e['status']==0x81]
    steps=[e['token'] for e in step_events]
    expected=reference['generated_tokens'] if common else reference['tokens']
    startup_count=result.get('startup_configurations_checked',0)
    if startup_count:
        startups=json.loads((c/'STARTUP-CONFIGURATIONS.json').read_text())
        assert startups['result']=='PASS'and startups['requested']==startup_count
        assert len(startups['configurations'])==startup_count and not startups['electrical_power_cycles']
        assert len({s['nonce']for s in startups['configurations']})==startup_count
        for s in startups['configurations']:
            assert s['nonce']in {e['nonce']for e in approved}
            observed=[e['token']for e in step_events if s['first_command_after']<=e['time']<=s['completed']]
            assert observed==s['tokens']==[108,32]
    assert steps==[108,32]*startup_count+[108,32]+expected*(2 if common else 1)
    context=step_events[2*startup_count:2*startup_count+2]
    assert any(context[0]['time']<e['time']<context[1]['time'] for e in approved), 'No observed renewal between context-preservation tokens'
    idle_checked=False
    if(c/'IDLE-RENEWAL.json').exists():
        idle=json.loads((c/'IDLE-RENEWAL.json').read_text());assert idle['result']=='PASS'
        assert idle.get('application_commands_since_configuration',idle.get('application_commands_sent'))==0
        first_idle=next(e for e in approved if e['nonce']==idle['first_nonce'])
        renewal_idle=next(e for e in approved if e['nonce']==idle['renewal_nonce'])
        assert first_idle['time']<renewal_idle['time']
        assert not any(first_idle['time']<=e['time']<=renewal_idle['time']for e in replies)
        idle_checked=True
    if common:
        seconds,rate,benchmark_files=audit_common(c,benchmark,reference,review,a.reference)
    else:
        assert benchmark['tokens']==reference['tokens'] and benchmark['prompt']==reference['prompt']==[1]
        assert benchmark['outputs']==len(benchmark['tokens'])==128 and benchmark['sampling']=='greedy'
        assert benchmark['reference_sha256']==sha(a.reference)
        assert abs(benchmark['tokens_per_second']-128/benchmark['wall_seconds'])<1e-9
        timing=benchmark['timings'];assert len(timing)==128
        for i,t in enumerate(timing):
            assert t['index']==i and 0<=t['command_start']<=t['response_end']<=benchmark['wall_seconds']
            if i:assert timing[i-1]['response_end']<=t['command_start']
        assert benchmark['wall_seconds']-timing[-1]['response_end']<0.01
        seconds,rate,benchmark_files=benchmark['wall_seconds'],benchmark['tokens_per_second'],['BENCHMARK.json']
    for name in ['baseline-before.json','baseline-after.json']:
        b=json.loads((c/name).read_text());assert b['result']=='PASS' and b['expected']==[108,32]
        assert [t['output_token'] for t in b['transactions'] if t['opcode']==1]==[108,32]
        for t in b['transactions']:
            raw=bytes.fromhex(t['response_hex']);assert crc(raw[:4])==raw[4]
    files=['RESULT.json','RESTORED.json','RECOVERY.json','TRANSCRIPT.json',
           'EVENTS.jsonl','RUNNER-SOURCE.py','HOST-SOURCES.json','baseline-before.json','baseline-after.json']+benchmark_files
    if startup_count:files.append('STARTUP-CONFIGURATIONS.json')
    if idle_checked:files.append('IDLE-RENEWAL.json')
    programmer_calls=[]
    for path in sorted(c.glob('*.command.json')):
        command=json.loads(path.read_text());args=command['command']
        if Path(args[0]).name!='programmer_cli':continue
        assert command['exit_code']==0
        operation=args[args.index('--operation_index')+1];assert operation in ['0','2']
        if operation=='2':
            image=a.candidate;expected_sha=review['sha256']
            if path.name=='restore-sawic.command.json':image=a.restored_image;expected_sha='4545bd0b0c4076eaea8358d547b19ff0176952417daa0e0f07d1c346aee5fee2'
            assert sha(image)==expected_sha
            log=path.with_name(path.name.replace('.command.json','.log'))
            assert 'Finished'in log.read_text()
            files.append(log.name)
        programmer_calls.append(path.name);files.append(path.name)
    assert 'load-home-variant.command.json'in programmer_calls and 'restore-sawic.command.json'in programmer_calls
    if startup_count:
        assert all(f'startup-reload-{i}.command.json'in programmer_calls for i in range(2,startup_count+1))
    record={'result':'PASS','candidate_sha256':review['sha256'],'home_requests':len(homes),
            'valid_grants':len(approved),'denied_requests':len(denied),'distinct_nonces':len(homes),
            'token_reply_frames_checked':len(replies),'reference_matched_steps':len(steps),
            'benchmark_tokens':256 if common else 128,'benchmark_seconds':seconds,
            'benchmark_counted_outputs':254 if common else 128,
            'benchmark_metric':'paired_cached_generation' if common else 'complete_first_step_to_last_reply',
            'benchmark_tokens_per_second':rate,
            'restored_baseline_verified':True,'source_hashes':{name:sha(c/name) for name in files},
            'startup_configurations_checked':startup_count,'passive_renewal_checked':idle_checked,
            'unique_lms_leaf_indices':leaf_indices,'programmer_commands_checked':programmer_calls,
            'scope':'Offline audit of saved host observations and real LMS grants. Rechecks CRCs, model binding, fresh nonces, token reference and restoration; not physical attestation, entropy certification or universal command-stream proof.'}
    a.output.write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({k:v for k,v in record.items() if k!='source_hashes'},indent=2))


if __name__=='__main__':main()

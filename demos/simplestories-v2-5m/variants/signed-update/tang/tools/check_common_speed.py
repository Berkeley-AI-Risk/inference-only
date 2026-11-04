#!/usr/bin/env python3
"""Replay common-speed UART frames, reference IDs and caller timestamps offline."""
from pathlib import Path
import argparse,hashlib,json,math

def need(value,message):
    if not value:raise ValueError(message)

def crc8(data):
    crc=0
    for b in data:
        crc^=b
        for _ in range(8):crc=((crc<<1)^7)&255 if crc&128 else (crc<<1)&255
    return crc

def verify_case(case,raw,expected):
    events=raw['events'];need(len(events)==131,'Expected 131 UART transactions')
    need(raw['timestamp_boundary']=='generation_loop_validated_reply','Wrong timing boundary')
    operations=[2,0]+[1]*128+[2];inputs=[0,378]+[0]*129;outputs=[0,0]+expected+[0]
    for i,(event,op,input_token,output_token) in enumerate(zip(events,operations,inputs,outputs)):
        tx=bytes.fromhex(event['request_hex']);rx=bytes.fromhex(event['response_hex'])
        need(tx[:4]==bytes([0xa5,op,input_token&255,input_token>>8]) and len(tx)==5 and tx[4]==crc8(tx[:4]),'Wrong request frame')
        need(rx[:4]==bytes([0x5a,0x80+op,output_token&255,output_token>>8]) and len(rx)==5 and rx[4]==crc8(rx[:4]),'Wrong response/reference frame')
        need(event['opcode']==op and event['input_token']==input_token and event['output_token']==output_token,'Frame/transaction disagreement')
        need(type(event['request_monotonic_ns']) is int and type(event['validated_return_monotonic_ns']) is int
             and event['validated_return_monotonic_ns']>event['request_monotonic_ns'],'Invalid monotonic timestamps')
        if i:need(event['request_monotonic_ns']>=events[i-1]['validated_return_monotonic_ns'],'Overlapping transactions')
    steps=events[2:130];arrivals=[e['validated_return_monotonic_ns'] for e in steps]
    durations=[(e['validated_return_monotonic_ns']-e['request_monotonic_ns'])/1e9 for e in steps]
    origin=case['trial_started_monotonic_ns']
    need(events[1]['validated_return_monotonic_ns']<=origin<=steps[0]['request_monotonic_ns'],'Wrong timing origin')
    need(case['reply_monotonic_ns']==arrivals and case['reply_elapsed_seconds']==[(x-origin)/1e9 for x in arrivals],'Raw/canonical caller timestamps differ')
    need(case['step_seconds']==durations and case['cached_command_seconds']==durations[1:] and case['first_step_seconds']==durations[0],'Raw/canonical STEP durations differ')
    need(case['prompt_tokens']==[378] and case['generated_tokens']==case['expected_tokens']==expected,'Wrong common reference IDs')
    need(case['decoding']=='greedy' and case['temperature']==0 and case['clear_before'] is True
         and case['final_clear_acknowledged'] is True and case['stop_at_eos'] is False
         and case['feedback_dependent'] is True,'Changed decoding/feedback policy')
    return {'cached_outputs':127,'cached_host_seconds':(arrivals[-1]-arrivals[0])/1e9,
            'first_step_seconds':durations[0]}

def verify(root,capture_dir):
    root=Path(root);capture_dir=Path(capture_dir);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    result=json.loads((capture_dir/'FINISHED.json').read_text())
    ref=json.loads((capture_dir/'reference.json').read_text());identity=result['identity']
    need(ref['output_count']==128 and ref['prompt_tokens']==[378] and len(ref['generated_tokens'])==128,'Wrong reference workload')
    for name,pin in ref['source_sha256'].items():
        need(not Path(name).is_absolute() and '..' not in Path(name).parts,'Unsafe reference source path')
        p=root.parents[2]/name[5:] if name.startswith('demo/') else root/name
        need(sha(p)==pin,'Changed numerical reference source')
    need(identity['reference_sha256']==sha(capture_dir/'reference.json'),'Changed reference record')
    need(identity['fpga_image_sha256']==sha(root/'prebuilt/swic_product.fs'),'Different FPGA image')
    need(identity['model_image_sha256']==ref['image_sha256']==sha(root.parents[2]/'assets/board1-real-semantic-image2048.bin'),'Different model image')
    need(identity['collector_sha256']==sha(root/'tools/collect_common_speed.py') and identity['uart_client_sha256']==sha(root/'tools/uart_check.py'),'Changed collection source')
    need(identity['board_result_sha256']==sha(root/'evidence/board/RESULT.json'),'Different physical qualification')
    board=json.loads((root/'evidence/board/RESULT.json').read_text())
    base=next(c for c in board['cases'] if c['case']=='base')
    need(identity['clock_hz']==25000000 and identity['variant']=='S-AWIC'
         and identity['admission_slot_sha256']==base['admission_slot_sha256'],'Different configured clock or admitted fixture')
    need(result['schema']=='fpga-common-speed-capture-v1' and result['protocol']=='greedy-one-token-128-host-v1'
         and result['timestamp_boundary']=='generation_loop_validated_reply','Wrong capture protocol')
    need([c['name'] for c in result['cases']]==['one-token-128-trial1','one-token-128-trial2'],'Wrong or missing repetitions')
    rows=[];raw_hashes=[]
    for c in result['cases']:
        p=capture_dir/c['raw_capture'];need(p.parent==capture_dir,'Unsafe raw capture path')
        raw_hashes.append(sha(p));need(raw_hashes[-1]==c['raw_capture_sha256'],'Changed raw capture')
        rows.append(verify_case(c,json.loads(p.read_text()),ref['generated_tokens']))
    need(len(set(raw_hashes))==2,'Reused capture')
    duration=math.fsum(r['cached_host_seconds'] for r in rows);rate=254/duration
    need(result['counted_cached_outputs']==254 and math.isclose(rate,result['cached_tokens_per_second'],rel_tol=1e-12),'Wrong pooled rate')
    return {'result':'PASS','trials':2,'validated_outputs':256,'uart_transactions':262,
            'cached_outputs':254,'cached_host_seconds':duration,'cached_tokens_per_second':rate,
            'raw_capture_sha256':raw_hashes,'reference_sha256':sha(capture_dir/'reference.json'),
            'source_sha256':sha(Path(__file__)),'hardware_access':False}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture',required=True,type=Path);a=p.parse_args()
    print(json.dumps(verify(Path(__file__).resolve().parents[1],a.capture),indent=2))

if __name__=='__main__':main()

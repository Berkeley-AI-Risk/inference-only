# SPDX-License-Identifier: Apache-2.0
"""Verify the two recorded TLM26 variants; read-only and standard-library only."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
R=None
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def pin(p):return {'bytes':p.stat().st_size,'sha256':sha(p)}

def read(p):return json.loads(p.read_text())

def crc(b):
    c=0
    for v in b:
        c^=v
        for _ in range(8):c=((c<<1)^(7 if c&128 else 0))&255
    return c

def frame(m,k,t):
    b=bytes([m,k,t&255,t>>8]);return (b+bytes([crc(b)])).hex()

def audit(row):
    cap=read(R/row['source']);folder=(R/row['source']).parent
    g=read(folder/'golden.json');expected=g['integer_reference_ids']
    assert expected==g['fp32_checkpoint_ids'] and len(expected)==128
    assert g['input_ids']==[1] and g['stop_at_eos'] is False
    identity=cap['identity'];assert row['identity']==identity
    assert identity['reference_sha256']==sha(folder/'golden.json')
    assert identity['model_sha256']==g['staged_int16_image_sha256']
    assert identity['checkpoint_sha256']==g['checkpoint_sha256']==cap['source_checkpoint_sha256']
    assert identity['semantic_clock_hz']==12500000 and identity['core_clock_mhz']==12.5
    assert identity['first_return_hold_cycles']==250000 and identity['first_return_hold_ms']==20
    route=read(R/row['route_source'])
    assert cap['bitstream_sha256']==identity['fpga_image_sha256']==route['programming_files']['tlm26.fs']
    assert route['requested_clock_mhz']['semantic']==12.5
    spans=[];firsts=[];raws=[]
    for i,c in enumerate(cap['cases'],1):
        p=folder/f'trial-{i}.json';r=read(p);raws.append(sha(p))
        assert sha(p)==c['raw_capture_sha256']
        assert r['result']=={k:v for k,v in c.items() if k not in ['name','raw_capture_sha256']}
        assert c['generated_tokens']==c['expected_tokens']==expected
        assert c['decoding']=='greedy' and c['temperature']==0 and c['prompt_tokens']==[1]
        assert c['feedback_dependent'] and c['clear_before'] and c['final_clear_acknowledged']
        assert c['stop_at_eos'] is False and c['observer_writes_during_trial'] is False
        events=r['uart_events'];script=[(2,0,130,0),(0,1,128,0)]+[(1,0,129,t) for t in expected]+[(2,0,130,0)]
        assert len(events)==len(script)==131
        for e,(op,t,k,w) in zip(events,script):
            assert e['tx']==frame(165,op,t) and e['rx']==frame(90,k,w)
            assert type(e['start_ns']) is int and type(e['validated_ns']) is int and e['validated_ns']>e['start_ns']
        assert all(b['start_ns']>=a['validated_ns'] for a,b in zip(events,events[1:]))
        steps=events[2:130];arr=[e['validated_ns'] for e in steps];dur=[e['validated_ns']-e['start_ns'] for e in steps]
        assert arr==c['reply_monotonic_ns'] and dur==c['step_elapsed_ns']
        assert c['cached_command_seconds']==[x/1e9 for x in dur[1:]]
        span=arr[-1]-arr[0];assert span==c['cached_first_to_last_ns'] and span>=sum(dur[1:])
        assert c['first_step_seconds']==dur[0]/1e9
        assert abs((c['reply_elapsed_seconds'][-1]-c['reply_elapsed_seconds'][0])*1e9-span)<1
        spans.append(span);firsts.append(dur[0])
    assert len(set(raws))==2 and len(cap['cases'])==2
    for k in ['owner_current_program_log','owner_current_load_receipt']:
        ref=identity[k];p=R/ref['path'];assert sha(p)==ref['sha256']
        if p.suffix=='.gz':
            raw=gzip.decompress(p.read_bytes());assert len(raw)==ref['uncompressed_bytes'] and hashlib.sha256(raw).hexdigest()==ref['uncompressed_sha256']
    loaded=read(folder/'custody/model-load.json')
    assert (loaded['acknowledged_pages'],loaded['bytes'],loaded['sha256'])==(768,3145728,identity['model_sha256'])
    restored=read(folder/'RESTORATION.json');assert restored['restored'] and restored['baseline_before']==restored['baseline_after']==[108,32]
    assert restored['flash_programming_operations']==0
    ref=restored['programming_transcript'];p=R/ref['path'];assert pin(p)=={k:ref[k] for k in ['bytes','sha256']}
    raw=gzip.decompress(p.read_bytes());assert len(raw)==ref['uncompressed_bytes'] and hashlib.sha256(raw).hexdigest()==ref['uncompressed_sha256']
    assert pin(folder/'custody/baseline-after.json')==restored['baseline_after_receipt']
    rate=254e9/sum(spans);review=read(folder/'REVIEW.json')
    assert abs(rate-review['pooled_cached_tokens_per_second'])<1e-12
    return {'id':row['id'],'accepted':True,'rate':rate,'per_trial_rates':[127e9/x for x in spans],
            'trial_spans_ns':spans,'first_STEP_ns':firsts,'raw_trial_sha256':raws,
            'all_256_IDs_and_262_command_reply_pairs_checked':True,'physical_boundary':'generation_loop_validated_reply'}

def main():
    global R
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[4])
    args=ap.parse_args();R=args.package.resolve()
    selection=read(R/'benchmarks/fpga-speed/selection.json')
    rows=[next(r for r in selection['rows'] if r['id']==name) for name in ['tlm26-moe','tlm26-moe-overlap-r2']]
    for row in rows:
        for name in ['source','route_source','evidence_review']:
            assert pin(R/row[name])==selection['sources'][row[name]]
    checked=[audit(row) for row in rows]
    assert len({h for x in checked for h in x['raw_trial_sha256']})==4
    assert abs(checked[0]['rate']-1.612038176875166)<1e-12
    assert abs(checked[1]['rate']-3.097428714761486)<1e-12
    parser=R/'tools/fpga_speed_benchmark.py'
    assert sha(parser)=='9ef4dbc85db2dcf987e01f8414259ef623382585a178a38a905d93ccfb945c2d'
    spec=importlib.util.spec_from_file_location('common_reader',parser)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    for row,review in zip(rows,checked):
        pooled=m.pool(m.selected_trials(row,{row['source']:read(R/row['source'])},None))
        assert abs(pooled['cached_tokens_per_second']-review['rate'])<1e-12
    print(json.dumps({'accepted':True,'variants':checked,'hardware_access':False,'network_access':False,'writes':False}))
if __name__=='__main__':main()

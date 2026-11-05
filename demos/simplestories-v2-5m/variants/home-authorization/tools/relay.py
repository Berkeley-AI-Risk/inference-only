#!/usr/bin/env python3
"""Relaying CLI with optional reference-checked token commands; does not program the FPGA."""
from pathlib import Path
import argparse,json,sys,time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'reference'));sys.path.insert(0,str(ROOT/'integration'))
from serial_client import AuthorizedSerial,BackgroundAuthorization
from common_speed import collect_trial,BOUNDARY
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--device',required=True);p.add_argument('--url',default='http://127.0.0.1:8765/authorize')
p.add_argument('--model-root',required=True);p.add_argument('--output',type=Path,required=True)
p.add_argument('--reference',type=Path,help='Run the common paired benchmark against this 128-token numerical reference')
p.add_argument('--smoke',action='store_true',help='Run base model prompt 1 and verify 108,32')
a=p.parse_args();assert not(a.reference and a.smoke)
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
assert len(bytes.fromhex(a.model_root))==32
client=AuthorizedSerial(a.device,a.url,a.model_root,grant_chunk_bytes=16,grant_chunk_pause=.003)
relay=None
try:
 relay=BackgroundAuthorization(client)
 print('Relay open. Load the SRAM image from a separate terminal now.',flush=True)
 first=relay.next_home(180)
 if first['decision']!='approved':raise RuntimeError('Home base denied this model')
 print('Approval relayed. Hardware checks the signature before permitting inference.',flush=True)
 window_nonce=None;window_start=0
 def wait_window():
  global window_nonce,window_start
  until=time.monotonic()+15
  while time.monotonic()<until:
   if relay.failure:raise RuntimeError('Relay failed')from relay.failure
   events=[e for e in client.events if e['event']=='home-request']
   if events:
    latest=events[-1]
    if latest['decision']!='approved':raise RuntimeError('Model permission denied')
    if latest['nonce']!=window_nonce:window_nonce=latest['nonce'];window_start=time.monotonic()+.5
    now=time.monotonic()
    if window_start<=now<latest['time']+4.5:return
   time.sleep(.005)
  raise TimeoutError('No safe command window')
 if a.smoke:
  for op,token,expected in [(2,0,0),(0,1,0),(1,0,108),(1,0,32),(2,0,0)]:
   wait_window();relay.command(op,token,expected=expected)
  print('PASS base-model outputs 108,32; CLEAR acknowledged.',flush=True)
 elif a.reference:
  reference=json.loads(a.reference.read_text())
  assert reference['prompt_tokens']==[378]and reference['decoding']=='greedy'and len(reference['generated_tokens'])==128
  cases=[]
  for i in [1,2]:
   case,events=collect_trial(relay,wait_window,reference['generated_tokens'])
   name=f'trial-{i}-raw.json';(out/name).write_text(json.dumps({'timestamp_boundary':BOUNDARY,'events':events},indent=2)+'\n')
   cases.append(case)
  duration=sum(c['reply_elapsed_seconds'][-1]-c['reply_elapsed_seconds'][0]for c in cases)
  (out/'MEASUREMENT.json').write_text(json.dumps({'cases':cases,'cached_outputs':254,'cached_seconds':duration,'tokens_per_second':254/duration,'renewal_gaps_included':True,'scope':'Fresh relay measurement; retain separate programmer/model/source identities before admitting a new overview-table row.'},indent=2)+'\n')
  print(json.dumps({'tokens_per_second':254/duration}),flush=True)
 else:
  print('Relaying renewals until interrupted or denied.',flush=True)
  while True:
   event=relay.next_home(15);print(json.dumps(event),flush=True)
   if event['decision']!='approved':raise RuntimeError('Home base withdrew model permission')
 (out/'RESULT.json').write_text(json.dumps({'result':'PASS','automatic_retry':False,'flash_write':False})+'\n')
except BaseException as exc:
 (out/'FAILURE.json').write_text(json.dumps({'type':type(exc).__name__,'message':str(exc),'automatic_retry':False})+'\n')
 raise
finally:
 try:
  if relay:relay.close()
  else:client.close()
 finally:(out/'EVENTS.json').write_text(json.dumps(client.events,indent=2)+'\n')

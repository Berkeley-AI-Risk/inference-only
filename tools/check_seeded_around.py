#!/usr/bin/env python3
"""Check eight archived around128 baseline-style control trials, offline.

Separate from the published benchmark. Full wire/reference comparisons and
12 probe outputs per case do not establish timing or whole-machine security.
No archive is accepted before actual completion hashes are reviewed and pinned.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
RECORD='evidence/seeded-sampling/around-control.json'
ARCHIVE_SHA='2723c71d481f9ae4226d3b22f9015036f35ccd5e142ea0c7714d3d80e5fc6b17'
SOURCE_PLAN_SHA='f311768086593c913db8c80a28fe1ad10d677168e8cb85e4d90c8e8059e0090a'
SOURCE_FINISHED_SHA='0bb5bb75163adf3c44a548b02b12863db129210ebfa45a07d91ee3cef5f1958a'
SOURCE_RUNNER_SHA='78ee824d4cf6b0db8b887c9280fb5e2099b29dd19098c3ebfa2ce1c8bceb9ccd'
ORIGINAL_SHA='fa7f64d4fa1d0abf266aeffe5e47a70a6f69b313f00ec5c233a717345bdec926'
REFERENCE_SHA='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
INDEX_SHA='a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b'
INPUTS_SHA='26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831'
IMAGE_SHA='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
MODEL_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
SEED='0x99aabbccddeeff001122334455667788'
TEMPS=('0','0.5','1','2')
PIN_SCOPE='21 runner, transport, source-inventory, reference and selected image files; not all 91 native inputs.'
CLAIMS=dict(physical_fpga=True,final_empty_greedy=True,usb_released=True,flash_modified=False,
    automatic_retries=False,configuration_independently_attested=False,timing_qualified=False,
    security_certified=False,benchmark_receipts_unchanged=True,oracle_replayed_by_archive_checker=False)

def need(ok,message):
    if not ok:raise ValueError(message)
def fields(value,names):need(type(value)is dict and set(value)==set(names.split()),'Unexpected around-control fields')
def sha(raw):return hashlib.sha256(raw).hexdigest()
def digest(value):need(type(value)is str and re.fullmatch('[0-9a-f]{64}',value)is not None,'Invalid around origin digest')
def crc8(raw):
    value=0
    for byte in raw:
        value^=byte
        for _ in range(8):value=((value<<1)^(7 if value&128 else 0))&255
    return value
def frame(body):return(body+bytes([crc8(body)])).hex()
def legacy(op,token=0):return frame(bytes([0xa5,op,token&255,token>>8]))
def reply(kind,token=0):return frame(bytes([0x5a,kind,token&255,token>>8]))
def settings(code,seed=int(SEED,16)):return frame(bytes([0xa5,3,code])+seed.to_bytes(16,'little'))
def regular(path):
    path=Path(path);need(path.is_file()and not path.is_symlink(),'Nonregular around-control input');return path.read_bytes()
def duration(value):need(type(value)in(int,float)and math.isfinite(value)and 0<value<120,'Invalid around command duration')

def references(package=ROOT):
    package=Path(package);lane=package/'reference/seeded-sampling'
    need(sha(regular(lane/'SOURCE.json'))==REFERENCE_SHA,'Portable reference inventory changed')
    raw=regular(lane/'goldens/INDEX.json');need(sha(raw)==INDEX_SHA,'Around golden index changed')
    index=json.loads(raw);refs={}
    for code in range(4):
        name=f'around128-t{code}-seed-a.json';path='reference/seeded-sampling/goldens/'+name;raw=regular(package/path)
        need(index['files'][name]==dict(bytes=len(raw),sha256=sha(raw)),'Around golden bytes changed')
        row=json.loads(raw)
        need(row['schema']=='seeded-exact-model-golden-v1'and row['case']=='around128'
             and row['temperature']==TEMPS[code]and row['seed']==SEED and row['prompt_tokens']==[378]
             and len(row['generated_tokens'])==128 and row['model_image_sha256']==MODEL_SHA,
             'Around golden model/settings/dimensions differ')
        refs[code]=(row,path,sha(raw))
    source=json.loads(regular(lane/'SOURCE.json'))
    need(sha(regular(lane/'compare_board.py'))==source['files']['compare_board.py'],'Independent comparator changed')
    spec=importlib.util.spec_from_file_location('_around_independent_wire_comparator',lane/'compare_board.py')
    comparator=importlib.util.module_from_spec(spec);spec.loader.exec_module(comparator)
    return refs,comparator

def labels():
    def probe(name):return[name+'-clear',name+'-empty-step',name+'-append']+[name+f'-step-{i}'for i in range(1,5)]
    return ['initial-clear','settings']+probe('before')+['long-clear','prompt-1']+[
        f'long-step-{i}'for i in range(1,129)]+probe('after-1')+probe('after-2')+['final-clear']

def validate_wire(rows,commands):
    need(type(rows)is list and len(rows)==3*len(commands)+1,'Around wire census differs')
    previous=-1;durations=[]
    for i,(label,tx,rx)in enumerate(commands):
        sent,received,op=rows[3*i:3*i+3]
        for n,row in enumerate((sent,received,op),3*i+1):
            need(row['sequence']==n and type(row['elapsed_ns'])is int and row['elapsed_ns']>previous
                 and(n!=1 or row['elapsed_ns']==0)and row['operation']==label,'Around wire order/timeline differs')
            previous=row['elapsed_ns']
        fields(sent,'event operation frame_hex sequence elapsed_ns');fields(received,'event operation frame_hex sequence elapsed_ns')
        fields(op,'event operation response_kind operand seconds sequence elapsed_ns')
        need(sent['event']=='tx'and sent['frame_hex']==tx and received['event']=='rx'and received['frame_hex']==rx,
             'Around frame/CRC/seed/reference/rejection differs')
        packet=bytes.fromhex(rx)
        need(op['event']=='operation'and op['response_kind']==packet[1]and op['operand']==packet[2]|packet[3]<<8,
             'Around operation disagrees with actual reply')
        duration(op['seconds'])
        need(abs(op['seconds']-(op['elapsed_ns']-sent['elapsed_ns'])/1e9)<.02,'Around command timing differs')
        if label.startswith('long-step-'):durations.append(op['seconds'])
    quiet=rows[-1];fields(quiet,'event operation requested_seconds buffered_hex sequence elapsed_ns')
    need(quiet['event']=='wire_quiet'and quiet['operation']=='final-clear-drain'and quiet['requested_seconds']==.1
         and quiet['buffered_hex']==''and quiet['sequence']==3*len(commands)+1
         and type(quiet['elapsed_ns'])is int and quiet['elapsed_ns']-previous>=90_000_000,'Around final drain differs')
    return durations

def final_commands():
    return [('restore-initial-clear',legacy(2),reply(0x82)),('settings',settings(0,0),reply(0x83)),
        ('append',legacy(0,378),reply(0x80)),('step-1',legacy(1),reply(0x81,200)),
        ('step-2',legacy(1),reply(0x81,15)),('step-3',legacy(1),reply(0x81,103)),
        ('restore-final-clear',legacy(2),reply(0x82))]

def validate(data,package=ROOT):
    fields(data,'schema passed image_sha256 model_image_sha256 hardware_inputs_sha256 source_reference_inventory_sha256 '
        'source_plan_sha256 source_finished_sha256 source_runner_sha256 source_command_generator_sha256 runtime_pinned_files '
        'runtime_pin_scope per_command_deadline_seconds cases main_reference_outputs probe_reference_outputs '
        'final_greedy_reference_outputs total_reference_outputs case_commands final_restoration_commands final_greedy_wire '
        'final_greedy_source_uart_sha256 claims')
    need(data['schema']=='seeded-around-control-public-v1'and data['passed']is True,'Incomplete around qualification')
    need((data['image_sha256'],data['model_image_sha256'],data['hardware_inputs_sha256'],data['source_reference_inventory_sha256'])
         ==(IMAGE_SHA,MODEL_SHA,INPUTS_SHA,REFERENCE_SHA),'Around image/model/source differs')
    for name,pin in(('source_plan_sha256',SOURCE_PLAN_SHA),('source_finished_sha256',SOURCE_FINISHED_SHA),
                    ('source_runner_sha256',SOURCE_RUNNER_SHA)):
        digest(data[name])
        if pin is not None:need(data[name]==pin,'Around original capture identity differs')
    need(data['source_command_generator_sha256']==ORIGINAL_SHA and data['runtime_pinned_files']==21
         and data['runtime_pin_scope']==PIN_SCOPE and data['per_command_deadline_seconds']==120,'Around source/deadline scope differs')
    refs,comparator=references(package);need(len(data['cases'])==8,'Around case census differs');prior={}
    for i,case in enumerate(data['cases']):
        code,repeat0=divmod(i,2);repeat=repeat0+1;gold,path,pin=refs[code]
        fields(case,'label case temperature seed repeat_index prompt_tokens reference_path reference_sha256 source_reference_sha256 '
            'generated_tokens commands probe_exact_outputs empty_step_rejections first_step_seconds cached_step_seconds '
            'all_outputs_match_independent_reference settings_applied_once_per_case intra_case_clear_probes_retain_and_rewind_settings '
            'full_sequence_matches_prior_run final_clear_acknowledged image_sha256 passed source_uart_sha256 wire')
        need(case['label']==f'around128-t{code}-seed-a-run{repeat}'and case['case']=='around128'
             and case['temperature']==TEMPS[code]and case['seed']==SEED and case['repeat_index']==repeat,
             'Around case order/settings/repetition differ')
        need(case['prompt_tokens']==[378]and case['generated_tokens']==gold['generated_tokens']and case['reference_path']==path
             and case['reference_sha256']==pin and case['source_reference_sha256']==gold['source_reference_receipt_sha256'],
             'Around independent reference differs')
        need(case['commands']==154 and case['probe_exact_outputs']==12 and case['empty_step_rejections']==3
             and case['full_sequence_matches_prior_run']is bool(repeat0)and case['image_sha256']==IMAGE_SHA,
             'Around per-case control census differs')
        need(all(case[n]is True for n in('all_outputs_match_independent_reference','settings_applied_once_per_case',
             'intra_case_clear_probes_retain_and_rewind_settings','final_clear_acknowledged','passed')),'Missing around control result')
        digest(case['source_uart_sha256'])
        wire=case['wire'];physical={k:case[k]for k in('case','temperature','seed','prompt_tokens','generated_tokens','image_sha256')}
        physical['wire']=[dict(direction=row['event'],frame_hex=row['frame_hex'])for row in wire if row['event']in('tx','rx')]
        checked=comparator.compare_context(physical,gold,gold)
        need(checked['commands']==154 and checked['recovery_outputs_compared']==12,'Independent around command plan differs')
        packets=[row for row in wire if row['event']in('tx','rx')]
        commands=[(name,packets[2*j]['frame_hex'],packets[2*j+1]['frame_hex'])for j,name in enumerate(labels())]
        durations=validate_wire(wire,commands)
        need(case['first_step_seconds']==durations[0]and case['cached_step_seconds']==durations[1:],'Around recorded STEP timing differs')
        if repeat==2:need(case['generated_tokens']==prior[code],'Repeated around full sequence differs')
        prior[code]=case['generated_tokens']
    need((data['main_reference_outputs'],data['probe_reference_outputs'],data['final_greedy_reference_outputs'],
          data['total_reference_outputs'],data['case_commands'],data['final_restoration_commands'])==(1024,96,3,1123,1232,7),
         'Around total qualification census differs')
    validate_wire(data['final_greedy_wire'],final_commands());digest(data['final_greedy_source_uart_sha256'])
    need(data['claims']==CLAIMS,'Unsupported around-control qualification claim')
    return dict(passed=True,physical_cases=8,main_reference_outputs=1024,probe_reference_outputs=96,
        final_greedy_reference_outputs=3,total_reference_outputs=1123,commands=1239,
        hardware_access=False,oracle_replayed=False,benchmark_receipts_unchanged=True)

def check_bindings(package=ROOT):
    package=Path(package);references(package)
    source=json.loads(regular(package/'reference/seeded-sampling/SOURCE.json'))
    for name,pin in source['files'].items():need(sha(regular(package/'reference/seeded-sampling'/name))==pin,'Portable reference source changed')
    for name,pin in source['package_inputs'].items():need(sha(regular(package/name))==pin,'Portable model input changed')
    inv=json.loads(regular(package/'host-app/hardware-inputs-seeded-sampling.json'))
    raw=(json.dumps(inv,sort_keys=True,separators=(',',':'))+'\n').encode();need(len(inv)==91 and sha(raw)==INPUTS_SHA,'Around native inventory changed')
    for name,pin in inv.items():
        target=package/'variants/seeded-sampling/hardware'/name
        if name.startswith('project/official/')and not target.exists():continue
        need(sha(regular(target))==pin,'Around native source changed')
    need(sha(regular(package/'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'))==IMAGE_SHA,'Around selected image changed')

def check(package=ROOT):
    need(all(pin is not None for pin in(ARCHIVE_SHA,SOURCE_PLAN_SHA,SOURCE_FINISHED_SHA,SOURCE_RUNNER_SHA)),
         'No completed physical around-control campaign has been pinned')
    package=Path(package);raw=regular(package/RECORD);need(sha(raw)==ARCHIVE_SHA,'Frozen around-control archive changed')
    result=validate(json.loads(raw),package);check_bindings(package);return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(parser.parse_args().package),indent=2))

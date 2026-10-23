#!/usr/bin/env python3
"""Validate a completed recorded seed-domain campaign against exact goldens.

This checker is prepared before the physical campaign. check() refuses to claim
qualification until the completed archive and origin hashes are explicitly
pinned. validate() supports synthetic mutation tests without hardware access.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
RECORD='evidence/seeded-sampling/seed-domain.json'
ARCHIVE_SHA='d56cd8312e13ac74374425e1de10d15a5d6764580faf8762a7deaba72b27ed6f'
SOURCE_PLAN_SHA='b3df8abf431f733103b7eade9aa9be33c77f0d1afe58925346244c9bfc72652f'
SOURCE_FINISHED_SHA='7d459e25879a9ce94ecd51b6c113fbe5a6e7a4d47c0b13e1444cdb79260c750c'
SOURCE_RUNNER_SHA='e66b8bfc24135408a6a25728822863fc379f018dfa48fb3a278fb4b01fb9e779'
SOURCE_SHA='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
IMAGE_SHA='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
MODEL_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
INDEX_SHAS={'goldens':'a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b',
    'domain-goldens':'8e4a3bcc11a6626490f2b5d630b8347dde8e707f1b5ac3b4d041b9f0f6097ab1'}
TEMPS=('0','0.5','1','2')

def need(ok,message):
    if not ok:raise ValueError(message)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def fields(value,names):need(type(value)is dict and set(value)==set(names.split()),'Unexpected seed-domain evidence fields')
def digest(value):need(type(value)is str and re.fullmatch('[0-9a-f]{64}',value),'Invalid seed-domain origin digest')
def positive(value):need(type(value)in(int,float)and math.isfinite(value)and 0<value<120,'Invalid seed-domain command duration')
def crc8(raw):
    value=0
    for byte in raw:
        value^=byte
        for _ in range(8):value=((value<<1)^(7 if value&128 else 0))&255
    return value
def frame(body):return(body+bytes([crc8(body)])).hex()
def legacy(op,token=0):return frame(bytes([0xa5,op,token&255,token>>8]))
def reply(kind,operand=0):return frame(bytes([0x5a,kind,operand&255,operand>>8]))
def settings(code,seed):return frame(bytes([0xa5,3,code])+seed.to_bytes(16,'little'))

def reference_paths():
    paths=[f'reference/seeded-sampling/goldens/around128-t{code}-seed-b.json'for code in(1,2,3)]
    paths +=[f'reference/seeded-sampling/domain-goldens/around32-t{code}-seed-{seed}.json'
             for code in(1,2,3)for seed in('zero','all-ones')]
    paths +=[f'reference/seeded-sampling/goldens/prefix128-t{code}-seed-b.json'for code in(1,2,3)]
    return paths

def read_references(package):
    package=Path(package);indices={}
    for name,pin in INDEX_SHAS.items():
        raw=(package/f'reference/seeded-sampling/{name}/INDEX.json').read_bytes()
        need(sha(raw)==pin,'Seed-domain numerical index changed');indices[name]=json.loads(raw)
    references=[]
    for path in reference_paths():
        raw=(package/path).read_bytes();name=Path(path).name;folder=Path(path).parent.name
        need(indices[folder]['files'].get(name)==dict(bytes=len(raw),sha256=sha(raw)),'Seed-domain golden bytes changed')
        references.append((path,json.loads(raw),sha(raw)))
    return references

def commands(reference):
    rows=[('clear',legacy(2),0x82,0),
          ('settings',settings(TEMPS.index(reference['temperature']),int(reference['seed'],16)),0x83,TEMPS.index(reference['temperature']))]
    rows +=[(f'append-{i+1}',legacy(0,token),0x80,0)for i,token in enumerate(reference['prompt_tokens'])]
    rows +=[(f'step-{i+1}',legacy(1),0x81,token)for i,token in enumerate(reference['generated_tokens'])]
    rows +=[('replay-clear',legacy(2),0x82,0)]
    rows +=[(f'replay-append-{i+1}',legacy(0,token),0x80,0)for i,token in enumerate(reference['prompt_tokens'])]
    rows +=[(f'replay-step-{i+1}',legacy(1),0x81,token)for i,token in enumerate(reference['generated_tokens'][:8])]
    return rows+[('final-clear',legacy(2),0x82,0)]

def validate_wire(wire,plan):
    need(type(wire)is list and len(wire)==len(plan)*3+1,'Seed-domain wire census differs')
    previous=-1;main_seconds=[]
    for i,(operation,tx,kind,operand)in enumerate(plan):
        sent,received,completed=wire[3*i:3*i+3]
        for seq,row in enumerate((sent,received,completed),3*i+1):
            fields(row,'event operation frame_hex sequence elapsed_ns'if row['event']in('tx','rx')else
                   'event operation response_kind operand seconds sequence elapsed_ns')
            need(type(row['sequence'])is int and row['sequence']==seq and row['operation']==operation
                and type(row['elapsed_ns'])is int and row['elapsed_ns']>previous
                and(seq!=1 or row['elapsed_ns']==0),'Seed-domain command order/timeline differs')
            previous=row['elapsed_ns']
        need(sent['event']=='tx'and sent['frame_hex']==tx and received['event']=='rx'
            and received['frame_hex']==reply(kind,operand),'Seed-domain frame/CRC/settings/token differs')
        for row in(sent,received):
            raw=bytes.fromhex(row['frame_hex']);need(crc8(raw[:-1])==raw[-1],'Seed-domain CRC differs')
        need(completed['event']=='operation'and completed['response_kind']==kind
            and completed['operand']==operand,'Seed-domain operation result differs')
        positive(completed['seconds'])
        need(abs(completed['seconds']-(completed['elapsed_ns']-sent['elapsed_ns'])/1e9)<.02,
             'Seed-domain duration/timeline disagree')
        if operation.startswith('step-'):main_seconds.append(completed['seconds'])
    quiet=wire[-1];fields(quiet,'event operation requested_seconds buffered_hex sequence elapsed_ns')
    need(quiet['event']=='wire_quiet'and quiet['operation']=='final-clear-drain'and quiet['requested_seconds']==.1
        and quiet['buffered_hex']==''and quiet['sequence']==len(plan)*3+1 and type(quiet['elapsed_ns'])is int
        and quiet['elapsed_ns']-previous>=90_000_000,'Missing seed-domain final CLEAR drain observation')
    return main_seconds

def final_commands():
    return [('clear',legacy(2),0x82,0),('settings',settings(0,0),0x83,0),('append',legacy(0,378),0x80,0),
        ('step-1',legacy(1),0x81,200),('step-2',legacy(1),0x81,15),('step-3',legacy(1),0x81,103),
        ('clear',legacy(2),0x82,0)]

def validate(data,package=ROOT):
    package=Path(package)
    fields(data,'schema passed image_sha256 model_image_sha256 source_inventory_sha256 source_plan_sha256 '
        'source_finished_sha256 source_runner_sha256 runtime_pinned_files runtime_pin_scope cases '
        'full_reference_outputs clear_replay_outputs final_greedy_reference_outputs total_reference_outputs '
        'final_greedy_wire final_greedy_source_uart_sha256 per_command_deadline_seconds claims')
    need(data['schema']=='seeded-seed-domain-public-v1'and data['passed']is True,'Incomplete seed-domain campaign')
    need(data['image_sha256']==IMAGE_SHA and data['model_image_sha256']==MODEL_SHA
        and data['source_inventory_sha256']==SOURCE_SHA,'Seed-domain circuit/model source differs')
    need(sha((package/'reference/seeded-sampling/SOURCE.json').read_bytes())==SOURCE_SHA,'Portable numerical source inventory changed')
    for key,pin in [('source_plan_sha256',SOURCE_PLAN_SHA),('source_finished_sha256',SOURCE_FINISHED_SHA)]:
        digest(data[key])
        if pin is not None:need(data[key]==pin,'Seed-domain original campaign identity differs')
    need(data['source_runner_sha256']==SOURCE_RUNNER_SHA,'Seed-domain runner changed')
    need(data['runtime_pinned_files']==19 and data['runtime_pin_scope']==
        '19 runner, transport and numerical-reference files; not all 91 native inputs.', 'Seed-domain runtime pin scope differs')
    need((data['full_reference_outputs'],data['clear_replay_outputs'],data['final_greedy_reference_outputs'],
          data['total_reference_outputs'])==(960,96,3,1059),'Seed-domain output census differs')
    need(data['per_command_deadline_seconds']==120,'Seed-domain deadline differs')
    references=read_references(package);need(len(data['cases'])==12,'Seed-domain case census differs')
    total_commands=0
    for case,(path,reference,digest_value)in zip(data['cases'],references):
        fields(case,'label temperature seed prompt_tokens generated_tokens replayed_tokens step_seconds reference_path '
            'reference_sha256 source_reference_receipt_sha256 all_tokens_match_independent_reference '
            'replay_without_settings final_clear_acknowledged image_sha256 passed source_uart_sha256 wire')
        need(case['label']==Path(path).stem and case['reference_path']==path
            and case['reference_sha256']==digest_value
            and case['source_reference_receipt_sha256']==reference['source_reference_receipt_sha256'],
            'Seed-domain golden identity differs')
        for key in('temperature','seed','prompt_tokens','generated_tokens'):need(case[key]==reference[key],'Seed-domain numerical output/settings differ')
        need(case['replayed_tokens']==reference['generated_tokens'][:8]and case['image_sha256']==IMAGE_SHA
            and all(case[k]is True for k in('passed','all_tokens_match_independent_reference',
                'replay_without_settings','final_clear_acknowledged')),'Missing exact continuous stream/CLEAR replay')
        digest(case['source_uart_sha256']);plan=commands(reference);seconds=validate_wire(case['wire'],plan)
        need(seconds==case['step_seconds'],'Seed-domain STEP timing differs');total_commands+=len(plan)
    need(total_commands==1890,'Seed-domain command census differs')
    digest(data['final_greedy_source_uart_sha256']);validate_wire(data['final_greedy_wire'],final_commands())
    need(data['claims']==dict(physical_fpga=True,final_empty_greedy=True,usb_released=True,flash_modified=False,
        automatic_retries=False,configuration_independently_attested=False,timing_qualified=False,
        security_certified=False,full_context_qualified_by_this_campaign=False,
        zero_seed_remap_checked_by_transcript=True,internal_prng_state_observed=False,oracle_replayed_by_archive_checker=False),
        'Unsupported seed-domain qualification claim')
    return dict(passed=True,physical_cases=12,continuous_reference_outputs=960,clear_replay_outputs=96,
        final_greedy_outputs=3,total_reference_outputs=1059,commands=1897,hardware_access=False,oracle_replayed=False)

def check(package=ROOT):
    need(all(pin is not None for pin in(ARCHIVE_SHA,SOURCE_PLAN_SHA,SOURCE_FINISHED_SHA)),
         'No completed physical seed-domain campaign has been pinned yet')
    raw=(Path(package)/RECORD).read_bytes();need(sha(raw)==ARCHIVE_SHA,'Frozen seed-domain archive changed')
    result=validate(json.loads(raw),package)
    check_bindings(package)
    return result

def check_bindings(package=ROOT):
    package=Path(package)
    source=json.loads((package/'reference/seeded-sampling/SOURCE.json').read_bytes())
    need(sha((package/'reference/seeded-sampling/SOURCE.json').read_bytes())==SOURCE_SHA,'Portable source inventory changed')
    for name,digest_value in source['files'].items():
        path=package/'reference/seeded-sampling'/name
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==digest_value,'Portable numerical source changed')
    for name,digest_value in source['package_inputs'].items():
        path=package/name
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==digest_value,'Portable numerical model input changed')
    inventory=json.loads((package/'host-app/hardware-inputs-seeded-sampling.json').read_bytes())
    canonical=(json.dumps(inventory,sort_keys=True,separators=(',',':'))+'\n').encode()
    need(len(inventory)==91 and sha(canonical)=='26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831',
         'Selected native source inventory differs')
    for name,digest_value in inventory.items():
        path=package/'variants/seeded-sampling/hardware'/name
        if name.startswith('project/official/')and not path.exists():continue
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==digest_value,'Selected native source bytes changed')
    path=package/'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'
    need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==IMAGE_SHA,'Selected seeded FPGA image changed')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(parser.parse_args().package),indent=2))

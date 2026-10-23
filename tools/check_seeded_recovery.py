#!/usr/bin/env python3
"""Validate recorded host-observable cancellation/recovery, without hardware.

Prepared before the physical campaign: check() refuses until a completed
archive and its original plan/completion hashes have been reviewed and pinned.
These observations do not identify the internal command/read edge at CLEAR.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
RECORD='evidence/seeded-sampling/recovery.json'
ARCHIVE_SHA='e00ebbb5930bfb11c6486eaf871f49b3a2c640d7b6852199cd5f4e26b02c7f16'
SOURCE_PLAN_SHA='3ef193ced989676635f2b4598ce3933bc7909d6d6ec20312c3fd84b21916ae5b'
SOURCE_FINISHED_SHA='237322c84f3f919ae000e4e293cf4776b2021a3c22217ee5d3ff51c434928bb6'
SOURCE_RUNNER_SHA='c380d9eef2b1064561ea33f1e2ab30cdc2d9fdc4aa956ff4cf146d0b27f216c5'
SOURCE_SHA='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
INDEX_SHA='a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b'
IMAGE_SHA='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
MODEL_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
SEED='0x99aabbccddeeff001122334455667788'
GOLDEN_ROOT='reference/seeded-sampling/goldens/'
AROUND=GOLDEN_ROOT+'around128-t2-seed-a.json'
CASES=(('partial-prompt-upload','partial-upload',128,64),
       ('early-clear-prefix128','step-clear',128,128),
       ('early-clear-prefix2048','step-clear',2048,2048))
PIN_SCOPE='13 runner, transport, numerical-reference and selected image files; not all 91 native inputs.'
CLAIMS=dict(physical_fpga=True,final_empty_greedy=True,usb_released=True,
    flash_modified=False,automatic_retries=False,configuration_independently_attested=False,
    internal_inflight_command_edge_observed=False,internal_active_read_at_clear_observed=False,
    timing_qualified=False,security_certified=False,full_context_inference_qualified_by_this_campaign=False,
    oracle_replayed_by_archive_checker=False)


def need(ok,message):
    if not ok:raise ValueError(message)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def fields(value,names):need(type(value)is dict and set(value)==set(names.split()),'Unexpected recovery evidence fields')
def digest(value):need(type(value)is str and re.fullmatch('[0-9a-f]{64}',value),'Invalid recovery origin digest')
def duration(value):need(type(value)in(int,float)and math.isfinite(value)and 0<value<5,'Invalid recovery command duration')
def crc8(raw):
    value=0
    for byte in raw:
        value^=byte
        for _ in range(8):value=((value<<1)^(7 if value&128 else 0))&255
    return value
def frame(body):return(body+bytes([crc8(body)])).hex()
def legacy(op,token=0):return frame(bytes([0xa5,op,token&255,token>>8]))
def reply(kind,operand=0):return frame(bytes([0x5a,kind,operand&255,operand>>8]))
def settings(code=2,seed=int(SEED,16)):return frame(bytes([0xa5,3,code])+seed.to_bytes(16,'little'))


def read_references(package=ROOT):
    package=Path(package)
    source_raw=(package/'reference/seeded-sampling/SOURCE.json').read_bytes()
    need(sha(source_raw)==SOURCE_SHA,'Portable numerical source inventory changed')
    raw=(package/GOLDEN_ROOT/'INDEX.json').read_bytes()
    need(sha(raw)==INDEX_SHA,'Recovery numerical index changed')
    index=json.loads(raw);references={}
    for name in ('around128-t2-seed-a.json','prefix128-t2-seed-a.json','prefix2048-t2-seed-a.json'):
        path=GOLDEN_ROOT+name;raw=(package/path).read_bytes();pin=sha(raw)
        need(index['files'].get(name)==dict(bytes=len(raw),sha256=pin),'Recovery golden bytes changed')
        row=json.loads(raw)
        expected_case=name.split('-t')[0]
        need(row['schema']=='seeded-exact-model-golden-v1'and row['case']==expected_case
             and row['temperature']=='1'and row['seed']==SEED and row['model_image_sha256']==MODEL_SHA,
             'Recovery golden model/settings differ')
        references[path]=(row,pin)
    around=references[AROUND][0]
    need(around['prompt_tokens']==[378]and len(around['generated_tokens'])==128,'Recovery around fixture differs')
    return references


def normal_before(prompt):
    return [('initial-clear',legacy(2),0x82,0),('settings',settings(),0x83,2)]+[
        (f'append-{i+1}',legacy(0,token),0x80,0)for i,token in enumerate(prompt)]

def normal_after(known):
    return [('recovery-append',legacy(0,378),0x80,0)]+[
        (f'recovery-step-{i+1}',legacy(1),0x81,token)for i,token in enumerate(known)]+[
        ('replay-clear',legacy(2),0x82,0),('replay-append',legacy(0,378),0x80,0)]+[
        (f'replay-step-{i+1}',legacy(1),0x81,token)for i,token in enumerate(known)]+[
        ('final-clear',legacy(2),0x82,0)]

def final_commands():
    return [('restore-initial-clear',legacy(2),0x82,0),('settings',settings(0,0),0x83,0),('append',legacy(0,378),0x80,0),
        ('step-1',legacy(1),0x81,200),('step-2',legacy(1),0x81,15),('step-3',legacy(1),0x81,103),
        ('restore-final-clear',legacy(2),0x82,0)]


class Wire:
    def __init__(self,rows):
        need(type(rows)is list,'Recovery wire must be a list')
        self.rows=rows;self.index=0;self.previous=-1
    def take(self,event,operation):
        need(self.index<len(self.rows),'Missing recovery wire event')
        row=self.rows[self.index];self.index+=1
        need(row.get('event')==event and row.get('operation')==operation,'Recovery wire event/order differs')
        need(type(row.get('sequence'))is int and row['sequence']==self.index
             and type(row.get('elapsed_ns'))is int and row['elapsed_ns']>self.previous
             and(self.index!=1 or row['elapsed_ns']==0),'Recovery wire timeline differs')
        self.previous=row['elapsed_ns'];return row
    def packet(self,event,operation,expected):
        row=self.take(event,operation);fields(row,'event operation frame_hex sequence elapsed_ns')
        need(row['frame_hex']==expected,'Recovery frame/CRC/token/settings differ')
        raw=bytes.fromhex(row['frame_hex']);need(crc8(raw[:-1])==raw[-1],'Recovery frame CRC differs')
        return row
    def operation(self,label,kind,operand,sent):
        row=self.take('operation',label);fields(row,'event operation response_kind operand seconds sequence elapsed_ns')
        need(row['response_kind']==kind and row['operand']==operand,'Recovery response result differs')
        duration(row['seconds'])
        need(abs(row['seconds']-(row['elapsed_ns']-sent['elapsed_ns'])/1e9)<.02,'Recovery command timing differs')
        return row
    def exchange(self,command):
        label,tx,kind,operand=command
        sent=self.packet('tx',label,tx);self.packet('rx',label,reply(kind,operand))
        return self.operation(label,kind,operand,sent)
    def quiet(self,label):
        previous=self.previous;row=self.take('wire_quiet',label)
        fields(row,'event operation requested_seconds buffered_hex sequence elapsed_ns')
        need(row['requested_seconds']==.1 and row['buffered_hex']==''and row['elapsed_ns']-previous>=90_000_000,
             'Missing recovery quiet/drain observation')
    def finish(self):need(self.index==len(self.rows),'Extra recovery wire event')


def validate_case(case,descriptor,references):
    label,mode,length,uploaded=descriptor
    path=GOLDEN_ROOT+f'prefix{length}-t2-seed-a.json'
    reference,pin=references[path];around,around_pin=references[AROUND]
    known=around['generated_tokens'][:8];prompt=reference['prompt_tokens'][:uploaded]
    fields(case,'label mode temperature seed uploaded_prompt_tokens source_reference_path source_reference_sha256 '
        'recovery_reference_path recovery_reference_sha256 cancelled_step_sent requested_cancel_delay_seconds '
        'observed_host_cancel_delay_seconds completed_before_clear_tokens recovery_tokens replayed_tokens '
        'clear_response_seconds all_tokens_match_independent_reference final_clear_acknowledged '
        'internal_inflight_command_edge_observed image_sha256 passed source_uart_sha256 wire')
    need(case['label']==label and case['mode']==mode and case['temperature']=='1'and case['seed']==SEED,
         'Recovery case order/settings differ')
    need(case['source_reference_path']==path and case['source_reference_sha256']==pin
         and case['recovery_reference_path']==AROUND and case['recovery_reference_sha256']==around_pin,
         'Recovery reference origin differs')
    need(case['uploaded_prompt_tokens']==prompt and len(reference['prompt_tokens'])==length,
         'Recovery exact uploaded prompt differs')
    need(case['recovery_tokens']==known and case['replayed_tokens']==known
         and case['all_tokens_match_independent_reference']is True and case['final_clear_acknowledged']is True
         and case['internal_inflight_command_edge_observed']is False and case['image_sha256']==IMAGE_SHA
         and case['passed']is True,'Missing recovery reference/CLEAR result or unsupported internal-edge claim')
    digest(case['source_uart_sha256']);wire=Wire(case['wire'])
    before=normal_before(prompt)
    for command in before:wire.exchange(command)
    completed=case['completed_before_clear_tokens']
    if mode=='partial-upload':
        need(case['cancelled_step_sent']is False and case['requested_cancel_delay_seconds']==0
             and case['observed_host_cancel_delay_seconds']is None and completed==[],
             'Partial-upload cancellation sent STEP or claimed an internal result')
        clear=wire.exchange(('cancel-clear',legacy(2),0x82,0))
        cancel_commands=1
    else:
        need(case['cancelled_step_sent']is True and case['requested_cancel_delay_seconds']==.05,
             'Early cancellation STEP/delay scope differs')
        need(completed in ([],reference['generated_tokens'][:1]),'Unexpected result before cancellation CLEAR')
        sent_step=wire.packet('tx','cancelled-step',legacy(1))
        queued=wire.take('step_queued','cancelled-step')
        fields(queued,'event operation seconds sequence elapsed_ns');duration(queued['seconds'])
        need(abs(queued['seconds']-(queued['elapsed_ns']-sent_step['elapsed_ns'])/1e9)<.02,
             'STEP queue timestamp differs')
        delay=wire.take('host_delay','cancelled-step')
        fields(delay,'event operation requested_seconds seconds sequence elapsed_ns')
        need(delay['requested_seconds']==.05 and type(delay['seconds'])in(int,float)
             and math.isfinite(delay['seconds'])and .05<=delay['seconds']<1
             and abs(delay['seconds']-(delay['elapsed_ns']-queued['elapsed_ns'])/1e9)<.02,
             'Measured host CLEAR delay differs')
        need(case['observed_host_cancel_delay_seconds']==delay['seconds'],'Recovery delay summary differs')
        sent_clear=wire.packet('tx','cancel-clear',legacy(2))
        if completed:
            wire.packet('rx','cancel-drain',reply(0x81,completed[0]))
            wire.operation('cancelled-step',0x81,completed[0],sent_step)
        wire.packet('rx','cancel-drain',reply(0x82))
        clear=wire.operation('cancel-clear',0x82,0,sent_clear);cancel_commands=2
    need(case['clear_response_seconds']==clear['seconds'],'CLEAR response time summary differs')
    wire.quiet('cancel-clear-drain')
    after=normal_after(known)
    for command in after:wire.exchange(command)
    wire.quiet('final-clear-drain');wire.finish()
    return dict(commands=len(before)+cancel_commands+len(after),recovery_outputs=16,
                completed_before_clear_outputs=len(completed))


def validate(data,package=ROOT):
    package=Path(package)
    fields(data,'schema passed image_sha256 model_image_sha256 source_inventory_sha256 source_plan_sha256 '
        'source_finished_sha256 source_runner_sha256 runtime_pinned_files runtime_pin_scope cases '
        'recovery_reference_outputs completed_before_clear_reference_outputs final_greedy_reference_outputs '
        'total_reference_outputs commands final_restoration_commands final_greedy_wire '
        'final_greedy_source_uart_sha256 per_command_deadline_seconds claims')
    need(data['schema']=='seeded-recovery-edges-public-v1'and data['passed']is True,'Incomplete recovery campaign')
    need(data['image_sha256']==IMAGE_SHA and data['model_image_sha256']==MODEL_SHA
         and data['source_inventory_sha256']==SOURCE_SHA,'Recovery circuit/model source differs')
    for key,pin in [('source_plan_sha256',SOURCE_PLAN_SHA),('source_finished_sha256',SOURCE_FINISHED_SHA),
                    ('source_runner_sha256',SOURCE_RUNNER_SHA)]:
        digest(data[key])
        if pin is not None:need(data[key]==pin,'Recovery original campaign identity differs')
    need(data['runtime_pinned_files']==13 and data['runtime_pin_scope']==PIN_SCOPE,'Recovery runtime pin scope differs')
    need(data['per_command_deadline_seconds']==5 and len(data['cases'])==3,'Recovery deadline/case census differs')
    references=read_references(package)
    rows=[validate_case(case,descriptor,references)for case,descriptor in zip(data['cases'],CASES)]
    total_commands=sum(row['commands']for row in rows);completed=sum(row['completed_before_clear_outputs']for row in rows)
    need(total_commands==2311 and data['commands']==2311 and data['final_restoration_commands']==7,
         'Recovery command census differs')
    need((data['recovery_reference_outputs'],data['completed_before_clear_reference_outputs'],
          data['final_greedy_reference_outputs'],data['total_reference_outputs'])==(48,completed,3,51+completed),
         'Recovery exact output census differs')
    final=Wire(data['final_greedy_wire'])
    for command in final_commands():final.exchange(command)
    final.quiet('final-clear-drain');final.finish();digest(data['final_greedy_source_uart_sha256'])
    need(data['claims']==CLAIMS,'Unsupported recovery qualification claim')
    return dict(passed=True,physical_cases=3,recovery_reference_outputs=48,
        completed_before_clear_reference_outputs=completed,final_greedy_reference_outputs=3,
        total_reference_outputs=51+completed,commands=2318,hardware_access=False,
        internal_inflight_command_edge_observed=False,oracle_replayed=False)


def check_bindings(package=ROOT):
    package=Path(package);read_references(package)
    source=json.loads((package/'reference/seeded-sampling/SOURCE.json').read_bytes())
    for name,pin in source['files'].items():
        path=package/'reference/seeded-sampling'/name
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Portable reference source changed')
    for name,pin in source['package_inputs'].items():
        path=package/name
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Portable model input changed')
    inventory=json.loads((package/'host-app/hardware-inputs-seeded-sampling.json').read_bytes())
    canonical=(json.dumps(inventory,sort_keys=True,separators=(',',':'))+'\n').encode()
    need(len(inventory)==91 and sha(canonical)=='26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831',
         'Native recovery inventory differs')
    for name,pin in inventory.items():
        path=package/'variants/seeded-sampling/hardware'/name
        if name.startswith('project/official/')and not path.exists():continue
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Native recovery source changed')
    path=package/'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'
    need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==IMAGE_SHA,'Selected recovery image changed')


def check(package=ROOT):
    need(all(pin is not None for pin in(ARCHIVE_SHA,SOURCE_PLAN_SHA,SOURCE_FINISHED_SHA,SOURCE_RUNNER_SHA)),
         'No completed physical recovery campaign has been pinned yet')
    package=Path(package);raw=(package/RECORD).read_bytes()
    need(sha(raw)==ARCHIVE_SHA,'Frozen recovery archive changed')
    result=validate(json.loads(raw),package);check_bindings(package);return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(parser.parse_args().package),indent=2))

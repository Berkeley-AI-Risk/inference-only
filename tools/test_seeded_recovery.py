"""Synthetic recovery-evidence mutation tests; no FPGA access or measurements.

The fixture is generated in memory. It is never written as physical evidence.
The archive checker must continue refusing qualification before real pinning.
"""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('recovery_check',HERE/'check_seeded_recovery.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
PACKAGE=HERE.parent


def encode(body):
    crc=0
    for byte in body:
        crc^=byte
        for _ in range(8):crc=((crc<<1)^7)&255 if crc&128 else(crc<<1)&255
    return(body+bytes([crc])).hex()
def tx(op,operand=0):return encode(bytes((0xa5,op,operand&255,operand>>8)))
def rx(kind,operand=0):return encode(bytes((0x5a,kind,operand&255,operand>>8)))
def setting(code,seed):return encode(bytes((0xa5,3,code))+seed.to_bytes(16,'little'))


class SyntheticWire:
    def __init__(self):self.rows=[];self.now=-100_000
    def row(self,event,operation,advance=100_000,**fields):
        self.now+=advance;value=dict(event=event,operation=operation,sequence=len(self.rows)+1,elapsed_ns=self.now,**fields)
        self.rows.append(value);return value
    def command(self,label,frame,kind,operand=0):
        sent=self.row('tx',label,frame_hex=frame)
        self.row('rx',label,advance=20_000_000,frame_hex=rx(kind,operand))
        return self.row('operation',label,response_kind=kind,operand=operand,seconds=.0201)
    def quiet(self,label):self.row('wire_quiet',label,advance=100_000_000,requested_seconds=.1,buffered_hex='')


def synthetic(completions=(False,True)):
    refs=c.read_references(PACKAGE);around,around_sha=refs[c.AROUND];known=around['generated_tokens'][:8];cases=[]
    completed_total=0
    for number,(label,mode,length,uploaded)in enumerate(c.CASES):
        path=c.GOLDEN_ROOT+f'prefix{length}-t2-seed-a.json';reference,pin=refs[path];prompt=reference['prompt_tokens'][:uploaded]
        wire=SyntheticWire();wire.command('initial-clear',tx(2),0x82)
        wire.command('settings',setting(2,int(c.SEED,16)),0x83,2)
        for i,token in enumerate(prompt):wire.command(f'append-{i+1}',tx(0,token),0x80)
        delay=None;completed=[]
        if mode=='partial-upload':clear=wire.command('cancel-clear',tx(2),0x82)
        else:
            sent_step=wire.row('tx','cancelled-step',frame_hex=tx(1))
            wire.row('step_queued','cancelled-step',advance=1_000_000,seconds=.001)
            wire.row('host_delay','cancelled-step',advance=50_000_000,requested_seconds=.05,seconds=.05);delay=.05
            sent_clear=wire.row('tx','cancel-clear',frame_hex=tx(2))
            if completions[number-1]:
                completed=reference['generated_tokens'][:1]
                wire.row('rx','cancel-drain',advance=10_000_000,frame_hex=rx(0x81,completed[0]))
                wire.row('operation','cancelled-step',response_kind=0x81,operand=completed[0],
                    seconds=(wire.now+100_000-sent_step['elapsed_ns'])/1e9)
            wire.row('rx','cancel-drain',advance=10_000_000,frame_hex=rx(0x82))
            clear=wire.row('operation','cancel-clear',response_kind=0x82,operand=0,
                seconds=(wire.now+100_000-sent_clear['elapsed_ns'])/1e9)
        wire.quiet('cancel-clear-drain')
        wire.command('recovery-append',tx(0,378),0x80)
        for i,token in enumerate(known):wire.command(f'recovery-step-{i+1}',tx(1),0x81,token)
        wire.command('replay-clear',tx(2),0x82);wire.command('replay-append',tx(0,378),0x80)
        for i,token in enumerate(known):wire.command(f'replay-step-{i+1}',tx(1),0x81,token)
        wire.command('final-clear',tx(2),0x82);wire.quiet('final-clear-drain')
        cases.append(dict(label=label,mode=mode,temperature='1',seed=c.SEED,uploaded_prompt_tokens=prompt,
            source_reference_path=path,source_reference_sha256=pin,recovery_reference_path=c.AROUND,
            recovery_reference_sha256=around_sha,cancelled_step_sent=mode=='step-clear',
            requested_cancel_delay_seconds=0 if mode=='partial-upload'else .05,
            observed_host_cancel_delay_seconds=delay,completed_before_clear_tokens=completed,
            recovery_tokens=known[:],replayed_tokens=known[:],clear_response_seconds=clear['seconds'],
            all_tokens_match_independent_reference=True,final_clear_acknowledged=True,
            internal_inflight_command_edge_observed=False,image_sha256=c.IMAGE_SHA,passed=True,
            source_uart_sha256='a'*64,wire=wire.rows));completed_total+=len(completed)
    final=SyntheticWire();final.command('restore-initial-clear',tx(2),0x82);final.command('settings',setting(0,0),0x83)
    final.command('append',tx(0,378),0x80)
    for i,token in enumerate((200,15,103)):final.command(f'step-{i+1}',tx(1),0x81,token)
    final.command('restore-final-clear',tx(2),0x82);final.quiet('final-clear-drain')
    return dict(schema='seeded-recovery-edges-public-v1',passed=True,image_sha256=c.IMAGE_SHA,
        model_image_sha256=c.MODEL_SHA,source_inventory_sha256=c.SOURCE_SHA,
        source_plan_sha256=c.SOURCE_PLAN_SHA or'1'*64,source_finished_sha256=c.SOURCE_FINISHED_SHA or'2'*64,source_runner_sha256=c.SOURCE_RUNNER_SHA,
        runtime_pinned_files=13,runtime_pin_scope=c.PIN_SCOPE,cases=cases,recovery_reference_outputs=48,
        completed_before_clear_reference_outputs=completed_total,final_greedy_reference_outputs=3,
        total_reference_outputs=51+completed_total,commands=2311,final_restoration_commands=7,
        final_greedy_wire=final.rows,final_greedy_source_uart_sha256='b'*64,per_command_deadline_seconds=5,
        claims=dict(c.CLAIMS))


class RecoveryEvidenceTests(unittest.TestCase):
    def test_both_clear_race_outcomes_are_numerically_checked(self):
        for a,b in((False,False),(False,True),(True,False),(True,True)):
            with self.subTest(first_completed=a,second_completed=b):
                result=c.validate(synthetic((a,b)),PACKAGE)
                self.assertEqual(result['commands'],2318)
                self.assertEqual(result['total_reference_outputs'],51+int(a)+int(b))
                self.assertFalse(result['internal_inflight_command_edge_observed'])

    def test_no_qualification_before_each_final_physical_hash_is_pinned(self):
        for missing in('ARCHIVE_SHA','SOURCE_PLAN_SHA','SOURCE_FINISHED_SHA','SOURCE_RUNNER_SHA'):
            pins={name:'0'*64 for name in('ARCHIVE_SHA','SOURCE_PLAN_SHA','SOURCE_FINISHED_SHA','SOURCE_RUNNER_SHA')}
            pins[missing]=None
            with self.subTest(missing=missing),patch.multiple(c,**pins),patch.object(Path,'read_bytes',side_effect=AssertionError('must refuse before I/O')):
                with self.assertRaisesRegex(ValueError,'No completed physical recovery'):c.check(PACKAGE)

    def test_wire_timing_replay_and_cancel_mutations_are_rejected(self):
        base=synthetic((True,False))
        for mutation in('crc','token-before-clear','missing-clear','extra-result','seed','reorder',
            'replay-token','recovery-settings','quiet','partial-buffer','early-delay','late-delay',
            'partial-step','duration-nan','timeline','extra-tail'):
            with self.subTest(mutation=mutation):
                data=copy.deepcopy(base);case=data['cases'][1];wire=case['wire']
                def row(event,operation):return next(x for x in wire if x['event']==event and x['operation']==operation)
                if mutation=='crc':row('tx','cancel-clear')['frame_hex']=tx(2)[:-2]+'00'
                elif mutation=='token-before-clear':row('rx','cancel-drain')['frame_hex']=rx(0x81,2)
                elif mutation=='missing-clear':wire.remove(row('rx','cancel-drain'))
                elif mutation=='extra-result':wire.insert(-1,copy.deepcopy(row('rx','cancel-drain')))
                elif mutation=='seed':row('tx','settings')['frame_hex']=setting(2,int(c.SEED,16)^(1<<100))
                elif mutation=='reorder':wire[3],wire[4]=wire[4],wire[3]
                elif mutation=='replay-token':row('rx','replay-step-2')['frame_hex']=rx(0x81,13)
                elif mutation=='recovery-settings':row('tx','recovery-append')['frame_hex']=setting(0,0)
                elif mutation=='quiet':next(x for x in wire if x['event']=='wire_quiet')['requested_seconds']=0
                elif mutation=='partial-buffer':next(x for x in wire if x['event']=='wire_quiet')['buffered_hex']='5a'
                elif mutation=='early-delay':row('host_delay','cancelled-step')['seconds']=.049
                elif mutation=='late-delay':row('host_delay','cancelled-step')['seconds']=1.1
                elif mutation=='partial-step':data['cases'][0]['cancelled_step_sent']=True
                elif mutation=='duration-nan':row('operation','cancel-clear')['seconds']=float('nan')
                elif mutation=='timeline':row('operation','cancel-clear')['elapsed_ns']=0
                else:wire.append(copy.deepcopy(wire[-1]))
                with self.assertRaises(ValueError):c.validate(data,PACKAGE)

    def test_reference_origins_scope_and_final_restoration_mutations_are_rejected(self):
        with patch.object(c,'SOURCE_PLAN_SHA','1'*64),patch.object(c,'SOURCE_FINISHED_SHA','2'*64):
            base=synthetic((False,False))
        for mutation in('model','runner','source-plan','source-finished','source-index','prompt','reference-path',
            'known-token','census','pin-scope','internal-edge','qualified-full-context','final-clear','greedy-setting',
            'deadline','unknown-field'):
            with self.subTest(mutation=mutation):
                data=copy.deepcopy(base)
                if mutation=='model':data['model_image_sha256']='0'*64
                elif mutation=='runner':data['source_runner_sha256']='0'*64
                elif mutation=='source-plan':data['source_plan_sha256']='0'*64
                elif mutation=='source-finished':data['source_finished_sha256']='0'*64
                elif mutation=='source-index':data['source_inventory_sha256']='0'*64
                elif mutation=='prompt':data['cases'][2]['uploaded_prompt_tokens'][0]^=1
                elif mutation=='reference-path':data['cases'][2]['source_reference_path']='../../private.json'
                elif mutation=='known-token':data['cases'][0]['recovery_tokens'][1]^=1
                elif mutation=='census':data['total_reference_outputs']+=1
                elif mutation=='pin-scope':data['runtime_pinned_files']=91
                elif mutation=='internal-edge':data['cases'][1]['internal_inflight_command_edge_observed']=True
                elif mutation=='qualified-full-context':data['claims']['full_context_inference_qualified_by_this_campaign']=True
                elif mutation=='final-clear':data['final_greedy_wire'][-3]['frame_hex']=rx(0x81,200)
                elif mutation=='greedy-setting':data['final_greedy_wire'][3]['frame_hex']=setting(2,int(c.SEED,16))
                elif mutation=='deadline':data['per_command_deadline_seconds']=3600
                else:data['undeclared_private_path']='/private/not-published'
                with patch.object(c,'SOURCE_PLAN_SHA','1'*64),patch.object(c,'SOURCE_FINISHED_SHA','2'*64):
                    with self.assertRaises(ValueError):c.validate(data,PACKAGE)


if __name__=='__main__':unittest.main(verbosity=2)

"""Synthetic around-control validator mutation tests, never physical evidence."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('_around_control_test',HERE/'check_seeded_around.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
PACKAGE=HERE.parent

def packet(body):
    value=0
    for byte in body:
        value^=byte
        for _ in range(8):value=((value<<1)^7)&255 if value&128 else(value<<1)&255
    return(body+bytes([value])).hex()
def tx(op,token=0):return packet(bytes([0xa5,op,token&255,token>>8]))
def rx(kind,token=0):return packet(bytes([0x5a,kind,token&255,token>>8]))

class Wire:
    def __init__(self):self.rows=[];self.ns=-100_000
    def emit(self,event,label,advance=100_000,**fields):
        self.ns+=advance;self.rows.append(dict(event=event,operation=label,sequence=len(self.rows)+1,elapsed_ns=self.ns,**fields))
    def exchange(self,label,raw,kind,value=0):
        self.emit('tx',label,frame_hex=raw);self.emit('rx',label,20_000_000,frame_hex=rx(kind,value))
        self.emit('operation',label,response_kind=kind,operand=value,seconds=.0201)
    def quiet(self):self.emit('wire_quiet','final-clear-drain',100_000_000,requested_seconds=.1,buffered_hex='')

def fixture():
    refs,_=c.references(PACKAGE);cases=[]
    for code in range(4):
        gold,path,pin=refs[code];known=gold['generated_tokens'][:4]
        for repeat in(1,2):
            wire=Wire()
            def probe(label):
                wire.exchange(label+'-clear',tx(2),0x82);wire.exchange(label+'-empty-step',tx(1),0xc1)
                wire.exchange(label+'-append',tx(0,378),0x80)
                for i,token in enumerate(known):wire.exchange(label+f'-step-{i+1}',tx(1),0x81,token)
            wire.exchange('initial-clear',tx(2),0x82)
            wire.exchange('settings',packet(bytes([0xa5,3,code])+int(c.SEED,16).to_bytes(16,'little')),0x83,code)
            probe('before');wire.exchange('long-clear',tx(2),0x82);wire.exchange('prompt-1',tx(0,378),0x80)
            for i,token in enumerate(gold['generated_tokens']):wire.exchange(f'long-step-{i+1}',tx(1),0x81,token)
            probe('after-1');probe('after-2');wire.exchange('final-clear',tx(2),0x82);wire.quiet()
            cases.append(dict(label=f'around128-t{code}-seed-a-run{repeat}',case='around128',temperature=c.TEMPS[code],seed=c.SEED,
                repeat_index=repeat,prompt_tokens=[378],reference_path=path,reference_sha256=pin,
                source_reference_sha256=gold['source_reference_receipt_sha256'],generated_tokens=gold['generated_tokens'][:],commands=154,
                probe_exact_outputs=12,empty_step_rejections=3,first_step_seconds=.0201,cached_step_seconds=[.0201]*127,
                all_outputs_match_independent_reference=True,settings_applied_once_per_case=True,
                intra_case_clear_probes_retain_and_rewind_settings=True,full_sequence_matches_prior_run=repeat==2,
                final_clear_acknowledged=True,image_sha256=c.IMAGE_SHA,passed=True,source_uart_sha256='a'*64,wire=wire.rows))
    final=Wire();final.exchange('restore-initial-clear',tx(2),0x82)
    final.exchange('settings',packet(bytes([0xa5,3,0])+bytes(16)),0x83);final.exchange('append',tx(0,378),0x80)
    for i,token in enumerate((200,15,103)):final.exchange(f'step-{i+1}',tx(1),0x81,token)
    final.exchange('restore-final-clear',tx(2),0x82);final.quiet()
    return dict(schema='seeded-around-control-public-v1',passed=True,image_sha256=c.IMAGE_SHA,model_image_sha256=c.MODEL_SHA,
        hardware_inputs_sha256=c.INPUTS_SHA,source_reference_inventory_sha256=c.REFERENCE_SHA,
        source_plan_sha256=c.SOURCE_PLAN_SHA or'1'*64,source_finished_sha256=c.SOURCE_FINISHED_SHA or'2'*64,
        source_runner_sha256=c.SOURCE_RUNNER_SHA,source_command_generator_sha256=c.ORIGINAL_SHA,
        runtime_pinned_files=21,runtime_pin_scope=c.PIN_SCOPE,per_command_deadline_seconds=120,cases=cases,
        main_reference_outputs=1024,probe_reference_outputs=96,final_greedy_reference_outputs=3,total_reference_outputs=1123,
        case_commands=1232,final_restoration_commands=7,final_greedy_wire=final.rows,final_greedy_source_uart_sha256='b'*64,
        claims=dict(c.CLAIMS))

class AroundControlEvidenceTests(unittest.TestCase):
    def test_complete_synthetic_baseline_controls_and_actual_bindings(self):
        archive=PACKAGE/c.RECORD;before=archive.read_bytes()if archive.exists()else None
        result=c.validate(fixture(),PACKAGE);self.assertEqual(result['commands'],1239)
        self.assertEqual(result['total_reference_outputs'],1123);c.check_bindings(PACKAGE)
        self.assertEqual(archive.read_bytes()if archive.exists()else None,before)

    def test_no_qualification_before_every_actual_origin_pin(self):
        for missing in('ARCHIVE_SHA','SOURCE_PLAN_SHA','SOURCE_FINISHED_SHA','SOURCE_RUNNER_SHA'):
            values={k:'f'*64 for k in('ARCHIVE_SHA','SOURCE_PLAN_SHA','SOURCE_FINISHED_SHA','SOURCE_RUNNER_SHA')};values[missing]=None
            with self.subTest(missing=missing),patch.multiple(c,**values),patch.object(Path,'read_bytes',side_effect=AssertionError('must refuse before archive access')):
                with self.assertRaisesRegex(ValueError,'No completed physical around'):c.check(PACKAGE)

    def test_actual_wire_crc_tokens_empty_rejection_replay_and_timings(self):
        base=fixture()
        for mutation in('crc','main-token','probe-token','empty-step','seed','temperature','missing-clear','extra',
                         'order','label','nan','duration','timeline','quiet','partial'):
            with self.subTest(mutation=mutation):
                data=copy.deepcopy(base);wire=data['cases'][3]['wire']
                def row(event,label):return next(x for x in wire if x['event']==event and x['operation']==label)
                if mutation=='crc':row('tx','settings')['frame_hex']=row('tx','settings')['frame_hex'][:-2]+'ff'
                elif mutation=='main-token':row('rx','long-step-72')['frame_hex']=rx(0x81,1)
                elif mutation=='probe-token':row('rx','after-2-step-2')['frame_hex']=rx(0x81,17)
                elif mutation=='empty-step':row('rx','before-empty-step')['frame_hex']=rx(0x81,200)
                elif mutation=='seed':row('tx','settings')['frame_hex']=c.settings(1,int(c.SEED,16)^(1<<120))
                elif mutation=='temperature':row('tx','settings')['frame_hex']=c.settings(3)
                elif mutation=='missing-clear':wire.remove(row('rx','final-clear'))
                elif mutation=='extra':wire.append(copy.deepcopy(wire[-1]))
                elif mutation=='order':wire[3],wire[4]=wire[4],wire[3]
                elif mutation=='label':row('operation','long-step-1')['operation']='different'
                elif mutation=='nan':row('operation','long-step-1')['seconds']=float('nan')
                elif mutation=='duration':row('operation','long-step-1')['seconds']+=.1
                elif mutation=='timeline':row('operation','long-step-1')['elapsed_ns']=0
                elif mutation=='quiet':wire[-1]['requested_seconds']=0
                else:wire[-1]['buffered_hex']='5a'
                with self.assertRaises(ValueError):c.validate(data,PACKAGE)

    def test_metadata_origins_scope_restoration_and_final_pinned_fixture(self):
        with patch.object(c,'SOURCE_PLAN_SHA','1'*64),patch.object(c,'SOURCE_FINISHED_SHA','2'*64):
            base=fixture();self.assertTrue(c.validate(base,PACKAGE)['passed'])
            for mutation in('plan','finished','runner','generator','model','reference','repeat','probes','rejections',
                             'count','source-count','deadline','scope','final-clear','final-temperature','claim','unknown'):
                with self.subTest(mutation=mutation):
                    data=copy.deepcopy(base)
                    if mutation=='plan':data['source_plan_sha256']='0'*64
                    elif mutation=='finished':data['source_finished_sha256']='0'*64
                    elif mutation=='runner':data['source_runner_sha256']='0'*64
                    elif mutation=='generator':data['source_command_generator_sha256']='0'*64
                    elif mutation=='model':data['model_image_sha256']='0'*64
                    elif mutation=='reference':data['cases'][0]['reference_path']='../../private'
                    elif mutation=='repeat':data['cases'][1]['generated_tokens'][5]^=1
                    elif mutation=='probes':data['cases'][0]['probe_exact_outputs']=8
                    elif mutation=='rejections':data['cases'][0]['empty_step_rejections']=0
                    elif mutation=='count':data['total_reference_outputs']+=1
                    elif mutation=='source-count':data['runtime_pinned_files']=91
                    elif mutation=='deadline':data['per_command_deadline_seconds']=3600
                    elif mutation=='scope':data['runtime_pin_scope']='whole native hardware proof'
                    elif mutation=='final-clear':data['final_greedy_wire'][-3]['frame_hex']=rx(0x81,200)
                    elif mutation=='final-temperature':data['final_greedy_wire'][3]['frame_hex']=c.settings(2)
                    elif mutation=='claim':data['claims']['timing_qualified']=True
                    else:data['private_path']='/private/not-published'
                    with self.assertRaises(ValueError):c.validate(data,PACKAGE)
        with patch.object(c,'SOURCE_PLAN_SHA','c'*64),patch.object(c,'SOURCE_FINISHED_SHA','d'*64):
            self.assertTrue(c.validate(fixture(),PACKAGE)['passed'])

if __name__=='__main__':unittest.main(verbosity=2)

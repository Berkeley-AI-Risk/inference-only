"""Synthetic adversarial browser-evidence fixtures; no UI, server or board.

Passing these tests checks archive-validator sensitivity. It does not create or
qualify an actual browser result; check() remains closed while pins are None.
"""
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('_browser_check_test',HERE/'check_seeded_browser.py')
check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)
PACKAGE=HERE.parent
PIN='a'*64

def wire(result):
    rows=[];ns=-100_000
    def emit(event,**values):
        nonlocal ns
        ns+=100_000;rows.append(dict(event=event,sequence=len(rows)+1,elapsed_ns=ns,**values))
    for op,tx,kind,token,operand in check.case_commands(result):
        emit('command_intent',label=op,hex=tx);emit('raw_chunk',direction='tx',hex=tx)
        response=check.reply(kind,token)
        emit('raw_chunk',direction='rx',hex=response[:4]);emit('raw_chunk',direction='rx',hex=response[4:])
        emit('decoded',kind='normal',response=kind,token=token,frame_hex=response)
        if op=='settings':emit('sampling_settings',temperature=result['temperature'],seed=result['seed']or'0x'+'0'*32,seed_used=result['seed_used'])
        else:emit('command_result',operation=op,operand=operand,token=token if op=='step'else None,seconds=.05)
    return rows

def fixture():
    cases=[]
    for number,(label,temp,seed,requested)in enumerate(check.CASES):
        used_seed=check.SEED_A if label=='automatic-1'else check.SEED_B if label=='automatic-2'else seed
        path,pin,gold=check.golden(PACKAGE,temp,used_seed)
        n=5 if label=='stopped-t1-b'else 3
        tokens=gold['generated_tokens'][:n];arrivals=[1.1+i*.1 for i in range(n)]
        result=dict(state='stopped'if label=='stopped-t1-b'else'complete',prompt='around',prompt_tokens=[378],generated=tokens,
            step_seconds=[.05]*n,arrivals_seconds=arrivals,text='around synthetic fixture '+label,uploaded=1,requested=requested,
            first_token_seconds=arrivals[0],elapsed_seconds=arrivals[-1]+.05,clear_acknowledged=True,
            stop_reason='Stopped by you'if label=='stopped-t1-b'else'Requested token limit reached',error='',temperature=temp,
            seed=used_seed,seed_used=temp!='0',sampling_settings_applied=True,streaming_tokens_per_second=(n-1)/(arrivals[-1]-arrivals[0]))
        obs=dict(browser='Chrome',url=check.URL,observed_utc='2026-10-23T09:00:00+00:00',prompt_value='around',
            maximum_new_tokens_value=requested,temperature_value=temp,seed_input_value=''if seed=='auto'else check.SEED_B if temp=='0'else seed,
            temperature_displayed=temp,seed_displayed=used_seed,tokens_generated_displayed=n,story_displayed=result['text'],
            download_clicked=True,source_ui_snapshot_sha256=PIN)
        if label=='stopped-t1-b':obs.update(before_stop_tokens_generated=2,before_stop_state='generating',stop_clicked=True,source_before_stop_snapshot_sha256=PIN)
        if seed=='auto':
            reference=dict(kind='fresh-portable',temperature=temp,seed=used_seed,prompt_tokens=[378],generated_tokens=gold['generated_tokens'][:3],
                head_rows_sha256=gold['head_rows_sha256'][:3],final_prng_state=gold['final_prng_state'],final_kv_sha256=gold['final_kv_sha256'],
                evaluated_positions=3,source_inventory_sha256=check.REFERENCE_SHA,source_receipt_sha256=PIN,engine='scalar')
        else:reference=dict(kind='packaged',path=path,sha256=pin)
        cases.append(dict(label=label,result=result,observation=obs,wire=wire(result),connection_started='new'if number in(0,9)else'reused',
            source_download_sha256=PIN,source_backend_log_sha256=PIN,source_observation_sha256=PIN,reference=reference))
    setup=dict(recipient_manifest_sha256=PIN,recipient_files=1302,strict_inventory_verified_before_runtime=True,release_files_unchanged_after_browser=True,
        model_readback=dict(whole_flash_bytes=16777216,model_bytes=7265984,model_start=8392704,model_end_exclusive=15658688,
            model_sha256=check.MODEL_SHA,full_array_sha256=check.FLASH_SHA,reported_crc32='28e34a2f',other_bytes='FF',read_command_hex='52',
            single_fresh_physical_read=True,all_model_and_erased_region_bytes_equal=True,flash_modified=False,new_independent_factory_backup_pair=False,
            source_summary_sha256=PIN,source_receiver_receipt_sha256=PIN,source_reader_load_sha256=PIN,source_readback_verifier_sha256=PIN,
            receiver_source_sha256=check.READBACK_SOURCES['maintenance/flash-reader/host/read_factory_flash.py'],checker_source_sha256=check.READBACK_SOURCES['tools/check_flash_layout.py']),
        sram_reload=dict(image_sha256=check.IMAGE_SHA,sram_load_reported=True,flash_modified=False,configuration_independently_attested=False,
            verified_backup_files=4,source_receipt_sha256=PIN,source_association_sha256=PIN),
        qualification=dict(operations=45,exact_tokens=19,transactions=check.qualifier_commands(),source_profile_sha256=PIN,source_uart_sha256=PIN),
        launcher=dict(url=check.URL,loopback_only=True,dependencies={'streamlit':'1.64.0','tokenizers':'0.23.2'},
            argv=['python','-B','-m','streamlit','run','host-app/streamlit_app.py','--server.address','127.0.0.1','--server.port','8507','--server.headless','true'],source_record_sha256=PIN,source_log_sha256=PIN),
        health=dict(status=200,body='ok',source_receipt_sha256=PIN))
    disconnect=dict(browser='Chrome',url=check.URL,disconnect_clicked=True,disconnect_button_disabled=True,uart_ownership_queried=True,
        uart_owner_exit=1,source_ui_snapshot_sha256=PIN,source_ownership_receipt_sha256=PIN)
    return dict(schema='seeded-ordinary-browser-public-v1',passed=True,scope=check.SCOPE,source_sha256=copy.deepcopy(check.SOURCES),
        image_sha256=check.IMAGE_SHA,hardware_inputs_sha256=check.INPUTS_SHA,model_image_sha256=check.MODEL_SHA,setup=setup,cases=cases,
        disconnect=disconnect,counts=dict(cases=10,generated_tokens=32,wire_commands=72,qualifier_exact_tokens=19,automatic_reference_runs=2),
        source_inputs_sha256=check.SOURCE_INPUTS_SHA or PIN,source_finished_sha256=check.SOURCE_FINISHED_SHA or PIN,
        claims=dict(actual_browser=True,listening_server=True,physical_fpga_backend=True,operator_ui_observations=True,mocked_uart=False,
            software_inference_in_app=False,streamlit_apptest=False,checker_replays_browser=False,checker_replays_model=False,
            physical_configuration_attested=False,timing_qualified=False,flash_modified=False,model_flash_reinstalled=False))


class BrowserEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.original=fixture()

    def test_synthetic_consistent_record_and_unfinished_scaffold(self):
        result=check.validate(copy.deepcopy(self.original),PACKAGE)
        self.assertEqual(result['cases'],10);self.assertEqual(result['reference_matching_outputs'],32)
        self.assertFalse(result['checker_drives_browser'])
        with patch.object(check,'ARCHIVE_SHA',None):
            with self.assertRaisesRegex(ValueError,'not complete/pinned'):check.check(Path('/not-a-browser-result'))

    def test_raw_frames_chunks_crc_settings_and_command_order(self):
        for change in('crc','reply','missing-byte','extra-byte','settings','missing-settings','order','timing'):
            with self.subTest(change=change):
                data=copy.deepcopy(self.original);rows=data['cases'][0]['wire']
                if change=='crc':rows[2]['hex']='5a00'
                elif change=='reply':
                    r=next(r for r in rows if r['event']=='decoded'and r['response']==0x81);r['token']^=1
                elif change=='missing-byte':rows[3]['hex']=rows[3]['hex'][:-2]
                elif change=='extra-byte':rows[3]['hex']+='00'
                elif change=='settings':
                    r=next(r for r in rows if r['event']=='raw_chunk'and r['direction']=='tx'and len(r['hex'])==40);r['hex']=check.settings(3,check.SEED_A)
                elif change=='missing-settings':
                    del rows[6:12]
                    for i,r in enumerate(rows,1):r['sequence']=i
                elif change=='order':rows[2],rows[3]=rows[3],rows[2]
                else:next(r for r in rows if r['event']=='command_result'and r['operation']=='step')['seconds']=.08
                with self.assertRaises(ValueError):check.validate(data,PACKAGE)

    def test_ui_reference_stop_recovery_and_claim_mutations(self):
        for change in('ui-seed','ui-count','ui-text','seed-reuse','reference','greedy-settings','stop-before-output',
                       'stop-complete','stop-not-active','connection','disconnect','apptest-claim','count','rate','source','private-field'):
            with self.subTest(change=change):
                data=copy.deepcopy(self.original)
                if change=='ui-seed':data['cases'][0]['observation']['seed_displayed']=check.SEED_B
                elif change=='ui-count':data['cases'][0]['observation']['tokens_generated_displayed']=2
                elif change=='ui-text':data['cases'][0]['observation']['story_displayed']='different displayed story'
                elif change=='seed-reuse':
                    data['cases'][7]=copy.deepcopy(data['cases'][6]);data['cases'][7]['label']='automatic-2'
                elif change=='reference':data['cases'][6]['reference']['generated_tokens'][0]^=1
                elif change=='greedy-settings':
                    rows=data['cases'][1]['wire'];next(r for r in rows if r['event']=='sampling_settings')['seed']=check.SEED_A
                elif change=='stop-before-output':data['cases'][8]['observation']['before_stop_tokens_generated']=0
                elif change=='stop-complete':data['cases'][8]['result']['state']='complete'
                elif change=='stop-not-active':data['cases'][8]['observation']['before_stop_state']='complete'
                elif change=='connection':data['cases'][9]['connection_started']='reused'
                elif change=='disconnect':data['disconnect']['uart_owner_exit']=0
                elif change=='apptest-claim':data['claims']['streamlit_apptest']=True
                elif change=='count':data['counts']['generated_tokens']+=1
                elif change=='rate':data['cases'][0]['result']['streaming_tokens_per_second']*=2
                elif change=='source':data['source_sha256']['host-app/runtime_profile.py']='0'*64
                else:data['cases'][0]['result']['private_log_path']='/private/unpublished'
                with self.assertRaises(ValueError):check.validate(data,PACKAGE)

    def test_synthetic_provenance_checks_remain_effective_after_public_pinning(self):
        data=copy.deepcopy(self.original)
        with patch.object(check,'SOURCE_INPUTS_SHA',data['source_inputs_sha256']),patch.object(check,'SOURCE_FINISHED_SHA',data['source_finished_sha256']):
            check.validate(copy.deepcopy(data),PACKAGE)
            for field in('source_inputs_sha256','source_finished_sha256'):
                changed=copy.deepcopy(data);changed[field]='0'*64
                with self.assertRaisesRegex(ValueError,'provenance'):check.validate(changed,PACKAGE)

    def test_seed_input_spellings_preserve_canonical_display_and_wire_value(self):
        for spelling in(check.SEED_A_INPUT,check.SEED_A,str(int(check.SEED_A,0))):
            data=copy.deepcopy(self.original);data['cases'][0]['observation']['seed_input_value']=spelling
            check.validate(data,PACKAGE)
        for field in('result','observation'):
            data=copy.deepcopy(self.original)
            data['cases'][0][field]['seed'if field=='result'else'seed_displayed']=check.SEED_A_INPUT
            with self.assertRaises(ValueError):check.validate(data,PACKAGE)
        data=copy.deepcopy(self.original);data['cases'][0]['observation']['seed_input_value']=check.SEED_B
        with self.assertRaisesRegex(ValueError,'Entered seed value'):check.validate(data,PACKAGE)

    def test_recipient_setup_and_actual_source_revision(self):
        for change in('load','flash','qualifier','health','loopback','dependencies','source-edited','readback-hash','readback-not-fresh','readback-write'):
            with self.subTest(change=change):
                data=copy.deepcopy(self.original)
                if change=='load':data['setup']['sram_reload']['sram_load_reported']=False
                elif change=='flash':data['setup']['sram_reload']['flash_modified']=True
                elif change=='qualifier':data['setup']['qualification']['transactions'].pop()
                elif change=='health':data['setup']['health']['status']=503
                elif change=='loopback':data['setup']['launcher']['loopback_only']=False
                elif change=='dependencies':data['setup']['launcher']['dependencies']['streamlit']='unqualified'
                elif change=='readback-hash':data['setup']['model_readback']['full_array_sha256']='0'*64
                elif change=='readback-not-fresh':data['setup']['model_readback']['single_fresh_physical_read']=False
                elif change=='readback-write':data['setup']['model_readback']['flash_modified']=True
                else:data['setup']['release_files_unchanged_after_browser']=False
                with self.assertRaises(ValueError):check.validate(data,PACKAGE)
        with tempfile.TemporaryDirectory(prefix='browser-evidence-source-')as directory:
            package=Path(directory)
            for name in check.SOURCES:
                target=package/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(PACKAGE/name,target)
            target=package/'host-app/runtime_profile.py';target.write_bytes(target.read_bytes()+b'\n# synthetic source mutation\n')
            with self.assertRaisesRegex(ValueError,'Changed browser source'):check.validate(copy.deepcopy(self.original),package)


if __name__=='__main__':unittest.main(verbosity=2)

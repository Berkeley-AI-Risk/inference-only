#!/usr/bin/env python3
"""Check archived ordinary-browser/FPGA observations, downloads and raw bytes.

No browser, local server, UART, model or compiler is invoked. UI observations
remain operator observations; hashes and matching bytes do not attest silicon
or independently prove that a browser action occurred.
"""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
RECORD='evidence/seeded-sampling/browser.json'
ARCHIVE_SHA='f2996c088dec588eaefd50a2296a1f527d6b769e324544b97f854d831d862019'
SOURCE_INPUTS_SHA='9efac7360f7bf2c3a77bf8c8b2d96f1538361a7908d9670f2f2e9570bc767e8c'
SOURCE_FINISHED_SHA='90f41552dab20136c5f07f42e456a5719d3ce47d758a83bf13ed606b51610738'
IMAGE_SHA='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
MODEL_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
INPUTS_SHA='26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831'
REFERENCE_SHA='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
FLASH_SHA='b6be312296b01d4eb2f985cd71f90d110a2a632c42ca0b4698dc8c9832765a25'
READBACK_SOURCES={'prebuilt/flash-reader/readonly_flash_reader.fs':'5c0736fff07d5550dc2b563df009bc9f8922a100b38cbb93db5cf2a7eb7824c9',
    'maintenance/flash-reader/host/read_factory_flash.py':'e4ff0907724a86fa4466c274c59b47da99bd23eef64ed70d2c5b71aa95decf6d',
    'tools/check_flash_layout.py':'13e17eebfe62827fa2f72bce465ea0b76665bbf9c7a081050c3fa46b69ec46f5'}
URL='http://127.0.0.1:8507'
SEED_A='0x99aabbccddeeff001122334455667788'
SEED_A_INPUT='0x0099aabbccddeeff001122334455667788'
SEED_B='0xfefdfcfbfaf9f8f70102030405060708'
TEMPS=('0','0.5','1','2')
EOS=1
CASES=(('fixed-t1-a','1',SEED_A,3),('greedy-after-sampling','0',None,3),
    ('fixed-t05-a','0.5',SEED_A,3),('fixed-t2-a','2',SEED_A,3),
    ('repeat-t1-a','1',SEED_A,3),('fixed-t1-b','1',SEED_B,3),
    ('automatic-1','1','auto',3),('automatic-2','1','auto',3),
    ('stopped-t1-b','1',SEED_B,128),('resumed-greedy','0',None,3))
SOURCES={
    'host-app/streamlit_app.py':'1755664f718fe29b91b510b5aa6b95ad79c9a8dbf05289e44005495f174ca844',
    'host-app/fpga_backend.py':'cd8a3c64dd6211d5d866666cda57132fa0f140723ceee013849c894fa3457171',
    'host-app/runtime_profile.py':'8921585f9d3b2b3643f099797d884eb4f315ee19ecf3bb409c9be8c5ede8d7f2',
    'host-app/qualify_board.py':'9e590c6ec49fe2ce02b3c6eb711e2971d53186d36dbbb9205e32f888a96cc6ee',
    'host-app/sampling_protocol.py':'e754440e991e3a84ea246292080be9a955957be6bedbc6a82ed38a67c54fae75',
    'host-app/token_machine_uart.py':'00d18e9411d52f7d7414b96cbf28d29db38d1c5008705dfb4194f268cbb11cbf',
    'host-app/uart_channel.py':'b56f591d546bbc55ad0b8de3d6a5aa179206a3b5c813a6da1ce86aca4a2e3c0e',
    'host-app/start_local_server.py':'33e2e8002d7bc62873a9ed850f4c9018037deae78dd2412dd8f1aacfbf5b5dbe',
    'host-app/.streamlit/config.toml':'85703c45c372948241fcfaa1a9411e9aa31159a74f6ddedcfecad8d47bc94c6c',
    'host-app/assets/tokenizer.json':'01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51',
    'host-app/requirements.txt':'f22d07d97ecfc2ddfa1031acb721944f63d983e56cc665b3845c4e49418daebd',
    'variants/seeded-sampling/tools/settings_codec.py':'6e2f5cf5310700888187d3d4d9af1921e2150adbe865773874bdbe7eaecc326a'}
RESULT_FIELDS='state prompt prompt_tokens generated step_seconds arrivals_seconds text uploaded requested first_token_seconds elapsed_seconds clear_acknowledged stop_reason error temperature seed seed_used sampling_settings_applied streaming_tokens_per_second'
OBS_FIELDS='browser url observed_utc prompt_value maximum_new_tokens_value temperature_value seed_input_value temperature_displayed seed_displayed tokens_generated_displayed story_displayed download_clicked source_ui_snapshot_sha256'
SCOPE=('Actual listening Streamlit application driven in Chrome, with operator/Cua observations, downloaded run records and physical FPGA UART bytes. '
    'This checker validates the archived observations and byte/reference bindings; it does not drive a browser, rerun the model or attest physical configuration.')

def need(ok,message):
    if not ok:raise ValueError(message)
def fields(value,names):need(type(value)is dict and set(value)==set(names.split()),'Unexpected browser evidence fields')
def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def digest(value):need(type(value)is str and re.fullmatch('[0-9a-f]{64}',value)is not None,'Invalid provenance digest')
def instant(value):
    try:date=datetime.datetime.fromisoformat(value)
    except(TypeError,ValueError):raise ValueError('Invalid observed UTC timestamp')
    need(date.tzinfo is not None and date.utcoffset()==datetime.timedelta(0),'Observation timestamp must identify UTC')
def positive(value):need(type(value)in(int,float)and math.isfinite(value)and value>0,'Invalid browser timing')
def crc8(raw):
    value=0
    for byte in raw:
        value^=byte
        for _ in range(8):value=((value<<1)^(7 if value&128 else 0))&255
    return value
def frame(body):return (body+bytes((crc8(body),))).hex()
def legacy(op,operand=0):return frame(bytes((0xa5,op,operand&255,operand>>8)))
def reply(kind,operand=0):return frame(bytes((0x5a,kind,operand&255,operand>>8)))
def settings(code,seed):return frame(bytes((0xa5,3,code))+int(seed,0).to_bytes(16,'little'))

def case_commands(result):
    code=TEMPS.index(result['temperature']);seed=result['seed']or'0x'+32*'0'
    return [('clear',legacy(2),0x82,0,0),('settings',settings(code,seed),0x83,code,code),
        ('append',legacy(0,378),0x80,0,378)]+[
        ('step',legacy(1),0x81,token,0)for token in result['generated']]+[('clear',legacy(2),0x82,0,0)]

def validate_wire(rows,commands,result):
    """Preserve every raw RX chunk, independently assembling each response."""
    need(type(rows)is list,'Missing raw browser wire data')
    previous=-1
    for sequence,row in enumerate(rows,1):
        need(row['sequence']==sequence and type(row['elapsed_ns'])is int and row['elapsed_ns']>previous
             and(sequence!=1 or row['elapsed_ns']==0),'Wire order/timeline differs')
        previous=row['elapsed_ns']
    cursor=0;durations=[]
    def take(event,names):
        nonlocal cursor
        need(cursor<len(rows),'Truncated browser wire trace')
        row=rows[cursor];cursor+=1
        fields(row,names+' sequence elapsed_ns');need(row['event']==event,'Browser wire event order differs');return row
    for op,tx,kind,token,operand in commands:
        intent=take('command_intent','event label hex')
        need(intent['label']==op and intent['hex']==tx,'Command intent/settings differ')
        sent=take('raw_chunk','event direction hex')
        need(sent['direction']=='tx'and sent['hex']==tx,'Actual sent frame differs')
        received=bytearray()
        while cursor<len(rows)and rows[cursor]['event']=='raw_chunk':
            row=take('raw_chunk','event direction hex')
            need(row['direction']=='rx','Unexpected extra transmission')
            try:chunk=bytes.fromhex(row['hex'])
            except(TypeError,ValueError):raise ValueError('Malformed raw RX hex')
            need(0<len(chunk)<=5-len(received),'Extra/noise response bytes');received.extend(chunk)
        need(received.hex()==reply(kind,token),'Raw reply/CRC/generated token differs')
        decoded=take('decoded','event kind response token frame_hex')
        need(decoded['kind']=='normal'and decoded['response']==kind and decoded['token']==token
             and decoded['frame_hex']==received.hex(),'Decoded reply disagrees with raw bytes')
        if op=='settings':
            row=take('sampling_settings','event temperature seed seed_used')
            need(row['temperature']==result['temperature']and row['seed']==(result['seed']or'0x'+32*'0')
                 and row['seed_used']is result['seed_used'],'Applied settings differ from download')
        else:
            row=take('command_result','event operation operand token seconds')
            need(row['operation']==op and row['operand']==operand and row['token']==(token if op=='step'else None),
                 'Command result differs')
            positive(row['seconds']);need(row['seconds']<(120 if op=='step'else 10),'Command exceeded app deadline')
            if op=='step':durations.append(row['seconds'])
    need(cursor==len(rows),'Unexpected trailing wire event')
    need(durations==result['step_seconds'],'Downloaded timings disagree with raw command results')
    return len(commands)

def golden(package,temperature,seed):
    code=TEMPS.index(temperature);name=f'around128-t{code}-seed-'+('b'if seed==SEED_B else'a')+'.json'
    path='reference/seeded-sampling/goldens/'+name;raw=(package/path).read_bytes()
    source_raw=(package/'reference/seeded-sampling/SOURCE.json').read_bytes()
    need(sha(source_raw)==REFERENCE_SHA,'Changed exact-reference source inventory')
    index_raw=(package/'reference/seeded-sampling/goldens/INDEX.json').read_bytes()
    need(sha(index_raw)==json.loads(source_raw)['files']['goldens/INDEX.json'],'Changed exact-reference golden index')
    index=json.loads(index_raw)
    need(index['files'][name]==dict(bytes=len(raw),sha256=sha(raw)),'Changed packaged golden')
    return path,sha(raw),json.loads(raw)

def qualifier_commands():
    rows=[('clear',0,None,None),('settings',0,None,0),('append',378,None,None)]
    rows += [('step',0,t,None)for t in (200,15,103,157)]+[('clear',0,None,None)]
    sequences={1:(247,130,32),2:(357,3898,104),3:(3436,4007,141)}
    for code in(1,2,3):
        rows += [('settings',code,None,int(SEED_A,0)),('append',378,None,None)]
        rows += [('step',0,t,None)for t in sequences[code]]+[('clear',0,None,None)]
        if code==2:rows += [('append',378,None,None)]+[('step',0,t,None)for t in sequences[code]]+[('clear',0,None,None)]
    for code,token in((1,13),(2,13),(3,2)):
        rows += [('settings',code,None,int(SEED_B,0)),('append',378,None,None),('step',0,token,None),('clear',0,None,None)]
    rows += [('settings',0,None,0),('clear',0,None,None)]
    return [dict(tx_hex=settings(operand,f'0x{seed:032x}')if op=='settings'else legacy({'clear':2,'append':0,'step':1}[op],operand),
        rx_hex=reply(0x83 if op=='settings'else {'clear':0x82,'append':0x80,'step':0x81}[op],
                     operand if op=='settings'else token if op=='step'else 0))for op,operand,token,seed in rows]

def validate_observation(obs,label,temp,seed,requested,result):
    tokens=result['generated']
    extra=' before_stop_tokens_generated before_stop_state stop_clicked source_before_stop_snapshot_sha256'if label=='stopped-t1-b'else''
    fields(obs,OBS_FIELDS+extra)
    need(obs['browser']=='Chrome'and obs['url']==URL and isinstance(obs['observed_utc'],str)
         and obs['prompt_value']=='around'and obs['maximum_new_tokens_value']==requested and obs['temperature_value']==temp
         and obs['temperature_displayed']==temp and obs['seed_displayed']==result['seed']
         and obs['tokens_generated_displayed']==len(tokens)and obs['story_displayed']==result['text']
         and obs['download_clicked']is True,'Browser observation disagrees with download')
    need(isinstance(obs['seed_input_value'],str)and len(obs['seed_input_value'])<=40,'Invalid observed seed field')
    if temp!='0':
        if seed=='auto':need(obs['seed_input_value']=='','Automatic seed input was not empty')
        else:
            try:entered=int(obs['seed_input_value'].strip(),0)
            except ValueError:raise ValueError('Invalid entered seed spelling')
            need(entered==int(seed,0),'Entered seed value differs')
    instant(obs['observed_utc']);digest(obs['source_ui_snapshot_sha256'])
    if label=='stopped-t1-b':
        need(type(obs['before_stop_tokens_generated'])is int and 0<obs['before_stop_tokens_generated']<=len(tokens)<128
             and obs['before_stop_state']=='generating'and obs['stop_clicked']is True,'Stop was not observed after output while active')
        digest(obs['source_before_stop_snapshot_sha256'])

def validate_setup(setup):
    fields(setup,'recipient_manifest_sha256 recipient_files strict_inventory_verified_before_runtime release_files_unchanged_after_browser model_readback sram_reload qualification launcher health')
    digest(setup['recipient_manifest_sha256']);need(type(setup['recipient_files'])is int and setup['recipient_files']>=1199,'Wrong recipient package census')
    need(setup['strict_inventory_verified_before_runtime']is True and setup['release_files_unchanged_after_browser']is True,'Missing clean recipient checks')
    readback=setup['model_readback']
    fields(readback,'whole_flash_bytes model_bytes model_start model_end_exclusive model_sha256 full_array_sha256 reported_crc32 other_bytes read_command_hex single_fresh_physical_read all_model_and_erased_region_bytes_equal flash_modified new_independent_factory_backup_pair source_summary_sha256 source_receiver_receipt_sha256 source_reader_load_sha256 source_readback_verifier_sha256 receiver_source_sha256 checker_source_sha256')
    need(readback['whole_flash_bytes']==16777216 and readback['model_bytes']==7265984 and readback['model_start']==8392704
         and readback['model_end_exclusive']==15658688 and readback['model_sha256']==MODEL_SHA and readback['full_array_sha256']==FLASH_SHA
         and readback['reported_crc32']=='28e34a2f'and readback['other_bytes']=='FF'and readback['read_command_hex']=='52'
         and readback['single_fresh_physical_read']is True and readback['all_model_and_erased_region_bytes_equal']is True
         and readback['flash_modified']is False and readback['new_independent_factory_backup_pair']is False
         and readback['receiver_source_sha256']==READBACK_SOURCES['maintenance/flash-reader/host/read_factory_flash.py']
         and readback['checker_source_sha256']==READBACK_SOURCES['tools/check_flash_layout.py'],'Fresh physical model readback differs')
    for key in('source_summary_sha256','source_receiver_receipt_sha256','source_reader_load_sha256','source_readback_verifier_sha256'):digest(readback[key])
    reload=setup['sram_reload'];fields(reload,'image_sha256 sram_load_reported flash_modified configuration_independently_attested verified_backup_files source_receipt_sha256 source_association_sha256')
    need(reload['image_sha256']==IMAGE_SHA and reload['sram_load_reported']is True and reload['flash_modified']is False
         and reload['configuration_independently_attested']is False and reload['verified_backup_files']==4,'Wrong recipient SRAM reload scope')
    digest(reload['source_receipt_sha256']);digest(reload['source_association_sha256'])
    qual=setup['qualification'];fields(qual,'operations exact_tokens transactions source_profile_sha256 source_uart_sha256')
    need(qual['operations']==45 and qual['exact_tokens']==19 and qual['transactions']==qualifier_commands(),'Extended recipient registration differs')
    digest(qual['source_profile_sha256']);digest(qual['source_uart_sha256'])
    launch=setup['launcher'];fields(launch,'url loopback_only dependencies argv source_record_sha256 source_log_sha256')
    need(launch['url']==URL and launch['loopback_only']is True
         and launch['dependencies']=={'streamlit':'1.64.0','tokenizers':'0.23.2'}
         and launch['argv']==['python','-B','-m','streamlit','run','host-app/streamlit_app.py','--server.address','127.0.0.1','--server.port','8507','--server.headless','true'],
         'Ordinary app launcher/dependency scope differs')
    digest(launch['source_record_sha256']);digest(launch['source_log_sha256'])
    health=setup['health'];fields(health,'status body source_receipt_sha256')
    need(health['status']==200 and health['body'].strip()=='ok','Listening server health was not confirmed');digest(health['source_receipt_sha256'])

def validate(data,package=ROOT):
    package=Path(package)
    fields(data,'schema passed scope source_sha256 image_sha256 hardware_inputs_sha256 model_image_sha256 setup cases disconnect counts source_inputs_sha256 source_finished_sha256 claims')
    need(data['schema']=='seeded-ordinary-browser-public-v1'and data['passed']is True and data['scope']==SCOPE,'Wrong browser evidence scope')
    need(data['source_sha256']==SOURCES,'Browser source revision differs')
    for name,pin in SOURCES.items():
        path=package/name;need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Changed browser source: '+name)
    need(data['image_sha256']==IMAGE_SHA and data['hardware_inputs_sha256']==INPUTS_SHA and data['model_image_sha256']==MODEL_SHA,'Changed image/model/source')
    for key,expected in(('source_inputs_sha256',SOURCE_INPUTS_SHA),('source_finished_sha256',SOURCE_FINISHED_SHA)):
        digest(data[key])
        if expected is not None:need(data[key]==expected,'Changed original browser provenance')
    validate_setup(data['setup'])
    need(len(data['cases'])==10,'Missing browser scenario')
    counts=dict(cases=10,generated_tokens=0,wire_commands=0,qualifier_exact_tokens=19,automatic_reference_runs=2)
    auto_seeds=[]
    for i,(case,(label,temp,seed,requested))in enumerate(zip(data['cases'],CASES)):
        fields(case,'label result observation wire connection_started source_download_sha256 source_backend_log_sha256 source_observation_sha256 reference')
        need(case['label']==label,'Browser case order differs')
        for key in('source_download_sha256','source_backend_log_sha256','source_observation_sha256'):digest(case[key])
        result=case['result'];fields(result,RESULT_FIELDS)
        need(result['prompt']=='around'and result['prompt_tokens']==[378]and result['uploaded']==1
             and result['requested']==requested and result['temperature']==temp and result['seed_used']is(temp!='0')
             and result['sampling_settings_applied']is True and result['clear_acknowledged']is True and result['error']=='',
             'Downloaded prompt/settings/CLEAR differ')
        tokens=result['generated'];need(type(tokens)is list and 0<len(tokens)<=requested and all(type(t)is int and 0<=t<4019 for t in tokens),'Invalid downloaded output')
        if seed=='auto':
            need(type(result['seed'])is str and re.fullmatch('0x[0-9a-f]{32}',result['seed'])is not None,'Missing displayed automatic seed');auto_seeds.append(result['seed'])
        else:need(result['seed']==seed,'Wrong chosen/greedy seed')
        if temp!='0':need(re.fullmatch('0x[0-9a-f]{32}',result['seed'])is not None,'Positive seed display is not canonical')
        if label=='stopped-t1-b':
            need(result['state']=='stopped'and 0<len(tokens)<128 and result['stop_reason']=='Stopped by you','Stop did not interrupt generation')
        else:
            need(result['state']=='complete','Browser run did not complete')
            if EOS in tokens:need(tokens[-1]==EOS and tokens.index(EOS)==len(tokens)-1 and result['stop_reason']=='Model reached end of story','Browser EOS handling differs')
            else:need(len(tokens)==requested and result['stop_reason']=='Requested token limit reached','Browser token-limit handling differs')
        positive(result['elapsed_seconds']);need(len(result['step_seconds'])==len(result['arrivals_seconds'])==len(tokens),'Missing download timings')
        for seconds in result['step_seconds']+result['arrivals_seconds']:positive(seconds)
        arrivals=result['arrivals_seconds'];need(all(a<b for a,b in zip(arrivals,arrivals[1:]))and result['first_token_seconds']==arrivals[0]
             and result['elapsed_seconds']>=arrivals[-1],'Downloaded arrival timing differs')
        rate=result['streaming_tokens_per_second']
        need(rate is None if len(tokens)==1 else type(rate)in(int,float)and math.isclose(rate,(len(tokens)-1)/(arrivals[-1]-arrivals[0]),rel_tol=1e-12,abs_tol=1e-12),'Downloaded streaming rate arithmetic differs')
        validate_observation(case['observation'],label,temp,seed,requested,result)
        reference=case['reference']
        if seed=='auto':
            fields(reference,'kind temperature seed prompt_tokens generated_tokens head_rows_sha256 final_prng_state final_kv_sha256 evaluated_positions source_inventory_sha256 source_receipt_sha256 engine')
            need(reference['kind']=='fresh-portable'and reference['temperature']==temp and reference['seed']==result['seed']
                 and reference['prompt_tokens']==[378]and reference['engine']=='scalar'and reference['source_inventory_sha256']==REFERENCE_SHA
                 and len(reference['generated_tokens'])==requested and tokens==reference['generated_tokens'][:len(tokens)],'Automatic output differs from fresh exact model')
            need(len(reference['head_rows_sha256'])==requested and reference['evaluated_positions']==requested,'Automatic reference dimension differs')
            for pin in reference['head_rows_sha256']+[reference['final_kv_sha256'],reference['source_receipt_sha256']]:digest(pin)
            need(len(reference['final_prng_state'])==2 and all(re.fullmatch('0x[0-9a-f]{16}',v)for v in reference['final_prng_state']),'Automatic reference PRNG state differs')
        else:
            fields(reference,'kind path sha256');path,pin,gold=golden(package,temp,seed)
            need(reference==dict(kind='packaged',path=path,sha256=pin)and tokens==gold['generated_tokens'][:len(tokens)],'Output differs from packaged exact reference')
        need(case['connection_started']==('new'if i in(0,9)else'reused'),'Connection reuse/Stop release sequence differs')
        counts['wire_commands']+=validate_wire(case['wire'],case_commands(result),result);counts['generated_tokens']+=len(tokens)
    need(auto_seeds[0]!=auto_seeds[1],'Automatic seed was reused')
    need(data['cases'][0]['result']['generated']==data['cases'][4]['result']['generated'],'Chosen-seed browser replay differs')
    disconnect=data['disconnect'];fields(disconnect,'browser url disconnect_clicked disconnect_button_disabled uart_ownership_queried uart_owner_exit source_ui_snapshot_sha256 source_ownership_receipt_sha256')
    need(disconnect['browser']=='Chrome'and disconnect['url']==URL and all(disconnect[k]is True for k in('disconnect_clicked','disconnect_button_disabled','uart_ownership_queried'))
         and disconnect['uart_owner_exit']==1,'Disconnect/release observation differs')
    digest(disconnect['source_ui_snapshot_sha256']);digest(disconnect['source_ownership_receipt_sha256'])
    need(data['counts']==counts,'Browser evidence census differs')
    need(data['claims']==dict(actual_browser=True,listening_server=True,physical_fpga_backend=True,
        operator_ui_observations=True,mocked_uart=False,software_inference_in_app=False,streamlit_apptest=False,
        checker_replays_browser=False,checker_replays_model=False,physical_configuration_attested=False,
        timing_qualified=False,flash_modified=False,model_flash_reinstalled=False),'Unsupported browser qualification claim')
    return dict(passed=True,cases=10,reference_matching_outputs=counts['generated_tokens'],wire_commands=counts['wire_commands'],
        actual_browser_recorded=True,checker_drives_browser=False,checker_replays_model=False,hardware_access=False,
        ui_observations_are_operator_records=True,physical_configuration_attested=False)

def check(package=ROOT):
    need(all(pin is not None for pin in(ARCHIVE_SHA,SOURCE_INPUTS_SHA,SOURCE_FINISHED_SHA)),
         'Browser qualification is not complete/pinned; no physical result may be inferred from this scaffold')
    package=Path(package);raw=(package/RECORD).read_bytes();result=validate(json.loads(raw),package)
    need(sha(raw)==ARCHIVE_SHA,'Frozen browser archive differs')
    for name,pin in(('prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs',IMAGE_SHA),('assets/board1-real-semantic-image2048.bin',MODEL_SHA)):
        need(sha((package/name).read_bytes())==pin,'Changed image/model asset')
    for name,pin in READBACK_SOURCES.items():
        path=package/name
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Changed readback source/image')
    inventory=json.loads((package/'host-app/hardware-inputs-seeded-sampling.json').read_bytes())
    need(len(inventory)==91 and sha(canonical(inventory))==INPUTS_SHA,'Changed native source inventory')
    for name,pin in inventory.items():
        path=package/'variants/seeded-sampling/hardware'/name
        if name.startswith('project/official/')and not path.exists():continue
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Changed native source bytes')
    source_raw=(package/'reference/seeded-sampling/SOURCE.json').read_bytes()
    need(sha(source_raw)==REFERENCE_SHA,'Changed exact reference source inventory')
    source=json.loads(source_raw)
    for name,pin in source['files'].items():
        path=package/'reference/seeded-sampling'/name
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Changed portable reference source')
    for name,pin in source['package_inputs'].items():
        path=package/name
        need(path.is_file()and not path.is_symlink()and sha(path.read_bytes())==pin,'Changed exact-reference package input')
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(parser.parse_args().package),indent=2,sort_keys=True))

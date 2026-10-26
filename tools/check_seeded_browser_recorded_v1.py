"""Fresh current-image ordinary-browser status and evidence; stdlib/offline only.

Pending status credits no case. Completion requires newly pinned actual records;
no old image's output/Stop census or qualification flag is inherited.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re

SOURCE_REVIEWED=True
ROOT=Path(__file__).resolve().parents[1]
STATUS='evidence/seeded-sampling/current-browser.json'
ARCHIVE='evidence/seeded-sampling/current-browser-complete.json'
PROMPT_FIXTURE='evidence/seeded-sampling/browser-fixtures/prefix2048-prompt.json'
PROMPT_FIXTURE_SHA='175f84fba76e46d80bd61ac9ba480ce6613b6a3b52ef8c7f2df71cfa5f77137c'
STOP_PROMPT_FIXTURE='evidence/seeded-sampling/browser-fixtures/prefix2047-stop-prompt.json'
STOP_PROMPT_FIXTURE_SHA='ad974238e0c236f169b76baa8a44de9fad91b710aff1c386c0c8209b0a30194b'
STATUS_SCHEMA='long-context-current-browser-status-v4'
ARCHIVE_SCHEMA='long-context-current-browser-record-v4'
# Finalization may fill only these fresh-record pins after actual capture.
BROWSER_ARCHIVE_SHA='7af2a227616b6907c95fe65d3f8fa182df9fb2ba749bb28e19e624c46c74cf17'
BROWSER_INPUTS_SHA='a5fee88c2bacb63e7c7474ac74b4881f8727b71d1dd532810cc7f19795a22443'
BROWSER_FINISHED_SHA='1a35adb3680025b6bcd3a2a8fe37cb5a7d5c433bb5fd070eb92519494aa3c56c'
SCOPE=('Actual listening current-recipient Streamlit application driven in Chrome, with operator/Cua observations, downloaded run records and physical FPGA UART bytes. '
       'This checker validates recorded bytes/reference/source bindings; it does not drive a browser, rerun inference or attest the configured circuit.')
CASES=(('fixed-t1-a','1','A',3),('greedy-after-sampling','0',None,3),
 ('fixed-t05-a','0.5','A',3),('fixed-t2-a','2','A',3),('repeat-t1-a','1','A',3),
 ('fixed-t1-b','1','B',3),('automatic-1','1','auto',3),('automatic-2','1','auto',3),
 ('stopped-t1-b','1','B',128),('resumed-greedy','0',None,3),('prefix2048-greedy','0',None,1),
 ('prefix2047-stop','1','A',2))
SOURCE_PATHS=('host-app/streamlit_app.py','host-app/fpga_backend.py','host-app/runtime_profile.py',
 'host-app/qualify_board.py','host-app/sampling_protocol.py','host-app/token_machine_uart.py',
 'host-app/uart_channel.py','host-app/start_local_server.py','host-app/.streamlit/config.toml',
 'host-app/assets/tokenizer.json','host-app/requirements.txt','variants/seeded-sampling/tools/settings_codec.py')
MODEL_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
REFERENCE_SHA='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
FLASH_SHA='b6be312296b01d4eb2f985cd71f90d110a2a632c42ca0b4698dc8c9832765a25'
READBACK_SOURCES={'prebuilt/flash-reader/readonly_flash_reader.fs': '5c0736fff07d5550dc2b563df009bc9f8922a100b38cbb93db5cf2a7eb7824c9', 'maintenance/flash-reader/host/read_factory_flash.py': 'e4ff0907724a86fa4466c274c59b47da99bd23eef64ed70d2c5b71aa95decf6d', 'tools/check_flash_layout.py': '13e17eebfe62827fa2f72bce465ea0b76665bbf9c7a081050c3fa46b69ec46f5'}
URL='http://127.0.0.1:8507'
SEED_A='0x99aabbccddeeff001122334455667788'
SEED_B='0xfefdfcfbfaf9f8f70102030405060708'
TEMPS=('0', '0.5', '1', '2')
EOS=1
RESULT_FIELDS='state prompt prompt_tokens generated step_seconds arrivals_seconds text uploaded requested first_token_seconds elapsed_seconds clear_acknowledged stop_reason error temperature seed seed_used sampling_settings_applied streaming_tokens_per_second'
OBS_FIELDS='browser url observed_utc prompt_value maximum_new_tokens_value temperature_value seed_input_value temperature_displayed seed_displayed tokens_generated_displayed story_displayed download_clicked source_ui_snapshot_sha256'

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
        *[('append',legacy(0,token),0x80,0,token)for token in result['prompt_tokens']]]+[
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
            positive(row['seconds']);need(row['seconds']<(3600 if op=='step'else 10),'Command exceeded app deadline')
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

def validate_observation(obs,label,temp,seed,requested,result,prompt='around'):
    tokens=result['generated']
    stop_case=label in('stopped-t1-b','prefix2047-stop')
    extra=' before_stop_tokens_generated before_stop_state stop_clicked source_before_stop_snapshot_sha256'if stop_case else''
    fields(obs,OBS_FIELDS+extra)
    need(obs['browser']=='Chrome'and obs['url']==URL and isinstance(obs['observed_utc'],str)
         and obs['prompt_value']==prompt and obs['maximum_new_tokens_value']==requested and obs['temperature_value']==temp
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
    elif label=='prefix2047-stop':
        need(obs['before_stop_tokens_generated']==0 and obs['before_stop_state']=='generating'
             and obs['stop_clicked']is True and len(tokens)==1,'Long-prompt Stop was not clicked before first output')
        digest(obs['source_before_stop_snapshot_sha256'])

def validate_setup(setup,image_sha256):
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
    need(reload['image_sha256']==image_sha256 and reload['sram_load_reported']is True and reload['flash_modified']is False
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


def regular(package,name):
    need(type(name)is str and name and not name.startswith('/')and '\\'not in name
         and '..'not in Path(name).parts and Path(name).as_posix()==name,'Unsafe browser package path')
    path=Path(package)/name
    need(path.is_file()and not any(p.is_symlink()for p in(path,*path.parents)if p.is_relative_to(package)),
         'Missing/linked browser package input: '+name)
    return path


def identity(path):
    need(path.is_file()and not path.is_symlink(),'Missing/linked browser input')
    with path.open('rb')as stream:value=hashlib.file_digest(stream,'sha256').hexdigest()
    return dict(bytes=path.stat().st_size,sha256=value)


def read(package,name):
    return json.loads(regular(package,name).read_bytes())


def pending_status(candidate):
    """Construction metadata only: no credited case or qualifying receipt."""
    return dict(schema=STATUS_SCHEMA,state='pending',image_sha256=candidate['image_sha256'],
        model_image_sha256=candidate['model_image_sha256'],hardware_inputs_sha256=candidate['hardware_inputs_sha256'],
        host_source_inputs=candidate['host_source_inputs'],archive=None,
        source_inputs_receipt_sha256=None,source_finished_receipt_sha256=None,credited_cases=0)


def status_binding(status,candidate):
    fields(status,'schema state image_sha256 model_image_sha256 hardware_inputs_sha256 host_source_inputs '
           'archive source_inputs_receipt_sha256 source_finished_receipt_sha256 credited_cases')
    need(status['schema']==STATUS_SCHEMA and status['state']in('pending','complete'),'Wrong current browser status')
    for name in('image_sha256','model_image_sha256','hardware_inputs_sha256','host_source_inputs'):
        need(status[name]==candidate[name],'Browser status/candidate association differs: '+name)
    need(status['image_sha256']!='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
         and status['model_image_sha256']==MODEL_SHA,'Historical image cannot become current browser evidence')
    if status['state']=='pending':
        need(status==pending_status(candidate),'Pending browser status credits an archive or result')
    else:
        fields(status['archive'],'path sha256 bytes')
        need(status['archive']['path']==ARCHIVE and type(status['archive']['bytes'])is int and status['archive']['bytes']>0,
             'Wrong current browser archive path/size')
        for value in(status['archive']['sha256'],status['source_inputs_receipt_sha256'],status['source_finished_receipt_sha256']):digest(value)
        need(status['credited_cases']==len(CASES),'Wrong fresh browser scenario census')
    return status['state']


def prompt_fixture(package,stop=False):
    path=STOP_PROMPT_FIXTURE if stop else PROMPT_FIXTURE;pin=STOP_PROMPT_FIXTURE_SHA if stop else PROMPT_FIXTURE_SHA
    need(identity(regular(package,path))['sha256']==pin,'Current maximum-prompt fixture changed')
    fixture=read(package,path)
    fields(fixture,'schema text prompt_tokens tokenizer_sha256 golden_path golden_sha256 producer_scope tokenizers_version')
    need(fixture['schema']==('current-browser-prefix2047-stop-prompt-fixture-v1'if stop else'current-browser-prefix2048-prompt-fixture-v1')and type(fixture['text'])is str
         and len(fixture['text'])==(8424 if stop else 8431)and len(fixture['prompt_tokens'])==(2047 if stop else 2048)
         and fixture['tokenizers_version']=='0.23.2','Wrong maximum-prompt browser fixture')
    need(identity(regular(package,'host-app/assets/tokenizer.json'))['sha256']==fixture['tokenizer_sha256'],
         'Browser fixture tokenizer changed')
    need(fixture['golden_path']==('reference/seeded-sampling/goldens/prefix2047-t2-seed-a.json'if stop else'reference/seeded-sampling/goldens/prefix2048-t0-seed-a.json'),
         'Wrong maximum-prompt independent fixture')
    golden_path=regular(package,fixture['golden_path']);need(identity(golden_path)['sha256']==fixture['golden_sha256'],
         'Maximum-prompt independent golden changed')
    golden_row=json.loads(golden_path.read_bytes())
    need(golden_row['prompt_tokens']==fixture['prompt_tokens']and golden_row['model_image_sha256']==MODEL_SHA,
         'Maximum-prompt token list differs from exact model')
    return fixture,golden_row



def recorded_host_context(package):
    path=Path(package)/'tools/seeded_recorded_host_context_v1.py'
    need(path.is_file()and not path.is_symlink()and hashlib.sha256(path.read_bytes()).hexdigest()=='0d04670916e49722e5a0222adf0af19e442b587cf69a1c6aceb01fc3a14d465f',
         'Recorded seeded host source reader changed')
    spec=importlib.util.spec_from_file_location('_seeded_recorded_host_context_v1',path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    return value

def validate_complete(data,package,candidate):
    """Validate an actual fresh archive before its final literal pins are set."""
    package=Path(package)
    host=recorded_host_context(package);host.check(package,candidate)
    need(candidate['image_sha256']!='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033',
         'Historical image cannot become fresh current browser evidence')
    fields(data,'schema passed scope source_sha256 image_sha256 hardware_inputs_sha256 model_image_sha256 '
           'setup cases idle_disconnect disconnect counts source_inputs_sha256 source_finished_sha256 claims')
    need(data['schema']==ARCHIVE_SCHEMA and data['passed']is True and data['scope']==SCOPE,
         'Wrong fresh browser archive scope')
    need(set(data['source_sha256'])==set(SOURCE_PATHS),'Incomplete current browser runtime source census')
    for name,want in data['source_sha256'].items():
        need(identity(host.source_path(package,name))['sha256']==want,'Changed recorded seeded browser source: '+name)
    for name,want in candidate['host_source_inputs'].items():
        need(identity(host.source_path(package,name))==want and data['source_sha256'].get(name)==want['sha256'],
             'Browser runtime differs from current candidate host')
    need(data['image_sha256']==candidate['image_sha256']and data['hardware_inputs_sha256']==candidate['hardware_inputs_sha256']
         and data['model_image_sha256']==MODEL_SHA,'Browser image/model/source differs')
    for key in('source_inputs_sha256','source_finished_sha256'):digest(data[key])
    validate_setup(data['setup'],candidate['image_sha256'])
    need(len(data['cases'])==len(CASES),'Missing fresh browser scenario')
    counts=dict(cases=len(CASES),generated_tokens=0,wire_commands=0,qualifier_exact_tokens=19,automatic_reference_runs=2)
    auto_seeds=[];long_fixture,long_golden=prompt_fixture(package)
    for index,(case,(label,temp,seed_kind,requested))in enumerate(zip(data['cases'],CASES)):
        long_stop=label=='prefix2047-stop'
        fields(case,'label result observation wire connection_started source_download_sha256 source_backend_log_sha256 '
               'source_observation_sha256 reference'+(' active_step_stop'if long_stop else''))
        need(case['label']==label,'Fresh browser case order differs')
        for key in('source_download_sha256','source_backend_log_sha256','source_observation_sha256'):digest(case[key])
        result=case['result'];fields(result,RESULT_FIELDS)
        long_case=label in('prefix2048-greedy','prefix2047-stop')
        fixture,gold=(prompt_fixture(package,True)if long_stop else(long_fixture,long_golden))
        expected_prompt=fixture['text']if long_case else'around'
        expected_tokens=fixture['prompt_tokens']if long_case else[378]
        seed={'A':SEED_A,'B':SEED_B}.get(seed_kind,seed_kind)
        need(result['prompt']==expected_prompt and result['prompt_tokens']==expected_tokens
             and result['uploaded']==len(expected_tokens)and result['requested']==requested
             and result['temperature']==temp and result['seed_used']is(temp!='0')
             and result['sampling_settings_applied']is True and result['clear_acknowledged']is True and result['error']=='',
             'Fresh downloaded prompt/settings/CLEAR differ')
        tokens=result['generated']
        need(type(tokens)is list and 0<len(tokens)<=requested and all(type(t)is int and 0<=t<4019 for t in tokens),
             'Invalid fresh downloaded output')
        if seed=='auto':
            need(type(result['seed'])is str and re.fullmatch('0x[0-9a-f]{32}',result['seed'])is not None,
                 'Missing current automatic seed');auto_seeds.append(result['seed'])
        else:need(result['seed']==seed,'Wrong current chosen/greedy seed')
        if temp!='0':need(re.fullmatch('0x[0-9a-f]{32}',result['seed'])is not None,'Noncanonical current seed')
        if label in('stopped-t1-b','prefix2047-stop'):
            need(result['state']=='stopped'and 0<len(tokens)<requested and result['stop_reason']=='Stopped by you',
                 'Stop did not interrupt the current image')
            if long_stop:need(tokens==[1184],'Long Stop must complete only its first independent token')
        else:
            need(result['state']=='complete','Fresh browser run did not complete')
            if EOS in tokens:
                need(tokens[-1]==EOS and tokens.index(EOS)==len(tokens)-1 and result['stop_reason']=='Model reached end of story',
                     'Fresh browser EOS handling differs')
            else:need(len(tokens)==requested and result['stop_reason']=='Requested token limit reached',
                      'Fresh browser output limit differs')
        positive(result['elapsed_seconds'])
        need(len(result['step_seconds'])==len(result['arrivals_seconds'])==len(tokens),'Missing fresh download timings')
        for value in result['step_seconds']+result['arrivals_seconds']:positive(value)
        arrivals=result['arrivals_seconds']
        need(all(a<b for a,b in zip(arrivals,arrivals[1:]))and result['first_token_seconds']==arrivals[0]
             and result['elapsed_seconds']>=arrivals[-1],'Fresh arrival timings differ')
        rate=result['streaming_tokens_per_second']
        need(rate is None if len(tokens)==1 else type(rate)in(int,float)and math.isclose(
            rate,(len(tokens)-1)/(arrivals[-1]-arrivals[0]),rel_tol=1e-12,abs_tol=1e-12),'Fresh streaming-rate arithmetic differs')
        validate_observation(case['observation'],label,temp,seed,requested,result,expected_prompt)
        reference=case['reference']
        if seed=='auto':
            fields(reference,'kind temperature seed prompt_tokens generated_tokens head_rows_sha256 final_prng_state '
                   'final_kv_sha256 evaluated_positions source_inventory_sha256 source_receipt_sha256 engine')
            need(reference['kind']=='fresh-portable'and reference['temperature']==temp and reference['seed']==result['seed']
                 and reference['prompt_tokens']==[378]and reference['engine']=='scalar'
                 and reference['source_inventory_sha256']==REFERENCE_SHA
                 and len(reference['generated_tokens'])==requested and tokens==reference['generated_tokens'][:len(tokens)],
                 'Current automatic output differs from fresh exact scalar reference')
            need(len(reference['head_rows_sha256'])==requested and reference['evaluated_positions']==requested,
                 'Current automatic reference dimensions differ')
            for value in reference['head_rows_sha256']+[reference['final_kv_sha256'],reference['source_receipt_sha256']]:digest(value)
            need(len(reference['final_prng_state'])==2 and all(re.fullmatch('0x[0-9a-f]{16}',v)for v in reference['final_prng_state']),
                 'Current automatic reference PRNG state differs')
        else:
            fields(reference,'kind path sha256')
            if long_case:path,pin,gold=fixture['golden_path'],fixture['golden_sha256'],gold
            else:path,pin,gold=golden(package,temp,seed)
            need(reference==dict(kind='packaged',path=path,sha256=pin)and tokens==gold['generated_tokens'][:len(tokens)],
                 'Current browser output differs from packaged exact reference')
        need(case['connection_started']==('new'if index in(0,9,10)else'reused'),
             'Fresh current connection reuse/Stop release sequence differs')
        counts['wire_commands']+=validate_wire(case['wire'],case_commands(result),result)
        counts['generated_tokens']+=len(tokens)
        if long_stop:
            witness=case['active_step_stop']
            fields(witness,'source_backend_snapshot_sha256 source_active_ui_snapshot_sha256 wire_prefix_events '
                   'wire_prefix_sha256 step_requests_before_stop step_replies_before_stop stop_clicked_while_first_step_pending')
            digest(witness['source_backend_snapshot_sha256']);digest(witness['source_active_ui_snapshot_sha256'])
            need(witness['source_active_ui_snapshot_sha256']==case['observation']['source_before_stop_snapshot_sha256']
                 and witness['step_requests_before_stop']==1 and witness['step_replies_before_stop']==0
                 and witness['stop_clicked_while_first_step_pending']is True,'Long Stop active-request observation differs')
            step=[i for i,row in enumerate(case['wire'])if row['event']=='command_intent'and row['label']=='step']
            need(len(step)==1,'Long Stop issued a second STEP')
            prefix=case['wire'][:step[0]+2]
            need(prefix[-1]['event']=='raw_chunk'and prefix[-1]['direction']=='tx'and prefix[-1]['hex']==legacy(1)
                 and witness['wire_prefix_events']==len(prefix)and witness['wire_prefix_sha256']==sha(canonical(prefix)),
                 'Long Stop pre-reply backend snapshot does not bind the actual first STEP TX prefix')
    need(len(auto_seeds)==2 and auto_seeds[0]!=auto_seeds[1],'Current automatic seed was reused')
    need(data['cases'][0]['result']['generated']==data['cases'][4]['result']['generated'],
         'Current chosen-seed replay differs')
    for label,clicked,trigger in(('idle_disconnect',True,'idle-disconnect-after-resumed-greedy'),
                                ('disconnect',False,'stop-after-first-step-tx')):
        disconnect=data[label]
        fields(disconnect,'browser url trigger observed_utc disconnect_clicked disconnect_button_disabled uart_ownership_queried uart_owner_exit '
               'source_ui_snapshot_sha256 source_ownership_receipt_sha256')
        need(disconnect['browser']=='Chrome'and disconnect['url']==URL and disconnect['trigger']==trigger
             and disconnect['disconnect_clicked']is clicked
             and all(disconnect[k]is True for k in('disconnect_button_disabled','uart_ownership_queried'))
             and disconnect['uart_owner_exit']==1,'Current Disconnect/Stop release observation differs')
        digest(disconnect['source_ui_snapshot_sha256']);digest(disconnect['source_ownership_receipt_sha256'])
        instant(disconnect['observed_utc'])
    when=lambda value:datetime.datetime.fromisoformat(value)
    need(when(data['cases'][9]['observation']['observed_utc'])<=when(data['idle_disconnect']['observed_utc'])
         <=when(data['cases'][10]['observation']['observed_utc'])
         <=when(data['cases'][11]['observation']['observed_utc'])<=when(data['disconnect']['observed_utc']),
         'Idle Disconnect and final Stop release do not surround the actual long-prompt cases')
    need(data['counts']==counts,'Current browser census differs')
    need(data['claims']==dict(actual_browser=True,listening_server=True,physical_fpga_backend=True,
        operator_ui_observations=True,mocked_uart=False,software_inference_in_app=False,streamlit_apptest=False,
        checker_replays_browser=False,checker_replays_model=False,physical_configuration_attested=False,
        timing_qualified=False,flash_modified=False,model_flash_reinstalled=False),'Unsupported current browser claim')
    return dict(state='complete',image_sha256=candidate['image_sha256'],passed=True,credited_cases=len(CASES),
        reference_matching_outputs=counts['generated_tokens'],wire_commands=counts['wire_commands'],
        checker_drives_browser=False,checker_replays_model=False,physical_configuration_attested=False,hardware_access=False)


def check(package=ROOT,require_complete=False):
    need(SOURCE_REVIEWED is True,'Recorded seeded browser source is not reviewed')
    package=Path(package).resolve();candidate=read(package,'CANDIDATE.json');status=read(package,STATUS)
    host=recorded_host_context(package);host.check(package,candidate)
    state=status_binding(status,candidate)
    for name,want in candidate['host_source_inputs'].items():
        need(identity(host.source_path(package,name))==want,'Recorded seeded host binding changed')
    need(identity(regular(package,'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'))['sha256']==candidate['image_sha256']
         and identity(regular(package,'assets/board1-real-semantic-image2048.bin'))['sha256']==MODEL_SHA,
         'Current browser image/model asset changed')
    if state=='pending':
        need(not require_complete,'Fresh current-image browser rehearsal is pending; zero cases credited')
        return dict(state='pending',image_sha256=candidate['image_sha256'],passed=False,credited_cases=0,
            hardware_access=False,actual_browser_test_passed=False)
    need(all(value is not None for value in(BROWSER_ARCHIVE_SHA,BROWSER_INPUTS_SHA,BROWSER_FINISHED_SHA)),
         'Fresh current browser archive is not finalized/pinned')
    need(status['archive']['sha256']==BROWSER_ARCHIVE_SHA and status['source_inputs_receipt_sha256']==BROWSER_INPUTS_SHA
         and status['source_finished_receipt_sha256']==BROWSER_FINISHED_SHA,'Current browser origin pins differ')
    archive=regular(package,ARCHIVE);need(identity(archive)=={key:status['archive'][key]for key in('bytes','sha256')},
         'Current browser archive changed')
    data=json.loads(archive.read_bytes())
    need(data['source_inputs_sha256']==BROWSER_INPUTS_SHA and data['source_finished_sha256']==BROWSER_FINISHED_SHA,
         'Current browser source receipt identities differ')
    result=validate_complete(data,package,candidate)
    return dict(result,recorded_host_source_context=True,current_shared_host_physical_qualification_inherited=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=ROOT)
    parser.add_argument('--require-complete',action='store_true');args=parser.parse_args()
    print(json.dumps(check(args.package,args.require_complete),indent=2,sort_keys=True))


if __name__=='__main__':main()


"""Explicitly adapted offline actual-download/AX/UART capture functions.

These functions open no UART or browser. Automatic oracles run only the scalar
software reference after actual downloads exist. Provenance is in the overlay
BROWSER-COLLECTOR-ORIGIN.json. No old case count/pass is imported.
"""
import importlib.metadata
import json
import os
from pathlib import Path
import re
import sys
from types import SimpleNamespace

# The entrypoint binds these helpers after authenticating the installed sources.
def normalized_wire(rows):
    allowed={'command_intent':('label','hex'),'raw_chunk':('direction','hex'),
        'decoded':('kind','response','token','frame_hex'),'command_result':('operation','operand','token','seconds'),
        'sampling_settings':('temperature','seed','seed_used')}
    wire=[]
    for row in rows:
        if row['event']not in allowed:continue
        item={key:row[key]for key in allowed[row['event']]};item['event']=row['event'];item['elapsed_ns']=row['monotonic_ns'];wire.append(item)
    need(wire,'No actual UART records')
    origin=wire[0]['elapsed_ns']
    for sequence,row in enumerate(wire,1):row['sequence']=sequence;row['elapsed_ns']-=origin
    return wire

def capture_case(args,context=None,replay=False):
    run,record,package,check=inputs(args.run)if context is None else context
    labels=[row[0]for row in check.CASES];need(args.label in labels,'Unknown browser scenario')
    number=labels.index(args.label)
    for previous in labels[:number]:need((run/'cases'/previous/'CAPTURE.json').is_file(),'Capture the browser cases in documented order')
    folder=run/'cases'/args.label
    consumed={}
    def consume(name,path):
        raw=read(folder/name if replay else path);consumed[name]=raw;return raw
    download=json.loads(consume('download.json',args.download))
    _,temperature,seed,requested=check.CASES[number]
    seed={"A":check.SEED_A,"B":check.SEED_B}.get(seed,seed)
    long_case=args.label in("prefix2048-greedy","prefix2047-stop")
    long_stop=args.label=='prefix2047-stop'
    stop_case=args.label in('stopped-t1-b','prefix2047-stop')
    fixture=check.prompt_fixture(package,long_stop)[0]if long_case else None
    prompt=fixture["text"]if long_case else "around"
    prompt_tokens=fixture["prompt_tokens"]if long_case else[378]
    need(download.get('temperature')==temperature and download.get('requested')==requested
         and(seed=='auto'or download.get('seed')==seed),'Downloaded record is not the requested browser scenario')
    need(re.fullmatch('[0-9a-f]{32}',download.get('job_id',''))is not None,'Downloaded record has no valid job ID')
    log=Path(download['log_path']).resolve();expected=(package/'host-app/logs'/(download['job_id']+'.jsonl')).resolve()
    need(log==expected,'Download does not identify this recipient server log')
    raw=consume('uart.jsonl',log);rows=[json.loads(line)for line in raw.splitlines()]
    need(rows[0]['event']=='run'and rows[-1]['event']=='finished'and not any(row['event']=='error'for row in rows),'Backend run is incomplete or failed')
    result=rows[-1]['result'];need({k:v for k,v in download.items()if k!='streaming_tokens_per_second'}==result,
        'Actual downloaded JSON differs from the backend finished result')
    allowed={'run','deployment_guard','connection_reused','finished','command_intent','raw_chunk','decoded','command_result','sampling_settings'}
    need(all(row['event']in allowed for row in rows),'Unexpected backend event/noise')
    start=rows[0]
    need(start['tokens']==prompt_tokens and start['prompt']==prompt and start['backend_source_sha256']==check.SOURCES['host-app/fpga_backend.py']
        and start['software_inference']is False and start['temperature']==download['temperature']
        and start['seed']==download['seed']and start['seed_used']is download['seed_used'],'Backend start/source/settings differ')
    connections=[r for r in rows if r['event']in('deployment_guard','connection_reused')]
    need(len(connections)==1,'Missing or repeated actual connection guard')
    connection=connections[0]
    need(connection['image_sha256']==check.IMAGE_SHA and connection['variant']=='seeded-sampling'
         and connection['hardware_configuration_not_independently_attested']is True,'Wrong actual deployment guard')
    if connection['event']=='connection_reused':need(connection['previous_run_ended_with_acknowledged_clear']is True,'Uncleared reused connection')
    public_result={name:download[name]for name in check.RESULT_FIELDS.split()}
    wire=normalized_wire(rows);check.validate_wire(wire,check.case_commands(public_result),public_result)
    # Recompute text with the shipped, pinned tokenizer, without opening UART.
    import importlib.metadata
    from tokenizers import Tokenizer
    need(importlib.metadata.version('tokenizers')=='0.23.2','Use the pinned host environment for case capture')
    tokenizer=Tokenizer.from_str(read(package/'host-app/assets/tokenizer.json').decode())
    need(tokenizer.encode(prompt,add_special_tokens=False).ids==prompt_tokens
         and tokenizer.decode([t for t in download['prompt_tokens']+download['generated']if t!=check.EOS],skip_special_tokens=False)==download['text'],
         'Downloaded text disagrees with shipped tokenizer/returned token IDs')
    observation=json.loads(consume('observation.json',args.observation))
    keys=set(check.OBS_FIELDS.split())-{'source_ui_snapshot_sha256'}|{'schema','label','ui_snapshot_path'}
    if stop_case:keys|={'before_stop_tokens_generated','before_stop_state','stop_clicked','before_stop_snapshot_path'}
    if long_stop:keys|={'before_stop_backend_snapshot_path','stop_clicked_while_first_step_pending'}
    need(set(observation)==keys and observation['schema']=='fpga-browser-observation-v1'and observation['label']==args.label,
         'Wrong actual UI observation schema')
    snapshot=consume('ui.txt',observation['ui_snapshot_path']);text=snapshot.decode('utf-8')
    need('FPGA story lab'in text and 'Download run record'in text and download['text']in text,'UI snapshot does not contain the observed result/download control')
    if download['seed_used']:need(download['seed']in text,'Displayed positive-temperature seed missing from UI snapshot')
    else:need('Seed unused'in text,'Greedy unused-seed caption missing from UI snapshot')
    need(observation['story_displayed']==download['text']and observation['tokens_generated_displayed']==len(download['generated'])
         and observation['temperature_displayed']==download['temperature']and observation['seed_displayed']==download['seed']
         and observation['download_clicked']is True,'Actual UI observation differs from downloaded result')
    public_obs={name:observation[name]for name in check.OBS_FIELDS.split()if name!='source_ui_snapshot_sha256'}
    public_obs['source_ui_snapshot_sha256']=sha(snapshot)
    if stop_case:
        before=consume('before-stop-ui.txt',observation['before_stop_snapshot_path']);before_text=before.decode('utf-8')
        need('generating'in before_text.lower()and 'Stop'in before_text,'Missing active pre-Stop UI snapshot')
        public_obs.update({key:observation[key]for key in('before_stop_tokens_generated','before_stop_state','stop_clicked')})
        public_obs['source_before_stop_snapshot_sha256']=sha(before)
    check.validate_observation(public_obs,args.label,temperature,seed,requested,public_result,prompt)
    fixed=check.CASES[number][2]!='auto'
    if fixed:
        name,pin,gold=(fixture['golden_path'],fixture['golden_sha256'],check.prompt_fixture(package,long_stop)[1])if long_case else check.golden(package,download['temperature'],download['seed'])
        need(download['generated']==gold['generated_tokens'][:len(download['generated'])],'Actual browser output differs from packaged integer reference')
        reference=dict(kind='packaged',path=name,sha256=pin)
    else:reference=None
    public=dict(label=args.label,result=public_result,observation=public_obs,wire=wire,
        connection_started='new'if connection['event']=='deployment_guard'else'reused',
        source_download_sha256=sha(consumed['download.json']),source_backend_log_sha256=sha(raw),
        source_observation_sha256=sha(consumed['observation.json']),reference=reference)
    if long_stop:
        before_raw=consume('before-stop-backend.jsonl',observation['before_stop_backend_snapshot_path'])
        before_rows=[json.loads(line)for line in before_raw.splitlines()]
        before_wire=normalized_wire(before_rows)
        step=[i for i,row in enumerate(wire)if row['event']=='command_intent'and row['label']=='step']
        need(len(step)==1 and before_wire==wire[:step[0]+2]
             and before_wire[-1]['event']=='raw_chunk'and before_wire[-1]['direction']=='tx'
             and before_wire[-1]['hex']==check.legacy(1)
             and observation['stop_clicked_while_first_step_pending']is True,
             'Long Stop snapshot must end at the real first STEP TX, before its reply')
        public['active_step_stop']=dict(source_backend_snapshot_sha256=sha(before_raw),
            source_active_ui_snapshot_sha256=sha(before),wire_prefix_events=len(before_wire),
            wire_prefix_sha256=sha(check.canonical(before_wire)),step_requests_before_stop=1,
            step_replies_before_stop=0,stop_clicked_while_first_step_pending=True)
    if replay:return public,{name:sha(raw)for name,raw in consumed.items()}
    folder.mkdir(parents=True,exist_ok=False,mode=0o700)
    # Save the exact byte strings consumed above. Never reopen mutable source
    # downloads/logs/AX paths after semantic validation.
    for name,payload in consumed.items():
        fd=os.open(folder/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
        with os.fdopen(fd,'wb')as stream:stream.write(payload);stream.flush();os.fsync(stream.fileno())
    put(folder/'CAPTURE.json',dict(schema='browser-case-capture-v1',captured_utc=utc(),label=args.label,
        inputs_sha256=pathsha(run/'INPUTS.json'),public_case=public,
        files={name:sha(payload)for name,payload in consumed.items()}))
    print(json.dumps(dict(captured=True,label=args.label,outputs=len(download['generated']),
        fixed_reference_matches=fixed,needs_automatic_reference=not fixed,hardware_access=False)),flush=True)

def automatic_oracles(args):
    run,record,package,check=inputs(args.run)
    need(sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize,'Run oracle with Python -I -B')
    lane=package/'reference/seeded-sampling'
    need(pathsha(lane/'SOURCE.json')==check.REFERENCE_SHA,'Portable numerical source inventory changed')
    source=jsonread(lane/'SOURCE.json')
    for name,pin in source['files'].items():need(pathsha(lane/name)==pin,'Portable numerical source changed')
    recon=module('_browser_reference_rom',lane/'reconstruct_rom.py');payloads=recon.reconstruct()
    rom=run/'oracle-rom'
    if not rom.exists():
        rom.mkdir(mode=0o700)
        for name,raw in payloads.items():
            fd=os.open(rom/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            with os.fdopen(fd,'wb')as stream:stream.write(raw)
    for name,raw in payloads.items():need(read(rom/name)==raw,'Existing browser oracle ROM differs')
    model=module('_browser_exact_reference',lane/'model.py');loaded=model.load(rom,engine='scalar')
    labels=[args.label]if args.label else['automatic-1','automatic-2']
    for label in labels:
        need(label in('automatic-1','automatic-2'),'Oracle is for the two actual automatic-seed cases')
        folder=run/'cases'/label;capture_raw=read(folder/'CAPTURE.json');download_raw=read(folder/'download.json')
        capture=json.loads(capture_raw);download=json.loads(download_raw)
        need(sha(download_raw)==capture['files']['download.json'],'Automatic download changed')
        original_pins={str(folder/name):digest for name,digest in capture['files'].items()}
        original_pins[str(folder/'CAPTURE.json')]=sha(capture_raw);original_pins[str(run/'INPUTS.json')]=pathsha(run/'INPUTS.json')
        rebuilt,files=capture_case(SimpleNamespace(run=run,label=label,download=folder/'download.json',observation=folder/'observation.json'),
            context=(run,record,package,check),replay=True)
        need(rebuilt==capture['public_case']and files==capture['files'],'Automatic captured raw inputs differ')
        engine=loaded['Model'](loaded['data']);head=engine.consume(378)
        result=model.generate(engine,head,loaded['sampler'],check.TEMPS.index(download['temperature']),int(download['seed'],0),download['requested'])
        need(download['generated']==result['generated_tokens'][:len(download['generated'])],'Automatic browser output differs from independent exact model')
        receipt=dict(schema='browser-automatic-reference-v1',passed=True,label=label,temperature=download['temperature'],seed=download['seed'],
            prompt_tokens=[378],engine='scalar',source_inventory_sha256=check.REFERENCE_SHA,
            source_download_sha256=sha(download_raw),source_capture_sha256=sha(capture_raw),
            inputs_sha256=original_pins[str(run/'INPUTS.json')],model_image_sha256=check.MODEL_SHA,
            hardware_access=False,network_access=False,rtl_executed=False,**result)
        need(all(pathsha(name)==digest for name,digest in original_pins.items()),'Automatic raw/reference inputs changed during computation')
        inputs(run)  # Freshly rehash all prepared sources after software inference.
        put(folder/'ORACLE.json',receipt)
        print(json.dumps(dict(passed=True,label=label,exact_outputs=len(download['generated']),engine='scalar',hardware_access=False)),flush=True)

def public_cases(run,check):
    cases=[];pins={}
    for label,*_ in check.CASES:
        folder=run/'cases'/label;capture_raw=read(folder/'CAPTURE.json');capture=json.loads(capture_raw)
        need(capture['inputs_sha256']==pathsha(run/'INPUTS.json'),'Browser case preparation binding differs')
        for name,pin in capture['files'].items():need(pathsha(folder/name)==pin,'Captured browser file changed: '+label+'/'+name)
        record=jsonread(run/'INPUTS.json');package=Path(record['package'])
        case,files=capture_case(SimpleNamespace(run=run,label=label,download=folder/'download.json',observation=folder/'observation.json'),
            context=(run,record,package,check),replay=True)
        need(files==capture['files']and case==capture['public_case'],'Actual copied browser inputs do not rebuild the recorded semantic case')
        pins['cases/'+label+'/CAPTURE.json']=sha(capture_raw)
        if label.startswith('automatic-'):
            oracle_raw=read(folder/'ORACLE.json');oracle=json.loads(oracle_raw)
            need(oracle['passed']and oracle['source_download_sha256']==case['source_download_sha256']
                and oracle['source_capture_sha256']==pathsha(folder/'CAPTURE.json')and oracle['inputs_sha256']==pathsha(run/'INPUTS.json')
                and all(oracle[key]is False for key in('hardware_access','network_access','rtl_executed')),'Automatic oracle provenance differs')
            case['reference']={key:oracle[key]for key in('temperature','seed','prompt_tokens','generated_tokens','head_rows_sha256',
                'final_prng_state','final_kv_sha256','evaluated_positions','source_inventory_sha256','engine')}
            case['reference'].update(kind='fresh-portable',source_receipt_sha256=pathsha(folder/'ORACLE.json'))
            pins['cases/'+label+'/ORACLE.json']=sha(oracle_raw)
            need(pathsha(folder/'ORACLE.json')==sha(oracle_raw),'Automatic oracle changed during parsing')
        need(pathsha(folder/'CAPTURE.json')==sha(capture_raw)and all(pathsha(folder/name)==pin for name,pin in files.items()),
             'Actual copied browser inputs changed during semantic replay')
        cases.append(case)
    return cases,pins

"""Collect already performed current browser actions; no UI/UART/network access.

prepare/case/assemble read actual files. oracle alone executes the unchanged
scalar reference on actual automatic-seed downloads. assemble requires a
separately reviewed policy binding the actual setup/Disconnect evidence. This
is operator/Cua evidence, never independent circuit attestation.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent


def need(ok,message):
    if not ok:raise ValueError(message)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def pathsha(path):return sha(read(path,128*1024*1024))
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def canonical(value):return(json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def read(path,maximum=16*1024*1024):
    path=Path(path);need(path.is_file()and not path.is_symlink()and path.stat().st_size<=maximum,
        'Expected bounded regular input: '+str(path));return path.read_bytes()
def jsonread(path):return json.loads(read(path))
def identity(path):
    path=Path(path);need(path.is_file()and not path.is_symlink(),'Missing/linked evidence input')
    with path.open('rb')as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    return dict(bytes=path.stat().st_size,sha256=digest)
def put(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
    with os.fdopen(fd,'w')as stream:json.dump(value,stream,indent=2,sort_keys=True);stream.write('\n');stream.flush();os.fsync(stream.fileno())
def copy_private(source,target):
    raw=read(source);path=Path(target);path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
    with os.fdopen(fd,'wb')as stream:stream.write(raw)
    return sha(raw)
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec)
    sys.modules[name]=value;spec.loader.exec_module(value);return value
def unchanged(pins):
    for path,want in pins.items():need(identity(Path(path))==want,'Browser evidence changed: '+path)


def source_pins():
    return {str(path.resolve()):identity(path)for path in(Path(__file__),HERE/'browser_capture_functions.py')}


def inputs(run):
    run=Path(run).resolve();record=jsonread(run/'INPUTS.json');package=Path(record['package'])
    need(record['schema']=='current-browser-inputs-v4'and record['collector_source_inputs']==source_pins(),
         'Collector changed after preparation; preserve this run')
    unchanged(record['prepared_package_files'])
    need(identity(package/'MANIFEST.json')==record['manifest'],'Recipient manifest changed during rehearsal')
    check=module('_fresh_current_browser_validator',package/'tools/check_long_context_browser.py')
    need(record['source_sha256']=={name:pathsha(package/name)for name in check.SOURCE_PATHS},'Current browser source changed')
    # Compatibility shim for the explicitly listed offline capture functions.
    check.SOURCES=record['source_sha256'];check.IMAGE_SHA=record['image_sha256']
    return run,record,package,check


def prepare(args):
    package=args.package.resolve(strict=True)
    need(identity(package/'MANIFEST.json')['sha256']==args.manifest_sha256,
         'Recipient manifest differs from the independently reviewed export')
    manifest=jsonread(package/'MANIFEST.json');pins={}
    # Authenticate every executable/data dependency before importing any
    # recipient Python code, under the explicitly supplied export manifest pin.
    for name,want in manifest['files'].items():
        path=package/name;relative=Path(name)
        need(not relative.is_absolute()and'..'not in relative.parts and'\\'not in name
             and not any(p.is_symlink()for p in(path,*path.parents)if p.is_relative_to(package)),
             'Unsafe/linked prepared package member')
        pins[str(path.resolve())]=want
    pins[str((package/'MANIFEST.json').resolve())]=identity(package/'MANIFEST.json');unchanged(pins)
    compat=module('_fresh_current_browser_prepare',package/'tools/seeded_release_compat.py')
    current=compat.check_current(package,'phase')
    need(current['browser_state']=='pending'and current['current_browser_passed']is False,'Rehearsal must start from pending current recipient')
    candidate=jsonread(package/'CANDIDATE.json')
    check=module('_fresh_current_browser_prepare_validator',package/'tools/check_long_context_browser.py')
    # No generated logs/cache join the release inventory.
    unchanged(pins)
    args.out.mkdir(parents=True,exist_ok=False,mode=0o700)
    put(args.out/'INPUTS.json',dict(schema='current-browser-inputs-v4',prepared_utc=utc(),package=str(package),
        manifest=identity(package/'MANIFEST.json'),prepared_package_files=pins,collector_source_inputs=source_pins(),
        image_sha256=candidate['image_sha256'],hardware_inputs_sha256=candidate['hardware_inputs_sha256'],
        model_image_sha256=candidate['model_image_sha256'],host_source_inputs=candidate['host_source_inputs'],
        source_sha256={name:pathsha(package/name)for name in check.SOURCE_PATHS},cases=[list(row)for row in check.CASES],
        hardware_access=False,browser_actions_performed_by_collector=False))
    print(json.dumps(dict(prepared=True,cases=len(check.CASES),hardware_access=False)),flush=True)


def functions():
    value=module('_fresh_current_browser_capture_functions',HERE/'browser_capture_functions.py')
    for name in('need','sha','pathsha','utc','read','jsonread','put','copy_private','module','inputs'):
        setattr(value,name,globals()[name])
    return value


def assemble(args):
    run,record,package,check=inputs(args.run)
    policy=jsonread(args.policy)
    need(policy.get('reviewed')is True and policy.get('schema')=='current-browser-reviewed-observation-policy-v4',
         'Actual setup/Disconnect evidence has not been independently reviewed')
    need(policy['inputs_sha256']==pathsha(run/'INPUTS.json')and policy['collector_source_inputs']==source_pins(),
         'Reviewed observation policy has a different preparation/collector')
    need(identity(args.setup)==policy['setup']and identity(args.disconnect)==policy['disconnect']
         and identity(args.idle_disconnect)==policy['idle_disconnect'],
         'Reviewed actual setup/Disconnect record changed')
    pins=dict(policy['source_files']);need(pins,'Actual source setup/Disconnect receipts are required')
    pins.update({str(Path(p).resolve()):identity(p)for p in(args.policy,args.setup,args.disconnect,args.idle_disconnect,run/'INPUTS.json')})
    cases,case_pins=functions().public_cases(run,check)
    for name,digest in case_pins.items():
        path=run/name;need(pathsha(path)==digest,'Actual case receipt changed');pins[str(path)]=identity(path)
        if name.endswith('/CAPTURE.json'):
            receipt=jsonread(path)
            for child,d in receipt['files'].items():
                original=path.parent/child;need(pathsha(original)==d,'Actual captured file changed');pins[str(original)]=identity(original)
    unchanged(pins);setup=jsonread(args.setup);disconnect=jsonread(args.disconnect);idle_disconnect=jsonread(args.idle_disconnect)
    need(setup['recipient_manifest_sha256']==record['manifest']['sha256']
         and setup['recipient_files']==len(record['prepared_package_files']),
         'Actual setup belongs to another pre-browser recipient manifest')
    # These digests must identify real files in the reviewed private evidence set.
    def required_origins(value):
        if type(value)is dict:
            for name,child in value.items():
                if name.startswith('source_')and name.endswith('_sha256'):
                    need(any(want['sha256']==child for want in pins.values())or child in record['source_sha256'].values(),
                         'Sanitized observation lacks its original source file: '+name)
                else:required_origins(child)
        elif type(value)is list:
            for child in value:required_origins(child)
    required_origins(setup);required_origins(disconnect);required_origins(idle_disconnect)
    counts=dict(cases=len(check.CASES),generated_tokens=sum(len(c['result']['generated'])for c in cases),
        wire_commands=sum(len(check.case_commands(c['result']))for c in cases),qualifier_exact_tokens=19,automatic_reference_runs=2)
    payload=dict(schema=check.ARCHIVE_SCHEMA,passed=True,scope=check.SCOPE,source_sha256=record['source_sha256'],
        image_sha256=record['image_sha256'],hardware_inputs_sha256=record['hardware_inputs_sha256'],model_image_sha256=record['model_image_sha256'],
        setup=setup,cases=cases,idle_disconnect=idle_disconnect,disconnect=disconnect,counts=counts,
        claims=dict(actual_browser=True,listening_server=True,physical_fpga_backend=True,operator_ui_observations=True,
            mocked_uart=False,software_inference_in_app=False,streamlit_apptest=False,checker_replays_browser=False,
            checker_replays_model=False,physical_configuration_attested=False,timing_qualified=False,flash_modified=False,model_flash_reinstalled=False))
    finished=dict(schema='current-browser-finished-v4',passed=True,finished_utc=utc(),source_inputs_sha256=pathsha(run/'INPUTS.json'),
        evidence_payload_sha256=sha(canonical(payload)),collector_source_inputs=source_pins(),checked_inputs=pins,
        counts=counts,hardware_access=False,browser_actions_performed_by_collector=False)
    # Validate the prospective archive before writing either qualifying record.
    prospective=dict(payload,source_inputs_sha256=finished['source_inputs_sha256'],
        source_finished_sha256=sha((json.dumps(finished,indent=2,sort_keys=True)+'\n').encode()))
    check.validate_complete(prospective,package,jsonread(package/'CANDIDATE.json'));unchanged(pins)
    put(run/'FINISHED.json',finished)
    need(pathsha(run/'FINISHED.json')==prospective['source_finished_sha256'],'Completed browser receipt serialization changed')
    archive=dict(payload,source_inputs_sha256=pathsha(run/'INPUTS.json'),source_finished_sha256=pathsha(run/'FINISHED.json'))
    check.validate_complete(archive,package,jsonread(package/'CANDIDATE.json'));put(run/'PUBLIC-BROWSER.json',archive)
    print(json.dumps(dict(passed=True,archive_sha256=pathsha(run/'PUBLIC-BROWSER.json'),**counts)),flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__);s=p.add_subparsers(dest='command',required=True)
    a=s.add_parser('prepare');a.add_argument('--package',type=Path,required=True);a.add_argument('--out',type=Path,required=True)
    a.add_argument('--manifest-sha256',required=True)
    a=s.add_parser('case');a.add_argument('--run',type=Path,required=True);a.add_argument('--label',required=True)
    a.add_argument('--download',type=Path,required=True);a.add_argument('--observation',type=Path,required=True)
    a=s.add_parser('oracle');a.add_argument('--run',type=Path,required=True);a.add_argument('--label')
    a=s.add_parser('assemble');a.add_argument('--run',type=Path,required=True);a.add_argument('--setup',type=Path,required=True)
    a.add_argument('--disconnect',type=Path,required=True);a.add_argument('--idle-disconnect',type=Path,required=True)
    a.add_argument('--policy',type=Path,required=True)
    args=p.parse_args()
    if args.command=='prepare':prepare(args)
    elif args.command=='case':functions().capture_case(args)
    elif args.command=='oracle':functions().automatic_oracles(args)
    else:assemble(args)


if __name__=='__main__':main()

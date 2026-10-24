"""Prepare a separate clean recipient from reviewed actual browser evidence.

Default is read-only validation. --finalize copies only manifest files to a NEW
directory, adds the actual archive, fills three browser-origin pins and updates
the separate browser/manifest phase. Construction CANDIDATE flags remain false
as provenance. No source package edit, UI, UART, network or programming occurs.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys


def need(ok,message):
    if not ok:raise ValueError(message)
def canonical(value):return(json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def identity(path):
    path=Path(path);need(path.is_file()and not path.is_symlink(),'Missing/linked finalization input')
    with path.open('rb')as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    return dict(bytes=path.stat().st_size,sha256=digest)
def read(path):
    need(identity(path)['bytes']<=32*1024*1024,'Unbounded browser receipt');return json.loads(Path(path).read_bytes())
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec)
    sys.modules[name]=value;spec.loader.exec_module(value);return value
def unchanged(pins):
    for name,want in pins.items():need(identity(name)==want,'Finalization input changed: '+name)
def put(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x')as stream:json.dump(value,stream,indent=2,sort_keys=True);stream.write('\n')


def prepare(package,run,policy_path):
    package=Path(package).resolve();run=Path(run).resolve();policy=read(policy_path)
    need(policy.get('schema')=='current-browser-finalization-policy-v4'and policy.get('reviewed')is True,
         'Actual fresh browser packet has not been independently reviewed')
    pins={str(Path(policy_path).resolve()):identity(policy_path)}
    for label,path in(('manifest',package/'MANIFEST.json'),('archive',run/'PUBLIC-BROWSER.json'),
                       ('inputs',run/'INPUTS.json'),('finished',run/'FINISHED.json')):
        actual=identity(path);need(actual==policy[label],'Reviewed actual browser input differs: '+label);pins[str(path)]=actual
    need(identity(__file__)['sha256']==policy['finalizer_sha256'],'Unreviewed browser finalizer')
    manifest=read(package/'MANIFEST.json')
    for name,want in manifest['files'].items():
        relative=Path(name);need(not relative.is_absolute()and'..'not in relative.parts and'\\'not in name,
            'Unsafe release inventory member')
        path=package/name;need(not any(p.is_symlink()for p in(path,*path.parents)if p.is_relative_to(package)),
            'Linked source release input');pins[str(path)]=want
    unchanged(pins)
    compat=module('_actual_current_browser_finalize_compat',package/'tools/seeded_release_compat.py')
    phase=compat.check_current(package,'phase');need(phase['browser_state']=='pending','Only the original pending recipient can be finalized')
    collector=module('_actual_current_browser_finalize_collector',package/'tools/collect_current_browser.py')
    _,inputs,prepared,check=collector.inputs(run)
    need(prepared.resolve()==package,'Browser preparation belongs to another recipient')
    finished=read(run/'FINISHED.json');archive=read(run/'PUBLIC-BROWSER.json')
    need(finished['schema']=='current-browser-finished-v4'and finished['passed']is True
         and finished['source_inputs_sha256']==policy['inputs']['sha256']
         and finished['collector_source_inputs']==inputs['collector_source_inputs']
         and finished['hardware_access']is False and finished['browser_actions_performed_by_collector']is False,
         'Actual current-browser completion/producer binding differs')
    pins.update(finished['checked_inputs']);unchanged(pins)
    need(archive['source_inputs_sha256']==policy['inputs']['sha256']
         and archive['source_finished_sha256']==policy['finished']['sha256'],'Browser archive origin differs')
    payload={name:value for name,value in archive.items()if name not in('source_inputs_sha256','source_finished_sha256')}
    need(hashlib.sha256(canonical(payload)).hexdigest()==finished['evidence_payload_sha256']
         and finished['counts']==archive['counts'],'Actual browser payload/census changed')
    cases,_=collector.functions().public_cases(run,check)
    need(cases==archive['cases'],'Original actual case files differ from the archive')
    result=check.validate_complete(archive,package,read(package/'CANDIDATE.json'));unchanged(pins)
    need(result['passed']is True and result['credited_cases']==12,'Incomplete actual browser rehearsal')
    return dict(package=package,run=run,policy=policy,manifest=manifest,archive=archive,result=result,pins=pins)


def browser_source(raw,archive,inputs,finished):
    text=raw.decode()
    for name,value in(('BROWSER_ARCHIVE_SHA',archive),('BROWSER_INPUTS_SHA',inputs),('BROWSER_FINISHED_SHA',finished)):
        need(re.fullmatch('[0-9a-f]{64}',value)is not None,'Invalid actual browser origin pin')
        old=name+'=None';need(text.count(old)==1,'Browser source is already finalized or changed')
        text=text.replace(old,name+'='+repr(value),1)
    return text.encode()


def readme_source(raw):
    warning=('PRIVATE PRE-BROWSER RECIPIENT CANDIDATE. The active seeded image has new CLI evidence; '
        'its recipient/browser test is pending. Historical0e6 qualification below is retained as provenance, not inherited.\n\n').encode()
    need(raw.startswith(warning)and raw.count(warning)==1,'Unknown pre-browser README construction prefix')
    current=('CURRENT SEEDED IMAGE: the separate current browser record is complete after twelve fresh '
        'actual generation cases, including both long-prompt scenarios, idle Disconnect and final Stop release. '
        'See [current qualification and source/proof limits](CURRENT-QUALIFICATION.md). '
        'Construction CANDIDATE/BUILD flags remain provenance; current browser/manifest status is separate. '
        'Native timing, whole-machine proof and independent physical attestation are not claimed.\n\n'
        'The original release documentation below is retained as historical0e6 context. Its original seeded '
        'timing/browser/proof counts do not describe the current image. Current checker entrypoints dispatch '
        'current records; the exact older package is available in the history archive.\n\n').encode()
    return current+raw[len(warning):]


def finalize(plan,out):
    out=Path(out).resolve();need(not out.exists()and out.parent.is_dir(),'Use a NEW clean output directory')
    package=Path(plan['package']).resolve();need(not out.is_relative_to(package)and not package.is_relative_to(out),
         'Finalized output must be separate from the source recipient')
    readme=readme_source((package/'README.md').read_bytes())
    unchanged(plan['pins']);out.mkdir(mode=0o700)
    for name,want in plan['manifest']['files'].items():
        raw=(package/name).read_bytes();need(dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())==want,
            'Source changed during clean copy')
        target=out/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
    policy=plan['policy'];archive_relative='evidence/seeded-sampling/current-browser-complete.json'
    target=out/archive_relative;target.parent.mkdir(parents=True,exist_ok=True)
    with target.open('xb')as stream:stream.write((plan['run']/'PUBLIC-BROWSER.json').read_bytes())
    need(identity(target)==policy['archive'],'Original archive changed during clean copy')
    checker='tools/check_long_context_browser.py'
    (out/checker).write_bytes(browser_source((out/checker).read_bytes(),policy['archive']['sha256'],
        policy['inputs']['sha256'],policy['finished']['sha256']))
    status_path=out/'evidence/seeded-sampling/current-browser.json';status=json.loads(status_path.read_bytes())
    need(status['state']=='pending'and status['credited_cases']==0,'Source browser phase is not pending')
    status.update(state='complete',archive=dict(path=archive_relative,**policy['archive']),
        source_inputs_receipt_sha256=policy['inputs']['sha256'],source_finished_receipt_sha256=policy['finished']['sha256'],credited_cases=12)
    status_path.write_text(json.dumps(status,indent=2,sort_keys=True)+'\n')
    (out/'README.md').write_bytes(readme)
    receipt='evidence/seeded-sampling/current-browser-finalization.json'
    put(out/receipt,dict(schema='current-browser-clean-finalization-v4',original_manifest=policy['manifest'],
        actual_archive=policy['archive'],source_inputs=policy['inputs'],source_finished=policy['finished'],
        finalizer_sha256=identity(__file__)['sha256'],credited_cases=12,construction_flags_preserved=True,
        source_recipient_modified=False,checker_drives_browser=False,physical_configuration_attested=False,
        hardware_access=False,timing_qualified=False))
    manifest=plan['manifest'];changed=[archive_relative,checker,'evidence/seeded-sampling/current-browser.json',receipt,'README.md']
    for name in changed:manifest['files'][name]=identity(out/name)
    selected=manifest['variants']['seeded-sampling'];selected['opened_browser_rehearsal_complete']=True;selected['experimental']=False
    put(out/'MANIFEST.json',manifest);unchanged(plan['pins'])
    compat=module('_finalized_current_recipient',out/'tools/seeded_release_compat.py')
    result=compat.check_current(out,'phase',True)
    verifier=module('_finalized_current_inventory',out/'tools/verify_release.py');verifier.verify(out,True)
    portable=module('_finalized_current_portable',out/'tools/check_long_context_recipient.py');portable.check(out,True)
    unchanged(plan['pins']);return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True);parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--policy',type=Path,required=True);parser.add_argument('--out',type=Path)
    parser.add_argument('--finalize',action='store_true');args=parser.parse_args()
    plan=prepare(args.package,args.run,args.policy)
    if args.finalize:
        need(args.out is not None,'Finalization needs a NEW clean output directory');result=finalize(plan,args.out)
    else:result=dict(validated_actual_packet=True,output_created=False,**plan['result'])
    print(json.dumps(result,indent=2,sort_keys=True))


if __name__=='__main__':main()

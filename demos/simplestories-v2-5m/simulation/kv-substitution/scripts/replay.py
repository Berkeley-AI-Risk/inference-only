if not __debug__:
    raise SystemExit('Optimized Python is unsupported; run without -O or -OO')
"""Retained preparation, compilation, six native trials and independent checks."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import collections
import hashlib
import importlib.util
import json
import platform
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
DRIVER = HERE.parent
TOP = 'tb_board1_booted_shared_semantic'
CASES = {'plain': ('honest','negated','layer4'), 'protected': ('honest','both','head1')}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value,indent=2,sort_keys=True)+'\n')


def invoke(command, cwd, target, allow_failure=False):
    target.mkdir(parents=True,exist_ok=False)
    save(target/'COMMAND.json', {'argv':command,'cwd':str(cwd)})
    start=time.monotonic()
    with (target/'stdout.log').open('xb') as stdout, (target/'stderr.log').open('xb') as stderr:
        child=subprocess.run(command,cwd=cwd,stdout=stdout,stderr=stderr)
    row={'actual_child_exit':child.returncode,'wall_seconds':time.monotonic()-start,
         'stdout_sha256':sha(target/'stdout.log'),'stderr_sha256':sha(target/'stderr.log')}
    save(target/'EXIT.json',row)
    if child.returncode and not allow_failure:
        raise RuntimeError('Child failed; retained logs: '+str(target))
    return row


def check_input(path, expected):
    if path.stat().st_size != expected['bytes'] or sha(path) != expected['sha256']:
        raise ValueError('Selected input changed: '+str(path))


def check_inputs(root):
    for name, row in read(DRIVER/'SOURCE-INPUTS.json')['files'].items():
        check_input(root/name,row)


def seal(folder):
    return {str(p.relative_to(folder)):{'bytes':p.stat().st_size,'sha256':sha(p)}
            for p in sorted(folder.rglob('*')) if p.is_file()}


def check_seal(folder, records):
    for name, row in records.items():
        check_input(folder/name,row)


def load(name):
    path=HERE/(name+'.py')
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepare(args):
    import numpy
    if numpy.__version__ != '1.26.4':
        raise ValueError('Use NumPy 1.26.4')
    version=subprocess.check_output(['verilator','--version'],text=True).strip()
    if not version.startswith('Verilator 5.050 '):
        raise ValueError('Use the pinned Verilator 5.050 toolchain')
    save(args.output/'TOOLS.json',{'python':sys.version,'numpy':numpy.__version__,
        'platform':platform.platform(),'verilator':version,
        'compiler':subprocess.check_output(['c++','--version'],text=True).splitlines()[0]})
    package=args.repository/'demos/simplestories-v2-5m'
    for kind in CASES:
        work=args.output/(kind+'-source');work.mkdir()
        module=load('prepare_'+kind)
        record=module.prepare(package,work)
        references=record['reference_sources'] if kind=='plain' else record
        save(args.output/(kind+'-SOURCE-SEAL.json'),{'files':seal(work),'references':references,
            'source':str(work),'no_functional_RTL_edits':True})
    ref=invoke([sys.executable,'-I','-B',str(HERE/'reference.py'),str(args.repository)],
               args.output,args.output/'reference-generation')
    generated=read(args.output/'reference-generation/stdout.log')
    if generated != read(DRIVER/'reference/EXPECTED.json'):
        raise ValueError('Independent numerical reference differs from the declared fixture')
    directory=args.output/'plain-kv-observation';directory.mkdir()
    shutil.copyfile(args.output/'reference-generation/stdout.log',directory/'reference.json')
    (args.output/'protected-kv-observation').mkdir()
    save(args.output/'PREPARED.json',{'passed':True,'source_inputs_sha256':sha(DRIVER/'SOURCE-INPUTS.json'),
        'independent_reference_sha256':sha(directory/'reference.json'),'reference_child':ref,
        'tools_sha256':sha(args.output/'TOOLS.json'),'driver_seal_sha256':sha(args.output/'DRIVER-SEAL.json'),
        'source_seals':{kind:sha(args.output/(kind+'-SOURCE-SEAL.json')) for kind in CASES}})
    print('PASS_PAIRED_PREPARATION',flush=True)


def warnings(log, folder):
    found=re.findall(r'^%Warning-([A-Z0-9_]+): ([^:\n]+):(\d+):(\d+): (.*)$',log,re.M)
    if len(found) != len(re.findall(r'^%Warning-',log,re.M)):
        raise ValueError('Unparsed compiler warning')
    counts=collections.Counter()
    for code,file,line,column,message in found:
        text=(folder/file).read_text().splitlines()[int(line)-1]
        counts[(code,file,hashlib.sha256(text.encode()).hexdigest(),message)] += 1
    return [{'code':k[0],'file':k[1],'source_line_sha256':k[2],'message':k[3],'count':v}
            for k,v in sorted(counts.items())]


def build(args):
    needs_review=[]
    for kind in CASES:
        source=args.output/(kind+'-source');spec=read(args.output/(kind+'-SOURCE-SEAL.json'))
        check_seal(source,spec['files'])
        command=['verilator','--binary','--timing','--build-jobs',str(args.build_jobs),
            '-MAKEFLAGS',f'CURDIR={source}/obj OPT_FAST=-O3 OPT_SLOW=-O3',
            '-Wno-fatal','-DSYNTHESIS','-GAUTH_BANKS=4','--top-module',TOP,
            '--Mdir',str(source/'obj'),'-f','production_sources.f',*spec['references'],'tb.sv','-CFLAGS','-O3']
        result=invoke(command,source,args.output/(kind+'-compile'))
        check_seal(source,spec['files'])
        records=warnings((args.output/(kind+'-compile/stderr.log')).read_text(),source)
        save(args.output/(kind+'-WARNINGS.json'),records)
        policy=read(DRIVER/'reference/WARNING-POLICY.json')
        if records != policy.get(kind):
            needs_review.append(kind)
            print('WARNING_REVIEW_REQUIRED',kind,flush=True)
            continue
        save(args.output/(kind+'-BUILT.json'),{'passed':True,**result,
            'binary_sha256':sha(source/'obj'/('V'+TOP)),'warnings_sha256':sha(args.output/(kind+'-WARNINGS.json')),
            'source_seal_sha256':sha(args.output/(kind+'-SOURCE-SEAL.json')),
            'command_sha256':sha(args.output/(kind+'-compile/COMMAND.json'))})
        print('PASS_PAIRED_BUILD',kind,flush=True)
    if needs_review:
        raise ValueError('Warnings require source-bound review: '+','.join(needs_review))


def one_case(args,kind,name):
    source=args.output/(kind+'-source');binary=source/'obj'/('V'+TOP)
    built=read(args.output/(kind+'-BUILT.json'))
    check_seal(source,read(args.output/(kind+'-SOURCE-SEAL.json'))['files'])
    if not built['passed'] or sha(binary) != built['binary_sha256']:
        raise ValueError('Compiled binary changed')
    command=[str(binary),'+IMAGE_MEMH=image.memh','+ZERO_STALL']
    if kind=='plain':
        command += {'honest':[],'negated':['+NEGATE_V'],'layer4':['+NEGATE_L4']}[name]
    else:
        command += ['+CASE='+str(CASES[kind].index(name))]
    directory=args.output/(kind+'-kv-observation')
    result=invoke(command,source,directory/(name+'-native'))
    log=directory/(name+'-native/stdout.log')
    body=log.read_text();lines=body.splitlines()
    if not any(line.startswith('BOOT_AUTHENTICATED ') for line in lines):
        raise ValueError('Real full-image boot was not observed')
    events={'BOOT_AUTHENTICATED','KV_RETURN','KV_WRITE','L0_QUERY','L4_QUERY','L0_ATTENTION','L4_ATTENTION',
        'L0_PV','L4_PV','MEASURED_TOKEN','TWO_STEPS_COMPLETE','TOKEN'} if kind=='plain' else {
        'BOOT_AUTHENTICATED','PHY_RD','PHY_WR','SNAPSHOT','DIGEST','GUARD_OFFER','TOKEN','QUERY',
        'ATT_REQ','ATT_RSP','ATT_OUT','GUARD_FAULT','CLOSED','COMPLETED'}
    selected=[line for line in lines if line and line.split()[0] in events]
    tokens=[int(line.split()[-1]) for line in selected if line.startswith('TOKEN ')]
    expected=[200,15] if name=='honest' or name=='negated' else ([200,1138] if kind=='plain' else [200])
    if tokens != expected:
        raise ValueError('Actual token handshakes differ: '+kind+'/'+name)
    trace=directory/(name+'.trace')
    with trace.open('x') as stream:stream.write('\n'.join(selected)+'\n')
    save(directory/(name+'-VERIFIED.json'),{'passed':True,**result,'kind':kind,'case':name,
        'tokens':tokens,'trace_sha256':sha(trace),'binary_sha256':sha(binary),
        'command_sha256':sha(directory/(name+'-native/COMMAND.json'))})
    print('PASS_PAIRED_NATIVE',kind,name,tokens,flush=True)


def run_cases(args):
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures=[pool.submit(one_case,args,kind,name) for kind,names in CASES.items() for name in names]
        errors=[]
        for future in futures:
            try:future.result()
            except Exception as error:errors.append(str(error))
        if errors:raise RuntimeError('; '.join(errors))


def check_receipt_links(output):
    for kind,names in CASES.items():
        source=(output/(kind+'-source')).resolve()
        binary=source/'obj'/('V'+TOP)
        built=read(output/(kind+'-BUILT.json'))
        compile_dir=output/(kind+'-compile')
        actual=read(compile_dir/'EXIT.json')
        if (not built['passed'] or built['actual_child_exit']!=0 or actual['actual_child_exit']!=0
                or sha(binary)!=built['binary_sha256']
                or sha(output/(kind+'-SOURCE-SEAL.json'))!=built['source_seal_sha256']
                or sha(compile_dir/'COMMAND.json')!=built['command_sha256']
                or sha(output/(kind+'-WARNINGS.json'))!=built['warnings_sha256']):
            raise ValueError('Compile receipt, binary, source seal or warnings differ: '+kind)
        for key,file in [('stdout_sha256','stdout.log'),('stderr_sha256','stderr.log')]:
            digest=sha(compile_dir/file)
            if actual[key]!=digest or built[key]!=digest:
                raise ValueError('Actual compile exit/log differs: '+kind+'/'+key)
        if actual['wall_seconds']!=built['wall_seconds']:
            raise ValueError('Compile exit interval differs')
        observed=warnings((compile_dir/'stderr.log').read_text(),source)
        if observed!=read(output/(kind+'-WARNINGS.json')) or observed!=read(DRIVER/'reference/WARNING-POLICY.json')[kind]:
            raise ValueError('Actual compiler warnings differ from the reviewed report')
        for name in names:
            directory=output/(kind+'-kv-observation')
            recorded=read(directory/(name+'-VERIFIED.json'))
            native=directory/(name+'-native');actual=read(native/'EXIT.json')
            if (not recorded['passed'] or recorded['kind']!=kind or recorded['case']!=name
                    or recorded['actual_child_exit']!=0 or actual['actual_child_exit']!=0
                    or recorded['binary_sha256']!=built['binary_sha256']
                    or recorded['binary_sha256']!=sha(binary)):
                raise ValueError('Actual native exit or saved binary identity differs: '+kind+'/'+name)
            if recorded['wall_seconds']!=actual['wall_seconds']:
                raise ValueError('Native exit interval differs')
            for key,file in [('stdout_sha256','stdout.log'),('stderr_sha256','stderr.log')]:
                digest=sha(native/file)
                if actual[key]!=digest or recorded[key]!=digest:
                    raise ValueError('Actual native exit/log differs: '+kind+'/'+name+'/'+key)
            command=read(native/'COMMAND.json')
            expected=[str(binary),'+IMAGE_MEMH=image.memh','+ZERO_STALL']
            expected+=({'honest':[],'negated':['+NEGATE_V'],'layer4':['+NEGATE_L4']}[name]
                       if kind=='plain' else ['+CASE='+str(CASES[kind].index(name))])
            if (command['argv']!=expected or Path(command['cwd']).resolve()!=source
                    or recorded['command_sha256']!=sha(native/'COMMAND.json')):
                raise ValueError('Actual native command identity differs: '+kind+'/'+name)
            events={'BOOT_AUTHENTICATED','KV_RETURN','KV_WRITE','L0_QUERY','L4_QUERY','L0_ATTENTION','L4_ATTENTION',
                'L0_PV','L4_PV','MEASURED_TOKEN','TWO_STEPS_COMPLETE','TOKEN'} if kind=='plain' else {
                'BOOT_AUTHENTICATED','PHY_RD','PHY_WR','SNAPSHOT','DIGEST','GUARD_OFFER','TOKEN','QUERY',
                'ATT_REQ','ATT_RSP','ATT_OUT','GUARD_FAULT','CLOSED','COMPLETED'}
            selected=[line for line in (native/'stdout.log').read_text().splitlines()
                      if line and line.split()[0] in events]
            trace=directory/(name+'.trace')
            if trace.read_text()!='\n'.join(selected)+'\n' or sha(trace)!=recorded['trace_sha256']:
                raise ValueError('Trace is not the exact extraction from the actual native log')
            tokens=[int(line.split()[-1]) for line in selected if line.startswith('TOKEN ')]
            expected_tokens=[200,15] if name in ('honest','negated') else ([200,1138] if kind=='plain' else [200])
            if recorded['tokens']!=tokens or tokens!=expected_tokens:
                raise ValueError('Saved tokens differ from the actual public handshakes')


def validate(args, comparison_output=None):
    check_inputs(args.repository)
    check_receipt_links(args.output)
    for kind,names in CASES.items():
        source=args.output/(kind+'-source')
        check_seal(source,read(args.output/(kind+'-SOURCE-SEAL.json'))['files'])
        built=read(args.output/(kind+'-BUILT.json'))
        if (sha(source/'obj'/('V'+TOP)) != built['binary_sha256']
                or sha(args.output/(kind+'-SOURCE-SEAL.json')) != built['source_seal_sha256']
                or sha(args.output/(kind+'-compile/COMMAND.json')) != built['command_sha256']):
            raise ValueError('Binary changed before validation')
        for name in names:
            directory=args.output/(kind+'-kv-observation');r=read(directory/(name+'-VERIFIED.json'))
            if not r['passed'] or r['kind']!=kind or r['case']!=name or r['actual_child_exit']!=0:
                raise ValueError('Case receipt differs')
            for key,file in [('trace_sha256',name+'.trace'),('stdout_sha256',name+'-native/stdout.log'),
                             ('stderr_sha256',name+'-native/stderr.log'),('command_sha256',name+'-native/COMMAND.json')]:
                if sha(directory/file) != r[key]:raise ValueError('Retained case evidence changed: '+kind+'/'+name+'/'+key)
    results={}
    for kind in CASES:
        directory=args.output/(kind+'-kv-observation')
        target=(args.output if comparison_output is None else comparison_output)/(kind+'-comparison')
        invoke([sys.executable,'-I','-S','-B',str(HERE/('compare_'+kind+'.py')),str(directory)],
               args.output,target)
        results[kind]=read(target/'stdout.log')
    return results


def controls(args, control_output=None):
    out=args.output/'controls' if control_output is None else control_output
    out.mkdir()
    refused=[]
    selected='demos/simplestories-v2-5m/hardware/project/cluster-tile.sv'
    original=args.repository/selected
    altered=out/'changed-source.sv';raw=original.read_bytes();altered.write_bytes(bytes([raw[0]^1])+raw[1:])
    try:check_input(altered,read(DRIVER/'SOURCE-INPUTS.json')['files'][selected])
    except ValueError as error:refused.append({'control':'changed-selected-source','refused':True,'reason':str(error)})
    else:raise ValueError('Changed source accepted')
    for name,kind in [('changed-trace','plain'),('wrong-numeric-reference','plain'),('wrong-SHA-digest','protected')]:
        fixture=out/name;fixture.mkdir()
        for k in CASES:
            destination=fixture/(k+'-kv-observation');destination.mkdir()
            source=args.output/(k+'-kv-observation')
            for f in source.iterdir():
                if f.suffix in ('.trace','.json') and f.is_file():shutil.copyfile(f,destination/f.name)
        if name=='changed-trace':
            f=fixture/'plain-kv-observation/layer4.trace';raw=f.read_bytes();f.write_bytes(bytes([raw[0]^1])+raw[1:])
        elif name=='wrong-numeric-reference':
            f=fixture/'plain-kv-observation/reference.json';r=read(f);r['layer4']['second_token']^=1;f.write_text(json.dumps(r))
        else:
            f=fixture/'protected-kv-observation/both.trace';lines=f.read_text().splitlines();changed=False
            for i,line in enumerate(lines):
                fields=line.split()
                if fields[0]=='DIGEST' and fields[2]=='0':
                    value=fields[-2];fields[-2]=('0' if value[0]!='0' else '1')+value[1:]
                    lines[i]=' '.join(fields);changed=True;break
            if not changed:raise ValueError('No genuine read SHA record for the defect control')
            f.write_text('\n'.join(lines)+'\n')
        row=invoke([sys.executable,'-I','-S','-B',str(HERE/('compare_'+kind+'.py')),str(fixture/(kind+'-kv-observation'))],
                   args.output,out/(name+'-child'),allow_failure=True)
        if row['actual_child_exit']==0:raise ValueError('Defect control accepted: '+name)
        refused.append({'control':name,'refused':True,**row})
    # A full positive view retains real commands, logs and native binaries.
    # Mutate only one independently copied saved field after that view passes.
    for name in ('saved-binary-identity','actual-native-exit'):
        fixture=out/name;fixture.mkdir()
        for path in args.output.iterdir():
            if path.name=='controls':continue
            if path.name=='plain-kv-observation':
                shutil.copytree(path,fixture/path.name)
            else:
                (fixture/path.name).symlink_to(path,target_is_directory=path.is_dir())
        check_receipt_links(fixture)
        target=fixture/'plain-kv-observation'/'honest-VERIFIED.json'
        if name=='actual-native-exit':target=fixture/'plain-kv-observation/honest-native/EXIT.json'
        record=read(target)
        if name=='saved-binary-identity':
            value=record['binary_sha256'];record['binary_sha256']=('0' if value[0]!='0' else '1')+value[1:]
        else:record['actual_child_exit']=19
        target.write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
        try:check_receipt_links(fixture)
        except ValueError as error:refused.append({'control':name,'refused':True,'real_positive_view_passed':True,'reason':str(error)})
        else:raise ValueError('Changed saved execution receipt accepted: '+name)
    # All assertion-based entry points must refuse optimized mode before argument/input access.
    scripts=[DRIVER.parent/'ENTRY-SNAPSHOT.py',*sorted(HERE.glob('*.py'))]
    for script in scripts:
        for flag in ('-O','-OO'):
            name=script.stem+'-'+flag[1:]
            row=invoke([sys.executable,'-I','-S','-B',flag,str(script),'--output',str(out/(name+'-must-not-exist'))],
                       args.output,out/('optimized-'+name),allow_failure=True)
            if row['actual_child_exit']==0 or 'Optimized Python is unsupported' not in (out/('optimized-'+name+'/stderr.log')).read_text():
                raise ValueError('Optimized mode was not explicitly refused: '+name)
            if (out/(name+'-must-not-exist')).exists():raise ValueError('Optimized mode accessed output')
    save(out/'RESULT.json',{'passed':True,'negative_controls':refused,'optimized_entry_checks':len(scripts)*2,
        'real_positive_evidence_unchanged':True})


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--repository',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--phase',required=True);parser.add_argument('--build-jobs',type=int,required=True)
    parser.add_argument('--jobs',type=int,required=True);args=parser.parse_args()
    check_inputs(args.repository)
    if args.phase in ('all','prepare'):prepare(args)
    prepared=read(args.output/'PREPARED.json')
    if (not prepared['passed'] or prepared['source_inputs_sha256']!=sha(DRIVER/'SOURCE-INPUTS.json')
            or prepared['tools_sha256']!=sha(args.output/'TOOLS.json')
            or prepared['driver_seal_sha256']!=sha(args.output/'DRIVER-SEAL.json')
            or prepared['independent_reference_sha256']!=sha(args.output/'plain-kv-observation/reference.json')
            or prepared['independent_reference_sha256']!=sha(args.output/'reference-generation/stdout.log')
            or read(args.output/'reference-generation/EXIT.json')['actual_child_exit']!=0):
        raise ValueError('Prepared source, tool or independent reference identity changed')
    for kind,digest in prepared['source_seals'].items():
        if digest!=sha(args.output/(kind+'-SOURCE-SEAL.json')):
            raise ValueError('Prepared source seal changed')
    if args.phase in ('all','build'):build(args)
    if args.phase in ('all','run'):run_cases(args)
    if args.phase in ('all','check'):
        results=validate(args);controls(args)
        # Recheck actual source, command, log and trace identities after all controls.
        check_inputs(args.repository)
        for kind,names in CASES.items():
            for name in names:
                d=args.output/(kind+'-kv-observation');r=read(d/(name+'-VERIFIED.json'))
                if sha(d/(name+'.trace'))!=r['trace_sha256']:raise ValueError('Positive trace changed by control')
        save(args.output/'RESULT.json',{'passed':True,'results':results,'cases':6,
            'controls_sha256':sha(args.output/'controls/RESULT.json'),
            'source_inputs_sha256':sha(DRIVER/'SOURCE-INPUTS.json'),
            'tools_sha256':sha(args.output/'TOOLS.json'),'finite_two_state_simulation':True,
            'hardware_or_training_rate_claim':False})
        print('PASS_PAIRED_PUBLIC_REPLAY',flush=True)


if __name__=='__main__':
    main()

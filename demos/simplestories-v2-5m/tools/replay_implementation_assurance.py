"""Run a fresh selected RTL proof phase, preserving the original evidence.

Use the portable recorded checker with --work first. This command validates
the frozen source inputs, compiles them with the locally installed Yosys, and
executes a real solver in a new output directory. No FPGA or vendor tool is used.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def helper():
    path=Path(__file__).with_name('check_implementation_assurance.py')
    if not path.is_file():path=path.with_name('check_recorded_package.py')
    spec=importlib.util.spec_from_file_location('_fresh_assurance_checker',path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    c=helper();parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--evidence',type=Path)
    parser.add_argument('--work',type=Path,required=True,help='Evidence extracted by the recorded checker')
    parser.add_argument('--run',required=True)
    parser.add_argument('--solver',choices=('z3','cvc5'),default='z3')
    parser.add_argument('--phase',choices=('bmc','induction','cover'),default='induction')
    parser.add_argument('--timeout',type=int)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();package=args.package.resolve(strict=True);work=args.work.resolve(strict=True)
    model=package/'demos/simplestories-v2-5m'if(package/'demos/simplestories-v2-5m/MANIFEST.json').is_file()else package
    evidence=(args.evidence or(model/'evidence/implementation-assurance')).resolve(strict=True)
    raw=(evidence/'INDEX.json').read_bytes();c.need(c.sha(raw)==c.EXPECTED_INDEX_SHA256,'Evidence index changed');index=json.loads(raw)
    selected=[r for r in index['runs']if r['run']==args.run];c.need(len(selected)==1,'Run is not part of the selected current suite')
    item=selected[0];run=work/'runs'/item['run'];inp_raw=(run/'INPUTS.json').read_bytes()
    c.need(c.sha(inp_raw)==item['inputs_sha256'],'Frozen input receipt changed');inp=json.loads(inp_raw)
    fin_raw=(run/'FINISHED.json').read_bytes();c.need(c.sha(fin_raw)==item['finished_sha256'],'Original result receipt changed');fin=json.loads(fin_raw)
    sources=evidence.parent.parent/'formal/implementation-assurance'
    for name,row in index['source_tools'].items():
        data=c.safe(sources,name).read_bytes();c.need(c.sha(data)==row['sha256']and len(data)==row['bytes'],'Source tool changed')
    common=c.load(sources,'run_handoff')
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):common.binding(package,variant)
    label=args.solver+'-'+args.phase;c.need(label in fin['results'],'This phase was not part of the selected run')
    command=list(fin['results'][label]['command'])
    c.need(command[0]=='yosys-smtbmc','Concrete QSPI witness checking uses check_qspi_witness.py rather than this replay command')
    if args.phase=='induction':c.need('-i'in command and'--smtc'not in command,'Induction constraints changed')
    timeout=args.timeout or int(command[command.index('--timeout')+1]);c.need(1<=timeout<=3600,'Timeout must be 1..3600 seconds')
    command[command.index('--timeout')+1]=str(timeout)
    if '--dump-smt2'not in command:command[-1:-1]=['--dump-smt2',label+'.smt2']
    if '--dummy'not in command:command[-1:-1]=['--dummy',label+'.responses']
    if '--dump-vcd'not in command:command[-1:-1]=['--dump-vcd',label+'-%.vcd']
    if '--noprogress'not in command:command[-1:-1]=['--noprogress']
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    for name,row in inp['files'].items():
        data=c.safe(run,name).read_bytes();c.need(c.sha(data)==row['sha256']and len(data)==row['bytes'],'Frozen RTL input changed')
        target=c.safe(out,name);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    tools={}
    for name in ('yosys','yosys-smtbmc',args.solver):
        binary=shutil.which(name);c.need(binary is not None,'Missing tool: '+name)
        tools[name]=dict(path=binary,sha256=c.sha(Path(binary).read_bytes()))
        if name!='yosys-smtbmc':
            cp=subprocess.run([name,'-V'if name=='yosys'else'--version'],capture_output=True,text=True,timeout=10)
            tools[name]['version']=(cp.stdout+cp.stderr).strip()
    with(out/'yosys.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=90)
    c.need(cp.returncode==0,'Fresh RTL compilation failed; see '+str(out/'yosys.log'))
    started=time.monotonic();timed_out=False
    with(out/(label+'.log')).open('w')as log:
        try:cp=subprocess.run(command,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=timeout+20);code=cp.returncode
        except subprocess.TimeoutExpired:code=None;timed_out=True
    log=(out/(label+'.log')).read_bytes();statuses=re.findall(rb'Status: (\w+)',log)
    expected=b'FAILED'if item['mutant']else b'PASSED'
    passed=not timed_out and code==(1 if item['mutant']else 0)and statuses==[expected]
    if item['mutant']:passed=passed and b'Assert failed in'in log and any(out.glob(label+'*.yw'))
    unchanged=all(c.sha(c.safe(out,n).read_bytes())==r['sha256']for n,r in inp['files'].items())
    result=dict(schema='fresh-current-implementation-proof-phase-v1',passed=bool(passed and unchanged),
        selected_run=item['run'],phase=label,mutant=item['mutant'],command=command,tools=tools,
        original_inputs_sha256=c.sha(inp_raw),fresh_compiler_executed=True,fresh_solver_executed=True,
        original_evidence_unchanged=True,source_inputs_unchanged=unchanged,
        emitted_smt_identical_to_recorded=(out/'design.smt2').read_bytes()==(run/'design.smt2').read_bytes(),
        exit=code,status=[s.decode()for s in statuses],timed_out=timed_out,seconds=time.monotonic()-started,
        solver_log_sha256=c.sha(log),query_sha256=c.sha((out/(label+'.smt2')).read_bytes()),
        solver_responses_sha256=c.sha((out/(label+'.responses')).read_bytes()),
        hardware_access=False,whole_machine_theorem=False,source_to_bitstream_equivalence=False)
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in ('passed','selected_run','phase','status','emitted_smt_identical_to_recorded','seconds')},sort_keys=True))
    raise SystemExit(0 if result['passed']else 1)


if __name__=='__main__':main()

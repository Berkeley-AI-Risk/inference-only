"""Shared bounded-process and file-registry helpers for local HWIC experiments."""
from pathlib import Path
import hashlib,json,os,signal,subprocess,sys,time,traceback,types

def pin(path):
    path=Path(path).resolve(strict=True)
    with path.open('rb')as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    return dict(path=str(path),bytes=path.stat().st_size,sha256=digest)
def read(path):return json.loads(Path(path).read_bytes())
def save(path,value):
    with Path(path).open('x')as stream:json.dump(value,stream,indent=2);stream.write('\n')
def load_source(descriptor,name):
    path=Path(descriptor['path']);raw=path.read_bytes();assert pin(path)==descriptor
    assert len(raw)==descriptor['bytes']and hashlib.sha256(raw).hexdigest()==descriptor['sha256']
    module=types.ModuleType(name);module.__file__=str(path);sys.modules[name]=module
    exec(compile(raw,str(path),'exec'),module.__dict__)
    return module
def rows(log):
    result=[]
    for line in Path(log).read_text(errors='replace').splitlines():
        if not line.startswith('{'):continue
        try:result.append(json.loads(line))
        except json.JSONDecodeError:pass
    return result
def registry_inputs(contract_path,binding_path,c,label):
    contract=read(contract_path);envelope=read(binding_path)
    assert envelope['contract_descriptor']==c.fingerprint(contract_path)
    controls=dict(envelope['files']);stage=contract['stages'][0]
    for row in contract['controls']:
        if row['id']in stage['control_inputs']and row['role']in ('contract','binding_envelope'):
            controls[row['id']]=c.fingerprint(contract_path if row['role']=='contract'else binding_path)
    v=c.Validator(contract,stage['id'],'input_post',None,controls=controls,audit_only=True)
    for key in sorted(v.current_file_ids):v.file(key)
    for key in sorted(v.roots):v.root(key)
    absences={}
    for tool in contract['tools']:
        for absence in tool['runtime']['absences']:absences[c.canonical(absence)]=absence
    for absence in absences.values():
        c.path_descriptor(absence['ancestor'],'runtime absence ancestor')
        assert str(Path(absence['ancestor']['path'])/absence['relative_path'])==absence['path']
        assert not os.path.lexists(absence['path'])
    return dict(label=label,files=len(v.read),recursive_roots=len(v.root_members),absences=len(absences),
                all_current_byte_path_namespace_checks_passed=True,closed_action_admission_claimed=False)

def run_outer(command,environment,cwd,work,identity_reader_module,lock_fd):
    """Own the child across every parent-side exception; preserve genuine status."""
    from datetime import datetime,timezone
    work=Path(work);log=work/'OUTER.log';child=None;status=usage=None;caught=None
    assert signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL
    assert dict(os.environ)==environment
    old_handlers={}
    def interrupted(sig,frame):raise InterruptedError('root signal '+str(sig))
    for sig in (signal.SIGTERM,signal.SIGINT):
        old_handlers[sig]=signal.getsignal(sig);signal.signal(sig,interrupted)
    began=time.monotonic()
    try:
        with log.open('xb')as stream:
            try:
                child=subprocess.Popen(command,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,
                    start_new_session=True,pass_fds=(lock_fd,),env=environment)
                save(work/'OUTER-STARTED.json',dict(pid=child.pid,launcher_PID=os.getpid(),argv=command,
                    started_utc=datetime.now(timezone.utc).isoformat()))
                done,status,usage=os.wait4(child.pid,0);assert done==child.pid
            except BaseException:
                caught=traceback.format_exc()
                if child is not None and status is None:
                    for sig in old_handlers:signal.signal(sig,signal.SIG_IGN)
                    try:terminal=identity_reader_module.ProcessReader().terminal_unreaped(child.pid)
                    except OSError as error:
                        save(work/'UNKNOWN-OUTER-OWNERSHIP.json',dict(pid=child.pid,error=repr(error),
                            signal_sent=False,outcome_unknown=True,completion_claimed=False))
                        raise RuntimeError('Outer wait ownership unknown; no cleanup signal sent')from error
                    if terminal is None:
                        try:os.kill(child.pid,signal.SIGTERM)
                        except ProcessLookupError:pass
                    done,status,usage=os.wait4(child.pid,0);assert done==child.pid
    finally:
        for sig,handler in old_handlers.items():signal.signal(sig,handler)
    assert child is not None and status is not None and usage is not None
    child.returncode=os.waitstatus_to_exitcode(status)
    record=dict(pid=child.pid,exit_code=child.returncode,raw_wait_status=status,
        wall_seconds=time.monotonic()-began,CPU_user_seconds=usage.ru_utime,CPU_system_seconds=usage.ru_stime,
        nonadditive_outer_aggregate=True,root_exception=caught,log=pin(log))
    save(work/'ACTUAL-OUTER-RETURN.json',record)
    observed=rows(log);outer=[r for r in observed if 'owned_controller_terminal_exit'in r]
    assert len(outer)==1 and outer[0]['all_observed_owned_descendants_terminal']
    assert not outer[0]['known_owned_descendants_still_live']
    if caught:raise RuntimeError('Root exception after owned tree drained: '+caught)
    return record,observed

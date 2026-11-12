#!/usr/bin/env python3
"""Portable, offline, full-machine protected Qwen3-1.7B long18 replay.

Only capture imports PyTorch/NumPy. No downloads, private paths, vendor tools,
FPGA access or automatic retries. Prepare/build do not execute the model.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
VARIANT = HERE.parent
MODEL = VARIANT.parents[1]
BANKS = dict(zip(('X','Z','Q','K','V','A','T','G','U','logits'), range(10)))
ELEMENTS = dict(X=2048,Z=2048,Q=2048,K=1024,V=1024,A=2048,T=2048,G=6144,U=6144,logits=151936)
IMAGE_BYTES = 2354380800


def need(ok, why):
    if not ok:
        raise ValueError(why)


def pin(path):
    path = Path(path)
    with path.open('rb') as stream:
        return dict(bytes=path.stat().st_size, sha256=hashlib.file_digest(stream,'sha256').hexdigest())


def read(path):
    return json.loads(Path(path).read_bytes())


def save(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def reference():
    return read(VARIANT/'references/long18.json')


def sources():
    locked = read(HERE/'INPUTS.json')['files']
    # Also preserve the short runner's independently owned dependency checks.
    short = read(VARIANT/'SOURCE-INPUTS.json')
    for root, files in ((MODEL,locked),(VARIANT,short['variant_files']),(MODEL,short['shared_public_files'])):
        for name, expected in files.items():
            path = root/name
            need(not Path(name).is_absolute() and '..' not in Path(name).parts and not path.is_symlink()
                 and path.resolve().is_relative_to(root.resolve()), 'Unsafe source input: '+name)
            need(pin(path)==expected, 'Changed source input: '+name)
    return locked


def model_image(path):
    expected = dict(bytes=IMAGE_BYTES,sha256=reference()['model_image_sha256'])
    need(pin(path)==expected, 'Wrong fixed model image (size or SHA-256); use tools/prepare_model.py')
    return expected


def tensor_tape(events):
    rows = [[e['operation'],e['layer'],e['tensor'],e['elements'],e['file'],e['sha256']] for e in events]
    return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()


def verify_oracle(directory):
    directory = Path(directory)
    need(not (directory/'FAILED.json').exists(), 'Oracle capture has an actual failure receipt')
    oracle = read(directory/'FINISHED.json')
    historical = reference()
    tape = read(HERE/'TENSOR-TAPE.json')
    need(oracle['run_completed'] and len(oracle['steps'])==18, 'Incomplete independent 18-step oracle')
    if oracle.get('schema')=='qwen-fixed-core-capture-v1':
        need(pin(directory/'FINISHED.json')==historical['original_receipt_identities']['independent_oracle_FINISHED'],
             'Unrecognized historical oracle; regenerate with capture')
        origin = 'verified historical independent oracle, not freshly regenerated'
    else:
        need(oracle.get('schema')=='qwen-portable-long18-oracle-v1', 'Unknown independent oracle schema')
        need(oracle['model_image']==dict(bytes=IMAGE_BYTES,sha256=historical['model_image_sha256']), 'Oracle model identity')
        need(oracle['source_inputs']==sources(), 'Oracle source identity changed')
        origin = 'portable independent software capture'
    jobs = []
    total = 0
    for pos, step in enumerate(oracle['steps']):
        need(step['position']==pos and step['input_token']==historical['input_token_tape'][pos]
             and step['next_token']==historical['expected_tokens'][pos], 'Independent greedy token tape mismatch')
        events = step['events']
        need(len(events)==507 and tensor_tape(events)==tape['step_tensor_tape_sha256'][pos],
             'Independent tensor coordinates/hashes differ at position '+str(pos))
        need(len({(e['operation'],e['layer'],e['tensor']) for e in events})==507, 'Duplicate tensor coordinate')
        jobs.append(f"STEP {pos} {step['input_token']} {step['next_token']}\n")
        for index,e in enumerate(events):
            name = f'{pos:02d}-{index:03d}.bin'
            need(e['file']==name and e['elements']==ELEMENTS[e['tensor']], 'Unsafe tensor filename/geometry')
            path = directory/name
            need(not path.is_symlink() and pin(path)==dict(bytes=2*e['elements'],sha256=e['sha256']), 'Corrupt/missing tensor: '+name)
            total += e['elements']
            jobs.append(f"EVENT {pos} {e['operation']} {e['layer']} {BANKS[e['tensor']]} {e['elements']} {name}\n")
    need(total==27581184 and oracle['tensor_boundaries']==9126 and oracle['bf16_values']==total, 'Oracle counts')
    jobs = ''.join(jobs)
    need(hashlib.sha256(jobs.encode()).hexdigest()==historical['jobs_sha256'], 'Complete jobs identity mismatch')
    return oracle, jobs, origin


def capture(image, output, threads):
    locked = sources()
    image_pin = model_image(image)  # Reject a wrong model before importing numerical libraries.
    output.mkdir(parents=True,exist_ok=False)
    record = dict(schema='qwen-portable-long18-oracle-v1',run_completed=False,source_inputs=locked,
                  model_image=image_pin,steps=[],scope='Independent CPU oracle, not RTL execution')
    save(output/'STARTED.json',record)
    started = time.monotonic()
    try:
        os.environ['PYTORCH_MPS_FAST_MATH']='0'
        sys.path.insert(0,str(MODEL/'reference'))
        import numpy as np
        import torch
        from fixed_qwen_reference import FixedQwenEngine
        torch.set_num_threads(threads)
        torch.set_float32_matmul_precision('highest')
        step = None
        def emit(code,layer,tensor,value):
            need(value.dtype==torch.bfloat16 and bool(torch.isfinite(value).all()), 'Nonfinite/non-BF16 oracle value')
            a=value.detach().cpu().contiguous().view(torch.int16).numpy().view(np.uint16)
            data=a.astype('<u2',copy=False).tobytes()
            filename=f"{step['position']:02d}-{len(step['events']):03d}.bin"
            with (output/filename).open('xb') as stream:
                stream.write(data)
            step['events'].append(dict(operation=code,layer=layer,tensor=tensor,elements=int(a.size),
                                       file=filename,sha256=hashlib.sha256(data).hexdigest()))
        def observe(name,value):
            if name=='model.embed_tokens': emit(0,0,'X',value)
            elif name=='model.norm': emit(21,27,'Z',value)
            elif name=='lm_head': emit(22,27,'logits',value)
            else:
                match=re.fullmatch(r'model.layers.(\d+)(?:\.(.*))?',name)
                need(match is not None,'Unexpected reference event: '+name)
                codes={None:(20,'X'),'input_layernorm':(1,'Z'),'self_attn.q_proj':(2,'Q'),
                       'self_attn.q_norm':(3,'Q'),'self_attn.k_proj':(4,'K'),'self_attn.k_norm':(5,'K'),
                       'self_attn.v_proj':(6,'V'),'self_attn.o_proj':(12,'T'),'post_attention_layernorm':(14,'Z'),
                       'mlp.gate_proj':(15,'G'),'mlp.up_proj':(16,'U'),'mlp.down_proj':(19,'T')}
                code,tensor=codes[match[2]]
                emit(code,int(match[1]),tensor,value)
        engine=FixedQwenEngine(image,device='cpu',observer=observe,serial_prefill=True,
            norm_arithmetic='ordered-fp32',nonlinear_arithmetic='fixed-tables',
            attention_arithmetic='tree-qk-ordered-av',softmax_arithmetic='fixed-exp2-exact-sum')
        norm,project,rotary,silu,attention=engine._norm,engine._project,engine._rotary,engine._silu,engine._attention
        def wrapped_norm(name,value):
            if name.endswith('.post_attention_layernorm'): emit(13,int(name.split('.')[2]),'X',value)
            return norm(name,value)
        def wrapped_project(name,value):
            if name.endswith('.mlp.down_proj'): emit(18,int(name.split('.')[2]),'G',value)
            return project(name,value)
        def wrapped_rotary(name,value,cosine,sine):
            result=rotary(name,value,cosine,sine)
            emit(7,int(name.split('.')[2]),'Q' if name.endswith('.q_rotary') else 'K',result)
            return result
        def wrapped_silu(name,value):
            result=silu(name,value); emit(17,int(name.split('.')[2]),'G',result); return result
        def wrapped_attention(name,q,k,v,mask):
            result=attention(name,q,k,v,mask); emit(9,int(name.split('.')[2]),'A',result); return result
        engine._norm,engine._project=wrapped_norm,wrapped_project
        engine._rotary,engine._silu,engine._attention=wrapped_rotary,wrapped_silu,wrapped_attention
        token=reference()['initial_token']
        for pos in range(18):
            step=dict(position=pos,input_token=token,events=[])
            token=engine.consume([token]); step['next_token']=token
            need(token==reference()['expected_tokens'][pos], 'Regenerated token differs at '+str(pos))
            need(tensor_tape(step['events'])==read(HERE/'TENSOR-TAPE.json')['step_tensor_tape_sha256'][pos],
                 'Regenerated independent tensors differ at '+str(pos))
            record['steps'].append(step)
            print(f'CAPTURE position={pos} token={token} tensor_boundaries={len(step["events"])}',flush=True)
        need(sources()==locked and model_image(image)==image_pin,'Inputs changed during capture')
        record.update(run_completed=True,tensor_boundaries=9126,bf16_values=27581184,
                      elapsed_seconds=time.monotonic()-started,torch=torch.__version__,numpy=np.__version__)
        save(output/'FINISHED.json',record)
        verify_oracle(output)
    except BaseException as error:
        save(output/'FAILED.json',dict(error=repr(error),elapsed_seconds=time.monotonic()-started))
        raise


def staged_sources():
    locked=sources()
    selected={}
    for directory in (MODEL/'hardware/design',VARIANT/'rtl',HERE/'tests'):
        for source in sorted(directory.iterdir()):
            if source.is_file() and source.suffix in ('.sv','.v','.vi','.vh','.cpp','.h','.hpp'):
                relative=source.relative_to(MODEL).as_posix()
                need(relative in locked and pin(source)==locked[relative],
                     'Unpinned compiler source: '+relative)
                need(source.name not in selected,'Duplicate staged source: '+source.name)
                selected[source.name]=source.read_bytes()
    # Reuse the existing public helper, rather than publishing another copy.
    helper=VARIANT/'tests/sha256_reference.h'
    relative=helper.relative_to(MODEL).as_posix()
    need(relative in locked and pin(helper)==locked[relative],'Unpinned shared compiler helper')
    selected['sha256_reference.h']=helper.read_bytes()
    name='qwen_hbm_cdc_verified_machine.sv'
    text=selected[name].decode(); old='    qwen_verified_machine #('
    need(text.count(old)==1,'Unexpected public wrapper selection')
    selected[name]=text.replace(old,'    qwen_protected_machine #(').encode()
    return selected


def prepare(image, oracle, output):
    locked=sources(); image_pin=model_image(image)
    _,jobs,origin=verify_oracle(oracle)
    selected=staged_sources()
    output.mkdir(parents=True,exist_ok=False)
    stage=output/'source'; stage.mkdir()
    # Local simulation selection only: retain the public default and board inventory.
    for name,data in selected.items():
        with (stage/name).open('xb') as stream: stream.write(data)
    for name,digest in reference()['runtime_files_sha256'].items():
        source=MODEL/'hardware/design/rom'/name
        need(pin(source)['sha256']==digest,'Different runtime ROM: '+name)
        shutil.copyfile(source,output/name)
    (output/'jobs.txt').write_text(jobs)
    manifest=dict(schema='qwen-portable-long18-prepared-v1',source_inputs=locked,
        source_files={p.name:pin(p) for p in stage.iterdir()},model_image=image_pin,
        oracle_manifest=pin(oracle/'FINISHED.json'),oracle_origin=origin,jobs=pin(output/'jobs.txt'),
        runtime_files={n:pin(output/n) for n in reference()['runtime_files_sha256']},
        selection='staged wrapper instance qwen_verified_machine -> qwen_protected_machine only',
        full_model_RTL_executed=False,automatic_retry=False)
    need(sources()==locked,'Inputs changed while preparing')
    save(output/'PREPARED.json',manifest)
    return manifest


def prepared(output, image=None, oracle=None):
    p=read(output/'PREPARED.json')
    current=sources()
    if p['source_inputs']!=current:
        rebound=read(output/'CONTROL-REBIND.json')
        need(rebound['original_prepared']==pin(output/'PREPARED.json')
             and rebound['original_build']==pin(output/'BUILT.json')
             and rebound['original_binary']==pin(output/'long18-test')
             and rebound['source_inputs']==current,
             'Prepared/control rebind identity differs')
    expected={name:dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
              for name,data in staged_sources().items()}
    need(p['source_files']==expected, 'Staged source derivation differs from canonical public inputs')
    for name,row in p['source_files'].items(): need(pin(output/'source'/name)==row,'Changed compiler input: '+name)
    for name,row in p['runtime_files'].items(): need(pin(output/name)==row,'Changed runtime ROM: '+name)
    need(pin(output/'jobs.txt')==p['jobs'],'Changed jobs file')
    if image is not None: need(model_image(image)==p['model_image'],'Different prepared model')
    if oracle is not None:
        _,jobs,_=verify_oracle(oracle)
        need(pin(oracle/'FINISHED.json')==p['oracle_manifest'] and (output/'jobs.txt').read_text()==jobs,'Changed prepared oracle')
    return p


def rebind_control(output):
    """Preserve a compiled build only when every compiler input remains exact."""
    need(not (output/'run').exists() and not (output/'VERIFIED.json').exists(),'Cannot rebind an executed case')
    p=read(output/'PREPARED.json'); b=read(output/'BUILT.json'); current=sources()
    need(b['prepared']==pin(output/'PREPARED.json') and b['binary']==pin(output/'long18-test'), 'Original build binding')
    need(b['compiler_source_files']==p['source_files'], 'Original compiler input identity')
    expected={name:dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
              for name,data in staged_sources().items()}
    need(expected==p['source_files'],'Compiler inputs changed; a new build is required')
    for name,row in expected.items(): need(pin(output/'source'/name)==row,'Retained compiler input changed')
    prefix='variants/protected-kv-simulation/full-machine/'
    allowed={prefix+n for n in ('replay.py','test_replay.py','README.md','tests/sha256_reference.h')}
    changed={n for n in set(p['source_inputs'])|set(current) if p['source_inputs'].get(n)!=current.get(n)}
    need(changed and changed<=allowed,'Changes extend beyond the reviewed control-only rebind')
    save(output/'CONTROL-REBIND.json',dict(original_prepared=pin(output/'PREPARED.json'),
        original_build=pin(output/'BUILT.json'),original_binary=pin(output/'long18-test'),
        source_inputs=current,changed_control_inputs=sorted(changed),
        compiler_input_map_unchanged=True,old_receipts_rewritten=False))
    prepared(output)


def child(argv, cwd, directory, seconds):
    directory.mkdir(exist_ok=False)
    record=dict(argv=[str(a) for a in argv],started_utc=datetime.now(timezone.utc).isoformat(),
                timeout_seconds=seconds,automatic_retry=False,actual_child_exit=None,stop_reason=None,error=None)
    save(directory/'STARTED.json',record)
    start=time.monotonic(); process=None
    handlers={}

    def cancel(signum, frame):
        # Keep signals from throwing out of Popen or cleanup. The wait loop
        # notices cancellation; repeated requests cannot skip child reaping.
        name=signal.Signals(signum).name
        record.setdefault('interrupted_signal',name)
        record['stop_reason']=record['stop_reason'] or 'parent_signal_'+name

    try:
        for signum in (signal.SIGTERM,signal.SIGINT):
            handlers[signum]=signal.signal(signum,cancel)
        with (directory/'stdout.log').open('xb') as stdout,(directory/'stderr.log').open('xb') as stderr:
            if not record['stop_reason']:
                process=subprocess.Popen(argv,cwd=cwd,stdout=stdout,stderr=stderr,start_new_session=True,
                                         env=dict(os.environ,CCACHE_DISABLE='1'))
                record['pid']=process.pid
                deadline=time.monotonic()+seconds
                while process.poll() is None and not record['stop_reason']:
                    remaining=deadline-time.monotonic()
                    if remaining<=0:
                        record['stop_reason']='process_timeout'
                        break
                    try: process.wait(timeout=min(0.1,remaining))
                    except subprocess.TimeoutExpired: pass
    except BaseException as error:
        record['error']=repr(error)
        raise
    finally:
        try:
            try:
                if process is not None and process.poll() is None:
                    try:
                        need(os.getpgid(process.pid)==process.pid,'Owned child group identity changed')
                        os.killpg(process.pid,signal.SIGTERM)
                    except ProcessLookupError: pass
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        try:
                            need(os.getpgid(process.pid)==process.pid,'Owned child group identity changed')
                            os.killpg(process.pid,signal.SIGKILL)
                        except ProcessLookupError: pass
                        process.wait()
            except BaseException as error:
                record['cleanup_error']=repr(error)
                record['error']=record['error'] or repr(error)
                record['stop_reason']=record['stop_reason'] or 'owned_child_cleanup_failed'
            if process is not None: record['actual_child_exit']=process.returncode
            record.update(elapsed_seconds=time.monotonic()-start,ended_utc=datetime.now(timezone.utc).isoformat(),
                          launched=process is not None,
                          owned_child_reaped=process is not None and process.returncode is not None,
                          passed=process is not None and process.returncode==0
                                 and record['stop_reason'] is None and record['error'] is None)
            record['stdout']=pin(directory/'stdout.log') if (directory/'stdout.log').is_file() else None
            record['stderr']=pin(directory/'stderr.log') if (directory/'stderr.log').is_file() else None
            save(directory/'EXIT.json',record)
        finally:
            for signum,previous in handlers.items(): signal.signal(signum,previous)
    need(record['actual_child_exit']==0 and record['stop_reason'] is None and record['error'] is None,
         'Child failed/interrupted; see '+str(directory))
    return record


def check_child_logs(directory, terminal):
    need(terminal['stdout']==pin(directory/'stdout.log'),'Changed stdout after recorded child exit')
    need(terminal['stderr']==pin(directory/'stderr.log'),'Changed stderr after recorded child exit')


def build(output):
    p=prepared(output)
    tool=shutil.which('verilator'); need(tool is not None,'Install Verilator and a C++17 compiler')
    work=Path(tempfile.mkdtemp(prefix='qwen17-long18-',dir='/tmp'))
    need(not any(c.isspace() for c in str(work)),'Unspaced compiler scratch required')
    stage=work/'source'; shutil.copytree(output/'source',stage)
    flags='-std=c++17 -O2 -ffp-contract=off -DQWEN_KV_PROTECTED=1'
    argv=[tool,'--cc','--exe','--build','--assert','-Wno-fatal','-j','1','--threads','1',
          '--top-module','qwen_hbm_cdc_verified_machine','--prefix','Vqwen_kv_variant_core',
          '-GMODEL_PREFETCH_PAGES=32','-I'+str(stage),'-y',str(stage),'+libext+.sv+.v',
          '-Mdir',str(work/'obj'),'-o','long18-test','-CFLAGS',flags]
    argv += [str(f) for f in sorted(stage.glob('*.v'))]
    argv += [str(stage/'qwen_hbm_cdc_verified_machine.sv'),str(stage/'long18.cpp')]
    receipt=child(argv,work,output/'build',1800)
    warnings=(output/'build/stderr.log').read_text()
    need('%Warning-UNOPTFLAT:' not in warnings and '%Warning-MODDUP:' not in warnings,'Feedback/duplicate module warning')
    for name,row in p['source_files'].items(): need(pin(stage/name)==row,'Compiler copy changed: '+name)
    prepared(output)
    shutil.copyfile(work/'obj/long18-test',output/'long18-test'); (output/'long18-test').chmod(0o755)
    save(output/'BUILT.json',dict(binary=pin(output/'long18-test'),prepared=pin(output/'PREPARED.json'),
        build_exit=pin(output/'build/EXIT.json'),elapsed_seconds=receipt['elapsed_seconds'],
        compiler_source_files=p['source_files'],compiler_directory=str(stage),full_model_RTL_executed=False))


def check_transcript(text, command_records=True):
    need(not re.search(r'^FAIL\b',text,re.M),'FAIL in raw transcript')
    layers=[(int(a),int(b)) for a,b in re.findall(r'^PASS layer position=(\d+) layer=(\d+) cycles=\d+$',text,re.M)]
    need(layers==[(p,l) for p in range(18) for l in range(28)],'Incomplete/unordered layer checks')
    tokens=[(int(a),int(b)) for a,b in re.findall(r'^PASS token position=(\d+) token=(\d+) step_cycles=\d+$',text,re.M)]
    need(tokens==list(enumerate(reference()['expected_tokens'])),'Independent token mismatch')
    final=re.findall(r'^PASS working_qwen_profile .+$',text,re.M)
    need(len(final)==1 and text.rstrip().endswith(final[0]),'Missing/ambiguous original terminal PASS')
    counts={k:int(v) for k,v in re.findall(r'\b(\w+)=(\d+)\b',final[0])}
    for key,value in reference()['review']['counts'].items():
        if key not in ('cycles','raw_pages','raw_beats'): need(counts.get(key)==value,'Incomplete coverage: '+key)
    need(counts.get('cycles',0)>0 and counts.get('raw_pages',0)>0 and counts.get('raw_beats',0)>0,'No actual memory activity')
    if command_records:
        commands=[(int(a),int(b)) for a,b in re.findall(r'^COMMAND accepted opcode=(\d+) token=(\d+)$',text,re.M)]
        need(commands==[(3,0),(1,reference()['initial_token'])]+[(2,0)]*18+[(3,0)],'Actual APPEND/STEP/CLEAR command coverage')
    return dict(tokens=[t for _,t in tokens],ordered_layers=len(layers),counts=counts)


def verify_run(output,image,oracle):
    p=prepared(output,image,oracle); b=read(output/'BUILT.json'); terminal=read(output/'run/EXIT.json')
    need(b['prepared']==pin(output/'PREPARED.json') and b['binary']==pin(output/'long18-test'), 'Binary/build identity changed')
    need(b['compiler_source_files']==p['source_files'],'Different compiler source identity')
    need(b['build_exit']==pin(output/'build/EXIT.json') and read(output/'build/EXIT.json')['actual_child_exit']==0,'Build child identity/exit')
    need(terminal['actual_child_exit']==0 and terminal['stop_reason'] is None and terminal['error'] is None,'Actual simulator failed/interrupted')
    check_child_logs(output/'run',terminal)
    need(terminal['argv']==[str(output/'long18-test'),str(image),str(oracle),str(output/'jobs.txt')],'Actual simulator/input identity')
    need(not (output/'run/stderr.log').read_bytes(),'Simulator stderr is not empty')
    result=check_transcript((output/'run/stdout.log').read_text())
    result.update(passed=True,scope='Fresh portable full-machine simulation only; no physical qualification',
        terminal=pin(output/'run/EXIT.json'),stdout=pin(output/'run/stdout.log'),binary=b['binary'],
        elapsed_seconds=terminal['elapsed_seconds'],source_inputs=p['source_inputs'],oracle_origin=p['oracle_origin'])
    result['review_control_inputs']=sources()
    result['control_rebind']=pin(output/'CONTROL-REBIND.json') if (output/'CONTROL-REBIND.json').is_file() else None
    save(output/'VERIFIED.json',result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('check-sources','capture','check-oracle','prepare','build','rebind-control','run','verify'))
    parser.add_argument('--model-image',type=Path)
    parser.add_argument('--oracle',type=Path)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--threads',type=int,default=8)
    parser.add_argument('--max-seconds',type=int,default=18000)
    args=parser.parse_args()
    for name in ('model_image','oracle','output'):
        value=getattr(args,name)
        if value is not None: setattr(args,name,value.resolve())
    need(1<=args.threads<=32 and 1<=args.max_seconds<=86400,'Invalid finite resource setting')
    sources()
    if args.action=='check-sources': print(json.dumps(dict(source_inputs=len(sources()),RTL_executed=False))); return
    if args.action=='check-oracle':
        need(args.oracle is not None,'--oracle required')
        oracle,_,origin=verify_oracle(args.oracle)
        print(json.dumps(dict(oracle_origin=origin,tokens=[s['next_token'] for s in oracle['steps']],
                              tensor_boundaries=9126,bf16_values=27581184,RTL_executed=False))); return
    need(args.output is not None,'--output required')
    if args.action=='capture':
        need(args.model_image is not None,'--model-image required')
        capture(args.model_image,args.output,args.threads)
    elif args.action=='prepare':
        need(args.model_image is not None and args.oracle is not None,'--model-image and --oracle required')
        prepare(args.model_image,args.oracle,args.output)
    elif args.action=='build': build(args.output)
    elif args.action=='rebind-control': rebind_control(args.output)
    else:
        need(args.model_image is not None and args.oracle is not None,'--model-image and --oracle required')
        if args.action=='run':
            prepared(args.output,args.model_image,args.oracle)
            b=read(args.output/'BUILT.json')
            need(b['prepared']==pin(args.output/'PREPARED.json') and b['binary']==pin(args.output/'long18-test'),'Changed binary/build')
            child([str(args.output/'long18-test'),str(args.model_image),str(args.oracle),str(args.output/'jobs.txt')],
                  args.output,args.output/'run',args.max_seconds)
        result=verify_run(args.output,args.model_image,args.oracle)
        print(json.dumps(dict(passed=result['passed'],tokens=result['tokens'],ordered_layers=result['ordered_layers'])))


if __name__=='__main__':
    main()

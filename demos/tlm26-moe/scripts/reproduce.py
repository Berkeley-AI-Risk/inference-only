"""Acquire only pinned small inputs and run each private or released replay stage."""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')
import argparse,hashlib,importlib.util,json,os,shutil,subprocess,sys,tempfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PINS=json.loads((ROOT/'metadata/pins.json').read_bytes())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def fetched(url,path,expected,limit):
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists():
        if sha(path)!=expected:raise ValueError('different existing file '+str(path))
        return
    with urllib.request.urlopen(url) as response:
        raw=response.read(limit+1)
    if len(raw)>limit or hashlib.sha256(raw).hexdigest()!=expected:raise ValueError('upstream hash mismatch '+str(path))
    path.write_bytes(raw)
def upstream():
    rev=PINS['author_source_revision'];hf=PINS['checkpoint_revision']
    for name,pin in PINS['upstream_input_sha256'].items():
        url=f'https://huggingface.co/h1matthew/tlm26/resolve/{hf}/moe_d64_e8/model.pt' if name=='model.pt' else f'https://raw.githubusercontent.com/ANRGUSC/tlm26/{rev}/tinylm/'+('data/' if name=='tok512.model' else '')+name
        fetched(url,ROOT/'upstream'/name,pin,6340671)
def cpu():
    (ROOT/'receipts').mkdir(exist_ok=True);(ROOT/'build').mkdir(exist_ok=True)
    for name in ['checkpoint_reference','integer_reference','layout','generate_decoder']:
        subprocess.run([sys.executable,ROOT/'scripts'/(name+'.py')],cwd=ROOT,check=True)
    actual=json.loads((ROOT/'receipts/integer-cpu.json').read_bytes())['results']
    reference=json.loads((ROOT/'evidence/integer-cpu.json').read_bytes())['results']
    assert actual==reference and sha(ROOT/'build/model.bin')=='221d412a48f1809d6b9cc46ab9f8d572c37af226d07ec710c82bd0d530b49ce1'
def board_input(name,folder):
    f=PINS['board_inputs'][name];u=f"https://raw.githubusercontent.com/Berkeley-AI-Risk/inference-only/{PINS['board_revision']}/{f['repo_path']}"
    fetched(u,folder/name,f['sha256'],180000)
def rtl():
    work=Path(tempfile.mkdtemp(prefix='tlm26-rtl-'))
    for p in list((ROOT/'rtl').glob('*.sv'))+[ROOT/'tests/boot_product.sv',ROOT/'tests/product_sim.cpp']:
        shutil.copyfile(p,work/p.name)
    for p in ['fixed_uart_rx.sv','fixed_uart_tx.sv']:board_input(p,work)
    subprocess.run(['verilator','-Wno-fatal','--cc','--exe','--build','-j','2','-CFLAGS','-DBOOT_TEST -std=c++20 -O2','--top-module','boot_product',*[p.name for p in sorted(work.glob('*.sv'))],'product_sim.cpp'],cwd=work,check=True)
    for name,commands in [('honest','product_commands.txt'),('corrupt','physical-corruption-commands.txt')]:
        env=os.environ.copy();env.pop('BAD_BOOT_PAGE',None)
        if name=='corrupt':env['BAD_BOOT_PAGE']='1'
        dst=ROOT/'receipts'/('boot3-'+name+'-simulation.log')
        with (ROOT/'tests'/commands).open() as std_in,dst.open('w') as std_out:
            subprocess.run([work/'obj_dir/Vboot_product'],cwd=ROOT/'build',stdin=std_in,stdout=std_out,env=env,check=True)
        assert dst.read_bytes()==(ROOT/'evidence'/dst.name).read_bytes()
def stage(directory):
    directory.mkdir(parents=True,exist_ok=False)
    for p in [*sorted((ROOT/'board').iterdir()),*sorted((ROOT/'rtl').glob('*.sv'))]:
        shutil.copyfile(p,directory/p.name)
    for n in ['page_digest.hex','exp.hex','cos.hex','sin.hex']:shutil.copyfile(ROOT/'build'/n,directory/n)
    for n in PINS['board_inputs']:board_input(n,directory)
    for n,f in PINS['vendor_inputs'].items():fetched(f['url'],directory/n,f['sha256'],f['bytes'])
    for n,h in PINS['all_native_input_hashes'].items():
        assert sha(directory/n)==h,n
    print('Exact build inputs verified in',directory)

def dispatch_sources(source_root=None):
    """Check the public sources for the recorded observer, without running tools."""
    bindings=json.loads((ROOT/'evidence/expert-dispatch/source-bindings.json').read_bytes())
    found={}
    for name,expected in bindings['sources'].items():
        relative=Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('unsafe dispatch source path '+name)
        prefix='demos/tlm26-moe/'
        candidates=([ROOT/name[len(prefix):]] if name.startswith(prefix) else
                    ([source_root/name] if source_root is not None else [])+[parent/name for parent in ROOT.parents])
        source=next((p for p in candidates if p.is_file()),None)
        if source is None:
            raise ValueError('dispatch source missing; use the complete release checkout: '+name)
        if {'bytes':source.stat().st_size,'sha256':sha(source)}!=expected:
            raise ValueError('dispatch source changed: '+name)
        if source.name in found:
            raise ValueError('duplicate staged dispatch source '+source.name)
        found[source.name]=source
    if len(found)!=12:
        raise ValueError('expected twelve bound dispatch sources')
    stimulus=bindings['stimulus']
    command=ROOT/'tests/dispatch_commands.txt'
    if {'bytes':command.stat().st_size,'sha256':sha(command)}!={k:stimulus[k] for k in ('bytes','sha256')}:
        raise ValueError('dispatch commands changed')
    expected=bindings['expected']
    reference=ROOT/'evidence/expert-dispatch/expected.json'
    if {'bytes':reference.stat().st_size,'sha256':sha(reference)}!={k:expected[k] for k in ('bytes','sha256')}:
        raise ValueError('dispatch reference changed')
    return bindings,found

def dispatch(directory,prepare_only=False,source_root=None):
    """Stage one observer replay in a fresh directory; never overwrite a result."""
    directory=directory.resolve()
    if directory.exists() or directory.is_relative_to(ROOT):
        raise ValueError('dispatch requires a fresh output directory outside the demo')
    for parent in ROOT.parents:
        if (parent/'tools/verify_release.py').is_file() and directory.is_relative_to(parent):
            raise ValueError('dispatch output must be outside the release checkout')
    bindings,sources=dispatch_sources(source_root)
    def check_runtime():
        for name,expected in bindings['runtime_files'].items():
            source=ROOT/'build'/name
            if not source.is_file() or {'bytes':source.stat().st_size,'sha256':sha(source)}!=expected:
                raise ValueError('missing or changed build/'+name+'; run the documented CPU preparation first')
    check_runtime()
    if not prepare_only:
        spec=importlib.util.spec_from_file_location('dispatch_checker',ROOT/'scripts/check_dispatch.py')
        checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
    compiler=shutil.which('verilator')
    if compiler is None:
        raise ValueError('verilator must be on PATH')
    directory.mkdir(parents=True,exist_ok=False)
    staged=directory/'source';staged.mkdir()
    source_pins={Path(name).name:value for name,value in bindings['sources'].items()}
    for name,source in sources.items():
        shutil.copyfile(source,staged/name)
        if {'bytes':(staged/name).stat().st_size,'sha256':sha(staged/name)}!=source_pins[name]:
            raise ValueError('source changed during staging: '+name)
    command=directory/'commands.txt';shutil.copyfile(ROOT/'tests/dispatch_commands.txt',command)
    if {'bytes':command.stat().st_size,'sha256':sha(command)}!={k:bindings['stimulus'][k] for k in ('bytes','sha256')}:
        raise ValueError('dispatch commands changed during staging')
    argv=[compiler,'-Wno-fatal','--cc','--exe','--build','-j','2','-CFLAGS',
          '-DBOOT_TEST -std=c++20 -O2','--top-module','boot_product',
          *sorted(name for name in sources if name.endswith('.sv')),'product_sim.cpp']
    plan={'schema':'tlm26-dispatch-replay-plan-v1','build_argv':argv,'build_cwd':str(staged),
          'runtime_cwd':str(ROOT/'build'),'binary':str(staged/'obj_dir/Vboot_product'),
          'stdin':str(command),'source_bindings_sha256':sha(ROOT/'evidence/expert-dispatch/source-bindings.json'),
          'environment_remove':['BAD_BOOT_PAGE'],'source_sha256':{n:sha(staged/n) for n in sorted(sources)},
          'runtime_files':bindings['runtime_files'],'prepare_only':prepare_only}
    (directory/'PLAN.json').write_text(json.dumps(plan,indent=2,sort_keys=True)+'\n')
    if prepare_only:
        print(json.dumps({'prepared':True,'native_execution':False,'plan':str(directory/'PLAN.json')}))
        return
    def run_phase(label,args,cwd,stdin=None,env=None):
        with (directory/(label+'.stdout.log')).open('xb') as stdout,(directory/(label+'.stderr.log')).open('xb') as stderr:
            result=subprocess.run(args,cwd=cwd,stdin=stdin if stdin is not None else subprocess.DEVNULL,
                                  stdout=stdout,stderr=stderr,env=env,check=False)
        (directory/(label+'.exit.json')).write_text(json.dumps({'argv':[str(x) for x in args],
            'cwd':str(cwd),'actual_exit':result.returncode},indent=2)+'\n')
        if result.returncode:
            raise RuntimeError(label+' failed; preserve this directory and inspect its logs')
    run_phase('compile',argv,staged)
    binary=staged/'obj_dir/Vboot_product'
    env=os.environ.copy();env.pop('BAD_BOOT_PAGE',None)
    check_runtime()
    with command.open('rb') as stdin:run_phase('native',[binary],ROOT/'build',stdin,env)
    if (directory/'native.stderr.log').read_bytes():
        raise ValueError('unexpected native stderr; preserve the replay logs')
    # Import only the release checker. No CPU oracle or original private runner.
    result=checker.check((directory/'native.stdout.log').read_text(),
        json.loads((ROOT/'evidence/expert-dispatch/expected.json').read_bytes()),
        json.loads((ROOT/'evidence/physical.json').read_bytes()))
    result.update(binary_sha256=sha(binary),stdout_sha256=sha(directory/'native.stdout.log'),
                  source_bindings_sha256=plan['source_bindings_sha256'],actual_native_exit=0)
    (directory/'RESULT.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result,indent=2,sort_keys=True))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['fetch','cpu','rtl','stage','dispatch','dispatch-sources']);p.add_argument('destination',nargs='?',type=Path)
    p.add_argument('--prepare-only',action='store_true',help='stage dispatch sources and plan without compiling or simulating')
    p.add_argument('--source-root',type=Path,help='complete release checkout containing the shared UART sources')
    a=p.parse_args()
    if a.prepare_only and a.action!='dispatch':p.error('--prepare-only is for dispatch')
    if a.source_root and a.action not in ('dispatch','dispatch-sources'):p.error('--source-root is for dispatch sources')
    if a.action in ('stage','dispatch'):
        if not a.destination:p.error(a.action+' requires an empty destination path')
        if a.action=='stage':stage(a.destination)
        else:dispatch(a.destination,a.prepare_only,a.source_root)
    elif a.action=='dispatch-sources':
        bindings,sources=dispatch_sources(a.source_root);print(json.dumps({'passed':True,'sources_checked':len(sources),'native_execution':False}))
    else:{'fetch':upstream,'cpu':cpu,'rtl':rtl}[a.action]()

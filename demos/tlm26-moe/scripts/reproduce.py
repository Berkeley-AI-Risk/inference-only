"""Acquire only pinned small inputs and run each private or released replay stage."""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')
import argparse,hashlib,json,os,shutil,subprocess,sys,tempfile,urllib.request
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
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['fetch','cpu','rtl','stage']);p.add_argument('destination',nargs='?',type=Path);a=p.parse_args()
    if a.action=='stage':
        if not a.destination:p.error('stage requires an empty destination path')
        stage(a.destination)
    else:{'fetch':upstream,'cpu':cpu,'rtl':rtl}[a.action]()

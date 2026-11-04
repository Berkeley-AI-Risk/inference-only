#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--fast',action='store_true');a=p.parse_args()
out=ROOT/'evidence'/('tang-fast-simulation' if a.fast else 'tang-simulation');out.mkdir(exist_ok=True)
if (out/'BUILD.json').exists() or (out/'build.log').exists():
    raise FileExistsError('Preserve the previous campaign directory before compiling another build')
build=Path(tempfile.mkdtemp(prefix='swic-tang-sim-'))
project=ROOT/'hardware/project'
shutil.copytree(project,build/'project')
files=[]
for line in (project/'production_sources.f').read_text().splitlines():
    line=line.strip()
    if not line or line.startswith('#'):continue
    if line.startswith('official/') or 'board1_gowin_ddr3_raw_controller_shell.sv' in line or line=='defines.v':continue
    if a.fast and line=='swic/swic_qspi_boot_source.sv':continue
    if line.endswith(('.sv','.v')):
        assert (project/line).exists(),line
        files.append('project/'+line)
for name in ['phy_model.sv','tb_tang.sv']:
    shutil.copyfile(ROOT/'tests'/name,build/name);files.append(name)
if a.fast:
    s=(project/'swic/swic_qspi_boot_source.sv').read_text();start=s.index('module ');end=s.index('\n);',start)+4
    (build/'fast_flash.sv').write_text('`timescale 1ns/1ps\n'+s[start:end]+'\n'+(ROOT/'tests/fast_flash_body.sv').read_text())
    files.append('fast_flash.sv')
cmd=['verilator','--binary','--timing','-DSYNTHESIS','-Wno-fatal','--top-module','tb_tang','-j','1',
     '--output-split','20000','--output-split-cfuncs','500','-CFLAGS','-O2','--Mdir','obj']+files
if a.fast:cmd.insert(4,'-DSWIC_FAST_FLASH')
t=time.time()
with (out/'build.log').open('w') as log:subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT,check=True)
source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in project.rglob('*') if p.is_file()}
for name in ['phy_model.sv','tb_tang.sv']:source_hashes['tests/'+name]=hashlib.sha256((ROOT/'tests'/name).read_bytes()).hexdigest()
result={'build_directory':str(build),'binary':str(build/'obj/Vtb_tang'),'source_sha256':source_hashes,
        'simulation_cwd':str(build/'project'),
        'fast_flash_source_abstraction':a.fast,
        'command':cmd,'elapsed_seconds':time.time()-t,'phy_abstraction':'simulation-only raw clock/calibration/DDR storage; real native UART, SPI, CDC, boot, hash, page service, token arithmetic'}
(out/'BUILD.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'binary':result['binary'],'elapsed_seconds':result['elapsed_seconds']},indent=2))

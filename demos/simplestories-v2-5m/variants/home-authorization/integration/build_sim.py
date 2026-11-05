#!/usr/bin/env python3
"""Compile complete Tang source with home authorization and modeled entropy/DDR."""
import argparse,hashlib,json,shutil,sys,tempfile,time,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import clock_variant
import shared_selector
import permit_register
import shared_boot_compressor
import publication_guard
import registered_nonce
import compact_norm
import registered_collision
import sha_data_reset
import verifier_reset_arm
import startup_reset_phase
import startup_reset_qualifier
import qspi_reset_guard
import qspi_phase_reset
import permit_fanout
import qspi_core_buffers
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import home_auth as h
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--fixtures',type=Path,required=True)
p.add_argument('--core-divider',type=int,choices=[2,4],default=2)
p.add_argument('--share-message-selector',action='store_true')
p.add_argument('--registered-permit',action='store_true')
p.add_argument('--share-boot-compressor',action='store_true')
p.add_argument('--direct-publication-guard',action='store_true')
p.add_argument('--registered-nonce-data',action='store_true')
p.add_argument('--compact-norm-loader',action='store_true')
p.add_argument('--narrow-norm-carry',action='store_true')
p.add_argument('--registered-metadata-collision',action='store_true')
p.add_argument('--resetless-sha-data',action='store_true')
p.add_argument('--registered-verifier-reset',action='store_true')
p.add_argument('--falling-edge-startup-reset',action='store_true')
p.add_argument('--phase-qualified-startup-reset',action='store_true')
p.add_argument('--qualified-qspi-reset',action='store_true')
p.add_argument('--phase-qualified-qspi-reset',action='store_true')
p.add_argument('--permit-reset-maxfan',type=int,default=0)
p.add_argument('--qspi-core-reset-buffers',type=int,default=0)
a=p.parse_args();assert not a.narrow_norm_carry or a.compact_norm_loader
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
project=ROOT/'integration/project';build=Path(tempfile.mkdtemp(prefix='home-tang-'))
shutil.copytree(project,build/'project')
clock_variant.apply_project(build/'project',a.core_divider)
assert not(a.falling_edge_startup_reset and a.phase_qualified_startup_reset)
if a.falling_edge_startup_reset:startup_reset_phase.apply(build/'project')
if a.phase_qualified_startup_reset:startup_reset_qualifier.apply(build/'project')
assert not a.qualified_qspi_reset or a.phase_qualified_startup_reset
if a.qualified_qspi_reset:qspi_reset_guard.apply(build/'project')
assert not(a.qualified_qspi_reset and a.phase_qualified_qspi_reset)
assert not a.phase_qualified_qspi_reset or a.phase_qualified_startup_reset
if a.phase_qualified_qspi_reset:qspi_phase_reset.apply(build/'project')
if a.qspi_core_reset_buffers:
    assert not(a.qualified_qspi_reset or a.phase_qualified_qspi_reset)
    qspi_core_buffers.apply(build/'project',a.qspi_core_reset_buffers)
if a.share_message_selector:
    shared_selector.apply(build/'project')
if a.registered_permit:
    permit_register.apply(build/'project')
if a.permit_reset_maxfan:
    assert a.registered_permit
    permit_fanout.apply(build/'project',a.permit_reset_maxfan)
if a.share_boot_compressor:
    shared_boot_compressor.apply(build/'project')
if a.direct_publication_guard:
    publication_guard.apply(build/'project')
if a.compact_norm_loader:
    compact_norm.apply(build/'project',a.narrow_norm_carry)
if a.registered_metadata_collision:
    registered_collision.apply(build/'project')
if a.resetless_sha_data:
    sha_data_reset.apply(build/'project')
if a.registered_verifier_reset:
    verifier_reset_arm.apply(build/'project')
files=[]
for line in (project/'production_sources.f').read_text().splitlines():
    line=line.strip()
    if not line or line.startswith('#') or line.startswith('official/') or line=='defines.v' or 'board1_gowin_ddr3_raw_controller_shell.sv' in line or line=='swic/swic_qspi_boot_source.sv':continue
    if line.endswith(('.sv','.v')):files.append('project/'+line)
files+=['project/home/home_boot_gate.sv','project/home/home_uart_transport.sv']
shutil.copyfile(ROOT/'nonce/nonce_frontend.sv',build/'nonce_frontend.sv');files.append('nonce_frontend.sv')
if a.registered_nonce_data:
    q=build/'nonce_frontend.sv';q.write_text(registered_nonce.frontend(q.read_text()))
for name in ['phy_model.sv','tb_home_tang.sv']:
    content=(ROOT/'integration/tests'/name).read_text()
    content=(clock_variant.phy_text(content,a.core_divider) if name=='phy_model.sv'
             else clock_variant.testbench_text(content,a.core_divider))
    if name=='tb_home_tang.sv' and a.registered_permit:
        content=permit_register.testbench_text(content)
    if name=='tb_home_tang.sv' and a.registered_nonce_data:
        content=registered_nonce.testbench(content)
    (build/name).write_text(content);files.append(name)
source=(project/'swic/swic_qspi_boot_source.sv').read_text();start=source.index('module ');end=source.index('\n);',start)+4
(build/'fast_flash.sv').write_text('`timescale 1ns/1ps\n'+source[start:end]+'\n'+(ROOT/'integration/tests/fast_flash_body.sv').read_text());files.append('fast_flash.sv')
domain=b'SAWIC-NONCE-v1'.ljust(16,b'\0')
n1=hashlib.sha256(domain+bytes((13*i+7)%256 for i in range(512))).digest()
n2=hashlib.sha256(domain+bytes((29*i+11)%256 for i in range(512))).digest()
slot=(a.fixtures/'case-0.slot.bin').read_bytes();root=slot[72:104]
key=h.su.DemoAuthority(h.HOME_AUTHORITY)
requests={'a1':h.request_bytes(h.DEVICE_ID,n1,root),'a2':h.request_bytes(h.DEVICE_ID,n2,root),
          'wrong-model':h.request_bytes(h.DEVICE_ID,n1,bytes(32))}
for q,(name,request) in enumerate(requests.items()):
    for typ,data in [('request',request),('grant',request+key.sign_reserved_leaf(request,q))]:
        (out/f'{typ}-{name}.hex').write_text(''.join(f'{b:02x}\n' for b in data))
const='\n'.join(f"localparam logic [255:0] {name}=256'h{val.hex()};" for name,val in [('N1',n1),('N2',n2),('MODEL_A',root)])+'\n'
(build/'home_fixtures.svh').write_text(const)
cmd=['verilator','--binary','--timing','-DSYNTHESIS','-DSWIC_FAST_FLASH','-Wno-fatal','--top-module','tb_home_tang','-j','1',
     '--output-split','20000','--output-split-cfuncs','500','-CFLAGS','-O2','--Mdir','obj']+files
started=time.monotonic()
with (out/'build.log').open('w') as log:
    result=subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT)
record={'result':'PASS' if result.returncode==0 else 'FAIL','command':cmd,'build_directory':str(build),
        'binary':str(build/'obj/Vtb_home_tang'),'simulation_cwd':str(build/'project'),'elapsed_seconds':time.monotonic()-started,
        'source_sha256':{str(q.relative_to(ROOT)):hashlib.sha256(q.read_bytes()).hexdigest() for q in (ROOT/'integration').rglob('*') if q.is_file()},
        'fixtures':str(a.fixtures.resolve()),'home_fixtures':str(out),'scope':'Complete native arithmetic, UART and nonce conditioner sharing the boot-root SHA; fast flash/DDR models and deterministic raw-entropy fixtures.'}
record['source_sha256']['nonce/nonce_frontend.sv']=hashlib.sha256((ROOT/'nonce/nonce_frontend.sv').read_bytes()).hexdigest()
record['configuration']=clock_variant.config(a.core_divider)
record['configuration']['shared_message_selector']=a.share_message_selector
record['configuration']['registered_permit']=a.registered_permit
record['configuration']['shared_boot_compressor']=a.share_boot_compressor
record['configuration']['direct_publication_guard']=a.direct_publication_guard
record['configuration']['registered_nonce_data']=a.registered_nonce_data
record['configuration']['compact_norm_loader']=a.compact_norm_loader
record['configuration']['narrow_norm_carry']=a.narrow_norm_carry
record['configuration']['registered_metadata_collision']=a.registered_metadata_collision
record['configuration']['resetless_sha_data']=a.resetless_sha_data
record['configuration']['registered_verifier_reset']=a.registered_verifier_reset
record['configuration']['falling_edge_startup_reset']=a.falling_edge_startup_reset
record['configuration']['phase_qualified_startup_reset']=a.phase_qualified_startup_reset
record['configuration']['qualified_qspi_reset']=a.qualified_qspi_reset
record['configuration']['phase_qualified_qspi_reset']=a.phase_qualified_qspi_reset
record['configuration']['permit_reset_maxfan']=a.permit_reset_maxfan
record['configuration']['qspi_core_reset_buffers']=a.qspi_core_reset_buffers
record['compiled_snapshot_sha256']={str(q.relative_to(build)):hashlib.sha256(q.read_bytes()).hexdigest()
    for q in build.rglob('*') if q.is_file() and 'obj' not in q.relative_to(build).parts}
if result.returncode==0:
    record['simulator_sha256']=hashlib.sha256((build/'obj/Vtb_home_tang').read_bytes()).hexdigest()
(out/'BUILD.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({k:record[k] for k in ['result','binary','elapsed_seconds']},indent=2));raise SystemExit(result.returncode)

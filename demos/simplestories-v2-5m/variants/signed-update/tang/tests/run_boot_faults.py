#!/usr/bin/env python3
"""Directed complete-boot faults with real crypto/DDR and a byte-source abstraction.

Reuses the committed integration harness, altering only its fixture loading and
expected terminal condition. It never programs a board. The ordinary full SPI
campaign remains separate.
"""
from pathlib import Path
import concurrent.futures,hashlib,json,shutil,subprocess,sys,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su

out=ROOT/'evidence/boot-faults';out.mkdir(exist_ok=False)
fixtures=ROOT/'evidence/fixtures'
image=(fixtures/'case-0.image.bin').read_bytes()
slot=(fixtures/'case-0.slot.bin').read_bytes()
frame=slot[:115396]
payload_at=132+2*(4+su.SIG_BYTES)
metadata=frame[payload_at+32+32*su.PAGES:payload_at+su.PAYLOAD_BYTES]
authorities=[su.DemoAuthority(i) for i in (0,1)]
cases=[]
for case in range(5):
    data=bytearray(image);meta=bytearray(metadata);admission=bytearray(slot)
    if case==0:data[0]^=1
    if case==1:data[214261*32]^=1
    if case==2:meta[2]^=1
    if case==3:data[214260*32+1:214260*32+3]=b'\x00\x00'
    if case in (1,2,3):
        package=su.make_package(bytes(data),bytes(meta),10+case,authorities,[10+case]*2)
        admission=package[:-su.IMAGE_BYTES].ljust(262144,b'\xff')
    if case==4:admission[-1]=0
    for name,values in [('image',data),('slot',admission)]:
        (out/f'case-{case}.{name}.hex').write_text(''.join(f'{b:02x}\n' for b in values))
    cases.append({'case':case,'name':['unsigned-image-bit','signed-fixed-LUT-change','signed-metadata-mismatch','signed-zero-norm-scale','non-erased-slot-padding'][case],
                  'image_sha256':hashlib.sha256(data).hexdigest(),'slot_sha256':hashlib.sha256(admission).hexdigest()})

tb=(ROOT/'tests/tb_tang.sv').read_text()
start=tb.index('        path=$sformatf(');end=tb.index('        repeat(10)',start)
tb=tb[:start]+'''        path=$sformatf("%s/case-%0d.image.hex",fixture,case_id);$readmemh(path,image);
        path=$sformatf("%s/case-%0d.slot.hex",fixture,case_id);$readmemh(path,slot);
'''+tb[end:]
start=tb.index('        if(case_id==2) begin')
tb=tb[:start]+'''        if(dut.model_locked || !(dut.memory_fault || dut.source_fault))
            $fatal(1,"corrupt boot reached lock case=%0d",case_id);
        if(case_id==0 && !dut.u_memory.u_boot.image_fault) $fatal(1,"missing image mismatch");
        if(case_id==1 && !dut.u_memory.u_boot.local_fault_q) $fatal(1,"missing fixed-LUT mismatch");
        if(case_id==2 && !dut.u_memory.u_boot.local_fault_q) $fatal(1,"missing metadata mismatch");
        if(case_id==3 && !dut.u_memory.u_boot.norm_fault) $fatal(1,"missing norm rejection");
        if(case_id==4 && (!dut.swic_ingress_fault || dut.u_raw_controller.model_writes!=0))
            $fatal(1,"padding fault reached DDR writes");
        repeat(100) @(negedge dut.core_clk);
        if(dut.model_locked || dut.tx_valid) $fatal(1,"post-fault readiness");
        $display("PASS complete boot fault case=%0d cycles=%0d",case_id,ticks);$finish;
    end
endmodule
'''
# uart_core's externally visible tx must remain idle on these failed boots.
tb=tb.replace('dut.tx_valid','(tx!=1)')
(out/'tb_faults.sv').write_text(tb)
build=Path(tempfile.mkdtemp(prefix='swic-tang-faults-'))
project=ROOT/'hardware/project';shutil.copytree(project,build/'project')
files=[]
for line in (project/'production_sources.f').read_text().splitlines():
    line=line.strip()
    if not line or line.startswith('#') or line.startswith('official/') or line in ['defines.v','swic/swic_qspi_boot_source.sv'] or 'board1_gowin_ddr3_raw_controller_shell.sv' in line:continue
    if line.endswith(('.v','.sv')):files.append('project/'+line)
s=(project/'swic/swic_qspi_boot_source.sv').read_text();start=s.index('module ');end=s.index('\n);',start)+4
(build/'fast_flash.sv').write_text('`timescale 1ns/1ps\n'+s[start:end]+'\n'+(ROOT/'tests/fast_flash_body.sv').read_text())
shutil.copyfile(ROOT/'tests/phy_model.sv',build/'phy_model.sv')
shutil.copyfile(out/'tb_faults.sv',build/'tb_faults.sv')
cmd=['verilator','--binary','--timing','-DSYNTHESIS','-DSWIC_FAST_FLASH','-Wno-fatal','--top-module','tb_tang','-j','1','-CFLAGS','-O2','--Mdir','obj']+files+['fast_flash.sv','phy_model.sv','tb_faults.sv']
t=time.time()
with (out/'build.log').open('w') as log:subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT,check=True)
def run(case):
    n=case['case'];started=time.time()
    with (out/f'case-{n}.log').open('w') as log:
        code=subprocess.run([str(build/'obj/Vtb_tang'),f'+CASE={n}',f'+FIXTURES={out}'],cwd=build/'project',stdout=log,stderr=subprocess.STDOUT).returncode
    text=(out/f'case-{n}.log').read_text()
    return dict(case,result='PASS' if code==0 and f'PASS complete boot fault case={n}' in text and not any(x in text for x in ['%Fatal','%Error','Assertion failed']) else 'FAIL',
                exit_code=code,elapsed_seconds=time.time()-started,log_sha256=hashlib.sha256(text.encode()).hexdigest())
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(run,cases))
sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in project.rglob('*') if p.is_file()}
for p in [Path(__file__).resolve(),ROOT/'tests/tb_tang.sv',ROOT/'tests/fast_flash_body.sv',ROOT/'tests/phy_model.sv',out/'tb_faults.sv']:
    sources[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
record={'result':'PASS' if all(x['result']=='PASS' for x in results) else 'FAIL','cases':results,'elapsed_seconds':time.time()-t,
        'source_sha256':sources,'fast_flash_source_abstraction':True,'phy_abstraction':True,'command':cmd,'build_directory':str(build)}
(out/'result.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({'result':record['result'],'cases':results},indent=2))
raise SystemExit(0 if record['result']=='PASS' else 1)

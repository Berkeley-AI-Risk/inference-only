"""Check the selected implementation evidence without FPGA/vendor/SMT tools.

Verifies bounded decompression, every recorded byte identity, current native
sources/images, reversible instrumentation, elaborated scope and original
solver outcomes. Compiler/query reproduction is credited only to its recorded
source audit; this command neither reruns a compiler nor establishes a new
solver result. The full audit scripts remain available for that separate step.
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path,PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile

EXPECTED_INDEX_SHA256='36ee9b8de68369b0316d1b277500d50259a354341f0d743fb8ff4497083424ae'


def sha(raw):return hashlib.sha256(raw).hexdigest()
def need(condition,message):
    if not condition:raise ValueError(message)
def safe(root,name):
    p=PurePosixPath(name)
    need(not p.is_absolute()and'..'not in p.parts and'\\'not in name and p.parts,'Unsafe evidence path')
    target=root
    for part in p.parts:
        target=target/part;need(not target.is_symlink(),'Symlink evidence member')
    return target
def read(path):return json.loads(path.read_bytes())
def load(work,name):
    spec=importlib.util.spec_from_file_location('_recorded_assurance_'+name,work/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def materialize(model,evidence,work):
    raw=(evidence/'INDEX.json').read_bytes();need(sha(raw)==EXPECTED_INDEX_SHA256,'Implementation evidence index changed')
    index=json.loads(raw)
    need(index['schema']=='current-simplestories-implementation-assurance-evidence-v1','Unknown evidence schema')
    need(len(index['files'])<=3000 and len(index['runs'])==43,'Evidence inventory changed')
    need(sum(r['bytes']for r in index['files'].values())==index['raw_total_bytes']<=2_000_000_000,'Raw evidence budget changed')
    cache=work/'_objects';cache.mkdir();seen={}
    for logical,row in index['files'].items():
        digest=row['sha256'];need(re.fullmatch('[0-9a-f]{64}',digest),'Invalid object digest')
        need(row['object']=='objects/'+digest+'.gz','Noncanonical object path')
        need(0<=row['bytes']<=512_000_000 and row['compressed_bytes']<=100_000_000,'Evidence member exceeds size bound')
        if digest not in seen:
            obj=safe(evidence,row['object']);data=obj.read_bytes()
            need(len(data)==row['compressed_bytes']and sha(data)==row['compressed_sha256'],'Compressed evidence changed')
            target=cache/digest;length=0;h=hashlib.sha256()
            with gzip.GzipFile(fileobj=__import__('io').BytesIO(data),mode='rb')as z,target.open('xb')as f:
                while True:
                    chunk=z.read(min(1024*1024,row['bytes']-length+1))
                    if not chunk:break
                    length+=len(chunk);need(length<=row['bytes'],'Decompressed member exceeds declared size')
                    h.update(chunk);f.write(chunk)
            need(length==row['bytes']and h.hexdigest()==digest,'Raw evidence changed')
            seen[digest]=row
        else:need(seen[digest]==row,'Inconsistent duplicate object metadata')
        destination=safe(work,logical);destination.parent.mkdir(parents=True,exist_ok=True)
        os.link(cache/digest,destination)
    source=evidence.parent.parent/'formal/implementation-assurance'
    for name,row in index['source_tools'].items():
        raw=safe(source,name).read_bytes()
        need(len(raw)==row['bytes']and sha(raw)==row['sha256'],'Source/audit tool changed: '+name)
        safe(work,name).write_bytes(raw)
    return index


def recorded_rows(work,index):
    reports={
        'fifo':read(work/'audit-probes/transport-source-audit-r3-checked/fifo-premise-recheck/FINISHED.json'),
        'transport':read(work/'audit-probes/transport-source-audit-r3-checked/FINISHED.json'),
        'boot-order':read(work/'audit-probes/boot-order-source-audit-r1/FINISHED.json')}
    for kind,record in reports.items():
        need(record['passed'],'Incomplete recorded source audit: '+kind)
        need(record['checker_sha256']==index['source_tools']['audit_'+('boot_order'if kind=='boot-order'else kind)+'.py']['sha256'],
            'Recorded source audit/tool binding changed: '+kind)
    rows={r['run']:(kind,r)for kind,record in reports.items()for r in record['runs']}
    for item in index['runs']:
        run=work/'runs'/item['run'];inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes()
        inp,fin=json.loads(inp_raw),json.loads(fin_raw)
        need(sha(inp_raw)==item['inputs_sha256']==fin['inputs_sha256']and sha(fin_raw)==item['finished_sha256'],'Run receipt identity changed')
        need(inp['mutant']==item['mutant']and inp['assertion_cells']==item['assertions']and inp['assumption_cells']==item['assumptions'],
            'Recorded run scope changed')
        need(fin['passed']==item['original_aggregate_passed'],'A partial campaign was relabelled')
        for name,row in inp['files'].items():
            raw=safe(run,name).read_bytes();need(len(raw)==row['bytes']and sha(raw)==row['sha256'],'Frozen proof input changed')
        if item['kind']in reports:
            kind,record=rows[item['run']]
            need(kind==item['kind']and record['finished_sha256']==sha(fin_raw)and
                record.get('inputs_sha256',record.get('input_sha256'))==sha(inp_raw)and
                record['emitted_smt_sha256']==sha((run/'design.smt2').read_bytes()),'Recorded compiler/query audit no longer binds this run')
        for label,row in fin['results'].items():
            log=(run/(label+'.log')).read_bytes();need(sha(log)==row['log_sha256'],'Real solver log changed')
            if row.get('query_sha256'):need(sha((run/(label+'.smt2')).read_bytes())==row['query_sha256'],'Solver query changed')
            if row.get('solver_responses_sha256'):
                need(sha((run/(label+'.responses')).read_bytes())==row['solver_responses_sha256'],'Real solver responses changed')
            for name,digest in row.get('traces',row.get('witnesses',{})).items():need(sha((run/name).read_bytes())==digest,'Solver witness changed')
            if row.get('verification_mode'):
                need(item['run']=='qspi-baseline-r6'and label=='cvc5-cover','Unexpected concrete-witness result')
                # audit.py below checks the actual SAT answer, all 163 states,
                # every transition, the exact design and both coverage goals.
                continue
            if row['passed']:
                expected='FAILED'if item['mutant']else'PASSED'
                need(re.findall(rb'Status: (\w+)',log)==[expected.encode()]and row['exit']==(1 if item['mutant']else 0),'Recorded solver conclusion changed')
                if label.endswith('induction'):
                    need(not item['mutant']and b'Temporal induction successful.'in log and'--smtc'not in row['command'],
                        'Induction was incomplete or externally constrained')
            else:need(row.get('status')!=['PASSED'],'Unresolved solver result was relabelled as a pass')
    return reports


def recover_current_sources(work,package,index):
    common=load(work,'run_handoff');fifo=load(work,'run_fifo');transport=load(work,'run_transport');boot=load(work,'run_boot_order')
    bindings={v:common.binding(package,v)for v in ('baseline','kv-protected','encrypted-memory','seeded-sampling')}
    for item in index['runs']:
        if item['kind']not in ('fifo','transport','boot-order'):continue
        run=work/'runs'/item['run'];inp=read(run/'INPUTS.json');mutant=item['mutant']
        if item['kind']=='boot-order':
            original=None
            for variant,(_,root,bound)in bindings.items():
                raw=(root/boot.SOURCE).read_bytes();need(inp['binding']['native_joins'][variant]==bound,'Boot native join changed')
                if original is not None:need(raw==original,'Boot native sources differ')
                original=raw
            monitor=(work/'boot-order-monitor.inc.sv').read_text();source=original.decode()
            if mutant:
                before,after=boot.MUTATIONS[mutant];need(source.count(before)==1,'Boot mutation site changed');source=source.replace(before,after)
            need((run/'production-boot.sv').read_bytes()==original and(run/'monitor.inc.sv').read_text()==monitor,'Boot source/observer changed')
            expected='`undef FORMAL\n'+source.replace('\nendmodule','\n'+monitor+'\nendmodule')
            need((run/'boot.sv').read_text()==expected and inp['assumption_cells']==0 and not inp['internal_cuts'],'Boot instrumentation or constraints changed')
            continue
        variant=next(v for v,(_,_,b)in bindings.items()if b['image_sha256']==inp['binding']['image_sha256'])
        pin,root,bound=bindings[variant]
        need(all(inp['binding'].get(k)==v for k,v in bound.items()),'FIFO/transport native image association changed')
        original=(root/'project/fifo.sv').read_bytes();parent=(root/'project/thin_transport.sv').read_bytes()
        need((run/'production-fifo.sv').read_bytes()==original and(run/'production-transport.sv').read_bytes()==parent,'FIFO/transport native source changed')
        monitor=(work/'fifo-monitor.inc.sv').read_text();source=original.decode()
        if item['kind']=='fifo':
            channel=inp['binding']['channel'];width,bits,module,override=fifo.channel_binding(parent,channel)
            start=parent.decode().index('    wire common_reset_n = ');end=parent.decode().index('\n    logic core_fault_q,',start)
            need((run/'harness.sv').read_text()==fifo.harness(parent.decode()[start:end],width,bits,channel,module,override),'FIFO native clock/reset/parameter context changed')
            if mutant:
                mutations={
                    'flip-operation-bit':('memory_q[write_binary_q[ADDR_BITS-1:0]] <= s_data_i;',"memory_q[write_binary_q[ADDR_BITS-1:0]] <= s_data_i ^ (WIDTH'(1) << (WIDTH-1));"),
                    'wrong-prefetch-row':('m_data_q <= memory_q[m_binary_next_address];',"m_data_q <= memory_q[m_binary_next_address ^ {{(ADDR_BITS-1){1'b0}},1'b1}];")}
                before,after=mutations[mutant];need(source.count(before)==1,'FIFO mutation site changed');source=source.replace(before,after)
            policy=''
        else:
            module=fifo.channel_binding(parent,'commands')[2]
            ledger=read(run/'discharged-fifo-lemma-audit.json')
            origins=transport.verify_fifo_lemma_inputs(ledger,variant,original,parent,monitor,common)
            need(origins==inp['binding']['discharged_fifo_lemma_origins'],'FIFO premise discharge changed')
            monitor='\n'.join(s for s in monitor.splitlines()if not s.strip().startswith('cover('))+'\n';monitor=monitor.replace('assert(','assume(')
            policy=transport.render_policy_monitor(pin['kv_limit'])
            parent_monitor=transport.render_parent_monitor(pin['kv_limit'],field_identity=True);native_parent=parent.decode()
            if mutant:
                before,after=transport.MUTATIONS[mutant];need(native_parent.count(before)==1,'Transport mutation site changed');native_parent=native_parent.replace(before,after)
            expected='`undef FORMAL\n'+native_parent.replace('\nendmodule','\n'+parent_monitor+'\nendmodule')
            need((run/'transport.sv').read_text()==expected and(run/'parent-monitor.inc.sv').read_text()==parent_monitor and
                (run/'policy-monitor.inc.sv').read_text()==policy and inp['assumption_cells']==52,'Transport obligations/production logic changed')
        start=source.index('module '+module+' #(');end=source.index('\nendmodule',start)
        need((run/'fifo.sv').read_text()=='`undef FORMAL\n'+source[:end]+'\n'+monitor+policy+source[end:],'FIFO instrumentation changed native logic')
        need(not inp['internal_cuts']and not inp['changed_production_parameters']and inp['multiclock'],'FIFO/transport abstraction scope changed')
    return bindings


def check(package,evidence,work):
    model=package/'demos/simplestories-v2-5m'if(package/'demos/simplestories-v2-5m/MANIFEST.json').is_file()else package
    index=materialize(model,evidence,work)
    return check_materialized(package,index,work)


def check_materialized(package,index,work):
    reports=recorded_rows(work,index)
    bindings=recover_current_sources(work,package,index)
    # These two source audits are already entirely recorded-only. They recover
    # the actual parent/controller instrumentation and inspect raw outcomes.
    for name,destination in [('audit','fixed-audit.json'),('audit_control','control-audit.json')]:
        command=[sys.executable,'-I','-S','-B',str(work/(name+'.py')),'--package',str(package),'--out',str(work/destination)]
        with(work/(name+'-recorded.log')).open('w')as log:cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=90)
        need(cp.returncode==0,'Recorded source audit failed: '+name+'; see '+str(work/(name+'-recorded.log')))
    connections=load(work,'check_top_connections')
    for variant,(_,root,_)in bindings.items():
        directory=work/'runs/top-connections-r1'/variant
        need((directory/'top.sv').read_bytes()==(root/'project/top.sv').read_bytes(),'Native top-level source changed')
        top=read(directory/'top.json')['modules']['board1_fixed_shared_product_top']
        need(len(connections.connections(top))==63,'Top-level enforcement wiring changed')
    for channel in ('commands','returns'):
        directory=work/('audit-probes/fifo-encrypted-'+channel+'-cover-r2');record=read(directory/'FINISHED.json');row=record['results']['cvc5']
        log=(directory/'cvc5.log').read_bytes();need(row['passed']and row['exit']==0 and sha(log)==row['log_sha256']and
            len(re.findall(rb'Reached cover statement',log))==4,'Separate encrypted full-capacity coverage changed')
    for name in ('fifo-audit-sensitivity-r3-current','transport-audit-sensitivity-r1'):
        record=read(work/('audit-probes/'+name+'/FINISHED.json'))
        need(record['passed']and len(record['controls'])==5 and all(r['rejected']for r in record['controls']),'Auditor sensitivity controls changed')
    result=dict(recorded_evidence_checks_passed=True,selected_runs=len(index['runs']),
        native_designs=len(bindings),current_source_instrumentation_recovered=True,
        full_compiler_and_query_reproduction_report_bindings_checked=True,
        compiler_or_solver_executed=False,hardware_access=False,whole_machine_theorem=False,
        boot_runtime_transport_temporal_join_proved=False,source_to_bitstream_equivalence=False,
        raw_evidence_bytes=index['raw_total_bytes'],secondary_timeouts_retained=True)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--evidence',type=Path)
    parser.add_argument('--work',type=Path,help='Keep extracted evidence and diagnostic files in this new directory')
    args=parser.parse_args();package=args.package.resolve(strict=True)
    model=package/'demos/simplestories-v2-5m'if(package/'demos/simplestories-v2-5m/MANIFEST.json').is_file()else package
    evidence=(args.evidence or(model/'evidence/implementation-assurance')).resolve(strict=True)
    if args.work:
        work=args.work.resolve();work.mkdir(parents=True,exist_ok=False);result=check(package,evidence,work)
    else:
        with tempfile.TemporaryDirectory(prefix='current-rtl-evidence-')as tmp:result=check(package,evidence,Path(tmp))
    print(json.dumps(result,sort_keys=True))


if __name__=='__main__':main()

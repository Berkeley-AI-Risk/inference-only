"""Relocated offline oracle, logs, terminal and source review; never runs tools."""
import argparse,importlib.util,json
from pathlib import Path
from common import ROOT,identity,need,save,verify
def oracle():
    spec=importlib.util.spec_from_file_location('frozen_component_oracle',ROOT/'oracle.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
def expected(mod):
    tag='d2e8e6bc0a5f3e019d133b6da82a89cd2379745f8908eff0c07f12bb559badf8'
    rows={str(l):mod.roots(tag,l,l*3) for l in range(36)};fixture=json.loads((ROOT/'EXPECTED.json').read_text());need(rows==fixture['model8'] and len({r['root'] for r in rows.values()})==36,'Independent SHA fixture generation')
    return fixture
def review_logs(logs):
    mod=oracle();ex=expected(mod);answers={}
    for case,lines in logs.items():
        if case in ('plain','protected'):
            protected=case=='protected';answers[case]=mod.review8(lines,protected,ex)
            summaries=[json.loads(x) for x in lines if x.startswith('{') and json.loads(x)['event']=='result']
            for i,row in enumerate(summaries):
                reads=(10368,144,288)[i] if protected else (9216,256,256)[i]
                need(row['axi_write_words']==(74304 if protected else 4608) and row['axi_read_words']==reads,'Actual traffic counters differ')
        else:
            need(lines[-1:] == ['PASS protected_transport_boundaries'],'Original boundary PASS')
            rows=[json.loads(x) for x in lines if x.startswith('{')];last=[r for r in rows if r['event']=='last_digest'];reject=[r for r in rows if r['event']=='typed_reject']
            need(len(last)==1 and last[0]['last_logical_beat']==ex['last_digest_beat'] and last[0]['last_byte']==ex['final_digest_byte'] and last[0]['axi_write_words']==last[0]['axi_read_words']==16,'Last digest actually written/read')
            need(len(reject)==9 and len({r['case'] for r in reject})==9 and any(r['case']=='first_out_of_range' and r['address']==ex['first_out_of_range'] for r in reject),'All nine typed refusals')
            answers[case]=dict(passed=True,last_digest_beat=True,typed_refusals=9)
    need(set(answers)=={'plain','protected','bounds'},'All three independent cases required');return answers
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--plain',type=Path,required=True);p.add_argument('--protected',type=Path,required=True);p.add_argument('--bounds',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();verify();logs={};pins={}
    for case in ('plain','protected','bounds'):
        path=getattr(a,case).resolve();f=json.loads((path/'FINISHED.json').read_text());start=json.loads((path/'STARTED.json').read_text())
        need(f['case']==start['case']==case and f['manifest']==start['manifest']==identity(ROOT/'MANIFEST.json') and f['binary']==identity(path/'build/component-test') and start['runner']==identity(ROOT/'run.py'),'Actual relocated producer')
        argv=f['compile']['command'];need(argv==start['compiler_command'] and argv[argv.index('-j')+1]==argv[argv.index('--threads')+1]=='1' and '--assert' in argv,'Actual bounded compiler invocation')
        produced=Path(start['output'])/'build/component-test';need(f['native']['command']==[str(produced)] and f['native']['cwd']==start['output'] and argv[argv.index('-Mdir')+1]==str(produced.parent),'Actual binary producer, not an echoed PASS')
        for phase in ('compile','native'):
            receipt=json.loads((path/phase/'EXIT.json').read_text());need(f[phase]==receipt and receipt['actual_child_exit']==0 and receipt['stop_reason'] is None,'Actual clean child0')
            for stream in ('stdout','stderr'):need(receipt[stream]==identity(path/phase/(stream+'.log')),'Original raw log identity')
        need(not (path/'native/stderr.log').read_bytes(),'Actual native stderr empty');logs[case]=(path/'native/stdout.log').read_text().splitlines();pins[case]=dict(terminal=identity(path/'FINISHED.json'),stdout=identity(path/'native/stdout.log'),native_seconds=f['native']['elapsed_seconds'],compile_seconds=f['compile']['elapsed_seconds'],system=start['system'])
    result=review_logs(logs);save(a.output,dict(passed=True,scope='Single position deterministic component across36layers, not full-model/physical qualification',manifest=identity(ROOT/'MANIFEST.json'),checker=identity(Path(__file__)),cases=result,actual=pins,protected_first_position_write_bytes=2377728,plain_first_position_write_bytes=147456,first_position_write_amplification=16.125,whole_model_overhead_or_speed_claimed=False));print('PASS independent relocated component review')
if __name__=='__main__':main()

"""Read-only replay of supplied recorded logs, not a fresh native execution."""
import json
from pathlib import Path
from common import ROOT,identity,need,verify
from check import review_logs
def main():
    verify();evidence=ROOT/'evidence';record=json.loads((evidence/'RECORDED.json').read_text())
    need(record['source_manifest']==identity(ROOT/'MANIFEST.json'),'Recorded source binding')
    for name,pin in record['files'].items():need(identity(evidence/name)==pin,'Changed recorded evidence '+name)
    logs={case:(evidence/case/'native/stdout.log').read_text().splitlines() for case in ('plain','protected','bounds')}
    result=review_logs(logs);review=json.loads((evidence/'RELOCATED-VERIFIED.json').read_text());need(review['passed'] and review['manifest']==identity(ROOT/'MANIFEST.json') and review['cases']==result,'Recorded reviewed outcome')
    for case in logs:
        f=json.loads((evidence/case/'FINISHED.json').read_text());start=json.loads((evidence/case/'STARTED.json').read_text());need(f['case']==start['case']==case and start['system']=='Linux' and f['manifest']==record['source_manifest'],'Original Linux source/case binding')
        for phase in ('compile','native'):
            e=json.loads((evidence/case/phase/'EXIT.json').read_text());need(e==f[phase] and e['actual_child_exit']==0 and e['stop_reason'] is None,'Original recorded clean terminal')
            for stream in ('stdout','stderr'):need(e[stream]==identity(evidence/case/phase/(stream+'.log')),'Original recorded stream')
    print('PASS recorded source/log/oracle integrity; no compiler, simulator or hardware invoked')
if __name__=='__main__':main()

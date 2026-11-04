"""Recompile and independently replay the frozen RMSNorm pilot verification.

This entry has fresh per-run resource bounds and no dependency on chat usage,
campaign phase or its old deadline. It never changes RTL, candidates or claims.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

import check
from prepare import HERE, ROM, TOP, sha, verify_inventory, write_json
from checkpoint import snapshot
from validate_witnesses import validate as validate_operating


def checked_hash(path, expected):
    if sha(path.read_bytes())!=expected:raise ValueError('Identity mismatch: '+str(path))


def validate_inputs():
    verify_inventory()
    qualified=json.loads((HERE/'QUALIFICATION.json').read_text())
    if qualified.get('passed') is not True:raise ValueError('No qualified pilot')
    for name,key in [('SOURCES.json','source_manifest_sha256'),('product.smt2','product_sha256'),
                     ('history.smt2','history_sha256'),('CHECKS.json','checks_sha256'),
                     ('PROOF-PLAN.json','proof_plan_sha256'),('THEOREM.md','theorem_sha256')]:
        checked_hash(HERE/name,qualified[key])
    plan=json.loads((HERE/'PROOF-PLAN.json').read_text())
    checked_hash(HERE/'project/native.smt2',plan['native_sha256'])
    checks=json.loads((HERE/'CHECKS.json').read_text())
    if not checks['checked_pilot']:raise ValueError('Incomplete recorded verification')
    nodes=plan['nodes'];order=plan['topological_order'];seen=set()
    width=int(re.search(r'^; yosys-smt2-wire state_q (\d+)$',(HERE/'project/native.smt2').read_text(),re.M)[1])
    if width!=plan['native_parent_state_width'] or plan['group_mode']!='root-state cases':
        raise ValueError('Unsupported or incomplete source case coverage')
    check.RULES.clear();check.RULES.update(nodes)
    body=check.inputs()
    jobs=[]
    for rule in order:
        node=nodes[rule]
        if not set(node['dependencies'])<=seen:raise ValueError('Forward/circular proof dependency')
        if 'source_context' in node:
            if not set(node['passthrough'])<=set(node['source_context']):raise ValueError('Context not supplied')
            facts=list(node['passthrough'])
            for dep in node['context_facts']:
                if dep not in node['dependencies'] or nodes[dep].get('expected','unsat')!='unsat':raise ValueError('Unproved contextual fact')
                context=nodes[dep].get('source_context',nodes[dep]['assumptions'])
                rest=[a for a in context if a not in node['source_context']]
                facts.append('(=> '+check.conj(rest)+' '+nodes[dep]['conclusion']+')')
            if facts!=node['assumptions']:raise ValueError('Contextual consequence changed')
        group=plan['groups'].get(rule)
        record=checks['local_rules'][rule]
        if group:
            expected=[rule+'-root-'+str(v).zfill(2) for v in range(1<<width)]
            if group!=expected or set(record['clauses'])!=set(expected) or record['expected_clause_count']!=len(expected):
                raise ValueError('Incomplete native-state case coverage')
            selected=[(name,record['clauses'][name]) for name in expected]
            for value,(name,leaf) in enumerate(selected):
                spec=nodes[name]
                case=node['assumptions']+['(not (|'+TOP+'_n clear_i| a))','(not (failed a))',
                    '(= (|'+TOP+'_n state_q| a) (_ bv'+str(value)+' 5))']
                if spec['assumptions']!=case or spec['conclusion']!=node['conclusion']:
                    raise ValueError('Case is not a specialization of the claimed theorem')
        else:selected=[(rule,record)]
        if not record['passed']:raise ValueError('Recorded failed obligation')
        for name,leaf in selected:
            spec=nodes[name]
            for dep in spec.get('imports',[]):
                if dep not in spec['dependencies'] or nodes[dep].get('expected','unsat')!='unsat':raise ValueError('Invalid theorem import')
            if check.import_formulas(name)!=spec['import_formulas']:raise ValueError('Import specialization changed')
            query=(HERE/leaf['command'][-1]).resolve()
            if not query.is_relative_to((HERE/'queries').resolve()):raise ValueError('Query outside frozen proof')
            checked_hash(query,leaf['query_sha256']);checked_hash(query.parent/'z3.log',leaf['log_sha256'])
            expected=check.query_text(name,body).encode()
            if query.read_bytes()!=expected:raise ValueError('Engine query differs from declarative plan')
            expected_answer=spec.get('expected','unsat')
            if not leaf['passed'] or leaf['answers']!=[expected_answer]:raise ValueError('Bad recorded engine answer')
            jobs.append((name,query,expected_answer))
        seen.add(rule)
    if len(jobs)!=qualified['engine_queries']:raise ValueError('Qualification query count changed')
    operating=validate_operating()
    checked_hash(HERE/'OPERATING-EVIDENCE.json',qualified['operating_evidence_sha256'])
    return qualified,plan,jobs,operating


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--validate-only',action='store_true')
    ap.add_argument('--workers',type=int,default=8)
    args=ap.parse_args()
    if not 1<=args.workers<=8:raise ValueError('At most eight 4-GiB solver jobs')
    qualified,plan,jobs,operating=validate_inputs()
    if args.validate_only:
        print('Source, proof plan, contexts, complete case coverage and',len(jobs),'exact engine queries validated; finite transcripts validated.')
        return 0
    run=HERE/'verification-runs'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    build=run/'compile';build.mkdir(parents=True)
    for filename in ['native.sv','compile.ys']:
        shutil.copyfile(HERE/'project'/filename,build/filename)
    rom=build/ROM;rom.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(HERE/'project'/ROM,rom)
    started=time.monotonic()
    with (build/'yosys.log').open('w') as log:
        cp=subprocess.run(['yosys','-Q','compile.ys'],cwd=build,stdout=log,stderr=subprocess.STDOUT,timeout=120)
    if cp.returncode:raise ValueError('Fresh source compilation failed: '+str(build/'yosys.log'))
    checked_hash(build/'native.smt2',plan['native_sha256'])
    print('Fresh Yosys compilation matches the qualified native transition system.',flush=True)
    results={}
    def replay(job):
        name,query,answer=job
        if time.monotonic()-started+130>8*3600:raise ValueError('Fresh verification wall-time cap')
        folder=run/name;folder.mkdir()
        before=time.monotonic()
        with (folder/'z3.log').open('w') as log:
            proc=subprocess.run(['z3','-memory:4096','-T:120',str(query)],stdout=log,stderr=subprocess.STDOUT,timeout=130)
        raw=(folder/'z3.log').read_text()
        answers=re.findall(r'^(sat|unsat|unknown|timeout)$',raw,re.M)
        receipt=dict(rule=name,answers=answers,expected_answer=answer,exit_code=proc.returncode,
            passed=proc.returncode==0 and answers==[answer],seconds=time.monotonic()-before,
            query_sha256=sha(query.read_bytes()),log_sha256=sha(raw.encode()))
        write_json(folder/'RESULT.json',receipt)
        return name,receipt
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for future in as_completed([pool.submit(replay,job) for job in jobs]):
            name,receipt=future.result();results[name]=receipt
            if len(results)%16==0 or not receipt['passed']:print('replayed',len(results),'/',len(jobs),name,receipt['passed'],flush=True)
    elapsed=time.monotonic()-started
    solver=sum(r['seconds'] for r in results.values())
    # The frozen query count and 120-second per-job cap also bound the worst
    # accumulated solver time, independently of the old campaign ledger.
    if len(jobs)*130>32*3600:raise ValueError('Frozen verification could exceed solver budget')
    result=dict(schema='RMSNorm-fresh-verification-v1',passed=all(r['passed'] for r in results.values()),
        fresh_source_recompiled=True,source_model_sha256=plan['native_sha256'],
        qualification_sha256=sha((HERE/'QUALIFICATION.json').read_bytes()),
        engine_queries=len(results),solver_seconds=solver,elapsed_seconds=elapsed,
        expected_unsat=qualified['expected_unsat'],expected_sat=qualified['expected_sat'],
        operating_evidence_validated=operating['passed'],results=results,whole_machine_theorem=False)
    write_json(run/'RESULT.json',result)
    write_json(HERE/'LATEST-VERIFICATION.json',dict(result=str((run/'RESULT.json').relative_to(HERE)),
        sha256=sha((run/'RESULT.json').read_bytes()),passed=result['passed']))
    snapshot('Fresh source compilation and all frozen SMT queries replayed')
    print(json.dumps({k:v for k,v in result.items() if k!='results'},indent=2))
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())

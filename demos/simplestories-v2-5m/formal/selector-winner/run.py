"""Fresh native selector winner theorem and wrong-tie diagnostic from public RTL."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,re,shutil
HERE=Path(__file__).resolve().parent
if not __debug__:raise SystemExit("Assertions are required; do not use -O")
def sha(raw):return hashlib.sha256(raw).hexdigest()
def save(p,d):p.write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
def audit_wrong_tie(folder):
    signals={}
    for signal in json.loads((folder/'counterexample.json').read_text())['signal']:
        data=iter(signal.get('data',[]));values=[];value=None
        for mark in signal['wave']:
            if mark in '23456789=':
                raw=next(data,None);value=int(raw,2) if raw and set(raw)<=set('01') else None
            elif mark in '01':value=int(mark)
            elif mark in 'xz':value=None
            else:assert mark=='.'
            values.append(value)
        signals[signal['name']]=values
    assert signals['reset_n'][1]==0
    assert signals['start_valid_i'][2]==signals['start_ready_o'][2]==1
    assert signals['row_valid_i'][3]==signals['row_ready_o'][3]==1 and signals['row_index_i'][3]==0
    assert signals['row_valid_i'][5]==signals['row_ready_o'][5]==1 and signals['row_index_i'][5]==1
    assert signals['obs_consumed_q'][7]==2 and signals['best_token_q'][7]==1 and signals['join_id_q'][7]==0
    assert signals['join_score_q'][7]==20 and all(x==0 for x in signals['fail_closed_o'][1:9])
    return {'reset_started':True,'two_rows_actually_admitted':True,'wrong_native_ID':1,'correct_strict_fold_ID':0,'common_normalized_score':20}
def audit_native(native,selector):
    counts={}
    for c in native['cells'].values():counts[c['type']]=counts.get(c['type'],0)+1
    assert counts.get('$assert',0)==58 and counts.get('$assume',0)==0
    assert counts.get('$anyconst',0)==1 and counts.get('$anyseq',0)==0
    choice=next(c for c in native['cells'].values() if c['type']=='$anyconst')
    assert int(choice['parameters']['WIDTH'],2)==12
    bits=set(choice['connections']['Y']);assert len(bits)==12 and bits==set(native['netnames']['join_watch_id']['bits'])
    edges={}
    for cell in native['cells'].values():
        incoming={b for port,values in cell['connections'].items() if cell['port_directions'][port]=='input' for b in values if isinstance(b,int)}
        for port,values in cell['connections'].items():
            if cell['port_directions'][port]=='output':
                for b in values:
                    if isinstance(b,int):edges.setdefault(b,set()).update(incoming)
    outputs={name:row for name,row in native['ports'].items() if row['direction']=='output'}
    assert set(outputs)=={'start_ready_o','row_ready_o','winner_valid_o','winner_token_id_o',
        'winner_scaled_raw_o','winner_source_exponent_o','busy_o','fail_closed_o'}
    stack=[b for row in outputs.values() for b in row['bits'] if isinstance(b,int)];visited=set(stack)
    while stack:
        for b in edges.get(stack.pop(),set())-visited:visited.add(b);stack.append(b)
    assert not bits&visited
    initialized={b for row in native['netnames'].values() if 'init' in row.get('attributes',{}) for b in row['bits'] if isinstance(b,int)}
    boundary=selector[:selector.index('endmodule\n\n`default_nettype wire\n')].count('\n')+1
    source_bits=set()
    for cell in native['cells'].values():
        match=re.search(r'selector\.sv:(\d+)',cell.get('attributes',{}).get('src',''))
        if cell['type']=='$dff' and match and int(match[1])<boundary:source_bits.update(cell['connections']['Q'])
    assert len(source_bits)==166 and not source_bits&initialized
    return {'assertion_cells':58,'assumption_cells':0,'arbitrary_choice_bits':12,
        'choice_cannot_drive_original_outputs':True,'original_source_storage_bits':166,'initialized_source_storage_bits':0}
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repository-root',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--tool-receipt',type=Path)
    a=p.parse_args();root=a.repository_root.resolve();out=a.output.resolve()
    assert not out.exists() and root not in out.parents and HERE not in out.parents
    plan=json.loads((HERE/'PLAN.json').read_text())
    for name,row in plan['bundle_inputs'].items():
        raw=(HERE/name).read_bytes();assert len(raw)==row['bytes'] and sha(raw)==row['sha256'],name
    source=json.loads((HERE/'SOURCE.json').read_text());inputs={}
    for name,row in source['repository_inputs'].items():
        q=root/name;raw=q.read_bytes();assert q.is_file() and not q.is_symlink() and len(raw)==row['bytes'] and sha(raw)==row['sha256'],name
        inputs[name]=raw
    spec=importlib.util.spec_from_file_location('public_resource_guard',root/source['process_guard_path'])
    guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
    tools=guard.select_tools(a.tool_receipt.resolve() if a.tool_receipt else None)
    out.mkdir();save(out/'SOURCE.json',source);save(out/'TOOLS.json',tools)
    selector=inputs[source['selector_path']].decode();comparator=inputs[source['comparator_path']].decode()
    monitor='\n'.join((HERE/name).read_text() for name in plan['observers'])
    end='endmodule\n\n`default_nettype wire\n';assert selector.count(end)==1
    joined=selector.replace(end,monitor+'\n'+end);assert joined.replace(monitor+'\n','',1)==selector
    records={}
    for role in ['theorem','wrong-tie']:
        folder=out/'models'/role;folder.mkdir(parents=True)
        compare=comparator
        if role=='wrong-tie':
            before='assign greater_o = greater_node[0];';after='assign greater_o = greater_node[0] || equal_node[0];'
            assert compare.count(before)==1;compare=compare.replace(before,after,1)
        (folder/'selector.sv').write_text(joined);(folder/'compare.sv').write_text(compare)
        shutil.copyfile(HERE/(role+'.ys'),folder/'query.ys')
        if role=='theorem':
            script=(folder/'query.ys').read_text()
            assert '-set-def join_watch_id' in script and not re.search(r'-set\s+join_watch_id\s',script)
            assert '-set-at ' not in script
        receipt=guard.execute(out,role,[tools['yosys']['path'],'-Q','query.ys'],folder,90)
        log=(out/'fresh'/role/'tool.log').read_text();assert plan['expected_markers'][role] in log
        native=json.loads((folder/'native.json').read_text())['modules']['board1_fixed_head_argmax']
        structure=audit_native(native,selector);save(folder/'STRUCTURE.json',structure)
        assert (folder/'counterexample.json').is_file() if role=='wrong-tie' else 'Induction step proven: SUCCESS!' in log
        defect=audit_wrong_tie(folder) if role=='wrong-tie' else None
        if defect:save(folder/'DEFECT.json',defect)
        records[role]={'expected_result_observed':True,'receipt':receipt,'assertions':58,'assumption_cells':0,'arbitrary_defined_constant_row_ID_bits':12,
            'selector_sha256':sha(joined.encode()),'comparator_sha256':sha(compare.encode()),'native_json_sha256':sha((folder/'native.json').read_bytes()),
            'query_sha256':sha((folder/'query.ys').read_bytes()),'structural_audit':structure,'defect_trace':defect}
    save(out/'RESULT.json',{'passed':True,'native_winner_theorem':'Least-ID maximum of4019 actual legally admitted rows in a healthy accepted selector invocation',
        'original':'UNBOUNDED_INDUCTION','wrong_tie':'SAT_REACHABLE_COUNTEREXAMPLE','records':records,
        'parent_STEP_or_model_logit_provenance':False,'physical_timing_or_device_job':False})
    print(json.dumps({'passed':True,'theorem':'UNBOUNDED','wrong_tie':'SAT','parent_STEP_theorem':False}),flush=True)
if __name__=='__main__':main()

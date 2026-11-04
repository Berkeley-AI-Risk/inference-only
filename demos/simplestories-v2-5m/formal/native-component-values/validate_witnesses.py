"""Check source identity and the complete finite operating/defect transcripts."""
import json
import re

from prepare import HERE, TOP, ROM, modules, sha, verify_inventory, write_json
from witness import testbench


def validate():
    verify_inventory()
    native=(HERE/'project/native.sv').read_text()
    rom_sha=sha((HERE/'project'/ROM).read_bytes())
    records={}
    reference12=None
    for kind,role in [('native',r) for r in range(13)]+[('stale-state',12),('wrong-operand',12)]:
        folder=HERE/'witnesses'/(kind+'-role'+str(role))
        result=json.loads((folder/'RESULT.json').read_text())
        source=(folder/'native-and-actual.sv').read_text()
        expected=native
        actual=TOP
        if kind!='native':
            actual='pilot_actual_mutant'
            change=result['mutation']
            assert change['reference_changed'] is False
            body=modules(native)[TOP]
            assert body.count(change['before'])==1
            body=body.replace(change['before'],change['after']).replace('module '+TOP,'module '+actual,1)
            expected+='\n'+body+'\n'
        assert source==expected and sha(source.encode())==result['source_sha256']
        assert (folder/'testbench.sv').read_text()==testbench(actual)
        assert sha((folder/'testbench.sv').read_bytes())==result['testbench_sha256']
        assert sha((folder/ROM).read_bytes())==result['rom_sha256']==rom_sha
        log=(folder/'simulation.log').read_text()
        assert sha(log.encode())==result['simulation_log_sha256']
        values=(folder/'values.csv').read_bytes()
        assert sha(values)==result['values_sha256']
        rows={'reference':[],'actual':[]}
        for line in values.decode().splitlines():
            name,index,word=line.split(',')
            rows[name].append((int(index),int(word,16)))
        reference=rows['reference']
        assert len(reference)==256 and [i for i,_ in reference]==list(range(256))
        assert all((word>>25)==i and (word&1)==(i==255) for i,word in reference)
        assert any((word>>9)&65535 for _,word in reference)
        if kind=='native':
            assert result['simulation_exit']==0 and result['operating_witness'] is True
            assert re.search(r'WITNESS_PASS role='+str(role)+r' rows=256 cycles=\d+',log)
            assert rows['actual']==reference
            if role==12:reference12=reference
        else:
            assert result['simulation_exit']!=0 and result['defect_detected'] is True
            mismatch=re.search(r'RESULT_MISMATCH row=(\d+) actual=([0-9a-fA-F]+) expected=([0-9a-fA-F]+)',log)
            assert mismatch and int(mismatch[2],16)!=int(mismatch[3],16)
            assert reference==reference12
        assert result['actual_hard_resets']==1 and result['actual_clear_after_owned_old_work']
        records[folder.name]=dict(result_sha256=sha((folder/'RESULT.json').read_bytes()),
            case=kind,role=role,verified=True,unbounded_proof=False)
    return dict(schema='RMSNorm-operating-evidence-v1',passed=True,
        native_roles=13,compared_native_results=13*256,
        actual_only_defects_detected=['stale-state','wrong-operand'],
        records=records,unbounded_proof=False,pilot_complete=False)


if __name__=='__main__':
    result=validate();write_json(HERE/'OPERATING-EVIDENCE.json',result)
    print(json.dumps({k:v for k,v in result.items() if k!='records'},indent=2))

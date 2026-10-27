"""Port the source-exact protected history observers to encrypted RAM timing.

Only formal tooling/observers change. The production encrypted guard and hash
wrapper are read from the qualified package and remain byte-identical. Capture
addresses use the current chunk; the pipelined physical read issues the next
chunk during HCAP/OCAP. Both addresses are observed explicitly.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def replace_once(text,before,after):
    if text.count(before)!=1:raise ValueError('Pinned formal adaptation site changed: '+before[:80])
    return text.replace(before,after,1)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    helper=HERE.parent/'formal-assurance/run_handoff.py'
    spec=importlib.util.spec_from_file_location('_encrypted_history_binding',helper);common=importlib.util.module_from_spec(spec);spec.loader.exec_module(common)
    package=common.model_package(args.package);_,directory,bound=common.binding(args.package,'encrypted-memory')
    source=package/'formal/kv-integrity';manifest=json.loads((package/'MANIFEST.json').read_bytes())['files']
    native_guard=(directory/'project/kv_integrity_guard.sv').read_bytes();native_hash=(directory/'project/kv_page_hash.sv').read_bytes()
    names=['run_control.py','compress_boundary.sv','hash_boundary.sv']
    names+=sorted(f.name for f in source.glob('*monitor.inc.sv'))
    names+=['audit_history.py','audit_control.py','audit_hash.py','audit_contract.py']
    records={}
    for name in names:
        raw=(source/name).read_bytes();row=manifest['formal/kv-integrity/'+name]
        if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Published proof helper differs from its manifest')
        text=raw.decode()
        if name.endswith('.py'):
            text=text.replace('board1_kv_integrity_guard','tang_kv_integrity_guard_epoch')
            text=text.replace('variants/kv-protected/hardware/project/','variants/encrypted-memory/hardware/project/')
            text=text.replace('4a90d4233f628c3ca69e42266c0a9064c5ffd766b45e2e403389696a0a2d2299',sha(native_guard))
            text=text.replace('3ee9a8a716916dcaba6d3434f722b301b3e4fb6b258ee429a457bb246191faba',sha(native_hash))
            text=text.replace('board1_sha256_compact_compress','board1_sha256_owner_held_kv_compress')
        if name=='compress_boundary.sv':
            text=replace_once(text,'module board1_sha256_compact_compress (','module board1_sha256_owner_held_kv_compress (')
        if name=='staging_monitor.inc.sv':
            text=replace_once(text,
                '    wire f_stage_read = live && ((state_q == HREAD && !hash_write_q) || state_q == OREAD);',
                '    wire [9:0] f_stage_capture_address = {stage_slot,chunk_q};\n'
                '    wire f_stage_read = live && (((state_q == HREAD || (state_q == HCAP && chunk_q != 7)) && !hash_write_q) ||\n'
                '        state_q == OREAD || (state_q == OCAP && chunk_q != 7));')
            text=replace_once(text,'f_stage_read_target == (stage_address == f_stage_address)',
                'f_stage_read_target == (f_stage_capture_address == f_stage_address)')
        if name=='partial_history_monitor.inc.sv':
            text=replace_once(text,'    wire f_partial_read = live && state_q == HREAD && hash_write_q;',
                "    wire [13:0] f_partial_capture_address = layer_base(layer_q) + {2'd0,partial_slot,chunk_q};\n"
                '    wire f_partial_read = live && (state_q == HREAD || (state_q == HCAP && chunk_q != 7)) && hash_write_q;')
            text=replace_once(text,'(f_partial_hash_match && chunk_q == f_partial_chunk)',
                '(f_partial_hash_match && memory_chunk == f_partial_chunk)')
            text=replace_once(text,'f_partial_read_target == (partial_address == f_partial_address)',
                'f_partial_read_target == (f_partial_capture_address == f_partial_address)')
        raw_out=text.encode();(out/name).write_bytes(raw_out)
        records[name]=dict(original_sha256=sha(raw),adapted_sha256=sha(raw_out),changed=raw!=raw_out)
    receipt=dict(schema='encrypted-native-KV-history-observer-port-v1',passed=True,
        source_package=str(package),native_join=bound,production_guard_sha256=sha(native_guard),
        production_hash_sha256=sha(native_hash),production_hardware_modified=False,
        adaptations='Native module/source identities and held-SHA interface name; actual pipelined read enables, physical memory_chunk read address and current-chunk capture address.',
        files=records,scope='Formal source preparation only. No solver theorem or guard-to-machine composition is established by preparing these observers.')
    (out/'PORT-SOURCES.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (out/'preparer.py').write_bytes(Path(__file__).read_bytes())
    print(json.dumps(dict(passed=True,files=len(records),changed=[n for n,r in records.items()if r['changed']])))


if __name__=='__main__':main()

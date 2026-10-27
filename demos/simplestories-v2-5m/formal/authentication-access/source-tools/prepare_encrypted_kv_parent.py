"""Prepare a fresh current-cache/actual encrypted-guard proof source package.

No production source is modified. The already replayed encrypted guard-history
observers replace the protected observers. The parent projection retains the
actual encrypted fault OR and treats every reply beyond the guard as arbitrary;
there is no assumption about the SIV or external memory's behavior.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1'


def pin(raw):
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def once(text, before, after):
    if text.count(before) != 1:
        raise ValueError('Projection port site changed: ' + before[:80])
    return text.replace(before, after, 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--revision', default='r1')
    args = ap.parse_args()
    spec = importlib.util.spec_from_file_location('encrypted_parent_binding', HERE.parent/'formal-assurance/run_handoff.py')
    common = importlib.util.module_from_spec(spec); spec.loader.exec_module(common)
    _, native, binding = common.binding(args.package, 'encrypted-memory')
    manifest = json.loads((SOURCE/'MANIFEST.json').read_bytes())
    out = args.out.resolve(); out.mkdir(parents=True, exist_ok=False)
    originals = {}; files = {}
    for relative, wanted in manifest['files'].items():
        raw = (SOURCE/relative).read_bytes()
        if pin(raw) != wanted:
            raise ValueError('Source package changed: '+relative)
        originals[relative] = raw
        files[relative] = raw
    origins = json.loads((SOURCE/'SOURCE-ORIGINS.json').read_bytes())
    source_joins = {}
    for relative in origins['sources']:
        path = native/relative.removeprefix('production/')
        raw = path.read_bytes(); files[relative] = raw
        source_joins[relative] = dict(path=str(path), **pin(raw))
    files['SOURCE-ORIGINS.json'] = (json.dumps(dict(schema=origins['schema'], source_only=True,
        sources=source_joins), indent=2, sort_keys=True)+'\n').encode()
    port = HERE/'encrypted-kv-history-r1'
    guard_dependencies = json.loads((SOURCE/'GUARD-DEPENDENCIES.json').read_bytes())
    guard_helpers = set(guard_dependencies['copied_dependencies']) | {
        'formal/kv-integrity/'+n for n in ('audit_history.py','audit_control.py','audit_hash.py','audit_contract.py')}
    for relative in list(files):
        if relative in guard_helpers and (port/Path(relative).name).is_file():
            # Shared source-exact observers and auditors from the independently
            # replayed full encrypted history model, not any saved PASS flag.
            files[relative] = (port/Path(relative).name).read_bytes()
    relative = 'formal/kv-integrity/parent_model.py'
    text = files[relative].decode().replace('board1_kv_integrity_guard', 'tang_kv_integrity_guard_epoch')
    text = once(text,
        '    controls += "\\n" + shared_control',
        '    # Retain the actual guard/cipher fault OR; cipher replies/fault are free.\n'
        '    fault_or = "    assign kv_integrity_fault=guard_integrity_fault || kv_cipher_fault;"\n'
        '    assert source["shared"].count(fault_or) == 1\n'
        '    controls += "\\n" + shared_control + "\\n" + fault_or')
    text = once(text, '"private_model_locked_i": "", "boundary_core_fault": "", "auth_fault": "",',
        '"private_model_locked_i": "", "boundary_core_fault": "", "auth_fault": "", "kv_cipher_fault": "",')
    files[relative] = text.encode()
    dependency = json.loads((SOURCE/'GUARD-DEPENDENCIES.json').read_bytes())
    dependency['copied_dependencies'] = {r:pin(files[r]) for r in dependency['copied_dependencies']}
    dependencies = {}
    for relative, wanted in dependency['copied_dependencies'].items():
        path = native/relative.removeprefix('production/') if relative.startswith('production/') else port/Path(relative).name
        if pin(path.read_bytes()) != wanted:
            raise ValueError('Dependency differs: '+relative)
        dependencies[relative] = dict(path=str(path), **wanted)
    dependency['original_dependencies'] = dependencies
    dependency['scope'] = 'Native encrypted guard/hash and pipelined read observers; all conclusions reproved jointly. No prior receipt is assumed.'
    files['GUARD-DEPENDENCIES.json'] = (json.dumps(dependency, indent=2, sort_keys=True)+'\n').encode()
    files.pop('PLAN.json', None)
    files.pop('MANIFEST.json', None)
    for relative, raw in files.items():
        target=out/relative; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(raw)
    new_manifest=dict(manifest, files={relative:pin(raw) for relative,raw in files.items()})
    (out/'MANIFEST.json').write_text(json.dumps(new_manifest,indent=2,sort_keys=True)+'\n')
    plan=json.loads((SOURCE/'PLAN.json').read_bytes())
    plan['source_package']=str(out);plan['source_manifest']=pin((out/'MANIFEST.json').read_bytes())
    plan['runs']={k:str(HERE/'runs'/('encrypted-kv-parent-'+k+'-'+args.revision))for k in plan['runs']}
    plan['audit_output']=str(HERE/'runs'/('audit-encrypted-kv-parent-'+args.revision))
    plan['prepared_only']=False;plan['execution_authorized']=True
    path=HERE/('encrypted-kv-parent-plan-'+args.revision+'.json')
    if path.exists():raise ValueError('Plan output already exists')
    path.write_text(json.dumps(plan,indent=2,sort_keys=True)+'\n')
    receipt=dict(schema='encrypted-current-cache-parent-preparation-v1',passed=True,source_only=True,
        original_source_package=str(SOURCE),native_binding=binding,source_package=str(out),
        production_hardware_modified=False,source_joins=source_joins,
        changed_files={r:dict(original=pin(originals[r]),prepared=pin(raw)) for r,raw in files.items()
            if r in originals and raw!=originals[r]},
        scope='Preparation and byte association only. No solver or composition theorem is established by this generator.')
    (out/'PREPARATION.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (out/'preparer.py').write_bytes(Path(__file__).read_bytes())
    print(json.dumps(dict(passed=True,plan=str(path),plan_sha256=pin(path.read_bytes())['sha256'])))


if __name__=='__main__':main()

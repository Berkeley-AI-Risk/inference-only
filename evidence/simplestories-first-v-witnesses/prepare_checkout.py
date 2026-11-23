"""Rebuild the proof inputs from pinned public Git objects and the reviewed Lisp sources."""
import argparse
from hashlib import file_digest, sha256
import io
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tarfile
import tempfile

RECIPE = Path(__file__).resolve().parent
EVIDENCE = 'evidence/simplestories-kv-record'
DEMO = 'demos/simplestories-v2-5m/'
EXP_FILE = DEMO + 'hardware/project/model_rtl_evidence/attention_sublayer/exp_neg_q30.memh'
PACKER = 'corrected-cycle/kv-producer-to-record/full-design-run/prepare_run_inputs.py'
JOINED = 'kv-joined-book-checked-sat'


def need(condition, explanation):
    if not condition:
        raise ValueError(explanation)


def identity(path):
    with path.open('rb') as stream:
        digest = file_digest(stream, 'sha256').hexdigest()
    return dict(bytes=path.stat().st_size, sha256=digest)


def load(path):
    return json.loads(path.read_bytes())


def put(path, obj):
    with path.open('x') as output:
        json.dump(obj, output, indent=2, sort_keys=True)
        output.write('\n')


def exact_bytes(data, wanted, label):
    need(len(data) == wanted['bytes'] and sha256(data).hexdigest() == wanted['sha256'],
         'Pinned input differs: ' + label)
    return data


def verify(destination):
    manifest = load(destination/'SOURCES.json')
    need(manifest['schema'] == 'first-value-clean-checkout-inputs-v1', 'Unrecognized source manifest')
    wanted = load(RECIPE/'PINS.json')
    need(manifest['public_commit'] == wanted['public_commit']
         and manifest['public_tree'] == wanted['public_tree']
         and manifest['recipe_pins'] == identity(RECIPE/'PINS.json'), 'Source manifest detached from the recipe')
    for member, expected in manifest['inputs'].items():
        path = destination/member
        need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(destination.resolve()),
             'Unexpected input file: ' + member)
        need(identity(path) == expected, 'Pinned input differs: ' + member)
    recorded = manifest['inputs']
    named = {**{'proof/'+path: row for path,row in wanted['source_inventory'].items()},
             **{'public-objects/'+path: {key: row[key] for key in ('sha256','bytes')}
                for path,row in wanted['public_assets'].items()}}
    for path, row in named.items():
        need(recorded.get(path) == row, 'Pinned input differs: '+path)
    acl2_constants = {'proof/'+path: digest for path,digest in wanted['generated_numerical_book_sha256'].items()}
    packed = {'packed-inputs/'+path: digest for path,digest in wanted['packed_sha256'].items()}
    joined = 'proof/corrected-cycle/'+JOINED+'/'
    rtl_manifest = joined+'SOURCES.sha256'
    need(recorded.get(rtl_manifest, {}).get('sha256') == wanted['public_reproduction']['rtl_manifest_sha256'],
         'Pinned RTL manifest differs')
    rtl = {joined+relative: digest for digest, relative in
           (line.split() for line in (destination/rtl_manifest).read_text().splitlines())}
    for path,digest in (acl2_constants|packed|rtl).items():
        need(recorded.get(path, {}).get('sha256') == digest, 'Pinned input differs: '+path)
    return manifest


def prepare(public_git, destination):
    needle = load(RECIPE/'PINS.json')
    commit = needle['public_commit']

    def git(*args):
        return subprocess.check_output(['git', '-C', str(public_git), *args])

    need(not destination.exists() and destination.parent.is_dir(), 'Use a new output directory')
    need(git('rev-parse', commit+'^{tree}').decode().strip() == needle['public_tree'],
         'Public tree does not match the pinned commit')
    with tempfile.TemporaryDirectory(prefix='first-value-public-') as tmp:
        scratch = Path(tmp)
        with tarfile.open(fileobj=io.BytesIO(git('archive', commit, EVIDENCE)), mode='r:') as archive:
            archive.extractall(scratch, filter='data')
        replay = scratch/'replay'
        subprocess.run([sys.executable,'-I','-S','-B',str(scratch/EVIDENCE/'reproduce.py'),
                        '--public-git',str(public_git),'--out',str(replay)],
                       cwd=scratch, check=True, capture_output=True)
        reproduction = load(replay/'REPRODUCTION.json')
        want = needle['public_reproduction']
        for key in ('verified_rtl_names', 'rtl_manifest_sha256', 'elaboration_order_sha256',
                    'regenerated_books_sha256', 'public_commit', 'public_tree'):
            need(reproduction[key] == want[key], 'Pinned public reconstruction differs: '+key)

        destination.mkdir()
        proof = destination/'proof'
        for relative, expected in needle['source_inventory'].items():
            raw = exact_bytes((RECIPE/'book-sources'/relative).read_bytes(), expected, relative)
            target = proof/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        joined = proof/'corrected-cycle'/JOINED
        shutil.copytree(replay/JOINED/'rtl', joined/'rtl')
        shutil.copytree(replay/JOINED/'rtl-original', joined/'rtl-original')
        shutil.copyfile(replay/JOINED/'SOURCES.sha256', joined/'SOURCES.sha256')
        rtl_rows = [line.split() for line in (joined/'SOURCES.sha256').read_text().splitlines()]
        need(len(rtl_rows) == 77, 'Wrong reconstructed RTL input census')
        for digest, relative in rtl_rows:
            need(identity(joined/relative)['sha256'] == digest, 'Pinned reconstructed RTL differs: '+relative)

        public_inputs = destination/'public-objects'
        for relative, wanted in needle['public_assets'].items():
            raw = exact_bytes(git('cat-file', 'blob', commit+':'+relative), wanted, relative)
            target = public_inputs/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        shutil.copytree(scratch/EVIDENCE/'notices', destination/'proof-tool-notices')
        shutil.copytree(scratch/EVIDENCE/'translator', destination/'translator-recipe')

        # Recreate the paths expected by the originally certified serializer, in
        # a disposable layout. The shipped executable and data are unchanged.
        legacy = scratch/'legacy-asset-layout'
        legacy_audit = legacy/'audit'
        packer = proof/PACKER
        packing = runpy.run_path(str(packer))
        for key in ('IMAGE','DIGESTS','METADATA','NORM'):
            old_path, want = packing[key]
            public_rel = DEMO + ('assets/' + Path(old_path).name if key == 'IMAGE'
                                 else 'hardware/project/' + old_path.split('/project/',1)[1])
            source = public_inputs/public_rel
            need(identity(source)['sha256'] == want, 'Model/ROM equivalence changed')
            target = legacy/old_path
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,target)
        old_exp = legacy/packing['EXP_MEMH']
        old_exp.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(public_inputs/EXP_FILE,old_exp)
        inlined_exp = legacy_audit/packing['RTL_ROOT']/packing['EXP_RTL']
        inlined_exp.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(joined/'rtl'/packing['EXP_RTL'],inlined_exp)
        legacy_manifest = legacy_audit/packing['SOURCES']
        legacy_manifest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(joined/'SOURCES.sha256',legacy_manifest)

        packed = destination/'packed-inputs'
        packed.mkdir()
        subprocess.run([sys.executable,'-I','-S','-B',str(packer),str(legacy_audit),str(legacy),str(packed)],
                       cwd=scratch,check=True,capture_output=True)
        for name,digest in needle['packed_sha256'].items():
            need(identity(packed/name)['sha256'] == digest, 'Packed proof input differs: '+name)
        regenerated = scratch/'books'
        regenerated.mkdir()
        subprocess.run([sys.executable,'-I','-S','-B',str(proof/'first-value-numeric/make_inputs.py'),
                        str(packed),str(regenerated)], check=True, capture_output=True)
        for name, digest in needle['generated_numerical_book_sha256'].items():
            actual = regenerated/Path(name).name
            need(identity(actual)['sha256'] == digest, 'Generated ACL2 constant differs: '+name)
            shutil.copyfile(actual, proof/name)
        # Keep portable digests rather than a temporary path inventory.
        (packed/'PREPARED.txt').unlink()

    inputs = {path.relative_to(destination).as_posix():identity(path)
              for path in sorted(destination.rglob('*')) if path.is_file()}
    manifest = dict(schema='first-value-clean-checkout-inputs-v1', public_commit=commit,
                    public_tree=needle['public_tree'], recipe_pins=identity(RECIPE/'PINS.json'),
                    rtl_files=len(rtl_rows), source_books=len([n for n in inputs if n.endswith('.lisp')]),
                    inputs=inputs, fixed_cases=needle['checked_model_cases'],
                    source_reproduction=reproduction, certification_executed=False)
    put(destination/'SOURCES.json', manifest)
    return verify(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--public-git', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    destination = args.out.resolve()
    if args.verify:
        need(args.public_git is None,'--verify reads only the staged tree')
        manifest = verify(destination)
    else:
        need(args.public_git is not None,'Source staging needs a public Git clone')
        manifest = prepare(args.public_git.resolve(), destination)
    print(json.dumps(dict(passed=True, rtl_files=manifest['rtl_files'], acl2_sources=manifest['source_books'],
                          checked_members=len(manifest['inputs']), certification_executed=False)))


if __name__ == '__main__':
    main()


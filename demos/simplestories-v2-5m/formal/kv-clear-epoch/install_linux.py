"""Install digest-pinned Linux proof tools outside the repository."""
import argparse, hashlib, json, os, platform, subprocess, tarfile, time, urllib.request, zipfile
from pathlib import Path
HERE = Path(__file__).resolve().parent
def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(4 * 1024 * 1024), b''): h.update(block)
    return h.hexdigest()
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True); parser.add_argument('--cache', type=Path)
    args = parser.parse_args(); assert platform.system() == 'Linux', 'Linux tools only'
    out = args.out.resolve(); assert not out.exists(), 'Use a new tool directory'
    cache = args.cache.resolve() if args.cache else out.parent / 'proof-tool-downloads'
    cache.mkdir(parents=True, exist_ok=True); out.mkdir(parents=True)
    pins = json.loads((HERE / 'LINUX-TOOLS.json').read_text())
    arch = platform.machine(); assert arch in pins['architectures'], ('Unsupported architecture', arch)
    records = []
    for row in pins['architectures'][arch]:
        archive = cache / row['name']
        if not archive.exists():
            temporary = archive.with_suffix(archive.suffix + '.part')
            request = urllib.request.Request(row['url'], headers={'User-Agent': 'inference-only-formal-replay'})
            start = time.monotonic(); count = 0
            with urllib.request.urlopen(request, timeout=60) as response, temporary.open('wb') as target:
                while block := response.read(4 * 1024 * 1024):
                    count += len(block); assert count <= row['bytes'] and time.monotonic() - start < 300
                    target.write(block)
            assert count == row['bytes']; temporary.rename(archive)
        assert archive.stat().st_size == row['bytes'] and digest(archive) == row['sha256'], 'Tool archive mismatch'
        if archive.name.endswith('.tgz'):
            with tarfile.open(archive) as tf: tf.extractall(out, filter='data')
        else:
            with zipfile.ZipFile(archive) as zf:
                for info in zf.infolist():
                    p = Path(info.filename)
                    assert not p.is_absolute() and '..' not in p.parts
                    zf.extract(info, out)
                    target = out / p
                    if target.is_file(): target.chmod((info.external_attr >> 16) & 0o777 or 0o644)
        records.append(row)
    cvc5 = list(out.glob('cvc5-Linux-*-static/bin/cvc5')); assert len(cvc5) == 1
    paths = [str(cvc5[0].parent), str(out / 'oss-cad-suite/bin')]
    env = dict(os.environ); env['PATH'] = os.pathsep.join(paths + [env.get('PATH', '')])
    versions = {}
    for name, flag in [('yosys', '-V'), ('z3', '--version'), ('cvc5', '--version')]:
        r = subprocess.run([name, flag], capture_output=True, text=True, timeout=10, check=True, env=env)
        versions[name] = r.stdout.strip()
    result = {'passed': True, 'architecture': arch, 'path_entries': paths, 'archives': records, 'versions': versions}
    (out / 'TOOLS.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if 'GITHUB_PATH' in os.environ:
        with Path(os.environ['GITHUB_PATH']).open('a') as f: f.write('\n'.join(paths) + '\n')
    print(json.dumps(result, indent=2))
if __name__ == '__main__': main()

#!/usr/bin/env python3
"""Reconstruct the two public signed test packages without hardware access."""
from pathlib import Path
import argparse, importlib.util, json

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('replacement_models', ROOT / 'tools/check_model_replacement.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    dest = a.output.resolve()
    assert not dest.is_relative_to(checker.DEMO.parents[1]), 'Use a fresh workspace outside the repository'
    evidence = ROOT / 'evidence/model-replacement-v2'
    checker.capture_integrity(evidence)
    roots, images, slots, blocks = checker.signed_models(evidence)
    dest.mkdir(parents=True, exist_ok=False)
    files = {}
    for label, image in images.items():
        package = (evidence / ('model-' + label + '-signed-prefix.bin')).read_bytes() + image
        for name, data in [('model-' + label + '.bin', image), ('model-' + label + '.swic', package)]:
            (dest / name).write_bytes(data)
            files[name] = {'bytes': len(data), 'sha256': checker.digest(data)}
    result = {'models': roots, 'files': files, 'fixture': 'Public synthetic replacement with zero final-normalization weights', 'hardware_access': False, 'network_access': False}
    (dest / 'MODELS.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))

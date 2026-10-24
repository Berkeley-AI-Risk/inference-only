"""Check current record integrity and report its actual browser phase, offline."""
import argparse
import importlib.util
import json
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--require-complete',action='store_true')
    args=parser.parse_args();package=args.package.resolve()
    spec=importlib.util.spec_from_file_location('_current_release_phase',package/'tools/seeded_release_compat.py')
    compat=importlib.util.module_from_spec(spec);spec.loader.exec_module(compat)
    result=compat.check_current(package,'phase',args.require_complete)
    compat.check_unchanged_greedy_payloads(package)
    result['historical_greedy_payloads_unchanged']=True
    print(json.dumps(result,indent=2,sort_keys=True))


if __name__=='__main__':main()

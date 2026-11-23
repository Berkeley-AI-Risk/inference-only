"""Certify one recipient stage and record theorem identities from its fresh ACL2 world."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys

RECIPE = Path(__file__).resolve().parent
CHECKOUT = runpy.run_path(str(RECIPE/'prepare_checkout.py'))
VERIFY = CHECKOUT['verify']
IDENTITY = CHECKOUT['identity']
FIXED_TRANSLATOR = '99f4a19521edf7aa657744c3865bec70f05ffd4135696b7c04f0dc3a6c46486c'
APPROVED_TAGS = set('''SWAP-ELAB-MODS FAST-ALIST-POP SNEAKY-LOAD FAST-CONS-MEMO AIG-VARS OSLIB
QUICKLISP QUICKLISP.SHELLPOOL TSHELL SATLINK VL-OPTIMIZE CW-UNFORMATTED OPEN-OUTPUT-CHANNEL!
FAST-CAT MEMORY-MGMT VL-GC QUICKLISP.OSICAT'''.split())
CORRECTED_TOP = 'corrected-cycle/kv-producer-to-record/full-design-run/kv-step-to-record-evaluable'
HELD_TOP = 'held-clear-record/kv-step-to-record-held'
FINITE = 'first-value-numeric/'
STAGES = {
    'corrected': {
        'prior': (), 'targets': (CORRECTED_TOP,), 'probe_books': (CORRECTED_TOP,),
        'events': ('SV::KV-STEP-TO-RECORD', 'SV::KV-STEP-TO-RECORD-LAYER-0-POSITION-0')},
    'held': {
        'prior': ('corrected',), 'targets': (HELD_TOP,), 'probe_books': (HELD_TOP,),
        'events': ('SV::KVH-HELD-MACHINE-AGREES-WITH-CORRECTED-CYCLE',
                   'SV::KV-STEP-TO-RECORD-HELD-LAYER-0-POSITION-0')},
    'finite': {
        'prior': ('corrected','held'),
        'targets': tuple(FINITE + name for name in (
            'kvn-token-1-stages', 'kvn-open-equation', 'kvn-control-changed-reference',
            'kvn-rom-rms-weights', 'ssv-spec-properties', 'ssv-saved-runs', 'ssv-image-sha256',
            'more-tokens/kvn-token-27', 'more-tokens/kvn-token-32','more-tokens/kvn-token-3258')),
        'events': ('SV::KVN-TOKEN-1-FIRST-VALUE', 'SV::KVN-TOKEN-1-ORDINARY-STEP','SV::KVN-TOKEN-1-STAGES',
                   'SV::KVN-TOKEN-27-ORDINARY-STEP', 'SV::KVN-TOKEN-32-ORDINARY-STEP',
                   'SV::KVN-TOKEN-3258-ORDINARY-STEP',
                   'SV::KVN-FIRST-VALUE-OF-EVERY-LEGAL-TOKEN-GIVEN-THE-OPEN-EQUATION')},
}
STATEMENT = re.compile(r'^PROOF-TERM-BEGIN ([0-9A-F]{16})\s*\n(.*?)^PROOF-TERM-END \1\s*$', re.M|re.S)
FAILURE = re.compile(r'ACL2 Error|FAILED \*+|Unhandled .* in thread|HARD ACL2 ERROR')


def need(condition, detail):
    if not condition:
        raise ValueError(detail)


def load(path):
    return json.loads(path.read_bytes())


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def statement_key(name):
    return sha256(name.encode()).hexdigest()[:16].upper()


def statement_form(name):
    marker = statement_key(name)
    return f"""(make-event
 (let* ((name '{name}) (world (w state))
        (actual (getpropc name 'theorem nil world))
        (introduced (get-event name world)))
   (if (and actual (eq (car introduced) 'defthm)
            (not (get-skipped-proofs-p name world)))
       (prog2$ (cw "~%PROOF-TERM-BEGIN {marker}~%~x0~%PROOF-TERM-END {marker}~%" actual)
               (value '(value-triple :statement-present)))
     (er soft 'recipient-world "The named theorem is absent or has a skipped proof."))))"""


def extract_statements(log, names):
    statements = STATEMENT.findall(log)
    name_by_marker = {statement_key(name): name for name in names}
    need(len(statements)==len(names)==len(name_by_marker) and {marker for marker, _ in statements}==set(name_by_marker),
         'Missing or repeated observed ACL2 theorem')
    return {name_by_marker[marker]: {'translated_formula_sha256': sha256(body.strip().encode()).hexdigest(),
                   'acl2_printed_formula': body.strip()} for marker, body in statements}


def probe_script(books, names):
    includes = [f'(include-book "{book}" :ttags :all)' for book in books]
    return '\n'.join(['(in-package "ACL2")','(set-ld-error-action :error state)',
        *includes,'(in-package "ACL2")','(set-evisc-tuple nil :iprint nil :sites :all)',
        '(ld "acl2-pilot/nonblocking/library-report.lsp")',
        *map(statement_form,names),
        '(cw "~%RECIPIENT-WORLD-COMPLETE~%")',':q',''])


def proof_environment(library, log_path):
    env = os.environ.copy()
    env.pop('MAKEFLAGS',None)
    env.update(ACL2_SYSTEM_BOOKS=str(library), ACL2_CUSTOMIZATION='NONE',
               SBCL_USER_ARGS='--control-stack-size 4000 --dynamic-space-size 100000',
               KVJ_SAT_LOG=str(log_path))
    return env


def saved_parent(checkout, stage, identities, tools):
    receipt = checkout/'certification'/stage/'RESULT.json'
    record = load(receipt)
    need(record['certified'] and record['stage']==stage and record['prepared_sources']==identities
         and record['tools']==tools, 'Parent receipt detached: '+stage)
    for relative, digest in record['certificates'].items():
        need(IDENTITY(checkout/'proof'/relative)==digest, 'Fresh parent certificate changed: '+relative)
    log = receipt.with_name('world.log')
    need(IDENTITY(log)==record['world_log'], 'Fresh parent world transcript changed')
    extracted = extract_statements(log.read_text(), record['statements'])
    need(extracted==record['statements'], 'Parent statement identity detached from its world')
    return record, IDENTITY(receipt)


def stage_main(args):
    checkout = args.checkout.resolve()
    acl2, library = args.acl2.resolve(), args.books.resolve()
    proof = checkout/'proof'
    metadata = VERIFY(checkout)
    need(not any(char.isspace() for char in str(checkout)+str(library)+str(acl2)),
         'Use whitespace-free checkout and ACL2 paths for cert.pl')
    translator = library/'centaur/sv/vl/svstmt-compile.lisp'
    need(IDENTITY(translator)['sha256']==FIXED_TRANSLATOR, 'Wrong corrected translator source')
    tool = library/'build/cert.pl'
    tools = {'acl2': IDENTITY(acl2), 'cert_pl': IDENTITY(tool), 'corrected_translator': IDENTITY(translator)}
    prepared = IDENTITY(checkout/'SOURCES.json')
    spec = STAGES[args.stage]
    output = checkout/'certification'/args.stage
    argv = [str(tool),'-a',str(acl2),'-b',str(library),'-j','1']
    if args.dry_run:
        # A make dry run discovers the transitive book inputs without loading
        # ACL2. Put it in the isolated source staging tree.
        dry = [*argv,'--make-args','-n', *spec['targets']]
        return subprocess.run(dry,cwd=proof,
            env=proof_environment(library,checkout/'dry-run-sat.log')).returncode

    need(not output.exists(), 'Use a fresh stage output directory')
    parents = [saved_parent(checkout, name, prepared, tools) for name in spec['prior']]
    inherited = {name: row for record, _ in parents for name,row in record['statements'].items()
                 if name in STAGES[record['stage']]['events']}
    need(all(not (proof/(target+'.cert')).exists() for target in spec['targets']),
         'A stage target certificate already exists')
    output.mkdir(parents=True)
    argv.extend(spec['targets'])
    save(output/'INTENT.json',{'stage':args.stage,'argv':argv,'source_manifest':prepared,
                              'one_certification_job':True,'hardware_access':False})
    env = proof_environment(library,output/'sat-calls.txt')
    certlog = output/'cert-pl.log'
    with certlog.open('x') as stream:
        process = subprocess.run(argv,cwd=proof,env=env,stdout=stream,stderr=subprocess.STDOUT)
    need(process.returncode == 0, 'cert.pl failed. Retain cert-pl.log and the partial tree')
    need(all((proof/(target+'.cert')).is_file() for target in spec['targets']), 'Missing current stage certificates')
    # Imported certificates must remain those previously proved on this tree.
    for name in spec['prior']:
        saved_parent(checkout,name,prepared,tools)

    all_names = [*inherited,*spec['events']]
    examiner = output/'world.lsp'
    examiner.write_text(probe_script(spec.get('probe_books',spec['targets']),all_names))
    log = output/'world.log'
    with examiner.open('r') as data, log.open('x') as stream:
        result = subprocess.run([str(acl2)],cwd=proof,env=env,stdin=data,stdout=stream,stderr=subprocess.STDOUT)
    raw = log.read_text()
    need(result.returncode==0 and not FAILURE.search(raw)
         and re.search(r'^RECIPIENT-WORLD-COMPLETE\s*$',raw,re.M), 'Fresh ACL2 world failed to load')
    need('ACL2 Version 8.7' in raw and re.search(r'BCT-LIB loaded without a certificate:\s+0\b',raw)
         and re.search(r'BCT-LIB skip-proofs seen:\s+NIL\b',raw)
         and re.search(r'BCT-LIB redefinition seen:\s+NIL\b',raw),
         'Unexpected ACL2 version or compiled book trust state')
    tags_body = re.search(r'BCT-LIB-DETAIL trust tags:\s*(.*?)BCT-LIB-DETAIL svstmt-compile:',raw,re.S)
    need(tags_body is not None,'No trust-tag report')
    tags = set(re.findall(r'(?<!:):([A-Z0-9.!-]+)', tags_body[1]))
    count = re.search(r'BCT-LIB trust tags:\s+(\d+)',raw)
    need(count is not None and len(tags)==int(count[1]) and tags<=APPROVED_TAGS,
         'Unexpected trust tags in the loaded world')
    statements = extract_statements(raw,all_names)
    need(all(statements[name]==row for name,row in inherited.items()),
         'A freshly certified parent statement changed on import')
    VERIFY(checkout)
    certificates = {path.relative_to(proof).as_posix(): IDENTITY(path)
                    for path in sorted(proof.rglob('*.cert'))}
    archive = {'stage':args.stage,'certified':True,'prepared_sources':prepared,'tools':tools,
               'source_tree_public_basis':metadata['public_commit'], 'prior_stage_receipts':dict(
                   (name, digest) for name, (_,digest) in zip(spec['prior'],parents)),
               'certificates':certificates, 'cert_pl_log':IDENTITY(certlog),'world_log':IDENTITY(log),
               'statements':statements, 'trust_tags':sorted(tags), 'hardware_access':False}
    save(output/'RESULT.json',archive)
    print(json.dumps({'stage':args.stage,'certified':True,'world_statement_count':len(statements)}))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout',required=True,type=Path)
    parser.add_argument('--stage',required=True,choices=tuple(STAGES))
    parser.add_argument('--acl2',required=True,type=Path)
    parser.add_argument('--books',required=True,type=Path)
    parser.add_argument('--dry-run',action='store_true')
    return stage_main(parser.parse_args())


if __name__ == '__main__':
    raise SystemExit(main())


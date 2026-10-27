"""Prove native bank handshake contracts independent of private SHA replies.

The original bank control, payload RAM and dimensions are retained. Standalone
SHA child outputs, where present, become unrestricted inputs without assumptions.
Encrypted banks already have private SHA/crypto input ports. These stronger
interface theorems make no claim that arbitrary replies authenticate payloads.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_bank_interface_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory'),default='baseline')
    p.add_argument('--timeout',type=int,default=30);p.add_argument('--mutant',action='store_true')
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    group=('baseline','seeded-sampling')if args.variant=='baseline'else(args.variant,)
    original=None;joins={}
    for variant in group:
        _,directory,bound=common.binding(args.package,variant);raw=(directory/'project/bank.sv').read_bytes()
        if original is not None and original!=raw:raise ValueError('Claimed native bank identity differs')
        original=raw;joins[variant]=bound
    source=original.decode();encrypted=args.variant=='encrypted-memory';cuts=[];removed={}
    if not encrypted:
        matches=list(re.finditer(r'    board1_sha256_bank_owned_compress #\([^\n]*\) u_sha \([\s\S]*?\);',source))
        if len(matches)!=1:raise ValueError('Native SHA child boundary changed')
        match=matches[0];removed['removed-sha-instance.sv.txt']=match[0].encode()
        replacement='    assign sha_busy=f_sha_busy_i;\n    assign sha_done=f_sha_done_i;\n    assign sha_state=f_sha_state_i;'
        source=source[:match.start()]+replacement+source[match.end():]
        source=source.replace('\n);',',\n    input wire f_sha_busy_i,f_sha_done_i,\n    input wire [255:0] f_sha_state_i\n);',1)
        cuts=[dict(instance='u_sha',output=n,replacement='unrestricted input f_sha_'+n+'_i',assumptions=[])for n in('busy','done','state')]
    if args.mutant:
        before='response_valid_q<=read_fire;';after='response_valid_q<=read_valid_i;'
        if source.count(before)!=1:raise ValueError('Native response ownership mutation site changed')
        source=source.replace(before,after,1)
    monitor=(HERE/'bank-interface-monitor.inc.sv').read_text()
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    module='tang_pooled_confidential_page_bank'if encrypted else'board1_verified_page_bank'
    header=source[source.index(') (')+3:source.index('\n);')].replace('output logic','output wire')
    names=[]
    for line in header.splitlines():
        if 'input wire'in line or'output wire'in line:
            tail=re.sub(r'^.*?\b(?:input|output)\s+wire\s*(?:\[[^]]+\])?\s*','',line).rstrip(',')
            names.extend(x.strip()for x in tail.split(','))
    params='.IMAGE_WORDS(227062)'
    if encrypted:params+=",.KEY_IS_PROVISIONED(1'b1),.MODEL_NONCE(96'h112233445566778899aabbcc)"
    harness='module bank_interface_native('+header+'\n);\n    '+module+' #('+params+') u_bank (\n'
    harness+=',\n'.join('        .'+n+'('+n+')'for n in names)+'\n    );\nendmodule\n'
    files={'bank.sv':b'`undef FORMAL\n'+source.encode(),'harness.sv':harness.encode(),
        'production-bank.sv':original,'monitor.inc.sv':monitor.encode(),**removed,
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    return engine.check(args.run,files,top='bank_interface_native',
        reset_constraints='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n',
        assertions=monitor.count('assert('),covers=1,binding=dict(native_joins=joins,native_image_words=227062,
            private_SHA_and_crypto_behavior_unrestricted_without_assumptions=True,payload_authenticity_not_claimed=True,
            production_source_sha256=hashlib.sha256(original).hexdigest()),cuts=cuts,depth=6,induction_depth=3,
        cover_depth=8,timeout=args.timeout,mutant='raw-valid-is-response'if args.mutant else None,
        source_list=['bank.sv','harness.sv'],optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Native bank single-pending-request interface and reference transaction identity, independent of all private SHA/crypto replies. Response ownership, READY and recorded word/page, cancellation, refill exclusion, backpressure and sticky fault are proved without child assumptions. Payload authentication is a separate full native bank/SHA theorem; this interface model is not an authentication or whole-device training theorem.')


if __name__=='__main__':raise SystemExit(main())

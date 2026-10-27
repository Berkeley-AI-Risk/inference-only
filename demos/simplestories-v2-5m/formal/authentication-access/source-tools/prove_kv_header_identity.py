"""Universal injectivity lemma for the source-connected K/V identity encoding.

This is an encoding lemma, not a SHA collision-resistance theorem. The native
wrapper correspondence separately joins this exact format to accepted SHA
header blocks. A dropped-role control must produce a real collision witness.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time


def sha(raw):return hashlib.sha256(raw).hexdigest()


def concat(parts):
    result=parts[-1]
    for part in reversed(parts[:-1]):result=f'(concat {part} {result})'
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--mutant',action='store_true');args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    domain=struct.pack('>16s',b'IO-KV-ROLE-v2')
    fields=(('epoch',64),('layer',3),('page',7),('head',1),('role',1),('positions',5))
    query='(set-logic QF_BV)\n';headers=[]
    for n in range(2):
        for field,width in fields:query+=f'(declare-fun {field}{n} () (_ BitVec {width}))\n'
        query+=f'(assert (bvult layer{n} (_ bv6 3)))\n'
        query+=f'(assert (and (bvuge positions{n} (_ bv1 5)) (bvule positions{n} (_ bv16 5))))\n'
        parts=['#x'+domain.hex(),f'epoch{n}',f'((_ zero_extend 29) layer{n})',f'((_ zero_extend 25) page{n})',
            f'((_ zero_extend 31) head{n})',f'((_ zero_extend 31) '+('#b0'if args.mutant else f'role{n}')+')',
            f'((_ zero_extend 27) positions{n})','#x00000010','#x00000020','#x'+'00'*12]
        headers.append(concat(parts))
    query+='(check-sat)\n(push 1)\n(assert (= '+headers[0]+' '+headers[1]+'))\n'
    query+='(assert (not (and '+' '.join(f'(= {field}0 {field}1)'for field,_ in fields)+')))\n(check-sat)\n(exit)\n'
    (out/'query.smt2').write_text(query);(out/'runner.py').write_bytes(Path(__file__).read_bytes());rows=[]
    for solver in('z3','cvc5'):
        binary=Path(shutil.which(solver)).resolve()
        command=[str(binary),'-smt2',str(out/'query.smt2')]if solver=='z3'else[str(binary),'--lang=smt2','--incremental','--tlimit-per=10000',str(out/'query.smt2')]
        start=time.monotonic();cp=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=15)
        (out/(solver+'.log')).write_bytes(cp.stdout);answers=re.findall(r'^(sat|unsat|unknown)$',cp.stdout.decode(),re.M)
        rows.append(dict(solver=solver,command=command,binary_sha256=sha(binary.read_bytes()),exit=cp.returncode,
            answers=answers,passed=cp.returncode==0 and answers==(['sat','sat']if args.mutant else['sat','unsat']),
            seconds=time.monotonic()-start,log_sha256=sha(cp.stdout)))
    receipt=dict(schema='K-V-identity-header-injectivity-v1',passed=all(r['passed']for r in rows),
        mutant='role-field-removed'if args.mutant else None,results=rows,fields=dict(fields),header_bytes=64,
        format='>16sQIIIIIII12x',domain=domain.hex(),satisfiable_legal_identity_domain_checked=True,
        query_sha256=sha(query.encode()),runner_sha256=sha(Path(__file__).read_bytes()),
        scope='Universal finite-bit identity encoding lemma over every legal epoch, layer, page, head, role and positions tuple. Equal encoded headers imply equal identity fields. This is joined to the real SHA input by a separate native wrapper theorem; no cryptographic hardness or whole-device guarantee.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=receipt['passed'],mutant=receipt['mutant'],answers=[r['answers']for r in rows])))


if __name__=='__main__':main()

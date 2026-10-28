"""Check completed native RAM lemmas against all four current source inventories."""
import hashlib
import json
from pathlib import Path

from run_memory_isolation import HERE, SPECS, load


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    package=HERE.parents[1]/'fpga-demo/public-release'
    binder=load('binding_audit',HERE.parent/'formal-assurance/run_handoff.py')
    runs={k:HERE/'runs'/('query-clear-r1'if k=='query'else'accumulator-clear-r1'if k=='accumulator'else
        'native-leaf-clear-r1-'+k)for k in SPECS}
    selected={}
    for kind,run in runs.items():
        inputs=json.loads((run/'INPUTS.json').read_bytes())
        result=json.loads((run/'FINISHED.json').read_bytes())
        if result.get('passed')is not True or inputs['cover_cells']!=(3 if kind=='accumulator'else 2)or inputs['assumption_cells']!=0:
            raise ValueError('Incomplete native RAM result '+kind)
        if result['inputs_sha256']!=sha((run/'INPUTS.json').read_bytes()):
            raise ValueError('Changed run inputs')
        for name,row in inputs['files'].items():
            raw=(run/name).read_bytes()
            if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Changed input '+name)
        for solver in ('z3','cvc5'):
            for phase in ('bmc','induction','cover'):
                row=result['results'][solver+'-'+phase]
                if not row['passed'] or row['status']!=['PASSED']:raise ValueError('Incomplete solver phase')
                if row['log_sha256']!=sha((run/(solver+'-'+phase+'.log')).read_bytes()):
                    raise ValueError('Changed solver log')
        graph=json.loads((run/'elaborated.json').read_bytes())['modules']['native_memory_isolation']
        memories={n:c for n,c in graph['cells'].items()if c['type']=='$mem_v2'}
        module,address,lanes,width,_=SPECS[kind]
        expected_per_copy=8 if kind in ('query','accumulator')else 3 if kind=='workspace'else 1
        if len(memories)!=2*expected_per_copy:raise ValueError('Independent RAM census changed')
        words=682 if kind=='scratch'else 1<<address
        for copy in ('u_a.','u_b.'):
            members=[c for n,c in memories.items()if n.startswith(copy)]
            if len(members)!=expected_per_copy:raise ValueError('Missing independent payload')
            for cell in members:
                parameters=cell['parameters']
                if int(parameters['SIZE'],2)!=words or int(parameters['WIDTH'],2)!=width:
                    raise ValueError('Native RAM geometry changed')
                if set(parameters['INIT'])!={'x'}:raise ValueError('RAM initial contents were constrained')
        raw=(run/'production-memories.sv').read_bytes()
        selected[kind]=dict(production_path=inputs['binding']['production_path'],
            source_sha256=sha(raw),proof_run=str(run.relative_to(HERE)),
            result_sha256=sha((run/'FINISHED.json').read_bytes()),
            native_words=words,physical_banks_per_copy=expected_per_copy,bank_width=width,
            native_uninitialized_payloads_retained=True,both_solvers_complete=True,initial_hard_reset=False,
            unequal_old_state_cover=True,current_owned_read_cover=True)
    joins={}
    for variant in ('baseline','seeded-sampling','kv-protected','encrypted-memory'):
        _,root,bound=binder.binding(package,variant)
        for kind,row in selected.items():
            path=row['production_path']
            if path not in bound['distributed_inputs']or sha((root/path).read_bytes())!=row['source_sha256']:
                raise ValueError('Native variant memory differs: '+variant+' '+kind)
        joins[variant]=dict(image_sha256=bound['image_sha256'],
            inventory_sha256=bound['native_inventory_sha256'],memory_families=list(selected))
    result=dict(passed=True,scope='Native RAM history and conditional two-copy leaf isolation only; parent ownership and complete session composition remain separate.',
                memories=selected,variant_joins=joins,checker_sha256=sha(Path(__file__).read_bytes()))
    (HERE/'MEMORY-BINDINGS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('MEMORY_BINDINGS passed=True families='+str(len(selected))+' variants='+str(len(joins)))


if __name__=='__main__':main()

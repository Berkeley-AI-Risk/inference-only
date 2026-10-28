"""Join full native-top census objects to the four pinned source inventories.

Source classes include actual instantiated module names and native defines.
This prevents crediting an unused distributed implementation as active hardware.
It is a structural binding audit, not a property/composition proof.
"""
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load

RUNS={'baseline':'native-hierarchy-r1','seeded-sampling':'native-hierarchy-seeded-sampling-r1',
      'kv-protected':'native-hierarchy-kv-protected-r1','encrypted-memory':'native-hierarchy-encrypted-memory-r4'}


def main():
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    package=HERE.parents[1]/'fpga-demo/public-release'
    classes={};variants={}
    for variant,name in RUNS.items():
        run=HERE/'runs'/name;inputs=json.loads((run/'INPUTS.json').read_text())
        census=json.loads((run/'CENSUS.json').read_text());graph=json.loads((run/'hierarchy.json').read_text())['modules']
        for filename,key in [('INPUTS.json','input_sha256'),('hierarchy.json','hierarchy_json_sha256'),
                             ('hierarchy.il','hierarchy_rtlil_sha256'),('yosys.log','log_sha256')]:
            if binder.sha((run/filename).read_bytes())!=census[key]:raise ValueError('Census artifact changed')
        _,native,binding=binder.binding(package,variant)
        if binding!=inputs['native_join']:raise ValueError('Native census detached from current image/source inventory')
        definitions={}
        for relative in inputs['compile_files']:
            raw=(native/'project'/relative).read_bytes()
            for m in re.finditer(r'^module\s+(\w+)\b',raw.decode(),re.M):
                definitions.setdefault(m[1],[]).append('project/'+relative)
        for row in census['instances']:
            module=row['original_module']or row['module']
            if module not in definitions:raise ValueError('Unbound instantiated custom module: '+module)
            paths=definitions[module]
            if len(paths)!=1:raise ValueError('Ambiguous native module definition: '+module)
            path=paths[0];digest=binding['distributed_inputs'][path]
            key=path+'@'+digest
            entry=classes.setdefault(module,{}).setdefault(key,dict(production_path=path,source_sha256=digest,
                variants=[],instances_by_variant={},sequential_cells_by_variant={},memory_objects_by_variant={}))
            if variant not in entry['variants']:entry['variants'].append(variant)
            entry['instances_by_variant'][variant]=entry['instances_by_variant'].get(variant,0)+1
            entry['sequential_cells_by_variant'][variant]=len(row['sequential_cells'])
            entry['memory_objects_by_variant'][variant]=list(row['declared_memory_objects'])
        leaves={r['type']for r in census['unresolved_leaf_instances']}
        if not leaves.issubset({'Gowin_PLL','CLKDIV','DDR3_Memory_Interface_Top','MULTALU27X18','DPB'}):
            raise ValueError('Unreviewed unresolved leaf type '+str(leaves))
        latches=[dict(path=r['path'],cell=n,type=c['type'])for r in census['instances']for n,c in r['sequential_cells'].items()
                 if'latch'in c['type']]
        if latches:raise ValueError('Retained latch state requires review '+str(latches))
        variants[variant]=dict(census_run=name,census_sha256=binder.sha((run/'CENSUS.json').read_bytes()),
            image_sha256=binding['image_sha256'],inventory_sha256=binding['native_inventory_sha256'],
            compile_defines_sha256=binding['distributed_inputs']['project/defines.v'],
            instantiated_custom_modules=census['instantiated_custom_modules'],vendor_leaf_types=sorted(leaves),
            retained_latches=latches)
    result=dict(structural_binding_passed=True,formal_proof=False,session_milestone_complete=False,
        variants=variants,instantiated_module_source_classes=classes,
        checker_sha256=binder.sha(Path(__file__).read_bytes()))
    (HERE/'HIERARCHY-BINDINGS.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(structural_binding_passed=True,variants=len(variants),
        instantiated_module_names=len(classes),session_milestone_complete=False)))


if __name__=='__main__':main()

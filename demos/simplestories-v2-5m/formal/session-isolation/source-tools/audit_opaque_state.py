"""Inventory state enabled in the actual native vendor arithmetic leaves.

Configuration/wiring audit only: does not prove vendor primitive internals.
Every stateful arithmetic instance must use the separately proved MAC role.
Other vendor RAM/clock/DDR boundaries remain explicitly listed.
"""
import json
from pathlib import Path

from audit_hierarchy_bindings import RUNS
from run_attention_ownership import HERE, load


def main():
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py');variants={}
    for variant,name in RUNS.items():
        run=HERE/'runs'/name;census=json.loads((run/'CENSUS.json').read_text())
        graph=json.loads((run/'hierarchy.json').read_text())['modules']
        if binder.sha((run/'hierarchy.json').read_bytes())!=census['hierarchy_json_sha256']:
            raise ValueError('Native hierarchy graph changed')
        instances={r['path']:r for r in census['instances']};arithmetic=[];other=[]
        for row in census['unresolved_leaf_instances']:
            parent,cell=row['path'].rsplit('/',1);owner=instances[parent]
            native=graph[owner['module']]['cells'][cell]
            if row['type']!='MULTALU27X18':other.append(row);continue
            parameters=native['parameters'];enabled={k:v for k,v in parameters.items()if k.endswith('_CLK')and v!='BYPASS'}
            if parameters.get('FB_PREG_EN')!='FALSE'or parameters.get('SOA_PREG_EN')!='FALSE':
                raise ValueError('Unreviewed native DSP feedback state: '+row['path'])
            role='stateless combinational arithmetic'
            if enabled:
                if owner['original_module']!='board1_projection_dsp_accumulator'or enabled!={'OREG_CLK':'CLK0','PREG_CLK':'CLK0'}:
                    raise ValueError('Uncovered registered native arithmetic: '+row['path'])
                if parameters.get('PREG_CE')!='CE0'or parameters.get('OREG_CE')!='CE1'or parameters.get('DYN_ACC_SEL')!='TRUE':
                    raise ValueError('Native MAC temporal configuration changed')
                role='registered projection MAC; cluster ownership plus conditional recurrence lemma'
            arithmetic.append(dict(path=row['path'],owner=owner['original_module'],role=role,
                registered_clock_parameters=enabled,parameters=parameters,connections=native['connections']))
        variants[variant]=dict(native_hierarchy_sha256=census['hierarchy_json_sha256'],arithmetic=arithmetic,
            registered_arithmetic_instances=sum(bool(r['registered_clock_parameters'])for r in arithmetic),
            other_vendor_boundaries=other)
    result=dict(configuration_audit_passed=True,vendor_semantics_proved=False,variants=variants,
        checker_sha256=binder.sha(Path(__file__).read_bytes()))
    (HERE/'OPAQUE-STATE-AUDIT.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(configuration_audit_passed=True,registered_arithmetic_instances={v:r['registered_arithmetic_instances']for v,r in variants.items()},vendor_semantics_proved=False)))


if __name__=='__main__':main()

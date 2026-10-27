"""Congruence substitution of independently proved, stateless native leaves.

No value becomes arbitrary: each replacement is the exact total input/output
function proved against the actual native wrapper and installed vendor RTL.
"""
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def module(raw,name):
    start=raw.index(('module '+name+' ').encode())
    end=raw.index(b'\nendmodule',start)+len(b'\nendmodule')
    return raw[start:end]


def rewrite(raw):
    selected=[('tang_sha_dsp_add32','native-sha-fixed-add-r2-opt',
        b'module tang_sha_dsp_add32(input wire [31:0] a_i,b_i,output wire [31:0] sum_o);\n    assign sum_o=32\'(a_i+b_i);\nendmodule'),
        ('tang_sha_csa3_add32','native-sha-csa-add-r1',
        b'module tang_sha_csa3_add32(input wire [31:0] x_i,y_i,z_i,output wire [31:0] sum_o);\n    assign sum_o=32\'(x_i+y_i+z_i);\nendmodule')]
    obligations=[];evidence={}
    for name,run,replacement in selected:
        path=HERE/'runs'/run
        input_raw=(path/'INPUTS.json').read_bytes();inputs=json.loads(input_raw)
        finished_raw=(path/'FINISHED.json').read_bytes();result=json.loads(finished_raw)
        if not result['passed'] or result['internal_cuts'] or inputs['assumption_cells']:
            raise ValueError('Native arithmetic premise has not been discharged')
        if (path/'reset.smtc').read_bytes():raise ValueError('Arithmetic proof restricts its inputs')
        for n,row in inputs['files'].items():
            data=(path/n).read_bytes()
            if row!={'bytes':len(data),'sha256':sha(data)}:raise ValueError('Arithmetic proof source changed')
        if result['inputs_sha256']!=sha(input_raw):raise ValueError('Arithmetic proof/input binding changed')
        for label,row in result['results'].items():
            if not row['passed'] or row['status']!=['PASSED'] or row['exit']!=0:
                raise ValueError('An arithmetic solver phase is incomplete')
            if sha((path/(label+'.log')).read_bytes())!=row['log_sha256'] or sha((path/(label+'.smt2')).read_bytes())!=row['query_sha256']:
                raise ValueError('Arithmetic solver evidence changed')
        graph=json.loads((path/'elaborated.json').read_bytes())['modules'][inputs['top']]
        for cell in graph['cells'].values():
            if cell['type']in('$assume','$anyseq','$anyconst','$mem_v2')or 'ff'in cell['type'].lower()or'latch'in cell['type'].lower():
                raise ValueError('Replacement premise is not a total stateless function')
        native=module((path/'production-sha.sv').read_bytes(),name)
        if raw.count(native)!=1:raise ValueError('Native arithmetic leaf differs from proved source: '+name)
        raw=raw.replace(native,replacement,1)
        obligations.append(dict(kind='proved-equivalent-stateless-leaf-substitution',module=name,
            original_module_sha256=sha(native),replacement_module_sha256=sha(replacement),
            premise_run=run,premise_inputs_sha256=sha(input_raw),premise_result_sha256=sha(finished_raw),
            independently_discharged=True,arbitrary_output=False,
            trusted_vendor_functional_model_sha256=inputs['binding']['vendor_library_sha256']))
        evidence[name+'-premise-INPUTS.json']=input_raw
        evidence[name+'-premise-FINISHED.json']=finished_raw
        evidence[name+'-original.sv']=native
        evidence[name+'-equivalent.sv']=replacement
    return raw,obligations,evidence

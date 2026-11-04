"""Portable source binding for the two native component proofs."""
import hashlib
import json
from pathlib import Path
import re
from checkpoint import atomic_json

HERE=Path(__file__).resolve().parent
MODEL=HERE.parent.parent
PUBLIC=MODEL/'hardware/project'
PROJECT=PUBLIC
CAMPAIGN=HERE
BINDING=HERE/'SOURCE-PINS.json'
TOP='board1_fixed_vector_rmsnorm_service'
RMS='fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/'
ROM=RMS+'recorded/norm_rom34.memh'
ORDER=[RMS+'rtl/board1_fixed_vector_rmsnorm_service.sv',
       RMS+'rtl/board1_fixed_rmsnorm_arithmetic.sv',RMS+'rtl/board1_fixed_rmsnorm_rom.sv',
       'fpga/token_only_model0_board0/rtl/physical/board0_exact_isqrt_u45_iterative.sv',
       'fpga/token_only_model0_ddr_board1/fixed_elementwise0/rtl/board1_fixed_elementwise_dsp_lane.sv',
       'normalizer_pipeline.sv','candidate.sv']


def sha(raw):return hashlib.sha256(raw).hexdigest()
def write_json(path,value):atomic_json(path,value)
def modules(raw):
    return {m[1]:m[0] for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw,re.M)}


def verify_inventory():
    manifest=json.loads((HERE/'SOURCES.json').read_text());selected=[]
    for name,row in manifest['files'].items():
        raw=(MODEL/row['model_source']).read_bytes()
        if sha(raw)!=row['sha256']:raise ValueError('Current source changed: '+name)
        for module,digest in row.get('module_sha256',{}).items():
            if sha(modules(raw.decode())[module].encode())!=digest:raise ValueError('Module changed: '+module)
    for name in ORDER:
        defs=modules((PUBLIC/name).read_text())
        selected.extend(defs[m] for m in manifest['files'][name]['compiled_modules'])
    native='`undef FORMAL\n`default_nettype none\n'+'\n\n'.join(selected)+'\n'
    if sha(native.encode())!=manifest['compiler_source_sha256'] or (HERE/'project/native.sv').read_text()!=native:
        raise ValueError('Native source does not equal selected production modules')
    if (HERE/'project'/ROM).read_bytes()!=(PUBLIC/ROM).read_bytes():raise ValueError('Compiled ROM changed')
    for name,instance in manifest['caller_instances'].items():
        if (PUBLIC/name).read_text().count(instance)!=1:raise ValueError('Actual caller changed')
    shell='fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv'
    if 'RMS_MAX_COMPUTE_CYCLES = 2_000_000;' not in (PUBLIC/shell).read_text():raise ValueError('Caller watchdog changed')
    return manifest

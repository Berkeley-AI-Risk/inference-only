"""Read-only checks of the shipped Qwen source selection, not HDL elaboration."""
import argparse
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re


ROOT = Path(__file__).resolve().parents[1]
MODELS = ('qwen3-1.7b', 'qwen3-8b')
VENDOR_INCLUDES = {'cl_ports.vh', 'unused_ddr_template.inc'}


def need(value, message):
    if not value:
        raise ValueError(message)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def static_sources(text):
    """Accept only the two literal lists used by these frozen build scripts."""
    text = re.sub(r'(?m)^\s*#.*$', '', text)
    pattern = r'\s*set qwen_sv_sources\s*\{([^{}]*)\}\s*set qwen_v_sources\s*\{([^{}]*)\}\s*'
    match = re.fullmatch(pattern, text)
    need(match, 'Source list is not the supported pair of literal Tcl lists')
    groups = []
    for block, suffix in zip(match.groups(), ('.sv', '.v')):
        names = block.split()
        need(names and all(re.fullmatch(r'[A-Za-z0-9_]+' + re.escape(suffix), n) for n in names),
             'Unsafe or unexpected source-list member')
        groups.append(names)
    all_names = groups[0] + groups[1]
    need(len(all_names) == len(set(all_names)), 'Duplicate compiled source')
    return groups


def selection(manifest, groups):
    selected = {'hardware/design/' + name for group in groups for name in group}
    inventoried = {name for name in manifest if name.startswith('hardware/design/')
                   and name.endswith(('.sv', '.v'))}
    need(selected == inventoried, 'Compiled HDL differs from the frozen design inventory')
    need('hardware/design/cl_qwen.sv' in selected, 'Missing selected CL top')
    return selected


def uncomment_tcl(text):
    return re.sub(r'\s+', ' ', re.sub(r'(?m)^\s*#.*$', '', text)).strip()


def consumers(synth, staging, build):
    synth = uncomment_tcl(synth)
    for statement in (
        'source ${CL_DIR}/build/scripts/qwen_sources.tcl',
        'foreach name $qwen_sv_sources {read_verilog -sv [file join $src_post_enc_dir $name]}',
        'foreach name $qwen_v_sources {read_verilog [file join $src_post_enc_dir $name]}',
        'synth_design -mode out_of_context -top ${CL} -part ${DEVICE_TYPE}',
        '-verilog_define XSDB_SLV_DIS -keep_equivalent_registers -flatten_hierarchy none',
        'source ${CL_DIR}/build/scripts/qwen_cdc_constraints.tcl',
        'qwen_apply_cdc_constraints',
    ):
        # Tcl line continuations are lexical whitespace here; no Tcl is executed.
        need(statement in synth.replace('\\ ', ' '), 'Changed synthesis consumer: ' + statement)
    need(len(re.findall(r'\bread_verilog\b', synth)) == 2, 'Unexpected direct Verilog reader')
    staging = uncomment_tcl(staging)
    need('foreach source [glob -directory ${CL_DIR}/design *]' in staging
         and 'file copy -force $source $src_post_enc_dir' in staging,
         'Changed CL source staging')
    build = uncomment_tcl(build)
    need('source encrypt.tcl' in build and 'source ${scripts_dir}/synth_${CL}.tcl' in build,
         'Build entry no longer consumes the checked staging/synthesis scripts')


def local_includes(root, manifest, selected):
    pending, seen, vendor = list(selected), set(), set()
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        text = (root / name).read_text()
        for include in re.findall(r'^\s*`include\s+"([^"\n]+)"', text, re.M):
            rel = PurePosixPath(include)
            need(len(rel.parts) == 1 and '\\' not in include and rel.name not in ('.', '..'),
                 'Unsupported include path')
            if include in VENDOR_INCLUDES:
                vendor.add(include)
            else:
                target = 'hardware/design/' + include
                need(target in manifest, 'Unpinned local include: ' + include)
                pending.append(target)
    return sorted(vendor), sorted(seen - selected)


def verify(root=ROOT, model=None):
    root = Path(root).resolve(strict=True)
    model = model or root.name
    need(model in MODELS, 'Choose a supported released Qwen configuration')
    # Reuse the existing byte/hash and path checks. This does not stage a build.
    prepare = load_module(root / 'tools/prepare_hardware.py', 'selected_qwen_prepare')
    original = prepare.verify(root)
    if model == 'qwen3-1.7b':
        manifest, implementation = original
    else:
        implementation = original
        manifest = original['frozen_hardware_inputs']
    need(implementation['clock_recipes'] == dict(a='A0', b='B0', c='C2', hbm='H1'),
         'Different clock recipe selection')
    scripts = root / 'hardware/build/scripts'
    groups = static_sources((scripts / 'qwen_sources.tcl').read_text())
    selected = selection(manifest, groups)
    consumers((scripts / 'synth_cl_qwen.tcl').read_text(), (scripts / 'encrypt.tcl').read_text(),
              (scripts / 'build_all.tcl').read_text())
    top = (root / 'hardware/design/cl_qwen.sv').read_text()
    need(re.search(r'^module cl_qwen\s*\(', top, re.M), 'Selected file does not declare the expected CL top')
    need('qwen_aws_host_machine #(.MODEL_PREFETCH_PAGES(32)) fixed_machine(' in top,
         'Different top-level model-prefetch selection')
    vendor, headers = local_includes(root, manifest, selected)
    need(set(vendor) == VENDOR_INCLUDES, 'Different separately acquired shell interfaces')
    has_root_rom = 'qwen_fixed_root_rom.sv' in groups[0]
    need(has_root_rom == (model == 'qwen3-8b'), 'Wrong model-specific root-ROM selection')
    for name in ('qwen_kv_plain_writer.sv', 'qwen_kv_plain_reader.sv', 'qwen_kv_plain_store.sv'):
        need(name in groups[0], 'This is not the released plain-K/V source selection')
    return dict(passed=True, model=model, top='cl_qwen',
                ordered_systemverilog_sources=groups[0], ordered_verilog_sources=groups[1],
                local_include_files=headers, separately_acquired_shell_includes=vendor,
                clock_recipes=implementation['clock_recipes'], synthesis_define='XSDB_SLV_DIS',
                model_prefetch_pages_at_top=32, private_KV_candidate_selected=False,
                checked_scope='Frozen byte identities and static source-list/build relationships',
                HDL_or_Tcl_elaboration=False, solver_run=False, cloud_actions=False, hardware_access=False)


def main(model=None, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=root, help='Read another complete release demo directory')
    args = parser.parse_args()
    print(json.dumps(verify(args.root, model), indent=2))


if __name__ == '__main__':
    main()

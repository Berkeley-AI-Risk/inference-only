"""Check selected public source bytes and recorded HWIC configuration boundaries.

This is a file-only check. It does not execute RTL, elaborate a circuit, replay
private campaigns, rerun proofs, or qualify physical memories or an ASIC.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def owned(root, name):
    path = PurePosixPath(name)
    require(bool(name) and not path.is_absolute() and '..' not in path.parts and '\\' not in name, 'invalid public path')
    result = root / name
    require(result.resolve().is_relative_to(root.resolve()), 'path escapes release')
    return result


def source_list(raw):
    rows = [line.strip() for line in raw.splitlines() if line.strip()]
    require(len(set(rows)) == len(rows), 'duplicate source operand')
    return rows


def project_sources(raw):
    project = ET.fromstring(raw)
    return [f.attrib['path'] for f in project.findall('./FileList/File')
            if f.attrib.get('enable') == '1' and f.attrib.get('type') == 'file.verilog']


def verify(root, data):
    root = Path(root)
    require(data['schema'] == 'hwic-configuration-evidence-fragment-v1', 'wrong schema')
    records = {x['id']: x for x in data['source_records']}
    require(len(records) == len(data['source_records']), 'duplicate source record')
    for row in records.values():
        require(re.fullmatch('[0-9a-f]{64}', row['sha256']) is not None, 'invalid source hash')
        require(isinstance(row['bytes'], int) and row['bytes'] > 0, 'invalid byte count')
        if row['availability'] == 'public':
            raw = owned(root, row['path']).read_bytes()
            require(len(raw) == row['bytes'] and sha(raw) == row['sha256'], 'source record changed: ' + row['path'])
        else:
            require(row['availability'] == 'private-recorded-not-bundled' and 'path' not in row, 'private source availability')
    configs = {x['configuration']: x for x in data['configurations']}
    require(set(configs) == {'public-rom', 'integrated-spatial', 'split-kv', 'attention-reuse'}, 'configuration selection changed')
    required = {'status', 'development_source', 'selected_source', 'build', 'numerical_contract', 'interfaces',
                'protections_and_clocks', 'evidence', 'reproduction', 'open_obligations'}
    for name, row in configs.items():
        require(required <= row.keys(), 'incomplete configuration row')
        require(row['build']['defines'] == ['SYNTHESIS'], 'HWIC define selection changed')
        require(row['build']['top'] == 'hwic_simplestories' and row['build']['simulation_top'] == 'tb_hwic_simplestories', 'HWIC top selection changed')
        require(row['build']['top_parameter_overrides'] == {}, 'unexpected top parameter override')
        for identifier in row['evidence']['records']:
            require(identifier in records, 'evidence lacks source record: ' + identifier)
        if name != 'public-rom':
            require(row['selected_source']['availability'] == 'private-recorded-not-bundled' and
                    row['reproduction']['public_fresh_rtl_replay'] is False and row['build']['build_entry'] is None,
                    'private selection represented as public replay')
    reuse = data['public_reuse']
    checkpoint = 'research/hwic/simplestories-2026-10-27'
    prov = json.loads(owned(root, checkpoint + '/PROVENANCE.json').read_bytes())
    hwic_list = source_list(owned(root, reuse['hwic_source_list']).read_text())
    prov_files = {x['path']: x for x in prov['RTL_sources']}
    require(set(prov_files) == {'rtl/' + p for p in hwic_list} | {'rtl/sources.f'}, 'provenance/list membership changed')
    hwic_hashes = {}
    for relative, pin in prov_files.items():
        raw = owned(root, checkpoint + '/' + relative).read_bytes()
        require(len(raw) == pin['bytes'] and sha(raw) == pin['sha256'], 'checkpoint source changed: ' + relative)
        if relative != 'rtl/sources.f':
            hwic_hashes[relative.removeprefix('rtl/')] = sha(raw)
    public = configs['public-rom']
    require(public['build']['source_operands'] == len(hwic_list) and len(hwic_list) == 68, 'checkpoint source count')
    require(public['build']['defines'] == prov['compile_defines'] and public['build']['simulation_top'] == prov['compile_top'], 'checkpoint compile binding')
    require(public['build']['top'] == prov['sealed_top'], 'checkpoint sealed top')
    require(public['numerical_contract']['contract'] == prov['numerical_contract'], 'numerical contract changed')
    manifest = json.loads(owned(root, reuse['awic_manifest']).read_bytes())
    awic_list = source_list(owned(root, reuse['awic_source_list']).read_text())
    require(project_sources(owned(root, reuse['awic_native_project']).read_text()) == awic_list, 'AWIC native project/list order differs')
    project_root = Path(reuse['awic_source_list']).parent.as_posix()
    absent = []
    for relative in awic_list:
        key = 'project/' + relative
        require(key in manifest, 'AWIC source lacks selected manifest hash')
        path = owned(root, project_root + '/' + relative)
        if path.is_file():
            require(sha(path.read_bytes()) == manifest[key], 'AWIC source changed: ' + relative)
        else:
            absent.append(relative)
    require(absent == reuse['separately_acquired_vendor_sources'] and all(p.startswith('official/') for p in absent), 'unexpected absent AWIC source')
    defines = re.findall(r'^\s*`define\s+(\w+)\s*$', owned(root, project_root + '/defines.v').read_text(), re.M)
    require(defines == reuse['awic_defines'], 'AWIC define selection changed')
    tcl = owned(root, reuse['awic_build_entry']).read_text()
    require('set_option -top_module board1_fixed_shared_product_top' in tcl, 'AWIC top build binding changed')
    pairs = [dict(awic_path=p, hwic_path=q, sha256=h) for p in awic_list for q, h in hwic_hashes.items() if manifest['project/' + p] == h]
    require(pairs == reuse['pairs'], 'reuse content pairs changed')
    changed = [dict(path=p, awic_sha256=manifest['project/' + p], hwic_sha256=hwic_hashes[p])
               for p in awic_list if p in hwic_hashes and manifest['project/' + p] != hwic_hashes[p]]
    require(changed == reuse['same_path_changed'], 'changed shared-path inventory changed')
    require(public['reuse']['byte_identical_source_operands'] == len({p['hwic_path'] for p in pairs}), 'reuse count changed')
    require(public['reuse']['awic_source_operands'] == len(awic_list), 'AWIC operand count changed')
    original = json.loads(owned(root, checkpoint + '/evidence/original-rtl-validation.json').read_bytes())
    for a, b in [('numerical_cases','case_count'), ('outputs','exact_tokens'), ('tensor_logit_comparisons','selected_tensor_and_logit_checks')]:
        require(public['evidence'][a] == original[b], 'original numerical scope changed')
    totals = json.loads(owned(root, 'research/hwic/evidence/integrated-model-2026-11-04/results.json').read_bytes())['totals']
    for a, b in [('numerical_cases','positive_cases'),('outputs','output_tokens'),('tensor_logit_comparisons','tensor_comparisons'),('circuit_fault_cases','actual_fault_cases')]:
        require(configs['integrated-spatial']['evidence'][a] == totals[b], 'integrated numerical scope changed')
    m = data['memory_process']
    rom_source = owned(root, checkpoint + '/rtl/hwic_fixed_model_rom.sv').read_text()
    for array in m['central_rom_arrays']:
        match = re.search(r'\blogic\s*\[(\d+):0\]\s*' + re.escape(array['name']) + r'\s*\[0:(\d+)\]', rom_source)
        require(match is not None and int(match[1])+1 == array['width_bits'] and int(match[2])+1 == array['depth'], 'ROM array source binding')
    require(sum(x['depth'] * x['width_bits'] // 8 for x in m['central_rom_arrays']) == m['central_rom_payload_bytes'], 'ROM capacity arithmetic')
    payload, meta = m['split_payload_banks'], m['split_metadata_banks']
    capacity = sum(x['count'] * x['depth'] * x['width_bits'] // 8 for x in [payload, meta])
    require(capacity == m['split_kv_array_bytes'], 'split KV capacity arithmetic')
    require(m['physical_optimization'] == 'hold' and m['legal_instances_obtained'] is False and m['characterized_views_or_access_obtained'] is False, 'memory qualification scope changed')
    require(m['full_chip_area_mm2'] is None and m['achieved_full_chip_clock_hz'] is None, 'unqualified physical estimate promoted')
    require(configs['split-kv']['evidence']['full_corpus_accepted'] is False, 'partial campaign promoted to accepted')
    require(configs['attention-reuse']['evidence']['native_invocations'] == 0 and configs['attention-reuse']['evidence']['source_review_only'] is True, 'source-only candidate promoted')
    return dict(status='PASS_FILE_CONSISTENCY_ONLY', public_configurations_recomputed=1,
                private_configurations_recorded_only=3, public_hwic_source_operands=len(hwic_list),
                selected_awic_source_operands=len(awic_list), identical_hwic_source_operands=len({p['hwic_path'] for p in pairs}),
                missing_vendor_source_prerequisites=absent, rtl_simulation_run=False, ASIC_qualified=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-root', type=Path, default=HERE.parents[3])
    parser.add_argument('--rows', type=Path, default=HERE / 'rows.json')
    args = parser.parse_args()
    print(json.dumps(verify(args.release_root, json.loads(args.rows.read_bytes())), sort_keys=True))


if __name__ == '__main__':
    main()

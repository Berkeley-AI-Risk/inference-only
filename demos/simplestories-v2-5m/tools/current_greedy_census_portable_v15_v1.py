"""Recompute accounting from pinned original observational MULT censuses.

This rechecks actual raw report/VO byte identities and recorded per-cell rows.
It does not re-enumerate or reinterpret the complete VO, rerun a tool, establish
operand controllability or calculate training capacity. Source entries, HDL
module definitions and physical MULT instances are distinct quantities.
"""
from collections import Counter
import hashlib
import re

CLOSED_CENSUSES = {'protected-v15-compact-prefix': ('selected-native-mapped-multiplier-observational-census-v15-v1', '0d82fab3e80c9c9a6737e1a38a81f75777e03849a9a9f1519ab4d461ca647224', 8, 8), 'baseline-v1': ('baseline-selected-native-mapped-multiplier-observational-census-v1', '5ce797c87d11b838e7b990a34a662b15ba3fac221d0201d6d17c8ba849cc65e0', 8, 8), 'encrypted-v5-coordinate': ('selected-native-mapped-multiplier-observational-census-mixed-v2', '37c421f11fd20bd3c03a6f8a772d91d25289951e41dfe1a2284a28b90c66f688', 8, 8)}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def pin(reader, row):
    return reader.read(row['path'], {key: row[key] for key in ('path','bytes','sha256')})


def validate_census(reader, origin, epoch, native):
    need(epoch in CLOSED_CENSUSES, 'No actual eligible census registered for this source epoch')
    schema, sha, score, value = CLOSED_CENSUSES[epoch]
    need(type(sha)is str and len(sha)==64,'Actual final observational census pin pending')
    raw = reader.read(origin)
    need(hashlib.sha256(raw).hexdigest() == sha, 'Original reviewed observational census differs')
    record = reader.json(origin)
    need(record['schema'] == schema and record['passed'] is True and record['variant'] == reader.variant
         and record['training_capacity_calculated'] is False and record['whole_machine_claim'] is False,
         'Recorded observational census scope differs')
    rows = record['mapped_instances']
    need(type(rows) is list and 0 < len(rows) <= 512 and len({row['instance'] for row in rows}) == len(rows),
         'Complete unique bounded recorded physical-instance census required')
    groups = dict(Counter(row['group'] for row in rows))
    kinds = dict(Counter(row['primitive'] for row in rows))
    need(groups == record['functional_group_counts'] and kinds == record['primitive_counts']
         and set(kinds) <= {'MULTALU27X18','MULT12X12'}
         and record['attention_score_instances'] == groups['attention_score'] == score
         and record['attention_value_instances'] == groups['attention_value'] == value
         and record['attention_shared_mac_pool'] is False
         and record['unclassified_multiplier_cells'] == [] and record['unknown_multiplier_types'] == [],
         'Recorded instance/classification/attention census differs')
    products = record['raw_native_products']
    image_sha = record['image_sha256'] if epoch == 'baseline-v1' else record['image']['sha256']
    need(image_sha == native['image']['sha256'] and products['.fs']['sha256'] == image_sha,
         'Census image belongs to another selected native')
    for row in products.values():
        pin(reader, row)
    text = pin(reader, products['.rpt.txt']).decode()
    report = {}
    for kind in ('MULTALU27X18','MULT12X12'):
        matches = re.findall(r'^\s*--' + kind + r'\s*\|\s*(\d+)\s*$',text,re.M)
        need(len(matches) == 1, 'Missing/duplicate actual resource report MULT class')
        report[kind] = int(matches[0])
    dsp = re.findall(r'^\s*DSP\s*\|\s*([\d.]+)/298\s*\|',text,re.M)
    need(kinds == report and len(dsp) == 1 and float(dsp[0]) == report['MULTALU27X18'] + report['MULT12X12']/2,
         'Raw report/count/vendor resource accounting differs')
    total_key = 'total_multiplier_instances' if epoch == 'baseline-v1' else 'total_MULT_family_primitive_instances'
    dsp_key = 'reported_vendor_dsp_blocks' if epoch == 'baseline-v1' else 'reported_vendor_DSP_blocks'
    need(record[total_key] == len(rows) and record[dsp_key] == float(dsp[0]), 'Recorded total/DSP accounting differs')
    for field, role in [('native_plan','native_plan'),('native_finished','native_finished'),
                        ('native_static_audit','native_static'),('source_native_join','source_join')]:
        need(record[field] == reader.pin(reader.data['roles'][role]), 'Census/source/native selected role differs')
    if epoch != 'baseline-v1':
        fixed=72 if epoch=='protected-v15-compact-prefix'else 52
        need(record['source_fixed_add_DSP_instances'] == groups['sha_fixed_add32_dsp'] == fixed
             and record['other_source_role_primitive_instances'] == len(rows)-fixed
             and record['baseline_or_historical76_counts_inherited'] is False
             and record['historical5_over76_factor_applied'] is False, 'Fixed-add/nonlinear-role observational accounting differs')
        descriptor = reader.json(record['actual_role_descriptor']['path'], record['actual_role_descriptor'])
        need(descriptor['source_join'] == record['source_native_join'] and descriptor['image'] == products['.fs']
             and descriptor['netlist'] == products['.vo'] and record['fixed_add_control_observations'] == descriptor['fixed_add_control_observations']
             and record['fixed_add_constant_fact'] == descriptor['fixed_add_constant_fact'], 'Fixed-add descriptor/control provenance differs')
    return dict(passed_recorded_accounting_recheck=True, recorded_MULT_family_physical_instances=len(rows),
        recorded_functional_group_counts=groups, recorded_primitive_counts=kinds, reported_vendor_DSP_blocks=float(dsp[0]),
        actual_report_reparsed_and_VO_bytes_rehashed=True, complete_VO_freshly_enumerated=False,
        independent_source_to_netlist_or_operand_control_theorem=False, training_capacity_calculated=False,
        historical5_over76_factor_applied=False, native_or_model_or_simulation_executed=False)

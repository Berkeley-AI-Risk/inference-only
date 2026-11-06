"""Read-only source/report-to-document checks, not FPGA or proof qualification.

This deliberately recognizes the frozen top's small management-display block;
it is not a SystemVerilog parser or a synthesized-netlist equivalence checker.
No model, vendor tool, solver, network or FPGA is used.
"""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MODELS = ('qwen3-1.7b', 'qwen3-8b')
FIELDS = (
    ('lifecycle_error_code', 4), ('clock_error_code', 4), ("2'b0", 2),
    ('clock_failed', 1), ('pcis_guard_error', 1), ('hbm_ready', 1),
    ('clock_ready', 1), ('lifecycle_failed', 1), ('online', 1),
)
BEGIN = '<!-- BEGIN GENERATED QWEN {} -->'
END = '<!-- END GENERATED QWEN {} -->'


def need(condition, message):
    if not condition:
        raise ValueError(message)


def verify_identity(data, expected, label):
    need(len(data) == expected['bytes']
         and hashlib.sha256(data).hexdigest() == expected['sha256'],
         'Changed bound input: ' + label)


def management_bits(source):
    """Recognize only the recorded direct-concatenation display shape."""
    clean = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    compact = re.sub(r'\s+', '', clean)
    expression = ','.join(name for name, _ in FIELDS)
    expected = (
        'reg[15:0]management_status;'
        'always@(posedgeclk_main_a0)begin'
        "if(!rst_main_n)management_status<=16'b0;"
        'elsemanagement_status<={' + expression + '};'
        'endassigncl_sh_status_vled=management_status;'
    )
    need(compact.count(expected) == 1, 'Management display shape changed')
    need(len(re.findall(r'\bmanagement_status\s*<=', clean)) == 2
         and len(re.findall(r'\bassign\s+cl_sh_status_vled\s*=', clean)) == 1,
         'Unexpected management display driver')
    need(len(re.findall(r'\bmanagement_status\b', clean)) == 4
         and len(re.findall(r'\bcl_sh_status_vled\b', clean)) == 1,
         'Unexpected additional management-display reference')
    need('wire[3:0]clock_error_code,lifecycle_error_code;' in compact,
         'Management error-code widths changed')
    # Flag declarations are part of this intentionally narrow frozen shape.
    need('wireclock_ready,clock_failed,hbm_ready,lifecycle_failed,pcis_guard_error;' in compact
         and 'wirehost_reset_n,machine_reset_n,online,hbm_shell_reset_n,hbm_memory_reset_n;' in compact,
         'Management flag declarations changed')
    bit, rows = 15, []
    for name, width in FIELDS:
        low = bit-width+1
        rows.append((str(bit) if low == bit else f'{bit}:{low}', name))
        bit = low-1
    need(bit == -1, 'Management field widths do not cover sixteen bits')
    return rows


def critical_cdc_counts(report):
    rows = re.findall(r'^(CDC-\d+)\s+Critical\s+(\d+)\s+(.+)$', report, re.M)
    need(rows and len({row[0] for row in rows}) == len(rows),
         'Missing or ambiguous CDC summary')
    return [(name, int(count)) for name, count, _ in rows]


def display_block(rows):
    lines = [
        BEGIN.format('MANAGEMENT DISPLAY'),
        '### Management display', '',
        'The [packaged top-level RTL](hardware/design/cl_qwen.sv) drives',
        '`cl_sh_status_vled` from this 16-bit management display, sampled on',
        '`clk_main_a0` with synchronous reset to zero:', '',
        '| Bits | Source |', '| --- | --- |',
        *[f'| `{bits}` | `{name}` |' for bits, name in rows], '',
        'This expression contains lifecycle, clock, HBM and error status, not',
        'attention-control state or arithmetic results. It is observable status',
        'beyond returned tokens. This is a source-wiring statement: correspondence',
        'of this display to the published routed checkpoint remains unverified.',
        'It is not a complete test/debug or physical-access assessment.',
        END.format('MANAGEMENT DISPLAY'),
    ]
    return '\n'.join(lines)


def cdc_block(rows):
    total = sum(count for _, count in rows)
    details = ', '.join(f'`{name}`: {count}' for name, count in rows)
    return '\n'.join([
        BEGIN.format('CDC DISCLOSURE'),
        f'The [CDC report](evidence/implementation/cdc.rpt) retains **{total} critical',
        f'findings** in its summary ({details}).',
        'These are reported finding counts, not a count of proved functional',
        'failures. Per-finding disposition and whole-path reset/CDC qualification',
        'remain open; positive setup/hold slack does not discharge them.',
        END.format('CDC DISCLOSURE'),
    ])


def check_block(document, name, expected):
    begin, end = BEGIN.format(name), END.format(name)
    need(document.count(begin) == document.count(end) == 1,
         'Missing or duplicate generated disclosure: ' + name)
    start, stop = document.index(begin), document.index(end)+len(end)
    need(document[start:stop] == expected, 'Stale generated disclosure: ' + name)


def check(package=ROOT):
    results = {}
    for model in MODELS:
        demo = package / 'demos' / model
        manifest = json.loads((demo / 'SOURCE-INPUTS.json').read_text())
        key = 'source_files' if model == 'qwen3-1.7b' else 'frozen_hardware_inputs'
        relative = 'hardware/design/cl_qwen.sv'
        source = (demo / relative).read_bytes()
        verify_identity(source, manifest[key][relative], model + '/' + relative)
        bits = management_bits(source.decode('utf-8'))
        report = (demo / 'evidence/implementation/cdc.rpt').read_bytes()
        reports = json.loads((demo / 'evidence/implementation/REPORTS.json').read_text())
        verify_identity(report, reports['reports']['cdc.rpt']['public'], model + '/cdc.rpt')
        cdc = critical_cdc_counts(report.decode('utf-8'))
        check_block((demo / 'README.md').read_text(), 'MANAGEMENT DISPLAY', display_block(bits))
        check_block((demo / 'HARDWARE.md').read_text(), 'CDC DISCLOSURE', cdc_block(cdc))
        results[model] = dict(
            top_sha256=hashlib.sha256(source).hexdigest(), management_bits=bits,
            cdc_report_sha256=hashlib.sha256(report).hexdigest(),
            critical_cdc_findings=dict(cdc),
        )
    return dict(passed=True, scope='Frozen source/report disclosure consistency only',
                models=results, routed_display_correspondence_verified=False,
                authenticated_operand_use_proved=False,
                full_cdc_signoff=False, hardware_access=False, cloud_actions=False)


if __name__ == '__main__':
    print(json.dumps(check(), indent=2))

"""Offline audit of the finite component logs; never launches native work."""
if not __debug__:
    raise RuntimeError('Run the prefetch auditors with Python assertions enabled')
import collections
import copy
import hashlib
import json
import re
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORACLE = json.loads((HERE / 'ORACLE.json').read_text())
EXPECTED = {(r['mode'], r['context'], r['KV_head']): r['expected_outputs'] for r in ORACLE['rows']}

def require(ok, why):
    if not ok:
        raise AssertionError(why)

def pin(p):
    return {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'bytes': p.stat().st_size}

def bf16(x):
    u = struct.unpack('<I', struct.pack('<f', x))[0]
    return ((u + 0x7fff + ((u >> 16) & 1)) >> 16) & 65535

def word(mode, pos, role, head, coordinate):
    if role:
        return bf16(.25*(pos+1) + .03125*(head+1) + .001953125*(coordinate % 8))
    return bf16(((pos % 5 - 2)*4 + head/2)*(-1 if mode else 1)) if coordinate == 0 else 0

def read_rows(path):
    lines = path.read_text().splitlines()
    terminal = re.fullmatch(r'PASS paired_multi_position profile=([01]) workload=([0-5])', lines[-1]) if lines else None
    require(terminal is not None, 'Missing or malformed native terminal PASS')
    require(all(line.startswith('{') for line in lines[:-1]), 'Unexpected non-JSON native diagnostic')
    rows = [json.loads(line) for line in lines[:-1]]
    require(rows and all(isinstance(row, dict) for row in rows), 'Native events must be JSON objects')
    profile, workload = map(int, terminal.groups())
    require(all(row.get('profile') == profile and row.get('workload') == workload for row in rows),
            'Terminal profile/workload differs from native events')
    return rows

def audit(rows, stall, workload):
    mode = int(workload == 1)
    contexts = [2] if workload < 2 else [16, 17, 33]
    cert = {}; slots = {}; active_reads = {}; by_phase = collections.defaultdict(list)
    outputs = []; pairs = []; sequences = []; publications = []
    read_requests = []; operands = collections.Counter(); last_cycle = -1
    for r in rows:
        require(r['profile'] == stall and r['workload'] == workload, 'Profile/workload label mismatch')
        require(r['cycle'] >= last_cycle, 'Nonmonotonic native cycle')
        last_cycle = r['cycle']; event = r['event']
        if event == 'publication':
            publications.append((r['position'], r['layer']))
        if event == 'population_complete':
            cert.clear(); slots.clear()
        if event == 'request':
            expected_delay = 3 + (((r['address'] >> 8) + r['bytes']//256) % 7 if stall else 0)
            require(r['initial_delay'] == expected_delay, 'Transport descriptor policy differs')
            if not r['update']:
                require(r['bytes'] in (512, 4096), 'Unexpected attention read size')
                key = (r['node'], r['group'], r['address'])
                require(key not in active_reads, 'Overlapping matching read')
                active_reads[key] = (r, [])
                read_requests.append(r)
        if event == 'read_beat':
            key = (r['node'], r['group'], r['address'])
            require(key in active_reads, 'Unowned read beat')
            req, beats = active_reads[key]
            require(r['beat'] == len(beats), 'Read beat order/count')
            due = req['cycle'] + req['initial_delay'] if not beats else beats[-1] + (1 + (((r['address'] >> 8) + r['beat']*5) % 5) if stall else 1)
            require(r['cycle'] >= due, 'Beat arrived before matched transport policy')
            beats.append(r['cycle'])
            if len(beats)*256 == req['bytes']:
                del active_reads[key]
        if event == 'allocation':
            tag = r['new_tag']; node = (tag >> 11) & 15; group = tag & 2047
            require(tag >> 15 == 0, 'Attention allocation outside layer zero')
            require(r['slot'] == ((node >> 3)*128 + group % 128), 'Real slot mapping differs')
            previous = slots.get(r['slot'])
            require(bool(r['old_valid']) == bool(previous), 'Allocation old-valid differs from retained slot')
            if previous:
                require(r['old_tag'] == previous[0], 'Eviction old tag differs')
            slots[r['slot']] = (tag, r['cycle'])
        if event == 'verification':
            require(r.get('ok', True), 'Failed verification in numerical case')
            key = (r['node'], r['group'], r['count'])
            cert.setdefault(key, {})['root' if r['root'] else 'leaf'] = r['cycle']
        if event == 'operand':
            context = contexts[r['phase']]; head = [0, 1, 0][r['head_index']]
            require(r['context'] == context and r['KV_head'] == head, 'Wrong consumed context/head')
            pos = r['position']; role = r['role']; group = pos//16; node = head + 8*role
            require(0 <= pos < context, 'Operand outside prefix')
            slot = 128*role + group % 128; tag = node*2048 + group
            require(slot in slots and slots[slot][0] == tag, 'Operand consumed from wrong retained slot')
            alloc = slots[slot][1]; count = min(16, context-group*16)
            c = cert.get((node, group, count), {})
            require(alloc < c.get('root', -1) < c.get('leaf', -1) <= r['cycle'], 'Operand lacks own fresh allocation/root/leaf chain')
            start = r['half']*64 if role else 0; length = 64 if role else 128
            require(r['bits'] == [word(mode, pos, role, head, i) for i in range(start, start+length)], 'Consumed K/V differs from independent input formula')
            operands[(r['phase'], r['head_index'], role, pos, r['half'])] += 1
        if event == 'numerical_result':
            require(r['outputs'] == EXPECTED[(mode, r['context'], r['KV_head'])], 'Output differs from independent numerical reference')
            outputs.append(r)
        if event == 'pair_done':
            require(r['KV_head'] == [0, 1, 0][r['head_index']], 'Head sequence differs')
            require(r['pair_cycles'] == r['result']-r['start'], 'Pair duration mismatch')
            require(outputs and outputs[-1]['cycle'] == r['result'], 'Pair receipt lacks actual output event')
            require(r['start'] < r['first_K_ready'] <= r['first_K_use'] < r['result'], 'K first-use timing')
            require(r['start'] < r['first_V_ready'] <= r['first_V_use'] < r['result'], 'V first-use timing')
            if r['context'] == 17:
                require(r['first_K_group1'] and r['first_V_group1'], 'Boundary group1 not consumed')
            pairs.append(r)
        if event == 'sequence_done':
            require(r['through_last_result'] == r['last_result']-r['first_start'], 'Last-result sequence duration mismatch')
            require(r['through_quiescence'] == r['cycle']-r['first_start'], 'Quiescence duration mismatch')
            require(r['tail_drain'] == r['cycle']-r['last_result'], 'Tail duration mismatch')
            require(r['evictions'] >= 4, 'Head changes did not replace actual retained slots')
            reqs = [x for x in read_requests if x['phase'] == r['phase']]
            require(sum(x['bytes'] for x in reqs) == r['read_bytes'] and len(reqs) == r['read_requests'], 'Whole-sequence traffic mismatch')
            sequences.append(r)
        by_phase[r['phase']].append(r)
    require(not active_reads, 'Sequence ended with unreturned read')
    require(len(outputs) == len(pairs) == 3*len(contexts), 'Missing numerical heads')
    require(len(sequences) == len(contexts), 'Missing full sequence receipt')
    wanted_publications = [(p, layer) for p in range(2 if workload < 2 else 33) for layer in range(28)]
    require(publications == wanted_publications, 'Actual ordered full-layer publications missing')
    for phase, context in enumerate(contexts):
        for hi in range(3):
            for p in range(context):
                require(operands[(phase, hi, 0, p, 0)] == 1, 'Missing or repeated actual K use')
                for half in range(2):
                    require(operands[(phase, hi, 1, p, half)] == 1, 'Missing or repeated actual V use')
    require(rows[-1]['event'] == 'case_done', 'Missing final quiescent case receipt')
    return {'pairs': pairs, 'sequences': sequences, 'case': rows[-1],
            'numerical_words_compared': len(outputs)*256,
            'actual_operands_compared': sum(operands.values()),
            'attention_policy_descriptors': sorted((r['phase'], r['node'], r['group'], r['address'], r['bytes'], r['initial_delay']) for r in read_requests)}


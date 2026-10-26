"""Bind recorded Qwen common-speed data to raw replies and numerical provenance.

Standard library only; does not execute a model, binary or hardware operation.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath


def need(ok, message):
    if not ok:
        raise ValueError(message)


def read(root, name):
    path = PurePosixPath(name)
    need(not path.is_absolute() and '..' not in path.parts and str(path) == name,
         'Unsafe Qwen evidence path')
    return (Path(root) / name).read_bytes()


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify(root, row, capture, review):
    need(review['schema'] == 'qwen-common-speed-source-review-v1', 'Changed Qwen review schema')
    files = {}
    for name, pin in review['files'].items():
        raw = read(root, name)
        need({'bytes': len(raw), 'sha256': digest(raw)} == pin, 'Changed Qwen evidence: ' + name)
        files[name] = raw
    def raw(name):
        need(name in files, 'Unbound Qwen evidence member: ' + name)
        return files[name]
    def obj(name):
        return json.loads(raw(name))
    identity = capture['identity']
    need(identity == row['identity'], 'Qwen selected identity differs')
    reference = obj(review['reference'])
    need(reference['passed'] is True and reference['software_reference_only'] is True
         and reference['hardware_access'] is False and reference['backend'] == 'cpu'
         and reference['model_image_sha256'] == identity['model_image_sha256']
         and reference['prompt_tokens'] == row['prompt_tokens'] == [9707]
         and reference['max_new_tokens'] == 128 and reference['stop_at_eos'] is False
         and reference['greedy_feedback_dependent'] is True, 'Wrong Qwen numerical reference')
    for name, pin in reference['source_sha256'].items():
        need(digest(read(root, name)) == pin, 'Changed Qwen numerical source: ' + name)
    if review.get('reference_stdout'):
        stdout = raw(review['reference_stdout'])
        software = [json.loads(line) for line in stdout.decode().splitlines()]
        exit_record = obj(review['reference_exit'])
        need(exit_record['actual_exit'] == 0 and exit_record['timed_out'] is False
             and exit_record['stdout_sha256'] == digest(stdout), 'Qwen reference process did not complete')
        need(len(software) == 129 and [x['index'] for x in software[:-1]] == list(range(128))
             and [x['token'] for x in software[:-1]] == reference['expected_tokens']
             and software[-1]['passed'] is True and software[-1]['output_tokens'] == 128
             and software[-1]['record_sha256'] == reference['original_record_sha256'],
             'Qwen numerical-reference transcript differs')
    else:
        need(review.get('reference_completion') in files, 'Missing Qwen numerical completion record')
        original = obj(review['reference_completion'])
        need(original['passed'] is True and original['device'] == 'cpu'
             and original['fpga_executed'] is False
             and original['image_sha256'] == reference['model_image_sha256'],
             'Wrong preserved Qwen CPU reference')
        case = next(c for c in original['cases'] if c['name'] == 'single-token-128-output')
        need(case['passed'] is True and case['prompt_tokens'] == [9707]
             and case['max_new_tokens'] == 128 and case['stop_at_eos'] is False
             and case['tokens'] == reference['expected_tokens'], 'Preserved Qwen reference IDs differ')
        for name, member in review['reference_sources'].items():
            need(digest(raw(member)) == original['source_sha256'][name], 'Preserved Qwen reference source differs')
        need(raw(review['reference_sources']['dense_qwen_reference.py'])
             == read(root, 'demos/' + row['id'] + '/reference/dense_qwen_reference.py'),
             'Preserved Qwen numerical engine differs from release')
    need(identity['clocks_mhz'] == {'core': 100, 'memory_axi': 125, 'shell': 250}
         and bool(identity['clock_scope']), 'Changed released Qwen clock recipe')
    for key, member in (('loaded_image_record_sha256', 'loaded_image'),
                        ('model_ready_record_sha256', 'model_ready'),
                        ('clock_observation_sha256', 'clock_observation'),
                        ('host_source_sha256', 'host_source'),
                        ('host_protocol_sha256', 'host_protocol'),
                        ('host_binary_sha256', 'host_binary')):
        need(digest(raw(review[member])) == identity[key], 'Changed Qwen identity source: ' + key)
    loaded = raw(review['loaded_image'])
    need(loaded == raw(review['after_image']) and identity['fpga_image_global_id'].encode() in loaded
         and b'loaded' in loaded and b' ok ' in loaded, 'Published Qwen image differs across trials')
    ready = json.loads(raw(review['model_ready']).decode().splitlines()[-1])
    need(ready['model_ready'] is True and ready['image_bytes'] == reference['model_image_bytes'],
         'Qwen model upload did not complete')
    build = obj(review['host_build'])
    need(build['actual_exit'] == 0 and build['binary_sha256'] == identity['host_binary_sha256'],
         'Qwen host build differs')
    source = raw(review['host_source']).decode()
    edits = [
        ('okay(client.command(Operation::Clear));uint64_t prompt_start=transport.now_ns();',
         'Result clear_reply=client.command(Operation::Clear);okay(clear_reply);\n'
         '        std::cerr<<"{\\"matched_benchmark_clear\\":true,\\"id\\":"<<clear_reply.id<<",\\"status\\":"<<clear_reply.status<<",\\"elapsed_ns\\":"<<clear_reply.elapsed_ns<<"}\\n";\n'
         '        uint64_t prompt_start=transport.now_ns();'),
        ('Result r=client.command(Operation::Step);okay(r);',
         'Result r=client.command(Operation::Step);okay(r);const uint64_t validated_reply_ns=transport.now_ns();'),
        ('transport.now_ns()-generation_start', 'validated_reply_ns-generation_start'),
        ('transport.now_ns()-prompt_start', 'validated_reply_ns-prompt_start')]
    for before, after in reversed(edits):
        need(source.count(after) == 1, 'Qwen host instrumentation changed')
        source = source.replace(after, before)
    parent = 'demos/' + row['id'] + '/host/'
    need(source.encode() == read(root, parent + 'qwen_host.cpp')
         and raw(review['host_protocol']) == read(root, parent + 'qwen_host_protocol.h'),
         'Qwen benchmark host differs beyond the declared timestamp/CLEAR instrumentation')
    need(len(capture['cases']) == len(review['trials']) == 2, 'Missing Qwen raw trial pair')
    intervals = []
    for case, record in zip(capture['cases'], review['trials']):
        need(record['name'] == case['name'], 'Qwen raw trial ordering differs')
        log = raw(record['stdout'])
        exit_record = obj(record['exit'])
        need(exit_record['actual_exit'] == 0 and exit_record['timed_out'] is False
             and exit_record['stdout_sha256'] == digest(log) == case['raw_capture_sha256'],
             'Qwen trial exit/capture identity differs')
        lines = log.decode().splitlines()
        need(len(lines) == 129, 'Qwen raw trial must contain CLEAR and 128 outputs')
        clear, rows = json.loads(lines[0]), [json.loads(x) for x in lines[1:]]
        need(clear['matched_benchmark_clear'] is True and clear['status'] == 0
             and clear['elapsed_ns'] > 0, 'Qwen pretrial CLEAR failed')
        need([r['index'] for r in rows] == list(range(128))
             and [r['token'] for r in rows] == case['generated_tokens']
             == case['expected_tokens'] == reference['expected_tokens'], 'Qwen raw/reference token IDs differ')
        need([r['generation_elapsed_ns'] / 1e9 for r in rows] == case['reply_elapsed_seconds']
             and [r['step_ns'] / 1e9 for r in rows[1:]] == case['cached_command_seconds']
             and rows[0]['step_ns'] / 1e9 == case['first_step_seconds'], 'Qwen raw/canonical timings differ')
        for previous, current in zip(rows, rows[1:]):
            need(current['generation_elapsed_ns'] - previous['generation_elapsed_ns'] >= current['step_ns'] > 0,
                 'Qwen reply interval shorter than STEP duration')
        offsets = {r['prompt_elapsed_ns'] - r['generation_elapsed_ns'] for r in rows}
        need(len(offsets) == 1 and next(iter(offsets)) > 0, 'Qwen generation clock origin differs')
        intervals.append(rows[-1]['generation_elapsed_ns'] - rows[0]['generation_elapsed_ns'])
    return {'passed': True, 'compared_tokens': 256, 'cached_host_ns': sum(intervals),
            'cached_tokens_per_second': 254e9 / sum(intervals), 'hardware_access': False,
            'fresh_numerical_replay': False}

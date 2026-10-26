"""Generate bounded 8B acceptance vectors in software, not an FPGA benchmark.

Fixed prompts, exact candidate arithmetic, greedy output, and CLEAR/replay.
The longer prompt exercises prefill separately from cached token generation.
No hardware or cloud access occurs here.
"""
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'tools'))
from fixed_model_export import digest
from dense_qwen_reference import DenseQwenEngine


def main():
    import torch
    from tokenizers import Tokenizer
    torch.set_num_threads(8)
    torch.set_float32_matmul_precision('highest')
    lock = json.loads((HERE / 'source-lock.json').read_text())
    tokenizer_path = HERE / 'sources' / lock['revision'] / 'tokenizer.json'
    if digest(tokenizer_path) != lock['files']['tokenizer.json']['sha256']:
        raise ValueError('Changed pinned tokenizer')
    tokenizer = Tokenizer.from_file(str(tokenizer_path))
    chat = ('<|im_start|>user\nExplain what an FPGA is in two short sentences.'
            '<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n')
    long_text = ('A scientist built a small machine to help people learn about computers. '
                 'The machine could answer questions and tell stories. ') * 50
    cases = [
        dict(name='single-token-128-output', prompt_tokens=[9707], max_new_tokens=128, stop_at_eos=False),
        dict(name='chat-fpga', prompt_tokens=tokenizer.encode(chat, add_special_tokens=False).ids,
             max_new_tokens=64, stop_at_eos=True, formatted_prompt=chat),
        dict(name='512-token-prefill', prompt_tokens=tokenizer.encode(long_text, add_special_tokens=False).ids[:512],
             max_new_tokens=16, stop_at_eos=False),
    ]
    if len(cases[2]['prompt_tokens']) != 512:
        raise ValueError('Long prompt changed')
    output = HERE / 'runs' / ('hardware-vectors-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    output.mkdir()
    paths = [Path(__file__), HERE.parent / 'tools/dense_qwen_reference.py',
             HERE.parent / 'tools/model_geometry.py']
    for path in paths:
        shutil.copy2(path, output / path.name)
    record = dict(passed=False, scope=__doc__, device='cpu', threads=8,
                  tokenizer_sha256=digest(tokenizer_path), source_sha256={p.name: digest(p) for p in paths},
                  numerical_parent_equality_claimed=False, fpga_executed=False, cases=[])
    def save(name):
        (output / name).write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    save('STARTED.json')
    print('Evidence: ' + str(output), flush=True)
    try:
        engine = DenseQwenEngine(HERE / 'runs/model-export-20261019', 'cpu')
        record['image_sha256'] = engine.image.sha256
        if engine.image.sha256 != 'a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833':
            raise ValueError('Different 8B candidate image')
        machine = engine.token_machine()
        for case in cases:
            machine.clear()
            for token in case['prompt_tokens']:
                machine.append(token)
            row = dict(case, tokens=[], software_step_seconds=[])
            record['cases'].append(row)
            for index in range(case['max_new_tokens']):
                start = time.monotonic()
                token = machine.step()
                row['tokens'].append(token)
                row['software_step_seconds'].append(time.monotonic() - start)
                if index % 8 == 0:
                    print(json.dumps(dict(case=case['name'], outputs=index + 1,
                                          suffix=tokenizer.decode(row['tokens'][-24:]))), flush=True)
                    save('PROGRESS.json')
                if case['stop_at_eos'] and token in (151643, 151645):
                    break
            row['text'] = tokenizer.decode(row['tokens'])
            machine.clear()
            for token in case['prompt_tokens']:
                machine.append(token)
            row['clear_replay_tokens'] = [machine.step() for _ in range(3)]
            if row['clear_replay_tokens'] != row['tokens'][:3]:
                raise ValueError('CLEAR/replay mismatch: ' + case['name'])
            row['passed'] = True
            save('PROGRESS.json')
        record.update(passed=True, completed_utc=datetime.now(timezone.utc).isoformat())
        save('FINISHED.json')
        print(json.dumps(dict(passed=True, cases=[dict(name=c['name'], outputs=len(c['tokens']))
                                                for c in record['cases']])), flush=True)
    except BaseException as error:
        record['error'] = repr(error)
        save('FAILED.json')
        raise


if __name__ == '__main__':
    main()

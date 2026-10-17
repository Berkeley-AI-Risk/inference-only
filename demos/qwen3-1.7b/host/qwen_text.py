"""Text/JSON adapter for qwen_host; never loads weights or runs model inference."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

MODEL_ID = 'Qwen/Qwen3-1.7B'
REVISION = '70d244cc86ccca08cf5af4e1e306ecf908b1ad5e'
TOKENIZER_BYTES = 11422654
TOKENIZER_SHA256 = 'aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4'
CONTEXT_LIMIT = 32768
VOCAB_SIZE = 151936
END_TOKENS = {151643, 151645}
MAX_PROMPT_BYTES = 16 * 1024 * 1024
MAX_REPLY_BYTES = 16384
STEP_FIELDS = {'index', 'token', 'step_ns', 'generation_elapsed_ns', 'prompt_elapsed_ns'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_tokenizer(path):
    """Parse the same verified bytes that were hashed; no remote code/downloads."""
    with Path(path).open('rb') as source:
        data = source.read(TOKENIZER_BYTES + 1)
    require(len(data) == TOKENIZER_BYTES and hashlib.sha256(data).hexdigest() == TOKENIZER_SHA256,
            'Tokenizer does not match the fixed Qwen3-1.7B revision')
    from tokenizers import Tokenizer
    return Tokenizer.from_str(data.decode('utf-8'))


def format_prompt(text, raw=False):
    require(isinstance(text, str) and bool(text), 'Prompt must not be empty')
    require(len(text.encode('utf-8')) <= MAX_PROMPT_BYTES, 'Prompt exceeds the text-input byte limit')
    if raw:
        return text
    # The pinned upstream template's single-user, no-tools, non-thinking case.
    # No executable template, model code, or host-side inference is needed.
    return '<|im_start|>user\n' + text + '<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'


def encode_prompt(tokenizer, text, count, raw=False):
    require(type(count) is int and count > 0, 'Output count must be positive')
    ids = tokenizer.encode(format_prompt(text, raw), add_special_tokens=False).ids
    require(ids and all(type(t) is int and 0 <= t < VOCAB_SIZE for t in ids), 'Invalid prompt token ID')
    require(len(ids) + count <= CONTEXT_LIMIT, 'Prompt plus output exceeds the fixed token tape')
    return ids


def command_for(client, slot, ids, count, stop_at_end=False):
    require(type(slot) is int and slot >= 0, 'Slot must be a nonnegative integer')
    return [str(Path(client).resolve()), '--slot', str(slot),
            'generate-until-end' if stop_at_end else 'generate', ','.join(map(str, ids)), str(count)]


def parse_step(line, index, previous=None):
    require(len(line.encode('utf-8')) <= MAX_REPLY_BYTES, 'Oversized host-client reply')
    def unique_fields(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'Duplicate host-client reply field: ' + key)
            result[key] = value
        return result
    step = json.loads(line, object_pairs_hook=unique_fields)
    require(isinstance(step, dict) and set(step) == STEP_FIELDS, 'Unexpected host-client reply fields')
    require(all(type(v) is int and v >= 0 for v in step.values()), 'Reply fields must be unsigned integers')
    require(step['index'] == index and step['token'] < VOCAB_SIZE, 'Out-of-order reply or invalid token ID')
    require(0 < step['step_ns'] <= step['generation_elapsed_ns'] <= step['prompt_elapsed_ns'],
            'Inconsistent host-client timing')
    if previous is not None:
        require(step['generation_elapsed_ns'] > previous['generation_elapsed_ns']
                and step['prompt_elapsed_ns'] > previous['prompt_elapsed_ns'], 'Host-client timing went backwards')
    return step


def stream_client(command, tokenizer, count, stop_at_end=False):
    """Run exactly one existing generate transaction, with one client-held lock.

    The child provides all generated IDs and timings. This function has no
    simulated inference fallback. Only this owned child is stopped on error.
    """
    child = subprocess.Popen(command, stdout=subprocess.PIPE, text=True, encoding='utf-8',
                             errors='strict', bufsize=1, shell=False)
    tokens = []
    previous = None
    try:
        while True:
            line = child.stdout.readline(MAX_REPLY_BYTES + 1)
            if not line:
                break
            require(not (stop_at_end and tokens and tokens[-1] in END_TOKENS),
                    'Host client continued after an end-of-response marker')
            require(len(tokens) < count, 'Host client returned more tokens than requested')
            step = parse_step(line, len(tokens), previous)
            require(tokenizer.id_to_token(step['token']) is not None,
                    'Returned token ID has no spelling in the fixed tokenizer: ' + str(step['token']))
            tokens.append(step['token'])
            previous = step
            # Decode the WHOLE prefix: a UTF-8 character can span token IDs.
            # JSON consumers replace text rather than concatenate each field.
            yield {**step, 'text': tokenizer.decode(tokens, skip_special_tokens=stop_at_end),
                   'end_marker': step['token'] in END_TOKENS}
        code = child.wait(timeout=5)
        require(code == 0, 'Host client failed with exit code ' + str(code))
        require(len(tokens) == count or (stop_at_end and tokens and tokens[-1] in END_TOKENS),
                'Host client ended before the requested token count without an end marker')
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)
        child.stdout.close()


def console_text(text, final=False):
    # Hold a trailing partial UTF-8 character until another ID arrives. An
    # actual trailing replacement character is emitted on final completion.
    if not final:
        text = text.rstrip('\ufffd')
    # Do not let generated terminal-control sequences operate the terminal.
    return ''.join('\\x%02x' % ord(c) if (ord(c) < 32 and c not in '\n\t') or 127 <= ord(c) < 160
                   else c for c in text)


def summarize(steps, requested=None):
    require(bool(steps), 'No generated tokens to summarize')
    first, last = steps[0], steps[-1]
    decode_ns = last['generation_elapsed_ns'] - first['generation_elapsed_ns']
    return {'event': 'summary', 'generated_tokens': len(steps),
            'fixed_count_completed': len(steps) == requested if requested is not None else None,
            'first_token_seconds': first['prompt_elapsed_ns'] / 1e9,
            'decode_tokens_per_second_after_first': (len(steps) - 1) * 1e9 / decode_ns if len(steps) > 1 else None,
            'end_marker_seen': any(s['end_marker'] for s in steps),
            'timing_source': 'qwen_host wall clock; excludes model loading, CLEAR and text tokenization'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tokenizer', type=Path, default=Path(__file__).with_name('tokenizer.json'))
    parser.add_argument('--host-client', type=Path, default=Path(__file__).with_name('qwen_host'))
    parser.add_argument('--slot', type=int, default=0)
    prompts = parser.add_mutually_exclusive_group(required=True)
    prompts.add_argument('--prompt')
    prompts.add_argument('--prompt-file', type=Path)
    parser.add_argument('--count', type=int, default=32, help='Fixed number of STEPs; does not stop at an end marker')
    parser.add_argument('--raw', action='store_true', help='Raw completion instead of a single-user non-thinking chat prompt')
    parser.add_argument('--stop-at-end', action='store_true', help='Stop at the first end marker; count becomes a maximum')
    parser.add_argument('--json', action='store_true', help='Stream token IDs, full decoded prefix and client timings as JSON lines')
    parser.add_argument('--dry-run', action='store_true', help='Print token IDs/command without starting the client or touching a device')
    args = parser.parse_args(argv)
    if args.prompt_file is not None:
        with args.prompt_file.open('rb') as source:
            data = source.read(MAX_PROMPT_BYTES + 1)
        require(len(data) <= MAX_PROMPT_BYTES, 'Prompt exceeds the text-input byte limit')
        prompt = data.decode('utf-8')
    else:
        prompt = args.prompt
    tokenizer = load_tokenizer(args.tokenizer)
    ids = encode_prompt(tokenizer, prompt, args.count, args.raw)
    command = command_for(args.host_client, args.slot, ids, args.count, args.stop_at_end)
    metadata = {'event': 'prompt', 'model_id': MODEL_ID, 'revision': REVISION,
                'format': 'raw' if args.raw else 'single-user non-thinking chat',
                'prompt_tokens': len(ids), 'requested_output_tokens': args.count,
                'stop_at_end_marker': args.stop_at_end, 'tokenizer_sha256': TOKENIZER_SHA256}
    if args.dry_run:
        print(json.dumps({**metadata, 'dry_run': True, 'device_access': False,
                          'token_ids': ids, 'client_command': command}, ensure_ascii=True))
        return 0
    if args.json:
        print(json.dumps(metadata), flush=True)
    else:
        mode = 'maximum STEPs; stop at end marker' if args.stop_at_end else 'fixed STEPs (including any end markers)'
        print(f"{len(ids)} prompt tokens; requesting {args.count} {mode}.", file=sys.stderr)
    steps = []
    emitted = ''
    replies = stream_client(command, tokenizer, args.count, args.stop_at_end)
    try:
        for step in replies:
            steps.append(step)
            if args.json:
                print(json.dumps({'event': 'token', **step}, ensure_ascii=True), flush=True)
            else:
                text = console_text(step['text'])
                require(text.startswith(emitted), 'Decoded text changed an already displayed prefix; use --json')
                print(text[len(emitted):], end='', flush=True)
                emitted = text
    finally:
        replies.close()
    summary = summarize(steps, args.count)
    if args.json:
        print(json.dumps(summary), flush=True)
    else:
        text = console_text(steps[-1]['text'], final=True)
        require(text.startswith(emitted), 'Final text changed an already displayed prefix; use --json')
        print(text[len(emitted):], flush=True)
        rate = summary['decode_tokens_per_second_after_first']
        rate_text = 'not measured (one output token)' if rate is None else f'{rate:.3f} tokens/s'
        print(f"First token: {summary['first_token_seconds']:.3f} s; subsequent decode: {rate_text}.", file=sys.stderr)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print('\nInterrupted. A submitted FPGA operation may still finish; no automatic reset was sent.', file=sys.stderr)
        raise SystemExit(130)
    except (OSError, ValueError, subprocess.SubprocessError, ImportError) as error:
        print('Error: ' + str(error), file=sys.stderr)
        raise SystemExit(1)

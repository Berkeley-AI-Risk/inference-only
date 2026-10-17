"""Offline runtime tests. Fixture streams are not model or FPGA tests."""
import json
import io
from pathlib import Path
import shlex
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

from qwen_backend import Controller, Result, check_ready, command, load_connection
from check_hardware import expected_prefix
from qwen_text import command_for, encode_prompt, format_prompt, load_tokenizer, parse_step, stream_client, summarize

CONFIG = dict(host_client='/opt/qwen/host/qwen_host', slot=0, ssh_argv=[], sudo=False)


def step(index=0):
    return dict(index=index, token=25, step_ns=100, generation_elapsed_ns=1000+index*200,
                prompt_elapsed_ns=2000+index*200, text=':'*(index+1), end_marker=False)


class Tokenizer:
    def encode(self, text, add_special_tokens=False):
        return type('Encoding', (), dict(ids=[9707]))()


class Tests(unittest.TestCase):
    def test_default_chat(self):
        self.assertEqual(format_prompt('Hi'), '<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n')

    def test_raw(self):
        self.assertEqual(format_prompt('Hello', raw=True), 'Hello')

    def test_pinned_tokenizer(self):
        tokenizer = load_tokenizer(Path(__file__).with_name('tokenizer.json'))
        self.assertEqual(encode_prompt(tokenizer, 'Hello', 3, raw=True), [9707])
        self.assertEqual(tokenizer.decode([25, 358, 1184]), ': I need')

    def test_bad_tokenizer(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'tokenizer.json'; p.write_text('{}')
            with self.assertRaises(ValueError): load_tokenizer(p)

    def test_reply_validation(self):
        s = step(); s.pop('text'); s.pop('end_marker')
        self.assertEqual(parse_step(json.dumps(s), 0), s)
        for key, value in [('index', 1), ('token', 151936), ('step_ns', 0), ('prompt_elapsed_ns', 2)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                parse_step(json.dumps({**s, key:value}), 0)

    def test_duplicates(self):
        with self.assertRaises(ValueError): parse_step('{"index":0,"index":0}', 0)

    def test_metrics(self):
        result = Result(steps=[step(0), step(1)])
        self.assertEqual(result.streaming_tps, 5e6)
        self.assertEqual(result.first_token_seconds, 2e-6)
        self.assertIsNone(summarize([step()])['decode_tokens_per_second_after_first'])
        self.assertFalse(summarize([step()], requested=3)['fixed_count_completed'])

    def read_fixture_stream(self, tokens, count, stop_at_end):
        rows = []
        for i, token in enumerate(tokens):
            row = step(i)
            row.pop('text'); row.pop('end_marker'); row['token'] = token
            rows.append(json.dumps(row))
        child = Mock(stdout=io.StringIO('\n'.join(rows)+'\n'))
        child.wait.return_value = 0
        child.poll.return_value = 0
        tokenizer = load_tokenizer(Path(__file__).with_name('tokenizer.json'))
        with patch('qwen_text.subprocess.Popen', return_value=child):
            return list(stream_client(['fixture-not-executed'], tokenizer, count, stop_at_end))

    def test_stop_at_end_and_hide_marker(self):
        rows = self.read_fixture_stream([25, 151645], 64, True)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[-1]['text'], ':')
        self.assertTrue(rows[-1]['end_marker'])

    def test_stop_at_end_requires_marker_or_limit(self):
        with self.assertRaises(ValueError): self.read_fixture_stream([25], 64, True)
        self.assertEqual(len(self.read_fixture_stream([25], 1, True)), 1)

    def test_reject_output_after_marker(self):
        with self.assertRaises(ValueError): self.read_fixture_stream([25, 151645, 358], 64, True)

    def test_fixed_length_benchmark_unchanged(self):
        rows = self.read_fixture_stream([25, 151645, 358], 3, False)
        self.assertEqual(len(rows), 3)
        self.assertIn('<|im_end|>', rows[-1]['text'])

    def test_reference_prefix_for_chat_hardware_check(self):
        tokens = [25, 151645, 358, 151643]
        self.assertEqual(expected_prefix(tokens, True), [25, 151645])
        self.assertEqual(expected_prefix(tokens, False), tokens)
        self.assertEqual(expected_prefix([25, 151643], True), [25, 151643])
        self.assertEqual(expected_prefix([25, 358], True), [25, 358])

    def test_chat_command(self):
        argv = command_for('/opt/qwen/host/qwen_host', 0, [9707], 64, True)
        self.assertEqual(argv[-3:], ['generate-until-end', '9707', '64'])
        self.assertEqual(command(CONFIG, 'generate-until-end', [9707], 64)[-3:], argv[-3:])

    def test_ssh_quoting(self):
        cfg = {**CONFIG, 'host_client': '/opt/qwen demo/qwen_host', 'ssh_argv':['ssh', '-T', 'qwen-host'], 'sudo':True}
        argv = command(cfg, 'generate', [9707], 3)
        self.assertEqual(shlex.split(argv[-1]), ['sudo','-n','/opt/qwen demo/qwen_host','--slot','0','generate','9707','3'])

    def test_no_extra_browser_operations(self):
        for action in ('load', 'reset', 'shell', 'clear'):
            with self.assertRaises(ValueError): command(CONFIG, action)

    def test_bad_tokens(self):
        for ids in ([True], [151936], [-1], ['1; touch /tmp/x']):
            with self.assertRaises(ValueError): command(CONFIG, 'generate', ids, 1)

    def test_config_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'connection.json'
            for cfg in ({**CONFIG,'slot':True}, {**CONFIG,'host_client':'qwen_host'}, {**CONFIG,'unknown':1}):
                p.write_text(json.dumps(cfg))
                with self.assertRaises(ValueError): load_connection(p)
            p.write_text(json.dumps(CONFIG)); self.assertEqual(load_connection(p), CONFIG)

    def test_readiness(self):
        with patch('qwen_backend.subprocess.run') as run:
            run.return_value.stdout = '{"flags":19,"credits":0,"received_bytes":2354380800}'
            check_ready(CONFIG)
            run.return_value.stdout = '{"flags":3,"credits":0,"received_bytes":0}'
            with self.assertRaises(RuntimeError): check_ready(CONFIG)

    def test_controller_and_privacy(self):
        started, release = threading.Event(), threading.Event()
        def stream(*args, **kwargs):
            started.set(); release.wait(5)
            yield step(0); yield step(1)
        c = Controller(CONFIG, Tokenizer(), stream, lambda _:None)
        c.start('owner', 'private prompt', 2)
        self.assertTrue(started.wait(5))
        self.assertTrue(c.busy())
        other = c.snapshot('other'); self.assertEqual(other.prompt, ''); self.assertEqual(other.steps, [])
        with self.assertRaises(RuntimeError): c.start('other', 'prompt', 1)
        release.set(); c.worker.join(5)
        self.assertEqual(c.snapshot('owner').state, 'complete')
        self.assertEqual(c.snapshot('owner').text, '::')
        self.assertEqual(c.snapshot('other').job_id, '')

    def test_failure_blocks_retry(self):
        def ready(_): raise ValueError('Not ready')
        c = Controller(CONFIG, Tokenizer(), ready=ready)
        c.start('a', 'prompt', 1); c.worker.join(5)
        self.assertEqual(c.snapshot('a').state, 'error')
        with self.assertRaises(RuntimeError): c.start('a', 'prompt', 1)

    def test_missing_executable_does_not_expose_path(self):
        def ready(_): raise FileNotFoundError('/private/operator/key-or-client')
        c = Controller(CONFIG, Tokenizer(), ready=ready)
        c.start('a', 'prompt', 1); c.worker.join(5)
        self.assertNotIn('/private/', c.snapshot('a').error)
        self.assertTrue(c.needs_check)

    def test_bounds(self):
        c = Controller(CONFIG, Tokenizer(), ready=lambda _:None)
        for count in (0, 129, True):
            with self.assertRaises(ValueError): c.start('a', 'prompt', count)


if __name__ == '__main__': unittest.main()

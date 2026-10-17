"""Single-owner FPGA stream controller; tokenizer only, no software inference."""
from copy import deepcopy
from dataclasses import dataclass, field
import json
import os
from pathlib import Path
import shlex
import subprocess
import threading
import time
import uuid

from qwen_text import encode_prompt, load_tokenizer, stream_client, summarize

MAX_PROMPT = 512
MAX_NEW = 128
ACTIVE = {'checking FPGA', 'processing prompt', 'generating'}


@dataclass
class Result:
    owner: str = ''
    job_id: str = ''
    state: str = 'idle'
    prompt: str = ''
    prompt_tokens: list = field(default_factory=list)
    steps: list = field(default_factory=list)
    text: str = ''
    requested: int = 0
    raw: bool = False
    error: str = ''
    stop_reason: str = ''
    ui_first_token_seconds: float | None = None

    @property
    def first_token_seconds(self):
        return self.steps[0]['prompt_elapsed_ns'] / 1e9 if self.steps else None

    @property
    def streaming_tps(self):
        return summarize(self.steps)['decode_tokens_per_second_after_first'] if self.steps else None


def load_connection(path):
    config = json.loads(Path(path).read_text())
    allowed = {'host_client', 'slot', 'ssh_argv', 'sudo'}
    if not isinstance(config, dict) or not set(config) <= allowed:
        raise ValueError('Unexpected connection settings')
    client = config.get('host_client')
    if not isinstance(client, str) or not client.startswith('/') or '\0' in client or '\n' in client:
        raise ValueError('Set host_client to its absolute installed path')
    slot = config.get('slot', 0)
    if type(slot) is not int or not 0 <= slot <= 7:
        raise ValueError('Invalid FPGA slot')
    ssh = config.get('ssh_argv', [])
    if not isinstance(ssh, list) or any(not isinstance(x, str) or not x or '\0' in x for x in ssh):
        raise ValueError('ssh_argv must be an operator-owned argument list')
    if type(config.get('sudo', False)) is not bool:
        raise ValueError('sudo must be true or false')
    return dict(host_client=client, slot=slot, ssh_argv=ssh, sudo=config.get('sudo', False))


def command(config, action, ids=None, count=None):
    if action not in {'status', 'generate', 'generate-until-end'}:
        raise ValueError('The browser backend only checks status or generates tokens')
    argv = (['sudo', '-n'] if config['sudo'] else []) + [config['host_client'], '--slot', str(config['slot']), action]
    if action in {'generate', 'generate-until-end'}:
        if not ids or type(count) is not int or not 1 <= count <= MAX_NEW or any(type(t) is not int or not 0 <= t < 151936 for t in ids):
            raise ValueError('Invalid numeric generation request')
        argv += [','.join(map(str, ids)), str(count)]
    # Only deployment configuration selects a destination or executable.
    # Prompt text never becomes a shell command: only validated decimal IDs.
    return config['ssh_argv'] + [shlex.join(argv)] if config['ssh_argv'] else argv


def check_ready(config):
    result = subprocess.run(command(config, 'status'), capture_output=True, text=True,
                            timeout=30, check=True, shell=False)
    if len(result.stdout) > 16384:
        raise ValueError('Oversized status reply')
    status = json.loads(result.stdout)
    if set(status) != {'flags', 'credits', 'received_bytes'} or any(type(v) is not int for v in status.values()):
        raise ValueError('Invalid status reply')
    if not status['flags'] & 16 or status['flags'] & 0xe0 or status['received_bytes'] != 2354380800:
        raise RuntimeError('The fixed model is not ready; follow INSTALL.md. No reload attempted.')


class Controller:
    def __init__(self, config=None, tokenizer=None, stream=None, ready=None, stop_at_end=True):
        if config is None:
            path = os.environ.get('QWEN_CONNECTION')
            if not path:
                raise RuntimeError('Set QWEN_CONNECTION to your private connection JSON; see BROWSER.md')
            config = load_connection(path)
        self.config = config
        self.tokenizer = tokenizer if tokenizer is not None else load_tokenizer(Path(__file__).with_name('tokenizer.json'))
        self.stream = stream if stream is not None else stream_client
        self.ready = ready if ready is not None else check_ready
        self.lock = threading.Lock()
        self.result = Result()
        self.needs_check = False
        self.worker = None
        self.stop_at_end = stop_at_end

    def busy(self):
        with self.lock:
            return self.result.state in ACTIVE

    def snapshot(self, owner):
        with self.lock:
            if self.result.owner and self.result.owner != owner:
                return Result(state='busy in another tab' if self.result.state in ACTIVE else 'idle')
            return deepcopy(self.result)

    def start(self, owner, prompt, count, raw=False):
        if not owner or type(count) is not int or not 1 <= count <= MAX_NEW or type(raw) is not bool:
            raise ValueError('Invalid request')
        ids = encode_prompt(self.tokenizer, prompt, count, raw)
        if len(ids) > MAX_PROMPT:
            raise ValueError(f'This browser demo allows at most {MAX_PROMPT} prompt tokens, including chat formatting')
        with self.lock:
            if self.result.state in ACTIVE:
                raise RuntimeError('The FPGA is already in use')
            if self.needs_check:
                raise RuntimeError('A previous request failed. Check the FPGA and restart this app; no automatic retry.')
            self.result = Result(owner=owner, job_id=uuid.uuid4().hex, state='checking FPGA',
                                 prompt=prompt, prompt_tokens=ids, requested=count, raw=raw)
            self.worker = threading.Thread(target=self._run, daemon=True)
            self.worker.start()

    def _run(self):
        start = time.monotonic()
        replies = None
        try:
            self.ready(self.config)
            with self.lock:
                ids, count = list(self.result.prompt_tokens), self.result.requested
                self.result.state = 'processing prompt'
            action = 'generate-until-end' if self.stop_at_end else 'generate'
            replies = self.stream(command(self.config, action, ids, count), self.tokenizer, count,
                                  stop_at_end=self.stop_at_end)
            for step in replies:
                with self.lock:
                    if not self.result.steps:
                        self.result.ui_first_token_seconds = time.monotonic() - start
                    self.result.steps.append(step)
                    self.result.text = step['text']
                    self.result.state = 'generating'
            with self.lock:
                self.result.stop_reason = ('end of response' if self.stop_at_end and self.result.steps
                                           and self.result.steps[-1]['end_marker'] else 'token limit')
                self.result.state = 'complete'
        except Exception as error:
            with self.lock:
                # Do not expose an SSH key path/host/command in the browser.
                self.result.error = ('FPGA connection or client failed; check the local terminal.'
                                     if isinstance(error, (OSError, subprocess.SubprocessError)) else str(error))
                self.result.state = 'error'
                self.needs_check = True
        finally:
            if replies is not None:
                replies.close()

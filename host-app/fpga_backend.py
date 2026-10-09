"""Local, fixed-UART FPGA controller. No model execution or programming API."""
from __future__ import annotations

import atexit
from contextlib import contextmanager
import copy
from dataclasses import dataclass, field
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import select
import stat
import threading
import time
import uuid

import runtime_profile

APP = Path(__file__).resolve().parent
TOKENIZER_SHA = '01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51'
IMAGE_SHA = '5a5b6788ea0d5b07d25614e91f2950c0c3a7b3cf49f8e225f2dcaf9e76ac8c2a'
VOCAB_SIZE, EOS, MAX_PROMPT, MAX_NEW, DEMO_CAP = 4019, 1, 128, 128, 256
ACTIVE = {'connecting', 'loading prompt', 'generating', 'clearing'}
BACKEND_SHA = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def utc() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def pinned_module(name: str, path: Path, digest: str):
    if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError('Changed pinned UART helper: ' + path.name)
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Tokenizer:
    def __init__(self):
        from tokenizers import Tokenizer as RustTokenizer
        path = APP / 'assets/tokenizer.json'
        data = path.read_bytes()
        if path.is_symlink() or len(data) != 86463 or hashlib.sha256(data).hexdigest() != TOKENIZER_SHA:
            raise RuntimeError('The fixed model tokenizer is missing or has changed.')
        self.native = RustTokenizer.from_str(data.decode('utf-8'))
        if self.native.get_vocab_size() != VOCAB_SIZE:
            raise RuntimeError('Wrong tokenizer vocabulary.')

    def encode(self, prompt: str) -> list[int]:
        if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 4000 or '\x00' in prompt:
            raise ValueError('Enter a nonempty story beginning (at most 4,000 characters).')
        # The upstream postprocessor adds EOS to finished stories. A prompt
        # is an UNFINISHED story: do not append that special token here.
        tokens = self.native.encode(prompt, add_special_tokens=False).ids
        if not 1 <= len(tokens) <= MAX_PROMPT:
            raise ValueError(f'This first app demo accepts 1–{MAX_PROMPT} prompt tokens; got {len(tokens)}.')
        if EOS in tokens:
            raise ValueError('Do not put [EOS] in an unfinished prompt.')
        return tokens

    def decode(self, tokens: list[int]) -> str:
        return self.native.decode([x for x in tokens if x != EOS], skip_special_tokens=False)


class BoardError(RuntimeError):
    pass


class LiveUART:
    """Own one physical UART exclusively, preserving every received byte."""
    def __init__(self, observe):
        self.client = pinned_module('fpga_console_uart', APP / 'token_machine_uart.py',
            '00d18e9411d52f7d7414b96cbf28d29db38d1c5008705dfb4194f268cbb11cbf')
        self.reader = pinned_module('fpga_console_strict_channel', APP / 'uart_channel.py',
            'b56f591d546bbc55ad0b8de3d6a5aa179206a3b5c813a6da1ce86aca4a2e3c0e')
        self.observe = observe
        self.session = None
        self.channel = None
        self.profile = None

    def _deployment(self):
        return runtime_profile.load_checked()

    def __enter__(self):
        profile = self._deployment()
        self.observe({'event': 'deployment_guard', 'image_sha256': profile['image_sha256'],
            'variant': profile.get('variant', 'baseline'),
            'build_receipt_sha256': profile['build_receipt_sha256'],
            'hardware_configuration_not_independently_attested': True})
        self.session = self.client.TokenMachineSession(profile['device']['path'], timeout_seconds=120, not_ready_retries=0)
        self.session.open()
        try:
            runtime_profile.check_open_device(self.session.fd, profile['device'])
            self.channel = self.reader.StrictChannel(self.session, self.client, self.observe)
            event = self.channel.next(1.0)
            if event is not None or self.channel.pending:
                raise BoardError('Unexpected startup data or a latched FPGA fault. No command was sent. See the local log.')
        except BaseException as error:
            self.session.close()
            if isinstance(error, Exception):
                raise BoardError('FPGA startup check failed; have the board checked. ' + str(error)) from error
            raise
        self.profile = profile
        return self

    def resume(self, observe):
        """Reuse only an unchanged, idle connection after acknowledged CLEAR.

        Do not flush or silently consume late bytes. Even a partial frame or
        disconnected descriptor makes this session unusable. The controller
        closes it and latches an error instead of retrying a command.
        """
        self.observe = observe
        self.channel.observe = observe
        try:
            profile = self._deployment()
            if profile != self.profile:
                raise BoardError('The board profile changed while the USB connection was retained.')
            runtime_profile.check_open_device(self.session.fd, profile['device'])
            ready, _, _ = select.select((self.session.fd,), (), (), 0)
            if self.channel.pending or ready:
                raise BoardError('Unexpected idle UART data or disconnect. No command was sent.')
            observe({'event': 'connection_reused', 'image_sha256': profile['image_sha256'],
                'variant': profile.get('variant', 'baseline'),
                'previous_run_ended_with_acknowledged_clear': True,
                'hardware_configuration_not_independently_attested': True})
        except Exception as error:
            raise BoardError('FPGA connection reuse failed; have the board checked. ' + str(error)) from error

    def command(self, operation: str, token: int = 0) -> int | None:
        # The pinned request builder admits only APPEND / STEP / CLEAR and
        # validates the fixed vocabulary. There is no raw command UI/API.
        frame = self.client.request_frame(operation, token)
        self.channel.send(frame, operation)
        event = self.channel.next(120 if operation == 'step' else 10)
        if event is None:
            raise BoardError(f'FPGA {operation.upper()} timed out. No retry or automatic reset was attempted.')
        if event['kind'] != 'normal' or event['response'] != self.client.EXPECTED_RESULTS[operation]:
            raise BoardError('Unexpected or rejected FPGA response. Generation stopped; see the local log.')
        result = event['token']
        if operation == 'step':
            if not 0 <= result < VOCAB_SIZE:
                raise BoardError('FPGA token is outside the fixed vocabulary.')
            return result
        if result != 0:
            raise BoardError('Noncanonical FPGA acknowledgment.')
        return None

    def __exit__(self, *args):
        self.session.close()


@dataclass
class Result:
    owner: str = ''
    job_id: str = ''
    state: str = 'idle'
    prompt: str = ''
    prompt_tokens: list[int] = field(default_factory=list)
    generated: list[int] = field(default_factory=list)
    step_seconds: list[float] = field(default_factory=list)
    arrivals_seconds: list[float] = field(default_factory=list)
    text: str = ''
    uploaded: int = 0
    requested: int = 0
    first_token_seconds: float | None = None
    elapsed_seconds: float = 0.0
    clear_acknowledged: bool = False
    stop_reason: str = ''
    error: str = ''
    log_path: str = ''
    started_utc: str = ''

    @property
    def streaming_tps(self) -> float | None:
        if len(self.arrivals_seconds) < 2:
            return None
        elapsed = self.arrivals_seconds[-1] - self.arrivals_seconds[0]
        return (len(self.arrivals_seconds) - 1) / elapsed if elapsed > 0 else None


class Controller:
    """One shared physical board; UI reruns never interrupt its serial worker."""
    def __init__(self, tokenizer=None, link_factory=LiveUART, logs=APP / 'logs',
                 keep_connection=None):
        self.tokenizer = tokenizer or Tokenizer()
        self.link_factory = link_factory
        self.logs = Path(logs)
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        self.result = Result()
        self.thread = None
        self.needs_board_check = False
        # Existing injected fixtures retain their per-run context behaviour.
        # Real hardware has one exclusive session for this cached controller.
        self.keep_connection = (link_factory is LiveUART if keep_connection is None
                                else bool(keep_connection))
        self._retained_link = None
        if self.keep_connection:
            atexit.register(self._close_retained)

    def connection_retained(self) -> bool:
        with self.lock:
            return self._retained_link is not None

    def _close_retained(self):
        with self.lock:
            link, self._retained_link = self._retained_link, None
            if link is not None:
                link.__exit__(None, None, None)

    def disconnect(self):
        """Release idle USB ownership; never interrupt or clear a live command."""
        with self.lock:
            if self.busy():
                raise RuntimeError('Finish or stop the active run before disconnecting USB.')
            self._close_retained()

    @contextmanager
    def _run_link(self, observe):
        with self.lock:
            link, self._retained_link = self._retained_link, None
        if link is None:
            link = self.link_factory(observe)
            # __enter__ owns cleanup if opening or its startup check fails.
            link.__enter__()
        else:
            try:
                link.resume(observe)
            except BaseException:
                link.__exit__(None, None, None)
                raise
        try:
            yield link
        except BaseException as error:
            link.__exit__(type(error), error, error.__traceback__)
            raise
        else:
            with self.lock:
                if self.keep_connection and self.result.clear_acknowledged and not self.stop_event.is_set():
                    self._retained_link = link
                else:
                    link.__exit__(None, None, None)

    def snapshot(self, owner: str) -> Result:
        with self.lock:
            if self.result.owner not in ('', owner):
                return Result(state='busy in another tab' if self.result.state in ACTIVE else 'idle')
            return copy.deepcopy(self.result)

    def busy(self) -> bool:
        with self.lock:
            return self.thread is not None and self.thread.is_alive()

    def start(self, owner: str, prompt: str, count: int):
        if type(count) is not int or not 1 <= count <= MAX_NEW:
            raise ValueError(f'Choose 1–{MAX_NEW} generated tokens.')
        tokens = self.tokenizer.encode(prompt)
        if len(tokens) + count > DEMO_CAP:
            raise ValueError(f'The interactive demo is limited to {DEMO_CAP} total tokens.')
        with self.lock:
            if self.busy():
                raise RuntimeError('The FPGA is already working. Stop that run or wait for it to finish.')
            if self.needs_board_check:
                raise RuntimeError('A previous command failed. The FPGA needs an engineering check; this app will not reset or reflash it.')
            self.stop_event.clear()
            self.result = Result(owner=owner, job_id=uuid.uuid4().hex, state='connecting',
                prompt=prompt, prompt_tokens=tokens, text=self.tokenizer.decode(tokens),
                requested=count, started_utc=utc())
            self.thread = threading.Thread(target=self._work, name='fpga-uart-worker', daemon=True)
            self.thread.start()

    def stop(self, owner: str):
        with self.lock:
            if self.result.owner != owner:
                raise RuntimeError('This tab does not own the active FPGA run.')
            self.stop_event.set()
            # Covers Stop arriving just after the worker parks a cleared link.
            # An in-flight link is never in this slot, so it is not interrupted.
            self._close_retained()

    def update(self, **values):
        with self.lock:
            for key, value in values.items():
                setattr(self.result, key, value)

    def _work(self):
        start = time.monotonic()
        commands_started = False
        try:
            self.logs.mkdir(parents=True, exist_ok=True, mode=0o700)
            log_path = self.logs / (self.result.job_id + '.jsonl')
            fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
            self.update(log_path=str(log_path))
            with os.fdopen(fd, 'w') as log:
                def observe(value):
                    item = dict(value, utc=utc(), monotonic_ns=time.monotonic_ns())
                    log.write(json.dumps(item, sort_keys=True) + '\n'); log.flush(); os.fsync(log.fileno())
                observe({'event':'run', 'prompt':self.result.prompt, 'tokens':self.result.prompt_tokens,
                    'tokenizer_sha256':TOKENIZER_SHA, 'backend_source_sha256':BACKEND_SHA,
                    'original_tested_baseline_image_sha256':IMAGE_SHA,
                    'hardware_configuration_not_independently_attested':True, 'software_inference':False})
                try:
                    with self._run_link(observe) as link:
                        def command(op, operand=0):
                            nonlocal commands_started
                            commands_started = True
                            began = time.monotonic()
                            token = link.command(op, operand)
                            seconds = time.monotonic() - began
                            observe({'event':'command_result', 'operation':op, 'operand':operand,
                                'token':token, 'seconds':seconds})
                            return token, seconds
                        command('clear')
                        self.update(state='loading prompt')
                        for index, token in enumerate(self.result.prompt_tokens):
                            if self.stop_event.is_set(): break
                            command('append', token)
                            self.update(uploaded=index + 1)
                        self.update(state='generating')
                        for _ in range(self.result.requested):
                            if self.stop_event.is_set():
                                self.update(stop_reason='Stopped by you')
                                break
                            token, seconds = command('step')
                            arrival = time.monotonic() - start
                            with self.lock:
                                self.result.generated.append(token)
                                self.result.step_seconds.append(seconds)
                                self.result.arrivals_seconds.append(arrival)
                                self.result.elapsed_seconds = arrival
                                self.result.first_token_seconds = self.result.arrivals_seconds[0]
                                self.result.text = self.tokenizer.decode(self.result.prompt_tokens + self.result.generated)
                            if token == EOS:
                                self.update(stop_reason='Model reached end of story')
                                break
                        if not self.result.stop_reason:
                            self.update(stop_reason='Requested token limit reached')
                        self.update(state='clearing')
                        command('clear')
                        self.update(clear_acknowledged=True)
                    self.update(state='stopped' if self.stop_event.is_set() else 'complete',
                        elapsed_seconds=time.monotonic() - start)
                    observe({'event':'finished', 'result':self.result.__dict__})
                except BaseException as error:
                    observe({'event':'error', 'type':type(error).__name__, 'error':str(error),
                        'no_automatic_retry_reset_or_reconfiguration':True})
                    raise
        except BaseException as error:
            self._close_retained()
            self.update(state='error', error=str(error), elapsed_seconds=time.monotonic() - start)
            # Failure after opening/command admission leaves state uncertain.
            # Do not issue cleanup CLEAR after such a failure or auto-retry.
            with self.lock:
                self.needs_board_check = commands_started or isinstance(error, BoardError)

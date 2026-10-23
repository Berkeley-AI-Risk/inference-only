"""Bounded seeded settings and qualification fixtures; no device access."""
import hashlib
import importlib.util
from pathlib import Path
import secrets
import sys

TEMPERATURES = ('0', '0.5', '1', '2')
SEED_A = 0x99aabbccddeeff001122334455667788
SEED_B = 0xfefdfcfbfaf9f8f70102030405060708
SEQUENCES = {1: (247, 130, 32), 2: (357, 3898, 104), 3: (3436, 4007, 141)}
CHANGED_FIRST = {1: 13, 2: 13, 3: 2}
CODEC_SHA256 = '6e2f5cf5310700888187d3d4d9af1921e2150adbe865773874bdbe7eaecc326a'
_path = Path(__file__).resolve().parent.parent / 'variants/seeded-sampling/tools/settings_codec.py'
if _path.is_symlink() or hashlib.sha256(_path.read_bytes()).hexdigest() != CODEC_SHA256:
    raise RuntimeError('The bounded settings codec changed.')
_spec = importlib.util.spec_from_file_location('_fpga_seeded_settings_codec', _path)
codec = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = codec
_spec.loader.exec_module(codec)


def temperature_code(temperature):
    return codec.temperature_code(temperature)


def run_seed(temperature, seed):
    """Return one seed per run; greedy ignores seeds and does not draw one."""
    if temperature_code(temperature) == 0:
        return None
    if seed is None or (isinstance(seed, str) and not seed.strip()):
        seed = secrets.randbits(128)
    elif isinstance(seed, str):
        try:
            seed = int(seed.strip(), 0)
        except ValueError as error:
            raise ValueError('Seed must be a decimal integer or 0x-prefixed hexadecimal.') from error
    return f'0x{codec.checked_integer(seed, 1 << 128, "seed"):032x}'


def decoder_client(released):
    """Per-session adapter for the unchanged strict UART channel."""
    class Validator:
        @staticmethod
        def _validate_response_token(kind, token):
            if kind == 0x83:
                if type(token) is not int or not 0 <= token <= 3:
                    raise ValueError('Unsupported acknowledged temperature')
                return
            released.TokenMachineSession._validate_response_token(kind, token)

    class Client:
        TokenMachineSession = Validator

        @staticmethod
        def decode_response(frame):
            response = codec.decode_response(frame)
            return response.kind, response.operand

    return Client


def qualification_plan():
    """45 bounded operations, including 19 independently pinned output IDs.

    Tuples are operation, operand, expected generated token, settings seed.
    CLEAR replay deliberately contains no SETTINGS between the two T=1 tapes.
    """
    plan = [('clear', 0, None, None), ('settings', 0, None, 0), ('append', 378, None, None)]
    plan.extend(('step', 0, token, None) for token in (200, 15, 103, 157))
    plan.append(('clear', 0, None, None))
    for code in (1, 2, 3):
        plan.extend((('settings', code, None, SEED_A), ('append', 378, None, None)))
        plan.extend(('step', 0, token, None) for token in SEQUENCES[code])
        plan.append(('clear', 0, None, None))
        if code == 2:
            plan.append(('append', 378, None, None))
            plan.extend(('step', 0, token, None) for token in SEQUENCES[code])
            plan.append(('clear', 0, None, None))
    for code in (1, 2, 3):
        plan.extend((('settings', code, None, SEED_B), ('append', 378, None, None),
                     ('step', 0, CHANGED_FIRST[code], None), ('clear', 0, None, None)))
    plan.extend((('settings', 0, None, 0), ('clear', 0, None, None)))
    return plan


def qualification_results():
    rows = []
    for operation, operand, token, seed in qualification_plan():
        row = dict(operation=operation, operand=operand, token=token)
        if operation == 'settings':
            row['seed'] = f'0x{seed:032x}'
        rows.append(row)
    return rows


def known_answer():
    return dict(protocol='seeded-sampling-v1', prompt_tokens=[378],
                greedy_generated_tokens=[200, 15, 103, 157],
                seed_a=f'0x{SEED_A:032x}', seed_b=f'0x{SEED_B:032x}',
                positive_generated_tokens={TEMPERATURES[code]: list(tokens) for code, tokens in SEQUENCES.items()},
                clear_replay_temperature='1', clear_replay_generated_tokens=[357, 3898, 104],
                changed_seed_first_tokens={TEMPERATURES[code]: token for code, token in CHANGED_FIRST.items()},
                initial_clear_acknowledged=True, final_clear_acknowledged=True,
                final_greedy_settings_acknowledged=True, exact_token_checks=19)

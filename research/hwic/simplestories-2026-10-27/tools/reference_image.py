#!/usr/bin/env python3
"""Reconstruct the selected FPGA's exact image directly from canonical Q0 ROMs.

This is a build-time utility, not a device command or a model-update service.
It imports the packaged, pinned numerical loader; no development-archive
exporter, old build directory, vendor library or FPGA connection is needed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

if not sys.flags.isolated or not sys.flags.dont_write_bytecode or sys.flags.optimize:
    raise SystemExit('Run with the reference environment Python -I -B (without -O).')

IMAGE_SHA256 = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
ORACLE_SHA256 = '9b048a8e8b82faba3d21fd6b259aa1c23d91f04662fe2734fc109602777b4a74'
IMAGE_BYTES = 7_265_984
NORM_ROM = 'fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh'
EXP_ROM = 'model_rtl_evidence/attention_sublayer/exp_neg_q30.memh'
JOBS = (('self_attn.q_proj.weight', 256, 256),
        ('self_attn.k_proj.weight', 128, 256),
        ('self_attn.v_proj.weight', 128, 256),
        ('self_attn.o_proj.weight', 256, 256),
        ('mlp.gate_proj.weight', 682, 256),
        ('mlp.up_proj.weight', 682, 256),
        ('mlp.down_proj.weight', 256, 682))
NORMS = ('input_layernorm.weight', 'post_attention_layernorm.weight')


def sha(data: bytes) -> str: return hashlib.sha256(data).hexdigest()


def require(condition: bool, explanation: str) -> None:
    if not condition: raise ValueError(explanation)


def memh(values, bits: int) -> bytes:
    return ''.join(f'{int(value) & ((1 << bits) - 1):0{(bits + 3) // 4}x}\n'
                   for value in values).encode('ascii')


def derive(model, np) -> tuple[dict[str, bytes], dict]:
    """Independent four-coefficient packing, with exhaustive bit-unpacking checks."""
    coefficient_count = 0

    def packed(values):
        nonlocal coefficient_count
        flat = np.asarray(values).reshape(-1)
        require(np.issubdtype(flat.dtype, np.integer) and flat.size % 4 == 0,
                'W10 input type/packing geometry differs')
        require(bool(np.all((flat >= -511) & (flat <= 511))), 'W10 input out of range')
        raw = (flat.astype(np.int64) & 1023).astype(np.uint64).reshape(-1, 4)
        words = raw[:, 0] | (raw[:, 1] << 10) | (raw[:, 2] << 20) | (raw[:, 3] << 30)
        payload = ((words[:, None] >> np.arange(0, 40, 8, dtype=np.uint64)) & 255).astype(np.uint8).tobytes()
        # Different implementation: reconstruct from individual serialized bits.
        bits = np.unpackbits(np.frombuffer(payload, dtype=np.uint8), bitorder='little')
        unsigned = bits.reshape(-1, 10).astype(np.int16) @ (1 << np.arange(10, dtype=np.int16))
        recovered = np.where(unsigned >= 512, unsigned - 1024, unsigned)
        require(bool(np.array_equal(recovered, flat)), 'W10 reconstruction differs')
        coefficient_count += int(flat.size)
        return payload

    jobs = [('model.layers.' + str(layer) + '.' + suffix, rows, columns)
            for layer in range(6) for suffix, rows, columns in JOBS]
    jobs.append(('model.embed_tokens.weight', 4019, 256))
    norm_names = ['model.layers.' + str(layer) + '.' + suffix
                  for layer in range(6) for suffix in NORMS]
    require(set(model.tensors) == {job[0] for job in jobs} | set(norm_names) | {'model.norm.weight'},
            'Fixed tensor inventory differs')
    require(sum(tensor.value.size for tensor in model.tensors.values()) == 5_354_496,
            'Fixed parameter count differs')

    weights, metadata = bytearray(), bytearray()
    schedule = []
    real, ragged = 0, 0
    for name, rows, columns in jobs:
        tensor = model.tensors[name]
        require(tensor.value.shape == (rows, columns) and tensor.exponent.size == rows
                and tensor.multiplier.size == rows, 'Tensor geometry differs: ' + name)
        groups = (rows + 63) // 64
        padded = np.zeros((groups * 64, columns), dtype=np.int16)
        padded[:rows] = tensor.value
        striped = padded.reshape(groups, 64, columns).transpose(0, 2, 1).reshape(-1)
        payload = packed(striped)
        schedule.append({'tensor': name, 'rows': rows, 'columns': columns,
                         'first_word': len(weights) // 32, 'bytes': len(payload), 'sha256': sha(payload)})
        weights.extend(payload)
        for row in range(rows):
            multiplier = int(tensor.multiplier[row])
            require(1 <= multiplier <= 32767, 'Invalid projection multiplier')
            metadata.extend(struct.pack('<bHB', int(tensor.exponent[row]), multiplier, 0))
        metadata.extend(bytes((groups * 64 - rows) * 4))
        real += rows * columns
        ragged += (groups * 64 - rows) * columns
    require(len(jobs) == 43 and real == 5_351_168 and ragged == 70_912
            and len(weights) == 211800 * 32 and len(metadata) == 2328 * 32,
            'Projection stream census differs')

    norm_weights, norm_metadata = bytearray(), bytearray()
    norm_rom = []
    final_norm = b''
    for name in norm_names + ['model.norm.weight']:
        tensor = model.tensors[name]
        require(tensor.value.shape == (256,) and tensor.exponent.size == tensor.multiplier.size == 1,
                'Norm tensor geometry differs')
        exponent, multiplier = int(tensor.exponent[0]), int(tensor.multiplier[0])
        require(1 <= multiplier <= 32767, 'Invalid norm multiplier')
        payload = packed(tensor.value)
        for coefficient in tensor.value:
            norm_rom.append(((exponent & 255) << 26) | (multiplier << 10) | (int(coefficient) & 1023))
        if name == 'model.norm.weight':
            final_norm = payload + struct.pack('<bH', exponent, multiplier)
        else:
            norm_weights.extend(payload)
            norm_metadata.extend(struct.pack('<bHB', exponent, multiplier, 0))
    require(len(norm_weights) == 3840 and len(norm_metadata) == 48 and len(final_norm) == 323,
            'Norm region lengths differ')
    image = bytearray(weights + norm_weights)
    require(sha(image) == 'e558febf5bedffff485d9f340d40784fc532e91e3bce5f40482a6f4bbe19860a',
            'Selected weight/norm image prefix differs')
    regions = [{'name': 'projection_weights_and_norm_coefficients', 'first_word': 0,
                'bytes': len(image), 'sha256': sha(image)}]

    def append(name, payload):
        require(len(image) % 32 == 0, 'Region address is not aligned')
        regions.append({'name': name, 'first_word': len(image) // 32,
                        'bytes': len(payload), 'sha256': sha(payload)})
        image.extend(payload); image.extend(bytes((-len(payload)) % 32))

    cosine, sine = [], []
    inverse = [math.pow(10000.0, -float(2 * index) / 64.0) for index in range(32)]
    for position in range(2048):
        for frequency in inverse:
            angle = position * frequency
            cosine.append(max(-32768, min(32767, round(math.cos(angle) * 32768.0))))
            sine.append(max(-32768, min(32767, round(math.sin(angle) * 32768.0))))
    cosine_bytes = np.asarray(cosine, dtype='<i2').tobytes()
    sine_bytes = np.asarray(sine, dtype='<i2').tobytes()
    require(cosine_bytes[:32768] == model.rope_cos.astype('<i2').tobytes()
            and sine_bytes[:32768] == model.rope_sin.astype('<i2').tobytes(),
            'RoPE reconstruction disagrees with canonical 512-position tables')
    append('projection_row_metadata_l64', bytes(metadata))
    append('transformer_norm_metadata', bytes(norm_metadata))
    append('final_norm', final_norm)
    append('rope_cos_positions0_127', cosine_bytes[:8192])
    append('rope_sin_positions0_127', sine_bytes[:8192])
    append('exp_neg_q30', model.exp_neg.astype('<i4').tobytes())
    append('silu_q10', model.silu.astype('<i2').tobytes())
    require(len(image) == 219382 * 32
            and sha(image) == 'e892739af5ec348967ae3d67f9cebf7a527d4cdb6010ca8042853dc8d61518fd',
            'Selected context-128 image prefix differs')
    append('rope_cos_positions128_2047', cosine_bytes[8192:])
    append('rope_sin_positions128_2047', sine_bytes[8192:])
    require(len(image) == IMAGE_BYTES and sha(image) == IMAGE_SHA256,
            'Selected complete FPGA image differs; do not change its expected digest to bypass this check')

    compact_metadata = []
    for start in range(0, len(metadata), 32):
        word = metadata[start:start + 32]
        require(all(word[index] == 0 for index in range(3, 32, 4)), 'Metadata reserved byte nonzero')
        compact_metadata.append(int.from_bytes(b''.join(word[index:index + 3] for index in range(0, 32, 4)), 'little'))
    digest_words = []
    for start in range(0, len(image), 4096):
        page = bytes(image[start:start + 4096]).ljust(4096, b'\0')
        digest = hashlib.sha256(page).digest()
        digest_words.extend(int.from_bytes(digest[index:index + 4], 'big') for index in range(0, 32, 4))
    require(len(digest_words) == 14192 and len(norm_rom) == 3328,
            'On-chip ROM word counts differ')
    outputs = {'board1-real-semantic-image2048.bin': bytes(image),
               'metadata192.memh': memh(compact_metadata, 192),
               'digests32.memh': memh(digest_words, 32),
               NORM_ROM: memh(norm_rom, 34),
               EXP_ROM: memh(model.exp_neg, 32)}
    return outputs, {'projection_jobs': schedule, 'regions': regions,
                     'real_projection_coefficients': real, 'zero_padding_coefficients': ragged,
                     'all_serialized_w10_fields_reconstructed': coefficient_count}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-root', type=Path, required=True)
    parser.add_argument('--rom', type=Path, required=True)
    parser.add_argument('--hardware-project', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true', help='compare an existing output without writing')
    options = parser.parse_args()
    reference = options.reference_root.resolve(strict=True)
    require(sha((reference / 'quantization/oracle.py').read_bytes()) == ORACLE_SHA256,
            'Packaged numerical loader identity differs')
    sys.path.insert(0, str(reference))
    import numpy as np
    from quantization.oracle import QuantizedModel
    require(np.__version__ == '1.26.4', 'Use the pinned NumPy 1.26.4 reference environment')
    model = QuantizedModel.load(options.rom)
    outputs, details = derive(model, np)
    for name in (NORM_ROM, EXP_ROM, 'metadata192.memh', 'digests32.memh'):
        require((options.hardware_project / name).read_bytes() == outputs[name],
                'Reconstructed initializer does not match selected hardware: ' + name)
    manifest = {'schema_version': 1, 'image_sha256': IMAGE_SHA256,
        'model_revision': 'c4b3a4bb81297f5316697098e1d4b65c1249daf8',
        'profile': 'simplestories-w10-a16-kv16-bfp-v5',
        'q0_manifest_sha256': sha((options.rom / 'manifest.json').read_bytes()),
        'builder_sha256': sha(Path(__file__).read_bytes()),
        'files': {name: {'bytes': len(data), 'sha256': sha(data)} for name, data in outputs.items()},
        'reconstruction': details, 'hardware_access': False,
        'scope': 'Exact image and four selected synthesis initializers reconstructed from canonical Q0 ROMs. Not a flash-programming utility, bitstream reproduction or full-model numerical proof.'}
    outputs['materialization.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    if options.check:
        require({str(path.relative_to(options.output)) for path in options.output.rglob('*') if path.is_file()} == set(outputs),
                'Materialized output file inventory differs')
        for name, payload in outputs.items():
            require((options.output / name).read_bytes() == payload, 'Output differs: ' + name)
    else:
        options.output.mkdir(parents=False, exist_ok=False)
        for name, payload in outputs.items():
            path = options.output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as out: out.write(payload)
    print('PASS selected image plus four synthesis ROMs; '
          f'{details["all_serialized_w10_fields_reconstructed"]} W10 fields reconstructed; '
          f'image_sha256={IMAGE_SHA256}; hardware_access=0', flush=True)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError) as error:
        raise SystemExit('FAIL: ' + str(error)) from error

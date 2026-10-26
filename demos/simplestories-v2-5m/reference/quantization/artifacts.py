"""Canonical ROM-image builder for the SimpleStories integer profile.

Weights use packed signed int10 values. Every matrix row has its own fixed
uint15-significand/power-of-two scale; each one-dimensional RMSNorm vector has
one scale. Runtime
activations and KV entries use signed int16 block floating point (BFP), with a
small signed exponent stored as metadata.  All runtime rescaling is therefore
integer shifting and explicitly specified rounding.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import stat
import tempfile
from typing import Any, Dict, Mapping, Tuple

import numpy as np


PROFILE_NAME = "simplestories-w10-a16-kv16-bfp-v5"
SCHEMA_VERSION = 1
WEIGHT_BITS = 10
WEIGHT_MAX = (1 << (WEIGHT_BITS - 1)) - 1
SOURCE_REPOSITORY = "SimpleStories/SimpleStories-V2-5M"
SOURCE_REVISION = "c4b3a4bb81297f5316697098e1d4b65c1249daf8"
SOURCE_MODEL_SHA256 = "7c8a5d078690e816920b4779decf55e58c34901c2668a1bc4f344b21862fce03"
CALIBRATION_CORPUS_SHA256 = "f5eb872eb2f572166f69bad6bc17f3b9db9b81f32f0f3b6459983686dc4047f2"
EVALUATION_CORPUS_SHA256 = "8c11dc3aedfbeaeb446b7c5f1cedceafbf7cf4ef5fa26be8fe8920cc1344d7e9"
ROM_FILES = (
    "exp_neg_q30.i32le.bin",
    "exponents.i8.bin",
    "multipliers.u16le.bin",
    "rope_cos_q15.i16le.bin",
    "rope_sin_q15.i16le.bin",
    "silu_q10.i16le.bin",
    "weights.i10.lsb0.bin",
)
OUTPUT_FILES = ROM_FILES + ("manifest.json",)


class QuantizationError(ValueError):
    """A quantization artifact is invalid or cannot be reproduced."""


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _tool_source_records() -> list[Dict[str, object]]:
    project = Path(__file__).resolve().parents[1]
    records = []
    for relative in (
        "quantization/artifacts.py",
        "quantization/oracle.py",
        "scripts/quantize.py",
    ):
        payload = (project / relative).read_bytes()
        records.append(
            {"path": relative, "size": len(payload), "sha256": sha256_bytes(payload)}
        )
    return records


def _round_even_float(values: np.ndarray) -> np.ndarray:
    """Round finite float64 values to nearest, with exact ties to even."""

    return np.rint(values)


def _encode_scale(maximum: float) -> Tuple[int, int, float]:
    """Encode max/511 as a 15-bit significand and signed power-of-two exponent."""

    if maximum == 0.0:
        return 0, 1, 0.0
    if not math.isfinite(maximum) or maximum < 0.0:
        raise QuantizationError("weight maximum must be finite and nonnegative")
    target = maximum / float(WEIGHT_MAX)
    fraction, exponent = math.frexp(target)
    multiplier = int(np.rint(fraction * (1 << 15)))
    if multiplier == (1 << 15):
        multiplier = 1 << 14
        exponent += 1
    if not -128 <= exponent <= 127:
        raise QuantizationError(f"weight exponent {exponent} does not fit int8")
    if not 1 <= multiplier <= 32767:
        raise QuantizationError("weight scale multiplier does not fit 15 bits")
    scale = math.ldexp(float(multiplier), exponent - 15)
    # Never let scale approximation cause int10 saturation. Increasing the
    # significand by one is deterministic and has negligible relative error.
    while np.rint(maximum / scale) > float(WEIGHT_MAX):
        multiplier += 1
        if multiplier == (1 << 15):
            multiplier = 1 << 14
            exponent += 1
        scale = math.ldexp(float(multiplier), exponent - 15)
    return exponent, multiplier, scale


def _quantize_weight(
    value: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, str]:
    if value.dtype != np.dtype("float32") or value.ndim not in (1, 2):
        raise QuantizationError("weights must be one- or two-dimensional float32")
    rows = value if value.ndim == 2 else value.reshape(1, -1)
    quantized = np.empty(rows.shape, dtype=np.int16)
    exponents = np.empty(rows.shape[0], dtype=np.int8)
    multipliers = np.empty(rows.shape[0], dtype=np.uint16)
    for row_index, row in enumerate(rows):
        exponent, multiplier, scale = _encode_scale(float(np.max(np.abs(row))))
        scaled = row.astype(np.float64) / np.float64(scale) if scale else row.astype(np.float64)
        rounded = _round_even_float(scaled)
        if np.any(rounded < -WEIGHT_MAX) or np.any(rounded > WEIGHT_MAX):
            raise QuantizationError("internal error: int10 weight saturation")
        quantized[row_index] = rounded.astype(np.int16)
        exponents[row_index] = exponent
        multipliers[row_index] = multiplier
    layout = "per_output_row" if value.ndim == 2 else "per_tensor"
    return quantized.reshape(value.shape), exponents, multipliers, layout


def _little_endian_bytes(value: np.ndarray, dtype: str) -> bytes:
    return np.ascontiguousarray(value, dtype=np.dtype(dtype)).tobytes(order="C")


def _pack_int10(values: np.ndarray) -> bytes:
    """Pack symmetric signed int10 values as two's-complement LSB-first bits."""

    source = np.asarray(values)
    if not np.issubdtype(source.dtype, np.integer):
        raise QuantizationError("int10 pack input must have an integer dtype")
    flat_source = source.reshape(-1)
    # Validate before narrowing.  Casting first would let values such as 65536
    # wrap to zero and silently enter the immutable ROM image.
    if np.any(flat_source < -WEIGHT_MAX) or np.any(flat_source > WEIGHT_MAX):
        raise QuantizationError("int10 pack input exceeds symmetric range")
    flat = flat_source.astype(np.int16)
    unsigned = np.bitwise_and(flat.astype(np.int32), (1 << WEIGHT_BITS) - 1)
    bits = ((unsigned[:, None] >> np.arange(WEIGHT_BITS)) & 1).astype(np.uint8)
    return np.packbits(bits.reshape(-1), bitorder="little").tobytes()


def _build_luts() -> Dict[str, bytes]:
    positions = np.arange(512, dtype=np.float64)[:, None]
    dimensions = np.arange(0, 64, 2, dtype=np.float64)[None, :]
    inverse = np.power(np.float64(10000.0), -dimensions / np.float64(64.0))
    angles = positions * inverse
    cosine = np.clip(
        _round_even_float(np.cos(angles) * np.float64(32768.0)), -32768, 32767
    ).astype(np.int16)
    sine = np.clip(
        _round_even_float(np.sin(angles) * np.float64(32768.0)), -32768, 32767
    ).astype(np.int16)

    silu_inputs = np.arange(-32768, 32768, dtype=np.float64) / np.float64(1024.0)
    silu_real = silu_inputs / (np.float64(1.0) + np.exp(-silu_inputs))
    silu = np.clip(
        _round_even_float(silu_real * np.float64(1024.0)), -32768, 32767
    ).astype(np.int16)

    exp_inputs = -np.arange(4097, dtype=np.float64) / np.float64(256.0)
    exp_neg = _round_even_float(
        np.exp(exp_inputs) * np.float64(1 << 30)
    ).astype(np.int32)
    return {
        "rope_cos_q15.i16le.bin": _little_endian_bytes(cosine, "<i2"),
        "rope_sin_q15.i16le.bin": _little_endian_bytes(sine, "<i2"),
        "silu_q10.i16le.bin": _little_endian_bytes(silu, "<i2"),
        "exp_neg_q30.i32le.bin": _little_endian_bytes(exp_neg, "<i4"),
    }


def build_artifacts(model: Any) -> Dict[str, bytes]:
    """Build canonical ROM images and their self-describing manifest."""

    weight_arrays = []
    weight_count = 0
    exponents = bytearray()
    multipliers = bytearray()
    tensor_records = []
    for name in sorted(model.tensors):
        value = model.tensors[name]
        quantized, tensor_exponents, tensor_multipliers, layout = _quantize_weight(value)
        canonical_weight_bytes = _little_endian_bytes(quantized, "<i2")
        exponent_bytes = _little_endian_bytes(tensor_exponents, "i1")
        multiplier_bytes = _little_endian_bytes(tensor_multipliers, "<u2")
        record = {
            "name": name,
            "shape": list(value.shape),
            "values": {
                "dtype": "int10_twos_complement_lsb0",
                "bit_offset": weight_count * WEIGHT_BITS,
                "count": quantized.size,
                "bit_size": quantized.size * WEIGHT_BITS,
                "canonical_int16le_sha256": sha256_bytes(canonical_weight_bytes),
            },
            "exponents": {
                "dtype": "int8",
                "layout": layout,
                "offset": len(exponents),
                "count": len(tensor_exponents),
                "sha256": sha256_bytes(exponent_bytes),
            },
            "multipliers": {
                "dtype": "uint15_in_uint16le",
                "layout": layout,
                "offset": len(multipliers),
                "count": len(tensor_multipliers),
                "sha256": sha256_bytes(multiplier_bytes),
            },
            "real_value": (
                "int10_value * uint15_multiplier * "
                "2**(signed_int8_exponent - 15)"
            ),
        }
        weight_arrays.append(quantized.reshape(-1))
        weight_count += quantized.size
        exponents.extend(exponent_bytes)
        multipliers.extend(multiplier_bytes)
        tensor_records.append(record)

    artifacts = _build_luts()
    artifacts["weights.i10.lsb0.bin"] = _pack_int10(
        np.concatenate(weight_arrays)
    )
    artifacts["exponents.i8.bin"] = bytes(exponents)
    artifacts["multipliers.u16le.bin"] = bytes(multipliers)
    files = [
        {"path": name, "size": len(artifacts[name]), "sha256": sha256_bytes(artifacts[name])}
        for name in ROM_FILES
    ]
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "profile": PROFILE_NAME,
        "source": {
            "repository": SOURCE_REPOSITORY,
            "revision": SOURCE_REVISION,
            "model_sha256": SOURCE_MODEL_SHA256,
        },
        "builder": {
            "canonical_command": (
                "python scripts/quantize.py MODEL_DIRECTORY OUTPUT_DIRECTORY"
            ),
            "numpy": np.__version__,
            "sources": _tool_source_records(),
        },
        "corpora": {
            "calibration": {
                "sha256": CALIBRATION_CORPUS_SHA256,
                "records": 512,
                "teacher_forced_positions": 145667,
                "used_for_scales": False,
            },
            "evaluation": {
                "sha256": EVALUATION_CORPUS_SHA256,
                "records": 1024,
                "teacher_forced_positions": 282976,
                "used_for_scales": False,
            },
        },
        "arithmetic": {
            "weights": (
                "signed symmetric int10 [-511,511], packed two's-complement "
                "LSB-first; per-output-row uint15 significand and "
                "signed int8 power-of-two exponent"
            ),
            "activations": "signed int16 BFP with signed exponent",
            "kv_cache": "signed int16 BFP per token and projection",
            "bfp_exponent_derivation": (
                "finest exponent in [-32,31] for which all RNE-even-aligned "
                "nonzero mantissas fit symmetric [-32767,32767]"
            ),
            "bfp_exponent_visibility": (
                "derived only from token-dependent internal values; not host "
                "addressable, writable, or persistent across CLEAR"
            ),
            "bfp_exponent_range": [-32, 31],
            "host_carrier": "signed int64, with asserted hardware-width bounds",
            "matrix_accumulator": "signed 35 bits (682*511*32767 bound)",
            "scale_product_intermediate": (
                "signed 50 bits (682*511*32767*32767 bound)"
            ),
            "attention_score_accumulator": "signed 37 bits",
            "attention_value_accumulator": "signed 40 bits",
            "softmax_exponential": "unsigned Q2.30 in 31 bits",
            "softmax_denominator": (
                "unsigned 40 bits (at most 512*2**30, inclusive)"
            ),
            "softmax_probability_numerator": (
                "unsigned 45 bits (at most 2**30*32767)"
            ),
            "rope_accumulator": "signed 32 bits",
            "right_shift_rounding": "nearest, exact ties to even",
            "saturation": "symmetric [-32767,32767] after BFP normalization",
            "residual_add": (
                "normalize both branches to the finest common BFP exponent, "
                "sum in signed 17 bits, then BFP-normalize the sum"
            ),
            "elementwise_product": "signed 31 bits (32767**2 bound)",
            "rms_square_sum": "unsigned 38 bits (256*32767**2 bound)",
            "rms_epsilon_aligned_radicand": (
                "unsigned 45 bits for BFP exponents in [-32,31]"
            ),
            "rms_division_numerator": "signed 28 bits (32767*2**12 bound)",
            "rms_weight_product": (
                "signed 40 bits (32767*511*32767 bound)"
            ),
            "rmsnorm": (
                "epsilon=2**-20; floor integer square root; RNE-even division; "
                "normalized value in signed Q3.12"
            ),
            "rope": "Q0.15 int16 LUT, half-split pairing",
            "silu": "Q5.10 input/output int16 LUT",
            "softmax": (
                "difference Q8.8, exp(-x) Q2.30 LUT over [0,16]; each "
                "probability is independently RNE-even(exp*32767/sum_exp); "
                "value accumulation divides by 32767"
            ),
            "greedy_tie_break": "lowest token ID",
            "range_fault": (
                "any declared-width violation, invalid shift, or BFP exponent "
                "overflow raises a fail-stop RANGE_FAULT; no token is appended, "
                "and the inference state remains fault-latched until CLEAR"
            ),
            "reachable_state_status": (
                "the declared arithmetic is total because out-of-range states "
                "trap; absence of RANGE_FAULT on every possible token history "
                "is not proved by this artifact"
            ),
        },
        "luts": {
            "rope_shape": [512, 32],
            "silu_entries": 65536,
            "softmax_exp_entries": 4097,
        },
        "files": files,
        "tensors": tensor_records,
    }
    artifacts["manifest.json"] = (
        json.dumps(manifest, sort_keys=True, indent=2) + "\n"
    ).encode("utf-8")
    return artifacts


def _inspect_output(directory: Path) -> None:
    try:
        entries = list(os.scandir(directory))
    except OSError as exc:
        raise QuantizationError(f"cannot inspect artifact directory: {exc}") from exc
    names = sorted(entry.name for entry in entries)
    if names != sorted(OUTPUT_FILES):
        raise QuantizationError(
            f"artifact inventory differs: expected={sorted(OUTPUT_FILES)!r}, found={names!r}"
        )
    for entry in entries:
        if entry.is_symlink() or not stat.S_ISREG(entry.stat(follow_symlinks=False).st_mode):
            raise QuantizationError(f"artifact is not a regular file: {entry.name!r}")


def check_artifacts(directory: Path | str, expected: Mapping[str, bytes]) -> None:
    """Require byte-for-byte identity with a freshly generated artifact set."""

    directory = Path(directory)
    _inspect_output(directory)
    for name in OUTPUT_FILES:
        try:
            actual = (directory / name).read_bytes()
        except OSError as exc:
            raise QuantizationError(f"cannot read artifact {name}: {exc}") from exc
        if actual != expected[name]:
            raise QuantizationError(
                f"artifact is not reproducible: {name}; "
                f"expected sha256={sha256_bytes(expected[name])}, "
                f"found sha256={sha256_bytes(actual)}"
            )


def publish_artifacts(directory: Path | str, artifacts: Mapping[str, bytes]) -> None:
    """Publish ROM images atomically per file, with the manifest last."""

    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    if directory.is_symlink() or not directory.is_dir():
        raise QuantizationError("artifact destination must be a real directory")
    unexpected = sorted(path.name for path in directory.iterdir() if path.name not in OUTPUT_FILES)
    if unexpected:
        raise QuantizationError(f"refusing destination with unexpected entries: {unexpected!r}")
    staged: Dict[str, Path] = {}
    try:
        for name in OUTPUT_FILES:
            descriptor, raw_path = tempfile.mkstemp(prefix=f".{name}.", dir=directory)
            stage = Path(raw_path)
            staged[name] = stage
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(artifacts[name])
                stream.flush()
                os.fsync(stream.fileno())
        for name in ROM_FILES:
            os.replace(staged.pop(name), directory / name)
        os.replace(staged.pop("manifest.json"), directory / "manifest.json")
        directory_descriptor = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except OSError as exc:
        raise QuantizationError(f"cannot publish artifacts: {exc}") from exc
    finally:
        for path in staged.values():
            try:
                path.unlink()
            except FileNotFoundError:
                pass

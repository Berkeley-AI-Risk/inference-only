"""Bit-exact integer oracle for the SimpleStories W10/A16/KV16 BFP profile."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
import math
import os
from pathlib import Path
import stat
from types import MappingProxyType
from typing import Dict, Mapping, Sequence, Tuple

import numpy as np

from .artifacts import OUTPUT_FILES, PROFILE_NAME, ROM_FILES, QuantizationError


I16_MAX = 32767
I16_MIN = -32767
Q_PROBABILITY = 32767
RMS_UNIT_FRACTION = 12
SILU_FRACTION = 10
SOFTMAX_FRACTION = 8
MAX_BFP_SHIFT = 62
BFP_EXPONENT_MIN = -32
BFP_EXPONENT_MAX = 31
MATRIX_ACCUMULATOR_BITS = 35
SCALE_PRODUCT_BITS = 50
PROJECT_ROOT = Path(__file__).resolve().parents[1]
RELEASE_RECEIPT = PROJECT_ROOT / "evidence" / "q0-receipt.json"


def _strict_json(payload: bytes, label: str) -> object:
    def unique(pairs: list[Tuple[str, object]]) -> Dict[str, object]:
        result: Dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise QuantizationError(f"{label} contains duplicate key {key!r}")
            result[key] = value
        return result

    try:
        return json.loads(payload.decode("utf-8"), object_pairs_hook=unique)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise QuantizationError(f"invalid {label}: {exc}") from exc


def _freeze_json(value: object) -> object:
    """Recursively freeze authenticated JSON metadata exposed to callers."""

    if isinstance(value, dict):
        return MappingProxyType(
            {str(key): _freeze_json(item) for key, item in value.items()}
        )
    if isinstance(value, list):
        return tuple(_freeze_json(item) for item in value)
    return value


def _release_specs() -> Dict[str, Tuple[int, str]]:
    """Load exact release hashes from committed, non-executable evidence data."""

    try:
        receipt = _strict_json(RELEASE_RECEIPT.read_bytes(), "Q0 release receipt")
    except OSError as exc:
        raise QuantizationError(f"cannot read Q0 release receipt: {exc}") from exc
    if not isinstance(receipt, dict) or receipt.get("profile") != PROFILE_NAME:
        raise QuantizationError("Q0 release receipt profile is not exact")
    rom = receipt.get("rom")
    records = rom.get("files") if isinstance(rom, dict) else None
    if not isinstance(records, dict) or tuple(sorted(records)) != tuple(
        sorted(OUTPUT_FILES)
    ):
        raise QuantizationError("Q0 release receipt ROM inventory is not exact")
    specs: Dict[str, Tuple[int, str]] = {}
    for name, record in records.items():
        if (
            not isinstance(record, list)
            or len(record) != 2
            or type(record[0]) is not int
            or record[0] <= 0
            or not isinstance(record[1], str)
            or len(record[1]) != 64
            or any(character not in "0123456789abcdef" for character in record[1])
        ):
            raise QuantizationError(f"invalid Q0 release record: {name}")
        specs[name] = (record[0], record[1])
    return specs


def _unpack_int10(payload: bytes, count: int) -> np.ndarray:
    """Unpack canonical two's-complement LSB-first signed int10 values."""

    expected_bytes = (count * 10 + 7) // 8
    if len(payload) != expected_bytes:
        raise QuantizationError("packed int10 ROM has the wrong byte count")
    bits = np.unpackbits(np.frombuffer(payload, dtype=np.uint8), bitorder="little")
    used = count * 10
    if np.any(bits[used:]):
        raise QuantizationError("packed int10 ROM has nonzero padding bits")
    groups = bits[:used].reshape(count, 10).astype(np.uint16)
    unsigned = np.sum(
        groups * (np.uint16(1) << np.arange(10, dtype=np.uint16)),
        axis=1,
        dtype=np.uint16,
    )
    signed = unsigned.astype(np.int16)
    signed[unsigned >= 512] -= 1024
    if np.any(signed < -511) or np.any(signed > 511):
        raise QuantizationError("packed weight uses forbidden int10 value -512")
    # Use immutable bytes as the ultimate owner.  Merely setting an owning
    # ndarray's writeable flag false is reversible by a caller that reaches it
    # through ``view.base``.
    return np.frombuffer(signed.astype("<i2", copy=False).tobytes(), dtype="<i2")


@dataclass(frozen=True)
class BFP:
    """Signed int16 block floating-point value: real = value * 2**exponent."""

    value: np.ndarray
    exponent: int

    def __post_init__(self) -> None:
        if self.value.dtype != np.dtype("int16"):
            raise QuantizationError("BFP mantissa must be int16")
        if np.any(self.value == -32768):
            raise QuantizationError("BFP uses symmetric saturation and forbids -32768")
        if (
            type(self.exponent) is not int
            or not BFP_EXPONENT_MIN <= self.exponent <= BFP_EXPONENT_MAX
        ):
            raise QuantizationError(
                "BFP exponent is outside the declared [-32,31] range"
            )


@dataclass
class OracleStats:
    """Runtime range and saturation evidence."""

    activation_saturations: int = 0
    softmax_clips: int = 0
    silu_clips: int = 0
    max_matrix_accumulator: int = 0
    max_scale_product: int = 0
    max_attention_score_accumulator: int = 0
    max_attention_accumulator: int = 0
    max_softmax_denominator: int = 0
    max_softmax_probability_numerator: int = 0
    max_rope_accumulator: int = 0
    max_rms_square_sum: int = 0
    max_rms_radicand: int = 0
    max_rms_division_numerator: int = 0
    max_rms_weight_product: int = 0
    max_elementwise_product: int = 0
    exponent_min: int = 127
    exponent_max: int = -128
    saturation_sites: Dict[str, int] = field(default_factory=dict)

    def observe_exponent(self, exponent: int) -> None:
        self.exponent_min = min(self.exponent_min, exponent)
        self.exponent_max = max(self.exponent_max, exponent)

    def observe_saturation(self, site: str, count: int) -> None:
        if count:
            self.activation_saturations += count
            self.saturation_sites[site] = self.saturation_sites.get(site, 0) + count


def _round_div_even_scalar(numerator: int, denominator: int) -> int:
    """Round a signed integer quotient to nearest, with ties to even."""

    if denominator <= 0:
        raise QuantizationError("rounding denominator must be positive")
    sign = -1 if numerator < 0 else 1
    magnitude = abs(numerator)
    quotient, remainder = divmod(magnitude, denominator)
    twice = remainder * 2
    if twice > denominator or (twice == denominator and quotient & 1):
        quotient += 1
    return sign * quotient


def _round_shift_even_scalar(value: int, shift: int) -> int:
    if shift < 0:
        if -shift > MAX_BFP_SHIFT:
            raise QuantizationError("left shift exceeds declared arithmetic bound")
        return value << -shift
    if shift == 0:
        return value
    if shift > MAX_BFP_SHIFT:
        return 0
    return _round_div_even_scalar(value, 1 << shift)


def _round_shift_even(values: np.ndarray, shift: int) -> np.ndarray:
    flat = np.asarray(values).reshape(-1)
    result = np.fromiter(
        (_round_shift_even_scalar(int(value), shift) for value in flat),
        dtype=np.int64,
        count=flat.size,
    )
    return result.reshape(values.shape)


def _select_exponent(values: np.ndarray, exponents: np.ndarray) -> int:
    """Choose the finest common exponent whose RNE mantissas fit symmetrically."""

    flat_values = np.asarray(values, dtype=np.int64).reshape(-1)
    flat_exponents = np.asarray(exponents, dtype=np.int16).reshape(-1)
    if flat_values.size != flat_exponents.size:
        raise QuantizationError("mixed-exponent values have inconsistent shapes")
    nonzero = np.flatnonzero(flat_values)
    if nonzero.size == 0:
        return 0
    candidate = max(
        int(flat_exponents[index]) + abs(int(flat_values[index])).bit_length() - 15
        for index in nonzero
    )
    candidate = max(BFP_EXPONENT_MIN, min(BFP_EXPONENT_MAX, candidate))

    def fits(exponent: int) -> bool:
        for index in nonzero:
            converted = _round_shift_even_scalar(
                int(flat_values[index]), exponent - int(flat_exponents[index])
            )
            if converted < I16_MIN or converted > I16_MAX:
                return False
        return True

    while not fits(candidate):
        candidate += 1
        if candidate > BFP_EXPONENT_MAX:
            raise QuantizationError("BFP exponent overflow")
    while candidate > BFP_EXPONENT_MIN and fits(candidate - 1):
        candidate -= 1
    return candidate


def _normalize_mixed(
    values: np.ndarray,
    exponents: np.ndarray,
    stats: OracleStats,
    site: str = "bfp_normalize",
) -> BFP:
    values = np.asarray(values, dtype=np.int64)
    exponents = np.broadcast_to(np.asarray(exponents, dtype=np.int16), values.shape)
    exponent = _select_exponent(values, exponents)
    result = np.empty(values.shape, dtype=np.int64)
    for source_exponent in np.unique(exponents):
        mask = exponents == source_exponent
        result[mask] = _round_shift_even(
            values[mask], exponent - int(source_exponent)
        )
    clipped = np.clip(result, I16_MIN, I16_MAX)
    stats.observe_saturation(site, int(np.count_nonzero(clipped != result)))
    stats.observe_exponent(exponent)
    return BFP(clipped.astype(np.int16), exponent)


def _normalize(
    values: np.ndarray,
    exponent: int,
    stats: OracleStats,
    site: str = "bfp_normalize",
) -> BFP:
    return _normalize_mixed(
        values,
        np.full(np.asarray(values).shape, exponent, dtype=np.int16),
        stats,
        site,
    )


def _add(left: BFP, right: BFP, stats: OracleStats) -> BFP:
    if left.value.shape != right.value.shape:
        raise QuantizationError("BFP addition shape mismatch")
    mixed_values = np.stack((left.value.astype(np.int64), right.value.astype(np.int64)))
    mixed_exponents = np.empty(mixed_values.shape, dtype=np.int16)
    mixed_exponents[0].fill(left.exponent)
    mixed_exponents[1].fill(right.exponent)
    aligned = _normalize_mixed(mixed_values, mixed_exponents, stats)
    total = np.sum(aligned.value.astype(np.int64), axis=0, dtype=np.int64)
    return _normalize(total, aligned.exponent, stats)


@dataclass(frozen=True)
class QuantizedTensor:
    value: np.ndarray
    exponent: np.ndarray
    multiplier: np.ndarray


class QuantizedModel:
    """Authenticated immutable view of canonical ROM artifacts."""

    __slots__ = (
        "tensors",
        "rope_cos",
        "rope_sin",
        "silu",
        "exp_neg",
        "manifest",
        "_sealed",
    )

    def __setattr__(self, name: str, value: object) -> None:
        if getattr(self, "_sealed", False):
            raise AttributeError("authenticated QuantizedModel is immutable")
        object.__setattr__(self, name, value)

    def __init__(
        self,
        tensors: Mapping[str, QuantizedTensor],
        rope_cos: np.ndarray,
        rope_sin: np.ndarray,
        silu: np.ndarray,
        exp_neg: np.ndarray,
        manifest: Mapping[str, object],
    ) -> None:
        self.tensors = MappingProxyType(dict(tensors))
        self.rope_cos = rope_cos
        self.rope_sin = rope_sin
        self.silu = silu
        self.exp_neg = exp_neg
        self.manifest = _freeze_json(manifest)
        self._sealed = True

    @classmethod
    def load(cls, directory: Path | str) -> "QuantizedModel":
        directory = Path(directory)
        release_specs = _release_specs()
        try:
            if directory.is_symlink() or not directory.is_dir():
                raise QuantizationError("ROM directory must be a real directory")
            entries = list(os.scandir(directory))
        except OSError as exc:
            raise QuantizationError(f"cannot inspect ROM directory: {exc}") from exc
        names = sorted(entry.name for entry in entries)
        if names != sorted(OUTPUT_FILES):
            raise QuantizationError("ROM artifact inventory is not exact")
        for entry in entries:
            if entry.is_symlink() or not stat.S_ISREG(
                entry.stat(follow_symlinks=False).st_mode
            ):
                raise QuantizationError(f"ROM artifact is not a regular file: {entry.name}")

        blobs: Dict[str, bytes] = {}
        for name in OUTPUT_FILES:
            expected_size, expected_digest = release_specs[name]
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            try:
                descriptor = os.open(directory / name, flags)
                try:
                    metadata = os.fstat(descriptor)
                    if (
                        not stat.S_ISREG(metadata.st_mode)
                        or metadata.st_size != expected_size
                    ):
                        raise QuantizationError(
                            f"ROM differs from committed Q0 release: {name}"
                        )
                    with os.fdopen(descriptor, "rb", closefd=False) as stream:
                        payload = stream.read(expected_size + 1)
                finally:
                    os.close(descriptor)
            except OSError as exc:
                raise QuantizationError(f"cannot read ROM artifact {name}: {exc}") from exc
            blobs[name] = payload
            actual_digest = hashlib.sha256(blobs[name]).hexdigest()
            if len(blobs[name]) != expected_size or actual_digest != expected_digest:
                raise QuantizationError(
                    f"ROM differs from committed Q0 release: {name}"
                )
        manifest = _strict_json(blobs["manifest.json"], "ROM manifest")
        if (
            not isinstance(manifest, dict)
            or manifest.get("schema_version") != 1
            or manifest.get("profile") != PROFILE_NAME
        ):
            raise QuantizationError("unsupported ROM manifest identity")
        file_records = manifest.get("files")
        if not isinstance(file_records, list):
            raise QuantizationError("ROM manifest file table is malformed")
        expected_files = {}
        for record in file_records:
            if not isinstance(record, dict) or set(record) != {"path", "size", "sha256"}:
                raise QuantizationError("ROM file record is malformed")
            expected_files[record["path"]] = record
        if tuple(sorted(expected_files)) != ROM_FILES:
            raise QuantizationError("ROM manifest inventory is not exact")
        for name in ROM_FILES:
            record = expected_files[name]
            if len(blobs[name]) != record["size"] or hashlib.sha256(blobs[name]).hexdigest() != record["sha256"]:
                raise QuantizationError(f"ROM hash or size mismatch: {name}")

        weight_blob = blobs["weights.i10.lsb0.bin"]
        exponent_blob = blobs["exponents.i8.bin"]
        multiplier_blob = blobs["multipliers.u16le.bin"]
        tensor_records = manifest.get("tensors", [])
        if not isinstance(tensor_records, list):
            raise QuantizationError("quantized tensor table is malformed")
        total_values = sum(
            record.get("values", {}).get("count", 0)
            for record in tensor_records
            if isinstance(record, dict)
        )
        unpacked_weights = _unpack_int10(weight_blob, total_values)
        # `_unpack_int10` gives every tensor view an immutable bytes object at
        # the end of its base chain, so callers cannot re-enable writes after
        # authentication.
        tensors: Dict[str, QuantizedTensor] = {}
        value_cursor = 0
        for record in tensor_records:
            name = record["name"]
            shape = tuple(record["shape"])
            value_spec = record["values"]
            exponent_spec = record["exponents"]
            multiplier_spec = record["multipliers"]
            value_count = int(np.prod(shape, dtype=np.int64))
            if (
                value_spec.get("dtype") != "int10_twos_complement_lsb0"
                or value_spec.get("count") != value_count
                or value_spec.get("bit_offset") != value_cursor * 10
                or value_spec.get("bit_size") != value_count * 10
            ):
                raise QuantizationError(f"tensor int10 layout mismatch: {name}")
            value = unpacked_weights[
                value_cursor : value_cursor + value_count
            ].reshape(shape)
            value_cursor += value_count
            value_bytes = value.astype("<i2", copy=False).tobytes(order="C")
            exponent_bytes = exponent_blob[
                exponent_spec["offset"] : exponent_spec["offset"] + exponent_spec["count"]
            ]
            multiplier_offset = multiplier_spec["offset"]
            multiplier_size = multiplier_spec["count"] * 2
            multiplier_bytes = multiplier_blob[
                multiplier_offset : multiplier_offset + multiplier_size
            ]
            if (
                hashlib.sha256(value_bytes).hexdigest()
                != value_spec["canonical_int16le_sha256"]
            ):
                raise QuantizationError(f"tensor value hash mismatch: {name}")
            if hashlib.sha256(exponent_bytes).hexdigest() != exponent_spec["sha256"]:
                raise QuantizationError(f"tensor exponent hash mismatch: {name}")
            if (
                hashlib.sha256(multiplier_bytes).hexdigest()
                != multiplier_spec["sha256"]
            ):
                raise QuantizationError(f"tensor multiplier hash mismatch: {name}")
            exponent = np.frombuffer(exponent_bytes, dtype=np.int8)
            multiplier = np.frombuffer(multiplier_bytes, dtype="<u2")
            if np.any(multiplier == 0) or np.any(multiplier > 32767):
                raise QuantizationError(f"tensor multiplier is outside uint15: {name}")
            value.flags.writeable = False
            exponent.flags.writeable = False
            multiplier.flags.writeable = False
            if name in tensors:
                raise QuantizationError(f"duplicate tensor record: {name}")
            tensors[name] = QuantizedTensor(value, exponent, multiplier)
        if len(tensors) != 56 or value_cursor != total_values:
            raise QuantizationError("quantized tensor inventory must contain 56 tensors")

        def array(name: str, dtype: str, shape: Tuple[int, ...]) -> np.ndarray:
            result = np.frombuffer(blobs[name], dtype=np.dtype(dtype)).reshape(shape)
            result.flags.writeable = False
            return result

        return cls(
            tensors,
            array("rope_cos_q15.i16le.bin", "<i2", (512, 32)),
            array("rope_sin_q15.i16le.bin", "<i2", (512, 32)),
            array("silu_q10.i16le.bin", "<i2", (65536,)),
            array("exp_neg_q30.i32le.bin", "<i4", (4097,)),
            manifest,
        )


class IntegerLlama:
    """Integer-only token inference after ROM artifacts have been loaded."""

    def __init__(self, model: QuantizedModel) -> None:
        self.model = model
        self.stats = OracleStats()
        self.keys: list[list[BFP]] = [[] for _ in range(6)]
        self.values: list[list[BFP]] = [[] for _ in range(6)]
        self.position = 0
        self.faulted = False

    def clear(self) -> None:
        self.keys = [[] for _ in range(6)]
        self.values = [[] for _ in range(6)]
        self.position = 0
        self.faulted = False

    def _embedding(self, token_id: int) -> BFP:
        tensor = self.model.tensors["model.embed_tokens.weight"]
        return _normalize(
            tensor.value[token_id].astype(np.int64)
            * int(tensor.multiplier[token_id]),
            int(tensor.exponent[token_id]) - 15,
            self.stats,
        )

    def _matvec(self, name: str, vector: BFP) -> BFP:
        tensor = self.model.tensors[name]
        dot = tensor.value.astype(np.int64) @ vector.value.astype(np.int64)
        maximum = int(np.max(np.abs(dot)))
        self.stats.max_matrix_accumulator = max(
            self.stats.max_matrix_accumulator, maximum
        )
        if maximum >= (1 << (MATRIX_ACCUMULATOR_BITS - 1)):
            raise QuantizationError("matrix accumulator exceeds signed 35-bit profile")
        scaled = dot * tensor.multiplier.astype(np.int64)
        maximum_scaled = int(np.max(np.abs(scaled)))
        self.stats.max_scale_product = max(
            self.stats.max_scale_product, maximum_scaled
        )
        if maximum_scaled >= (1 << (SCALE_PRODUCT_BITS - 1)):
            raise QuantizationError("weight scale product exceeds signed 50-bit profile")
        exponents = tensor.exponent.astype(np.int16) + vector.exponent - 15
        return _normalize_mixed(scaled, exponents, self.stats)

    def _rms_norm(self, vector: BFP, weight_name: str) -> BFP:
        squares = vector.value.astype(np.int64) ** 2
        square_sum = int(np.sum(squares))
        self.stats.max_rms_square_sum = max(
            self.stats.max_rms_square_sum, square_sum
        )
        if square_sum >= (1 << 38):
            raise QuantizationError("RMS square sum exceeds unsigned 38-bit profile")
        mean_square = _round_div_even_scalar(square_sum, squares.size)
        epsilon_shift = -20 - 2 * vector.exponent
        epsilon_integer = (
            _round_shift_even_scalar(1, -epsilon_shift)
            if epsilon_shift < 0
            else 1 << epsilon_shift
        )
        radicand = max(1, mean_square + epsilon_integer)
        self.stats.max_rms_radicand = max(self.stats.max_rms_radicand, radicand)
        if radicand >= (1 << 45):
            raise QuantizationError("RMS radicand exceeds unsigned 45-bit profile")
        rms = math.isqrt(radicand)
        maximum_numerator = int(np.max(np.abs(vector.value.astype(np.int64)))) << RMS_UNIT_FRACTION
        self.stats.max_rms_division_numerator = max(
            self.stats.max_rms_division_numerator, maximum_numerator
        )
        if maximum_numerator >= (1 << 27):
            raise QuantizationError("RMS division numerator exceeds signed 28-bit profile")
        normalized = np.fromiter(
            (
                _round_div_even_scalar(int(value) << RMS_UNIT_FRACTION, rms)
                for value in vector.value
            ),
            dtype=np.int64,
            count=vector.value.size,
        ).reshape(vector.value.shape)
        clipped = np.clip(normalized, I16_MIN, I16_MAX)
        self.stats.observe_saturation(
            f"{weight_name}:rms_q3_12",
            int(np.count_nonzero(clipped != normalized)),
        )
        normalized = clipped.astype(np.int16)
        weight = self.model.tensors[weight_name]
        products = (
            normalized.astype(np.int64)
            * weight.value.astype(np.int64)
            * int(weight.multiplier[0])
        )
        maximum_product = int(np.max(np.abs(products)))
        self.stats.max_rms_weight_product = max(
            self.stats.max_rms_weight_product, maximum_product
        )
        if maximum_product >= (1 << 39):
            raise QuantizationError("RMS weight product exceeds signed 40-bit profile")
        return _normalize(
            products,
            int(weight.exponent[0]) - 15 - RMS_UNIT_FRACTION,
            self.stats,
        )

    def _rope(self, vector: BFP, position: int) -> BFP:
        heads = vector.value.reshape(-1, 64).astype(np.int64)
        first, second = heads[:, :32], heads[:, 32:]
        cosine = self.model.rope_cos[position].astype(np.int64)
        sine = self.model.rope_sin[position].astype(np.int64)
        rotated_first = first * cosine - second * sine
        rotated_second = second * cosine + first * sine
        maximum = max(
            int(np.max(np.abs(rotated_first))),
            int(np.max(np.abs(rotated_second))),
        )
        self.stats.max_rope_accumulator = max(self.stats.max_rope_accumulator, maximum)
        if maximum >= (1 << 31):
            raise QuantizationError("RoPE accumulator exceeds signed 32-bit profile")
        joined = np.concatenate((rotated_first, rotated_second), axis=1)
        rounded = _round_shift_even(joined, 15)
        return _normalize(rounded.reshape(vector.value.shape), vector.exponent, self.stats)

    def _attention(self, query: BFP, layer: int) -> BFP:
        query_heads = query.value.reshape(4, 64).astype(np.int64)
        head_outputs = []
        head_exponents = []
        for query_head in range(4):
            kv_head = query_head // 2
            score_values = []
            score_exponents = []
            for key in self.keys[layer]:
                key_head = key.value.reshape(2, 64)[kv_head].astype(np.int64)
                score = int(query_heads[query_head] @ key_head)
                self.stats.max_attention_score_accumulator = max(
                    self.stats.max_attention_score_accumulator, abs(score)
                )
                if abs(score) >= (1 << 36):
                    raise QuantizationError("attention dot exceeds signed 37-bit profile")
                score_values.append(score)
                score_exponents.append(query.exponent + key.exponent - 3)
            scores = _normalize_mixed(
                np.array(score_values, dtype=np.int64),
                np.array(score_exponents, dtype=np.int16),
                self.stats,
            )
            maximum = int(np.max(scores.value))
            differences = scores.value.astype(np.int64) - maximum
            q8 = _round_shift_even(differences, -(scores.exponent + SOFTMAX_FRACTION))
            clipped = np.clip(q8, -4096, 0)
            self.stats.softmax_clips += int(np.count_nonzero(q8 != clipped))
            exponentials = self.model.exp_neg[(-clipped).astype(np.int64)].astype(np.int64)
            denominator = int(np.sum(exponentials, dtype=np.int64))
            self.stats.max_softmax_denominator = max(
                self.stats.max_softmax_denominator, denominator
            )
            if denominator <= 0 or denominator >= (1 << 40):
                raise QuantizationError(
                    "softmax denominator exceeds unsigned 40-bit profile"
                )
            maximum_probability_numerator = (
                int(np.max(exponentials)) * Q_PROBABILITY
            )
            self.stats.max_softmax_probability_numerator = max(
                self.stats.max_softmax_probability_numerator,
                maximum_probability_numerator,
            )
            if maximum_probability_numerator >= (1 << 45):
                raise QuantizationError(
                    "softmax probability numerator exceeds unsigned 45-bit profile"
                )
            probabilities = np.fromiter(
                (
                    _round_div_even_scalar(int(value) * Q_PROBABILITY, denominator)
                    for value in exponentials
                ),
                dtype=np.int64,
                count=exponentials.size,
            )

            selected_values = [
                value.value.reshape(2, 64)[kv_head] for value in self.values[layer]
            ]
            value_array = np.stack(selected_values).astype(np.int64)
            value_exponents = np.array(
                [value.exponent for value in self.values[layer]], dtype=np.int16
            )[:, None]
            aligned = _normalize_mixed(value_array, value_exponents, self.stats)
            accumulator = probabilities @ aligned.value.astype(np.int64)
            maximum_accumulator = int(np.max(np.abs(accumulator)))
            self.stats.max_attention_accumulator = max(
                self.stats.max_attention_accumulator, maximum_accumulator
            )
            if maximum_accumulator >= (1 << 39):
                raise QuantizationError(
                    "attention value accumulator exceeds signed 40-bit profile"
                )
            output = np.fromiter(
                (
                    _round_div_even_scalar(int(value), Q_PROBABILITY)
                    for value in accumulator
                ),
                dtype=np.int64,
                count=64,
            )
            head_outputs.append(output)
            head_exponents.append(np.full(64, aligned.exponent, dtype=np.int16))
        return _normalize_mixed(
            np.concatenate(head_outputs),
            np.concatenate(head_exponents),
            self.stats,
        )

    def _silu(self, vector: BFP) -> BFP:
        q10 = _round_shift_even(
            vector.value.astype(np.int64), -(vector.exponent + SILU_FRACTION)
        )
        clipped = np.clip(q10, -32768, 32767)
        self.stats.silu_clips += int(np.count_nonzero(q10 != clipped))
        output = self.model.silu[(clipped + 32768).astype(np.int64)]
        return BFP(output.copy(), -SILU_FRACTION)

    def _multiply(self, left: BFP, right: BFP) -> BFP:
        products = left.value.astype(np.int64) * right.value.astype(np.int64)
        maximum = int(np.max(np.abs(products)))
        self.stats.max_elementwise_product = max(
            self.stats.max_elementwise_product, maximum
        )
        if maximum >= (1 << 30):
            raise QuantizationError("elementwise product exceeds signed 31-bit profile")
        return _normalize(products, left.exponent + right.exponent, self.stats)

    def _layer(self, hidden: BFP, layer: int, position: int) -> BFP:
        prefix = f"model.layers.{layer}"
        normalized = self._rms_norm(hidden, f"{prefix}.input_layernorm.weight")
        query = self._rope(
            self._matvec(f"{prefix}.self_attn.q_proj.weight", normalized), position
        )
        key = self._rope(
            self._matvec(f"{prefix}.self_attn.k_proj.weight", normalized), position
        )
        value = self._matvec(f"{prefix}.self_attn.v_proj.weight", normalized)
        self.keys[layer].append(key)
        self.values[layer].append(value)
        attention = self._attention(query, layer)
        attention = self._matvec(f"{prefix}.self_attn.o_proj.weight", attention)
        hidden = _add(hidden, attention, self.stats)

        normalized = self._rms_norm(
            hidden, f"{prefix}.post_attention_layernorm.weight"
        )
        gate = self._matvec(f"{prefix}.mlp.gate_proj.weight", normalized)
        up = self._matvec(f"{prefix}.mlp.up_proj.weight", normalized)
        product = self._multiply(self._silu(gate), up)
        down = self._matvec(f"{prefix}.mlp.down_proj.weight", product)
        return _add(hidden, down, self.stats)

    @staticmethod
    def _greater(
        left_value: int, left_exponent: int, right_value: int, right_exponent: int
    ) -> bool:
        common = min(left_exponent, right_exponent)
        return (left_value << (left_exponent - common)) > (
            right_value << (right_exponent - common)
        )

    def _argmax(self, hidden: BFP) -> Tuple[int, int, int]:
        embedding = self.model.tensors["model.embed_tokens.weight"]
        best_token = 0
        best_value = 0
        best_exponent = 0
        for start in range(0, 4019, 256):
            block = embedding.value[start : start + 256].astype(np.int64)
            dots = block @ hidden.value.astype(np.int64)
            maximum = int(np.max(np.abs(dots)))
            self.stats.max_matrix_accumulator = max(
                self.stats.max_matrix_accumulator, maximum
            )
            if maximum >= (1 << (MATRIX_ACCUMULATOR_BITS - 1)):
                raise QuantizationError(
                    "logit matrix accumulator exceeds signed 35-bit profile"
                )
            multipliers = embedding.multiplier[start : start + len(dots)].astype(np.int64)
            accumulators = dots * multipliers
            maximum_scaled = int(np.max(np.abs(accumulators)))
            self.stats.max_scale_product = max(
                self.stats.max_scale_product, maximum_scaled
            )
            if maximum_scaled >= (1 << (SCALE_PRODUCT_BITS - 1)):
                raise QuantizationError("logit scale product exceeds signed 50-bit profile")
            for offset, accumulator in enumerate(accumulators):
                token = start + offset
                exponent = hidden.exponent + int(embedding.exponent[token]) - 15
                if token == 0 or self._greater(
                    int(accumulator), exponent, best_value, best_exponent
                ):
                    best_token = token
                    best_value = int(accumulator)
                    best_exponent = exponent
        return best_token, best_value, best_exponent

    def _logits(self, hidden: BFP) -> np.ndarray:
        """Materialize dequantized logits derived only from integer dot products."""

        embedding = self.model.tensors["model.embed_tokens.weight"]
        logits = np.empty(4019, dtype=np.float64)
        for start in range(0, 4019, 256):
            block = embedding.value[start : start + 256].astype(np.int64)
            dots = block @ hidden.value.astype(np.int64)
            maximum_dot = int(np.max(np.abs(dots)))
            self.stats.max_matrix_accumulator = max(
                self.stats.max_matrix_accumulator, maximum_dot
            )
            if maximum_dot >= (1 << (MATRIX_ACCUMULATOR_BITS - 1)):
                raise QuantizationError(
                    "logit matrix accumulator exceeds signed 35-bit profile"
                )
            multipliers = embedding.multiplier[start : start + len(dots)].astype(
                np.int64
            )
            scaled = dots * multipliers
            maximum_scaled = int(np.max(np.abs(scaled)))
            self.stats.max_scale_product = max(
                self.stats.max_scale_product, maximum_scaled
            )
            if maximum_scaled >= (1 << (SCALE_PRODUCT_BITS - 1)):
                raise QuantizationError(
                    "logit scale product exceeds signed 50-bit profile"
                )
            exponents = (
                embedding.exponent[start : start + len(dots)].astype(np.int16)
                + hidden.exponent
                - 15
            )
            logits[start : start + len(dots)] = np.ldexp(
                scaled.astype(np.float64), exponents.astype(np.int32)
            )
        return logits

    def forward_token_logits(self, token_id: int) -> Tuple[int, float, np.ndarray]:
        """Consume one token and return greedy result plus all integer-derived logits."""

        if type(token_id) is not int or not 0 <= token_id < 4019:
            raise ValueError("token ID must be an integer in [0, 4019)")
        if self.faulted:
            raise QuantizationError(
                "integer oracle is latched in RANGE_FAULT until CLEAR"
            )
        if self.position >= 512:
            raise ValueError("integer oracle context is full at 512 tokens")
        try:
            hidden = self._embedding(token_id)
            for layer in range(6):
                hidden = self._layer(hidden, layer, self.position)
            hidden = self._rms_norm(hidden, "model.norm.weight")
            logits = self._logits(hidden)
            token = int(np.argmax(logits))
            self.position += 1
            return token, float(logits[token]), logits
        except QuantizationError:
            self.faulted = True
            raise

    def forward_token(self, token_id: int) -> Tuple[int, float]:
        if type(token_id) is not int or not 0 <= token_id < 4019:
            raise ValueError("token ID must be an integer in [0, 4019)")
        if self.faulted:
            raise QuantizationError(
                "integer oracle is latched in RANGE_FAULT until CLEAR"
            )
        if self.position >= 512:
            raise ValueError("integer oracle context is full at 512 tokens")
        try:
            hidden = self._embedding(token_id)
            for layer in range(6):
                hidden = self._layer(hidden, layer, self.position)
            hidden = self._rms_norm(hidden, "model.norm.weight")
            token, value, exponent = self._argmax(hidden)
            self.position += 1
            return token, math.ldexp(float(value), exponent)
        except QuantizationError:
            self.faulted = True
            raise

    def score_token(self, token_id: int, target_id: int) -> Tuple[int, float]:
        """Consume a token and return prediction plus target negative log-likelihood."""

        if type(target_id) is not int or not 0 <= target_id < 4019:
            raise ValueError("target ID must be an integer in [0, 4019)")
        prediction, _best, logits = self.forward_token_logits(token_id)
        maximum = float(np.max(logits))
        log_normalizer = maximum + math.log(
            float(np.sum(np.exp(logits - maximum), dtype=np.float64))
        )
        return prediction, log_normalizer - float(logits[target_id])

    def prefill(self, prompt: Sequence[int]) -> Tuple[int, float]:
        if not prompt or len(prompt) > 512:
            raise ValueError("prompt length must be in [1, 512]")
        self.clear()
        prediction = (0, float("-inf"))
        for token in prompt:
            prediction = self.forward_token(token)
        return prediction

    def generate(
        self, prompt: Sequence[int], max_new_tokens: int, *, stop_at_eos: bool = True
    ) -> list[int]:
        if type(max_new_tokens) is not int or max_new_tokens < 0:
            raise ValueError("max_new_tokens must be nonnegative")
        if not prompt or len(prompt) > 512:
            raise ValueError("prompt length must be in [1, 512]")
        if any(type(token) is not int or not 0 <= token < 4019 for token in prompt):
            raise ValueError("prompt token IDs must be integers in [0, 4019)")
        if len(prompt) + max_new_tokens > 513:
            raise ValueError("generation exceeds the 513-slot tape")
        if max_new_tokens == 0:
            self.clear()
            return []
        token, _ = self.prefill(prompt)
        generated = []
        for index in range(max_new_tokens):
            generated.append(token)
            if stop_at_eos and token == 1:
                break
            if index + 1 < max_new_tokens:
                token, _ = self.forward_token(token)
        return generated

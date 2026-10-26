"""Dependency-light FP32 reference for SimpleStories-V2-5M.

This module intentionally does not import Transformers or execute model-supplied
Python.  It accepts only the one reviewed Llama geometry described by
``SimpleStoriesConfig`` and only the exact expected safetensors inventory.

The text tokenizer is outside the token machine's trusted computation.  The
model API below consumes integer token IDs.  ``validate_tokenizer`` checks the
tokenizer boundary contract without loading tokenizer executable code.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import stat
import struct
from types import MappingProxyType
from typing import Any, Dict, Mapping, Sequence, Tuple

import numpy as np


class ConfigurationError(ValueError):
    """The model or tokenizer configuration is not the pinned configuration."""


class ModelFormatError(ValueError):
    """The checkpoint container or tensor inventory is malformed."""


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PINNED_MANIFEST = PROJECT_ROOT / "upstream" / "manifest.json"
PINNED_REPOSITORY = "SimpleStories/SimpleStories-V2-5M"
PINNED_REVISION = "c4b3a4bb81297f5316697098e1d4b65c1249daf8"
PINNED_FILES = (
    "README.md",
    "config.json",
    "model.safetensors",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer_config.json",
)


def _json_bytes(payload: bytes, label: str) -> Any:
    def unique_object(pairs: Sequence[Tuple[str, Any]]) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ConfigurationError(f"{label} contains duplicate key {key!r}")
            result[key] = value
        return result

    try:
        return json.loads(payload.decode("utf-8"), object_pairs_hook=unique_object)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ConfigurationError(f"cannot parse {label}: {exc}") from exc


def _pinned_file_specs(manifest_path: Path = PINNED_MANIFEST) -> Dict[str, Tuple[int, str]]:
    """Read the committed data manifest without importing executable tooling."""

    try:
        document = _json_bytes(manifest_path.read_bytes(), "upstream manifest")
    except OSError as exc:
        raise ModelFormatError(f"cannot read pinned upstream manifest: {exc}") from exc
    if not isinstance(document, dict) or set(document) != {
        "schema_version",
        "repository",
        "revision",
        "license",
        "files",
    }:
        raise ModelFormatError("pinned upstream manifest has the wrong schema")
    if (
        document["schema_version"] != 1
        or type(document["schema_version"]) is not int
        or document["repository"] != PINNED_REPOSITORY
        or document["revision"] != PINNED_REVISION
        or document["license"] != "MIT"
        or not isinstance(document["files"], list)
    ):
        raise ModelFormatError("pinned upstream manifest identity is not supported")
    specs: Dict[str, Tuple[int, str]] = {}
    for entry in document["files"]:
        if not isinstance(entry, dict) or set(entry) != {"path", "size", "sha256", "url"}:
            raise ModelFormatError("malformed pinned file specification")
        name, size, digest, url = (
            entry["path"],
            entry["size"],
            entry["sha256"],
            entry["url"],
        )
        expected_url = (
            f"https://huggingface.co/{PINNED_REPOSITORY}/resolve/"
            f"{PINNED_REVISION}/{name}"
        )
        if (
            name not in PINNED_FILES
            or name in specs
            or type(size) is not int
            or size <= 0
            or not isinstance(digest, str)
            or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
            or url != expected_url
        ):
            raise ModelFormatError(f"invalid manifest specification for {name!r}")
        specs[name] = (size, digest)
    if tuple(sorted(specs)) != PINNED_FILES:
        raise ModelFormatError("pinned manifest file inventory is not exact")
    return specs


def _load_pinned_snapshot(directory: Path | str) -> Dict[str, bytes]:
    """Read and authenticate the complete six-file upstream snapshot."""

    directory = Path(directory)
    specs = _pinned_file_specs()
    try:
        entries = list(os.scandir(directory))
    except OSError as exc:
        raise ModelFormatError(f"cannot inspect upstream snapshot: {exc}") from exc
    names = sorted(entry.name for entry in entries)
    if names != list(PINNED_FILES):
        raise ModelFormatError(
            f"snapshot inventory is not exact; expected={list(PINNED_FILES)!r}, "
            f"found={names!r}"
        )
    blobs: Dict[str, bytes] = {}
    for entry in entries:
        try:
            mode = entry.stat(follow_symlinks=False).st_mode
        except OSError as exc:
            raise ModelFormatError(f"cannot inspect {entry.name!r}: {exc}") from exc
        if not stat.S_ISREG(mode) or entry.is_symlink():
            raise ModelFormatError(f"snapshot entry is not a regular file: {entry.name!r}")
        descriptor = None
        try:
            flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
            descriptor = os.open(entry.path, flags)
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise ModelFormatError(
                    f"snapshot entry is not a regular file: {entry.name!r}"
                )
            with os.fdopen(descriptor, "rb") as stream:
                descriptor = None
                payload = stream.read()
        except ModelFormatError:
            raise
        except OSError as exc:
            raise ModelFormatError(f"cannot read {entry.name!r}: {exc}") from exc
        finally:
            if descriptor is not None:
                os.close(descriptor)
        size, digest = specs[entry.name]
        if len(payload) != size:
            raise ModelFormatError(
                f"{entry.name}: expected {size} bytes, found {len(payload)}"
            )
        actual = hashlib.sha256(payload).hexdigest()
        if actual != digest:
            raise ModelFormatError(
                f"{entry.name}: SHA-256 mismatch; expected {digest}, found {actual}"
            )
        blobs[entry.name] = payload
    return blobs


@dataclass(frozen=True)
class SimpleStoriesConfig:
    """The only model geometry accepted by this reference implementation."""

    num_hidden_layers: int = 6
    hidden_size: int = 256
    intermediate_size: int = 682
    num_attention_heads: int = 4
    num_key_value_heads: int = 2
    head_dim: int = 64
    vocab_size: int = 4019
    max_position_embeddings: int = 2048
    interface_context: int = 512
    rms_norm_eps: float = 1.0e-6
    rope_theta: float = 10000.0
    eos_token_id: int = 1

    @classmethod
    def from_json(cls, path: Path | str) -> "SimpleStoriesConfig":
        """Validate a Hugging Face config and return the pinned runtime config.

        The published checkpoint's ``config.json`` declares ``eos_token_id=2``,
        although its tokenizer assigns ``[EOS]`` ID 1 and assigns ID 2 to ``!``.
        Generation therefore follows the separately checked tokenizer contract,
        EOS=1.  Every architectural value is still required to match exactly.
        """

        try:
            payload = Path(path).read_bytes()
        except OSError as exc:
            raise ConfigurationError(f"cannot read model config: {exc}") from exc
        return cls.from_bytes(payload)

    @classmethod
    def from_bytes(cls, payload: bytes) -> "SimpleStoriesConfig":
        """Validate model configuration bytes from an authenticated snapshot."""

        raw = _json_bytes(payload, "model config")
        if not isinstance(raw, dict):
            raise ConfigurationError("model config root must be an object")

        expected = {
            "architectures": ["LlamaForCausalLM"],
            "model_type": "llama",
            "num_hidden_layers": 6,
            "hidden_size": 256,
            "intermediate_size": 682,
            "num_attention_heads": 4,
            "num_key_value_heads": 2,
            "head_dim": 64,
            "vocab_size": 4019,
            "max_position_embeddings": 2048,
            "rms_norm_eps": 1.0e-6,
            "rope_theta": 10000.0,
            "hidden_act": "silu",
            "attention_bias": False,
            "mlp_bias": False,
            "tie_word_embeddings": True,
            "rope_scaling": None,
            "pretraining_tp": 1,
            "torch_dtype": "float32",
        }
        mismatches = [
            f"{key}: expected {value!r}, got {raw.get(key)!r}"
            for key, value in expected.items()
            if raw.get(key) != value or type(raw.get(key)) is not type(value)
        ]
        # Pin the known upstream metadata discrepancy instead of silently
        # accepting arbitrary special-token declarations.
        if raw.get("bos_token_id") != 1 or type(raw.get("bos_token_id")) is not int:
            mismatches.append(
                f"bos_token_id: expected 1, got {raw.get('bos_token_id')!r}"
            )
        if raw.get("eos_token_id") != 2 or type(raw.get("eos_token_id")) is not int:
            mismatches.append(
                "published config eos_token_id: expected 2, "
                f"got {raw.get('eos_token_id')!r}"
            )
        if mismatches:
            raise ConfigurationError("unsupported model config: " + "; ".join(mismatches))
        return cls()


def _expected_shapes(config: SimpleStoriesConfig) -> Dict[str, Tuple[int, ...]]:
    d = config.hidden_size
    ff = config.intermediate_size
    kv = config.num_key_value_heads * config.head_dim
    shapes: Dict[str, Tuple[int, ...]] = {
        "model.embed_tokens.weight": (config.vocab_size, d),
        "model.norm.weight": (d,),
    }
    for layer in range(config.num_hidden_layers):
        prefix = f"model.layers.{layer}"
        shapes.update(
            {
                f"{prefix}.input_layernorm.weight": (d,),
                f"{prefix}.post_attention_layernorm.weight": (d,),
                f"{prefix}.self_attn.q_proj.weight": (d, d),
                f"{prefix}.self_attn.k_proj.weight": (kv, d),
                f"{prefix}.self_attn.v_proj.weight": (kv, d),
                f"{prefix}.self_attn.o_proj.weight": (d, d),
                f"{prefix}.mlp.gate_proj.weight": (ff, d),
                f"{prefix}.mlp.up_proj.weight": (ff, d),
                f"{prefix}.mlp.down_proj.weight": (d, ff),
            }
        )
    return shapes


def _parse_safetensors_f32(blob: bytes) -> Dict[str, np.ndarray]:
    """Parse a strict, contiguous, little-endian F32 safetensors blob.

    A tiny reader keeps the reference independent of framework runtimes.  The
    complete file is retained as the arrays' immutable backing storage.
    """

    if len(blob) < 8:
        raise ModelFormatError("checkpoint is shorter than the safetensors prefix")
    header_len = struct.unpack_from("<Q", blob, 0)[0]
    if header_len == 0 or header_len > 16 * 1024 * 1024:
        raise ModelFormatError(f"implausible safetensors header length {header_len}")
    data_start = 8 + header_len
    if data_start > len(blob):
        raise ModelFormatError("safetensors header extends beyond end of file")
    def unique_header_object(
        pairs: Sequence[Tuple[str, Any]],
    ) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ModelFormatError(
                    f"safetensors header contains duplicate key {key!r}"
                )
            result[key] = value
        return result

    try:
        header = json.loads(
            blob[8:data_start].decode("utf-8"),
            object_pairs_hook=unique_header_object,
        )
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ModelFormatError(f"invalid safetensors header: {exc}") from exc
    if not isinstance(header, dict):
        raise ModelFormatError("safetensors header must be an object")

    metadata = header.get("__metadata__")
    if metadata is not None and (
        not isinstance(metadata, dict)
        or any(
            not isinstance(key, str) or not isinstance(value, str)
            for key, value in metadata.items()
        )
    ):
        raise ModelFormatError("safetensors __metadata__ must map strings to strings")

    payload_size = len(blob) - data_start
    entries = []
    for name, spec in header.items():
        if name == "__metadata__":
            continue
        if not isinstance(name, str) or not isinstance(spec, dict):
            raise ModelFormatError("malformed tensor entry")
        if spec.get("dtype") != "F32":
            raise ModelFormatError(f"{name}: only F32 tensors are accepted")
        shape = spec.get("shape")
        offsets = spec.get("data_offsets")
        if (
            not isinstance(shape, list)
            or not shape
            or any(type(dim) is not int or dim <= 0 for dim in shape)
            or not isinstance(offsets, list)
            or len(offsets) != 2
            or any(type(offset) is not int for offset in offsets)
        ):
            raise ModelFormatError(f"{name}: malformed shape or offsets")
        begin, end = offsets
        elements = math.prod(shape)
        nbytes = 4 * elements
        if begin < 0 or end < begin or end > payload_size or end - begin != nbytes:
            raise ModelFormatError(f"{name}: inconsistent data range")
        entries.append((begin, end, name, tuple(shape)))

    entries.sort()
    cursor = 0
    for begin, end, name, _ in entries:
        if begin != cursor:
            kind = "overlap" if begin < cursor else "gap"
            raise ModelFormatError(f"{name}: {kind} in tensor payload at byte {cursor}")
        cursor = end
    if cursor != payload_size:
        raise ModelFormatError("unclaimed bytes at end of tensor payload")

    tensors: Dict[str, np.ndarray] = {}
    for begin, _end, name, shape in entries:
        array = np.frombuffer(
            blob,
            dtype="<f4",
            count=math.prod(shape),
            offset=data_start + begin,
        )
        array = array.reshape(shape)
        array.flags.writeable = False
        if not np.all(np.isfinite(array)):
            raise ModelFormatError(f"{name}: checkpoint contains NaN or infinity")
        tensors[name] = array
    return tensors


def _load_safetensors_f32(path: Path | str) -> Dict[str, np.ndarray]:
    """Read and parse one local safetensors file (unit-test convenience API)."""

    try:
        blob = Path(path).read_bytes()
    except OSError as exc:
        raise ModelFormatError(f"cannot read checkpoint: {exc}") from exc
    return _parse_safetensors_f32(blob)


_SPECIAL_TOKEN_ENTRY_UNK = {
    "id": 0,
    "content": "[UNK]",
    "single_word": False,
    "lstrip": False,
    "rstrip": False,
    "normalized": False,
    "special": True,
}
_SPECIAL_TOKEN_ENTRY_EOS = {
    "id": 1,
    "content": "[EOS]",
    "single_word": False,
    "lstrip": False,
    "rstrip": False,
    "normalized": False,
    "special": True,
}
_TOKENIZER_NORMALIZER = {
    "type": "Sequence",
    "normalizers": [
        {"type": "Lowercase"},
        {"type": "Replace", "pattern": {"String": "``"}, "content": '"'},
        {"type": "Replace", "pattern": {"String": "''"}, "content": '"'},
    ],
}
_TOKENIZER_PRETOKENIZER = {
    "type": "Sequence",
    "pretokenizers": [
        {"type": "Whitespace"},
        {"type": "Punctuation", "behavior": "Isolated"},
        {"type": "Digits", "individual_digits": True},
    ],
}
_TOKENIZER_POSTPROCESSOR = {
    "type": "TemplateProcessing",
    "single": [
        {"Sequence": {"id": "A", "type_id": 0}},
        {"SpecialToken": {"id": "[EOS]", "type_id": 0}},
    ],
    "pair": [
        {"Sequence": {"id": "A", "type_id": 0}},
        {"Sequence": {"id": "B", "type_id": 1}},
    ],
    "special_tokens": {
        "[EOS]": {"id": "[EOS]", "ids": [1], "tokens": ["[EOS]"]}
    },
}
_TOKENIZER_CONFIG = {
    "added_tokens_decoder": {
        "0": {key: value for key, value in _SPECIAL_TOKEN_ENTRY_UNK.items() if key != "id"},
        "1": {key: value for key, value in _SPECIAL_TOKEN_ENTRY_EOS.items() if key != "id"},
    },
    "clean_up_tokenization_spaces": False,
    "eos_token": "[EOS]",
    "extra_special_tokens": {},
    "model_max_length": 512,
    "pad_token": "[UNK]",
    "tokenizer_class": "PreTrainedTokenizerFast",
    "unk_token": "[UNK]",
}
_SPECIAL_TOKENS_MAP = {
    "eos_token": "[EOS]",
    "pad_token": "[UNK]",
    "unk_token": "[UNK]",
}


def _validate_tokenizer_documents(
    tokenizer: Any, tokenizer_config: Any, special_tokens: Any
) -> None:
    """Validate every tokenizer behavior that defines the text/ID boundary."""

    if not isinstance(tokenizer, dict) or not isinstance(tokenizer_config, dict):
        raise ConfigurationError("tokenizer metadata roots must be objects")
    if set(tokenizer) != {
        "version",
        "truncation",
        "padding",
        "added_tokens",
        "normalizer",
        "pre_tokenizer",
        "post_processor",
        "decoder",
        "model",
    }:
        raise ConfigurationError("tokenizer.json top-level schema is not exact")
    failures = []
    if tokenizer.get("version") != "1.0":
        failures.append("tokenizer version must be 1.0")
    if tokenizer.get("truncation") is not None or tokenizer.get("padding") is not None:
        failures.append("tokenizer must not implicitly truncate or pad")
    if tokenizer.get("added_tokens") != [
        _SPECIAL_TOKEN_ENTRY_UNK,
        _SPECIAL_TOKEN_ENTRY_EOS,
    ]:
        failures.append("added token definitions are not exact")
    if tokenizer.get("normalizer") != _TOKENIZER_NORMALIZER:
        failures.append("lowercase/quote normalizer semantics are not exact")
    if tokenizer.get("pre_tokenizer") != _TOKENIZER_PRETOKENIZER:
        failures.append("whitespace/punctuation/digit pre-tokenizer semantics are not exact")
    if tokenizer.get("post_processor") != _TOKENIZER_POSTPROCESSOR:
        failures.append("EOS post-processor semantics are not exact")
    if tokenizer.get("decoder") != {
        "type": "WordPiece",
        "prefix": "##",
        "cleanup": True,
    }:
        failures.append("WordPiece decoder semantics are not exact")

    model = tokenizer.get("model")
    if not isinstance(model, dict) or set(model) != {
        "type",
        "unk_token",
        "continuing_subword_prefix",
        "max_input_chars_per_word",
        "vocab",
    }:
        failures.append("WordPiece model schema is not exact")
        vocab = None
    else:
        vocab = model["vocab"]
        if {key: model[key] for key in model if key != "vocab"} != {
            "type": "WordPiece",
            "unk_token": "[UNK]",
            "continuing_subword_prefix": "##",
            "max_input_chars_per_word": 100,
        }:
            failures.append("WordPiece model semantics are not exact")
    if not isinstance(vocab, dict) or len(vocab) != 4019:
        failures.append("tokenizer vocabulary must contain 4019 entries")
    else:
        if vocab.get("[UNK]") != 0 or vocab.get("[EOS]") != 1 or vocab.get("!") != 2:
            failures.append("token IDs 0, 1, and 2 must be [UNK], [EOS], and !")
        ids = list(vocab.values())
        if any(type(token_id) is not int for token_id in ids):
            failures.append("tokenizer IDs must be integers")
        elif set(ids) != set(range(4019)):
            failures.append("tokenizer IDs must be a bijection onto [0, 4019)")
    if tokenizer_config != _TOKENIZER_CONFIG:
        failures.append("tokenizer_config.json semantics are not exact")
    if special_tokens != _SPECIAL_TOKENS_MAP:
        failures.append("special_tokens_map.json semantics are not exact")
    if failures:
        raise ConfigurationError("unsupported tokenizer: " + "; ".join(failures))


def validate_tokenizer(directory: Path | str) -> None:
    """Check the tokenizer facts used by the token-machine boundary.

    Encoding must be requested with ``add_special_tokens=False`` by the caller;
    that is an API choice and is not encoded as a tokenizer-file setting.  This
    check establishes the corresponding fixed facts: vocabulary size 4019,
    ``[EOS]`` ID 1, and an interface context limit of 512.
    """

    directory = Path(directory)
    try:
        tokenizer = _json_bytes((directory / "tokenizer.json").read_bytes(), "tokenizer.json")
        tokenizer_config = _json_bytes(
            (directory / "tokenizer_config.json").read_bytes(), "tokenizer_config.json"
        )
        special_tokens = _json_bytes(
            (directory / "special_tokens_map.json").read_bytes(),
            "special_tokens_map.json",
        )
    except OSError as exc:
        raise ConfigurationError(f"cannot read tokenizer metadata: {exc}") from exc
    _validate_tokenizer_documents(tokenizer, tokenizer_config, special_tokens)


def checkpoint_sha256(path: Path | str) -> str:
    """Return the checkpoint digest without making it part of model execution."""

    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class SimpleStoriesReference:
    """Stateful, KV-cached, greedy FP32 inference for the pinned checkpoint."""

    def __init__(
        self,
        tensors: Mapping[str, np.ndarray],
        config: SimpleStoriesConfig = SimpleStoriesConfig(),
    ) -> None:
        if config != SimpleStoriesConfig():
            raise ConfigurationError("runtime accepts only the pinned model geometry")
        expected = _expected_shapes(config)
        missing = sorted(set(expected) - set(tensors))
        extra = sorted(set(tensors) - set(expected))
        if missing or extra:
            raise ModelFormatError(
                f"wrong tensor inventory; missing={missing!r}, extra={extra!r}"
            )
        checked: Dict[str, np.ndarray] = {}
        for name, shape in expected.items():
            value = np.asarray(tensors[name])
            if value.dtype != np.dtype("float32") or value.shape != shape:
                raise ModelFormatError(
                    f"{name}: expected F32 {shape}, got {value.dtype} {value.shape}"
                )
            if not np.all(np.isfinite(value)):
                raise ModelFormatError(f"{name}: contains NaN or infinity")
            # Back the array with immutable bytes.  A caller retaining a
            # mutable source cannot change it, and setflags(write=True) fails.
            value = np.frombuffer(value.tobytes(order="C"), dtype=np.float32).reshape(
                shape
            )
            value.flags.writeable = False
            checked[name] = value
        self.config = config
        self.tensors = MappingProxyType(checked)
        self._inv_freq = (
            np.float32(1.0)
            / np.power(
                np.float32(config.rope_theta),
                np.arange(0, config.head_dim, 2, dtype=np.float32)
                / np.float32(config.head_dim),
            )
        ).astype(np.float32)
        cache_shape = (
            config.num_hidden_layers,
            config.interface_context,
            config.num_key_value_heads,
            config.head_dim,
        )
        self._keys = np.zeros(cache_shape, dtype=np.float32)
        self._values = np.zeros(cache_shape, dtype=np.float32)
        self.position = 0

    def clear(self) -> None:
        """Reset logical context; stale cache cells become unreachable."""

        self.position = 0

    @staticmethod
    def _rms_norm(x: np.ndarray, weight: np.ndarray, eps: float) -> np.ndarray:
        variance = np.mean(np.square(x, dtype=np.float32), dtype=np.float32)
        scale = np.float32(1.0) / np.sqrt(variance + np.float32(eps))
        return np.multiply(
            weight, np.multiply(x, scale, dtype=np.float32), dtype=np.float32
        )

    def _rope(self, x: np.ndarray, position: int) -> np.ndarray:
        frequencies = self._inv_freq * np.float32(position)
        angles = np.concatenate((frequencies, frequencies))
        cos = np.cos(angles).astype(np.float32)
        sin = np.sin(angles).astype(np.float32)
        half = self.config.head_dim // 2
        rotated = np.concatenate((-x[:, half:], x[:, :half]), axis=1)
        return np.add(x * cos, rotated * sin, dtype=np.float32)

    @staticmethod
    def _softmax(scores: np.ndarray) -> np.ndarray:
        shifted = scores - np.max(scores, axis=-1, keepdims=True)
        numerator = np.exp(shifted).astype(np.float32)
        denominator = np.sum(numerator, axis=-1, keepdims=True, dtype=np.float32)
        return np.divide(numerator, denominator, dtype=np.float32)

    def _layer(self, hidden: np.ndarray, layer: int, position: int) -> np.ndarray:
        cfg = self.config
        prefix = f"model.layers.{layer}"
        normed = self._rms_norm(
            hidden, self.tensors[f"{prefix}.input_layernorm.weight"], cfg.rms_norm_eps
        )
        q = self.tensors[f"{prefix}.self_attn.q_proj.weight"] @ normed
        k = self.tensors[f"{prefix}.self_attn.k_proj.weight"] @ normed
        v = self.tensors[f"{prefix}.self_attn.v_proj.weight"] @ normed
        q = self._rope(q.reshape(cfg.num_attention_heads, cfg.head_dim), position)
        k = self._rope(k.reshape(cfg.num_key_value_heads, cfg.head_dim), position)
        v = v.reshape(cfg.num_key_value_heads, cfg.head_dim)
        self._keys[layer, position] = k
        self._values[layer, position] = v

        # GQA maps consecutive pairs of query heads to each KV head.
        repeats = cfg.num_attention_heads // cfg.num_key_value_heads
        keys = np.repeat(self._keys[layer, : position + 1], repeats, axis=1)
        values = np.repeat(self._values[layer, : position + 1], repeats, axis=1)
        scores = np.einsum("hd,thd->ht", q, keys, dtype=np.float32)
        scores *= np.float32(1.0 / np.sqrt(np.float32(cfg.head_dim)))
        probabilities = self._softmax(scores)
        attention = np.einsum("ht,thd->hd", probabilities, values, dtype=np.float32)
        attention = attention.reshape(cfg.hidden_size)
        attention = self.tensors[f"{prefix}.self_attn.o_proj.weight"] @ attention
        hidden = np.add(hidden, attention, dtype=np.float32)

        normed = self._rms_norm(
            hidden,
            self.tensors[f"{prefix}.post_attention_layernorm.weight"],
            cfg.rms_norm_eps,
        )
        gate = self.tensors[f"{prefix}.mlp.gate_proj.weight"] @ normed
        up = self.tensors[f"{prefix}.mlp.up_proj.weight"] @ normed
        sigmoid = np.float32(1.0) / (
            np.float32(1.0) + np.exp(-gate).astype(np.float32)
        )
        activated = np.multiply(gate, sigmoid, dtype=np.float32)
        mlp = self.tensors[f"{prefix}.mlp.down_proj.weight"] @ np.multiply(
            activated, up, dtype=np.float32
        )
        return np.add(hidden, mlp, dtype=np.float32)

    @staticmethod
    def _streaming_argmax(
        embedding: np.ndarray, hidden: np.ndarray, block_rows: int = 256
    ) -> Tuple[int, np.float32]:
        """Find the tied-head argmax without materializing the complete logits."""

        if type(block_rows) is not int or block_rows <= 0:
            raise ValueError("block_rows must be a positive integer")
        best_token = 0
        best_logit = np.float32(-np.inf)
        for start in range(0, embedding.shape[0], block_rows):
            logits = embedding[start : start + block_rows] @ hidden
            local = int(np.argmax(logits))
            value = np.float32(logits[local])
            # Strict greater-than preserves the lowest token ID on exact ties.
            if value > best_logit:
                best_token = start + local
                best_logit = value
        return best_token, best_logit

    def forward_token(
        self, token_id: int, *, logit_block_rows: int = 256
    ) -> Tuple[int, np.float32]:
        """Consume one token and return the greedy prediction and its logit."""

        cfg = self.config
        if type(token_id) is not int or not 0 <= token_id < cfg.vocab_size:
            raise ValueError(f"token ID must be an integer in [0, {cfg.vocab_size})")
        if self.position >= cfg.interface_context:
            raise ValueError(f"context is full at {cfg.interface_context} tokens")
        position = self.position
        hidden = self.tensors["model.embed_tokens.weight"][token_id].copy()
        for layer in range(cfg.num_hidden_layers):
            hidden = self._layer(hidden, layer, position)
        hidden = self._rms_norm(
            hidden, self.tensors["model.norm.weight"], cfg.rms_norm_eps
        )
        prediction = self._streaming_argmax(
            self.tensors["model.embed_tokens.weight"], hidden, logit_block_rows
        )
        self.position += 1
        return prediction

    def prefill(self, token_ids: Sequence[int]) -> Tuple[int, np.float32]:
        """Clear the cache, consume a nonempty prompt, and predict one token."""

        if not token_ids:
            raise ValueError("prompt must contain at least one token")
        if len(token_ids) > self.config.interface_context:
            raise ValueError("prompt exceeds the 512-token interface context")
        self.clear()
        prediction = (0, np.float32(-np.inf))
        for token_id in token_ids:
            prediction = self.forward_token(token_id)
        return prediction

    def generate(
        self,
        prompt: Sequence[int],
        max_new_tokens: int,
        *,
        stop_at_eos: bool = True,
    ) -> list[int]:
        """Greedily generate token IDs from a raw-token prompt.

        No token is automatically added to ``prompt``.  In particular, callers
        must encode text with ``add_special_tokens=False``.  The evaluated
        context is at most 512 tokens, while the physical protocol has a 513th
        tape slot for the final returned token.  Thus a 512-token prompt can
        produce one terminal token, but that token cannot itself be evaluated.
        """

        if type(max_new_tokens) is not int or max_new_tokens < 0:
            raise ValueError("max_new_tokens must be a nonnegative integer")
        if not prompt:
            raise ValueError("prompt must contain at least one token")
        if len(prompt) > self.config.interface_context:
            raise ValueError("prompt exceeds the 512-token model context")
        if any(
            type(token_id) is not int
            or not 0 <= token_id < self.config.vocab_size
            for token_id in prompt
        ):
            raise ValueError(
                f"token IDs must be integers in [0, {self.config.vocab_size})"
            )
        if len(prompt) + max_new_tokens > self.config.interface_context + 1:
            raise ValueError("requested generation can exceed the 513-slot tape")
        if max_new_tokens == 0:
            self.clear()
            return []
        next_token, _ = self.prefill(prompt)
        generated = []
        for index in range(max_new_tokens):
            generated.append(next_token)
            if stop_at_eos and next_token == self.config.eos_token_id:
                break
            if index + 1 < max_new_tokens:
                next_token, _ = self.forward_token(next_token)
        return generated


def load_model(directory: Path | str) -> SimpleStoriesReference:
    """Authenticate, parse, and load the exact pinned upstream snapshot."""

    blobs = _load_pinned_snapshot(directory)
    config = SimpleStoriesConfig.from_bytes(blobs["config.json"])
    _validate_tokenizer_documents(
        _json_bytes(blobs["tokenizer.json"], "tokenizer.json"),
        _json_bytes(blobs["tokenizer_config.json"], "tokenizer_config.json"),
        _json_bytes(blobs["special_tokens_map.json"], "special_tokens_map.json"),
    )
    tensors = _parse_safetensors_f32(blobs["model.safetensors"])
    return SimpleStoriesReference(tensors, config)

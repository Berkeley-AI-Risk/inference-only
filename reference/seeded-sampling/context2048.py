"""Portable 2048-position extension of the unchanged Q0 integer model.

Adapted from the project-owned adapter SHA-256
810125faf6a7cdb3ba218d8de5ff89b6488741eea9dd2fc6bbcb3fc5671ecdd2.
Only context/RoPE geometry and the 42-bit attention denominator bound extend Q0.
"""
from __future__ import annotations
import hashlib
import math
from typing import Optional, Tuple
import numpy as np
from quantization import oracle as q0

def sha256(payload):return hashlib.sha256(payload).hexdigest()

CONTEXT = 2048
ROPE_COS_SHA256 = (
    "79f7f407afea8759b487b1c1af04086514011cf4541a13e6fb7113bc03697e5a"
)
ROPE_SIN_SHA256 = (
    "4acbdcf5d0d83ad9dca7a1a8619ba5e481d594365751b2fb564eaf4e13a8201f"
)
FROZEN_Q0_MANIFEST_SHA256 = (
    "b921e209e53c8d8c52fbabc20e464b85affc537fb705d5472261e0a29a8df0c1"
)
REPRODUCED_Q0_MANIFEST_SHA256 = (
    "f801609a7ca9cd8a270669d557ff0837b897ceabaab802dafbf94205bdafb8ab"
)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def q15(value: float) -> int:
    return min(32767, max(-32768, int(round(value * 32768.0))))


def derive_rope() -> Tuple[np.ndarray, np.ndarray]:
    inverse = [
        math.pow(10000.0, -float(2 * index) / 64.0)
        for index in range(32)
    ]
    cosine = np.empty((CONTEXT, 32), dtype="<i2")
    sine = np.empty((CONTEXT, 32), dtype="<i2")
    for position in range(CONTEXT):
        for index, frequency in enumerate(inverse):
            angle = float(position) * frequency
            cosine[position, index] = q15(math.cos(angle))
            sine[position, index] = q15(math.sin(angle))
    cosine.flags.writeable = False
    sine.flags.writeable = False
    if sha256(cosine.tobytes(order="C")) != ROPE_COS_SHA256:
        raise RuntimeError("context-2048 cosine table identity differs")
    if sha256(sine.tobytes(order="C")) != ROPE_SIN_SHA256:
        raise RuntimeError("context-2048 sine table identity differs")
    return cosine, sine


class IntegerLlama2048(q0.IntegerLlama):
    """The frozen integer oracle with the Board1 2,048-token geometry."""

    def _attention(self, query: q0.BFP, layer: int) -> q0.BFP:
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
                    raise q0.QuantizationError(
                        "attention dot exceeds signed 37-bit profile"
                    )
                score_values.append(score)
                score_exponents.append(query.exponent + key.exponent - 3)
            scores = q0._normalize_mixed(
                np.array(score_values, dtype=np.int64),
                np.array(score_exponents, dtype=np.int16),
                self.stats,
            )
            maximum = int(np.max(scores.value))
            differences = scores.value.astype(np.int64) - maximum
            q8 = q0._round_shift_even(
                differences, -(scores.exponent + q0.SOFTMAX_FRACTION)
            )
            clipped = np.clip(q8, -4096, 0)
            self.stats.softmax_clips += int(np.count_nonzero(q8 != clipped))
            exponentials = self.model.exp_neg[
                (-clipped).astype(np.int64)
            ].astype(np.int64)
            denominator = int(np.sum(exponentials, dtype=np.int64))
            self.stats.max_softmax_denominator = max(
                self.stats.max_softmax_denominator, denominator
            )
            # Board1 widened this exact accumulator from Q0's 40-bit/512-token
            # evaluation contract to 42 bits for at most 2,048 Q30 terms.
            if denominator <= 0 or denominator >= (1 << 42):
                raise q0.QuantizationError(
                    "softmax denominator exceeds unsigned 42-bit profile"
                )
            maximum_probability_numerator = (
                int(np.max(exponentials)) * q0.Q_PROBABILITY
            )
            self.stats.max_softmax_probability_numerator = max(
                self.stats.max_softmax_probability_numerator,
                maximum_probability_numerator,
            )
            if maximum_probability_numerator >= (1 << 45):
                raise q0.QuantizationError(
                    "softmax probability numerator exceeds unsigned 45-bit profile"
                )
            probabilities = np.fromiter(
                (
                    q0._round_div_even_scalar(
                        int(value) * q0.Q_PROBABILITY, denominator
                    )
                    for value in exponentials
                ),
                dtype=np.int64,
                count=exponentials.size,
            )
            selected_values = [
                value.value.reshape(2, 64)[kv_head]
                for value in self.values[layer]
            ]
            value_array = np.stack(selected_values).astype(np.int64)
            value_exponents = np.array(
                [value.exponent for value in self.values[layer]],
                dtype=np.int16,
            )[:, None]
            aligned = q0._normalize_mixed(
                value_array, value_exponents, self.stats
            )
            accumulator = probabilities @ aligned.value.astype(np.int64)
            maximum_accumulator = int(np.max(np.abs(accumulator)))
            self.stats.max_attention_accumulator = max(
                self.stats.max_attention_accumulator, maximum_accumulator
            )
            if maximum_accumulator >= (1 << 39):
                raise q0.QuantizationError(
                    "attention value accumulator exceeds signed 40-bit profile"
                )
            output = np.fromiter(
                (
                    q0._round_div_even_scalar(int(value), q0.Q_PROBABILITY)
                    for value in accumulator
                ),
                dtype=np.int64,
                count=64,
            )
            head_outputs.append(output)
            head_exponents.append(
                np.full(64, aligned.exponent, dtype=np.int16)
            )
        return q0._normalize_mixed(
            np.concatenate(head_outputs),
            np.concatenate(head_exponents),
            self.stats,
        )

    def consume(self, token_id: int, produce_prediction: bool
                ) -> Optional[Tuple[int, float]]:
        if type(token_id) is not int or not 0 <= token_id < 4019:
            raise ValueError("token ID must be an integer in [0, 4019)")
        if self.faulted:
            raise q0.QuantizationError(
                "integer oracle is latched in RANGE_FAULT until CLEAR"
            )
        if self.position >= CONTEXT:
            raise ValueError("integer oracle context is full at 2048 tokens")
        try:
            hidden = self._embedding(token_id)
            for layer in range(6):
                hidden = self._layer(hidden, layer, self.position)
            result: Optional[Tuple[int, float]] = None
            if produce_prediction:
                hidden = self._rms_norm(hidden, "model.norm.weight")
                winner, value, exponent = self._argmax(hidden)
                result = (winner, math.ldexp(float(value), exponent))
            self.position += 1
            return result
        except q0.QuantizationError:
            self.faulted = True
            raise



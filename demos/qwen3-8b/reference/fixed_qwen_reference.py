"""Fixed Qwen3-1.7B schedule and three-operation software reference.

This module does not call a Transformers model or generation loop. It still
uses PyTorch floating-point primitives for non-projection arithmetic. It is
therefore a control/numerical reference, NOT synthesizable RTL, a complete
bit-exact hardware oracle, or a security boundary enforced by Python.

Qwen arithmetic and rounding order follow the Apache-2.0 implementation in
Transformers 5.17.0, modeling_qwen3.py, copyright 2025 the Qwen team, Alibaba
Group and HuggingFace Inc. https://www.apache.org/licenses/LICENSE-2.0
"""
import json
from pathlib import Path

import torch

from integer_projection import IntegerProjection
from model_image import FixedImage

LAYERS = 28
WIDTH = 2048
FFN = 6144
Q_HEADS = 16
KV_HEADS = 8
HEAD = 128
VOCAB = 151936
CONTEXT = 32768
EPSILON = 1e-6
THETA = 1000000.0
REVISION = '70d244cc86ccca08cf5af4e1e306ecf908b1ad5e'


def expected_tensors():
    """The fixed architecture, not dimensions supplied through a host command."""
    matrices = {'model.embed_tokens.weight': (VOCAB, WIDTH)}
    vectors = {'model.norm.weight': (WIDTH,)}
    for layer in range(LAYERS):
        prefix = f'model.layers.{layer}'
        for name, rows, columns in (
            ('self_attn.q_proj', Q_HEADS*HEAD, WIDTH),
            ('self_attn.k_proj', KV_HEADS*HEAD, WIDTH),
            ('self_attn.v_proj', KV_HEADS*HEAD, WIDTH),
            ('self_attn.o_proj', WIDTH, Q_HEADS*HEAD),
            ('mlp.gate_proj', FFN, WIDTH), ('mlp.up_proj', FFN, WIDTH),
            ('mlp.down_proj', WIDTH, FFN),
        ):
            matrices[f'{prefix}.{name}.weight'] = (rows, columns)
        for name, width in (
            ('input_layernorm', WIDTH), ('post_attention_layernorm', WIDTH),
            ('self_attn.q_norm', HEAD), ('self_attn.k_norm', HEAD),
        ):
            vectors[f'{prefix}.{name}.weight'] = (width,)
    return matrices, vectors




def rms_norm(value, weight):
    # Round normalized values to BF16 BEFORE multiplying the BF16 norm weight.
    wide = value.float()
    variance = wide.square().mean(dim=-1, keepdim=True)
    normalized = wide*torch.rsqrt(variance+EPSILON)
    return normalized.to(value.dtype)*weight


def rotary(value, cosine, sine):
    first, second = value[..., :HEAD//2], value[..., HEAD//2:]
    rotated = torch.cat((-second, first), dim=-1)
    # Each multiply and the following sum have the input BF16 precision.
    return value*cosine + rotated*sine


def grouped_kv(value):
    batch, heads, length, width = value.shape
    copies = Q_HEADS//KV_HEADS
    return value[:, :, None, :, :].expand(batch, heads, copies, length, width).reshape(
        batch, heads*copies, length, width)


def causal_mask(start, length, device):
    positions = torch.arange(start, start+length, device=device)
    keys = torch.arange(start+length, device=device)
    return torch.where(keys[None, :] <= positions[:, None], 0.0,
                       torch.finfo(torch.bfloat16).min).to(torch.bfloat16)[None, None, :, :]


class FixedQwenEngine:
    """Private full-model engine. Diagnostics below are NOT application ports."""

    def __init__(self, model_image, device='cpu', observer=None, serial_prefill=False, norm_arithmetic='framework',
                 nonlinear_arithmetic='framework', attention_arithmetic='framework', softmax_arithmetic='framework'):
        if device not in ('cpu', 'mps'):
            raise ValueError('Only validated full-FP32 reference backends are allowed')
        if torch.get_float32_matmul_precision() != 'highest':
            raise ValueError('Exact integer partial dots require highest FP32 precision')
        self.device = device
        self.observer = observer
        self.serial_prefill = serial_prefill
        if norm_arithmetic not in ('framework','ordered-fp32'):
            raise ValueError('Unknown internal normalization arithmetic')
        self.norm_arithmetic = norm_arithmetic
        if nonlinear_arithmetic not in ('framework','fixed-tables'):
            raise ValueError('Unknown internal nonlinear arithmetic')
        self.nonlinear_arithmetic = nonlinear_arithmetic
        if attention_arithmetic not in ('framework','tree-qk','tree-qk-ordered-av'):
            raise ValueError('Unknown internal attention arithmetic')
        if attention_arithmetic!='framework' and not serial_prefill:
            raise ValueError('The attention candidate requires the fixed serial schedule')
        self.attention_arithmetic=attention_arithmetic
        if softmax_arithmetic not in ('framework','fixed-exp2-exact-sum'):
            raise ValueError('Unknown internal softmax arithmetic')
        self.softmax_arithmetic=softmax_arithmetic
        self.fixed_softmax=None
        if softmax_arithmetic=='fixed-exp2-exact-sum':
            from fixed_softmax import FixedSoftmax
            self.fixed_softmax=FixedSoftmax()
        self.nonlinear_tables = None
        if nonlinear_arithmetic=='fixed-tables':
            from fixed_nonlinear_tables import FixedNonlinearTables
            self.nonlinear_tables = FixedNonlinearTables()
        self._trace_enabled = True
        self.projections = {}
        self.norms = {}
        image = FixedImage(model_image)
        matrices, vectors = expected_tensors()
        if set(matrices) != set(image.matrices) or set(vectors) != set(image.vectors):
            raise ValueError('Fixed image tensor map differs from the numerical model')
        for name, shape in matrices.items():
            codes, scale = image.matrix(name)
            if tuple(codes.shape) != shape or tuple(scale.shape) != (shape[0], 1):
                raise ValueError('Wrong fixed image matrix geometry')
            if name == 'model.embed_tokens.weight':
                self.embedding_codes = codes.clone()
                self.embedding_scales = scale.clone()
                operation = 'lm_head'
            else:
                operation = name.removesuffix('.weight')
            self.projections[operation] = IntegerProjection(codes, scale, device, operation)
        for name, shape in vectors.items():
            value = image.vector(name)
            if tuple(value.shape) != shape:
                raise ValueError('Wrong fixed image vector geometry')
            self.norms[name.removesuffix('.weight')] = value.to(device)
        # Match the source implementation's CPU-created inverse frequencies.
        self.inverse_frequency = (1.0/(THETA**(torch.arange(0, HEAD, 2).float()/HEAD))).to(device)
        self.clear()

    def clear(self):
        self.keys = [None]*LAYERS
        self.values = [None]*LAYERS
        self.position = 0
        self.last_logits = None
        self.faulted = False

    def _observe(self, name, value):
        if self.observer is not None and self._trace_enabled:
            self.observer(name, value)
        return value

    def _project(self, name, value):
        return self._observe(name, self.projections[name](value))

    def _norm(self, name, value):
        if self.norm_arithmetic=='ordered-fp32':
            from ordered_rms_norm import ordered_rms_torch
            result=ordered_rms_torch(value,self.norms[name])
        else:
            result=rms_norm(value,self.norms[name])
        return self._observe(name,result)

    def _silu(self, name, value):
        return (self.nonlinear_tables.silu(value) if self.nonlinear_tables is not None
                else torch.nn.functional.silu(value))

    def _rotary(self, name, value, cosine, sine):
        return rotary(value,cosine,sine)

    def _attention(self, name, query, key, value, mask):
        if self.attention_arithmetic in ('tree-qk','tree-qk-ordered-av'):
            from tree_attention import tree_qk_torch
            scores=tree_qk_torch(query,key)
        else:
            scores=(query @ grouped_kv(key).transpose(2,3))*(HEAD**-0.5)
        scores=scores+mask
        probabilities=(self.fixed_softmax(scores) if self.fixed_softmax is not None
            else torch.softmax(scores,dim=-1,dtype=torch.float32).to(torch.bfloat16))
        if self.attention_arithmetic=='tree-qk-ordered-av':
            from tree_attention import ordered_av_torch
            return ordered_av_torch(probabilities,value)
        return probabilities @ grouped_kv(value)

    @torch.inference_mode()
    def consume(self, tokens):
        """Internal operation: consume pending tape tokens and choose the next one."""
        if self.faulted:
            raise RuntimeError('Numerical engine fault: CLEAR is required')
        if not tokens or any(type(t) is not int or not 0 <= t < VOCAB for t in tokens):
            raise ValueError('Expected valid, nonempty pending token sequence')
        if self.position+len(tokens) > CONTEXT:
            raise ValueError('Context capacity exceeded')
        try:
            if self.serial_prefill:
                # Match the first RTL sequencer: one complete 28-layer pass
                # per pending token, but skip the output head for prefix tokens.
                # Only the last token emits diagnostic stage observations.
                self._trace_enabled = False
                for token in tokens[:-1]:
                    self._evaluate([token], finish=False)
                    self.position += 1
                self._trace_enabled = True
                tokens = tokens[-1:]
            logits = self._evaluate(tokens)
            if not torch.isfinite(logits).all():
                raise ValueError('Non-finite logits')
            self.last_logits = logits
            self.position += len(tokens)
            # torch.argmax selects the lowest token ID if logits tie.
            return int(logits.argmax().item())
        except Exception:
            # Some layers may have updated private state: never resume that
            # partially executed inference. CLEAR discards all cache validity.
            self.faulted = True
            raise
        finally:
            self._trace_enabled = True

    def _evaluate(self, tokens, finish=True):
        length = len(tokens)
        ids = torch.tensor(tokens, dtype=torch.long)
        x = (self.embedding_codes[ids].float()*self.embedding_scales[ids]).to(
            device=self.device, dtype=torch.bfloat16)[None, :, :]
        self._observe('model.embed_tokens', x)
        if self.nonlinear_tables is None:
            positions = torch.arange(self.position, self.position+length, device=self.device).float()
            frequencies = (self.inverse_frequency[None, :, None] @ positions[None, None, :]).transpose(1, 2)
            angles = torch.cat((frequencies, frequencies), dim=-1)
            cosine = angles.cos().to(torch.bfloat16)[:, None, :, :]
            sine = angles.sin().to(torch.bfloat16)[:, None, :, :]
        else:
            cosine,sine=self.nonlinear_tables.rotary(self.position,length,self.device)
        mask = causal_mask(self.position, length, self.device)
        for layer in range(LAYERS):
            prefix = f'model.layers.{layer}'
            attention = prefix+'.self_attn'
            residual = x
            z = self._norm(prefix+'.input_layernorm', x)
            q = self._norm(attention+'.q_norm', self._project(attention+'.q_proj', z).reshape(
                1, length, Q_HEADS, HEAD)).transpose(1, 2)
            k = self._norm(attention+'.k_norm', self._project(attention+'.k_proj', z).reshape(
                1, length, KV_HEADS, HEAD)).transpose(1, 2)
            v = self._project(attention+'.v_proj', z).reshape(1, length, KV_HEADS, HEAD).transpose(1, 2)
            q = self._rotary(attention+'.q_rotary',q,cosine,sine)
            k = self._rotary(attention+'.k_rotary',k,cosine,sine)
            if self.keys[layer] is not None:
                k = torch.cat((self.keys[layer], k), dim=2)
                v = torch.cat((self.values[layer], v), dim=2)
            self.keys[layer], self.values[layer] = k, v
            attended = self._attention(attention,q,k,v,mask).transpose(1, 2).contiguous().reshape(1, length, WIDTH)
            x = residual+self._project(attention+'.o_proj', attended)
            residual = x
            z = self._norm(prefix+'.post_attention_layernorm', x)
            gate = self._project(prefix+'.mlp.gate_proj', z)
            up = self._project(prefix+'.mlp.up_proj', z)
            product = self._silu(prefix+'.mlp.silu',gate)*up
            x = residual+self._project(prefix+'.mlp.down_proj', product)
            self._observe(prefix, x)
        if not finish:
            return None
        final = self._norm('model.norm', x)
        return self._project('lm_head', final[:, -1:, :])[0, 0]


class TokenMachine:
    """APPEND / STEP / CLEAR semantics, separate from private numerical diagnostics.

    APPEND stores a token. STEP processes pending tokens, chooses one greedy
    token, appends it and returns it. CLEAR invalidates the tape and K/V cache.
    Empty-tape STEP and operations that would exceed capacity are rejected.
    EOS is an ordinary token here; stopping on EOS is a host presentation rule.
    """

    def __init__(self, engine, vocabulary=VOCAB, capacity=CONTEXT):
        self._engine = engine
        self._vocabulary = vocabulary
        self._capacity = capacity
        self.clear()

    def clear(self):
        self._engine.clear()
        self._tape = []
        self._processed = 0
        self._faulted = False

    def append(self, token):
        if self._faulted:
            raise RuntimeError('CLEAR is required after an execution fault')
        if type(token) is not int or not 0 <= token < self._vocabulary:
            raise ValueError('Token ID outside the fixed vocabulary')
        if len(self._tape) >= self._capacity:
            raise ValueError('Tape is full')
        self._tape.append(token)

    def step(self):
        if self._faulted:
            raise RuntimeError('CLEAR is required after an execution fault')
        if not self._tape:
            raise ValueError('APPEND at least one token before STEP')
        if len(self._tape) >= self._capacity:
            raise ValueError('No room for a generated token')
        try:
            token = self._engine.consume(self._tape[self._processed:])
            if type(token) is not int or not 0 <= token < self._vocabulary:
                raise RuntimeError('Engine produced an invalid token')
        except Exception:
            self._faulted = True
            raise
        self._processed = len(self._tape)
        self._tape.append(token)
        return token

"""Private serial reference for build-time specializations of dense Qwen3.

Reuses the released exact integer projection, nonlinear tables, tree QK,
ordered AV, BF16 conversions, rotary operation and token-machine semantics.
The schedule and dimensional adapters here are new and require regression.
This software oracle is not an application API or a hardware security proof.
"""
import json
from pathlib import Path
import sys

import numpy as np
import torch

from model_geometry import Geometry, model_layout
from fixed_model_export import RELEASE, digest
sys.path.insert(0, str(RELEASE/'reference'))
from fixed_model_layout import unpack_codes
from integer_projection import IntegerProjection
from fixed_nonlinear_tables import FixedNonlinearTables
from fixed_softmax import FixedSoftmax
from tree_attention import tree_qk_bits, ordered_av_bits
from ordered_rms_norm import bf16_from_float, float_from_bf16
from fixed_qwen_reference import rotary, TokenMachine


def bits(value):
    return value.detach().cpu().contiguous().view(torch.int16).numpy().view(np.uint16)


def tensor(value, device='cpu'):
    return torch.from_numpy(np.asarray(value, dtype=np.uint16).view(np.int16).copy()).view(torch.bfloat16).to(device)


def ordered_norm(value, weight, allowed_width):
    """Same left-to-right FP32 order as released RMSNorm, with fixed new width."""
    if value.dtype != torch.bfloat16 or weight.dtype != torch.bfloat16:
        raise ValueError('BF16 normalization only')
    x, w = float_from_bf16(bits(value)), float_from_bf16(bits(weight))
    if x.ndim < 1 or x.shape[-1] != allowed_width or w.shape != (allowed_width,):
        raise ValueError('Wrong normalization geometry')
    if not np.isfinite(x).all() or not np.isfinite(w).all():
        raise ValueError('Nonfinite normalization input')
    with np.errstate(over='ignore', invalid='ignore', divide='ignore', under='ignore'):
        squares = np.multiply(x, x, dtype=np.float32)
        total = np.add.accumulate(squares, axis=-1, dtype=np.float32)[..., -1:]
        mean = np.multiply(total, np.float32(1.0/allowed_width), dtype=np.float32)
        variance = np.add(mean, np.float32(1e-6), dtype=np.float32)
        root = np.sqrt(variance, dtype=np.float32)
        inverse = np.divide(np.float32(1), root, dtype=np.float32)
        normalized = np.multiply(x, inverse, dtype=np.float32)
        narrowed = float_from_bf16(bf16_from_float(normalized))
        product = np.multiply(narrowed, w, dtype=np.float32)
        result = bf16_from_float(product)
    if any(not np.isfinite(v).all() for v in (squares, total, mean, variance, root,
            inverse, normalized, narrowed, product, float_from_bf16(result))):
        raise ValueError('Nonfinite normalization arithmetic')
    return tensor(result, value.device)


def serial_attention(query, key, value, softmax, g):
    if (query.dtype != torch.bfloat16 or key.dtype != torch.bfloat16 or value.dtype != torch.bfloat16
            or tuple(query.shape) != (1, g.query_heads, 1, g.head_dim)
            or key.ndim != 4 or tuple(key.shape[:2]) != (1, g.kv_heads)
            or key.shape[-1] != g.head_dim or not 1 <= key.shape[2] <= g.positions
            or value.shape != key.shape):
        raise ValueError('Wrong serial attention geometry')
    repeats = g.query_heads//g.kv_heads
    q, k = bits(query)[0], np.repeat(bits(key)[0], repeats, axis=0)
    scores = tree_qk_bits(q, k)
    probabilities = softmax.bits(scores)
    attended = ordered_av_bits(probabilities, np.repeat(bits(value)[0], repeats, axis=0))
    return tensor(attended[None, :, None, :], query.device)


class DenseFixedImage:
    def __init__(self, directory):
        directory = Path(directory)
        receipt = json.loads((directory/'FINISHED.json').read_text())
        verified = json.loads((directory/'CONTENT-VERIFIED.json').read_text())
        self.geometry = Geometry(**receipt['geometry'])
        self.layout = model_layout(self.geometry)
        if (not receipt['passed'] or not verified['passed']
                or verified['image_sha256'] != receipt['image_sha256']
                or json.loads((directory/'layout.json').read_text()) != self.layout
                or (directory/'model.bin').stat().st_size != self.layout['image_bytes']
                or digest(directory/'model.bin') != receipt['image_sha256']):
            raise ValueError('Unverified or changed candidate image')
        self.sha256 = receipt['image_sha256']
        self.data = np.memmap(directory/'model.bin', dtype=np.uint8, mode='r')

    def matrix(self, m):
        raw = self.data[m['codes_offset']:m['codes_offset']+m['codes_bytes']].view(np.int8)
        codes = unpack_codes(raw, m['rows'], m['columns']).copy()
        scales = self.data[m['scales_offset']:m['scales_offset']+m['scales_bytes']].view('<f4').copy()
        if not np.isfinite(scales).all() or not (scales > 0).all():
            raise ValueError('Invalid matrix scale')
        return torch.from_numpy(codes), torch.from_numpy(scales.reshape(-1, 1))


class DenseQwenEngine:
    def __init__(self, directory, device='cpu', observer=None):
        if device not in ('cpu', 'mps') or torch.get_float32_matmul_precision() != 'highest':
            raise ValueError('Full-FP32 CPU/MPS reference required')
        self.image = DenseFixedImage(directory)
        self.g = g = self.image.geometry
        self.device, self.observer = device, observer
        self.projections, self.norms = {}, {}
        for m in self.image.layout['matrices']:
            codes, scales = self.image.matrix(m)
            operation = 'lm_head' if m['kind'] == 7 else m['name'].removesuffix('.weight')
            self.projections[operation] = IntegerProjection(codes, scales, device, operation)
        for v in self.image.layout['vectors']:
            raw = self.image.data[v['offset']:v['offset']+v['bytes']].view('<u2')
            self.norms[v['name'].removesuffix('.weight')] = tensor(raw, device)
        e = self.image.layout['embedding']
        # CPU storage: transfer only the requested embedding row to the backend.
        self.embeddings = tensor(self.image.data[e['offset']:e['offset']+e['bytes']].view('<u2').reshape(g.vocab, g.width))
        self.tables, self.softmax = FixedNonlinearTables(), FixedSoftmax()
        self.clear()

    def clear(self):
        self.keys, self.values = [None]*self.g.layers, [None]*self.g.layers
        self.position, self.last_logits, self.faulted = 0, None, False

    def _observe(self, name, value):
        if self.observer is not None:
            self.observer(name, value)
        return value

    def _project(self, name, value):
        return self._observe(name, self.projections[name](value))

    def _norm(self, name, value):
        weight = self.norms[name]
        return self._observe(name, ordered_norm(value, weight, weight.numel()))

    @torch.inference_mode()
    def consume(self, tokens):
        if self.faulted:
            raise RuntimeError('CLEAR is required after a numerical fault')
        if not tokens or any(type(t) is not int or not 0 <= t < self.g.vocab for t in tokens):
            raise ValueError('Nonempty valid token list required')
        if self.position + len(tokens) > self.g.positions:
            raise ValueError('Context capacity exceeded')
        try:
            for i, token in enumerate(tokens):
                logits = self._evaluate(token, finish=i == len(tokens)-1)
                self.position += 1
            if not torch.isfinite(logits).all():
                raise ValueError('Nonfinite logits')
            self.last_logits = logits
            return int(logits.argmax().item())
        except Exception:
            self.faulted = True
            raise

    def _evaluate(self, token, finish):
        g = self.g
        x = self.embeddings[token].to(self.device)[None, None, :]
        self._observe('model.embed_tokens', x)
        cosine, sine = self.tables.rotary(self.position, 1, self.device)
        for layer in range(g.layers):
            prefix = f'model.layers.{layer}'
            attention = prefix+'.self_attn'
            residual = x
            z = self._norm(prefix+'.input_layernorm', x)
            q = self._norm(attention+'.q_norm', self._project(attention+'.q_proj', z).reshape(1, 1, g.query_heads, g.head_dim)).transpose(1, 2)
            k = self._norm(attention+'.k_norm', self._project(attention+'.k_proj', z).reshape(1, 1, g.kv_heads, g.head_dim)).transpose(1, 2)
            v = self._project(attention+'.v_proj', z).reshape(1, 1, g.kv_heads, g.head_dim).transpose(1, 2)
            q, k = rotary(q, cosine, sine), rotary(k, cosine, sine)
            self._observe(attention+'.q_rotary', q)
            self._observe(attention+'.k_rotary', k)
            if self.keys[layer] is not None:
                k, v = torch.cat((self.keys[layer], k), dim=2), torch.cat((self.values[layer], v), dim=2)
            self.keys[layer], self.values[layer] = k, v
            # Serial processing admits exactly the already-populated causal prefix.
            attended = serial_attention(q, k, v, self.softmax, g).transpose(1, 2).contiguous().reshape(1, 1, g.width)
            self._observe(attention+'.attention', attended)
            x = residual+self._project(attention+'.o_proj', attended)
            self._observe(prefix+'.attention_residual', x)
            residual = x
            z = self._norm(prefix+'.post_attention_layernorm', x)
            gate, up = self._project(prefix+'.mlp.gate_proj', z), self._project(prefix+'.mlp.up_proj', z)
            activated = self.tables.silu(gate)
            self._observe(prefix+'.mlp.silu', activated)
            gated = activated*up
            self._observe(prefix+'.mlp.gate_product', gated)
            x = residual+self._project(prefix+'.mlp.down_proj', gated)
            self._observe(prefix, x)
        if not finish:
            return None
        return self._project('lm_head', self._norm('model.norm', x))[0, 0]

    def token_machine(self):
        return TokenMachine(self, vocabulary=self.g.vocab, capacity=self.g.positions)

"""Candidate RTL RMSNorm order, independently expressible with native FP32.

This is deliberately not a claim of bit equivalence to torch.mean/rsqrt.
Each column is accumulated left-to-right in FP32; sqrt and reciprocal are
separate FP32 operations. BF16 rounding precedes the norm-weight multiply.
"""
import numpy as np


def float_from_bf16(bits):
    # Keep a 0-D scalar uint32: Python's integer shift can promote it to int64.
    return np.left_shift(np.asarray(bits,dtype=np.uint16).astype(np.uint32),
                         np.uint32(16),dtype=np.uint32).view(np.float32)


def bf16_from_float(value):
    raw=np.asarray(value,dtype=np.float32).view(np.uint32)
    return ((raw+np.uint32(0x7fff)+((raw>>16)&1))>>16).astype(np.uint16)


def ordered_rms_bits(inputs, weights):
    """Return uint16 BF16 bits, or reject any nonfinite arithmetic result."""
    x=float_from_bf16(inputs)
    w=float_from_bf16(weights)
    if x.ndim<1 or x.shape[-1] not in (128,2048) or w.shape!=(x.shape[-1],):
        raise ValueError('Only the two fixed Qwen normalization widths are allowed')
    if not np.isfinite(x).all() or not np.isfinite(w).all():
        raise ValueError('Nonfinite RMSNorm input/weight')
    with np.errstate(over='ignore',invalid='ignore',divide='ignore',under='ignore'):
        squares=np.multiply(x,x,dtype=np.float32)
        total=np.add.accumulate(squares,axis=-1,dtype=np.float32)[...,-1:]
        mean=np.multiply(total,np.float32(1.0/x.shape[-1]),dtype=np.float32)
        variance=np.add(mean,np.float32(1e-6),dtype=np.float32)
        root=np.sqrt(variance,dtype=np.float32)
        inverse=np.divide(np.float32(1),root,dtype=np.float32)
        normalized=np.multiply(x,inverse,dtype=np.float32)
        narrowed=float_from_bf16(bf16_from_float(normalized))
        product=np.multiply(narrowed,w,dtype=np.float32)
        result=bf16_from_float(product)
    if any(not np.isfinite(v).all() for v in (squares,total,mean,variance,root,inverse,
                                              normalized,narrowed,product,float_from_bf16(result))):
        raise ValueError('Nonfinite RMSNorm intermediate/result')
    return result


def ordered_rms_torch(value, weight):
    """CPU reference adapter; not a performance implementation or public port."""
    import torch
    if value.dtype!=torch.bfloat16 or weight.dtype!=torch.bfloat16:
        raise ValueError('The candidate RMSNorm requires BF16 tensors')
    x=value.detach().cpu().contiguous().view(torch.int16).numpy().view(np.uint16)
    w=weight.detach().cpu().contiguous().view(torch.int16).numpy().view(np.uint16)
    result=ordered_rms_bits(x,w)
    return torch.from_numpy(result.view(np.int16).copy()).view(torch.bfloat16).to(value.device)

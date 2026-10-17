"""Explicit-order candidate attention arithmetic, independent of BLAS/GEMM.

QK uses a balanced tree; the optional AV candidate uses ordered FP32 sums.
Softmax is still a framework operation.
This CPU oracle specifies values, not performance or an application interface.
"""
import numpy as np

from ordered_rms_norm import bf16_from_float,float_from_bf16

HEAD=128
SCALE=np.array(0x3db504f3,dtype=np.uint32).view(np.float32)


def tree_qk_bits(query,key):
    """Broadcast leading axes; exactly 128 BF16 inputs per dot. Return BF16 score."""
    q=float_from_bf16(query);k=float_from_bf16(key)
    if q.ndim<1 or k.ndim<1 or q.shape[-1]!=HEAD or k.shape[-1]!=HEAD:
        raise ValueError('The fixed Qwen attention dot has exactly 128 coordinates')
    if not np.isfinite(q).all() or not np.isfinite(k).all():
        raise ValueError('Nonfinite query/key')
    with np.errstate(over='ignore',invalid='ignore',under='ignore'):
        work=np.multiply(q,k,dtype=np.float32)
        if not np.isfinite(work).all():raise ValueError('Nonfinite QK product')
        for _ in range(7):
            work=np.add(work[...,0::2],work[...,1::2],dtype=np.float32)
            if not np.isfinite(work).all():raise ValueError('Nonfinite QK partial sum')
        dot=float_from_bf16(bf16_from_float(work[...,0]))
        score=bf16_from_float(np.multiply(dot,SCALE,dtype=np.float32))
    if not np.isfinite(dot).all() or not np.isfinite(float_from_bf16(score)).all():
        raise ValueError('Nonfinite rounded dot/score')
    return score


def tree_qk_torch(query,key):
    """One-token, batch-one query against all private K/V heads; GQA ratio two."""
    import torch
    if (query.dtype!=torch.bfloat16 or key.dtype!=torch.bfloat16
            or tuple(query.shape)!=(1,16,1,128) or key.ndim!=4
            or key.shape[0]!=1 or key.shape[1]!=8 or key.shape[3]!=128
            or not 1<=key.shape[2]<=32768):
        raise ValueError('Expected fixed, serial Qwen attention shapes')
    def bits(t):return t.detach().cpu().contiguous().view(torch.int16).numpy().view(np.uint16)
    q=bits(query)[0];k=np.repeat(bits(key)[0],2,axis=0)
    score=tree_qk_bits(q,k)[None,:,None,:]
    return torch.from_numpy(score.view(np.int16).copy()).view(torch.bfloat16).to(query.device)


def ordered_av_bits(probability,value):
    """BF16 p[...,N] and V[...,N,128], FP32 p*V then sums in context order."""
    p=float_from_bf16(probability);v=float_from_bf16(value)
    if (p.ndim<1 or v.ndim<2 or v.shape[-1]!=128 or p.shape[-1]!=v.shape[-2]
            or not 1<=p.shape[-1]<=32768):
        raise ValueError('Expected fixed-width AV data and 1..32768 probabilities')
    if not np.isfinite(p).all() or not np.isfinite(v).all() or (p<0).any() or (p>1).any():
        raise ValueError('Invalid attention probability/value')
    with np.errstate(over='ignore',invalid='ignore',under='ignore'):
        products=np.multiply(p[...,None],v,dtype=np.float32)
        # Include the initial +0 addition (including its signed-zero behavior).
        work=np.concatenate((np.zeros_like(products[...,:1,:]),products),axis=-2)
        sums=np.add.accumulate(work,axis=-2,dtype=np.float32)
        result=bf16_from_float(sums[...,-1,:])
    if (not np.isfinite(products).all() or not np.isfinite(sums).all()
            or not np.isfinite(float_from_bf16(result)).all()):
        raise ValueError('Nonfinite AV intermediate/result')
    return result


def ordered_av_torch(probability,value):
    import torch
    if (probability.dtype!=torch.bfloat16 or value.dtype!=torch.bfloat16
            or probability.ndim!=4 or tuple(probability.shape[:3])!=(1,16,1)
            or value.ndim!=4 or tuple(value.shape[:2])!=(1,8) or value.shape[3]!=128
            or probability.shape[3]!=value.shape[2]):
        raise ValueError('Expected fixed, serial Qwen AV shapes')
    def bits(t):return t.detach().cpu().contiguous().view(torch.int16).numpy().view(np.uint16)
    result=ordered_av_bits(bits(probability)[0,:,0,:],np.repeat(bits(value)[0],2,axis=0))[None,:,None,:]
    return torch.from_numpy(result.view(np.int16).copy()).view(torch.bfloat16).to(value.device)

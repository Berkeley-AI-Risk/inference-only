"""Private, explicitly specified softmax numerical candidate (not host API)."""
import json
from pathlib import Path

from model_image import checked_asset




def exact_sum_fp32_bits(values):
    """Exact nonnegative FP32 sum in units 2^-149, then one FP32 RNE rounding.

    Softmax always includes exp(0)=1, so the sum is in [1,32768].
    Python integers are an independent oracle for the RTL carry-save sum.
    """
    total=0
    for raw in values:
        raw=int(raw)
        if not 0<=raw<=0x3f800000:raise ValueError('Exponential outside [0,1]')
        exponent=raw>>23;mantissa=raw&0x7fffff
        total+=(mantissa if exponent==0 else ((1<<23)|mantissa)<<(exponent-1))
    if not (1<<149)<=total<=(32768<<149):raise ValueError('Softmax denominator outside its invariant')
    exponent=total.bit_length()-1-149;shift=126+exponent
    mantissa=total>>shift;remainder=total&((1<<shift)-1);half=1<<(shift-1)
    mantissa+=int(remainder>half or (remainder==half and mantissa&1))
    if mantissa==(1<<24):mantissa>>=1;exponent+=1
    return ((127+exponent)<<23)|(mantissa&0x7fffff)


class FixedSoftmax:
    def __init__(self):
        import numpy as np
        self.table_bits = np.fromfile(checked_asset('softmax'), dtype='<u4').reshape(1024,2)
        self.table = self.table_bits.view(np.float32)

    def exp_negative(self,distance):
        import numpy as np
        d=np.asarray(distance,dtype=np.float32)
        if np.isnan(d).any() or (d<0).any():raise ValueError('Expected nonnegative distance; +infinity maps to zero')
        clip=d>=np.float32(104);safe=np.where(clip,np.float32(0),d)
        factor=np.array(0x3fb8aa3b,dtype=np.uint32).view(np.float32)
        t=np.multiply(safe,factor,dtype=np.float32)
        fixed=np.rint(t.astype(np.float64)*16777216.0).astype(np.uint32)
        integer=(fixed>>24).astype(np.int32);index=(fixed>>14)&1023
        residual=np.multiply((fixed&16383).astype(np.float32),np.float32(1.0/16384),dtype=np.float32)
        product=np.multiply(self.table[index,1],residual,dtype=np.float32)
        fraction=np.add(self.table[index,0],product,dtype=np.float32)
        with np.errstate(under='ignore'):result=np.ldexp(fraction,-integer,dtype=np.float32)
        result=np.where(clip,np.float32(0),result)
        if not np.isfinite(result).all() or (result<0).any() or (result>1).any():raise ValueError('Invalid exponential')
        return result

    def bits(self,scores):
        import numpy as np
        from ordered_rms_norm import float_from_bf16,bf16_from_float
        x=float_from_bf16(scores)
        if x.ndim<1 or not 1<=x.shape[-1]<=32768 or not np.isfinite(x).all():raise ValueError('Expected 1..32768 finite BF16 scores')
        with np.errstate(over='ignore'):distance=np.subtract(np.max(x,axis=-1,keepdims=True),x,dtype=np.float32)
        exp=self.exp_negative(distance)
        totals=np.asarray([exact_sum_fp32_bits(row) for row in exp.view(np.uint32).reshape(-1,x.shape[-1])],dtype=np.uint32)
        totals=totals.view(np.float32).reshape(x.shape[:-1])
        inverse=np.divide(np.float32(1),totals,dtype=np.float32)
        return bf16_from_float(np.multiply(exp,inverse[...,None],dtype=np.float32))

    def __call__(self,scores):
        import numpy as np
        import torch
        if scores.dtype!=torch.bfloat16:raise ValueError('Expected BF16 softmax scores')
        bits=scores.detach().cpu().contiguous().view(torch.int16).numpy().view(np.uint16)
        result=self.bits(bits)
        return torch.from_numpy(result.view(np.int16).copy()).view(torch.bfloat16).to(scores.device)

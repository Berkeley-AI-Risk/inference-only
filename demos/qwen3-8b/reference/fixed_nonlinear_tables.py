"""Verified fixed-table reference, not an application-level configurable LUT."""
import json
from pathlib import Path

from model_image import checked_asset

REVISION='70d244cc86ccca08cf5af4e1e306ecf908b1ad5e'




class FixedNonlinearTables:
    def __init__(self):
        import numpy as np
        self.silu_bits = np.fromfile(checked_asset('silu'), dtype='<u2')
        self.rotary_bits = np.fromfile(checked_asset('rope'), dtype='<u2').reshape(32768,64,2)
        self._devices = {}

    def _device(self,device):
        import numpy as np
        import torch
        key=str(device)
        if key not in self._devices:
            def tensor(bits):return torch.from_numpy(bits.astype(np.uint16).view(np.int16).copy()).view(torch.bfloat16).to(device)
            self._devices[key]=(tensor(self.silu_bits),tensor(self.rotary_bits[:,:,0]),tensor(self.rotary_bits[:,:,1]))
        return self._devices[key]

    def silu(self,value):
        import torch
        if value.dtype!=torch.bfloat16 or not torch.isfinite(value).all():raise ValueError('SiLU requires finite BF16 input')
        indices=value.contiguous().view(torch.int16).to(torch.int32).bitwise_and(65535).long()
        return self._device(value.device)[0][indices]

    def rotary(self,start,length,device):
        import torch
        if type(start) is not int or type(length) is not int or start<0 or length<1 or start+length>32768:
            raise ValueError('Rotary position outside the fixed token tape')
        _,cos,sin=self._device(device)
        cos=cos[start:start+length];sin=sin[start:start+length]
        return torch.cat((cos,cos),dim=-1)[None,None,:,:],torch.cat((sin,sin),dim=-1)[None,None,:,:]

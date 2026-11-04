#!/usr/bin/env python3
"""Fixed Tang flash layout and an image-derived independent integer oracle."""
from pathlib import Path
import hashlib
import sys
import signed_update as su

MODEL_BASE=0x801000
SLOT_BASE=0xF00000
SLOT_BYTES=0x40000
FLASH_BYTES=0x1000000
LUT_FIRST_WORD=214261
LUT_SHA='fea751d73eb4fd28f160a4dcc4b8d1fa39c125cb05d10393ac45ad4e3e1bb76b'

def norm_rows(image):
    if len(image)!=su.IMAGE_BYTES:raise su.Reject('wrong Tang image length')
    rows=[]
    for selector in range(13):
        base=(211800+selector*10)*32 if selector<12 else 214250*32
        packed=int.from_bytes(image[base:base+320],'little')
        at=214248*32+selector*4 if selector<12 else 214260*32
        exp=image[at];mult=int.from_bytes(image[at+1:at+3],'little')
        if selector<12 and image[at+3]!=0:raise su.Reject('nonzero norm metadata padding')
        if not 0<mult<32768:raise su.Reject('invalid norm multiplier')
        for i in range(256):
            coef=(packed>>(10*i))&1023
            if coef==512:raise su.Reject('forbidden norm coefficient')
            rows.append((exp<<26)|(mult<<10)|coef)
    if any(image[214249*32+16:214250*32]) or any(image[214260*32+3:214261*32]):
        raise su.Reject('nonzero unused norm metadata')
    return rows

def validate_tang(package,keys):
    info=su.verify_package(package,keys)
    image=package[-su.IMAGE_BYTES:]
    if hashlib.sha256(image[LUT_FIRST_WORD*32:]).hexdigest()!=LUT_SHA:
        raise su.Reject('fixed arithmetic lookup tables changed')
    count=int.from_bytes(package[128:132],'big')
    payload_at=132+count*(4+su.SIG_BYTES)
    metadata=package[payload_at+32+32*su.PAGES:payload_at+su.PAYLOAD_BYTES]
    # Native metadata words serialize the high lane first in each 192-bit row.
    expanded=b''.join(
        b''.join(int.from_bytes(metadata[i+j:i+j+3],'big').to_bytes(4,'little') for j in range(21,-1,-3))
        for i in range(0,len(metadata),24))
    if image[211920*32:214248*32]!=expanded:
        raise su.Reject('signed projection metadata differs from the model image')
    norm_rows(image)
    return info

def integer_model(image,demo):
    """Decode the physical W10/lane image, not the HDL or its observations."""
    import numpy as np
    sys.path.insert(0,str(Path(demo)/'reference'))
    from quantization.oracle import QuantizedTensor,QuantizedModel
    tensors={};weight_byte=0;metadata_row=0
    metadata=np.frombuffer(image[211920*32:214248*32],dtype='<u4')
    geometry=[('self_attn.q_proj',256,256),('self_attn.k_proj',128,256),
              ('self_attn.v_proj',128,256),('self_attn.o_proj',256,256),
              ('mlp.gate_proj',682,256),('mlp.up_proj',682,256),('mlp.down_proj',256,682)]
    jobs=[(f'model.layers.{l}.{name}.weight',r,c) for l in range(6) for name,r,c in geometry]
    jobs.append(('model.embed_tokens.weight',4019,256))
    for name,rows,cols in jobs:
        groups=(rows+63)//64;n=groups*cols*64;size=n*10//8
        bits=np.unpackbits(np.frombuffer(image[weight_byte:weight_byte+size],dtype=np.uint8),bitorder='little').reshape(-1,10)
        values=(bits.astype(np.int16)*(1<<np.arange(10,dtype=np.int16))).sum(axis=1).astype(np.int16)
        values=np.where(values>=512,values-1024,values).astype(np.int16)
        values=values.reshape(groups,cols,64).transpose(0,2,1).reshape(groups*64,cols)[:rows].copy()
        m=metadata[metadata_row:metadata_row+groups*64][:rows]
        exponent=(m&255).astype(np.uint8).view(np.int8).copy()
        multiplier=((m>>8)&65535).astype(np.uint16).copy()
        tensors[name]=QuantizedTensor(values,exponent,multiplier)
        weight_byte+=size;metadata_row+=groups*64
    assert weight_byte==211800*32 and metadata_row==2328*8
    packed=norm_rows(image)
    for sel in range(13):
        raw=packed[sel*256:(sel+1)*256];co=np.asarray([x&1023 for x in raw],dtype=np.int16)
        co=np.where(co>=512,co-1024,co).astype(np.int16)
        e=(raw[0]>>26)&255;e=e-256 if e>=128 else e
        name='model.norm.weight' if sel==12 else f'model.layers.{sel//2}.'+('input_layernorm.weight' if sel%2==0 else 'post_attention_layernorm.weight')
        tensors[name]=QuantizedTensor(co,np.asarray([e],dtype=np.int8),np.asarray([(raw[0]>>10)&65535],dtype=np.uint16))
    def i16(start,length):return np.frombuffer(image[start*32:start*32+length],dtype='<i2').copy()
    cosine=np.concatenate((i16(214261,8192),i16(219382,122880))).reshape(2048,32)
    sine=np.concatenate((i16(214517,8192),i16(223222,122880))).reshape(2048,32)
    silu=i16(215286,131072)
    exp=np.frombuffer(image[214773*32:214773*32+4097*4],dtype='<i4').copy()
    return QuantizedModel(tensors,cosine,sine,silu,exp,{'source':'signed physical Tang image','sha256':hashlib.sha256(image).hexdigest()})

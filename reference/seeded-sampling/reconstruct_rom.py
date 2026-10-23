#!/usr/bin/env python3
"""Reconstruct authenticated Q0 ROMs from the included fixed plaintext image.

Offline build-time inversion of the documented image layout. No model update,
network, serial, FPGA or flash operation exists in this program.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys

HERE=Path(__file__).resolve().parent
PACKAGE=HERE.parents[1]
IMAGE_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
MANIFEST_SHA='b921e209e53c8d8c52fbabc20e464b85affc537fb705d5472261e0a29a8df0c1'
ORACLE_SHA='9b048a8e8b82faba3d21fd6b259aa1c23d91f04662fe2734fc109602777b4a74'

def require(ok,message):
    if not ok:raise ValueError(message)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module)
    return module

def reconstruct(image=None):
    import numpy as np
    require(np.__version__=='1.26.4','Use NumPy 1.26.4')
    image=PACKAGE/'assets/board1-real-semantic-image2048.bin'if image is None else Path(image)
    require(image.is_file()and not image.is_symlink(),'Image must be a regular file')
    raw=image.read_bytes();require(len(raw)==7265984 and sha(raw)==IMAGE_SHA,'Fixed model image identity differs')
    manifest_raw=(HERE/'rom-manifest.json').read_bytes()
    require(sha(manifest_raw)==MANIFEST_SHA,'Canonical ROM manifest differs')
    manifest=json.loads(manifest_raw)
    reference=HERE.parent
    require(sha((reference/'quantization/oracle.py').read_bytes())==ORACLE_SHA,'Original integer loader differs')
    sys.path.insert(0,str(reference))
    from quantization import oracle as q0
    from quantization import artifacts
    builder=load_module('_seeded_image_builder',PACKAGE/'tools/materialize_image.py')
    tensors={};weight_cursor=0;metadata_cursor=211920*32
    for layer in range(6):
        for suffix,rows,columns in builder.JOBS:
            name=f'model.layers.{layer}.{suffix}'
            groups=(rows+63)//64;count=groups*64*columns;size=count*10//8
            striped=q0._unpack_int10(raw[weight_cursor:weight_cursor+size],count)
            matrix=striped.reshape(groups,columns,64).transpose(0,2,1).reshape(groups*64,columns)
            require(np.all(matrix[rows:]==0),'Projection padding coefficients differ')
            metadata=raw[metadata_cursor:metadata_cursor+groups*64*4]
            require(all(metadata[i]==0 for i in range(3,len(metadata),4)),'Reserved projection metadata differs')
            require(not any(metadata[rows*4:]),'Projection padding metadata differs')
            exponents=np.array([struct.unpack_from('<b',metadata,i*4)[0]for i in range(rows)],dtype=np.int8)
            multipliers=np.array([struct.unpack_from('<H',metadata,i*4+1)[0]for i in range(rows)],dtype='<u2')
            tensors[name]=(matrix[:rows].copy(),exponents,multipliers)
            weight_cursor+=size;metadata_cursor+=len(metadata)
    # Tied embedding/head follows the 42 transformer projections.
    rows,columns=4019,256;groups=(rows+63)//64;count=groups*64*columns;size=count*10//8
    matrix=q0._unpack_int10(raw[weight_cursor:weight_cursor+size],count).reshape(groups,columns,64).transpose(0,2,1).reshape(groups*64,columns)
    metadata=raw[metadata_cursor:metadata_cursor+groups*64*4]
    require(np.all(matrix[rows:]==0)and not any(metadata[rows*4:]),'Embedding padding differs')
    require(all(metadata[i]==0 for i in range(3,len(metadata),4)),'Embedding metadata reserved byte differs')
    tensors['model.embed_tokens.weight']=(matrix[:rows].copy(),
        np.array([struct.unpack_from('<b',metadata,i*4)[0]for i in range(rows)],dtype=np.int8),
        np.array([struct.unpack_from('<H',metadata,i*4+1)[0]for i in range(rows)],dtype='<u2'))
    weight_cursor+=size;metadata_cursor+=len(metadata)
    require(weight_cursor==211800*32 and metadata_cursor==(211920+2328)*32,'Projection region census differs')
    norm_metadata=raw[metadata_cursor:metadata_cursor+48]
    require(all(norm_metadata[i]==0 for i in range(3,48,4)),'Norm metadata reserved byte differs')
    for index,name in enumerate(f'model.layers.{l}.{suffix}'for l in range(6)for suffix in builder.NORMS):
        values=q0._unpack_int10(raw[weight_cursor+index*320:weight_cursor+(index+1)*320],256)
        exponent,multiplier=struct.unpack_from('<bH',norm_metadata,index*4)
        tensors[name]=(values.copy(),np.array([exponent],dtype=np.int8),np.array([multiplier],dtype='<u2'))
    cursor=metadata_cursor+64
    final=raw[cursor:cursor+323];cursor+=352
    exponent,multiplier=struct.unpack_from('<bH',final,320)
    tensors['model.norm.weight']=(q0._unpack_int10(final[:320],256).copy(),
        np.array([exponent],dtype=np.int8),np.array([multiplier],dtype='<u2'))
    cos0=raw[cursor:cursor+8192];cursor+=8192
    sin0=raw[cursor:cursor+8192];cursor+=8192
    exp=raw[cursor:cursor+16388];cursor+=16416
    silu=raw[cursor:cursor+131072];cursor+=131072
    cos_tail=raw[cursor:cursor+122880];cursor+=122880
    sin_tail=raw[cursor:cursor+122880];cursor+=122880
    require(cursor==len(raw),'Model image region census differs')
    records=manifest['tensors'];require(set(tensors)=={r['name']for r in records},'Reconstructed tensor census differs')
    coefficients=[];exponents=bytearray();multipliers=bytearray()
    for record in records:
        values,exponent,multiplier=tensors[record['name']]
        require(list(values.shape)==record['shape'],'Reconstructed tensor geometry differs')
        coefficients.append(values.reshape(-1));exponents.extend(exponent.tobytes());multipliers.extend(multiplier.tobytes())
    payloads={'manifest.json':manifest_raw,'weights.i10.lsb0.bin':artifacts._pack_int10(np.concatenate(coefficients)),
        'exponents.i8.bin':bytes(exponents),'multipliers.u16le.bin':bytes(multipliers),
        'rope_cos_q15.i16le.bin':(cos0+cos_tail)[:32768],
        'rope_sin_q15.i16le.bin':(sin0+sin_tail)[:32768],
        'exp_neg_q30.i32le.bin':exp,'silu_q10.i16le.bin':silu}
    for name,(size,digest)in q0._release_specs().items():
        require(len(payloads[name])==size and sha(payloads[name])==digest,'Reconstructed canonical ROM differs: '+name)
    return payloads

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image',type=Path,default=PACKAGE/'assets/board1-real-semantic-image2048.bin')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();payloads=reconstruct(args.image)
    args.output.mkdir(parents=True,exist_ok=False)
    for name,raw in payloads.items():
        with(args.output/name).open('xb')as stream:stream.write(raw)
    from quantization.oracle import QuantizedModel
    canonical=QuantizedModel.load(args.output)
    import numpy as np
    builder=load_module('_seeded_image_roundtrip',PACKAGE/'tools/materialize_image.py')
    outputs,_=builder.derive(canonical,np)
    require(outputs['board1-real-semantic-image2048.bin']==args.image.read_bytes(),'Image/ROM roundtrip differs')
    print(json.dumps(dict(passed=True,rom_files=8,all_canonical_rom_hashes_match=True,
        image_roundtrip_matches=True,image_sha256=IMAGE_SHA,hardware_access=False)))

if __name__=='__main__':
    require(sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize,'Run Python -I -B, without -O')
    main()

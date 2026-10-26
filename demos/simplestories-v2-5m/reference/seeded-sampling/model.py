"""Portable exact integer model with explicit scalar/native arithmetic engines.

The unchanged authenticated Q0 source supplies matrix, RMSNorm, residual, RoPE,
SiLU and attention arithmetic. Native mode replaces only normalization/shift
loops with checked integer C++ kernels; scalar mode never builds/loads a library.
"""
from __future__ import annotations
import copy
import ctypes
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent
REFERENCE=HERE.parent
PACKAGE=HERE.parents[1]
ORACLE_SHA='9b048a8e8b82faba3d21fd6b259aa1c23d91f04662fe2734fc109602777b4a74'
IMAGE_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
SEED_A=0x99aabbccddeeff001122334455667788
SEED_B=0xfefdfcfbfaf9f8f70102030405060708

def require(ok,message):
    if not ok:raise ValueError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module)
    return module

def native_functions(oracle,np,build_dir):
    require(build_dir is not None,'Native mode requires --build-dir outside the source package')
    folder=Path(build_dir).resolve()
    require(folder!=PACKAGE.resolve()and PACKAGE.resolve()not in folder.parents,'Native build must be outside the source package')
    folder.mkdir(parents=True,exist_ok=True)
    compiler=shutil.which('c++');require(compiler is not None,'No C++ compiler; select --engine scalar')
    compiler=Path(compiler).resolve();source=HERE/'exact_normalize.cpp'
    extension='.dylib'if sys.platform=='darwin'else'.so'
    library=folder/('seeded_exact_normalize'+extension);receipt=folder/'BUILD.json'
    flags=['-dynamiclib']if sys.platform=='darwin'else['-shared','-fPIC']
    inputs=dict(source_sha256=sha(source),compiler_sha256=sha(compiler),flags=['-O3','-std=c++17',*flags])
    reuse=False
    if receipt.is_file()and library.is_file()and not receipt.is_symlink()and not library.is_symlink():
        old=json.loads(receipt.read_bytes())
        reuse=old.get('inputs')==inputs and old.get('library_sha256')==sha(library)
    if not reuse:
        require(not library.is_symlink()and not receipt.is_symlink(),'Native build output is a symlink')
        subprocess.run([str(compiler),*inputs['flags'],str(source),'-o',str(library)],check=True)
        receipt.write_text(json.dumps(dict(inputs=inputs,library_sha256=sha(library)),indent=2)+'\n')
    native=ctypes.CDLL(str(library));i64=ctypes.POINTER(ctypes.c_int64);i16=ctypes.POINTER(ctypes.c_int16)
    native.normalize.argtypes=[i64,i16,ctypes.c_size_t,i16,ctypes.POINTER(ctypes.c_int),ctypes.POINTER(ctypes.c_size_t)]
    native.normalize.restype=ctypes.c_int
    native.round_shift.argtypes=[i64,ctypes.c_size_t,ctypes.c_int,i64];native.round_shift.restype=ctypes.c_int
    def normalize(values,exponents,stats,site='bfp_normalize'):
        values=np.ascontiguousarray(values,dtype=np.int64)
        exponents=np.ascontiguousarray(np.broadcast_to(np.asarray(exponents,dtype=np.int16),values.shape))
        output=np.empty(values.shape,dtype=np.int16);exponent=ctypes.c_int();saturation=ctypes.c_size_t()
        status=native.normalize(values.ctypes.data_as(i64),exponents.ctypes.data_as(i16),values.size,
            output.ctypes.data_as(i16),ctypes.byref(exponent),ctypes.byref(saturation))
        if status:raise oracle.QuantizationError('Native exact normalization rejected arithmetic bound')
        stats.observe_saturation(site,saturation.value);stats.observe_exponent(exponent.value)
        return oracle.BFP(output,exponent.value)
    def round_shift(values,shift):
        values=np.ascontiguousarray(values,dtype=np.int64);output=np.empty_like(values)
        if native.round_shift(values.ctypes.data_as(i64),values.size,shift,output.ctypes.data_as(i64)):
            raise oracle.QuantizationError('Native exact signed shift rejected arithmetic bound')
        return output
    return normalize,round_shift

def load(rom,*,engine='scalar',build_dir=None):
    require(sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize,'Run Python -I -B, without -O')
    import numpy as np
    require(np.__version__=='1.26.4','Use NumPy 1.26.4')
    require(sha(REFERENCE/'quantization/oracle.py')==ORACLE_SHA,'Original integer model source changed')
    require(engine in ('scalar','native'),'Engine must be scalar or native')
    sys.path.insert(0,str(REFERENCE))
    from quantization import oracle as baseline
    oracle=load_module('quantization.portable_seeded_oracle',REFERENCE/'quantization/oracle.py')
    context=load_module('_portable_seeded_context2048',HERE/'context2048.py')
    original=baseline.QuantizedModel.load(rom)
    cosine,sine=context.derive_rope()
    require(np.array_equal(cosine[:512],original.rope_cos)and np.array_equal(sine[:512],original.rope_sin),
            '2048 RoPE prefix differs from authenticated ROM')
    builder=load_module('_portable_seeded_image_builder',PACKAGE/'tools/materialize_image.py')
    outputs,_=builder.derive(original,np)
    require(sha(PACKAGE/'assets/board1-real-semantic-image2048.bin')==IMAGE_SHA
        and outputs['board1-real-semantic-image2048.bin']==(PACKAGE/'assets/board1-real-semantic-image2048.bin').read_bytes(),
        'Authenticated integer model does not reconstruct the fixed model image')
    data=oracle.QuantizedModel(original.tensors,cosine,sine,original.silu,original.exp_neg,original.manifest)
    if engine=='native':oracle._normalize_mixed,oracle._round_shift_even=native_functions(oracle,np,build_dir)
    context.q0=oracle
    sampler=load_module('_portable_seeded_sampler',PACKAGE/'variants/seeded-sampling/tools/sampler_oracle.py')
    class IntegerModel(oracle.IntegerLlama):
        _attention=context.IntegerLlama2048._attention
        def raw_head(self,hidden):
            embedding=self.model.tensors['model.embed_tokens.weight']
            dots=embedding.value.astype(np.int64)@hidden.value.astype(np.int64)
            self.stats.max_matrix_accumulator=max(self.stats.max_matrix_accumulator,int(np.max(np.abs(dots))))
            if int(np.max(np.abs(dots)))>=1<<34:raise oracle.QuantizationError('Head signed35 dot bound exceeded')
            scaled=dots*embedding.multiplier.astype(np.int64)
            self.stats.max_scale_product=max(self.stats.max_scale_product,int(np.max(np.abs(scaled))))
            if int(np.max(np.abs(scaled)))>=1<<49:raise oracle.QuantizationError('Head signed50 scaled bound exceeded')
            exponents=embedding.exponent.astype(np.int16)+hidden.exponent-15
            return [(int(value),int(exponent))for value,exponent in zip(scaled,exponents)]
        def consume(self,token,produce=True):
            require(type(token)is int and 0<=token<4019,'Token outside fixed vocabulary')
            require(not self.faulted and self.position<2048,'Integer reference context full or faulted')
            try:
                hidden=self._embedding(token)
                for layer in range(6):hidden=self._layer(hidden,layer,self.position)
                result=self.raw_head(self._rms_norm(hidden,'model.norm.weight'))if produce else None
                self.position+=1
                return result
            except oracle.QuantizationError:
                self.faulted=True;raise
        def fork(self):
            other=IntegerModel(self.model);other.keys=[list(layer)for layer in self.keys]
            other.values=[list(layer)for layer in self.values];other.position=self.position
            other.stats=copy.deepcopy(self.stats);other.faulted=self.faulted;return other
    return dict(np=np,baseline=baseline,oracle=oracle,canonical_model=original,data=data,
        Model=IntegerModel,sampler=sampler,engine=engine)

def state_digest(model):
    digest=hashlib.sha256()
    for cache in(model.keys,model.values):
        for layer in cache:
            for row in layer:
                digest.update(row.exponent.to_bytes(2,'little',signed=True));digest.update(row.value.astype('<i2').tobytes())
    return digest.hexdigest()

def generate(model,head,sampler,temperature,seed,count):
    state=sampler.initial_state(seed);tokens=[];digests=[]
    for index in range(count):
        previous=state;token,state=sampler.sample(head,temperature,state)
        if temperature==0:require(state==previous,'Greedy selection consumed PRNG state')
        tokens.append(token);digests.append(hashlib.sha256(canonical(head)).hexdigest())
        if index+1<count:head=model.consume(token)
    return dict(generated_tokens=tokens,head_rows_sha256=digests,final_prng_state=[f'0x{x:016x}'for x in state],
        evaluated_positions=model.position,final_kv_sha256=state_digest(model))

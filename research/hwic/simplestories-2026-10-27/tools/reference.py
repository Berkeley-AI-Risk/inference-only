"""Separate pinned integer model and exhaustive image-to-coefficient audit.

This program prepares comparison fixtures only. It is never called by the DUT,
never supplies a DUT memory response, and never fills a missing RTL operation.
"""
import argparse,hashlib,json,math,pathlib,sys
import numpy as np
OWN=pathlib.Path(__file__).resolve().parents[1]
RELEASE=OWN
assert np.__version__=='1.26.4'
assert hashlib.sha256((RELEASE/'reference/quantization/oracle.py').read_bytes()).hexdigest()=='9b048a8e8b82faba3d21fd6b259aa1c23d91f04662fe2734fc109602777b4a74'
sys.path.insert(0,str(RELEASE/'reference'))
from quantization import oracle as q

def sha(b):return hashlib.sha256(b).hexdigest()

def audit(model,image):
    """Decode the image backwards into canonical tensor coordinates independently.

    No call to the image exporter and no adoption of a generator's checksum.
    Compare every true coefficient, every padded lane, row scale/exponent,
    norm coefficient and nonlinear-table byte against the authenticated Q0.
    """
    raw=np.unpackbits(np.frombuffer(image[:211800*32],dtype=np.uint8),bitorder='little').reshape(-1,10)
    u=raw.astype(np.int16)@(1<<np.arange(10,dtype=np.int16))
    values=np.where(u>=512,u-1024,u).astype(np.int16)
    jobs=[]
    geometry=[('self_attn.q_proj.weight',256,256),('self_attn.k_proj.weight',128,256),('self_attn.v_proj.weight',128,256),('self_attn.o_proj.weight',256,256),('mlp.gate_proj.weight',682,256),('mlp.up_proj.weight',682,256),('mlp.down_proj.weight',256,682)]
    for layer in range(6):
        jobs.extend((f'model.layers.{layer}.{name}',rows,cols) for name,rows,cols in geometry)
    jobs.append(('model.embed_tokens.weight',4019,256))
    cursor=0;meta_cursor=211920*32;count=0;padding=0;records=[]
    for name,rows,cols in jobs:
        groups=(rows+63)//64;n=groups*64*cols
        decoded=values[cursor:cursor+n].reshape(groups,cols,64).transpose(0,2,1).reshape(groups*64,cols)
        t=model.tensors[name]
        assert np.array_equal(decoded[:rows],t.value),name
        assert not np.any(decoded[rows:]),name
        metadata=np.frombuffer(image[meta_cursor:meta_cursor+groups*64*4],dtype=np.uint8).reshape(-1,4)
        assert np.array_equal(metadata[:rows,0].view(np.int8),t.exponent),name
        assert np.array_equal(metadata[:rows,1].astype(np.uint16)+(metadata[:rows,2].astype(np.uint16)<<8),t.multiplier),name
        assert not np.any(metadata[:,3]) and not np.any(metadata[rows:]),name
        records.append({'tensor':name,'shape':[rows,cols],'first_image_bit':cursor*10,'coefficient_count':rows*cols,'padded_zero_coefficients':n-rows*cols,'first_metadata_byte':meta_cursor,'canonical_int16le_sha256':sha(decoded[:rows].astype('<i2').tobytes())})
        cursor+=n;meta_cursor+=groups*64*4;count+=rows*cols;padding+=n-rows*cols
    assert cursor==values.size and meta_cursor==214248*32
    norm_start=211800*32
    norm_names=[f'model.layers.{layer}.{kind}.weight' for layer in range(6) for kind in ['input_layernorm','post_attention_layernorm']]
    for i,name in enumerate(norm_names+['model.norm.weight']):
        start=norm_start+i*320 if i<12 else 214250*32
        bits=np.unpackbits(np.frombuffer(image[start:start+320],dtype=np.uint8),bitorder='little').reshape(-1,10)
        u=bits.astype(np.int16)@(1<<np.arange(10,dtype=np.int16));v=np.where(u>=512,u-1024,u)
        assert np.array_equal(v,model.tensors[name].value),name
        mstart=214248*32+i*4 if i<12 else start+320
        assert int.from_bytes(image[mstart:mstart+1],'little',signed=True)==int(model.tensors[name].exponent[0])
        assert int.from_bytes(image[mstart+1:mstart+3],'little')==int(model.tensors[name].multiplier[0])
        count+=256
        records.append({'tensor':name,'shape':[256],'first_image_byte':start,'coefficient_count':256})
    assert count==5354496 and padding==70912
    assert image[214773*32:214773*32+16388]==model.exp_neg.astype('<i4').tobytes()
    assert image[215286*32:219382*32]==model.silu.astype('<i2').tobytes()
    cosine=image[214261*32:214517*32]+image[219382*32:223222*32]
    sine=image[214517*32:214773*32]+image[223222*32:227062*32]
    assert sha(cosine)=='79f7f407afea8759b487b1c1af04086514011cf4541a13e6fb7113bc03697e5a'
    assert sha(sine)=='4acbdcf5d0d83ad9dca7a1a8619ba5e481d594365751b2fb564eaf4e13a8201f'
    assert cosine[:32768]==model.rope_cos.astype('<i2').tobytes() and sine[:32768]==model.rope_sin.astype('<i2').tobytes()
    return {'passed':True,'coefficients_compared':count,'padded_zero_coefficients_compared':padding,'all_row_metadata_compared':True,'all_nonlinear_table_bytes_compared':True,'records':records,'image_sha256':sha(image),'independence':'Reverse-decode image to canonical tensor coordinates; not exporter checksum.'}

class Trace(q.IntegerLlama):
    def __init__(self,model,out):super().__init__(model);self.out=out;self.epoch=0;self.count=0
    def emit(self,layer,stage,vector):
        for index,value in enumerate(vector.value):self.emit_raw(layer,stage,index,int(value),vector.exponent)
    def emit_raw(self,layer,stage,index,value,exponent):
        word=(self.epoch<<120)|(self.position<<104)|(layer<<96)|(stage<<88)|(index<<72)|((exponent&255)<<64)|(value&((1<<64)-1))
        self.out.write(f'{word:032x}\n');self.count+=1
    def _layer(self,h,layer,position):
        p=f'model.layers.{layer}'
        n=self._rms_norm(h,p+'.input_layernorm.weight');self.emit(layer,0,n)
        query=self._matvec(p+'.self_attn.q_proj.weight',n);self.emit(layer,1,query)
        key=self._matvec(p+'.self_attn.k_proj.weight',n);self.emit(layer,2,key)
        val=self._matvec(p+'.self_attn.v_proj.weight',n);self.emit(layer,3,val)
        query=self._rope(query,position);self.emit(layer,4,query)
        key=self._rope(key,position);self.emit(layer,5,key)
        self.keys[layer].append(key);self.values[layer].append(val)
        a=self._attention(query,layer);self.emit(layer,7,a)
        a=self._matvec(p+'.self_attn.o_proj.weight',a);self.emit(layer,8,a)
        h=q._add(h,a,self.stats);self.emit(layer,9,h)
        n=self._rms_norm(h,p+'.post_attention_layernorm.weight');self.emit(layer,10,n)
        gate=self._matvec(p+'.mlp.gate_proj.weight',n);self.emit(layer,11,gate)
        up=self._matvec(p+'.mlp.up_proj.weight',n);self.emit(layer,12,up)
        product=self._multiply(self._silu(gate),up);self.emit(layer,13,product)
        down=self._matvec(p+'.mlp.down_proj.weight',product);self.emit(layer,14,down)
        h=q._add(h,down,self.stats);self.emit(layer,15,h)
        return h
    def consume(self,token,head):
        h=self._embedding(token);self.emit(7,17,h)
        for layer in range(6):h=self._layer(h,layer,self.position)
        prediction=None
        if head:
            h=self._rms_norm(h,'model.norm.weight');self.emit(7,18,h)
            t=self.model.tensors['model.embed_tokens.weight']
            dot=t.value.astype(np.int64)@h.value.astype(np.int64)
            raw=dot*t.multiplier.astype(np.int64)
            exps=t.exponent.astype(np.int64)+h.exponent-15
            for i in range(4019):self.emit_raw(7,19,i,int(raw[i]),int(exps[i]))
            prediction=self._argmax(h)[0]
        self.position+=1
        return prediction
    def continuation(self,prompt,count):
        for token in prompt[:-1]:self.consume(token,False)
        token=self.consume(prompt[-1],True);generated=[token]
        for _ in range(count-1):token=self.consume(token,True);generated.append(token)
        return generated

def main():
    p=argparse.ArgumentParser();p.add_argument('--work',type=pathlib.Path,required=True);p.add_argument('--rom',type=pathlib.Path,required=True);p.add_argument('--smoke',action='store_true');p.add_argument('--image',type=pathlib.Path,required=True);a=p.parse_args()
    model=q.QuantizedModel.load(a.rom)
    image=a.image.read_bytes()
    audit_record=audit(model,image)
    (a.work/'WEIGHT-MAP-AUDIT.json').write_text(json.dumps(audit_record,indent=2,sort_keys=True)+'\n')
    curated=json.loads((RELEASE/'tests/reference-cases.json').read_text())
    specs=[('around','around128',2,1,[])] if a.smoke else [('around','around128',16,2,[]),('fox','fox128',8,2,[]),('moon','moon64',8,1,[]),('cancel-model','around128',4,1,['+CANCEL_MODEL']),('cancel-kv','around128',4,1,['+CANCEL_KV']),('cancel-held','around128',2,1,['+CANCEL_HELD']),('admission','around128',2,1,['+ADMISSION'])]
    cases={}
    for name,key,count,replay,flags in specs:
        d=a.work/name;d.mkdir()
        prompt=curated[key]['prompt_tokens']
        with (d/'expected.memh').open('w') as out:
            m=Trace(model,out);generated=m.continuation(prompt,count)
            assert generated==curated[key]['generated_tokens'][:count]
            independent=q.IntegerLlama(model).generate(prompt,count,stop_at_eos=False)
            assert generated==independent
            m.clear();m.epoch=1;replayed=m.continuation(prompt,replay)
            assert replayed==generated[:replay]
            events=m.count
        config=[0]*4096;config[:4]=[len(prompt),count,replay,events]
        config[16:16+len(prompt)]=prompt;config[1024:1024+count]=generated;config[2048:2048+replay]=replayed
        (d/'case.memh').write_text(''.join(f'{n:08x}\n' for n in config))
        cases[name]={'prompt_tokens':prompt,'generated_tokens':generated,'replay_tokens':replayed,'tensor_values':events,'flags':flags,'expected_sha256':sha((d/'expected.memh').read_bytes())}
    (a.work/'REFERENCE.json').write_text(json.dumps({'passed':True,'oracle_sha256':sha((RELEASE/'reference/quantization/oracle.py').read_bytes()),'numpy_version':np.__version__,'cases':cases,'scope':'Separate integer inference and tensor fixtures; never connected to DUT arithmetic or memory.'},indent=2,sort_keys=True)+'\n')
    print('REFERENCE_PASS',len(cases),'cases',flush=True)
if __name__=='__main__':main()

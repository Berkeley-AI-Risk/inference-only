"""Integer, incremental-KV model of the target hardware arithmetic."""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import sentencepiece
import torch
from checkpoint_reference import EXPECTED, PROMPTS, ROOT, UPSTREAM, digest

Q = 65536
EXP = np.rint(np.exp(-np.arange(4097) / 256) * (1 << 24)).astype(np.int64)
POS = np.arange(256)[:, None] / np.power(10000., np.arange(4)[None, :] / 4)
COS = np.rint(np.cos(POS) * 32768).astype(np.int64)
SIN = np.rint(np.sin(POS) * 32768).astype(np.int64)

def shift(v, n):
    return (v + (1 << (n - 1))) >> n

def divide(v, d):
    return (v + (d // 2)) // d

def expneg(v):
    return EXP[np.minimum(4096, shift(v, 8))]

def unit(v, weights):
    rms = math.isqrt(int((v @ v) // 64) + 42950)
    return divide((v * weights) << 4, rms)

def rotary(x, pos):
    pairs = x.reshape(-1, 4, 2)
    a, b = pairs[:,:,0], pairs[:,:,1]
    return np.stack([shift(a*COS[pos] - b*SIN[pos],15),
                     shift(a*SIN[pos] + b*COS[pos],15)],axis=-1).reshape(x.shape)

def softmax(v):
    ex = expneg(v.max() - v)
    return divide(ex * Q, ex.sum())

def silu(x):
    ex = expneg(np.abs(x))
    den = (1 << 24) + ex
    sigmoid = divide(np.where(x<0,ex,1<<24) * Q, den)
    return shift(x * sigmoid, 16)

def quantized_parameters():
    assert digest(UPSTREAM/'model.pt') == EXPECTED
    weights = torch.load(UPSTREAM/'model.pt', map_location='cpu', weights_only=True)['model']
    result = {}
    for key, tensor in weights.items():
        fracbits = 12 if 'norm.weight' in key else 15
        values = np.rint(tensor.numpy().astype('float64') * (1 << fracbits))
        assert values.min() >= -32768 and values.max() <= 32767, key
        result[key] = values.astype(np.int64)
    return result

class Decoder:
    def __init__(self,w):
        self.w = w
        self.clear()

    def clear(self):
        self.pos = 0
        self.k = np.zeros((5,256,4,8), dtype=np.int64)
        self.v = np.zeros_like(self.k)

    def token(self, token_id):
        assert self.pos < 256 and 0 <= token_id < 512
        x = self.w['tok_embeddings.weight'][token_id] * 2
        routes = []
        for layer in range(5):
            prefix = f'layers.{layer}.'
            def weight(k):
                return self.w[prefix+k+'.weight']
            def project(k,a):
                return shift(weight(k) @ a,15)
            z = unit(x,weight('attention_norm'))
            q = rotary(project('attention.wq',z).reshape(8,8),self.pos)
            self.k[layer,self.pos] = rotary(project('attention.wk',z).reshape(4,8),self.pos)
            self.v[layer,self.pos] = project('attention.wv',z).reshape(4,8)
            heads = []
            for h in range(8):
                keys = self.k[layer,:self.pos+1,h//2]
                values = self.v[layer,:self.pos+1,h//2]
                scores = shift(shift(keys @ q[h],16) * 11585,15)
                result = shift(softmax(scores) @ values, 16)
                heads.extend(result)
            x = x + project('attention.wo',heads)
            z = unit(x,weight('ffn_norm'))
            scores = project('feed_forward.gate',z)
            chosen = np.argsort(-scores, kind='stable')[:2]
            mixture = softmax(scores[chosen])
            routes.append([int(e) for e in chosen])
            y = np.zeros_like(x)
            for e,c in zip(chosen,mixture):
                expert = f'feed_forward.experts.{e}.'
                mid = shift(silu(project(expert+'w1',z)) * project(expert+'w3',z),16)
                y += project(expert+'w2',mid) * c
            x = x + shift(y,16)
        self.pos += 1
        logits = shift(self.w['output.weight'] @ unit(x,self.w['norm.weight']),15)
        return int(np.argmax(logits)),routes,logits

def main():
    ref = json.loads((ROOT/'receipts/checkpoint-cpu.json').read_bytes())
    sp = sentencepiece.SentencePieceProcessor(model_file=str(UPSTREAM/'tok512.model'))
    model = Decoder(quantized_parameters())
    results = []
    for item in ref['prompts']:
        model.clear()
        generated, traces = [], []
        for t in item['prompt_ids']:
            out, routes, logits = model.token(t)
        for step in range(12):
            generated.append(out)
            traces.append({'routes':routes,'next_id':out,'logits_i32le_sha256':hashlib.sha256(logits.astype('<i4').tobytes()).hexdigest()})
            if step<11:
                out,routes,logits = model.token(out)
        first_diff = next((i for i,(a,b) in enumerate(zip(generated,item['generated_ids'])) if a != b),None)
        route_matches = sum(a==b for s,t in zip(traces,item['trace']) for a,b in zip(s['routes'],t['routes']))
        results.append({'prompt_ids':item['prompt_ids'],'generated_ids':generated,'decoded':sp.decode(item['prompt_ids']+generated),'first_greedy_difference':first_diff,'ordered_layer_routes_matching_fp32_out_of_60':route_matches,'trace':traces})
    out={'scope':'independently implemented NumPy integer incremental-KV reference vs authors FP32 checkpoint','weights_sha256':EXPECTED,'cpu_ref_sha256':digest(ROOT/'receipts/checkpoint-cpu.json'),'integer_reference_source_sha256':digest(Path(__file__)),'position_limit':256,'results':results}
    (ROOT/'receipts/integer-cpu.json').write_text(json.dumps(out,indent=2)+'\n')
    for r in results:
        print(r['decoded'],r['first_greedy_difference'],r['ordered_layer_routes_matching_fp32_out_of_60'])
if __name__=='__main__':
    main()

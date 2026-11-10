"""Private linear int16 weight image. A fixed digest ROM authenticates each 4 KiB page."""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')
import hashlib
import json
import struct
from pathlib import Path
import numpy as np
from integer_reference import COS, EXP, SIN, ROOT, quantized_parameters

BLOCK = 4096
def digest(data):
    return hashlib.sha256(data).hexdigest()

def main():
    w = quantized_parameters()
    tensors, blob = {}, bytearray()
    def append(name, key):
        values = w[key]
        tensors[name]={'offset_words':len(blob)//2,'shape':list(values.shape),'key':key}
        blob.extend(values.astype('<i2').tobytes())
    append('emb','tok_embeddings.weight')
    append('final','norm.weight')
    for l in range(5):
        base=f'layers.{l}.'
        for name,field in [('an','attention_norm'),('q','attention.wq'),('k','attention.wk'),('v','attention.wv'),('o','attention.wo'),('fn','ffn_norm'),('gate','feed_forward.gate')]:
            append(f'l{l}_{name}',base+field+'.weight')
        for e in range(8):
            for name in ['w1','w3','w2']:
                append(f'l{l}_e{e}_{name}',base+f'feed_forward.experts.{e}.{name}.weight')
    assert np.array_equal(w['output.weight'],w['tok_embeddings.weight'])
    unpadded_size = len(blob)
    blob.extend(bytes(-len(blob)%BLOCK))
    out = ROOT/'build'
    (out/'model.bin').write_bytes(blob)
    hashes = [digest(blob[i:i+BLOCK]) for i in range(0,len(blob),BLOCK)]
    (out/'page_digest.hex').write_text('\n'.join(hashes)+'\n')
    for name,values in [('exp',EXP),('cos',COS),('sin',SIN)]:
        (out/(name+'.hex')).write_text('\n'.join(f'{int(v)&0xffffffff:08x}' for v in values.ravel())+'\n')
    (ROOT/'receipts/layout.json').write_text(json.dumps({'tensors':tensors,'parameter_bytes':unpadded_size,'padded_bytes':len(blob),'image_sha256':digest(blob),'page_bytes':BLOCK,'pages':len(hashes),'ordered_page_digest_bytes_sha256':digest(b''.join(bytes.fromhex(h) for h in hashes))},indent=2)+'\n')
    print(unpadded_size,len(blob),len(hashes),digest(blob))
if __name__=='__main__':
    main()

"""Verify captured UART bytes and cross-check recorded results against both CPU traces."""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')
import hashlib,json,statistics
from pathlib import Path
from uart_replay import crc
ROOT=Path(__file__).resolve().parents[1]
def load(p):return json.loads((ROOT/'evidence'/p).read_bytes())
def decode(raw,magic):
    data=bytes.fromhex(raw)
    assert len(data)==5 and data[0]==magic and data[4]==crc(data[:4])
    return data[1],int.from_bytes(data[2:4],'little')
def main():
    d=load('physical.json');g=load('checkpoint-cpu.json')['prompts'];q=load('integer-cpu.json')['results']
    assert all(x['prompt_ids']==y['prompt_ids'] and x['generated_ids']==y['generated_ids'] for x,y in zip(g,q))
    expected=[]
    for h in g:expected.extend([(2,0,130,0)]+[(0,t,128,0) for t in h['prompt_ids']]+[(1,0,129,t) for t in h['generated_ids']])
    expected.extend([(2,0,130,0),(2,0,130,0),(0,1,128,0),(1,0,129,403),(2,0,130,0)])
    def decoded(rows):return [(*decode(r['tx'],0xa5),*decode(r['rx'],0x5a)) for r in rows]
    assert decoded(d['honest'])==expected
    cancelled=[r for r in d['honest'] if 'cancelled_tx' in r]
    assert len(cancelled)==1 and decode(cancelled[0]['cancelled_tx'],0xa5)==(1,0) and cancelled[0]['roundtrip_us']>=19000 and cancelled[0]['single_write_bytes']==10
    assert decoded(d['corrupt'])==[(2,0,130,0)]+[(0,t,128,0) for t in g[0]['prompt_ids']]+[(1,0,193,0)]
    assert d['bitstream_sha256']==load('route-volatile3.json')['programming_files']['tlm26.fs']
    assert d['boot']['honest']['acknowledged_pages']==d['boot']['corrupt']['acknowledged_pages']==768
    img=bytearray((ROOT/'build/model.bin').read_bytes())
    assert hashlib.sha256(img).hexdigest()==d['boot']['honest']['sha256']
    img[23*4096]^=1
    assert hashlib.sha256(img).hexdigest()==d['boot']['corrupt']['sha256']
    steps=[r['roundtrip_us'] for r in d['honest'] if decode(r['rx'],0x5a)[0]==129][:24]
    assert statistics.median(steps)/1000==d['latency']['24_generated_steps']['median_ms']
    print('Verified both histories, 24 tokens, the affected STEP refusal, CLEAR, the fresh-token replay, and the recorded median latency.')
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Compute the common 128-output greedy reference from physical model bytes."""
from pathlib import Path
import argparse,datetime,hashlib,json,sys,time

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--demo',required=True,type=Path)
    p.add_argument('--image',required=True,type=Path)
    p.add_argument('--output',required=True,type=Path)
    a=p.parse_args()
    if a.output.exists():raise FileExistsError('preserve existing evidence')
    sys.path.insert(0,str(ROOT/'reference'))
    import tang_image
    image=a.image.read_bytes()
    model=tang_image.integer_model(image,a.demo)
    from quantization.oracle import IntegerLlama
    oracle=IntegerLlama(model);tokens=[];token=378;t=time.monotonic()
    for i in range(128):
        token,_=oracle.forward_token(token);tokens.append(int(token))
        if (i+1)%32==0:print('Reference outputs:',i+1,flush=True)
    existing=json.loads((a.demo/'tests/reference-cases.json').read_text())['around128']
    if image== (a.demo/'assets/board1-real-semantic-image2048.bin').read_bytes():
        assert existing['prompt_tokens']==[378] and tokens==existing['generated_tokens']
    sources={'tools/common_speed_reference.py':Path(__file__),
             'reference/tang_image.py':ROOT/'reference/tang_image.py',
             'reference/signed_update.py':ROOT/'reference/signed_update.py'}
    sources.update({'demo/reference/quantization/'+s.name:s for s in (a.demo/'reference/quantization').glob('*.py')})
    result={'schema':'signed-update-common-speed-reference-v1','prompt_tokens':[378],
            'generated_tokens':tokens,'output_count':128,'decoding':'greedy','temperature':0,
            'stop_at_eos':False,'feedback_dependent':True,'image_sha256':hashlib.sha256(image).hexdigest(),
            'source_sha256':{n:hashlib.sha256(s.read_bytes()).hexdigest() for n,s in sources.items()},
            'elapsed_seconds':time.monotonic()-t,'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'agrees_with_published_base_reference':tokens==existing['generated_tokens']}
    with a.output.open('x') as f:json.dump(result,f,indent=2);f.write('\n')
    print(json.dumps({'result':'PASS','outputs':128,'elapsed_seconds':result['elapsed_seconds']}))

if __name__=='__main__':main()

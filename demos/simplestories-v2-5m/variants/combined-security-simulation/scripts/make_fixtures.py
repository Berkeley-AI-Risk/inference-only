"""Private public-key fixtures and fresh independent numerical/AES references."""
from pathlib import Path
import hashlib, json, subprocess, sys, shutil
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from pin_sources import DEMO, sha
from prepare import KEYS, NONCES
sys.path.insert(0,str(DEMO/'variants/signed-update/tang/reference'))
import signed_update as su
import tang_image as tang
sys.path.insert(0,str(DEMO/'variants/home-authorization/reference'))
import home_auth as h
sys.path.insert(0,str(DEMO/'reference'))
from quantization.oracle import IntegerLlama

def context(root,epoch,domain):
    return hashlib.sha256(b'SAWIC-COMBO-v1'.ljust(16,b'\0')+root+epoch.to_bytes(4,'big')+domain.to_bytes(4,'big')).digest()

def main():
    out=HERE/'fixtures-v1';out.mkdir(exist_ok=False)
    base=(DEMO/'assets/board1-real-semantic-image2048.bin').read_bytes()
    changed=bytearray(base);changed[214250*32:214260*32]=bytes(320)
    metadata=bytes.fromhex(''.join((DEMO/'hardware/project/metadata192.memh').read_text().split()))
    authorities=[su.DemoAuthority(i) for i in range(3)]
    keys=[a.public_key for a in authorities]
    home=h.su.DemoAuthority(h.HOME_AUTHORITY)
    nonces=[hashlib.sha256(label).digest() for label in (b'PUBLIC COMBINED CHALLENGE ONE',b'PUBLIC COMBINED CHALLENGE TWO')]
    models={};record={'public_demo_keys':True,'source_model_sha256':sha(DEMO/'assets/board1-real-semantic-image2048.bin'),'models':models,'keys':KEYS,'counter_nonces':NONCES,'contexts':{},'nonce_provider':'Explicit deterministic private challenge fixture; no physical entropy claim','epoch_service':'Explicit modeled persistent nonzero monotonic epoch; not a DUT nonvolatile implementation','time_service':'Explicit modeled monotonic private time; no trusted physical clock claim'}
    def hexbytes(name,data): (out/name).write_text(''.join(f'{b:02x}\n' for b in data))
    for i,(label,image) in enumerate((('A',base),('B',bytes(changed)))):
        package=su.make_package(image,metadata,i+1,authorities[:2],[8+i]*2)
        info=tang.validate_tang(package,keys)
        frame=package[:-su.IMAGE_BYTES];root=frame[72:104]
        command=[shutil.which('openssl') or 'openssl','enc','-aes-256-ctr','-K',KEYS['weight'+label],'-iv',NONCES[i]+'00000000','-nosalt']
        cipher=subprocess.run(command,input=image,capture_output=True,check=True).stdout
        plain=subprocess.run(command,input=cipher,capture_output=True,check=True).stdout
        if plain!=image or len(cipher)!=len(image): raise ValueError('Independent AES round trip')
        if label=='A' and cipher!=(DEMO/'assets/board1-encrypted-model2048.bin').read_bytes(): raise ValueError('Released ciphertext differs')
        (out/f'{label}.image.bin').write_bytes(image);(out/f'{label}.cipher.bin').write_bytes(cipher)
        (out/f'{label}.frame.bin').write_bytes(frame);hexbytes(f'{label}.frame.hex',frame)
        (out/f'{label}.cipher.memh').write_text(''.join(cipher[x:x+32][::-1].hex()+'\n' for x in range(0,len(cipher),32)))
        model=tang.integer_model(image,DEMO);oracle=IntegerLlama(model)
        t0,_=oracle.forward_token(1);t1,_=oracle.forward_token(t0)
        if label=='B' and [t0,t1]!=[0,0]: raise ValueError('Synthetic B oracle')
        models[label]={'model_commitment':root.hex(),'image_sha256':hashlib.sha256(image).hexdigest(),'cipher_sha256':hashlib.sha256(cipher).hexdigest(),'frame_bytes':len(frame),'prompt':[1],'tokens':[int(t0),int(t1)],'key_domain':i+1,'validated_package':info}
        for epoch in (1,2):
            ctx=context(root,epoch,i+1)
            record['contexts'][label+'-e'+str(epoch)]=ctx.hex()
            for n,nonce in enumerate(nonces):
                request=h.request_bytes(h.DEVICE_ID,nonce,ctx)
                leaf=(i*4+(epoch-1)*2+n)
                grant=request+home.sign_reserved_leaf(request,leaf)
                h.su.lms_verify(home.public_key,request,grant[128:])
                hexbytes(f'{label}-e{epoch}-n{n+1}.request.hex',request)
                hexbytes(f'{label}-e{epoch}-n{n+1}.grant.hex',grant)
        print(label,'fresh numerical oracle',[int(t0),int(t1)],flush=True)
    lines=[]
    for i,label in enumerate('AB'):
        lines+=[f"localparam logic [255:0] MODEL_{label}=256'h{models[label]['model_commitment']};",
                f"localparam logic [95:0] NONCE_{label}=96'h{NONCES[i]};"]
    for i,nonce in enumerate(nonces): lines.append(f"localparam logic [255:0] CHALLENGE_{i+1}=256'h{nonce.hex()};")
    lines += [f"localparam logic [127:0] HOME_DEVICE=128'h{h.DEVICE_ID.hex()};",
              f"localparam logic [127:0] HOME_KEY_ID=128'h{home.public_key[8:24].hex()};",
              f"localparam logic [255:0] HOME_KEY_ROOT=256'h{home.public_key[24:].hex()};",
              f"localparam logic [255:0] HOME_GEOMETRY=256'h{h.su.GEOMETRY.hex()};"]
    (out/'fixture_constants.svh').write_text('\n'.join(lines)+'\n')
    record['files']={p.name:{'sha256':sha(p),'bytes':p.stat().st_size} for p in out.iterdir() if p.is_file()}
    (out/'FIXTURES.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
    print('FIXTURES_READY',out,flush=True)

if __name__=='__main__': main()

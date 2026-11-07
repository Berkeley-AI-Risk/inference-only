"""Independently authenticate native captured SIV records with OpenSSL."""
from pathlib import Path
import hashlib,importlib.util,json,re,sys
HERE=Path(__file__).resolve().parent
HISTORY=HERE/'reference'

def check_role(path,model_label,epoch,fixtures):
    if Path(path).stat().st_size>4096:raise ValueError('Role capture exceeds fixed fixture geometry')
    sys.path.insert(0,str(HISTORY))
    import kv_siv_role_reference as ref
    words=[]
    for line in Path(path).read_text().splitlines():
        line=line.split('//',1)[0].strip()
        if not line or line.startswith('@'):continue
        for word in line.split():
            if not re.fullmatch('[a-fA-F0-9]{64}',word):raise ValueError('Malformed native role capture')
            words.append(int(word,16).to_bytes(32,'little'))
    if len(words)!=5:raise ValueError('Expected five actual native cipher words')
    raw=b''.join(words);f=json.loads(Path(fixtures).read_text())
    key=bytes.fromhex(f['keys']['mac'+model_label]+f['keys']['ctr'+model_label])
    other='B' if model_label=='A' else 'A'
    model_id=bytes.fromhex(f['models'][model_label]['image_sha256'])
    associated=ref.context(epoch<<32,0,0,0,0,model_id=model_id)
    aes=ref.OpenSSL()
    plain=aes.native_siv(key,associated,raw[:130],raw[130:146])
    independent=ref.open_role(aes,key,associated,raw)
    if independent!=plain+bytes(30):raise ValueError('Native and composed SIV references differ')
    tag,cipher=aes.native_siv(key,associated,plain)
    if cipher+tag+bytes(14)!=raw:raise ValueError('Native SIV ciphertext differs from RTL capture')
    controls=[]
    tests=[('wrong-model-ID',key,ref.context(epoch<<32,0,0,0,0,model_id=bytes.fromhex(f['models'][other]['image_sha256'])),raw),
           ('wrong-model-key',bytes.fromhex(f['keys']['mac'+other]+f['keys']['ctr'+other]),associated,raw),
           ('wrong-session-epoch',key,ref.context((epoch+1)<<32,0,0,0,0,model_id=model_id),raw),
           ('changed-cipher-byte',key,associated,bytes([raw[0]^1])+raw[1:])]
    for name,k,ad,data in tests:
        try:aes.native_siv(k,ad,data[:130],data[130:146])
        except ref.AuthenticationError:controls.append(name)
        else:raise ValueError('Independent SIV negative control accepted '+name)
    return {'passed':True,'native_capture':str(path),'native_capture_sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),
        'record_bytes':len(raw),'model':model_label,'epoch':epoch,'SIV_MODEL_ID':model_id.hex(),'plaintext_sha256':hashlib.sha256(plain).hexdigest(),
        'independent_OpenSSL_native_SIV_and_composed_reference_agree':True,'actual_RTL_record_reencrypted_byte_exact':True,'refused_controls':controls,
        'openssl_version':aes.version,'libcrypto_identifier':str(sys.modules['kv_siv_reference'].LIBCRYPTO),
        'reference_pins':{str(HISTORY/n):hashlib.sha256((HISTORY/n).read_bytes()).hexdigest() for n in ('kv_siv_reference.py','kv_siv_role_reference.py')},
        'private_test_values_only':True}

def check_openssl():
    sys.path.insert(0,str(HISTORY))
    import kv_siv_role_reference as ref
    aes=ref.OpenSSL()
    # Exercise native SIV rather than accepting a version string alone.
    key=bytes(range(64));ad=[b'combined replay prerequisite'];plain=b'public test'
    tag,cipher=aes.native_siv(key,ad,plain)
    if aes.native_siv(key,ad,cipher,tag)!=plain:raise ValueError('Native SIV roundtrip failed')
    return {'version':aes.version,'libcrypto_identifier':str(sys.modules['kv_siv_reference'].LIBCRYPTO)}

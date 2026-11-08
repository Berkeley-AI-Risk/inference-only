"""Reproduce the complete three-step clean traces and two-step influence control."""
import hashlib
import importlib.util
import json
import struct
import sys
from pathlib import Path

if not sys.flags.isolated or not sys.flags.dont_write_bytecode or sys.flags.optimize:
    raise SystemExit('Use Python -I -B without -O.')
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import numpy as np
from build import build, PUBLIC
from transport import Pipeline, bind, check, descriptor, HEADER, tag, IMAGE

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def encode(value):
    return (json.dumps(value,sort_keys=True,indent=2)+'\n').encode()

pins=json.loads((HERE/'PUBLIC-PINS.json').read_bytes())
for name,digest in pins.items():
    check(sha((PUBLIC/name).read_bytes())==digest,'source pin '+name)

def source(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[name]=mod
    spec.loader.exec_module(mod)
    return mod

def model():
    extract=source('release_reconstruct',PUBLIC/'reference/seeded-sampling/reconstruct_rom.py')
    payloads=extract.reconstruct()
    rom=HERE/'build/rom'
    rom.mkdir(exist_ok=True,parents=True)
    for name,raw in payloads.items():
        (rom/name).write_bytes(raw)
    from quantization import oracle
    return oracle,oracle.QuantizedModel.load(rom)

def monitor(instance):
    trace=[]
    # Exact BFP exponent and signed element bytes. Internal residual adds are
    # compared at subsequent consumers and at the layer-return boundary.
    for opname in ('_embedding','_matvec','_rms_norm','_rope','_attention','_silu','_multiply','_layer','_logits'):
        operation=getattr(instance,opname)
        def observe(*args,operation=operation,opname=opname):
            value=operation(*args)
            if isinstance(value,np.ndarray):
                trace.append((opname,0,value.tobytes()))
            else:
                trace.append((opname,int(value.exponent),value.value.tobytes()))
            return value
        setattr(instance,opname,observe)
    return trace

def generate(instance,steps,expected=None):
    trace=monitor(instance)
    token=378
    records=[]
    observations=[]
    for pos in range(steps):
        trace.clear()
        incoming=token
        token,top,logits=instance.forward_token_logits(incoming)
        for layer in range(6):
            for kind,states in [('k',instance.keys),('v',instance.values)]:
                check(len(states[layer])==pos+1,'causal history length')
                for item in states[layer]:
                    trace.append((kind+str(layer),int(item.exponent),item.value.tobytes()))
        values=tuple(trace)
        if expected is not None:
            check(values==expected[pos],f'intermediate/logit/cache mismatch at position {pos}')
        digest=hashlib.sha256()
        for name,exp,data in values:
            digest.update(name.encode()+b'\0'+struct.pack('<iI',exp,len(data))+data)
        records.append(dict(input=incoming,output=token,logit=top,runner_up=int(np.argsort(logits)[-2]),
            all_logits_sha256=sha(logits.tobytes()),all_observations_sha256=digest.hexdigest(),
            observation_count=len(values)))
        observations.append(values)
    return records,observations

def install_native(instance,pipe,q):
    op_index=0
    # position comes from the actual recurrent caller. The code always retires
    # the device-produced dots into the same scale and normalize operation.
    def dots(name,vector,head):
        nonlocal op_index
        tensor=instance.model.tensors[name]
        op=op_index%43
        check((op==42)==head,'matrix/head order')
        op_index+=1
        raw=pipe.apply(tensor.value,vector.value,instance.position,op)
        scaled=raw*tensor.multiplier.astype(np.int64)
        check(np.max(np.abs(raw)) < 1<<34 and np.max(np.abs(scaled)) < 1<<49,'W10/A16 profile')
        exponents=tensor.exponent.astype(np.int16)+vector.exponent-15
        if head:
            return np.ldexp(scaled.astype(np.float64),exponents.astype(np.int32))
        return q._normalize_mixed(scaled,exponents,instance.stats)
    instance._matvec=lambda name,v:dots(name,v,False)
    instance._logits=lambda v:dots('model.embed_tokens.weight',v,True)

def alternate_reference(instance):
    original=instance._logits
    def alternate(hidden):
        logits=original(hidden)
        if instance.position==0:
            tied=instance.model.tensors['model.embed_tokens.weight']
            x=hidden.value.astype(np.int64)
            dot=int(tied.value[0,:128].astype(np.int64)@x[:128])+511*sum(abs(int(a)) for a in x[128:])
            logits[0]=np.ldexp(float(dot*int(tied.multiplier[0])),int(tied.exponent[0])+hidden.exponent-15)
        return logits
    instance._logits=alternate

def arm(q,model,lib,chips,steps,expected,perturb=False,session=1,previous_packet=None,capture=None):
    device=Pipeline(lib,chips,perturb,session,previous_packet)
    try:
        instance=q.IntegerLlama(model)
        install_native(instance,device,q)
        result,_=generate(instance,steps,expected)
        stats=[device.state(i)[0] for i in range(chips)]
        check(sum(x[0] for x in stats)==sum(device.sequences),'RX sequence census')
        if chips==2:
            check(stats[0][1]==device.metrics['raw_rows_checked'],'all row sums externally owned')
            check(stats[1][2]*2==device.metrics['0_to_1_accepted_payload_bytes'],'all peer activations consumed')
            check(len(device.events)==(3 if steps>=2 else 0),'prior-position replay recovery')
            check(len(device.reset_events)==(2 if previous_packet is not None else 0),'reset replay recovery')
            if capture is not None:
                capture.append(device.saved)
            check([s[4] for s in stats]==device.sequences,'RTL sender retirement census')
        else:
            check(stats[0][:3]==(0,0,0) and stats[0][4]==0 and not device.events,'singleton receive idle')
        metrics={key:device.metrics[key] for key in
            ('0_to_1_tx_frames','0_to_1_rx_frames','0_to_1_tx_wire_bytes','0_to_1_rx_wire_bytes',
             '1_to_0_tx_frames','1_to_0_rx_frames','1_to_0_tx_wire_bytes','1_to_0_rx_wire_bytes',
             '0_to_1_accepted_payload_bytes','1_to_0_accepted_payload_bytes')}
        metrics.update(device.metrics)
        return dict(steps=result,metrics=metrics,instances=[dict(rx_sequence=s[0],sum_row_writes=s[1],
            verified_activation_elements=s[2],local_simulated_edges=s[3],tx_retired_frames=s[4]) for s in stats],
            events=device.events,reset_events=device.reset_events,first_head_rows=device.proof,accepted_frame_stream_sha256=device.flow.hexdigest())
    finally:
        device.close()

def singleton_control(lib):
    pipe=Pipeline(lib,1)
    try:
        dev=pipe.devices[0]
        header=np.empty(2,dtype='<u8')
        body=np.zeros(128,dtype=np.uint8)
        queued=lib.publish(dev,0,16,descriptor(0,0,0,0,16),body.ctypes.data,
                           header.ctypes.data,body.ctypes.data,0)
        expected=descriptor(0,0,1,0,16)
        hdr=HEADER.pack(expected,0)
        raw=body.tobytes()
        status,verified=pipe.deliver((0,0,1,0,16),(hdr,raw,tag(1,hdr,raw)),expected)
        counts,_=pipe.state(0)
        check(queued==0 and verified and status==-1 and counts[:3]==(0,0,0) and counts[4]==0,
              'strap must block peer IO even on an explicit request')
        return dict(tx_attempts=1,tx_retired=counts[4],rx_attempts=1,rx_mac_valid=verified,
                    rx_accepted=counts[0],sum_writes=counts[1],activation_writes=counts[2])
    finally:
        pipe.close()

def main():
    check(np.__version__=='1.26.4','Use NumPy 1.26.4')
    lib=bind(build())
    q,data=model()
    capture='benchmarks/fpga-speed/captures/baseline-common-speed-20261026-r1/trial-1'
    trial=json.loads((PUBLIC/(capture+'.json')).read_bytes())
    raw=(PUBLIC/(capture+'.jsonl')).read_bytes()
    check(trial['raw_capture_sha256']==sha(raw) and trial['prompt_tokens']==[378]
          and trial['feedback_dependent'] and trial['clear_before'],'board prefix provenance')
    prefix=trial['generated_tokens'][:3]
    clean,expected=generate(q.IntegerLlama(data),3)
    check([r['output'] for r in clean]==prefix==[200,15,103],'integer oracle vs board')
    tp1=arm(q,data,lib,1,3,expected)
    first_partial=[]
    tp2=arm(q,data,lib,2,3,expected,capture=first_partial)
    restarted=arm(q,data,lib,2,1,expected,session=2,previous_packet=first_partial[0])
    check(restarted['steps']==clean[:1],'reset recovery through final greedy ID')
    check(tp1['steps']==tp2['steps']==clean,'clean end-to-end agreement')
    faulty=q.IntegerLlama(data)
    alternate_reference(faulty)
    ref,changed=generate(faulty,2)
    fault=arm(q,data,lib,2,2,changed,True)
    check(fault['steps']==ref and ref[0]['output']!=prefix[0] and ref[1]['input']==ref[0]['output'],
          'accepted altered contribution must affect feedback')
    filepins={n:sha((HERE/n).read_bytes()) for n in
        ('run.py','build.py','native.cpp','rank.sv','transport.py','PUBLIC-PINS.json')}
    result=dict(model_image_sha256=IMAGE,public_commit='159528e36d46fc803326758b160aa5e84aebd72b',
        source_pins=filepins,board_trial_prefix=prefix,integer_reference=clean,
        tp1=tp1,tp2=tp2,changed_peer_control=fault,restarted_tp2_control=restarted,singleton_strap_control=singleton_control(lib))
    out=encode(result)
    if sys.argv[1:]==['--record']:
        (HERE/'receipt.json').write_bytes(out)
    else:
        check(not sys.argv[1:] and (HERE/'receipt.json').read_bytes()==out,'receipt reproducibility')
    print('PASS',sha(out),'TP1/TP2',prefix,'changed',[x['output'] for x in ref],flush=True)
if __name__=='__main__':
    main()

"""Independent original scalar/SHA/log rules, preserved function bodies."""
import hashlib,json
from common import need

def word(role,head,c,generation):
    return (0x3e00+((head*53+c*17+role*67+generation*29)&511)) | (0x8000 if (head+c+generation)%5==0 else 0)

def page(generation):
    data=bytearray(65536)
    for role in range(2):
        for head in range(8):
            for c in range(128):
                i=(role*8+head)*4096+2*c
                data[i:i+2]=word(role,head,c,generation).to_bytes(2,'little')
    return bytes(data)

def frame(tag,layer,node):
    return bytes([0x21 if node==16 else 0x20])+bytes.fromhex(tag)+(0).to_bytes(8,'little')+bytes([layer,0,0,node,1,0,0])

def roots(tag,layer,generation):
    data=page(generation)
    manifest=b''.join(hashlib.sha256(frame(tag,layer,n)+data[n*4096:(n+1)*4096]).digest() for n in range(16))
    return dict(payload_sha256=hashlib.sha256(data).hexdigest(),manifest_sha256=hashlib.sha256(manifest).hexdigest(),
                root=hashlib.sha256(frame(tag,layer,16)+manifest).hexdigest())

def review8(lines,protected,expected):
    need(lines[-1:]==['PASS operand_integrity_observation protected='+str(int(protected))],'Missing original terminal PASS')
    events=[json.loads(line) for line in lines if line.startswith('{')]
    summaries=[e for e in events if e['event']=='result']
    need([e['scenario'] for e in summaries]==[0,1,2],'Wrong/duplicate 8B cases')
    for scenario,row in enumerate(summaries):
        need(row['protected_build']==protected and row['actual_writes']==36 and row['independent_roots']==(36 if protected else 0),'Incomplete actual writer/root coverage')
        group=[e for e in events if e['scenario']==scenario]
        roots=[e for e in group if e['event']=='root_bytes']
        need([e['layer'] for e in roots]==(list(range(36)) if protected else []),'Wrong root order/count')
        for root in roots:need(bytes(root['bytes']).hex()==expected['model8'][str(root['layer'])]['root'],'Independent full root differs')
        publications=[e for e in group if e['event']=='writer_publication']
        need([e['layer'] for e in publications]==list(range(36)),'Publication order differs')
        results=[e for e in group if e['event']=='layer_result']
        need([e['layer'] for e in results]==(list(range(36)) if scenario==0 else [35]),'Actual consumer layer coverage')
        consumed=[e for e in group if e['event']=='operand_handshake']
        for layer in (range(36) if scenario==0 else [35]):
            operands=[e for e in consumed if e['layer']==layer]
            roles=[e['role'] for e in operands]
            need(roles==([0,1,1] if scenario==0 or not protected else [] if scenario==1 else [0]),'Affected protected operand was used or honest use absent')
            for e in operands:
                need(e['valid'] is True and e['ready'] is True and e['generation']==layer*3,'Wrong actual handshake/source generation')
                role=e['role'];first=e['group']*64 if role else 0;n=64 if role else 128
                values=[word(role,0,c,layer*3) for c in range(first,first+n)]
                if not protected and scenario==role+1 and first==0:values[7]^=1
                need(e['BF16']==values,'Independent consumed BF16 mismatch')
        faults=[e for e in group if e['event']=='fault_edge']
        if protected and scenario:
            need(len(faults)==1 and faults[0]['auth_error'] and faults[0]['layer']==35,'Actual authentication fault absent')
            need(faults[0]['key_valid' if scenario==1 else 'value_valid'] is False,'Affected valid asserted on fault')
        else:need(not faults,'Honest/plain native fault')
        requests=[e for e in group if e['event']=='raw_request']
        for e in requests:
            l=e['layer'];p=8828026880+(l<<27);d=13659865088+(l<<20);a=e['address'];n=e['bytes']
            if protected:need((e['update'] and e['write'] and (a,n) in ((p,65536),(d,512)))
                or (not e['update'] and not e['write'] and (a,n) in ((p,4096),(p+32768,4096),(d,512))),'Typed actual protected request differs')
            else:need(p<=a and a+n<=p+65536,'Actual plain request aliases layer/model')
        need(row['axi_read_bursts']>0 and row['axi_write_bursts']>0 and row['axi_read_words']>0 and row['axi_write_words']>0,'No actual AXI traffic')
    return dict(passed=True,cases=3,ordered_layer_publications_per_case=36,protected=protected)

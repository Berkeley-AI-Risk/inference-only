"""Fixed private link functional model and Verilator ABI. No link rate is assumed."""
import ctypes as C
import hashlib
import hmac
import struct
from collections import Counter
import numpy as np

IMAGE = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
HEADER = struct.Struct('<QQ')
DOMAIN = b'SimpleStories/tp2/single-tape/session-'
KEYS = [hashlib.sha256(b'public laboratory key/'+bytes([d])).digest() for d in range(2)]
def check(condition, message):
    if not condition:
        raise ValueError(message)

def bind(path):
    lib = C.CDLL(str(path))
    void, i, u = C.c_void_p, C.c_int, C.c_uint64
    for name, result, args in [
        ('create_rank',void,[i,i]),('destroy_rank',None,[void]),('load',None,[void,i,i,void]),
        ('publish',i,[void,i,i,u,void,void,void,i]),('dot_tile',None,[void,i,i,i,void,void]),
        ('deliver',i,[void,i,i,i,u,u,u,i,void]),('inspect',None,[void,void,void])]:
        f = getattr(lib,name)
        f.restype, f.argtypes = result,args
    return lib

def tag(direction, header, payload, session=1):
    context = DOMAIN+str(session).encode('ascii')+b'/'+bytes.fromhex(IMAGE)
    return hmac.digest(KEYS[direction],context+bytes([direction])+header+payload,'sha256')

def descriptor(position, matrix, direction, offset, count):
    return (position << 48) | (matrix << 40) | (direction << 32) | (offset << 12) | count

class Pipeline:
    def __init__(self, lib, chips, perturb=False, session=1, previous_packet=None):
        self.lib, self.chips, self.perturb = lib,chips,perturb
        self.devices = [lib.create_rank(chips==2,i) for i in range(chips)]
        self.sequences = [0,0]
        self.events, self.metrics, self.proof = [],Counter(),{}
        self.saved = None
        self.session, self.previous_packet = session,previous_packet
        self.reset_events = []
        self.flow = hashlib.sha256()

    def close(self):
        for device in self.devices:
            self.lib.destroy_rank(device)

    def state(self, rank):
        counters = np.empty(5,dtype=np.uint64)
        result = np.empty(16,dtype='<i8')
        self.lib.inspect(self.devices[rank],counters.ctypes.data,result.ctypes.data)
        return tuple(map(int,counters)),result

    def deliver(self, context, packet, expected):
        pos,op,d,offset,n = context
        hdr,data,mac = packet
        actual,seq = HEADER.unpack(hdr)
        verified = hmac.compare_digest(mac,tag(d,hdr,data,self.session))
        # The bounded decode and signed wire representation are checked before
        # staging the frame. RTL owns transaction freshness and the sum write.
        check(len(data)==n*(8 if d else 2) and len(data)<=128,'payload shape')
        if d:
            v = np.frombuffer(data,dtype='<i8')
            check(np.all(v >= -(1<<34)) and np.all(v < 1<<34),'partial signed35 wire')
        dst = self.devices[0 if d else 1]
        status = self.lib.deliver(dst,d,offset,n,actual,expected,seq,verified,data)
        key = '1_to_0' if d else '0_to_1'
        self.metrics[key+'_rx_frames']+=1
        self.metrics[key+'_rx_wire_bytes']+=len(data)+HEADER.size+len(mac)
        if status==1:
            self.metrics[key+'_accepted_payload_bytes']+=len(data)
            self.flow.update(bytes([d])+hdr+data+mac)
        return status,verified

    def send(self, context, data):
        pos,op,d,offset,n = context
        expected = descriptor(*context)
        header = np.empty(2,dtype='<u8')
        body = np.empty(128,dtype=np.uint8)
        stalled = 3 if (pos,op,d,offset)==(1,0,1,0) else 0
        status = self.lib.publish(self.devices[d],d,n,expected,data if not d else None,
                                  header.ctypes.data,body.ctypes.data,stalled)
        check(status==1,'sender readiness/held frame')
        hdr = header.tobytes()
        check(HEADER.unpack(hdr)==(expected,self.sequences[d]),'retired native header')
        wire = body[:n*(8 if d else 2)].tobytes()
        check(data==wire,'published body vs private partial/activation')
        packet = hdr,wire,tag(d,hdr,wire,self.session)
        key = '1_to_0' if d else '0_to_1'
        self.metrics[key+'_tx_frames']+=1
        self.metrics[key+'_tx_wire_bytes']+=len(wire)+48
        self.metrics['tx_hold_test_edges']+=stalled
        if (pos,op,d,offset)==(0,0,1,0):
            self.saved=packet
            if self.previous_packet is not None:
                old_header,old_payload,old_tag=self.previous_packet
                check(self.session==2 and old_header==hdr and old_payload==wire and old_tag!=packet[2],
                      'require a descriptor/sequence/payload collision across reset')
                check(hmac.compare_digest(old_tag,tag(d,hdr,wire,1)),'original session tag invalid')
                before,old_sum=self.state(0)
                status,verified=self.deliver(context,self.previous_packet,expected)
                after,new_sum=self.state(0)
                check(status==-1 and not verified and before[:3]==after[:3]==(0,0,0)
                      and np.array_equal(old_sum,new_sum),'old-session frame changed arithmetic')
                self.reset_events.append(dict(test='old_session_same_coordinate',old_session=1,current_session=2,
                    direction='1_to_0',position=pos,matrix=op,row=offset,rows=n,sequence=0,
                    same_keys=True,identical_header_and_payload=True,header_hex=hdr.hex(),
                    payload_sha256=hashlib.sha256(wire).hexdigest(),old_tag=old_tag.hex(),
                    current_tag=packet[2].hex(),mac_valid_under_old_session=True,
                    mac_valid_under_current_session=verified,rtl_descriptor_and_sequence_match=True,
                    sum_writes_before=before[1],sum_writes_after=after[1],all_sum_registers_unchanged=True,
                    expected_sequence_after=after[0],rejected_edge=after[3]))
        if (pos,op,d,offset)==(1,0,1,0):
            for label,frame in [('previous_position',self.saved),
                                ('bad_tag',(hdr,data,bytes([packet[2][0]^1])+packet[2][1:]))]:
                before,old = self.state(0)
                status,verified = self.deliver(context,frame,expected)
                after,new = self.state(0)
                check(status==-1 and before[:3]==after[:3] and np.array_equal(old,new),'pre-add rejection')
                check(verified==(label=='previous_position'),'authentication control')
                rx_desc,rx_seq=HEADER.unpack(frame[0])
                self.events.append(dict(test=label,valid_mac=verified,received_position=rx_desc>>48,
                    expected_position=pos,received_sequence=rx_seq,expected_sequence=before[0],
                    sum_writes_before=before[1],sum_writes_after=after[1],all_sum_registers_unchanged=True,
                    rejected_edge=after[3]))
        status,verified = self.deliver(context,packet,expected)
        check(status==1 and verified,'valid frame refused')
        self.sequences[d]+=1
        if (pos,op,d,offset)==(0,0,1,0) and self.previous_packet is not None:
            after,_=self.state(0)
            check(after[:3]==(1,16,0),'honest progress after stale first frame')
            self.reset_events.append(dict(test='current_session_first_partial',accepted_edge=after[3],
                accepted_sequence=0,sum_writes_after=after[1],expected_sequence_after=after[0]))
        if (pos,op,d,offset)==(1,0,1,0):
            counters,_=self.state(0)
            self.events.append(dict(test='honest_successor',accepted_sequence=counters[0]-1,
                sum_writes_after=counters[1],accepted_edge=counters[3]))
        return hdr,packet[2]

    def apply(self, weights, vec, pos, op):
        rows,columns = weights.shape
        check(weights.dtype==np.dtype('<i2') and vec.dtype==np.dtype('<i2'),'W10/A16 storage')
        split = columns if self.chips==1 else columns//2
        for rank,(start,end) in enumerate([(0,split),(split,columns)][:self.chips]):
            for offset in range(0,end-start,64):
                data = vec[start+offset:min(end,start+offset+64)].tobytes()
                n = len(data)//2
                if rank:
                    self.send((pos,op,0,offset,n),data)
                else:
                    self.lib.load(self.devices[0],offset,n,data)
        result=np.empty(rows,dtype='<i8')
        modified=self.perturb and pos==0 and op==42
        for row in range(0,rows,16):
            n=min(16,rows-row)
            parts=[]
            for rank,(start,end) in enumerate([(0,split),(split,columns)][:self.chips]):
                tile=weights[row:row+n,start:end]
                if modified and row==0 and rank==1:
                    tile=tile.copy()
                    tile[0]=np.where(vec[start:end]>=0,511,-511)
                local=np.empty(n,dtype='<i8')
                self.lib.dot_tile(self.devices[rank],n,end-start,tile.strides[0]//2,
                                  tile.ctypes.data,local.ctypes.data)
                self.metrics['rank'+str(rank)+'_macs']+=n*(end-start)
                self.metrics['rank'+str(rank)+'_dot_edges']+=n*((end-start+15)//16)
                parts.append(local)
            if self.chips==2:
                hdr,mac=self.send((pos,op,1,row,n),parts[1].tobytes())
                _,reduced=self.state(0)
                result[row:row+n]=reduced[:n]
                if op==42 and pos==0 and row in (0,192):
                    j=0 if row==0 else 8
                    self.proof[str(row+j)]=dict(local=int(parts[0][j]),peer=int(parts[1][j]),
                        retired_dot=int(result[row+j]),sequence=HEADER.unpack(hdr)[1],frame_tag=mac.hex())
            else:
                result[row:row+n]=parts[0]
        # Independent sum check is an observation only. It does not enter the model result.
        oracle=weights.astype(np.int64) @ vec.astype(np.int64)
        if modified:
            v=vec[split:].astype(np.int64)
            oracle[0]=weights[0,:split].astype(np.int64)@vec[:split].astype(np.int64)+511*np.abs(v).sum()
        check(np.array_equal(result,oracle),'raw dot oracle at position/matrix '+str((pos,op)))
        self.metrics['raw_rows_checked']+=rows
        self.metrics['matrix_calls']+=1
        return result

"""Serial relay for the fixed token protocol and A6 home requests."""
import fcntl,json,os,queue,select,termios,threading,time
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from home_auth import parse_request,GRANT_BYTES

def crc8(data):
    c=0
    for b in data:
        c^=b
        for _ in range(8):c=((c<<1)^7)&255 if c&128 else (c<<1)&255
    return c

class AuthorizedSerial:
    def __init__(self,port,url,expected_root,*,grant_chunk_bytes=0,grant_chunk_pause=0):
        self.url=url;self.expected_root=expected_root;self.events=[]
        if not 0<=grant_chunk_bytes<=1420 or grant_chunk_pause<0:raise ValueError('Invalid grant pacing')
        self.grant_chunk_bytes=grant_chunk_bytes;self.grant_chunk_pause=grant_chunk_pause
        self.write_trace=None
        self.write_lock=threading.Lock()
        self.fd=os.open(port,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
        fcntl.flock(self.fd,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.ioctl(self.fd,termios.TIOCEXCL)
        a=termios.tcgetattr(self.fd);a[0]=a[1]=a[3]=0;a[2]=termios.CS8|termios.CREAD|termios.CLOCAL
        a[4]=a[5]=termios.B115200;a[6][termios.VMIN]=a[6][termios.VTIME]=0
        termios.tcsetattr(self.fd,termios.TCSANOW,a)
    def close(self):
        fcntl.ioctl(self.fd,termios.TIOCNXCL);os.close(self.fd)
    def read(self,n,deadline):
        b=b''
        while len(b)<n:
            left=deadline-time.monotonic()
            if left<=0:raise TimeoutError('Incomplete serial frame')
            if select.select([self.fd],[],[],left)[0]:
                try:b+=os.read(self.fd,n-len(b))
                except BlockingIOError:pass
        return b
    def write(self,b):
        with self.write_lock:
            deadline=time.monotonic()+3
            while b:
                if time.monotonic()>deadline:raise TimeoutError('Serial write timeout')
                if select.select([],[self.fd],[],0.1)[1]:
                    try:n=os.write(self.fd,b)
                    except BlockingIOError:continue
                    if self.write_trace is not None:self.write_trace.append({'requested':len(b),'returned':n,'time':time.monotonic()})
                    b=b[n:]
    def write_grant(self,grant):
        if len(grant)!=GRANT_BYTES:raise ValueError('Invalid grant length')
        if not self.grant_chunk_bytes:
            self.write(grant);return None
        started=time.monotonic()
        for offset in range(0,len(grant),self.grant_chunk_bytes):
            self.write(grant[offset:offset+self.grant_chunk_bytes])
            if offset+self.grant_chunk_bytes<len(grant):time.sleep(self.grant_chunk_pause)
        return {'chunk_bytes':self.grant_chunk_bytes,'pause_seconds':self.grant_chunk_pause,
                'write_seconds':time.monotonic()-started}
    def next(self,timeout=10):
        deadline=time.monotonic()+timeout;magic=self.read(1,deadline)
        if magic==b'\xa6':
            request=self.read(128,deadline);fields=parse_request(request)
            if fields['model_root']!=self.expected_root:raise ValueError('Unexpected admitted model')
            event={'event':'home-request','request_hex':request.hex(),'time':time.monotonic(),**fields}
            try:
                req=Request(self.url,data=request,headers={'Content-Type':'application/octet-stream'})
                with urlopen(req,timeout=2)as reply:grant=reply.read(GRANT_BYTES+1)
                if len(grant)!=GRANT_BYTES or grant[:128]!=request:raise ValueError('Mismatched grant')
                pacing=self.write_grant(grant)
                if pacing is not None:event['grant_pacing']=pacing
                event['decision']='approved';event['grant_hex']=grant.hex()
            except HTTPError as e:
                if e.code!=403:raise
                e.close()
                event['decision']='denied'
            self.events.append(event);return event
        if magic==b'\x5a':
            frame=magic+self.read(4,deadline)
            if frame[4]!=crc8(frame[:4]) or frame[3]&0xf0:raise ValueError('Invalid token reply')
            event={'event':'token-reply','frame_hex':frame.hex(),'status':frame[1],
                   'token':int.from_bytes(frame[2:4],'little'),'time':time.monotonic()}
            self.events.append(event);return event
        raise ValueError('Unexpected serial frame prefix '+magic.hex())
    def command(self,op,token=0,expected=0):
        if op not in [0,1,2] or not 0<=token<4019 or (op!=0 and token):raise ValueError('Invalid token command')
        payload=bytes([0xa5,op,token&255,token>>8]);self.write(payload+bytes([crc8(payload)]))
        deadline=time.monotonic()+10
        while True:
            event=self.next(max(0.001,deadline-time.monotonic()))
            if event['event']=='token-reply':
                if event['status']!=0x80+op or event['token']!=expected:raise ValueError('Unexpected command result')
                return event

class BackgroundAuthorization:
    """Keep servicing home requests while the controlling thread loads the FPGA.

    This object owns all reads until close(). Commands are never retried; token
    replies and home events go to separate queues so neither can consume the
    other's evidence. It is a test relay, not a serial multiplexing protocol.
    """
    def __init__(self,client):
        self.client=client;self.homes=queue.Queue();self.replies=queue.Queue()
        self.stopping=threading.Event();self.failure=None
        self.thread=threading.Thread(target=self._run,daemon=True);self.thread.start()
    def _run(self):
        try:
            while not self.stopping.is_set():
                if not select.select([self.client.fd],[],[],0.1)[0]:continue
                event=self.client.next(10)
                (self.homes if event['event']=='home-request' else self.replies).put(event)
        except Exception as exc:
            self.failure=exc;self.stopping.set()
    def _take(self,events,timeout):
        deadline=time.monotonic()+timeout
        while True:
            if self.failure is not None:raise RuntimeError('Serial relay failed') from self.failure
            left=deadline-time.monotonic()
            if left<=0:raise TimeoutError('No matching serial event')
            try:return events.get(timeout=min(left,.1))
            except queue.Empty:pass
    def next_home(self,timeout=10):return self._take(self.homes,timeout)
    def command(self,op,token=0,expected=0):
        if op not in [0,1,2] or not 0<=token<4019 or (op!=0 and token):raise ValueError('Invalid token command')
        payload=bytes([0xa5,op,token&255,token>>8]);self.client.write(payload+bytes([crc8(payload)]))
        event=self._take(self.replies,10)
        if event['status']!=0x80+op or event['token']!=expected:raise ValueError('Unexpected command result')
        return event
    def expect_quiet(self,timeout):
        deadline=time.monotonic()+timeout
        while True:
            if self.failure is not None:raise RuntimeError('Serial relay failed') from self.failure
            if not self.replies.empty() or not self.homes.empty():raise RuntimeError('Unexpected serial output')
            left=deadline-time.monotonic()
            if left<=0:return
            time.sleep(min(left,.05))
    def close(self):
        self.stopping.set();self.thread.join(20)
        if self.thread.is_alive():raise RuntimeError('Serial reader did not stop')
        self.client.close()

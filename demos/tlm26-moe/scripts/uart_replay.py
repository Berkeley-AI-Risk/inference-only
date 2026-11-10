"""Provision a pre-loaded candidate over UART and replay its fixed test cases."""
import argparse, contextlib, fcntl, hashlib, json, os, select, stat, termios, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def record(p,d):p.write_text(json.dumps(d,indent=2)+'\n')
def crc(b):
    c=0
    for n in b:
        c^=n
        for _ in range(8):c=((c<<1)^(7 if c&128 else 0))&255
    return c
def frame(magic,k,t):
    data=bytes([magic,k,t&255,t>>8]);return data+bytes([crc(data)])
def request_frame(op,t):return frame(0xa5,{'append':0,'step':1,'clear':2}[op],t)
def response_frame(k,t):return frame(0x5a,k,t)
def claim_exclusive_uart(fd,port):
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.ioctl(fd,termios.TIOCEXCL)
def release_exclusive_uart(fd):fcntl.ioctl(fd,termios.TIOCNXCL)
def configure_uart(fd):
    a=termios.tcgetattr(fd);a[0]=a[1]=a[3]=0;a[2]=termios.CREAD|termios.CLOCAL|termios.CS8
    a[4]=a[5]=termios.B115200;a[6][termios.VMIN]=a[6][termios.VTIME]=0
    termios.tcsetattr(fd,termios.TCSANOW,a);termios.tcflush(fd,termios.TCIOFLUSH)
@contextlib.contextmanager
def uart(port):
    fd=os.open(port,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
    try:
        if not stat.S_ISCHR(os.fstat(fd).st_mode):raise RuntimeError('not a serial device')
        claim_exclusive_uart(fd,port);configure_uart(fd)
        yield fd
    finally:
        release_exclusive_uart(fd);os.close(fd)

def read_bytes(fd,n,timeout):
    data=bytearray();end=time.monotonic()+timeout
    while len(data)<n:
        remaining=end-time.monotonic()
        if remaining<=0 or not select.select([fd],[],[],remaining)[0]:raise TimeoutError(f'wanted {n} UART bytes, found {bytes(data).hex()}')
        chunk=os.read(fd,n-len(data))
        if not chunk:raise RuntimeError('UART closed')
        data+=chunk
    return bytes(data)

def write_bytes(fd,b):
    v=memoryview(b)
    while v:
        if not select.select([],[fd],[],5)[1]:raise TimeoutError('UART stalled')
        v=v[os.write(fd,v):]

def provision(fd,model,out,phase):
    t=time.monotonic()
    write_bytes(fd,b'TLM1')
    if read_bytes(fd,1,12)!=b'B':raise RuntimeError('loader handshake failed')
    for off in range(0,len(model),4096):
        write_bytes(fd,model[off:off+4096])
        if read_bytes(fd,1,6)!=b'y':raise RuntimeError(f'loader ACK page {off//4096}')
        if (off//4096+1)%64==0:print(phase,'uploaded',off//4096+1,'pages',flush=True)
    record(out/(phase+'-load.json'),{'acknowledged_pages':768,'bytes':len(model),'sha256':hashlib.sha256(model).hexdigest(),'elapsed_s':time.monotonic()-t})
    time.sleep(.02)

def run_interactions(fd,phase,out):
    gold=json.loads((ROOT/'receipts/integer-cpu.json').read_bytes())['results']
    rows=[]
    def save():record(out/(phase+'-uart.json'),rows)
    def transact(op,t,kind,val):
        begin=time.monotonic_ns();tx=request_frame(op,t);write_bytes(fd,tx);rx=read_bytes(fd,5,10)
        us=(time.monotonic_ns()-begin)//1000
        rows.append({'tx':tx.hex(),'rx':rx.hex(),'roundtrip_us':us});save()
        if rx!=response_frame(kind,val):raise RuntimeError(f'{op}({t}) reply {rx.hex()}, expected {kind:02x} with token {val}')
    for history in gold if phase=='honest' else gold[:1]:
        transact('clear',0,0x82,0)
        for t in history['prompt_ids']:transact('append',t,0x80,0)
        if phase=='corrupt':transact('step',0,0xc1,0);return
        for t in history['generated_ids']:transact('step',0,0x81,t)
    # The model's first real DDR response is retained for 20 ms. CLEAR's
    # reply is gated on the page engine draining that real response.
    transact('clear',0,0x82,0)
    tx=request_frame('step',0);cancel=request_frame('clear',0)
    # One OS write keeps the two five-byte frames adjacent on the physical wire.
    # A host-side tcdrain can block longer than an entire inference on macOS.
    begin=time.monotonic_ns()
    sent=os.write(fd,tx+cancel)
    if sent!=10:raise RuntimeError('paired probe was not accepted in a single write')
    queued=time.monotonic_ns()
    rx=read_bytes(fd,5,2);us=(time.monotonic_ns()-begin)//1000
    rows.append({'cancelled_tx':tx.hex(),'tx':cancel.hex(),'rx':rx.hex(),'single_write_bytes':sent,'enqueue_us':(queued-begin)//1000,'roundtrip_us':us});save()
    if rx!=response_frame(0x82,0) or us<19000:raise RuntimeError('outstanding CLEAR timing witness absent')
    if select.select([fd],[],[],.080)[0]:raise RuntimeError('stale output after CLEAR')
    transact('append',1,0x80,0);transact('step',0,0x81,403);transact('clear',0,0x82,0)

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--uart',required=True);ap.add_argument('--case',choices=['honest','corrupt'],required=True);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    a.out.mkdir(exist_ok=False);model=bytearray((ROOT/'build/model.bin').read_bytes())
    if hashlib.sha256(model).hexdigest()!='221d412a48f1809d6b9cc46ab9f8d572c37af226d07ec710c82bd0d530b49ce1':raise ValueError('wrong model')
    if a.case=='corrupt':model[23*4096]^=1
    with uart(a.uart) as fd:provision(fd,model,a.out,a.case);run_interactions(fd,a.case,a.out)
if __name__=='__main__':main()

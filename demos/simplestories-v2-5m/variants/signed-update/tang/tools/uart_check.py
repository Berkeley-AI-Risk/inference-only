#!/usr/bin/env python3
"""Exercise only CLEAR/APPEND/STEP on a SWIC already running in SRAM.

No programming, mode selection, raw memory access, fourth opcode or update
operation is provided. Token expectations come from the matching signed model.
"""
from pathlib import Path
import argparse,datetime,fcntl,json,os,select,stat,termios,time

def crc8(data):
    crc=0
    for b in data:
        crc^=b
        for _ in range(8):crc=((crc<<1)^7)&255 if crc&128 else (crc<<1)&255
    return crc

def transact(fd,opcode,token,timeout):
    payload=bytes([0xa5,opcode,token&255,token>>8]);request=payload+bytes([crc8(payload)])
    if os.write(fd,request)!=5:raise IOError('short UART write')
    reply=b'';deadline=time.monotonic()+timeout
    while len(reply)<5:
        remaining=deadline-time.monotonic()
        if remaining<=0:raise TimeoutError('UART response not completed; no automatic retry')
        if not select.select([fd],[],[],remaining)[0]:continue
        try:chunk=os.read(fd,5-len(reply))
        except BlockingIOError:continue
        if not chunk:raise EOFError('UART closed')
        reply+=chunk
    if reply[0]!=0x5a or reply[4]!=crc8(reply[:4]) or reply[3]&0xf0:raise ValueError('Invalid response frame')
    value=reply[2]|reply[3]<<8
    if reply[1]!=0x80+opcode:raise ValueError(f'Rejected command: {reply.hex()}')
    if opcode!=1 and value!=0:raise ValueError('Nonzero command acknowledgement payload')
    return {'opcode':opcode,'input_token':token,'output_token':value,'request_hex':request.hex(),'response_hex':reply.hex()}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device',required=True);p.add_argument('--prompt',default='1')
    p.add_argument('--expected',required=True,help='Comma-separated exact greedy output token IDs')
    p.add_argument('--output',required=True,type=Path);p.add_argument('--timeout-seconds',default=60,type=float)
    a=p.parse_args();prompt=[int(x) for x in a.prompt.split(',')];expected=[int(x) for x in a.expected.split(',')]
    if not prompt or not expected or any(not 0<=x<4019 for x in prompt+expected):raise ValueError('Invalid token IDs')
    if a.output.exists():raise FileExistsError('Preserve existing evidence')
    fd=os.open(a.device,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK);rows=[]
    try:
        if not stat.S_ISCHR(os.fstat(fd).st_mode):raise ValueError('Device is not a character device')
        fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.ioctl(fd,termios.TIOCEXCL)
        attr=termios.tcgetattr(fd);attr[0]=attr[1]=attr[3]=0;attr[2]=termios.CS8|termios.CREAD|termios.CLOCAL
        attr[4]=attr[5]=termios.B115200;attr[6][termios.VMIN]=attr[6][termios.VTIME]=0
        termios.tcsetattr(fd,termios.TCSANOW,attr);termios.tcflush(fd,termios.TCIOFLUSH)
        rows.append(transact(fd,2,0,a.timeout_seconds))
        for token in prompt:rows.append(transact(fd,0,token,a.timeout_seconds))
        for token in expected:
            r=transact(fd,1,0,a.timeout_seconds);rows.append(r)
            if r['output_token']!=token:raise ValueError(f'Expected {token}, received {r["output_token"]}')
        rows.append(transact(fd,2,0,a.timeout_seconds))
        result={'result':'PASS','device':a.device,'prompt':prompt,'expected':expected,'transactions':rows,'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
        a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
    except BaseException as exc:
        a.output.with_suffix(a.output.suffix+'.partial').write_text(json.dumps({'result':'INCOMPLETE','error':str(exc),'transactions':rows},indent=2)+'\n');raise
    finally:
        try:fcntl.ioctl(fd,termios.TIOCNXCL)
        finally:os.close(fd)

if __name__=='__main__':main()

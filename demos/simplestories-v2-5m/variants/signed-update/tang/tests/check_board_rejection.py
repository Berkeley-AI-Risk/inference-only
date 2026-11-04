#!/usr/bin/env python3
"""Check the frozen UART rejects APPEND/STEP after a deliberate bad boot.

Use only for the documented invalid-signature physical fixture, after loading
the same experimental inference image used by positive qualification.
"""
from pathlib import Path
import argparse,datetime,fcntl,json,os,stat,sys,termios
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
import uart_check as uart
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--device',required=True);p.add_argument('--output',required=True,type=Path)
a=p.parse_args()
if a.output.exists() or a.output.with_suffix(a.output.suffix+'.partial').exists():raise FileExistsError('preserve existing evidence')
rows=[];fd=os.open(a.device,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
try:
    if not stat.S_ISCHR(os.fstat(fd).st_mode):raise ValueError('not a character device')
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.ioctl(fd,termios.TIOCEXCL)
    attr=termios.tcgetattr(fd);attr[0]=attr[1]=attr[3]=0;attr[2]=termios.CS8|termios.CREAD|termios.CLOCAL
    attr[4]=attr[5]=termios.B115200;attr[6][termios.VMIN]=attr[6][termios.VTIME]=0
    termios.tcsetattr(fd,termios.TCSANOW,attr);termios.tcflush(fd,termios.TCIOFLUSH)
    rows.append(uart.transact(fd,2,0,10))
    for op,token in [(0,1),(1,0)]:
        try:
            uart.transact(fd,op,token,10)
        except ValueError as exc:
            if not str(exc).startswith('Rejected command: '):raise
            reply=bytes.fromhex(str(exc).split(': ',1)[1])
            if reply[1]!=0xc0+op or reply[2:4]!=b'\0\0':raise ValueError('wrong rejection response')
            rows.append({'opcode':op,'input_token':token,'rejected':True,'response_hex':reply.hex()})
        else:raise AssertionError('bad boot admitted a model operation')
    result={'result':'PASS','scope':'invalid boot: CLEAR acknowledged; valid APPEND and STEP explicitly rejected; no generation',
            'transactions':rows,'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
except BaseException as exc:
    a.output.with_suffix(a.output.suffix+'.partial').write_text(json.dumps({'result':'INCOMPLETE','error':str(exc),'transactions':rows},indent=2)+'\n');raise
finally:
    try:fcntl.ioctl(fd,termios.TIOCNXCL)
    finally:os.close(fd)

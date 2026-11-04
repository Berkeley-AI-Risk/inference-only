#!/usr/bin/env python3
"""Collect two common-protocol S-AWIC trials without programming hardware.

Only CLEAR, APPEND(378), and 128 feedback-dependent STEP operations are used.
The caller clock is sampled immediately after a validated transaction returns.
Raw observations are buffered in memory and saved outside the measured loop.
"""
from pathlib import Path
import argparse,datetime,fcntl,hashlib,json,os,platform,select,stat,subprocess,sys,termios,time
import uart_check as uart

ROOT=Path(__file__).resolve().parents[1]
BOUNDARY='generation_loop_validated_reply'
sha=lambda b:hashlib.sha256(b).hexdigest()
def save(path,data):
    with path.open('x') as f:json.dump(data,f,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())

def transaction(fd,op,token,expected):
    result=uart.transact(fd,op,token,60)
    if result['output_token']!=expected:raise ValueError('Output differs from independent reference')
    return result

def measured_trial(fd,expected,clock=time.monotonic_ns):
    events=[]
    def do(op,token,value,label):
        start=clock();result=transaction(fd,op,token,value);returned=clock()
        events.append(dict(result,operation=label,request_monotonic_ns=start,validated_return_monotonic_ns=returned))
        return result,returned,(returned-start)/1e9
    try:
        do(2,0,0,'clear-before');do(0,378,0,'prompt')
        tokens=[];arrivals=[];durations=[];origin=clock()
        for index,wanted in enumerate(expected):
            start=clock()
            result=transaction(fd,1,0,wanted)
            returned=clock()
            duration=(returned-start)/1e9
            events.append(dict(result,operation='output-'+str(index+1),request_monotonic_ns=start,validated_return_monotonic_ns=returned))
            tokens.append(result['output_token']);arrivals.append(returned);durations.append(duration)
        do(2,0,0,'clear-after')
        time.sleep(0.1)
        if select.select([fd],[],[],0)[0]:raise ValueError('Unexpected bytes after final acknowledgement')
        return {'prompt_tokens':[378],'generated_tokens':tokens,'expected_tokens':expected,
                'reply_monotonic_ns':arrivals,'trial_started_monotonic_ns':origin,
                'reply_elapsed_seconds':[(n-origin)/1e9 for n in arrivals],
                'step_seconds':durations,'cached_command_seconds':durations[1:],
                'first_step_seconds':durations[0],'decoding':'greedy','temperature':0,
                'clear_before':True,'final_clear_acknowledged':True,'stop_at_eos':False,
                'feedback_dependent':True,'observer_writes_during_trial':False},events
    except BaseException as error:
        error.raw_events=events
        raise

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['reference','bitstream','load-record','flash-readback','flash-record','board-result','output']:
        p.add_argument('--'+name,required=True,type=Path)
    p.add_argument('--device',required=True);a=p.parse_args()
    reference=json.loads(a.reference.read_text());expected=reference['generated_tokens']
    assert reference['prompt_tokens']==[378] and len(expected)==128 and reference['decoding']=='greedy'
    load=json.loads(a.load_record.read_text());flash_record=json.loads(a.flash_record.read_text())
    board=json.loads(a.board_result.read_text());bitstream_sha=sha(a.bitstream.read_bytes())
    assert load['exit_code']==0 and load['command'][load['command'].index('--operation_index')+1]=='2'
    loaded_file=Path(load['command'][load['command'].index('--fsFile')+1])
    assert sha(loaded_file.read_bytes())==bitstream_sha==board['bitstream_sha256']
    assert board['result']=='PASS'
    flash=a.flash_readback.read_bytes();assert len(flash)==16777216 and sha(flash)==flash_record['sha256']
    assert flash_record['status']=='PASS' and flash_record['expected_array_equal']
    read_end=datetime.datetime.fromisoformat(flash_record['started_utc'])+datetime.timedelta(seconds=flash_record['elapsed_seconds'])
    assert datetime.datetime.fromisoformat(load['started_utc'])>=read_end
    image=flash[0x801000:0x801000+7265984];slot=flash[0xf00000:0xf40000]
    assert sha(image)==reference['image_sha256']
    sys.path.insert(0,str(ROOT/'reference'))
    import signed_update as su
    import tang_image as tang
    signers=int.from_bytes(slot[128:132],'big');assert signers in [2,3]
    frame_bytes=132+signers*(4+su.SIG_BYTES)+su.PAYLOAD_BYTES
    info=tang.validate_tang(slot[:frame_bytes]+image,[su.DemoAuthority(i).public_key for i in range(3)])
    assert slot[frame_bytes:]==b'\xff'*(len(slot)-frame_bytes)
    pins={name:sha(path.read_bytes()) for name,path in {
        'collector':Path(__file__),'uart_check':ROOT/'tools/uart_check.py','reference':a.reference,
        'load_record':a.load_record,'flash_record':a.flash_record,'bitstream':a.bitstream,
        'board_result':a.board_result}.items()}
    a.output.mkdir(parents=True,exist_ok=False)
    ports=[a.device,a.device.replace('/cu.','/tty.'),a.device[:-1]+'0',a.device.replace('/cu.','/tty.')[:-1]+'0']
    owners=subprocess.run(['/usr/sbin/lsof','-nP',*sorted(set(ports))],capture_output=True,text=True)
    programmers=subprocess.run(['/usr/bin/pgrep','-i','-f','(^|/)(programmer_cli|openFPGALoader|GowinProgrammer)( |$)'],capture_output=True,text=True)
    assert owners.returncode==programmers.returncode==1 and not owners.stdout and not programmers.stdout
    save(a.output/'ownership.json',{'uart_has_owner':False,'programmer_running':False})
    identity={'model':'SimpleStories-V2-5M','variant':'S-AWIC','clock_hz':25000000,
              'fpga_image_sha256':bitstream_sha,'model_image_sha256':sha(image),
              'admission_slot_sha256':sha(slot),'signed_manifest_version':info['version'],
              'host_platform':platform.platform(),'python_version':sys.version,
              'collector_sha256':pins['collector'],'uart_client_sha256':pins['uart_check'],
              'reference_sha256':pins['reference'],'board_result_sha256':pins['board_result'],
              'baud_rate':115200,'clock':'time.monotonic_ns','timestamp_boundary':BOUNDARY}
    save(a.output/'load-provenance.json',{'bitstream_sha256':bitstream_sha,'sram_load_exit_code':0,
         'sram_load_completed_utc':load['completed_utc'],'original_load_record_sha256':pins['load_record'],
         'original_full_flash_record_sha256':pins['flash_record'],'full_flash_readback_preceded_sram_load':True,
         'signed_base_model_verified':True,'configuration_independently_attested':False})
    save(a.output/'PLAN.json',{'identity':identity,'input_sha256':pins,'automatic_retry':False,
         'flash_modified':False,'fpga_programmed':False,'concurrent_fpga_workload':False,
         'protocol':'greedy-one-token-128-host-v1','repetitions':2,'outputs_per_trial':128})
    descriptor=os.open(a.device,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK);cases=[]
    try:
        assert stat.S_ISCHR(os.fstat(descriptor).st_mode)
        fcntl.flock(descriptor,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.ioctl(descriptor,termios.TIOCEXCL)
        attr=termios.tcgetattr(descriptor);attr[0]=attr[1]=attr[3]=0;attr[2]=termios.CS8|termios.CREAD|termios.CLOCAL
        attr[4]=attr[5]=termios.B115200;attr[6][termios.VMIN]=attr[6][termios.VTIME]=0
        termios.tcsetattr(descriptor,termios.TCSANOW,attr);termios.tcflush(descriptor,termios.TCIOFLUSH)
        for i in range(1,3):
            case,events=measured_trial(descriptor,expected)
            raw_path=a.output/('trial-'+str(i)+'-raw.json')
            save(raw_path,{'timestamp_boundary':BOUNDARY,'events':events})
            case.update(name='one-token-128-trial'+str(i),raw_capture=raw_path.name,
                        raw_capture_sha256=sha(raw_path.read_bytes()))
            save(a.output/('trial-'+str(i)+'.json'),case);cases.append(case)
            print(json.dumps({'trial':i,'outputs':128,'cached_host_seconds':case['reply_elapsed_seconds'][-1]-case['reply_elapsed_seconds'][0]}),flush=True)
        assert sha(Path(__file__).read_bytes())==pins['collector']
        assert sha((ROOT/'tools/uart_check.py').read_bytes())==pins['uart_check']
        wall=sum(c['reply_elapsed_seconds'][-1]-c['reply_elapsed_seconds'][0] for c in cases)
        result={'schema':'fpga-common-speed-capture-v1','protocol':'greedy-one-token-128-host-v1',
                'passed':True,'timestamp_boundary':BOUNDARY,'identity':identity,'cases':cases,
                'counted_cached_outputs':254,'cached_host_seconds':wall,'cached_tokens_per_second':254/wall,
                'command_only_diagnostic_tokens_per_second':254/sum(sum(c['cached_command_seconds']) for c in cases),
                'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'flash_modified':False,
                'fpga_programmed':False,'automatic_retry':False,'final_clear_acknowledged':True}
        save(a.output/'FINISHED.json',result)
        print(json.dumps({'passed':True,'cached_tokens_per_second':result['cached_tokens_per_second']}),flush=True)
    except BaseException as error:
        save(a.output/'FAILED.json',{'error':str(error),'completed_trials':len(cases),'raw_events':getattr(error,'raw_events',[]),'automatic_retry':False})
        raise
    finally:
        try:fcntl.ioctl(descriptor,termios.TIOCNXCL)
        finally:os.close(descriptor)

if __name__=='__main__':main()

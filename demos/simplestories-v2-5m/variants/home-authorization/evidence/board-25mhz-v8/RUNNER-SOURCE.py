#!/usr/bin/env python3
"""SRAM-only physical renewal/revocation test; restores baseline in finally."""
import argparse,datetime,fcntl,hashlib,json,os,select,subprocess,sys,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT.parent
sys.path.insert(0,str(ROOT/'reference'))
from home_auth import policy_for
from home_server import make_server
from serial_client import AuthorizedSerial,BackgroundAuthorization,crc8
from usb_debugger import reset_known_debugger
sys.path.insert(0,str(Path(__file__).resolve().parent))
import common_speed
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
p.add_argument('--location',default='131153')
p.add_argument('--benchmark-reference',type=Path)
p.add_argument('--common-benchmark-reference',type=Path)
p.add_argument('--idle-renewal-before-commands',action='store_true',help='Observe one accepted lease renewal without sending any application command first')
p.add_argument('--startup-configurations',type=int,default=1,help='With 2..8, verify tokens after each volatile configuration before the full campaign; these are not electrical power cycles')
p.add_argument('--grant-chunk-bytes',type=int,default=0)
p.add_argument('--grant-chunk-pause',type=float,default=0)
p.add_argument('--open-serial-after-load',action='store_true',help='Initialize UART after each programmer invocation instead of before it')
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
assert 1<=a.startup_configurations<=8
assert not (a.benchmark_reference and a.common_benchmark_reference)
(out/'STARTED.json').write_text(json.dumps({'pid':os.getpid(),'python':sys.version,
    'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
(out/'RUNNER-SOURCE.py').write_bytes(Path(__file__).read_bytes())
(out/'HOST-SOURCES.json').write_text(json.dumps({name:hashlib.sha256((ROOT/'reference'/name).read_bytes()).hexdigest()
    for name in ['serial_client.py','home_auth.py','home_server.py','usb_debugger.py']},indent=2)+'\n')
build=json.loads((a.build/'RESULT.json').read_text());assert build['exit_code']==0
image=Path(build['directory'])/'project/impl/pnr/home_product.fs'
review=json.loads((a.build/'REVIEW.json').read_text())
assert review['result']=='COMPILED_SOURCE_BOUND'
qualification_path=a.build/'SIMULATION-QUALIFICATION.json'
qualification=json.loads(qualification_path.read_text())
assert qualification['result']=='PASS'
assert qualification['native_inputs_sha256']==hashlib.sha256((a.build/'INPUTS.json').read_bytes()).hexdigest()
assert len(qualification['checks'])==4
timing=json.loads((a.build/'TIMING-REVIEW.json').read_text())
assert timing['bitstream_sha256']==review['sha256']
assert timing['functional_board_test_allowed'] is True,'Timing review does not allow this board test'
assert review['wrapper_routes_physical_nonce'] and not review['physical_source_simulation_mode']
assert image.resolve()==Path(review['bitstream']).resolve()
assert image.stat().st_size==review['bytes']
assert hashlib.sha256(image.read_bytes()).hexdigest()==review['sha256']
inputs=json.loads((a.build/'INPUTS.json').read_text())
for name,sha in inputs.items():
    assert hashlib.sha256((Path(build['directory'])/name).read_bytes()).hexdigest()==sha,name
restore=Path('RELEASE_ROOT/demos/simplestories-v2-5m/variants/signed-update/tang/prebuilt/swic_product.fs')
assert hashlib.sha256(restore.read_bytes()).hexdigest()=='4545bd0b0c4076eaea8358d547b19ff0176952417daa0e0f07d1c346aee5fee2'
programmer=Path('LOCAL_REPOSITORY/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/programmer_cli')
assert hashlib.sha256(programmer.read_bytes()).hexdigest()=='41a967c1d18ec73b420801d52bf83ad40b92ca032683231d55a5ef158d523cfb'
port='/dev/cu.usbserial-20250303171'
lock=open('/tmp/inference-only-tang-mega-2025030317.lock','a+');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
if subprocess.run(['/usr/sbin/lsof',port,'/dev/cu.usbserial-20250303170'],capture_output=True,text=True).stdout.strip():raise RuntimeError('Board serial port owned')
check=WORK/'simplestories-swic-tang-20261103/tools/uart_check.py'
def run(cmd,name):
    with (out/(name+'.log')).open('xb')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
    text=(out/(name+'.log')).read_text(errors='replace')
    (out/(name+'.command.json')).write_text(json.dumps({'command':cmd,'exit_code':r.returncode,'time':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
    if r.returncode or 'ERROR' in text.upper():raise RuntimeError(name+' failed')
    return text
def load(fs,name):
    if 'Finished' not in run([str(programmer),'--device','GW5AST-138C','--cable-index','4','--location',a.location,'--frequency','0.9MHz',
                              '--operation_index','2','--fsFile',str(fs)],name):raise RuntimeError('Incomplete SRAM load')
run([sys.executable,str(check),'--device',port,'--expected','108,32','--output',str(out/'baseline-before.json')],'baseline-before')
identity=run([str(programmer),'--device','GW5AST-138C','--cable-index','4','--location',a.location,'--frequency','0.9MHz',
              '--operation_index','0'],'identity')
if '0001081B' not in identity.upper():raise RuntimeError('Unexpected FPGA identity')
root=(WORK/'swic-tang-private-recovery-20261103/base.swic').read_bytes()[72:104]
policy=out/'policy.json';policy.write_text(json.dumps(policy_for([root]))+'\n')
server=make_server(policy,out/'signer-state.json');thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
client=None;relay=None;changed=False;passed=False
class RecordedEvents(list):
    """Persist each observation before a later error can discard the trace."""
    def __init__(self):
        super().__init__();self.lock=threading.Lock();self.buffered=False;self.pending=[]
    def append(self,event):
        with self.lock:
            super().append(event)
            if self.buffered:self.pending.append(event)
            else:
                with (out/'EVENTS.jsonl').open('a') as log:log.write(json.dumps(event)+'\n')
    def flush(self):
        with self.lock:
            with (out/'EVENTS.jsonl').open('a') as log:
                for event in self.pending:log.write(json.dumps(event)+'\n')
            self.pending=[];self.buffered=False
GRANT_SETTLE_SECONDS=.5
def next_home_after(cutoff,timeout=15):
    deadline=time.monotonic()+timeout
    while True:
        event=relay.next_home(max(.001,deadline-time.monotonic()))
        if event['time']>cutoff:return event
        if time.monotonic()>=deadline:raise TimeoutError('No fresh home request after checkpoint')
last_window_nonce=None;window_start=0
def wait_command_window():
    # The native test image renews every five seconds. Keep whole token frames
    # outside its UART handover interval; never retry ambiguous commands.
    global last_window_nonce,window_start
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        if relay.failure:raise RuntimeError('Serial reader failed')from relay.failure
        events=[e for e in client.events if e['event']=='home-request']
        if events:
            latest=events[-1]
            if latest['decision']!='approved':raise RuntimeError('No approved command window')
            if latest['nonce']!=last_window_nonce:
                last_window_nonce=latest['nonce'];window_start=time.monotonic()+GRANT_SETTLE_SECONDS
            now=time.monotonic()
            if window_start<=now<latest['time']+4.5:return
        time.sleep(.005)
    raise TimeoutError('No command window before next renewal')
(out/'RECOVERY.json').write_text(json.dumps({'restore':str(restore),'candidate':str(image),
 'candidate_sha256':hashlib.sha256(image.read_bytes()).hexdigest(),'model_root':root.hex(),
 'review_sha256':hashlib.sha256((a.build/'REVIEW.json').read_bytes()).hexdigest(),
 'simulation_qualification_sha256':hashlib.sha256(qualification_path.read_bytes()).hexdigest(),
 'timing_review_sha256':hashlib.sha256((a.build/'TIMING-REVIEW.json').read_bytes()).hexdigest(),
 'location':a.location,'flash_write':False},indent=2)+'\n')
phase='initial approval'
def open_relay(events=None):
    global client,relay
    client=AuthorizedSerial(port,f'http://127.0.0.1:{server.server_port}/authorize',root.hex(),
                            grant_chunk_bytes=a.grant_chunk_bytes,grant_chunk_pause=a.grant_chunk_pause)
    client.events=events if events is not None else RecordedEvents()
    relay=BackgroundAuthorization(client)
try:
    if not a.open_serial_after_load:open_relay()
    changed=True;load(image,'load-home-variant')
    if a.open_serial_after_load:open_relay()
    first=relay.next_home(90)
    assert first['event']=='home-request' and first['decision']=='approved'
    current_boot=first
    if a.startup_configurations>1:
        startups=[]
        for configuration in range(a.startup_configurations):
            if configuration:
                phase='startup reconfiguration '+str(configuration+1)
                started=time.monotonic();load(image,'startup-reload-'+str(configuration+1))
                current_boot=next_home_after(started,90)
                assert current_boot['decision']=='approved'
            assert current_boot['nonce']not in {s['nonce']for s in startups}
            time.sleep(GRANT_SETTLE_SECONDS)
            checkpoint=time.monotonic()
            for op,token,expected in [(2,0,0),(0,1,0),(1,0,108),(1,0,32),(2,0,0)]:
                wait_command_window();relay.command(op,token,expected=expected)
            startups.append({'configuration':configuration+1,'nonce':current_boot['nonce'],
                'tokens':[108,32],'first_command_after':checkpoint,'completed':time.monotonic()})
            (out/'STARTUP-CONFIGURATIONS.json').write_text(json.dumps({'result':'PASS'if len(startups)==a.startup_configurations else'IN_PROGRESS',
                'requested':a.startup_configurations,'configurations':startups,'electrical_power_cycles':False},indent=2)+'\n')
    if a.idle_renewal_before_commands:
        phase='idle renewal before any application command'
        # A separate configuration keeps this check free of startup-test commands.
        if a.startup_configurations>1:
            started=time.monotonic();load(image,'reload-before-idle-renewal')
            current_boot=next_home_after(started,90)
            assert current_boot['decision']=='approved'
        idle=next_home_after(current_boot['time'])
        assert idle['decision']=='approved' and idle['nonce']!=current_boot['nonce']
        (out/'IDLE-RENEWAL.json').write_text(json.dumps({'result':'PASS','first_nonce':current_boot['nonce'],
            'renewal_nonce':idle['nonce'],'application_commands_since_configuration':0},indent=2)+'\n')
    time.sleep(GRANT_SETTLE_SECONDS)
    phase='initial CLEAR';relay.command(2)
    phase='initial APPEND';relay.command(0,1)
    phase='initial STEP';first_token=relay.command(1,expected=108)
    phase='renewal between context-preservation tokens'
    second=next_home_after(first_token['time'])
    assert second['event']=='home-request' and second['decision']=='approved' and first['nonce']!=second['nonce']
    time.sleep(GRANT_SETTLE_SECONDS)
    relay.command(1,expected=32);relay.command(2)
    if a.benchmark_reference:
        reference=json.loads(a.benchmark_reference.read_text())
        expected=reference['tokens']
        assert reference['result']=='PASS'and reference['prompt']==[1]and len(expected)==128
        wait_command_window();relay.command(2)
        wait_command_window();relay.command(0,1)
        timing=[];tokens=[];benchmark_start=None
        for index,token in enumerate(expected):
            wait_command_window()
            if benchmark_start is None:benchmark_start=time.perf_counter()
            sent=time.perf_counter()-benchmark_start
            event=relay.command(1,expected=token);tokens.append(event['token'])
            timing.append({'index':index,'command_start':sent,'response_end':time.perf_counter()-benchmark_start})
        elapsed=time.perf_counter()-benchmark_start
        (out/'BENCHMARK.json').write_text(json.dumps({'result':'PASS','prompt':[1],'outputs':128,'sampling':'greedy',
            'wall_seconds':elapsed,'tokens_per_second':128/elapsed,'tokens':tokens,'timings':timing,
            'reference_sha256':hashlib.sha256(a.benchmark_reference.read_bytes()).hexdigest(),
            'timing_scope':reference['timing_scope'],
            'host_scheduling':'Wait before commands during renewal handover; settle 0.5s after observing a sent grant, avoid final 0.5s of the five-second interval.'},indent=2)+'\n')
        wait_command_window();relay.command(2)
    if a.common_benchmark_reference:
        phase='common paired speed benchmark'
        reference=json.loads(a.common_benchmark_reference.read_text())
        assert reference['prompt_tokens']==[378] and reference['decoding']=='greedy'
        expected=reference['generated_tokens'];assert len(expected)==128
        model_package=(WORK/'swic-tang-private-recovery-20261103/base.swic').read_bytes()
        assert hashlib.sha256(model_package[-7265984:]).hexdigest()==reference['image_sha256']
        (out/'COMMON-COLLECTOR.py').write_bytes(Path(common_speed.__file__).read_bytes())
        (out/'common-reference.json').write_bytes(a.common_benchmark_reference.read_bytes())
        cases=[]
        for trial in [1,2]:
            client.events.buffered=True
            try:case,events=common_speed.collect_trial(relay,wait_command_window,expected)
            except BaseException as exc:
                (out/'COMMON-FAILED.json').write_text(json.dumps({'trial':trial,'error':str(exc),
                    'raw_events':getattr(exc,'raw_events',[]),'automatic_retry':False},indent=2)+'\n')
                raise
            finally:client.events.flush()
            raw_name='common-trial-'+str(trial)+'-raw.json'
            (out/raw_name).write_text(json.dumps({'timestamp_boundary':common_speed.BOUNDARY,'events':events},indent=2)+'\n')
            case.update(name='one-token-128-trial'+str(trial),raw_capture=raw_name,
                        raw_capture_sha256=hashlib.sha256((out/raw_name).read_bytes()).hexdigest())
            cases.append(case)
        elapsed=sum(c['reply_elapsed_seconds'][-1]-c['reply_elapsed_seconds'][0] for c in cases)
        (out/'COMMON-SPEED.json').write_text(json.dumps({'schema':'fpga-common-speed-capture-v1',
            'protocol':'greedy-one-token-128-host-v1','passed':True,'timestamp_boundary':common_speed.BOUNDARY,
            'identity':{'model':'SimpleStories-V2-5M','variant':'S-AWIC with renewable home authorization',
                'clock_hz':review['nominal_core_hz'],'fpga_image_sha256':review['sha256'],
                'model_image_sha256':reference['image_sha256'],'model_root':root.hex(),
                'collector_sha256':hashlib.sha256(Path(common_speed.__file__).read_bytes()).hexdigest(),
                'reference_sha256':hashlib.sha256(a.common_benchmark_reference.read_bytes()).hexdigest(),
                'clock':'time.monotonic_ns','timestamp_boundary':common_speed.BOUNDARY},
            'cases':cases,'counted_cached_outputs':254,'cached_host_seconds':elapsed,
            'cached_tokens_per_second':254/elapsed,'automatic_retry':False,
            'flash_modified':False,'renewal_gaps_included':True,
            'home_authorization':{'lease_seconds':10,'renewal_interval_seconds':5,
                'response_deadline_seconds':4,'grant_settle_seconds':GRANT_SETTLE_SECONDS,
                'grant_chunk_bytes':a.grant_chunk_bytes,'grant_chunk_pause_seconds':a.grant_chunk_pause,
                'serial_initialized_after_programming':a.open_serial_after_load,
                'command_end_guard_seconds':0.5}},indent=2)+'\n')
    new=out/'policy-next.json';new.write_text(json.dumps(policy_for([]))+'\n');os.replace(new,policy)
    revoked_at=time.monotonic()
    # A request can be read just before the policy replacement and receive its
    # denial just afterward. Keep that denial. Drain older approvals, but fail
    # if a genuinely later request is approved under the withdrawn policy.
    denial_deadline=time.monotonic()+15
    while True:
        third=relay.next_home(max(.001,denial_deadline-time.monotonic()))
        if third['decision']=='denied':break
        if third['time']>revoked_at:raise AssertionError('Request approved after policy withdrawal')
        if time.monotonic()>=denial_deadline:raise TimeoutError('No denial after policy withdrawal')
    assert third['event']=='home-request' and third['decision']=='denied' and len({first['nonce'],second['nonce'],third['nonce']})==3
    time.sleep(10.5)
    payload=bytes([0xa5,1,0,0]);client.write(payload+bytes([crc8(payload)]))
    relay.expect_quiet(1)
    # A fresh FPGA configuration must issue a different challenge. Keep the
    # model withdrawn, then try the old, valid signed grant against that boot.
    # This tests reconfiguration/reset freshness, not electrical power cycling.
    reboot_started=time.monotonic()
    if a.open_serial_after_load:
        saved_events=client.events
        relay.close();relay=None;client=None
    load(image,'reload-home-denied')
    if a.open_serial_after_load:open_relay(saved_events)
    reboot=next_home_after(reboot_started,90)
    assert reboot['decision']=='denied'
    assert reboot['nonce'] not in {e['nonce'] for e in client.events
        if e['event']=='home-request' and e is not reboot}
    replay_pacing=client.write_grant(bytes.fromhex(first['grant_hex']))
    client.events.append({'event':'old-grant-replay','time':time.monotonic(),
                          'old_nonce':first['nonce'],'fresh_nonce':reboot['nonce'],
                          'grant_pacing':replay_pacing})
    time.sleep(GRANT_SETTLE_SECONDS)
    for op,token in [(2,0),(0,1),(1,0)]:
        payload=bytes([0xa5,op,token&255,token>>8]);client.write(payload+bytes([crc8(payload)]))
    relay.expect_quiet(1)
    passed=True
finally:
    # sys.exc_info works on Python 3.8 and later. Keep even failure
    # logging inside the protected cleanup so it cannot bypass restoration.
    failure=sys.exc_info()[1]
    try:
        try:
            if failure is not None:
                (out/'FAILURE.json').write_text(json.dumps({'result':'FAIL','type':type(failure).__name__,
                    'message':str(failure),'phase':phase},indent=2)+'\n')
        finally:
            try:
                if client:
                    try:
                        if relay:
                            try:relay.close()
                            except Exception:
                                # This relay raises before closing its client
                                # if the reader fails to stop. Close it here.
                                client.close()
                                raise
                        else:client.close()
                    finally:
                        (out/'TRANSCRIPT.json').write_text(json.dumps(client.events,indent=2)+'\n')
            finally:
                try:server.shutdown()
                finally:
                    try:server.server_close()
                    finally:thread.join(timeout=2)
    finally:
        if changed:
            load(restore,'restore-sawic')
            usb_reset=reset_known_debugger()
            (out/'usb-reset-after-restore.json').write_text(json.dumps(usb_reset,indent=2)+'\n')
            time.sleep(45)
            run([sys.executable,str(check),'--device',port,'--expected','108,32','--output',str(out/'baseline-after.json')],'baseline-after')
            (out/'RESTORED.json').write_text(json.dumps({'result':'PASS','flash_write':False})+'\n')
home_events=[event for event in client.events if event['event']=='home-request']
result={'result':'PASS' if passed else 'FAIL','tokens':[108,32],
        'reconfiguration_fresh_nonce':passed,'old_grant_replay_blocked':passed,
        'approved_turns':sum(e['decision']=='approved'for e in home_events),
        'denied_turns':sum(e['decision']=='denied'for e in home_events),
        'fresh_nonces':len({e['nonce']for e in home_events}),
        'startup_configurations_checked':a.startup_configurations if a.startup_configurations>1 else 0,
        'model_root':root.hex(),'physical_entropy_qualification':False,'flash_write':False}
(out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

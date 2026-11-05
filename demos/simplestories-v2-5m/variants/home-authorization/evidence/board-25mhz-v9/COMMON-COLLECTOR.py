"""Common paired benchmark measurement; no file writes in measured trials."""
import time

BOUNDARY='generation_loop_validated_reply'


def crc(data):
    c=0
    for b in data:
        c^=b
        for _ in range(8):c=((c<<1)^7)&255 if c&128 else (c<<1)&255
    return c


def collect_trial(relay,wait_window,expected,prompt=378,clock=time.monotonic_ns):
    assert len(expected)==128 and prompt==378
    events=[]
    def command(op,token,wanted,label):
        wait_window()
        start=clock();event=relay.command(op,token,expected=wanted);returned=clock()
        if event['token']!=wanted:raise ValueError('Output differs from independent reference')
        payload=bytes([0xa5,op,token&255,token>>8]);request=payload+bytes([crc(payload)])
        events.append({'operation':label,'opcode':op,'input_token':token,'output_token':event['token'],
                       'request_hex':request.hex(),'response_hex':event['frame_hex'],
                       'request_monotonic_ns':start,'validated_return_monotonic_ns':returned})
        return returned,(returned-start)/1e9
    try:
        command(2,0,0,'clear-before');command(0,prompt,0,'prompt')
        origin=clock();arrivals=[];durations=[];generated=[]
        for index,token in enumerate(expected):
            returned,duration=command(1,0,token,'output-'+str(index+1))
            arrivals.append(returned);durations.append(duration)
            generated.append(events[-1]['output_token'])
        command(2,0,0,'clear-after')
    except BaseException as exc:
        exc.raw_events=events
        raise
    return {'prompt_tokens':[prompt],'generated_tokens':generated,'expected_tokens':list(expected),
            'reply_monotonic_ns':arrivals,'trial_started_monotonic_ns':origin,
            'reply_elapsed_seconds':[(x-origin)/1e9 for x in arrivals],
            'step_seconds':durations,'cached_command_seconds':durations[1:],
            'first_step_seconds':durations[0],'decoding':'greedy','temperature':0,
            'clear_before':True,'final_clear_acknowledged':True,'stop_at_eos':False,
            'feedback_dependent':True,'observer_writes_during_trial':False},events

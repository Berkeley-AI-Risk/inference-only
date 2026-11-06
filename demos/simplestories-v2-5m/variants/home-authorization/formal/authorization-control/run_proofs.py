#!/usr/bin/env python3
"""Pinned, bounded-resource authorization proofs; each attempt is immutable."""
import argparse, datetime, hashlib, json, os, shutil, subprocess, time
from pathlib import Path
if not __debug__:raise SystemExit('Run without Python -O; audit assertions must remain enabled.')

HERE=Path(__file__).resolve().parent
PROJECT=Path(os.environ.get('AUTHORIZATION_PROJECT',str(HERE.parents[1]/'hardware/project')))
COMMIT='c7ea55dba49bb64bd99a601421bb42cb9e6e8347'
FILES=['home/home_boot_gate.sv','home/home_product_top.sv','top.sv','uart_core.sv',
       'shared_token_probe.sv','arbiter.sv','swic/swic_boot_admission.sv',
       'swic/swic_boot_ingress.sv','swic/su_lms_verify.sv',
       'fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv',
       'fpga/token_only_model0_mac_uart0/rtl/fixed_uart_tx.sv',
       'fpga/token_only_model0_mac_uart0/rtl/fixed_uart_rx.sv']
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('job',choices=['pin','controller','core','publication','verifier']);p.add_argument('--name');p.add_argument('--maxsteps',type=int,default=6);p.add_argument('--mutant',choices=['header-check','model-binding','permit-register']);a=p.parse_args()
    pin=HERE/'SOURCE-PINS.json'
    if a.job=='pin':
        assert not pin.exists()
        pin.write_text(json.dumps({'public_commit':COMMIT,'files':{f:sha(PROJECT/f) for f in FILES}},indent=2)+'\n')
        print(pin);return
    pins=json.loads(pin.read_text())
    for f,h in pins['files'].items(): assert sha(PROJECT/f)==h, f+' source changed'
    out=HERE/'runs'/(a.name or datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    out.mkdir(parents=True,exist_ok=False)
    src=(PROJECT/'home/home_boot_gate.sv').read_text()
    pos=src.index('\nendmodule')
    properties=HERE/(a.job+'_properties.sv')
    prop=properties.read_text()
    extra=''
    extraction={}
    if a.job=='core':
        top=(PROJECT/'top.sv').read_text()
        block=top[top.index('    logic home_mode_q'):top.index('    home_boot_gate #')]
        probe=(PROJECT/'shared_token_probe.sv').read_text()
        runtime=probe[probe.index('    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;'):probe.index('\n\n    // The existing typed endpoint')]
        prop=prop.replace('    // INSERT_ACTUAL_CORE_BLOCK',block).replace('    // INSERT_ACTUAL_RUNTIME_RESET',runtime)
        arb=(PROJECT/'arbiter.sv').read_text().split('\nendmodule')[0]
        # Exclude pre-existing unrelated owner/count assertions; keep every RTL
        # statement of the arbiter unchanged. Only the authorization gates are claimed.
        arb=arb[:arb.index('\n`ifdef FORMAL\n')]+ '\nendmodule\n'
        extra=arb
        extraction={'top_core_block_sha256':hashlib.sha256(block.encode()).hexdigest(),'runtime_reset_block_sha256':hashlib.sha256(runtime.encode()).hexdigest(),'arbiter_exclusion':'existing FORMAL assertion block only; first module retained; request/response data and valid logic unchanged'}
    if a.job=='publication':
        u=PROJECT/'fpga/token_only_model0_mac_uart0/rtl'
        src=(u/'token_only_model0_uart_bridge.sv').read_text();pos=src.index('\nendmodule')
        extra='\n'+(u/'fixed_uart_tx.sv').read_text()+'\n'+(u/'fixed_uart_rx.sv').read_text()
    if a.job=='verifier':
        src=(PROJECT/'swic/su_lms_verify.sv').read_text();pos=src.index('\nendmodule')
    design=src[:pos]+'\n'+prop+src[pos:]+extra
    if a.mutant:
        old,new={'header-check':('(index_q<128 && grant_byte_i!=selected_message_byte)',"1'b0"),
                 'model-binding':('(!admitted_root_valid_i || !root_equal)','(!admitted_root_valid_i)'),
                 'permit-register':('wire token_reset_n=~token_reset_asserted;',"wire token_reset_n=1'b1;")}[a.mutant]
        assert design.count(old)==1
        design=design.replace(old,new)
        extraction['negative_control']={'name':a.mutant,'replace':old,'with':new}
    if extraction:(out/'EXTRACTIONS.json').write_text(json.dumps(extraction,indent=2)+'\n')
    (out/'design.sv').write_text(design)
    ys='''read_verilog -formal -D SYNTHESIS -sv design.sv
chparam -set USE_SHARED_VERIFIER 1 -set RESPONSE_LIMIT_CYCLES 100000000 -set LEASE_CYCLES 250000000 -set RENEW_LEAD_CYCLES 125000000 -set DEVICE_ID 128'h395c83e440d5252bfa59f6138e5ed3b8 -set GEOMETRY 256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078 home_boot_gate
prep -top home_boot_gate -flatten
delete home_boot_gate/shared_signature_byte_o
async2sync
memory_map
opt -full
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps MAXSTEPS -set clk 1 -set-at 1 reset_n 0 -set-def-inputs -show-ports -show-regs -show state_q -show age_q -show lease_age_q -show index_q SPECSHOW -dump_vcd failure.vcd
'''
    ys=ys.replace('SPECSHOW','-show spec_received -show spec_frame -show spec_started -show spec_permitted' if a.job=='controller' else '')
    if a.job=='publication':
        ys='''read_verilog -formal -D SYNTHESIS -sv design.sv
chparam -set CLKS_PER_BIT 217 token_only_model0_uart_bridge
prep -top token_only_model0_uart_bridge -flatten
async2sync
opt -full
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps MAXSTEPS -set clk 1 -set-at 1 rst_n 0 -set-def-inputs -show-ports -dump_vcd failure.vcd
'''
    if a.job=='verifier':
        ys='''read_verilog -formal -D SYNTHESIS -sv design.sv
chparam -set USE_SHARED_HASH 1 -set MAX_MESSAGE_BYTES 128 su_lms_verify
prep -top su_lms_verify -flatten
delete su_lms_verify/shared_hash_byte_o su_lms_verify/signature_address_o su_lms_verify/message_address_o
async2sync
memory_map
opt -full
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps MAXSTEPS -set clk 1 -set-at 1 reset_n 0 -set-def-inputs -show-ports -show state_q -show after_hash_q -show spec_started -dump_vcd failure.vcd
'''
    ys=ys.replace('MAXSTEPS',str(a.maxsteps))
    (out/'prove.ys').write_text(ys)
    (out/'STARTED.json').write_text(json.dumps({'job':a.job,'source_pins_sha256':sha(pin),'runner_sha256':sha(Path(__file__)),'properties_sha256':sha(properties),'rss_watchdog_limit_bytes':8*1024**3,'rss_watchdog_interval_seconds':1,'pid':os.getpid()},indent=2)+'\n')
    peak=0; memory_stopped=False
    with (out/'console.log').open('w') as log:
        proc=subprocess.Popen([shutil.which('yosys'),'-Q','-T','-l','proof.log','prove.ys'],cwd=out,stdout=log,stderr=subprocess.STDOUT)
        while proc.poll() is None:
            rss=subprocess.run(['/bin/ps','-o','rss=','-p',str(proc.pid)],capture_output=True,text=True).stdout.strip()
            peak=max(peak,int(rss or 0)*1024)
            if peak>8*1024**3:
                memory_stopped=True;proc.terminate();break
            time.sleep(1)
        returncode=proc.wait()
    log=(out/'console.log').read_text()
    ok=returncode==0 and 'Induction step proven: SUCCESS!' in log
    result={'result':'PASS' if ok else 'NOT_PROVEN','exit_code':returncode,'job':a.job,'negative_control':a.mutant,'peak_sampled_rss_bytes':peak,'memory_stopped':memory_stopped,
            'proof_log_sha256':sha(out/'proof.log'),'design_sha256':sha(out/'design.sv'),
            'source_pins_sha256':sha(pin),'scope':{'controller':'Selected controller transcript, binding, reset/start, provenance, expiry and publication runway; arbitrary binary verifier verdicts; signature RAM output cone removed.',
                     'core':'Selected controller plus exact top-level permit/mux and runtime reset excerpts; actual backend arbiter, arbitrary numerical-client requests/responses. Reset/permission suppression and runtime admission. Physical hierarchy correspondence needs separate wiring audit.',
                     'publication':'Actual UART bridge, RX and TX at 217 cycles/bit: result acceptance and first response-byte admission require publication permission; pause suppresses offers; quiet implies transmitter ready. No bound on complete frame drain.',
                     'verifier':'Actual LMS controller with arbitrary private hash results/bytes: a valid verdict requires a start since reset; selected key and message length are latched on that start. Unused address and outgoing hash-byte cones removed; no LMS/SHA algorithm claim.'}[a.job]+' Two-state clocked async2sync model. No LMS/SHA correctness, entropy, analog timing or unconditional whole-chip security claim.'}
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(0 if ok else 1)
if __name__=='__main__': main()

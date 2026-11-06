#!/usr/bin/env python3
"""Deadline/renewal/composition proofs on pinned production authorization RTL."""
import argparse,json,re
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
from run_memory_proof import monitored
UART=PROJECT/'fpga/token_only_model0_mac_uart0/rtl'
def inject(src,properties):
    i=src.index('\nendmodule');return src[:i]+'\n'+properties+src[i:]
def uart_design(properties,observe=False):
    src=(UART/'token_only_model0_uart_bridge.sv').read_text()
    original='.serial_o(uart_tx_o)';assert src.count(original)==1
    src=src.replace(original,original+', .proof_remaining_o(proof_tx_remaining)')
    src=src.replace('    wire rx_valid;','    wire [11:0] proof_tx_remaining;\n    wire rx_valid;')
    if observe:
        original='input  wire [11:0] out_token_i';assert src.count(original)==1
        src=src.replace(original,original+',\n    output wire proof_flight_o,proof_first_o,proof_quiet_o,\n    output wire [13:0] proof_elapsed_o,proof_rank_o')
        properties+='\n assign proof_flight_o=spec_flight; assign proof_first_o=spec_first; assign proof_quiet_o=uart_quiet_o;\n assign proof_elapsed_o=spec_elapsed; assign proof_rank_o=spec_rank;\n'
    src=inject(src,properties)
    tx=(UART/'fixed_uart_tx.sv').read_text()
    original='output wire       serial_o';assert tx.count(original)==1
    tx=tx.replace(original,original+',\n    output wire [11:0] proof_remaining_o')
    tx=inject(tx,(HERE/'tx_deadline_properties.sv').read_text())
    return src+'\n'+tx+'\n'+(UART/'fixed_uart_rx.sv').read_text()
def home_design(job):
    src=(PROJECT/'home/home_boot_gate.sv').read_text()
    props=(HERE/'controller_properties.sv').read_text()+'\n'+(HERE/'renewal_properties.sv').read_text()
    extra=''
    if job=='composition':
        core=(HERE/'core_properties.sv').read_text()
        top=(PROJECT/'top.sv').read_text();probe=(PROJECT/'shared_token_probe.sv').read_text()
        block=top[top.index('    logic home_mode_q'):top.index('    home_boot_gate #')]
        runtime=probe[probe.index('    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;'):probe.index('\n\n    // The existing typed endpoint')]
        core=core.replace('    // INSERT_ACTUAL_CORE_BLOCK',block).replace('    // INSERT_ACTUAL_RUNTIME_RESET',runtime)
        old='(* anyseq *) wire home_transport_fault, token_uart_quiet, home_uart_tx, token_uart_tx;'
        assert core.count(old)==1
        core=core.replace(old,'(* anyseq *) wire home_transport_fault, home_uart_tx;\n    wire token_uart_quiet,token_uart_tx;')
        props+='\n'+core+'\n'+(HERE/'composition_properties.sv').read_text()
        extra=(PROJECT/'arbiter.sv').read_text().split('\nendmodule')[0].split('\n`ifdef FORMAL\n')[0]+'\nendmodule\n'
        extra+='\n'+uart_design((HERE/'uart_deadline_properties.sv').read_text()+'\n'+(HERE/'publication_properties.sv').read_text(),observe=True)
    design=inject(src,props)+extra
    if job=='composition':design=design.replace('(* anyseq *)','(* anyseq, keep *)')
    return design
def main():
    p=argparse.ArgumentParser();p.add_argument('job',choices=['uart-deadline','renewal','composition']);p.add_argument('--name',required=True);p.add_argument('--maxsteps',default=8,type=int);p.add_argument('--mutant',choices=['stall-transmitter','short-guard','pause-midframe']);a=p.parse_args()
    pins=json.loads((HERE/'SOURCE-PINS.json').read_text())
    for f,h in pins['files'].items():assert sha(PROJECT/f)==h,f
    out=HERE/'runs'/a.name;out.mkdir(exist_ok=False)
    design=uart_design((HERE/'uart_deadline_properties.sv').read_text()) if a.job=='uart-deadline' else home_design(a.job)
    if a.mutant=='stall-transmitter':
        begin=design.index('module fixed_uart_tx');end=design.index('\nendmodule',begin)
        tx=design[begin:end];old="counter_q <= counter_q - 1'b1;";assert tx.count(old)==1
        design=design[:begin]+tx.replace(old,'counter_q <= counter_q;')+design[end:]
    elif a.mutant=='short-guard':
        old="lease_age_q<LW'(LEASE_CYCLES-20001)";assert design.count(old)==1
        design=design.replace(old,"lease_age_q<LW'(LEASE_CYCLES-10001)")
    elif a.mutant=='pause-midframe':
        old='else if(home_request_valid && token_uart_quiet) home_mode_q<=1;';assert design.count(old)==1
        design=design.replace(old,'else if(home_request_valid) home_mode_q<=1;')
    top='token_only_model0_uart_bridge' if a.job=='uart-deadline' else 'home_boot_gate'
    config=f'chparam -set CLKS_PER_BIT 217 {top}' if a.job=='uart-deadline' else "chparam -set USE_SHARED_VERIFIER 1 -set RESPONSE_LIMIT_CYCLES 100000000 -set LEASE_CYCLES 250000000 -set RENEW_LEAD_CYCLES 125000000 -set DEVICE_ID 128'h395c83e440d5252bfa59f6138e5ed3b8 -set GEOMETRY 256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078 home_boot_gate"
    cut='' if a.job=='uart-deadline' else 'delete home_boot_gate/shared_signature_byte_o'
    reset='rst_n' if a.job=='uart-deadline' else 'reset_n'
    show='-show state_q -show response_index_q -show spec_flight -show spec_rank -show spec_elapsed -show proof_tx_remaining' if a.job=='uart-deadline' else '-show state_q -show lease_age_q -show age_q -show spec_consumed -show spec_had_grant'
    if a.job=='composition':show+=' -show home_mode_q -show token_reset_n -show token_uart_quiet -show proof_uart_flight -show proof_uart_first -show proof_uart_elapsed -show proof_uart_rank -show publication_allowed_o -show lease_cycles_remaining_o -show u_actual_token_uart.state_q -show u_actual_token_uart.response_index_q'
    # SAT's -set-def-inputs covers module ports, not internal anyseq seams.
    # Explicitly keep every abstract client/transport input in the binary model.
    binary=[]
    for m in re.finditer(r'\(\*\s*anyseq(?:,\s*keep)?\s*\*\)\s*(?:wire|logic)\s*(?:\[[^]]+\])?\s*([^;]+);',design):
        binary.extend(n.strip() for n in m[1].split(','))
    assert all(re.fullmatch(r'\w+',n) for n in binary)
    defined=' '.join('-set-def '+n for n in binary)
    (out/'design.sv').write_text(design)
    ys=f'''read_verilog -formal -D SYNTHESIS -sv design.sv
{config}
prep -top {top} -flatten
{cut}
async2sync
opt -full
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps {a.maxsteps} -set clk 1 -set-at 1 {reset} 0 -set-def-inputs {defined} -show-ports {show} -dump_vcd failure.vcd
'''
    (out/'prove.ys').write_text(ys)
    (out/'STARTED.json').write_text(json.dumps({'job':a.job,'runner_sha256':sha(Path(__file__)),'source_pins_sha256':sha(HERE/'SOURCE-PINS.json'),'properties_sha256':sha(HERE/'uart_deadline_properties.sv'),'tx_properties_sha256':sha(HERE/'tx_deadline_properties.sv'),'binary_private_seams':binary,'rss_process_tree_watchdog_bytes':8*1024**3},indent=2)+'\n')
    r=monitored(['yosys','-Q','-T','-l','proof.log','prove.ys'],out,'console')
    ok=r['exit_code']==0 and 'Induction step proven: SUCCESS!' in (out/'proof.log').read_text()
    result={'result':'PASS' if ok else 'NOT_PROVEN','job':a.job,'negative_control':a.mutant,'process':r,'design_sha256':sha(out/'design.sv'),'proof_log_sha256':sha(out/'proof.log'),'scope':{'uart-deadline':'Actual UART bridge/TX/RX at 217 clocks/bit, observation-only remaining-cycle port: complete frame reaches quiet within 10855 clocks absent reset/pause.', 'renewal':'Actual production controller/timers: each challenge can grant only once; a subsequent grant uses a different nonce; renewal initiation preserves the decrementing old deadline; failure cannot be renewed away.', 'composition':'Joined actual home controller, top-level permit/mux, runtime reset/backend arbiter and UART bridge/TX/RX. Response admission is model-bound and authorized, an in-flight packet retains enough permission budget and cannot be interrupted by nonterminal home transport; revoked/expired permission suppresses runtime requests and token output. Crypto verdicts/private boot/nonce seams remain abstract.'}[a.job]+' Binary clocked async2sync model; not a whole-machine numerical or physical security theorem.'}
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(0 if ok else 1)
if __name__=='__main__':main()

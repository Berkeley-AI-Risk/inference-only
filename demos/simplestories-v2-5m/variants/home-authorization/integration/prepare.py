#!/usr/bin/env python3
"""Apply source-bound home authorization overlay to our frozen Tang copy."""
from pathlib import Path
import hashlib,json,sys,shutil,subprocess

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import home_auth as h
p=ROOT/'integration/project'
baseline=json.loads((ROOT/'integration/BASELINE.json').read_text())
def edit(name, changes):
    path=p/name
    before=path.read_text()
    expected=baseline['files']['project/'+name]
    assert hashlib.sha256(before.encode()).hexdigest()==expected,name
    value=before
    for old,new in changes:
        assert value.count(old)==1,(name,old,value.count(old))
        value=value.replace(old,new)
    path.write_text(value)

edit('swic/swic_boot_admission.sv',[
 ('output wire [255:0] expected_image_sha_o,','output wire [255:0] expected_image_sha_o,\n    output wire [255:0] model_commitment_o,'),
 ('assign expected_image_sha_o=sealed_o ? image_sha_q : 256\'d0;',
  'assign expected_image_sha_o=sealed_o ? image_sha_q : 256\'d0;\n    assign model_commitment_o=sealed_o ? signed_root_q : 256\'d0;')])
edit('swic/swic_boot_ingress.sv',[
 ('output wire [255:0] image_sha_o,','output wire [255:0] image_sha_o,\n    output wire [255:0] model_commitment_o,'),
 ('.expected_image_sha_o(image_sha_o),','.expected_image_sha_o(image_sha_o),.model_commitment_o(model_commitment_o),')])

bridge='fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv'
edit(bridge,[
 ('input  wire        rst_n,','input  wire        rst_n,\n    input wire transport_pause_i, publication_allowed_i,\n    output wire uart_quiet_o,'),
 ('.clk(clk), .rst_n(rst_n), .serial_i(uart_rx_i),','.clk(clk), .rst_n(rst_n && !transport_pause_i), .serial_i(uart_rx_i),'),
 ('.clk(clk), .rst_n(rst_n), .byte_valid_i(tx_valid),','.clk(clk), .rst_n(rst_n && !transport_pause_i), .byte_valid_i(tx_valid),'),
 ('assign cmd_valid_o = (state_q == BRIDGE_OFFER) ||\n                         (state_q == BRIDGE_WAIT_RESULT && clear_pending_q);',
  'assign cmd_valid_o = !transport_pause_i && ((state_q == BRIDGE_OFFER) ||\n                         (state_q == BRIDGE_WAIT_RESULT && clear_pending_q));'),
 ('assign out_ready_o = (state_q == BRIDGE_WAIT_RESULT);',
  'assign out_ready_o = !transport_pause_i && publication_allowed_i && (state_q == BRIDGE_WAIT_RESULT);'),
 ('assign tx_valid = (state_q == BRIDGE_SEND);',
  'assign tx_valid = !transport_pause_i && (state_q == BRIDGE_SEND) && (response_index_q!=0 || publication_allowed_i);\n    assign uart_quiet_o = tx_ready && state_q!=BRIDGE_DRAIN &&\n        (state_q!=BRIDGE_SEND || (response_index_q==0 && !publication_allowed_i));'),
 ('end else begin\n            if ((state_q == BRIDGE_IDLE ||',
  'end else if (!transport_pause_i) begin\n            if ((state_q == BRIDGE_IDLE ||'),
 ('end else if (out_valid_i) begin\n                        prepare_response',
  'end else if (out_valid_i && publication_allowed_i) begin\n                        prepare_response'),
 ('if (tx_ready) begin\n                        if (response_index_q == 3\'d4)',
  'if (tx_ready && tx_valid) begin\n                        if (response_index_q == 3\'d4)'),
 ('else clear_command_q <= clear_command_next;',
  'else if (transport_pause_i) clear_command_q <= 1\'b0;\n        else clear_command_q <= clear_command_next;'),
 ('assign clear_command_o = clear_command_q;',
  'assign clear_command_o = clear_command_q && !transport_pause_i;')])

edit('uart_core.sv',[
 ('input wire core_clk_i,app_clk_i,reset_n_i,uart_rx_i,',
  'input wire core_clk_i,app_clk_i,reset_n_i,uart_rx_i,\n    input wire private_transport_pause_i, private_publication_allowed_i,\n    output wire private_uart_quiet_o,'),
 ('.clk(core_clk_i),.rst_n(reset_n_i),.uart_rx_i(uart_rx_i),.uart_tx_o(uart_tx_o),',
  '.clk(core_clk_i),.rst_n(reset_n_i),.transport_pause_i(private_transport_pause_i),\n        .publication_allowed_i(private_publication_allowed_i),.uart_quiet_o(private_uart_quiet_o),\n        .uart_rx_i(uart_rx_i),.uart_tx_o(uart_tx_o),')])

key=h.su.DemoAuthority(h.HOME_AUTHORITY).public_key
policy=f'''    localparam [127:0] HOME_DEVICE=128'h{h.DEVICE_ID.hex()};
    localparam [255:0] HOME_GEOMETRY=256'h{h.su.GEOMETRY.hex()};
    localparam [127:0] HOME_KEY_ID=128'h{key[8:24].hex()};
    localparam [255:0] HOME_KEY_ROOT=256'h{key[24:].hex()};
    wire home_enabled,home_failed,home_accepted,home_request_valid,home_request_last,home_request_ready;
    wire [7:0] home_request_byte,home_grant_byte;
    wire home_grant_valid,home_grant_last,home_grant_ready,home_transport_fault;
    wire [255:0] model_commitment;
    wire [63:0] home_remaining;
    wire token_uart_tx,token_uart_quiet,home_uart_tx;
    logic home_mode_q,home_stop_q;
    wire token_reset_n=core_reset_n && home_enabled && !home_stop_q;
    always_ff @(posedge core_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin home_mode_q<=0;home_stop_q<=0;end
        else begin
            if(home_failed || home_transport_fault) home_stop_q<=1;
            if(home_accepted) home_mode_q<=0;
            else if(home_request_valid && token_uart_quiet) home_mode_q<=1;
        end
    end
    assign uart_tx=home_mode_q ? home_uart_tx : (home_enabled ? token_uart_tx : 1'b1);
    home_boot_gate #(.DEVICE_ID(HOME_DEVICE),.GEOMETRY(HOME_GEOMETRY),
        .HOME_KEY_ID(HOME_KEY_ID),.HOME_KEY_ROOT(HOME_KEY_ROOT),
        .RESPONSE_LIMIT_CYCLES(HOME_RESPONSE_CYCLES),.LEASE_CYCLES(HOME_LEASE_CYCLES),
        .RENEW_LEAD_CYCLES(HOME_RENEW_CYCLES)) u_home (
        .clk(core_clk),.reset_n(core_reset_n),.nonce_valid_i(private_nonce_valid_i),
        .nonce_fault_i(private_nonce_fault_i),.nonce_i(private_nonce_i),.nonce_request_o(private_nonce_request_o),
        .admitted_root_valid_i(model_locked),.admitted_root_i(model_commitment),
        .model_fault_i(memory_fault || source_fault || home_transport_fault),
        .request_valid_o(home_request_valid),.request_last_o(home_request_last),
        .request_byte_o(home_request_byte),.request_ready_i(home_request_ready),
        .grant_valid_i(home_grant_valid),.grant_last_i(home_grant_last),
        .grant_byte_i(home_grant_byte),.grant_ready_o(home_grant_ready),
        .inference_enabled_o(home_enabled),.failed_o(home_failed),.new_lease_o(home_accepted),
        .lease_cycles_remaining_o(home_remaining));
    home_uart_transport u_home_uart (
        .clk(core_clk),.reset_n(core_reset_n),.enabled_i(home_mode_q),.uart_rx_i(uart_rx),.uart_tx_o(home_uart_tx),
        .request_valid_i(home_request_valid),.request_last_i(home_request_last),
        .request_byte_i(home_request_byte),.request_ready_o(home_request_ready),
        .grant_valid_o(home_grant_valid),.grant_last_o(home_grant_last),
        .grant_byte_o(home_grant_byte),.grant_ready_i(home_grant_ready),.fault_o(home_transport_fault));
'''
edit('top.sv',[
 ('module board1_fixed_swic_product_top (',
  'module board1_home_auth_core #(\n    parameter longint unsigned HOME_RESPONSE_CYCLES=250000000,\n    parameter longint unsigned HOME_LEASE_CYCLES=1500000000,\n    parameter longint unsigned HOME_RENEW_CYCLES=375000000\n) (\n    input wire private_nonce_valid_i,private_nonce_fault_i,\n    input wire [255:0] private_nonce_i,\n    output wire private_nonce_request_o,'),
 ('wire model_locked,memory_fault,core_fault,core_fault_in_app;',
  'wire model_locked,memory_fault,core_fault,core_fault_in_app;\n'+policy),
 ('.image_sha_o(swic_image_sha),.fault_o(swic_ingress_fault),',
  '.image_sha_o(swic_image_sha),.model_commitment_o(model_commitment),.fault_o(swic_ingress_fault),'),
 ('.private_runtime_app_fault_i(core_fault_in_app),',
  '.private_runtime_app_fault_i(core_fault_in_app || home_stop_q),'),
 ('.core_clk_i(core_clk),.app_clk_i(core_clk),.reset_n_i(core_reset_n),.uart_rx_i(uart_rx),.uart_tx_o(uart_tx),',
  '.core_clk_i(core_clk),.app_clk_i(core_clk),.reset_n_i(token_reset_n),\n        .private_transport_pause_i(home_mode_q),.private_publication_allowed_i(home_remaining>20000),\n        .private_uart_quiet_o(token_uart_quiet),.uart_rx_i(uart_rx),.uart_tx_o(token_uart_tx),')])
home=p/'home';home.mkdir()
for name in ['home_boot_gate.sv','home_uart_transport.sv']:
    shutil.copyfile(ROOT/'rtl'/name,home/name)
patch=ROOT/'integration/final-integration.patch'
command=['patch','-f','-F','0','-p1','-i',str(patch)]
subprocess.run(command+['--dry-run'],cwd=p,check=True)
subprocess.run(command,cwd=p,check=True)
record={'base':str(ROOT/'integration/BASELINE.json'),
        'files':{str(q.relative_to(p)):hashlib.sha256(q.read_bytes()).hexdigest() for q in p.rglob('*') if q.is_file()}}
(ROOT/'integration/OVERLAY.json').write_text(json.dumps(record,indent=2)+'\n')
print('Prepared home authorization overlay')

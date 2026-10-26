"""Replay the boot return corner with the native controller and real boundary.

This is a directed RTL simulation using all 227062 native boot words. It is
separate from induction and does not assume correctness of an external DDR.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import time

HERE=Path(__file__).resolve().parent
BOUNDARY='project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_ddr_preboard_locked_boundary.sv'
FIFO='project/fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv'


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_corner_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def boundary_testbench(original):
    ports='''wire [2:0] app_cmd;
    wire [28:0] app_addr;
    wire [31:0] app_mask;
    wire app_wr_en,app_wr_end,app_burst,app_self_refresh,app_refresh,raw_fault;
    assign phy_req_write=(app_cmd==0);
    assign phy_req_word_addr=app_addr[21:3];
    board1_context2048_ddr_preboard_locked_boundary dut(
        .app_clk_i(clk),.app_reset_n_i(reset_n),.private_upstream_fault_i(1'b0),
        .private_fixed_source_done_i(fixed_source_done),.private_fixed_source_ok_i(fixed_source_ok),
        .private_loader_data_i(loader_data),.private_loader_valid_i(loader_valid),.private_loader_ready_o(loader_ready),
        .private_readback_word_data_o(readback_word_data),.private_readback_word_valid_o(readback_word_valid),
        .private_readback_word_last_o(readback_word_last),.private_readback_word_ready_i(readback_word_ready),
        .private_readback_digest_done_i(readback_digest_done),.private_readback_digest_ok_i(readback_digest_ok),
        .private_runtime_req_valid_i(runtime_req_valid),.private_runtime_req_ready_o(runtime_req_ready),
        .private_runtime_req_word_address_i(runtime_req_word_address),.private_runtime_req_write_i(runtime_req_write),
        .private_runtime_req_write_data_i(runtime_req_write_data),.private_runtime_rsp_data_o(runtime_rsp_data),
        .private_runtime_rsp_valid_o(runtime_rsp_valid),.private_runtime_rsp_ready_i(runtime_rsp_ready),
        .private_runtime_rsp_error_o(runtime_rsp_error),.controller_pll_lock_i(calib_done),
        .controller_init_calib_complete_i(calib_done),.app_cmd_ready_i(phy_req_ready),
        .app_cmd_o(app_cmd),.app_cmd_en_o(phy_req_valid),.app_addr_o(app_addr),
        .app_wr_data_ready_i(phy_req_ready),.app_wr_data_o(phy_req_wdata),.app_wr_data_en_o(app_wr_en),
        .app_wr_data_end_o(app_wr_end),.app_wr_data_mask_o(app_mask),.app_rd_data_i(phy_rsp_data),
        .app_rd_data_valid_i(phy_rsp_valid),.app_rd_data_end_i(!phy_rsp_error),.app_burst_o(app_burst),
        .app_self_refresh_req_o(app_self_refresh),.app_refresh_req_o(app_refresh),
        .model_locked_o(model_locked),.fail_closed_o(fail_closed),.raw_response_protocol_fault_now_o(raw_fault));'''
    needle='board1_context2048_private_ddr_lock_bridge dut(.*);'
    if original.count(needle)!=1:raise ValueError('Corner testbench boundary changed')
    result=original.replace(needle,ports).replace('dut.state_q','dut.u_fixed_boot_lock.state_q')
    result=result.replace('dut.u_fixed_boot_lock.state_q!=5||!fail_closed||!model_locked',
        'dut.u_fixed_boot_lock.state_q!=15||!fail_closed||model_locked')
    result=result.replace('PASS: state/lock corner reproduced; sticky fault still gates all physical and runtime traffic',
        'PASS: actual boundary catches the extra return; adapter fault prevents LOCK and suppresses all physical and runtime traffic')
    return result


def main():
    common,order=load('run_handoff'),load('run_boot_order')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--boundary',action='store_true')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    _,root,bound=common.binding(args.package,'baseline')
    names={'production-boot.sv':order.SOURCE}
    if args.boundary:names.update({'boundary.sv':BOUNDARY,'fifo.sv':FIFO,'adapter.sv':'project/adapter.sv'})
    joins={}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,r,b=common.binding(args.package,variant)
        if all((root/path).read_bytes()==(r/path).read_bytes()for path in names.values()):joins[variant]=b
    for local,path in names.items():(out/local).write_bytes((root/path).read_bytes())
    tb=(HERE/'boot-order-corner-tb.sv').read_text()
    (out/'corner-tb.sv').write_text(boundary_testbench(tb)if args.boundary else tb)
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    inputs=dict(binding=bound,byte_identical_source_joins=joins,boundary_composed=args.boundary,
        native_model_words=227062,controller_input_ports_forced_or_cut=False,
        stimulus='All native boot writes/reads/returns, then an extra return on held final readback consumption; successful digest follows.',
        sources={n:dict(native_path=p,sha256=common.sha((out/n).read_bytes()))for n,p in names.items()},
        testbench_sha256=common.sha((out/'corner-tb.sv').read_bytes()),
        tools={n:dict(path=shutil.which(n),sha256=common.sha(Path(shutil.which(n)).read_bytes()))for n in ('iverilog','vvp')})
    raw=(json.dumps(inputs,indent=2,sort_keys=True)+'\n').encode();(out/'INPUTS.json').write_bytes(raw)
    commands=[['iverilog','-g2012','-DSYNTHESIS','-s','boot_order_corner_tb','-o','corner.vvp',*names,'corner-tb.sv'],['vvp','corner.vvp']]
    results=[]
    for phase,cmd in zip(('compile','replay'),commands):
        started=time.monotonic()
        with(out/(phase+'.log')).open('w')as log:
            cp=subprocess.run(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=90)
        results.append(dict(command=cmd,exit=cp.returncode,seconds=time.monotonic()-started,
            log_sha256=common.sha((out/(phase+'.log')).read_bytes())))
        if cp.returncode:break
    passed=len(results)==2 and all(r['exit']==0 for r in results)and'PASS:'in(out/'replay.log').read_text()
    result=dict(schema='native-full-boot-corner-simulation-v1',passed=passed,boundary_composed=args.boundary,
        inputs_sha256=common.sha(raw),hardware_access=False,inductive_theorem=False,
        physical_ddr_proved=False,production_source_bytes_unchanged=True,results=results)
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print((out/'replay.log').read_text()if(out/'replay.log').exists()else(out/'compile.log').read_text())
    raise SystemExit(0 if passed else 1)


if __name__=='__main__':main()

"""Check native transport packing, FIFO/reset connections and output decoding.

This is an exact source-expression/wiring audit used to compose the separate
FIFO theorem. It is not an independent whole-transport temporal theorem.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_transport_bind_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def compact(s):return re.sub(r'\s+','',s)
def sha(raw):return hashlib.sha256(raw).hexdigest()


def instance(text,channel):
    marker=re.search(r'board1_async_fifo_gray(?:_block)?\s*#\(((?:[^()]|\([^()]*\))*)\)\s*u_'+channel+r'\s*\(',text,re.S)
    if not marker:raise ValueError('Missing actual FIFO instance')
    opening=marker.end()-1;depth=1;end=opening+1
    while depth:
        if text[end]=='(':depth+=1
        elif text[end]==')':depth-=1
        end+=1
    body=text[opening+1:end-1]
    matches=list(re.finditer(r'\.(\w+)\s*\(([^()]*)\)',body))
    if compact(re.sub(r'\.(\w+)\s*\(([^()]*)\)','',body)).replace(',',''):
        raise ValueError('Unparsed FIFO port expression')
    result={m[1]:compact(m[2])for m in matches}
    if len(result)!=len(matches):raise ValueError('Repeated FIFO port')
    return result


def expected(channel):
    command=channel=='commands'
    return dict(s_clk_i='core_clk_i'if command else'app_clk_i',
        s_reset_n_i='core_reset_n'if command else'app_reset_n',
        s_valid_i='enqueue'if command else'capture_return',
        s_ready_o='request_s_ready'if command else'response_s_ready',
        s_data_i='{core_write,core_addr_i[21:3],core_wr_data_i}'if command else'{app_rd_end_i,app_rd_data_i}',
        s_abort_i="1'b0",s_full_o='',s_empty_o='',
        s_protocol_fault_o='request_s_fault'if command else'response_s_fault',
        m_clk_i='app_clk_i'if command else'core_clk_i',
        m_reset_n_i='app_reset_n'if command else'core_reset_n',
        m_valid_o='request_m_valid'if command else'response_m_valid',
        m_ready_i='physical_ready'if command else"1'b1",
        m_data_o='request_m_data'if command else'response_m_data',m_empty_o='',
        m_protocol_fault_o='request_m_fault'if command else'response_m_fault')


def check_ports(ports,channel):
    wanted=expected(channel)
    if ports!=wanted:
        bad=[k for k in set(ports)|set(wanted)if ports.get(k)!=wanted.get(k)]
        raise ValueError('Actual FIFO contract connection changed: '+','.join(sorted(bad)))


def main():
    common,runner=load('run_handoff'),load('run_fifo')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();records={}
    expressions={
        'physical_write':'request_m_data[275]',
        'enqueue':'core_cmd_en_i&&core_ready&&!core_bad',
        'issue':'request_m_valid&&physical_ready',
        'app_cmd_o':"physical_write?3'd0:3'd1",
        'app_addr_o':"{7'd0,request_m_data[274:256],3'b000}",
        'app_wr_data_o':'request_m_data[255:0]',
        'app_cmd_en_o':'issue','app_wr_en_o':'issue&&physical_write',
        'app_wr_end_o':'app_wr_en_o','app_wr_mask_o':"32'd0",
        'app_burst_o':"1'b0",'app_self_refresh_o':"1'b0",'app_refresh_o':"1'b0",
        'core_rd_valid_o':'core_reset_n&&response_m_valid',
        'core_rd_data_o':'response_m_data[255:0]','core_rd_end_o':'response_m_data[256]',
    }
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        pin,root,bound=common.binding(args.package,variant)
        raw=(root/'project/thin_transport.sv').read_bytes();text=raw.decode()
        channels={};negative=[]
        for channel in ('commands','returns'):
            width,bits,module,override=runner.channel_binding(raw,channel)
            ports=instance(text,channel);check_ports(ports,channel)
            channels[channel]=dict(width=width,depth=1<<bits,module=module,
                lookahead=1 if override is None else override,checked_ports=ports)
            for port in ('s_data_i','m_clk_i','s_reset_n_i'):
                changed=copy.deepcopy(ports);changed[port]='0'
                try:check_ports(changed,channel)
                except ValueError:negative.append(dict(channel=channel,port=port,rejected=True))
                else:raise ValueError('Width-preserving connection bypass accepted')
        actual={}
        for name,wanted in expressions.items():
            matches=re.findall(r'(?:\bassign\s+|\bwire\s+)'+re.escape(name)+r'\s*=\s*([^;]+);',text)
            if len(matches)!=1 or compact(matches[0])!=wanted:
                raise ValueError('Actual transport field mapping changed: '+name)
            actual[name]=wanted
        records[variant]=dict(binding=bound,native_transport_sha256=sha(raw),
            channels=channels,checked_packing_and_decoding=actual,negative_controls=negative)
        print(variant,'PASS 32 FIFO port bindings, 16 field expressions, 6 bypass controls')
    result=dict(schema='current-transport-fifo-contract-connections-v1',passed=True,variants=records,
        whole_transport_temporal_theorem=False,physical_cdc_or_vendor_controller_proved=False,
        checker_sha256=sha(Path(__file__).read_bytes()),hardware_access=False)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    with args.out.open('x')as f:f.write(json.dumps(result,indent=2,sort_keys=True)+'\n')


if __name__=='__main__':main()

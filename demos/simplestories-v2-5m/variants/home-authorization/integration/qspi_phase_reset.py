"""Qualify only the flash FIFO core reset on a falling core-clock edge.

All source resets still assert asynchronously. The original three positive-edge
release stages and their functional fanout remain, as does the trusted-domain
chain. This changes startup latency; it does not change the clock constraints.
"""
from pathlib import Path
import re
import startup_reset_qualifier

FILE='swic/swic_qspi_boot_source.sv'
OLD='''    always_ff @(posedge core_clk_i or negedge common_reset_n)
        if(!common_reset_n) core_release_q<=0;else core_release_q<={core_release_q[1:0],1'b1};'''
NEW='''    (* async_reg="true",syn_preserve=1 *) logic core_phase_release_q;
    always_ff @(negedge core_clk_i or negedge common_reset_n)
        if(!common_reset_n) core_phase_release_q<=0;else core_phase_release_q<=1'b1;
    wire qualified_core_reset_n=common_reset_n && core_phase_release_q;
    always_ff @(posedge core_clk_i or negedge qualified_core_reset_n)
        if(!qualified_core_reset_n) core_release_q<=0;else core_release_q<={core_release_q[1:0],1'b1};'''

def transform(name,text):
    if name!=FILE:return text
    assert text.count(OLD)==1
    return text.replace(OLD,NEW)

def apply(project):
    p=Path(project)/FILE;p.write_text(transform(FILE,p.read_text()))

def audit_mapping(text,core_clock,trusted_clock):
    result=startup_reset_qualifier.audit_mapping(text,core_clock,prefix='u_core/u_fixed_qspi_boot')
    stages={}
    for m in re.finditer(r'^DFFCE\s+(\\u_core/u_fixed_qspi_boot/slow_release_q_([012])_s\d+)\s+\((.*?)^\);',text,re.M|re.S):
        ports={k:re.sub(r'\s+','',v)for k,v in re.findall(r'\.([A-Z][A-Z0-9_]*)\(([^()]*)\)',m[3])}
        assert int(m[2])not in stages;stages[int(m[2])]=ports
    assert set(stages)=={0,1,2}
    for i,ports in stages.items():
        assert ports['CE']=='VCC'and ports['CLK']==re.sub(r'\s+','',trusted_clock)
        assert ports['D']==('VCC'if i==0 else stages[i-1]['Q'])
        assert ports['CLEAR']==result['raw_clear']
    result['trusted_stages']=stages
    result['scope']='Flash-loader falling-edge core reset qualifier followed by the retained three rising stages; separate unchanged trusted-domain chain. Exact mapped clocks/data/enables and guarded-clear truth table. Not analog characterization or whole-chip equivalence.'
    return result

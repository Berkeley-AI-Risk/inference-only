"""Register private verifier reset and allow two preparatory states before start.

Decoding multiple FSM states directly onto an asynchronous reset can glitch
when state bits change. Only the registered value drives reset here.
"""
from pathlib import Path
import re

def transform(name,s):
    if name!='home/home_boot_gate.sv':return s
    changes=[
        ('VERIFY=4,RUN=5,FAIL=15;','VERIFY=4,RUN=5,ARM=6,ARM_WAIT=7,FAIL=15;'),
        ('    wire crypto_reset_n=reset_n && (state_q==START || state_q==VERIFY);',
         '''    logic crypto_reset_release_q;
    always_ff @(posedge clk or negedge reset_n)begin
        if(!reset_n)crypto_reset_release_q<=0;
        else crypto_reset_release_q<=state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY;
    end
    wire crypto_reset_n=reset_n && crypto_reset_release_q;'''),
        ('wire active_window=state_q==SEND || state_q==RECEIVE || state_q==START || state_q==VERIFY;',
         'wire active_window=state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY;'),
        ("else if(index_q==11'(FRAME_BYTES-1)) begin state_q<=START;end",
         "else if(index_q==11'(FRAME_BYTES-1)) begin state_q<=ARM;end"),
        ('                START: state_q<=VERIFY;',
         '                ARM: state_q<=ARM_WAIT;\n                ARM_WAIT: state_q<=START;\n                START: state_q<=VERIFY;')]
    for old,new in changes:
        assert s.count(old)==1,old;s=s.replace(old,new)
    return s

def apply(project):
    p=Path(project)/'home/home_boot_gate.sv';p.write_text(transform('home/home_boot_gate.sv',p.read_text()))

def audit_mapping(text,core_clock):
    """Require a retained register and no direct home-state path to LMS resets."""
    compact=lambda x:re.sub(r'\s+','',x)
    cells=[];drivers={}
    for m in re.finditer(r'^([A-Z][A-Z0-9_]*)\s+(\S+)\s+\((.*?)^\);',text,re.M|re.S):
        ports={k:compact(v)for k,v in re.findall(r'\.([A-Z][A-Z0-9_]*)\(([^()]*)\)',m[3])}
        cell=(m[1],m[2],ports);cells.append(cell)
        for output in ['Q','F','O']:
            if output in ports:drivers.setdefault(ports[output],[]).append(cell)
    selected=[c for c in cells if re.search(r'(?:^|/)(?:u_home|home)/crypto_reset_release_q',c[1].lstrip('\\'))]
    selected=[c for c in selected if c[0]in ['DFFC','DFFCE']]
    assert len(selected)==1,'Expected one retained asynchronously cleared verifier-reset register'
    kind,name,ports=selected[0];qnet=ports['Q'];assert ports['CLK']==compact(core_clock)and 'CLEAR'in ports
    def frontier(net,seen=None):
        if net in ['GND','VCC',"1'b0","1'b1"]:return set()
        if seen is None:seen=set()
        assert net not in seen,'Cycle in mapped reset cone'
        matches=drivers.get(net,[]);assert len(matches)==1,('Unknown/multiple reset-cone drivers',net)
        c=matches[0];typ,inst,p=c
        if 'Q'in p:return {inst}
        assert typ.startswith('LUT')or typ in ['INV','BUF','BUFG','IBUF','MUX2','MUX2_LUT5','MUX2_LUT6','MUX2_LUT7','MUX2_LUT8'],('Unexpected reset-cone cell',typ,inst)
        inputs=[v for k,v in p.items()if re.fullmatch(r'I\d*|S\d*|SEL',k)]
        assert inputs,('Missing reset-cone inputs',inst)
        result=set()
        for v in inputs:result|=frontier(v,seen|{net})
        return result
    resets={p[pin]for typ,inst,p in cells if '/u_lms/'in inst and 'Q'in p for pin in ['CLEAR','PRESET']if pin in p and p[pin]not in ['GND','VCC']}
    assert resets,'No shared LMS asynchronous reset loads found'
    cones={}
    for net in sorted(resets):
        sources=frontier(net);assert name in sources,('LMS reset does not depend on retained register',net)
        bypass=[n for n in sources if re.search(r'(?:^|/)(?:u_home|home)/',n.lstrip('\\'))and n!=name]
        assert not bypass,('Combinational home-state bypass into LMS asynchronous reset',net,bypass)
        cones[net]=sorted(sources)
    return {'result':'PASS','driver_type':kind,'driver_instance':name,'registered_net':qnet,'clock':ports['CLK'],
        'asynchronous_clear_net':ports['CLEAR'],'lms_reset_cones':cones,
        'scope':'Mapped register type/core clock and combinational cones of all shared-LMS asynchronous reset/preset loads. Every cone depends on the retained register; no other home-controller register has a direct combinational path into those reset pins. Not mapped functional equivalence, analog timing or complete security certification.'}

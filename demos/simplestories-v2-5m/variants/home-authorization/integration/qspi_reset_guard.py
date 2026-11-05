"""Use the global synchronized reset for both flash-loader reset inputs.

The global reset asserts whenever trusted reset asserts. Its release is already
phase-qualified and synchronized. The loader retains its own three-stage
release synchronizers in each clock domain. Removing the redundant raw-trusted
branch avoids a separately timed reset bypass; no flash/data logic changes.
"""
from pathlib import Path
import re

OLD='''.trusted_clk_i(trusted_clk),.trusted_reset_n_i(trusted_reset_n),.core_clk_i(core_clk),.core_reset_n_i(core_reset_n),'''
NEW=OLD.replace('.trusted_reset_n_i(trusted_reset_n)','.trusted_reset_n_i(core_reset_n)')

def transform(name,text):
    if name!='top.sv':return text
    assert text.count(OLD)==1
    return text.replace(OLD,NEW)

def apply(project):
    p=Path(project)/'top.sv';p.write_text(transform('top.sv',p.read_text()))

def audit_mapping(text,core_clock,trusted_clock,global_reset):
    compact=lambda x:re.sub(r'\s+','',x)
    cells=[];drivers={}
    for m in re.finditer(r'^([A-Z][A-Z0-9_]*)\s+(\S+)\s+\((.*?)^\);',text,re.M|re.S):
        ports={k:compact(v)for k,v in re.findall(r'\.([A-Z][A-Z0-9_]*)\(([^()]*)\)',m[3])}
        c={'kind':m[1],'name':m[2],'ports':ports};cells.append(c)
        for output in ['Q','F','O']:
            if output in ports:drivers.setdefault(ports[output],[]).append(c)
    stages={}
    for c in cells:
        m=re.fullmatch(r'\\u_core/u_fixed_qspi_boot/(core|slow)_release_q_([012])_s\d+',c['name'])
        if m:
            key=(m[1],int(m[2]));assert key not in stages;stages[key]=c
    assert len(stages)==6
    for domain,clock in [('core',core_clock),('slow',trusted_clock)]:
        for i in range(3):
            c=stages[domain,i];assert c['kind']=='DFFCE'
            assert c['ports']['CE']=='VCC'and c['ports']['CLK']==compact(clock)
            assert c['ports']['D']==('VCC'if i==0 else stages[domain,i-1]['ports']['Q'])
    clears={c['ports']['CLEAR']for c in stages.values()}
    assert len(clears)==1
    global_reset=compact(global_reset);cache={}
    def value(net,bit,seen=frozenset()):
        if net==global_reset:return bit
        if net in ['VCC',"1'b1"]:return 1
        if net in ['GND',"1'b0"]:return 0
        assert net not in seen
        matches=drivers.get(net,[]);assert len(matches)==1
        c=matches[0];p=c['ports'];kind=c['kind']
        assert 'Q'not in p,('Raw register bypass in loader reset',c)
        if kind in ['INV','BUF','BUFG']:return value(p['I'],bit,seen|{net})^(kind=='INV')
        assert re.fullmatch(r'LUT[1-6]',kind)
        if c['name']not in cache:
            m=re.search(r'defparam\s+'+re.escape(c['name'])+r"\s*\.INIT\s*=\s*(\d+)'([hHbB])([0-9a-fA-F_]+)\s*;",text);assert m
            cache[c['name']]=int(m[3].replace('_',''),16 if m[2].lower()=='h'else 2)
        index=sum(value(p['I'+str(i)],bit,seen|{net})<<i for i in range(int(kind[3:])))
        return (cache[c['name']]>>index)&1
    for bit in [0,1]:assert value(next(iter(clears)),bit)==1-bit
    return {'result':'PASS','global_reset_net':global_reset,'loader_clear_net':next(iter(clears)),
        'stages':{d+str(i):c for(d,i),c in stages.items()},
        'scope':'Exact two three-stage loader synchronizers with retained clocks/data/enables. Their shared asynchronous clear depends only on the globally synchronized reset, with exhaustive one-input truth table. No raw-trusted register bypass. Not whole-chip or analog equivalence.'}

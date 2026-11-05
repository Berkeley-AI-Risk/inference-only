"""Move only the three-stage startup reset release to falling core-clock edges.

Assertion remains asynchronous. Functional logic still uses rising edges.
No timing exceptions or clock frequencies are changed.
"""
from pathlib import Path
import re

OLD='''    always_ff @(posedge core_clk or negedge common_async_reset_n) begin
        if(!common_async_reset_n) core_release_q<=0;
        else core_release_q<={core_release_q[1:0],1'b1};
    end'''
NEW=OLD.replace('posedge core_clk','negedge core_clk')

def transform(name,text):
    if name!='top.sv':return text
    assert text.count(OLD)==1,'Expected the unchanged three-stage startup reset chain'
    return text.replace(OLD,NEW)

def apply(project):
    p=Path(project)/'top.sv';p.write_text(transform('top.sv',p.read_text()))

def audit_mapping(text,core_clock,expected_polarity=1):
    compact=lambda v:re.sub(r'\s+','',v)
    cells=[];drivers={}
    for m in re.finditer(r'^([A-Z][A-Z0-9_]*)\s+(\S+)\s+\((.*?)^\);',text,re.M|re.S):
        ports={k:compact(v)for k,v in re.findall(r'\.([A-Z][A-Z0-9_]*)\(([^()]*)\)',m[3])}
        cell={'kind':m[1],'name':m[2],'ports':ports};cells.append(cell)
        for output in ['Q','F','O']:
            if output in ports:drivers.setdefault(ports[output],[]).append(cell)
    stages={}
    for c in cells:
        m=re.fullmatch(r'\\u_core/core_release_q_([012])_s\d+',c['name'])
        if m:
            assert int(m[1])not in stages,'Duplicated startup release stage'
            stages[int(m[1])]=c
    assert set(stages)=={0,1,2},'Expected all three retained startup release registers'
    assert all(c['kind']in ['DFFCE','DFFNCE']for c in stages.values())
    assert all(c['ports']['CE']=='VCC'for c in stages.values())
    assert len({c['ports']['CLEAR']for c in stages.values()})==1
    assert stages[0]['ports']['D']=='VCC'
    assert stages[1]['ports']['D']==stages[0]['ports']['Q']
    assert stages[2]['ports']['D']==stages[1]['ports']['Q']
    def polarity(net,seen=None):
        if net==compact(core_clock):return 0
        if seen is None:seen=set()
        assert net not in seen,'Clock inversion loop'
        ds=drivers.get(net,[]);assert len(ds)==1,('Unknown startup clock driver',net)
        c=ds[0];assert c['kind']in ['INV','BUF','BUFG'],('Startup clock must be direct/inverted clock',c)
        assert 'I'in c['ports']
        return polarity(c['ports']['I'],seen|{net})^(c['kind']=='INV')
    for c in stages.values():
        effective=polarity(c['ports']['CLK'])^(c['kind']=='DFFNCE')
        assert effective==expected_polarity,('Unexpected startup clock edge',c)
    return {'result':'PASS','core_clock':compact(core_clock),'active_edge':'falling'if expected_polarity else'rising','stages':stages,
        'scope':'Exact three-stage asynchronous-clear chain, constant-one entry, retained stage wiring and effective selected clock polarity. Functional core frequency/clock is separately checked by the native reviewer. Not an analog metastability certificate.'}

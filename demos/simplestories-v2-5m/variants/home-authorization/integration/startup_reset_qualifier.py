"""Qualify startup reset on a falling edge; keep the three rising-edge stages.

The entry stage has only the three-stage chain's reset pins as loads. The final
release retains a full rising-to-rising cycle for functional reset/enable paths.
Assertion of any source reset remains asynchronous through the AND guard.
"""
from pathlib import Path
import itertools,re
from startup_reset_phase import OLD

COMMON='    wire common_async_reset_n=board_reset_n && trusted_reset_n && app_reset_n;'
ENTRY='''
    (* async_reg="true",syn_preserve=1 *) logic core_phase_release_q;
    always_ff @(negedge core_clk or negedge common_async_reset_n) begin
        if(!common_async_reset_n) core_phase_release_q<=0;
        else core_phase_release_q<=1'b1;
    end
    wire qualified_async_reset_n=common_async_reset_n && core_phase_release_q;'''
CHAIN=OLD.replace('common_async_reset_n','qualified_async_reset_n')

def transform(name,text):
    if name!='top.sv':return text
    assert text.count(COMMON)==1 and text.count(OLD)==1
    return text.replace(COMMON,COMMON+ENTRY).replace(OLD,CHAIN)

def apply(project):
    p=Path(project)/'top.sv';p.write_text(transform('top.sv',p.read_text()))

def audit_mapping(text,core_clock,prefix='u_core'):
    compact=lambda x:re.sub(r'\s+','',x)
    cells=[];drivers={}
    for m in re.finditer(r'^([A-Z][A-Z0-9_]*)\s+(\S+)\s+\((.*?)^\);',text,re.M|re.S):
        ports={k:compact(v)for k,v in re.findall(r'\.([A-Z][A-Z0-9_]*)\(([^()]*)\)',m[3])}
        c={'kind':m[1],'name':m[2],'ports':ports};cells.append(c)
        for output in ['Q','F','O']:
            if output in ports:drivers.setdefault(ports[output],[]).append(c)
    stages={};entry=[]
    for c in cells:
        m=re.fullmatch(r'\\'+re.escape(prefix)+r'/core_release_q_([012])_s\d+',c['name'])
        if m:
            assert int(m[1])not in stages;stages[int(m[1])]=c
        if re.fullmatch(r'\\'+re.escape(prefix)+r'/core_phase_release_q_s\d+',c['name']):entry.append(c)
    assert set(stages)=={0,1,2}and len(entry)==1
    entry=entry[0]
    for c in list(stages.values())+[entry]:
        assert c['kind']=='DFFCE'and c['ports']['CE']=='VCC'
    assert entry['ports']['D']==stages[0]['ports']['D']=='VCC'
    assert stages[1]['ports']['D']==stages[0]['ports']['Q']
    assert stages[2]['ports']['D']==stages[1]['ports']['Q']
    assert len({c['ports']['CLEAR']for c in stages.values()})==1
    assert all(c['ports']['CLK']==compact(core_clock)for c in stages.values())
    def driver(net):
        matches=drivers.get(net,[]);assert len(matches)==1,('Unknown/multiple drivers',net)
        return matches[0]
    def polarity(net,seen=frozenset()):
        if net==compact(core_clock):return 0
        assert net not in seen
        c=driver(net);assert c['kind']in ['INV','BUF','BUFG']
        return polarity(c['ports']['I'],seen|{net})^(c['kind']=='INV')
    assert polarity(entry['ports']['CLK'])==1
    q=entry['ports']['Q'];raw_clear=entry['ports']['CLEAR'];chain_clear=stages[0]['ports']['CLEAR']
    def leaves(net,seen=frozenset()):
        if net in ['GND','VCC',"1'b0","1'b1"]:return set()
        if net==q:return {net}
        assert net not in seen
        c=driver(net)
        if 'Q'in c['ports']:return {net}
        assert c['kind'].startswith('LUT')or c['kind']in ['INV','BUF','BUFG','IBUF']
        ins=[v for k,v in c['ports'].items()if re.fullmatch(r'I\d*',k)]
        assert ins
        return set().union(*(leaves(v,seen|{net})for v in ins))
    raw_leaves=leaves(raw_clear);chain_leaves=leaves(chain_clear)
    assert q not in raw_leaves and q in chain_leaves
    assert chain_leaves<=raw_leaves|{q}
    inputs=sorted(raw_leaves|{q});assert len(inputs)<=8
    init_cache={}
    def value(net,assignment):
        if net in assignment:return assignment[net]
        if net in ['GND',"1'b0"]:return 0
        if net in ['VCC',"1'b1"]:return 1
        c=driver(net);typ=c['kind'];ports=c['ports']
        if typ in ['INV','BUF','BUFG','IBUF']:return value(ports['I'],assignment)^(typ=='INV')
        assert re.fullmatch(r'LUT[1-6]',typ)
        if c['name']not in init_cache:
            m=re.search(r'defparam\s+'+re.escape(c['name'])+r"\s*\.INIT\s*=\s*(\d+)'([hHbB])([0-9a-fA-F_]+)\s*;",text)
            assert m,('Missing LUT truth table',c['name'])
            init_cache[c['name']]=int(m[3].replace('_',''),16 if m[2].lower()=='h'else 2)
        index=sum(value(ports['I'+str(i)],assignment)<<i for i in range(int(typ[3:])))
        return (init_cache[c['name']]>>index)&1
    for bits in itertools.product([0,1],repeat=len(inputs)):
        assignment=dict(zip(inputs,bits))
        assert value(chain_clear,assignment)==(value(raw_clear,assignment)or not assignment[q]),('Reset guard differs',assignment)
    return {'result':'PASS','entry':entry,'rising_stages':stages,'core_clock':compact(core_clock),
        'raw_clear':raw_clear,'qualified_chain_clear':chain_clear,'truth_table_inputs':inputs,
        'truth_table_cases':2**len(inputs),
        'scope':'Retained falling-edge qualification stage followed by exact three-stage rising-edge release chain. Constant data/enables, stage wiring and full mapped combinational truth table of qualified clear = raw clear OR NOT entry Q. Core clock unchanged. Not analog metastability or complete mapped-design equivalence.'}

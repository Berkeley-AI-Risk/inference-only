"""Request a distinct flash-loader core reset path with preserved nets.

This is a physical hold/removal experiment, not an SDC exception. Its timing
must be checked in the routed report; source identity alone proves no delay.
LUT1 INIT=2'h2 is the vendor identity truth table (SUG283). syn_keep preserves
the intermediate nets (SUG550). Mapping must confirm what was retained.
"""
from pathlib import Path
import itertools,re
FILE='swic/swic_qspi_boot_source.sv'
OLD='''    always_ff @(posedge core_clk_i or negedge common_reset_n)
        if(!common_reset_n) core_release_q<=0;else core_release_q<={core_release_q[1:0],1'b1};'''

def transform(name,text,buffers):
    if name!=FILE:return text
    assert 1<=buffers<=4 and text.count(OLD)==1
    parts=[]
    for i in range(buffers):
        source='common_reset_n'if i==0 else f'core_reset_pad_{i-1}'
        parts.append(f'''    wire core_reset_pad_{i} /* synthesis syn_keep=1 */;
    LUT1 #(.INIT(2'h2)) u_core_reset_pad_{i}(.I0({source}),.F(core_reset_pad_{i}));''')
    parts.append(OLD.replace('common_reset_n',f'core_reset_pad_{buffers-1}'))
    return text.replace(OLD,'\n'.join(parts))

def apply(project,buffers):
    p=Path(project)/FILE;p.write_text(transform(FILE,p.read_text(),buffers))

def audit_mapping(text,core_clock,trusted_clock):
    compact=lambda x:re.sub(r'\s+','',x)
    cells=[];drivers={};stages={};cache={}
    for m in re.finditer(r'^([A-Z][A-Z0-9_]*)\s+(\S+)\s+\((.*?)^\);',text,re.M|re.S):
        ports={k:compact(v)for k,v in re.findall(r'\.([A-Z][A-Z0-9_]*)\(([^()]*)\)',m[3])}
        cell={'kind':m[1],'name':m[2],'ports':ports};cells.append(cell)
        for output in ['Q','F','O']:
            if output in ports:drivers.setdefault(ports[output],[]).append(cell)
        match=re.fullmatch(r'\\u_core/u_fixed_qspi_boot/(core|slow)_release_q_([012])_s\d+',m[2])
        if match:
            key=(match[1],int(match[2]));assert key not in stages;stages[key]=cell
    assert len(stages)==6
    clears={}
    for domain,clock in [('core',core_clock),('slow',trusted_clock)]:
        for i in range(3):
            c=stages[domain,i];ports=c['ports']
            assert c['kind']=='DFFCE'and ports['CE']=='VCC'and ports['CLK']==compact(clock)
            assert ports['D']==('VCC'if i==0 else stages[domain,i-1]['ports']['Q'])
        group={stages[domain,i]['ports']['CLEAR']for i in range(3)};assert len(group)==1
        clears[domain]=next(iter(group))
    def driver(net):
        matches=drivers.get(net,[]);assert len(matches)==1,('Unknown/multiple reset drivers',net)
        return matches[0]
    def leaves(net,seen=frozenset()):
        if net in ['GND','VCC',"1'b0","1'b1"]:return set()
        assert net not in seen
        c=driver(net)
        if 'Q'in c['ports']or c['kind']=='IBUF':return {net}
        assert re.fullmatch(r'LUT[1-6]',c['kind'])or c['kind']in ['INV','BUF','BUFG']
        return set().union(*(leaves(v,seen|{net})for k,v in c['ports'].items()if re.fullmatch(r'I\d*',k)))
    inputs=sorted(leaves(clears['core'])|leaves(clears['slow']));assert len(inputs)<=8
    def value(net,assignment):
        if net in assignment:return assignment[net]
        if net in ['GND',"1'b0"]:return 0
        if net in ['VCC',"1'b1"]:return 1
        c=driver(net);kind=c['kind'];ports=c['ports']
        if kind in ['INV','BUF','BUFG']:return value(ports['I'],assignment)^(kind=='INV')
        assert re.fullmatch(r'LUT[1-6]',kind)
        if c['name']not in cache:
            m=re.search(r'defparam\s+'+re.escape(c['name'])+r"\s*\.INIT\s*=\s*(\d+)'([hHbB])([0-9a-fA-F_]+)\s*;",text);assert m
            cache[c['name']]=int(m[3].replace('_',''),16 if m[2].lower()=='h'else 2)
        index=sum(value(ports['I'+str(i)],assignment)<<i for i in range(int(kind[3:])))
        return(cache[c['name']]>>index)&1
    for bits in itertools.product([0,1],repeat=len(inputs)):
        assignment=dict(zip(inputs,bits))
        assert value(clears['core'],assignment)==value(clears['slow'],assignment),'Core and trusted asynchronous assertion functions differ'
    pads=[c for c in cells if c['name'].startswith('\\u_core/u_fixed_qspi_boot/u_core_reset_pad_')]
    return {'result':'PASS','stages':{d+str(i):c for(d,i),c in stages.items()},'clear_nets':clears,'truth_inputs':inputs,'truth_cases':2**len(inputs),'named_pad_cells':pads,'scope':'Retained two three-stage release chains, exact clocks/data/enables, and exhaustive combinational identity of both reset assertion cones. Named pad cells are listed, not assumed. Physical delay and closure require the raw routed timing report; this is not an analog or whole-design proof.'}

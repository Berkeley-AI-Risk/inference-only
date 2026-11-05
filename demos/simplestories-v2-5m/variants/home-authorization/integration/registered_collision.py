"""Latch boot metadata-owner collisions outside the inference data path."""


def transform(name, text):
    if name != 'top.sv':
        return text
    old='    assign source_fault=swic_qspi_fault || swic_ingress_fault || (swic_boot_metadata_read && swic_metadata_read);'
    assert text.count(old)==1
    return text.replace(old,'''    logic metadata_collision_q;
    always_ff @(posedge core_clk or negedge core_reset_n) begin
        if(!core_reset_n) metadata_collision_q<=0;
        else if(swic_boot_metadata_read && swic_metadata_read) metadata_collision_q<=1;
    end
    assign source_fault=swic_qspi_fault || swic_ingress_fault || metadata_collision_q;''')


def apply(project):
    from pathlib import Path
    p=Path(project)/'top.sv'
    p.write_text(transform('top.sv',p.read_text()))


def audit_mapping(text, core_clock):
    import re
    found=[]
    for m in re.finditer(r'^(\w+)\s+(\\\S+)\s+\((.*?)^\);',text,re.M|re.S):
        ports={k:re.sub(r'\s+','',v) for k,v in re.findall(r'\.(\w+)\(([^()]*)\)',m[3])}
        if ports.get('Q','').lstrip('\\')=='u_core/metadata_collision_q':
            found.append((m[1],m[2],ports))
    assert len(found)==1, 'Expected one registered collision driver'
    kind,name,ports=found[0]
    assert kind=='DFFCE', 'Collision latch is not the expected sticky flip-flop'
    assert ports['CLK']==core_clock and ports['D']=='VCC'
    assert ports['CE'] not in ('GND','VCC') and ports['CLEAR'] not in ('GND','VCC')
    return {'result':'PASS','driver_type':kind,'driver_instance':name,'clock':core_clock,
            'scope':'Registered sticky-fault boundary and core clock only. Input-condition equivalence is established at RTL; this is not full gate-level equivalence.'}

"""Replace subtract-then-compare with the same private publication predicate."""
from pathlib import Path

FILES={'top.sv','home/home_boot_gate.sv'}


def once(text,old,new):
    assert text.count(old)==1,old
    return text.replace(old,new)


def transform(name,text):
    if name=='home/home_boot_gate.sv':
        text=once(text,'    output wire [63:0] lease_cycles_remaining_o,',
                  '    output wire [63:0] lease_cycles_remaining_o,\n    output wire publication_allowed_o,')
        old="    assign lease_cycles_remaining_o=inference_enabled_o ? 64'(remaining_cycles) : 64'd0;"
        text=once(text,old,old+'''
    // Equivalent to lease_cycles_remaining_o > 20000. inference_enabled_o
    // already requires lease_age_q < LEASE_CYCLES-1, excluding wraparound.
    assign publication_allowed_o=(LEASE_CYCLES>20001) && inference_enabled_o &&
                                 lease_age_q<LW'(LEASE_CYCLES-20001);''')
    elif name=='top.sv':
        text=once(text,'    wire [63:0] home_remaining;',
                  '    wire [63:0] home_remaining;\n    wire home_publication_allowed;')
        text=once(text,'.lease_cycles_remaining_o(home_remaining),',
                  '.lease_cycles_remaining_o(home_remaining),.publication_allowed_o(home_publication_allowed),')
        text=once(text,'.private_publication_allowed_i(home_remaining>20000)',
                  '.private_publication_allowed_i(home_publication_allowed)')
    return text


def apply(project):
    for name in sorted(FILES):
        p=Path(project)/name;p.write_text(transform(name,p.read_text()))

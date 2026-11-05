"""Omit reset wiring only for fully overwritten, private SHA working data.

The one-round compressor's busy/done/result/round control retains its original
asynchronous reset. Working data changes only on an accepted block or a busy
round, and the public result remains the original resettable register. Other
compressors in sha.sv are unchanged. This is an opt-in copied-source transform.
"""
from pathlib import Path

FILE='sha.sv'


def transform(name,text):
    if name!=FILE:return text
    first=text.index('    always_ff @(posedge clk_i or negedge reset_n_i) begin')
    last=text.index('\n`ifdef FORMAL',first)
    old=text[first:last]
    reset_data='''            initial_state_q <= 256'd0;
            a_q <= 32'd0;
            b_q <= 32'd0;
            c_q <= 32'd0;
            d_q <= 32'd0;
            e_q <= 32'd0;
            f_q <= 32'd0;
            g_q <= 32'd0;
            h_q <= 32'd0;
'''
    reset_schedule='''            for (index = 0; index < 16; index = index + 1)
                schedule_q[index] <= 32'd0;
'''
    capture='''                for (index = 0; index < 16; index = index + 1)
                    schedule_q[index] <=
                        block_i[511 - index * 32 -: 32];
                initial_state_q <= state_i;
                a_q <= state_i[255:224];
                b_q <= state_i[223:192];
                c_q <= state_i[191:160];
                d_q <= state_i[159:128];
                e_q <= state_i[127:96];
                f_q <= state_i[95:64];
                g_q <= state_i[63:32];
                h_q <= state_i[31:0];
'''
    iterate='''                for (index = 0; index < 15; index = index + 1)
                    schedule_q[index] <= schedule_q[index + 1];
                schedule_q[15] <= schedule_next;
                a_q <= next_a;
                b_q <= a_q;
                c_q <= b_q;
                d_q <= c_q;
                e_q <= next_e;
                f_q <= e_q;
                g_q <= f_q;
                h_q <= g_q;
'''
    control=old
    for part in [reset_data,reset_schedule,capture,iterate]:
        assert control.count(part)==1
        control=control.replace(part,'')
    data='''    // Private working state is overwritten in full before busy becomes true.
    // It is not a result, validity bit or permission state.
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            if (start_i && !busy_o) begin
'''+capture+'''            end else if (busy_o) begin
'''+iterate+'''            end
        end
    end

'''
    return text[:first]+data+control+text[last:]


def apply(project):
    p=Path(project)/FILE
    p.write_text(transform(FILE,p.read_text()))


def audit_mapping(text,core_clock):
    """Check the intended reset boundary in a plain post-PnR netlist."""
    import re
    groups={}
    for m in re.finditer(r'^(\w+)\s+(\\\S+)\s+\((.*?)^\);',text,re.M|re.S):
        if not m[1].startswith('DFF'):continue
        name=m[2].lstrip('\\')
        hit=re.match(r'(.*u_compress/)(schedule_q(?:_|\[)|initial_state_q_|[a-h]_q_|state_o_|busy_o_|done_o_|round_q_).*',name)
        if not hit:continue
        ports={k:re.sub(r'\s+','',v) for k,v in re.findall(r'\.(\w+)\(([^()]*)\)',m[3])}
        group=groups.setdefault(hit[1],{'private_data':[],'reset_control_and_result':[]})
        assert ports.get('CLK')==core_clock,'Unexpected SHA data/control clock'
        private=hit[2] not in ['state_o_','busy_o_','done_o_','round_q_']
        reset_ports={k:v for k,v in ports.items() if k in ['CLEAR','PRESET','RESET','SET'] and v!='GND'}
        if private:
            assert not reset_ports,'Private SHA working register retains reset wiring: '+name
            group['private_data'].append(name)
        else:
            assert reset_ports,'SHA result/control lost its reset: '+name
            group['reset_control_and_result'].append(name)
    assert len(groups)==2,'Expected the admission/root and shared-DDR compact compressors'
    summary={}
    for name,group in groups.items():
        assert len(group['private_data'])==1024,'Unexpected working-register count: '+name
        assert len(group['reset_control_and_result'])==264,'Unexpected result/control register count: '+name
        summary[name]={key:len(value) for key,value in group.items()}
    return {'result':'PASS','core_clock':core_clock,'compressors':summary,
            'private_reset_connections_removed':2048,
            'scope':'Mapped register/reset/clock structure only. RTL observable equivalence is checked separately; not complete gate-level equivalence or timing signoff.'}

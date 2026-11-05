"""Register the high-fanout permission reset; retain asynchronous fault assertion.

The register releases only on home_accepted. The lease remains enabled until
a fault or expiry, which asynchronously asserts this reset. UART publication
and memory fault gates remain unchanged. Full-system simulation additionally
compares this signal with the original permission expression on every cycle.
"""
from pathlib import Path

FILE='top.sv'


def transform(name,text):
    if name!=FILE:return text
    choices=[
        '    wire token_reset_n=core_reset_n && home_enabled && !home_stop_q;',
        '    wire token_reset_asserted /* synthesis syn_keep = 1 */=!(core_reset_n && home_enabled && !home_stop_q);\n    wire token_reset_n=~token_reset_asserted;',
    ]
    matches=[old for old in choices if old in text]
    assert len(matches)==1,'Expected exactly one known permission-reset form'
    replacement='''    wire permit_register_reset_n = core_reset_n && !home_failed &&
                                   !home_transport_fault && !home_stop_q;
    logic token_reset_asserted /* synthesis syn_preserve = 1 */;
    always_ff @(posedge core_clk or negedge permit_register_reset_n) begin
        if (!permit_register_reset_n) token_reset_asserted <= 1'b1;
        else if (home_accepted) token_reset_asserted <= 1'b0;
    end
    wire token_reset_n=~token_reset_asserted;'''
    return text.replace(matches[0],replacement)


def apply(project):
    path=Path(project)/FILE
    path.write_text(transform(FILE,path.read_text()))


def testbench_text(text):
    check='''
    // Compare the registered permit with the original combinational policy.
    always @(negedge dut.core_clk) begin
        if (dut.core_reset_n &&
            dut.token_reset_n !== (dut.core_reset_n && dut.home_enabled && !dut.home_stop_q))
            $fatal(1,"registered permission reset differs from original policy");
    end
    always @(posedge dut.home_failed or posedge dut.home_transport_fault) begin
        #1;
        if (dut.core_reset_n && dut.token_reset_n !== 1'b0)
            $fatal(1,"permission fault did not assert reset asynchronously");
    end
'''
    assert text.count('\nendmodule')==1
    return text.replace('\nendmodule',check+'\nendmodule')

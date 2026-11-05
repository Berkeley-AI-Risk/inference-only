"""Explicit physical core-clock variants; source clock and UART stay matched."""
from pathlib import Path

CONTROLLER = 'fpga/token_only_model0_ddr_board1/product8_timing_successor1/rtl/board1_gowin_ddr3_raw_controller_shell.sv'
PROJECT_FILES = {CONTROLLER, 'uart_core.sv', 'top.sv', 'constraints/product.sdc'}


def config(divider):
    assert divider in (2, 4)
    hz = 50000000 // divider
    return {'core_divider': divider, 'core_hz': hz,
            'uart_clocks_per_bit': (hz + 57600) // 115200}


def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)


def project_text(name, text, divider):
    if divider == 2 or name not in PROJECT_FILES:
        return text
    cfg = config(divider)
    if name == CONTROLLER:
        text = replace_once(text, 'defparam u_core_clkdiv.DIV_MODE = "2";',
                            'defparam u_core_clkdiv.DIV_MODE = "4";')
        text = replace_once(text, 'CLKDIV u_core_clkdiv (',
                            '(* syn_preserve=1 *) CLKDIV u_core_clkdiv (')
    elif name == 'uart_core.sv':
        text = replace_once(text, '.CLKS_PER_BIT(217)',
                            f'.CLKS_PER_BIT({cfg["uart_clocks_per_bit"]})')
    elif name == 'top.sv':
        text = replace_once(text, 'home_uart_transport u_home_uart (',
                            f'home_uart_transport #(.CLKS_PER_BIT({cfg["uart_clocks_per_bit"]})) u_home_uart (')
    else:
        lines = text.splitlines(keepends=True)
        found = 0
        for i, line in enumerate(lines):
            if 'create_generated_clock -name inference_clk25 ' in line:
                assert '-divide_by 2 ' in line and 'u_core_clkdiv/CLKOUT' in line
                lines[i] = line.replace('inference_clk25', 'inference_clk12p5').replace('-divide_by 2 ', '-divide_by 4 ')
                found += 1
        assert found == 1
        text = ''.join(lines).replace('inference_clk25', 'inference_clk12p5')
    return text


def apply_project(project, divider):
    config(divider)
    if divider == 2:
        return
    for name in PROJECT_FILES:
        path = Path(project) / name
        path.write_text(project_text(name, path.read_text(), divider))


def shared_clock_text(name, text):
    """Merge identical DIV4 primitives; call after the 12.5 MHz transform."""
    if name == CONTROLLER:
        trusted = '''    CLKDIV u_trusted_clkdiv (
        .HCLKIN(pll_clkout1_50mhz),
        .RESETN(reset_button_n && pll_lock),
        .CALIB(1'b0),
        .CLKOUT(trusted_clk_25mhz_o)
    );
    defparam u_trusted_clkdiv.DIV_MODE = "4";'''
        core = '''CLKDIV u_core_clkdiv (
        .HCLKIN(pll_clkout1_50mhz),
        .RESETN(reset_button_n && pll_lock),
        .CALIB(1'b0),
        .CLKOUT(core_clk_25mhz_o)
    );
    defparam u_core_clkdiv.DIV_MODE = "4";'''
        assert core in text, 'Both dividers must have identical clock/reset/calibration and DIV4'
        text=replace_once(text, trusted,
            '    // One DIV4 drives both clock ports with identical phase and reset.\n'
            '    assign trusted_clk_25mhz_o = core_clk_25mhz_o;')
        return text.replace('// Separate fixed inference clock; DDR reference/app/memory clocks stay unchanged.',
                            '// Shared fixed inference/trusted clock; DDR clocks stay unchanged.')
    if name == 'constraints/product.sdc':
        lines=text.splitlines(keepends=True)
        selected=[line for line in lines if 'create_generated_clock -name trusted_clk12p5 ' in line]
        assert len(selected)==1 and 'u_trusted_clkdiv/CLKOUT' in selected[0]
        assert 'create_generated_clock -name inference_clk12p5 ' in text
        return ''.join(line for line in lines if line != selected[0])
    return text


def share_core_clock(project):
    for name in [CONTROLLER, 'constraints/product.sdc']:
        path=Path(project)/name
        path.write_text(shared_clock_text(name,path.read_text()))


def testbench_text(text, divider):
    if divider == 2:
        return text
    # These are accelerated simulation budgets, not the native wall-clock
    # policy. Keep enough core cycles for the unchanged cryptographic and
    # inference work; only the serial timing follows the physical clock.
    for old, new in [("#(.USE_SHARED_HASH(1'b1))front", "#(.USE_SHARED_HASH(1'b1),.TIMEOUT_CYCLES(12500000))front")]:
        text = replace_once(text, old, new)
    assert 'repeat(217)' in text and 'repeat(325)' in text
    return text.replace('repeat(217)', 'repeat(109)').replace('repeat(325)', 'repeat(163)')


def phy_text(text, divider):
    if divider == 2:
        return text
    return replace_once(text, 'always #20 core_clk=~core_clk;',
                        'always #40 core_clk=~core_clk;')

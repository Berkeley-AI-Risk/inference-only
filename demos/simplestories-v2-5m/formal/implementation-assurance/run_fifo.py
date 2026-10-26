"""Current DDR transport FIFO, literal payload/queue geometry, arbitrary clocks."""
import argparse
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_fifo_'+name,HERE/(name+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def channel_binding(transport,channel):
    text=transport.decode()
    match=re.search(r'(board1_async_fifo_gray(?:_block)?)\s*#\(((?:[^()]|\([^()]*\))*)\)\s*u_'+channel+r'\s*\(',text,re.S)
    if not match:raise ValueError('Actual transport channel instance missing')
    module,parameters=match.groups()
    width,bits=(276,5)if channel=='commands'else(257,6)
    expected=f'.WIDTH({"COMMAND_W" if channel=="commands" else width}),.ADDR_BITS({bits}),.RAM_STYLE("block")'
    normalized=re.sub(r'\s+','',parameters)
    override=0 if normalized==expected+',.DESTINATION_LOOKAHEAD(0)'else None
    if normalized!=expected and override is None:raise ValueError('Actual FIFO parameter binding changed')
    if text.count('localparam integer COMMAND_W = 276;')!=1:raise ValueError('Actual command payload width changed')
    return width,bits,module,override


def harness(release,width,bits,channel,module='board1_async_fifo_gray',lookahead_override=None):
    override=''if lookahead_override is None else f',.DESTINATION_LOOKAHEAD({lookahead_override})'
    return f'''module fifo_harness (
        input wire core_clk_i,app_clk_i,core_reset_n_i,app_reset_n_i,
        input wire s_valid_i,s_abort_i,m_ready_i,
        input wire [{width-1}:0] s_data_i
    );
{release}
    // Reachable reset-release patterns, proved rather than assumed. They
    // exclude induction-only states that would reassert one domain's reset
    // without a common reset and invent a new queue epoch.
    always_comb begin
        assert(core_release_q == 0 || core_release_q == 1 ||
               core_release_q == 3 || core_release_q == 7);
        assert(app_release_q == 0 || app_release_q == 1 ||
               app_release_q == 3 || app_release_q == 7);
    end
    wire s_ready,m_valid;
    wire [{width-1}:0] m_data;
    {module} #(.WIDTH({width}),.ADDR_BITS({bits}),.RAM_STYLE("block"){override}) dut (
        .s_clk_i({'core' if channel=='commands' else 'app'}_clk_i),
        .s_reset_n_i({'core' if channel=='commands' else 'app'}_reset_n),
        .s_valid_i(s_valid_i),.s_abort_i(s_abort_i),.s_ready_o(s_ready),.s_data_i(s_data_i),
        .s_full_o(),.s_empty_o(),.s_protocol_fault_o(),
        .m_clk_i({'app' if channel=='commands' else 'core'}_clk_i),
        .m_reset_n_i({'app' if channel=='commands' else 'core'}_reset_n),
        .m_ready_i(m_ready_i),.m_valid_o(m_valid),.m_data_o(m_data),
        .m_empty_o(),.m_protocol_fault_o()
    );
endmodule
'''


def main():
    common,engine=load('run_handoff'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),default='baseline')
    parser.add_argument('--channel',choices=('commands','returns'),default='commands')
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--depth',type=int,default=12)
    parser.add_argument('--induction-depth',type=int)
    parser.add_argument('--solver-unroll',action='store_true')
    parser.add_argument('--mutant',choices=('flip-operation-bit','wrong-prefetch-row'))
    parser.add_argument('--timeout',type=int,default=60)
    args=parser.parse_args()
    pin,root,bound=common.binding(args.package,args.variant)
    original=(root/'project/fifo.sv').read_bytes()
    transport=(root/'project/thin_transport.sv').read_bytes()
    source=original.decode()
    width,bits,module,override=channel_binding(transport,args.channel)
    start=source.index('module '+module+' #(')
    end=source.index('\nendmodule',start)
    header=source[start:source.index(') (',start)]
    if not re.search(r'parameter integer DESTINATION_LOOKAHEAD = 1(?:,|\n)',header):
        raise ValueError('Actual FIFO lookahead default changed')
    selected=source[start:end]
    mutations={
        'flip-operation-bit':(
            'memory_q[write_binary_q[ADDR_BITS-1:0]] <= s_data_i;',
            'memory_q[write_binary_q[ADDR_BITS-1:0]] <= s_data_i ^ (WIDTH\'(1) << (WIDTH-1));'),
        'wrong-prefetch-row':(
            'm_data_q <= memory_q[m_binary_next_address];',
            'm_data_q <= memory_q[m_binary_next_address ^ {{(ADDR_BITS-1){1\'b0}},1\'b1}];'),
    }
    if args.mutant:
        old,new=mutations[args.mutant]
        if selected.count(old)!=1:raise ValueError('Mutation site changed')
        selected=selected.replace(old,new)
    monitor=(HERE/'fifo-monitor.inc.sv').read_text()
    source='`undef FORMAL\n'+source[:start]+selected+'\n'+monitor+source[end:]
    # Exact clock/reset-release implementation used by the actual transport.
    reset_start=transport.decode().index('    wire common_reset_n = ')
    reset_end=transport.decode().index('\n    logic core_fault_q,',reset_start)
    release=transport.decode()[reset_start:reset_end]
    wrapper=harness(release,width,bits,args.channel,module,override)
    files={'fifo.sv':source.encode(),'harness.sv':wrapper.encode(),
        'production-fifo.sv':original,'production-transport.sv':transport,
        'monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes(),
        'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),
        'SOURCES.json':(HERE/'SOURCES.json').read_bytes()}
    # One source assertion is instantiated fifteen times by the ordered-pair
    # generate loop; there are nine payload/ownership assertions.
    count=15+11+2
    bound=dict(bound,channel=args.channel,width=width,depth=1<<bits,
        actual_fifo_module=module,actual_destination_lookahead=1 if override is None else override,
        source_fifo_sha256=common.sha(original),source_transport_sha256=common.sha(transport),
        common_reset_release_bytes=release,
        arbitrary_clock_phases=True,physical_metastability_or_skew_proved=False)
    scope=('Digital FIFO accepted-sequence ownership and full-width payload preservation under '
        'arbitrary independent clock edge schedules and the actual transport common reset/release. '
        'No input payload/valid/ready assumptions, no fairness, no upstream memory policy theorem, '
        'no physical metastability/Gray-bus-skew or vendor primitive theorem. '
        'Actual per-variant FIFO module and lookahead override retained, with positive-edge transport pointer synchronization.')
    constraints=('initial\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n'
        'state 1\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n')
    # Explicit stimulus only for legal-traffic reachability. It is never used
    # in BMC or induction. Actual full capacity and wrap are reached without
    # shrinking the FIFO or assuming a proof conclusion.
    cover_steps=32+(1<<bits)*12
    cover_inputs='initial\nassume (= [dut.f_slot] (_ bv0 '+str(bits)+'))\n'
    for step in range(cover_steps):
        cover_inputs+=f'state {step}\n'
        for name,value in dict(core_clk_i=bool((step//4)%2),app_clk_i=bool(step%2),
            core_reset_n_i=step>=2,app_reset_n_i=step>=2,
            s_valid_i=step>=2,s_abort_i=False,
            m_ready_i=step>=(1<<bits)*(9 if args.channel=='commands' else 3)).items():
            cover_inputs+=f'assume (= [{name}] {str(value).lower()})\n'
        cover_inputs+=f'assume (= [s_data_i] (_ bv1 {width}))\n'
    raise SystemExit(engine.check(args.run,files,top='fifo_harness',reset_constraints=constraints,
        assertions=count,covers=4,binding=bound,scope=scope,cuts=[],depth=args.depth,mutant=args.mutant,
        timeout=args.timeout,observer_constants=1,expected_memories=0 if module.endswith('_block')else 1,multiclock=True,
        expected_register_memories={'dut.memory_q':{'width':width,'size':1<<bits}}if module.endswith('_block')else None,
        cover_constraints=cover_inputs,cover_depth=cover_steps,
        induction_depth=args.induction_depth,
        solver_cli={s:['--unroll'] for s in ('z3','cvc5')} if args.solver_unroll else None))


if __name__=='__main__':main()

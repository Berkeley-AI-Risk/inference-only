"""Prove actual top/memory/transport clock and reset-epoch correspondence.

Copies the native reset logic and validates the real top instance bindings.
Clocks and vendor/reset-source outputs remain arbitrary. No payload, UART,
vendor controller or authenticator behavior is credited by this small lemma.
"""
import argparse
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
TOP='board1_actual_reset_correspondence'


def load(name):
    spec=importlib.util.spec_from_file_location('_reset_correspondence_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def fragment(source,start,end):
    if source.count(start)!=1 or source.count(end)!=1:raise ValueError('Native reset fragment boundary changed')
    left=source.index(start);right=source.index(end,left)+len(end)
    return source[left:right]


def derive(native):
    model=load('control_model');memory=load('run_memory_path')
    top=native['top.sv'].decode();parent=native['memory.sv'].decode();transport=native['transport.sv'].decode()
    _,mb=model.instance(top,memory.top_module(native['memory.sv']),'u_memory')
    _,tb=model.instance(top,'board1_thin_ddr_app_transport','u_transport')
    expected_m=dict(app_clk_i='core_clk',app_reset_n_i='core_reset_n',trusted_clk_i='trusted_clk',trusted_reset_n_i='trusted_reset_n')
    expected_t=dict(core_clk_i='core_clk',core_reset_n_i='core_reset_n',app_clk_i='app_clk',app_reset_n_i='app_reset_n')
    if any(mb.get(k)!=v for k,v in expected_m.items())or any(tb.get(k)!=v for k,v in expected_t.items()):
        raise ValueError('Actual source/transport clock/reset instance bindings changed')
    fragments={
        'top.sv':fragment(top,'    wire common_async_reset_n=board_reset_n && trusted_reset_n && app_reset_n;',
            '    wire core_reset_n=core_release_q[2];'),
        'memory.sv':fragment(parent,'    wire common_async_reset_n=trusted_reset_n_i && app_reset_n_i;',
            '    wire app_domain_reset_n=app_release_q[2];'),
        'transport.sv':fragment(transport,'    wire common_reset_n = core_reset_n_i && app_reset_n_i;',
            '    wire app_reset_n = app_release_q[2];')}
    source='''module native_memory_reset_view (
        input wire trusted_clk_i,trusted_reset_n_i,app_clk_i,app_reset_n_i,
        output wire f_common_o,f_domain_o,output wire [2:0] f_release_o
    );
'''+fragments['memory.sv']+'''
    assign f_common_o=common_async_reset_n;
    assign f_domain_o=app_domain_reset_n;
    assign f_release_o=app_release_q;
endmodule
module native_transport_reset_view (
        input wire core_clk_i,core_reset_n_i,app_clk_i,app_reset_n_i,
        output wire f_common_o,f_core_o,f_app_o,
        output wire [2:0] f_core_release_o,f_app_release_o
    );
'''+fragments['transport.sv']+'''
    assign f_common_o=common_reset_n;
    assign f_core_o=core_reset_n;
    assign f_app_o=app_reset_n;
    assign f_core_release_o=core_release_q;
    assign f_app_release_o=app_release_q;
endmodule
module board1_actual_reset_correspondence (
        input wire core_clk,app_clk,trusted_clk,board_reset_n,trusted_reset_n,app_reset_n
    );
'''+fragments['top.sv']+'''
    wire f_memory_common,f_memory_domain,f_transport_common,f_transport_core,f_transport_app;
    wire [2:0] f_memory_release,f_transport_core_release,f_transport_app_release;
    native_memory_reset_view u_memory_reset (
        .trusted_clk_i(trusted_clk),.trusted_reset_n_i(trusted_reset_n),
        .app_clk_i(core_clk),.app_reset_n_i(core_reset_n),
        .f_common_o(f_memory_common),.f_domain_o(f_memory_domain),.f_release_o(f_memory_release));
    native_transport_reset_view u_transport_reset (
        .core_clk_i(core_clk),.core_reset_n_i(core_reset_n),
        .app_clk_i(app_clk),.app_reset_n_i(app_reset_n),
        .f_common_o(f_transport_common),.f_core_o(f_transport_core),.f_app_o(f_transport_app),
        .f_core_release_o(f_transport_core_release),.f_app_release_o(f_transport_app_release));
    logic f_core_released_seen_q;
    always_ff @(posedge core_clk or negedge common_async_reset_n) begin
        if (!common_async_reset_n) f_core_released_seen_q<=0;
        else if (core_reset_n) f_core_released_seen_q<=1;
    end
    always_comb begin
        assert(core_release_q==0 || core_release_q==1 || core_release_q==3 || core_release_q==7);
        assert(f_memory_release==0 || f_memory_release==1 || f_memory_release==3 || f_memory_release==7);
        assert(f_transport_core_release==0 || f_transport_core_release==1 || f_transport_core_release==3 || f_transport_core_release==7);
        assert(f_transport_app_release==0 || f_transport_app_release==1 || f_transport_app_release==3 || f_transport_app_release==7);
        if (core_reset_n) assert(common_async_reset_n);
        assert(f_memory_common==core_reset_n);
        assert(f_transport_common==core_reset_n);
        assert(f_memory_release==f_transport_core_release);
        assert(f_memory_domain==f_transport_core);
        if (common_async_reset_n && f_core_released_seen_q) assert(core_reset_n);
        if (f_memory_domain) assert(f_core_released_seen_q);
        cover(f_memory_domain && f_transport_app);
    end
endmodule
'''
    return source,fragments,dict(memory=expected_m,transport=expected_t)


def main():
    common,engine=load('run_handoff'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=90)
    args=parser.parse_args();reference=None;joins={};native_sources={}
    paths={'top.sv':'project/top.sv','memory.sv':'project/booted_memory.sv','transport.sv':'project/thin_transport.sv'}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,root,bound=common.binding(args.package,variant)
        native={n:(root/p).read_bytes()for n,p in paths.items()}
        source,fragments,bindings=derive(native)
        current=(source,fragments,bindings)
        if reference is not None and current!=reference:raise ValueError('Native reset correspondence differs: '+variant)
        reference=current;joins[variant]=bound
        native_sources[variant]={n:dict(path=paths[n],sha256=common.sha(raw))for n,raw in native.items()}
    source,fragments,bindings=reference
    files={'reset.sv':source.encode(),'runner.py':Path(__file__).read_bytes(),
        'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),'SOURCES.json':(HERE/'SOURCES.json').read_bytes()}
    files.update({'native-fragment-'+n:raw.encode()for n,raw in fragments.items()})
    bound=dict(native_joins=joins,native_sources=native_sources,actual_clock_reset_connections=bindings,
        source_history_reset_equals_transport_core_reset=True,
        transport_common_reset_equals_actual_top_core_reset=True,
        top_core_release_does_not_reassert_without_common_hard_reset=True)
    reset='initial\nassume (= [board_reset_n] false)\nassume (= [trusted_reset_n] false)\nassume (= [app_reset_n] false)\nstate 1\nassume (= [board_reset_n] false)\nassume (= [trusted_reset_n] false)\nassume (= [app_reset_n] false)\n'
    scope=('Exact native top-level core release, memory release and transport release fragments, '
        'with their actual clock/reset instance bindings. All raw reset outputs and independent '
        'clock levels arbitrary. The source memory-history epoch equals the transport core epoch; '
        'the transport common reset equals the native top core reset; the latter cannot drop after '
        'source-domain release without the actual common hard reset. No input protocol/frequency '
        'assumption, vendor reset-generation, physical CDC, payload or whole-machine theorem.')
    raise SystemExit(engine.check(args.run,files,top=TOP,reset_constraints=reset,
        assertions=source.count('assert('),covers=1,binding=bound,scope=scope,cuts=[],
        depth=12,induction_depth=8,cover_depth=32,timeout=args.timeout,expected_memories=0,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},multiclock=True,source_list=['reset.sv']))


if __name__=='__main__':main()

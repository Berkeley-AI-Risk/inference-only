"""Two-copy native RAM history, with arbitrary independent initial payloads.

The only instrumentation is nondriving ports exposing a symbolic RAM row and
the existing read/write enables. A ghost ownership mask is invalidated by
reset/CLEAR. It never constrains inputs or drives either implementation.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REL = ('project/fpga/token_only_model0_ddr_board1/'
       'context2048_token_machine0/rtl/board1_context2048_attention_memories.sv')
SPECS = {
    'query': ('board1_context2048_attention_query8', 5, 8, 16, 8),
    'workspace': ('board1_context2048_attention_workspace3x18', 13, 3, 18, 13),
    'output': ('board1_context2048_attention_vector256x18', 8, 1, 18, 8),
    'accumulator': ('board1_context2048_attention_accumulator8', 5, 8, 38, 5),
    'vector256': ('board1_fixed_semantic_vector256_ram', 8, 1, 16, 8),
    'vector128': ('board1_fixed_semantic_vector128_ram', 7, 1, 16, 7),
    'scratch': ('board1_fixed_semantic_scratch_ram', 10, 1, 16, 10),
    'rope': ('board1_fixed_semantic_rope_raw_ram', 5, 1, 50, 5),
}


def load(name, path):
    spec = importlib.util.spec_from_file_location('_isolation_' + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def derive(package, variant, kind, mutant=None, clear_entry=False):
    bind = load('binding', HERE.parent / 'formal-assurance/run_handoff.py')
    _, root, binding = bind.binding(package, variant)
    module, addr, lanes, width, write_addr = SPECS[kind]
    semantic = kind in ('vector256','vector128','scratch','rope')
    relative = ('project/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/'+module+'.sv') if semantic else REL
    raw = (root / relative).read_bytes()
    found = re.findall(r'^module\s+' + module + r'\b[\s\S]*?^endmodule', raw.decode(), re.M)
    if len(found) != 1:
        raise ValueError('Production module not unique')
    original = found[0]
    source = original
    total = lanes * width
    extra = (f',\n    input wire [{addr-1}:0] f_observed_address_i,\n'
             f'    output wire [{total-1}:0] f_observed_word_o,\n'
             '    output wire f_do_read_o, f_do_write_o\n')
    source = source.replace('\n);', extra + ');', 1)
    if kind in ('query', 'accumulator'):
        before = f'logic [{width-1}:0] payload_mem [0:31];'
        after = before + f'\n        assign f_observed_word_o[lane*{width} +:{width}]=payload_mem[f_observed_address_i];'
        if source.count(before) != 1:
            raise ValueError('Banked payload declaration changed')
        source = source.replace(before, after)
    elif kind == 'workspace':
        source = source.replace('\nendmodule', '\n' + '\n'.join(
            f'    assign f_observed_word_o[{i*18} +:18]=bank{i}_mem[f_observed_address_i];'
            for i in range(3)) + '\nendmodule')
    else:
        source = source.replace('\nendmodule', '\n    assign f_observed_word_o=payload_mem[f_observed_address_i];\nendmodule')
    prefix = 'private_' if semantic else ''
    source = source.replace('\nendmodule', '\n    assign f_do_read_o=' + ('do_read' if kind == 'accumulator' else prefix+'read_enable_i') + ';\n'
                            '    assign f_do_write_o=' + ('do_write' if kind == 'accumulator' else prefix+'write_enable_i') + ';\nendmodule')
    if mutant:
        # Mutate one implementation only. The reference copy and ghost remain.
        broken = source.replace(module, module + '_broken', 1)
        if kind == 'query':
            before = 'if (write_enable_i && write_address_i[2:0]==lane)'
            after = 'if (write_enable_i && write_address_i[2:0]==lane && lane!=0)'
        elif kind == 'accumulator':
            before, after = 'if(do_write)payload_mem', 'if(do_write && lane!=0)payload_mem'
        elif kind == 'workspace':
            before, after = 'bank0_mem[write_address_i] <= bank0_write_data_i;', 'bank0_mem[write_address_i] <= 18\'d0;'
        else:
            before = 'payload_mem['+prefix+'write_address_i] <= '+prefix+'write_data_i;'
            after = 'payload_mem['+prefix+'write_address_i] <= '+str(width)+"'d0;"
        if broken.count(before) != 1:
            raise ValueError('Mutation site changed')
        broken = broken.replace(before, after, 1)
        source += '\n' + broken
    lines = [
        '`default_nettype none',
        f'module native_memory_isolation(input wire clk,rst_n,clear_i,read_enable_i,write_enable_i,',
        f'    input wire [{addr-1}:0] read_address_i,',
        f'    input wire [{write_addr-1}:0] write_address_i,',
        f'    input wire [{(width if kind=="query" else total)-1}:0] write_data_i);',
        f'    (* anyconst *) reg [{addr-1}:0] f_address;',
        f'    wire [{total-1}:0] a_word,b_word,a_read,b_read;',
        '    wire a_do_read,b_do_read,a_do_write,b_do_write;',
    ]
    for copy in ('a', 'b'):
        ports = ['.clk(clk)', '.read_enable_i(read_enable_i)', '.write_enable_i(write_enable_i)',
                 '.read_address_i(read_address_i)', '.write_address_i(write_address_i)',
                 '.f_observed_address_i(f_address)', f'.f_observed_word_o({copy}_word)',
                 f'.f_do_read_o({copy}_do_read)', f'.f_do_write_o({copy}_do_write)']
        if kind == 'workspace':
            ports += [f'.bank{i}_read_data_o({copy}_read[{i*18} +:18])' for i in range(3)]
            ports += [f'.bank{i}_write_data_i(write_data_i[{i*18} +:18])' for i in range(3)]
        else:
            ports += [f'.read_data_o({copy}_read)', '.write_data_i(write_data_i)']
        if semantic:
            ports=[re.sub(r'\.(read_|write_)',r'.private_\1',p) for p in ports]
        if kind == 'accumulator':
            lines += [f'    wire {copy}_valid,{copy}_fault; wire [4:0] {copy}_tag;']
            ports += ['.rst_n(rst_n)', '.clear_i(clear_i)', f'.read_valid_o({copy}_valid)',
                      f'.read_tag_o({copy}_tag)', f'.fault_o({copy}_fault)']
        selected = module + ('_broken' if copy == 'b' and mutant else '')
        lines += [f'    {selected} u_{copy}(' + ','.join(ports) + ');']
    lines += [
        f'    reg [{lanes-1}:0] f_owned;',
        f'    reg [{total-1}:0] f_shadow,f_read_shadow;',
        f'    reg [{lanes-1}:0] f_read_owned;',
        '    reg f_read_target;',
        '    reg f_past_valid=0;',
        '    always @(posedge clk) begin',
        '        f_past_valid<=1;',
        '        if(!rst_n || clear_i) begin f_owned<=0;f_read_owned<=0;f_read_target<=0;end',
        '        else begin',
        '            if(a_do_write && ' + ('write_address_i[7:3]' if kind == 'query' else 'write_address_i') + '==f_address) begin',
    ]
    for lane in range(lanes):
        guard = f'if(write_address_i[2:0]==3\'d{lane}) ' if kind == 'query' else ''
        data = 'write_data_i' if kind == 'query' else f'write_data_i[{lane*width} +:{width}]'
        lines += [f'                {guard}begin f_owned[{lane}]<=1;f_shadow[{lane*width} +:{width}]<={data};end']
    lines += [
        '            end',
        '            if(a_do_read) begin',
        '                f_read_target<=read_address_i==f_address;',
        '                f_read_owned<=f_owned;f_read_shadow<=f_shadow;',
        '            end',
        '        end',
        '        if(f_past_valid && rst_n'+(' && f_address<682' if kind=='scratch' else '')+') begin',
        '            assert(a_do_read==b_do_read);assert(a_do_write==b_do_write);',
    ]
    if kind == 'accumulator':
        lines += ['            assert(a_valid==b_valid);assert(a_fault==b_fault);assert(a_tag==b_tag);']
    for lane in range(lanes):
        sl = f'[{lane*width} +:{width}]'
        lines += [f'            if(f_owned[{lane}]) begin assert(a_word{sl}==f_shadow{sl});assert(b_word{sl}==f_shadow{sl});end',
                  f'            if(f_read_target && f_read_owned[{lane}]) begin assert(a_read{sl}==f_read_shadow{sl});assert(b_read{sl}==f_read_shadow{sl});assert(a_read{sl}==b_read{sl});end']
    lines += ['        end', '        cover(f_past_valid && rst_n && !clear_i && f_read_target && (&f_read_owned));',
              "        cover(f_past_valid && rst_n && !clear_i && f_owned==0 && a_word!=b_word);",
              '    end', 'endmodule', '`default_nettype wire']
    wrapper = '\n'.join(lines) + '\n'
    if clear_entry:
        wrapper=wrapper.replace('    reg f_past_valid=0;',
            '    reg f_past_valid=0,f_joined=0;\n    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i'+
            (' && !a_fault && !b_fault'if kind=='accumulator'else'')+')f_joined<=1;')
        wrapper=wrapper.replace('if(f_past_valid && rst_n', 'if(f_joined && rst_n')
        if kind=='accumulator':
            wrapper=wrapper.replace('assert(a_tag==b_tag);','if(a_valid)assert(a_tag==b_tag);')
            wrapper=wrapper.replace('    end\nendmodule',
                '        cover(f_joined && rst_n && !a_valid && a_tag!=b_tag);\n    end\nendmodule')
    files = {'production-memories.sv': raw, 'memory.sv': ('`undef FORMAL\n'+source+'\n').encode(),
             'wrapper.sv': wrapper.encode(), 'runner.py': Path(__file__).read_bytes()}
    return files, dict(variant=variant, kind=kind, native_join=binding, production_path=relative,
                      native_words=682 if kind=='scratch' else 1 << addr, lanes=lanes, lane_width=width,
                      instrumentation='Nondriving symbolic-row and enable output taps only',
                      independent_initial_payloads=True,healthy_clear_entry=clear_entry)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package', type=Path, required=True)
    ap.add_argument('--variant', default='baseline')
    ap.add_argument('--kind', choices=SPECS, required=True)
    ap.add_argument('--run', type=Path, required=True)
    ap.add_argument('--mutant', choices=('corrupt-one-bank',))
    ap.add_argument('--timeout', type=int, default=60)
    ap.add_argument('--clear-entry',action='store_true')
    args = ap.parse_args()
    files, binding = derive(args.package, args.variant, args.kind, args.mutant,args.clear_entry)
    engine = load('engine', HERE / 'proof_engine.py')
    wrapper = files['wrapper.sv'].decode()
    # Serial query upload must write all eight lanes before a full owned read.
    cover = 14 if args.kind == 'query' else 8
    return engine.check(args.run, files, top='native_memory_isolation',
        reset_constraints=('initial\nassume (= [rst_n] true)\nassume (= [clear_i] true)\n'+
            ('assume (= [a_fault] false)\nassume (= [b_fault] false)\n'if args.kind=='accumulator'else'')+
            'state 1\nassume (= [rst_n] true)\nassume (= [clear_i] true)\n'if args.clear_entry else
            'initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'),
        constraint_scope_description=('No initial hard reset; arbitrary independent native memory and read-register payloads. A common CLEAR initializes only observer ownership (plus native accumulator control). Accumulator sticky faults initially healthy, invalid old read tags may differ. Inputs unrestricted in induction.'if args.clear_entry else None),
        assertions=wrapper.count('assert('), covers=wrapper.count('cover('), binding=binding,
        cuts=[], observer_constants=1, depth=6 if args.mutant else 4, induction_depth=3, cover_depth=cover,
        timeout=args.timeout, mutant=args.mutant, optimize_full=True,
        solver_cli={s:['--unroll'] for s in ('z3','cvc5')},
        source_list=['memory.sv','wrapper.sv'],
        expected_memories=2*(8 if args.kind in ('query','accumulator')else 3 if args.kind=='workspace'else 1),
        scope='Actual native RAMs in two copies with independent arbitrary initial payloads. Current-epoch owned writes determine observed RAM rows and their registered reads; accumulator tags/fault control agree. No read-before-write permission is assumed or established for the parent. This is a conditional leaf isolation lemma, not session-level token-output equivalence.')


if __name__ == '__main__':
    raise SystemExit(main())

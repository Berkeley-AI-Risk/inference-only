"""Source-bound attention workspace ownership; numerical children unrestricted.

Complete children are replaced by free output ports. No child contract is
assumed. This is a parent-control safety proof, composed with native RAM
history separately; it is not a numerical-attention proof.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REL = ('project/fpga/token_only_model0_ddr_board1/'
       'context2048_token_machine0/rtl/board1_context2048_attention.sv')
TOP = 'board1_context2048_attention'


def load(name, path):
    spec = importlib.util.spec_from_file_location('_attention_ownership_' + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def current_state_observer(text):
    """Keep ghost updates clocked; check invariants in their current state.

    Only our observer block is moved. Production text is never passed here.
    This removes assertion-register history from the induction problem.
    """
    match=re.search(r'if\(f_past_valid && rst_n && interface_live\)\s*begin',text)
    if match is None:raise ValueError('Observer guard changed')
    level=1;end=None
    for token in re.finditer(r'\bbegin\b|\bend\b',text[match.end():]):
        level+=1 if token[0]=='begin'else-1
        if level==0:end=match.end()+token.end();break
    if end is None:raise ValueError('Observer block unbalanced')
    block=text[match.start():end].replace('f_past_valid && rst_n && interface_live','rst_n && interface_live',1)
    return text[:match.start()]+text[end:]+'\n    always @*begin\n'+block+'\n    end\n'


def derive(package, variant, monitor_path, mutant=None):
    binder = load('binding', HERE.parent/'formal-assurance/run_handoff.py')
    parser = load('parser', HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _, root, binding = binder.binding(package, variant)
    original = (root/REL).read_bytes()
    source = original.decode()
    top = re.search(r'^module '+TOP+r'\b[\s\S]*?^endmodule', source, re.M)[0]
    definitions = {}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):
            continue
        raw = (root/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule', raw.decode(), re.M):
            if m[1] in definitions and definitions[m[1]][0] != m[0]:
                raise ValueError('Ambiguous module '+m[1])
            definitions[m[1]] = (m[0], name, raw)
    files = {'production-attention.sv': original}
    replacements, additions, cuts = [], [], []
    # Generated arithmetic instances share the explicit free output vector per
    # instance name only where their output expression is an indexed array.
    for match in re.finditer(r'^\s+(board1_\w+)\s+(?:#\([^\n]*\)\s+)?(u_\w+)\s*\(', top, re.M):
        module, instance = match[1], match[2]
        start = match.start(); cursor = match.end(); nesting = 1
        while nesting:
            nesting += (top[cursor]=='(')-(top[cursor]==')'); cursor += 1
        if top[cursor] != ';':
            raise ValueError('Instance terminator changed')
        before = top[start:cursor+1]
        child, relative, raw = definitions[module]
        files['production-child-'+module+'.sv'] = raw
        rows = []
        for port, (direction, shape) in parser.ports(child).items():
            if direction != 'output':
                continue
            expressions = re.findall(r'\.'+re.escape(port)+r'\s*\(([^()]*)\)', before)
            if len(expressions) != 1:
                raise ValueError('Output binding changed '+instance+'.'+port)
            expression = expressions[0].strip()
            if not expression:
                continue
            free = 'f_child_'+instance+'_'+port
            generated = '[mac]' in expression
            if generated:
                width = re.fullmatch(r'(?:signed\s+)?\[(\d+):0\]\s*', shape)
                if not width:
                    raise ValueError('Generated child output width changed')
                bits = int(width[1])+1
                additions.append(f'    input wire [{8*bits-1}:0] {free}')
                rhs = f'{free}[mac*{bits} +:{bits}]'
            else:
                if not re.fullmatch(r'\w+', expression):
                    raise ValueError('Unexpected output expression '+expression)
                additions.append('    input wire '+shape+free)
                rhs = free
            rows.append('    assign '+expression+' = '+rhs+';')
            cuts.append(dict(instance=instance,module=module,port=port,expression=expression,
                             shape=shape,replacement=free,source=relative,assumptions=[]))
        replacements.append((before,'\n'+'\n'.join(rows)))
    if len(replacements) != 12:
        raise ValueError('Attention child census changed: '+str(len(replacements)))
    for before, after in replacements:
        if top.count(before) != 1:
            raise ValueError('Nonunique instance')
        top = top.replace(before,after,1)
    top = top.replace('\n);', ',\n'+',\n'.join(additions)+'\n);',1)
    if mutant == 'skip-query-word':
        before = '(state_q == ST_QUERY_STORE);'
        after = "(state_q == ST_QUERY_STORE) && query_bram_write_address != 8'd0;"
        if top.count(before) != 1:
            raise ValueError('Query write mutation site changed')
        top=top.replace(before,after,1)
    if isinstance(monitor_path,list):
        monitor='\n'.join('generate if(1)begin : f_scope'+str(i)+'\n'+current_state_observer(p.read_text())+
                          '\nend endgenerate'for i,p in enumerate(monitor_path))
    else:
        monitor = current_state_observer(monitor_path.read_text())
    pair_major='// Keep one authenticated head/role page hot while' in original.decode()
    if pair_major:
        expected="attention_head_q <= attention_head_q - 2'd1;\n                            scan_position_q <= scan_position_q + 1'b1;"
    else:
        expected="end else if (attention_head_q == 2'd1) begin\n                            attention_head_q <= 2'd2;\n                            state_q <= ST_SCORE_REQUEST;"
    if original.decode().count(expected)!=1:
        raise ValueError('Raw score traversal no longer matches the native rank function')
    monitor=monitor.replace('__RAW_SCORE_PAIR_MAJOR__',"1'b1"if pair_major else"1'b0")
    top=top.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files['attention.sv']=('`undef FORMAL\n'+top+'\n').encode()
    files['monitor.inc.sv']=monitor.encode()
    files['runner.py']=Path(__file__).read_bytes()
    return files,dict(native_join=binding,variant=variant,production_path=REL,
                      child_instances=len(replacements),raw_score_traversal='pair-position-sibling'if pair_major else'position-head',
                      full_private_inputs_unrestricted=True,observer_evaluation='current-state combinational assertions; clocked nondriving ghost history'),cuts,monitor


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--monitor',type=Path,nargs='+',default=[HERE/'query-ownership-monitor.inc.sv'])
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--mutant',choices=('skip-query-word',))
    ap.add_argument('--timeout',type=int,default=45)
    ap.add_argument('--cover-workspace-write',action='store_true')
    ap.add_argument('--clear-entry',action='store_true')
    args=ap.parse_args()
    files,binding,cuts,monitor=derive(args.package,args.variant,args.monitor,args.mutant)
    if args.clear_entry:
        previous=monitor
        monitor=monitor.replace('if(rst_n && interface_live)', 'if(rst_n && interface_live && f_completed_clear)')
        monitor+='''
    reg f_completed_clear=0;
    always @(posedge clk)begin
        if(!rst_n)f_completed_clear<=0;
        else if(clear_i && state_q==ST_IDLE)f_completed_clear<=1;
        cover(rst_n && f_completed_clear && interface_live && state_q==ST_QUERY_STORE && coordinate_q==2);
    end
'''
        files['attention.sv']=files['attention.sv'].replace(previous.encode(),monitor.encode())
        files['monitor.inc.sv']=monitor.encode()
        binding['initial_hard_reset']=False
        binding['entry_policy']='A common CLEAR while native parent is IDLE enables ownership conclusions; arbitrary old controller state before that edge'
    cover_constraints=None
    cover_depth=12
    if args.cover_workspace_write:
        original_monitor=monitor
        while 'cover('in monitor:
            start=monitor.index('cover(');end=start+len('cover(');nesting=1
            while nesting:
                nesting+=(monitor[end]=='(')-(monitor[end]==')');end+=1
            if monitor[end]!=';':raise ValueError('Cover terminator changed')
            monitor=monitor[:start]+'begin end'+monitor[end+1:]
        monitor+='\n    always @(posedge clk)cover(rst_n && interface_live && workspace_bram_write_enable);\n'
        files['attention.sv']=files['attention.sv'].replace(original_monitor.encode(),monitor.encode())
        files['monitor.inc.sv']=monitor.encode()
        parser=load('cover_parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
        inputs=parser.ports(files['attention.sv'].decode())
        rows=['always']
        for name,(direction,shape)in inputs.items():
            if direction!='input' or name in ('clk','rst_n','query_last_i'):continue
            width=re.search(r'\[(\d+):0\]',shape)
            width=int(width[1])+1 if width else 1
            value=name in ('model_lock_i','start_valid_i','query_valid_i','private_cache_request_ready_i',
                           'private_cache_response_valid_i','f_child_u_value_prefix_read_valid_o')
            rows.append('assume (= ['+name+'] '+(('true'if value else'false')if width==1 else f'(_ bv0 {width})')+')')
        rows.append("assume (= [query_last_i] (= [query_beat_q] #b11))")
        cover_constraints='\n'.join(rows)+'\n'
        cover_depth='260:290'
    engine=load('engine',HERE.parent/'authentication-access/engine.py')
    return engine.check(args.run,files,top=TOP,
        reset_constraints=('initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n'if args.clear_entry else
            'initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'),
        constraint_scope_description='No initial hard reset; old control state arbitrary. Conclusions start after a CLEAR edge while native parent is IDLE. Child replies unrestricted; no extra input assumptions.'if args.clear_entry else None,
        assertions=monitor.count('assert('),covers=monitor.count('cover('),binding=binding,cuts=cuts,
        observer_constants=monitor.count('(* anyconst *)'),depth=10 if args.mutant else 6,induction_depth=4,
        cover_depth=cover_depth,cover_constraints=cover_constraints,timeout=args.timeout,mutant=args.mutant,
        source_list=['attention.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Actual native attention controller and transient registers, full geometry/watchdog, all complete child outputs unrestricted. Read/overwrite ownership only; native RAM history is separately proved. No whole-machine or numerical theorem.')


if __name__=='__main__':
    raise SystemExit(main())

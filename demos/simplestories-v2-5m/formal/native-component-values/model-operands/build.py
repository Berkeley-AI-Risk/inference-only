"""Build the complete native bank and its read-only provenance observer."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from prepare import PROJECT, PUBLIC, BINDING, modules, sha, write_json

TOP = 'board1_verified_page_bank'
S = '|'+TOP+'_s|'


def n(name, state='a'):
    return '(|'+TOP+'_n '+name+'| '+state+')'


def bv(value, width):
    return '(_ bv'+str(value)+' '+str(width)+')'


def conj(items):
    return '(and '+' '.join(items)+')'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--service-compile', action='store_true',
                    help='Compile the actual four-bank caller configuration; no service proof is implied.')
    args = ap.parse_args()
    top = 'board1_verified_ddr_page_service' if args.service_compile else TOP
    pins = json.loads(BINDING.read_text())['binding']['native_join']['distributed_inputs']
    rows = {}; bodies = []
    selection = [('bank.sv', [TOP]), ('sha.sv', ['board1_sha256_bank_owned_compress'])]
    if args.service_compile:
        selection += [('service.sv', [top]), ('top.sv', []), ('uart_core.sv', [])]
    for filename, names in selection:
        data = (PROJECT/filename).read_bytes(); expected = pins['project/'+filename]
        if sha(data) != expected or sha((PUBLIC/filename).read_bytes()) != expected:
            raise ValueError('Frozen source mismatch: '+filename)
        definitions = modules(data.decode())
        rows[filename] = dict(sha256=expected, baseline=str(PROJECT/filename),
                              public_export=str(PUBLIC/filename), modules=names)
        bodies.extend(definitions[name] for name in names)
    build = HERE/('service-project' if args.service_compile else 'project'); build.mkdir(exist_ok=True)
    native = '`undef FORMAL\n`default_nettype none\n'+'\n\n'.join(bodies)+'\n'
    (build/'native.sv').write_text(native)
    commands = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS native.sv']
    tables = {}
    if args.service_compile:
        for filename in ['metadata192.memh','digests32.memh']:
            data = (PROJECT/filename).read_bytes()
            if sha(data) != pins['project/'+filename] or sha((PUBLIC/filename).read_bytes()) != sha(data):
                raise ValueError('Table mismatch: '+filename)
            (build/filename).write_bytes(data)
            tables[filename] = sha(data)
        if '#(.AUTH_BANKS(4)) u_machine' not in (PROJECT/'uart_core.sv').read_text():
            raise ValueError('Actual bank-count specialization changed')
        commands += ['chparam -set BANKS 4 -set ADDR_W 19 '+top]
    recipe = '\n'.join(commands+[
        'hierarchy -check -top '+top,
        *(['rename -top '+top] if args.service_compile else []), 'proc', 'opt_clean',
        'setattr -set keep 1 t:$dff t:$adff t:$dffe t:$adffe t:$sdff t:$sdffe',
        'flatten', 'async2sync', 'opt_clean', 'dffunmap', 'memory_collect',
        'select -assert-none t:$assume t:$assert t:$anyseq t:$anyconst',
        'check -assert', 'write_json native.json', 'write_smt2 -wires native.smt2'])+'\n'
    (build/'compile.ys').write_text(recipe)
    started = time.monotonic()
    with (build/'yosys.log').open('w') as log:
        cp = subprocess.run(['yosys', '-Q', 'compile.ys'], cwd=build, stdout=log,
                            stderr=subprocess.STDOUT, timeout=120)
    if cp.returncode: raise ValueError('Native compilation failed')
    graph = json.loads((build/'native.json').read_text())['modules'][top]
    memories = {name:{key:int(cell['parameters'][key], 2) for key in ['WIDTH', 'SIZE']}
                for name,cell in graph['cells'].items() if cell['type'] == '$mem_v2'}
    manifest = dict(schema='Native-bank-provenance-setup-v1', sources=rows,
        complete_native_bank_hierarchy=True, internal_cuts=[], IMAGE_WORDS=227062,
        REGISTER_RESULT=0, source_sha256=sha(native.encode()),
        native_smt_sha256=sha((build/'native.smt2').read_bytes()), memories=memories,
        compile_seconds=time.monotonic()-started, solver_started=False,
        whole_model_consumption_proved=False)
    if args.service_compile:
        manifest.update(schema='Native-model-service-setup-v1', top=top,
                        production_parameters=dict(BANKS=4,ADDR_W=19,IMAGE_WORDS=227062,
                                                   WEIGHT_WORDS=211800,MAX_OUTSTANDING=32,
                                                   DDR_WATCHDOG_CYCLES=50000000,LOCAL_METADATA=1),
                        tables=tables,complete_native_service_hierarchy=True,service_induction_proved=False)
        write_json(HERE/'SERVICE-SOURCES.json', manifest)
        print('Compiled complete production four-bank service, metadata and expected digests; no service theorem claimed.')
        return
    write_json(HERE/'SOURCES.json', manifest)

    # Arbitrary fixed w ranges over the complete native 7-bit address space.
    # The observer receives no opportunity to choose or overwrite DUT data.
    st = n('state_q'); count = n('fill_count_q'); valid = n('valid_words_q')
    eq = lambda left,right: '(= '+left+' '+right+')'
    phase = lambda value: eq(st, bv(value,4))
    active = '(and (bvuge '+st+' #x1) (bvule '+st+' #x9))'
    sealed = '(and (bvuge '+st+' #x3) (bvule '+st+' #x9))'
    write_watch = conj([n('memory_write'), eq('((_ extract 6 0) '+count+')', 'w')])
    seen_next = '(ite '+n('begin_fire')+' false (or (o-seen h) '+write_watch+'))'
    value_next = '(ite '+write_watch+' (ite '+n('fill_fire')+' '+n('fill_data_i')+' '+bv(0,256)+') (o-word h))'
    pending_next = '(ite (or '+n('cancel_read_i')+' '+n('begin_fire')+') false (or '+n('read_fire')+' (and (o-pending h) (not '+n('response_ready_i')+'))))'
    addr_next = '(ite '+n('read_fire')+' '+n('read_word_i')+' (o-address h))'
    page_next = '(ite '+n('begin_fire')+' '+n('begin_page_i')+' (o-page h))'
    read_page_next = '(ite '+n('read_fire')+' (o-page h) (o-read-page h))'
    clauses = [
        '(bvule '+st+' #x9)',
        '(=> '+phase(0)+' (and (not (o-seen h)) (not (o-pending h))))',
        '(=> '+active+' '+conj(['(bvult '+n('page_o')+' '+bv(1774,11)+')',
            eq(n('page_o'), '(o-page h)'),
            eq(valid, '(ite '+eq(n('page_o'), bv(1773,11))+' '+bv(118,8)+' '+bv(128,8)+')')])+')',
        '(=> '+phase(1)+' '+conj(['(bvult '+count+' '+valid+')', eq('(o-seen h)', '(bvult ((_ zero_extend 1) w) '+count+')')])+')',
        '(=> '+phase(2)+' '+conj(['(bvult '+valid+' '+bv(128,8)+')','(bvuge '+count+' '+valid+')',
            '(bvult '+count+' '+bv(128,8)+')',eq('(o-seen h)', '(bvult ((_ zero_extend 1) w) '+count+')')])+')',
        '(=> '+sealed+' '+conj([eq(count,bv(128,8)), '(o-seen h)'])+')',
        '(=> (o-seen h) '+eq('(select (|'+TOP+'_m memory_q| a) w)', '(o-word h)')+')',
        eq(n('response_valid_q'), '(o-pending h)'),
        '(=> (o-pending h) '+conj([phase(9),eq('(o-read-page h)', '(o-page h)'),
            '(bvult ((_ zero_extend 1) (o-address h)) '+valid+')',
            '(=> '+eq('(o-address h)','w')+' '+conj(['(o-seen h)',eq(n('read_data_q'),'(o-word h)')])+')'])+')',
    ]
    definitions = [
        '(declare-datatypes () ((Origin (origin (o-seen Bool) (o-word (_ BitVec 256)) (o-pending Bool) (o-address (_ BitVec 7)) (o-page (_ BitVec 11)) (o-read-page (_ BitVec 11))))))',
        '(define-fun origin-zero () Origin (origin false '+bv(0,256)+' false '+bv(0,7)+' '+bv(0,11)+' '+bv(0,11)+'))',
        '(define-fun origin-next ((a '+S+') (h Origin) (w (_ BitVec 7))) Origin (ite (not '+n('reset_n')+') origin-zero (origin '+
            ' '.join([seen_next,value_next,pending_next,addr_next,page_next,read_page_next])+')))',
    ]
    for i,clause in enumerate(clauses):definitions.append('(define-fun inv'+str(i)+' ((a '+S+') (h Origin) (w (_ BitVec 7))) Bool '+clause+')')
    failed = conj([eq(st,'#xf'),'(not '+n('response_valid_q')+')','(not '+n('response_valid_o')+')'])
    definitions.append('(define-fun origin-inv ((a '+S+') (h Origin) (w (_ BitVec 7))) Bool (ite '+n('fault_o')+' '+failed+' '+conj(['(inv'+str(i)+' a h w)' for i in range(len(clauses))])+'))')
    meaning = '(=> '+n('response_valid_o')+' '+conj(['(not '+n('fault_o')+')','(o-pending h)',
        eq(n('page_o'),'(o-read-page h)'),'(bvult ((_ zero_extend 1) (o-address h)) '+valid+')',
        '(=> '+eq('(o-address h)','w')+' '+eq(n('response_data_o'),'(o-word h)')+')'])+')'
    definitions.append('(define-fun read-origin ((a '+S+') (h Origin) (w (_ BitVec 7))) Bool '+meaning+')')
    (HERE/'origin.smt2').write_text('\n'.join(definitions)+'\n')
    rules = {
      'reset-base':dict(assumptions=['(not '+n('reset_n')+')',n('reset_n','an'),'(|'+TOP+'_t| a an)'],conclusion='(origin-inv an origin-zero w)'),
      'preserved':dict(assumptions=[n('reset_n'),n('reset_n','an'),'(|'+TOP+'_t| a an)','(origin-inv a h w)','(= hn (origin-next a h w))'],conclusion='(origin-inv an hn w)'),
      'read-value':dict(assumptions=[n('reset_n'),'(origin-inv a h w)'],conclusion='(read-origin a h w)'),
    }
    input_names = ['project/native.sv','project/compile.ys','project/native.smt2','origin.smt2','SOURCES.json']
    write_json(HERE/'PLAN.json', dict(schema='Declarative-native-induction-v1', bodies=['project/native.smt2','origin.smt2'],
        inputs={name:sha((HERE/name).read_bytes()) for name in input_names},
        declarations=['(declare-const a '+S+')','(declare-const an '+S+')','(declare-const h Origin)',
                      '(declare-const hn Origin)','(declare-const w (_ BitVec 7))'],
        order=list(rules),rules=rules,observations=['w']+[n(x,s) for s in ['a','an'] for x in
          ['state_q','fault_o','fill_count_q','valid_words_q','page_o','begin_fire','fill_fire','read_fire','read_word_i','cancel_read_i','response_valid_q','response_ready_i']]+
          ['(inv'+str(i)+' an hn w)' for i in range(len(clauses))]+['h','hn'],
        production_memory_words=128,production_memory_width=256,property='Response value comes from its owned completed page fill; fixed-model identity remains open'))
    print('Built complete native bank, symbolic-address observer and three exact induction obligations.')


if __name__ == '__main__': main()

"""Actual boot wrapper and image authenticator: no arbitrary authentication flags."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_auth_boot_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),default='baseline')
    p.add_argument('--timeout',type=int,default=90)
    p.add_argument('--focus-admission',action='store_true',help='Check the new authentication composition properties; previous write-order theorems retain their separate proofs')
    p.add_argument('--mutant',choices=('counterfeit-auth-success',))
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py')
    builder=load('wrapper',OLD/'run_boot_wrapper.py');boundary=builder.load('run_boot_boundary')
    engine=load('engine',HERE/'engine.py')
    _,directory,bound=common.binding(args.package,args.variant)
    paths=dict(boundary.SOURCES,**{'wrapper.sv':builder.WRAPPER,'async-fifo.sv':'project/fifo.sv',
        'auth.sv':builder.AUTH,'sha.sv':'project/sha.sv'})
    original={n:(directory/path).read_bytes()for n,path in paths.items()}
    # Existing observer ports and scalar boot/boundary invariants are retained;
    # the four prior arbitrary authenticator outputs are all removed again.
    boot=builder.multiclock_boot_monitor((OLD/'boot-order-monitor.inc.sv').read_text())
    boundary_monitor=(OLD/'boot-boundary-monitor.inc.sv').read_text()
    wrapper_monitor=(OLD/'boot-wrapper-monitor.inc.sv').read_text()
    strip_cover=lambda text:re.sub(r'^\s*cover\([^\n]*\);\n','\n',text,flags=re.M)
    boot,boundary_monitor,wrapper_monitor=map(strip_cover,(boot,boundary_monitor,wrapper_monitor))
    if args.focus_admission:
        remove_checks=lambda text:re.sub(r'assert\([^;]*\);',';',text)
        boot,boundary_monitor,wrapper_monitor=map(remove_checks,(boot,boundary_monitor,wrapper_monitor))
    files,instance=builder.instrument(original,boot,boundary_monitor,wrapper_monitor)
    wrapper=files['wrapper.sv'].decode()
    header=',\n'+',\n'.join('    input wire '+r['input']for r in builder.AUTH_CUTS)
    if wrapper.count(header)!=1:raise ValueError('Old flag-cut header changed')
    wrapper=wrapper.replace(header,'',1)
    assignments='\n'.join('    assign '+r['connected_net']+' = '+r['input']+';'for r in builder.AUTH_CUTS)
    actual_instance=instance[:-2]+',\n        .f_observe_admitted_o(f_actual_auth_admitted)\n    );'
    if wrapper.count(assignments)!=1:raise ValueError('Old flag-cut assignments changed')
    wrapper=wrapper.replace(assignments,'    wire f_actual_auth_admitted;\n'+actual_instance,1)
    if any(row['input']in wrapper for row in builder.AUTH_CUTS):raise ValueError('An authentication cut remains')
    join_monitor='''
    always_comb begin
        assert(app_release_q==0 || app_release_q==1 || app_release_q==3 || app_release_q==7);
        assert(trusted_release_q==0 || trusted_release_q==1 || trusted_release_q==3 || trusted_release_q==7);
    end
    // Epoch history of actual trusted-domain admission, not an input promise.
    logic f_auth_success_seen_q;
    always_ff @(posedge trusted_clk_i or negedge common_async_reset_n) begin
        if(!common_async_reset_n) f_auth_success_seen_q<=0;
        else if(trusted_domain_reset_n && auth_digest_done && auth_digest_ok &&
            !auth_fail_closed && !readback_fifo_m_fault) f_auth_success_seen_q<=1;
    end
    always_comb if(common_async_reset_n) begin
        if(f_auth_success_seen_q) assert(trusted_domain_reset_n && f_actual_auth_admitted);
        if(auth_digest_ok) assert(f_actual_auth_admitted);
        if(digest_success_trusted_q) assert(f_auth_success_seen_q && f_actual_auth_admitted);
        if(digest_success_sync1_q) assert(f_auth_success_seen_q && f_actual_auth_admitted);
        if(digest_success_sync2_q) assert(f_auth_success_seen_q && f_actual_auth_admitted);
        if(boundary_model_locked) assert(f_auth_success_seen_q && f_actual_auth_admitted);
        if(model_locked_o) assert(f_auth_success_seen_q && f_actual_auth_admitted);
        cover(loader_accept);
    end
'''
    wrapper=wrapper.replace('\nendmodule','\n'+join_monitor+'\nendmodule',1)
    files['wrapper.sv']=wrapper.encode()
    caller_name={'baseline':'image-auth-baseline-r4-once','seeded-sampling':'image-auth-baseline-r4-once',
        'kv-protected':'image-auth-protected-r2-once','encrypted-memory':'image-auth-encrypted-r2-once'}[args.variant]
    caller=HERE/'runs'/caller_name
    if (caller/'production-auth.sv').read_bytes()!=original['auth.sv']:
        raise ValueError('Selected caller/source identity differs')
    auth=(caller/'auth.sv').read_text()
    if args.mutant:
        for before,after in(('assign digest_done_o = done_q;',"assign digest_done_o = 1'b1;"),
            ('assign digest_ok_o = done_q && ok_q && !fail_q;','assign digest_ok_o = !fail_q;')):
            if auth.count(before)!=1:raise ValueError('Actual authentication-output mutation site changed')
            auth=auth.replace(before,after,1)
    # Clocked assertion enable/history registers may be arbitrary while that
    # clock remains stopped in a multiclock induction trace. Check the same
    # state invariants continuously, and express stickiness using epoch latches.
    before='''    logic f_past_valid=0;
    always_ff @(posedge trusted_clk_i) begin
        f_past_valid<=1;
'''
    if auth.count(before)!=1:raise ValueError('Caller invariant block changed')
    auth=auth.replace(before,'    always_comb begin\n',1)
    before='''            if(f_past_valid && $past(trusted_reset_n_i)) begin
                if($past(fail_q)) assert(fail_q);
                if($past(digest_ok_o) && !fail_q) assert(digest_ok_o);
            end
'''
    if auth.count(before)!=1:raise ValueError('Caller sticky properties changed')
    auth=auth.replace(before,'',1)
    sticky='''
    logic f_failure_epoch_q,f_success_epoch_q;
    always_ff @(posedge trusted_clk_i or negedge trusted_reset_n_i) begin
        if(!trusted_reset_n_i) begin f_failure_epoch_q<=0;f_success_epoch_q<=0;end
        else begin
            if(fail_q) f_failure_epoch_q<=1;
            if(digest_ok_o) f_success_epoch_q<=1;
        end
    end
    always_comb if(trusted_reset_n_i) begin
        if(f_failure_epoch_q) assert(fail_q);
        if(f_success_epoch_q && !fail_q) assert(digest_ok_o);
        // INIT can persist indefinitely when the trusted clock stops. Its
        // reset-only origin must constrain the payload-valid bits as well.
        if(state_q==ST_INIT) assert(!word_buffer_valid_q && word_byte_q==0 && !word_buffer_final_q);
    end
'''
    auth=auth.replace('\nendmodule','\n'+sticky+'\nendmodule',1)
    if auth.count('\n);')!=1:raise ValueError('Authenticator observation port boundary changed')
    auth=auth.replace('\n);',',\n    output wire f_observe_admitted_o\n);',1)
    admission='''
    assign f_observe_admitted_o=f_digest_match_seen_q &&
        f_words_q==19'd227062 && f_payload_bytes_q==24'd7265984 && f_padding_bytes_q==7'd64;
'''
    auth=auth.replace('\nendmodule','\n'+admission+'\nendmodule',1)
    auth=strip_cover(auth)
    files.update({'auth.sv':auth.encode(),'sha.sv':b'`undef FORMAL\n'+original['sha.sv'],
        **{'production-'+n:raw for n,raw in original.items()},'join-monitor.inc.sv':join_monitor.encode(),
        'auth-monitor.inc.sv':(caller/'monitor.inc.sv').read_bytes(),
        'runner.py':Path(__file__).read_bytes(),'wrapper_builder.py':(OLD/'run_boot_wrapper.py').read_bytes(),
        'boundary_builder.py':(OLD/'run_boot_boundary.py').read_bytes(),
        'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),'SOURCES.json':(OLD/'SOURCES.json').read_bytes()})
    assertions=1+sum(text.count('assert(')for text in(boot,boundary_monitor,wrapper_monitor,join_monitor,
        (caller/'monitor.inc.sv').read_text()))
    cover='\n'.join(line for line in builder.cover_stimulus().splitlines()if 'f_auth_cut_'not in line)+'\n'
    reset='initial\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\nstate 1\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\n'
    binding=dict(native_join=bound,variant=args.variant,production_sources={n:dict(path=paths[n],sha256=hashlib.sha256(raw).hexdigest())for n,raw in original.items()},
        authentication_flags_arbitrary=False,complete_actual_image_auth_and_sha=True,
        original_model_words=227062,readback_cdc_width=257,readback_cdc_depth=4,
        admission_observer_has_no_production_fanout=True,common_reset_and_both_clocks_retained=True)
    binding['prior_write_order_properties_rechecked_here']=not args.focus_admission
    return engine.check(args.run,files,top=builder.TOP,reset_constraints=reset,
        assertions=assertions,covers=1,binding=binding,cuts=[],depth=32 if args.mutant else 12,induction_depth=8,
        cover_depth=48,cover_constraints=cover,timeout=args.timeout,
        source_list=['boot.sv','fifo.sv','adapter.sv','boundary.sv','async-fifo.sv','wrapper.sv','auth.sv','sha.sv'],
        solver_cli={s:['--unroll']for s in('z3','cvc5')},multiclock=True,
        map_literal_roms=True,optimize_full=True,mutant=args.mutant,
        scope='Complete actual boot controller/boundary/wrapper, readback FIFO, actual image authenticator and SHA child. Runtime LOCK requires real native-count, padding and matching-digest admission in the common reset epoch; no arbitrary authenticator flag inputs. Arbitrary clocks, stalls, data, requests and resets under digital clock-edge semantics. No full native-length successful LOCK reachability, physical CDC/metastability, cryptographic-hardness or bitstream theorem. Component SHA algorithm correspondence and fixed source bytes have separate proofs.')


if __name__=='__main__':raise SystemExit(main())

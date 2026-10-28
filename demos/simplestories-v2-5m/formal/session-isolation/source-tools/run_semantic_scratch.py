"""Native semantic scratch initialization before reads, per layer epoch."""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    ap.add_argument('--clear-entry',action='store_true')
    args=ap.parse_args()
    builder=load('datapath',HERE.parent/'authentication-access/run_datapath_access.py')
    files,binding,cuts,original_monitor=builder.derive(args.package,args.variant)
    monitor=(HERE/'semantic-scratch-monitor.inc.sv').read_text()+'\n'+(HERE/'semantic-metadata-monitor.inc.sv').read_text()
    if args.clear_entry:
        previous=original_monitor
        original_monitor=original_monitor.replace('if (rst_n) begin','if (rst_n && f_completed_clear) begin')
        if previous==original_monitor:raise ValueError('Original access observer guard changed')
        files['datapath.sv']=files['datapath.sv'].replace(previous.encode(),original_monitor.encode())
        files['monitor.inc.sv']=original_monitor.encode()
        monitor=monitor.replace('always @*if(rst_n && !clear_i && !fault_q)',
            'always @*if(rst_n && !clear_i && !fault_q && f_completed_clear)')
        monitor+='\n    reg f_completed_clear=0;\n    always @(posedge clk)if(!rst_n)f_completed_clear<=0;else if(clear_i)f_completed_clear<=1;\n'
        binding['initial_hard_reset']=False
    files['datapath.sv']=files['datapath.sv'].replace(b'\nendmodule',b'\n'+monitor.encode()+b'\nendmodule',1)
    files['scratch-monitor.inc.sv']=monitor.encode();files['scratch-runner.py']=Path(__file__).read_bytes()
    engine=load('engine',HERE.parent/'authentication-access/engine.py')
    return engine.check(args.run,files,top='native_datapath_access',
        reset_constraints=('initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n'if args.clear_entry else
            'initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'),
        assertions=original_monitor.count('assert(')+monitor.count('assert('),
        covers=original_monitor.count('cover('),observer_constants=monitor.count('(* anyconst *)'),binding=binding,cuts=cuts,
        depth=6,induction_depth=4,cover_depth=12,timeout=args.timeout,
        source_list=['datapath.sv','wrapper.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Actual native semantic datapath controller. Per-layer first initialization before RAM reads for RMS, Q/K/V, attention, output and gate/up memories; per-head RoPE raw scratch initialization and registered consumption. All complete child outputs unrestricted. Read-data history, hidden ingress and numerical-service session contracts are separate. No whole-device session or numerical theorem.')


if __name__=='__main__':raise SystemExit(main())

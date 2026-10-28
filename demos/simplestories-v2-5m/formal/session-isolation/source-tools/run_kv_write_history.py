"""Baseline/seeded native staging-prefetch history through actual typed writes."""
import argparse
import json
from pathlib import Path

from run_attention_ownership import HERE, load
from run_kv_session_drain import TOP


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45);args=ap.parse_args()
    prior=HERE/'runs/kv-cached-row-owner-r1';pi=json.loads((prior/'INPUTS.json').read_text())
    engine=load('engine',HERE/'proof_engine.py');files={}
    for n,row in pi['files'].items():
        raw=(prior/n).read_bytes()
        if engine.sha(raw)!=row['sha256']:raise ValueError('Frozen cache source changed')
        files[n]=raw
    source=files[TOP+'.sv'].decode()
    monitor='''
    reg f_rd_live=0,f_rd_staged_target=0;
    reg [4:0] f_rd_address;
    reg [31:0] f_rd_staged_expected;
    wire [4:0] f_staged_address=5'd8+{1'b0,f_coordinate[6:3]};
    wire [31:0] f_staged_read_pair=cache_read_data_q[f_coordinate[2:0]*32 +:32];
    always @(posedge clk)begin
        if(!reset_n || clear_i || f_begin || f_commit)begin f_rd_live<=0;f_rd_staged_target<=0;end
        else if(f_epoch && store_read_enable)begin
            f_rd_live<=1;f_rd_address<=store_read_address;
            f_rd_staged_target<=store_read_address==f_staged_address;
            f_rd_staged_expected<=f_staged_pair;
        end
    end
    always @*if(reset_n && !f_epoch)assert(!f_rd_live && !f_rd_staged_target);
    always @*if(f_healthy)begin
        if(state_q==ST_STAGE)assert(!f_rd_live && !f_rd_staged_target);
        if(state_q==ST_WRITE_META && !clear_i)assert(write_word_q==8);
        if(state_q==ST_WRITE_PACK && !clear_i)assert(write_word_q<8);
        if(f_rd_live && f_rd_staged_target)assert(f_staged_read_pair==f_rd_staged_expected);
        if(f_rd_live && f_rd_staged_target && f_stage_live && f_full)
            assert(f_rd_staged_expected=={f_value,f_key});
        if(state_q==ST_WRITE_PREFETCH_B && !clear_i)begin
            assert(f_rd_live && f_rd_address==5'd8+{write_word_q,1'b0});
            assert(f_rd_staged_target==(f_coordinate[6:3]=={write_word_q[2:0],1'b0}));
        end
        if(state_q==ST_WRITE_PACK && !clear_i)begin
            assert(f_rd_live && f_rd_address==5'd9+{write_word_q,1'b0});
            assert(f_rd_staged_target==(f_coordinate[6:3]=={write_word_q[2:0],1'b1}));
        end
        if(state_q==ST_WRITE_PACK && !clear_i && !f_coordinate[3] && write_word_q=={1'b0,f_coordinate[6:4]})
            assert(write_offer_q[f_coordinate[3:0]*16 +:16]==(write_head_q ? f_value : f_key));
        if((state_q==ST_WRITE_REQ || state_q==ST_WRITE_WAIT) && !write_aborted_q)begin
            if(write_word_q<8 && write_word_q[2:0]==f_coordinate[6:4])
                assert(write_offer_q[f_coordinate[3:0]*16 +:16]==(write_head_q ? f_value : f_key));
            if(write_word_q==8)assert(write_offer_q=={240'd0,write_head_q ? f_value_exponents : f_key_exponents});
        end
        if(kv_write_req_valid_o)begin
            assert(f_stage_live && f_full && f_written);
            if(kv_write_req_row_word_o<8 && kv_write_req_row_word_o[2:0]==f_coordinate[6:4])
                assert(kv_write_req_data_o[f_coordinate[3:0]*16 +:16]==(kv_write_req_head_o[0] ? f_value : f_key));
            if(kv_write_req_row_word_o==8)
                assert(kv_write_req_data_o=={240'd0,kv_write_req_head_o[0] ? f_value_exponents : f_key_exponents});
        end
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files[TOP+'.sv']=source.encode();files['typed-write-history-monitor.inc.sv']=monitor.encode()
    files['typed-write-history-runner.py']=Path(__file__).read_bytes()
    files['wrapper.sv']=files['wrapper.sv'].replace(b'module native_kv_cached_row(',b'module native_kv_write_history(',1)
    return engine.check(args.run,files,top='native_kv_write_history',
        reset_constraints=(prior/'reset.smtc').read_text(),cover_constraints=(prior/'cover.smtc').read_text(),
        assertions=pi['assertion_cells']+monitor.count('assert('),covers=pi['cover_cells'],
        binding=dict(pi['binding'],native_staging_prefetch_and_typed_write_history=True),cuts=[],
        depth=2,induction_depth=1,cover_depth=6,timeout=args.timeout,
        source_list=pi['compile_sources'],optimize_full=True,observer_constants=1,
        primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual baseline/seeded native staging RAM, synchronous read registers, write-prefetch/pack/meta controller and typed write data, with committed cache ownership retained. Every exposed typed payload coordinate/exponent equals its current legal stage writer after logical CLEAR. No physical reset or old payload equality. Short formal stage-entry covers plus separate full native stage/write/cache simulation; attention assembly/output and outer/device composition remain separate.')


if __name__=='__main__':raise SystemExit(main())

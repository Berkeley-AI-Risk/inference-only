"""Baseline/seeded committed-kind cache: fresh full fill and exact RAM history."""
import argparse
import json
from pathlib import Path

from run_attention_ownership import HERE, load
from run_kv_session_drain import TOP


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45);args=ap.parse_args()
    prior=HERE/'runs/kv-staging-owner-baseline-r4';pi=json.loads((prior/'INPUTS.json').read_text())
    engine=load('engine',HERE/'proof_engine.py');files={}
    for n,row in pi['files'].items():
        raw=(prior/n).read_bytes()
        if engine.sha(raw)!=row['sha256']:raise ValueError('Frozen staging source changed')
        files[n]=raw
    source=files[TOP+'.sv'].decode();before='logic [31:0] words [0:31];'
    observation="assign f_cached_words[bank*32 +:32]=words[{2'b00,f_cache_word}];"
    if source.count(before)!=1:raise ValueError('Native cache RAM declaration changed')
    source=source.replace(before,before+'\n        '+observation,1)
    monitor='''
    wire [2:0] f_cache_word=f_coordinate[6:4];
    wire [255:0] f_cached_words;
    wire [31:0] f_cached_pair=f_cached_words[f_coordinate[3:1]*32 +:32];
    reg f_cache_active=0,f_cache_written=0,f_metadata_written=0;
    reg [8:0] f_cache_mask=0;
    reg [31:0] f_cache_expected;
    reg [15:0] f_metadata_expected;
    wire f_attention_take=attention_req_valid_i && attention_req_ready_o &&
        attention_request_legal && !terminal_fault_event;
    wire f_second_kind=reset_n && state_q==ST_CACHE_READ && cache_read_pending_q &&
        !read_abort_now && cache_response_match && cache_returned_q==3 &&
        response_kind_q==REQ_FULL_KV && !cache_copy_kind_q;
    wire f_cache_restart=(f_attention_take && !attention_request_pending && !cache_request_match) || f_second_kind;
    always @(posedge clk)begin
        if(!reset_n || clear_i || f_begin || f_commit)begin
            f_cache_active<=0;f_cache_written<=0;f_metadata_written<=0;f_cache_mask<=0;
        end else if(f_epoch)begin
            if(f_cache_restart)begin
                f_cache_active<=1;f_cache_written<=0;f_metadata_written<=0;f_cache_mask<=0;
            end
            if(healthy_fill_return)begin
                f_cache_mask[read_return_word_q]<=1;
                if(read_return_word_q<8 && read_return_word_q[2:0]==f_cache_word)begin
                    f_cache_written<=1;
                    f_cache_expected<=kv_read_rsp_data_i[f_coordinate[3:1]*32 +:32];
                end
                if(read_return_word_q==8)begin
                    f_metadata_written<=1;f_metadata_expected<=kv_read_rsp_data_i[15:0];
                end
            end
        end
    end
    always @*if(reset_n && !f_epoch)begin
        assert(!f_cache_active && !f_cache_written && !f_metadata_written && f_cache_mask==0);
    end
    always @*if(f_healthy)begin
        if(f_cache_written)assert(f_cached_pair==f_cache_expected);
        if(f_metadata_written)assert(cache_metadata_q==f_metadata_expected);
        assert(f_cache_written==f_cache_mask[f_cache_word]);
        assert(f_metadata_written==f_cache_mask[8]);
        if(read_collect_state && !read_aborted_q && !read_abort_now)begin
            assert(f_cache_active);
            assert(read_epoch_q==cache_epoch_q);
            assert(read_return_word_q<=8);
            assert(read_received_mask_q==f_cache_mask);
        end
        if(cache_valid_q)begin
            assert(f_cache_active && f_cache_mask==9'h1ff && f_cache_written && f_metadata_written);
            assert(cache_tag_epoch_q==cache_epoch_q && read_epoch_q==cache_epoch_q);
        end
        if(cache_read_enable)assert(cache_valid_q && f_cache_mask==9'h1ff && f_cache_written && f_metadata_written);
        if(healthy_fill_return)assert(f_cache_active && read_return_word_q<=8);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files[TOP+'.sv']=source.encode();files['cached-row-monitor.inc.sv']=monitor.encode()
    files['cached-row-observation.inc.sv']=observation.encode();files['cached-row-runner.py']=Path(__file__).read_bytes()
    files['wrapper.sv']=files['wrapper.sv'].replace(b'module native_kv_staging(',b'module native_kv_cached_row(',1)
    return engine.check(args.run,files,top='native_kv_cached_row',
        reset_constraints=(prior/'reset.smtc').read_text(),cover_constraints=(prior/'cover.smtc').read_text(),
        assertions=pi['assertion_cells']+monitor.count('assert('),covers=pi['cover_cells'],
        binding=dict(pi['binding'],cached_row_source_class=['baseline','seeded-sampling'],
            current_reply_history_without_payload_cut=True,
            scope_extension='Full native committed-kind row RAM: all nine data/metadata returns before cache validity; exact current-fill data at every symbolic coordinate. Staging proof retained. Short covers remain stage-entry covers; committed cache exercise is a separate native simulation obligation.'),
        cuts=[],depth=2,induction_depth=1,cover_depth=6,timeout=args.timeout,
        source_list=pi['compile_sources'],optimize_full=True,observer_constants=1,
        primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual baseline/seeded staged-pair and committed-kind cache RAMs, native read pipeline and mapper. Logical CLEAR revokes prior ownership. A valid cached row has all nine current fill returns and each actual symbolic RAM word/metadata equals its current reply writer; cache reads require that initialization. Assembly/output correspondence and whole-device/outer transport composition remain separate.')


if __name__=='__main__':raise SystemExit(main())

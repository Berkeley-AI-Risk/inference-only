; From staging to the record: the staging facts about one cycle.
;
; Written by make_producer_book.py; do not edit.  Private.
;
; This book imports the certified write-record book (../kv-write-record) and
; proves four facts about one cycle of the K/V controller while a record is
; being staged, from the hypotheses of the imported step lemmas: the joined
; control invariant, the payload invariant and the environment in one cycle.
;   stg-fact-entry   staging is entered only from idle by an accepted begin,
;                    which sets the record's layer, position and exponent
;                    registers from the datapath
;   stg-fact-stay    while staging lasts: no CLEAR, no other begin, those
;                    registers unchanged, each accepted transfer is for the
;                    expected coordinate and advances it by one
;   stg-fact-last    staging ends in the record's start only by the transfer
;                    for coordinate 127
;   stg-fact-begin   a begin is accepted only when idle, and starts a staging
; They need the controller's stage_begin_ready_o and stage_begin_legal, which
; the certified step run does not name.  So the step run here,
; staging-step-run, is the certified payload-step-run, stage for stage and
; name for name, with those two signals added to its outputs.  The RTL and
; its translation are the imported books'; nothing is read from disk here.
(in-package "SV")
(include-book "../kv-write-record/kv-write-record")

(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
; The library's generated lemmas about a run with several hundred named
; signals nest deeper than the rewriter's default limit of 1000.
(acl2::set-rewrite-stack-limit 20000)

; The SAT solver, as in the imported books.  No answer of the solver is
; believed: with :lrat-check t the library reports "unsatisfiable" only
; after ACL2 has run its verified checker (projects/sat/lrat) on the proof
; the solver wrote, against the formula ACL2 itself wrote; "satisfiable"
; only after ACL2 has evaluated the formula under the assignment.
(defun prod-satlink-config ()
  (declare (xargs :guard t))
  (satlink::make-config :cmdline "sh sat/cadical-lrat.sh" :verbose nil
                        :mintime 0 :remove-temps t :lrat-check t))
(defthm kv-producer-to-record-sat-proofs-are-checked
  (equal (satlink::config->lrat-check (prod-satlink-config)) t)
  :rule-classes nil)
(defattach fgl::fgl-satlink-config prod-satlink-config)
(value-triple (acl2::tshell-ensure))

; ===========================================================================
; The step run.
; ===========================================================================
(defsvtv$ staging-step-run
  :design *sv-design*
  :cycle-phases (list (make-svtv-cyclephase
                       :constants '(("core_clk_i" . 1) ("app_clk_i" . 1)
                                    ("reset_n_i" . 1) ("clear_i" . 0)))
                      (make-svtv-cyclephase
                       :constants '(("core_clk_i" . 0) ("app_clk_i" . 0))
                       :inputs-free t :outputs-captured t))
  :stages ((:label curr
            :inputs (("reset_n_i" i-reset-n)
                     ("clear_i" i-clear)
                     ("private_model_locked_i" 1))
            :overrides (
             ("model_lock_core_meta_q" r-p-lock-meta :cond c-p-lock-meta :output p-p-lock-meta)
             ("model_lock_core_sync_q" r-p-lock-sync :cond c-p-lock-sync :output p-p-lock-sync)
             ("core_fault_to_boundary_q" r-p-cfb :cond c-p-cfb :output p-p-cfb)
             ("app_runtime_release_q" r-p-apprel :cond c-p-apprel :output p-p-apprel)
             ("u_machine.machine_release_q" r-m-rel :cond c-m-rel :output p-m-rel)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" r-k-state-q :cond c-k-state-q :output p-k-state-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_issued_q" r-k-pending-issued-q :cond c-k-pending-issued-q :output p-k-pending-issued-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_returned_q" r-k-pending-returned-q :cond c-k-pending-returned-q :output p-k-pending-returned-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_read_pending_q" r-k-pending-read-pending-q :cond c-k-pending-read-pending-q :output p-k-pending-read-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.committed_prefix_q" r-k-committed-prefix-q :cond c-k-committed-prefix-q :output p-k-committed-prefix-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_layer_q" r-k-pending-layer-q :cond c-k-pending-layer-q :output p-k-pending-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_position_q" r-k-pending-position-q :cond c-k-pending-position-q :output p-k-pending-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_key_exponents_q" r-k-pending-key-exponents-q :cond c-k-pending-key-exponents-q :output p-k-pending-key-exponents-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_value_exponents_q" r-k-pending-value-exponents-q :cond c-k-pending-value-exponents-q :output p-k-pending-value-exponents-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.expected_coordinate_q" r-k-expected-coordinate-q :cond c-k-expected-coordinate-q :output p-k-expected-coordinate-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_persisted_q" r-k-pending-persisted-q :cond c-k-pending-persisted-q :output p-k-pending-persisted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_head_q" r-k-write-head-q :cond c-k-write-head-q :output p-k-write-head-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_word_q" r-k-write-word-q :cond c-k-write-word-q :output p-k-write-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_aborted_q" r-k-write-aborted-q :cond c-k-write-aborted-q :output p-k-write-aborted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_kind_q" r-k-response-kind-q :cond c-k-response-kind-q :output p-k-response-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_head_q" r-k-response-head-q :cond c-k-response-head-q :output p-k-response-head-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_layer_q" r-k-response-layer-q :cond c-k-response-layer-q :output p-k-response-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_position_q" r-k-response-position-q :cond c-k-response-position-q :output p-k-response-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_fault_q" r-k-response-fault-q :cond c-k-response-fault-q :output p-k-response-fault-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_from_pending_q" r-k-response-from-pending-q :cond c-k-response-from-pending-q :output p-k-response-from-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_word_q" r-k-read-word-q :cond c-k-read-word-q :output p-k-read-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_return_word_q" r-k-read-return-word-q :cond c-k-read-return-word-q :output p-k-read-return-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_outstanding_q" r-k-read-outstanding-q :cond c-k-read-outstanding-q :output p-k-read-outstanding-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_issue_done_q" r-k-read-issue-done-q :cond c-k-read-issue-done-q :output p-k-read-issue-done-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_aborted_q" r-k-read-aborted-q :cond c-k-read-aborted-q :output p-k-read-aborted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_physical_kind_q" r-k-read-physical-kind-q :cond c-k-read-physical-kind-q :output p-k-read-physical-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_epoch_q" r-k-read-epoch-q :cond c-k-read-epoch-q :output p-k-read-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_received_mask_q" r-k-read-received-mask-q :cond c-k-read-received-mask-q :output p-k-read-received-mask-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_valid_q" r-k-cache-valid-q :cond c-k-cache-valid-q :output p-k-cache-valid-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_kind_q" r-k-cache-kind-q :cond c-k-cache-kind-q :output p-k-cache-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_layer_q" r-k-cache-layer-q :cond c-k-cache-layer-q :output p-k-cache-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_position_q" r-k-cache-position-q :cond c-k-cache-position-q :output p-k-cache-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_tag_epoch_q" r-k-cache-tag-epoch-q :cond c-k-cache-tag-epoch-q :output p-k-cache-tag-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_epoch_q" r-k-cache-epoch-q :cond c-k-cache-epoch-q :output p-k-cache-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_clear_seen_q" r-k-cache-clear-seen-q :cond c-k-cache-clear-seen-q :output p-k-cache-clear-seen-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_issued_q" r-k-cache-issued-q :cond c-k-cache-issued-q :output p-k-cache-issued-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_returned_q" r-k-cache-returned-q :cond c-k-cache-returned-q :output p-k-cache-returned-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_read_pending_q" r-k-cache-read-pending-q :cond c-k-cache-read-pending-q :output p-k-cache-read-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_copy_kind_q" r-k-cache-copy-kind-q :cond c-k-cache-copy-kind-q :output p-k-cache-copy-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.lock_seen_q" r-k-lock-seen-q :cond c-k-lock-seen-q :output p-k-lock-seen-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.fault_q" r-k-fault-q :cond c-k-fault-q :output p-k-fault-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_consumed_q" r-k-stage-begin-consumed-q :cond c-k-stage-begin-consumed-q :output p-k-stage-begin-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_consumed_q" r-k-stage-payload-consumed-q :cond c-k-stage-payload-consumed-q :output p-k-stage-payload-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.commit_consumed_q" r-k-commit-consumed-q :cond c-k-commit-consumed-q :output p-k-commit-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_consumed_q" r-k-attention-req-consumed-q :cond c-k-attention-req-consumed-q :output p-k-attention-req-consumed-q)
             ("u_boundary.core_release_q" r-b-crel :cond c-b-crel :output p-b-crel)
             ("u_boundary.app_release_q" r-b-arel :cond c-b-arel :output p-b-arel)
             ("u_boundary.model_lock_core_meta_q" r-b-lock-meta :cond c-b-lock-meta :output p-b-lock-meta)
             ("u_boundary.model_lock_core_sync_q" r-b-lock-sync :cond c-b-lock-sync :output p-b-lock-sync)
             ("u_boundary.app_fault_core_meta_q" r-b-afc-meta :cond c-b-afc-meta :output p-b-afc-meta)
             ("u_boundary.app_fault_core_sync_q" r-b-afc-sync :cond c-b-afc-sync :output p-b-afc-sync)
             ("u_boundary.core_fault_app_meta_q" r-b-cfa-meta :cond c-b-cfa-meta :output p-b-cfa-meta)
             ("u_boundary.core_fault_app_sync_q" r-b-cfa-sync :cond c-b-cfa-sync :output p-b-cfa-sync)
             ("u_boundary.core_fault_q" r-b-fault :cond c-b-fault :output p-b-fault)
             ("u_boundary.core_lock_seen_q" r-b-lock-seen :cond c-b-lock-seen :output p-b-lock-seen)
             ("u_boundary.core_clear_seen_q" r-b-clr-seen :cond c-b-clr-seen :output p-b-clr-seen)
             ("u_boundary.core_clear_pending_q" r-b-clr-pend :cond c-b-clr-pend :output p-b-clr-pend)
             ("u_boundary.core_clear_drained_o" r-b-clr-drained :cond c-b-clr-drained :output p-b-clr-drained)
             ("u_boundary.core_epoch_q" r-b-epoch :cond c-b-epoch :output p-b-epoch)
             ("u_boundary.core_outstanding_q" r-b-out :cond c-b-out :output p-b-out)
             ("u_boundary.model_rsp_stalled_q" r-b-mstall :cond c-b-mstall :output p-b-mstall)
             ("u_boundary.kv_write_cpl_stalled_q" r-b-wstall :cond c-b-wstall :output p-b-wstall)
             ("u_boundary.kv_write_cpl_stalled_fault_q" r-b-wstallf :cond c-b-wstallf :output p-b-wstallf)
             ("u_boundary.kv_read_rsp_stalled_q" r-b-rstall :cond c-b-rstall :output p-b-rstall)
             ("u_boundary.request_fifo_i.write_binary_q" r-q-wb :cond c-q-wb :output p-q-wb)
             ("u_boundary.request_fifo_i.write_gray_q" r-q-wg :cond c-q-wg :output p-q-wg)
             ("u_boundary.request_fifo_i.write_full_q" r-q-full :cond c-q-full :output p-q-full)
             ("u_boundary.request_fifo_i.read_binary_q" r-q-rb :cond c-q-rb :output p-q-rb)
             ("u_boundary.request_fifo_i.read_gray_q" r-q-rg :cond c-q-rg :output p-q-rg)
             ("u_boundary.request_fifo_i.read_gray_sync1_q" r-q-rs1 :cond c-q-rs1 :output p-q-rs1)
             ("u_boundary.request_fifo_i.read_gray_sync2_q" r-q-rs2 :cond c-q-rs2 :output p-q-rs2)
             ("u_boundary.request_fifo_i.write_gray_sync1_q" r-q-ws1 :cond c-q-ws1 :output p-q-ws1)
             ("u_boundary.request_fifo_i.write_gray_sync2_q" r-q-ws2 :cond c-q-ws2 :output p-q-ws2)
             ("u_boundary.request_fifo_i.m_valid_q" r-q-mv :cond c-q-mv :output p-q-mv)
             ("u_boundary.request_fifo_i.source_fault_q" r-q-sf :cond c-q-sf :output p-q-sf)
             ("u_boundary.request_fifo_i.source_payload_fault_q" r-q-spf :cond c-q-spf :output p-q-spf)
             ("u_boundary.request_fifo_i.destination_fault_q" r-q-df :cond c-q-df :output p-q-df)
             ("u_boundary.request_fifo_i.source_stalled_q" r-q-st :cond c-q-st :output p-q-st)
             ("u_boundary.request_fifo_i.m_data_q[317:315]" r-q-md :cond c-q-md :output p-q-md)
             ("u_boundary.request_fifo_i.memory_q[0][317:315]" r-q-mem0 :cond c-q-mem0 :output p-q-mem0)
             ("u_boundary.request_fifo_i.memory_q[1][317:315]" r-q-mem1 :cond c-q-mem1 :output p-q-mem1)
             ("u_boundary.request_fifo_i.memory_q[2][317:315]" r-q-mem2 :cond c-q-mem2 :output p-q-mem2)
             ("u_boundary.request_fifo_i.memory_q[3][317:315]" r-q-mem3 :cond c-q-mem3 :output p-q-mem3)
             ("u_boundary.request_fifo_i.memory_q[4][317:315]" r-q-mem4 :cond c-q-mem4 :output p-q-mem4)
             ("u_boundary.request_fifo_i.memory_q[5][317:315]" r-q-mem5 :cond c-q-mem5 :output p-q-mem5)
             ("u_boundary.request_fifo_i.memory_q[6][317:315]" r-q-mem6 :cond c-q-mem6 :output p-q-mem6)
             ("u_boundary.request_fifo_i.memory_q[7][317:315]" r-q-mem7 :cond c-q-mem7 :output p-q-mem7)
             ("u_boundary.response_fifo_i.write_binary_q" r-s-wb :cond c-s-wb :output p-s-wb)
             ("u_boundary.response_fifo_i.write_gray_q" r-s-wg :cond c-s-wg :output p-s-wg)
             ("u_boundary.response_fifo_i.write_full_q" r-s-full :cond c-s-full :output p-s-full)
             ("u_boundary.response_fifo_i.read_binary_q" r-s-rb :cond c-s-rb :output p-s-rb)
             ("u_boundary.response_fifo_i.read_gray_q" r-s-rg :cond c-s-rg :output p-s-rg)
             ("u_boundary.response_fifo_i.read_gray_sync1_q" r-s-rs1 :cond c-s-rs1 :output p-s-rs1)
             ("u_boundary.response_fifo_i.read_gray_sync2_q" r-s-rs2 :cond c-s-rs2 :output p-s-rs2)
             ("u_boundary.response_fifo_i.write_gray_sync1_q" r-s-ws1 :cond c-s-ws1 :output p-s-ws1)
             ("u_boundary.response_fifo_i.write_gray_sync2_q" r-s-ws2 :cond c-s-ws2 :output p-s-ws2)
             ("u_boundary.response_fifo_i.m_valid_q" r-s-mv :cond c-s-mv :output p-s-mv)
             ("u_boundary.response_fifo_i.source_fault_q" r-s-sf :cond c-s-sf :output p-s-sf)
             ("u_boundary.response_fifo_i.source_payload_fault_q" r-s-spf :cond c-s-spf :output p-s-spf)
             ("u_boundary.response_fifo_i.destination_fault_q" r-s-df :cond c-s-df :output p-s-df)
             ("u_boundary.response_fifo_i.source_stalled_q" r-s-st :cond c-s-st :output p-s-st)
             ("u_boundary.response_fifo_i.m_data_q[259:256]" r-s-md :cond c-s-md :output p-s-md)
             ("u_boundary.response_fifo_i.memory_q[0][259:256]" r-s-mem0 :cond c-s-mem0 :output p-s-mem0)
             ("u_boundary.response_fifo_i.memory_q[1][259:256]" r-s-mem1 :cond c-s-mem1 :output p-s-mem1)
             ("u_boundary.response_fifo_i.memory_q[2][259:256]" r-s-mem2 :cond c-s-mem2 :output p-s-mem2)
             ("u_boundary.response_fifo_i.memory_q[3][259:256]" r-s-mem3 :cond c-s-mem3 :output p-s-mem3)
             ("u_boundary.response_fifo_i.memory_q[4][259:256]" r-s-mem4 :cond c-s-mem4 :output p-s-mem4)
             ("u_boundary.response_fifo_i.memory_q[5][259:256]" r-s-mem5 :cond c-s-mem5 :output p-s-mem5)
             ("u_boundary.response_fifo_i.memory_q[6][259:256]" r-s-mem6 :cond c-s-mem6 :output p-s-mem6)
             ("u_boundary.response_fifo_i.memory_q[7][259:256]" r-s-mem7 :cond c-s-mem7 :output p-s-mem7)
             ("u_boundary.request_fifo_i.m_data_q[278:275]" r-q-mdw :cond c-q-mdw :output p-q-mdw)
             ("u_boundary.request_fifo_i.memory_q[0][278:275]" r-q-memw0 :cond c-q-memw0 :output p-q-memw0)
             ("u_boundary.request_fifo_i.memory_q[1][278:275]" r-q-memw1 :cond c-q-memw1 :output p-q-memw1)
             ("u_boundary.request_fifo_i.memory_q[2][278:275]" r-q-memw2 :cond c-q-memw2 :output p-q-memw2)
             ("u_boundary.request_fifo_i.memory_q[3][278:275]" r-q-memw3 :cond c-q-memw3 :output p-q-memw3)
             ("u_boundary.request_fifo_i.memory_q[4][278:275]" r-q-memw4 :cond c-q-memw4 :output p-q-memw4)
             ("u_boundary.request_fifo_i.memory_q[5][278:275]" r-q-memw5 :cond c-q-memw5 :output p-q-memw5)
             ("u_boundary.request_fifo_i.memory_q[6][278:275]" r-q-memw6 :cond c-q-memw6 :output p-q-memw6)
             ("u_boundary.request_fifo_i.memory_q[7][278:275]" r-q-memw7 :cond c-q-memw7 :output p-q-memw7)
             ("u_boundary.app_boundary_i.fault_q" r-a-fault :cond c-a-fault :output p-a-fault)
             ("u_boundary.app_boundary_i.lock_seen_q" r-a-lock-seen :cond c-a-lock-seen :output p-a-lock-seen)
             ("u_boundary.app_boundary_i.offer_q" r-a-offer :cond c-a-offer :output p-a-offer)
             ("u_boundary.app_boundary_i.offer_write_q" r-a-offer-write :cond c-a-offer-write :output p-a-offer-write)
             ("u_boundary.app_boundary_i.offer_poison_q" r-a-poison :cond c-a-poison :output p-a-poison)
             ("u_boundary.app_boundary_i.offer_slot_q" r-a-offer-slot :cond c-a-offer-slot :output p-a-offer-slot)
             ("u_boundary.app_boundary_i.reserved_q" r-a-reserved :cond c-a-reserved :output p-a-reserved)
             ("u_boundary.app_boundary_i.unissued_q" r-a-unissued :cond c-a-unissued :output p-a-unissued)
             ("u_boundary.app_boundary_i.read_count_q" r-a-readcount :cond c-a-readcount :output p-a-readcount)
             ("u_boundary.app_boundary_i.head_q" r-a-head :cond c-a-head :output p-a-head)
             ("u_boundary.app_boundary_i.tail_q" r-a-tail :cond c-a-tail :output p-a-tail)
             ("u_boundary.app_boundary_i.issue_q" r-a-issue :cond c-a-issue :output p-a-issue)
             ("u_boundary.app_boundary_i.read_head_q" r-a-rhead :cond c-a-rhead :output p-a-rhead)
             ("u_boundary.app_boundary_i.read_tail_q" r-a-rtail :cond c-a-rtail :output p-a-rtail)
             ("u_boundary.app_boundary_i.slot_kind_q[0]" r-a-kind0 :cond c-a-kind0 :output p-a-kind0)
             ("u_boundary.app_boundary_i.slot_kind_q[1]" r-a-kind1 :cond c-a-kind1 :output p-a-kind1)
             ("u_boundary.app_boundary_i.slot_kind_q[2]" r-a-kind2 :cond c-a-kind2 :output p-a-kind2)
             ("u_boundary.app_boundary_i.slot_kind_q[3]" r-a-kind3 :cond c-a-kind3 :output p-a-kind3)
             ("u_boundary.app_boundary_i.slot_kind_q[4]" r-a-kind4 :cond c-a-kind4 :output p-a-kind4)
             ("u_boundary.app_boundary_i.slot_kind_q[5]" r-a-kind5 :cond c-a-kind5 :output p-a-kind5)
             ("u_boundary.app_boundary_i.slot_kind_q[6]" r-a-kind6 :cond c-a-kind6 :output p-a-kind6)
             ("u_boundary.app_boundary_i.slot_kind_q[7]" r-a-kind7 :cond c-a-kind7 :output p-a-kind7)
             ("u_boundary.app_boundary_i.slot_epoch_q[7]" r-a-epoch0 :cond c-a-epoch0 :output p-a-epoch0)
             ("u_boundary.app_boundary_i.slot_epoch_q[6]" r-a-epoch1 :cond c-a-epoch1 :output p-a-epoch1)
             ("u_boundary.app_boundary_i.slot_epoch_q[5]" r-a-epoch2 :cond c-a-epoch2 :output p-a-epoch2)
             ("u_boundary.app_boundary_i.slot_epoch_q[4]" r-a-epoch3 :cond c-a-epoch3 :output p-a-epoch3)
             ("u_boundary.app_boundary_i.slot_epoch_q[3]" r-a-epoch4 :cond c-a-epoch4 :output p-a-epoch4)
             ("u_boundary.app_boundary_i.slot_epoch_q[2]" r-a-epoch5 :cond c-a-epoch5 :output p-a-epoch5)
             ("u_boundary.app_boundary_i.slot_epoch_q[1]" r-a-epoch6 :cond c-a-epoch6 :output p-a-epoch6)
             ("u_boundary.app_boundary_i.slot_epoch_q[0]" r-a-epoch7 :cond c-a-epoch7 :output p-a-epoch7)
             ("u_boundary.app_boundary_i.slot_reject_q[7]" r-a-reject0 :cond c-a-reject0 :output p-a-reject0)
             ("u_boundary.app_boundary_i.slot_reject_q[6]" r-a-reject1 :cond c-a-reject1 :output p-a-reject1)
             ("u_boundary.app_boundary_i.slot_reject_q[5]" r-a-reject2 :cond c-a-reject2 :output p-a-reject2)
             ("u_boundary.app_boundary_i.slot_reject_q[4]" r-a-reject3 :cond c-a-reject3 :output p-a-reject3)
             ("u_boundary.app_boundary_i.slot_reject_q[3]" r-a-reject4 :cond c-a-reject4 :output p-a-reject4)
             ("u_boundary.app_boundary_i.slot_reject_q[2]" r-a-reject5 :cond c-a-reject5 :output p-a-reject5)
             ("u_boundary.app_boundary_i.slot_reject_q[1]" r-a-reject6 :cond c-a-reject6 :output p-a-reject6)
             ("u_boundary.app_boundary_i.slot_reject_q[0]" r-a-reject7 :cond c-a-reject7 :output p-a-reject7)
             ("u_boundary.app_boundary_i.slot_done_q[7]" r-a-done0 :cond c-a-done0 :output p-a-done0)
             ("u_boundary.app_boundary_i.slot_done_q[6]" r-a-done1 :cond c-a-done1 :output p-a-done1)
             ("u_boundary.app_boundary_i.slot_done_q[5]" r-a-done2 :cond c-a-done2 :output p-a-done2)
             ("u_boundary.app_boundary_i.slot_done_q[4]" r-a-done3 :cond c-a-done3 :output p-a-done3)
             ("u_boundary.app_boundary_i.slot_done_q[3]" r-a-done4 :cond c-a-done4 :output p-a-done4)
             ("u_boundary.app_boundary_i.slot_done_q[2]" r-a-done5 :cond c-a-done5 :output p-a-done5)
             ("u_boundary.app_boundary_i.slot_done_q[1]" r-a-done6 :cond c-a-done6 :output p-a-done6)
             ("u_boundary.app_boundary_i.slot_done_q[0]" r-a-done7 :cond c-a-done7 :output p-a-done7)
             ("u_boundary.app_boundary_i.slot_fault_q[7]" r-a-sfault0 :cond c-a-sfault0 :output p-a-sfault0)
             ("u_boundary.app_boundary_i.slot_fault_q[6]" r-a-sfault1 :cond c-a-sfault1 :output p-a-sfault1)
             ("u_boundary.app_boundary_i.slot_fault_q[5]" r-a-sfault2 :cond c-a-sfault2 :output p-a-sfault2)
             ("u_boundary.app_boundary_i.slot_fault_q[4]" r-a-sfault3 :cond c-a-sfault3 :output p-a-sfault3)
             ("u_boundary.app_boundary_i.slot_fault_q[3]" r-a-sfault4 :cond c-a-sfault4 :output p-a-sfault4)
             ("u_boundary.app_boundary_i.slot_fault_q[2]" r-a-sfault5 :cond c-a-sfault5 :output p-a-sfault5)
             ("u_boundary.app_boundary_i.slot_fault_q[1]" r-a-sfault6 :cond c-a-sfault6 :output p-a-sfault6)
             ("u_boundary.app_boundary_i.slot_fault_q[0]" r-a-sfault7 :cond c-a-sfault7 :output p-a-sfault7)
             ("u_boundary.app_boundary_i.slot_word_q[0]" r-a-word0 :cond c-a-word0 :output p-a-word0)
             ("u_boundary.app_boundary_i.slot_word_q[1]" r-a-word1 :cond c-a-word1 :output p-a-word1)
             ("u_boundary.app_boundary_i.slot_word_q[2]" r-a-word2 :cond c-a-word2 :output p-a-word2)
             ("u_boundary.app_boundary_i.slot_word_q[3]" r-a-word3 :cond c-a-word3 :output p-a-word3)
             ("u_boundary.app_boundary_i.slot_word_q[4]" r-a-word4 :cond c-a-word4 :output p-a-word4)
             ("u_boundary.app_boundary_i.slot_word_q[5]" r-a-word5 :cond c-a-word5 :output p-a-word5)
             ("u_boundary.app_boundary_i.slot_word_q[6]" r-a-word6 :cond c-a-word6 :output p-a-word6)
             ("u_boundary.app_boundary_i.slot_word_q[7]" r-a-word7 :cond c-a-word7 :output p-a-word7)
             ("u_boundary.app_boundary_i.read_slot_q[0]" r-a-rslot0 :cond c-a-rslot0 :output p-a-rslot0)
             ("u_boundary.app_boundary_i.read_slot_q[1]" r-a-rslot1 :cond c-a-rslot1 :output p-a-rslot1)
             ("u_boundary.app_boundary_i.read_slot_q[2]" r-a-rslot2 :cond c-a-rslot2 :output p-a-rslot2)
             ("u_boundary.app_boundary_i.read_slot_q[3]" r-a-rslot3 :cond c-a-rslot3 :output p-a-rslot3)
             ("u_boundary.app_boundary_i.read_slot_q[4]" r-a-rslot4 :cond c-a-rslot4 :output p-a-rslot4)
             ("u_boundary.app_boundary_i.read_slot_q[5]" r-a-rslot5 :cond c-a-rslot5 :output p-a-rslot5)
             ("u_boundary.app_boundary_i.read_slot_q[6]" r-a-rslot6 :cond c-a-rslot6 :output p-a-rslot6)
             ("u_boundary.app_boundary_i.read_slot_q[7]" r-a-rslot7 :cond c-a-rslot7 :output p-a-rslot7)
             ("u_machine.arbiter_fail" h-arbfail :cond c-h-arbfail :output p-h-arbfail)
             ("u_machine.shell_terminal_latched" h-shellterm :cond c-h-shellterm :output p-h-shellterm)
             ("u_machine.shell_fail" h-shellfail :cond c-h-shellfail :output p-h-shellfail)
             ("u_machine.layer_fail" h-layerfail :cond c-h-layerfail :output p-h-layerfail)
             ("auth_fault" h-auth :cond c-h-auth :output p-h-auth)
             ("model_cdc_core_fault" h-mcdc :cond c-h-mcdc :output p-h-mcdc)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.upstream_fault_i" h-kupf :cond c-h-kupf :output p-h-kupf)
             ("u_machine.u_six_layers.u_datapath.current_layer_q" h-layer :cond c-h-layer :output p-h-layer)
             ("u_machine.u_six_layers.u_datapath.current_position_q" h-position :cond c-h-position :output p-h-position)
             ("u_machine.u_six_layers.u_datapath.key_exponent_q" h-kexp :cond c-h-kexp :output p-h-kexp)
             ("u_machine.u_six_layers.u_datapath.value_exponent_q" h-vexp :cond c-h-vexp :output p-h-vexp)
             ("u_machine.u_six_layers.u_datapath.kv_stage_begin_valid" h-sbegin :cond c-h-sbegin :output p-h-sbegin)
             ("u_machine.u_six_layers.u_datapath.kv_stage_payload_valid" h-spayload :cond c-h-spayload :output p-h-spayload)
             ("u_machine.u_six_layers.u_datapath.input_index_q" h-index :cond c-h-index :output p-h-index)
             ("u_machine.u_six_layers.u_datapath.key_ram_read_data" h-key :cond c-h-key :output p-h-key)
             ("u_machine.u_six_layers.u_datapath.value_ram_read_data" h-value :cond c-h-value :output p-h-value)
             ("u_machine.u_six_layers.u_datapath.kv_commit_valid" h-commit :cond c-h-commit :output p-h-commit)
             ("u_machine.u_six_layers.u_datapath.attention_cache_req_valid" h-attn :cond c-h-attn :output p-h-attn)
             ("u_machine.u_six_layers.u_datapath.attention_cache_req_kind" h-attn-kind :cond c-h-attn-kind :output p-h-attn-kind)
             ("u_machine.u_six_layers.u_datapath.attention_cache_req_position" h-attn-pos :cond c-h-attn-pos :output p-h-attn-pos)
             ("u_machine.u_six_layers.u_datapath.attention_cache_req_head" h-attn-head :cond c-h-attn-head :output p-h-attn-head)
             ("u_machine.u_six_layers.u_datapath.attention_cache_rsp_ready" h-attn-ready :cond c-h-attn-ready :output p-h-attn-ready)
             ("private_kv_req_ready_i" h-epready :cond c-h-epready :output p-h-epready)
             ("private_kv_rsp_valid_i" h-eprspv :cond c-h-eprspv :output p-h-eprspv)
             ("private_kv_rsp_error_i" h-eprsperr :cond c-h-eprsperr :output p-h-eprsperr)
             ("private_kv_rsp_data_i" h-eprspdata :cond c-h-eprspdata :output p-h-eprspdata)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_read_rsp_data_i" h-rspdata :cond c-h-rspdata :output p-h-rspdata)
             ("u_boundary.app_upstream_fault_i" h-appup :cond c-h-appup :output p-h-appup)
             ("u_boundary.app_boundary_i.request_descriptor_legal" h-legal :cond c-h-legal :output p-h-legal)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[0].words" r-k-bank0 :cond c-k-bank0 :output p-k-bank0)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[1].words" r-k-bank1 :cond c-k-bank1 :output p-k-bank1)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[2].words" r-k-bank2 :cond c-k-bank2 :output p-k-bank2)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[3].words" r-k-bank3 :cond c-k-bank3 :output p-k-bank3)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[4].words" r-k-bank4 :cond c-k-bank4 :output p-k-bank4)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[5].words" r-k-bank5 :cond c-k-bank5 :output p-k-bank5)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[6].words" r-k-bank6 :cond c-k-bank6 :output p-k-bank6)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[7].words" r-k-bank7 :cond c-k-bank7 :output p-k-bank7)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[0].read_data_q" r-k-rd0 :cond c-k-rd0 :output p-k-rd0)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[1].read_data_q" r-k-rd1 :cond c-k-rd1 :output p-k-rd1)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[2].read_data_q" r-k-rd2 :cond c-k-rd2 :output p-k-rd2)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[3].read_data_q" r-k-rd3 :cond c-k-rd3 :output p-k-rd3)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[4].read_data_q" r-k-rd4 :cond c-k-rd4 :output p-k-rd4)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[5].read_data_q" r-k-rd5 :cond c-k-rd5 :output p-k-rd5)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[6].read_data_q" r-k-rd6 :cond c-k-rd6 :output p-k-rd6)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[7].read_data_q" r-k-rd7 :cond c-k-rd7 :output p-k-rd7)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_offer_q" r-k-offer :cond c-k-offer :output p-k-offer)
             ("u_boundary.request_fifo_i.memory_q[0][274:0]" r-q-memp0 :cond c-q-memp0 :output p-q-memp0)
             ("u_boundary.request_fifo_i.memory_q[1][274:0]" r-q-memp1 :cond c-q-memp1 :output p-q-memp1)
             ("u_boundary.request_fifo_i.memory_q[2][274:0]" r-q-memp2 :cond c-q-memp2 :output p-q-memp2)
             ("u_boundary.request_fifo_i.memory_q[3][274:0]" r-q-memp3 :cond c-q-memp3 :output p-q-memp3)
             ("u_boundary.request_fifo_i.memory_q[4][274:0]" r-q-memp4 :cond c-q-memp4 :output p-q-memp4)
             ("u_boundary.request_fifo_i.memory_q[5][274:0]" r-q-memp5 :cond c-q-memp5 :output p-q-memp5)
             ("u_boundary.request_fifo_i.memory_q[6][274:0]" r-q-memp6 :cond c-q-memp6 :output p-q-memp6)
             ("u_boundary.request_fifo_i.memory_q[7][274:0]" r-q-memp7 :cond c-q-memp7 :output p-q-memp7)
             ("u_boundary.request_fifo_i.memory_q[0][314:279]" r-q-memd0 :cond c-q-memd0 :output p-q-memd0)
             ("u_boundary.request_fifo_i.memory_q[1][314:279]" r-q-memd1 :cond c-q-memd1 :output p-q-memd1)
             ("u_boundary.request_fifo_i.memory_q[2][314:279]" r-q-memd2 :cond c-q-memd2 :output p-q-memd2)
             ("u_boundary.request_fifo_i.memory_q[3][314:279]" r-q-memd3 :cond c-q-memd3 :output p-q-memd3)
             ("u_boundary.request_fifo_i.memory_q[4][314:279]" r-q-memd4 :cond c-q-memd4 :output p-q-memd4)
             ("u_boundary.request_fifo_i.memory_q[5][314:279]" r-q-memd5 :cond c-q-memd5 :output p-q-memd5)
             ("u_boundary.request_fifo_i.memory_q[6][314:279]" r-q-memd6 :cond c-q-memd6 :output p-q-memd6)
             ("u_boundary.request_fifo_i.memory_q[7][314:279]" r-q-memd7 :cond c-q-memd7 :output p-q-memd7)
             ("u_boundary.request_fifo_i.m_data_q[314:279]" r-q-mdd :cond c-q-mdd :output p-q-mdd)
             ("u_boundary.request_fifo_i.m_data_q[274:0]" r-q-mdp :cond c-q-mdp :output p-q-mdp)
             ("u_boundary.app_boundary_i.slot_address_q" r-a-saddr :cond c-a-saddr :output p-a-saddr)
             ("u_boundary.app_boundary_i.slot_data_q" r-a-sdata :cond c-a-sdata :output p-a-sdata)
             ("u_boundary.app_boundary_i.offer_address_q" r-a-oaddr :cond c-a-oaddr :output p-a-oaddr)
             ("u_boundary.app_boundary_i.offer_write_data_q" r-a-odata :cond c-a-odata :output p-a-odata))
            :outputs (("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_cpl_valid_i" o-cplv)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_cpl_fault_i" o-cplf)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.clear_i" o-clear)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_read_rsp_valid_i" o-rspv)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_read_rsp_fault_i" o-rspf)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.protocol_fault_now" o-pfn)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.typed_padding_fault" o-tpf)
                      ("u_boundary.app_boundary_i.endpoint_padding_fault_now" o-epf)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.terminal_fault_event" o-tfe)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_req_valid_o" o-wreqv)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_req_ready_i" o-wreqr)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_req_shadow_address_o" o-wreqaddr)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_req_data_o" o-wreqdata)
                      ("private_kv_req_valid_o" o-epv)
                      ("private_kv_req_write_o" o-epw)
                      ("private_kv_req_word_address_o" o-epaddr)
                      ("private_kv_req_write_data_o" o-epdata)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_ready_o" o-spr)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_legal" o-spl)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_cpl_ready_o" o-wcplr)
                      ("u_boundary.app_boundary_i.kv_write_descriptor_legal" o-wlegal)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_ready_o" o-sbr)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_legal" o-sbl)
))
           (:label next
            :inputs (("reset_n_i" 1))
            :outputs (
             ("model_lock_core_meta_q" n-p-lock-meta)
             ("model_lock_core_sync_q" n-p-lock-sync)
             ("core_fault_to_boundary_q" n-p-cfb)
             ("app_runtime_release_q" n-p-apprel)
             ("u_machine.machine_release_q" n-m-rel)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" n-k-state-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_issued_q" n-k-pending-issued-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_returned_q" n-k-pending-returned-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_read_pending_q" n-k-pending-read-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.committed_prefix_q" n-k-committed-prefix-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_layer_q" n-k-pending-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_position_q" n-k-pending-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_key_exponents_q" n-k-pending-key-exponents-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_value_exponents_q" n-k-pending-value-exponents-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.expected_coordinate_q" n-k-expected-coordinate-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_persisted_q" n-k-pending-persisted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_head_q" n-k-write-head-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_word_q" n-k-write-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_aborted_q" n-k-write-aborted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_kind_q" n-k-response-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_head_q" n-k-response-head-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_layer_q" n-k-response-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_position_q" n-k-response-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_fault_q" n-k-response-fault-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_from_pending_q" n-k-response-from-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_word_q" n-k-read-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_return_word_q" n-k-read-return-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_outstanding_q" n-k-read-outstanding-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_issue_done_q" n-k-read-issue-done-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_aborted_q" n-k-read-aborted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_physical_kind_q" n-k-read-physical-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_epoch_q" n-k-read-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_received_mask_q" n-k-read-received-mask-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_valid_q" n-k-cache-valid-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_kind_q" n-k-cache-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_layer_q" n-k-cache-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_position_q" n-k-cache-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_tag_epoch_q" n-k-cache-tag-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_epoch_q" n-k-cache-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_clear_seen_q" n-k-cache-clear-seen-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_issued_q" n-k-cache-issued-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_returned_q" n-k-cache-returned-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_read_pending_q" n-k-cache-read-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_copy_kind_q" n-k-cache-copy-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.lock_seen_q" n-k-lock-seen-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.fault_q" n-k-fault-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_consumed_q" n-k-stage-begin-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_consumed_q" n-k-stage-payload-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.commit_consumed_q" n-k-commit-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_consumed_q" n-k-attention-req-consumed-q)
             ("u_boundary.core_release_q" n-b-crel)
             ("u_boundary.app_release_q" n-b-arel)
             ("u_boundary.model_lock_core_meta_q" n-b-lock-meta)
             ("u_boundary.model_lock_core_sync_q" n-b-lock-sync)
             ("u_boundary.app_fault_core_meta_q" n-b-afc-meta)
             ("u_boundary.app_fault_core_sync_q" n-b-afc-sync)
             ("u_boundary.core_fault_app_meta_q" n-b-cfa-meta)
             ("u_boundary.core_fault_app_sync_q" n-b-cfa-sync)
             ("u_boundary.core_fault_q" n-b-fault)
             ("u_boundary.core_lock_seen_q" n-b-lock-seen)
             ("u_boundary.core_clear_seen_q" n-b-clr-seen)
             ("u_boundary.core_clear_pending_q" n-b-clr-pend)
             ("u_boundary.core_clear_drained_o" n-b-clr-drained)
             ("u_boundary.core_epoch_q" n-b-epoch)
             ("u_boundary.core_outstanding_q" n-b-out)
             ("u_boundary.model_rsp_stalled_q" n-b-mstall)
             ("u_boundary.kv_write_cpl_stalled_q" n-b-wstall)
             ("u_boundary.kv_write_cpl_stalled_fault_q" n-b-wstallf)
             ("u_boundary.kv_read_rsp_stalled_q" n-b-rstall)
             ("u_boundary.request_fifo_i.write_binary_q" n-q-wb)
             ("u_boundary.request_fifo_i.write_gray_q" n-q-wg)
             ("u_boundary.request_fifo_i.write_full_q" n-q-full)
             ("u_boundary.request_fifo_i.read_binary_q" n-q-rb)
             ("u_boundary.request_fifo_i.read_gray_q" n-q-rg)
             ("u_boundary.request_fifo_i.read_gray_sync1_q" n-q-rs1)
             ("u_boundary.request_fifo_i.read_gray_sync2_q" n-q-rs2)
             ("u_boundary.request_fifo_i.write_gray_sync1_q" n-q-ws1)
             ("u_boundary.request_fifo_i.write_gray_sync2_q" n-q-ws2)
             ("u_boundary.request_fifo_i.m_valid_q" n-q-mv)
             ("u_boundary.request_fifo_i.source_fault_q" n-q-sf)
             ("u_boundary.request_fifo_i.source_payload_fault_q" n-q-spf)
             ("u_boundary.request_fifo_i.destination_fault_q" n-q-df)
             ("u_boundary.request_fifo_i.source_stalled_q" n-q-st)
             ("u_boundary.request_fifo_i.m_data_q[317:315]" n-q-md)
             ("u_boundary.request_fifo_i.memory_q[0][317:315]" n-q-mem0)
             ("u_boundary.request_fifo_i.memory_q[1][317:315]" n-q-mem1)
             ("u_boundary.request_fifo_i.memory_q[2][317:315]" n-q-mem2)
             ("u_boundary.request_fifo_i.memory_q[3][317:315]" n-q-mem3)
             ("u_boundary.request_fifo_i.memory_q[4][317:315]" n-q-mem4)
             ("u_boundary.request_fifo_i.memory_q[5][317:315]" n-q-mem5)
             ("u_boundary.request_fifo_i.memory_q[6][317:315]" n-q-mem6)
             ("u_boundary.request_fifo_i.memory_q[7][317:315]" n-q-mem7)
             ("u_boundary.response_fifo_i.write_binary_q" n-s-wb)
             ("u_boundary.response_fifo_i.write_gray_q" n-s-wg)
             ("u_boundary.response_fifo_i.write_full_q" n-s-full)
             ("u_boundary.response_fifo_i.read_binary_q" n-s-rb)
             ("u_boundary.response_fifo_i.read_gray_q" n-s-rg)
             ("u_boundary.response_fifo_i.read_gray_sync1_q" n-s-rs1)
             ("u_boundary.response_fifo_i.read_gray_sync2_q" n-s-rs2)
             ("u_boundary.response_fifo_i.write_gray_sync1_q" n-s-ws1)
             ("u_boundary.response_fifo_i.write_gray_sync2_q" n-s-ws2)
             ("u_boundary.response_fifo_i.m_valid_q" n-s-mv)
             ("u_boundary.response_fifo_i.source_fault_q" n-s-sf)
             ("u_boundary.response_fifo_i.source_payload_fault_q" n-s-spf)
             ("u_boundary.response_fifo_i.destination_fault_q" n-s-df)
             ("u_boundary.response_fifo_i.source_stalled_q" n-s-st)
             ("u_boundary.response_fifo_i.m_data_q[259:256]" n-s-md)
             ("u_boundary.response_fifo_i.memory_q[0][259:256]" n-s-mem0)
             ("u_boundary.response_fifo_i.memory_q[1][259:256]" n-s-mem1)
             ("u_boundary.response_fifo_i.memory_q[2][259:256]" n-s-mem2)
             ("u_boundary.response_fifo_i.memory_q[3][259:256]" n-s-mem3)
             ("u_boundary.response_fifo_i.memory_q[4][259:256]" n-s-mem4)
             ("u_boundary.response_fifo_i.memory_q[5][259:256]" n-s-mem5)
             ("u_boundary.response_fifo_i.memory_q[6][259:256]" n-s-mem6)
             ("u_boundary.response_fifo_i.memory_q[7][259:256]" n-s-mem7)
             ("u_boundary.request_fifo_i.m_data_q[278:275]" n-q-mdw)
             ("u_boundary.request_fifo_i.memory_q[0][278:275]" n-q-memw0)
             ("u_boundary.request_fifo_i.memory_q[1][278:275]" n-q-memw1)
             ("u_boundary.request_fifo_i.memory_q[2][278:275]" n-q-memw2)
             ("u_boundary.request_fifo_i.memory_q[3][278:275]" n-q-memw3)
             ("u_boundary.request_fifo_i.memory_q[4][278:275]" n-q-memw4)
             ("u_boundary.request_fifo_i.memory_q[5][278:275]" n-q-memw5)
             ("u_boundary.request_fifo_i.memory_q[6][278:275]" n-q-memw6)
             ("u_boundary.request_fifo_i.memory_q[7][278:275]" n-q-memw7)
             ("u_boundary.app_boundary_i.fault_q" n-a-fault)
             ("u_boundary.app_boundary_i.lock_seen_q" n-a-lock-seen)
             ("u_boundary.app_boundary_i.offer_q" n-a-offer)
             ("u_boundary.app_boundary_i.offer_write_q" n-a-offer-write)
             ("u_boundary.app_boundary_i.offer_poison_q" n-a-poison)
             ("u_boundary.app_boundary_i.offer_slot_q" n-a-offer-slot)
             ("u_boundary.app_boundary_i.reserved_q" n-a-reserved)
             ("u_boundary.app_boundary_i.unissued_q" n-a-unissued)
             ("u_boundary.app_boundary_i.read_count_q" n-a-readcount)
             ("u_boundary.app_boundary_i.head_q" n-a-head)
             ("u_boundary.app_boundary_i.tail_q" n-a-tail)
             ("u_boundary.app_boundary_i.issue_q" n-a-issue)
             ("u_boundary.app_boundary_i.read_head_q" n-a-rhead)
             ("u_boundary.app_boundary_i.read_tail_q" n-a-rtail)
             ("u_boundary.app_boundary_i.slot_kind_q[0]" n-a-kind0)
             ("u_boundary.app_boundary_i.slot_kind_q[1]" n-a-kind1)
             ("u_boundary.app_boundary_i.slot_kind_q[2]" n-a-kind2)
             ("u_boundary.app_boundary_i.slot_kind_q[3]" n-a-kind3)
             ("u_boundary.app_boundary_i.slot_kind_q[4]" n-a-kind4)
             ("u_boundary.app_boundary_i.slot_kind_q[5]" n-a-kind5)
             ("u_boundary.app_boundary_i.slot_kind_q[6]" n-a-kind6)
             ("u_boundary.app_boundary_i.slot_kind_q[7]" n-a-kind7)
             ("u_boundary.app_boundary_i.slot_epoch_q[7]" n-a-epoch0)
             ("u_boundary.app_boundary_i.slot_epoch_q[6]" n-a-epoch1)
             ("u_boundary.app_boundary_i.slot_epoch_q[5]" n-a-epoch2)
             ("u_boundary.app_boundary_i.slot_epoch_q[4]" n-a-epoch3)
             ("u_boundary.app_boundary_i.slot_epoch_q[3]" n-a-epoch4)
             ("u_boundary.app_boundary_i.slot_epoch_q[2]" n-a-epoch5)
             ("u_boundary.app_boundary_i.slot_epoch_q[1]" n-a-epoch6)
             ("u_boundary.app_boundary_i.slot_epoch_q[0]" n-a-epoch7)
             ("u_boundary.app_boundary_i.slot_reject_q[7]" n-a-reject0)
             ("u_boundary.app_boundary_i.slot_reject_q[6]" n-a-reject1)
             ("u_boundary.app_boundary_i.slot_reject_q[5]" n-a-reject2)
             ("u_boundary.app_boundary_i.slot_reject_q[4]" n-a-reject3)
             ("u_boundary.app_boundary_i.slot_reject_q[3]" n-a-reject4)
             ("u_boundary.app_boundary_i.slot_reject_q[2]" n-a-reject5)
             ("u_boundary.app_boundary_i.slot_reject_q[1]" n-a-reject6)
             ("u_boundary.app_boundary_i.slot_reject_q[0]" n-a-reject7)
             ("u_boundary.app_boundary_i.slot_done_q[7]" n-a-done0)
             ("u_boundary.app_boundary_i.slot_done_q[6]" n-a-done1)
             ("u_boundary.app_boundary_i.slot_done_q[5]" n-a-done2)
             ("u_boundary.app_boundary_i.slot_done_q[4]" n-a-done3)
             ("u_boundary.app_boundary_i.slot_done_q[3]" n-a-done4)
             ("u_boundary.app_boundary_i.slot_done_q[2]" n-a-done5)
             ("u_boundary.app_boundary_i.slot_done_q[1]" n-a-done6)
             ("u_boundary.app_boundary_i.slot_done_q[0]" n-a-done7)
             ("u_boundary.app_boundary_i.slot_fault_q[7]" n-a-sfault0)
             ("u_boundary.app_boundary_i.slot_fault_q[6]" n-a-sfault1)
             ("u_boundary.app_boundary_i.slot_fault_q[5]" n-a-sfault2)
             ("u_boundary.app_boundary_i.slot_fault_q[4]" n-a-sfault3)
             ("u_boundary.app_boundary_i.slot_fault_q[3]" n-a-sfault4)
             ("u_boundary.app_boundary_i.slot_fault_q[2]" n-a-sfault5)
             ("u_boundary.app_boundary_i.slot_fault_q[1]" n-a-sfault6)
             ("u_boundary.app_boundary_i.slot_fault_q[0]" n-a-sfault7)
             ("u_boundary.app_boundary_i.slot_word_q[0]" n-a-word0)
             ("u_boundary.app_boundary_i.slot_word_q[1]" n-a-word1)
             ("u_boundary.app_boundary_i.slot_word_q[2]" n-a-word2)
             ("u_boundary.app_boundary_i.slot_word_q[3]" n-a-word3)
             ("u_boundary.app_boundary_i.slot_word_q[4]" n-a-word4)
             ("u_boundary.app_boundary_i.slot_word_q[5]" n-a-word5)
             ("u_boundary.app_boundary_i.slot_word_q[6]" n-a-word6)
             ("u_boundary.app_boundary_i.slot_word_q[7]" n-a-word7)
             ("u_boundary.app_boundary_i.read_slot_q[0]" n-a-rslot0)
             ("u_boundary.app_boundary_i.read_slot_q[1]" n-a-rslot1)
             ("u_boundary.app_boundary_i.read_slot_q[2]" n-a-rslot2)
             ("u_boundary.app_boundary_i.read_slot_q[3]" n-a-rslot3)
             ("u_boundary.app_boundary_i.read_slot_q[4]" n-a-rslot4)
             ("u_boundary.app_boundary_i.read_slot_q[5]" n-a-rslot5)
             ("u_boundary.app_boundary_i.read_slot_q[6]" n-a-rslot6)
             ("u_boundary.app_boundary_i.read_slot_q[7]" n-a-rslot7)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[0].words" n-k-bank0)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[1].words" n-k-bank1)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[2].words" n-k-bank2)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[3].words" n-k-bank3)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[4].words" n-k-bank4)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[5].words" n-k-bank5)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[6].words" n-k-bank6)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[7].words" n-k-bank7)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[0].read_data_q" n-k-rd0)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[1].read_data_q" n-k-rd1)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[2].read_data_q" n-k-rd2)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[3].read_data_q" n-k-rd3)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[4].read_data_q" n-k-rd4)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[5].read_data_q" n-k-rd5)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[6].read_data_q" n-k-rd6)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.g_pair_bank[7].read_data_q" n-k-rd7)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_offer_q" n-k-offer)
             ("u_boundary.request_fifo_i.memory_q[0][274:0]" n-q-memp0)
             ("u_boundary.request_fifo_i.memory_q[1][274:0]" n-q-memp1)
             ("u_boundary.request_fifo_i.memory_q[2][274:0]" n-q-memp2)
             ("u_boundary.request_fifo_i.memory_q[3][274:0]" n-q-memp3)
             ("u_boundary.request_fifo_i.memory_q[4][274:0]" n-q-memp4)
             ("u_boundary.request_fifo_i.memory_q[5][274:0]" n-q-memp5)
             ("u_boundary.request_fifo_i.memory_q[6][274:0]" n-q-memp6)
             ("u_boundary.request_fifo_i.memory_q[7][274:0]" n-q-memp7)
             ("u_boundary.request_fifo_i.memory_q[0][314:279]" n-q-memd0)
             ("u_boundary.request_fifo_i.memory_q[1][314:279]" n-q-memd1)
             ("u_boundary.request_fifo_i.memory_q[2][314:279]" n-q-memd2)
             ("u_boundary.request_fifo_i.memory_q[3][314:279]" n-q-memd3)
             ("u_boundary.request_fifo_i.memory_q[4][314:279]" n-q-memd4)
             ("u_boundary.request_fifo_i.memory_q[5][314:279]" n-q-memd5)
             ("u_boundary.request_fifo_i.memory_q[6][314:279]" n-q-memd6)
             ("u_boundary.request_fifo_i.memory_q[7][314:279]" n-q-memd7)
             ("u_boundary.request_fifo_i.m_data_q[314:279]" n-q-mdd)
             ("u_boundary.request_fifo_i.m_data_q[274:0]" n-q-mdp)
             ("u_boundary.app_boundary_i.slot_address_q" n-a-saddr)
             ("u_boundary.app_boundary_i.slot_data_q" n-a-sdata)
             ("u_boundary.app_boundary_i.offer_address_q" n-a-oaddr)
             ("u_boundary.app_boundary_i.offer_write_data_q" n-a-odata)))))

(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export staging-step-run-data)
  (make-event '(def-svtv-refinement staging-step-run staging-step-run-data
                 :svtv-spec staging-step-spec :inclusive-overridekeys t
                 :fsm probe-fsm)))
(value-triple (acl2::cw "~%STG-REFINEMENT done~%"))

; The run fixes what the certified step run fixes: the lock input is 1 in
; the cycle and reset_n_i is 1 in the next.
(defthm kv-staging-run-constraints
  (equal (staging-step-run-fsm-constraints) (join-step-run-fsm-constraints))
  :rule-classes nil)

; ===========================================================================
; The facts, one predicate per conjunct.  Each hands its body to the SAT
; solver on its own, under the antecedent.
; ===========================================================================
(define stg-int-o-pfn (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-o-pfn"
  (integerp x)))
(defthm stg-int-o-pfn-integerp
  (implies (stg-int-o-pfn x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-o-pfn fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-o-tpf (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-o-tpf"
  (integerp x)))
(defthm stg-int-o-tpf-integerp
  (implies (stg-int-o-tpf x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-o-tpf fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-o-epf (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-o-epf"
  (integerp x)))
(defthm stg-int-o-epf-integerp
  (implies (stg-int-o-epf x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-o-epf fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-o-spr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-o-spr"
  (integerp x)))
(defthm stg-int-o-spr-integerp
  (implies (stg-int-o-spr x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-o-spr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-o-spl (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-o-spl"
  (integerp x)))
(defthm stg-int-o-spl-integerp
  (implies (stg-int-o-spl x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-o-spl fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-o-sbr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-o-sbr"
  (integerp x)))
(defthm stg-int-o-sbr-integerp
  (implies (stg-int-o-sbr x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-o-sbr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-o-sbl (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-o-sbl"
  (integerp x)))
(defthm stg-int-o-sbl-integerp
  (implies (stg-int-o-sbl x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-o-sbl fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-state-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-state-q"
  (integerp x)))
(defthm stg-int-n-k-state-q-integerp
  (implies (stg-int-n-k-state-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-state-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-pending-layer-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-pending-layer-q"
  (integerp x)))
(defthm stg-int-n-k-pending-layer-q-integerp
  (implies (stg-int-n-k-pending-layer-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-pending-layer-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-pending-position-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-pending-position-q"
  (integerp x)))
(defthm stg-int-n-k-pending-position-q-integerp
  (implies (stg-int-n-k-pending-position-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-pending-position-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-pending-key-exponents-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-pending-key-exponents-q"
  (integerp x)))
(defthm stg-int-n-k-pending-key-exponents-q-integerp
  (implies (stg-int-n-k-pending-key-exponents-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-pending-key-exponents-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-pending-value-exponents-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-pending-value-exponents-q"
  (integerp x)))
(defthm stg-int-n-k-pending-value-exponents-q-integerp
  (implies (stg-int-n-k-pending-value-exponents-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-pending-value-exponents-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-expected-coordinate-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-expected-coordinate-q"
  (integerp x)))
(defthm stg-int-n-k-expected-coordinate-q-integerp
  (implies (stg-int-n-k-expected-coordinate-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-expected-coordinate-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-write-head-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-write-head-q"
  (integerp x)))
(defthm stg-int-n-k-write-head-q-integerp
  (implies (stg-int-n-k-write-head-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-write-head-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-write-word-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-write-word-q"
  (integerp x)))
(defthm stg-int-n-k-write-word-q-integerp
  (implies (stg-int-n-k-write-word-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-write-word-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define stg-int-n-k-write-aborted-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-int-n-k-write-aborted-q"
  (integerp x)))
(defthm stg-int-n-k-write-aborted-q-integerp
  (implies (stg-int-n-k-write-aborted-q x) (integerp x))
  :hints (("Goal" :in-theory (enable stg-int-n-k-write-aborted-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(in-theory (disable stg-int-o-pfn stg-int-o-tpf stg-int-o-epf stg-int-o-spr stg-int-o-spl stg-int-o-sbr stg-int-o-sbl stg-int-n-k-state-q stg-int-n-k-pending-layer-q stg-int-n-k-pending-position-q stg-int-n-k-pending-key-exponents-q stg-int-n-k-pending-value-exponents-q stg-int-n-k-expected-coordinate-q stg-int-n-k-write-head-q stg-int-n-k-write-word-q stg-int-n-k-write-aborted-q))

; Staging is entered only from idle, by an accepted begin (valid, ready
; and legal) in a cycle without CLEAR, and that begin sets the record's
; layer, position and exponent registers from the datapath's current_layer_q,
; current_position_q, key_exponent_q and value_exponent_q, and the expected
; coordinate to 0.
(define stg-fact-entry (h-kexp h-layer h-position h-sbegin h-vexp i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-fact-entry"
  (or (not (and (equal (pay-u n-k-state-q) 1) (not (equal r-k-state-q 1))))
      (and (equal r-k-state-q 0) (equal (if (and (equal h-sbegin 1) (equal o-sbr 1) (equal o-sbl 1)) 1 0) 1) (equal i-clear 0)
           (equal (pay-u n-k-pending-layer-q) h-layer) (equal (pay-u n-k-pending-position-q) h-position)
           (equal (pay-u n-k-pending-key-exponents-q) (logapp 8 h-kexp (loghead 8 h-kexp))) (equal (pay-u n-k-pending-value-exponents-q) (logapp 8 h-vexp (loghead 8 h-vexp)))
           (equal (pay-u n-k-expected-coordinate-q) 0)))))
; While staging lasts there is no CLEAR and no accepted begin, the record's
; layer, position and exponents do not change, and the expected coordinate
; goes up by one exactly on an accepted payload transfer, which is for the
; expected coordinate.
(define stg-fact-stay (h-index h-sbegin h-spayload i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-fact-stay"
  (or (not (and (equal r-k-state-q 1) (equal (pay-u n-k-state-q) 1)))
      (and (equal i-clear 0) (equal (if (and (equal h-sbegin 1) (equal o-sbr 1) (equal o-sbl 1)) 1 0) 0)
           (equal (pay-u n-k-pending-layer-q) r-k-pending-layer-q) (equal (pay-u n-k-pending-position-q) r-k-pending-position-q)
           (equal (pay-u n-k-pending-key-exponents-q) r-k-pending-key-exponents-q) (equal (pay-u n-k-pending-value-exponents-q) r-k-pending-value-exponents-q)
           (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
               (and (equal (loghead 7 h-index) r-k-expected-coordinate-q)
                    (equal (pay-u n-k-expected-coordinate-q) (+ 1 r-k-expected-coordinate-q)))
             (equal (pay-u n-k-expected-coordinate-q) r-k-expected-coordinate-q))))))
; Staging ends in the record's start only by the accepted transfer for
; coordinate 127, in a cycle without CLEAR, and that step leaves the
; record's layer, position and exponents as they were.
(define stg-fact-last (h-index h-sbegin h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-fact-last"
  (or (not (and (equal r-k-state-q 1) (equal (pay-u n-k-state-q) 9)))
      (and (equal i-clear 0) (equal (if (and (equal h-sbegin 1) (equal o-sbr 1) (equal o-sbl 1)) 1 0) 0) (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
           (equal r-k-expected-coordinate-q 127) (equal (loghead 7 h-index) 127)
           (equal (pay-u n-k-write-head-q) 0) (equal (pay-u n-k-write-word-q) 0) (equal (pay-u n-k-write-aborted-q) 0)
           (equal (pay-u n-k-pending-layer-q) r-k-pending-layer-q) (equal (pay-u n-k-pending-position-q) r-k-pending-position-q)
           (equal (pay-u n-k-pending-key-exponents-q) r-k-pending-key-exponents-q) (equal (pay-u n-k-pending-value-exponents-q) r-k-pending-value-exponents-q)))))
; A begin is accepted only while the controller is idle, and it starts a
; staging.
(define stg-fact-begin (h-sbegin n-k-state-q o-sbl o-sbr r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "stg-fact-begin"
  (or (not (equal (if (and (equal h-sbegin 1) (equal o-sbr 1) (equal o-sbl 1)) 1 0) 1))
      (and (equal r-k-state-q 0) (equal (pay-u n-k-state-q) 1)))))
(in-theory (disable stg-fact-entry stg-fact-stay stg-fact-last stg-fact-begin))

; THE CONCLUSION of the staging step lemma: with no protocol violation by
; the client and no malformed metadata word from the endpoint in the cycle
; (the antecedent of the payload step lemma), all four facts.
(define stg-step-concl (h-index h-kexp h-layer h-position h-sbegin h-spayload h-vexp i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-sbl o-sbr o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (if (and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))
      (and (stg-fact-entry h-kexp h-layer h-position h-sbegin h-vexp i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr r-k-state-q)
           (stg-fact-stay h-index h-sbegin h-spayload i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
           (stg-fact-last h-index h-sbegin h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
           (stg-fact-begin h-sbegin n-k-state-q o-sbl o-sbr r-k-state-q))
    t))
(in-theory (disable stg-step-concl))

; ===========================================================================
; The step lemma for one symbolic cycle.
; ===========================================================================
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm stg-step-svtv-thm
     :svtv staging-step-run
     :svtv-spec staging-step-spec
     :input-vars :all
     :output-vars (o-pfn o-tpf o-epf o-spr o-spl o-sbr o-sbl n-k-state-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-expected-coordinate-q n-k-write-head-q n-k-write-word-q n-k-write-aborted-q)
     :unsigned-byte-hyps t
     :no-integerp t
     :enable (stg-int-o-pfn-integerp stg-int-o-tpf-integerp stg-int-o-epf-integerp stg-int-o-spr-integerp stg-int-o-spl-integerp stg-int-o-sbr-integerp stg-int-o-sbl-integerp stg-int-n-k-state-q-integerp stg-int-n-k-pending-layer-q-integerp stg-int-n-k-pending-position-q-integerp stg-int-n-k-pending-key-exponents-q-integerp stg-int-n-k-pending-value-exponents-q-integerp stg-int-n-k-expected-coordinate-q-integerp stg-int-n-k-write-head-q-integerp stg-int-n-k-write-word-q-integerp stg-int-n-k-write-aborted-q-integerp)
     :override-vars (r-p-lock-meta r-p-lock-sync r-p-cfb r-p-apprel r-m-rel r-k-state-q r-k-pending-issued-q r-k-pending-returned-q r-k-pending-read-pending-q r-k-committed-prefix-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-expected-coordinate-q r-k-pending-persisted-q r-k-write-head-q r-k-write-word-q r-k-write-aborted-q r-k-response-kind-q r-k-response-head-q r-k-response-layer-q r-k-response-position-q r-k-response-fault-q r-k-response-from-pending-q r-k-read-word-q r-k-read-return-word-q r-k-read-outstanding-q r-k-read-issue-done-q r-k-read-aborted-q r-k-read-physical-kind-q r-k-read-epoch-q r-k-read-received-mask-q r-k-cache-valid-q r-k-cache-kind-q r-k-cache-layer-q r-k-cache-position-q r-k-cache-tag-epoch-q r-k-cache-epoch-q r-k-cache-clear-seen-q r-k-cache-issued-q r-k-cache-returned-q r-k-cache-read-pending-q r-k-cache-copy-kind-q r-k-lock-seen-q r-k-fault-q r-k-stage-begin-consumed-q r-k-stage-payload-consumed-q r-k-commit-consumed-q r-k-attention-req-consumed-q r-b-crel r-b-arel r-b-lock-meta r-b-lock-sync r-b-afc-meta r-b-afc-sync r-b-cfa-meta r-b-cfa-sync r-b-fault r-b-lock-seen r-b-clr-seen r-b-clr-pend r-b-clr-drained r-b-epoch r-b-out r-b-mstall r-b-wstall r-b-wstallf r-b-rstall r-q-wb r-q-wg r-q-full r-q-rb r-q-rg r-q-rs1 r-q-rs2 r-q-ws1 r-q-ws2 r-q-mv r-q-sf r-q-spf r-q-df r-q-st r-q-md r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4 r-q-mem5 r-q-mem6 r-q-mem7 r-s-wb r-s-wg r-s-full r-s-rb r-s-rg r-s-rs1 r-s-rs2 r-s-ws1 r-s-ws2 r-s-mv r-s-sf r-s-spf r-s-df r-s-st r-s-md r-s-mem0 r-s-mem1 r-s-mem2 r-s-mem3 r-s-mem4 r-s-mem5 r-s-mem6 r-s-mem7 r-q-mdw r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3 r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 r-a-fault r-a-lock-seen r-a-offer r-a-offer-write r-a-poison r-a-offer-slot r-a-reserved r-a-unissued r-a-readcount r-a-head r-a-tail r-a-issue r-a-rhead r-a-rtail r-a-kind0 r-a-kind1 r-a-kind2 r-a-kind3 r-a-kind4 r-a-kind5 r-a-kind6 r-a-kind7 r-a-epoch0 r-a-epoch1 r-a-epoch2 r-a-epoch3 r-a-epoch4 r-a-epoch5 r-a-epoch6 r-a-epoch7 r-a-reject0 r-a-reject1 r-a-reject2 r-a-reject3 r-a-reject4 r-a-reject5 r-a-reject6 r-a-reject7 r-a-done0 r-a-done1 r-a-done2 r-a-done3 r-a-done4 r-a-done5 r-a-done6 r-a-done7 r-a-sfault0 r-a-sfault1 r-a-sfault2 r-a-sfault3 r-a-sfault4 r-a-sfault5 r-a-sfault6 r-a-sfault7 r-a-word0 r-a-word1 r-a-word2 r-a-word3 r-a-word4 r-a-word5 r-a-word6 r-a-word7 r-a-rslot0 r-a-rslot1 r-a-rslot2 r-a-rslot3 r-a-rslot4 r-a-rslot5 r-a-rslot6 r-a-rslot7 h-arbfail h-shellterm h-shellfail h-layerfail h-auth h-mcdc h-kupf h-layer h-position h-kexp h-vexp h-sbegin h-spayload h-index h-key h-value h-commit h-attn h-attn-kind h-attn-pos h-attn-head h-attn-ready h-epready h-eprspv h-eprsperr h-eprspdata h-rspdata h-appup h-legal r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-rd0 r-k-rd1 r-k-rd2 r-k-rd3 r-k-rd4 r-k-rd5 r-k-rd6 r-k-rd7 r-k-offer r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-memd0 r-q-memd1 r-q-memd2 r-q-memd3 r-q-memd4 r-q-memd5 r-q-memd6 r-q-memd7 r-q-mdd r-q-mdp r-a-saddr r-a-sdata r-a-oaddr r-a-odata)
     :spec-override-vars ()
     :hyp (and (and (joint-inv-p
                    r-p-lock-meta r-p-lock-sync r-p-cfb r-p-apprel r-m-rel
                    r-k-state-q r-k-pending-issued-q r-k-pending-returned-q
                    r-k-pending-read-pending-q r-k-committed-prefix-q
                    r-k-pending-layer-q r-k-pending-position-q
                    r-k-pending-key-exponents-q r-k-pending-value-exponents-q
                    r-k-expected-coordinate-q r-k-pending-persisted-q
                    r-k-write-head-q r-k-write-word-q r-k-write-aborted-q
                    r-k-response-kind-q r-k-response-head-q
                    r-k-response-layer-q r-k-response-position-q
                    r-k-response-fault-q r-k-response-from-pending-q
                    r-k-read-word-q r-k-read-return-word-q
                    r-k-read-outstanding-q r-k-read-issue-done-q
                    r-k-read-aborted-q r-k-read-physical-kind-q
                    r-k-read-epoch-q r-k-read-received-mask-q
                    r-k-cache-valid-q r-k-cache-kind-q r-k-cache-layer-q
                    r-k-cache-position-q r-k-cache-tag-epoch-q
                    r-k-cache-epoch-q r-k-cache-clear-seen-q
                    r-k-cache-issued-q r-k-cache-returned-q
                    r-k-cache-read-pending-q r-k-cache-copy-kind-q
                    r-k-lock-seen-q r-k-fault-q r-k-stage-begin-consumed-q
                    r-k-stage-payload-consumed-q r-k-commit-consumed-q
                    r-k-attention-req-consumed-q r-b-crel r-b-arel
                    r-b-lock-meta r-b-lock-sync r-b-afc-meta r-b-afc-sync
                    r-b-cfa-meta r-b-cfa-sync r-b-fault r-b-lock-seen
                    r-b-clr-seen r-b-clr-pend r-b-clr-drained r-b-epoch
                    r-b-out r-b-mstall r-b-wstall r-b-wstallf r-b-rstall
                    r-q-wb r-q-wg r-q-full r-q-rb r-q-rg r-q-rs1 r-q-rs2
                    r-q-ws1 r-q-ws2 r-q-mv r-q-sf r-q-spf r-q-df r-q-st
                    r-q-md r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4
                    r-q-mem5 r-q-mem6 r-q-mem7 r-s-wb r-s-wg r-s-full r-s-rb
                    r-s-rg r-s-rs1 r-s-rs2 r-s-ws1 r-s-ws2 r-s-mv r-s-sf
                    r-s-spf r-s-df r-s-st r-s-md r-s-mem0 r-s-mem1 r-s-mem2
                    r-s-mem3 r-s-mem4 r-s-mem5 r-s-mem6 r-s-mem7 r-q-mdw
                    r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3 r-q-memw4
                    r-q-memw5 r-q-memw6 r-q-memw7 r-a-fault r-a-lock-seen
                    r-a-offer r-a-offer-write r-a-poison r-a-offer-slot
                    r-a-reserved r-a-unissued r-a-readcount r-a-head r-a-tail
                    r-a-issue r-a-rhead r-a-rtail r-a-kind0 r-a-kind1
                    r-a-kind2 r-a-kind3 r-a-kind4 r-a-kind5 r-a-kind6
                    r-a-kind7 r-a-epoch0 r-a-epoch1 r-a-epoch2 r-a-epoch3
                    r-a-epoch4 r-a-epoch5 r-a-epoch6 r-a-epoch7 r-a-reject0
                    r-a-reject1 r-a-reject2 r-a-reject3 r-a-reject4
                    r-a-reject5 r-a-reject6 r-a-reject7 r-a-done0 r-a-done1
                    r-a-done2 r-a-done3 r-a-done4 r-a-done5 r-a-done6
                    r-a-done7 r-a-sfault0 r-a-sfault1 r-a-sfault2 r-a-sfault3
                    r-a-sfault4 r-a-sfault5 r-a-sfault6 r-a-sfault7 r-a-word0
                    r-a-word1 r-a-word2 r-a-word3 r-a-word4 r-a-word5
                    r-a-word6 r-a-word7 r-a-rslot0 r-a-rslot1 r-a-rslot2
                    r-a-rslot3 r-a-rslot4 r-a-rslot5 r-a-rslot6 r-a-rslot7)
                   (or (equal i-reset-n 1)
                       (joint-reset-p
                        r-p-lock-meta r-p-lock-sync r-p-cfb r-p-apprel
                        r-m-rel r-k-state-q r-k-pending-issued-q
                        r-k-pending-returned-q r-k-pending-read-pending-q
                        r-k-committed-prefix-q r-k-pending-layer-q
                        r-k-pending-position-q r-k-pending-key-exponents-q
                        r-k-pending-value-exponents-q
                        r-k-expected-coordinate-q r-k-pending-persisted-q
                        r-k-write-head-q r-k-write-word-q r-k-write-aborted-q
                        r-k-response-kind-q r-k-response-head-q
                        r-k-response-layer-q r-k-response-position-q
                        r-k-response-fault-q r-k-response-from-pending-q
                        r-k-read-word-q r-k-read-return-word-q
                        r-k-read-outstanding-q r-k-read-issue-done-q
                        r-k-read-aborted-q r-k-read-physical-kind-q
                        r-k-read-epoch-q r-k-read-received-mask-q
                        r-k-cache-valid-q r-k-cache-kind-q r-k-cache-layer-q
                        r-k-cache-position-q r-k-cache-tag-epoch-q
                        r-k-cache-epoch-q r-k-cache-clear-seen-q
                        r-k-cache-issued-q r-k-cache-returned-q
                        r-k-cache-read-pending-q r-k-cache-copy-kind-q
                        r-k-lock-seen-q r-k-fault-q
                        r-k-stage-begin-consumed-q
                        r-k-stage-payload-consumed-q r-k-commit-consumed-q
                        r-k-attention-req-consumed-q r-b-crel r-b-arel
                        r-b-lock-meta r-b-lock-sync r-b-afc-meta r-b-afc-sync
                        r-b-cfa-meta r-b-cfa-sync r-b-fault r-b-lock-seen
                        r-b-clr-seen r-b-clr-pend r-b-clr-drained r-b-epoch
                        r-b-out r-b-mstall r-b-wstall r-b-wstallf r-b-rstall
                        r-q-wb r-q-wg r-q-full r-q-rb r-q-rg r-q-rs1 r-q-rs2
                        r-q-ws1 r-q-ws2 r-q-mv r-q-sf r-q-spf r-q-df r-q-st
                        r-q-md r-s-wb r-s-wg r-s-full r-s-rb r-s-rg r-s-rs1
                        r-s-rs2 r-s-ws1 r-s-ws2 r-s-mv r-s-sf r-s-spf r-s-df
                        r-s-st r-s-md r-q-mdw r-a-fault r-a-lock-seen
                        r-a-offer r-a-offer-write r-a-poison r-a-offer-slot
                        r-a-reserved r-a-unissued r-a-readcount r-a-head
                        r-a-tail r-a-issue r-a-rhead r-a-rtail r-a-kind0
                        r-a-kind1 r-a-kind2 r-a-kind3 r-a-kind4 r-a-kind5
                        r-a-kind6 r-a-kind7 r-a-epoch0 r-a-epoch1 r-a-epoch2
                        r-a-epoch3 r-a-epoch4 r-a-epoch5 r-a-epoch6
                        r-a-epoch7 r-a-reject0 r-a-reject1 r-a-reject2
                        r-a-reject3 r-a-reject4 r-a-reject5 r-a-reject6
                        r-a-reject7 r-a-done0 r-a-done1 r-a-done2 r-a-done3
                        r-a-done4 r-a-done5 r-a-done6 r-a-done7 r-a-sfault0
                        r-a-sfault1 r-a-sfault2 r-a-sfault3 r-a-sfault4
                        r-a-sfault5 r-a-sfault6 r-a-sfault7 r-a-word0
                        r-a-word1 r-a-word2 r-a-word3 r-a-word4 r-a-word5
                        r-a-word6 r-a-word7))
                   (joint-env-p
                    h-arbfail h-shellterm h-shellfail h-layerfail h-auth
                    h-mcdc h-kupf h-layer h-position h-kexp h-vexp h-sbegin
                    h-spayload h-index h-key h-value h-commit h-attn
                    h-attn-kind h-attn-pos h-attn-head h-attn-ready h-epready
                    h-eprspv h-eprsperr h-eprspdata h-rspdata h-appup h-legal
                    r-q-mv r-a-readcount))
               (pay-inv-p r-k-state-q r-k-write-word-q r-k-write-head-q r-k-write-aborted-q r-k-pending-persisted-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-offer r-k-rd0 r-k-rd1 r-k-rd2 r-k-rd3 r-k-rd4 r-k-rd5 r-k-rd6 r-k-rd7 r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-q-wb r-q-rb r-q-mv r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-mdp r-q-memd0 r-q-memd1 r-q-memd2 r-q-memd3 r-q-memd4 r-q-memd5 r-q-memd6 r-q-memd7 r-q-mdd r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3 r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 r-q-mdw r-a-reserved r-a-head r-a-offer r-a-saddr r-a-sdata r-a-oaddr r-a-odata))
     :concl (and (stg-int-o-pfn o-pfn)
          (stg-int-o-tpf o-tpf)
          (stg-int-o-epf o-epf)
          (stg-int-o-spr o-spr)
          (stg-int-o-spl o-spl)
          (stg-int-o-sbr o-sbr)
          (stg-int-o-sbl o-sbl)
          (stg-int-n-k-state-q n-k-state-q)
          (stg-int-n-k-pending-layer-q n-k-pending-layer-q)
          (stg-int-n-k-pending-position-q n-k-pending-position-q)
          (stg-int-n-k-pending-key-exponents-q n-k-pending-key-exponents-q)
          (stg-int-n-k-pending-value-exponents-q n-k-pending-value-exponents-q)
          (stg-int-n-k-expected-coordinate-q n-k-expected-coordinate-q)
          (stg-int-n-k-write-head-q n-k-write-head-q)
          (stg-int-n-k-write-word-q n-k-write-word-q)
          (stg-int-n-k-write-aborted-q n-k-write-aborted-q)
          (stg-step-concl h-index h-kexp h-layer h-position h-sbegin h-spayload h-vexp i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-sbl o-sbr o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q))))
  (value-triple (acl2::cw "~%STG-STEP-LEMMA proved~%")))

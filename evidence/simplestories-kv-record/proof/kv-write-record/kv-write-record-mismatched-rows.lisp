; Negative control: a controller that pairs a K row with the V row of another position.
;
; Written by make_record_book.py; do not edit.  Private.
;
; The RTL here is the pinned RTL with one line added to the K/V controller
; (mismatched-rows.patch): at the step from the K row's last word to the V
; row, pending_position_q is incremented.  The V row of a record is then
; written to the V addresses of the next position.  Each row, taken alone,
; is still what the row theorem of the payload book asks: nine writes, in
; order, equal to the row's nine words as the controller holds them when
; that row starts.  The record is wrong: its two rows belong to different
; positions.  Three things are certified here.
;   1. The scripted run of kv-write-record.lisp, on this RTL, completes and
;      raises pending_persisted_q.
;   2. On that run each row alone passes, and the record fails: the
;      eighteen accepted writes are not the record held at the record's
;      start, the held record changes during the write, and the nine V
;      writes are the staged V words at addresses 18 too high.
;   3. The proof of the new step lemma, the one that succeeds for the pinned
;      RTL, fails, with a counterexample the prover verifies.
; If the patch were not applied this book would not certify.
(in-package "SV")
(include-book "centaur/sv/svtv/svtv-to-fsm-defs" :dir :system)
(include-book "centaur/fgl/top" :dir :system)
(include-book "centaur/sv/svtv/svtv-stobj-defsvtv" :dir :system)
(include-book "centaur/vl/loader/top" :dir :system)
(include-book "centaur/sv/vl/top" :dir :system)
(include-book "oslib/ls" :dir :system)
(include-book "centaur/sv/svtv/svtv-stobj-debug" :dir :system)
(include-book "centaur/misc/memory-mgmt" :dir :system)
(include-book "std/testing/must-fail" :dir :system)
(include-book "../kv-joined-book-checked-sat/kv-joined-statements")
(include-book "../kv-joined-book-checked-sat/kv-joined-pins")

(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
; The library's generated lemmas about a run with several hundred named
; signals nest deeper than the rewriter's default limit of 1000.
(acl2::set-rewrite-stack-limit 20000)

; The SAT solver, as in the payload book.  No answer of the solver is
; believed: with :lrat-check t the library reports "unsatisfiable" only
; after ACL2 has run its verified checker (projects/sat/lrat) on the proof
; the solver wrote, against the formula ACL2 itself wrote; "satisfiable"
; only after ACL2 has evaluated the formula under the assignment.
(defun rec-satlink-config ()
  (declare (xargs :guard t))
  (satlink::make-config :cmdline "sh sat/cadical-lrat.sh" :verbose nil
                        :mintime 0 :remove-temps t :lrat-check t))
(defthm kv-write-record-sat-proofs-are-checked
  (equal (satlink::config->lrat-check (rec-satlink-config)) t)
  :rule-classes nil)
(defattach fgl::fgl-satlink-config rec-satlink-config)
(value-triple (acl2::tshell-ensure))

; ---------------------------------------------------------------------------
; The RTL: the parent's pinned files, with the K/V controller taken from
; rtl-mismatched-rows/ (mismatched-rows.patch: one line added).
; ---------------------------------------------------------------------------
(defconst *kvj-rtl-files*
  '(
    "../kv-joined-book-checked-sat/rtl/defines.v"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_isqrt_u45_iterative.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_rne_div_signed64_iterative.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_private_issue_guard.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_unified_dsp64.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/ddr_phy_open0/rtl/board1_private_ddr256_to_w640.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_rne_div_signed64.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_attention_compact1/rtl/board1_fixed_attention_rne_shift_iterative.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise0/rtl/board1_fixed_elementwise_dsp_lane.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_dsp.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_compact_lane.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine1/rtl/board1_fixed_elementwise_lane_core.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_group_ddr_stream1/rtl/board1_fixed_group_ddr_stream.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_group_projection_scale_integration0/rtl/board1_fixed_group_projection_scale_job.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_argmax.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_logit_greater.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_metadata_stream0/rtl/board1_fixed_projection_metadata_reader.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_scratch_ram.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector128_ram.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector256_ram.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_rope_raw_ram.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_token_shell0/rtl/board1_fixed_embedding_lookup.sv"
    "../kv-joined-book-checked-sat/rtl/normalizer_pipeline.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_normalize0/rtl/board1_fixed_vector_rne_shift_iterative.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_arithmetic.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_rom.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_vector_rmsnorm_service.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/shared_projection_scale0/rtl/board1_shared_projection_scale_engine.sv"
    "../kv-joined-book-checked-sat/rtl/cluster-adapter.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/unified_dsp0/rtl/board1_unified_projection_head_mul_exact.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/unified_dynamic_dsp1/rtl/board1_unified_projection_head_dynamic_mul_exact.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine0/rtl/board1_fixed_private_ddr_arbiter.sv"
    "../kv-joined-book-checked-sat/rtl/fifo.sv"
    "../kv-joined-book-checked-sat/rtl/mapper_portable.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_app_boundary.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_boundary.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention_memories.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention.sv"
    "rtl-mismatched-rows/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_lookup.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_sequence.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_layer.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_machine_core.sv"
    "../kv-joined-book-checked-sat/rtl/shared_token_probe.sv"
    "../kv-joined-book-checked-sat/rtl/sha.sv"
    "../kv-joined-book-checked-sat/rtl/bank.sv"
    "../kv-joined-book-checked-sat/rtl/service.sv"
    "../kv-joined-book-checked-sat/rtl/cluster-mul.sv"
    "../kv-joined-book-checked-sat/rtl/cluster-tile.sv"
    "../kv-joined-book-checked-sat/rtl/cluster-engine.sv"
    "../kv-joined-book-checked-sat/rtl/candidate.sv"
    "../kv-joined-book-checked-sat/rtl/arbiter.sv"
    "../kv-joined-book-checked-sat/rtl/cdc.sv"
    "../kv-joined-book-checked-sat/rtl/adapter.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_private_ddr_lock_bridge.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_ddr_preboard_locked_boundary.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_ddr_locked_auth_watchdog_cdc.sv"
    "../kv-joined-book-checked-sat/rtl/handoff.sv"
    "../kv-joined-book-checked-sat/rtl/booted_memory.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_qspi_read03_master.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_qspi_async_word_fifo4.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_qspi_image_stream.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_rx.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_tx.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_command_adapter.sv"
    "../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_endpoint_fault_cdc.sv"
    "../kv-joined-book-checked-sat/rtl/reset.sv"
    "../kv-joined-book-checked-sat/rtl/uart_core.sv"
    "../kv-joined-book-checked-sat/rtl/thin_transport.sv"
    "../kv-joined-book-checked-sat/rtl/top.sv"
    ))

(defconst *kvj-rtl-sha256-pinned*
  '(
    ("../kv-joined-book-checked-sat/rtl/defines.v"
     . "4be31be33f0a15bf617e98aa6bbf465f3820603aec4302b8f9d28e5e0ae7420c")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_isqrt_u45_iterative.sv"
     . "307d3a01aab81015cc72360c70b1569895b5632d2f5bd12d40f26f998fb4d4a0")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_rne_div_signed64_iterative.sv"
     . "ae9d3077ae11693bfe67d8f0ef0f5c89bd3581ab6df2160aa63dbdebb6294707")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_private_issue_guard.sv"
     . "2335a5473e6f3e5bb71d3c64d136c5d1fb5cf0f8d73b5b907b4c1871c07f2755")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_unified_dsp64.sv"
     . "a82b7d0c9f97932c5205e2fe902e27ab341c15438f25bf067cb2b1a0a8cf43c4")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/ddr_phy_open0/rtl/board1_private_ddr256_to_w640.sv"
     . "1b35784af0052d923abcb5c6a57303252ef352774abc90d566d23ee0d6c8bd93")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv"
     . "71c528cd039ea3afd3d799ae44cdcb273c839a9c3ccbaf4c9c2b5d47c226388c")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_rne_div_signed64.sv"
     . "9137e2a36a27f9956bc9ecfdcbbbe3d1d4670dbd6fac2b2990653ff1eb79c236")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_attention_compact1/rtl/board1_fixed_attention_rne_shift_iterative.sv"
     . "91afdd7fb4e77f8f409bfdb20676e22ac365056d45f746b77c6eeefc191667b6")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise0/rtl/board1_fixed_elementwise_dsp_lane.sv"
     . "b892d1880c12e5dfe25f0df1c31e69e399b2d6395a906246c29cdec8c47aa766")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_dsp.sv"
     . "442e19ecee47bdab0c2e44536d3cb3663019077939aca1e23420ac7eaac8d30c")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_compact_lane.sv"
     . "ce337d8b56ebd3a91bf2788aa73ac13ecc6aff45a600447b51f87e795293b931")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine1/rtl/board1_fixed_elementwise_lane_core.sv"
     . "b6d795d540a3f6eac25cd2d783fc7bcb4e31edc5e7303e987ae4f5a153c7c199")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_group_ddr_stream1/rtl/board1_fixed_group_ddr_stream.sv"
     . "3ec7ab00aa43a5950e36be5f16edabf7250692488f1f69da348bcd22b75243b1")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_group_projection_scale_integration0/rtl/board1_fixed_group_projection_scale_job.sv"
     . "c5bd334b7a550cf33a2019d28f234c757415e1c2642f6e3862ffb62cfcd60a10")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_argmax.sv"
     . "2e66294ebc8be89651da3861d8c9200a9a1e689628630ae40a3cd6670bfe378d")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_logit_greater.sv"
     . "568a0db90018c50697072fce190ef448ab792f943fff906bd0113eb4630832d5")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_metadata_stream0/rtl/board1_fixed_projection_metadata_reader.sv"
     . "18f039839b7e91d41ddefbd20812a2114b99c58773d8cc577dd29f02f012d4e1")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_scratch_ram.sv"
     . "2fa8cb1f42f59262ff4183180aaf80336d877f527a2e103661ce9fe94d621bd7")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector128_ram.sv"
     . "4a51f313fe07d9af9b45f08af6c51a6f0952f98be74e29ffe8a320a6780e07d6")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector256_ram.sv"
     . "8d8ab1fc9d4e638b6ef13a0da50e22f65fcfb844bc6950ca88a09a466aad31f2")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_rope_raw_ram.sv"
     . "3238dc4454b9e37d54252c9cf2101e58cfaca527bff93dbad785667531e435fc")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_token_shell0/rtl/board1_fixed_embedding_lookup.sv"
     . "266f25879a3cc51424e6b71f46a5a1a62eab6b29c3c39c748bc4fc51de7d07ba")
    ("../kv-joined-book-checked-sat/rtl/normalizer_pipeline.sv"
     . "2c4f052ffcbdaba1c9b9b23035b39f3fb24ecbfd081edd45ca8d996f0c9ec028")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_normalize0/rtl/board1_fixed_vector_rne_shift_iterative.sv"
     . "12c73c9f2100212b87b9982e7ed43739db06c4a5376d4788cc08f391b61131ab")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_arithmetic.sv"
     . "375e5eef4069c1314103d98d562d6b31269a16eed4cb9e979358b7398ce05818")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_rom.sv"
     . "9f1b436fefe63a80a0ee1d8ef1766812d42749a1f9d2ff1b7958fa98e1438e73")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_vector_rmsnorm_service.sv"
     . "c4d1046ae5b0da5f2ed95ee684f59b637d93d4350db550f19a321773935874fb")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/shared_projection_scale0/rtl/board1_shared_projection_scale_engine.sv"
     . "52fd2d82ed6d80a77f5252a3437eac4661c13e4deccb03a9b68fbf1d2eec2bb4")
    ("../kv-joined-book-checked-sat/rtl/cluster-adapter.sv"
     . "ceece65290b18868e693009917b933c5259515d96ac7bbadf09efbb9ba9998ab")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/unified_dsp0/rtl/board1_unified_projection_head_mul_exact.sv"
     . "8385ac32fcd8037bd4f4722330949fddd88d5eaa5175155d903a86b76f39c2b9")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/unified_dynamic_dsp1/rtl/board1_unified_projection_head_dynamic_mul_exact.sv"
     . "be50b7539cb4e6518bd5f98e738d9fd8a9067fbe94a923cdc40857652505768c")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine0/rtl/board1_fixed_private_ddr_arbiter.sv"
     . "0bb8c9b269a6e7cd9e0a5ddac1e69b737de4031fca1d8da24ea6f3d6a25cc286")
    ("../kv-joined-book-checked-sat/rtl/fifo.sv"
     . "e742e2ebcce91154ff96892c32dc297bf1c1460a73b9de73eac1a8a4161f926f")
    ("../kv-joined-book-checked-sat/rtl/mapper_portable.sv"
     . "89e6de98bc965d0786d58cb56d1562d0448f95d342395a8badca35f4326428e1")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_app_boundary.sv"
     . "020fb750570e0a79537204a5cdb1ecace8ebf86711cf085f4f3d2247ce32b9e0")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_boundary.sv"
     . "d030fc7fcee27c1b2fddd3503ad9a3d2160b4af4df393393c5b727e7571369f1")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention_memories.sv"
     . "0210df9e549f44e1c71ed2ee4c9c3c6051c6b62c4c6f3bdbddaa6adb46d3e6ff")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention.sv"
     . "c310723548a61b48d19937de229ad349bd69901797916e18d1ff7bd6431f1a68")
    ("rtl-mismatched-rows/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv"
     . "c65adc9ba58678b9c420eae431ce9a8dff07d24fe67c9579c074831d6432f58e")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_lookup.sv"
     . "ec9cd7c0fd9982bdee31c0193d345821b266e68fcffc3693be1aea9bff5e297e")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_sequence.sv"
     . "2310be898bde68d1b824335f36147785d88b0a398906bc9488aedef70a1c3fc0")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv"
     . "020600127fe68203340e86d219de0f41d3d5210d8276b561a1ecde229d4987c6")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_layer.sv"
     . "9a5e3350773efdd8da29821bc8b936b57d2ba1287c10e863d010e30345755612")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv"
     . "b76ca530210fa416577410c1038d2d2f5ee16452ce39cabf8be2a3f7ead2d250")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_machine_core.sv"
     . "6432b4ef168ad61618e9994bc96a6c9172c60eca13f148fc0c2ecca80d03089a")
    ("../kv-joined-book-checked-sat/rtl/shared_token_probe.sv"
     . "c8681158676072106fa1f4072573813849d35744b1c723acb872a23ea0c49af0")
    ("../kv-joined-book-checked-sat/rtl/sha.sv"
     . "512a7d09bbcb30bb01a4dc6102590afe6eb886db5a27b1576a71f5577727768b")
    ("../kv-joined-book-checked-sat/rtl/bank.sv"
     . "00b1cc227e444f91af8ac3a8f374af8f2b1a5b14884ca51f46c312bbc970d6d6")
    ("../kv-joined-book-checked-sat/rtl/service.sv"
     . "a33e45de9d24668f105971bdfe8902882f793fa508c570c9bb0b5ce34a020403")
    ("../kv-joined-book-checked-sat/rtl/cluster-mul.sv"
     . "17dc41f46dd535434bf0f7da503218e61289dd63ea7409f4e687f38bf0615267")
    ("../kv-joined-book-checked-sat/rtl/cluster-tile.sv"
     . "60e79557fb67981cc4ad3f342c363b29a49456c482eea3de37ab40bc078b3068")
    ("../kv-joined-book-checked-sat/rtl/cluster-engine.sv"
     . "232949abf47d652df2f6c420f96445aed86e44c44d0e6481a28d522658a54b6f")
    ("../kv-joined-book-checked-sat/rtl/candidate.sv"
     . "92e265e267dcc1c988da340b9d6845332c8f67333f389412d3f9454ccb897479")
    ("../kv-joined-book-checked-sat/rtl/arbiter.sv"
     . "770f643a9b026904465c58f3c327a34ff124c9db0f41a833804491e2e776e76b")
    ("../kv-joined-book-checked-sat/rtl/cdc.sv"
     . "dbf6be77bdfeb952ea433ba2b27c3177b8f86f0ea11103dae7ea5f52efebe0ef")
    ("../kv-joined-book-checked-sat/rtl/adapter.sv"
     . "96c4d8eca498cf19687ba35c80e981b0122ba04345ca9ab399e969a894647cad")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_private_ddr_lock_bridge.sv"
     . "b801c921f7c0cf359fe33b04030f6701f43e4e9df24a9f04d92384a5ee1b0095")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv"
     . "c7b6eb47fd8b73d804d92651b950eb63fd896e2503b8efc7dc8b6985850c5c05")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_ddr_preboard_locked_boundary.sv"
     . "7c7582d45693e6abac33d9be91cbe64da832f0f358ab3c60450c00cddcf293c3")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv"
     . "0a3a8333213fb4f8fe4ee3ca17af6efb95bad61577c3c6f00233bb7ed875a59f")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_ddr_locked_auth_watchdog_cdc.sv"
     . "5262346f446d4e0fd7a982214652306d7dec94f2e8c43f9d909d67bde122782a")
    ("../kv-joined-book-checked-sat/rtl/handoff.sv"
     . "edca5ac4866b3ba2bdb96e47ac8d0b1ec56c3e890f1e328cf20d746d1c9d14f1")
    ("../kv-joined-book-checked-sat/rtl/booted_memory.sv"
     . "5e5c7081db529f581a421c48765db330a8bcdedecb95b0d98d356ffb973ad363")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_qspi_read03_master.sv"
     . "77ec76f2080e2bf7089c0fed001780e9d55703a5323ab951e0a0bc556523e161")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_qspi_async_word_fifo4.sv"
     . "47852af52c54917fd67bb7da0c76238a922ad7f33f2702ac812d0c9b35a94a47")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_qspi_image_stream.sv"
     . "7975f7c9835afda6561f11c2d026ada15e3f1003df129fe82aa20e2aa664b642")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_rx.sv"
     . "488bde775088037dd8aed998f4beef76e121ab2917d3f776359e99cc4b2c5739")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_tx.sv"
     . "48477b86e217a049ee912e3ace9ae4b3a4e5d6227f2b27f4f832330ff05fa527")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv"
     . "87abc248c3f154ac23ff78739aacfd21db10c277fbc2de75fca0129c403d0b0c")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_command_adapter.sv"
     . "2f788b202d2972238bb45076df61bb0e5f1dc40e790d9504c770a29adc121e56")
    ("../kv-joined-book-checked-sat/rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_endpoint_fault_cdc.sv"
     . "dd47d5fcb370002721ddb4accbab92d7572a723c994a8e04d97947215a39bea6")
    ("../kv-joined-book-checked-sat/rtl/reset.sv"
     . "06f46a593a7544ff16f931ff3e544c2bcbf3c2420ed5d6b0d33bfae6a45cf4fa")
    ("../kv-joined-book-checked-sat/rtl/uart_core.sv"
     . "6eac2d6506077023432fef601b458134007e619f5c9a026fed9729eabbb9f273")
    ("../kv-joined-book-checked-sat/rtl/thin_transport.sv"
     . "7deea87338c8c2160247bdb68961aed8513cb483a18450f38859f7edbeba46ed")
    ("../kv-joined-book-checked-sat/rtl/top.sv"
     . "2a58277179bb43d830099deca5529f9c269c7c4d64791fc9df22efcc1165c675")
    ))

; The Verilog loader reads the files; the SHA-256 of each is computed from
; the very text the loader read.
(encapsulate nil
  (local
   (defconsts (*vl-design* *kvj-digests* state)
     (b* (((mv (vl::vl-loadresult loadres) state)
           (vl::vl-load (vl::make-vl-loadconfig :start-files *kvj-rtl-files*))))
       (mv loadres.design
           (kvj-read-and-pinned *kvj-rtl-files* loadres.filemap)
           state))))
  (local
   (defconsts (*kvj-sv-design* *vl-good* *vl-bad*)
     (b* (((mv errmsg svex good bad)
           (vl::vl-design->sv-design "board1_context2048_shared_token_probe"
                                     *vl-design* (vl::make-vl-simpconfig))))
       (and errmsg (raise "~@0~%" errmsg))
       (mv svex good bad))))
  (make-event `(defconst *kvj-rtl-sha256-as-read* ',*kvj-digests*))
  (make-event `(defconst *sv-design* ',*kvj-sv-design*)))

(defthm kv-write-record-mismatched-rows-rtl-is-the-pinned-rtl
  (equal *kvj-rtl-sha256-as-read* *kvj-rtl-sha256-pinned*)
  :rule-classes nil)

(defconsts (*kvj-translator-sha256-when-translating* state)
  (mv (kvj-translator-sha256 state) state))

(defthm kv-write-record-mismatched-rows-rtl-was-translated-by-the-corrected-translator
  (equal *kvj-translator-sha256-when-translating* *kvj-translator-sha256-pinned*)
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The staged record as the controller holds it, and where a word of it goes.
; A whole array is one number here; RTL element e of an array of n elements
; of width k is bits [(n-1-e)*k +: k] of it (checked by a concrete run).
; ---------------------------------------------------------------------------
(define pay-word32 (bank a) :verify-guards nil
  (loghead 32 (logtail (* 32 (- 31 a)) bank)))

; Slot a of the pair store: the eight banks' words at address a, bank 0 lowest.
(define pay-slot (a b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (logapp 32 (pay-word32 b0 a) (logapp 32 (pay-word32 b1 a)
  (logapp 32 (pay-word32 b2 a) (logapp 32 (pay-word32 b3 a)
  (logapp 32 (pay-word32 b4 a) (logapp 32 (pay-word32 b5 a)
  (logapp 32 (pay-word32 b6 a) (pay-word32 b7 a)))))))))

; The eight keys (h = 0) or the eight values (h = 1) of a slot: a pair is
; {value, key}, sixteen bits each.
(define pay-half (slot h) :verify-guards nil
  (if (equal h 1)
      (logapp 16 (logtail 16 slot) (logapp 16 (logtail 48 slot)
      (logapp 16 (logtail 80 slot) (logapp 16 (logtail 112 slot)
      (logapp 16 (logtail 144 slot) (logapp 16 (logtail 176 slot)
      (logapp 16 (logtail 208 slot) (loghead 16 (logtail 240 slot)))))))))
    (logapp 16 slot (logapp 16 (logtail 32 slot)
    (logapp 16 (logtail 64 slot) (logapp 16 (logtail 96 slot)
    (logapp 16 (logtail 128 slot) (logapp 16 (logtail 160 slot)
    (logapp 16 (logtail 192 slot) (loghead 16 (logtail 224 slot)))))))))))

; The first and second slot of row word w (w < 8): slots 8+2w and 9+2w.
(define pay-slot-a (w b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (cond ((equal w 0) (pay-slot 8 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 1) (pay-slot 10 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 2) (pay-slot 12 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 3) (pay-slot 14 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 4) (pay-slot 16 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 5) (pay-slot 18 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 6) (pay-slot 20 b0 b1 b2 b3 b4 b5 b6 b7))
        (t (pay-slot 22 b0 b1 b2 b3 b4 b5 b6 b7))))
(define pay-slot-b (w b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (cond ((equal w 0) (pay-slot 9 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 1) (pay-slot 11 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 2) (pay-slot 13 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 3) (pay-slot 15 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 4) (pay-slot 17 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 5) (pay-slot 19 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 6) (pay-slot 21 b0 b1 b2 b3 b4 b5 b6 b7))
        (t (pay-slot 23 b0 b1 b2 b3 b4 b5 b6 b7))))

; Word w of row h of the staged record: sixteen coordinates for w < 8, the
; row's two exponent bytes under 240 zero bits for w = 8.
(define pay-data (w h ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (if (equal w 8)
      (loghead 16 (if (equal h 1) ve ke))
    (logapp 128
            (pay-half (pay-slot-a w b0 b1 b2 b3 b4 b5 b6 b7) h)
            (pay-half (pay-slot-b w b0 b1 b2 b3 b4 b5 b6 b7) h))))

; Its address: 227072 + 9 * row + w, row = 2 * (2048 * layer + position) + h.
(define pay-addr (l p h w) :verify-guards nil
  (b* ((row (+ (ash (+ (ash l 11) (loghead 11 p)) 1) h)))
    (loghead 19 (+ 227072 (ash row 3) row w))))

; Element e of the app side's arrays, and the request FIFO's cell.
(define pay-el256 (e x) :verify-guards nil
  (cond ((equal e 0) (loghead 256 (logtail 1792 x)))
        ((equal e 1) (loghead 256 (logtail 1536 x)))
        ((equal e 2) (loghead 256 (logtail 1280 x)))
        ((equal e 3) (loghead 256 (logtail 1024 x)))
        ((equal e 4) (loghead 256 (logtail 768 x)))
        ((equal e 5) (loghead 256 (logtail 512 x)))
        ((equal e 6) (loghead 256 (logtail 256 x)))
        (t (loghead 256 x))))
(define pay-el19 (e x) :verify-guards nil
  (cond ((equal e 0) (loghead 19 (logtail 133 x)))
        ((equal e 1) (loghead 19 (logtail 114 x)))
        ((equal e 2) (loghead 19 (logtail 95 x)))
        ((equal e 3) (loghead 19 (logtail 76 x)))
        ((equal e 4) (loghead 19 (logtail 57 x)))
        ((equal e 5) (loghead 19 (logtail 38 x)))
        ((equal e 6) (loghead 19 (logtail 19 x)))
        (t (loghead 19 x))))
(define pay-cell (i m0 m1 m2 m3 m4 m5 m6 m7) :verify-guards nil
  (cond ((equal i 0) m0) ((equal i 1) m1) ((equal i 2) m2) ((equal i 3) m3)
        ((equal i 4) m4) ((equal i 5) m5) ((equal i 6) m6) (t m7)))

; An entry of the request FIFO that carries the word the controller waits on:
; desc is its descriptor (head, position, layer, model word), word its row
; word, x its address and data.  The entry is consistent in itself, whether
; or not CLEAR has interrupted the write: it is word w, its data is the
; offer, and its address is the one its own descriptor specifies.  Unless
; CLEAR has interrupted the write, the descriptor is the controller's.
(define pay-entry-p (desc word x offer w l p h ab) :verify-guards nil
  (b* ((eh (loghead 2 desc))
       (ep (loghead 12 (logtail 2 desc)))
       (el (loghead 3 (logtail 14 desc))))
    (and (equal (logtail 17 desc) 0)
         (< el 6) (< ep 2048) (< eh 2)
         (equal word w)
         (equal (loghead 256 x) offer)
         (equal (logtail 256 x) (pay-addr el ep eh w))
         (or (not (equal ab 0))
             (and (equal el l) (equal ep p) (equal eh h))))))

; The address the waited-on word carries, wherever it is: in the request
; FIFO, or in the app side's slot.
(define pay-carried-addr (wb rb cell head saddr) :verify-guards nil
  (if (equal wb rb) (pay-el19 head saddr) (logtail 256 cell)))

; A carried request is the word the controller offered, and, unless CLEAR has
; interrupted the write, sits at the word's address.
(define pay-carried-p (data19-256 offer addr ab) :verify-guards nil
  (and (equal (loghead 256 data19-256) offer)
       (or (not (equal ab 0))
           (equal (loghead 19 (logtail 256 data19-256)) addr))))

; THE PAYLOAD INVARIANT.
(define pay-inv-p (st w h ab per l p ke ve offer rd0 rd1 rd2 rd3 rd4 rd5 rd6 rd7
                   b0 b1 b2 b3 b4 b5 b6 b7
                   wb rb mv m0 m1 m2 m3 m4 m5 m6 m7 md
                   d0 d1 d2 d3 d4 d5 d6 d7 mdd mw0 mw1 mw2 mw3 mw4 mw5 mw6 mw7 mdw
                   res head offq saddr sdata oaddr odata)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t :normalize nil
  (b* ((st (4vec->upper st))
       (w (4vec->upper w))
       (h (4vec->upper h))
       (ab (4vec->upper ab))
       (per (4vec->upper per))
       (l (4vec->upper l))
       (p (4vec->upper p))
       (ke (4vec->upper ke))
       (ve (4vec->upper ve))
       (offer (4vec->upper offer))
       (rd0 (4vec->upper rd0))
       (rd1 (4vec->upper rd1))
       (rd2 (4vec->upper rd2))
       (rd3 (4vec->upper rd3))
       (rd4 (4vec->upper rd4))
       (rd5 (4vec->upper rd5))
       (rd6 (4vec->upper rd6))
       (rd7 (4vec->upper rd7))
       (b0 (4vec->upper b0))
       (b1 (4vec->upper b1))
       (b2 (4vec->upper b2))
       (b3 (4vec->upper b3))
       (b4 (4vec->upper b4))
       (b5 (4vec->upper b5))
       (b6 (4vec->upper b6))
       (b7 (4vec->upper b7))
       (wb (4vec->upper wb))
       (rb (4vec->upper rb))
       (mv (4vec->upper mv))
       (m0 (4vec->upper m0))
       (m1 (4vec->upper m1))
       (m2 (4vec->upper m2))
       (m3 (4vec->upper m3))
       (m4 (4vec->upper m4))
       (m5 (4vec->upper m5))
       (m6 (4vec->upper m6))
       (m7 (4vec->upper m7))
       (md (4vec->upper md))
       (d0 (4vec->upper d0))
       (d1 (4vec->upper d1))
       (d2 (4vec->upper d2))
       (d3 (4vec->upper d3))
       (d4 (4vec->upper d4))
       (d5 (4vec->upper d5))
       (d6 (4vec->upper d6))
       (d7 (4vec->upper d7))
       (mdd (4vec->upper mdd))
       (mw0 (4vec->upper mw0))
       (mw1 (4vec->upper mw1))
       (mw2 (4vec->upper mw2))
       (mw3 (4vec->upper mw3))
       (mw4 (4vec->upper mw4))
       (mw5 (4vec->upper mw5))
       (mw6 (4vec->upper mw6))
       (mw7 (4vec->upper mw7))
       (mdw (4vec->upper mdw))
       (res (4vec->upper res))
       (head (4vec->upper head))
       (offq (4vec->upper offq))
       (saddr (4vec->upper saddr))
       (sdata (4vec->upper sdata))
       (oaddr (4vec->upper oaddr))
       (odata (4vec->upper odata))
       (rd (logapp 32 rd0 (logapp 32 rd1 (logapp 32 rd2 (logapp 32 rd3
           (logapp 32 rd4 (logapp 32 rd5 (logapp 32 rd6 (loghead 32 rd7)))))))))
       (addr (pay-addr l p h w))
       (data (pay-data w h ke ve b0 b1 b2 b3 b4 b5 b6 b7))
       (cell (pay-cell (loghead 3 rb) m0 m1 m2 m3 m4 m5 m6 m7))
       (dcell (pay-cell (loghead 3 rb) d0 d1 d2 d3 d4 d5 d6 d7))
       (wcell (pay-cell (loghead 3 rb) mw0 mw1 mw2 mw3 mw4 mw5 mw6 mw7)))
    (and
     ; nothing is reported complete while a record is staged or written
     (or (not (or (equal st 0) (equal st 1) (equal st 2) (equal st 3) (equal st 9)
                  (equal st 10) (equal st 11) (equal st 12)))
         (equal per 0))
     ; the word counter in each write state
     (or (not (or (equal st 9) (equal st 10) (equal st 11))) (<= w 7))
     (or (not (equal st 12)) (equal w 8))
     (or (not (or (equal st 2) (equal st 3))) (<= w 8))
     ; prefetch B: the store's read register holds the word's first slot
     (or (not (equal st 10))
         (equal rd (pay-slot-a w b0 b1 b2 b3 b4 b5 b6 b7)))
     ; pack: the offer's low half is packed, the read register holds the second slot
     (or (not (equal st 11))
         (and (equal (loghead 128 offer)
                     (pay-half (pay-slot-a w b0 b1 b2 b3 b4 b5 b6 b7) h))
              (equal rd (pay-slot-b w b0 b1 b2 b3 b4 b5 b6 b7))))
     ; request and wait: the offer is the staged word
     (or (not (or (equal st 2) (equal st 3))) (equal offer data))
     ; wait: wherever the request is, it carries the offer
     (or (not (equal st 3))
         (and ; in the request FIFO
              (or (equal wb rb) (pay-entry-p dcell wcell cell offer w l p h ab))
              ; the FIFO's output register is a copy of the entry
              (or (not (equal mv 1))
                  (and (not (equal wb rb)) (equal md cell) (equal mdd dcell) (equal mdw wcell)))
              ; in the app side's slot
              (or (equal res 0)
                  (pay-carried-p (logapp 256 (pay-el256 head sdata) (pay-el19 head saddr))
                                 offer addr ab))
              ; the endpoint offer is a copy of the slot
              (or (not (equal offq 1))
                  (and (not (equal res 0))
                       (equal oaddr (pay-el19 head saddr))
                       (equal odata (pay-el256 head sdata)))))))))

; ---------------------------------------------------------------------------
; What one cycle does: staging, progress, completion, CLEAR.
; ---------------------------------------------------------------------------
(define pay-u (x) :verify-guards nil (4vec->upper x))

; The controller is writing a row: prefetch A/B, pack, metadata, request, wait.
(define pay-writing-p (st) :verify-guards nil
  (or (equal st 2) (equal st 3) (equal st 9) (equal st 10) (equal st 11) (equal st 12)))

; 1 when the word the controller is waiting on has already been accepted at
; the endpoint: it is no longer in the request FIFO, in an unissued slot or
; on offer.
(define pay-accepted (st wb rb uni offq) :verify-guards nil
  (if (and (equal st 3) (equal wb rb) (equal uni 0) (equal offq 0)) 1 0))

; Row h has just been finished: the controller moves on to row 1, or, after
; row 1, to PENDING.
(define pay-row-done-p (h nst nh nw) :verify-guards nil
  (if (equal h 0)
      (and (equal nst 9) (equal nh 1) (equal nw 0))
    (equal nst 4)))

; The sixteen staged slots of one bank (addresses 8..23), and a pair written
; at address 8+i.
(define pay-staged (bank) :verify-guards nil (loghead 512 (logtail 256 bank)))
(define pay-staged-put (i pair field) :verify-guards nil
  (cond
        ((equal i 0) (logapp 480 field (logapp 32 pair (logtail 512 field))))
        ((equal i 1) (logapp 448 field (logapp 32 pair (logtail 480 field))))
        ((equal i 2) (logapp 416 field (logapp 32 pair (logtail 448 field))))
        ((equal i 3) (logapp 384 field (logapp 32 pair (logtail 416 field))))
        ((equal i 4) (logapp 352 field (logapp 32 pair (logtail 384 field))))
        ((equal i 5) (logapp 320 field (logapp 32 pair (logtail 352 field))))
        ((equal i 6) (logapp 288 field (logapp 32 pair (logtail 320 field))))
        ((equal i 7) (logapp 256 field (logapp 32 pair (logtail 288 field))))
        ((equal i 8) (logapp 224 field (logapp 32 pair (logtail 256 field))))
        ((equal i 9) (logapp 192 field (logapp 32 pair (logtail 224 field))))
        ((equal i 10) (logapp 160 field (logapp 32 pair (logtail 192 field))))
        ((equal i 11) (logapp 128 field (logapp 32 pair (logtail 160 field))))
        ((equal i 12) (logapp 96 field (logapp 32 pair (logtail 128 field))))
        ((equal i 13) (logapp 64 field (logapp 32 pair (logtail 96 field))))
        ((equal i 14) (logapp 32 field (logapp 32 pair (logtail 64 field))))
        (t (logapp 32 pair (logtail 32 field)))))

(define pay-is (x v) :verify-guards nil
  (and (equal (4vec->upper x) v) (equal (4vec->lower x) v)))

(in-theory (disable pay-word32 pay-slot pay-half pay-slot-a pay-slot-b pay-data
                    pay-addr pay-el256 pay-el19 pay-cell pay-carried-p pay-inv-p pay-is
                    pay-entry-p pay-carried-addr
                    pay-u pay-writing-p pay-accepted pay-row-done-p pay-staged pay-staged-put))

(defsvtv$ payload-step-run
  :design *sv-design*
  :cycle-phases (list (make-svtv-cyclephase
                       :constants '(("core_clk_i" . 1) ("app_clk_i" . 1)
                                    ("reset_n_i" . 1)))
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
  (def-svtv-data-export payload-step-run-data)
  (make-event '(def-svtv-refinement payload-step-run payload-step-run-data
                 :svtv-spec payload-step-spec :inclusive-overridekeys t
                 :fsm probe-fsm :define-fsm t)))
(value-triple (acl2::cw "~%PAY-REFINEMENT done~%"))

; ---------------------------------------------------------------------------
; 1 and 2. The scripted run.  The helpers are the payload book's, the record
; and the run are kv-write-record.lisp's, character for character.
; ---------------------------------------------------------------------------

(defconst *pay-state-ids* '(p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q k-pending-issued-q k-pending-returned-q k-pending-read-pending-q k-committed-prefix-q k-pending-layer-q k-pending-position-q k-pending-key-exponents-q k-pending-value-exponents-q k-expected-coordinate-q k-pending-persisted-q k-write-head-q k-write-word-q k-write-aborted-q k-response-kind-q k-response-head-q k-response-layer-q k-response-position-q k-response-fault-q k-response-from-pending-q k-read-word-q k-read-return-word-q k-read-outstanding-q k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q k-read-epoch-q k-read-received-mask-q k-cache-valid-q k-cache-kind-q k-cache-layer-q k-cache-position-q k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q k-cache-issued-q k-cache-returned-q k-cache-read-pending-q k-cache-copy-kind-q k-lock-seen-q k-fault-q k-stage-begin-consumed-q k-stage-payload-consumed-q k-commit-consumed-q k-attention-req-consumed-q b-crel b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6 s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4 q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer a-offer-write a-poison a-offer-slot a-reserved a-unissued a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1 a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0 a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6 a-rslot7 k-bank0 k-bank1 k-bank2 k-bank3 k-bank4 k-bank5 k-bank6 k-bank7 k-rd0 k-rd1 k-rd2 k-rd3 k-rd4 k-rd5 k-rd6 k-rd7 k-offer q-memp0 q-memp1 q-memp2 q-memp3 q-memp4 q-memp5 q-memp6 q-memp7 q-memd0 q-memd1 q-memd2 q-memd3 q-memd4 q-memd5 q-memd6 q-memd7 q-mdd q-mdp a-saddr a-sdata a-oaddr a-odata))
(defconst *pay-hyp-ids* '(h-arbfail h-shellterm h-shellfail h-layerfail h-auth h-mcdc h-kupf h-layer h-position h-kexp h-vexp h-sbegin h-spayload h-index h-key h-value h-commit h-attn h-attn-kind h-attn-pos h-attn-head h-attn-ready h-epready h-eprspv h-eprsperr h-eprspdata h-rspdata h-appup h-legal))
(defun pay-sym (prefix id)
  (declare (xargs :mode :program))
  (intern-in-package-of-symbol
   (concatenate 'string prefix (symbol-name id)) 'pay-sym))
(defun pay-get (k al)
  (declare (xargs :mode :program))
  (cdr (assoc-eq k al)))
; the run's inputs for one cycle: every register overridden with its value,
; every environment signal with the script's; the app side's verdict on a
; request's descriptor (h-legal) is left to the RTL
(defun pay-state-env (ids st)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (list* (cons (pay-sym "R-" (car ids)) (pay-get (car ids) st))
           (cons (pay-sym "C-" (car ids)) -1)
           (pay-state-env (cdr ids) st))))
(defun pay-hyp-env (ids hy)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (list* (cons (car ids) (nfix (pay-get (car ids) hy)))
           (cons (pay-sym "C-" (car ids)) (if (eq (car ids) 'h-legal) 0 -1))
           (pay-hyp-env (cdr ids) hy))))
(defun pay-next-state (ids out)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (cons (cons (car ids) (pay-get (pay-sym "N-" (car ids)) out))
          (pay-next-state (cdr ids) out))))
(defun pay-all-natp (al)
  (declare (xargs :mode :program))
  (or (atom al) (and (natp (cdar al)) (pay-all-natp (cdr al)))))
(defun pay-zero-state (ids)
  (declare (xargs :mode :program))
  (if (atom ids) nil (cons (cons (car ids) 0) (pay-zero-state (cdr ids)))))

; THE SCRIPT.  The client stages one record: layer 2, position
; 0, exponent bytes 5 and 250; coordinate c has key
; #x100 + 3c and value #x4000 + 5c.  It offers a beat on three cycles in
; four.  The endpoint is ready on six cycles in seven.
(defun pay-script (cycle st)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st))
       (c (pay-get 'k-expected-coordinate-q st))
       (base (list (cons 'h-epready (if (equal (mod cycle 7) 3) 0 1))
                   (cons 'h-attn-ready 1)
                   (cons 'h-layer 2) (cons 'h-position 0)
                   (cons 'h-kexp 5) (cons 'h-vexp 250))))
    (cond ((and (equal s 0) (equal (pay-get 'k-stage-begin-consumed-q st) 0)
                (equal (pay-get 'k-lock-seen-q st) 1))
           (cons (cons 'h-sbegin 1) base))
          ((and (equal s 1) (equal (pay-get 'k-stage-payload-consumed-q st) 0)
                (not (equal (mod cycle 4) 2)))
           (list* (cons 'h-spayload 1) (cons 'h-index c)
                  (cons 'h-key (+ #x100 (* 3 c))) (cons 'h-value (+ #x4000 (* 5 c)))
                  base))
          (t base))))

; One cycle after another, from `st`.  Collects the writes accepted at the
; boundary's endpoint and at the controller's typed port, in order, and stops
; when the controller reports the record complete (PENDING), on a signal that
; is not definite, or at the limit.
(defun pay-run-loop (cycle limit st ep typed)
  (declare (xargs :mode :program))
  (b* (((when (<= limit cycle)) (list :limit cycle (reverse ep) (reverse typed) st))
       (hy (pay-script cycle st))
       (out (svtv-run (payload-step-run)
                      (append (list (cons 'i-reset-n (if (< cycle 3) 0 1)) (cons 'i-clear 0))
                              (pay-state-env *pay-state-ids* st)
                              (pay-hyp-env *pay-hyp-ids* hy))
                      :quiet t))
       (nst (pay-next-state *pay-state-ids* out))
       ((unless (pay-all-natp nst)) (list :not-definite cycle (reverse ep) (reverse typed) st))
       ((unless (and (equal (pay-get 'o-pfn out) 0) (equal (pay-get 'o-tfe out) 0)))
        (list :fault cycle (reverse ep) (reverse typed) st))
       (ep (if (and (equal (pay-get 'o-epv out) 1) (equal (pay-get 'h-epready hy) 1)
                    (equal (pay-get 'o-epw out) 1))
               (cons (list cycle (pay-get 'o-epaddr out) (pay-get 'o-epdata out)) ep)
             ep))
       (typed (if (and (equal (pay-get 'o-wreqv out) 1) (equal (pay-get 'o-wreqr out) 1))
                  (cons (list cycle (pay-get 'o-wreqaddr out) (pay-get 'o-wreqdata out)) typed)
                typed))
       ((when (equal (pay-get 'k-state-q nst) 4))
        (list :complete (+ 1 cycle) (reverse ep) (reverse typed) nst)))
    (pay-run-loop (+ 1 cycle) limit nst ep typed)))

(define rec-word (h w l p ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (list (pay-addr l p h w)
        (pay-data w h ke ve b0 b1 b2 b3 b4 b5 b6 b7)))
(define rec-words (l p ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (list (rec-word 0 0 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 1 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 2 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 3 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 4 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 5 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 6 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 7 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 8 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 0 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 1 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 2 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 3 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 4 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 5 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 6 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 7 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 8 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)))


; THE SCRIPT.  The client stages the record of the payload book's run: layer
; 2, position 0, exponent bytes 5 and 250;
; coordinate c has key #x100 + 3c and value #x4000 + 5c; a beat on three
; cycles in four.  The endpoint is slow: it is not ready on three cycles in
; five, and while the controller is on word 0, 3 or 8 of either row it is
; also not ready on 48 cycles in every 64.  Word 8 of the K row and word 0 of
; the V row are the two sides of the step from one row to the other, and
; word 8 of the V row is the last before the record is reported complete.
(defun rec-ready (cycle st)
  (declare (xargs :mode :program))
  (if (or (< (mod cycle 5) 3)
          (and (member (pay-get 'k-write-word-q st) '(0 3 8))
               (< (mod cycle 64) 48)))
      0 1))
(defun rec-script (cycle st)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st))
       (c (pay-get 'k-expected-coordinate-q st))
       (base (list (cons 'h-epready (rec-ready cycle st))
                   (cons 'h-attn-ready 1)
                   (cons 'h-layer 2) (cons 'h-position 0)
                   (cons 'h-kexp 5) (cons 'h-vexp 250))))
    (cond ((and (equal s 0) (equal (pay-get 'k-stage-begin-consumed-q st) 0)
                (equal (pay-get 'k-lock-seen-q st) 1))
           (cons (cons 'h-sbegin 1) base))
          ((and (equal s 1) (equal (pay-get 'k-stage-payload-consumed-q st) 0)
                (not (equal (mod cycle 4) 2)))
           (list* (cons 'h-spayload 1) (cons 'h-index c)
                  (cons 'h-key (+ #x100 (* 3 c))) (cons 'h-value (+ #x4000 (* 5 c)))
                  base))
          (t base))))

; the eighteen words of the record as the registers hold it
(defun rec-held (st)
  (declare (xargs :mode :program))
  (rec-words (pay-get 'k-pending-layer-q st) (pay-get 'k-pending-position-q st)
             (pay-get 'k-pending-key-exponents-q st) (pay-get 'k-pending-value-exponents-q st)
             (pay-get 'k-bank0 st) (pay-get 'k-bank1 st) (pay-get 'k-bank2 st) (pay-get 'k-bank3 st) (pay-get 'k-bank4 st) (pay-get 'k-bank5 st) (pay-get 'k-bank6 st) (pay-get 'k-bank7 st)))

; One cycle after another from `st`; one entry per cycle:
;   (cycle state_q write_head_q write_word_q write_aborted_q
;    pending_persisted_q its-next-value accepted-write refused held-record)
; Stops when the controller reaches PENDING, on a signal that is not
; definite, on a fault, or at the limit.
(defun rec-run-loop (cycle limit st trace)
  (declare (xargs :mode :program))
  (b* (((when (<= limit cycle)) (list :limit (reverse trace)))
       (hy (rec-script cycle st))
       (out (svtv-run (payload-step-run)
                      (append (list (cons 'i-reset-n (if (< cycle 3) 0 1)) (cons 'i-clear 0))
                              (pay-state-env *pay-state-ids* st)
                              (pay-hyp-env *pay-hyp-ids* hy))
                      :quiet t))
       (nst (pay-next-state *pay-state-ids* out))
       ((unless (pay-all-natp nst)) (list :not-definite (reverse trace)))
       ((unless (and (equal (pay-get 'o-pfn out) 0) (equal (pay-get 'o-tfe out) 0)))
        (list :fault (reverse trace)))
       (offered (and (equal (pay-get 'o-epv out) 1) (equal (pay-get 'o-epw out) 1)))
       (ready (equal (pay-get 'h-epready hy) 1))
       (entry (list cycle
                    (pay-get 'k-state-q st) (pay-get 'k-write-head-q st)
                    (pay-get 'k-write-word-q st) (pay-get 'k-write-aborted-q st)
                    (pay-get 'k-pending-persisted-q st) (pay-get 'k-pending-persisted-q nst)
                    (and offered ready
                         (list (pay-get 'o-epaddr out) (pay-get 'o-epdata out)))
                    (if (and offered (not ready)) 1 0)
                    (rec-held st)))
       (trace (cons entry trace))
       ((when (equal (pay-get 'k-state-q nst) 4)) (list :complete (reverse trace))))
    (rec-run-loop (+ 1 cycle) limit nst trace)))

; Reading a trace.  The completion edge: the cycle whose pending_persisted_q
; is 0 with next value 1.
(defun rec-t-edge (trace)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((and (equal (nth 5 (car trace)) 0) (equal (nth 6 (car trace)) 1))
         (nth 0 (car trace)))
        (t (rec-t-edge (cdr trace)))))
; The latest cycle up to n with state_q = 9, write_head_q = h, write_word_q = 0.
(defun rec-t-start (trace n h best)
  (declare (xargs :mode :program))
  (cond ((atom trace) best)
        ((< n (nth 0 (car trace))) best)
        ((and (equal (nth 1 (car trace)) 9) (equal (nth 2 (car trace)) h)
              (equal (nth 3 (car trace)) 0))
         (rec-t-start (cdr trace) n h (nth 0 (car trace))))
        (t (rec-t-start (cdr trace) n h best))))
; The writes the endpoint accepted in cycles j to n, in order.
(defun rec-t-writes (trace j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((< (nth 0 (car trace)) j) (rec-t-writes (cdr trace) j n))
        ((< n (nth 0 (car trace))) nil)
        ((nth 7 (car trace)) (cons (nth 7 (car trace)) (rec-t-writes (cdr trace) j n)))
        (t (rec-t-writes (cdr trace) j n))))
; In how many cycles from j to n a write was offered and refused, and the
; longest run of such cycles.
(defun rec-t-refused (trace j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) 0)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-refused (cdr trace) j n))
        (t (+ (nth 8 (car trace)) (rec-t-refused (cdr trace) j n)))))
(defun rec-t-longest (trace j n run best)
  (declare (xargs :mode :program))
  (cond ((atom trace) (max run best))
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-longest (cdr trace) j n 0 (max run best)))
        ((equal (nth 8 (car trace)) 1) (rec-t-longest (cdr trace) j n (+ 1 run) best))
        (t (rec-t-longest (cdr trace) j n 0 (max run best)))))
; The record held in cycle j.
(defun rec-t-held (trace j)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((equal (nth 0 (car trace)) j) (nth 9 (car trace)))
        (t (rec-t-held (cdr trace) j))))
; Every cycle from j to n is a write cycle, not interrupted, and holds `held`.
(defun rec-t-steady (trace j n held)
  (declare (xargs :mode :program))
  (cond ((atom trace) t)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-steady (cdr trace) j n held))
        (t (and (member (nth 1 (car trace)) '(2 3 9 10 11 12))
                (equal (nth 4 (car trace)) 0)
                (or (null held) (equal (nth 9 (car trace)) held))
                (rec-t-steady (cdr trace) j n held)))))
; What the theorems below are stated about:
;   (outcome cycles n j jv writes held-at-j held-at-jv refused longest steady written)
; n the completion edge, j the record's start, jv the V row's start.
(defun rec-run-summary (limit)
  (declare (xargs :mode :program))
  (b* ((run (rec-run-loop 0 limit (pay-zero-state *pay-state-ids*) nil))
       (trace (second run))
       (n (rec-t-edge trace))
       (j (and n (rec-t-start trace n 0 nil)))
       (jv (and n (rec-t-start trace n 1 nil)))
       ((unless (and n j jv)) (list (first run) (len trace) n j jv nil nil nil 0 0 nil nil)))
    (list (first run) (len trace) n j jv
          (rec-t-writes trace j n)
          (rec-t-held trace j)
          (rec-t-held trace jv)
          (rec-t-refused trace j n)
          (rec-t-longest trace j n 0 0)
          (rec-t-steady trace j n (rec-t-held trace j))
          (rec-t-steady trace j n nil))))

(defconsts *rec-run* (rec-run-summary 6000))
(defconst *rec-run-outcome* (nth 0 *rec-run*))
(defconst *rec-run-cycles* (nth 1 *rec-run*))
; the completion edge, the record's start, the V row's start
(defconst *rec-run-n* (nth 2 *rec-run*))
(defconst *rec-run-j* (nth 3 *rec-run*))
(defconst *rec-run-jv* (nth 4 *rec-run*))
; the writes the endpoint accepted in cycles j to n
(defconst *rec-run-writes* (nth 5 *rec-run*))
; the record the registers hold at j, and at jv
(defconst *rec-run-held-at-start* (nth 6 *rec-run*))
(defconst *rec-run-held-at-v-start* (nth 7 *rec-run*))
; cycles from j to n in which a write was offered and refused; longest run
(defconst *rec-run-refused* (nth 8 *rec-run*))
(defconst *rec-run-longest-stall* (nth 9 *rec-run*))
; from j to n: a write state, not interrupted, in every cycle; and the same
; held record in every cycle
(defconst *rec-run-same-record-throughout* (nth 10 *rec-run*))
(defconst *rec-run-written-throughout* (nth 11 *rec-run*))

; the record the script stages, as kv-write-record.lisp states it
(defconst *rec-expected*
  '((300800 #x12d012a012701240121011e011b011801150112010f010c0109010601030100)
    (300801 #x15d015a015701540151014e014b014801450142013f013c0139013601330130)
    (300802 #x18d018a018701840181017e017b017801750172016f016c0169016601630160)
    (300803 #x1bd01ba01b701b401b101ae01ab01a801a501a2019f019c0199019601930190)
    (300804 #x1ed01ea01e701e401e101de01db01d801d501d201cf01cc01c901c601c301c0)
    (300805 #x21d021a021702140211020e020b02080205020201ff01fc01f901f601f301f0)
    (300806 #x24d024a024702440241023e023b023802350232022f022c0229022602230220)
    (300807 #x27d027a027702740271026e026b026802650262025f025c0259025602530250)
    (300808 #x505)
    (300809 #x404b40464041403c40374032402d40284023401e40194014400f400a40054000)
    (300810 #x409b40964091408c40874082407d40784073406e40694064405f405a40554050)
    (300811 #x40eb40e640e140dc40d740d240cd40c840c340be40b940b440af40aa40a540a0)
    (300812 #x413b41364131412c41274122411d41184113410e4109410440ff40fa40f540f0)
    (300813 #x418b41864181417c41774172416d41684163415e41594154414f414a41454140)
    (300814 #x41db41d641d141cc41c741c241bd41b841b341ae41a941a4419f419a41954190)
    (300815 #x422b42264221421c42174212420d4208420341fe41f941f441ef41ea41e541e0)
    (300816 #x427b42764271426c42674262425d42584253424e42494244423f423a42354230)
    (300817 #xfafa)))
; the staged V row at the V addresses of the next position: 18 higher
(defconst *rec-expected-v-row-misplaced*
  '((300827 #x404b40464041403c40374032402d40284023401e40194014400f400a40054000)
    (300828 #x409b40964091408c40874082407d40784073406e40694064405f405a40554050)
    (300829 #x40eb40e640e140dc40d740d240cd40c840c340be40b940b440af40aa40a540a0)
    (300830 #x413b41364131412c41274122411d41184113410e4109410440ff40fa40f540f0)
    (300831 #x418b41864181417c41774172416d41684163415e41594154414f414a41454140)
    (300832 #x41db41d641d141cc41c741c241bd41b841b341ae41a941a4419f419a41954190)
    (300833 #x422b42264221421c42174212420d4208420341fe41f941f441ef41ea41e541e0)
    (300834 #x427b42764271426c42674262425d42584253424e42494244423f423a42354230)
    (300835 #xfafa)))

; The run ends with pending_persisted_q rising, after eighteen writes, with
; the controller writing and not interrupted from the record's start on.
(defthm kv-write-record-mismatched-rows-run-completes
  (and (equal *rec-run-outcome* :complete)
       (natp *rec-run-n*) (natp *rec-run-j*) (natp *rec-run-jv*)
       (equal (len *rec-run-writes*) 18)
       (equal *rec-run-written-throughout* t))
  :rule-classes nil)

; Each row alone is what the row theorem asks of it: the first nine writes
; are the K row as held when the K row starts, the last nine are the V row
; as held when the V row starts.
(defthm kv-write-record-mismatched-rows-each-row-alone-passes
  (and (equal (take 9 *rec-run-writes*) (take 9 *rec-run-held-at-start*))
       (equal (nthcdr 9 *rec-run-writes*) (nthcdr 9 *rec-run-held-at-v-start*)))
  :rule-classes nil)

; The record fails.  The eighteen writes are not the record held at the
; record's start; the held record does not stay the same; the K row is the
; staged K row at its addresses, and the V row is the staged V row at the
; addresses of the next position.
(defthm kv-write-record-mismatched-rows-run-is-not-one-record
  (and (not (equal *rec-run-writes* *rec-run-held-at-start*))
       (not (equal *rec-run-same-record-throughout* t))
       (not (equal *rec-run-writes* *rec-expected*))
       (equal (take 9 *rec-run-writes*) (take 9 *rec-expected*))
       (equal (nthcdr 9 *rec-run-writes*) *rec-expected-v-row-misplaced*))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; 3. The new step lemma is not provable.  The predicates and the statement
;    below are, character for character, those of kv-write-record-step.lisp.
; ---------------------------------------------------------------------------
; The payload book's predicates come first: the statement uses its integer
; predicates pay-int-...
(define pay-int-o-pfn (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-pfn"
  (integerp x)))
(defthm pay-int-o-pfn-integerp
  (implies (pay-int-o-pfn x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-pfn fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-tpf (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-tpf"
  (integerp x)))
(defthm pay-int-o-tpf-integerp
  (implies (pay-int-o-tpf x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-tpf fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-epf (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-epf"
  (integerp x)))
(defthm pay-int-o-epf-integerp
  (implies (pay-int-o-epf x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-epf fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-wreqv (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-wreqv"
  (integerp x)))
(defthm pay-int-o-wreqv-integerp
  (implies (pay-int-o-wreqv x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-wreqv fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-wreqr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-wreqr"
  (integerp x)))
(defthm pay-int-o-wreqr-integerp
  (implies (pay-int-o-wreqr x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-wreqr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-wreqaddr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-wreqaddr"
  (integerp x)))
(defthm pay-int-o-wreqaddr-integerp
  (implies (pay-int-o-wreqaddr x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-wreqaddr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-wreqdata (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-wreqdata"
  (integerp x)))
(defthm pay-int-o-wreqdata-integerp
  (implies (pay-int-o-wreqdata x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-wreqdata fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-epv (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-epv"
  (integerp x)))
(defthm pay-int-o-epv-integerp
  (implies (pay-int-o-epv x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-epv fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-epw (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-epw"
  (integerp x)))
(defthm pay-int-o-epw-integerp
  (implies (pay-int-o-epw x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-epw fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-epaddr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-epaddr"
  (integerp x)))
(defthm pay-int-o-epaddr-integerp
  (implies (pay-int-o-epaddr x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-epaddr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-epdata (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-epdata"
  (integerp x)))
(defthm pay-int-o-epdata-integerp
  (implies (pay-int-o-epdata x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-epdata fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-spr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-spr"
  (integerp x)))
(defthm pay-int-o-spr-integerp
  (implies (pay-int-o-spr x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-spr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-spl (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-spl"
  (integerp x)))
(defthm pay-int-o-spl-integerp
  (implies (pay-int-o-spl x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-spl fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-o-wlegal (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-o-wlegal"
  (integerp x)))
(defthm pay-int-o-wlegal-integerp
  (implies (pay-int-o-wlegal x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-o-wlegal fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-state-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-state-q"
  (integerp x)))
(defthm pay-int-n-k-state-q-integerp
  (implies (pay-int-n-k-state-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-state-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-pending-layer-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-pending-layer-q"
  (integerp x)))
(defthm pay-int-n-k-pending-layer-q-integerp
  (implies (pay-int-n-k-pending-layer-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-pending-layer-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-pending-position-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-pending-position-q"
  (integerp x)))
(defthm pay-int-n-k-pending-position-q-integerp
  (implies (pay-int-n-k-pending-position-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-pending-position-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-pending-key-exponents-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-pending-key-exponents-q"
  (integerp x)))
(defthm pay-int-n-k-pending-key-exponents-q-integerp
  (implies (pay-int-n-k-pending-key-exponents-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-pending-key-exponents-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-pending-value-exponents-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-pending-value-exponents-q"
  (integerp x)))
(defthm pay-int-n-k-pending-value-exponents-q-integerp
  (implies (pay-int-n-k-pending-value-exponents-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-pending-value-exponents-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-pending-persisted-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-pending-persisted-q"
  (integerp x)))
(defthm pay-int-n-k-pending-persisted-q-integerp
  (implies (pay-int-n-k-pending-persisted-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-pending-persisted-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-write-head-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-write-head-q"
  (integerp x)))
(defthm pay-int-n-k-write-head-q-integerp
  (implies (pay-int-n-k-write-head-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-write-head-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-write-word-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-write-word-q"
  (integerp x)))
(defthm pay-int-n-k-write-word-q-integerp
  (implies (pay-int-n-k-write-word-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-write-word-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-write-aborted-q (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-write-aborted-q"
  (integerp x)))
(defthm pay-int-n-k-write-aborted-q-integerp
  (implies (pay-int-n-k-write-aborted-q x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-write-aborted-q fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-wb (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-wb"
  (integerp x)))
(defthm pay-int-n-q-wb-integerp
  (implies (pay-int-n-q-wb x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-wb fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-rb (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-rb"
  (integerp x)))
(defthm pay-int-n-q-rb-integerp
  (implies (pay-int-n-q-rb x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-rb fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-mv (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-mv"
  (integerp x)))
(defthm pay-int-n-q-mv-integerp
  (implies (pay-int-n-q-mv x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-mv fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-mdw (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-mdw"
  (integerp x)))
(defthm pay-int-n-q-mdw-integerp
  (implies (pay-int-n-q-mdw x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-mdw fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw0 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw0"
  (integerp x)))
(defthm pay-int-n-q-memw0-integerp
  (implies (pay-int-n-q-memw0 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw0 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw1 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw1"
  (integerp x)))
(defthm pay-int-n-q-memw1-integerp
  (implies (pay-int-n-q-memw1 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw1 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw2 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw2"
  (integerp x)))
(defthm pay-int-n-q-memw2-integerp
  (implies (pay-int-n-q-memw2 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw2 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw3 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw3"
  (integerp x)))
(defthm pay-int-n-q-memw3-integerp
  (implies (pay-int-n-q-memw3 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw3 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw4 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw4"
  (integerp x)))
(defthm pay-int-n-q-memw4-integerp
  (implies (pay-int-n-q-memw4 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw4 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw5 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw5"
  (integerp x)))
(defthm pay-int-n-q-memw5-integerp
  (implies (pay-int-n-q-memw5 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw5 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw6 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw6"
  (integerp x)))
(defthm pay-int-n-q-memw6-integerp
  (implies (pay-int-n-q-memw6 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw6 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memw7 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memw7"
  (integerp x)))
(defthm pay-int-n-q-memw7-integerp
  (implies (pay-int-n-q-memw7 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memw7 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-offer (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-offer"
  (integerp x)))
(defthm pay-int-n-a-offer-integerp
  (implies (pay-int-n-a-offer x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-offer fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-reserved (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-reserved"
  (integerp x)))
(defthm pay-int-n-a-reserved-integerp
  (implies (pay-int-n-a-reserved x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-reserved fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-unissued (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-unissued"
  (integerp x)))
(defthm pay-int-n-a-unissued-integerp
  (implies (pay-int-n-a-unissued x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-unissued fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-head (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-head"
  (integerp x)))
(defthm pay-int-n-a-head-integerp
  (implies (pay-int-n-a-head x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-head fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank0 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank0"
  (integerp x)))
(defthm pay-int-n-k-bank0-integerp
  (implies (pay-int-n-k-bank0 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank0 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank1 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank1"
  (integerp x)))
(defthm pay-int-n-k-bank1-integerp
  (implies (pay-int-n-k-bank1 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank1 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank2 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank2"
  (integerp x)))
(defthm pay-int-n-k-bank2-integerp
  (implies (pay-int-n-k-bank2 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank2 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank3 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank3"
  (integerp x)))
(defthm pay-int-n-k-bank3-integerp
  (implies (pay-int-n-k-bank3 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank3 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank4 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank4"
  (integerp x)))
(defthm pay-int-n-k-bank4-integerp
  (implies (pay-int-n-k-bank4 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank4 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank5 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank5"
  (integerp x)))
(defthm pay-int-n-k-bank5-integerp
  (implies (pay-int-n-k-bank5 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank5 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank6 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank6"
  (integerp x)))
(defthm pay-int-n-k-bank6-integerp
  (implies (pay-int-n-k-bank6 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank6 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-bank7 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-bank7"
  (integerp x)))
(defthm pay-int-n-k-bank7-integerp
  (implies (pay-int-n-k-bank7 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-bank7 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd0 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd0"
  (integerp x)))
(defthm pay-int-n-k-rd0-integerp
  (implies (pay-int-n-k-rd0 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd0 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd1 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd1"
  (integerp x)))
(defthm pay-int-n-k-rd1-integerp
  (implies (pay-int-n-k-rd1 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd1 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd2 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd2"
  (integerp x)))
(defthm pay-int-n-k-rd2-integerp
  (implies (pay-int-n-k-rd2 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd2 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd3 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd3"
  (integerp x)))
(defthm pay-int-n-k-rd3-integerp
  (implies (pay-int-n-k-rd3 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd3 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd4 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd4"
  (integerp x)))
(defthm pay-int-n-k-rd4-integerp
  (implies (pay-int-n-k-rd4 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd4 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd5 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd5"
  (integerp x)))
(defthm pay-int-n-k-rd5-integerp
  (implies (pay-int-n-k-rd5 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd5 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd6 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd6"
  (integerp x)))
(defthm pay-int-n-k-rd6-integerp
  (implies (pay-int-n-k-rd6 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd6 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-rd7 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-rd7"
  (integerp x)))
(defthm pay-int-n-k-rd7-integerp
  (implies (pay-int-n-k-rd7 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-rd7 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-k-offer (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-k-offer"
  (integerp x)))
(defthm pay-int-n-k-offer-integerp
  (implies (pay-int-n-k-offer x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-k-offer fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp0 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp0"
  (integerp x)))
(defthm pay-int-n-q-memp0-integerp
  (implies (pay-int-n-q-memp0 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp0 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp1 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp1"
  (integerp x)))
(defthm pay-int-n-q-memp1-integerp
  (implies (pay-int-n-q-memp1 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp1 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp2 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp2"
  (integerp x)))
(defthm pay-int-n-q-memp2-integerp
  (implies (pay-int-n-q-memp2 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp2 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp3 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp3"
  (integerp x)))
(defthm pay-int-n-q-memp3-integerp
  (implies (pay-int-n-q-memp3 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp3 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp4 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp4"
  (integerp x)))
(defthm pay-int-n-q-memp4-integerp
  (implies (pay-int-n-q-memp4 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp4 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp5 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp5"
  (integerp x)))
(defthm pay-int-n-q-memp5-integerp
  (implies (pay-int-n-q-memp5 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp5 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp6 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp6"
  (integerp x)))
(defthm pay-int-n-q-memp6-integerp
  (implies (pay-int-n-q-memp6 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp6 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memp7 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memp7"
  (integerp x)))
(defthm pay-int-n-q-memp7-integerp
  (implies (pay-int-n-q-memp7 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memp7 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd0 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd0"
  (integerp x)))
(defthm pay-int-n-q-memd0-integerp
  (implies (pay-int-n-q-memd0 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd0 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd1 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd1"
  (integerp x)))
(defthm pay-int-n-q-memd1-integerp
  (implies (pay-int-n-q-memd1 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd1 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd2 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd2"
  (integerp x)))
(defthm pay-int-n-q-memd2-integerp
  (implies (pay-int-n-q-memd2 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd2 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd3 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd3"
  (integerp x)))
(defthm pay-int-n-q-memd3-integerp
  (implies (pay-int-n-q-memd3 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd3 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd4 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd4"
  (integerp x)))
(defthm pay-int-n-q-memd4-integerp
  (implies (pay-int-n-q-memd4 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd4 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd5 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd5"
  (integerp x)))
(defthm pay-int-n-q-memd5-integerp
  (implies (pay-int-n-q-memd5 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd5 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd6 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd6"
  (integerp x)))
(defthm pay-int-n-q-memd6-integerp
  (implies (pay-int-n-q-memd6 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd6 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-memd7 (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-memd7"
  (integerp x)))
(defthm pay-int-n-q-memd7-integerp
  (implies (pay-int-n-q-memd7 x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-memd7 fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-mdd (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-mdd"
  (integerp x)))
(defthm pay-int-n-q-mdd-integerp
  (implies (pay-int-n-q-mdd x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-mdd fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-q-mdp (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-q-mdp"
  (integerp x)))
(defthm pay-int-n-q-mdp-integerp
  (implies (pay-int-n-q-mdp x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-q-mdp fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-saddr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-saddr"
  (integerp x)))
(defthm pay-int-n-a-saddr-integerp
  (implies (pay-int-n-a-saddr x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-saddr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-sdata (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-sdata"
  (integerp x)))
(defthm pay-int-n-a-sdata-integerp
  (implies (pay-int-n-a-sdata x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-sdata fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-oaddr (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-oaddr"
  (integerp x)))
(defthm pay-int-n-a-oaddr-integerp
  (implies (pay-int-n-a-oaddr x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-oaddr fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define pay-int-n-a-odata (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-int-n-a-odata"
  (integerp x)))
(defthm pay-int-n-a-odata-integerp
  (implies (pay-int-n-a-odata x) (integerp x))
  :hints (("Goal" :in-theory (enable pay-int-n-a-odata fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(in-theory (disable pay-int-o-pfn pay-int-o-tpf pay-int-o-epf pay-int-o-wreqv pay-int-o-wreqr pay-int-o-wreqaddr pay-int-o-wreqdata pay-int-o-epv pay-int-o-epw pay-int-o-epaddr pay-int-o-epdata pay-int-o-spr pay-int-o-spl pay-int-o-wlegal pay-int-n-k-state-q pay-int-n-k-pending-layer-q pay-int-n-k-pending-position-q pay-int-n-k-pending-key-exponents-q pay-int-n-k-pending-value-exponents-q pay-int-n-k-pending-persisted-q pay-int-n-k-write-head-q pay-int-n-k-write-word-q pay-int-n-k-write-aborted-q pay-int-n-q-wb pay-int-n-q-rb pay-int-n-q-mv pay-int-n-q-mdw pay-int-n-q-memw0 pay-int-n-q-memw1 pay-int-n-q-memw2 pay-int-n-q-memw3 pay-int-n-q-memw4 pay-int-n-q-memw5 pay-int-n-q-memw6 pay-int-n-q-memw7 pay-int-n-a-offer pay-int-n-a-reserved pay-int-n-a-unissued pay-int-n-a-head pay-int-n-k-bank0 pay-int-n-k-bank1 pay-int-n-k-bank2 pay-int-n-k-bank3 pay-int-n-k-bank4 pay-int-n-k-bank5 pay-int-n-k-bank6 pay-int-n-k-bank7 pay-int-n-k-rd0 pay-int-n-k-rd1 pay-int-n-k-rd2 pay-int-n-k-rd3 pay-int-n-k-rd4 pay-int-n-k-rd5 pay-int-n-k-rd6 pay-int-n-k-rd7 pay-int-n-k-offer pay-int-n-q-memp0 pay-int-n-q-memp1 pay-int-n-q-memp2 pay-int-n-q-memp3 pay-int-n-q-memp4 pay-int-n-q-memp5 pay-int-n-q-memp6 pay-int-n-q-memp7 pay-int-n-q-memd0 pay-int-n-q-memd1 pay-int-n-q-memd2 pay-int-n-q-memd3 pay-int-n-q-memd4 pay-int-n-q-memd5 pay-int-n-q-memd6 pay-int-n-q-memd7 pay-int-n-q-mdd pay-int-n-q-mdp pay-int-n-a-saddr pay-int-n-a-sdata pay-int-n-a-oaddr pay-int-n-a-odata))

; the next value of k-bank0 is definite
(define pay-next-definite-k-bank0 (n-k-bank0)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank0"
  (unsigned-byte-p 1024 n-k-bank0)))
; the next value of k-bank1 is definite
(define pay-next-definite-k-bank1 (n-k-bank1)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank1"
  (unsigned-byte-p 1024 n-k-bank1)))
; the next value of k-bank2 is definite
(define pay-next-definite-k-bank2 (n-k-bank2)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank2"
  (unsigned-byte-p 1024 n-k-bank2)))
; the next value of k-bank3 is definite
(define pay-next-definite-k-bank3 (n-k-bank3)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank3"
  (unsigned-byte-p 1024 n-k-bank3)))
; the next value of k-bank4 is definite
(define pay-next-definite-k-bank4 (n-k-bank4)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank4"
  (unsigned-byte-p 1024 n-k-bank4)))
; the next value of k-bank5 is definite
(define pay-next-definite-k-bank5 (n-k-bank5)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank5"
  (unsigned-byte-p 1024 n-k-bank5)))
; the next value of k-bank6 is definite
(define pay-next-definite-k-bank6 (n-k-bank6)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank6"
  (unsigned-byte-p 1024 n-k-bank6)))
; the next value of k-bank7 is definite
(define pay-next-definite-k-bank7 (n-k-bank7)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-bank7"
  (unsigned-byte-p 1024 n-k-bank7)))
; the next value of k-rd0 is definite
(define pay-next-definite-k-rd0 (n-k-rd0)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd0"
  (unsigned-byte-p 32 n-k-rd0)))
; the next value of k-rd1 is definite
(define pay-next-definite-k-rd1 (n-k-rd1)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd1"
  (unsigned-byte-p 32 n-k-rd1)))
; the next value of k-rd2 is definite
(define pay-next-definite-k-rd2 (n-k-rd2)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd2"
  (unsigned-byte-p 32 n-k-rd2)))
; the next value of k-rd3 is definite
(define pay-next-definite-k-rd3 (n-k-rd3)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd3"
  (unsigned-byte-p 32 n-k-rd3)))
; the next value of k-rd4 is definite
(define pay-next-definite-k-rd4 (n-k-rd4)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd4"
  (unsigned-byte-p 32 n-k-rd4)))
; the next value of k-rd5 is definite
(define pay-next-definite-k-rd5 (n-k-rd5)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd5"
  (unsigned-byte-p 32 n-k-rd5)))
; the next value of k-rd6 is definite
(define pay-next-definite-k-rd6 (n-k-rd6)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd6"
  (unsigned-byte-p 32 n-k-rd6)))
; the next value of k-rd7 is definite
(define pay-next-definite-k-rd7 (n-k-rd7)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-rd7"
  (unsigned-byte-p 32 n-k-rd7)))
; the next value of k-offer is definite
(define pay-next-definite-k-offer (n-k-offer)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-k-offer"
  (unsigned-byte-p 256 n-k-offer)))
; the next value of q-memp0 is definite
(define pay-next-definite-q-memp0 (n-q-memp0)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp0"
  (unsigned-byte-p 275 n-q-memp0)))
; the next value of q-memp1 is definite
(define pay-next-definite-q-memp1 (n-q-memp1)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp1"
  (unsigned-byte-p 275 n-q-memp1)))
; the next value of q-memp2 is definite
(define pay-next-definite-q-memp2 (n-q-memp2)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp2"
  (unsigned-byte-p 275 n-q-memp2)))
; the next value of q-memp3 is definite
(define pay-next-definite-q-memp3 (n-q-memp3)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp3"
  (unsigned-byte-p 275 n-q-memp3)))
; the next value of q-memp4 is definite
(define pay-next-definite-q-memp4 (n-q-memp4)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp4"
  (unsigned-byte-p 275 n-q-memp4)))
; the next value of q-memp5 is definite
(define pay-next-definite-q-memp5 (n-q-memp5)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp5"
  (unsigned-byte-p 275 n-q-memp5)))
; the next value of q-memp6 is definite
(define pay-next-definite-q-memp6 (n-q-memp6)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp6"
  (unsigned-byte-p 275 n-q-memp6)))
; the next value of q-memp7 is definite
(define pay-next-definite-q-memp7 (n-q-memp7)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memp7"
  (unsigned-byte-p 275 n-q-memp7)))
; the next value of q-memd0 is definite
(define pay-next-definite-q-memd0 (n-q-memd0)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd0"
  (unsigned-byte-p 36 n-q-memd0)))
; the next value of q-memd1 is definite
(define pay-next-definite-q-memd1 (n-q-memd1)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd1"
  (unsigned-byte-p 36 n-q-memd1)))
; the next value of q-memd2 is definite
(define pay-next-definite-q-memd2 (n-q-memd2)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd2"
  (unsigned-byte-p 36 n-q-memd2)))
; the next value of q-memd3 is definite
(define pay-next-definite-q-memd3 (n-q-memd3)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd3"
  (unsigned-byte-p 36 n-q-memd3)))
; the next value of q-memd4 is definite
(define pay-next-definite-q-memd4 (n-q-memd4)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd4"
  (unsigned-byte-p 36 n-q-memd4)))
; the next value of q-memd5 is definite
(define pay-next-definite-q-memd5 (n-q-memd5)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd5"
  (unsigned-byte-p 36 n-q-memd5)))
; the next value of q-memd6 is definite
(define pay-next-definite-q-memd6 (n-q-memd6)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd6"
  (unsigned-byte-p 36 n-q-memd6)))
; the next value of q-memd7 is definite
(define pay-next-definite-q-memd7 (n-q-memd7)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-memd7"
  (unsigned-byte-p 36 n-q-memd7)))
; the next value of q-mdd is definite
(define pay-next-definite-q-mdd (n-q-mdd)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-mdd"
  (unsigned-byte-p 36 n-q-mdd)))
; the next value of q-mdp is definite
(define pay-next-definite-q-mdp (n-q-mdp)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-q-mdp"
  (unsigned-byte-p 275 n-q-mdp)))
; the next value of a-saddr is definite
(define pay-next-definite-a-saddr (n-a-saddr)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-a-saddr"
  (unsigned-byte-p 152 n-a-saddr)))
; the next value of a-sdata is definite
(define pay-next-definite-a-sdata (n-a-sdata)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-a-sdata"
  (unsigned-byte-p 2048 n-a-sdata)))
; the next value of a-oaddr is definite
(define pay-next-definite-a-oaddr (n-a-oaddr)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-a-oaddr"
  (unsigned-byte-p 19 n-a-oaddr)))
; the next value of a-odata is definite
(define pay-next-definite-a-odata (n-a-odata)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-definite-a-odata"
  (unsigned-byte-p 256 n-a-odata)))
; the payload invariant holds of the next state
(define pay-next-inv (n-a-head n-a-oaddr n-a-odata n-a-offer n-a-reserved n-a-saddr n-a-sdata n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-offer n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-persisted-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-mdd n-q-mdp n-q-mdw n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mv n-q-rb n-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-next-inv"
  (pay-inv-p n-k-state-q n-k-write-word-q n-k-write-head-q n-k-write-aborted-q n-k-pending-persisted-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-offer n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-q-wb n-q-rb n-q-mv n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-mdp n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-mdd n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mdw n-a-reserved n-a-head n-a-offer n-a-saddr n-a-sdata n-a-oaddr n-a-odata)))
; a write accepted at the controller's typed port
(define pay-typed-accept-p (o-wreqaddr o-wreqdata o-wreqr o-wreqv r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-head-q r-k-write-word-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-typed-accept-p"
  (or (not (and (equal o-wreqv 1) (equal o-wreqr 1)))
      (and (equal r-k-state-q 2)
           (pay-is o-wreqdata (pay-data r-k-write-word-q r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7))
           (pay-is o-wreqaddr (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q r-k-write-word-q))))))
; a write accepted at the boundary's endpoint
(define pay-endpoint-accept-p (h-epready o-epaddr o-epdata o-epv o-epw r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-endpoint-accept-p"
  (or (not (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)))
      (and (equal r-k-state-q 3)
           (pay-is o-epdata (pay-data r-k-write-word-q r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7))
           (or (not (equal r-k-write-aborted-q 0))
               (pay-is o-epaddr (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q r-k-write-word-q)))))))
; a staging beat is accepted only while staging
(define pay-fact-stage-only-while-staging (h-spayload o-spl o-spr r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-stage-only-while-staging"
  (or (not (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)) (equal r-k-state-q 1))))
; bank 0: the staged slots change only by an accepted beat
(define pay-fact-bank0-staged (h-key h-spayload h-value n-k-bank0 o-spl o-spr r-k-bank0 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank0-staged"
  (equal (pay-staged (pay-u n-k-bank0))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 0))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank0))
                        (pay-staged r-k-bank0)))))
; bank 1: the staged slots change only by an accepted beat
(define pay-fact-bank1-staged (h-key h-spayload h-value n-k-bank1 o-spl o-spr r-k-bank1 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank1-staged"
  (equal (pay-staged (pay-u n-k-bank1))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 1))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank1))
                        (pay-staged r-k-bank1)))))
; bank 2: the staged slots change only by an accepted beat
(define pay-fact-bank2-staged (h-key h-spayload h-value n-k-bank2 o-spl o-spr r-k-bank2 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank2-staged"
  (equal (pay-staged (pay-u n-k-bank2))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 2))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank2))
                        (pay-staged r-k-bank2)))))
; bank 3: the staged slots change only by an accepted beat
(define pay-fact-bank3-staged (h-key h-spayload h-value n-k-bank3 o-spl o-spr r-k-bank3 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank3-staged"
  (equal (pay-staged (pay-u n-k-bank3))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 3))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank3))
                        (pay-staged r-k-bank3)))))
; bank 4: the staged slots change only by an accepted beat
(define pay-fact-bank4-staged (h-key h-spayload h-value n-k-bank4 o-spl o-spr r-k-bank4 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank4-staged"
  (equal (pay-staged (pay-u n-k-bank4))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 4))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank4))
                        (pay-staged r-k-bank4)))))
; bank 5: the staged slots change only by an accepted beat
(define pay-fact-bank5-staged (h-key h-spayload h-value n-k-bank5 o-spl o-spr r-k-bank5 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank5-staged"
  (equal (pay-staged (pay-u n-k-bank5))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 5))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank5))
                        (pay-staged r-k-bank5)))))
; bank 6: the staged slots change only by an accepted beat
(define pay-fact-bank6-staged (h-key h-spayload h-value n-k-bank6 o-spl o-spr r-k-bank6 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank6-staged"
  (equal (pay-staged (pay-u n-k-bank6))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 6))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank6))
                        (pay-staged r-k-bank6)))))
; bank 7: the staged slots change only by an accepted beat
(define pay-fact-bank7-staged (h-key h-spayload h-value n-k-bank7 o-spl o-spr r-k-bank7 r-k-expected-coordinate-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-bank7-staged"
  (equal (pay-staged (pay-u n-k-bank7))
                      (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal (loghead 3 r-k-expected-coordinate-q) 7))
                          (pay-staged-put (logtail 3 r-k-expected-coordinate-q) (logapp 16 h-key h-value) (pay-staged r-k-bank7))
                        (pay-staged r-k-bank7)))))
; progress counts the endpoint's acceptances while a row is written
(define pay-fact-progress (h-epready n-a-offer n-a-unissued n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-progress"
  (or (not (and (pay-writing-p r-k-state-q) (pay-writing-p (pay-u n-k-state-q)) (equal (pay-u n-k-write-head-q) r-k-write-head-q)
                              (equal r-k-write-aborted-q 0) (equal (pay-u n-k-write-aborted-q) 0)))
                    (and (equal (+ (pay-u n-k-write-word-q) (pay-accepted (pay-u n-k-state-q) (pay-u n-q-wb) (pay-u n-q-rb) (pay-u n-a-unissued) (pay-u n-a-offer))) (+ r-k-write-word-q (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0)))
                         (equal (pay-u n-k-pending-layer-q) r-k-pending-layer-q)
                         (equal (pay-u n-k-pending-position-q) r-k-pending-position-q)
                         (equal (pay-u n-k-pending-key-exponents-q) r-k-pending-key-exponents-q)
                         (equal (pay-u n-k-pending-value-exponents-q) r-k-pending-value-exponents-q)))))
; a row is finished only by the completion of its word 8, after the endpoint accepted it
(define pay-fact-row-finished (h-epready n-k-state-q n-k-write-head-q n-k-write-word-q o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-row-finished"
  (or (not (and (pay-writing-p r-k-state-q) (equal r-k-write-aborted-q 0)
                              (pay-row-done-p r-k-write-head-q (pay-u n-k-state-q) (pay-u n-k-write-head-q) (pay-u n-k-write-word-q))))
                    (and (equal r-k-state-q 3) (equal r-k-write-word-q 8) (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 1) (equal (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0) 0)))))
; an acceptance at the endpoint is of the word waited on, once
(define pay-fact-accepted-once (h-epready n-a-offer n-a-unissued n-k-state-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-q-rb r-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-accepted-once"
  (or (not (equal (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0) 1))
                    (and (equal r-k-state-q 3) (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 0)
                         (or (not (equal (pay-u n-k-state-q) 3)) (equal (pay-accepted (pay-u n-k-state-q) (pay-u n-q-wb) (pay-u n-q-rb) (pay-u n-a-unissued) (pay-u n-a-offer)) 1))))))
; the record is reported complete only at the unfaulted, uninterrupted completion of its last word
(define pay-fact-reported-complete (i-clear n-k-pending-persisted-q r-a-offer r-a-unissued r-k-pending-persisted-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-reported-complete"
  (or (not (and (equal r-k-pending-persisted-q 0) (equal (pay-u n-k-pending-persisted-q) 1)))
                    (and (equal r-k-state-q 3) (equal r-k-write-head-q 1) (equal r-k-write-word-q 8) (equal r-k-write-aborted-q 0)
                         (equal i-clear 0) (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 1)))))
; CLEAR while a row is written ends the write or marks it interrupted
(define pay-fact-clear (i-clear n-k-pending-persisted-q n-k-state-q n-k-write-aborted-q r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-clear"
  (or (not (and (equal i-clear 1) (pay-writing-p r-k-state-q)))
                    (and (equal (pay-u n-k-pending-persisted-q) 0)
                         (or (equal (pay-u n-k-state-q) 0)
                             (and (equal r-k-state-q 3) (equal (pay-u n-k-state-q) 3) (equal (pay-u n-k-write-aborted-q) 1)))))))
; an interrupted wait stays interrupted and is never reported complete
(define pay-fact-interrupted (n-k-pending-persisted-q n-k-state-q n-k-write-aborted-q r-k-pending-persisted-q r-k-state-q r-k-write-aborted-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-interrupted"
  (or (not (and (equal r-k-state-q 3) (equal r-k-write-aborted-q 1)))
                    (and (or (equal (pay-u n-k-state-q) 0) (and (equal (pay-u n-k-state-q) 3) (equal (pay-u n-k-write-aborted-q) 1)))
                         (or (equal (pay-u n-k-pending-persisted-q) 0) (equal (pay-u n-k-pending-persisted-q) r-k-pending-persisted-q))))))
; the app side judges the descriptor of a presented write legal
(define pay-fact-write-legal (o-wlegal r-k-state-q r-q-mv)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-write-legal"
  (or (not (and (equal r-k-state-q 3) (equal r-q-mv 1))) (equal o-wlegal 1))))
; the address a waited-on word carries does not change, and is the address the endpoint accepts
(define pay-fact-carried-address (h-epready n-a-head n-a-offer n-a-saddr n-a-unissued n-k-state-q n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-rb n-q-wb o-epaddr o-epv o-epw r-a-head r-a-offer r-a-saddr r-a-unissued r-k-state-q r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-rb r-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "pay-fact-carried-address"
  (or (not (and (equal r-k-state-q 3) (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 0)))
                    (and (or (not (equal (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0) 1)) (pay-is o-epaddr (pay-carried-addr r-q-wb r-q-rb (pay-cell (loghead 3 r-q-rb) r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7) r-a-head r-a-saddr)))
                         (or (not (and (equal (pay-u n-k-state-q) 3) (equal (pay-accepted (pay-u n-k-state-q) (pay-u n-q-wb) (pay-u n-q-rb) (pay-u n-a-unissued) (pay-u n-a-offer)) 0)))
                             (equal (pay-carried-addr (pay-u n-q-wb) (pay-u n-q-rb) (pay-cell (loghead 3 (pay-u n-q-rb)) (pay-u n-q-memp0) (pay-u n-q-memp1) (pay-u n-q-memp2) (pay-u n-q-memp3) (pay-u n-q-memp4) (pay-u n-q-memp5) (pay-u n-q-memp6) (pay-u n-q-memp7)) (pay-u n-a-head) (pay-u n-a-saddr)) (pay-carried-addr r-q-wb r-q-rb (pay-cell (loghead 3 r-q-rb) r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7) r-a-head r-a-saddr)))))))
(in-theory (disable pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7 pay-next-definite-k-rd0 pay-next-definite-k-rd1 pay-next-definite-k-rd2 pay-next-definite-k-rd3 pay-next-definite-k-rd4 pay-next-definite-k-rd5 pay-next-definite-k-rd6 pay-next-definite-k-rd7 pay-next-definite-k-offer pay-next-definite-q-memp0 pay-next-definite-q-memp1 pay-next-definite-q-memp2 pay-next-definite-q-memp3 pay-next-definite-q-memp4 pay-next-definite-q-memp5 pay-next-definite-q-memp6 pay-next-definite-q-memp7 pay-next-definite-q-memd0 pay-next-definite-q-memd1 pay-next-definite-q-memd2 pay-next-definite-q-memd3 pay-next-definite-q-memd4 pay-next-definite-q-memd5 pay-next-definite-q-memd6 pay-next-definite-q-memd7 pay-next-definite-q-mdd pay-next-definite-q-mdp pay-next-definite-a-saddr pay-next-definite-a-sdata pay-next-definite-a-oaddr pay-next-definite-a-odata pay-next-inv pay-typed-accept-p pay-endpoint-accept-p pay-fact-stage-only-while-staging pay-fact-bank0-staged pay-fact-bank1-staged pay-fact-bank2-staged pay-fact-bank3-staged pay-fact-bank4-staged pay-fact-bank5-staged pay-fact-bank6-staged pay-fact-bank7-staged pay-fact-progress pay-fact-row-finished pay-fact-accepted-once pay-fact-reported-complete pay-fact-clear pay-fact-interrupted pay-fact-write-legal pay-fact-carried-address))

; THE CONCLUSION of the step lemma: with no protocol violation by the
; client and no malformed metadata word from the endpoint in the cycle,
; every conjunct above.
(define pay-step-concl (h-epready h-key h-spayload h-value i-clear n-a-head n-a-oaddr n-a-odata n-a-offer n-a-reserved n-a-saddr n-a-sdata n-a-unissued n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-offer n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-persisted-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-mdd n-q-mdp n-q-mdw n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mv n-q-rb n-q-wb o-epaddr o-epdata o-epf o-epv o-epw o-pfn o-spl o-spr o-tpf o-wlegal o-wreqaddr o-wreqdata o-wreqr o-wreqv r-a-head r-a-offer r-a-saddr r-a-unissued r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-persisted-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-mv r-q-rb r-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (if (and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))
      (and (pay-next-definite-k-bank0 n-k-bank0)
           (pay-next-definite-k-bank1 n-k-bank1)
           (pay-next-definite-k-bank2 n-k-bank2)
           (pay-next-definite-k-bank3 n-k-bank3)
           (pay-next-definite-k-bank4 n-k-bank4)
           (pay-next-definite-k-bank5 n-k-bank5)
           (pay-next-definite-k-bank6 n-k-bank6)
           (pay-next-definite-k-bank7 n-k-bank7)
           (pay-next-definite-k-rd0 n-k-rd0)
           (pay-next-definite-k-rd1 n-k-rd1)
           (pay-next-definite-k-rd2 n-k-rd2)
           (pay-next-definite-k-rd3 n-k-rd3)
           (pay-next-definite-k-rd4 n-k-rd4)
           (pay-next-definite-k-rd5 n-k-rd5)
           (pay-next-definite-k-rd6 n-k-rd6)
           (pay-next-definite-k-rd7 n-k-rd7)
           (pay-next-definite-k-offer n-k-offer)
           (pay-next-definite-q-memp0 n-q-memp0)
           (pay-next-definite-q-memp1 n-q-memp1)
           (pay-next-definite-q-memp2 n-q-memp2)
           (pay-next-definite-q-memp3 n-q-memp3)
           (pay-next-definite-q-memp4 n-q-memp4)
           (pay-next-definite-q-memp5 n-q-memp5)
           (pay-next-definite-q-memp6 n-q-memp6)
           (pay-next-definite-q-memp7 n-q-memp7)
           (pay-next-definite-q-memd0 n-q-memd0)
           (pay-next-definite-q-memd1 n-q-memd1)
           (pay-next-definite-q-memd2 n-q-memd2)
           (pay-next-definite-q-memd3 n-q-memd3)
           (pay-next-definite-q-memd4 n-q-memd4)
           (pay-next-definite-q-memd5 n-q-memd5)
           (pay-next-definite-q-memd6 n-q-memd6)
           (pay-next-definite-q-memd7 n-q-memd7)
           (pay-next-definite-q-mdd n-q-mdd)
           (pay-next-definite-q-mdp n-q-mdp)
           (pay-next-definite-a-saddr n-a-saddr)
           (pay-next-definite-a-sdata n-a-sdata)
           (pay-next-definite-a-oaddr n-a-oaddr)
           (pay-next-definite-a-odata n-a-odata)
           (pay-next-inv n-a-head n-a-oaddr n-a-odata n-a-offer n-a-reserved n-a-saddr n-a-sdata n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-offer n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-persisted-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-mdd n-q-mdp n-q-mdw n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mv n-q-rb n-q-wb)
           (pay-typed-accept-p o-wreqaddr o-wreqdata o-wreqr o-wreqv r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-head-q r-k-write-word-q)
           (pay-endpoint-accept-p h-epready o-epaddr o-epdata o-epv o-epw r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
           (pay-fact-stage-only-while-staging h-spayload o-spl o-spr r-k-state-q)
           (pay-fact-bank0-staged h-key h-spayload h-value n-k-bank0 o-spl o-spr r-k-bank0 r-k-expected-coordinate-q)
           (pay-fact-bank1-staged h-key h-spayload h-value n-k-bank1 o-spl o-spr r-k-bank1 r-k-expected-coordinate-q)
           (pay-fact-bank2-staged h-key h-spayload h-value n-k-bank2 o-spl o-spr r-k-bank2 r-k-expected-coordinate-q)
           (pay-fact-bank3-staged h-key h-spayload h-value n-k-bank3 o-spl o-spr r-k-bank3 r-k-expected-coordinate-q)
           (pay-fact-bank4-staged h-key h-spayload h-value n-k-bank4 o-spl o-spr r-k-bank4 r-k-expected-coordinate-q)
           (pay-fact-bank5-staged h-key h-spayload h-value n-k-bank5 o-spl o-spr r-k-bank5 r-k-expected-coordinate-q)
           (pay-fact-bank6-staged h-key h-spayload h-value n-k-bank6 o-spl o-spr r-k-bank6 r-k-expected-coordinate-q)
           (pay-fact-bank7-staged h-key h-spayload h-value n-k-bank7 o-spl o-spr r-k-bank7 r-k-expected-coordinate-q)
           (pay-fact-progress h-epready n-a-offer n-a-unissued n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
           (pay-fact-row-finished h-epready n-k-state-q n-k-write-head-q n-k-write-word-q o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
           (pay-fact-accepted-once h-epready n-a-offer n-a-unissued n-k-state-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-q-rb r-q-wb)
           (pay-fact-reported-complete i-clear n-k-pending-persisted-q r-a-offer r-a-unissued r-k-pending-persisted-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
           (pay-fact-clear i-clear n-k-pending-persisted-q n-k-state-q n-k-write-aborted-q r-k-state-q)
           (pay-fact-interrupted n-k-pending-persisted-q n-k-state-q n-k-write-aborted-q r-k-pending-persisted-q r-k-state-q r-k-write-aborted-q)
           (pay-fact-write-legal o-wlegal r-k-state-q r-q-mv)
           (pay-fact-carried-address h-epready n-a-head n-a-offer n-a-saddr n-a-unissued n-k-state-q n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-rb n-q-wb o-epaddr o-epv o-epw r-a-head r-a-offer r-a-saddr r-a-unissued r-k-state-q r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-rb r-q-wb))
    t))
(in-theory (disable pay-step-concl))

; A write state that is not interrupted, other than the record's start, is
; entered only from a write state that is not interrupted, in a cycle
; without CLEAR: either on the same row, or by the one step that changes
; row, from the wait on word 8 of the K row to the first prefetch of word 0
; of the V row, and that step leaves the record's layer, position and
; exponent bytes as they were.
(define rec-fact-entry (i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "rec-fact-entry"
  (or (not (and (pay-writing-p (pay-u n-k-state-q)) (equal (pay-u n-k-write-aborted-q) 0)
                  (not (and (equal (pay-u n-k-state-q) 9) (equal (pay-u n-k-write-head-q) 0) (equal (pay-u n-k-write-word-q) 0)))))
      (and (pay-writing-p r-k-state-q) (equal r-k-write-aborted-q 0) (equal i-clear 0)
           (or (equal (pay-u n-k-write-head-q) r-k-write-head-q)
               (and (equal r-k-state-q 3) (equal r-k-write-head-q 0) (equal r-k-write-word-q 8)
                    (equal (pay-u n-k-state-q) 9) (equal (pay-u n-k-write-head-q) 1) (equal (pay-u n-k-write-word-q) 0)
                    (equal (pay-u n-k-pending-layer-q) r-k-pending-layer-q) (equal (pay-u n-k-pending-position-q) r-k-pending-position-q)
                    (equal (pay-u n-k-pending-key-exponents-q) r-k-pending-key-exponents-q) (equal (pay-u n-k-pending-value-exponents-q) r-k-pending-value-exponents-q)))))))
; The record's start, the first prefetch of word 0 of the K row, is entered
; only from staging, by the acceptance of the beat for coordinate 127, in a
; cycle without CLEAR, and it starts not interrupted.
(define rec-fact-start (h-spayload i-clear n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-spl o-spr r-k-expected-coordinate-q r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "rec-fact-start"
  (or (not (and (equal (pay-u n-k-state-q) 9) (equal (pay-u n-k-write-head-q) 0) (equal (pay-u n-k-write-word-q) 0)))
      (and (equal r-k-state-q 1) (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal r-k-expected-coordinate-q 127)
           (equal (pay-u n-k-write-aborted-q) 0) (equal i-clear 0)))))
(in-theory (disable rec-fact-entry rec-fact-start))

; THE CONCLUSION of the new step lemma: with no protocol violation by the
; client and no malformed metadata word from the endpoint in the cycle
; (the antecedent of the payload step lemma), both facts.
(define rec-step-concl (h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (if (and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))
      (and (rec-fact-entry i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
           (rec-fact-start h-spayload i-clear n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-spl o-spr r-k-expected-coordinate-q r-k-state-q))
    t))
(in-theory (disable rec-step-concl))

(acl2::must-fail
 (encapsulate nil
   (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
   (make-event
    '(def-svtv-generalized-thm rec-step-svtv-thm
       :svtv payload-step-run
       :svtv-spec payload-step-spec
       :input-vars :all
       :output-vars (o-pfn o-tpf o-epf o-spr o-spl n-k-state-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-write-head-q n-k-write-word-q n-k-write-aborted-q)
       :unsigned-byte-hyps t
       :no-integerp t
       :enable (pay-int-o-pfn-integerp pay-int-o-tpf-integerp pay-int-o-epf-integerp pay-int-o-spr-integerp pay-int-o-spl-integerp pay-int-n-k-state-q-integerp pay-int-n-k-pending-layer-q-integerp pay-int-n-k-pending-position-q-integerp pay-int-n-k-pending-key-exponents-q-integerp pay-int-n-k-pending-value-exponents-q-integerp pay-int-n-k-write-head-q-integerp pay-int-n-k-write-word-q-integerp pay-int-n-k-write-aborted-q-integerp)
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
       :concl (and (pay-int-o-pfn o-pfn)
            (pay-int-o-tpf o-tpf)
            (pay-int-o-epf o-epf)
            (pay-int-o-spr o-spr)
            (pay-int-o-spl o-spl)
            (pay-int-n-k-state-q n-k-state-q)
            (pay-int-n-k-pending-layer-q n-k-pending-layer-q)
            (pay-int-n-k-pending-position-q n-k-pending-position-q)
            (pay-int-n-k-pending-key-exponents-q n-k-pending-key-exponents-q)
            (pay-int-n-k-pending-value-exponents-q n-k-pending-value-exponents-q)
            (pay-int-n-k-write-head-q n-k-write-head-q)
            (pay-int-n-k-write-word-q n-k-write-word-q)
            (pay-int-n-k-write-aborted-q n-k-write-aborted-q)
            (rec-step-concl h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)))))
 :with-output-off nil)

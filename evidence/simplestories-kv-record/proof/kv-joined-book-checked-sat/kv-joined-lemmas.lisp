; The repaired RTL as a state machine, and the two lemmas about it on arbitrary executions.
;
; Private.  Part of the joined K/V book; see README.md in this directory.
; Written by make_book.py from the pilot's proof (../acl2-pilot/joined);
; edit that script, not this file.
;
; Exports
;   (probe-fsm)            the state machine of the probe module: one step is
;                          one clock cycle of both clocks
;   join-reset-fsm-thm     three reset cycles establish the invariant
;   join-step-fsm-thm      a cycle under the environment preserves it, and on
;                          that cycle the clause holds for writes and for
;                          reads and terminal_fault_event is low
; Each is first proved of one symbolic run by bit-blasting (FGL, and a SAT
; solver whose proofs ACL2 checks) and then lifted by the library to every
; cycle of every execution.
(in-package "SV")
(include-book "centaur/sv/svtv/svtv-to-fsm-defs" :dir :system)
(include-book "centaur/fgl/top" :dir :system)
(include-book "centaur/sv/svtv/svtv-stobj-defsvtv" :dir :system)
(include-book "centaur/vl/loader/top" :dir :system)
(include-book "centaur/sv/vl/top" :dir :system)
(include-book "oslib/ls" :dir :system)
(include-book "centaur/sv/svtv/svtv-stobj-debug" :dir :system)
(include-book "centaur/misc/memory-mgmt" :dir :system)
(include-book "kv-joined-statements")
(include-book "kv-joined-pins")

(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
; The library's generated lemmas about a run with several hundred named
; signals nest deeper than the rewriter's default limit of 1000.
(acl2::set-rewrite-stack-limit 20000)

; The SAT solver.  FGL turns each symbolic lemma into a propositional formula
; and hands it to a solver through satlink.  No answer of the solver is
; believed.  With :lrat-check t, satlink reports "unsatisfiable" only after
; ACL2 has run the library's verified checker (projects/sat/lrat) on the
; proof the solver wrote, against the formula ACL2 itself wrote; an answer
; of "satisfiable" is accepted only after ACL2 has evaluated the formula
; under the assignment.  The command is CaDiCaL behind a short script,
; run from this directory (README.md, "Trust").
(defun bct-satlink-config ()
  (declare (xargs :guard t))
  (satlink::make-config :cmdline "sh sat/cadical-lrat.sh" :verbose nil
                        :mintime 0 :remove-temps t :lrat-check t))
(defthm kv-joined-sat-proofs-are-checked
  (equal (satlink::config->lrat-check (bct-satlink-config)) t)
  :rule-classes nil)
(defattach fgl::fgl-satlink-config bct-satlink-config)
(value-triple (acl2::tshell-ensure))

; ---------------------------------------------------------------------------
; The RTL.  The joined source tree with the F1 repair: rtl/ in this directory.
; ---------------------------------------------------------------------------
(defconst *kvj-rtl-files*
  '(
    "rtl/defines.v"
    "rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_isqrt_u45_iterative.sv"
    "rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_rne_div_signed64_iterative.sv"
    "rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_private_issue_guard.sv"
    "rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_unified_dsp64.sv"
    "rtl/fpga/token_only_model0_ddr_board1/ddr_phy_open0/rtl/board1_private_ddr256_to_w640.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_rne_div_signed64.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_attention_compact1/rtl/board1_fixed_attention_rne_shift_iterative.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise0/rtl/board1_fixed_elementwise_dsp_lane.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_dsp.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_compact_lane.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine1/rtl/board1_fixed_elementwise_lane_core.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_group_ddr_stream1/rtl/board1_fixed_group_ddr_stream.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_group_projection_scale_integration0/rtl/board1_fixed_group_projection_scale_job.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_argmax.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_logit_greater.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_metadata_stream0/rtl/board1_fixed_projection_metadata_reader.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_scratch_ram.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector128_ram.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector256_ram.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_rope_raw_ram.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_token_shell0/rtl/board1_fixed_embedding_lookup.sv"
    "rtl/normalizer_pipeline.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_vector_normalize0/rtl/board1_fixed_vector_rne_shift_iterative.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_arithmetic.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_rom.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_vector_rmsnorm_service.sv"
    "rtl/fpga/token_only_model0_ddr_board1/shared_projection_scale0/rtl/board1_shared_projection_scale_engine.sv"
    "rtl/cluster-adapter.sv"
    "rtl/fpga/token_only_model0_ddr_board1/unified_dsp0/rtl/board1_unified_projection_head_mul_exact.sv"
    "rtl/fpga/token_only_model0_ddr_board1/unified_dynamic_dsp1/rtl/board1_unified_projection_head_dynamic_mul_exact.sv"
    "rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine0/rtl/board1_fixed_private_ddr_arbiter.sv"
    "rtl/fifo.sv"
    "rtl/mapper_portable.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_app_boundary.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_boundary.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention_memories.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_lookup.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_sequence.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_layer.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv"
    "rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_machine_core.sv"
    "rtl/shared_token_probe.sv"
    "rtl/sha.sv"
    "rtl/bank.sv"
    "rtl/service.sv"
    "rtl/cluster-mul.sv"
    "rtl/cluster-tile.sv"
    "rtl/cluster-engine.sv"
    "rtl/candidate.sv"
    "rtl/arbiter.sv"
    "rtl/cdc.sv"
    "rtl/adapter.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_private_ddr_lock_bridge.sv"
    "rtl/fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_ddr_preboard_locked_boundary.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_ddr_locked_auth_watchdog_cdc.sv"
    "rtl/handoff.sv"
    "rtl/booted_memory.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_qspi_read03_master.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_qspi_async_word_fifo4.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_qspi_image_stream.sv"
    "rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_rx.sv"
    "rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_tx.sv"
    "rtl/fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_command_adapter.sv"
    "rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_endpoint_fault_cdc.sv"
    "rtl/reset.sv"
    "rtl/uart_core.sv"
    "rtl/thin_transport.sv"
    "rtl/top.sv"
    ))

(defconst *kvj-rtl-sha256-pinned*
  '(
    ("rtl/defines.v"
     . "4be31be33f0a15bf617e98aa6bbf465f3820603aec4302b8f9d28e5e0ae7420c")
    ("rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_isqrt_u45_iterative.sv"
     . "307d3a01aab81015cc72360c70b1569895b5632d2f5bd12d40f26f998fb4d4a0")
    ("rtl/fpga/token_only_model0_board0/rtl/physical/board0_exact_rne_div_signed64_iterative.sv"
     . "ae9d3077ae11693bfe67d8f0ef0f5c89bd3581ab6df2160aa63dbdebb6294707")
    ("rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_private_issue_guard.sv"
     . "2335a5473e6f3e5bb71d3c64d136c5d1fb5cf0f8d73b5b907b4c1871c07f2755")
    ("rtl/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_unified_dsp64.sv"
     . "a82b7d0c9f97932c5205e2fe902e27ab341c15438f25bf067cb2b1a0a8cf43c4")
    ("rtl/fpga/token_only_model0_ddr_board1/ddr_phy_open0/rtl/board1_private_ddr256_to_w640.sv"
     . "1b35784af0052d923abcb5c6a57303252ef352774abc90d566d23ee0d6c8bd93")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv"
     . "71c528cd039ea3afd3d799ae44cdcb273c839a9c3ccbaf4c9c2b5d47c226388c")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_rne_div_signed64.sv"
     . "9137e2a36a27f9956bc9ecfdcbbbe3d1d4670dbd6fac2b2990653ff1eb79c236")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_attention_compact1/rtl/board1_fixed_attention_rne_shift_iterative.sv"
     . "91afdd7fb4e77f8f409bfdb20676e22ac365056d45f746b77c6eeefc191667b6")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise0/rtl/board1_fixed_elementwise_dsp_lane.sv"
     . "b892d1880c12e5dfe25f0df1c31e69e399b2d6395a906246c29cdec8c47aa766")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_dsp.sv"
     . "442e19ecee47bdab0c2e44536d3cb3663019077939aca1e23420ac7eaac8d30c")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_compact_lane.sv"
     . "ce337d8b56ebd3a91bf2788aa73ac13ecc6aff45a600447b51f87e795293b931")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine1/rtl/board1_fixed_elementwise_lane_core.sv"
     . "b6d795d540a3f6eac25cd2d783fc7bcb4e31edc5e7303e987ae4f5a153c7c199")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_group_ddr_stream1/rtl/board1_fixed_group_ddr_stream.sv"
     . "3ec7ab00aa43a5950e36be5f16edabf7250692488f1f69da348bcd22b75243b1")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_group_projection_scale_integration0/rtl/board1_fixed_group_projection_scale_job.sv"
     . "c5bd334b7a550cf33a2019d28f234c757415e1c2642f6e3862ffb62cfcd60a10")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_argmax.sv"
     . "2e66294ebc8be89651da3861d8c9200a9a1e689628630ae40a3cd6670bfe378d")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_logit_greater.sv"
     . "568a0db90018c50697072fce190ef448ab792f943fff906bd0113eb4630832d5")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_metadata_stream0/rtl/board1_fixed_projection_metadata_reader.sv"
     . "18f039839b7e91d41ddefbd20812a2114b99c58773d8cc577dd29f02f012d4e1")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_scratch_ram.sv"
     . "2fa8cb1f42f59262ff4183180aaf80336d877f527a2e103661ce9fe94d621bd7")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector128_ram.sv"
     . "4a51f313fe07d9af9b45f08af6c51a6f0952f98be74e29ffe8a320a6780e07d6")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector256_ram.sv"
     . "8d8ab1fc9d4e638b6ef13a0da50e22f65fcfb844bc6950ca88a09a466aad31f2")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_rope_raw_ram.sv"
     . "3238dc4454b9e37d54252c9cf2101e58cfaca527bff93dbad785667531e435fc")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_token_shell0/rtl/board1_fixed_embedding_lookup.sv"
     . "266f25879a3cc51424e6b71f46a5a1a62eab6b29c3c39c748bc4fc51de7d07ba")
    ("rtl/normalizer_pipeline.sv"
     . "2c4f052ffcbdaba1c9b9b23035b39f3fb24ecbfd081edd45ca8d996f0c9ec028")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_vector_normalize0/rtl/board1_fixed_vector_rne_shift_iterative.sv"
     . "12c73c9f2100212b87b9982e7ed43739db06c4a5376d4788cc08f391b61131ab")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_arithmetic.sv"
     . "375e5eef4069c1314103d98d562d6b31269a16eed4cb9e979358b7398ce05818")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_rom.sv"
     . "9f1b436fefe63a80a0ee1d8ef1766812d42749a1f9d2ff1b7958fa98e1438e73")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_vector_rmsnorm_service.sv"
     . "c4d1046ae5b0da5f2ed95ee684f59b637d93d4350db550f19a321773935874fb")
    ("rtl/fpga/token_only_model0_ddr_board1/shared_projection_scale0/rtl/board1_shared_projection_scale_engine.sv"
     . "52fd2d82ed6d80a77f5252a3437eac4661c13e4deccb03a9b68fbf1d2eec2bb4")
    ("rtl/cluster-adapter.sv"
     . "ceece65290b18868e693009917b933c5259515d96ac7bbadf09efbb9ba9998ab")
    ("rtl/fpga/token_only_model0_ddr_board1/unified_dsp0/rtl/board1_unified_projection_head_mul_exact.sv"
     . "8385ac32fcd8037bd4f4722330949fddd88d5eaa5175155d903a86b76f39c2b9")
    ("rtl/fpga/token_only_model0_ddr_board1/unified_dynamic_dsp1/rtl/board1_unified_projection_head_dynamic_mul_exact.sv"
     . "be50b7539cb4e6518bd5f98e738d9fd8a9067fbe94a923cdc40857652505768c")
    ("rtl/fpga/token_only_model0_ddr_board1/fixed_token_machine0/rtl/board1_fixed_private_ddr_arbiter.sv"
     . "0bb8c9b269a6e7cd9e0a5ddac1e69b737de4031fca1d8da24ea6f3d6a25cc286")
    ("rtl/fifo.sv"
     . "e742e2ebcce91154ff96892c32dc297bf1c1460a73b9de73eac1a8a4161f926f")
    ("rtl/mapper_portable.sv"
     . "89e6de98bc965d0786d58cb56d1562d0448f95d342395a8badca35f4326428e1")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_app_boundary.sv"
     . "020fb750570e0a79537204a5cdb1ecace8ebf86711cf085f4f3d2247ce32b9e0")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_boundary.sv"
     . "d030fc7fcee27c1b2fddd3503ad9a3d2160b4af4df393393c5b727e7571369f1")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention_memories.sv"
     . "0210df9e549f44e1c71ed2ee4c9c3c6051c6b62c4c6f3bdbddaa6adb46d3e6ff")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention.sv"
     . "c310723548a61b48d19937de229ad349bd69901797916e18d1ff7bd6431f1a68")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv"
     . "c3cc85fd18de01c20fe981bdb482ff17ed6706b6e3d7c257f57c10479674b272")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_lookup.sv"
     . "ec9cd7c0fd9982bdee31c0193d345821b266e68fcffc3693be1aea9bff5e297e")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_sequence.sv"
     . "2310be898bde68d1b824335f36147785d88b0a398906bc9488aedef70a1c3fc0")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv"
     . "020600127fe68203340e86d219de0f41d3d5210d8276b561a1ecde229d4987c6")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_layer.sv"
     . "9a5e3350773efdd8da29821bc8b936b57d2ba1287c10e863d010e30345755612")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv"
     . "b76ca530210fa416577410c1038d2d2f5ee16452ce39cabf8be2a3f7ead2d250")
    ("rtl/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_machine_core.sv"
     . "6432b4ef168ad61618e9994bc96a6c9172c60eca13f148fc0c2ecca80d03089a")
    ("rtl/shared_token_probe.sv"
     . "c8681158676072106fa1f4072573813849d35744b1c723acb872a23ea0c49af0")
    ("rtl/sha.sv"
     . "512a7d09bbcb30bb01a4dc6102590afe6eb886db5a27b1576a71f5577727768b")
    ("rtl/bank.sv"
     . "00b1cc227e444f91af8ac3a8f374af8f2b1a5b14884ca51f46c312bbc970d6d6")
    ("rtl/service.sv"
     . "a33e45de9d24668f105971bdfe8902882f793fa508c570c9bb0b5ce34a020403")
    ("rtl/cluster-mul.sv"
     . "17dc41f46dd535434bf0f7da503218e61289dd63ea7409f4e687f38bf0615267")
    ("rtl/cluster-tile.sv"
     . "60e79557fb67981cc4ad3f342c363b29a49456c482eea3de37ab40bc078b3068")
    ("rtl/cluster-engine.sv"
     . "232949abf47d652df2f6c420f96445aed86e44c44d0e6481a28d522658a54b6f")
    ("rtl/candidate.sv"
     . "92e265e267dcc1c988da340b9d6845332c8f67333f389412d3f9454ccb897479")
    ("rtl/arbiter.sv"
     . "770f643a9b026904465c58f3c327a34ff124c9db0f41a833804491e2e776e76b")
    ("rtl/cdc.sv"
     . "dbf6be77bdfeb952ea433ba2b27c3177b8f86f0ea11103dae7ea5f52efebe0ef")
    ("rtl/adapter.sv"
     . "96c4d8eca498cf19687ba35c80e981b0122ba04345ca9ab399e969a894647cad")
    ("rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_private_ddr_lock_bridge.sv"
     . "b801c921f7c0cf359fe33b04030f6701f43e4e9df24a9f04d92384a5ee1b0095")
    ("rtl/fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv"
     . "c7b6eb47fd8b73d804d92651b950eb63fd896e2503b8efc7dc8b6985850c5c05")
    ("rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_ddr_preboard_locked_boundary.sv"
     . "7c7582d45693e6abac33d9be91cbe64da832f0f358ab3c60450c00cddcf293c3")
    ("rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv"
     . "0a3a8333213fb4f8fe4ee3ca17af6efb95bad61577c3c6f00233bb7ed875a59f")
    ("rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_ddr_locked_auth_watchdog_cdc.sv"
     . "5262346f446d4e0fd7a982214652306d7dec94f2e8c43f9d909d67bde122782a")
    ("rtl/handoff.sv"
     . "edca5ac4866b3ba2bdb96e47ac8d0b1ec56c3e890f1e328cf20d746d1c9d14f1")
    ("rtl/booted_memory.sv"
     . "5e5c7081db529f581a421c48765db330a8bcdedecb95b0d98d356ffb973ad363")
    ("rtl/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_qspi_read03_master.sv"
     . "77ec76f2080e2bf7089c0fed001780e9d55703a5323ab951e0a0bc556523e161")
    ("rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_qspi_async_word_fifo4.sv"
     . "47852af52c54917fd67bb7da0c76238a922ad7f33f2702ac812d0c9b35a94a47")
    ("rtl/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_qspi_image_stream.sv"
     . "7975f7c9835afda6561f11c2d026ada15e3f1003df129fe82aa20e2aa664b642")
    ("rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_rx.sv"
     . "488bde775088037dd8aed998f4beef76e121ab2917d3f776359e99cc4b2c5739")
    ("rtl/fpga/token_only_model0_mac_uart0/rtl/fixed_uart_tx.sv"
     . "48477b86e217a049ee912e3ace9ae4b3a4e5d6227f2b27f4f832330ff05fa527")
    ("rtl/fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv"
     . "87abc248c3f154ac23ff78739aacfd21db10c277fbc2de75fca0129c403d0b0c")
    ("rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_command_adapter.sv"
     . "2f788b202d2972238bb45076df61bb0e5f1dc40e790d9504c770a29adc121e56")
    ("rtl/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_endpoint_fault_cdc.sv"
     . "dd47d5fcb370002721ddb4accbab92d7572a723c994a8e04d97947215a39bea6")
    ("rtl/reset.sv"
     . "06f46a593a7544ff16f931ff3e544c2bcbf3c2420ed5d6b0d33bfae6a45cf4fa")
    ("rtl/uart_core.sv"
     . "6eac2d6506077023432fef601b458134007e619f5c9a026fed9729eabbb9f273")
    ("rtl/thin_transport.sv"
     . "7deea87338c8c2160247bdb68961aed8513cb483a18450f38859f7edbeba46ed")
    ("rtl/top.sv"
     . "2a58277179bb43d830099deca5529f9c269c7c4d64791fc9df22efcc1165c675")
    ))

; The Verilog loader reads the files; the SHA-256 of each is computed from
; the very text the loader read.  The parse trees are not kept in the book.
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
  (make-event `(defconst *kvj-modules-translated*
                 ',(len (vl::vl-design->mods *vl-good*))))
  (make-event `(defconst *sv-design* ',*kvj-sv-design*)))

(defthm kv-joined-rtl-is-the-pinned-rtl
  (equal *kvj-rtl-sha256-as-read* *kvj-rtl-sha256-pinned*)
  :rule-classes nil)

(defthm kv-joined-modules-translated
  (equal *kvj-modules-translated* 70)
  :rule-classes nil)

; The translator source, hashed again in this session, the one that
; translated the RTL.
(defconsts (*kvj-translator-sha256-when-translating* state)
  (mv (kvj-translator-sha256 state) state))

(defthm kv-joined-rtl-was-translated-by-the-corrected-translator
  (equal *kvj-translator-sha256-when-translating* *kvj-translator-sha256-pinned*)
  :rule-classes nil)


; ===========================================================================
; Reset.  Three consecutive cycles with reset_n_i low; every other input and
; the whole prior state unknown.  In the third, every register the reset
; clears is zero.  The FIFO memory cells are not reset: their control bits
; are named in that cycle and assumed two-valued.
; ===========================================================================
(defsvtv$ join-reset-run
  :design *sv-design*
  :cycle-phases (list (make-svtv-cyclephase
                       :constants '(("core_clk_i" . 1) ("app_clk_i" . 1)
                                    ("reset_n_i" . 1)))
                      (make-svtv-cyclephase
                       :constants '(("core_clk_i" . 0) ("app_clk_i" . 0))
                       :inputs-free t :outputs-captured t))
  :stages ((:label rst0 :inputs (("reset_n_i" 0) ("clear_i" i-clear)))
           (:label rst1 :inputs (("reset_n_i" 0)))
           (:label rst2 :inputs (("reset_n_i" 0))
            :overrides (
             ("u_boundary.request_fifo_i.memory_q[0][317:315]" r-q-mem0 :cond c-q-mem0 :output p-q-mem0)
             ("u_boundary.request_fifo_i.memory_q[1][317:315]" r-q-mem1 :cond c-q-mem1 :output p-q-mem1)
             ("u_boundary.request_fifo_i.memory_q[2][317:315]" r-q-mem2 :cond c-q-mem2 :output p-q-mem2)
             ("u_boundary.request_fifo_i.memory_q[3][317:315]" r-q-mem3 :cond c-q-mem3 :output p-q-mem3)
             ("u_boundary.request_fifo_i.memory_q[4][317:315]" r-q-mem4 :cond c-q-mem4 :output p-q-mem4)
             ("u_boundary.request_fifo_i.memory_q[5][317:315]" r-q-mem5 :cond c-q-mem5 :output p-q-mem5)
             ("u_boundary.request_fifo_i.memory_q[6][317:315]" r-q-mem6 :cond c-q-mem6 :output p-q-mem6)
             ("u_boundary.request_fifo_i.memory_q[7][317:315]" r-q-mem7 :cond c-q-mem7 :output p-q-mem7)
             ("u_boundary.response_fifo_i.memory_q[0][259:256]" r-s-mem0 :cond c-s-mem0 :output p-s-mem0)
             ("u_boundary.response_fifo_i.memory_q[1][259:256]" r-s-mem1 :cond c-s-mem1 :output p-s-mem1)
             ("u_boundary.response_fifo_i.memory_q[2][259:256]" r-s-mem2 :cond c-s-mem2 :output p-s-mem2)
             ("u_boundary.response_fifo_i.memory_q[3][259:256]" r-s-mem3 :cond c-s-mem3 :output p-s-mem3)
             ("u_boundary.response_fifo_i.memory_q[4][259:256]" r-s-mem4 :cond c-s-mem4 :output p-s-mem4)
             ("u_boundary.response_fifo_i.memory_q[5][259:256]" r-s-mem5 :cond c-s-mem5 :output p-s-mem5)
             ("u_boundary.response_fifo_i.memory_q[6][259:256]" r-s-mem6 :cond c-s-mem6 :output p-s-mem6)
             ("u_boundary.response_fifo_i.memory_q[7][259:256]" r-s-mem7 :cond c-s-mem7 :output p-s-mem7)
             ("u_boundary.request_fifo_i.memory_q[0][278:275]" r-q-memw0 :cond c-q-memw0 :output p-q-memw0)
             ("u_boundary.request_fifo_i.memory_q[1][278:275]" r-q-memw1 :cond c-q-memw1 :output p-q-memw1)
             ("u_boundary.request_fifo_i.memory_q[2][278:275]" r-q-memw2 :cond c-q-memw2 :output p-q-memw2)
             ("u_boundary.request_fifo_i.memory_q[3][278:275]" r-q-memw3 :cond c-q-memw3 :output p-q-memw3)
             ("u_boundary.request_fifo_i.memory_q[4][278:275]" r-q-memw4 :cond c-q-memw4 :output p-q-memw4)
             ("u_boundary.request_fifo_i.memory_q[5][278:275]" r-q-memw5 :cond c-q-memw5 :output p-q-memw5)
             ("u_boundary.request_fifo_i.memory_q[6][278:275]" r-q-memw6 :cond c-q-memw6 :output p-q-memw6)
             ("u_boundary.request_fifo_i.memory_q[7][278:275]" r-q-memw7 :cond c-q-memw7 :output p-q-memw7)
             ("u_boundary.app_boundary_i.read_slot_q[0]" r-a-rslot0 :cond c-a-rslot0 :output p-a-rslot0)
             ("u_boundary.app_boundary_i.read_slot_q[1]" r-a-rslot1 :cond c-a-rslot1 :output p-a-rslot1)
             ("u_boundary.app_boundary_i.read_slot_q[2]" r-a-rslot2 :cond c-a-rslot2 :output p-a-rslot2)
             ("u_boundary.app_boundary_i.read_slot_q[3]" r-a-rslot3 :cond c-a-rslot3 :output p-a-rslot3)
             ("u_boundary.app_boundary_i.read_slot_q[4]" r-a-rslot4 :cond c-a-rslot4 :output p-a-rslot4)
             ("u_boundary.app_boundary_i.read_slot_q[5]" r-a-rslot5 :cond c-a-rslot5 :output p-a-rslot5)
             ("u_boundary.app_boundary_i.read_slot_q[6]" r-a-rslot6 :cond c-a-rslot6 :output p-a-rslot6)
             ("u_boundary.app_boundary_i.read_slot_q[7]" r-a-rslot7 :cond c-a-rslot7 :output p-a-rslot7))
            :outputs (
             ("model_lock_core_meta_q" z-p-lock-meta)
             ("model_lock_core_sync_q" z-p-lock-sync)
             ("core_fault_to_boundary_q" z-p-cfb)
             ("app_runtime_release_q" z-p-apprel)
             ("u_machine.machine_release_q" z-m-rel)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" z-k-state-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_issued_q" z-k-pending-issued-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_returned_q" z-k-pending-returned-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_read_pending_q" z-k-pending-read-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.committed_prefix_q" z-k-committed-prefix-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_layer_q" z-k-pending-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_position_q" z-k-pending-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_key_exponents_q" z-k-pending-key-exponents-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_value_exponents_q" z-k-pending-value-exponents-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.expected_coordinate_q" z-k-expected-coordinate-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.pending_persisted_q" z-k-pending-persisted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_head_q" z-k-write-head-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_word_q" z-k-write-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.write_aborted_q" z-k-write-aborted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_kind_q" z-k-response-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_head_q" z-k-response-head-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_layer_q" z-k-response-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_position_q" z-k-response-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_fault_q" z-k-response-fault-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.response_from_pending_q" z-k-response-from-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_word_q" z-k-read-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_return_word_q" z-k-read-return-word-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_outstanding_q" z-k-read-outstanding-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_issue_done_q" z-k-read-issue-done-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_aborted_q" z-k-read-aborted-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_physical_kind_q" z-k-read-physical-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_epoch_q" z-k-read-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.read_received_mask_q" z-k-read-received-mask-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_valid_q" z-k-cache-valid-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_kind_q" z-k-cache-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_layer_q" z-k-cache-layer-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_position_q" z-k-cache-position-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_tag_epoch_q" z-k-cache-tag-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_epoch_q" z-k-cache-epoch-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_clear_seen_q" z-k-cache-clear-seen-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_issued_q" z-k-cache-issued-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_returned_q" z-k-cache-returned-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_read_pending_q" z-k-cache-read-pending-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.cache_copy_kind_q" z-k-cache-copy-kind-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.lock_seen_q" z-k-lock-seen-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.fault_q" z-k-fault-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_consumed_q" z-k-stage-begin-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_consumed_q" z-k-stage-payload-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.commit_consumed_q" z-k-commit-consumed-q)
             ("u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_consumed_q" z-k-attention-req-consumed-q)
             ("u_boundary.core_release_q" z-b-crel)
             ("u_boundary.app_release_q" z-b-arel)
             ("u_boundary.model_lock_core_meta_q" z-b-lock-meta)
             ("u_boundary.model_lock_core_sync_q" z-b-lock-sync)
             ("u_boundary.app_fault_core_meta_q" z-b-afc-meta)
             ("u_boundary.app_fault_core_sync_q" z-b-afc-sync)
             ("u_boundary.core_fault_app_meta_q" z-b-cfa-meta)
             ("u_boundary.core_fault_app_sync_q" z-b-cfa-sync)
             ("u_boundary.core_fault_q" z-b-fault)
             ("u_boundary.core_lock_seen_q" z-b-lock-seen)
             ("u_boundary.core_clear_seen_q" z-b-clr-seen)
             ("u_boundary.core_clear_pending_q" z-b-clr-pend)
             ("u_boundary.core_clear_drained_o" z-b-clr-drained)
             ("u_boundary.core_epoch_q" z-b-epoch)
             ("u_boundary.core_outstanding_q" z-b-out)
             ("u_boundary.model_rsp_stalled_q" z-b-mstall)
             ("u_boundary.kv_write_cpl_stalled_q" z-b-wstall)
             ("u_boundary.kv_write_cpl_stalled_fault_q" z-b-wstallf)
             ("u_boundary.kv_read_rsp_stalled_q" z-b-rstall)
             ("u_boundary.request_fifo_i.write_binary_q" z-q-wb)
             ("u_boundary.request_fifo_i.write_gray_q" z-q-wg)
             ("u_boundary.request_fifo_i.write_full_q" z-q-full)
             ("u_boundary.request_fifo_i.read_binary_q" z-q-rb)
             ("u_boundary.request_fifo_i.read_gray_q" z-q-rg)
             ("u_boundary.request_fifo_i.read_gray_sync1_q" z-q-rs1)
             ("u_boundary.request_fifo_i.read_gray_sync2_q" z-q-rs2)
             ("u_boundary.request_fifo_i.write_gray_sync1_q" z-q-ws1)
             ("u_boundary.request_fifo_i.write_gray_sync2_q" z-q-ws2)
             ("u_boundary.request_fifo_i.m_valid_q" z-q-mv)
             ("u_boundary.request_fifo_i.source_fault_q" z-q-sf)
             ("u_boundary.request_fifo_i.source_payload_fault_q" z-q-spf)
             ("u_boundary.request_fifo_i.destination_fault_q" z-q-df)
             ("u_boundary.request_fifo_i.source_stalled_q" z-q-st)
             ("u_boundary.request_fifo_i.m_data_q[317:315]" z-q-md)
             ("u_boundary.response_fifo_i.write_binary_q" z-s-wb)
             ("u_boundary.response_fifo_i.write_gray_q" z-s-wg)
             ("u_boundary.response_fifo_i.write_full_q" z-s-full)
             ("u_boundary.response_fifo_i.read_binary_q" z-s-rb)
             ("u_boundary.response_fifo_i.read_gray_q" z-s-rg)
             ("u_boundary.response_fifo_i.read_gray_sync1_q" z-s-rs1)
             ("u_boundary.response_fifo_i.read_gray_sync2_q" z-s-rs2)
             ("u_boundary.response_fifo_i.write_gray_sync1_q" z-s-ws1)
             ("u_boundary.response_fifo_i.write_gray_sync2_q" z-s-ws2)
             ("u_boundary.response_fifo_i.m_valid_q" z-s-mv)
             ("u_boundary.response_fifo_i.source_fault_q" z-s-sf)
             ("u_boundary.response_fifo_i.source_payload_fault_q" z-s-spf)
             ("u_boundary.response_fifo_i.destination_fault_q" z-s-df)
             ("u_boundary.response_fifo_i.source_stalled_q" z-s-st)
             ("u_boundary.response_fifo_i.m_data_q[259:256]" z-s-md)
             ("u_boundary.request_fifo_i.m_data_q[278:275]" z-q-mdw)
             ("u_boundary.app_boundary_i.fault_q" z-a-fault)
             ("u_boundary.app_boundary_i.lock_seen_q" z-a-lock-seen)
             ("u_boundary.app_boundary_i.offer_q" z-a-offer)
             ("u_boundary.app_boundary_i.offer_write_q" z-a-offer-write)
             ("u_boundary.app_boundary_i.offer_poison_q" z-a-poison)
             ("u_boundary.app_boundary_i.offer_slot_q" z-a-offer-slot)
             ("u_boundary.app_boundary_i.reserved_q" z-a-reserved)
             ("u_boundary.app_boundary_i.unissued_q" z-a-unissued)
             ("u_boundary.app_boundary_i.read_count_q" z-a-readcount)
             ("u_boundary.app_boundary_i.head_q" z-a-head)
             ("u_boundary.app_boundary_i.tail_q" z-a-tail)
             ("u_boundary.app_boundary_i.issue_q" z-a-issue)
             ("u_boundary.app_boundary_i.read_head_q" z-a-rhead)
             ("u_boundary.app_boundary_i.read_tail_q" z-a-rtail)
             ("u_boundary.app_boundary_i.slot_kind_q[0]" z-a-kind0)
             ("u_boundary.app_boundary_i.slot_kind_q[1]" z-a-kind1)
             ("u_boundary.app_boundary_i.slot_kind_q[2]" z-a-kind2)
             ("u_boundary.app_boundary_i.slot_kind_q[3]" z-a-kind3)
             ("u_boundary.app_boundary_i.slot_kind_q[4]" z-a-kind4)
             ("u_boundary.app_boundary_i.slot_kind_q[5]" z-a-kind5)
             ("u_boundary.app_boundary_i.slot_kind_q[6]" z-a-kind6)
             ("u_boundary.app_boundary_i.slot_kind_q[7]" z-a-kind7)
             ("u_boundary.app_boundary_i.slot_epoch_q[7]" z-a-epoch0)
             ("u_boundary.app_boundary_i.slot_epoch_q[6]" z-a-epoch1)
             ("u_boundary.app_boundary_i.slot_epoch_q[5]" z-a-epoch2)
             ("u_boundary.app_boundary_i.slot_epoch_q[4]" z-a-epoch3)
             ("u_boundary.app_boundary_i.slot_epoch_q[3]" z-a-epoch4)
             ("u_boundary.app_boundary_i.slot_epoch_q[2]" z-a-epoch5)
             ("u_boundary.app_boundary_i.slot_epoch_q[1]" z-a-epoch6)
             ("u_boundary.app_boundary_i.slot_epoch_q[0]" z-a-epoch7)
             ("u_boundary.app_boundary_i.slot_reject_q[7]" z-a-reject0)
             ("u_boundary.app_boundary_i.slot_reject_q[6]" z-a-reject1)
             ("u_boundary.app_boundary_i.slot_reject_q[5]" z-a-reject2)
             ("u_boundary.app_boundary_i.slot_reject_q[4]" z-a-reject3)
             ("u_boundary.app_boundary_i.slot_reject_q[3]" z-a-reject4)
             ("u_boundary.app_boundary_i.slot_reject_q[2]" z-a-reject5)
             ("u_boundary.app_boundary_i.slot_reject_q[1]" z-a-reject6)
             ("u_boundary.app_boundary_i.slot_reject_q[0]" z-a-reject7)
             ("u_boundary.app_boundary_i.slot_done_q[7]" z-a-done0)
             ("u_boundary.app_boundary_i.slot_done_q[6]" z-a-done1)
             ("u_boundary.app_boundary_i.slot_done_q[5]" z-a-done2)
             ("u_boundary.app_boundary_i.slot_done_q[4]" z-a-done3)
             ("u_boundary.app_boundary_i.slot_done_q[3]" z-a-done4)
             ("u_boundary.app_boundary_i.slot_done_q[2]" z-a-done5)
             ("u_boundary.app_boundary_i.slot_done_q[1]" z-a-done6)
             ("u_boundary.app_boundary_i.slot_done_q[0]" z-a-done7)
             ("u_boundary.app_boundary_i.slot_fault_q[7]" z-a-sfault0)
             ("u_boundary.app_boundary_i.slot_fault_q[6]" z-a-sfault1)
             ("u_boundary.app_boundary_i.slot_fault_q[5]" z-a-sfault2)
             ("u_boundary.app_boundary_i.slot_fault_q[4]" z-a-sfault3)
             ("u_boundary.app_boundary_i.slot_fault_q[3]" z-a-sfault4)
             ("u_boundary.app_boundary_i.slot_fault_q[2]" z-a-sfault5)
             ("u_boundary.app_boundary_i.slot_fault_q[1]" z-a-sfault6)
             ("u_boundary.app_boundary_i.slot_fault_q[0]" z-a-sfault7)
             ("u_boundary.app_boundary_i.slot_word_q[0]" z-a-word0)
             ("u_boundary.app_boundary_i.slot_word_q[1]" z-a-word1)
             ("u_boundary.app_boundary_i.slot_word_q[2]" z-a-word2)
             ("u_boundary.app_boundary_i.slot_word_q[3]" z-a-word3)
             ("u_boundary.app_boundary_i.slot_word_q[4]" z-a-word4)
             ("u_boundary.app_boundary_i.slot_word_q[5]" z-a-word5)
             ("u_boundary.app_boundary_i.slot_word_q[6]" z-a-word6)
             ("u_boundary.app_boundary_i.slot_word_q[7]" z-a-word7)))))

(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export join-reset-run-data)
  (make-event '(def-svtv-refinement join-reset-run join-reset-run-data
                 :svtv-spec join-reset-spec :inclusive-overridekeys t
                 :fsm probe-fsm :define-fsm t)))
(value-triple (acl2::cw "~%BCT-RESET-REFINEMENT done~%"))

(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm join-reset-svtv-thm
      :svtv join-reset-run
      :svtv-spec join-reset-spec
      :input-vars :all
      :output-vars (
                    z-p-lock-meta z-p-lock-sync z-p-cfb z-p-apprel z-m-rel
                    z-k-state-q z-k-pending-issued-q
                    z-k-pending-returned-q z-k-pending-read-pending-q
                    z-k-committed-prefix-q z-k-pending-layer-q
                    z-k-pending-position-q z-k-pending-key-exponents-q
                    z-k-pending-value-exponents-q
                    z-k-expected-coordinate-q z-k-pending-persisted-q
                    z-k-write-head-q z-k-write-word-q z-k-write-aborted-q
                    z-k-response-kind-q z-k-response-head-q
                    z-k-response-layer-q z-k-response-position-q
                    z-k-response-fault-q z-k-response-from-pending-q
                    z-k-read-word-q z-k-read-return-word-q
                    z-k-read-outstanding-q z-k-read-issue-done-q
                    z-k-read-aborted-q z-k-read-physical-kind-q
                    z-k-read-epoch-q z-k-read-received-mask-q
                    z-k-cache-valid-q z-k-cache-kind-q z-k-cache-layer-q
                    z-k-cache-position-q z-k-cache-tag-epoch-q
                    z-k-cache-epoch-q z-k-cache-clear-seen-q
                    z-k-cache-issued-q z-k-cache-returned-q
                    z-k-cache-read-pending-q z-k-cache-copy-kind-q
                    z-k-lock-seen-q z-k-fault-q z-k-stage-begin-consumed-q
                    z-k-stage-payload-consumed-q z-k-commit-consumed-q
                    z-k-attention-req-consumed-q z-b-crel z-b-arel
                    z-b-lock-meta z-b-lock-sync z-b-afc-meta z-b-afc-sync
                    z-b-cfa-meta z-b-cfa-sync z-b-fault z-b-lock-seen
                    z-b-clr-seen z-b-clr-pend z-b-clr-drained z-b-epoch
                    z-b-out z-b-mstall z-b-wstall z-b-wstallf z-b-rstall
                    z-q-wb z-q-wg z-q-full z-q-rb z-q-rg z-q-rs1 z-q-rs2
                    z-q-ws1 z-q-ws2 z-q-mv z-q-sf z-q-spf z-q-df z-q-st
                    z-q-md z-s-wb z-s-wg z-s-full z-s-rb z-s-rg z-s-rs1
                    z-s-rs2 z-s-ws1 z-s-ws2 z-s-mv z-s-sf z-s-spf z-s-df
                    z-s-st z-s-md z-q-mdw z-a-fault z-a-lock-seen
                    z-a-offer z-a-offer-write z-a-poison z-a-offer-slot
                    z-a-reserved z-a-unissued z-a-readcount z-a-head
                    z-a-tail z-a-issue z-a-rhead z-a-rtail z-a-kind0
                    z-a-kind1 z-a-kind2 z-a-kind3 z-a-kind4 z-a-kind5
                    z-a-kind6 z-a-kind7 z-a-epoch0 z-a-epoch1 z-a-epoch2
                    z-a-epoch3 z-a-epoch4 z-a-epoch5 z-a-epoch6 z-a-epoch7
                    z-a-reject0 z-a-reject1 z-a-reject2 z-a-reject3
                    z-a-reject4 z-a-reject5 z-a-reject6 z-a-reject7
                    z-a-done0 z-a-done1 z-a-done2 z-a-done3 z-a-done4
                    z-a-done5 z-a-done6 z-a-done7 z-a-sfault0 z-a-sfault1
                    z-a-sfault2 z-a-sfault3 z-a-sfault4 z-a-sfault5
                    z-a-sfault6 z-a-sfault7 z-a-word0 z-a-word1 z-a-word2
                    z-a-word3 z-a-word4 z-a-word5 z-a-word6 z-a-word7)
      :unsigned-byte-hyps t
      :override-vars (
                      r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4
                      r-q-mem5 r-q-mem6 r-q-mem7 r-s-mem0 r-s-mem1
                      r-s-mem2 r-s-mem3 r-s-mem4 r-s-mem5 r-s-mem6
                      r-s-mem7 r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3
                      r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 r-a-rslot0
                      r-a-rslot1 r-a-rslot2 r-a-rslot3 r-a-rslot4
                      r-a-rslot5 r-a-rslot6 r-a-rslot7)
      :spec-override-vars ()
      :hyp t
      :concl (and (joint-reset-p
                   z-p-lock-meta z-p-lock-sync z-p-cfb z-p-apprel z-m-rel
                   z-k-state-q z-k-pending-issued-q z-k-pending-returned-q
                   z-k-pending-read-pending-q z-k-committed-prefix-q
                   z-k-pending-layer-q z-k-pending-position-q
                   z-k-pending-key-exponents-q
                   z-k-pending-value-exponents-q z-k-expected-coordinate-q
                   z-k-pending-persisted-q z-k-write-head-q
                   z-k-write-word-q z-k-write-aborted-q
                   z-k-response-kind-q z-k-response-head-q
                   z-k-response-layer-q z-k-response-position-q
                   z-k-response-fault-q z-k-response-from-pending-q
                   z-k-read-word-q z-k-read-return-word-q
                   z-k-read-outstanding-q z-k-read-issue-done-q
                   z-k-read-aborted-q z-k-read-physical-kind-q
                   z-k-read-epoch-q z-k-read-received-mask-q
                   z-k-cache-valid-q z-k-cache-kind-q z-k-cache-layer-q
                   z-k-cache-position-q z-k-cache-tag-epoch-q
                   z-k-cache-epoch-q z-k-cache-clear-seen-q
                   z-k-cache-issued-q z-k-cache-returned-q
                   z-k-cache-read-pending-q z-k-cache-copy-kind-q
                   z-k-lock-seen-q z-k-fault-q z-k-stage-begin-consumed-q
                   z-k-stage-payload-consumed-q z-k-commit-consumed-q
                   z-k-attention-req-consumed-q z-b-crel z-b-arel
                   z-b-lock-meta z-b-lock-sync z-b-afc-meta z-b-afc-sync
                   z-b-cfa-meta z-b-cfa-sync z-b-fault z-b-lock-seen
                   z-b-clr-seen z-b-clr-pend z-b-clr-drained z-b-epoch
                   z-b-out z-b-mstall z-b-wstall z-b-wstallf z-b-rstall
                   z-q-wb z-q-wg z-q-full z-q-rb z-q-rg z-q-rs1 z-q-rs2
                   z-q-ws1 z-q-ws2 z-q-mv z-q-sf z-q-spf z-q-df z-q-st
                   z-q-md z-s-wb z-s-wg z-s-full z-s-rb z-s-rg z-s-rs1
                   z-s-rs2 z-s-ws1 z-s-ws2 z-s-mv z-s-sf z-s-spf z-s-df
                   z-s-st z-s-md z-q-mdw z-a-fault z-a-lock-seen z-a-offer
                   z-a-offer-write z-a-poison z-a-offer-slot z-a-reserved
                   z-a-unissued z-a-readcount z-a-head z-a-tail z-a-issue
                   z-a-rhead z-a-rtail z-a-kind0 z-a-kind1 z-a-kind2
                   z-a-kind3 z-a-kind4 z-a-kind5 z-a-kind6 z-a-kind7
                   z-a-epoch0 z-a-epoch1 z-a-epoch2 z-a-epoch3 z-a-epoch4
                   z-a-epoch5 z-a-epoch6 z-a-epoch7 z-a-reject0
                   z-a-reject1 z-a-reject2 z-a-reject3 z-a-reject4
                   z-a-reject5 z-a-reject6 z-a-reject7 z-a-done0 z-a-done1
                   z-a-done2 z-a-done3 z-a-done4 z-a-done5 z-a-done6
                   z-a-done7 z-a-sfault0 z-a-sfault1 z-a-sfault2
                   z-a-sfault3 z-a-sfault4 z-a-sfault5 z-a-sfault6
                   z-a-sfault7 z-a-word0 z-a-word1 z-a-word2 z-a-word3
                   z-a-word4 z-a-word5 z-a-word6 z-a-word7)
                  (joint-inv-p
                   z-p-lock-meta z-p-lock-sync z-p-cfb z-p-apprel z-m-rel
                   z-k-state-q z-k-pending-issued-q z-k-pending-returned-q
                   z-k-pending-read-pending-q z-k-committed-prefix-q
                   z-k-pending-layer-q z-k-pending-position-q
                   z-k-pending-key-exponents-q
                   z-k-pending-value-exponents-q z-k-expected-coordinate-q
                   z-k-pending-persisted-q z-k-write-head-q
                   z-k-write-word-q z-k-write-aborted-q
                   z-k-response-kind-q z-k-response-head-q
                   z-k-response-layer-q z-k-response-position-q
                   z-k-response-fault-q z-k-response-from-pending-q
                   z-k-read-word-q z-k-read-return-word-q
                   z-k-read-outstanding-q z-k-read-issue-done-q
                   z-k-read-aborted-q z-k-read-physical-kind-q
                   z-k-read-epoch-q z-k-read-received-mask-q
                   z-k-cache-valid-q z-k-cache-kind-q z-k-cache-layer-q
                   z-k-cache-position-q z-k-cache-tag-epoch-q
                   z-k-cache-epoch-q z-k-cache-clear-seen-q
                   z-k-cache-issued-q z-k-cache-returned-q
                   z-k-cache-read-pending-q z-k-cache-copy-kind-q
                   z-k-lock-seen-q z-k-fault-q z-k-stage-begin-consumed-q
                   z-k-stage-payload-consumed-q z-k-commit-consumed-q
                   z-k-attention-req-consumed-q z-b-crel z-b-arel
                   z-b-lock-meta z-b-lock-sync z-b-afc-meta z-b-afc-sync
                   z-b-cfa-meta z-b-cfa-sync z-b-fault z-b-lock-seen
                   z-b-clr-seen z-b-clr-pend z-b-clr-drained z-b-epoch
                   z-b-out z-b-mstall z-b-wstall z-b-wstallf z-b-rstall
                   z-q-wb z-q-wg z-q-full z-q-rb z-q-rg z-q-rs1 z-q-rs2
                   z-q-ws1 z-q-ws2 z-q-mv z-q-sf z-q-spf z-q-df z-q-st
                   z-q-md r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4
                   r-q-mem5 r-q-mem6 r-q-mem7 z-s-wb z-s-wg z-s-full
                   z-s-rb z-s-rg z-s-rs1 z-s-rs2 z-s-ws1 z-s-ws2 z-s-mv
                   z-s-sf z-s-spf z-s-df z-s-st z-s-md r-s-mem0 r-s-mem1
                   r-s-mem2 r-s-mem3 r-s-mem4 r-s-mem5 r-s-mem6 r-s-mem7
                   z-q-mdw r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3
                   r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 z-a-fault
                   z-a-lock-seen z-a-offer z-a-offer-write z-a-poison
                   z-a-offer-slot z-a-reserved z-a-unissued z-a-readcount
                   z-a-head z-a-tail z-a-issue z-a-rhead z-a-rtail
                   z-a-kind0 z-a-kind1 z-a-kind2 z-a-kind3 z-a-kind4
                   z-a-kind5 z-a-kind6 z-a-kind7 z-a-epoch0 z-a-epoch1
                   z-a-epoch2 z-a-epoch3 z-a-epoch4 z-a-epoch5 z-a-epoch6
                   z-a-epoch7 z-a-reject0 z-a-reject1 z-a-reject2
                   z-a-reject3 z-a-reject4 z-a-reject5 z-a-reject6
                   z-a-reject7 z-a-done0 z-a-done1 z-a-done2 z-a-done3
                   z-a-done4 z-a-done5 z-a-done6 z-a-done7 z-a-sfault0
                   z-a-sfault1 z-a-sfault2 z-a-sfault3 z-a-sfault4
                   z-a-sfault5 z-a-sfault6 z-a-sfault7 z-a-word0 z-a-word1
                   z-a-word2 z-a-word3 z-a-word4 z-a-word5 z-a-word6
                   z-a-word7 r-a-rslot0 r-a-rslot1 r-a-rslot2 r-a-rslot3
                   r-a-rslot4 r-a-rslot5 r-a-rslot6 r-a-rslot7)
                  (joint-2valued-p
                   z-p-lock-meta z-p-lock-sync z-p-cfb z-p-apprel z-m-rel
                   z-k-state-q z-k-pending-issued-q z-k-pending-returned-q
                   z-k-pending-read-pending-q z-k-committed-prefix-q
                   z-k-pending-layer-q z-k-pending-position-q
                   z-k-pending-key-exponents-q
                   z-k-pending-value-exponents-q z-k-expected-coordinate-q
                   z-k-pending-persisted-q z-k-write-head-q
                   z-k-write-word-q z-k-write-aborted-q
                   z-k-response-kind-q z-k-response-head-q
                   z-k-response-layer-q z-k-response-position-q
                   z-k-response-fault-q z-k-response-from-pending-q
                   z-k-read-word-q z-k-read-return-word-q
                   z-k-read-outstanding-q z-k-read-issue-done-q
                   z-k-read-aborted-q z-k-read-physical-kind-q
                   z-k-read-epoch-q z-k-read-received-mask-q
                   z-k-cache-valid-q z-k-cache-kind-q z-k-cache-layer-q
                   z-k-cache-position-q z-k-cache-tag-epoch-q
                   z-k-cache-epoch-q z-k-cache-clear-seen-q
                   z-k-cache-issued-q z-k-cache-returned-q
                   z-k-cache-read-pending-q z-k-cache-copy-kind-q
                   z-k-lock-seen-q z-k-fault-q z-k-stage-begin-consumed-q
                   z-k-stage-payload-consumed-q z-k-commit-consumed-q
                   z-k-attention-req-consumed-q z-b-crel z-b-arel
                   z-b-lock-meta z-b-lock-sync z-b-afc-meta z-b-afc-sync
                   z-b-cfa-meta z-b-cfa-sync z-b-fault z-b-lock-seen
                   z-b-clr-seen z-b-clr-pend z-b-clr-drained z-b-epoch
                   z-b-out z-b-mstall z-b-wstall z-b-wstallf z-b-rstall
                   z-q-wb z-q-wg z-q-full z-q-rb z-q-rg z-q-rs1 z-q-rs2
                   z-q-ws1 z-q-ws2 z-q-mv z-q-sf z-q-spf z-q-df z-q-st
                   z-q-md r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4
                   r-q-mem5 r-q-mem6 r-q-mem7 z-s-wb z-s-wg z-s-full
                   z-s-rb z-s-rg z-s-rs1 z-s-rs2 z-s-ws1 z-s-ws2 z-s-mv
                   z-s-sf z-s-spf z-s-df z-s-st z-s-md r-s-mem0 r-s-mem1
                   r-s-mem2 r-s-mem3 r-s-mem4 r-s-mem5 r-s-mem6 r-s-mem7
                   z-q-mdw r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3
                   r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 z-a-fault
                   z-a-lock-seen z-a-offer z-a-offer-write z-a-poison
                   z-a-offer-slot z-a-reserved z-a-unissued z-a-readcount
                   z-a-head z-a-tail z-a-issue z-a-rhead z-a-rtail
                   z-a-kind0 z-a-kind1 z-a-kind2 z-a-kind3 z-a-kind4
                   z-a-kind5 z-a-kind6 z-a-kind7 z-a-epoch0 z-a-epoch1
                   z-a-epoch2 z-a-epoch3 z-a-epoch4 z-a-epoch5 z-a-epoch6
                   z-a-epoch7 z-a-reject0 z-a-reject1 z-a-reject2
                   z-a-reject3 z-a-reject4 z-a-reject5 z-a-reject6
                   z-a-reject7 z-a-done0 z-a-done1 z-a-done2 z-a-done3
                   z-a-done4 z-a-done5 z-a-done6 z-a-done7 z-a-sfault0
                   z-a-sfault1 z-a-sfault2 z-a-sfault3 z-a-sfault4
                   z-a-sfault5 z-a-sfault6 z-a-sfault7 z-a-word0 z-a-word1
                   z-a-word2 z-a-word3 z-a-word4 z-a-word5 z-a-word6
                   z-a-word7 r-a-rslot0 r-a-rslot1 r-a-rslot2 r-a-rslot3
                   r-a-rslot4 r-a-rslot5 r-a-rslot6 r-a-rslot7))))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event '(def-svtv-to-fsm-thm join-reset-fsm-thm
                 :svtv-spec-thmname join-reset-svtv-thm
                 :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%BCT-JRESET proved~%")))

; ===========================================================================
; Step.  Stage `curr`: the invariant's signals and the environment's signals
; are named; reset_n_i may be 0 or 1, the lock input is 1.  Stage `next`:
; reset_n_i is 1 and the invariant's signals are read one cycle later.
; ===========================================================================
(defsvtv$ join-step-run
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
             ("u_boundary.app_boundary_i.request_descriptor_legal" h-legal :cond c-h-legal :output p-h-legal))
            :outputs (("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_cpl_valid_i" o-cplv)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_write_cpl_fault_i" o-cplf)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.clear_i" o-clear)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_read_rsp_valid_i" o-rspv)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.kv_read_rsp_fault_i" o-rspf)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.protocol_fault_now" o-pfn)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.typed_padding_fault" o-tpf)
                      ("u_boundary.app_boundary_i.endpoint_padding_fault_now" o-epf)
                      ("u_machine.u_six_layers.u_datapath.u_kv_cache.terminal_fault_event" o-tfe)
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
             ("u_boundary.app_boundary_i.read_slot_q[7]" n-a-rslot7)))))

(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export join-step-run-data)
  (make-event '(def-svtv-refinement join-step-run join-step-run-data
                 :svtv-spec join-step-spec :inclusive-overridekeys t
                 :fsm probe-fsm)))
(value-triple (acl2::cw "~%BCT-STEP-REFINEMENT done~%"))

(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm join-step-svtv-thm
      :svtv join-step-run
      :svtv-spec join-step-spec
      :input-vars :all
      :output-vars (o-cplv o-cplf o-rspv o-rspf o-clear o-pfn o-tpf o-epf
                    o-tfe 
                    n-p-lock-meta n-p-lock-sync n-p-cfb n-p-apprel n-m-rel
                    n-k-state-q n-k-pending-issued-q
                    n-k-pending-returned-q n-k-pending-read-pending-q
                    n-k-committed-prefix-q n-k-pending-layer-q
                    n-k-pending-position-q n-k-pending-key-exponents-q
                    n-k-pending-value-exponents-q
                    n-k-expected-coordinate-q n-k-pending-persisted-q
                    n-k-write-head-q n-k-write-word-q n-k-write-aborted-q
                    n-k-response-kind-q n-k-response-head-q
                    n-k-response-layer-q n-k-response-position-q
                    n-k-response-fault-q n-k-response-from-pending-q
                    n-k-read-word-q n-k-read-return-word-q
                    n-k-read-outstanding-q n-k-read-issue-done-q
                    n-k-read-aborted-q n-k-read-physical-kind-q
                    n-k-read-epoch-q n-k-read-received-mask-q
                    n-k-cache-valid-q n-k-cache-kind-q n-k-cache-layer-q
                    n-k-cache-position-q n-k-cache-tag-epoch-q
                    n-k-cache-epoch-q n-k-cache-clear-seen-q
                    n-k-cache-issued-q n-k-cache-returned-q
                    n-k-cache-read-pending-q n-k-cache-copy-kind-q
                    n-k-lock-seen-q n-k-fault-q n-k-stage-begin-consumed-q
                    n-k-stage-payload-consumed-q n-k-commit-consumed-q
                    n-k-attention-req-consumed-q n-b-crel n-b-arel
                    n-b-lock-meta n-b-lock-sync n-b-afc-meta n-b-afc-sync
                    n-b-cfa-meta n-b-cfa-sync n-b-fault n-b-lock-seen
                    n-b-clr-seen n-b-clr-pend n-b-clr-drained n-b-epoch
                    n-b-out n-b-mstall n-b-wstall n-b-wstallf n-b-rstall
                    n-q-wb n-q-wg n-q-full n-q-rb n-q-rg n-q-rs1 n-q-rs2
                    n-q-ws1 n-q-ws2 n-q-mv n-q-sf n-q-spf n-q-df n-q-st
                    n-q-md n-q-mem0 n-q-mem1 n-q-mem2 n-q-mem3 n-q-mem4
                    n-q-mem5 n-q-mem6 n-q-mem7 n-s-wb n-s-wg n-s-full
                    n-s-rb n-s-rg n-s-rs1 n-s-rs2 n-s-ws1 n-s-ws2 n-s-mv
                    n-s-sf n-s-spf n-s-df n-s-st n-s-md n-s-mem0 n-s-mem1
                    n-s-mem2 n-s-mem3 n-s-mem4 n-s-mem5 n-s-mem6 n-s-mem7
                    n-q-mdw n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3
                    n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-a-fault
                    n-a-lock-seen n-a-offer n-a-offer-write n-a-poison
                    n-a-offer-slot n-a-reserved n-a-unissued n-a-readcount
                    n-a-head n-a-tail n-a-issue n-a-rhead n-a-rtail
                    n-a-kind0 n-a-kind1 n-a-kind2 n-a-kind3 n-a-kind4
                    n-a-kind5 n-a-kind6 n-a-kind7 n-a-epoch0 n-a-epoch1
                    n-a-epoch2 n-a-epoch3 n-a-epoch4 n-a-epoch5 n-a-epoch6
                    n-a-epoch7 n-a-reject0 n-a-reject1 n-a-reject2
                    n-a-reject3 n-a-reject4 n-a-reject5 n-a-reject6
                    n-a-reject7 n-a-done0 n-a-done1 n-a-done2 n-a-done3
                    n-a-done4 n-a-done5 n-a-done6 n-a-done7 n-a-sfault0
                    n-a-sfault1 n-a-sfault2 n-a-sfault3 n-a-sfault4
                    n-a-sfault5 n-a-sfault6 n-a-sfault7 n-a-word0
                    n-a-word1 n-a-word2 n-a-word3 n-a-word4 n-a-word5
                    n-a-word6 n-a-word7 n-a-rslot0 n-a-rslot1 n-a-rslot2
                    n-a-rslot3 n-a-rslot4 n-a-rslot5 n-a-rslot6 n-a-rslot7)
      :unsigned-byte-hyps t
      :override-vars (
                      r-p-lock-meta r-p-lock-sync r-p-cfb r-p-apprel
                      r-m-rel r-k-state-q r-k-pending-issued-q
                      r-k-pending-returned-q r-k-pending-read-pending-q
                      r-k-committed-prefix-q r-k-pending-layer-q
                      r-k-pending-position-q r-k-pending-key-exponents-q
                      r-k-pending-value-exponents-q
                      r-k-expected-coordinate-q r-k-pending-persisted-q
                      r-k-write-head-q r-k-write-word-q
                      r-k-write-aborted-q r-k-response-kind-q
                      r-k-response-head-q r-k-response-layer-q
                      r-k-response-position-q r-k-response-fault-q
                      r-k-response-from-pending-q r-k-read-word-q
                      r-k-read-return-word-q r-k-read-outstanding-q
                      r-k-read-issue-done-q r-k-read-aborted-q
                      r-k-read-physical-kind-q r-k-read-epoch-q
                      r-k-read-received-mask-q r-k-cache-valid-q
                      r-k-cache-kind-q r-k-cache-layer-q
                      r-k-cache-position-q r-k-cache-tag-epoch-q
                      r-k-cache-epoch-q r-k-cache-clear-seen-q
                      r-k-cache-issued-q r-k-cache-returned-q
                      r-k-cache-read-pending-q r-k-cache-copy-kind-q
                      r-k-lock-seen-q r-k-fault-q
                      r-k-stage-begin-consumed-q
                      r-k-stage-payload-consumed-q r-k-commit-consumed-q
                      r-k-attention-req-consumed-q r-b-crel r-b-arel
                      r-b-lock-meta r-b-lock-sync r-b-afc-meta
                      r-b-afc-sync r-b-cfa-meta r-b-cfa-sync r-b-fault
                      r-b-lock-seen r-b-clr-seen r-b-clr-pend
                      r-b-clr-drained r-b-epoch r-b-out r-b-mstall
                      r-b-wstall r-b-wstallf r-b-rstall r-q-wb r-q-wg
                      r-q-full r-q-rb r-q-rg r-q-rs1 r-q-rs2 r-q-ws1
                      r-q-ws2 r-q-mv r-q-sf r-q-spf r-q-df r-q-st r-q-md
                      r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4
                      r-q-mem5 r-q-mem6 r-q-mem7 r-s-wb r-s-wg r-s-full
                      r-s-rb r-s-rg r-s-rs1 r-s-rs2 r-s-ws1 r-s-ws2 r-s-mv
                      r-s-sf r-s-spf r-s-df r-s-st r-s-md r-s-mem0
                      r-s-mem1 r-s-mem2 r-s-mem3 r-s-mem4 r-s-mem5
                      r-s-mem6 r-s-mem7 r-q-mdw r-q-memw0 r-q-memw1
                      r-q-memw2 r-q-memw3 r-q-memw4 r-q-memw5 r-q-memw6
                      r-q-memw7 r-a-fault r-a-lock-seen r-a-offer
                      r-a-offer-write r-a-poison r-a-offer-slot
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
                      r-a-word6 r-a-word7 r-a-rslot0 r-a-rslot1 r-a-rslot2
                      r-a-rslot3 r-a-rslot4 r-a-rslot5 r-a-rslot6
                      r-a-rslot7
                      h-arbfail h-shellterm h-shellfail h-layerfail h-auth
                      h-mcdc h-kupf h-layer h-position h-kexp h-vexp
                      h-sbegin h-spayload h-index h-key h-value h-commit
                      h-attn h-attn-kind h-attn-pos h-attn-head
                      h-attn-ready h-epready h-eprspv h-eprsperr
                      h-eprspdata h-rspdata h-appup h-legal)
      :spec-override-vars ()
      :hyp (and (joint-inv-p
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
      :concl (implies
              (and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))
              (and (joint-inv-p
                   n-p-lock-meta n-p-lock-sync n-p-cfb n-p-apprel n-m-rel
                   n-k-state-q n-k-pending-issued-q n-k-pending-returned-q
                   n-k-pending-read-pending-q n-k-committed-prefix-q
                   n-k-pending-layer-q n-k-pending-position-q
                   n-k-pending-key-exponents-q
                   n-k-pending-value-exponents-q n-k-expected-coordinate-q
                   n-k-pending-persisted-q n-k-write-head-q
                   n-k-write-word-q n-k-write-aborted-q
                   n-k-response-kind-q n-k-response-head-q
                   n-k-response-layer-q n-k-response-position-q
                   n-k-response-fault-q n-k-response-from-pending-q
                   n-k-read-word-q n-k-read-return-word-q
                   n-k-read-outstanding-q n-k-read-issue-done-q
                   n-k-read-aborted-q n-k-read-physical-kind-q
                   n-k-read-epoch-q n-k-read-received-mask-q
                   n-k-cache-valid-q n-k-cache-kind-q n-k-cache-layer-q
                   n-k-cache-position-q n-k-cache-tag-epoch-q
                   n-k-cache-epoch-q n-k-cache-clear-seen-q
                   n-k-cache-issued-q n-k-cache-returned-q
                   n-k-cache-read-pending-q n-k-cache-copy-kind-q
                   n-k-lock-seen-q n-k-fault-q n-k-stage-begin-consumed-q
                   n-k-stage-payload-consumed-q n-k-commit-consumed-q
                   n-k-attention-req-consumed-q n-b-crel n-b-arel
                   n-b-lock-meta n-b-lock-sync n-b-afc-meta n-b-afc-sync
                   n-b-cfa-meta n-b-cfa-sync n-b-fault n-b-lock-seen
                   n-b-clr-seen n-b-clr-pend n-b-clr-drained n-b-epoch
                   n-b-out n-b-mstall n-b-wstall n-b-wstallf n-b-rstall
                   n-q-wb n-q-wg n-q-full n-q-rb n-q-rg n-q-rs1 n-q-rs2
                   n-q-ws1 n-q-ws2 n-q-mv n-q-sf n-q-spf n-q-df n-q-st
                   n-q-md n-q-mem0 n-q-mem1 n-q-mem2 n-q-mem3 n-q-mem4
                   n-q-mem5 n-q-mem6 n-q-mem7 n-s-wb n-s-wg n-s-full
                   n-s-rb n-s-rg n-s-rs1 n-s-rs2 n-s-ws1 n-s-ws2 n-s-mv
                   n-s-sf n-s-spf n-s-df n-s-st n-s-md n-s-mem0 n-s-mem1
                   n-s-mem2 n-s-mem3 n-s-mem4 n-s-mem5 n-s-mem6 n-s-mem7
                   n-q-mdw n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3
                   n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-a-fault
                   n-a-lock-seen n-a-offer n-a-offer-write n-a-poison
                   n-a-offer-slot n-a-reserved n-a-unissued n-a-readcount
                   n-a-head n-a-tail n-a-issue n-a-rhead n-a-rtail
                   n-a-kind0 n-a-kind1 n-a-kind2 n-a-kind3 n-a-kind4
                   n-a-kind5 n-a-kind6 n-a-kind7 n-a-epoch0 n-a-epoch1
                   n-a-epoch2 n-a-epoch3 n-a-epoch4 n-a-epoch5 n-a-epoch6
                   n-a-epoch7 n-a-reject0 n-a-reject1 n-a-reject2
                   n-a-reject3 n-a-reject4 n-a-reject5 n-a-reject6
                   n-a-reject7 n-a-done0 n-a-done1 n-a-done2 n-a-done3
                   n-a-done4 n-a-done5 n-a-done6 n-a-done7 n-a-sfault0
                   n-a-sfault1 n-a-sfault2 n-a-sfault3 n-a-sfault4
                   n-a-sfault5 n-a-sfault6 n-a-sfault7 n-a-word0 n-a-word1
                   n-a-word2 n-a-word3 n-a-word4 n-a-word5 n-a-word6
                   n-a-word7 n-a-rslot0 n-a-rslot1 n-a-rslot2 n-a-rslot3
                   n-a-rslot4 n-a-rslot5 n-a-rslot6 n-a-rslot7)
                   (joint-2valued-p
                   n-p-lock-meta n-p-lock-sync n-p-cfb n-p-apprel n-m-rel
                   n-k-state-q n-k-pending-issued-q n-k-pending-returned-q
                   n-k-pending-read-pending-q n-k-committed-prefix-q
                   n-k-pending-layer-q n-k-pending-position-q
                   n-k-pending-key-exponents-q
                   n-k-pending-value-exponents-q n-k-expected-coordinate-q
                   n-k-pending-persisted-q n-k-write-head-q
                   n-k-write-word-q n-k-write-aborted-q
                   n-k-response-kind-q n-k-response-head-q
                   n-k-response-layer-q n-k-response-position-q
                   n-k-response-fault-q n-k-response-from-pending-q
                   n-k-read-word-q n-k-read-return-word-q
                   n-k-read-outstanding-q n-k-read-issue-done-q
                   n-k-read-aborted-q n-k-read-physical-kind-q
                   n-k-read-epoch-q n-k-read-received-mask-q
                   n-k-cache-valid-q n-k-cache-kind-q n-k-cache-layer-q
                   n-k-cache-position-q n-k-cache-tag-epoch-q
                   n-k-cache-epoch-q n-k-cache-clear-seen-q
                   n-k-cache-issued-q n-k-cache-returned-q
                   n-k-cache-read-pending-q n-k-cache-copy-kind-q
                   n-k-lock-seen-q n-k-fault-q n-k-stage-begin-consumed-q
                   n-k-stage-payload-consumed-q n-k-commit-consumed-q
                   n-k-attention-req-consumed-q n-b-crel n-b-arel
                   n-b-lock-meta n-b-lock-sync n-b-afc-meta n-b-afc-sync
                   n-b-cfa-meta n-b-cfa-sync n-b-fault n-b-lock-seen
                   n-b-clr-seen n-b-clr-pend n-b-clr-drained n-b-epoch
                   n-b-out n-b-mstall n-b-wstall n-b-wstallf n-b-rstall
                   n-q-wb n-q-wg n-q-full n-q-rb n-q-rg n-q-rs1 n-q-rs2
                   n-q-ws1 n-q-ws2 n-q-mv n-q-sf n-q-spf n-q-df n-q-st
                   n-q-md n-q-mem0 n-q-mem1 n-q-mem2 n-q-mem3 n-q-mem4
                   n-q-mem5 n-q-mem6 n-q-mem7 n-s-wb n-s-wg n-s-full
                   n-s-rb n-s-rg n-s-rs1 n-s-rs2 n-s-ws1 n-s-ws2 n-s-mv
                   n-s-sf n-s-spf n-s-df n-s-st n-s-md n-s-mem0 n-s-mem1
                   n-s-mem2 n-s-mem3 n-s-mem4 n-s-mem5 n-s-mem6 n-s-mem7
                   n-q-mdw n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3
                   n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-a-fault
                   n-a-lock-seen n-a-offer n-a-offer-write n-a-poison
                   n-a-offer-slot n-a-reserved n-a-unissued n-a-readcount
                   n-a-head n-a-tail n-a-issue n-a-rhead n-a-rtail
                   n-a-kind0 n-a-kind1 n-a-kind2 n-a-kind3 n-a-kind4
                   n-a-kind5 n-a-kind6 n-a-kind7 n-a-epoch0 n-a-epoch1
                   n-a-epoch2 n-a-epoch3 n-a-epoch4 n-a-epoch5 n-a-epoch6
                   n-a-epoch7 n-a-reject0 n-a-reject1 n-a-reject2
                   n-a-reject3 n-a-reject4 n-a-reject5 n-a-reject6
                   n-a-reject7 n-a-done0 n-a-done1 n-a-done2 n-a-done3
                   n-a-done4 n-a-done5 n-a-done6 n-a-done7 n-a-sfault0
                   n-a-sfault1 n-a-sfault2 n-a-sfault3 n-a-sfault4
                   n-a-sfault5 n-a-sfault6 n-a-sfault7 n-a-word0 n-a-word1
                   n-a-word2 n-a-word3 n-a-word4 n-a-word5 n-a-word6
                   n-a-word7 n-a-rslot0 n-a-rslot1 n-a-rslot2 n-a-rslot3
                   n-a-rslot4 n-a-rslot5 n-a-rslot6 n-a-rslot7)
                   (kv-clause-p o-cplv o-cplf o-clear
                                r-k-write-aborted-q)
                   (kv-clause-p o-rspv o-rspf o-clear
                                r-k-read-aborted-q)
                   (equal o-tfe 0)))))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event '(def-svtv-to-fsm-thm join-step-fsm-thm
                 :svtv-spec-thmname join-step-svtv-thm
                 :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%BCT-JSTEP proved~%")))

; The library in use reads nonblocking assignments the standard way: a
; two-flop synchroniser is two flops deep.  With write_gray_q = 14 and the
; first stage at 15, the second stage takes 15 on the next edge (the
; released library gives 14).
(defconsts *kvj-sync-probe*
  (cdr (assoc 'n-s-ws2
              (svtv-run (join-step-run)
                        '((i-reset-n . 1) (i-clear . 0)
                          (r-p-apprel . 7) (c-p-apprel . -1)
                          (r-b-crel . 7) (c-b-crel . -1)
                          (r-b-arel . 7) (c-b-arel . -1)
                          (r-s-wg . 14) (c-s-wg . -1)
                          (r-s-ws1 . 15) (c-s-ws1 . -1)
                          (r-s-ws2 . 13) (c-s-ws2 . -1))
                        :include '(n-s-ws2)))))

(defthm kv-joined-synchroniser-is-two-flops-deep
  (equal *kvj-sync-probe* 15)
  :rule-classes nil)

; From the producer to the staging: the producer facts about one cycle.
;
; Written by make_step_book.py; do not edit.  Private.
;
; This book imports the certified first link (kv-staging-to-record) and
; proves, about one symbolic cycle of the pinned RTL, the facts the second
; link is built on.  They are about the datapath's stage controller, its key
; and value working memories (u_key_state, u_value_state) and the stage
; sequencer, in a step run of their own, producer-step-run: the registers it
; follows and the signals that reach them from outside are given values in
; the cycle (conditional overrides), so nothing here depends on how the
; arithmetic children compute.  Each fact is stated as a plain predicate
; (prd-p-...) and proved of the run by the SAT solver, whose proofs ACL2
; checks.
;   prod-sinv                 the state invariant of sequencer and controller
;   prd-p-accept ...          one predicate per fact; see each comment
; A second, small run (producer-hold-run) gives one fact about the K/V
; controller: while it is idle or staging it does not report its record
; complete.
(in-package "SV")
(include-book "kv-staging-to-record")

(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
(acl2::set-rewrite-stack-limit 20000)
; The SAT solver is the first link's (prod-satlink-config, attached in
; kv-staging-step.lisp): no answer of the solver is believed; with
; :lrat-check t the library reports "unsatisfiable" only after ACL2 has run
; its verified checker on the proof the solver wrote.
(value-triple (acl2::tshell-ensure))

; ===========================================================================
; The producer step run.
; ===========================================================================
(defsvtv$ producer-step-run
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
             ("model_lock_core_sync_q" r-p-lock-sync :cond c-p-lock-sync :output p-p-lock-sync)
             ("u_machine.machine_release_q" r-m-rel :cond c-m-rel :output p-m-rel)
             ("u_machine.u_six_layers.service_start_collision_q" r-l-coll :cond c-l-coll :output p-l-coll)
             ("u_machine.u_six_layers.u_sequence.state_q" r-s-state :cond c-s-state :output p-s-state)
             ("u_machine.u_six_layers.u_sequence.layer_q" r-s-layer :cond c-s-layer :output p-s-layer)
             ("u_machine.u_six_layers.u_sequence.stage_q" r-s-stage :cond c-s-stage :output p-s-stage)
             ("u_machine.u_six_layers.u_sequence.position_q" r-s-pos :cond c-s-pos :output p-s-pos)
             ("u_machine.u_six_layers.u_sequence.fault_q" r-s-fault :cond c-s-fault :output p-s-fault)
             ("u_machine.u_six_layers.u_sequence.lock_seen_q" r-s-lseen :cond c-s-lseen :output p-s-lseen)
             ("u_machine.u_six_layers.u_sequence.stream_index_q" r-s-sidx :cond c-s-sidx :output p-s-sidx)
             ("u_machine.u_six_layers.u_sequence.result_exponent_q" r-s-rexp :cond c-s-rexp :output p-s-rexp)
             ("u_machine.u_six_layers.u_datapath.engine_state_q" r-d-eng :cond c-d-eng :output p-d-eng)
             ("u_machine.u_six_layers.u_datapath.current_stage_q" r-d-cst :cond c-d-cst :output p-d-cst)
             ("u_machine.u_six_layers.u_datapath.current_layer_q" r-d-clay :cond c-d-clay :output p-d-clay)
             ("u_machine.u_six_layers.u_datapath.current_position_q" r-d-cpos :cond c-d-cpos :output p-d-cpos)
             ("u_machine.u_six_layers.u_datapath.expected_stage_q" r-d-est :cond c-d-est :output p-d-est)
             ("u_machine.u_six_layers.u_datapath.expected_layer_q" r-d-elay :cond c-d-elay :output p-d-elay)
             ("u_machine.u_six_layers.u_datapath.transaction_position_q" r-d-tpos :cond c-d-tpos :output p-d-tpos)
             ("u_machine.u_six_layers.u_datapath.transaction_seen_q" r-d-tseen :cond c-d-tseen :output p-d-tseen)
             ("u_machine.u_six_layers.u_datapath.fault_q" r-d-fault :cond c-d-fault :output p-d-fault)
             ("u_machine.u_six_layers.u_datapath.lock_seen_q" r-d-lseen :cond c-d-lseen :output p-d-lseen)
             ("u_machine.u_six_layers.u_datapath.stage_done_q" r-d-sdone :cond c-d-sdone :output p-d-sdone)
             ("u_machine.u_six_layers.u_datapath.key_exponent_q" r-d-kexp :cond c-d-kexp :output p-d-kexp)
             ("u_machine.u_six_layers.u_datapath.value_exponent_q" r-d-vexp :cond c-d-vexp :output p-d-vexp)
             ("u_machine.u_six_layers.u_datapath.service_start_seen_q" r-d-sss :cond c-d-sss :output p-d-sss)
             ("u_machine.u_six_layers.u_datapath.output_done_q" r-d-odone :cond c-d-odone :output p-d-odone)
             ("u_machine.u_six_layers.u_datapath.service_done_seen_q" r-d-sds :cond c-d-sds :output p-d-sds)
             ("u_machine.u_six_layers.u_datapath.norm_done_seen_q" r-d-nds :cond c-d-nds :output p-d-nds)
             ("u_machine.u_six_layers.u_datapath.input_index_q" r-d-iidx :cond c-d-iidx :output p-d-iidx)
             ("u_machine.u_six_layers.u_datapath.input_done_q" r-d-idone :cond c-d-idone :output p-d-idone)
             ("u_machine.u_six_layers.u_datapath.output_index_q" r-d-oidx :cond c-d-oidx :output p-d-oidx)
             ("u_machine.u_six_layers.u_datapath.rope_phase_q" r-d-rphase :cond c-d-rphase :output p-d-rphase)
             ("u_machine.u_six_layers.u_datapath.rope_head_q" r-d-rhead :cond c-d-rhead :output p-d-rhead)
             ("u_machine.u_six_layers.u_datapath.rope_half_q" r-d-rhalf :cond c-d-rhalf :output p-d-rhalf)
             ("u_machine.u_six_layers.u_datapath.rope_second_index_q" r-d-rsecond :cond c-d-rsecond :output p-d-rsecond)
             ("u_machine.u_six_layers.u_datapath.attention_result_head_q" r-d-arhead :cond c-d-arhead :output p-d-arhead)
             ("u_machine.u_six_layers.u_datapath.attention_store_lane_q" r-d-aslane :cond c-d-aslane :output p-d-aslane)
             ("u_machine.u_six_layers.u_datapath.silu_value_valid_q" r-d-svv :cond c-d-svv :output p-d-svv)
             ("u_machine.u_six_layers.u_datapath.gate_exponent_q" r-d-gexp :cond c-d-gexp :output p-d-gexp)
             ("u_machine.u_six_layers.u_datapath.kv_read_valid_q" r-d-kvrv :cond c-d-kvrv :output p-d-kvrv)
             ("u_machine.u_six_layers.u_datapath.elem_phase_q" r-d-ephase :cond c-d-ephase :output p-d-ephase)
             ("u_machine.u_six_layers.u_datapath.u_key_state.payload_mem" r-d-kmem :cond c-d-kmem :output p-d-kmem)
             ("u_machine.u_six_layers.u_datapath.u_value_state.payload_mem" r-d-vmem :cond c-d-vmem :output p-d-vmem)
             ("u_machine.u_six_layers.u_datapath.key_ram_read_data" r-d-krd :cond c-d-krd :output p-d-krd)
             ("u_machine.u_six_layers.u_datapath.value_ram_read_data" r-d-vrd :cond c-d-vrd :output p-d-vrd)
             ("u_machine.root_terminal" h-rterm :cond c-h-rterm :output p-h-rterm)
             ("u_machine.u_six_layers.u_datapath.child_fault" h-childfault :cond c-h-childfault :output p-h-childfault)
             ("u_machine.u_six_layers.u_datapath.norm_result_valid" h-nrv :cond c-h-nrv :output p-h-nrv)
             ("u_machine.u_six_layers.u_datapath.norm_result_index" h-nri :cond c-h-nri :output p-h-nri)
             ("u_machine.u_six_layers.u_datapath.norm_result_mantissa" h-nrm :cond c-h-nrm :output p-h-nrm)
             ("u_machine.u_six_layers.u_datapath.norm_result_exponent" h-nre :cond c-h-nre :output p-h-nre)
             ("u_machine.u_six_layers.u_datapath.norm_result_last" h-nrl :cond c-h-nrl :output p-h-nrl)
             ("u_machine.u_six_layers.u_datapath.norm_done_valid" h-ndv :cond c-h-ndv :output p-h-ndv)
             ("u_machine.u_six_layers.u_datapath.projection_done_valid" h-pdv :cond c-h-pdv :output p-h-pdv)
             ("u_machine.u_six_layers.u_datapath.rms_result_valid" h-rrv :cond c-h-rrv :output p-h-rrv)
             ("u_machine.u_six_layers.u_datapath.rms_result_index" h-rri :cond c-h-rri :output p-h-rri)
             ("u_machine.u_six_layers.u_datapath.rms_result_last" h-rrl :cond c-h-rrl :output p-h-rrl)
             ("u_machine.u_six_layers.u_datapath.rms_done_valid" h-rdv :cond c-h-rdv :output p-h-rdv)
             ("u_machine.u_six_layers.u_datapath.head_done_fire" h-hdf :cond c-h-hdf :output p-h-hdf)
             ("u_machine.u_six_layers.u_datapath.lookup_response_valid" h-lrv :cond c-h-lrv :output p-h-lrv)
             ("u_machine.u_six_layers.u_datapath.lookup_response_fault" h-lrf :cond c-h-lrf :output p-h-lrf)
             ("u_machine.u_six_layers.u_datapath.attention_result_valid" h-arv :cond c-h-arv :output p-h-arv)
             ("u_machine.u_six_layers.u_datapath.attention_result_last" h-arl :cond c-h-arl :output p-h-arl)
             ("u_machine.u_six_layers.u_datapath.attention_done_valid" h-adv :cond c-h-adv :output p-h-adv)
             ("u_machine.u_six_layers.u_datapath.lane_lut_request" h-llr :cond c-h-llr :output p-h-llr)
             ("u_machine.u_six_layers.u_datapath.lane_lut_index" h-lli :cond c-h-lli :output p-h-lli)
             ("u_machine.u_six_layers.u_datapath.gate_read_data" h-grd :cond c-h-grd :output p-h-grd)
             ("u_machine.u_six_layers.u_datapath.kv_commit_ready" h-kcr :cond c-h-kcr :output p-h-kcr)
             ("u_machine.u_six_layers.u_datapath.kv_stage_begin_ready" h-sbr :cond c-h-sbr :output p-h-sbr)
             ("u_machine.u_six_layers.u_datapath.kv_stage_payload_ready" h-spr :cond c-h-spr :output p-h-spr)
             ("u_machine.u_six_layers.u_datapath.kv_pending_complete" h-kpc :cond c-h-kpc :output p-h-kpc)
             ("u_machine.u_six_layers.u_datapath.private_head_start_ready_o" h-hsr :cond c-h-hsr :output p-h-hsr)
             ("u_machine.u_six_layers.u_datapath.rms_input_fire" h-rif :cond c-h-rif :output p-h-rif)
             ("u_machine.u_six_layers.u_datapath.projection_activation_fire" h-paf :cond c-h-paf :output p-h-paf)
             ("u_machine.u_six_layers.u_datapath.head_activation_fire" h-haf :cond c-h-haf :output p-h-haf)
             ("u_machine.u_six_layers.private_head_start_valid_i" h-hsv :cond c-h-hsv :output p-h-hsv)
             ("u_machine.u_six_layers.start_valid_i" h-lsv :cond c-h-lsv :output p-h-lsv)
             ("u_machine.u_six_layers.datapath_busy" h-dbusy :cond c-h-dbusy :output p-h-dbusy)
             ("u_machine.u_six_layers.u_sequence.input_fire" h-sif :cond c-h-sif :output p-h-sif)
             ("u_machine.u_six_layers.u_sequence.input_legal" h-sil :cond c-h-sil :output p-h-sil)
             ("u_machine.u_six_layers.u_sequence.prefixes_match" h-spm :cond c-h-spm :output p-h-spm)
             ("u_machine.u_six_layers.u_sequence.input_exponent_i" h-siexp :cond c-h-siexp :output p-h-siexp)
             ("u_machine.u_six_layers.u_sequence.fixed_position_i" h-sfpos :cond c-h-sfpos :output p-h-sfpos)
             ("u_machine.u_six_layers.u_sequence.done_fire" h-sdf :cond c-h-sdf :output p-h-sdf)
             ("u_machine.u_six_layers.u_sequence.result_fire" h-srf :cond c-h-srf :output p-h-srf)
             ("u_machine.u_six_layers.u_sequence.private_result_exponent_i" h-srexp :cond c-h-srexp :output p-h-srexp)
             ("u_machine.u_six_layers.u_sequence.private_result_mantissa_i" h-srman :cond c-h-srman :output p-h-srman))
            :outputs (
                      ("u_machine.u_six_layers.u_datapath.rst_n" o-dprst)
                      ("u_machine.u_six_layers.u_datapath.clear_i" o-dpclear)
                      ("u_machine.u_six_layers.u_datapath.stage_accept" o-sacc)
                      ("u_machine.u_six_layers.u_datapath.private_stage_i" o-pstage)
                      ("u_machine.u_six_layers.u_datapath.private_layer_i" o-player)
                      ("u_machine.u_six_layers.u_datapath.private_position_i" o-ppos)
                      ("u_machine.u_six_layers.u_datapath.key_ram_write_enable" o-kwe)
                      ("u_machine.u_six_layers.u_datapath.value_ram_write_enable" o-vwe)
                      ("u_machine.u_six_layers.u_datapath.key_ram_read_enable" o-kre)
                      ("u_machine.u_six_layers.u_datapath.value_ram_read_enable" o-vre)
                      ("u_machine.u_six_layers.u_datapath.key_ram_read_address" o-kra)
                      ("u_machine.u_six_layers.u_datapath.value_ram_read_address" o-vra)
                      ("u_machine.u_six_layers.u_datapath.kv_stage_begin_valid" o-sbv)
                      ("u_machine.u_six_layers.u_datapath.kv_stage_payload_valid" o-spv)
                      ("u_machine.u_six_layers.u_datapath.head_start_accept" o-hacc)
                      ("u_machine.u_six_layers.u_sequence.start_fire" o-sfire)
                      ("u_machine.layer_fail" o-layerfail)))
           (:label next
            :inputs (("reset_n_i" 1))
            :outputs (
             ("u_machine.machine_release_q" n-m-rel)
             ("u_machine.u_six_layers.u_sequence.state_q" n-s-state)
             ("u_machine.u_six_layers.u_sequence.layer_q" n-s-layer)
             ("u_machine.u_six_layers.u_sequence.stage_q" n-s-stage)
             ("u_machine.u_six_layers.u_sequence.position_q" n-s-pos)
             ("u_machine.u_six_layers.u_sequence.fault_q" n-s-fault)
             ("u_machine.u_six_layers.u_datapath.engine_state_q" n-d-eng)
             ("u_machine.u_six_layers.u_datapath.current_stage_q" n-d-cst)
             ("u_machine.u_six_layers.u_datapath.current_layer_q" n-d-clay)
             ("u_machine.u_six_layers.u_datapath.current_position_q" n-d-cpos)
             ("u_machine.u_six_layers.u_datapath.expected_stage_q" n-d-est)
             ("u_machine.u_six_layers.u_datapath.expected_layer_q" n-d-elay)
             ("u_machine.u_six_layers.u_datapath.transaction_position_q" n-d-tpos)
             ("u_machine.u_six_layers.u_datapath.transaction_seen_q" n-d-tseen)
             ("u_machine.u_six_layers.u_datapath.fault_q" n-d-fault)
             ("u_machine.u_six_layers.u_datapath.lock_seen_q" n-d-lseen)
             ("u_machine.u_six_layers.u_datapath.stage_done_q" n-d-sdone)
             ("u_machine.u_six_layers.u_datapath.key_exponent_q" n-d-kexp)
             ("u_machine.u_six_layers.u_datapath.value_exponent_q" n-d-vexp)
             ("u_machine.u_six_layers.u_datapath.output_done_q" n-d-odone)
             ("u_machine.u_six_layers.u_datapath.input_index_q" n-d-iidx)
             ("u_machine.u_six_layers.u_datapath.output_index_q" n-d-oidx)
             ("u_machine.u_six_layers.u_datapath.kv_read_valid_q" n-d-kvrv)
             ("u_machine.u_six_layers.u_datapath.u_key_state.payload_mem" n-d-kmem)
             ("u_machine.u_six_layers.u_datapath.u_value_state.payload_mem" n-d-vmem)
             ("u_machine.u_six_layers.u_datapath.key_ram_read_data" n-d-krd)
             ("u_machine.u_six_layers.u_datapath.value_ram_read_data" n-d-vrd)))))

(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export producer-step-run-data)
  (make-event '(def-svtv-refinement producer-step-run producer-step-run-data
                 :svtv-spec producer-step-spec :inclusive-overridekeys t
                 :fsm probe-fsm)))
(value-triple (acl2::cw "~%PROD-REFINEMENT done~%"))

; The run fixes what the certified step run fixes: the lock input is 1 in
; the cycle and reset_n_i is 1 in the next.
(defthm kv-producer-run-constraints
  (equal (producer-step-run-fsm-constraints) (join-step-run-fsm-constraints))
  :rule-classes nil)

; ===========================================================================
; The state invariant, the working memories' cells, and the facts.
; ===========================================================================

; The engine state that runs stage s.
(define prod-engine-of (s) :verify-guards nil
  (cond ((or (equal s 0) (equal s 10)) 1)
        ((or (equal s 1) (equal s 2) (equal s 3) (equal s 8) (equal s 11) (equal s 12) (equal s 14)) 2)
        ((or (equal s 4) (equal s 5)) 3)
        ((equal s 6) 4)
        ((equal s 7) 5)
        ((or (equal s 9) (equal s 13) (equal s 15)) 6)
        ((equal s 16) 7)
        (t 15)))
; The engine is running a stage.
(define prod-busy (eng) :verify-guards nil
  (and (<= 1 eng) (<= eng 7)))
; Cell c of a 128-cell working memory, cell 0 highest.
(define prod-slot (c mem) :verify-guards nil
  (loghead 16 (logtail (* 16 (- 127 (loghead 7 c))) mem)))
; The memory with cell c replaced by v.
(define prod-put (c v mem) :verify-guards nil
  (b* ((sh (* 16 (- 127 (loghead 7 c)))))
    (logior (logand (loghead 2048 mem) (lognot (ash #xffff sh)))
            (ash (loghead 16 v) sh))))
; THE STATE INVARIANT of the stage sequencer and the datapath's stage
; controller.
(define prod-sinv (eng cst clay cpos est elay tpos tseen sdone lseen sst slay sstage spos) :verify-guards nil
  (and
   ;; layers are 0 to 5 and stages 0 to 16
   (<= elay 5) (<= slay 5) (<= est 16) (<= sstage 16)
   ;; a running stage is the expected one, of the transaction in progress,
   ;; and the sequencer waits for exactly that stage
   (or (not (prod-busy eng))
       (and (equal cst est) (equal clay elay) (equal cpos tpos) (equal tseen 1) (equal sdone 0)
            (equal eng (prod-engine-of cst)) (equal lseen 1)
            (equal sst 3) (equal sstage cst) (equal slay clay) (equal spos cpos)))
   ;; the done pulse comes with an idle engine, to a waiting sequencer
   (or (equal sdone 0) (and (equal eng 0) (equal sst 3)))
   ;; outside a transaction nothing is expected but the first stage
   (or (equal tseen 1) (and (equal est 0) (equal elay 0) (not (prod-busy eng))))
   ;; inside a transaction the sequencer is mid-pass at the same position
   (or (equal tseen 0)
       (and (not (equal eng 8)) (equal spos tpos)
            (or (equal sst 2) (equal sst 3) (equal sst 4) (equal sst 6))))
   ;; ... about to request the expected stage,
   (or (not (and (equal tseen 1) (equal sst 2)))
       (and (equal eng 0) (equal sdone 0) (equal est sstage) (equal elay slay)))
   ;; ... or having just been told its stage is done,
   (or (not (and (equal tseen 1) (equal sst 3) (not (prod-busy eng))))
       (and (equal sdone 1)
            (or (and (< sstage 16) (equal est (+ 1 sstage)) (equal elay slay))
                (and (equal sstage 16) (< slay 5) (equal est 0) (equal elay (+ 1 slay))))))
   ;; ... or streaming the final hidden vector out before the last commit
   (or (not (and (equal tseen 1) (or (equal sst 4) (equal sst 6))))
       (and (equal eng 0) (equal sdone 0) (equal est 16) (equal elay 5) (equal slay 5)))
   ;; the done pulse that ends a transaction is the last layer's commit
   (or (not (and (equal sdone 1) (equal tseen 0)))
       (and (equal sstage 16) (equal slay 5)))))

; The guard of the step facts: the cycle is outside reset, no fault is
; registered before or after it, and the state invariant holds in it.
(define prd-guard-plain (n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (and (equal r-d-fault 0) (equal n-d-fault 0) (equal r-s-fault 0) (equal n-s-fault 0)) (prod-sinv r-d-eng r-d-cst r-d-clay r-d-cpos r-d-est r-d-elay r-d-tpos r-d-tseen r-d-sdone r-d-lseen r-s-state r-s-layer r-s-stage r-s-pos)))
; The six-layer block's fault output is the OR of the sequencer's fault
; register, the datapath's and the start-collision register.
(define prd-p-layerfail (o-layerfail r-d-fault r-l-coll r-s-fault)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (equal o-layerfail (if (or (equal r-s-fault 1) (equal r-d-fault 1) (equal r-l-coll 1)) 1 0)))
; While the machine core is not released its children are held in reset.
(define prd-p-inactive (o-dprst r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal r-m-rel 0)) (equal o-dprst 0)))
; The children's reset is released exactly when reset_n_i is high and
; the machine core is released.
(define prd-p-children-reset (i-reset-n o-dprst r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (equal o-dprst (if (and (equal i-reset-n 1) (logbitp 1 r-m-rel)) 1 0)))
; The machine core is not released in the cycle after one in which its
; release register is 0.
(define prd-p-release (n-m-rel r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal r-m-rel 0)) (not (equal n-m-rel 3))))
; The datapath offers a staging begin or a staging payload only with its
; engine in the K/V stage; a begin only before the stage's begin has been
; accepted, and a payload only when a read of both memories has landed.
(define prd-p-staging-valid (o-sbv o-spv r-d-eng r-d-kvrv r-d-sss)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (or (not (equal o-sbv 1))
          (and (equal r-d-eng 4) (equal r-d-sss 0)))
      (or (not (equal o-spv 1))
          (and (equal r-d-eng 4) (equal r-d-kvrv 1)))))
; Without the public CLEAR there is no CLEAR at the datapath.
(define prd-p-clear (i-clear o-dpclear)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal i-clear 0)) (equal o-dpclear 0)))
; A cycle in which the children's reset is asserted, or after which the
; machine core is not released, leaves the sequencer and the stage
; controller in their reset state.
(define prd-p-reset (n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (and (equal n-d-eng 0) (equal n-d-est 0) (equal n-d-elay 0) (equal n-d-tseen 0) (equal n-d-sdone 0) (equal n-s-state 0) (equal n-d-fault 0) (equal n-s-fault 0) (prod-sinv n-d-eng n-d-cst n-d-clay n-d-cpos n-d-est n-d-elay n-d-tpos n-d-tseen n-d-sdone n-d-lseen n-s-state n-s-layer n-s-stage n-s-pos))))
; The key memory's next contents are definite.
(define prd-p-key-memory-definite (n-d-kmem)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (unsigned-byte-p 2048 n-d-kmem))
; The value memory's next contents are definite.
(define prd-p-value-memory-definite (n-d-vmem)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (unsigned-byte-p 2048 n-d-vmem))
; The state invariant is kept by a cycle outside reset with no fault
; registered before or after it.
(define prd-p-sinv (n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (and (equal r-d-fault 0) (equal n-d-fault 0) (equal r-s-fault 0) (equal n-s-fault 0)) (prod-sinv r-d-eng r-d-cst r-d-clay r-d-cpos r-d-est r-d-elay r-d-tpos r-d-tseen r-d-sdone r-d-lseen r-s-state r-s-layer r-s-stage r-s-pos))) (prod-sinv n-d-eng n-d-cst n-d-clay n-d-cpos n-d-est n-d-elay n-d-tpos n-d-tseen n-d-sdone n-d-lseen n-s-state n-s-layer n-s-stage n-s-pos)))
; A stage request is accepted only by an idle engine, in a cycle without
; CLEAR, and only if it is for the expected stage and layer and, inside a
; transaction, for the transaction's position.  It starts that stage: the
; current stage, layer and position are the requested ones, the output index
; is 0, and no working memory is written in the cycle.
(define prd-p-accept (n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-iidx n-d-kvrv n-d-odone n-d-oidx n-d-tpos n-d-tseen o-dpclear o-kwe o-player o-ppos o-pstage o-sacc o-vwe r-d-elay r-d-eng r-d-est r-d-tpos r-d-tseen)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal o-sacc 1))
      (and (equal r-d-eng 0) (equal o-dpclear 0)
           (equal o-pstage r-d-est) (equal o-player r-d-elay)
           (or (equal r-d-tseen 0) (equal o-ppos r-d-tpos))
           (equal n-d-cst o-pstage) (equal n-d-clay o-player) (equal n-d-cpos o-ppos)
           (equal n-d-tpos o-ppos) (equal n-d-tseen 1)
           (equal n-d-est r-d-est) (equal n-d-elay r-d-elay)
           (equal n-d-oidx 0) (equal n-d-odone 0) (equal n-d-iidx 0) (equal n-d-kvrv 0)
           (equal n-d-eng (prod-engine-of o-pstage))
           (equal o-kwe 0) (equal o-vwe 0))))
; The key memory is written only by an accepted normalized result whose
; index is the output index, in the K projection stage or the K rotary
; stage; the write puts the result's mantissa in the cell of that index and
; its exponent in key_exponent_q.  In the rotary stage the result is the
; last one exactly at index 127, and the output index then stops; otherwise
; it goes up by one.  In a cycle without such a write the key memory and
; key_exponent_q do not change, and in the rotary stage neither does the
; output index.
(define prd-p-key-write (h-nre h-nri h-nrl h-nrm h-nrv n-d-kexp n-d-kmem n-d-odone n-d-oidx o-dpclear o-kwe r-d-cst r-d-eng r-d-kexp r-d-kmem r-d-odone r-d-oidx)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (if (equal o-kwe 1)
       (and (equal h-nrv 1) (equal o-dpclear 0) (equal h-nri r-d-oidx)
            (or (and (equal r-d-eng 2) (equal r-d-cst 2)) (and (equal r-d-eng 3) (equal r-d-cst 5)))
            (equal n-d-kmem (prod-put r-d-oidx h-nrm r-d-kmem))
            (equal n-d-kexp h-nre)
            (or (not (equal r-d-cst 5))
                (and (equal h-nrl (if (equal r-d-oidx 127) 1 0))
                     (if (equal h-nrl 1)
                         (and (equal n-d-odone 1) (equal n-d-oidx r-d-oidx))
                       (and (equal n-d-odone r-d-odone) (equal n-d-oidx (loghead 10 (+ 1 r-d-oidx))))))))
     (and (equal n-d-kmem r-d-kmem) (equal n-d-kexp r-d-kexp)
          (or (not (and (equal r-d-eng 3) (equal r-d-cst 5) (equal o-dpclear 0)))
              (and (equal n-d-odone r-d-odone) (equal n-d-oidx r-d-oidx))))))
; The value memory is written only by an accepted normalized result whose
; index is the output index, in the V projection stage; the rest as for the
; key memory's rotary stage.
(define prd-p-value-write (h-nre h-nri h-nrl h-nrm h-nrv n-d-odone n-d-oidx n-d-vexp n-d-vmem o-dpclear o-vwe r-d-cst r-d-eng r-d-odone r-d-oidx r-d-vexp r-d-vmem)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (if (equal o-vwe 1)
       (and (equal h-nrv 1) (equal o-dpclear 0) (equal h-nri r-d-oidx)
            (equal r-d-eng 2) (equal r-d-cst 3)
            (equal n-d-vmem (prod-put r-d-oidx h-nrm r-d-vmem))
            (equal n-d-vexp h-nre)
            (equal h-nrl (if (equal r-d-oidx 127) 1 0))
            (if (equal h-nrl 1)
                (and (equal n-d-odone 1) (equal n-d-oidx r-d-oidx))
              (and (equal n-d-odone r-d-odone) (equal n-d-oidx (loghead 10 (+ 1 r-d-oidx))))))
     (and (equal n-d-vmem r-d-vmem) (equal n-d-vexp r-d-vexp)
          (or (not (and (equal r-d-eng 2) (equal r-d-cst 3) (equal o-dpclear 0)))
              (and (equal n-d-odone r-d-odone) (equal n-d-oidx r-d-oidx))))))
; The K rotary stage, the V projection stage and the K/V stage are each
; entered only by the accepted request for that stage.
(define prd-p-stage-entry (n-d-cst n-d-eng o-pstage o-sacc r-d-cst r-d-eng)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (or (not (and (equal n-d-eng 3) (equal n-d-cst 5) (not (and (equal r-d-eng 3) (equal r-d-cst 5)))))
          (and (equal o-sacc 1) (equal o-pstage 5)))
      (or (not (and (equal n-d-eng 2) (equal n-d-cst 3) (not (and (equal r-d-eng 2) (equal r-d-cst 3)))))
          (and (equal o-sacc 1) (equal o-pstage 3)))
      (or (not (and (equal n-d-eng 4) (not (equal r-d-eng 4))))
          (and (equal o-sacc 1) (equal o-pstage 6)))))
; The K rotary stage is left, without CLEAR, only to the idle engine with
; stage 6 expected next, and only once its last result has been accepted.
(define prd-p-key-stage-end (h-nrl n-d-cst n-d-eng n-d-est o-dpclear o-kwe r-d-cst r-d-eng r-d-est r-d-odone)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-d-eng 3) (equal r-d-cst 5) (equal o-dpclear 0)))
      (or (and (equal n-d-eng 3) (equal n-d-cst 5) (equal n-d-est r-d-est))
          (and (equal n-d-eng 0) (equal n-d-est 6)
               (or (equal r-d-odone 1) (and (equal o-kwe 1) (equal h-nrl 1)))))))
; The V projection stage is left, without CLEAR, only to the idle engine
; with stage 4 expected next, and only once its last result has been
; accepted.
(define prd-p-value-stage-end (h-nrl n-d-cst n-d-eng n-d-est o-dpclear o-vwe r-d-cst r-d-eng r-d-est r-d-odone)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-d-eng 2) (equal r-d-cst 3) (equal o-dpclear 0)))
      (or (and (equal n-d-eng 2) (equal n-d-cst 3) (equal n-d-est r-d-est))
          (and (equal n-d-eng 0) (equal n-d-est 4)
               (or (equal r-d-odone 1) (and (equal o-vwe 1) (equal h-nrl 1)))))))
; The expected stage becomes 4, 5 or 6 from anything else only by the end
; of the V projection stage.
(define prd-p-value-done-entry (n-d-est o-dpclear r-d-cst r-d-eng r-d-est)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (<= 4 n-d-est) (<= n-d-est 6) (not (and (<= 4 r-d-est) (<= r-d-est 6)))))
      (and (equal r-d-est 3) (equal r-d-eng 2) (equal r-d-cst 3) (equal o-dpclear 0) (equal n-d-est 4))))
; The expected stage becomes 6 from anything else only by the end of the K
; rotary stage.
(define prd-p-key-done-entry (n-d-est o-dpclear r-d-cst r-d-eng r-d-est)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal n-d-est 6) (not (equal r-d-est 6))))
      (and (equal r-d-est 5) (equal r-d-eng 3) (equal r-d-cst 5) (equal o-dpclear 0))))
; While stage 4, 5 or 6 is expected the value memory is not written and no
; V projection stage is accepted.
(define prd-p-value-frozen (o-pstage o-sacc o-vwe r-d-est)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (<= 4 r-d-est) (<= r-d-est 6)))
      (and (equal o-vwe 0) (not (and (equal o-sacc 1) (equal o-pstage 3))))))
; While stage 6 is expected the key memory is not written and no K rotary
; stage is accepted.
(define prd-p-key-frozen (o-kwe o-pstage o-sacc r-d-est)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal r-d-est 6))
      (and (equal o-kwe 0) (not (and (equal o-sacc 1) (equal o-pstage 5))))))
; While stage 3, 4, 5 or 6 is expected and there is no CLEAR, the expected
; layer and the transaction's position do not change.
(define prd-p-transaction (n-d-elay n-d-tpos n-d-tseen o-dpclear r-d-elay r-d-est r-d-tpos r-d-tseen)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (<= 3 r-d-est) (<= r-d-est 6) (equal o-dpclear 0)))
      (and (equal n-d-elay r-d-elay) (equal n-d-tpos r-d-tpos) (equal r-d-tseen 1) (equal n-d-tseen 1))))
; While stage 6 is expected and there is no CLEAR, stage 6 stays expected
; unless the K/V stage ends, which needs the controller's
; pending_complete_o.
(define prd-p-staging-stage (h-kpc n-d-est o-dpclear r-d-eng r-d-est)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-d-est 6) (equal o-dpclear 0)))
      (or (equal n-d-est 6)
          (and (equal n-d-est 7) (equal h-kpc 1) (equal r-d-eng 4)))))
; Each working memory's read register takes the addressed cell in a cycle
; with its read enable and keeps its value otherwise.
(define prd-p-memory-read (n-d-krd n-d-vrd o-kra o-kre o-vra o-vre r-d-kmem r-d-krd r-d-vmem r-d-vrd)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (if (equal o-kre 1)
           (equal n-d-krd (prod-slot o-kra r-d-kmem))
         (equal n-d-krd r-d-krd))
      (if (equal o-vre 1)
          (equal n-d-vrd (prod-slot o-vra r-d-vmem))
        (equal n-d-vrd r-d-vrd))))
; In the K/V stage a landed read stays landed, with the input index
; unchanged and no new read, or has just been made: both memories read at
; the cell of the input index.
(define prd-p-staging-read (n-d-eng n-d-iidx n-d-kvrv o-kra o-kre o-vra o-vre r-d-eng r-d-iidx r-d-kvrv)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-d-eng 4) (equal n-d-eng 4) (equal n-d-kvrv 1)))
      (and (equal n-d-iidx r-d-iidx)
           (or (and (equal r-d-kvrv 1) (equal o-kre 0) (equal o-vre 0))
               (and (equal r-d-kvrv 0) (equal o-kre 1) (equal o-vre 1)
                    (equal o-kra (loghead 7 r-d-iidx)) (equal o-vra (loghead 7 r-d-iidx)))))))
; The sequencer leaves idle only by an accepted start, which takes the
; position offered with it; while it stays busy its position does not
; change and there is neither a start nor a CLEAR.
(define prd-p-sequence (h-lsv h-sfpos n-s-pos n-s-state o-dpclear o-sfire r-s-pos r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (or (not (equal o-sfire 1))
          (and (equal r-s-state 0) (equal n-s-state 1) (equal n-s-pos h-sfpos) (equal h-lsv 1) (equal o-dpclear 0)))
      (or (not (and (equal r-s-state 0) (not (equal n-s-state 0))))
          (equal o-sfire 1))
      (or (not (and (not (equal r-s-state 0)) (not (equal n-s-state 0))))
          (and (equal n-s-pos r-s-pos) (equal o-sfire 0) (equal o-dpclear 0)))))
; The sequencer's accepted done returns it to idle.
(define prd-p-sequence-done (h-sdf n-s-state r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-s-state 5) (equal h-sdf 1)))
      (equal n-s-state 0)))
; A CLEAR at the datapath leaves the stage controller idle with stage 0
; expected, and the sequencer idle.
(define prd-p-clear-resets (n-d-eng n-d-est n-s-state o-dpclear)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (equal o-dpclear 0)
      (and (equal n-d-eng 0) (equal n-d-est 0) (equal n-s-state 0))))

; ===========================================================================
; What the SAT solver is asked about the symbolic run: each fact, read of
; the run's outputs through pay-u.
; ===========================================================================
(define prod-int-o-dprst (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-dprst"
  (integerp x)))
(defthm prod-int-o-dprst-integerp
  (implies (prod-int-o-dprst x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-dprst fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-dpclear (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-dpclear"
  (integerp x)))
(defthm prod-int-o-dpclear-integerp
  (implies (prod-int-o-dpclear x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-dpclear fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-sacc (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-sacc"
  (integerp x)))
(defthm prod-int-o-sacc-integerp
  (implies (prod-int-o-sacc x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-sacc fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-pstage (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-pstage"
  (integerp x)))
(defthm prod-int-o-pstage-integerp
  (implies (prod-int-o-pstage x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-pstage fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-player (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-player"
  (integerp x)))
(defthm prod-int-o-player-integerp
  (implies (prod-int-o-player x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-player fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-ppos (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-ppos"
  (integerp x)))
(defthm prod-int-o-ppos-integerp
  (implies (prod-int-o-ppos x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-ppos fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-kwe (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-kwe"
  (integerp x)))
(defthm prod-int-o-kwe-integerp
  (implies (prod-int-o-kwe x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-kwe fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-vwe (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-vwe"
  (integerp x)))
(defthm prod-int-o-vwe-integerp
  (implies (prod-int-o-vwe x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-vwe fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-kre (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-kre"
  (integerp x)))
(defthm prod-int-o-kre-integerp
  (implies (prod-int-o-kre x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-kre fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-vre (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-vre"
  (integerp x)))
(defthm prod-int-o-vre-integerp
  (implies (prod-int-o-vre x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-vre fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-kra (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-kra"
  (integerp x)))
(defthm prod-int-o-kra-integerp
  (implies (prod-int-o-kra x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-kra fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-vra (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-vra"
  (integerp x)))
(defthm prod-int-o-vra-integerp
  (implies (prod-int-o-vra x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-vra fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-sbv (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-sbv"
  (integerp x)))
(defthm prod-int-o-sbv-integerp
  (implies (prod-int-o-sbv x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-sbv fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-spv (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-spv"
  (integerp x)))
(defthm prod-int-o-spv-integerp
  (implies (prod-int-o-spv x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-spv fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-sfire (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-sfire"
  (integerp x)))
(defthm prod-int-o-sfire-integerp
  (implies (prod-int-o-sfire x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-sfire fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-o-layerfail (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-o-layerfail"
  (integerp x)))
(defthm prod-int-o-layerfail-integerp
  (implies (prod-int-o-layerfail x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-o-layerfail fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-m-rel (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-m-rel"
  (integerp x)))
(defthm prod-int-n-m-rel-integerp
  (implies (prod-int-n-m-rel x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-m-rel fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-s-state (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-s-state"
  (integerp x)))
(defthm prod-int-n-s-state-integerp
  (implies (prod-int-n-s-state x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-s-state fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-s-layer (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-s-layer"
  (integerp x)))
(defthm prod-int-n-s-layer-integerp
  (implies (prod-int-n-s-layer x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-s-layer fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-s-stage (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-s-stage"
  (integerp x)))
(defthm prod-int-n-s-stage-integerp
  (implies (prod-int-n-s-stage x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-s-stage fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-s-pos (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-s-pos"
  (integerp x)))
(defthm prod-int-n-s-pos-integerp
  (implies (prod-int-n-s-pos x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-s-pos fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-s-fault (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-s-fault"
  (integerp x)))
(defthm prod-int-n-s-fault-integerp
  (implies (prod-int-n-s-fault x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-s-fault fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-eng (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-eng"
  (integerp x)))
(defthm prod-int-n-d-eng-integerp
  (implies (prod-int-n-d-eng x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-eng fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-cst (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-cst"
  (integerp x)))
(defthm prod-int-n-d-cst-integerp
  (implies (prod-int-n-d-cst x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-cst fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-clay (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-clay"
  (integerp x)))
(defthm prod-int-n-d-clay-integerp
  (implies (prod-int-n-d-clay x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-clay fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-cpos (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-cpos"
  (integerp x)))
(defthm prod-int-n-d-cpos-integerp
  (implies (prod-int-n-d-cpos x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-cpos fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-est (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-est"
  (integerp x)))
(defthm prod-int-n-d-est-integerp
  (implies (prod-int-n-d-est x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-est fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-elay (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-elay"
  (integerp x)))
(defthm prod-int-n-d-elay-integerp
  (implies (prod-int-n-d-elay x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-elay fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-tpos (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-tpos"
  (integerp x)))
(defthm prod-int-n-d-tpos-integerp
  (implies (prod-int-n-d-tpos x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-tpos fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-tseen (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-tseen"
  (integerp x)))
(defthm prod-int-n-d-tseen-integerp
  (implies (prod-int-n-d-tseen x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-tseen fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-fault (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-fault"
  (integerp x)))
(defthm prod-int-n-d-fault-integerp
  (implies (prod-int-n-d-fault x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-fault fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-lseen (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-lseen"
  (integerp x)))
(defthm prod-int-n-d-lseen-integerp
  (implies (prod-int-n-d-lseen x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-lseen fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-sdone (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-sdone"
  (integerp x)))
(defthm prod-int-n-d-sdone-integerp
  (implies (prod-int-n-d-sdone x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-sdone fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-kexp (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-kexp"
  (integerp x)))
(defthm prod-int-n-d-kexp-integerp
  (implies (prod-int-n-d-kexp x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-kexp fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-vexp (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-vexp"
  (integerp x)))
(defthm prod-int-n-d-vexp-integerp
  (implies (prod-int-n-d-vexp x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-vexp fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-odone (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-odone"
  (integerp x)))
(defthm prod-int-n-d-odone-integerp
  (implies (prod-int-n-d-odone x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-odone fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-iidx (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-iidx"
  (integerp x)))
(defthm prod-int-n-d-iidx-integerp
  (implies (prod-int-n-d-iidx x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-iidx fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-oidx (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-oidx"
  (integerp x)))
(defthm prod-int-n-d-oidx-integerp
  (implies (prod-int-n-d-oidx x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-oidx fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-kvrv (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-kvrv"
  (integerp x)))
(defthm prod-int-n-d-kvrv-integerp
  (implies (prod-int-n-d-kvrv x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-kvrv fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-kmem (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-kmem"
  (integerp x)))
(defthm prod-int-n-d-kmem-integerp
  (implies (prod-int-n-d-kmem x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-kmem fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-vmem (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-vmem"
  (integerp x)))
(defthm prod-int-n-d-vmem-integerp
  (implies (prod-int-n-d-vmem x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-vmem fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-krd (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-krd"
  (integerp x)))
(defthm prod-int-n-d-krd-integerp
  (implies (prod-int-n-d-krd x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-krd fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define prod-int-n-d-vrd (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-int-n-d-vrd"
  (integerp x)))
(defthm prod-int-n-d-vrd-integerp
  (implies (prod-int-n-d-vrd x) (integerp x))
  :hints (("Goal" :in-theory (enable prod-int-n-d-vrd fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(in-theory (disable prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))

(define prod-fact-layerfail (o-layerfail r-d-fault r-l-coll r-s-fault)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-layerfail"
  (prd-p-layerfail (pay-u o-layerfail) r-d-fault r-l-coll r-s-fault)))
(define prod-fact-inactive (o-dprst r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-inactive"
  (prd-p-inactive (pay-u o-dprst) r-m-rel)))
(define prod-fact-children-reset (i-reset-n o-dprst r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-children-reset"
  (prd-p-children-reset i-reset-n (pay-u o-dprst) r-m-rel)))
(define prod-fact-release (n-m-rel r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-release"
  (prd-p-release (pay-u n-m-rel) r-m-rel)))
(define prod-fact-staging-valid (o-sbv o-spv r-d-eng r-d-kvrv r-d-sss)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-staging-valid"
  (prd-p-staging-valid (pay-u o-sbv) (pay-u o-spv) r-d-eng r-d-kvrv r-d-sss)))
(define prod-fact-clear (i-clear o-dpclear)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-clear"
  (prd-p-clear i-clear (pay-u o-dpclear))))
(define prod-fact-reset (n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-reset"
  (prd-p-reset (pay-u n-d-clay) (pay-u n-d-cpos) (pay-u n-d-cst) (pay-u n-d-elay) (pay-u n-d-eng) (pay-u n-d-est) (pay-u n-d-fault) (pay-u n-d-lseen) (pay-u n-d-sdone) (pay-u n-d-tpos) (pay-u n-d-tseen) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u n-s-layer) (pay-u n-s-pos) (pay-u n-s-stage) (pay-u n-s-state) (pay-u o-dprst))))
(define prod-fact-key-memory-definite (n-d-kmem)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-key-memory-definite"
  (prd-p-key-memory-definite (pay-u n-d-kmem))))
(define prod-fact-value-memory-definite (n-d-vmem)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-value-memory-definite"
  (prd-p-value-memory-definite (pay-u n-d-vmem))))
(define prod-fact-sinv (n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-sinv"
  (prd-p-sinv (pay-u n-d-clay) (pay-u n-d-cpos) (pay-u n-d-cst) (pay-u n-d-elay) (pay-u n-d-eng) (pay-u n-d-est) (pay-u n-d-fault) (pay-u n-d-lseen) (pay-u n-d-sdone) (pay-u n-d-tpos) (pay-u n-d-tseen) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u n-s-layer) (pay-u n-s-pos) (pay-u n-s-stage) (pay-u n-s-state) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)))
(define prod-fact-accept (n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kvrv n-d-odone n-d-oidx n-d-tpos n-d-tseen n-m-rel n-s-fault o-dpclear o-dprst o-kwe o-player o-ppos o-pstage o-sacc o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-accept"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-accept (pay-u n-d-clay) (pay-u n-d-cpos) (pay-u n-d-cst) (pay-u n-d-elay) (pay-u n-d-eng) (pay-u n-d-est) (pay-u n-d-iidx) (pay-u n-d-kvrv) (pay-u n-d-odone) (pay-u n-d-oidx) (pay-u n-d-tpos) (pay-u n-d-tseen) (pay-u o-dpclear) (pay-u o-kwe) (pay-u o-player) (pay-u o-ppos) (pay-u o-pstage) (pay-u o-sacc) (pay-u o-vwe) r-d-elay r-d-eng r-d-est r-d-tpos r-d-tseen))))
(define prod-fact-key-write (h-nre h-nri h-nrl h-nrm h-nrv n-d-fault n-d-kexp n-d-kmem n-d-odone n-d-oidx n-m-rel n-s-fault o-dpclear o-dprst o-kwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-kexp r-d-kmem r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-key-write"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-key-write h-nre h-nri h-nrl h-nrm h-nrv (pay-u n-d-kexp) (pay-u n-d-kmem) (pay-u n-d-odone) (pay-u n-d-oidx) (pay-u o-dpclear) (pay-u o-kwe) r-d-cst r-d-eng r-d-kexp r-d-kmem r-d-odone r-d-oidx))))
(define prod-fact-value-write (h-nre h-nri h-nrl h-nrm h-nrv n-d-fault n-d-odone n-d-oidx n-d-vexp n-d-vmem n-m-rel n-s-fault o-dpclear o-dprst o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-value-write"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-value-write h-nre h-nri h-nrl h-nrm h-nrv (pay-u n-d-odone) (pay-u n-d-oidx) (pay-u n-d-vexp) (pay-u n-d-vmem) (pay-u o-dpclear) (pay-u o-vwe) r-d-cst r-d-eng r-d-odone r-d-oidx r-d-vexp r-d-vmem))))
(define prod-fact-stage-entry (n-d-cst n-d-eng n-d-fault n-m-rel n-s-fault o-dprst o-pstage o-sacc r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-stage-entry"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-stage-entry (pay-u n-d-cst) (pay-u n-d-eng) (pay-u o-pstage) (pay-u o-sacc) r-d-cst r-d-eng))))
(define prod-fact-key-stage-end (h-nrl n-d-cst n-d-eng n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst o-kwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-key-stage-end"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-key-stage-end h-nrl (pay-u n-d-cst) (pay-u n-d-eng) (pay-u n-d-est) (pay-u o-dpclear) (pay-u o-kwe) r-d-cst r-d-eng r-d-est r-d-odone))))
(define prod-fact-value-stage-end (h-nrl n-d-cst n-d-eng n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-value-stage-end"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-value-stage-end h-nrl (pay-u n-d-cst) (pay-u n-d-eng) (pay-u n-d-est) (pay-u o-dpclear) (pay-u o-vwe) r-d-cst r-d-eng r-d-est r-d-odone))))
(define prod-fact-value-done-entry (n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-value-done-entry"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-value-done-entry (pay-u n-d-est) (pay-u o-dpclear) r-d-cst r-d-eng r-d-est))))
(define prod-fact-key-done-entry (n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-key-done-entry"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-key-done-entry (pay-u n-d-est) (pay-u o-dpclear) r-d-cst r-d-eng r-d-est))))
(define prod-fact-value-frozen (n-d-fault n-m-rel n-s-fault o-dprst o-pstage o-sacc o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-value-frozen"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-value-frozen (pay-u o-pstage) (pay-u o-sacc) (pay-u o-vwe) r-d-est))))
(define prod-fact-key-frozen (n-d-fault n-m-rel n-s-fault o-dprst o-kwe o-pstage o-sacc r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-key-frozen"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-key-frozen (pay-u o-kwe) (pay-u o-pstage) (pay-u o-sacc) r-d-est))))
(define prod-fact-transaction (n-d-elay n-d-fault n-d-tpos n-d-tseen n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-transaction"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-transaction (pay-u n-d-elay) (pay-u n-d-tpos) (pay-u n-d-tseen) (pay-u o-dpclear) r-d-elay r-d-est r-d-tpos r-d-tseen))))
(define prod-fact-staging-stage (h-kpc n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-staging-stage"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-staging-stage h-kpc (pay-u n-d-est) (pay-u o-dpclear) r-d-eng r-d-est))))
(define prod-fact-memory-read (n-d-fault n-d-krd n-d-vrd n-m-rel n-s-fault o-dprst o-kra o-kre o-vra o-vre r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-kmem r-d-krd r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-d-vmem r-d-vrd r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-memory-read"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-memory-read (pay-u n-d-krd) (pay-u n-d-vrd) (pay-u o-kra) (pay-u o-kre) (pay-u o-vra) (pay-u o-vre) r-d-kmem r-d-krd r-d-vmem r-d-vrd))))
(define prod-fact-staging-read (n-d-eng n-d-fault n-d-iidx n-d-kvrv n-m-rel n-s-fault o-dprst o-kra o-kre o-vra o-vre r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kvrv r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-staging-read"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-staging-read (pay-u n-d-eng) (pay-u n-d-iidx) (pay-u n-d-kvrv) (pay-u o-kra) (pay-u o-kre) (pay-u o-vra) (pay-u o-vre) r-d-eng r-d-iidx r-d-kvrv))))
(define prod-fact-sequence (h-lsv h-sfpos n-d-fault n-m-rel n-s-fault n-s-pos n-s-state o-dpclear o-dprst o-sfire r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-sequence"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-sequence h-lsv h-sfpos (pay-u n-s-pos) (pay-u n-s-state) (pay-u o-dpclear) (pay-u o-sfire) r-s-pos r-s-state))))
(define prod-fact-sequence-done (h-sdf n-d-fault n-m-rel n-s-fault n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-sequence-done"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-sequence-done h-sdf (pay-u n-s-state) r-s-state))))
(define prod-fact-clear-resets (n-d-eng n-d-est n-d-fault n-m-rel n-s-fault n-s-state o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "prod-fact-clear-resets"
  (or (not (prd-guard-plain (pay-u n-d-fault) (pay-u n-m-rel) (pay-u n-s-fault) (pay-u o-dprst) r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
      (prd-p-clear-resets (pay-u n-d-eng) (pay-u n-d-est) (pay-u n-s-state) (pay-u o-dpclear)))))
(in-theory (disable prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets))

; THE CONCLUSION of the producer step lemma: every fact above.
(define prod-step-concl (h-kpc h-lsv h-nre h-nri h-nrl h-nrm h-nrv h-sdf h-sfpos i-clear i-reset-n n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kexp n-d-kmem n-d-krd n-d-kvrv n-d-lseen n-d-odone n-d-oidx n-d-sdone n-d-tpos n-d-tseen n-d-vexp n-d-vmem n-d-vrd n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dpclear o-dprst o-kra o-kre o-kwe o-layerfail o-player o-ppos o-pstage o-sacc o-sbv o-sfire o-spv o-vra o-vre o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kexp r-d-kmem r-d-krd r-d-kvrv r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-sss r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-d-vrd r-l-coll r-m-rel r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (prod-fact-layerfail o-layerfail r-d-fault r-l-coll r-s-fault)
       (prod-fact-inactive o-dprst r-m-rel)
       (prod-fact-children-reset i-reset-n o-dprst r-m-rel)
       (prod-fact-release n-m-rel r-m-rel)
       (prod-fact-staging-valid o-sbv o-spv r-d-eng r-d-kvrv r-d-sss)
       (prod-fact-clear i-clear o-dpclear)
       (prod-fact-reset n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst)
       (prod-fact-key-memory-definite n-d-kmem)
       (prod-fact-value-memory-definite n-d-vmem)
       (prod-fact-sinv n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-accept n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kvrv n-d-odone n-d-oidx n-d-tpos n-d-tseen n-m-rel n-s-fault o-dpclear o-dprst o-kwe o-player o-ppos o-pstage o-sacc o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-key-write h-nre h-nri h-nrl h-nrm h-nrv n-d-fault n-d-kexp n-d-kmem n-d-odone n-d-oidx n-m-rel n-s-fault o-dpclear o-dprst o-kwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-kexp r-d-kmem r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-value-write h-nre h-nri h-nrl h-nrm h-nrv n-d-fault n-d-odone n-d-oidx n-d-vexp n-d-vmem n-m-rel n-s-fault o-dpclear o-dprst o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-stage-entry n-d-cst n-d-eng n-d-fault n-m-rel n-s-fault o-dprst o-pstage o-sacc r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-key-stage-end h-nrl n-d-cst n-d-eng n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst o-kwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-value-stage-end h-nrl n-d-cst n-d-eng n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-value-done-entry n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-key-done-entry n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-value-frozen n-d-fault n-m-rel n-s-fault o-dprst o-pstage o-sacc o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-key-frozen n-d-fault n-m-rel n-s-fault o-dprst o-kwe o-pstage o-sacc r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-transaction n-d-elay n-d-fault n-d-tpos n-d-tseen n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-staging-stage h-kpc n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-memory-read n-d-fault n-d-krd n-d-vrd n-m-rel n-s-fault o-dprst o-kra o-kre o-vra o-vre r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-kmem r-d-krd r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-d-vmem r-d-vrd r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-staging-read n-d-eng n-d-fault n-d-iidx n-d-kvrv n-m-rel n-s-fault o-dprst o-kra o-kre o-vra o-vre r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kvrv r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-sequence h-lsv h-sfpos n-d-fault n-m-rel n-s-fault n-s-pos n-s-state o-dpclear o-dprst o-sfire r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-sequence-done h-sdf n-d-fault n-m-rel n-s-fault n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
       (prod-fact-clear-resets n-d-eng n-d-est n-d-fault n-m-rel n-s-fault n-s-state o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)))
(in-theory (disable prod-step-concl))

; ===========================================================================
; The producer step lemma for one symbolic cycle.
; ===========================================================================
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm prod-step-svtv-thm
     :svtv producer-step-run
     :svtv-spec producer-step-spec
     :input-vars :all
     :output-vars (o-dprst o-dpclear o-sacc o-pstage o-player o-ppos o-kwe o-vwe o-kre o-vre o-kra o-vra o-sbv o-spv o-sfire o-layerfail n-m-rel n-s-state n-s-layer n-s-stage n-s-pos n-s-fault n-d-eng n-d-cst n-d-clay n-d-cpos n-d-est n-d-elay n-d-tpos n-d-tseen n-d-fault n-d-lseen n-d-sdone n-d-kexp n-d-vexp n-d-odone n-d-iidx n-d-oidx n-d-kvrv n-d-kmem n-d-vmem n-d-krd n-d-vrd)
     :unsigned-byte-hyps t
     :no-integerp t
     :enable (prod-int-o-dprst-integerp prod-int-o-dpclear-integerp prod-int-o-sacc-integerp prod-int-o-pstage-integerp prod-int-o-player-integerp prod-int-o-ppos-integerp prod-int-o-kwe-integerp prod-int-o-vwe-integerp prod-int-o-kre-integerp prod-int-o-vre-integerp prod-int-o-kra-integerp prod-int-o-vra-integerp prod-int-o-sbv-integerp prod-int-o-spv-integerp prod-int-o-sfire-integerp prod-int-o-layerfail-integerp prod-int-n-m-rel-integerp prod-int-n-s-state-integerp prod-int-n-s-layer-integerp prod-int-n-s-stage-integerp prod-int-n-s-pos-integerp prod-int-n-s-fault-integerp prod-int-n-d-eng-integerp prod-int-n-d-cst-integerp prod-int-n-d-clay-integerp prod-int-n-d-cpos-integerp prod-int-n-d-est-integerp prod-int-n-d-elay-integerp prod-int-n-d-tpos-integerp prod-int-n-d-tseen-integerp prod-int-n-d-fault-integerp prod-int-n-d-lseen-integerp prod-int-n-d-sdone-integerp prod-int-n-d-kexp-integerp prod-int-n-d-vexp-integerp prod-int-n-d-odone-integerp prod-int-n-d-iidx-integerp prod-int-n-d-oidx-integerp prod-int-n-d-kvrv-integerp prod-int-n-d-kmem-integerp prod-int-n-d-vmem-integerp prod-int-n-d-krd-integerp prod-int-n-d-vrd-integerp)
     :override-vars (r-p-lock-sync r-m-rel r-l-coll r-s-state r-s-layer r-s-stage r-s-pos r-s-fault r-s-lseen r-s-sidx r-s-rexp r-d-eng r-d-cst r-d-clay r-d-cpos r-d-est r-d-elay r-d-tpos r-d-tseen r-d-fault r-d-lseen r-d-sdone r-d-kexp r-d-vexp r-d-sss r-d-odone r-d-sds r-d-nds r-d-iidx r-d-idone r-d-oidx r-d-rphase r-d-rhead r-d-rhalf r-d-rsecond r-d-arhead r-d-aslane r-d-svv r-d-gexp r-d-kvrv r-d-ephase r-d-kmem r-d-vmem r-d-krd r-d-vrd h-rterm h-childfault h-nrv h-nri h-nrm h-nre h-nrl h-ndv h-pdv h-rrv h-rri h-rrl h-rdv h-hdf h-lrv h-lrf h-arv h-arl h-adv h-llr h-lli h-grd h-kcr h-sbr h-spr h-kpc h-hsr h-rif h-paf h-haf h-hsv h-lsv h-dbusy h-sif h-sil h-spm h-siexp h-sfpos h-sdf h-srf h-srexp h-srman)
     :spec-override-vars ()
     :hyp t
     :concl (and (prod-int-o-dprst o-dprst)
          (prod-int-o-dpclear o-dpclear)
          (prod-int-o-sacc o-sacc)
          (prod-int-o-pstage o-pstage)
          (prod-int-o-player o-player)
          (prod-int-o-ppos o-ppos)
          (prod-int-o-kwe o-kwe)
          (prod-int-o-vwe o-vwe)
          (prod-int-o-kre o-kre)
          (prod-int-o-vre o-vre)
          (prod-int-o-kra o-kra)
          (prod-int-o-vra o-vra)
          (prod-int-o-sbv o-sbv)
          (prod-int-o-spv o-spv)
          (prod-int-o-sfire o-sfire)
          (prod-int-o-layerfail o-layerfail)
          (prod-int-n-m-rel n-m-rel)
          (prod-int-n-s-state n-s-state)
          (prod-int-n-s-layer n-s-layer)
          (prod-int-n-s-stage n-s-stage)
          (prod-int-n-s-pos n-s-pos)
          (prod-int-n-s-fault n-s-fault)
          (prod-int-n-d-eng n-d-eng)
          (prod-int-n-d-cst n-d-cst)
          (prod-int-n-d-clay n-d-clay)
          (prod-int-n-d-cpos n-d-cpos)
          (prod-int-n-d-est n-d-est)
          (prod-int-n-d-elay n-d-elay)
          (prod-int-n-d-tpos n-d-tpos)
          (prod-int-n-d-tseen n-d-tseen)
          (prod-int-n-d-fault n-d-fault)
          (prod-int-n-d-lseen n-d-lseen)
          (prod-int-n-d-sdone n-d-sdone)
          (prod-int-n-d-kexp n-d-kexp)
          (prod-int-n-d-vexp n-d-vexp)
          (prod-int-n-d-odone n-d-odone)
          (prod-int-n-d-iidx n-d-iidx)
          (prod-int-n-d-oidx n-d-oidx)
          (prod-int-n-d-kvrv n-d-kvrv)
          (prod-int-n-d-kmem n-d-kmem)
          (prod-int-n-d-vmem n-d-vmem)
          (prod-int-n-d-krd n-d-krd)
          (prod-int-n-d-vrd n-d-vrd)
          (prod-step-concl h-kpc h-lsv h-nre h-nri h-nrl h-nrm h-nrv h-sdf h-sfpos i-clear i-reset-n n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kexp n-d-kmem n-d-krd n-d-kvrv n-d-lseen n-d-odone n-d-oidx n-d-sdone n-d-tpos n-d-tseen n-d-vexp n-d-vmem n-d-vrd n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dpclear o-dprst o-kra o-kre o-kwe o-layerfail o-player o-ppos o-pstage o-sacc o-sbv o-sfire o-spv o-vra o-vre o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kexp r-d-kmem r-d-krd r-d-kvrv r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-sss r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-d-vrd r-l-coll r-m-rel r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))))
  (value-triple (acl2::cw "~%PROD-STEP-LEMMA proved~%")))

; ===========================================================================
; The hold run and its lemma.
; ===========================================================================
(defsvtv$ producer-hold-run
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
            :overrides (("u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" r-k-state-q :cond c-k-state-q :output p-k-state-q))
            :outputs (("u_machine.u_six_layers.u_datapath.kv_pending_complete" o-kpc)))
           (:label next
            :inputs (("reset_n_i" 1))
            :outputs (("u_machine.machine_release_q" n-m-rel)))))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export producer-hold-run-data)
  (make-event '(def-svtv-refinement producer-hold-run producer-hold-run-data
                 :svtv-spec producer-hold-spec :inclusive-overridekeys t
                 :fsm probe-fsm)))
(value-triple (acl2::cw "~%HOLD-REFINEMENT done~%"))
(defthm kv-producer-hold-run-constraints
  (equal (producer-hold-run-fsm-constraints) (join-step-run-fsm-constraints))
  :rule-classes nil)
(define hold-int-o-kpc (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "hold-int-o-kpc"
  (integerp x)))
(defthm hold-int-o-kpc-integerp
  (implies (hold-int-o-kpc x) (integerp x))
  :hints (("Goal" :in-theory (enable hold-int-o-kpc fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
; The controller's pending_complete_o, as the datapath reads it, is 0.
(define hold-fact-not-complete (o-kpc) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "hold-fact-not-complete"
  (equal o-kpc 0)))
(in-theory (disable hold-int-o-kpc hold-fact-not-complete))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm hold-svtv-thm
     :svtv producer-hold-run
     :svtv-spec producer-hold-spec
     :input-vars :all
     :output-vars (o-kpc)
     :unsigned-byte-hyps t
     :no-integerp t
     :enable (hold-int-o-kpc-integerp)
     :override-vars (r-k-state-q)
     :spec-override-vars ()
     :hyp (or (equal r-k-state-q 0) (equal r-k-state-q 1))
     :concl (and (hold-int-o-kpc o-kpc)
          (hold-fact-not-complete o-kpc))))
  (value-triple (acl2::cw "~%HOLD-LEMMA proved~%")))

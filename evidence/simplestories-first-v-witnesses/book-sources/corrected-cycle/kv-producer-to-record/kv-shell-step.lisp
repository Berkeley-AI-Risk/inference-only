; From the public STEP to the producer: the shell facts about one cycle.
;
; Written by make_step_book.py; do not edit.  Private.
;
; This book imports the certified first link and proves, about one symbolic
; cycle of the pinned RTL, facts about the token shell's state machine, in a
; step run of their own, shell-step-run.  Two lemmas: the first holds in any
; state of the shell; the second is about the shell's next state and holds
; in the seven states the third link follows (IDLE, LAYER_START, the three
; states that feed the layer block and take its result, LAYER_DONE and
; CLEAR_DRAIN), under a public CLEAR, or while the machine core is not
; released.
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
; The shell step run.
; ===========================================================================
(defsvtv$ shell-step-run
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
                     ("step_valid_i" i-step)
                     ("append_valid_i" i-append)
                     ("private_model_locked_i" 1))
            :overrides (
             ("model_lock_core_sync_q" r-p-lock-sync :cond c-p-lock-sync :output p-p-lock-sync)
             ("u_machine.machine_release_q" r-m-rel :cond c-m-rel :output p-m-rel)
             ("u_machine.u_six_layers.service_start_collision_q" r-l-coll :cond c-l-coll :output p-l-coll)
             ("u_machine.u_six_layers.u_sequence.state_q" r-s-state :cond c-s-state :output p-s-state)
             ("u_machine.u_six_layers.u_sequence.fault_q" r-s-fault :cond c-s-fault :output p-s-fault)
             ("u_machine.u_six_layers.u_sequence.stream_index_q" r-s-sidx :cond c-s-sidx :output p-s-sidx)
             ("u_machine.u_six_layers.u_sequence.result_exponent_q" r-s-rexp :cond c-s-rexp :output p-s-rexp)
             ("u_machine.u_six_layers.u_datapath.fault_q" r-d-fault :cond c-d-fault :output p-d-fault)
             ("u_machine.u_token_shell.state_q" r-t-state :cond c-t-state :output p-t-state)
             ("u_machine.u_token_shell.fail_q" r-t-fail :cond c-t-fail :output p-t-fail)
             ("u_machine.u_token_shell.ddr_owner_q" r-t-owner :cond c-t-owner :output p-t-owner)
             ("u_machine.u_token_shell.tape_count_q" r-t-tape :cond c-t-tape :output p-t-tape)
             ("u_machine.u_token_shell.committed_count_q" r-t-committed :cond c-t-committed :output p-t-committed)
             ("u_machine.u_token_shell.replay_position_q" r-t-replay :cond c-t-replay :output p-t-replay)
             ("u_machine.u_token_shell.last_hidden_valid_q" r-t-lastvalid :cond c-t-lastvalid :output p-t-lastvalid)
             ("u_machine.u_token_shell.stream_index_q" r-t-sidx :cond c-t-sidx :output p-t-sidx)
             ("u_machine.u_token_shell.capture_index_q" r-t-cidx :cond c-t-cidx :output p-t-cidx)
             ("u_machine.u_token_shell.embedding_read_q" r-t-eread :cond c-t-eread :output p-t-eread)
             ("u_machine.u_token_shell.layer5_exponent_q" r-t-l5exp :cond c-t-l5exp :output p-t-l5exp)
             ("u_machine.upstream_fail_closed_i" h-ufc :cond c-h-ufc :output p-h-ufc)
             ("u_machine.arbiter_fail" h-arbfail :cond c-h-arbfail :output p-h-arbfail)
             ("u_machine.shell_terminal_latched" h-shellterm :cond c-h-shellterm :output p-h-shellterm)
             ("u_machine.layer_fail" h-layerfail :cond c-h-layerfail :output p-h-layerfail)
             ("u_machine.u_six_layers.datapath_busy" h-dbusy :cond c-h-dbusy :output p-h-dbusy)
             ("u_machine.u_token_shell.child_fault" h-tchild :cond c-h-tchild :output p-h-tchild)
             ("u_machine.u_token_shell.lock_fault" h-tlock :cond c-h-tlock :output p-h-tlock)
             ("u_machine.u_token_shell.watchdog_fault" h-twatch :cond c-h-twatch :output p-h-twatch)
             ("u_machine.u_token_shell.public_protocol_fault" h-tpub :cond c-h-tpub :output p-h-tpub)
             ("u_machine.u_token_shell.private_protocol_fault" h-tpriv :cond c-h-tpriv :output p-h-tpriv)
             ("u_machine.u_token_shell.committed_prefixes_match" h-tcpm :cond c-h-tcpm :output p-h-tcpm)
             ("u_machine.u_token_shell.cleared_prefixes_match" h-tclpm :cond c-h-tclpm :output p-h-tclpm)
             ("u_machine.u_token_shell.embed_busy" h-tebusy :cond c-h-tebusy :output p-h-tebusy)
             ("u_machine.u_token_shell.rms_busy" h-trbusy :cond c-h-trbusy :output p-h-trbusy)
             ("u_machine.u_token_shell.argmax_busy" h-tabusy :cond c-h-tabusy :output p-h-tabusy)
             ("u_machine.u_six_layers.u_sequence.private_result_mantissa_i" h-srman :cond c-h-srman :output p-h-srman))
            :outputs (
                      ("step_ready_o" o-stepready)
                      ("append_ready_o" o-appendready)
                      ("u_machine.u_six_layers.u_sequence.start_fire" o-sfire)
                      ("u_machine.u_six_layers.u_sequence.done_fire" o-sdf)
                      ("u_machine.u_six_layers.u_sequence.fixed_position_i" o-sfpos)
                      ("u_machine.shell_fail" o-shellfail)
                      ("u_machine.u_six_layers.u_datapath.rst_n" o-dprst)
                      ("u_machine.u_six_layers.u_datapath.clear_i" o-dpclear)))
           (:label next
            :inputs (("reset_n_i" 1))
            :outputs (
             ("u_machine.machine_release_q" n-m-rel)
             ("u_machine.u_token_shell.state_q" n-t-state)))))

(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export shell-step-run-data)
  (make-event '(def-svtv-refinement shell-step-run shell-step-run-data
                 :svtv-spec shell-step-spec :inclusive-overridekeys t
                 :fsm probe-fsm)))
(value-triple (acl2::cw "~%SHL-REFINEMENT done~%"))
(defthm kv-shell-run-constraints
  (equal (shell-step-run-fsm-constraints) (join-step-run-fsm-constraints))
  :rule-classes nil)

; ===========================================================================
; The facts.
; ===========================================================================
; The public STEP and APPEND are ready only while the shell is idle.
(define shl-p-ready (o-appendready o-stepready r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (or (not (equal o-stepready 1)) (equal r-t-state 0))
      (or (not (equal o-appendready 1)) (equal r-t-state 0))))
; The sequencer's start is accepted only in the shell's LAYER_START state,
; and the position offered with it is replay_position_q[10:0].
(define shl-p-start (o-sfire o-sfpos r-t-replay r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal o-sfire 1))
      (and (equal r-t-state 5) (equal o-sfpos (loghead 11 r-t-replay)))))
; The sequencer's done is accepted only in the shell's LAYER_DONE state,
; with the sequencer in its DONE state.
(define shl-p-done (o-sdf r-s-state r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal o-sdf 1))
      (and (equal r-t-state 9) (equal r-s-state 5))))
; With the shell's fault output 0 the shell is not in its FAIL state.
(define shl-p-fail (o-shellfail r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal o-shellfail 0))
      (not (equal r-t-state 31))))
; While the machine core is not released the shell is held in reset.
(define shl-p-inactive (n-t-state r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (logbitp 1 r-m-rel) (equal n-t-state 0)))
; A cycle in which the children's reset is asserted, or after which the
; machine core is not released, leaves the shell in reset.
(define shl-p-reset (n-m-rel n-t-state o-dprst)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (equal n-t-state 0)))
; A public CLEAR leaves the shell in CLEAR_DRAIN, in FAIL, or in reset.
(define shl-p-clear (i-clear n-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal i-clear 1)) (equal n-t-state 23) (equal n-t-state 0) (equal n-t-state 31)))
; The idle shell leaves idle, other than to CLEAR_DRAIN or FAIL, only by
; an accepted public STEP.
(define shl-p-idle (h-layerfail i-step n-m-rel n-t-state o-dprst o-shellfail o-stepready r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-t-state 0) (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (equal h-layerfail 0) (equal o-shellfail 0)))
      (or (equal n-t-state 0) (equal n-t-state 23) (equal n-t-state 31)
          (and (equal i-step 1) (equal o-stepready 1)))))
; CLEAR_DRAIN is left only to idle or FAIL.
(define shl-p-drain (n-t-state r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (equal r-t-state 23))
      (equal n-t-state 23) (equal n-t-state 0) (equal n-t-state 31)))
; LAYER_START is left, without CLEAR, only to LAYER_INPUT_READ, and is
; left by the sequencer's accepted start.
(define shl-p-layer-start (n-m-rel n-t-state o-dpclear o-dprst o-sfire r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-t-state 5) (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (equal o-dpclear 0)))
      (and (or (equal n-t-state 5) (equal n-t-state 6) (equal n-t-state 31))
           (or (not (equal o-sfire 1)) (equal n-t-state 6) (equal n-t-state 31)))))
; The three states that feed the layer block and take its result lead,
; without CLEAR, only to each other or to LAYER_DONE.
(define shl-p-layer (n-m-rel n-t-state o-dpclear o-dprst r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (or (equal r-t-state 6) (equal r-t-state 7) (equal r-t-state 8))
                   (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (equal o-dpclear 0)))
      (or (equal n-t-state 6) (equal n-t-state 7) (equal n-t-state 8) (equal n-t-state 9)
          (equal n-t-state 31))))
; LAYER_DONE is left, without CLEAR, only by the sequencer's accepted
; done.
(define shl-p-layer-done (n-m-rel n-t-state o-dpclear o-dprst o-sdf r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (or (not (and (equal r-t-state 9) (and (equal o-dprst 1) (logbitp 1 n-m-rel)) (equal o-dpclear 0)))
      (or (equal n-t-state 9) (equal n-t-state 31)
          (and (equal n-t-state 10) (equal o-sdf 1)))))
(define shl0-int-o-stepready (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl0-int-o-stepready"
  (integerp x)))
(defthm shl0-int-o-stepready-integerp
  (implies (shl0-int-o-stepready x) (integerp x))
  :hints (("Goal" :in-theory (enable shl0-int-o-stepready fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl0-int-o-appendready (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl0-int-o-appendready"
  (integerp x)))
(defthm shl0-int-o-appendready-integerp
  (implies (shl0-int-o-appendready x) (integerp x))
  :hints (("Goal" :in-theory (enable shl0-int-o-appendready fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl0-int-o-sfire (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl0-int-o-sfire"
  (integerp x)))
(defthm shl0-int-o-sfire-integerp
  (implies (shl0-int-o-sfire x) (integerp x))
  :hints (("Goal" :in-theory (enable shl0-int-o-sfire fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl0-int-o-sdf (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl0-int-o-sdf"
  (integerp x)))
(defthm shl0-int-o-sdf-integerp
  (implies (shl0-int-o-sdf x) (integerp x))
  :hints (("Goal" :in-theory (enable shl0-int-o-sdf fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl0-int-o-sfpos (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl0-int-o-sfpos"
  (integerp x)))
(defthm shl0-int-o-sfpos-integerp
  (implies (shl0-int-o-sfpos x) (integerp x))
  :hints (("Goal" :in-theory (enable shl0-int-o-sfpos fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl0-int-o-shellfail (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl0-int-o-shellfail"
  (integerp x)))
(defthm shl0-int-o-shellfail-integerp
  (implies (shl0-int-o-shellfail x) (integerp x))
  :hints (("Goal" :in-theory (enable shl0-int-o-shellfail fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(in-theory (disable shl0-int-o-stepready shl0-int-o-appendready shl0-int-o-sfire shl0-int-o-sdf shl0-int-o-sfpos shl0-int-o-shellfail))

(define shl-fact-ready (o-appendready o-stepready r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-ready"
  (shl-p-ready (pay-u o-appendready) (pay-u o-stepready) r-t-state)))
(define shl-fact-start (o-sfire o-sfpos r-t-replay r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-start"
  (shl-p-start (pay-u o-sfire) (pay-u o-sfpos) r-t-replay r-t-state)))
(define shl-fact-done (o-sdf r-s-state r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-done"
  (shl-p-done (pay-u o-sdf) r-s-state r-t-state)))
(define shl-fact-fail (o-shellfail r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-fail"
  (shl-p-fail (pay-u o-shellfail) r-t-state)))
(in-theory (disable shl-fact-ready shl-fact-start shl-fact-done shl-fact-fail))
(define shl0-step-concl (o-appendready o-sdf o-sfire o-sfpos o-shellfail o-stepready r-s-state r-t-replay r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (shl-fact-ready o-appendready o-stepready r-t-state)
       (shl-fact-start o-sfire o-sfpos r-t-replay r-t-state)
       (shl-fact-done o-sdf r-s-state r-t-state)
       (shl-fact-fail o-shellfail r-t-state)))
(in-theory (disable shl0-step-concl))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm shl0-step-svtv-thm
     :svtv shell-step-run
     :svtv-spec shell-step-spec
     :input-vars :all
     :output-vars (o-stepready o-appendready o-sfire o-sdf o-sfpos o-shellfail)
     :unsigned-byte-hyps t
     :no-integerp t
     :enable (shl0-int-o-stepready-integerp shl0-int-o-appendready-integerp shl0-int-o-sfire-integerp shl0-int-o-sdf-integerp shl0-int-o-sfpos-integerp shl0-int-o-shellfail-integerp)
     :override-vars (r-p-lock-sync r-m-rel r-l-coll r-s-state r-s-fault r-s-sidx r-s-rexp r-d-fault r-t-state r-t-fail r-t-owner r-t-tape r-t-committed r-t-replay r-t-lastvalid r-t-sidx r-t-cidx r-t-eread r-t-l5exp h-ufc h-arbfail h-shellterm h-layerfail h-dbusy h-tchild h-tlock h-twatch h-tpub h-tpriv h-tcpm h-tclpm h-tebusy h-trbusy h-tabusy h-srman)
     :spec-override-vars ()
     :hyp t
     :concl (and (shl0-int-o-stepready o-stepready)
          (shl0-int-o-appendready o-appendready)
          (shl0-int-o-sfire o-sfire)
          (shl0-int-o-sdf o-sdf)
          (shl0-int-o-sfpos o-sfpos)
          (shl0-int-o-shellfail o-shellfail)
          (shl0-step-concl o-appendready o-sdf o-sfire o-sfpos o-shellfail o-stepready r-s-state r-t-replay r-t-state))))
  (value-triple (acl2::cw "~%SHL0-STEP-LEMMA proved~%")))
(define shl1-int-o-stepready (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-o-stepready"
  (integerp x)))
(defthm shl1-int-o-stepready-integerp
  (implies (shl1-int-o-stepready x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-o-stepready fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl1-int-o-sfire (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-o-sfire"
  (integerp x)))
(defthm shl1-int-o-sfire-integerp
  (implies (shl1-int-o-sfire x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-o-sfire fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl1-int-o-sdf (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-o-sdf"
  (integerp x)))
(defthm shl1-int-o-sdf-integerp
  (implies (shl1-int-o-sdf x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-o-sdf fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl1-int-o-shellfail (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-o-shellfail"
  (integerp x)))
(defthm shl1-int-o-shellfail-integerp
  (implies (shl1-int-o-shellfail x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-o-shellfail fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl1-int-o-dprst (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-o-dprst"
  (integerp x)))
(defthm shl1-int-o-dprst-integerp
  (implies (shl1-int-o-dprst x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-o-dprst fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl1-int-o-dpclear (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-o-dpclear"
  (integerp x)))
(defthm shl1-int-o-dpclear-integerp
  (implies (shl1-int-o-dpclear x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-o-dpclear fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl1-int-n-m-rel (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-n-m-rel"
  (integerp x)))
(defthm shl1-int-n-m-rel-integerp
  (implies (shl1-int-n-m-rel x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-n-m-rel fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(define shl1-int-n-t-state (x) :verify-guards nil
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl1-int-n-t-state"
  (integerp x)))
(defthm shl1-int-n-t-state-integerp
  (implies (shl1-int-n-t-state x) (integerp x))
  :hints (("Goal" :in-theory (enable shl1-int-n-t-state fgl::fgl-prove-fn)))
  :rule-classes :forward-chaining)
(in-theory (disable shl1-int-o-stepready shl1-int-o-sfire shl1-int-o-sdf shl1-int-o-shellfail shl1-int-o-dprst shl1-int-o-dpclear shl1-int-n-m-rel shl1-int-n-t-state))

(define shl-fact-inactive (n-t-state r-m-rel)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-inactive"
  (shl-p-inactive (pay-u n-t-state) r-m-rel)))
(define shl-fact-reset (n-m-rel n-t-state o-dprst)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-reset"
  (shl-p-reset (pay-u n-m-rel) (pay-u n-t-state) (pay-u o-dprst))))
(define shl-fact-clear (i-clear n-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-clear"
  (shl-p-clear i-clear (pay-u n-t-state))))
(define shl-fact-idle (h-layerfail i-step n-m-rel n-t-state o-dprst o-shellfail o-stepready r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-idle"
  (shl-p-idle h-layerfail i-step (pay-u n-m-rel) (pay-u n-t-state) (pay-u o-dprst) (pay-u o-shellfail) (pay-u o-stepready) r-t-state)))
(define shl-fact-drain (n-t-state r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-drain"
  (shl-p-drain (pay-u n-t-state) r-t-state)))
(define shl-fact-layer-start (n-m-rel n-t-state o-dpclear o-dprst o-sfire r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-layer-start"
  (shl-p-layer-start (pay-u n-m-rel) (pay-u n-t-state) (pay-u o-dpclear) (pay-u o-dprst) (pay-u o-sfire) r-t-state)))
(define shl-fact-layer (n-m-rel n-t-state o-dpclear o-dprst r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-layer"
  (shl-p-layer (pay-u n-m-rel) (pay-u n-t-state) (pay-u o-dpclear) (pay-u o-dprst) r-t-state)))
(define shl-fact-layer-done (n-m-rel n-t-state o-dpclear o-dprst o-sdf r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "shl-fact-layer-done"
  (shl-p-layer-done (pay-u n-m-rel) (pay-u n-t-state) (pay-u o-dpclear) (pay-u o-dprst) (pay-u o-sdf) r-t-state)))
(in-theory (disable shl-fact-inactive shl-fact-reset shl-fact-clear shl-fact-idle shl-fact-drain shl-fact-layer-start shl-fact-layer shl-fact-layer-done))
(define shl1-step-concl (h-layerfail i-clear i-step n-m-rel n-t-state o-dpclear o-dprst o-sdf o-sfire o-shellfail o-stepready r-m-rel r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (shl-fact-inactive n-t-state r-m-rel)
       (shl-fact-reset n-m-rel n-t-state o-dprst)
       (shl-fact-clear i-clear n-t-state)
       (shl-fact-idle h-layerfail i-step n-m-rel n-t-state o-dprst o-shellfail o-stepready r-t-state)
       (shl-fact-drain n-t-state r-t-state)
       (shl-fact-layer-start n-m-rel n-t-state o-dpclear o-dprst o-sfire r-t-state)
       (shl-fact-layer n-m-rel n-t-state o-dpclear o-dprst r-t-state)
       (shl-fact-layer-done n-m-rel n-t-state o-dpclear o-dprst o-sdf r-t-state)))
(in-theory (disable shl1-step-concl))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm shl1-step-svtv-thm
     :svtv shell-step-run
     :svtv-spec shell-step-spec
     :input-vars :all
     :output-vars (o-stepready o-sfire o-sdf o-shellfail o-dprst o-dpclear n-m-rel n-t-state)
     :unsigned-byte-hyps t
     :no-integerp t
     :enable (shl1-int-o-stepready-integerp shl1-int-o-sfire-integerp shl1-int-o-sdf-integerp shl1-int-o-shellfail-integerp shl1-int-o-dprst-integerp shl1-int-o-dpclear-integerp shl1-int-n-m-rel-integerp shl1-int-n-t-state-integerp)
     :override-vars (r-p-lock-sync r-m-rel r-l-coll r-s-state r-s-fault r-s-sidx r-s-rexp r-d-fault r-t-state r-t-fail r-t-owner r-t-tape r-t-committed r-t-replay r-t-lastvalid r-t-sidx r-t-cidx r-t-eread r-t-l5exp h-ufc h-arbfail h-shellterm h-layerfail h-dbusy h-tchild h-tlock h-twatch h-tpub h-tpriv h-tcpm h-tclpm h-tebusy h-trbusy h-tabusy h-srman)
     :spec-override-vars ()
     :hyp (or (or (equal r-t-state 0) (equal r-t-state 5) (equal r-t-state 6) (equal r-t-state 7) (equal r-t-state 8) (equal r-t-state 9) (equal r-t-state 23)) (equal i-clear 1) (not (logbitp 1 r-m-rel)))
     :concl (and (shl1-int-o-stepready o-stepready)
          (shl1-int-o-sfire o-sfire)
          (shl1-int-o-sdf o-sdf)
          (shl1-int-o-shellfail o-shellfail)
          (shl1-int-o-dprst o-dprst)
          (shl1-int-o-dpclear o-dpclear)
          (shl1-int-n-m-rel n-m-rel)
          (shl1-int-n-t-state n-t-state)
          (shl1-step-concl h-layerfail i-clear i-step n-m-rel n-t-state o-dpclear o-dprst o-sdf o-sfire o-shellfail o-stepready r-m-rel r-t-state))))
  (value-triple (acl2::cw "~%SHL1-STEP-LEMMA proved~%")))

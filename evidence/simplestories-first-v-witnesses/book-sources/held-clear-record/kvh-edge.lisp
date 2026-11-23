; The sampling edge: from the reset-reading registers to every signal and the
; whole stored state, and what the stored state then holds.
;
; Private.  See README.md in this directory.
;
; A cycle of either machine is a clock-high phase and then the clock-low
; phase, which is the same phase for both.  Write s1 for the stored state
; after a machine's clock-high phase.
;
;   kvh-edge-from-registers
;       If the two machines' reset-reading registers agree in the clock-low
;       phase, then so does every signal, and the stored states after the
;       cycle are the same.  (The clock-only registers agree by
;       kvh-clock-only; the rest follows from the register cut, kvh-settle.)
;   kvh-run-state-after-edge, kvh-reset-state-after-edge
;       What the stored state holds after the clock-low phase, from what the
;       signals were in it: the stored clock levels are low; the stored copy
;       of each reset net, guard register and loop variable is the signal's
;       low bits.
(in-package "SV")
(include-book "kvh-settle")
(include-book "kvh-clock-only")
(include-book "kvh-two-phase")

; ---------------------------------------------------------------------------
; States and inputs.
; ---------------------------------------------------------------------------
; A STATE IN RESET: the stored clock levels are low, and the stored root
; reset and the seven stored derived resets are asserted.
(define kvh-reset-state-p (st)
  :verify-guards nil
  (and (equal (kvh-env-vals (strip-cars (kvh-delay-nw (kvh-clkrstw))) st) '(0 0 0))
       (equal (kvh-env-vals (strip-cars (kvh-delay-nw (kvh-rnw))) st) '(0 0 0 0 0 0 0))))

; A RUNNING STATE: the stored clock levels are low, the three loop variables
; hold the values their loops leave (6, 2 and 6), and the stored reset nets
; and guard registers are two-valued.
(define kvh-run-state-p (st)
  :verify-guards nil
  (and (equal (kvh-env-vals (strip-cars (kvh-delay-nw (kvh-clkw))) st) '(0 0))
       (equal (kvh-env-vals (strip-cars (kvh-delay-nw (kvh-loop3w))) st) '(6 2 6))
       (kvh-2vec-list-p (kvh-zx-vals (kvh-delay-nw (kvh-rgw)) st))))

; THE GUARDS ARE DEFINITE in a cycle's sampled signals: the seven derived
; reset nets and the six registers they are computed from are two-valued.
(define kvh-guards-definite (outs)
  :verify-guards nil
  (kvh-2vec-list-p (kvh-zx-vals (kvh-rgw) outs)))

(defmacro kvh-elo (in) `(svtv-cycle-step-fsm-inputs ,in (kvh-lo)))
(defmacro kvh-outs-lo (s1 in) `(fsm-step-outs (kvh-elo ,in) ,s1 (kvh-p)))
(defmacro kvh-next-lo (s1 in) `(fsm-step (kvh-elo ,in) ,s1 (kvh-nx)))

; ---------------------------------------------------------------------------
; Checks on the design.
; ---------------------------------------------------------------------------
(define kvh-edge-check ()
  :verify-guards nil
  (and (subsetp-equal (svarlist-fix (kvh-regs))
                      (append (svarlist-fix (kvh-q0)) (svarlist-fix (kvh-q1))))
       (subsetp-equal (svarlist-fix (kvh-q1)) (svarlist-fix (kvh-qkeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-rgw))) (svarlist-fix (kvh-qkeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-rnw))) (svarlist-fix (kvh-qkeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-loop3w))) (svarlist-fix (kvh-qkeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-delay-nw (kvh-rgw))))
                      (svarlist-fix (kvh-statekeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-delay-nw (kvh-clkw))))
                      (svarlist-fix (kvh-statekeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-delay-nw (kvh-clkrstw))))
                      (svarlist-fix (kvh-statekeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-delay-nw (kvh-loop3w))))
                      (svarlist-fix (kvh-statekeys)))
       (subsetp-equal (svarlist-fix (strip-cars (kvh-delay-nw (kvh-rnw))))
                      (svarlist-fix (kvh-statekeys)))
       ;; the next-state expressions of the stored copies have the library's form
       (kvh-net-forms-ok (kvh-rgw) (kvh-nx) (kvh-vals))
       (kvh-net-forms-ok (kvh-rnw) (kvh-nx) (kvh-vals))
       (kvh-net-forms-ok (kvh-loop3w) (kvh-nx) (kvh-vals))
       (kvh-input-forms-ok (kvh-clkw) (kvh-nx))
       (kvh-input-forms-ok (kvh-clkrstw) (kvh-nx))
       ;; the stored values the two kinds of state fix
       (equal (kvh-run-consts)
              (append (pairlis$ (strip-cars (kvh-delay-nw (kvh-clkw))) '(0 0))
                      (pairlis$ (strip-cars (kvh-delay-nw (kvh-loop3w))) '(6 2 6))))
       (equal (kvh-reset-consts)
              (append (pairlis$ (strip-cars (kvh-delay-nw (kvh-clkrstw))) '(0 0 0))
                      (pairlis$ (strip-cars (kvh-delay-nw (kvh-rnw))) '(0 0 0 0 0 0 0))))
       (svarlist-p (strip-cars (kvh-delay-nw (kvh-clkw))))
       (svarlist-p (strip-cars (kvh-delay-nw (kvh-clkrstw))))
       (svarlist-p (strip-cars (kvh-delay-nw (kvh-loop3w))))
       (svarlist-p (strip-cars (kvh-delay-nw (kvh-rnw))))
       (equal (len (strip-cars (kvh-delay-nw (kvh-clkw)))) 2)
       (equal (len (strip-cars (kvh-delay-nw (kvh-clkrstw)))) 3)
       (equal (len (strip-cars (kvh-delay-nw (kvh-loop3w)))) 3)
       (equal (len (strip-cars (kvh-delay-nw (kvh-rnw)))) 7)
       ;; the clocks and the root reset are inputs
       (not (intersectp-equal (svarlist-fix (strip-cars (kvh-clkrstw))) (kvh-statekeys)))
       (not (intersectp-equal (svarlist-fix (strip-cars (kvh-clkw))) (kvh-statekeys)))
       ;; the constants of the clock-high phases
       (equal (kvh-hi-consts)
              (append '(("core_clk_i" . 1) ("app_clk_i" . 1)) (kvh-test-x)))
       (kvh-env-has (kvh-hi-consts)
                    '(("core_clk_i" . 1) ("app_clk_i" . 1) ("reset_n_i" . 1) ("clear_i" . 0)))
       (kvh-test-x-env-p (kvh-test-x))
       (equal (kvh-lo-clocks) '(("core_clk_i" . 0) ("app_clk_i" . 0)))
       (equal (kvh-clkw) '(("core_clk_i" . 1) ("app_clk_i" . 1)))
       (equal (kvh-clkrstw) '(("core_clk_i" . 1) ("app_clk_i" . 1) ("reset_n_i" . 1)))
       (equal (kvh-zx-list (kvh-loop3w) '(6 2 6)) '(6 2 6))
       (equal (len (kvh-loop3w)) 3)
       (equal (len (kvh-rnw)) 7))
  ///
  (in-theory (disable (:executable-counterpart kvh-edge-check))))

(defthm kvh-edge-check-holds
  (kvh-edge-check)
  :hints (("Goal" :in-theory '((:executable-counterpart kvh-edge-check))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The inputs of the three phases.
; ---------------------------------------------------------------------------
(local (in-theory (disable svex-env-lookup-when-not-boundp
                           svex-env-boundp-iff-member-alist-keys)))

(local (defthm kvh-lookup-of-cons-pair2
         (equal (svex-env-lookup w (cons (cons k v) a))
                (if (and (svar-p k) (equal (svar-fix w) k))
                    (4vec-fix v)
                  (svex-env-lookup w a)))
         :hints (("Goal" :in-theory (enable svex-env-lookup svex-env-fix)))))

(defthm kvh-elo-is-plain
  (implies (kv-plain-env-p in)
           (kv-plain-env-p (kvh-elo in)))
  :hints (("Goal" :use ((:instance kvh-plain-of-phase-inputs (ph (kvh-lo))))
           :in-theory (disable kvh-plain-of-phase-inputs))))

(defthm kvh-elo-has-low-clocks
  (kvh-env-has (kvh-lo-clocks) (kvh-elo in))
  :hints (("Goal" :use ((:instance kvh-edge-check-holds))
           :in-theory (enable kvh-edge-check svtv-cycle-step-fsm-inputs kvh-env-has)
           :expand ((:free (a b e) (kvh-env-has (cons a b) e))))))

(defthm kvh-ehi-c-has-high-constants
  (kvh-env-has (kvh-hi-consts) (svtv-cycle-step-fsm-inputs in (kvh-c-hi)))
  :hints (("Goal" :use ((:instance kvh-edge-check-holds))
           :in-theory (enable kvh-edge-check kvh-phase-inputs-when-not-free))))

(defthm kvh-ehi-h-has-high-constants
  (implies (kv-plain-env-p in)
           (kvh-env-has (kvh-hi-consts) (svtv-cycle-step-fsm-inputs in (kvh-h-hi))))
  :hints (("Goal" :use ((:instance kvh-edge-check-holds)
                        (:instance kvh-env-has-test-x-when-plain
                         (consts (kvh-test-x))
                         (e (svtv-cycle-step-fsm-inputs in (kvh-h-hi))))
                        (:instance kvh-plain-of-phase-inputs (ph (kvh-h-hi))))
           :in-theory (e/d (kvh-edge-check)
                           (kvh-env-has-test-x-when-plain kvh-plain-of-phase-inputs)))
          (and stable-under-simplificationp
               '(:in-theory (enable svtv-cycle-step-fsm-inputs kvh-env-has)
                 :expand ((:free (a b e) (kvh-env-has (cons a b) e)))))))

; ---------------------------------------------------------------------------
; From the reset-reading registers to everything.
; ---------------------------------------------------------------------------
(defthm kvh-edge-from-registers
  (implies (and (kv-plain-env-p in)
                (svex-envs-agree (kvh-q1)
                                 (kvh-outs-lo (kvh-st1c st in) in)
                                 (kvh-outs-lo (kvh-st1h st in) in)))
           (and (equal (kvh-outs-lo (kvh-st1c st in) in)
                       (kvh-outs-lo (kvh-st1h st in) in))
                (equal (kvh-next-lo (kvh-st1c st in) in)
                       (kvh-next-lo (kvh-st1h st in) in))))
  :hints (("Goal"
           :use ((:instance kvh-edge-check-holds)
                 (:instance kvh-clock-only-registers-agree
                  (elo (kvh-elo in))
                  (ehi1 (svtv-cycle-step-fsm-inputs in (kvh-c-hi)))
                  (ehi2 (svtv-cycle-step-fsm-inputs in (kvh-h-hi))))
                 (:instance kvh-probe-settles
                  (e (kvh-elo in)) (a (kvh-st1c st in)) (b (kvh-st1h st in)))
                 (:instance svex-envs-agree-when-subset
                  (vars (append (kvh-q0) (kvh-q1)))
                  (vars2 (kvh-regs))
                  (x (kvh-outs-lo (kvh-st1c st in) in))
                  (y (kvh-outs-lo (kvh-st1h st in) in))))
           :in-theory (e/d (kvh-edge-check)
                           (svex-envs-agree-when-subset))
           :do-not-induct t))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The stored state after the clock-low phase.
; ---------------------------------------------------------------------------
(local
 (defthm kvh-tests-unset-in-low-step
   (implies (kv-plain-env-p in)
            (kvh-tests-unset keys (fsm-step-env (kvh-elo in) s1 (kvh-nx))))
   :hints (("Goal" :use ((:instance kvh-tests-unset-of-fsm-step-env
                          (in (kvh-elo in)) (st s1) (nx (kvh-nx))))
            :in-theory (disable kvh-tests-unset-of-fsm-step-env)))
   :rule-classes nil))

; the stored clock levels after the phase are low
(local
 (defthm kvh-stored-clocks-after-edge
   (equal (kvh-env-vals (strip-cars (kvh-delay-nw (kvh-clkw))) (kvh-next-lo s1 in))
          '(0 0))
   :hints (("Goal"
            :use ((:instance kvh-edge-check-holds)
                  (:instance kvh-stored-inputs
                   (iw (kvh-clkw)) (nx (kvh-nx))
                   (env (fsm-step-env (kvh-elo in) s1 (kvh-nx))))
                  (:instance kvh-zx-vals-of-fsm-step-env-inputs
                   (nw (kvh-clkw)) (in (kvh-elo in)) (st s1) (nx (kvh-nx))))
            :in-theory (e/d (kvh-edge-check fsm-step)
                            (kvh-stored-inputs kvh-zx-vals-of-fsm-step-env-inputs)))
           (and stable-under-simplificationp
                '(:in-theory (enable svtv-cycle-step-fsm-inputs kvh-zx-vals)
                  :expand ((:free (a b e) (kvh-zx-vals (cons a b) e))))))
   :rule-classes nil))

; with the root reset asserted, so is its stored copy
(local
 (defthm kvh-stored-clocks-and-reset-after-edge
   (implies (equal (svex-env-lookup "reset_n_i" in) 0)
            (equal (kvh-env-vals (strip-cars (kvh-delay-nw (kvh-clkrstw))) (kvh-next-lo s1 in))
                   '(0 0 0)))
   :hints (("Goal"
            :use ((:instance kvh-edge-check-holds)
                  (:instance kvh-stored-inputs
                   (iw (kvh-clkrstw)) (nx (kvh-nx))
                   (env (fsm-step-env (kvh-elo in) s1 (kvh-nx))))
                  (:instance kvh-zx-vals-of-fsm-step-env-inputs
                   (nw (kvh-clkrstw)) (in (kvh-elo in)) (st s1) (nx (kvh-nx))))
            :in-theory (e/d (kvh-edge-check fsm-step)
                            (kvh-stored-inputs kvh-zx-vals-of-fsm-step-env-inputs)))
           (and stable-under-simplificationp
                '(:in-theory (enable svtv-cycle-step-fsm-inputs kvh-zx-vals)
                  :expand ((:free (a b e) (kvh-zx-vals (cons a b) e))))))
   :rule-classes nil))

; a state of either kind holds the constants the cases' expressions assume
(defthm kvh-run-state-has-consts
  (implies (kvh-run-state-p st)
           (kvh-env-has (kvh-run-consts) st))
  :hints (("Goal"
           :use ((:instance kvh-edge-check-holds)
                 (:instance kvh-env-has-of-pairlis
                  (keys (strip-cars (kvh-delay-nw (kvh-clkw)))) (vals '(0 0)) (e st))
                 (:instance kvh-env-has-of-pairlis
                  (keys (strip-cars (kvh-delay-nw (kvh-loop3w)))) (vals '(6 2 6)) (e st))
                 (:instance kvh-env-has-of-append
                  (a (pairlis$ (strip-cars (kvh-delay-nw (kvh-clkw))) '(0 0)))
                  (b (pairlis$ (strip-cars (kvh-delay-nw (kvh-loop3w))) '(6 2 6)))
                  (e st)))
           :in-theory '(kvh-edge-check kvh-run-state-p
                        (:executable-counterpart 4veclist-p)
                        (:executable-counterpart len))))
  :rule-classes nil)

(defthm kvh-reset-state-has-consts
  (implies (kvh-reset-state-p st)
           (kvh-env-has (kvh-reset-consts) st))
  :hints (("Goal"
           :use ((:instance kvh-edge-check-holds)
                 (:instance kvh-env-has-of-pairlis
                  (keys (strip-cars (kvh-delay-nw (kvh-clkrstw)))) (vals '(0 0 0)) (e st))
                 (:instance kvh-env-has-of-pairlis
                  (keys (strip-cars (kvh-delay-nw (kvh-rnw)))) (vals '(0 0 0 0 0 0 0)) (e st))
                 (:instance kvh-env-has-of-append
                  (a (pairlis$ (strip-cars (kvh-delay-nw (kvh-clkrstw))) '(0 0 0)))
                  (b (pairlis$ (strip-cars (kvh-delay-nw (kvh-rnw))) '(0 0 0 0 0 0 0)))
                  (e st)))
           :in-theory '(kvh-edge-check kvh-reset-state-p
                        (:executable-counterpart 4veclist-p)
                        (:executable-counterpart len))))
  :rule-classes nil)

; A RUNNING STATE AFTER THE EDGE: when the three loop variables were 6, 2
; and 6 in the phase and the guards were definite in it.
(defthm kvh-run-state-after-edge
  (implies (and (kv-plain-env-p in)
                (equal (kvh-env-vals (strip-cars (kvh-loop3w)) (kvh-outs-lo s1 in))
                       '(6 2 6))
                (kvh-guards-definite (kvh-outs-lo s1 in)))
           (kvh-run-state-p (svex-env-extract (kvh-statekeys) (kvh-next-lo s1 in))))
  :hints (("Goal"
           :use ((:instance kvh-edge-check-holds)
                 (:instance kvh-stored-clocks-after-edge)
                 (:instance kvh-stored-nets
                  (nw (kvh-loop3w)) (nx (kvh-nx)) (vals (kvh-vals))
                  (env (fsm-step-env (kvh-elo in) s1 (kvh-nx))))
                 (:instance kvh-stored-nets-zx
                  (nw (kvh-rgw)) (nx (kvh-nx)) (vals (kvh-vals))
                  (env (fsm-step-env (kvh-elo in) s1 (kvh-nx))))
                 (:instance kvh-zx-vals-is-zx-list
                  (nw (kvh-loop3w)) (env (kvh-outs-lo s1 in)))
                 (:instance kvh-env-vals-of-svex-env-extract
                  (keys (strip-cars (kvh-delay-nw (kvh-clkw))))
                  (keys2 (kvh-statekeys)) (env (kvh-next-lo s1 in)))
                 (:instance kvh-env-vals-of-svex-env-extract
                  (keys (strip-cars (kvh-delay-nw (kvh-loop3w))))
                  (keys2 (kvh-statekeys)) (env (kvh-next-lo s1 in)))
                 (:instance kvh-zx-vals-of-svex-env-extract
                  (nw (kvh-delay-nw (kvh-rgw)))
                  (keys (kvh-statekeys)) (env (kvh-next-lo s1 in)))
                 (:instance kvh-tests-unset-in-low-step (keys (strip-cars (kvh-loop3w))))
                 (:instance kvh-tests-unset-in-low-step (keys (strip-cars (kvh-rgw)))))
           :in-theory '(kvh-edge-check kvh-run-state-p kvh-guards-definite
                        fsm-step fsm-step-outs))
          (and stable-under-simplificationp
               '(:in-theory '(kvh-edge-check kvh-run-state-p kvh-guards-definite
                              fsm-step fsm-step-outs
                              (:executable-counterpart kvh-zx-list)))))
  :rule-classes nil)

; A STATE IN RESET AFTER THE EDGE: when the cycle's reset_n_i was 0 and the
; seven derived resets were asserted in the phase.
(defthm kvh-reset-state-after-edge
  (implies (and (kv-plain-env-p in)
                (equal (svex-env-lookup "reset_n_i" in) 0)
                (equal (kvh-zx-vals (kvh-rnw) (kvh-outs-lo s1 in))
                       '(0 0 0 0 0 0 0)))
           (kvh-reset-state-p (svex-env-extract (kvh-statekeys) (kvh-next-lo s1 in))))
  :hints (("Goal"
           :use ((:instance kvh-edge-check-holds)
                 (:instance kvh-stored-clocks-and-reset-after-edge)
                 (:instance kvh-stored-nets
                  (nw (kvh-rnw)) (nx (kvh-nx)) (vals (kvh-vals))
                  (env (fsm-step-env (kvh-elo in) s1 (kvh-nx))))
                 (:instance kvh-env-vals-of-svex-env-extract
                  (keys (strip-cars (kvh-delay-nw (kvh-clkrstw))))
                  (keys2 (kvh-statekeys)) (env (kvh-next-lo s1 in)))
                 (:instance kvh-env-vals-of-svex-env-extract
                  (keys (strip-cars (kvh-delay-nw (kvh-rnw))))
                  (keys2 (kvh-statekeys)) (env (kvh-next-lo s1 in)))
                 (:instance kvh-tests-unset-in-low-step (keys (strip-cars (kvh-rnw)))))
           :in-theory '(kvh-edge-check kvh-reset-state-p fsm-step fsm-step-outs)))
  :rule-classes nil)

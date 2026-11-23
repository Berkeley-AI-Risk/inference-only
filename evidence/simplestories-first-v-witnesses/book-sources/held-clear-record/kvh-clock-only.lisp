; The registers that read nothing but a clock: equal at the sampling edge
; whatever the two clock-high phases were given.
;
; Private.  See README.md in this directory.
;
; 396 of the 1,339 registers (1,031,647 of their 1,076,749 bits: the
; memories and the data registers) are clocked without a reset.  For them no
; solver is needed.  ACL2 evaluates two checks on the machine's expressions:
;   - with the clocks low, each of them reads only its own stored value;
;   - with the clocks high and no override, the value stored for each of
;     them reads only stored variables: no input at all.
; So after a clock-high phase and a clock-low phase from one stored state
; they hold the same values, whatever inputs the clock-high phase had.
(in-package "SV")
(include-book "kvh-machines")

(kvh-const kvh-lo-clocks '(("core_clk_i" . 0) ("app_clk_i" . 0)))
(kvh-const kvh-hi-consts
           (append '(("core_clk_i" . 1) ("app_clk_i" . 1))
                   (pairlis$ *kvh-tests* (repeat (len *kvh-tests*) (4vec-x)))))

(defthm kvh-clock-constants-are-environments
  (and (svex-env-p (kvh-lo-clocks))
       (svex-env-p (kvh-hi-consts)))
  :hints (("Goal" :in-theory '((:executable-counterpart kvh-lo-clocks)
                               (:executable-counterpart kvh-hi-consts)
                               (:executable-counterpart svex-env-p)))))

(define kvh-clock-only-check ()
  :verify-guards nil
  (and (subsetp-equal
        (svex-alist-vars (kvh-specialize (svex-alist-extract (kvh-q0) (kvh-vals))
                                         (kvh-lo-clocks)))
        (kvh-q0d))
       (subsetp-equal (svarlist-fix (kvh-q0d)) (kvh-statekeys))
       (subsetp-equal
        (svex-alist-vars (kvh-specialize (svex-alist-extract (kvh-q0d) (kvh-nx))
                                         (kvh-hi-consts)))
        (kvh-statekeys))
       (not (intersectp-equal (alist-keys (svex-env-fix (kvh-lo-clocks)))
                              (kvh-statekeys)))
       (not (intersectp-equal (alist-keys (svex-env-fix (kvh-hi-consts)))
                              (kvh-statekeys))))
  ///
  (in-theory (disable (:executable-counterpart kvh-clock-only-check))))

(defthm kvh-clock-only-check-holds
  (kvh-clock-only-check)
  :hints (("Goal" :in-theory '((:executable-counterpart kvh-clock-only-check))))
  :rule-classes nil)

; the stored values after the clock-high phase
(local
 (defthm kvh-clock-only-stored
   (implies (and (kvh-env-has (kvh-hi-consts) ehi1)
                 (kvh-env-has (kvh-hi-consts) ehi2))
            (equal (svex-env-extract (kvh-q0d) (fsm-step ehi1 st (kvh-nx)))
                   (svex-env-extract (kvh-q0d) (fsm-step ehi2 st (kvh-nx)))))
   :hints (("Goal"
            :use ((:instance kvh-clock-only-check-holds)
                  (:instance kvh-eval-of-specialize
                   (x (svex-alist-extract (kvh-q0d) (kvh-nx)))
                   (consts (kvh-hi-consts))
                   (env (fsm-step-env ehi1 st (kvh-nx))))
                  (:instance kvh-eval-of-specialize
                   (x (svex-alist-extract (kvh-q0d) (kvh-nx)))
                   (consts (kvh-hi-consts))
                   (env (fsm-step-env ehi2 st (kvh-nx))))
                  (:instance kvh-env-has-of-fsm-step-env-inputs
                   (consts (kvh-hi-consts)) (in ehi1) (nx (kvh-nx)))
                  (:instance kvh-env-has-of-fsm-step-env-inputs
                   (consts (kvh-hi-consts)) (in ehi2) (nx (kvh-nx)))
                  (:instance svex-alist-eval-when-envs-agree
                   (x (kvh-specialize (svex-alist-extract (kvh-q0d) (kvh-nx)) (kvh-hi-consts)))
                   (env1 (fsm-step-env ehi1 st (kvh-nx)))
                   (env2 (fsm-step-env ehi2 st (kvh-nx))))
                  (:instance kvh-step-envs-agree-on-state
                   (vars (svex-alist-vars
                          (kvh-specialize (svex-alist-extract (kvh-q0d) (kvh-nx))
                                          (kvh-hi-consts))))
                   (nx (kvh-nx)) (st1 st) (st2 st) (in1 ehi1) (in2 ehi2)))
            :in-theory (e/d (kvh-clock-only-check fsm-step)
                            (kvh-eval-of-specialize
                             kvh-env-has-of-fsm-step-env-inputs
                             svex-envs-agree-when-subset))
            :do-not-induct t))
   :rule-classes nil))

(defthm kvh-clock-only-registers-agree
  (implies (and (kvh-env-has (kvh-lo-clocks) elo)
                (kvh-env-has (kvh-hi-consts) ehi1)
                (kvh-env-has (kvh-hi-consts) ehi2))
           (svex-envs-agree (kvh-q0)
                            (fsm-step-outs elo (fsm-step ehi1 st (kvh-nx)) (kvh-p))
                            (fsm-step-outs elo (fsm-step ehi2 st (kvh-nx)) (kvh-p))))
  :hints (("Goal"
           :use ((:instance kvh-clock-only-check-holds)
                 (:instance kvh-clock-only-stored)
                 (:instance kvh-agree-when-extract-equal
                  (keys (kvh-q0d))
                  (a (fsm-step ehi1 st (kvh-nx)))
                  (b (fsm-step ehi2 st (kvh-nx))))
                 (:instance kvh-agree-when-extract-equal
                  (keys (kvh-q0))
                  (a (fsm-step-outs elo (fsm-step ehi1 st (kvh-nx)) (kvh-p)))
                  (b (fsm-step-outs elo (fsm-step ehi2 st (kvh-nx)) (kvh-p))))
                 (:instance kvh-eval-of-specialize
                  (x (svex-alist-extract (kvh-q0) (kvh-vals)))
                  (consts (kvh-lo-clocks))
                  (env (fsm-step-env elo (fsm-step ehi1 st (kvh-nx)) (kvh-nx))))
                 (:instance kvh-eval-of-specialize
                  (x (svex-alist-extract (kvh-q0) (kvh-vals)))
                  (consts (kvh-lo-clocks))
                  (env (fsm-step-env elo (fsm-step ehi2 st (kvh-nx)) (kvh-nx))))
                 (:instance kvh-env-has-of-fsm-step-env-inputs
                  (consts (kvh-lo-clocks)) (in elo) (nx (kvh-nx))
                  (st (fsm-step ehi1 st (kvh-nx))))
                 (:instance kvh-env-has-of-fsm-step-env-inputs
                  (consts (kvh-lo-clocks)) (in elo) (nx (kvh-nx))
                  (st (fsm-step ehi2 st (kvh-nx))))
                 (:instance svex-alist-eval-when-envs-agree
                  (x (kvh-specialize (svex-alist-extract (kvh-q0) (kvh-vals)) (kvh-lo-clocks)))
                  (env1 (fsm-step-env elo (fsm-step ehi1 st (kvh-nx)) (kvh-nx)))
                  (env2 (fsm-step-env elo (fsm-step ehi2 st (kvh-nx)) (kvh-nx))))
                 (:instance svex-envs-agree-when-subset
                  (vars (kvh-q0d))
                  (vars2 (svex-alist-vars
                          (kvh-specialize (svex-alist-extract (kvh-q0) (kvh-vals))
                                          (kvh-lo-clocks))))
                  (x (fsm-step-env elo (fsm-step ehi1 st (kvh-nx)) (kvh-nx)))
                  (y (fsm-step-env elo (fsm-step ehi2 st (kvh-nx)) (kvh-nx))))
                 (:instance kvh-step-envs-agree-on-state
                  (vars (kvh-q0d)) (nx (kvh-nx))
                  (st1 (fsm-step ehi1 st (kvh-nx)))
                  (st2 (fsm-step ehi2 st (kvh-nx)))
                  (in1 elo) (in2 elo)))
           :in-theory (e/d (kvh-clock-only-check fsm-step-outs)
                           (kvh-eval-of-specialize
                            kvh-env-has-of-fsm-step-env-inputs
                            svex-envs-agree-when-subset))
           :do-not-induct t))
  :rule-classes nil)

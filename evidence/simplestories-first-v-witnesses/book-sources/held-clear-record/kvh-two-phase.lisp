; The registers at the sampling edge of a cycle, as expressions over the
; state before the cycle, for each of the two clock models.
;
; Private.  See README.md in this directory.
;
;   (kvh-oc consts xlo)       the corrected-cycle machine
;   (kvh-oh consts xhi xlo)   the held-input machine
;
; Each is an alist of expressions for the reset-reading registers and the
; seven reset nets in the clock-low phase.  consts are stored values the
; state is assumed to hold; xlo and xhi are input values the cycle is
; assumed to have (the case: reset_n_i, clear_i, and no override).  The
; stored variables that are not kept between the phases are fresh variables
; in these expressions: the two machines get different ones.
;
;   kvh-eval-of-oc, kvh-eval-of-oh
;       WHAT THE EXPRESSIONS MEAN.  Evaluated in the environment (kvh-e* st
;       in), each alist gives the values those signals have in the clock-low
;       phase of that machine's cycle from state st with inputs in.
;
; The solver proves statements about the expressions for every environment
; (the four kvh-case books); these two theorems turn them into statements
; about steps of the machines.
(in-package "SV")
(include-book "kvh-machines")

; the inputs of a case: the root reset, CLEAR, and no override
(define kvh-x ((r 4vec-p) (c 4vec-p))
  :returns (x svex-env-p)
  (append (list (cons "reset_n_i" (4vec-fix r)) (cons "clear_i" (4vec-fix c)))
          (svex-env-fix (kvh-test-x)))
  ///
  (in-theory (disable (:executable-counterpart kvh-x))))

(local
 (defthm kvh-test-x-is-unset-tests
   (kvh-test-x-env-p (kvh-test-x))
   :hints (("Goal" :in-theory '((:executable-counterpart kvh-test-x)
                                (:executable-counterpart kvh-test-x-env-p))))))

(defthm kvh-inputs-have-case
  (implies (and (kv-plain-env-p in)
                (equal (svex-env-lookup "reset_n_i" in) (4vec-fix r))
                (equal (svex-env-lookup "clear_i" in) (4vec-fix c)))
           (kvh-env-has (kvh-x r c) in))
  :hints (("Goal" :in-theory (enable kvh-x kvh-env-has))))

(define kvh-oc ((consts svex-env-p) (xlo svex-env-p))
  :returns (o svex-alist-p)
  :verify-guards nil
  (kvh-two-phase (kvh-p) (kvh-qvals)
                 (kvh-prev-st (kvh-statekeys) consts)
                 (kvh-c-hi)
                 (kvh-phase-with (kvh-lo) xlo)
                 (kvh-kept) 2))

(define kvh-oh ((consts svex-env-p) (xhi svex-env-p) (xlo svex-env-p))
  :returns (o svex-alist-p)
  :verify-guards nil
  (kvh-two-phase (kvh-p) (kvh-qvals)
                 (kvh-prev-st (kvh-statekeys) consts)
                 (kvh-phase-with (kvh-h-hi) xhi)
                 (kvh-phase-with (kvh-lo) xlo)
                 (kvh-kept) 3))

; the state after the clock-high phase of each machine
(defmacro kvh-st1c (st in)
  `(fsm-step (svtv-cycle-step-fsm-inputs ,in (kvh-c-hi)) ,st (kvh-nx)))
(defmacro kvh-st1h (st in)
  `(fsm-step (svtv-cycle-step-fsm-inputs ,in (kvh-h-hi)) ,st (kvh-nx)))
; THE ENVIRONMENT the expressions are evaluated in
(defmacro kvh-e* (st in)
  `(kvh-estar (kvh-statekeys) (kvh-kept) (kvh-st1c ,st ,in) (kvh-st1h ,st ,in) ,st ,in))

(define kvh-two-phase-check ()
  :verify-guards nil
  (and (subsetp-equal (svex-alist-vars (kvh-nx))
                      (append (kvh-statekeys) (svarlist-fix (kvh-nonstate))))
       (subsetp-equal (svex-alist-vars (kvh-qvals))
                      (append (kvh-statekeys) (svarlist-fix (kvh-nonstate))))
       (no-duplicatesp-equal (kvh-tagged (kvh-statekeys) (kvh-kept) 2))
       (no-duplicatesp-equal (kvh-tagged (kvh-statekeys) (kvh-kept) 3))
       (not (intersectp-equal (kvh-tagged (kvh-statekeys) (kvh-kept) 3)
                              (kvh-tagged (kvh-statekeys) (kvh-kept) 2)))
       (not (intersectp-equal (svarlist-fix (kvh-statekeys))
                              (kvh-tagged (kvh-statekeys) (kvh-kept) 2)))
       (not (intersectp-equal (svarlist-fix (kvh-statekeys))
                              (kvh-tagged (kvh-statekeys) (kvh-kept) 3)))
       (not (intersectp-equal (svarlist-fix (kvh-nonstate))
                              (svarlist-fix (kvh-statekeys))))
       (not (intersectp-equal (svarlist-fix (kvh-nonstate))
                              (kvh-tagged (kvh-statekeys) (kvh-kept) 2)))
       (not (intersectp-equal (svarlist-fix (kvh-nonstate))
                              (kvh-tagged (kvh-statekeys) (kvh-kept) 3))))
  ///
  (in-theory (disable (:executable-counterpart kvh-two-phase-check))))

(defthm kvh-two-phase-check-holds
  (kvh-two-phase-check)
  :hints (("Goal" :in-theory '((:executable-counterpart kvh-two-phase-check))))
  :rule-classes nil)

(local (in-theory (disable kvh-eval-of-lookup-or-x
                           svex-env-lookup-of-svex-alist-eval
                           kvh-estar-prev-st
                           kvh-estar-phase-inputs
                           kvh-estar-free-ok-2
                           kvh-estar-free-ok-3
                           kvh-phase-inputs-when-not-free
                           svex-envs-agree-when-subset)))

(defthm kvh-eval-of-oc
  (implies (and (kvh-env-has consts st)
                (kvh-env-has xlo in))
           (equal (svex-alist-eval (kvh-oc consts xlo) (kvh-e* st in))
                  (svex-alist-eval (kvh-qvals)
                                   (fsm-step-env (svtv-cycle-step-fsm-inputs in (kvh-lo))
                                                 (kvh-st1c st in)
                                                 (kvh-nx)))))
  :hints (("Goal"
           :use ((:instance kvh-two-phase-check-holds)
                 (:instance kvh-eval-of-two-phase
                  (x (kvh-p)) (qvals (kvh-qvals))
                  (prev (kvh-prev-st (kvh-statekeys) consts))
                  (hi (kvh-c-hi)) (lo (kvh-phase-with (kvh-lo) xlo))
                  (kept (kvh-kept)) (tag 2)
                  (env (kvh-e* st in))
                  (nonstate (kvh-nonstate))
                  (ehi (svtv-cycle-step-fsm-inputs in (kvh-c-hi)))
                  (elo (svtv-cycle-step-fsm-inputs in (kvh-lo))))
                 (:instance kvh-estar-prev-st
                  (keys (kvh-statekeys)) (kept (kvh-kept))
                  (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in)))
                 (:instance kvh-estar-phase-inputs
                  (ph (kvh-lo)) (extra xlo)
                  (ns2 (kvh-nonstate)) (nonstate (kvh-nonstate))
                  (keys (kvh-statekeys)) (kept (kvh-kept))
                  (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in)))
                 (:instance kvh-estar-free-ok-2
                  (keys2 (kvh-statekeys)) (keys (kvh-statekeys)) (kept (kvh-kept))
                  (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in)))
                 (:instance kvh-phase-inputs-when-not-free
                  (ph (kvh-c-hi)) (e1 (kvh-e* st in)))
                 (:instance kvh-phase-inputs-when-not-free
                  (ph (kvh-c-hi)) (e1 in)))
           :in-theory (enable kvh-oc kvh-two-phase-check)
           :do-not-induct t))
  :rule-classes nil)

(defthm kvh-eval-of-oh
  (implies (and (kvh-env-has consts st)
                (kvh-env-has xhi in)
                (kvh-env-has xlo in))
           (equal (svex-alist-eval (kvh-oh consts xhi xlo) (kvh-e* st in))
                  (svex-alist-eval (kvh-qvals)
                                   (fsm-step-env (svtv-cycle-step-fsm-inputs in (kvh-lo))
                                                 (kvh-st1h st in)
                                                 (kvh-nx)))))
  :hints (("Goal"
           :use ((:instance kvh-two-phase-check-holds)
                 (:instance kvh-eval-of-two-phase
                  (x (kvh-p)) (qvals (kvh-qvals))
                  (prev (kvh-prev-st (kvh-statekeys) consts))
                  (hi (kvh-phase-with (kvh-h-hi) xhi))
                  (lo (kvh-phase-with (kvh-lo) xlo))
                  (kept (kvh-kept)) (tag 3)
                  (env (kvh-e* st in))
                  (nonstate (kvh-nonstate))
                  (ehi (svtv-cycle-step-fsm-inputs in (kvh-h-hi)))
                  (elo (svtv-cycle-step-fsm-inputs in (kvh-lo))))
                 (:instance kvh-estar-prev-st
                  (keys (kvh-statekeys)) (kept (kvh-kept))
                  (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in)))
                 (:instance kvh-estar-phase-inputs
                  (ph (kvh-lo)) (extra xlo)
                  (ns2 (kvh-nonstate)) (nonstate (kvh-nonstate))
                  (keys (kvh-statekeys)) (kept (kvh-kept))
                  (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in)))
                 (:instance kvh-estar-phase-inputs
                  (ph (kvh-h-hi)) (extra xhi)
                  (ns2 (kvh-nonstate)) (nonstate (kvh-nonstate))
                  (keys (kvh-statekeys)) (kept (kvh-kept))
                  (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in)))
                 (:instance kvh-estar-free-ok-3
                  (keys2 (kvh-statekeys)) (keys (kvh-statekeys)) (kept (kvh-kept))
                  (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in))))
           :in-theory (enable kvh-oh kvh-two-phase-check)
           :do-not-induct t))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The solver is given a free environment: it must not open the library's
; environment functions, and it is told how to build an environment from a
; satisfying assignment, so that ACL2 can evaluate a counterexample.
; ---------------------------------------------------------------------------
(fgl::disable-definition sv::svex-env-fix$inline)
(fgl::disable-definition sv::svex-env-lookup)
(fgl::def-ctrex-rule svex-env-fix-ctrex-rule
  :match ((val (sv::svex-env-fix x)))
  :assign val
  :assigned-var x
  :ruletype :elim)

; The two clock models agree at every sampling edge of a legal history.
;
; Private.  See README.md in this directory.
;
;   kvh-held-machine-agrees-with-corrected-cycle
;       THE CORRESPONDENCE.  Let initst be a state in reset and envs a list
;       of input environments, one per clock cycle, such that
;         - the first cycle asserts reset;
;         - in every cycle the inputs set no override, and reset_n_i and
;           clear_i are 0 or 1;
;         - once reset_n_i has been 1 it stays 1;
;         - in every cycle of the held-input machine's execution the seven
;           derived reset nets and the six registers they are computed from
;           are two-valued.
;       Then the held-input machine and the corrected-cycle machine, started
;       in initst and given envs, produce the same list of sampled signals:
;       (fsm-eval envs initst (probe-fsm-held)) = (fsm-eval envs initst (probe-fsm)).
;       Every one of the 4,515 signals, in every cycle.
;
; How it is proved.  One cycle is two phase steps.  kvh-case-* (solver, four
; cases) give the reset-reading registers at the sampling edge; kvh-edge
; extends that to every signal and to the stored state, and re-establishes
; what the next cycle's case assumes.  The rest is induction on the list of
; cycles.
(in-package "SV")
(include-book "kvh-edge")
(include-book "kvh-case-run-0")
(include-book "kvh-case-run-1")
(include-book "kvh-case-reset-0")
(include-book "kvh-case-reset-1")
(local (include-book "std/lists/sets" :dir :system))

(local (in-theory (disable svex-env-lookup-when-not-boundp
                           svex-env-boundp-iff-member-alist-keys
                           svex-env-lookup-of-svex-alist-eval
                           kvh-eval-of-lookup-or-x
                           svex-envs-agree-when-subset)))

; ---------------------------------------------------------------------------
; The environment of the cases' expressions agrees with the state on stored
; variables.
; ---------------------------------------------------------------------------
(local (defthm kvhc-not-member-when-not-intersectp
         (implies (and (not (intersectp-equal x y))
                       (member-equal v x))
                  (not (member-equal v y)))))

(local (defun kvhc-cdr-ind (x) (if (atom x) x (kvhc-cdr-ind (cdr x)))))

(local
 (defthm kvh-estar-agrees-with-state
   (implies (and (subsetp-equal (svarlist-fix keys2) (svarlist-fix keys))
                 (not (intersectp-equal (svarlist-fix keys) (kvh-tagged keys kept 2)))
                 (not (intersectp-equal (svarlist-fix keys) (kvh-tagged keys kept 3))))
            (svex-envs-agree keys2 (kvh-estar keys kept st1c st1h st in) st))
   :hints (("Goal" :induct (kvhc-cdr-ind keys2)
            :in-theory (e/d (svex-envs-agree svarlist-fix) (kvh-estar))))
   :rule-classes nil))

; ---------------------------------------------------------------------------
; The four cases, as statements about a cycle's two phase steps.
; ---------------------------------------------------------------------------
(defmacro kvh-outs-c (st in) `(kvh-outs-lo (kvh-st1c ,st ,in) ,in))
(defmacro kvh-outs-h (st in) `(kvh-outs-lo (kvh-st1h ,st ,in) ,in))

(defmacro kvh-def-run-edge (c)
  (let ((name (intern-in-package-of-symbol
               (concatenate 'string "KVH-RUN-" (coerce (explode-atom c 10) 'string) "-EDGE")
               'kvh-p))
        (reg (intern-in-package-of-symbol
              (concatenate 'string "KVH-RUN-" (coerce (explode-atom c 10) 'string) "-REGISTERS")
              'kvh-p)))
    `(defthm ,name
       (implies (and (kvh-run-state-p st)
                     (kv-plain-env-p in)
                     (equal (svex-env-lookup "reset_n_i" in) 1)
                     (equal (svex-env-lookup "clear_i" in) ,c)
                     (kvh-guards-definite (kvh-outs-h st in)))
                (and (svex-envs-agree (kvh-q1) (kvh-outs-c st in) (kvh-outs-h st in))
                     (equal (kvh-env-vals (strip-cars (kvh-loop3w)) (kvh-outs-h st in))
                            '(6 2 6))))
       :hints (("Goal"
                :use ((:instance ,reg (env (kvh-e* st in)))
                      (:instance kvh-eval-of-oc
                       (consts (kvh-run-consts)) (xlo (kvh-x 1 ,c)))
                      (:instance kvh-eval-of-oh
                       (consts (kvh-run-consts)) (xhi (kvh-x 1 ,c)) (xlo (kvh-x 1 ,c)))
                      (:instance kvh-run-state-has-consts)
                      (:instance kvh-inputs-have-case (r 1) (c ,c))
                      (:instance kvh-edge-check-holds)
                      (:instance kvh-two-phase-check-holds)
                      (:instance kvh-zx-vals-when-agree
                       (nw (kvh-delay-nw (kvh-rgw))) (a (kvh-e* st in)) (b st))
                      (:instance kvh-estar-agrees-with-state
                       (keys2 (strip-cars (kvh-delay-nw (kvh-rgw))))
                       (keys (kvh-statekeys)) (kept (kvh-kept))
                       (st1c (kvh-st1c st in)) (st1h (kvh-st1h st in)))
                      (:instance kvh-zx-vals-of-svex-env-extract
                       (nw (kvh-rgw)) (keys (kvh-qkeys))
                       (env (kvh-outs-h st in)))
                      (:instance kvh-env-vals-of-svex-env-extract
                       (keys (kvh-q1)) (keys2 (kvh-qkeys)) (env (kvh-outs-c st in)))
                      (:instance kvh-env-vals-of-svex-env-extract
                       (keys (kvh-q1)) (keys2 (kvh-qkeys)) (env (kvh-outs-h st in)))
                      (:instance kvh-env-vals-of-svex-env-extract
                       (keys (strip-cars (kvh-loop3w))) (keys2 (kvh-qkeys))
                       (env (kvh-outs-h st in)))
                      (:instance kvh-agree-when-env-vals-equal
                       (keys (kvh-q1)) (a (kvh-outs-c st in)) (b (kvh-outs-h st in))))
                :in-theory (e/d (kvh-edge-check kvh-two-phase-check kvh-run-state-p
                                 kvh-guards-definite fsm-step-outs)
                                (kvh-zx-vals-of-svex-env-extract
                                 kvh-env-vals-of-svex-env-extract))
                :do-not-induct t))
       :rule-classes nil)))

(kvh-def-run-edge 0)
(kvh-def-run-edge 1)

(defmacro kvh-def-reset-edge (c)
  (let ((name (intern-in-package-of-symbol
               (concatenate 'string "KVH-RESET-" (coerce (explode-atom c 10) 'string) "-EDGE")
               'kvh-p))
        (reg (intern-in-package-of-symbol
              (concatenate 'string "KVH-RESET-" (coerce (explode-atom c 10) 'string) "-REGISTERS")
              'kvh-p)))
    `(defthm ,name
       (implies (and (kvh-reset-state-p st)
                     (kv-plain-env-p in)
                     (equal (svex-env-lookup "reset_n_i" in) 0)
                     (equal (svex-env-lookup "clear_i" in) ,c)
                     (kvh-guards-definite (kvh-outs-h st in)))
                (and (svex-envs-agree (kvh-q1) (kvh-outs-c st in) (kvh-outs-h st in))
                     (equal (kvh-env-vals (strip-cars (kvh-loop3w)) (kvh-outs-h st in))
                            '(6 2 6))
                     (equal (kvh-zx-vals (kvh-rnw) (kvh-outs-h st in))
                            '(0 0 0 0 0 0 0))))
       :hints (("Goal"
                :use ((:instance ,reg (env (kvh-e* st in)))
                      (:instance kvh-eval-of-oc
                       (consts (kvh-reset-consts)) (xlo (kvh-x 0 ,c)))
                      (:instance kvh-eval-of-oh
                       (consts (kvh-reset-consts)) (xhi (kvh-x 0 ,c)) (xlo (kvh-x 0 ,c)))
                      (:instance kvh-reset-state-has-consts)
                      (:instance kvh-inputs-have-case (r 0) (c ,c))
                      (:instance kvh-edge-check-holds)
                      (:instance kvh-zx-vals-of-svex-env-extract
                       (nw (kvh-rgw)) (keys (kvh-qkeys))
                       (env (kvh-outs-h st in)))
                      (:instance kvh-zx-vals-of-svex-env-extract
                       (nw (kvh-rnw)) (keys (kvh-qkeys))
                       (env (kvh-outs-h st in)))
                      (:instance kvh-env-vals-of-svex-env-extract
                       (keys (kvh-q1)) (keys2 (kvh-qkeys)) (env (kvh-outs-c st in)))
                      (:instance kvh-env-vals-of-svex-env-extract
                       (keys (kvh-q1)) (keys2 (kvh-qkeys)) (env (kvh-outs-h st in)))
                      (:instance kvh-env-vals-of-svex-env-extract
                       (keys (strip-cars (kvh-loop3w))) (keys2 (kvh-qkeys))
                       (env (kvh-outs-h st in)))
                      (:instance kvh-agree-when-env-vals-equal
                       (keys (kvh-q1)) (a (kvh-outs-c st in)) (b (kvh-outs-h st in))))
                :in-theory (e/d (kvh-edge-check kvh-guards-definite fsm-step-outs)
                                (kvh-zx-vals-of-svex-env-extract
                                 kvh-env-vals-of-svex-env-extract))
                :do-not-induct t))
       :rule-classes nil)))

(kvh-def-reset-edge 0)
(kvh-def-reset-edge 1)

; ---------------------------------------------------------------------------
; A cycle of each machine, as two phase steps.
; ---------------------------------------------------------------------------
(defthm kvh-held-cycle-outs
  (equal (fsm-step-outs in st (probe-fsm-held))
         (kvh-outs-h st in))
  :hints (("Goal" :use ((:instance kvh-cycle-step-outs
                         (hi (kvh-h-hi)) (lo (kvh-lo)) (x (kvh-p)) (simp nil)))
           :in-theory '(probe-fsm-held kvh-phase-flags))))

(defthm kvh-held-cycle-next
  (equal (fsm-step in st (fsm->nextstate (probe-fsm-held)))
         (svex-env-extract (kvh-statekeys) (kvh-next-lo (kvh-st1h st in) in)))
  :hints (("Goal" :use ((:instance kvh-cycle-step
                         (hi (kvh-h-hi)) (lo (kvh-lo)) (x (kvh-p)) (simp nil)))
           :in-theory '(probe-fsm-held))))

(local
 (defthm kvh-corrected-cycle-outs-lemma
   (equal (fsm-step-outs in st (fsm-to-cycle (list (kvh-c-hi) (kvh-lo)) (kvh-p) nil))
          (kvh-outs-c st in))
   :hints (("Goal" :use ((:instance kvh-cycle-step-outs
                          (hi (kvh-c-hi)) (lo (kvh-lo)) (x (kvh-p)) (simp nil)))
            :in-theory '(kvh-phase-flags)))
   :rule-classes nil))

(local
 (defthm kvh-corrected-cycle-next-lemma
   (equal (fsm-step in st (fsm->nextstate (fsm-to-cycle (list (kvh-c-hi) (kvh-lo)) (kvh-p) nil)))
          (svex-env-extract (kvh-statekeys) (kvh-next-lo (kvh-st1c st in) in)))
   :hints (("Goal" :use ((:instance kvh-cycle-step
                          (hi (kvh-c-hi)) (lo (kvh-lo)) (x (kvh-p)) (simp nil)))
            :in-theory nil))
   :rule-classes nil))

(defthm kvh-corrected-cycle-outs
  (equal (fsm-step-outs in st (probe-fsm))
         (kvh-outs-c st in))
  :hints (("Goal" :use ((:instance probe-fsm-is-the-corrected-cycle)
                        (:instance kvh-corrected-cycle-outs-lemma))
           :in-theory nil)))

(defthm kvh-corrected-cycle-next
  (equal (fsm-step in st (fsm->nextstate (probe-fsm)))
         (svex-env-extract (kvh-statekeys) (kvh-next-lo (kvh-st1c st in) in)))
  :hints (("Goal" :use ((:instance probe-fsm-is-the-corrected-cycle)
                        (:instance kvh-corrected-cycle-next-lemma))
           :in-theory nil)))

; ---------------------------------------------------------------------------
; One cycle.
; ---------------------------------------------------------------------------
; a running cycle's inputs: no override, reset released, CLEAR 0 or 1
(define kvh-run-input-p (in)
  :verify-guards nil
  (and (kv-plain-env-p in)
       (equal (svex-env-lookup "reset_n_i" in) 1)
       (or (equal (svex-env-lookup "clear_i" in) 0)
           (equal (svex-env-lookup "clear_i" in) 1))))

; a reset cycle's inputs: no override, reset asserted, CLEAR 0 or 1
(define kvh-reset-input-p (in)
  :verify-guards nil
  (and (kv-plain-env-p in)
       (equal (svex-env-lookup "reset_n_i" in) 0)
       (or (equal (svex-env-lookup "clear_i" in) 0)
           (equal (svex-env-lookup "clear_i" in) 1))))

(local (in-theory (disable kvh-held-cycle-outs kvh-held-cycle-next
                           kvh-corrected-cycle-outs kvh-corrected-cycle-next)))

; A RUNNING CYCLE: same signals, same next state, and the next state is
; again a running state.
(defthm kvh-run-cycle
  (implies (and (kvh-run-state-p st)
                (kvh-run-input-p in)
                (kvh-guards-definite (fsm-step-outs in st (probe-fsm-held))))
           (and (equal (fsm-step-outs in st (probe-fsm-held))
                       (fsm-step-outs in st (probe-fsm)))
                (equal (fsm-step in st (fsm->nextstate (probe-fsm-held)))
                       (fsm-step in st (fsm->nextstate (probe-fsm))))
                (kvh-run-state-p (fsm-step in st (fsm->nextstate (probe-fsm-held))))))
  :hints (("Goal"
           :use ((:instance kvh-run-0-edge)
                 (:instance kvh-run-1-edge)
                 (:instance kvh-edge-from-registers)
                 (:instance kvh-run-state-after-edge (s1 (kvh-st1h st in)))
                 (:instance kvh-held-cycle-outs)
                 (:instance kvh-held-cycle-next)
                 (:instance kvh-corrected-cycle-outs)
                 (:instance kvh-corrected-cycle-next))
           :in-theory '(kvh-run-input-p)))
  :rule-classes nil)

; A RESET CYCLE from a state in reset: same signals, same next state, and
; the next state is both a state in reset and a running state.
(defthm kvh-reset-cycle
  (implies (and (kvh-reset-state-p st)
                (kvh-reset-input-p in)
                (kvh-guards-definite (fsm-step-outs in st (probe-fsm-held))))
           (and (equal (fsm-step-outs in st (probe-fsm-held))
                       (fsm-step-outs in st (probe-fsm)))
                (equal (fsm-step in st (fsm->nextstate (probe-fsm-held)))
                       (fsm-step in st (fsm->nextstate (probe-fsm))))
                (kvh-reset-state-p (fsm-step in st (fsm->nextstate (probe-fsm-held))))
                (kvh-run-state-p (fsm-step in st (fsm->nextstate (probe-fsm-held))))))
  :hints (("Goal"
           :use ((:instance kvh-reset-0-edge)
                 (:instance kvh-reset-1-edge)
                 (:instance kvh-edge-from-registers)
                 (:instance kvh-run-state-after-edge (s1 (kvh-st1h st in)))
                 (:instance kvh-reset-state-after-edge (s1 (kvh-st1h st in)))
                 (:instance kvh-held-cycle-outs)
                 (:instance kvh-held-cycle-next)
                 (:instance kvh-corrected-cycle-outs)
                 (:instance kvh-corrected-cycle-next))
           :in-theory '(kvh-reset-input-p)))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; Histories.
; ---------------------------------------------------------------------------
; every cycle is a running cycle, with definite guards in the given signals
(define kvh-run-history-p (envs outs)
  :verify-guards nil
  (if (atom envs)
      t
    (and (kvh-run-input-p (car envs))
         (kvh-guards-definite (car outs))
         (kvh-run-history-p (cdr envs) (cdr outs)))))

; A LEGAL HISTORY: reset cycles, then running cycles, with definite guards
; in the given signals throughout.
(define kvh-legal-history-p (envs outs)
  :verify-guards nil
  (if (atom envs)
      t
    (if (kvh-reset-input-p (car envs))
        (and (kvh-guards-definite (car outs))
             (kvh-legal-history-p (cdr envs) (cdr outs)))
      (kvh-run-history-p envs outs))))

(local (defun kvh-history-ind (envs st)
         (if (atom envs)
             st
           (kvh-history-ind (cdr envs)
                            (fsm-step (car envs) st (fsm->nextstate (probe-fsm-held)))))))

(local (in-theory (disable probe-fsm (:executable-counterpart probe-fsm)
                           probe-fsm-held)))

(defthm kvh-run-histories-agree
  (implies (and (kvh-run-state-p st)
                (kvh-run-history-p envs (fsm-eval envs st (probe-fsm-held))))
           (equal (fsm-eval envs st (probe-fsm-held))
                  (fsm-eval envs st (probe-fsm))))
  :hints (("Goal" :induct (kvh-history-ind envs st)
           :in-theory (enable kvh-run-history-p)
           :expand ((:free (x) (fsm-eval envs st x))))
          (and stable-under-simplificationp
               '(:use ((:instance kvh-run-cycle (in (car envs)))))))
  :rule-classes nil)

(defthm kvh-legal-histories-agree
  (implies (and (kvh-reset-state-p st)
                (or (kvh-run-state-p st)
                    (and (consp envs) (kvh-reset-input-p (car envs))))
                (kvh-legal-history-p envs (fsm-eval envs st (probe-fsm-held))))
           (equal (fsm-eval envs st (probe-fsm-held))
                  (fsm-eval envs st (probe-fsm))))
  :hints (("Goal" :induct (kvh-history-ind envs st)
           :in-theory (enable kvh-legal-history-p)
           :expand ((:free (x) (fsm-eval envs st x))))
          (and stable-under-simplificationp
               '(:use ((:instance kvh-reset-cycle (in (car envs)))
                       (:instance kvh-run-histories-agree)))))
  :rule-classes nil)

; THE CORRESPONDENCE.
(defthm kvh-held-machine-agrees-with-corrected-cycle
  (implies (and (kvh-reset-state-p initst)
                (consp envs)
                (kvh-reset-input-p (car envs))
                (kvh-legal-history-p envs (fsm-eval envs initst (probe-fsm-held))))
           (equal (fsm-eval envs initst (probe-fsm-held))
                  (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal" :use ((:instance kvh-legal-histories-agree (st initst)))
           :in-theory (theory 'minimal-theory)))
  :rule-classes nil)

; Two clock models of one phase machine: lemmas that mention no design.
;
; Private.  See README.md in this directory.
;
; Nothing here is about the SimpleStories RTL.  The lemmas are about any
; phase-level state machine x of the Centaur library (an FSM: an alist of
; signal expressions, x.values, and an alist of next-state expressions,
; x.nextstate), and about two ways of making a clock cycle out of two of
; its phases.  The books kvh-machines, kvh-settle, kvh-clock-only,
; kvh-cases and kvh-correspondence apply them to the probe.
;
;   A. Environments: lookups, agreement on a set of variables.
;   B. THE REGISTER CUT.  If x is override-transparent for a set of signals
;      (a fact the library proves by a syntactic check), and once every one
;      of those signals is overridden x reads no state variable, then one
;      phase step is determined by its inputs and the values of those
;      signals: two steps from different states that agree on them agree on
;      every signal and on the whole next state.
;   C. Specialising an alist of expressions to constants that the
;      environment is known to hold.
;   D. Stored values: the stored copy of a signal is the low bits of the
;      signal, when the next-state expression has the library's form.
;   E. TWO PHASES WITH FREE DATA.  The signals of the second phase written
;      as expressions over the state before the first phase, in which the
;      part of the intermediate state that is not kept is replaced by fresh
;      variables.  What those expressions evaluate to.
;   F. A cycle of two phases, outputs captured in the second, in terms of
;      two phase steps.
(in-package "SV")
(include-book "centaur/sv/svtv/svtv-to-fsm-defs" :dir :system)
(include-book "centaur/sv/svtv/cycle-compile" :dir :system)
(include-book "centaur/sv/svtv/fsm-override-defs" :dir :system)
(include-book "centaur/sv/svex/override-transparency" :dir :system)
(include-book "centaur/sv/svex/rewrite" :dir :system)
(local (include-book "std/lists/sets" :dir :system))
(local (include-book "std/lists/take" :dir :system))
(local (include-book "centaur/bitops/ihsext-basics" :dir :system))
(local (include-book "centaur/sv/svex/alist-thms" :dir :system))

; ===========================================================================
; A. Environments.
; ===========================================================================
(local (in-theory (enable svex-env-lookup-when-not-boundp
                          svex-env-boundp-iff-member-alist-keys)))

(local (defthm kvh-lookup-of-cons
         (equal (svex-env-lookup w (cons (cons k v) a))
                (if (and (svar-p k) (equal (svar-fix w) k))
                    (4vec-fix v)
                  (svex-env-lookup w a)))
         :hints (("Goal" :in-theory (enable svex-env-lookup svex-env-fix)))))

(local (defthm kvh-override-p-when-member
         (implies (and (svarlist-override-p x type)
                       (member-equal (svar-fix v) (svarlist-fix x)))
                  (svar-override-p v type))
         :hints (("Goal" :in-theory (enable svarlist-override-p svarlist-fix)))))

(defthm kvh-lookup-of-fsm-step-env
  (equal (svex-env-lookup v (fsm-step-env in st nx))
         (if (member-equal (svar-fix v) (svex-alist-keys nx))
             (svex-env-lookup v st)
           (svex-env-lookup v in)))
  :hints (("Goal" :in-theory (enable fsm-step-env))))

; the values of a list of variables
(define kvh-env-vals ((keys svarlist-p) (env svex-env-p))
  :returns (vals 4veclist-p)
  (if (atom keys)
      nil
    (cons (svex-env-lookup (car keys) env)
          (kvh-env-vals (cdr keys) env)))
  ///
  (defthm kvh-env-vals-when-agree
    (implies (svex-envs-agree keys a b)
             (equal (kvh-env-vals keys a) (kvh-env-vals keys b)))
    :hints (("Goal" :in-theory (enable svex-envs-agree)))
    :rule-classes nil)
  (defthm kvh-agree-when-env-vals-equal
    (implies (equal (kvh-env-vals keys a) (kvh-env-vals keys b))
             (svex-envs-agree keys a b))
    :hints (("Goal" :in-theory (enable svex-envs-agree)))
    :rule-classes nil)
  (defthm kvh-env-vals-of-svex-env-extract
    (implies (subsetp-equal (svarlist-fix keys) (svarlist-fix keys2))
             (equal (kvh-env-vals keys (svex-env-extract keys2 env))
                    (kvh-env-vals keys env)))
    :hints (("Goal" :in-theory (enable svarlist-fix)))))

(defthm kvh-agree-when-extract-equal
  (implies (equal (svex-env-extract keys a) (svex-env-extract keys b))
           (svex-envs-agree keys a b))
  :hints (("Goal" :in-theory (enable svex-envs-agree-by-witness)
           :use ((:instance svex-env-lookup-of-svex-env-extract
                  (v (svex-envs-disagree-witness keys a b)) (vars keys) (env a))
                 (:instance svex-env-lookup-of-svex-env-extract
                  (v (svex-envs-disagree-witness keys a b)) (vars keys) (env b)))
           :do-not-induct t))
  :rule-classes nil)

; Two environments with the same keys, none twice, that agree on every
; variable are the same list.
(local
 (defthm kvh-similar-of-cdrs
   (implies (and (svex-envs-similar (cons (cons k v1) a) (cons (cons k v2) b))
                 (svar-p k)
                 (not (member-equal k (alist-keys (svex-env-fix a))))
                 (not (member-equal k (alist-keys (svex-env-fix b)))))
            (svex-envs-similar a b))
   :hints (("Goal" :expand ((svex-envs-similar a b))
            :use ((:instance svex-envs-similar-necc
                   (x (cons (cons k v1) a)) (y (cons (cons k v2) b))
                   (k (svex-envs-similar-witness a b))))
            :in-theory (disable svex-envs-similar-necc
                                svex-envs-similar-implies-equal-svex-env-lookup-2)
            :do-not-induct t))))

(local
 (defthm kvh-value-when-similar-conses
   (implies (and (svex-envs-similar (cons (cons k v1) a) (cons (cons k v2) b))
                 (svar-p k))
            (equal (4vec-fix v1) (4vec-fix v2)))
   :hints (("Goal"
            :use ((:instance svex-envs-similar-necc
                   (x (cons (cons k v1) a)) (y (cons (cons k v2) b)) (k k)))
            :in-theory (disable svex-envs-similar-necc
                                svex-envs-similar-implies-equal-svex-env-lookup-2)
            :do-not-induct t))
   :rule-classes nil))

(local (defun kvh-two-cdr-ind (a b)
         (if (atom a) b (kvh-two-cdr-ind (cdr a) (cdr b)))))

(defthm kvh-env-equal-when-similar
  (implies (and (svex-env-p a) (svex-env-p b)
                (equal (alist-keys a) (alist-keys b))
                (no-duplicatesp-equal (alist-keys a))
                (svex-envs-similar a b))
           (equal a b))
  :hints (("Goal" :induct (kvh-two-cdr-ind a b)
           :in-theory (enable svex-env-p alist-keys))
          ("Subgoal *1/2"
           :use ((:instance kvh-similar-of-cdrs
                  (k (caar a)) (v1 (cdar a)) (v2 (cdar b)) (a (cdr a)) (b (cdr b)))
                 (:instance kvh-value-when-similar-conses
                  (k (caar a)) (v1 (cdar a)) (v2 (cdar b)) (a (cdr a)) (b (cdr b))))))
  :rule-classes nil)

; an environment holds the constants of another
(define kvh-env-has ((consts svex-env-p) (e svex-env-p))
  (if (atom consts)
      t
    (and (or (not (mbt (and (consp (car consts)) (svar-p (caar consts)))))
             (equal (svex-env-lookup (caar consts) e) (4vec-fix (cdar consts))))
         (kvh-env-has (cdr consts) e)))
  ///
  (defthm kvh-lookup-when-env-has
    (implies (and (kvh-env-has consts e)
                  (svex-env-boundp v consts))
             (equal (svex-env-lookup v consts) (svex-env-lookup v e)))
    :hints (("Goal" :in-theory (enable svex-env-boundp svex-env-lookup svex-env-fix
                                       alist-keys))))
  (defthm kvh-append-similar-when-env-has
    (implies (kvh-env-has consts e)
             (svex-envs-similar (append consts e) e))
    :hints (("Goal" :in-theory (enable svex-envs-similar))))
  ; holding constants is a matter of lookups only
  (defthm kvh-env-has-when-agree
    (implies (and (kvh-env-has consts e1)
                  (svex-envs-agree (alist-keys (svex-env-fix consts)) e1 e2))
             (kvh-env-has consts e2))
    :hints (("Goal" :in-theory (enable svex-env-fix alist-keys svex-envs-agree))))
  (defthm kvh-env-has-of-fsm-step-env-inputs
    (implies (and (kvh-env-has consts in)
                  (not (intersectp-equal (alist-keys (svex-env-fix consts))
                                         (svex-alist-keys nx))))
             (kvh-env-has consts (fsm-step-env in st nx)))
    :hints (("Goal" :in-theory (enable svex-env-fix alist-keys intersectp-equal))))
  (defthm kvh-env-has-of-fsm-step-env-state
    (implies (and (kvh-env-has consts st)
                  (subsetp-equal (alist-keys (svex-env-fix consts))
                                 (svex-alist-keys nx)))
             (kvh-env-has consts (fsm-step-env in st nx)))
    :hints (("Goal" :in-theory (enable svex-env-fix alist-keys)))))

; ===========================================================================
; C. Specialising expressions to constants the environment holds.
; ===========================================================================
(local (defthm kvh-eval-of-svex-env-to-subst
         (equal (svex-alist-eval (svex-env-to-subst consts) env)
                (svex-env-fix consts))
         :hints (("Goal" :in-theory (enable svex-env-to-subst svex-alist-eval
                                            svex-env-fix)))))

(define kvh-specialize ((x svex-alist-p) (consts svex-env-p))
  :returns (y svex-alist-p)
  :verify-guards nil
  (svex-alist-rewrite-fixpoint (svex-alist-compose x (svex-env-to-subst consts)))
  ///
  (defthm kvh-eval-of-specialize
    (implies (kvh-env-has consts env)
             (equal (svex-alist-eval (kvh-specialize x consts) env)
                    (svex-alist-eval x env)))))

; ===========================================================================
; B. The register cut.
; ===========================================================================
(local (in-theory (enable equal-of-svar-change-override)))

; every override test of the keys set to all ones
(define kvh-test-env ((keys svarlist-p))
  :returns (env svex-env-p)
  (if (atom keys)
      nil
    (cons (cons (svar-change-override (car keys) :test) -1)
          (kvh-test-env (cdr keys))))
  ///
  (defthm kvh-test-env-boundp
    (implies (svarlist-override-p keys nil)
             (iff (svex-env-boundp v (kvh-test-env keys))
                  (and (svar-override-p v :test)
                       (member-equal (svar-change-override v nil) (svarlist-fix keys)))))
    :hints (("Goal" :in-theory (enable svex-env-boundp svarlist-override-p
                                       svarlist-fix alist-keys))))
  (defthm kvh-test-env-lookup
    (implies (svex-env-boundp v (kvh-test-env keys))
             (equal (svex-env-lookup v (kvh-test-env keys)) -1))
    :hints (("Goal" :in-theory (enable svex-env-boundp svex-env-lookup alist-keys)))))

; every override value of the keys set to the key's value in outs
(define kvh-val-env ((keys svarlist-p) (outs svex-env-p))
  :returns (env svex-env-p)
  (if (atom keys)
      nil
    (cons (cons (svar-change-override (car keys) :val)
                (svex-env-lookup (car keys) outs))
          (kvh-val-env (cdr keys) outs)))
  ///
  (defthm kvh-val-env-boundp
    (implies (svarlist-override-p keys nil)
             (iff (svex-env-boundp v (kvh-val-env keys outs))
                  (and (svar-override-p v :val)
                       (member-equal (svar-change-override v nil) (svarlist-fix keys)))))
    :hints (("Goal" :in-theory (enable svex-env-boundp svarlist-override-p
                                       svarlist-fix alist-keys))))
  (defthm kvh-val-env-lookup
    (implies (and (svarlist-override-p keys nil)
                  (svex-env-boundp v (kvh-val-env keys outs)))
             (equal (svex-env-lookup v (kvh-val-env keys outs))
                    (svex-env-lookup (svar-change-override v nil) outs)))
    :hints (("Goal" :in-theory (enable svex-env-boundp svex-env-lookup alist-keys
                                       svarlist-override-p svarlist-fix))))
  (defthm kvh-val-env-when-agree
    (implies (svex-envs-agree keys a b)
             (equal (kvh-val-env keys a) (kvh-val-env keys b)))
    :hints (("Goal" :in-theory (enable svex-envs-agree)))
    :rule-classes nil))

; no override test of the keys is set in an environment
(define kvh-tests-unset ((keys svarlist-p) (e svex-env-p))
  (if (atom keys)
      t
    (and (equal (svex-env-lookup (svar-change-override (car keys) :test) e) (4vec-x))
         (kvh-tests-unset (cdr keys) e)))
  ///
  (defthm kvh-test-lookup-when-unset
    (implies (and (kvh-tests-unset keys e)
                  (member-equal (svar-fix k) (svarlist-fix keys)))
             (equal (svex-env-lookup (svar-change-override k :test) e) (4vec-x)))
    :hints (("Goal" :in-theory (enable svarlist-fix))))
  (defthm kvh-test-lookup-when-unset-var
    (implies (and (kvh-tests-unset keys e)
                  (svar-override-p v :test)
                  (member-equal (svar-change-override v nil) (svarlist-fix keys)))
             (equal (svex-env-lookup v e) (4vec-x)))
    :hints (("Goal" :use ((:instance kvh-test-lookup-when-unset
                           (k (svar-change-override v nil))))
             :in-theory (disable kvh-test-lookup-when-unset))))
  (defthm kvh-tests-unset-of-fsm-step-env
    (implies (and (kvh-tests-unset keys in)
                  (svarlist-override-p (svex-alist-keys nx) nil))
             (kvh-tests-unset keys (fsm-step-env in st nx)))
    :hints (("Goal" :induct (kvh-tests-unset keys in))
            (and stable-under-simplificationp
                 '(:use ((:instance kvh-override-p-when-member
                          (x (svex-alist-keys nx)) (type nil)
                          (v (svar-change-override (car keys) :test))))
                   :in-theory (disable kvh-override-p-when-member))))))

(local (defthm kvh-bit?!-of-neg1
         (equal (4vec-bit?! -1 a b) (4vec-fix a))
         :hints (("Goal" :in-theory (enable 4vec-bit?! 4vec-bitmux 4vec-1mask logite)))))
(local (defthm kvh-bit?!-of-0
         (equal (4vec-bit?! 0 a b) (4vec-fix b))
         :hints (("Goal" :in-theory (enable 4vec-bit?! 4vec-bitmux 4vec-1mask logite)))))
(local (defthm kvh-bit?!-of-x
         (equal (4vec-bit?! (4vec-x) a b) (4vec-fix b))
         :hints (("Goal" :in-theory (enable 4vec-bit?! 4vec-bitmux 4vec-1mask logite)))))

; the environment in which every key is overridden with its own value
(define kvh-cut-env ((keys svarlist-p) (outs svex-env-p) (spec svex-env-p))
  :returns (env svex-env-p)
  (append (kvh-test-env keys) (kvh-val-env keys outs) (svex-env-fix spec)))

(defthm kvh-cut-env-agrees
  (implies (and (svarlist-override-p keys nil)
                (kvh-tests-unset keys spec))
           (overridekeys-envs-agree keys (kvh-cut-env keys outs spec) spec outs))
  :hints (("Goal" :in-theory (e/d (overridekeys-envs-agree-by-witness
                                   svar-overridekeys-envs-agree
                                   kvh-cut-env
                                   4vec-override-mux-agrees
                                   4vec-muxtest-subsetp
                                   svar-override-p-when-other)
                                  (overridekeys-envs-agree))
           :do-not-induct t)))

(local (defthm kvh-append-same-similar
         (svex-envs-similar (append a (append a b)) (append a b))
         :hints (("Goal" :in-theory (enable svex-envs-similar)))))

; x with every key's override test replaced by all ones, then rewritten
(define kvh-cut ((x svex-alist-p) (keys svarlist-p))
  :returns (y svex-alist-p)
  :verify-guards nil
  (kvh-specialize x (kvh-test-env keys))
  ///
  (defthm kvh-eval-of-cut
    (equal (svex-alist-eval (kvh-cut x keys) (kvh-cut-env keys outs spec))
           (svex-alist-eval x (kvh-cut-env keys outs spec)))
    :hints (("Goal" :in-theory (enable kvh-cut-env kvh-specialize)))))

(local (defthm kvh-not-member-when-not-intersectp
         (implies (and (not (intersectp-equal x y))
                       (member-equal v x))
                  (not (member-equal v y)))))

; an alist that reads no state variable evaluates the same in the cut
; environments of two states whose key values agree
(defthm kvh-cut-eval-ignores-state
  (implies (and (not (intersectp-equal (svex-alist-vars y) (svex-alist-keys nx)))
                (svex-envs-agree keys outs-a outs-b))
           (equal (svex-alist-eval y (kvh-cut-env keys outs-a (fsm-step-env e a nx)))
                  (svex-alist-eval y (kvh-cut-env keys outs-b (fsm-step-env e b nx)))))
  :hints (("Goal"
           :use ((:instance svex-alist-eval-when-envs-agree
                  (x y)
                  (env1 (kvh-cut-env keys outs-a (fsm-step-env e a nx)))
                  (env2 (kvh-cut-env keys outs-b (fsm-step-env e b nx))))
                 (:instance kvh-val-env-when-agree (a outs-a) (b outs-b)))
           :in-theory (e/d (kvh-cut-env svex-envs-agree-by-witness)
                           (svex-env-lookup-when-not-boundp
                            svex-env-boundp-iff-member-alist-keys))
           :do-not-induct t))
  :rule-classes nil)

; THE NEXT STATE of a phase step is determined by the step's inputs and the
; values of the keys.
(defthm kvh-settle-nextstate
  (implies (and (svex-alist-overridekey-transparent-p nx keys vals)
                (svarlist-override-p keys nil)
                (svarlist-override-p (svex-alist-keys nx) nil)
                (not (intersectp-equal (svex-alist-vars (kvh-cut nx keys))
                                       (svex-alist-keys nx)))
                (kvh-tests-unset keys e)
                (svex-envs-agree keys
                                 (svex-alist-eval vals (fsm-step-env e a nx))
                                 (svex-alist-eval vals (fsm-step-env e b nx))))
           (equal (svex-alist-eval nx (fsm-step-env e a nx))
                  (svex-alist-eval nx (fsm-step-env e b nx))))
  :hints (("Goal"
           :use ((:instance svex-alist-overridekey-transparent-p-necc
                  (x nx) (overridekeys keys) (subst vals)
                  (impl-env (kvh-cut-env keys (svex-alist-eval vals (fsm-step-env e a nx))
                                         (fsm-step-env e a nx)))
                  (spec-env (fsm-step-env e a nx)))
                 (:instance svex-alist-overridekey-transparent-p-necc
                  (x nx) (overridekeys keys) (subst vals)
                  (impl-env (kvh-cut-env keys (svex-alist-eval vals (fsm-step-env e b nx))
                                         (fsm-step-env e b nx)))
                  (spec-env (fsm-step-env e b nx)))
                 (:instance kvh-cut-eval-ignores-state
                  (y (kvh-cut nx keys))
                  (outs-a (svex-alist-eval vals (fsm-step-env e a nx)))
                  (outs-b (svex-alist-eval vals (fsm-step-env e b nx))))
                 (:instance kvh-eval-of-cut (x nx)
                  (outs (svex-alist-eval vals (fsm-step-env e a nx)))
                  (spec (fsm-step-env e a nx)))
                 (:instance kvh-eval-of-cut (x nx)
                  (outs (svex-alist-eval vals (fsm-step-env e b nx)))
                  (spec (fsm-step-env e b nx))))
           :in-theory (disable kvh-eval-of-cut svex-alist-overridekey-transparent-p-necc)
           :do-not-induct t))
  :rule-classes nil)

; THE SIGNALS that are not keys, likewise.
(defthm kvh-settle-values-others
  (implies (and (svex-alist-overridekey-transparent-p vals keys vals)
                (svarlist-override-p keys nil)
                (svarlist-override-p (svex-alist-keys nx) nil)
                (not (intersectp-equal
                      (svex-alist-vars (kvh-cut (svex-alist-extract others vals) keys))
                      (svex-alist-keys nx)))
                (kvh-tests-unset keys e)
                (svex-envs-agree keys
                                 (svex-alist-eval vals (fsm-step-env e a nx))
                                 (svex-alist-eval vals (fsm-step-env e b nx))))
           (equal (svex-env-extract others (svex-alist-eval vals (fsm-step-env e a nx)))
                  (svex-env-extract others (svex-alist-eval vals (fsm-step-env e b nx)))))
  :hints (("Goal"
           :use ((:instance svex-alist-overridekey-transparent-p-necc
                  (x vals) (overridekeys keys) (subst vals)
                  (impl-env (kvh-cut-env keys (svex-alist-eval vals (fsm-step-env e a nx))
                                         (fsm-step-env e a nx)))
                  (spec-env (fsm-step-env e a nx)))
                 (:instance svex-alist-overridekey-transparent-p-necc
                  (x vals) (overridekeys keys) (subst vals)
                  (impl-env (kvh-cut-env keys (svex-alist-eval vals (fsm-step-env e b nx))
                                         (fsm-step-env e b nx)))
                  (spec-env (fsm-step-env e b nx)))
                 (:instance kvh-cut-eval-ignores-state
                  (y (kvh-cut (svex-alist-extract others vals) keys))
                  (outs-a (svex-alist-eval vals (fsm-step-env e a nx)))
                  (outs-b (svex-alist-eval vals (fsm-step-env e b nx))))
                 (:instance kvh-eval-of-cut (x (svex-alist-extract others vals))
                  (outs (svex-alist-eval vals (fsm-step-env e a nx)))
                  (spec (fsm-step-env e a nx)))
                 (:instance kvh-eval-of-cut (x (svex-alist-extract others vals))
                  (outs (svex-alist-eval vals (fsm-step-env e b nx)))
                  (spec (fsm-step-env e b nx))))
           :in-theory (disable kvh-eval-of-cut svex-alist-overridekey-transparent-p-necc)
           :do-not-induct t))
  :rule-classes nil)

(local
 (defthm kvh-similar-by-parts
   (implies (and (equal (svex-env-extract others oa) (svex-env-extract others ob))
                 (svex-envs-agree keys oa ob)
                 (subsetp-equal (alist-keys (svex-env-fix oa))
                                (append (svarlist-fix keys) (svarlist-fix others)))
                 (equal (alist-keys (svex-env-fix oa)) (alist-keys (svex-env-fix ob))))
            (svex-envs-similar oa ob))
   :hints (("Goal" :expand ((svex-envs-similar oa ob))
            :use ((:instance lookup-when-svex-envs-agree
                   (vars keys) (x oa) (y ob)
                   (v (svex-envs-similar-witness oa ob)))
                  (:instance svex-env-lookup-of-svex-env-extract
                   (v (svex-envs-similar-witness oa ob)) (vars others) (env oa))
                  (:instance svex-env-lookup-of-svex-env-extract
                   (v (svex-envs-similar-witness oa ob)) (vars others) (env ob)))
            :in-theory (disable lookup-when-svex-envs-agree
                                svex-env-lookup-of-svex-env-extract)
            :do-not-induct t))
   :rule-classes nil))

; ALL THE SIGNALS: two phase steps from different states, with the same
; inputs, that agree on the keys agree on every signal.
(defthm kvh-settle-values
  (implies (and (svex-alist-overridekey-transparent-p vals keys vals)
                (svarlist-override-p keys nil)
                (svarlist-override-p (svex-alist-keys nx) nil)
                (not (intersectp-equal
                      (svex-alist-vars (kvh-cut (svex-alist-extract others vals) keys))
                      (svex-alist-keys nx)))
                (subsetp-equal (svex-alist-keys vals)
                               (append (svarlist-fix keys) (svarlist-fix others)))
                (no-duplicatesp-equal (svex-alist-keys vals))
                (kvh-tests-unset keys e)
                (svex-envs-agree keys
                                 (svex-alist-eval vals (fsm-step-env e a nx))
                                 (svex-alist-eval vals (fsm-step-env e b nx))))
           (equal (svex-alist-eval vals (fsm-step-env e a nx))
                  (svex-alist-eval vals (fsm-step-env e b nx))))
  :hints (("Goal"
           :use ((:instance kvh-settle-values-others)
                 (:instance kvh-similar-by-parts
                  (oa (svex-alist-eval vals (fsm-step-env e a nx)))
                  (ob (svex-alist-eval vals (fsm-step-env e b nx))))
                 (:instance kvh-env-equal-when-similar
                  (a (svex-alist-eval vals (fsm-step-env e a nx)))
                  (b (svex-alist-eval vals (fsm-step-env e b nx)))))
           :do-not-induct t))
  :rule-classes nil)

; ===========================================================================
; D. Plain inputs, value lists, and stored values.
; ===========================================================================
; Inputs that bind no override-test variable.  The same definition as in
; corrected-cycle/kv-producer-to-record/full-design-run/kv-plain-inputs.lisp.
(defun kv-plain-env-p (env)
  (declare (xargs :guard t))
  (or (atom env)
      (and (consp (car env))
           (svar-p (car (car env)))
           (not (svar-override-p (car (car env)) :test))
           (kv-plain-env-p (cdr env)))))

(defthm kvh-plain-lookup-of-test
  (implies (and (kv-plain-env-p e)
                (svar-override-p v :test))
           (equal (svex-env-lookup v e) (4vec-x)))
  :hints (("Goal" :in-theory (enable svex-env-lookup svex-env-fix))))

(defthm kvh-tests-unset-when-plain
  (implies (kv-plain-env-p e)
           (kvh-tests-unset keys e))
  :hints (("Goal" :in-theory (enable kvh-tests-unset))))

(defthm kvh-plain-of-append
  (implies (and (kv-plain-env-p a) (kv-plain-env-p b))
           (kv-plain-env-p (append a b))))

(defthm kvh-plain-of-svex-env-fix
  (implies (kv-plain-env-p e)
           (kv-plain-env-p (svex-env-fix e)))
  :hints (("Goal" :in-theory (enable svex-env-fix))))

(defthm kvh-plain-of-phase-inputs
  (implies (and (kv-plain-env-p in)
                (kv-plain-env-p (svtv-cyclephase->constants ph)))
           (kv-plain-env-p (svtv-cycle-step-fsm-inputs in ph)))
  :hints (("Goal" :in-theory (enable svtv-cycle-step-fsm-inputs))))

(define kvh-2vec-list-p (x)
  :verify-guards nil
  (if (atom x)
      t
    (and (2vec-p (car x))
         (kvh-2vec-list-p (cdr x)))))

; the low bits of a list of variables: nw is a list of (variable . width)
(define kvh-zx-vals ((nw alistp) (env svex-env-p))
  :verify-guards nil
  (if (atom nw)
      nil
    (cons (4vec-zero-ext (2vec (nfix (cdar nw))) (svex-env-lookup (caar nw) env))
          (kvh-zx-vals (cdr nw) env)))
  ///
  (defthm kvh-zx-vals-when-agree
    (implies (svex-envs-agree (strip-cars nw) a b)
             (equal (kvh-zx-vals nw a) (kvh-zx-vals nw b)))
    :hints (("Goal" :in-theory (enable svex-envs-agree)))
    :rule-classes nil)
  (defthm kvh-zx-vals-of-svex-env-extract
    (implies (subsetp-equal (svarlist-fix (strip-cars nw)) (svarlist-fix keys))
             (equal (kvh-zx-vals nw (svex-env-extract keys env))
                    (kvh-zx-vals nw env)))
    :hints (("Goal" :in-theory (enable svarlist-fix)))))

(local (defthm kvh-eval-var
         (equal (svex-eval (svex-var v) env) (svex-env-lookup v env))
         :hints (("Goal" :expand ((svex-eval (svex-var v) env))))))
(local (defthm kvh-eval-zerox
         (equal (svex-eval (svex-call 'zerox (list a b)) env)
                (4vec-zero-ext (svex-eval a env) (svex-eval b env)))
         :hints (("Goal" :in-theory (enable svex-apply svexlist-eval)))))
(local (defthm kvh-eval-concat
         (equal (svex-eval (svex-call 'concat (list a b c)) env)
                (4vec-concat (svex-eval a env) (svex-eval b env) (svex-eval c env)))
         :hints (("Goal" :in-theory (enable svex-apply svexlist-eval)))))
(local (defthm kvh-eval-bit?!
         (equal (svex-eval (svex-call 'bit?! (list a b c)) env)
                (4vec-bit?! (svex-eval a env) (svex-eval b env) (svex-eval c env)))
         :hints (("Goal" :in-theory (enable svex-apply svexlist-eval)))))

; expressions for the values of a list of signals of an alist
(define kvh-lookup-exprs ((keys svarlist-p) (x svex-alist-p))
  :returns (e svexlist-p)
  (if (atom keys)
      nil
    (cons (or (svex-lookup (car keys) x) (svex-x))
          (kvh-lookup-exprs (cdr keys) x)))
  ///
  (defthm kvh-eval-of-lookup-exprs
    (equal (svexlist-eval (kvh-lookup-exprs keys x) env)
           (kvh-env-vals keys (svex-alist-eval x env)))
    :hints (("Goal" :in-theory (enable kvh-env-vals svexlist-eval)))))

; expressions for the low bits of a list of signals of an alist
(define kvh-zx-exprs ((nw alistp) (x svex-alist-p))
  :verify-guards nil
  :returns (e svexlist-p)
  (if (atom nw)
      nil
    (cons (svex-call 'zerox (list (svex-quote (2vec (nfix (cdar nw))))
                                  (or (svex-lookup (caar nw) x) (svex-x))))
          (kvh-zx-exprs (cdr nw) x)))
  ///
  (defthm kvh-eval-of-zx-exprs
    (equal (svexlist-eval (kvh-zx-exprs nw x) env)
           (kvh-zx-vals nw (svex-alist-eval x env)))
    :hints (("Goal" :in-theory (enable kvh-zx-vals svexlist-eval)))))

; expressions for the low bits of a list of variables
(define kvh-zxvar-exprs ((nw alistp))
  :verify-guards nil
  :returns (e svexlist-p)
  (if (atom nw)
      nil
    (cons (svex-call 'zerox (list (svex-quote (2vec (nfix (cdar nw))))
                                  (svex-var (caar nw))))
          (kvh-zxvar-exprs (cdr nw))))
  ///
  (defthm kvh-eval-of-zxvar-exprs
    (equal (svexlist-eval (kvh-zxvar-exprs nw) env)
           (kvh-zx-vals nw env))
    :hints (("Goal" :in-theory (enable kvh-zx-vals svexlist-eval)))))

; (variable . width) -> (stored copy of the variable . width)
(define kvh-delay-nw ((nw alistp))
  :verify-guards nil
  (if (atom nw)
      nil
    (cons (cons (change-svar (caar nw) :delay 1) (cdar nw))
          (kvh-delay-nw (cdr nw)))))

(local (defthm kvh-concat-0-is-zero-ext
         (equal (4vec-concat (2vec (nfix w)) x 0)
                (4vec-zero-ext (2vec (nfix w)) x))
         :hints (("Goal" :in-theory (enable 4vec-concat 4vec-zero-ext)))))
(local (defthm kvh-zero-ext-of-zero-ext
         (equal (4vec-zero-ext (2vec (nfix w)) (4vec-zero-ext (2vec (nfix w)) x))
                (4vec-zero-ext (2vec (nfix w)) x))
         :hints (("Goal" :in-theory (enable 4vec-zero-ext)))))

; The library's next-state expression for the stored copy of an internal
; signal n of width w: the low w bits of n, behind n's override.
(define kvh-net-stored-form ((n svar-p) (w natp) (vals svex-alist-p))
  :returns (e svex-p)
  (svex-call 'concat
             (list (svex-quote (2vec (nfix w)))
                   (svex-call 'bit?! (list (svex-var (svar-change-override n :test))
                                           (svex-var (svar-change-override n :val))
                                           (or (svex-lookup n vals) (svex-x))))
                   (svex-quote (2vec 0))))
  ///
  (defthm kvh-net-stored-form-is-not-nil
    (kvh-net-stored-form n w vals)
    :rule-classes :type-prescription))

(local
 (defthm kvh-stored-net-one
   (implies (and (equal look (kvh-net-stored-form n w vals))
                 (equal (svex-env-lookup (svar-change-override n :test) env) (4vec-x)))
            (equal (svex-eval look env)
                   (4vec-zero-ext (2vec (nfix w))
                                  (svex-env-lookup n (svex-alist-eval vals env)))))
   :hints (("Goal" :in-theory (enable kvh-net-stored-form svex-apply svexlist-eval
                                      4veclist-nth-safe)))))

(defthm kvh-stored-net-lookup
  (implies (and (equal (svex-lookup dv nx) (kvh-net-stored-form n w vals))
                (equal (svex-env-lookup (svar-change-override n :test) env) (4vec-x)))
           (equal (svex-env-lookup dv (svex-alist-eval nx env))
                  (4vec-zero-ext (2vec (nfix w))
                                 (svex-env-lookup n (svex-alist-eval vals env)))))
  :hints (("Goal" :use ((:instance kvh-stored-net-one (look (svex-lookup dv nx))))
           :in-theory (disable kvh-stored-net-one))))

(define kvh-net-forms-ok ((nw alistp) (nx svex-alist-p) (vals svex-alist-p))
  :verify-guards nil
  (if (atom nw)
      t
    (and (equal (svex-lookup (change-svar (caar nw) :delay 1) nx)
                (kvh-net-stored-form (caar nw) (cdar nw) vals))
         (kvh-net-forms-ok (cdr nw) nx vals))))

; ... so the stored copies after a step are the low bits of the signals in
; that step, when the step's environment sets no override of them.
(defthm kvh-stored-nets
  (implies (and (kvh-net-forms-ok nw nx vals)
                (kvh-tests-unset (strip-cars nw) env))
           (equal (kvh-env-vals (strip-cars (kvh-delay-nw nw)) (svex-alist-eval nx env))
                  (kvh-zx-vals nw (svex-alist-eval vals env))))
  :hints (("Goal" :in-theory (e/d (kvh-net-forms-ok kvh-tests-unset kvh-delay-nw
                                   kvh-env-vals kvh-zx-vals)
                                  (svex-env-lookup-of-svex-alist-eval)))))

; the low bits of a list of values
(define kvh-zx-list ((nw alistp) vals)
  :verify-guards nil
  (if (atom nw)
      nil
    (cons (4vec-zero-ext (2vec (nfix (cdar nw))) (car vals))
          (kvh-zx-list (cdr nw) (cdr vals))))
  ///
  (defthmd kvh-zx-vals-is-zx-list
    (equal (kvh-zx-vals nw env)
           (kvh-zx-list nw (kvh-env-vals (strip-cars nw) env)))
    :hints (("Goal" :in-theory (enable kvh-zx-vals kvh-env-vals))))
  (defthm kvh-zx-list-of-delay-nw
    (equal (kvh-zx-list (kvh-delay-nw nw) vals)
           (kvh-zx-list nw vals))
    :hints (("Goal" :in-theory (enable kvh-delay-nw))))
  (defthm kvh-zx-list-of-zx-vals
    (equal (kvh-zx-list nw (kvh-zx-vals nw env))
           (kvh-zx-vals nw env))
    :hints (("Goal" :in-theory (enable kvh-zx-vals)))))

(defthm kvh-stored-nets-zx
  (implies (and (kvh-net-forms-ok nw nx vals)
                (kvh-tests-unset (strip-cars nw) env))
           (equal (kvh-zx-vals (kvh-delay-nw nw) (svex-alist-eval nx env))
                  (kvh-zx-vals nw (svex-alist-eval vals env))))
  :hints (("Goal" :use ((:instance kvh-stored-nets)
                        (:instance kvh-zx-vals-is-zx-list
                         (nw (kvh-delay-nw nw)) (env (svex-alist-eval nx env))))
           :in-theory (disable kvh-stored-nets)
           :do-not-induct t)))

; The same for an input port i of width w, which has no override.
(define kvh-input-stored-form ((i svar-p) (w natp))
  :returns (e svex-p)
  (svex-call 'concat (list (svex-quote (2vec (nfix w)))
                           (svex-var i)
                           (svex-quote (2vec 0))))
  ///
  (defthm kvh-input-stored-form-is-not-nil
    (kvh-input-stored-form i w)
    :rule-classes :type-prescription))

(local
 (defthm kvh-stored-input-one
   (implies (equal look (kvh-input-stored-form i w))
            (equal (svex-eval look env)
                   (4vec-zero-ext (2vec (nfix w)) (svex-env-lookup i env))))
   :hints (("Goal" :in-theory (enable kvh-input-stored-form svex-apply svexlist-eval
                                      4veclist-nth-safe)))))

(defthm kvh-stored-input-lookup
  (implies (equal (svex-lookup dv nx) (kvh-input-stored-form i w))
           (equal (svex-env-lookup dv (svex-alist-eval nx env))
                  (4vec-zero-ext (2vec (nfix w)) (svex-env-lookup i env))))
  :hints (("Goal" :use ((:instance kvh-stored-input-one (look (svex-lookup dv nx))))
           :in-theory (disable kvh-stored-input-one))))

(define kvh-input-forms-ok ((iw alistp) (nx svex-alist-p))
  :verify-guards nil
  (if (atom iw)
      t
    (and (equal (svex-lookup (change-svar (caar iw) :delay 1) nx)
                (kvh-input-stored-form (caar iw) (cdar iw)))
         (kvh-input-forms-ok (cdr iw) nx))))

(defthm kvh-stored-inputs
  (implies (kvh-input-forms-ok iw nx)
           (equal (kvh-env-vals (strip-cars (kvh-delay-nw iw)) (svex-alist-eval nx env))
                  (kvh-zx-vals iw env)))
  :hints (("Goal" :in-theory (e/d (kvh-input-forms-ok kvh-delay-nw
                                   kvh-env-vals kvh-zx-vals)
                                  (svex-env-lookup-of-svex-alist-eval)))))

; a list of variables with given values, as an environment
(defthm kvh-env-has-of-pairlis
  (implies (and (svarlist-p keys) (4veclist-p vals) (equal (len keys) (len vals)))
           (equal (kvh-env-has (pairlis$ keys vals) e)
                  (equal (kvh-env-vals keys e) vals)))
  :hints (("Goal" :in-theory (enable kvh-env-has kvh-env-vals pairlis$))))

; ===========================================================================
; E. Two phases with free data.
; ===========================================================================
(local (defthmd kvh-lookup-of-cons-pair
         (equal (svex-env-lookup w (cons pair a))
                (if (and (consp pair) (svar-p (car pair)) (equal (svar-fix w) (car pair)))
                    (4vec-fix (cdr pair))
                  (svex-env-lookup w a)))
         :hints (("Goal" :in-theory (enable svex-env-lookup svex-env-fix)))))

; the expression of a signal in an alist, or X if it has none
(define kvh-lookup-or-x ((k svar-p) (x svex-alist-p))
  :returns (e svex-p)
  (or (svex-lookup k x) (svex-x))
  ///
  (defthm kvh-eval-of-lookup-or-x
    (equal (svex-eval (kvh-lookup-or-x k x) env)
           (svex-env-lookup k (svex-alist-eval x env)))))

; every variable of a list has the given delay number
(define svarlist-all-delay ((x svarlist-p) (d natp))
  (if (atom x)
      t
    (and (equal (svar->delay (car x)) (nfix d))
         (svarlist-all-delay (cdr x) d)))
  ///
  (defthm svar-delay-when-member-of-all-delay
    (implies (and (svarlist-all-delay x d)
                  (member-equal (svar-fix v) (svarlist-fix x)))
             (equal (svar->delay v) (nfix d)))
    :hints (("Goal" :in-theory (enable svarlist-fix)))))

; The stored state a first phase starts from, as expressions: each state
; variable itself, except those given as constants.
(define kvh-prev-st ((keys svarlist-p) (consts svex-env-p))
  :returns (st svex-alist-p)
  (if (atom keys)
      nil
    (cons (cons (svar-fix (car keys))
                (if (svex-env-boundp (car keys) consts)
                    (svex-quote (svex-env-lookup (car keys) consts))
                  (svex-var (car keys))))
          (kvh-prev-st (cdr keys) consts)))
  ///
  (defthm kvh-keys-of-prev-st
    (equal (svex-alist-keys (kvh-prev-st keys consts)) (svarlist-fix keys))
    :hints (("Goal" :in-theory (enable svex-alist-keys svarlist-fix))))
  (defthm kvh-lookup-of-eval-prev-st
    (implies (member-equal (svar-fix v) (svarlist-fix keys))
             (equal (svex-env-lookup v (svex-alist-eval (kvh-prev-st keys consts) env))
                    (if (svex-env-boundp v consts)
                        (svex-env-lookup v consts)
                      (svex-env-lookup v env))))
    :hints (("Goal" :in-theory (e/d (svex-alist-eval svarlist-fix kvh-lookup-of-cons-pair)
                                    (svex-env-lookup-of-svex-alist-eval
                                     svex-env-boundp-iff-member-alist-keys
                                     svex-env-lookup-when-not-boundp))))))

; The state between the phases, as expressions: the kept variables from the
; first phase's next-state expressions, every other one a fresh variable
; (the same name with delay number tag).
(define kvh-mix-st ((keys svarlist-p) (kept svarlist-p) (nx1 svex-alist-p) (tag natp))
  :returns (st svex-alist-p)
  (if (atom keys)
      nil
    (cons (cons (svar-fix (car keys))
                (if (member-equal (svar-fix (car keys)) (svarlist-fix kept))
                    (kvh-lookup-or-x (car keys) nx1)
                  (svex-var (change-svar (car keys) :delay tag))))
          (kvh-mix-st (cdr keys) kept nx1 tag)))
  ///
  (defthm kvh-keys-of-mix-st
    (equal (svex-alist-keys (kvh-mix-st keys kept nx1 tag)) (svarlist-fix keys))
    :hints (("Goal" :in-theory (enable svex-alist-keys svarlist-fix))))
  (defthm kvh-lookup-of-eval-mix-st
    (implies (member-equal (svar-fix v) (svarlist-fix keys))
             (equal (svex-env-lookup v (svex-alist-eval (kvh-mix-st keys kept nx1 tag) env))
                    (if (member-equal (svar-fix v) (svarlist-fix kept))
                        (svex-env-lookup v (svex-alist-eval nx1 env))
                      (svex-env-lookup (change-svar v :delay tag) env))))
    :hints (("Goal" :in-theory (e/d (svex-alist-eval svarlist-fix kvh-lookup-of-cons-pair)
                                    (svex-env-lookup-of-svex-alist-eval
                                     svex-env-boundp-iff-member-alist-keys
                                     svex-env-lookup-when-not-boundp))))))

; the fresh variables stand for the state after the first phase
(define kvh-free-ok ((keys svarlist-p) (kept svarlist-p) (tag natp)
                     (env svex-env-p) (st1 svex-env-p))
  (if (atom keys)
      t
    (and (or (and (member-equal (svar-fix (car keys)) (svarlist-fix kept)) t)
             (equal (svex-env-lookup (change-svar (car keys) :delay tag) env)
                    (svex-env-lookup (car keys) st1)))
         (kvh-free-ok (cdr keys) kept tag env st1)))
  ///
  (defthm kvh-free-lookup
    (implies (and (kvh-free-ok keys kept tag env st1)
                  (member-equal (svar-fix v) (svarlist-fix keys))
                  (not (member-equal (svar-fix v) (svarlist-fix kept))))
             (equal (svex-env-lookup (change-svar v :delay tag) env)
                    (svex-env-lookup v st1)))
    :hints (("Goal" :in-theory (enable svarlist-fix)))))

; THE SIGNALS qvals OF THE SECOND PHASE, as expressions over the state before
; the first phase, the inputs, and the fresh variables.
(define kvh-two-phase ((x fsm-p) (qvals svex-alist-p) (prev svex-alist-p)
                       (hi svtv-cyclephase-p) (lo svtv-cyclephase-p)
                       (kept svarlist-p) (tag natp))
  :returns (outs svex-alist-p)
  :verify-guards nil
  (b* (((mv ?o1 nx1) (svtv-cycle-step-phase-exprs prev hi x nil))
       (prev2 (kvh-mix-st (svex-alist-keys (fsm->nextstate x)) kept nx1 tag))
       ((mv outs2 ?nx2)
        (svtv-cycle-step-phase-exprs prev2 lo (change-fsm x :values qvals) nil)))
    outs2))

(local (defun kvh-cdr-ind (x) (if (atom x) x (kvh-cdr-ind (cdr x)))))

(local (defthm kvh-member-of-append-when-subsetp
         (implies (and (subsetp-equal vars (append a b))
                       (member-equal v vars)
                       (not (member-equal v a)))
                  (member-equal v b))))

; two step environments agree on a list of variables when the states agree
; on the state variables and the inputs agree on the others
(defthm kvh-step-envs-agree
  (implies (and (subsetp-equal (svarlist-fix vars)
                               (append (svex-alist-keys nx) (svarlist-fix nonstate)))
                (svex-envs-agree (svex-alist-keys nx) st1 st2)
                (svex-envs-agree nonstate in1 in2))
           (svex-envs-agree vars (fsm-step-env in1 st1 nx) (fsm-step-env in2 st2 nx)))
  :hints (("Goal" :induct (kvh-cdr-ind vars)
           :in-theory (e/d (svex-envs-agree svarlist-fix)
                           (svex-env-lookup-when-not-boundp
                            svex-env-boundp-iff-member-alist-keys))))
  :rule-classes nil)

; the mixed state agrees with the state after the first phase
(defthm kvh-mix-agrees
  (implies (and (subsetp-equal (svarlist-fix keys2) (svarlist-fix keys))
                (svex-envs-agree keys (svex-alist-eval nx1 env) st1)
                (kvh-free-ok keys kept tag env st1))
           (svex-envs-agree keys2
                            (svex-alist-eval (kvh-mix-st keys kept nx1 tag) env)
                            st1))
  :hints (("Goal" :induct (kvh-cdr-ind keys2)
           :in-theory (e/d (svex-envs-agree svarlist-fix)
                           (svex-env-lookup-of-svex-alist-eval
                            svex-env-lookup-when-not-boundp
                            svex-env-boundp-iff-member-alist-keys))))
  :rule-classes nil)

(defthm kvh-eval-of-two-phase
  (b* ((nx (fsm->nextstate x)))
    (implies (and (svtv-cyclephase->outputs-captured lo)
                  ;; the state the first phase starts from
                  (svex-envs-agree (svex-alist-keys nx) (svex-alist-eval prev env) st)
                  ;; the inputs of the two phases
                  (svex-envs-agree nonstate (svtv-cycle-step-fsm-inputs env hi) ehi)
                  (svex-envs-agree nonstate (svtv-cycle-step-fsm-inputs env lo) elo)
                  ;; the fresh variables are the state after the first phase
                  (kvh-free-ok (svex-alist-keys nx) kept tag env (fsm-step ehi st nx))
                  ;; what the machine's expressions read
                  (subsetp-equal (svex-alist-vars nx)
                                 (append (svex-alist-keys nx) (svarlist-fix nonstate)))
                  (subsetp-equal (svex-alist-vars qvals)
                                 (append (svex-alist-keys nx) (svarlist-fix nonstate))))
             (equal (svex-alist-eval (kvh-two-phase x qvals prev hi lo kept tag) env)
                    (svex-alist-eval qvals
                                     (fsm-step-env elo (fsm-step ehi st nx) nx)))))
  :hints (("Goal"
           :in-theory (e/d (kvh-two-phase
                            svtv-cycle-step-phase-outs-is-fsm-step-outs-of-fsm-inputs
                            svtv-cycle-step-phase-nextsts-is-fsm-step-of-fsm-inputs
                            fsm-step-outs fsm-step)
                           (svex-env-lookup-when-not-boundp
                            svex-env-boundp-iff-member-alist-keys))
           :use ((:instance svex-alist-eval-when-envs-agree
                  (x (fsm->nextstate x))
                  (env1 (fsm-step-env (svtv-cycle-step-fsm-inputs env hi)
                                      (svex-alist-eval prev env) (fsm->nextstate x)))
                  (env2 (fsm-step-env ehi st (fsm->nextstate x))))
                 (:instance kvh-step-envs-agree
                  (vars (svex-alist-vars (fsm->nextstate x)))
                  (nx (fsm->nextstate x))
                  (st1 (svex-alist-eval prev env)) (st2 st)
                  (in1 (svtv-cycle-step-fsm-inputs env hi)) (in2 ehi))
                 (:instance kvh-mix-agrees
                  (keys2 (svex-alist-keys (fsm->nextstate x)))
                  (keys (svex-alist-keys (fsm->nextstate x)))
                  (nx1 (mv-nth 1 (svtv-cycle-step-phase-exprs prev hi x nil)))
                  (st1 (svex-alist-eval (fsm->nextstate x)
                                        (fsm-step-env ehi st (fsm->nextstate x)))))
                 (:instance kvh-step-envs-agree
                  (vars (svex-alist-vars qvals))
                  (nx (fsm->nextstate x))
                  (st1 (svex-alist-eval
                        (kvh-mix-st (svex-alist-keys (fsm->nextstate x)) kept
                                    (mv-nth 1 (svtv-cycle-step-phase-exprs prev hi x nil))
                                    tag)
                        env))
                  (st2 (svex-alist-eval (fsm->nextstate x)
                                        (fsm-step-env ehi st (fsm->nextstate x))))
                  (in1 (svtv-cycle-step-fsm-inputs env lo)) (in2 elo))
                 (:instance svex-alist-eval-when-envs-agree
                  (x qvals)
                  (env1 (fsm-step-env
                         (svtv-cycle-step-fsm-inputs env lo)
                         (svex-alist-eval
                          (kvh-mix-st (svex-alist-keys (fsm->nextstate x)) kept
                                      (mv-nth 1 (svtv-cycle-step-phase-exprs prev hi x nil))
                                      tag)
                          env)
                         (fsm->nextstate x)))
                  (env2 (fsm-step-env elo
                                      (svex-alist-eval (fsm->nextstate x)
                                                       (fsm-step-env ehi st (fsm->nextstate x)))
                                      (fsm->nextstate x)))))
           :do-not-induct t))
  :rule-classes nil)

; The fresh variables of a tag, in order.
(define kvh-tagged ((keys svarlist-p) (kept svarlist-p) (tag natp))
  :returns (vars svarlist-p)
  (if (atom keys)
      nil
    (if (member-equal (svar-fix (car keys)) (svarlist-fix kept))
        (kvh-tagged (cdr keys) kept tag)
      (cons (change-svar (car keys) :delay tag)
            (kvh-tagged (cdr keys) kept tag))))
  ///
  (defthm kvh-member-of-tagged
    (implies (and (member-equal (svar-fix v) (svarlist-fix keys))
                  (not (member-equal (svar-fix v) (svarlist-fix kept))))
             (member-equal (change-svar v :delay tag) (kvh-tagged keys kept tag)))
    :hints (("Goal" :in-theory (enable svarlist-fix)))))

; The fresh variables of a tag bound to a state's values.
(define kvh-free-env ((keys svarlist-p) (kept svarlist-p) (tag natp) (st1 svex-env-p))
  :returns (env svex-env-p)
  (if (atom keys)
      nil
    (if (member-equal (svar-fix (car keys)) (svarlist-fix kept))
        (kvh-free-env (cdr keys) kept tag st1)
      (cons (cons (change-svar (car keys) :delay tag)
                  (svex-env-lookup (car keys) st1))
            (kvh-free-env (cdr keys) kept tag st1))))
  ///
  (defthm kvh-keys-of-free-env
    (equal (alist-keys (kvh-free-env keys kept tag st1))
           (kvh-tagged keys kept tag))
    :hints (("Goal" :in-theory (enable alist-keys kvh-tagged))))
  (defthm kvh-free-env-boundp
    (iff (svex-env-boundp v (kvh-free-env keys kept tag st1))
         (member-equal (svar-fix v) (kvh-tagged keys kept tag)))
    :hints (("Goal" :in-theory (e/d (svex-env-boundp kvh-tagged)
                                    (svex-env-boundp-iff-member-alist-keys))
             :induct (kvh-free-env keys kept tag st1))))
  (defthm kvh-free-env-lookup
    (implies (and (no-duplicatesp-equal (kvh-tagged keys kept tag))
                  (member-equal (svar-fix v) (svarlist-fix keys))
                  (not (member-equal (svar-fix v) (svarlist-fix kept))))
             (equal (svex-env-lookup (change-svar v :delay tag)
                                     (kvh-free-env keys kept tag st1))
                    (svex-env-lookup v st1)))
    :hints (("Goal" :in-theory (e/d (svarlist-fix kvh-lookup-of-cons-pair kvh-tagged)
                                    (svex-env-boundp-iff-member-alist-keys
                                     svex-env-lookup-when-not-boundp
                                     kvh-member-of-tagged))
             :induct (kvh-free-env keys kept tag st1))
            (and stable-under-simplificationp
                 '(:use ((:instance kvh-member-of-tagged (keys (cdr keys)))))))))

; THE ENVIRONMENT in which the two machines' expressions are evaluated: the
; fresh variables of each (tags 2 and 3) bound to that machine's state after
; the first phase, over the state and the inputs.
(define kvh-estar ((keys svarlist-p) (kept svarlist-p)
                   (st1c svex-env-p) (st1h svex-env-p)
                   (st svex-env-p) (in svex-env-p))
  :returns (env svex-env-p)
  (append (kvh-free-env keys kept 2 st1c)
          (kvh-free-env keys kept 3 st1h)
          (svex-env-extract keys st)
          (svex-env-fix in))
  ///
  ; an ordinary variable: from the state if it is a state variable, else an input
  (defthm kvh-estar-lookup
    (implies (and (not (member-equal (svar-fix w) (kvh-tagged keys kept 2)))
                  (not (member-equal (svar-fix w) (kvh-tagged keys kept 3))))
             (equal (svex-env-lookup w (kvh-estar keys kept st1c st1h st in))
                    (if (member-equal (svar-fix w) (svarlist-fix keys))
                        (svex-env-lookup w st)
                      (svex-env-lookup w in)))))
  (defthm kvh-estar-lookup-2
    (implies (and (no-duplicatesp-equal (kvh-tagged keys kept 2))
                  (member-equal (svar-fix v) (svarlist-fix keys))
                  (not (member-equal (svar-fix v) (svarlist-fix kept))))
             (equal (svex-env-lookup (change-svar v :delay 2)
                                     (kvh-estar keys kept st1c st1h st in))
                    (svex-env-lookup v st1c))))
  (defthm kvh-estar-lookup-3
    (implies (and (no-duplicatesp-equal (kvh-tagged keys kept 3))
                  (not (intersectp-equal (kvh-tagged keys kept 3) (kvh-tagged keys kept 2)))
                  (member-equal (svar-fix v) (svarlist-fix keys))
                  (not (member-equal (svar-fix v) (svarlist-fix kept))))
             (equal (svex-env-lookup (change-svar v :delay 3)
                                     (kvh-estar keys kept st1c st1h st in))
                    (svex-env-lookup v st1h)))
    :hints (("Goal" :use ((:instance kvh-not-member-when-not-intersectp
                           (x (kvh-tagged keys kept 3)) (y (kvh-tagged keys kept 2))
                           (v (change-svar v :delay 3)))
                          (:instance kvh-member-of-tagged (tag 3)))
             :in-theory (disable kvh-not-member-when-not-intersectp
                                 kvh-member-of-tagged)))))

(defthm kvh-estar-free-ok-2
  (implies (and (no-duplicatesp-equal (kvh-tagged keys kept 2))
                (subsetp-equal (svarlist-fix keys2) (svarlist-fix keys)))
           (kvh-free-ok keys2 kept 2 (kvh-estar keys kept st1c st1h st in) st1c))
  :hints (("Goal" :induct (kvh-cdr-ind keys2)
           :in-theory (e/d (kvh-free-ok svarlist-fix) (kvh-estar)))))

(defthm kvh-estar-free-ok-3
  (implies (and (no-duplicatesp-equal (kvh-tagged keys kept 3))
                (not (intersectp-equal (kvh-tagged keys kept 3) (kvh-tagged keys kept 2)))
                (subsetp-equal (svarlist-fix keys2) (svarlist-fix keys)))
           (kvh-free-ok keys2 kept 3 (kvh-estar keys kept st1c st1h st in) st1h))
  :hints (("Goal" :induct (kvh-cdr-ind keys2)
           :in-theory (e/d (kvh-free-ok svarlist-fix) (kvh-estar)))))

; the state the first phase starts from, when the state holds the constants
(defthm kvh-estar-prev-st
  (implies (and (kvh-env-has consts st)
                (not (intersectp-equal (svarlist-fix keys) (kvh-tagged keys kept 2)))
                (not (intersectp-equal (svarlist-fix keys) (kvh-tagged keys kept 3))))
           (svex-envs-agree keys
                            (svex-alist-eval (kvh-prev-st keys consts)
                                             (kvh-estar keys kept st1c st1h st in))
                            st))
  :hints (("Goal"
           :expand ((:with svex-envs-agree-by-witness
                     (svex-envs-agree keys
                                      (svex-alist-eval (kvh-prev-st keys consts)
                                                       (kvh-estar keys kept st1c st1h st in))
                                      st)))
           :use ((:instance kvh-not-member-when-not-intersectp
                  (x (svarlist-fix keys)) (y (kvh-tagged keys kept 2))
                  (v (svar-fix (svex-envs-disagree-witness
                                keys
                                (svex-alist-eval (kvh-prev-st keys consts)
                                                 (kvh-estar keys kept st1c st1h st in))
                                st))))
                 (:instance kvh-not-member-when-not-intersectp
                  (x (svarlist-fix keys)) (y (kvh-tagged keys kept 3))
                  (v (svar-fix (svex-envs-disagree-witness
                                keys
                                (svex-alist-eval (kvh-prev-st keys consts)
                                                 (kvh-estar keys kept st1c st1h st in))
                                st)))))
           :in-theory (disable kvh-not-member-when-not-intersectp
                               svex-env-lookup-of-svex-alist-eval
                               svex-env-lookup-when-not-boundp
                               svex-env-boundp-iff-member-alist-keys
                               kvh-estar)
           :do-not-induct t)))

; A phase with more constants.  They are put after the phase's own, so that
; they bind only what the phase leaves to the inputs.
(define kvh-phase-with ((ph svtv-cyclephase-p) (extra svex-env-p))
  :returns (new svtv-cyclephase-p)
  (change-svtv-cyclephase ph :constants (append (svtv-cyclephase->constants ph)
                                                (svex-env-fix extra)))
  ///
  (defthm kvh-phase-with-outputs-captured
    (equal (svtv-cyclephase->outputs-captured (kvh-phase-with ph extra))
           (svtv-cyclephase->outputs-captured ph)))
  (defthm kvh-phase-with-inputs-free
    (equal (svtv-cyclephase->inputs-free (kvh-phase-with ph extra))
           (svtv-cyclephase->inputs-free ph)))
  (defthm kvh-phase-with-constants
    (equal (svtv-cyclephase->constants (kvh-phase-with ph extra))
           (append (svtv-cyclephase->constants ph) (svex-env-fix extra)))))

; the inputs of a phase that takes inputs, with constants the inputs hold
(defthm kvh-estar-phase-inputs
  (implies (and (svtv-cyclephase->inputs-free ph)
                (kvh-env-has extra in)
                (subsetp-equal (svarlist-fix ns2) (svarlist-fix nonstate))
                (not (intersectp-equal (svarlist-fix nonstate) (svarlist-fix keys)))
                (not (intersectp-equal (svarlist-fix nonstate) (kvh-tagged keys kept 2)))
                (not (intersectp-equal (svarlist-fix nonstate) (kvh-tagged keys kept 3))))
           (svex-envs-agree ns2
                            (svtv-cycle-step-fsm-inputs (kvh-estar keys kept st1c st1h st in)
                                                        (kvh-phase-with ph extra))
                            (svtv-cycle-step-fsm-inputs in ph)))
  :hints (("Goal" :induct (kvh-cdr-ind ns2)
           :in-theory (e/d (svtv-cycle-step-fsm-inputs svex-envs-agree svarlist-fix)
                           (svex-env-lookup-when-not-boundp
                            svex-env-boundp-iff-member-alist-keys
                            kvh-estar)))))

; a phase that takes no inputs has the same inputs whatever the cycle's are
(defthm kvh-phase-inputs-when-not-free
  (implies (not (svtv-cyclephase->inputs-free ph))
           (equal (svtv-cycle-step-fsm-inputs e1 ph)
                  (svtv-cyclephase->constants ph)))
  :hints (("Goal" :in-theory (enable svtv-cycle-step-fsm-inputs))))

; ===========================================================================
; F. A cycle of two phases, outputs captured in the second.
; ===========================================================================
(defthm kvh-cycle-step-outs
  (implies (and (not (svtv-cyclephase->outputs-captured hi))
                (svtv-cyclephase->outputs-captured lo))
           (equal (fsm-step-outs in st (fsm-to-cycle (list hi lo) x simp))
                  (fsm-step-outs (svtv-cycle-step-fsm-inputs in lo)
                                 (fsm-step (svtv-cycle-step-fsm-inputs in hi) st
                                           (fsm->nextstate x))
                                 x)))
  :hints (("Goal" :in-theory (enable svtv-cycle-fsm-inputs svtv-cycle-output-phase
                                     svtv-cyclephaselist-has-outputs-captured)
           :expand ((:free (a b st x) (fsm-eval (cons a b) st x))
                    (:free (st x) (fsm-eval nil st x))
                    (:free (a b) (svtv-cyclephaselist-has-outputs-captured (cons a b)))))))

(defthm kvh-cycle-step
  (equal (fsm-step in st (fsm->nextstate (fsm-to-cycle (list hi lo) x simp)))
         (svex-env-extract (svex-alist-keys (fsm->nextstate x))
                           (fsm-step (svtv-cycle-step-fsm-inputs in lo)
                                     (fsm-step (svtv-cycle-step-fsm-inputs in hi) st
                                               (fsm->nextstate x))
                                     (fsm->nextstate x))))
  :hints (("Goal" :in-theory (enable svtv-cycle-fsm-inputs)
           :expand ((:free (a b st x) (fsm-final-state (cons a b) st x))
                    (:free (st x) (fsm-final-state nil st x))))))

; ===========================================================================
; G. Small facts used when the lemmas above are applied.
; ===========================================================================
(defthm kvh-env-has-of-append
  (equal (kvh-env-has (append a b) e)
         (and (kvh-env-has a e) (kvh-env-has b e)))
  :hints (("Goal" :in-theory (enable kvh-env-has))))

; a list of override tests, each left unset
(define kvh-test-x-env-p (consts)
  (if (atom consts)
      t
    (and (consp (car consts))
         (svar-p (caar consts))
         (svar-override-p (caar consts) :test)
         (equal (cdar consts) (4vec-x))
         (kvh-test-x-env-p (cdr consts))))
  ///
  (defthm kvh-env-has-test-x-when-plain
    (implies (and (kvh-test-x-env-p consts)
                  (kv-plain-env-p e))
             (kvh-env-has consts e))
    :hints (("Goal" :in-theory (enable kvh-env-has)))))

(defthm kvh-env-vals-of-append
  (equal (kvh-env-vals (append a b) e)
         (append (kvh-env-vals a e) (kvh-env-vals b e)))
  :hints (("Goal" :in-theory (enable kvh-env-vals))))

(defthm kvh-zx-vals-of-append
  (equal (kvh-zx-vals (append a b) e)
         (append (kvh-zx-vals a e) (kvh-zx-vals b e)))
  :hints (("Goal" :in-theory (enable kvh-zx-vals))))

(defthm kvh-2vec-list-p-of-append
  (equal (kvh-2vec-list-p (append a b))
         (and (kvh-2vec-list-p a) (kvh-2vec-list-p b)))
  :hints (("Goal" :in-theory (enable kvh-2vec-list-p))))

(defthm kvh-delay-nw-of-append
  (equal (kvh-delay-nw (append a b))
         (append (kvh-delay-nw a) (kvh-delay-nw b)))
  :hints (("Goal" :in-theory (enable kvh-delay-nw))))

(defthm kvh-strip-cars-of-append
  (equal (strip-cars (append a b))
         (append (strip-cars a) (strip-cars b))))

; two step environments agree on stored variables on which the states agree
(defthm kvh-step-envs-agree-on-state
  (implies (and (subsetp-equal (svarlist-fix vars) (svex-alist-keys nx))
                (svex-envs-agree vars st1 st2))
           (svex-envs-agree vars (fsm-step-env in1 st1 nx) (fsm-step-env in2 st2 nx)))
  :hints (("Goal" :induct (kvh-cdr-ind vars)
           :in-theory (e/d (svex-envs-agree svarlist-fix)
                           (svex-env-lookup-when-not-boundp
                            svex-env-boundp-iff-member-alist-keys))))
  :rule-classes nil)

; a variable that is not stored comes from the step's inputs
(defthm kvh-zx-vals-of-fsm-step-env-inputs
  (implies (not (intersectp-equal (svarlist-fix (strip-cars nw)) (svex-alist-keys nx)))
           (equal (kvh-zx-vals nw (fsm-step-env in st nx))
                  (kvh-zx-vals nw in)))
  :hints (("Goal" :in-theory (e/d (kvh-zx-vals svarlist-fix intersectp-equal)
                                  (svex-env-lookup-when-not-boundp
                                   svex-env-boundp-iff-member-alist-keys)))))

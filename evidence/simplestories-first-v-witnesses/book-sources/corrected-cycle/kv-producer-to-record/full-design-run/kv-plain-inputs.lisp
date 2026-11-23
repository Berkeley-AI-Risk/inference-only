; Inputs that bind no override-test variable set no override.
;
; Private.  Part of the full-design run; see README.md in this directory.
;
; Two hypotheses of the K/V theorems, kv-reset-held-at and
; kv-environment-ok-at, contain a conjunct of the form
;   (svex-envlists-ovtestsimilar (take m (nthcdr k envs)) '(nil ... nil)),
; "the inputs of these cycles set no override of an internal signal".  It
; quantifies over all variable names, so ACL2 cannot evaluate it.  This book
; proves that it follows from a condition ACL2 can evaluate: no input list
; binds an override-test variable (kv-plain-envlist-p).
(in-package "SV")
(include-book "centaur/sv/svtv/svtv-to-fsm-defs" :dir :system)

; every key of the input list is a variable that is not an override test
(defun kv-plain-env-p (env)
  (declare (xargs :guard t))
  (or (atom env)
      (and (consp (car env))
           (svar-p (car (car env)))
           (not (svar-override-p (car (car env)) :test))
           (kv-plain-env-p (cdr env)))))
(defun kv-plain-envlist-p (envs)
  (declare (xargs :guard t))
  (or (atom envs)
      (and (kv-plain-env-p (car envs))
           (kv-plain-envlist-p (cdr envs)))))

(local (defthm kv-plain-env-binds-no-override-test
         (implies (and (kv-plain-env-p env)
                       (svar-override-p k :test))
                  (not (hons-assoc-equal (svar-fix k) env)))))

; one input list: every override-test variable is unbound in it, as in the
; empty list
(defthm kv-plain-env-sets-no-override
  (implies (kv-plain-env-p env)
           (svex-envs-ovtestsimilar env nil))
  :hints (("Goal" :in-theory (enable svex-envs-ovtestsimilar svex-env-lookup))))

(local (defthm kv-plain-envlist-p-of-nthcdr
         (implies (kv-plain-envlist-p envs)
                  (kv-plain-envlist-p (nthcdr k envs)))))
(local (defthm kv-plain-envlist-p-of-repeat-nil
         (kv-plain-envlist-p (repeat m nil))
         :hints (("Goal" :in-theory (enable repeat)))))
(local (defthm kv-plain-envlist-p-of-take
         (implies (kv-plain-envlist-p envs)
                  (kv-plain-envlist-p (take m envs)))))
(local (defthm kv-plain-envlist-sets-no-override
         (implies (kv-plain-envlist-p x)
                  (svex-envlists-ovtestsimilar x (repeat (len x) nil)))
         :hints (("Goal" :in-theory (enable svex-envlists-ovtestsimilar repeat)))))

(local (defthm kv-len-of-take
         (equal (len (take m x)) (nfix m))))

; The conjunct as it stands in kv-environment-ok-at (two cycles) and in
; kv-reset-held-at (three cycles): x is (nthcdr k envs) there.
(defthm kv-plain-inputs-set-no-override-in-two-cycles
  (implies (kv-plain-envlist-p (take 2 x))
           (svex-envlists-ovtestsimilar (take 2 x) '(nil nil)))
  :hints (("Goal" :use ((:instance kv-plain-envlist-sets-no-override (x (take 2 x))))
           :in-theory (disable kv-plain-envlist-sets-no-override)))
  :rule-classes nil)
(defthm kv-plain-inputs-set-no-override-in-three-cycles
  (implies (kv-plain-envlist-p (take 3 x))
           (svex-envlists-ovtestsimilar (take 3 x) '(nil nil nil)))
  :hints (("Goal" :use ((:instance kv-plain-envlist-sets-no-override (x (take 3 x))))
           :in-theory (disable kv-plain-envlist-sets-no-override)))
  :rule-classes nil)

; The theorem kv-step-to-record with hypotheses ACL2 can evaluate.
;
; Private.  Part of the full-design run; see README.md in this directory.
;
; Two hypotheses of kv-step-to-record, kv-reset-held-at and
; kv-environment-ok-at (through kv-environment-ok-from), each contain one
; conjunct that ACL2 cannot evaluate, because it quantifies over all
; variable names:
;   (svex-envlists-ovtestsimilar (take m (nthcdr k envs)) '(nil ... nil)),
; "the inputs of these cycles set no override of an internal signal".
;
; This book defines kv-reset-held-at-evaluable and
; kv-environment-ok-at-evaluable: the two definitions' own bodies, taken
; from the logical world, with that one call replaced by
;   (kv-plain-envlist-p (take m (nthcdr k envs))),
; "no input list of these cycles binds an override-test variable"
; (kv-plain-inputs.lisp proves that the one implies the other).  It proves
; that each evaluable hypothesis implies the original, and restates the
; theorem with them:
;
;   kv-step-to-record-evaluable
;   kv-step-to-record-evaluable-layer-0-position-0
;
; Every hypothesis of these two can be evaluated on a given execution
; (fsm-eval envs initst (probe-fsm)).  When they evaluate to T, the
; conclusion holds of that execution by this theorem.
(in-package "SV")
(include-book "../kv-step-to-record")
(include-book "kv-plain-inputs")

; the bodies below bind variables they do not use, as the originals do
(set-ignore-ok t)
(set-irrelevant-formals-ok t)

; A term with every call of svex-envlists-ovtestsimilar replaced by a call of
; kv-plain-envlist-p on its first argument; and the number of such calls.
(local
 (mutual-recursion
  (defun kvx-subst (term)
    (declare (xargs :mode :program))
    (cond ((atom term) term)
          ((eq (car term) 'quote) term)
          ((eq (car term) 'svex-envlists-ovtestsimilar)
           (list 'kv-plain-envlist-p (kvx-subst (cadr term))))
          ((consp (car term))
           (cons (list 'lambda (cadr (car term)) (kvx-subst (caddr (car term))))
                 (kvx-subst-lst (cdr term))))
          (t (cons (car term) (kvx-subst-lst (cdr term))))))
  (defun kvx-subst-lst (terms)
    (declare (xargs :mode :program))
    (if (atom terms)
        nil
      (cons (kvx-subst (car terms)) (kvx-subst-lst (cdr terms)))))))
(local
 (mutual-recursion
  (defun kvx-count (term)
    (declare (xargs :mode :program))
    (cond ((atom term) 0)
          ((eq (car term) 'quote) 0)
          ((eq (car term) 'svex-envlists-ovtestsimilar) 1)
          ((consp (car term))
           (+ (kvx-count (caddr (car term))) (kvx-count-lst (cdr term))))
          (t (kvx-count-lst (cdr term)))))
  (defun kvx-count-lst (terms)
    (declare (xargs :mode :program))
    (if (atom terms) 0 (+ (kvx-count (car terms)) (kvx-count-lst (cdr terms)))))))

(make-event
 (b* ((wrld (w state))
      (body1 (getpropc 'kv-reset-held-at 'acl2::unnormalized-body nil wrld))
      (body2 (getpropc 'kv-environment-ok-at 'acl2::unnormalized-body nil wrld))
      ((unless (and (equal (kvx-count body1) 1) (equal (kvx-count body2) 1)))
       (er hard 'kv-step-to-record-evaluable
           "expected one call of svex-envlists-ovtestsimilar in each definition, found ~x0 and ~x1"
           (kvx-count body1) (kvx-count body2))))
   `(progn
      (defun kv-reset-held-at-evaluable ,(acl2::formals 'kv-reset-held-at wrld)
        (declare (xargs :verify-guards nil))
        ,(kvx-subst body1))
      (defun kv-environment-ok-at-evaluable ,(acl2::formals 'kv-environment-ok-at wrld)
        (declare (xargs :verify-guards nil))
        ,(kvx-subst body2))
      (value-triple (acl2::cw "~%KVX one conjunct replaced in each of kv-reset-held-at and kv-environment-ok-at~%")))))

; Each evaluable hypothesis implies the original.  With only the two
; definitions opened, the two sides are the same conjunction apart from the
; replaced conjunct, which kv-plain-inputs.lisp supplies.
(defthm kv-environment-ok-at-when-evaluable
  (implies (kv-environment-ok-at-evaluable k envs outs)
           (kv-environment-ok-at k envs outs))
  :hints (("Goal" :use ((:instance kv-plain-inputs-set-no-override-in-two-cycles
                                   (x (nthcdr k envs))))
           :in-theory (union-theories (theory 'minimal-theory)
                                      '(kv-environment-ok-at-evaluable kv-environment-ok-at))))
  :rule-classes nil)
(defthm kv-reset-held-at-when-evaluable
  (implies (kv-reset-held-at-evaluable r envs outs)
           (kv-reset-held-at r envs outs))
  :hints (("Goal" :use ((:instance kv-plain-inputs-set-no-override-in-three-cycles
                                   (x (nthcdr r envs))))
           :in-theory (union-theories (theory 'minimal-theory)
                                      '(kv-reset-held-at-evaluable kv-reset-held-at))))
  :rule-classes nil)
(in-theory (disable kv-reset-held-at-evaluable kv-environment-ok-at-evaluable))
(value-triple (acl2::cw "~%KVX-AT proved~%"))

; as kv-environment-ok-from
(defun kv-environment-ok-from-evaluable (j n envs outs)
  (declare (xargs :verify-guards nil :measure (nfix (- (nfix n) (nfix j)))))
  (if (zp (- (nfix n) (nfix j)))
      t
    (and (kv-environment-ok-at-evaluable (nfix j) envs outs)
         (kv-environment-ok-from-evaluable (+ 1 (nfix j)) n envs outs))))
(defthm kv-environment-ok-from-when-evaluable
  (implies (kv-environment-ok-from-evaluable j n envs outs)
           (kv-environment-ok-from j n envs outs))
  :hints (("Goal" :induct (kv-environment-ok-from-evaluable j n envs outs)
           :in-theory (e/d (kv-environment-ok-from kv-environment-ok-from-evaluable)
                           (kv-environment-ok-at)))
          ("Subgoal *1/2" :use ((:instance kv-environment-ok-at-when-evaluable (k (nfix j))))))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVX-FROM proved~%"))

; ---------------------------------------------------------------------------
; THE THEOREM, with every hypothesis evaluable.  The statement is
; kv-step-to-record's with kv-reset-held-at and kv-environment-ok-from
; replaced by their evaluable versions.
; ---------------------------------------------------------------------------
(defthm kv-step-to-record-evaluable
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (ps (kv-pass-start-cycle b outs))
       (s (kv-step-cycle b envs outs))
       (keys (kv-key-results b outs))
       (values (kv-value-results b outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at-evaluable r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-producer-storage-definite-at (+ 2 r) outs)
                  (kv-environment-ok-from-evaluable (+ 2 r) (+ 1 n) envs outs)
                  (kv-producer-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-shell-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs))
             (and ;; one accepted public STEP, identified by its handshake
                  (natp s) (< (+ 2 r) s) (< s ps) (< ps b) (< b j) (<= j n)
                  (kv-step-accepted-at s envs outs)
                  (kv-shell-working-since s b envs outs)
                  (kv-pass-started-by-shell-at ps (kv-staged-position b outs) outs)
                  ;; the producer's work in the pass that STEP's processing started
                  (kv-producer-work-identified b outs)
                  (kv-all-coordinates-produced keys)
                  (kv-all-coordinates-produced values)
                  ;; the begin, the staging and the record
                  (kv-staging-begin-accepted-at b envs outs)
                  (kv-staging-uninterrupted b j envs outs)
                  (kv-record-uninterrupted j n envs outs)
                  ;; the eighteen writes
                  (equal (kv-endpoint-writes j (+ 1 n) envs outs)
                         (kv-reference-record (kv-staged-layer b outs)
                                              (kv-staged-position b outs)
                                              (kv-final-exponent keys)
                                              (kv-final-exponent values)
                                              (kv-produced-transfers keys values))))))
  :hints (("Goal"
           :use ((:instance kv-step-to-record)
                 (:instance kv-reset-held-at-when-evaluable
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kv-environment-ok-from-when-evaluable
                  (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (theory 'minimal-theory)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVX-THEOREM proved~%"))

(defthm kv-step-to-record-evaluable-layer-0-position-0
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (ps (kv-pass-start-cycle b outs))
       (s (kv-step-cycle b envs outs))
       (keys (kv-key-results b outs))
       (values (kv-value-results b outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at-evaluable r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-producer-storage-definite-at (+ 2 r) outs)
                  (kv-environment-ok-from-evaluable (+ 2 r) (+ 1 n) envs outs)
                  (kv-producer-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-shell-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs)
                  (equal (kv-staged-layer b outs) 0)
                  (equal (kv-staged-position b outs) 0))
             (and ;; one accepted public STEP, identified by its handshake
                  (natp s) (< (+ 2 r) s) (< s ps) (< ps b) (< b j) (<= j n)
                  (kv-step-accepted-at s envs outs)
                  (kv-shell-working-since s b envs outs)
                  (kv-pass-started-by-shell-at ps 0 outs)
                  ;; the producer's work in the pass that STEP's processing started
                  (kv-producer-work-identified b outs)
                  (kv-all-coordinates-produced keys)
                  (kv-all-coordinates-produced values)
                  ;; the begin, the staging and the record
                  (kv-staging-begin-accepted-at b envs outs)
                  (kv-staging-uninterrupted b j envs outs)
                  (kv-record-uninterrupted j n envs outs)
                  ;; the eighteen writes
                  (equal (kv-endpoint-writes j (+ 1 n) envs outs)
                         (kv-reference-record 0
                                              0
                                              (kv-final-exponent keys)
                                              (kv-final-exponent values)
                                              (kv-produced-transfers keys values))))))
  :hints (("Goal"
           :use ((:instance kv-step-to-record-evaluable))
           :in-theory (theory 'minimal-theory)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVX-THEOREM-0 proved~%"))

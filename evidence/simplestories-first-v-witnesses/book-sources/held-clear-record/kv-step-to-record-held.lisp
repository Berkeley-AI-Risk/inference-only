; THE K/V RECORD THEOREM ON THE HELD-INPUT CLOCK MODEL.
;
; Private.  See README.md in this directory.
;
; This is the top-level book.  It imports two certified results and joins
; them:
;
;   kv-step-to-record-evaluable        (the corrected-cycle chain,
;       ../corrected-cycle/kv-producer-to-record/full-design-run/)
;       On the corrected-cycle machine (probe-fsm): a completed K/V record
;       has the eighteen accepted address/data writes of the reference
;       record of one identified public STEP, its staging and its 128
;       rotary-K and 128 projected-V results.
;
;   kvh-held-machine-agrees-with-corrected-cycle        (kvh-correspondence)
;       On a legal history from a state in reset, the held-input machine
;       (probe-fsm-held) and the corrected-cycle machine produce the same
;       sampled signals in every cycle.
;
;   kv-step-to-record-held
;       THE THEOREM.  The first statement, about the held-input machine:
;       every hypothesis is stated on the held-input execution, and so is
;       the conclusion.
;
;   kv-step-to-record-held-layer-0-position-0
;       The same when the completed record's staged layer and position are
;       both 0.
;
; THE MACHINE.  One step of (probe-fsm-held) is one clock cycle of the pinned
; probe module: a clock-high phase and a clock-low phase, with the cycle's
; inputs -- clear_i and reset_n_i among them -- applied in both.  The signals
; of the clock-low phase are the cycle's sampled signals.
;
; THE HYPOTHESES, all evaluable by ACL2 on a given execution:
;   the clock, reset and input contract
;     (kvh-reset-state-p initst)      the start state is a state in reset: its
;                                     stored clock levels are low and its
;                                     stored root reset and seven derived
;                                     resets are asserted
;     (kvh-reset-input-p (car envs))  the first cycle asserts reset
;     (kvh-legal-history-p envs outs) in every cycle the inputs set no
;                                     override and reset_n_i and clear_i are
;                                     0 or 1; reset_n_i, once 1, stays 1; and
;                                     in every cycle the seven derived reset
;                                     nets and the six registers they are
;                                     computed from are two-valued
;   the hypotheses of kv-step-to-record-evaluable, unchanged, on outs
;
; The statements of those hypotheses and of the conclusion are in the
; corrected-cycle chain's books; nothing about them is changed here.
(in-package "SV")
(include-book "../corrected-cycle/kv-producer-to-record/full-design-run/kv-step-to-record-evaluable")
(include-book "kvh-correspondence")

(defthm kv-step-to-record-held
  (b* ((outs (fsm-eval envs initst (probe-fsm-held)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (ps (kv-pass-start-cycle b outs))
       (s (kv-step-cycle b envs outs))
       (keys (kv-key-results b outs))
       (values (kv-value-results b outs)))
    (implies (and ;; the clock, reset and input contract of the held-input model
                  (kvh-reset-state-p initst)
                  (consp envs)
                  (kvh-reset-input-p (car envs))
                  (kvh-legal-history-p envs outs)
                  ;; the hypotheses of the K/V record theorem
                  (natp r) (natp n) (<= (+ 2 r) n)
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
           :use ((:instance kv-step-to-record-evaluable)
                 (:instance kvh-held-machine-agrees-with-corrected-cycle))
           :in-theory (theory 'minimal-theory)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVH-THEOREM proved~%"))

(defthm kv-step-to-record-held-layer-0-position-0
  (b* ((outs (fsm-eval envs initst (probe-fsm-held)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (ps (kv-pass-start-cycle b outs))
       (s (kv-step-cycle b envs outs))
       (keys (kv-key-results b outs))
       (values (kv-value-results b outs)))
    (implies (and ;; the clock, reset and input contract of the held-input model
                  (kvh-reset-state-p initst)
                  (consp envs)
                  (kvh-reset-input-p (car envs))
                  (kvh-legal-history-p envs outs)
                  ;; the hypotheses of the K/V record theorem
                  (natp r) (natp n) (<= (+ 2 r) n)
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
           :use ((:instance kv-step-to-record-evaluable-layer-0-position-0)
                 (:instance kvh-held-machine-agrees-with-corrected-cycle))
           :in-theory (theory 'minimal-theory)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVH-THEOREM-0 proved~%"))

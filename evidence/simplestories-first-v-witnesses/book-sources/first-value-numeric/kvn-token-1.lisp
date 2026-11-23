; THE FIRST VALUE COORDINATE OF A COMPLETED RECORD, FOR TOKEN 1.
;
; Private.  See README.md in this directory.
;
; One execution of the held-input machine (probe-fsm-held): from the state
; with every stored variable 0, the 68,605 clock cycles of inputs of
; kvn-inputs-token-1 -- a reset, one APPEND of token 1, one STEP, and a
; memory behind the raw word port that holds the model image -- with the
; read-only memories bound to the contents of kvn-rom.  The K/V record of
; layer 0, position 0 is reported complete at cycle 68,596.
;
;   kvn-token-1-first-value
;       THE THEOREM.  On this execution the contract and every hypothesis of
;       the K/V record theorem hold; the memory contract and the read-only
;       memories' contents hold; the STEP is accepted in cycle 8 and its
;       token is 1; and the accepted write at word address 227081 has the
;       specification's first V mantissa of token 1, -6191, in its bits
;       [15:0], and the write at 227089 the specification's V exponent, -16,
;       in its bits [7:0].  All 128 V mantissas of the record are the
;       specification's.
;
; Quantifiers: none.  It is a statement about one execution, proved by
; ACL2 evaluating both sides: the execution with the library's fsm-eval and
; the books' own predicates, the specification with ssv-spec's definitions.
(in-package "SV")
(include-book "kvn-witness")
(include-book "ssv-image")
(include-book "ssv-values")
(include-book "kvn-rom")
(include-book "kvn-inputs-token-1")

; Remembering the answers of two recognizers the library's functions check
; on every call.  This changes no value.
(local (memoize 'svex-env-p :recursive nil))
(local (memoize 'svex-envlist-p))

; ---------------------------------------------------------------------------
; The evaluation.  (kvn-fast-all is the identity, and kvn-envlist-ok is
; true of a list of environments; see kvn-witness.  Each list is asked
; about before a library function is called on it.)
; ---------------------------------------------------------------------------
(define kvn-token-1-evaluated () :verify-guards nil
  (b* ((envs (kvn-envs (kvn-tuples-token-1) (kvn-rom)))
       ((unless (kvn-envlist-ok envs)) nil)
       (initst (kvn-zero-state))
       (outs (kvn-fast-all (fsm-eval envs initst (probe-fsm-held))))
       ((unless (kvn-envlist-ok outs)) nil))
    (kvn-ordinary-step-statement 1 68596 envs initst outs
                                 (acl2::ssv-image) (kvn-rom)))
  ///
  (in-theory (disable (:e kvn-token-1-evaluated))))

(defthm kvn-token-1-evaluated-is-true
  (kvn-token-1-evaluated)
  :hints (("Goal" :in-theory '((:e kvn-token-1-evaluated))))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVN-TOKEN-1 evaluated~%"))

; ---------------------------------------------------------------------------
; The statement about the execution as the library defines it.
; ---------------------------------------------------------------------------
(defthm kvn-token-1-ordinary-step
  (b* ((envs (kvn-envs (kvn-tuples-token-1) (kvn-rom)))
       (initst (kvn-zero-state))
       (outs (fsm-eval envs initst (probe-fsm-held))))
    (kvn-ordinary-step-statement 1 68596 envs initst outs
                                 (acl2::ssv-image) (kvn-rom)))
  :hints (("Goal"
           :use ((:instance kvn-token-1-evaluated-is-true))
           :in-theory '(kvn-token-1-evaluated kvn-fast-all-is-identity)))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; THE THEOREM, written out.
; ---------------------------------------------------------------------------
(defthm kvn-token-1-first-value
  (b* ((envs (kvn-envs (kvn-tuples-token-1) (kvn-rom)))
       (initst (kvn-zero-state))
       (outs (fsm-eval envs initst (probe-fsm-held)))
       (image (acl2::ssv-image))
       (n 68596)
       (r 0)
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (s (kv-step-cycle b envs outs))
       (values (kv-value-results b outs))
       (writes (kv-endpoint-writes j (+ 1 n) envs outs)))
    (and ;; (1) the clock, reset and input contract of the held-input model
         (kvh-reset-state-p initst)
         (consp envs)
         (kvh-reset-input-p (car envs))
         (kvh-legal-history-p envs outs)
         ;; (2) the hypotheses of the K/V record theorem, layer 0, position 0
         (kv-reset-held-at-evaluable r envs outs)
         (kv-payload-storage-definite-at (+ 2 r) envs outs)
         (kv-producer-storage-definite-at (+ 2 r) outs)
         (kv-environment-ok-from-evaluable (+ 2 r) (+ 1 n) envs outs)
         (kv-producer-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
         (kv-shell-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
         (kv-record-reported-complete-at n outs)
         (equal (kv-staged-layer b outs) 0)
         (equal (kv-staged-position b outs) 0)
         ;; (3) the model memory holds the image; the read-only memories hold
         ;;     the pinned contents
         (kvn-model-memory-ok image envs outs)
         (kvn-roms-bound (kvn-rom) envs)
         ;; (4) the accepted STEP, and its token: 1
         (kv-step-accepted-at s envs outs)
         (equal (kvn-position-0-token s envs outs) 1)
         (acl2::ssv-profile-ok 1 image)
         ;; (5) the accepted writes at 227081 and 227089 hold the
         ;;     specification's first V mantissa and V exponent of token 1
         (equal (len writes) 18)
         (equal (kvn-write-address 9 writes) 227081)
         (equal (kvn-write-address 17 writes) 227089)
         (equal (kvn-record-v0 writes) (acl2::ssv-v-mantissa 0 1 image))
         (equal (kvn-record-v-exponent writes) (acl2::ssv-v-exponent 1 image))
         ;;     which are these numbers
         (equal (kvn-record-v0 writes) -6191)
         (equal (kvn-record-v-exponent writes) -16)
         ;;     and all 128 V mantissas of the record are the specification's
         (equal (kvn-record-v-list 0 writes) (cdr (acl2::ssv-v-vector 1 image)))
         ;; (6) the same about the producer's V results
         (kvn-value-claim 1 image values)))
  :hints (("Goal"
           :use ((:instance kvn-token-1-ordinary-step)
                 (:instance acl2::ssv-first-value-of-token-1))
           :in-theory '(kvn-ordinary-step-statement)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVN-TOKEN-1-THEOREM proved~%"))

; THE THREE STAGES ON THE EXECUTION OF TOKEN 1.
;
; Private.  See README.md in this directory.
;
; On the execution of kvn-token-1, in the cycle in which the datapath
; accepts the request for the V projection stage:
;   the hidden-state memory and hidden_exponent_q hold the specification's
;       embedding of token 1 (256 mantissas, exponent -18);
;   the RMS scratch memory and rms_exponent_q hold the specification's
;       input RMS normalization of that embedding (256 mantissas, exponent -13);
; and the 128 final V results accepted afterwards, with the last result's
; exponent, are the specification's value projection of that (exponent -16).
;
;   kvn-token-1-stages      THE STATEMENT, proved by evaluation
;
; Quantifiers: none; one execution.  It locates the three stages of the
; open equation (kvn-open-equation) at the circuit's working state.
(in-package "SV")
(include-book "kvn-stages")
(include-book "ssv-image")
(include-book "kvn-rom")
(include-book "kvn-inputs-token-1")

(local (memoize 'svex-env-p :recursive nil))
(local (memoize 'svex-envlist-p))

(define kvn-token-1-stages-evaluated () :verify-guards nil
  (b* ((envs (kvn-envs (kvn-tuples-token-1) (kvn-rom)))
       ((unless (kvn-envlist-ok envs)) nil)
       (initst (kvn-zero-state))
       (outs (kvn-fast-all (fsm-eval envs initst (probe-fsm-held))))
       ((unless (kvn-envlist-ok outs)) nil))
    (kvn-stage-statement 1 68596 envs outs (acl2::ssv-image)))
  ///
  (in-theory (disable (:e kvn-token-1-stages-evaluated))))

(defthm kvn-token-1-stages-evaluated-is-true
  (kvn-token-1-stages-evaluated)
  :hints (("Goal" :in-theory '((:e kvn-token-1-stages-evaluated))))
  :rule-classes nil)

(defthm kvn-token-1-stages
  (b* ((envs (kvn-envs (kvn-tuples-token-1) (kvn-rom)))
       (initst (kvn-zero-state))
       (outs (fsm-eval envs initst (probe-fsm-held))))
    (kvn-stage-statement 1 68596 envs outs (acl2::ssv-image)))
  :hints (("Goal"
           :use ((:instance kvn-token-1-stages-evaluated-is-true))
           :in-theory '(kvn-token-1-stages-evaluated kvn-fast-all-is-identity)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVN-TOKEN-1-STAGES proved~%"))

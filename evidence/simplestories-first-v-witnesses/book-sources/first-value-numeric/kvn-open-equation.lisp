; THE EQUATION THAT REMAINS FOR EVERY LEGAL TOKEN, AND WHAT FOLLOWS FROM IT.
;
; Private.  See README.md in this directory.
;
; NOT PROVED HERE: that the producer's V results are the specification's
; for every legal token and every legal history.  This book states that
; equation as one ACL2 formula and proves what the rest of the argument
; already gives:
;
;   kvn-value-equation-holds-generally
;       THE OPEN EQUATION, as a predicate of the image and the read-only
;       memories' contents.  On every execution of the held-input machine
;       that meets the hypotheses of the K/V record theorem for a completed
;       record of layer 0, position 0, on which the memory behind the raw
;       word port holds the image and the read-only memories hold the given
;       contents, and whose token of position 0 the oracle does not refuse:
;       the final V result with index 0 is the specification's first V
;       mantissa of that token, and the last V result's exponent is the
;       specification's V exponent.
;
;   kvn-first-value-of-every-legal-token-given-the-open-equation
;       IF that equation holds, THEN on every such execution the accepted
;       write at 227081 holds the specification's first V mantissa of the
;       accepted token in its bits [15:0] and the write at 227089 its V
;       exponent in its bits [7:0].
;
; The token books prove the equation's conclusion on one execution each
; (kvn-token-1), where every one of its hypotheses holds.
(in-package "SV")
(include-book "kvn-witness")

(defun-sk kvn-value-equation-holds-generally (image rom)
  (forall (envs initst n r)
    (b* ((outs (fsm-eval envs initst (probe-fsm-held)))
         (j (kv-record-start n outs))
         (b (kv-staging-begin j envs outs))
         (s (kv-step-cycle b envs outs))
         (token (kvn-position-0-token s envs outs))
         (values (kv-value-results b outs)))
      (implies (and ;; the clock, reset and input contract of the held-input model
                    (kvh-reset-state-p initst)
                    (consp envs)
                    (kvh-reset-input-p (car envs))
                    (kvh-legal-history-p envs outs)
                    ;; the hypotheses of the K/V record theorem, layer 0, position 0
                    (natp r) (natp n) (<= (+ 2 r) n)
                    (kv-reset-held-at-evaluable r envs outs)
                    (kv-payload-storage-definite-at (+ 2 r) envs outs)
                    (kv-producer-storage-definite-at (+ 2 r) outs)
                    (kv-environment-ok-from-evaluable (+ 2 r) (+ 1 n) envs outs)
                    (kv-producer-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                    (kv-shell-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                    (kv-record-reported-complete-at n outs)
                    (equal (kv-staged-layer b outs) 0)
                    (equal (kv-staged-position b outs) 0)
                    ;; the model memory and the read-only memories
                    (kvn-model-memory-ok image envs outs)
                    (kvn-roms-bound rom envs)
                    ;; the token is one the oracle does not refuse
                    (acl2::ssv-profile-ok token image))
               (kvn-value-claim token image values))))
  :rewrite :direct)
(in-theory (disable kvn-value-equation-holds-generally
                    kvn-value-equation-holds-generally-necc))

(defthm kvn-first-value-of-every-legal-token-given-the-open-equation
  (b* ((outs (fsm-eval envs initst (probe-fsm-held)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (s (kv-step-cycle b envs outs))
       (token (kvn-position-0-token s envs outs))
       (writes (kv-endpoint-writes j (+ 1 n) envs outs)))
    (implies (and ;; THE OPEN EQUATION
                  (kvn-value-equation-holds-generally image rom)
                  ;; the clock, reset and input contract of the held-input model
                  (kvh-reset-state-p initst)
                  (consp envs)
                  (kvh-reset-input-p (car envs))
                  (kvh-legal-history-p envs outs)
                  ;; the hypotheses of the K/V record theorem, layer 0, position 0
                  (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at-evaluable r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-producer-storage-definite-at (+ 2 r) outs)
                  (kv-environment-ok-from-evaluable (+ 2 r) (+ 1 n) envs outs)
                  (kv-producer-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-shell-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs)
                  (equal (kv-staged-layer b outs) 0)
                  (equal (kv-staged-position b outs) 0)
                  ;; the model memory and the read-only memories
                  (kvn-model-memory-ok image envs outs)
                  (kvn-roms-bound rom envs)
                  ;; the token is one the oracle does not refuse
                  (acl2::ssv-profile-ok token image))
             (and (equal (len writes) 18)
                  (equal (kvn-write-address 9 writes) 227081)
                  (equal (kvn-write-address 17 writes) 227089)
                  (equal (kvn-record-v0 writes)
                         (acl2::ssv-v-mantissa 0 token image))
                  (equal (kvn-record-v-exponent writes)
                         (acl2::ssv-v-exponent token image)))))
  :hints (("Goal"
           :use ((:instance kvn-value-equation-holds-generally-necc)
                 (:instance kvn-completed-record-value-words)
                 (:instance kvn-record-value-is-the-specification-given-the-claim
                            (token (kvn-position-0-token
                                    (kv-step-cycle
                                     (kv-staging-begin
                                      (kv-record-start n (fsm-eval envs initst (probe-fsm-held)))
                                      envs (fsm-eval envs initst (probe-fsm-held)))
                                     envs (fsm-eval envs initst (probe-fsm-held)))
                                    envs (fsm-eval envs initst (probe-fsm-held))))))
           :in-theory nil))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVN-CONDITIONAL proved~%"))

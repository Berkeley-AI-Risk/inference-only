; WHICH BITS OF A COMPLETED RECORD ARE THE FIRST VALUE AND ITS EXPONENT.
;
; Private.  See README.md in this directory.
;
; For every legal history of the held-input machine, with no restriction on
; the token: when the K/V record of layer 0, position 0 is reported
; complete, the tenth accepted write is at word address 227081 and its bits
; [15:0] are the mantissa of the final V result with index 0, and the
; eighteenth is at 227089 and its bits [7:0] are the exponent of the last V
; result.  This is a corollary of kv-step-to-record-held-layer-0-position-0
; (../held-clear-record), whose conclusion gives the eighteen writes as the
; reference record of the produced results.
;
;   kvn-record-v0, kvn-record-v-exponent
;       the signed first V mantissa and the signed shared V exponent, read
;       from the accepted writes
;   kvn-completed-record-value-words
;       THE COROLLARY
;   kvn-value-claim
;       the numerical equation about the producer's V results, as a
;       predicate; it is not asserted here
;   kvn-record-value-is-the-specification-given-the-claim
;       under the corollary's hypotheses, the claim about the V results is
;       the same statement about the record's words
(in-package "SV")
(include-book "../held-clear-record/kv-step-to-record-held")
(include-book "ssv-spec")
(local (include-book "centaur/bitops/ihsext-basics" :dir :system))

; ---------------------------------------------------------------------------
; Reading the accepted writes.  kv-endpoint-writes lists them in order, each
; (address data).
; ---------------------------------------------------------------------------
(define kvn-write-address (i writes) :verify-guards nil (first (nth i writes)))
(define kvn-write-data (i writes) :verify-guards nil (second (nth i writes)))
; THE SIGNED FIRST V MANTISSA: bits [15:0] of the tenth write's data
(define kvn-record-v0 (writes) :verify-guards nil
  (logext 16 (kvn-write-data 9 writes)))
; THE SIGNED SHARED V EXPONENT: bits [7:0] of the eighteenth write's data
(define kvn-record-v-exponent (writes) :verify-guards nil
  (logext 8 (kvn-write-data 17 writes)))
; the signed V mantissa of coordinate c: sixteen per word, the first lowest,
; in the tenth to the seventeenth write
(define kvn-record-v (c writes) :verify-guards nil
  (logext 16 (logtail (* 16 (mod (nfix c) 16))
                      (kvn-write-data (+ 9 (floor (nfix c) 16)) writes))))

; ---------------------------------------------------------------------------
; The reference record's tenth and eighteenth words.
; ---------------------------------------------------------------------------
(local
 (defthm kvn-logext-of-logapp-same
   (implies (posp n)
            (equal (logext n (logapp n a b)) (logext n a)))
   :hints (("Goal" :in-theory (enable* bitops::ihsext-inductions
                                       bitops::ihsext-recursive-redefs)))))
(local
 (defthm kvn-logext-of-loghead-same
   (implies (posp n)
            (equal (logext n (loghead n a)) (logext n a)))
   :hints (("Goal" :in-theory (enable* bitops::ihsext-inductions
                                       bitops::ihsext-recursive-redefs)))))
(local
 (defthm kvn-first-produced-transfer
   (equal (car (kv-produced-transfers klog vlog))
          (list 0 (kv-final-result 0 klog) (kv-final-result 0 vlog)))
   :hints (("Goal" :in-theory (enable kv-produced-transfers)
            :expand ((kv-produced-transfers-from 0 klog vlog))))))
(local
 (defthm kvn-reference-record-value-words
   (b* ((record (kv-reference-record 0 0 kexp vexp transfers)))
     (and (equal (len record) 18)
          (equal (kvn-write-address 9 record) 227081)
          (equal (kvn-write-address 17 record) 227089)
          (equal (kvn-record-v0 record) (logext 16 (third (car transfers))))
          (equal (kvn-record-v-exponent record) (logext 8 vexp))))
   :hints (("Goal"
            :in-theory (enable kvn-write-address kvn-write-data kvn-record-v0
                               kvn-record-v-exponent
                               kv-reference-record kv-reference-word
                               kv-reference-address kv-reference-data
                               kv-reference-lane)
            :expand ((:free (h tr) (kv-reference-pack h tr 16)))))))

; ---------------------------------------------------------------------------
; THE COROLLARY.
; ---------------------------------------------------------------------------
(defthm kvn-completed-record-value-words
  (b* ((outs (fsm-eval envs initst (probe-fsm-held)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (values (kv-value-results b outs))
       (writes (kv-endpoint-writes j (+ 1 n) envs outs)))
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
             (and ;; eighteen accepted writes; the tenth and the eighteenth
                  (equal (len writes) 18)
                  (equal (kvn-write-address 9 writes) 227081)
                  (equal (kvn-write-address 17 writes) 227089)
                  ;; the first V mantissa is the final V result with index 0
                  (equal (kvn-record-v0 writes)
                         (logext 16 (kv-final-result 0 values)))
                  ;; the V exponent is the exponent of the last V result
                  (equal (kvn-record-v-exponent writes)
                         (logext 8 (kv-final-exponent values))))))
  :hints (("Goal"
           :use ((:instance kv-step-to-record-held-layer-0-position-0)
                 (:instance kvn-reference-record-value-words
                            (kexp (kv-final-exponent
                                   (kv-key-results
                                    (kv-staging-begin
                                     (kv-record-start n (fsm-eval envs initst (probe-fsm-held)))
                                     envs (fsm-eval envs initst (probe-fsm-held)))
                                    (fsm-eval envs initst (probe-fsm-held)))))
                            (vexp (kv-final-exponent
                                   (kv-value-results
                                    (kv-staging-begin
                                     (kv-record-start n (fsm-eval envs initst (probe-fsm-held)))
                                     envs (fsm-eval envs initst (probe-fsm-held)))
                                    (fsm-eval envs initst (probe-fsm-held)))))
                            (transfers (kv-produced-transfers
                                        (kv-key-results
                                         (kv-staging-begin
                                          (kv-record-start n (fsm-eval envs initst (probe-fsm-held)))
                                          envs (fsm-eval envs initst (probe-fsm-held)))
                                         (fsm-eval envs initst (probe-fsm-held)))
                                        (kv-value-results
                                         (kv-staging-begin
                                          (kv-record-start n (fsm-eval envs initst (probe-fsm-held)))
                                          envs (fsm-eval envs initst (probe-fsm-held)))
                                         (fsm-eval envs initst (probe-fsm-held))))))
                 (:instance kvn-first-produced-transfer
                            (klog (kv-key-results
                                   (kv-staging-begin
                                    (kv-record-start n (fsm-eval envs initst (probe-fsm-held)))
                                    envs (fsm-eval envs initst (probe-fsm-held)))
                                   (fsm-eval envs initst (probe-fsm-held))))
                            (vlog (kv-value-results
                                   (kv-staging-begin
                                    (kv-record-start n (fsm-eval envs initst (probe-fsm-held)))
                                    envs (fsm-eval envs initst (probe-fsm-held)))
                                   (fsm-eval envs initst (probe-fsm-held))))))
           :in-theory '(car-cons cdr-cons)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVN-COROLLARY proved~%"))

; ---------------------------------------------------------------------------
; THE NUMERICAL EQUATION about the producer's V results, for a token and an
; image: the final V result with index 0 is the specification's first V
; mantissa, and the last V result's exponent is the specification's V
; exponent.  A predicate; nothing here asserts it.
; ---------------------------------------------------------------------------
(define kvn-value-claim (token image values) :verify-guards nil
  (and (equal (logext 16 (kv-final-result 0 values))
              (acl2::ssv-v-mantissa 0 token image))
       (equal (logext 8 (kv-final-exponent values))
              (acl2::ssv-v-exponent token image))))

(defthm kvn-record-value-is-the-specification-given-the-claim
  (b* ((outs (fsm-eval envs initst (probe-fsm-held)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (values (kv-value-results b outs))
       (writes (kv-endpoint-writes j (+ 1 n) envs outs)))
    (implies (and (kvh-reset-state-p initst)
                  (consp envs)
                  (kvh-reset-input-p (car envs))
                  (kvh-legal-history-p envs outs)
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
             (equal (kvn-value-claim token image values)
                    (and (equal (kvn-record-v0 writes)
                                (acl2::ssv-v-mantissa 0 token image))
                         (equal (kvn-record-v-exponent writes)
                                (acl2::ssv-v-exponent token image))))))
  :hints (("Goal"
           :use ((:instance kvn-completed-record-value-words))
           :in-theory '(kvn-value-claim)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVN-CLAIM-EQUIVALENCE proved~%"))

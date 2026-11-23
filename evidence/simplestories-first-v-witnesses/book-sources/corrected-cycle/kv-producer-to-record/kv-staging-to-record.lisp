; From staging to the record: the theorem.
;
; Written by make_producer_book.py; do not edit.  Private.
;
; THE CLAIM.  Take any execution of the probe module's state machine
; satisfying the reset, storage and environment hypotheses of the payload
; book.  When the controller's pending_persisted_q rises, the eighteen
; writes the typed DDR boundary's endpoint (private_kv_req_*) accepted
; since the record's start are the REFERENCE RECORD: the record computed
; from what the datapath presented at one accepted staging begin (its
; layer, position and two exponent bytes) and at the 128 payload transfers
; accepted after it (coordinates 0 to 127 in order, each with a key and a
; value).  The reference does not read the controller's storage.  This is
; kv-staging-to-record, near the end of this file; kv-staging-prefix says
; what holds of a staging that is cut short.
;
; WHAT IT RESTS ON.  The imported record theorem (kv-write-record), the
; imported payload book's facts about the pair store, the four staging
; facts of kv-staging-lift.lisp, and an induction over the cycles of a
; staging from its begin.
(in-package "SV")
(include-book "kv-staging-lift")
(acl2::set-slow-alist-action nil)
(value-triple (acl2::tshell-ensure))

; ---------------------------------------------------------------------------
; THE STAGING FACTS AT CYCLE k OF AN EXECUTION.
; ---------------------------------------------------------------------------
(make-event
 (b* ((ev (acl2::get-event 'stg-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (decl `(declare (xargs :verify-guards nil) (ignorable ,@formals)))
      (idecl `(declare (ignorable ,@vars))))
   `(progn
      (defun stg-facts-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and (stg-fact-entry h-kexp h-layer h-position h-sbegin h-vexp i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr r-k-state-q)
               (stg-fact-stay h-index h-sbegin h-spayload i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
               (stg-fact-last h-index h-sbegin h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
               (stg-fact-begin h-sbegin n-k-state-q o-sbl o-sbr r-k-state-q))))
      (in-theory (disable stg-facts-raw)))))
; The four staging facts about cycle k.
(define stg-facts-at (k envs outs) :verify-guards nil
  (stg-facts-raw k (+ 1 k) envs outs))

; One cycle: from the joined invariant, the payload invariant and the
; environment at cycle k to the staging facts about cycle k.
(defthm stg-step-glue
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at k envs (fsm-eval envs initst (probe-fsm))))
           (stg-facts-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance stg-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-staging-run-constraints))
           :in-theory (e/d (join-j-at join-env-at join-inv-raw join-resetalt-raw
                            join-env-raw joint-2valued-p
                            pay-j-at stg-facts-at pay-definite-raw pay-inv-raw
                            stg-facts-raw stg-step-all stg-step-concl
                            fgl::fgl-prove-fn pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7 pay-next-definite-k-rd0 pay-next-definite-k-rd1 pay-next-definite-k-rd2 pay-next-definite-k-rd3 pay-next-definite-k-rd4 pay-next-definite-k-rd5 pay-next-definite-k-rd6 pay-next-definite-k-rd7 pay-next-definite-k-offer pay-next-definite-q-memp0 pay-next-definite-q-memp1 pay-next-definite-q-memp2 pay-next-definite-q-memp3 pay-next-definite-q-memp4 pay-next-definite-q-memp5 pay-next-definite-q-memp6 pay-next-definite-q-memp7 pay-next-definite-q-memd0 pay-next-definite-q-memd1 pay-next-definite-q-memd2 pay-next-definite-q-memd3 pay-next-definite-q-memd4 pay-next-definite-q-memd5 pay-next-definite-q-memd6 pay-next-definite-q-memd7 pay-next-definite-q-mdd pay-next-definite-q-mdp pay-next-definite-a-saddr pay-next-definite-a-sdata pay-next-definite-a-oaddr pay-next-definite-a-odata pay-next-inv)
                           (stg-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

; The staging signals of a cycle, by the lifted lemma's own bindings: the
; datapath's kv_stage_begin_valid, current_layer_q, current_position_q,
; key_exponent_q, value_exponent_q and input_index_q, the controller's
; stage_begin_ready_o and stage_begin_legal, and the next expected coordinate.
(make-event
 (b* ((ev (acl2::get-event 'stg-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (names '(h-sbegin h-layer h-position h-kexp h-vexp h-index o-sbr o-sbl n-k-expected-coordinate-q)))
   (cons 'progn
         (append
          (pay-accessor-events names formals bindings vars)
          (list `(in-theory (disable ,@(pay-accessor-names names))))))))

; ---------------------------------------------------------------------------
; STAGING, in terms of one cycle's signals.
; ---------------------------------------------------------------------------
; 1 when a staging begin is accepted in cycle k: the datapath's
; kv_stage_begin_valid with the controller's stage_begin_ready_o and
; stage_begin_legal.
(define stg-begin-at (k envs outs) :verify-guards nil
  (if (and (equal (pay$h-sbegin k k envs outs) 1)
           (equal (pay$o-sbr k k envs outs) 1)
           (equal (pay$o-sbl k k envs outs) 1))
      1 0))
; What the datapath presents with a begin in cycle k: current_layer_q,
; current_position_q, key_exponent_q, value_exponent_q.
(define stg-layer-at (k outs) :verify-guards nil (pay$h-layer k k nil outs))
(define stg-position-at (k outs) :verify-guards nil (pay$h-position k k nil outs))
(define stg-kexp-at (k outs) :verify-guards nil (pay$h-kexp k k nil outs))
(define stg-vexp-at (k outs) :verify-guards nil (pay$h-vexp k k nil outs))
; What a begin accepted in cycle k puts in the controller's four record
; registers: the layer, the position, and each exponent byte twice.
(define stg-captured-at (k outs) :verify-guards nil
  (list (stg-layer-at k outs) (stg-position-at k outs)
        (logapp 8 (stg-kexp-at k outs) (loghead 8 (stg-kexp-at k outs)))
        (logapp 8 (stg-vexp-at k outs) (loghead 8 (stg-vexp-at k outs)))))
; The controller's four record registers in cycle k: pending_layer_q,
; pending_position_q, pending_key_exponents_q, pending_value_exponents_q.
(define stg-held-at (k outs) :verify-guards nil
  (list (pay$r-k-pending-layer-q k k nil outs) (pay$r-k-pending-position-q k k nil outs)
        (pay$r-k-pending-key-exponents-q k k nil outs)
        (pay$r-k-pending-value-exponents-q k k nil outs)))
; The payload transfer of cycle k: (coordinate key value), the datapath's
; input_index_q[6:0], key_ram_read_data and value_ram_read_data.  It is an
; accepted transfer when rec-beat-at is 1 in the cycle.
(define stg-transfer-at (k envs outs) :verify-guards nil
  (list (loghead 7 (pay$h-index k k envs outs))
        (pay$h-key k k envs outs)
        (pay$h-value k k envs outs)))
; the pair a transfer puts in the pair store: {value, key}
(define stg-pair (tr) :verify-guards nil
  (logapp 16 (second tr) (third tr)))
; The pair, {value, key}, that the staged slots hold for coordinate c: bank
; c mod 8, cell c div 8.  s0 .. s7 are the staged fields of the eight banks
; (pay-staged of each), sixteen cells of 32 bits, cell 0 highest.
(define stg-slot (c s0 s1 s2 s3 s4 s5 s6 s7) :verify-guards nil
  (b* ((f (cond ((equal (loghead 3 c) 0) s0)
        ((equal (loghead 3 c) 1) s1)
        ((equal (loghead 3 c) 2) s2)
        ((equal (loghead 3 c) 3) s3)
        ((equal (loghead 3 c) 4) s4)
        ((equal (loghead 3 c) 5) s5)
        ((equal (loghead 3 c) 6) s6)
        (t s7))))
    (cond
      ((equal (logtail 3 c) 0) (loghead 32 (logtail 480 f)))
      ((equal (logtail 3 c) 1) (loghead 32 (logtail 448 f)))
      ((equal (logtail 3 c) 2) (loghead 32 (logtail 416 f)))
      ((equal (logtail 3 c) 3) (loghead 32 (logtail 384 f)))
      ((equal (logtail 3 c) 4) (loghead 32 (logtail 352 f)))
      ((equal (logtail 3 c) 5) (loghead 32 (logtail 320 f)))
      ((equal (logtail 3 c) 6) (loghead 32 (logtail 288 f)))
      ((equal (logtail 3 c) 7) (loghead 32 (logtail 256 f)))
      ((equal (logtail 3 c) 8) (loghead 32 (logtail 224 f)))
      ((equal (logtail 3 c) 9) (loghead 32 (logtail 192 f)))
      ((equal (logtail 3 c) 10) (loghead 32 (logtail 160 f)))
      ((equal (logtail 3 c) 11) (loghead 32 (logtail 128 f)))
      ((equal (logtail 3 c) 12) (loghead 32 (logtail 96 f)))
      ((equal (logtail 3 c) 13) (loghead 32 (logtail 64 f)))
      ((equal (logtail 3 c) 14) (loghead 32 (logtail 32 f)))
      (t (loghead 32 f)))))

; the same of the pair store in cycle k
(define stg-slot-at (c k outs) :verify-guards nil
  (stg-slot c (pay-staged (pay$r-k-bank0 k k nil outs)) (pay-staged (pay$r-k-bank1 k k nil outs)) (pay-staged (pay$r-k-bank2 k k nil outs)) (pay-staged (pay$r-k-bank3 k k nil outs)) (pay-staged (pay$r-k-bank4 k k nil outs)) (pay-staged (pay$r-k-bank5 k k nil outs)) (pay-staged (pay$r-k-bank6 k k nil outs)) (pay-staged (pay$r-k-bank7 k k nil outs))))
; one bank's staged field after an accepted transfer for coordinate `coord`
(define stg-put (coord pair bank field) :verify-guards nil
  (if (equal (loghead 3 coord) bank)
      (pay-staged-put (logtail 3 coord) pair field)
    field))
(in-theory (disable stg-slot stg-put))
; Everything known about cycle i: what the record book knows, the four
; staging facts, and that the environment behaves in the cycle.
(define stg-known-at (i envs outs) :verify-guards nil
  (and (rec-known-at i envs outs)
       (stg-facts-at i envs outs)
       (join-env-at i envs outs)))

; ---------------------------------------------------------------------------
; ONE CYCLE OF STAGING, first about plain values.
; ---------------------------------------------------------------------------
(defthm stg-entry-of-values
  (implies (and (stg-fact-entry h-kexp h-layer h-position h-sbegin h-vexp i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr r-k-state-q)
                (unsigned-byte-p 4 n-k-state-q)
                (unsigned-byte-p 3 n-k-pending-layer-q) (unsigned-byte-p 12 n-k-pending-position-q)
                (unsigned-byte-p 16 n-k-pending-key-exponents-q)
                (unsigned-byte-p 16 n-k-pending-value-exponents-q)
                (unsigned-byte-p 7 n-k-expected-coordinate-q)
                (equal n-k-state-q 1)
                (not (equal r-k-state-q 1)))
           (and (equal r-k-state-q 0)
                (equal (if (and (equal h-sbegin 1) (equal o-sbr 1) (equal o-sbl 1)) 1 0) 1)
                (equal i-clear 0)
                (equal n-k-pending-layer-q h-layer)
                (equal n-k-pending-position-q h-position)
                (equal n-k-pending-key-exponents-q (logapp 8 h-kexp (loghead 8 h-kexp)))
                (equal n-k-pending-value-exponents-q (logapp 8 h-vexp (loghead 8 h-vexp)))
                (equal n-k-expected-coordinate-q 0)))
  :hints (("Goal" :in-theory (e/d (stg-fact-entry fgl::fgl-prove-fn) (unsigned-byte-p))))
  :rule-classes nil)

(defthm stg-stay-of-values
  (implies (and (stg-fact-stay h-index h-sbegin h-spayload i-clear n-k-expected-coordinate-q n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
                (unsigned-byte-p 4 n-k-state-q)
                (unsigned-byte-p 3 n-k-pending-layer-q) (unsigned-byte-p 12 n-k-pending-position-q)
                (unsigned-byte-p 16 n-k-pending-key-exponents-q)
                (unsigned-byte-p 16 n-k-pending-value-exponents-q)
                (unsigned-byte-p 7 n-k-expected-coordinate-q)
                (equal r-k-state-q 1)
                (equal n-k-state-q 1))
           (and (equal i-clear 0)
                (equal (if (and (equal h-sbegin 1) (equal o-sbr 1) (equal o-sbl 1)) 1 0) 0)
                (equal n-k-pending-layer-q r-k-pending-layer-q)
                (equal n-k-pending-position-q r-k-pending-position-q)
                (equal n-k-pending-key-exponents-q r-k-pending-key-exponents-q)
                (equal n-k-pending-value-exponents-q r-k-pending-value-exponents-q)
                (implies (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                         (and (equal (loghead 7 h-index) r-k-expected-coordinate-q)
                              (equal n-k-expected-coordinate-q (+ 1 r-k-expected-coordinate-q))))
                (implies (not (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1))
                         (equal n-k-expected-coordinate-q r-k-expected-coordinate-q))))
  :hints (("Goal" :in-theory (e/d (stg-fact-stay fgl::fgl-prove-fn) (unsigned-byte-p))))
  :rule-classes nil)

(defthm stg-last-of-values
  (implies (and (stg-fact-last h-index h-sbegin h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-sbl o-sbr o-spl o-spr r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q)
                (unsigned-byte-p 4 n-k-state-q)
                (unsigned-byte-p 1 n-k-write-head-q) (unsigned-byte-p 4 n-k-write-word-q)
                (unsigned-byte-p 1 n-k-write-aborted-q)
                (unsigned-byte-p 3 n-k-pending-layer-q) (unsigned-byte-p 12 n-k-pending-position-q)
                (unsigned-byte-p 16 n-k-pending-key-exponents-q)
                (unsigned-byte-p 16 n-k-pending-value-exponents-q)
                (equal r-k-state-q 1)
                (equal n-k-state-q 9))
           (and (equal i-clear 0)
                (equal (if (and (equal h-sbegin 1) (equal o-sbr 1) (equal o-sbl 1)) 1 0) 0)
                (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                (equal r-k-expected-coordinate-q 127)
                (equal (loghead 7 h-index) 127)
                (equal n-k-write-head-q 0) (equal n-k-write-word-q 0)
                (equal n-k-write-aborted-q 0)
                (equal n-k-pending-layer-q r-k-pending-layer-q)
                (equal n-k-pending-position-q r-k-pending-position-q)
                (equal n-k-pending-key-exponents-q r-k-pending-key-exponents-q)
                (equal n-k-pending-value-exponents-q r-k-pending-value-exponents-q)))
  :hints (("Goal" :in-theory (e/d (stg-fact-last fgl::fgl-prove-fn) (unsigned-byte-p))))
  :rule-classes nil)

; The pair store.  By the payload book's bank facts each bank's staged field
; is unchanged, or, on an accepted transfer, has the pair put at the expected
; coordinate if that coordinate is the bank's.
(defthm stg-banks-of-values
  (implies (and (pay-fact-bank0-staged h-key h-spayload h-value n-k-bank0 o-spl o-spr r-k-bank0 r-k-expected-coordinate-q)
                (pay-fact-bank1-staged h-key h-spayload h-value n-k-bank1 o-spl o-spr r-k-bank1 r-k-expected-coordinate-q)
                (pay-fact-bank2-staged h-key h-spayload h-value n-k-bank2 o-spl o-spr r-k-bank2 r-k-expected-coordinate-q)
                (pay-fact-bank3-staged h-key h-spayload h-value n-k-bank3 o-spl o-spr r-k-bank3 r-k-expected-coordinate-q)
                (pay-fact-bank4-staged h-key h-spayload h-value n-k-bank4 o-spl o-spr r-k-bank4 r-k-expected-coordinate-q)
                (pay-fact-bank5-staged h-key h-spayload h-value n-k-bank5 o-spl o-spr r-k-bank5 r-k-expected-coordinate-q)
                (pay-fact-bank6-staged h-key h-spayload h-value n-k-bank6 o-spl o-spr r-k-bank6 r-k-expected-coordinate-q)
                (pay-fact-bank7-staged h-key h-spayload h-value n-k-bank7 o-spl o-spr r-k-bank7 r-k-expected-coordinate-q)
                (unsigned-byte-p 1024 r-k-bank0)
                (unsigned-byte-p 1024 r-k-bank1)
                (unsigned-byte-p 1024 r-k-bank2)
                (unsigned-byte-p 1024 r-k-bank3)
                (unsigned-byte-p 1024 r-k-bank4)
                (unsigned-byte-p 1024 r-k-bank5)
                (unsigned-byte-p 1024 r-k-bank6)
                (unsigned-byte-p 1024 r-k-bank7)
                (unsigned-byte-p 1024 n-k-bank0)
                (unsigned-byte-p 1024 n-k-bank1)
                (unsigned-byte-p 1024 n-k-bank2)
                (unsigned-byte-p 1024 n-k-bank3)
                (unsigned-byte-p 1024 n-k-bank4)
                (unsigned-byte-p 1024 n-k-bank5)
                (unsigned-byte-p 1024 n-k-bank6)
                (unsigned-byte-p 1024 n-k-bank7))
           (and (equal (pay-staged n-k-bank0)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 0 (pay-staged r-k-bank0))
                         (pay-staged r-k-bank0)))
                (equal (pay-staged n-k-bank1)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 1 (pay-staged r-k-bank1))
                         (pay-staged r-k-bank1)))
                (equal (pay-staged n-k-bank2)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 2 (pay-staged r-k-bank2))
                         (pay-staged r-k-bank2)))
                (equal (pay-staged n-k-bank3)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 3 (pay-staged r-k-bank3))
                         (pay-staged r-k-bank3)))
                (equal (pay-staged n-k-bank4)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 4 (pay-staged r-k-bank4))
                         (pay-staged r-k-bank4)))
                (equal (pay-staged n-k-bank5)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 5 (pay-staged r-k-bank5))
                         (pay-staged r-k-bank5)))
                (equal (pay-staged n-k-bank6)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 6 (pay-staged r-k-bank6))
                         (pay-staged r-k-bank6)))
                (equal (pay-staged n-k-bank7)
                       (if (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                           (stg-put r-k-expected-coordinate-q (logapp 16 h-key h-value) 7 (pay-staged r-k-bank7))
                         (pay-staged r-k-bank7)))))
  :hints (("Goal" :in-theory (e/d (pay-fact-bank0-staged pay-fact-bank1-staged pay-fact-bank2-staged pay-fact-bank3-staged pay-fact-bank4-staged pay-fact-bank5-staged pay-fact-bank6-staged pay-fact-bank7-staged
                                   fgl::fgl-prove-fn stg-put)
                                  (unsigned-byte-p pay-staged pay-staged-put))))
  :rule-classes nil)
; So the pair held for a coordinate c changes only by an accepted transfer
; for c, which makes it that transfer's pair.
(fgl::def-fgl-thm stg-slot-after-put
  (implies (and (unsigned-byte-p 512 s0) (unsigned-byte-p 512 s1)
                (unsigned-byte-p 512 s2) (unsigned-byte-p 512 s3)
                (unsigned-byte-p 512 s4) (unsigned-byte-p 512 s5)
                (unsigned-byte-p 512 s6) (unsigned-byte-p 512 s7)
                (unsigned-byte-p 7 c) (unsigned-byte-p 7 coord)
                (unsigned-byte-p 32 pair))
           (equal (stg-slot c (stg-put coord pair 0 s0) (stg-put coord pair 1 s1) (stg-put coord pair 2 s2) (stg-put coord pair 3 s3) (stg-put coord pair 4 s4) (stg-put coord pair 5 s5) (stg-put coord pair 6 s6) (stg-put coord pair 7 s7))
                  (if (equal c coord)
                      pair
                    (stg-slot c s0 s1 s2 s3 s4 s5 s6 s7)))))
(in-theory (disable stg-slot-after-put))
(fgl::def-fgl-thm stg-staged-size
  (implies (unsigned-byte-p 1024 x)
           (unsigned-byte-p 512 (pay-staged x))))
(fgl::def-fgl-thm stg-pair-size
  (implies (and (unsigned-byte-p 16 k) (unsigned-byte-p 16 v))
           (unsigned-byte-p 32 (logapp 16 k v))))
(defthm stg-slot-step-of-values
  (implies (and (pay-fact-bank0-staged h-key h-spayload h-value n-k-bank0 o-spl o-spr r-k-bank0 r-k-expected-coordinate-q)
                (pay-fact-bank1-staged h-key h-spayload h-value n-k-bank1 o-spl o-spr r-k-bank1 r-k-expected-coordinate-q)
                (pay-fact-bank2-staged h-key h-spayload h-value n-k-bank2 o-spl o-spr r-k-bank2 r-k-expected-coordinate-q)
                (pay-fact-bank3-staged h-key h-spayload h-value n-k-bank3 o-spl o-spr r-k-bank3 r-k-expected-coordinate-q)
                (pay-fact-bank4-staged h-key h-spayload h-value n-k-bank4 o-spl o-spr r-k-bank4 r-k-expected-coordinate-q)
                (pay-fact-bank5-staged h-key h-spayload h-value n-k-bank5 o-spl o-spr r-k-bank5 r-k-expected-coordinate-q)
                (pay-fact-bank6-staged h-key h-spayload h-value n-k-bank6 o-spl o-spr r-k-bank6 r-k-expected-coordinate-q)
                (pay-fact-bank7-staged h-key h-spayload h-value n-k-bank7 o-spl o-spr r-k-bank7 r-k-expected-coordinate-q)
                (unsigned-byte-p 1024 r-k-bank0)
                (unsigned-byte-p 1024 r-k-bank1)
                (unsigned-byte-p 1024 r-k-bank2)
                (unsigned-byte-p 1024 r-k-bank3)
                (unsigned-byte-p 1024 r-k-bank4)
                (unsigned-byte-p 1024 r-k-bank5)
                (unsigned-byte-p 1024 r-k-bank6)
                (unsigned-byte-p 1024 r-k-bank7)
                (unsigned-byte-p 1024 n-k-bank0)
                (unsigned-byte-p 1024 n-k-bank1)
                (unsigned-byte-p 1024 n-k-bank2)
                (unsigned-byte-p 1024 n-k-bank3)
                (unsigned-byte-p 1024 n-k-bank4)
                (unsigned-byte-p 1024 n-k-bank5)
                (unsigned-byte-p 1024 n-k-bank6)
                (unsigned-byte-p 1024 n-k-bank7)
                (unsigned-byte-p 7 r-k-expected-coordinate-q)
                (unsigned-byte-p 16 h-key) (unsigned-byte-p 16 h-value)
                (unsigned-byte-p 7 c))
           (equal (stg-slot c (pay-staged n-k-bank0) (pay-staged n-k-bank1) (pay-staged n-k-bank2) (pay-staged n-k-bank3) (pay-staged n-k-bank4) (pay-staged n-k-bank5) (pay-staged n-k-bank6) (pay-staged n-k-bank7))
                  (if (and (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal c r-k-expected-coordinate-q))
                      (logapp 16 h-key h-value)
                    (stg-slot c (pay-staged r-k-bank0) (pay-staged r-k-bank1) (pay-staged r-k-bank2) (pay-staged r-k-bank3) (pay-staged r-k-bank4) (pay-staged r-k-bank5) (pay-staged r-k-bank6) (pay-staged r-k-bank7)))))
  :hints (("Goal"
           :use ((:instance stg-banks-of-values)
                 (:instance stg-slot-after-put
                  (coord r-k-expected-coordinate-q) (pair (logapp 16 h-key h-value))
                  (s0 (pay-staged r-k-bank0))
                  (s1 (pay-staged r-k-bank1))
                  (s2 (pay-staged r-k-bank2))
                  (s3 (pay-staged r-k-bank3))
                  (s4 (pay-staged r-k-bank4))
                  (s5 (pay-staged r-k-bank5))
                  (s6 (pay-staged r-k-bank6))
                  (s7 (pay-staged r-k-bank7))))
           :in-theory (e/d ()
                           (unsigned-byte-p pay-staged pay-staged-put stg-slot stg-put
                            logapp loghead logtail
                            pay-fact-bank0-staged pay-fact-bank1-staged pay-fact-bank2-staged pay-fact-bank3-staged pay-fact-bank4-staged pay-fact-bank5-staged pay-fact-bank6-staged pay-fact-bank7-staged))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The same about cycle k of an execution.
; ---------------------------------------------------------------------------
; Staging is entered by an accepted begin, which sets the record registers.
(defthm stg-entry-step
  (implies (and (natp k)
                (stg-known-at k envs outs)
                (equal (pay-st-at (+ 1 k) outs) 1)
                (not (equal (pay-st-at k outs) 1)))
           (and (equal (pay-st-at k outs) 0)
                (equal (stg-begin-at k envs outs) 1)
                (equal (rec-clear-at k envs) 0)
                (equal (stg-held-at (+ 1 k) outs) (stg-captured-at k outs))
                (equal (rec-coord-at (+ 1 k) outs) 0)))
  :hints (("Goal"
           :use ((:instance stg-entry-of-values
                  (h-kexp (pay$h-kexp k (+ 1 k) envs outs))
                  (h-layer (pay$h-layer k (+ 1 k) envs outs))
                  (h-position (pay$h-position k (+ 1 k) envs outs))
                  (h-sbegin (pay$h-sbegin k (+ 1 k) envs outs))
                  (h-vexp (pay$h-vexp k (+ 1 k) envs outs))
                  (i-clear (pay$i-clear k (+ 1 k) envs outs))
                  (n-k-expected-coordinate-q (pay$n-k-expected-coordinate-q k (+ 1 k) envs outs))
                  (n-k-pending-key-exponents-q (pay$n-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (n-k-pending-layer-q (pay$n-k-pending-layer-q k (+ 1 k) envs outs))
                  (n-k-pending-position-q (pay$n-k-pending-position-q k (+ 1 k) envs outs))
                  (n-k-pending-value-exponents-q (pay$n-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (n-k-state-q (pay$n-k-state-q k (+ 1 k) envs outs))
                  (o-sbl (pay$o-sbl k (+ 1 k) envs outs))
                  (o-sbr (pay$o-sbr k (+ 1 k) envs outs))
                  (r-k-state-q (pay$r-k-state-q k (+ 1 k) envs outs))))
           :in-theory (e/d (stg-known-at rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            join-env-at join-env-raw joint-env-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw stg-facts-at stg-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw
                            rec-clear-at rec-beat-at rec-coord-at rec-start-p rec-live-p
                            stg-begin-at stg-layer-at stg-position-at stg-kexp-at stg-vexp-at
                            stg-captured-at stg-held-at stg-transfer-at stg-pair stg-slot-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q pay$h-sbegin pay$h-layer pay$h-position pay$h-kexp pay$h-vexp pay$h-index pay$o-sbr pay$o-sbl pay$n-k-expected-coordinate-q)
                           (unsigned-byte-p nth nthcdr take len stg-slot stg-put pay-staged
                            pay-staged-put logapp loghead logtail))))
  :rule-classes nil)
; While staging lasts.
(defthm stg-stay-step
  (implies (and (natp k)
                (stg-known-at k envs outs)
                (equal (pay-st-at k outs) 1)
                (equal (pay-st-at (+ 1 k) outs) 1))
           (and (equal (rec-clear-at k envs) 0)
                (equal (stg-begin-at k envs outs) 0)
                (equal (stg-held-at (+ 1 k) outs) (stg-held-at k outs))
                (implies (equal (rec-beat-at k envs outs) 1)
                         (and (equal (car (stg-transfer-at k envs outs)) (rec-coord-at k outs))
                              (equal (rec-coord-at (+ 1 k) outs) (+ 1 (rec-coord-at k outs)))))
                (implies (not (equal (rec-beat-at k envs outs) 1))
                         (equal (rec-coord-at (+ 1 k) outs) (rec-coord-at k outs)))))
  :hints (("Goal"
           :use ((:instance stg-stay-of-values
                  (h-index (pay$h-index k (+ 1 k) envs outs))
                  (h-sbegin (pay$h-sbegin k (+ 1 k) envs outs))
                  (h-spayload (pay$h-spayload k (+ 1 k) envs outs))
                  (i-clear (pay$i-clear k (+ 1 k) envs outs))
                  (n-k-expected-coordinate-q (pay$n-k-expected-coordinate-q k (+ 1 k) envs outs))
                  (n-k-pending-key-exponents-q (pay$n-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (n-k-pending-layer-q (pay$n-k-pending-layer-q k (+ 1 k) envs outs))
                  (n-k-pending-position-q (pay$n-k-pending-position-q k (+ 1 k) envs outs))
                  (n-k-pending-value-exponents-q (pay$n-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (n-k-state-q (pay$n-k-state-q k (+ 1 k) envs outs))
                  (o-sbl (pay$o-sbl k (+ 1 k) envs outs))
                  (o-sbr (pay$o-sbr k (+ 1 k) envs outs))
                  (o-spl (pay$o-spl k (+ 1 k) envs outs))
                  (o-spr (pay$o-spr k (+ 1 k) envs outs))
                  (r-k-expected-coordinate-q (pay$r-k-expected-coordinate-q k (+ 1 k) envs outs))
                  (r-k-pending-key-exponents-q (pay$r-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (r-k-pending-layer-q (pay$r-k-pending-layer-q k (+ 1 k) envs outs))
                  (r-k-pending-position-q (pay$r-k-pending-position-q k (+ 1 k) envs outs))
                  (r-k-pending-value-exponents-q (pay$r-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (r-k-state-q (pay$r-k-state-q k (+ 1 k) envs outs))))
           :in-theory (e/d (stg-known-at rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            join-env-at join-env-raw joint-env-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw stg-facts-at stg-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw
                            rec-clear-at rec-beat-at rec-coord-at rec-start-p rec-live-p
                            stg-begin-at stg-layer-at stg-position-at stg-kexp-at stg-vexp-at
                            stg-captured-at stg-held-at stg-transfer-at stg-pair stg-slot-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q pay$h-sbegin pay$h-layer pay$h-position pay$h-kexp pay$h-vexp pay$h-index pay$o-sbr pay$o-sbl pay$n-k-expected-coordinate-q)
                           (unsigned-byte-p nth nthcdr take len stg-slot stg-put pay-staged
                            pay-staged-put logapp loghead logtail))))
  :rule-classes nil)
; The last transfer, into the record's start.
(defthm stg-last-step
  (implies (and (natp k)
                (stg-known-at k envs outs)
                (equal (pay-st-at k outs) 1)
                (equal (pay-st-at (+ 1 k) outs) 9))
           (and (equal (rec-clear-at k envs) 0)
                (equal (stg-begin-at k envs outs) 0)
                (equal (rec-beat-at k envs outs) 1)
                (equal (rec-coord-at k outs) 127)
                (equal (car (stg-transfer-at k envs outs)) 127)
                (rec-start-p (+ 1 k) outs)
                (equal (stg-held-at (+ 1 k) outs) (stg-held-at k outs))))
  :hints (("Goal"
           :use ((:instance stg-last-of-values
                  (h-index (pay$h-index k (+ 1 k) envs outs))
                  (h-sbegin (pay$h-sbegin k (+ 1 k) envs outs))
                  (h-spayload (pay$h-spayload k (+ 1 k) envs outs))
                  (i-clear (pay$i-clear k (+ 1 k) envs outs))
                  (n-k-pending-key-exponents-q (pay$n-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (n-k-pending-layer-q (pay$n-k-pending-layer-q k (+ 1 k) envs outs))
                  (n-k-pending-position-q (pay$n-k-pending-position-q k (+ 1 k) envs outs))
                  (n-k-pending-value-exponents-q (pay$n-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (n-k-state-q (pay$n-k-state-q k (+ 1 k) envs outs))
                  (n-k-write-aborted-q (pay$n-k-write-aborted-q k (+ 1 k) envs outs))
                  (n-k-write-head-q (pay$n-k-write-head-q k (+ 1 k) envs outs))
                  (n-k-write-word-q (pay$n-k-write-word-q k (+ 1 k) envs outs))
                  (o-sbl (pay$o-sbl k (+ 1 k) envs outs))
                  (o-sbr (pay$o-sbr k (+ 1 k) envs outs))
                  (o-spl (pay$o-spl k (+ 1 k) envs outs))
                  (o-spr (pay$o-spr k (+ 1 k) envs outs))
                  (r-k-expected-coordinate-q (pay$r-k-expected-coordinate-q k (+ 1 k) envs outs))
                  (r-k-pending-key-exponents-q (pay$r-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (r-k-pending-layer-q (pay$r-k-pending-layer-q k (+ 1 k) envs outs))
                  (r-k-pending-position-q (pay$r-k-pending-position-q k (+ 1 k) envs outs))
                  (r-k-pending-value-exponents-q (pay$r-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (r-k-state-q (pay$r-k-state-q k (+ 1 k) envs outs))))
           :in-theory (e/d (stg-known-at rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            join-env-at join-env-raw joint-env-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw stg-facts-at stg-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw
                            rec-clear-at rec-beat-at rec-coord-at rec-start-p rec-live-p
                            stg-begin-at stg-layer-at stg-position-at stg-kexp-at stg-vexp-at
                            stg-captured-at stg-held-at stg-transfer-at stg-pair stg-slot-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q pay$h-sbegin pay$h-layer pay$h-position pay$h-kexp pay$h-vexp pay$h-index pay$o-sbr pay$o-sbl pay$n-k-expected-coordinate-q)
                           (unsigned-byte-p nth nthcdr take len stg-slot stg-put pay-staged
                            pay-staged-put logapp loghead logtail))))
  :rule-classes nil)
; The pair store in the next cycle.
(defthm stg-slot-step
  (implies (and (natp k)
                (stg-known-at k envs outs)
                (unsigned-byte-p 7 c))
           (equal (stg-slot-at c (+ 1 k) outs)
                  (if (and (equal (rec-beat-at k envs outs) 1)
                           (equal c (rec-coord-at k outs)))
                      (stg-pair (stg-transfer-at k envs outs))
                    (stg-slot-at c k outs))))
  :hints (("Goal"
           :use ((:instance stg-slot-step-of-values
                  (c c)
                  (h-key (pay$h-key k (+ 1 k) envs outs))
                  (h-spayload (pay$h-spayload k (+ 1 k) envs outs))
                  (h-value (pay$h-value k (+ 1 k) envs outs))
                  (n-k-bank0 (pay$n-k-bank0 k (+ 1 k) envs outs))
                  (n-k-bank1 (pay$n-k-bank1 k (+ 1 k) envs outs))
                  (n-k-bank2 (pay$n-k-bank2 k (+ 1 k) envs outs))
                  (n-k-bank3 (pay$n-k-bank3 k (+ 1 k) envs outs))
                  (n-k-bank4 (pay$n-k-bank4 k (+ 1 k) envs outs))
                  (n-k-bank5 (pay$n-k-bank5 k (+ 1 k) envs outs))
                  (n-k-bank6 (pay$n-k-bank6 k (+ 1 k) envs outs))
                  (n-k-bank7 (pay$n-k-bank7 k (+ 1 k) envs outs))
                  (o-spl (pay$o-spl k (+ 1 k) envs outs))
                  (o-spr (pay$o-spr k (+ 1 k) envs outs))
                  (r-k-bank0 (pay$r-k-bank0 k (+ 1 k) envs outs))
                  (r-k-bank1 (pay$r-k-bank1 k (+ 1 k) envs outs))
                  (r-k-bank2 (pay$r-k-bank2 k (+ 1 k) envs outs))
                  (r-k-bank3 (pay$r-k-bank3 k (+ 1 k) envs outs))
                  (r-k-bank4 (pay$r-k-bank4 k (+ 1 k) envs outs))
                  (r-k-bank5 (pay$r-k-bank5 k (+ 1 k) envs outs))
                  (r-k-bank6 (pay$r-k-bank6 k (+ 1 k) envs outs))
                  (r-k-bank7 (pay$r-k-bank7 k (+ 1 k) envs outs))
                  (r-k-expected-coordinate-q (pay$r-k-expected-coordinate-q k (+ 1 k) envs outs))))
           :in-theory (e/d (stg-known-at rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            join-env-at join-env-raw joint-env-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw stg-facts-at stg-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw
                            rec-clear-at rec-beat-at rec-coord-at rec-start-p rec-live-p
                            stg-begin-at stg-layer-at stg-position-at stg-kexp-at stg-vexp-at
                            stg-captured-at stg-held-at stg-transfer-at stg-pair stg-slot-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q pay$h-sbegin pay$h-layer pay$h-position pay$h-kexp pay$h-vexp pay$h-index pay$o-sbr pay$o-sbl pay$n-k-expected-coordinate-q)
                           (unsigned-byte-p nth nthcdr take len stg-slot stg-put pay-staged
                            pay-staged-put logapp loghead logtail))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; THE REFERENCE RECORD.  It is built from what the datapath presented at one
; accepted begin and at the accepted payload transfers, and from nothing the
; controller stored: a layer, a position, the two exponent bytes, and a list
; of transfers, each (coordinate key value).
; ---------------------------------------------------------------------------
; what a transfer contributes to row h: its key to the K row (h = 0), its
; value to the V row (h = 1)
(define kv-reference-lane (h tr) :verify-guards nil
  (if (equal h 0) (second tr) (third tr)))
; the first n transfers' contributions, sixteen bits each, the first lowest
(define kv-reference-pack (h transfers n) :verify-guards nil
  (if (zp n)
      0
    (logapp 16 (kv-reference-lane h (car transfers))
            (kv-reference-pack h (cdr transfers) (- n 1)))))
; the data of word w of row h: for w < 8 the contributions of transfers
; 16w .. 16w+15; for w = 8 the row's exponent byte, twice, in bits [15:0]
(define kv-reference-data (h w kexp vexp transfers) :verify-guards nil
  (if (equal w 8)
      (b* ((e (loghead 8 (if (equal h 0) kexp vexp))))
        (logapp 8 e e))
    (kv-reference-pack h (nthcdr (* 16 w) transfers) 16)))
; the address of word w of row h of the record for a layer and a position
(define kv-reference-address (layer position h w) :verify-guards nil
  (+ 227072 (* 9 (+ (* 2 (+ (* 2048 layer) position)) h)) w))
(define kv-reference-word (h w layer position kexp vexp transfers) :verify-guards nil
  (list (kv-reference-address layer position h w)
        (kv-reference-data h w kexp vexp transfers)))
; THE EIGHTEEN WORDS, each (address data): the K row's eight coordinate
; words and its metadata word, then the V row's.
(define kv-reference-record (layer position kexp vexp transfers) :verify-guards nil
  (list (kv-reference-word 0 0 layer position kexp vexp transfers)
        (kv-reference-word 0 1 layer position kexp vexp transfers)
        (kv-reference-word 0 2 layer position kexp vexp transfers)
        (kv-reference-word 0 3 layer position kexp vexp transfers)
        (kv-reference-word 0 4 layer position kexp vexp transfers)
        (kv-reference-word 0 5 layer position kexp vexp transfers)
        (kv-reference-word 0 6 layer position kexp vexp transfers)
        (kv-reference-word 0 7 layer position kexp vexp transfers)
        (kv-reference-word 0 8 layer position kexp vexp transfers)
        (kv-reference-word 1 0 layer position kexp vexp transfers)
        (kv-reference-word 1 1 layer position kexp vexp transfers)
        (kv-reference-word 1 2 layer position kexp vexp transfers)
        (kv-reference-word 1 3 layer position kexp vexp transfers)
        (kv-reference-word 1 4 layer position kexp vexp transfers)
        (kv-reference-word 1 5 layer position kexp vexp transfers)
        (kv-reference-word 1 6 layer position kexp vexp transfers)
        (kv-reference-word 1 7 layer position kexp vexp transfers)
        (kv-reference-word 1 8 layer position kexp vexp transfers)))

; ---------------------------------------------------------------------------
; The controller's record against the reference, first about plain values.
; ---------------------------------------------------------------------------
; the key (h = 0) or value (h = 1) half of a stored pair
(define stg-lane (h pair) :verify-guards nil
  (if (equal h 0) (loghead 16 pair) (loghead 16 (logtail 16 pair))))
; sixteen such halves as one data word, the first lowest
(define stg-word16 (h p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13 p14 p15) :verify-guards nil
  (logapp 16 (stg-lane h p0)
  (logapp 16 (stg-lane h p1)
  (logapp 16 (stg-lane h p2)
  (logapp 16 (stg-lane h p3)
  (logapp 16 (stg-lane h p4)
  (logapp 16 (stg-lane h p5)
  (logapp 16 (stg-lane h p6)
  (logapp 16 (stg-lane h p7)
  (logapp 16 (stg-lane h p8)
  (logapp 16 (stg-lane h p9)
  (logapp 16 (stg-lane h p10)
  (logapp 16 (stg-lane h p11)
  (logapp 16 (stg-lane h p12)
  (logapp 16 (stg-lane h p13)
  (logapp 16 (stg-lane h p14)
  (logapp 16 (stg-lane h p15)
  0)))))))))))))))))
(in-theory (disable stg-lane stg-word16))
; The payload book's address is the reference's.
(fgl::def-fgl-thm stg-address-is-reference
  (implies (and (unsigned-byte-p 3 l) (unsigned-byte-p 11 p)
                (unsigned-byte-p 1 h) (unsigned-byte-p 4 w))
           (equal (pay-addr l p h w)
                  (+ 227072 (* 9 (+ (* 2 (+ (* 2048 l) p)) h)) w))))
; A coordinate word of the payload book's data is the sixteen halves the
; staged slots hold for its sixteen coordinates.
(fgl::def-fgl-thm stg-data-of-slots
  (implies (and (unsigned-byte-p 512 s0) (unsigned-byte-p 512 s1)
                (unsigned-byte-p 512 s2) (unsigned-byte-p 512 s3)
                (unsigned-byte-p 512 s4) (unsigned-byte-p 512 s5)
                (unsigned-byte-p 512 s6) (unsigned-byte-p 512 s7)
                (unsigned-byte-p 3 w) (unsigned-byte-p 1 h)
                (unsigned-byte-p 16 ke) (unsigned-byte-p 16 ve))
           (equal (pay-data-s w h ke ve s0 s1 s2 s3 s4 s5 s6 s7)
                  (stg-word16 h
                             (stg-slot (* 16 w) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 1 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 2 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 3 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 4 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 5 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 6 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 7 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 8 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 9 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 10 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 11 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 12 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 13 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 14 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 15 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)))))
; The metadata word of the payload book's data is the row's exponent byte,
; twice, when the exponent register holds the byte twice.
(fgl::def-fgl-thm stg-metadata-is-reference
  (implies (and (unsigned-byte-p 8 ke) (unsigned-byte-p 8 ve) (unsigned-byte-p 1 h))
           (equal (loghead 16 (if (equal h 1)
                                  (logapp 8 ve (loghead 8 ve))
                                (logapp 8 ke (loghead 8 ke))))
                  (logapp 8 (loghead 8 (if (equal h 0) ke ve))
                          (loghead 8 (if (equal h 0) ke ve))))))
(fgl::def-fgl-thm stg-exponents-size
  (implies (unsigned-byte-p 8 e)
           (unsigned-byte-p 16 (logapp 8 e (loghead 8 e)))))
; the halves of a pair made from a sixteen-bit key and value
(fgl::def-fgl-thm stg-lane-of-pair-bits
  (implies (and (unsigned-byte-p 16 k) (unsigned-byte-p 16 v))
           (and (equal (stg-lane 0 (logapp 16 k v)) k)
                (equal (stg-lane 1 (logapp 16 k v)) v))))
(in-theory (disable stg-address-is-reference stg-data-of-slots stg-metadata-is-reference
                    stg-lane-of-pair-bits))
(defthm stg-w3-is-w4
  (implies (unsigned-byte-p 3 w) (unsigned-byte-p 4 w)))
(defthm stg-8-is-w4
  (unsigned-byte-p 4 8))
(defthm stg-data-s-metadata
  (equal (pay-data-s 8 h ke ve s0 s1 s2 s3 s4 s5 s6 s7)
         (loghead 16 (if (equal h 1) ve ke)))
  :hints (("Goal" :in-theory (e/d (pay-data-s) (loghead logapp logtail)))))

; A coordinate word of a record held as (l p KE VE banks).
(defthm stg-coordinate-word-of-values
  (implies (and (unsigned-byte-p 1024 r-k-bank0)
                (unsigned-byte-p 1024 r-k-bank1)
                (unsigned-byte-p 1024 r-k-bank2)
                (unsigned-byte-p 1024 r-k-bank3)
                (unsigned-byte-p 1024 r-k-bank4)
                (unsigned-byte-p 1024 r-k-bank5)
                (unsigned-byte-p 1024 r-k-bank6)
                (unsigned-byte-p 1024 r-k-bank7)
                (unsigned-byte-p 16 r-k-pending-key-exponents-q)
                (unsigned-byte-p 16 r-k-pending-value-exponents-q)
                (unsigned-byte-p 3 r-k-pending-layer-q)
                (unsigned-byte-p 11 r-k-pending-position-q)
                (unsigned-byte-p 1 h) (unsigned-byte-p 3 w))
           (equal (rec-word h w r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)
                  (list (kv-reference-address r-k-pending-layer-q r-k-pending-position-q h w)
                        (b* ((s0 (pay-staged r-k-bank0)) (s1 (pay-staged r-k-bank1))
                             (s2 (pay-staged r-k-bank2)) (s3 (pay-staged r-k-bank3))
                             (s4 (pay-staged r-k-bank4)) (s5 (pay-staged r-k-bank5))
                             (s6 (pay-staged r-k-bank6)) (s7 (pay-staged r-k-bank7)))
                          (stg-word16 h
                             (stg-slot (* 16 w) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 1 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 2 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 3 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 4 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 5 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 6 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 7 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 8 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 9 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 10 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 11 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 12 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 13 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 14 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7)
                             (stg-slot (+ 15 (* 16 w)) s0 s1 s2 s3 s4 s5 s6 s7))))))
  :hints (("Goal"
           :in-theory (e/d (rec-word kv-reference-address pay-data-is-of-staged
                            stg-address-is-reference stg-data-of-slots)
                           (unsigned-byte-p pay-addr pay-data pay-data-s pay-staged stg-slot
                            stg-word16 logapp loghead logtail))))
  :rule-classes nil)
; The metadata word, when the exponent registers hold each byte twice.
(defthm stg-metadata-word-of-values
  (implies (and (unsigned-byte-p 1024 r-k-bank0)
                (unsigned-byte-p 1024 r-k-bank1)
                (unsigned-byte-p 1024 r-k-bank2)
                (unsigned-byte-p 1024 r-k-bank3)
                (unsigned-byte-p 1024 r-k-bank4)
                (unsigned-byte-p 1024 r-k-bank5)
                (unsigned-byte-p 1024 r-k-bank6)
                (unsigned-byte-p 1024 r-k-bank7)
                (unsigned-byte-p 3 r-k-pending-layer-q)
                (unsigned-byte-p 11 r-k-pending-position-q)
                (unsigned-byte-p 8 ke) (unsigned-byte-p 8 ve) (unsigned-byte-p 1 h)
                (equal r-k-pending-key-exponents-q (logapp 8 ke (loghead 8 ke)))
                (equal r-k-pending-value-exponents-q (logapp 8 ve (loghead 8 ve))))
           (equal (rec-word h 8 r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)
                  (kv-reference-word h 8 r-k-pending-layer-q r-k-pending-position-q ke ve log)))
  :hints (("Goal"
           :in-theory (e/d (rec-word kv-reference-word kv-reference-address kv-reference-data
                            pay-data-is-of-staged stg-address-is-reference
                            stg-metadata-is-reference stg-exponents-size)
                           (unsigned-byte-p pay-addr pay-data pay-data-s pay-staged stg-slot
                            logapp loghead logtail))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The same about a cycle of an execution.
; ---------------------------------------------------------------------------
; the record registers and the pair store hold definite values
(defthm stg-record-definite
  (implies (pay-known-at k envs outs)
           (and (unsigned-byte-p 1024 (pay$r-k-bank0 k k nil outs))
                (unsigned-byte-p 1024 (pay$r-k-bank1 k k nil outs))
                (unsigned-byte-p 1024 (pay$r-k-bank2 k k nil outs))
                (unsigned-byte-p 1024 (pay$r-k-bank3 k k nil outs))
                (unsigned-byte-p 1024 (pay$r-k-bank4 k k nil outs))
                (unsigned-byte-p 1024 (pay$r-k-bank5 k k nil outs))
                (unsigned-byte-p 1024 (pay$r-k-bank6 k k nil outs))
                (unsigned-byte-p 1024 (pay$r-k-bank7 k k nil outs))
                (unsigned-byte-p 3 (pay$r-k-pending-layer-q k k nil outs))
                (unsigned-byte-p 12 (pay$r-k-pending-position-q k k nil outs))
                (unsigned-byte-p 16 (pay$r-k-pending-key-exponents-q k k nil outs))
                (unsigned-byte-p 16 (pay$r-k-pending-value-exponents-q k k nil outs))))
  :hints (("Goal"
           :in-theory (e/d (pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q pay$h-sbegin pay$h-layer pay$h-position pay$h-kexp pay$h-vexp pay$h-index pay$o-sbr pay$o-sbl pay$n-k-expected-coordinate-q)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
; what the datapath presents with a begin, and with a transfer, is definite
(defthm stg-begin-definite
  (implies (stg-known-at k envs outs)
           (and (unsigned-byte-p 3 (stg-layer-at k outs))
                (unsigned-byte-p 11 (stg-position-at k outs))
                (unsigned-byte-p 8 (stg-kexp-at k outs))
                (unsigned-byte-p 8 (stg-vexp-at k outs))
                (unsigned-byte-p 16 (second (stg-transfer-at k envs outs)))
                (unsigned-byte-p 16 (third (stg-transfer-at k envs outs)))))
  :hints (("Goal"
           :in-theory (e/d (stg-known-at join-env-at join-env-raw joint-env-p
                            stg-layer-at stg-position-at stg-kexp-at stg-vexp-at stg-transfer-at
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q pay$h-sbegin pay$h-layer pay$h-position pay$h-kexp pay$h-vexp pay$h-index pay$o-sbr pay$o-sbl pay$n-k-expected-coordinate-q)
                           (unsigned-byte-p nth nthcdr take len loghead logapp logtail))))
  :rule-classes nil)
; so the halves of the pair an accepted transfer stores are its key and value
(defthm stg-transfer-lanes
  (implies (stg-known-at k envs outs)
           (and (equal (stg-lane 0 (stg-pair (stg-transfer-at k envs outs)))
                       (second (stg-transfer-at k envs outs)))
                (equal (stg-lane 1 (stg-pair (stg-transfer-at k envs outs)))
                       (third (stg-transfer-at k envs outs)))))
  :hints (("Goal"
           :use ((:instance stg-begin-definite)
                 (:instance stg-lane-of-pair-bits
                  (k (second (stg-transfer-at k envs outs)))
                  (v (third (stg-transfer-at k envs outs)))))
           :in-theory (e/d (stg-pair)
                           (stg-known-at stg-transfer-at unsigned-byte-p logapp loghead logtail))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; A STAGING AS A LIST OF TRANSFERS.
; ---------------------------------------------------------------------------
; The payload transfers accepted in cycles j .. k-1, in order.
(defund stg-log (j k envs outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix j))) :verify-guards nil))
  (if (zp (- (nfix k) (nfix j)))
      nil
    (append (stg-log j (- (nfix k) 1) envs outs)
            (if (equal (rec-beat-at (- (nfix k) 1) envs outs) 1)
                (list (stg-transfer-at (- (nfix k) 1) envs outs))
              nil))))
; The transfers of a list are for coordinates c0, c0+1, ... in order.
(defund stg-coords-from (c0 log)
  (declare (xargs :measure (acl2-count log) :verify-guards nil))
  (or (atom log)
      (and (equal (car (car log)) c0)
           (stg-coords-from (+ 1 c0) (cdr log)))))
(defthm stg-coords-from-of-snoc
  (implies (and (stg-coords-from c0 log)
                (acl2-numberp c0)
                (equal (car tr) (+ c0 (len log))))
           (stg-coords-from c0 (append log (list tr))))
  :hints (("Goal" :induct (stg-coords-from c0 log)
           :in-theory (enable stg-coords-from))))
(defthm stg-nth-of-snoc
  (implies (natp i)
           (equal (nth i (append log (list tr)))
                  (cond ((< i (len log)) (nth i log))
                        ((equal i (len log)) tr)
                        (t nil))))
  :hints (("Goal" :induct (nth i log) :in-theory (enable nth))))
(defthm stg-len-of-snoc
  (equal (len (append log (list tr))) (+ 1 (len log))))
; The pair store in cycle k holds the first c transfers of a list at their
; coordinates.
(defund stg-slots-ok (c k log outs)
  (declare (xargs :verify-guards nil))
  (or (zp c)
      (and (equal (stg-lane 0 (stg-slot-at (- c 1) k outs)) (second (nth (- c 1) log)))
           (equal (stg-lane 1 (stg-slot-at (- c 1) k outs)) (third (nth (- c 1) log)))
           (stg-slots-ok (- c 1) k log outs))))
(defthm stg-slot-when-ok
  (implies (and (stg-slots-ok c k log outs) (natp i) (natp c) (< i c))
           (and (equal (stg-lane 0 (stg-slot-at i k outs)) (second (nth i log)))
                (equal (stg-lane 1 (stg-slot-at i k outs)) (third (nth i log)))))
  :hints (("Goal" :induct (stg-slots-ok c k log outs)
           :in-theory (enable stg-slots-ok)))
  :rule-classes nil)
; the expected coordinate is seven bits
(defthm stg-coord-size
  (implies (pay-known-at k envs outs)
           (unsigned-byte-p 7 (rec-coord-at k outs)))
  :hints (("Goal"
           :in-theory (e/d (pay-known-at join-j-at join-inv-raw joint-2valued-p
                            rec-coord-at pay$r-k-expected-coordinate-q)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
; the pair store one cycle later, as rewrite rules for the two cases
(defthm stg-slot-next-quiet
  (implies (and (stg-known-at k envs outs)
                (not (equal (rec-beat-at k envs outs) 1))
                (natp k) (unsigned-byte-p 7 c))
           (equal (stg-slot-at c (+ 1 k) outs) (stg-slot-at c k outs)))
  :hints (("Goal" :use ((:instance stg-slot-step))
           :in-theory (disable stg-known-at stg-slot-at rec-beat-at unsigned-byte-p))))
(defthm stg-slot-next-beat
  (implies (and (stg-known-at k envs outs)
                (equal (rec-beat-at k envs outs) 1)
                (natp k) (unsigned-byte-p 7 c))
           (equal (stg-slot-at c (+ 1 k) outs)
                  (if (equal c (rec-coord-at k outs))
                      (stg-pair (stg-transfer-at k envs outs))
                    (stg-slot-at c k outs))))
  :hints (("Goal" :use ((:instance stg-slot-step))
           :in-theory (disable stg-known-at stg-slot-at rec-beat-at rec-coord-at
                               stg-pair stg-transfer-at unsigned-byte-p))))
(in-theory (disable stg-slot-next-quiet stg-slot-next-beat))
(defthm stg-slots-ok-next-quiet
  (implies (and (stg-slots-ok c k log outs)
                (stg-known-at k envs outs)
                (not (equal (rec-beat-at k envs outs) 1))
                (natp k) (natp c) (<= c 128))
           (stg-slots-ok c (+ 1 k) log outs))
  :hints (("Goal" :induct (stg-slots-ok c k log outs)
           :in-theory (e/d (stg-slots-ok stg-slot-next-quiet)
                           (stg-known-at stg-slot-at rec-beat-at))))
  :rule-classes nil)
(defthm stg-slots-ok-next-beat-below
  (implies (and (stg-slots-ok c k log outs)
                (stg-known-at k envs outs)
                (equal (rec-beat-at k envs outs) 1)
                (natp k) (natp c) (<= c (rec-coord-at k outs))
                (<= c (len log)) (<= c 128))
           (stg-slots-ok c (+ 1 k) (append log (list tr)) outs))
  :hints (("Goal" :induct (stg-slots-ok c k log outs)
           :in-theory (e/d (stg-slots-ok stg-slot-next-beat)
                           (stg-known-at stg-slot-at rec-beat-at rec-coord-at
                            stg-pair stg-transfer-at))))
  :rule-classes nil)
(defthm stg-slots-ok-next-beat
  (implies (and (stg-slots-ok (len log) k log outs)
                (stg-known-at k envs outs)
                (equal (rec-beat-at k envs outs) 1)
                (equal (rec-coord-at k outs) (len log))
                (natp k) (< (len log) 128))
           (stg-slots-ok (+ 1 (len log)) (+ 1 k)
                         (append log (list (stg-transfer-at k envs outs))) outs))
  :hints (("Goal"
           :use ((:instance stg-slots-ok-next-beat-below
                  (c (len log)) (tr (stg-transfer-at k envs outs)))
                 (:instance stg-transfer-lanes))
           :expand ((stg-slots-ok (+ 1 (len log)) (+ 1 k)
                                  (append log (list (stg-transfer-at k envs outs))) outs))
           :in-theory (e/d (stg-slot-next-beat)
                           (stg-known-at stg-slot-at rec-beat-at rec-coord-at
                            stg-pair stg-transfer-at stg-lane))))
  :rule-classes nil)

; From cycle b to cycle k: the controller is staging in every cycle after b
; up to k, there is no CLEAR in any cycle from b to k-1, and no begin is
; accepted in any cycle after b up to k-1.
(defund stg-quiet (b k envs outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix b))) :verify-guards nil))
  (or (zp (- (nfix k) (nfix b)))
      (and (equal (pay-st-at (nfix k) outs) 1)
           (equal (rec-clear-at (- (nfix k) 1) envs) 0)
           (or (equal (- (nfix k) 1) (nfix b))
               (equal (stg-begin-at (- (nfix k) 1) envs outs) 0))
           (stg-quiet b (- (nfix k) 1) envs outs))))
; The latest cycle up to n in which a begin is accepted; nil when none.
(defund stg-begin (n envs outs)
  (declare (xargs :measure (nfix n) :verify-guards nil))
  (cond ((equal (stg-begin-at (nfix n) envs outs) 1) (nfix n))
        ((zp n) nil)
        (t (stg-begin (- n 1) envs outs))))
; The invariant of the argument, for a staging that began at cycle b and is
; still going at cycle k: the record registers hold what the begin captured,
; the transfers accepted since are for coordinates 0, 1, 2, ... up to the
; expected coordinate, and the pair store holds each at its coordinate.
(defund stg-inv (b k envs outs)
  (declare (xargs :verify-guards nil))
  (and (natp b) (< b k)
       (equal (stg-begin-at b envs outs) 1)
       (equal (pay-st-at b outs) 0)
       (stg-quiet b k envs outs)
       (equal (stg-held-at k outs) (stg-captured-at b outs))
       (equal (len (stg-log (+ 1 b) k envs outs)) (rec-coord-at k outs))
       (stg-coords-from 0 (stg-log (+ 1 b) k envs outs))
       (stg-slots-ok (rec-coord-at k outs) k (stg-log (+ 1 b) k envs outs) outs)))

(defthm stg-inv-base
  (implies (and (natp k)
                (stg-known-at k envs outs)
                (equal (pay-st-at (+ 1 k) outs) 1)
                (not (equal (pay-st-at k outs) 1)))
           (stg-inv k (+ 1 k) envs outs))
  :hints (("Goal"
           :use ((:instance stg-entry-step))
           :expand ((stg-quiet k (+ 1 k) envs outs)
                    (stg-quiet k k envs outs)
                    (stg-log (+ 1 k) (+ 1 k) envs outs))
           :in-theory (e/d (stg-inv stg-slots-ok stg-coords-from)
                           (stg-known-at stg-held-at stg-captured-at stg-begin-at
                            rec-clear-at rec-coord-at))))
  :rule-classes nil)

(defthm stg-inv-step
  (implies (and (natp b) (natp k) (< b k)
                (stg-known-at k envs outs)
                (equal (pay-st-at k outs) 1)
                (equal (pay-st-at (+ 1 k) outs) 1)
                (stg-inv b k envs outs))
           (stg-inv b (+ 1 k) envs outs))
  :hints (("Goal"
           :use ((:instance stg-stay-step)
                 (:instance stg-coord-size)
                 (:instance stg-slots-ok-next-quiet
                  (c (rec-coord-at k outs)) (log (stg-log (+ 1 b) k envs outs)))
                 (:instance stg-slots-ok-next-beat
                  (log (stg-log (+ 1 b) k envs outs)))
                 (:instance stg-coords-from-of-snoc
                  (c0 0) (log (stg-log (+ 1 b) k envs outs))
                  (tr (stg-transfer-at k envs outs))))
           :expand ((stg-quiet b (+ 1 k) envs outs)
                    (stg-log (+ 1 b) (+ 1 k) envs outs))
           :in-theory (e/d (stg-inv stg-known-at rec-known-at)
                           (pay-known-at rec-facts-at stg-facts-at join-env-at stg-held-at
                            stg-captured-at stg-begin-at rec-clear-at rec-coord-at rec-beat-at
                            stg-transfer-at stg-coords-from-of-snoc))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; From the reset and the environment to the invariant at every staging cycle.
; ---------------------------------------------------------------------------
(defthm stg-known-at-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp i) (<= (+ 2 r) i)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) (+ 1 i) envs outs))
             (stg-known-at i envs outs)))
  :hints (("Goal"
           :use ((:instance rec-known-at-from-reset)
                 (:instance join-env-from-shorter
                  (j (+ 2 r)) (n i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-inv-from-reset (n i))
                 (:instance pay-inv-from-reset (n i))
                 (:instance stg-step-glue (k i)))
           :in-theory (e/d (stg-known-at)
                           (join-inv-from-reset pay-inv-from-reset join-step-glue
                            pay-step-glue pay-ints-glue rec-step-glue stg-step-glue
                            join-inv-preserved pay-inv-preserved join-reset-glue
                            pay-reset-glue join-j-at pay-j-at pay-facts-at pay-ints-at
                            rec-facts-at stg-facts-at rec-known-at pay-known-at
                            join-env-at join-env-from join-reset-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; One more cycle of the induction.
(defthm stg-inv-holds-step
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp k) (< (+ 2 r) k)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) k envs outs)
                  (equal (pay-st-at k outs) 1)
                  (implies (and (< (+ 2 r) (+ -1 k))
                                (equal (pay-st-at (+ -1 k) outs) 1))
                           (and (natp (stg-begin (+ -2 k) envs outs))
                                (<= (+ 2 r) (stg-begin (+ -2 k) envs outs))
                                (stg-inv (stg-begin (+ -2 k) envs outs) (+ -1 k) envs outs))))
             (and (natp (stg-begin (+ -1 k) envs outs))
                  (<= (+ 2 r) (stg-begin (+ -1 k) envs outs))
                  (stg-inv (stg-begin (+ -1 k) envs outs) k envs outs))))
  :hints (("Goal"
           :use ((:instance stg-known-at-from-reset (i (+ -1 k)))
                 (:instance rec-idle-after-reset)
                 (:instance stg-inv-base (k (+ -1 k)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-stay-step (k (+ -1 k)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-inv-step (k (+ -1 k))
                  (b (stg-begin (+ -2 k) envs (fsm-eval envs initst (probe-fsm))))
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-entry-step (k (+ -1 k)) (outs (fsm-eval envs initst (probe-fsm)))))
           :expand ((stg-begin (+ -1 k) envs (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (stg-inv)
                           (stg-known-at stg-quiet stg-log stg-slots-ok stg-coords-from
                            stg-held-at stg-captured-at stg-begin-at rec-clear-at rec-coord-at
                            rec-beat-at stg-transfer-at join-env-from join-reset-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; THE STAGING INVARIANT AT EVERY CYCLE.  In every execution, with the reset,
; storage and environment hypotheses holding up to cycle k: if at cycle k the
; controller is staging, then a begin was accepted at some cycle b after the
; reset, b is the latest such cycle before k, and the invariant holds
; between b and k.
(defthm stg-inv-holds
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp k) (< (+ 2 r) k)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) k envs outs)
                  (equal (pay-st-at k outs) 1))
             (and (natp (stg-begin (+ -1 k) envs outs))
                  (<= (+ 2 r) (stg-begin (+ -1 k) envs outs))
                  (stg-inv (stg-begin (+ -1 k) envs outs) k envs outs))))
  :hints (("Goal"
           :induct (rec-ind r k)
           :in-theory (e/d (rec-ind)
                           (stg-inv stg-begin join-env-from
                            join-reset-at pay-definite-at fsm-eval (probe-fsm) probe-fsm)))
          ("Subgoal *1/2"
           :use ((:instance stg-inv-holds-step))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; THE RECORD AT ITS START IS THE REFERENCE RECORD.
; ---------------------------------------------------------------------------
; a half of the pair the store holds for a coordinate, once all 128 are in
(defthm stg-lane-of-staged-when-ok
  (implies (and (stg-slots-ok 128 k log outs)
                (natp i) (< i 128)
                (or (equal h 0) (equal h 1)))
           (equal (stg-lane h (stg-slot i (pay-staged (pay$r-k-bank0 k k nil outs)) (pay-staged (pay$r-k-bank1 k k nil outs)) (pay-staged (pay$r-k-bank2 k k nil outs)) (pay-staged (pay$r-k-bank3 k k nil outs)) (pay-staged (pay$r-k-bank4 k k nil outs)) (pay-staged (pay$r-k-bank5 k k nil outs)) (pay-staged (pay$r-k-bank6 k k nil outs)) (pay-staged (pay$r-k-bank7 k k nil outs))))
                  (kv-reference-lane h (nth i log))))
  :hints (("Goal"
           :use ((:instance stg-slot-when-ok (c 128)))
           :in-theory (e/d (stg-slot-at kv-reference-lane) (nth)))))
(in-theory (disable stg-lane-of-staged-when-ok))
; the reference's packing, one transfer at a time
(defthm stg-cdr-of-nthcdr
  (implies (natp m)
           (equal (cdr (nthcdr m x)) (nthcdr (+ 1 m) x))))
(defthm stg-pack-unroll
  (implies (and (posp n) (natp m))
           (equal (kv-reference-pack h (nthcdr m x) n)
                  (logapp 16 (kv-reference-lane h (nth m x))
                          (kv-reference-pack h (nthcdr (+ 1 m) x) (+ -1 n)))))
  :hints (("Goal" :expand ((kv-reference-pack h (nthcdr m x) n))
           :in-theory (disable logapp nth nthcdr))))
(defthm stg-pack-zero
  (equal (kv-reference-pack h x 0) 0)
  :hints (("Goal" :in-theory (enable kv-reference-pack))))
(in-theory (disable stg-cdr-of-nthcdr stg-pack-unroll stg-pack-zero))
(defthm stg-pack-16
  (implies (and (natp w) (< w 8))
           (equal (kv-reference-pack h (nthcdr (* 16 w) log) 16)
                  (logapp 16 (kv-reference-lane h (nth (* 16 w) log))
            (logapp 16 (kv-reference-lane h (nth (+ 1 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 2 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 3 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 4 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 5 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 6 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 7 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 8 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 9 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 10 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 11 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 12 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 13 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 14 (* 16 w)) log))
            (logapp 16 (kv-reference-lane h (nth (+ 15 (* 16 w)) log))
            0))))))))))))))))))
  :hints (("Goal" :in-theory (e/d (stg-pack-unroll stg-pack-zero)
                                  (logapp nth nthcdr kv-reference-lane))))
  :rule-classes nil)

; A coordinate word of the record held in cycle k, when the pair store holds
; the 128 transfers of `log`.
(defthm stg-coordinate-word-is-reference
  (implies (and (stg-slots-ok 128 k log outs)
                (pay-known-at k envs outs)
                (equal (stg-held-at k outs)
                       (list l p (logapp 8 ke (loghead 8 ke)) (logapp 8 ve (loghead 8 ve))))
                (unsigned-byte-p 3 l) (unsigned-byte-p 11 p)
                (unsigned-byte-p 8 ke) (unsigned-byte-p 8 ve)
                (or (equal h 0) (equal h 1))
                (natp w) (< w 8))
           (equal (rec-word-at h w k outs)
                  (kv-reference-word h w l p ke ve log)))
  :hints (("Goal"
           :use ((:instance stg-record-definite)
                 (:instance stg-pack-16)
                 (:instance stg-coordinate-word-of-values
                  (r-k-pending-layer-q (pay$r-k-pending-layer-q k k nil outs))
                  (r-k-pending-position-q (pay$r-k-pending-position-q k k nil outs))
                  (r-k-pending-key-exponents-q (pay$r-k-pending-key-exponents-q k k nil outs))
                  (r-k-pending-value-exponents-q (pay$r-k-pending-value-exponents-q k k nil outs))
                  (r-k-bank0 (pay$r-k-bank0 k k nil outs))
                  (r-k-bank1 (pay$r-k-bank1 k k nil outs))
                  (r-k-bank2 (pay$r-k-bank2 k k nil outs))
                  (r-k-bank3 (pay$r-k-bank3 k k nil outs))
                  (r-k-bank4 (pay$r-k-bank4 k k nil outs))
                  (r-k-bank5 (pay$r-k-bank5 k k nil outs))
                  (r-k-bank6 (pay$r-k-bank6 k k nil outs))
                  (r-k-bank7 (pay$r-k-bank7 k k nil outs))))
           :in-theory (e/d (rec-word-at stg-held-at kv-reference-word kv-reference-data
                            stg-word16 stg-lane-of-staged-when-ok)
                           (unsigned-byte-p rec-word kv-reference-address kv-reference-pack
                            kv-reference-lane pay-staged stg-slot stg-lane
                            logapp loghead logtail nth nthcdr))))
  :rule-classes nil)
; The metadata word.
(defthm stg-metadata-word-is-reference
  (implies (and (pay-known-at k envs outs)
                (equal (stg-held-at k outs)
                       (list l p (logapp 8 ke (loghead 8 ke)) (logapp 8 ve (loghead 8 ve))))
                (unsigned-byte-p 3 l) (unsigned-byte-p 11 p)
                (unsigned-byte-p 8 ke) (unsigned-byte-p 8 ve)
                (or (equal h 0) (equal h 1)))
           (equal (rec-word-at h 8 k outs)
                  (kv-reference-word h 8 l p ke ve log)))
  :hints (("Goal"
           :use ((:instance stg-record-definite)
                 (:instance stg-metadata-word-of-values
                  (r-k-pending-layer-q (pay$r-k-pending-layer-q k k nil outs))
                  (r-k-pending-position-q (pay$r-k-pending-position-q k k nil outs))
                  (r-k-pending-key-exponents-q (pay$r-k-pending-key-exponents-q k k nil outs))
                  (r-k-pending-value-exponents-q (pay$r-k-pending-value-exponents-q k k nil outs))
                  (r-k-bank0 (pay$r-k-bank0 k k nil outs))
                  (r-k-bank1 (pay$r-k-bank1 k k nil outs))
                  (r-k-bank2 (pay$r-k-bank2 k k nil outs))
                  (r-k-bank3 (pay$r-k-bank3 k k nil outs))
                  (r-k-bank4 (pay$r-k-bank4 k k nil outs))
                  (r-k-bank5 (pay$r-k-bank5 k k nil outs))
                  (r-k-bank6 (pay$r-k-bank6 k k nil outs))
                  (r-k-bank7 (pay$r-k-bank7 k k nil outs))))
           :in-theory (e/d (rec-word-at stg-held-at)
                           (unsigned-byte-p rec-word kv-reference-word
                            logapp loghead logtail nth nthcdr))))
  :rule-classes nil)

; At a record's start: a begin was accepted at b, the latest before the
; start; staging ran from b+1 without CLEAR and without another begin; the
; record registers hold what that begin captured; 128 transfers were accepted,
; for coordinates 0 to 127 in order; and the pair store holds them.
(defthm stg-record-staged
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (b (stg-begin (+ -1 j) envs outs))
       (log (stg-log (+ 1 b) j envs outs)))
    (implies (and (natp r) (natp j) (< (+ 2 r) j)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) j envs outs)
                  (rec-start-p j outs))
             (and (natp b) (<= (+ 2 r) b) (< b (+ -1 j))
                  (equal (stg-begin-at b envs outs) 1)
                  (equal (pay-st-at b outs) 0)
                  (stg-quiet b (+ -1 j) envs outs)
                  (equal (rec-clear-at (+ -1 j) envs) 0)
                  (equal (stg-begin-at (+ -1 j) envs outs) 0)
                  (equal (stg-held-at j outs) (stg-captured-at b outs))
                  (equal (len log) 128)
                  (stg-coords-from 0 log)
                  (stg-slots-ok 128 j log outs))))
  :hints (("Goal"
           :use ((:instance rec-start-facts (n j))
                 (:instance rec-idle-after-reset)
                 (:instance stg-known-at-from-reset (i (+ -1 j)))
                 (:instance stg-inv-holds (k (+ -1 j)))
                 (:instance stg-last-step (k (+ -1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-coord-size (k (+ -1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-slots-ok-next-beat (k (+ -1 j)) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -2 j) envs (fsm-eval envs initst (probe-fsm)))) (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coords-from-of-snoc
                  (c0 0) (log (stg-log (+ 1 (stg-begin (+ -2 j) envs (fsm-eval envs initst (probe-fsm)))) (+ -1 j) envs (fsm-eval envs initst (probe-fsm))))
                  (tr (stg-transfer-at (+ -1 j) envs (fsm-eval envs initst (probe-fsm))))))
           :expand ((stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))
                    (stg-log (+ 1 (stg-begin (+ -2 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (stg-inv stg-known-at rec-known-at rec-start-p)
                           (pay-known-at rec-facts-at stg-facts-at join-env-at stg-quiet stg-log
                            stg-slots-ok stg-coords-from stg-coords-from-of-snoc
                            stg-held-at stg-captured-at stg-begin-at rec-clear-at
                            rec-coord-at rec-beat-at stg-transfer-at
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; So the record held at the start is the reference record of that begin and
; those transfers.
(defthm stg-record-is-reference
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (b (stg-begin (+ -1 j) envs outs))
       (log (stg-log (+ 1 b) j envs outs)))
    (implies (and (natp r) (natp j) (< (+ 2 r) j)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) (+ 1 j) envs outs)
                  (rec-start-p j outs))
             (equal (rec-words-at j outs)
                    (kv-reference-record (stg-layer-at b outs) (stg-position-at b outs)
                                         (stg-kexp-at b outs) (stg-vexp-at b outs) log))))
  :hints (("Goal"
           :use ((:instance stg-record-staged)
                 (:instance pay-known-at-from-reset (i j))
                 (:instance join-env-from-prefix
                  (j (+ 2 r)) (m j) (n (+ 1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-prefix
                  (j (+ 2 r)) (m (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))))) (n (+ 1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-known-at-from-reset (i (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-begin-definite (k (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 0) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 1) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 2) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 3) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 4) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 5) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 6) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 0) (w 7) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 0) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 1) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 2) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 3) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 4) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 5) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 6) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-coordinate-word-is-reference (h 1) (w 7) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-metadata-word-is-reference (h 0) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-metadata-word-is-reference (h 1) (k j) (outs (fsm-eval envs initst (probe-fsm)))
                  (log (stg-log (+ 1 (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))) j envs (fsm-eval envs initst (probe-fsm))))
                  (l (stg-layer-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (p (stg-position-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))
                  (ke (stg-kexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (ve (stg-vexp-at (stg-begin (+ -1 j) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))))
           :in-theory (e/d (rec-words-at rec-words rec-word-at kv-reference-record stg-captured-at)
                           (rec-word kv-reference-word stg-known-at pay-known-at stg-quiet
                            stg-log stg-slots-ok stg-coords-from stg-held-at stg-begin
                            stg-begin-at rec-clear-at rec-start-p stg-layer-at stg-position-at
                            stg-kexp-at stg-vexp-at stg-transfer-at unsigned-byte-p
                            logapp loghead logtail nth nthcdr
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ===========================================================================
; THE STAGING-TO-RECORD THEOREM.
;
; The definitions it is stated with.  Every one reads RTL signals of the
; probe module board1_context2048_shared_token_probe.  The datapath is
; u_machine.u_six_layers.u_datapath and the controller is its u_kv_cache.
; ===========================================================================
; AN ACCEPTED BEGIN in cycle b: the datapath's kv_stage_begin_valid with the
; controller's stage_begin_ready_o and stage_begin_legal, and the controller
; idle (state_q = 0).
(define kv-staging-begin-accepted-at (b envs outs) :verify-guards nil
  (and (equal (stg-begin-at b envs outs) 1)
       (equal (pay-st-at b outs) 0)))
; THE BEGIN OF THE RECORD THAT STARTS AT j: the latest cycle before j in
; which a begin is accepted.
(define kv-staging-begin (j envs outs) :verify-guards nil
  (stg-begin (+ -1 j) envs outs))
; What the datapath presents with the begin in cycle b: current_layer_q,
; current_position_q, key_exponent_q, value_exponent_q.
(define kv-staged-layer (b outs) :verify-guards nil (stg-layer-at b outs))
(define kv-staged-position (b outs) :verify-guards nil (stg-position-at b outs))
(define kv-staged-key-exponent (b outs) :verify-guards nil (stg-kexp-at b outs))
(define kv-staged-value-exponent (b outs) :verify-guards nil (stg-vexp-at b outs))
; THE ACCEPTED PAYLOAD TRANSFERS of cycles b+1 to j-1, in order.  A transfer
; is accepted in a cycle when the datapath's kv_stage_payload_valid meets the
; controller's stage_payload_ready_o and stage_payload_legal; it is the list
; (input_index_q[6:0] key_ram_read_data value_ram_read_data) of that cycle.
(define kv-staged-transfers (b j envs outs) :verify-guards nil
  (stg-log (+ 1 b) j envs outs))
; the transfers are for coordinates 0, 1, 2, ... in order
(define kv-transfers-in-order (transfers) :verify-guards nil
  (stg-coords-from 0 transfers))
; STAGING FROM b TO THE START j: the controller is staging (state_q = 1) in
; every cycle from b+1 to j-1, clear_i is 0 in every cycle from b to j-1,
; and no other begin is accepted in any cycle from b+1 to j-1.
(define kv-staging-uninterrupted (b j envs outs) :verify-guards nil
  (and (stg-quiet b (+ -1 j) envs outs)
       (equal (rec-clear-at (+ -1 j) envs) 0)
       (equal (stg-begin-at (+ -1 j) envs outs) 0)))

; Take any execution of the probe module's state machine, from any initial
; state, with the reset, storage and environment hypotheses of the payload
; book holding through cycle n.  Suppose pending_persisted_q rises at cycle
; n.  Let j be the record's start (kv-write-record), b the latest cycle
; before j in which a begin is accepted, and `transfers` the payload
; transfers accepted from b+1 to j-1.  Then
;   - b is after the reset, the begin at b is accepted with the controller
;     idle, and from b to n there is no CLEAR, no other accepted begin before
;     the start, and no interruption;
;   - exactly 128 transfers were accepted, for coordinates 0 to 127 in order;
;   - the eighteen writes the endpoint (private_kv_req_*) accepted in cycles
;     j to n, in order, are the reference record of the begin's layer,
;     position and exponents and those transfers' keys and values.
(defthm kv-staging-to-record
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (transfers (kv-staged-transfers b j envs outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs))
             (and (natp b) (<= (+ 2 r) b) (< b j) (<= j n)
                  (kv-staging-begin-accepted-at b envs outs)
                  (kv-staging-uninterrupted b j envs outs)
                  (kv-record-uninterrupted j n envs outs)
                  (equal (len transfers) 128)
                  (kv-transfers-in-order transfers)
                  (equal (kv-endpoint-writes j (+ 1 n) envs outs)
                         (kv-reference-record (kv-staged-layer b outs)
                                              (kv-staged-position b outs)
                                              (kv-staged-key-exponent b outs)
                                              (kv-staged-value-exponent b outs)
                                              transfers)))))
  :hints (("Goal"
           :use ((:instance rec-record-written)
                 (:instance kvj-reset-connects (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-prefix
                  (j (+ 2 r)) (m (rec-start n (fsm-eval envs initst (probe-fsm)))) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-prefix
                  (j (+ 2 r)) (m (+ 1 (rec-start n (fsm-eval envs initst (probe-fsm))))) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance stg-record-staged (j (rec-start n (fsm-eval envs initst (probe-fsm)))))
                 (:instance stg-record-is-reference (j (rec-start n (fsm-eval envs initst (probe-fsm))))))
           :in-theory (e/d (kv-record-reported-complete-at kv-record-start kv-record-uninterrupted
                            kv-endpoint-writes kv-payload-storage-definite-at
                            kv-staging-begin-accepted-at kv-staging-begin kv-staged-layer
                            kv-staged-position kv-staged-key-exponent kv-staged-value-exponent
                            kv-staged-transfers kv-transfers-in-order kv-staging-uninterrupted)
                           (kvj-reset-connects kvj-environment-from-connects
                            rec-start rec-start-p rec-uninterrupted rec-complete-at rec-words-at
                            rec-clear-at pay-log stg-begin stg-begin-at stg-quiet stg-log
                            stg-slots-ok stg-coords-from stg-held-at stg-captured-at
                            stg-layer-at stg-position-at stg-kexp-at stg-vexp-at
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; WHILE A RECORD IS BEING STAGED, finished or not.  If in cycle k the
; controller is staging, then a begin was accepted at b, the latest before k,
; after the reset; since then there has been no CLEAR and no other accepted
; begin; and the transfers accepted since b are for coordinates 0, 1, 2, ...
; in order, as many as the controller's expected_coordinate_q says.  So a
; staging that CLEAR cuts short has accepted a prefix of a record's
; transfers, and by kv-write-record-not-credited-when-interrupted no
; completion is ever credited to it.
(define kv-staging-at (k outs) :verify-guards nil
  (equal (pay-st-at k outs) 1))
(define kv-expected-coordinate-at (k outs) :verify-guards nil
  (rec-coord-at k outs))
(defthm kv-staging-prefix
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (b (kv-staging-begin k envs outs))
       (transfers (kv-staged-transfers b k envs outs)))
    (implies (and (natp r) (natp k) (< (+ 2 r) k)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) k envs outs)
                  (kv-staging-at k outs))
             (and (natp b) (<= (+ 2 r) b) (< b k)
                  (kv-staging-begin-accepted-at b envs outs)
                  (equal (len transfers) (kv-expected-coordinate-at k outs))
                  (kv-transfers-in-order transfers))))
  :hints (("Goal"
           :use ((:instance stg-inv-holds)
                 (:instance kvj-reset-connects (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n k) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (kv-staging-at kv-expected-coordinate-at kv-payload-storage-definite-at
                            kv-staging-begin-accepted-at kv-staging-begin kv-staged-transfers
                            kv-transfers-in-order stg-inv)
                           (kvj-reset-connects kvj-environment-from-connects
                            stg-begin stg-begin-at stg-quiet stg-log stg-slots-ok
                            stg-coords-from stg-held-at stg-captured-at rec-coord-at
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ===========================================================================
; A REACHABLE RUN: three stagings for layer 0, position 0.  One cycle after
; another of the step run from the reset state, three reset cycles first.
; The first staging is cut short by CLEAR after 40 transfers.  The second
; completes; CLEAR cuts its write short on word 3 of the K row, and that
; word, already on its way, is accepted by the endpoint afterwards.  The
; third, with other keys, values and exponents, completes, and its write
; completes under a slow endpoint.  The datapath side is scripted, so this
; is a run of the slice and not a run from the public interface.
; ===========================================================================

; THE SCRIPT.  Three stagings for layer 0, position 0.
; Sets of data: set 0 has key #x100 + 3c and value #x4000 + 5c for coordinate
; c and exponent bytes 5 and 250; set 1 has key #x2000 + 7c,
; value #x7000 + 11c and exponent bytes 9 and 244.  Phases 1 and
; 2 stage set 0, phase 3 stages set 1.
(defun stg-key (set c)
  (declare (xargs :mode :program))
  (if (equal set 0) (+ #x100 (* 3 c)) (+ #x2000 (* 7 c))))
(defun stg-value (set c)
  (declare (xargs :mode :program))
  (if (equal set 0) (+ #x4000 (* 5 c)) (+ #x7000 (* 11 c))))
; The endpoint is slow, as in the record book's run: not ready on three
; cycles in five, and while the controller is on word 0, 3 or 8 of either
; row also not ready on 48 cycles in every 64.
(defun stg-ready (cycle st)
  (declare (xargs :mode :program))
  (if (or (< (mod cycle 5) 3)
          (and (member (pay-get 'k-write-word-q st) '(0 3 8))
               (< (mod cycle 64) 48)))
      0 1))
; What the datapath side presents in a cycle.  A begin when the controller
; is idle; a payload offer for the expected coordinate on three cycles in
; four while it is staging; and, when `hold` is 1, the offer accepted in the
; previous cycle held for one more cycle.
(defun stg-script (cycle st phase hold)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st))
       (c (pay-get 'k-expected-coordinate-q st))
       (set (if (equal phase 3) 1 0))
       (base (list (cons 'h-epready (stg-ready cycle st))
                   (cons 'h-attn-ready 1)
                   (cons 'h-layer 0) (cons 'h-position 0)
                   (cons 'h-kexp (if (equal set 0) 5 9))
                   (cons 'h-vexp (if (equal set 0) 250 244)))))
    (cond ((and (equal s 0) (equal (pay-get 'k-stage-begin-consumed-q st) 0)
                (equal (pay-get 'k-lock-seen-q st) 1))
           (cons (cons 'h-sbegin 1) base))
          ((and (equal hold 1) (equal (pay-get 'k-stage-payload-consumed-q st) 1))
           (b* ((pc (if (equal s 1) (- c 1) 127)))
             (list* (cons 'h-spayload 1) (cons 'h-index pc)
                    (cons 'h-key (stg-key set pc)) (cons 'h-value (stg-value set pc))
                    base)))
          ((and (equal s 1) (equal (pay-get 'k-stage-payload-consumed-q st) 0)
                (not (equal (mod cycle 4) 2)))
           (list* (cons 'h-spayload 1) (cons 'h-index c)
                  (cons 'h-key (stg-key set c)) (cons 'h-value (stg-value set c))
                  base))
          (t base))))
; CLEAR: once in phase 1, when 40 transfers have been accepted; once in
; phase 2, in the first cycle of the wait on word 3 of the K row.
(defun stg-clear (st phase)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st)))
    (cond ((and (equal phase 1) (equal s 1)
                (equal (pay-get 'k-expected-coordinate-q st) 40))
           1)
          ((and (equal phase 2) (equal s 3)
                (equal (pay-get 'k-write-head-q st) 0)
                (equal (pay-get 'k-write-word-q st) 3))
           1)
          (t 0))))

; One cycle after another from `st`; one entry per cycle:
;   (cycle state_q write_head_q write_word_q write_aborted_q
;    pending_persisted_q its-next-value clear_i
;    begin        (layer position kexp vexp) when a begin is accepted, else nil
;    transfer     (coordinate key value) when a payload transfer is accepted
;    write        (address data) when the endpoint accepts a write
;    refused      1 when a write is offered and refused
;    held         1 when a payload offer is presented after its acceptance
;    phase)
; Stops when the controller reaches PENDING, on a signal that is not
; definite, on a fault, or at the limit.
(defun stg-run-loop (cycle limit st phase hold trace)
  (declare (xargs :mode :program))
  (b* (((when (<= limit cycle)) (list :limit (reverse trace)))
       (clear (stg-clear st phase))
       (hy (if (equal clear 1)
               (list (cons 'h-epready (stg-ready cycle st)) (cons 'h-attn-ready 1))
             (stg-script cycle st phase hold)))
       (out (svtv-run (staging-step-run)
                      (append (list (cons 'i-reset-n (if (< cycle 3) 0 1)) (cons 'i-clear clear))
                              (pay-state-env *pay-state-ids* st)
                              (pay-hyp-env *pay-hyp-ids* hy))
                      :quiet t))
       (nst (pay-next-state *pay-state-ids* out))
       ((unless (pay-all-natp nst)) (list :not-definite (reverse trace)))
       ((unless (and (equal (pay-get 'o-pfn out) 0) (equal (pay-get 'o-tfe out) 0)))
        (list :fault (reverse trace)))
       (begin (and (equal (pay-get 'h-sbegin hy) 1) (equal (pay-get 'o-sbr out) 1)
                   (equal (pay-get 'o-sbl out) 1)))
       (beat (and (equal (pay-get 'h-spayload hy) 1) (equal (pay-get 'o-spr out) 1)
                  (equal (pay-get 'o-spl out) 1)))
       (offered (and (equal (pay-get 'o-epv out) 1) (equal (pay-get 'o-epw out) 1)))
       (ready (equal (pay-get 'h-epready hy) 1))
       (held (if (and (equal (pay-get 'h-spayload hy) 1)
                      (equal (pay-get 'k-stage-payload-consumed-q st) 1))
                 1 0))
       (entry (list cycle
                    (pay-get 'k-state-q st) (pay-get 'k-write-head-q st)
                    (pay-get 'k-write-word-q st) (pay-get 'k-write-aborted-q st)
                    (pay-get 'k-pending-persisted-q st) (pay-get 'k-pending-persisted-q nst)
                    clear
                    (and begin (list (pay-get 'h-layer hy) (pay-get 'h-position hy)
                                     (pay-get 'h-kexp hy) (pay-get 'h-vexp hy)))
                    (and beat (list (loghead 7 (pay-get 'h-index hy))
                                    (pay-get 'h-key hy) (pay-get 'h-value hy)))
                    (and offered ready
                         (list (pay-get 'o-epaddr out) (pay-get 'o-epdata out)))
                    (if (and offered (not ready)) 1 0)
                    held phase))
       (trace (cons entry trace))
       ((when (equal (pay-get 'k-state-q nst) 4)) (list :complete (reverse trace)))
       (phase (if (equal clear 1) (+ 1 phase) phase))
       (hold (if (and beat (equal (mod (pay-get 'k-expected-coordinate-q st) 4) 1)) 1 0)))
    (stg-run-loop (+ 1 cycle) limit nst phase hold trace)))

; Reading a trace.  Field i of the entry of each cycle from j to n for which
; it is not nil, in order.
(defun stg-t-collect (trace i j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((< (nth 0 (car trace)) j) (stg-t-collect (cdr trace) i j n))
        ((< n (nth 0 (car trace))) nil)
        ((nth i (car trace)) (cons (nth i (car trace)) (stg-t-collect (cdr trace) i j n)))
        (t (stg-t-collect (cdr trace) i j n))))
; the sum of field i over the cycles from j to n
(defun stg-t-sum (trace i j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) 0)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (stg-t-sum (cdr trace) i j n))
        (t (+ (nth i (car trace)) (stg-t-sum (cdr trace) i j n)))))
; the completion edge: pending_persisted_q is 0 with next value 1
(defun stg-t-edge (trace)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((and (equal (nth 5 (car trace)) 0) (equal (nth 6 (car trace)) 1)) (nth 0 (car trace)))
        (t (stg-t-edge (cdr trace)))))
; the latest cycle up to n at which a record starts
(defun stg-t-start (trace n best)
  (declare (xargs :mode :program))
  (cond ((atom trace) best)
        ((< n (nth 0 (car trace))) best)
        ((and (equal (nth 1 (car trace)) 9) (equal (nth 2 (car trace)) 0)
              (equal (nth 3 (car trace)) 0))
         (stg-t-start (cdr trace) n (nth 0 (car trace))))
        (t (stg-t-start (cdr trace) n best))))
; the latest cycle before j in which a begin is accepted, and its fields
(defun stg-t-begin (trace j best)
  (declare (xargs :mode :program))
  (cond ((atom trace) best)
        ((<= j (nth 0 (car trace))) best)
        ((nth 8 (car trace)) (stg-t-begin (cdr trace) j (car trace)))
        (t (stg-t-begin (cdr trace) j best))))
; the cycles, from j to n, of the writes the endpoint accepted while
; write_aborted_q was 1, each with the write
(defun stg-t-late (trace j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (stg-t-late (cdr trace) j n))
        ((and (nth 10 (car trace)) (equal (nth 4 (car trace)) 1))
         (cons (list (nth 0 (car trace)) (nth 10 (car trace))) (stg-t-late (cdr trace) j n)))
        (t (stg-t-late (cdr trace) j n))))
; the cycles with CLEAR
(defun stg-t-clears (trace)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((equal (nth 7 (car trace)) 1) (cons (nth 0 (car trace)) (stg-t-clears (cdr trace))))
        (t (stg-t-clears (cdr trace)))))
(defun stg-t-coordinates (transfers)
  (declare (xargs :mode :program))
  (if (atom transfers) nil (cons (car (car transfers)) (stg-t-coordinates (cdr transfers)))))
(defun stg-count-up (i n)
  (declare (xargs :mode :program))
  (if (zp n) nil (cons i (stg-count-up (+ 1 i) (- n 1)))))
; the transfers of a list with the one for coordinate c replaced by tr
(defun stg-substitute (transfers c tr)
  (declare (xargs :mode :program))
  (cond ((atom transfers) nil)
        ((equal (car (car transfers)) c) (cons tr (cdr transfers)))
        (t (cons (car transfers) (stg-substitute (cdr transfers) c tr)))))
(defun stg-find (transfers c)
  (declare (xargs :mode :program))
  (cond ((atom transfers) nil)
        ((equal (car (car transfers)) c) (car transfers))
        (t (stg-find (cdr transfers) c))))
; What the theorems below are stated about.
(defun stg-run-summary (limit)
  (declare (xargs :mode :program))
  (b* ((run (stg-run-loop 0 limit (pay-zero-state *pay-state-ids*) 1 0 nil))
       (trace (second run))
       (n (stg-t-edge trace))
       (j (and n (stg-t-start trace n nil)))
       (bentry (and j (stg-t-begin trace j nil)))
       ((unless (and n j bentry)) (list (first run) (len trace) n j nil)))
    (b* ((b (nth 0 bentry))
         (fields (nth 8 bentry))
         (transfers (stg-t-collect trace 9 (+ 1 b) (- j 1)))
         (clears (stg-t-clears trace))
         (c1 (first clears))
         (c2 (second clears)))
      (list (first run) (len trace) n j b fields transfers
            ; the writes the endpoint accepted from j to n
            (stg-t-collect trace 10 j n)
            ; the reference record of the begin at b and those transfers
            (kv-reference-record (first fields) (second fields) (third fields) (fourth fields)
                                 transfers)
            ; cycles with CLEAR; cycles from b to n with CLEAR
            clears (stg-t-sum trace 7 b n)
            ; the first staging: its transfers, accepted before the first CLEAR
            (len (stg-t-collect trace 9 0 c1))
            ; the second staging's transfers, between the two CLEARs
            (stg-t-collect trace 9 c1 c2)
            ; every write the endpoint accepted before j, and those of them it
            ; accepted while write_aborted_q was 1
            (stg-t-collect trace 10 0 (- j 1))
            (stg-t-late trace 0 n)
            ; refused writes from j to n; held offers from b to j
            (stg-t-sum trace 11 j n)
            (stg-t-sum trace 12 b j)))))

(defconsts *stg-run* (stg-run-summary 8000))
(defconst *stg-run-outcome* (nth 0 *stg-run*))
(defconst *stg-run-cycles* (nth 1 *stg-run*))
; the completion edge, the record's start, the begin
(defconst *stg-run-n* (nth 2 *stg-run*))
(defconst *stg-run-j* (nth 3 *stg-run*))
(defconst *stg-run-b* (nth 4 *stg-run*))
; what the datapath presented with that begin: (layer position kexp vexp)
(defconst *stg-run-begin-fields* (nth 5 *stg-run*))
; the transfers accepted after b and before j
(defconst *stg-run-transfers* (nth 6 *stg-run*))
; the writes the endpoint accepted from j to n
(defconst *stg-run-writes* (nth 7 *stg-run*))
; the reference record of that begin and those transfers
(defconst *stg-run-reference* (nth 8 *stg-run*))
; the cycles with CLEAR, and how many of them are from b to n
(defconst *stg-run-clears* (nth 9 *stg-run*))
(defconst *stg-run-clears-in-record* (nth 10 *stg-run*))
; the transfers the first staging had accepted when CLEAR cut it short
(defconst *stg-run-first-staging-transfers* (nth 11 *stg-run*))
; the transfers of the second staging
(defconst *stg-run-second-staging* (nth 12 *stg-run*))
; the writes the endpoint accepted before j, and the writes it accepted
; while write_aborted_q was 1 (each with its cycle)
(defconst *stg-run-earlier-writes* (nth 13 *stg-run*))
(defconst *stg-run-late-writes* (nth 14 *stg-run*))
; refused writes from j to n; payload offers held after acceptance
(defconst *stg-run-refused* (nth 15 *stg-run*))
(defconst *stg-run-held-offers* (nth 16 *stg-run*))

; The record the third staging presents, computed outside ACL2 from its
; keys, values and exponents and the address formula: eighteen (address
; data).  And the same with the key and value of coordinate 77 taken
; from the earlier, second staging.
(defconst *stg-expected*
  '((227072 #x20692062205b2054204d2046203f20382031202a2023201c2015200e20072000)
    (227073 #x20d920d220cb20c420bd20b620af20a820a1209a2093208c2085207e20772070)
    (227074 #x21492142213b2134212d2126211f21182111210a210320fc20f520ee20e720e0)
    (227075 #x21b921b221ab21a4219d2196218f21882181217a2173216c2165215e21572150)
    (227076 #x22292222221b2214220d220621ff21f821f121ea21e321dc21d521ce21c721c0)
    (227077 #x22992292228b2284227d2276226f22682261225a2253224c2245223e22372230)
    (227078 #x2309230222fb22f422ed22e622df22d822d122ca22c322bc22b522ae22a722a0)
    (227079 #x23792372236b2364235d2356234f23482341233a2333232c2325231e23172310)
    (227080 #x909)
    (227081 #x70a5709a708f70847079706e70637058704d70427037702c70217016700b7000)
    (227082 #x7155714a713f71347129711e7113710870fd70f270e770dc70d170c670bb70b0)
    (227083 #x720571fa71ef71e471d971ce71c371b871ad71a27197718c71817176716b7160)
    (227084 #x72b572aa729f72947289727e72737268725d72527247723c72317226721b7210)
    (227085 #x7365735a734f73447339732e73237318730d730272f772ec72e172d672cb72c0)
    (227086 #x7415740a73ff73f473e973de73d373c873bd73b273a7739c73917386737b7370)
    (227087 #x74c574ba74af74a47499748e74837478746d74627457744c74417436742b7420)
    (227088 #x7575756a755f75547549753e75337528751d7512750774fc74f174e674db74d0)
    (227089 #xf4f4)))
(defconst *stg-expected-with-earlier-77*
  '((227072 #x20692062205b2054204d2046203f20382031202a2023201c2015200e20072000)
    (227073 #x20d920d220cb20c420bd20b620af20a820a1209a2093208c2085207e20772070)
    (227074 #x21492142213b2134212d2126211f21182111210a210320fc20f520ee20e720e0)
    (227075 #x21b921b221ab21a4219d2196218f21882181217a2173216c2165215e21572150)
    (227076 #x2229222201e72214220d220621ff21f821f121ea21e321dc21d521ce21c721c0)
    (227077 #x22992292228b2284227d2276226f22682261225a2253224c2245223e22372230)
    (227078 #x2309230222fb22f422ed22e622df22d822d122ca22c322bc22b522ae22a722a0)
    (227079 #x23792372236b2364235d2356234f23482341233a2333232c2325231e23172310)
    (227080 #x909)
    (227081 #x70a5709a708f70847079706e70637058704d70427037702c70217016700b7000)
    (227082 #x7155714a713f71347129711e7113710870fd70f270e770dc70d170c670bb70b0)
    (227083 #x720571fa71ef71e471d971ce71c371b871ad71a27197718c71817176716b7160)
    (227084 #x72b572aa729f72947289727e72737268725d72527247723c72317226721b7210)
    (227085 #x7365735a418173447339732e73237318730d730272f772ec72e172d672cb72c0)
    (227086 #x7415740a73ff73f473e973de73d373c873bd73b273a7739c73917386737b7370)
    (227087 #x74c574ba74af74a47499748e74837478746d74627457744c74417436742b7420)
    (227088 #x7575756a755f75547549753e75337528751d7512750774fc74f174e674db74d0)
    (227089 #xf4f4)))
(defconst *stg-run-transfer-coordinates* (stg-t-coordinates *stg-run-transfers*))
(defconst *stg-count-128* (stg-count-up 0 128))
; the reference record of the begin at b with the transfer for coordinate
; 77 replaced by the second staging's transfer for that coordinate
(defconst *stg-run-reference-with-earlier-77*
  (kv-reference-record (first *stg-run-begin-fields*) (second *stg-run-begin-fields*)
                       (third *stg-run-begin-fields*) (fourth *stg-run-begin-fields*)
                       (stg-substitute *stg-run-transfers* 77
                                       (stg-find *stg-run-second-staging* 77))))

; pending_persisted_q rises once, at cycle n.  The record started at j; the
; latest begin before j was accepted at b, for layer 0 and position 0 with
; exponent bytes 9 and 244; there is no CLEAR from b to n.
(defthm kv-staging-run-completes
  (and (equal *stg-run-outcome* :complete)
       (natp *stg-run-b*) (natp *stg-run-j*) (natp *stg-run-n*)
       (< *stg-run-b* *stg-run-j*) (< *stg-run-j* *stg-run-n*)
       (equal *stg-run-begin-fields* '(0 0 9 244))
       (equal *stg-run-clears-in-record* 0))
  :rule-classes nil)

; The theorem's conclusion on this run: 128 transfers were accepted between
; b and j, for coordinates 0 to 127 in order; the eighteen writes accepted
; from j to n are the reference record of that begin and those transfers;
; and that is the record the script presented in its third staging.
(defthm kv-staging-run-is-the-reference
  (and (equal (len *stg-run-transfers*) 128)
       (equal *stg-run-transfer-coordinates* *stg-count-128*)
       (equal (len *stg-run-writes*) 18)
       (equal *stg-run-writes* *stg-run-reference*)
       (equal *stg-run-reference* *stg-expected*))
  :rule-classes nil)

; What came before it.  CLEAR in cycles 108 479.  The first staging had
; accepted 40 transfers.  The second accepted all 128, and four of its
; record's words reached the endpoint: the fourth was accepted in cycle
; 498, after its CLEAR, while write_aborted_q was 1, and before the third
; begin.  All four are at the addresses the completed record uses again.
; The endpoint refused a write in 129 of the cycles from j to n, and
; 32 payload offers were held for a cycle after they had been accepted.
(defthm kv-staging-run-was-interrupted-and-stalled
  (and (equal *stg-run-clears* '(108 479))
       (equal *stg-run-first-staging-transfers* 40)
       (equal (len *stg-run-second-staging*) 128)
       (equal (strip-cars *stg-run-earlier-writes*) (take 4 (strip-cars *stg-run-writes*)))
       (equal (strip-cars *stg-run-late-writes*) '(498))
       (< (second *stg-run-clears*) 498)
       (< 498 *stg-run-b*)
       (equal *stg-run-refused* 129)
       (equal *stg-run-held-offers* 32))
  :rule-classes nil)

; Substituting the earlier record's key and value at one coordinate gives a
; different expected record, at the same eighteen addresses, and the run's
; writes are not that record.
(defthm kv-staging-run-substitution-changes-the-record
  (and (not (equal *stg-run-reference-with-earlier-77* *stg-run-reference*))
       (equal (strip-cars *stg-run-reference-with-earlier-77*)
              (strip-cars *stg-run-reference*))
       (equal *stg-run-reference-with-earlier-77* *stg-expected-with-earlier-77*)
       (not (equal *stg-run-writes* *stg-run-reference-with-earlier-77*)))
  :rule-classes nil)

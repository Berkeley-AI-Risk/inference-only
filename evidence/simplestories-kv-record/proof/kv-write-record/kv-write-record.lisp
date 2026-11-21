; The K/V write record: the theorem.
;
; Written by make_record_book.py; do not edit.  Private.
;
; THE CLAIM.  Take any execution of the probe module's state machine
; satisfying the reset, storage and environment hypotheses of the payload
; book.  When the controller's pending_persisted_q rises, the writes the
; typed DDR boundary's endpoint (private_kv_req_*) accepted since the
; record's start are exactly eighteen: the eight coordinate words of the K
; row, the K metadata word, the eight coordinate words of the V row, the V
; metadata word, in that order, each at its address, and all eighteen
; address and data words are those of the record as the controller held it
; in one cycle, the record's start.  The record was not interrupted between
; its start and that edge.  This is kv-write-record, near the end of this
; file, stated in terms of RTL signals; kv-write-record-prefix and
; kv-write-record-not-credited-when-interrupted say what holds of a record
; that CLEAR interrupts.
;
; WHAT IT RESTS ON.  The imported book's facts about every cycle
; (kv-write-payload-guarantee and the lemmas under its row theorem), the
; two new facts of kv-write-record-lift.lisp, and an induction over the
; cycles of the execution that follows one record from its start.  No row is
; assumed to complete: the K row, the step to the V row, the V row and the
; identity of the record across all three are derived.
(in-package "SV")
(include-book "kv-write-record-lift")
(acl2::set-slow-alist-action nil)

; ---------------------------------------------------------------------------
; THE NEW FACTS AT CYCLE k OF AN EXECUTION.  The lifted lemma's own signal
; bindings are read back from the world, as the payload book does.
; ---------------------------------------------------------------------------
(make-event
 (b* ((ev (acl2::get-event 'rec-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (decl `(declare (xargs :verify-guards nil) (ignorable ,@formals)))
      (idecl `(declare (ignorable ,@vars))))
   `(progn
      (defun rec-facts-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and (rec-fact-entry i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
               (rec-fact-start h-spayload i-clear n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-spl o-spr r-k-expected-coordinate-q r-k-state-q))))
      (in-theory (disable rec-facts-raw)))))
; The two new facts about cycle k.
(define rec-facts-at (k envs outs) :verify-guards nil
  (rec-facts-raw k (+ 1 k) envs outs))

; One cycle: from the joined invariant, the payload invariant and the
; environment at cycle k to the new facts about cycle k.
(defthm rec-step-glue
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at k envs (fsm-eval envs initst (probe-fsm))))
           (rec-facts-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance rec-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-write-payload-run-constraints))
           :in-theory (e/d (join-j-at join-env-at join-inv-raw join-resetalt-raw
                            join-env-raw joint-2valued-p
                            pay-j-at rec-facts-at pay-definite-raw pay-inv-raw
                            rec-facts-raw rec-step-all rec-step-concl
                            fgl::fgl-prove-fn pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7 pay-next-definite-k-rd0 pay-next-definite-k-rd1 pay-next-definite-k-rd2 pay-next-definite-k-rd3 pay-next-definite-k-rd4 pay-next-definite-k-rd5 pay-next-definite-k-rd6 pay-next-definite-k-rd7 pay-next-definite-k-offer pay-next-definite-q-memp0 pay-next-definite-q-memp1 pay-next-definite-q-memp2 pay-next-definite-q-memp3 pay-next-definite-q-memp4 pay-next-definite-q-memp5 pay-next-definite-q-memp6 pay-next-definite-q-memp7 pay-next-definite-q-memd0 pay-next-definite-q-memd1 pay-next-definite-q-memd2 pay-next-definite-q-memd3 pay-next-definite-q-memd4 pay-next-definite-q-memd5 pay-next-definite-q-memd6 pay-next-definite-q-memd7 pay-next-definite-q-mdd pay-next-definite-q-mdp pay-next-definite-a-saddr pay-next-definite-a-sdata pay-next-definite-a-oaddr pay-next-definite-a-odata pay-next-inv)
                           (rec-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

; Two signals the payload book did not need by name: clear_i in a cycle, and
; the next value of pending_persisted_q.
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (names '(i-clear n-k-pending-persisted-q)))
   (cons 'progn
         (append
          (pay-accessor-events names formals bindings vars)
          (list `(in-theory (disable ,@(pay-accessor-names names))))))))

; ---------------------------------------------------------------------------
; A RECORD.  The controller holds a staged record as a layer, a position, two
; exponent registers (one for the K row, one for the V row) and the pair
; store.  Word w of row h of it (h = 0 the K row, h = 1 the V row; w = 8 the
; metadata word) is an address and a data word, by the payload book's
; pay-addr and pay-data.  The record is its eighteen words in the order they
; are written: the K row's nine, then the V row's nine.
; ---------------------------------------------------------------------------
(define rec-word (h w l p ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (list (pay-addr l p h w)
        (pay-data w h ke ve b0 b1 b2 b3 b4 b5 b6 b7)))
(define rec-words (l p ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (list (rec-word 0 0 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 1 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 2 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 3 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 4 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 5 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 6 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 7 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 0 8 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 0 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 1 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 2 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 3 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 4 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 5 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 6 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 7 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)
        (rec-word 1 8 l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)))

; The same of the record as the controller holds it in cycle k.
(define rec-word-at (h w k outs) :verify-guards nil
  (rec-word h w (pay$r-k-pending-layer-q k k nil outs) (pay$r-k-pending-position-q k k nil outs) (pay$r-k-pending-key-exponents-q k k nil outs) (pay$r-k-pending-value-exponents-q k k nil outs) (pay$r-k-bank0 k k nil outs) (pay$r-k-bank1 k k nil outs) (pay$r-k-bank2 k k nil outs) (pay$r-k-bank3 k k nil outs) (pay$r-k-bank4 k k nil outs) (pay$r-k-bank5 k k nil outs) (pay$r-k-bank6 k k nil outs) (pay$r-k-bank7 k k nil outs)))
(define rec-words-at (k outs) :verify-guards nil
  (rec-words (pay$r-k-pending-layer-q k k nil outs) (pay$r-k-pending-position-q k k nil outs) (pay$r-k-pending-key-exponents-q k k nil outs) (pay$r-k-pending-value-exponents-q k k nil outs) (pay$r-k-bank0 k k nil outs) (pay$r-k-bank1 k k nil outs) (pay$r-k-bank2 k k nil outs) (pay$r-k-bank3 k k nil outs) (pay$r-k-bank4 k k nil outs) (pay$r-k-bank5 k k nil outs) (pay$r-k-bank6 k k nil outs) (pay$r-k-bank7 k k nil outs)))
; clear_i in cycle k
(define rec-clear-at (k envs) :verify-guards nil
  (pay$i-clear k k envs nil))
; pending_persisted_q in cycle k
(define rec-per-at (k outs) :verify-guards nil
  (pay$r-k-pending-persisted-q k k nil outs))
; 1 when a staging beat is accepted in cycle k, and the coordinate it is for
(define rec-beat-at (k envs outs) :verify-guards nil
  (if (and (equal (pay$h-spayload k k envs outs) 1)
           (equal (pay$o-spr k k envs outs) 1)
           (equal (pay$o-spl k k envs outs) 1))
      1 0))
(define rec-coord-at (k outs) :verify-guards nil
  (pay$r-k-expected-coordinate-q k k nil outs))
; The record's start: the first prefetch state with the K row selected and
; the word counter at 0.
(define rec-start-p (k outs) :verify-guards nil
  (and (equal (pay-st-at k outs) 9)
       (equal (pay-h-at k outs) 0)
       (equal (pay-w-at k outs) 0)))
; The controller is writing a record and CLEAR has not interrupted it.
(define rec-live-p (k outs) :verify-guards nil
  (and (pay-writing-p (pay-st-at k outs))
       (equal (pay-ab-at k outs) 0)))
; How many of the record's eighteen words the endpoint has accepted: nine for
; the K row once the V row is selected, the word counter, and one more when
; the word waited on has been accepted.
(define rec-progress-at (k outs) :verify-guards nil
  (+ (* 9 (pay-h-at k outs)) (pay-w-at k outs) (pay-acc-at k outs)))
; The completion edge: pending_persisted_q is 0 in cycle k and 1 in cycle k+1.
(define rec-complete-at (k outs) :verify-guards nil
  (and (equal (rec-per-at k outs) 0)
       (equal (rec-per-at (+ 1 k) outs) 1)))
; Everything known about cycle i: what the payload book knows, and the two
; new facts.
(define rec-known-at (i envs outs) :verify-guards nil
  (and (pay-known-at i envs outs)
       (rec-facts-at i envs outs)))

; ---------------------------------------------------------------------------
; ONE CYCLE OF A RECORD, first about plain values.  If the next state is a
; write state, not interrupted and not the record's start, then this state
; is one too, there is no CLEAR in the cycle, the record's eighteen words do
; not change, progress goes up exactly by the endpoint's acceptance, and an
; accepted write is the word that progress points at.  This covers the step
; from the K row to the V row: there the progress is nine before and after.
; ---------------------------------------------------------------------------
(defthm rec-accepted-when-not-waiting
  (implies (not (equal st 3))
           (equal (pay-accepted st wb rb uni offq) 0))
  :hints (("Goal" :in-theory (enable pay-accepted))))
(defthm rec-step-of-values
  (implies (and (pay-fact-progress h-epready n-a-offer n-a-unissued n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
                (pay-fact-stage-only-while-staging h-spayload o-spl o-spr r-k-state-q)
                (pay-fact-accepted-once h-epready n-a-offer n-a-unissued n-k-state-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-q-rb r-q-wb)
                (pay-endpoint-accept-p h-epready o-epaddr o-epdata o-epv o-epw r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
                (pay-fact-row-finished h-epready n-k-state-q n-k-write-head-q n-k-write-word-q o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
                (pay-fact-bank0-staged h-key h-spayload h-value n-k-bank0 o-spl o-spr r-k-bank0 r-k-expected-coordinate-q)
                (pay-fact-bank1-staged h-key h-spayload h-value n-k-bank1 o-spl o-spr r-k-bank1 r-k-expected-coordinate-q)
                (pay-fact-bank2-staged h-key h-spayload h-value n-k-bank2 o-spl o-spr r-k-bank2 r-k-expected-coordinate-q)
                (pay-fact-bank3-staged h-key h-spayload h-value n-k-bank3 o-spl o-spr r-k-bank3 r-k-expected-coordinate-q)
                (pay-fact-bank4-staged h-key h-spayload h-value n-k-bank4 o-spl o-spr r-k-bank4 r-k-expected-coordinate-q)
                (pay-fact-bank5-staged h-key h-spayload h-value n-k-bank5 o-spl o-spr r-k-bank5 r-k-expected-coordinate-q)
                (pay-fact-bank6-staged h-key h-spayload h-value n-k-bank6 o-spl o-spr r-k-bank6 r-k-expected-coordinate-q)
                (pay-fact-bank7-staged h-key h-spayload h-value n-k-bank7 o-spl o-spr r-k-bank7 r-k-expected-coordinate-q)
                (rec-fact-entry i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
                (unsigned-byte-p 4 r-k-state-q)
                (unsigned-byte-p 4 r-k-write-word-q)
                (unsigned-byte-p 1 r-k-write-head-q)
                (unsigned-byte-p 1 r-k-write-aborted-q)
                (unsigned-byte-p 3 r-k-pending-layer-q)
                (unsigned-byte-p 12 r-k-pending-position-q)
                (unsigned-byte-p 16 r-k-pending-key-exponents-q)
                (unsigned-byte-p 16 r-k-pending-value-exponents-q)
                (unsigned-byte-p 4 r-q-wb)
                (unsigned-byte-p 4 r-q-rb)
                (unsigned-byte-p 4 r-a-unissued)
                (unsigned-byte-p 1 r-a-offer)
                (unsigned-byte-p 1024 r-k-bank0)
                (unsigned-byte-p 1024 r-k-bank1)
                (unsigned-byte-p 1024 r-k-bank2)
                (unsigned-byte-p 1024 r-k-bank3)
                (unsigned-byte-p 1024 r-k-bank4)
                (unsigned-byte-p 1024 r-k-bank5)
                (unsigned-byte-p 1024 r-k-bank6)
                (unsigned-byte-p 1024 r-k-bank7)
                (unsigned-byte-p 4 n-k-state-q)
                (unsigned-byte-p 4 n-k-write-word-q)
                (unsigned-byte-p 1 n-k-write-head-q)
                (unsigned-byte-p 1 n-k-write-aborted-q)
                (unsigned-byte-p 3 n-k-pending-layer-q)
                (unsigned-byte-p 12 n-k-pending-position-q)
                (unsigned-byte-p 16 n-k-pending-key-exponents-q)
                (unsigned-byte-p 16 n-k-pending-value-exponents-q)
                (unsigned-byte-p 4 n-q-wb)
                (unsigned-byte-p 4 n-q-rb)
                (unsigned-byte-p 4 n-a-unissued)
                (unsigned-byte-p 1 n-a-offer)
                (unsigned-byte-p 1024 n-k-bank0)
                (unsigned-byte-p 1024 n-k-bank1)
                (unsigned-byte-p 1024 n-k-bank2)
                (unsigned-byte-p 1024 n-k-bank3)
                (unsigned-byte-p 1024 n-k-bank4)
                (unsigned-byte-p 1024 n-k-bank5)
                (unsigned-byte-p 1024 n-k-bank6)
                (unsigned-byte-p 1024 n-k-bank7)
                (integerp o-epaddr)
                (integerp o-epdata)
                (pay-writing-p n-k-state-q)
                (equal n-k-write-aborted-q 0)
                (not (and (equal n-k-state-q 9) (equal n-k-write-head-q 0)
                          (equal n-k-write-word-q 0))))
           (and (pay-writing-p r-k-state-q)
                (equal r-k-write-aborted-q 0)
                (equal i-clear 0)
                (equal (rec-words n-k-pending-layer-q n-k-pending-position-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7)
                       (rec-words r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7))
                (equal (+ (* 9 n-k-write-head-q) n-k-write-word-q (pay-accepted n-k-state-q n-q-wb n-q-rb n-a-unissued n-a-offer))
                       (+ (* 9 r-k-write-head-q) r-k-write-word-q (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer)
                          (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0)))
                (implies (equal (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0) 1)
                         (and (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 0)
                              (equal (list o-epaddr o-epdata)
                                     (rec-word r-k-write-head-q r-k-write-word-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7))))))
  :hints (("Goal"
           :in-theory (e/d (pay-fact-progress pay-fact-stage-only-while-staging
                            pay-fact-accepted-once pay-endpoint-accept-p pay-fact-row-finished
                            pay-fact-bank0-staged pay-fact-bank1-staged pay-fact-bank2-staged pay-fact-bank3-staged pay-fact-bank4-staged pay-fact-bank5-staged pay-fact-bank6-staged pay-fact-bank7-staged
                            rec-fact-entry fgl::fgl-prove-fn pay-data-is-of-staged
                            rec-words rec-word pay-row-done-p)
                           (unsigned-byte-p pay-writing-p pay-accepted pay-addr
                            pay-data pay-data-s pay-staged pay-staged-put))))
  :rule-classes nil)

; The same about cycle k of an execution.
(defthm rec-step
  (implies (and (natp k)
                (rec-known-at k envs outs)
                (rec-live-p (+ 1 k) outs)
                (not (rec-start-p (+ 1 k) outs)))
           (and (rec-live-p k outs)
                (equal (rec-clear-at k envs) 0)
                (equal (rec-words-at (+ 1 k) outs) (rec-words-at k outs))
                (equal (rec-progress-at (+ 1 k) outs)
                       (+ (rec-progress-at k outs) (pay-ep-at k envs outs)))
                (implies (equal (pay-ep-at k envs outs) 1)
                         (and (equal (pay-acc-at k outs) 0)
                              (equal (pay-epwrite-at k envs outs)
                                     (rec-word-at (pay-h-at k outs) (pay-w-at k outs) k outs))))))
  :hints (("Goal"
           :use ((:instance rec-step-of-values
                  (h-epready (pay$h-epready k (+ 1 k) envs outs))
                  (h-key (pay$h-key k (+ 1 k) envs outs))
                  (h-spayload (pay$h-spayload k (+ 1 k) envs outs))
                  (h-value (pay$h-value k (+ 1 k) envs outs))
                  (i-clear (pay$i-clear k (+ 1 k) envs outs))
                  (n-a-offer (pay$n-a-offer k (+ 1 k) envs outs))
                  (n-a-unissued (pay$n-a-unissued k (+ 1 k) envs outs))
                  (n-k-bank0 (pay$n-k-bank0 k (+ 1 k) envs outs))
                  (n-k-bank1 (pay$n-k-bank1 k (+ 1 k) envs outs))
                  (n-k-bank2 (pay$n-k-bank2 k (+ 1 k) envs outs))
                  (n-k-bank3 (pay$n-k-bank3 k (+ 1 k) envs outs))
                  (n-k-bank4 (pay$n-k-bank4 k (+ 1 k) envs outs))
                  (n-k-bank5 (pay$n-k-bank5 k (+ 1 k) envs outs))
                  (n-k-bank6 (pay$n-k-bank6 k (+ 1 k) envs outs))
                  (n-k-bank7 (pay$n-k-bank7 k (+ 1 k) envs outs))
                  (n-k-pending-key-exponents-q (pay$n-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (n-k-pending-layer-q (pay$n-k-pending-layer-q k (+ 1 k) envs outs))
                  (n-k-pending-position-q (pay$n-k-pending-position-q k (+ 1 k) envs outs))
                  (n-k-pending-value-exponents-q (pay$n-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (n-k-state-q (pay$n-k-state-q k (+ 1 k) envs outs))
                  (n-k-write-aborted-q (pay$n-k-write-aborted-q k (+ 1 k) envs outs))
                  (n-k-write-head-q (pay$n-k-write-head-q k (+ 1 k) envs outs))
                  (n-k-write-word-q (pay$n-k-write-word-q k (+ 1 k) envs outs))
                  (n-q-rb (pay$n-q-rb k (+ 1 k) envs outs))
                  (n-q-wb (pay$n-q-wb k (+ 1 k) envs outs))
                  (o-epaddr (pay$o-epaddr k (+ 1 k) envs outs))
                  (o-epdata (pay$o-epdata k (+ 1 k) envs outs))
                  (o-epv (pay$o-epv k (+ 1 k) envs outs))
                  (o-epw (pay$o-epw k (+ 1 k) envs outs))
                  (o-spl (pay$o-spl k (+ 1 k) envs outs))
                  (o-spr (pay$o-spr k (+ 1 k) envs outs))
                  (r-a-offer (pay$r-a-offer k (+ 1 k) envs outs))
                  (r-a-unissued (pay$r-a-unissued k (+ 1 k) envs outs))
                  (r-k-bank0 (pay$r-k-bank0 k (+ 1 k) envs outs))
                  (r-k-bank1 (pay$r-k-bank1 k (+ 1 k) envs outs))
                  (r-k-bank2 (pay$r-k-bank2 k (+ 1 k) envs outs))
                  (r-k-bank3 (pay$r-k-bank3 k (+ 1 k) envs outs))
                  (r-k-bank4 (pay$r-k-bank4 k (+ 1 k) envs outs))
                  (r-k-bank5 (pay$r-k-bank5 k (+ 1 k) envs outs))
                  (r-k-bank6 (pay$r-k-bank6 k (+ 1 k) envs outs))
                  (r-k-bank7 (pay$r-k-bank7 k (+ 1 k) envs outs))
                  (r-k-expected-coordinate-q (pay$r-k-expected-coordinate-q k (+ 1 k) envs outs))
                  (r-k-pending-key-exponents-q (pay$r-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (r-k-pending-layer-q (pay$r-k-pending-layer-q k (+ 1 k) envs outs))
                  (r-k-pending-position-q (pay$r-k-pending-position-q k (+ 1 k) envs outs))
                  (r-k-pending-value-exponents-q (pay$r-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (r-k-state-q (pay$r-k-state-q k (+ 1 k) envs outs))
                  (r-k-write-aborted-q (pay$r-k-write-aborted-q k (+ 1 k) envs outs))
                  (r-k-write-head-q (pay$r-k-write-head-q k (+ 1 k) envs outs))
                  (r-k-write-word-q (pay$r-k-write-word-q k (+ 1 k) envs outs))
                  (r-q-rb (pay$r-q-rb k (+ 1 k) envs outs))
                  (r-q-wb (pay$r-q-wb k (+ 1 k) envs outs))))
           :in-theory (e/d (rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw pay-acc-at pay-acc-raw
                            pay-ep-at pay-ep-raw pay-epwrite-at pay-epwrite-raw
                            rec-word-at rec-words-at rec-clear-at rec-per-at rec-beat-at
                            rec-coord-at rec-progress-at rec-start-p rec-live-p rec-complete-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay-int-o-epaddr pay-int-o-epdata
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q)
                           (unsigned-byte-p nth nthcdr take len rec-word rec-words))))
  :rule-classes nil)

; The record is reported complete only from the wait on word 8 of the V row,
; not interrupted, in a cycle without CLEAR, after the endpoint accepted
; that word and not in a cycle in which the endpoint accepts a write.
(defthm rec-complete-of-values
  (implies (and (pay-fact-reported-complete i-clear n-k-pending-persisted-q r-a-offer r-a-unissued r-k-pending-persisted-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
                (pay-fact-accepted-once h-epready n-a-offer n-a-unissued n-k-state-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-q-rb r-q-wb)
                (unsigned-byte-p 1 r-k-pending-persisted-q)
                (unsigned-byte-p 1 n-k-pending-persisted-q)
                (unsigned-byte-p 4 n-k-state-q)
                (unsigned-byte-p 4 n-q-wb) (unsigned-byte-p 4 n-q-rb)
                (unsigned-byte-p 4 n-a-unissued) (unsigned-byte-p 1 n-a-offer)
                (equal r-k-pending-persisted-q 0)
                (equal n-k-pending-persisted-q 1))
           (and (equal r-k-state-q 3)
                (equal r-k-write-head-q 1)
                (equal r-k-write-word-q 8)
                (equal r-k-write-aborted-q 0)
                (equal i-clear 0)
                (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 1)
                (equal (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0) 0)))
  :hints (("Goal" :in-theory (e/d (pay-fact-reported-complete pay-fact-accepted-once fgl::fgl-prove-fn)
                                  (unsigned-byte-p pay-accepted))))
  :rule-classes nil)
(defthm rec-complete-step
  (implies (and (natp k)
                (rec-known-at k envs outs)
                (rec-complete-at k outs))
           (and (equal (pay-st-at k outs) 3)
                (equal (pay-h-at k outs) 1)
                (equal (pay-w-at k outs) 8)
                (equal (pay-ab-at k outs) 0)
                (equal (rec-clear-at k envs) 0)
                (equal (pay-acc-at k outs) 1)
                (equal (pay-ep-at k envs outs) 0)))
  :hints (("Goal"
           :use ((:instance rec-complete-of-values
                  (h-epready (pay$h-epready k (+ 1 k) envs outs))
                  (i-clear (pay$i-clear k (+ 1 k) envs outs))
                  (n-a-offer (pay$n-a-offer k (+ 1 k) envs outs))
                  (n-a-unissued (pay$n-a-unissued k (+ 1 k) envs outs))
                  (n-k-pending-persisted-q (pay$n-k-pending-persisted-q k (+ 1 k) envs outs))
                  (n-k-state-q (pay$n-k-state-q k (+ 1 k) envs outs))
                  (n-q-rb (pay$n-q-rb k (+ 1 k) envs outs))
                  (n-q-wb (pay$n-q-wb k (+ 1 k) envs outs))
                  (o-epv (pay$o-epv k (+ 1 k) envs outs))
                  (o-epw (pay$o-epw k (+ 1 k) envs outs))
                  (r-a-offer (pay$r-a-offer k (+ 1 k) envs outs))
                  (r-a-unissued (pay$r-a-unissued k (+ 1 k) envs outs))
                  (r-k-pending-persisted-q (pay$r-k-pending-persisted-q k (+ 1 k) envs outs))
                  (r-k-state-q (pay$r-k-state-q k (+ 1 k) envs outs))
                  (r-k-write-aborted-q (pay$r-k-write-aborted-q k (+ 1 k) envs outs))
                  (r-k-write-head-q (pay$r-k-write-head-q k (+ 1 k) envs outs))
                  (r-k-write-word-q (pay$r-k-write-word-q k (+ 1 k) envs outs))
                  (r-q-rb (pay$r-q-rb k (+ 1 k) envs outs))
                  (r-q-wb (pay$r-q-wb k (+ 1 k) envs outs))))
           :in-theory (e/d (rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw pay-acc-at pay-acc-raw
                            pay-ep-at pay-ep-raw pay-epwrite-at pay-epwrite-raw
                            rec-word-at rec-words-at rec-clear-at rec-per-at rec-beat-at
                            rec-coord-at rec-progress-at rec-start-p rec-live-p rec-complete-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay-int-o-epaddr pay-int-o-epdata
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q)
                           (unsigned-byte-p nth nthcdr take len rec-word rec-words))))
  :rule-classes nil)

; The record's start is entered only from staging, by the acceptance of the
; beat for coordinate 127, in a cycle without CLEAR.
(defthm rec-start-of-values
  (implies (and (rec-fact-start h-spayload i-clear n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-spl o-spr r-k-expected-coordinate-q r-k-state-q)
                (unsigned-byte-p 4 n-k-state-q) (unsigned-byte-p 1 n-k-write-head-q)
                (unsigned-byte-p 4 n-k-write-word-q) (unsigned-byte-p 1 n-k-write-aborted-q)
                (equal n-k-state-q 9) (equal n-k-write-head-q 0) (equal n-k-write-word-q 0))
           (and (equal r-k-state-q 1)
                (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1)
                (equal r-k-expected-coordinate-q 127)
                (equal n-k-write-aborted-q 0)
                (equal i-clear 0)))
  :hints (("Goal" :in-theory (e/d (rec-fact-start fgl::fgl-prove-fn) (unsigned-byte-p))))
  :rule-classes nil)
(defthm rec-start-step
  (implies (and (natp k)
                (rec-known-at k envs outs)
                (rec-start-p (+ 1 k) outs))
           (and (equal (pay-st-at k outs) 1)
                (equal (rec-beat-at k envs outs) 1)
                (equal (rec-coord-at k outs) 127)
                (equal (rec-clear-at k envs) 0)
                (rec-live-p (+ 1 k) outs)))
  :hints (("Goal"
           :use ((:instance rec-start-of-values
                  (h-spayload (pay$h-spayload k (+ 1 k) envs outs))
                  (i-clear (pay$i-clear k (+ 1 k) envs outs))
                  (n-k-state-q (pay$n-k-state-q k (+ 1 k) envs outs))
                  (n-k-write-aborted-q (pay$n-k-write-aborted-q k (+ 1 k) envs outs))
                  (n-k-write-head-q (pay$n-k-write-head-q k (+ 1 k) envs outs))
                  (n-k-write-word-q (pay$n-k-write-word-q k (+ 1 k) envs outs))
                  (o-spl (pay$o-spl k (+ 1 k) envs outs))
                  (o-spr (pay$o-spr k (+ 1 k) envs outs))
                  (r-k-expected-coordinate-q (pay$r-k-expected-coordinate-q k (+ 1 k) envs outs))
                  (r-k-state-q (pay$r-k-state-q k (+ 1 k) envs outs))))
           :in-theory (e/d (rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw pay-acc-at pay-acc-raw
                            pay-ep-at pay-ep-raw pay-epwrite-at pay-epwrite-raw
                            rec-word-at rec-words-at rec-clear-at rec-per-at rec-beat-at
                            rec-coord-at rec-progress-at rec-start-p rec-live-p rec-complete-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay-int-o-epaddr pay-int-o-epdata
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb pay$i-clear pay$n-k-pending-persisted-q)
                           (unsigned-byte-p nth nthcdr take len rec-word rec-words))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; THE RECORD AS A LIST OF WRITES.
; ---------------------------------------------------------------------------
(defthm rec-len-of-words
  (equal (len (rec-words-at k outs)) 18)
  :hints (("Goal" :in-theory (enable rec-words-at rec-words))))
(defthm rec-nth-of-words
  (implies (and (natp w) (<= w 8) (or (equal h 0) (equal h 1)))
           (equal (nth (+ (* 9 h) w) (rec-words-at k outs))
                  (rec-word-at h w k outs)))
  :hints (("Goal" :cases ((equal w 0) (equal w 1) (equal w 2) (equal w 3) (equal w 4) (equal w 5) (equal w 6) (equal w 7) (equal w 8))
           :in-theory (e/d (rec-words-at rec-words rec-word-at) (rec-word))))
  :rule-classes nil)
(defthm rec-take-18-of-words
  (equal (take 18 (rec-words-at k outs)) (rec-words-at k outs))
  :hints (("Goal" :in-theory (enable rec-words-at rec-words))))
(defthm rec-append-nil-of-words
  (equal (append (rec-words-at k outs) nil) (rec-words-at k outs))
  :hints (("Goal" :in-theory (enable rec-words-at rec-words))))
(defthm rec-bit-cases
  (implies (unsigned-byte-p 1 x) (or (equal x 0) (equal x 1)))
  :rule-classes nil)
; the row selector is a bit
(defthm rec-head-bit
  (implies (pay-known-at k envs outs)
           (or (equal (pay-h-at k outs) 0) (equal (pay-h-at k outs) 1)))
  :hints (("Goal"
           :use ((:instance rec-bit-cases (x (pay-h-at k outs))))
           :in-theory (e/d (pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-h-at pay-h-raw)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)

; The latest cycle up to n at which a record starts; nil when there is none.
(defund rec-start (n outs)
  (declare (xargs :measure (nfix n) :verify-guards nil))
  (cond ((rec-start-p (nfix n) outs) (nfix n))
        ((zp n) nil)
        (t (rec-start (- n 1) outs))))
; In every cycle from j to n the controller is writing and not interrupted,
; and there is no CLEAR in any cycle from j to n-1.
(defund rec-uninterrupted (j n envs outs)
  (declare (xargs :measure (nfix (- (nfix n) (nfix j))) :verify-guards nil))
  (and (rec-live-p (nfix n) outs)
       (or (zp (- (nfix n) (nfix j)))
           (and (equal (rec-clear-at (- (nfix n) 1) envs) 0)
                (rec-uninterrupted j (- (nfix n) 1) envs outs)))))
; The invariant of the argument, for a record that started at cycle j and is
; still being written at cycle n: it has not been interrupted, its eighteen
; words are those of cycle j, and the writes the endpoint accepted since j
; are the first `progress` of them.
(defund rec-inv (j n envs outs)
  (declare (xargs :verify-guards nil))
  (and (natp j) (<= j n)
       (rec-start-p j outs)
       (rec-uninterrupted j n envs outs)
       (equal (rec-words-at n outs) (rec-words-at j outs))
       (equal (pay-log j n envs outs)
              (take (rec-progress-at n outs) (rec-words-at j outs)))))

(defthm rec-inv-base
  (implies (and (natp j) (rec-start-p j outs) (rec-live-p j outs))
           (rec-inv j j envs outs))
  :hints (("Goal" :in-theory (enable rec-inv pay-log rec-uninterrupted rec-progress-at
                                     rec-start-p))))

(defthm rec-inv-step
  (implies (and (natp j) (natp k) (< j k)
                (rec-known-at (+ -1 k) envs outs)
                (rec-live-p k outs)
                (not (rec-start-p k outs))
                (rec-inv j (+ -1 k) envs outs))
           (rec-inv j k envs outs))
  :hints (("Goal"
           :use ((:instance rec-step (k (+ -1 k)))
                 (:instance pay-word-bound (k (+ -1 k)))
                 (:instance rec-head-bit (k (+ -1 k)))
                 (:instance pay-ep-at-is-a-bit (k (+ -1 k)))
                 (:instance pay-take-snoc
                  (m (rec-progress-at (+ -1 k) outs)) (x (rec-words-at j outs)))
                 (:instance rec-nth-of-words
                  (h (pay-h-at (+ -1 k) outs)) (w (pay-w-at (+ -1 k) outs)) (k (+ -1 k))))
           :expand ((pay-log j k envs outs)
                    (rec-uninterrupted j k envs outs))
           :in-theory (e/d (rec-inv rec-known-at rec-live-p rec-progress-at)
                           (pay-take-snoc pay-known-at rec-facts-at
                            rec-words-at rec-word-at take nth rec-start-p))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; From the reset and the environment to the invariant at every cycle.
; ---------------------------------------------------------------------------
; After three reset cycles the controller is idle.
(defthm rec-idle-after-reset
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm))))
           (equal (pay-st-at (+ 2 r) (fsm-eval envs initst (probe-fsm))) 0))
  :hints (("Goal"
           :use ((:instance join-reset-fsm-thm
                  (base-cycle r) (base-cycle+2 (+ 2 r))))
           :in-theory (e/d (join-reset-at join-reset-raw joint-reset-p
                            pay-st-at pay-st-raw)
                           (join-reset-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

(defthm rec-known-at-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp i) (<= (+ 2 r) i)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) (+ 1 i) envs outs))
             (rec-known-at i envs outs)))
  :hints (("Goal"
           :use ((:instance pay-known-at-from-reset)
                 (:instance join-env-from-shorter
                  (j (+ 2 r)) (n i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-inv-from-reset (n i))
                 (:instance pay-inv-from-reset (n i))
                 (:instance rec-step-glue (k i)))
           :in-theory (e/d (rec-known-at)
                           (join-inv-from-reset pay-inv-from-reset join-step-glue
                            pay-step-glue pay-ints-glue rec-step-glue join-inv-preserved
                            pay-inv-preserved join-reset-glue pay-reset-glue
                            join-j-at pay-j-at pay-facts-at pay-ints-at rec-facts-at
                            pay-known-at join-env-at join-env-from join-reset-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; One more cycle of the induction.
(defthm rec-inv-holds-step
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (< (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs)
                  (rec-live-p n outs)
                  (implies (rec-live-p (+ -1 n) outs)
                           (and (natp (rec-start (+ -1 n) outs))
                                (< (+ 2 r) (rec-start (+ -1 n) outs))
                                (rec-inv (rec-start (+ -1 n) outs) (+ -1 n) envs outs))))
             (and (natp (rec-start n outs))
                  (< (+ 2 r) (rec-start n outs))
                  (rec-inv (rec-start n outs) n envs outs))))
  :hints (("Goal"
           :use ((:instance rec-known-at-from-reset (i (+ -1 n)))
                 (:instance rec-step (k (+ -1 n))
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance rec-inv-step (k n)
                  (j (rec-start (+ -1 n) (fsm-eval envs initst (probe-fsm))))
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance rec-inv-base (j n)
                  (outs (fsm-eval envs initst (probe-fsm)))))
           :expand ((rec-start n (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (rec-inv)
                           (rec-inv-base rec-known-at rec-live-p rec-start-p
                            rec-uninterrupted pay-log rec-words-at rec-progress-at
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

(defun rec-ind (r n)
  (declare (xargs :measure (nfix n)))
  (if (or (zp n) (<= n (+ 2 (nfix r))))
      (list r n)
    (rec-ind r (- n 1))))

; THE INVARIANT AT EVERY CYCLE.  In every execution, with the reset, storage
; and environment hypotheses holding up to cycle n: if at cycle n the
; controller is writing a record, not interrupted, then a record started at
; some cycle j after the reset, j is the latest such cycle, and the
; invariant holds between j and n.
(defthm rec-inv-holds
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs)
                  (rec-live-p n outs))
             (and (natp (rec-start n outs))
                  (< (+ 2 r) (rec-start n outs))
                  (rec-inv (rec-start n outs) n envs outs))))
  :hints (("Goal"
           :induct (rec-ind r n)
           :in-theory (e/d (rec-ind)
                           (rec-inv rec-start rec-live-p rec-start-p join-env-from
                            join-reset-at pay-definite-at fsm-eval (probe-fsm) probe-fsm)))
          ("Subgoal *1/2"
           :use ((:instance rec-inv-holds-step)))
          ("Subgoal *1/1"
           :use ((:instance rec-idle-after-reset))
           :in-theory (e/d (rec-live-p)
                           (rec-inv rec-start rec-start-p join-env-from
                            join-reset-at pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; Inside an uninterrupted stretch every cycle is a write cycle, not
; interrupted, and none before the last has CLEAR.
(defthm rec-uninterrupted-at
  (implies (and (rec-uninterrupted j n envs outs)
                (natp j) (natp n) (natp m) (<= j m) (<= m n))
           (and (rec-live-p m outs)
                (implies (< m n) (equal (rec-clear-at m envs) 0))))
  :hints (("Goal"
           :induct (rec-uninterrupted j n envs outs)
           :in-theory (e/d (rec-uninterrupted) (rec-live-p rec-clear-at))))
  :rule-classes nil)

; A record's start, after the reset, is the cycle after staging accepted the
; beat for coordinate 127.
(defthm rec-start-facts
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp j) (natp n) (< (+ 2 r) j) (<= j n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs)
                  (rec-start-p j outs))
             (and (equal (pay-st-at (+ -1 j) outs) 1)
                  (equal (rec-beat-at (+ -1 j) envs outs) 1)
                  (equal (rec-coord-at (+ -1 j) outs) 127)
                  (equal (rec-clear-at (+ -1 j) envs) 0))))
  :hints (("Goal"
           :use ((:instance join-env-from-prefix
                  (j (+ 2 r)) (m j) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance rec-known-at-from-reset (i (+ -1 j)))
                 (:instance rec-start-step (k (+ -1 j)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (disable rec-known-at rec-start-p rec-beat-at rec-coord-at rec-clear-at
                               rec-live-p join-env-from join-reset-at pay-definite-at
                               fsm-eval (probe-fsm) probe-fsm)))
  :rule-classes nil)

; THE RECORD, with the hypotheses in the form the induction uses.
(defthm rec-record-written
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (rec-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) (+ 1 n) envs outs)
                  (rec-complete-at n outs))
             (and (natp j) (< (+ 2 r) j) (<= j n)
                  (rec-start-p j outs)
                  (rec-uninterrupted j n envs outs)
                  (equal (rec-clear-at n envs) 0)
                  (equal (pay-log j (+ 1 n) envs outs) (rec-words-at j outs)))))
  :hints (("Goal"
           :use ((:instance rec-known-at-from-reset (i n))
                 (:instance rec-complete-step (k n) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance rec-inv-holds)
                 (:instance join-env-from-shorter
                  (j (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm)))))
           :expand ((pay-log (rec-start n (fsm-eval envs initst (probe-fsm))) (+ 1 n) envs (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (rec-inv rec-live-p rec-progress-at)
                           (rec-known-at rec-start-p rec-uninterrupted pay-log
                            rec-words-at rec-complete-at rec-start rec-clear-at
                            join-env-from join-reset-at pay-definite-at pay-writing-p
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ===========================================================================
; THE RECORD THEOREM.
;
; The definitions it is stated with.  Every one reads RTL signals of the
; probe module board1_context2048_shared_token_probe; the controller is
; u_machine.u_six_layers.u_datapath.u_kv_cache.
; ===========================================================================
; clear_i in cycle k
(define kv-clear-at (k envs) :verify-guards nil
  (rec-clear-at k envs))
; THE COMPLETION EDGE: the controller's pending_persisted_q is 0 in cycle n
; and 1 in cycle n+1.
(define kv-record-reported-complete-at (n outs) :verify-guards nil
  (rec-complete-at n outs))
; THE RECORD'S START, as a condition on one cycle: the controller's state_q
; is its first write prefetch state (9), write_head_q is 0 (the K row) and
; write_word_q is 0; and in the cycle before, state_q is the staging state
; (1) and the staging beat for expected_coordinate_q = 127 is accepted
; (kv_stage_payload_valid, stage_payload_ready_o and stage_payload_legal).
(define kv-record-starts-at (j envs outs) :verify-guards nil
  (and (rec-start-p j outs)
       (equal (pay-st-at (+ -1 j) outs) 1)
       (equal (rec-beat-at (+ -1 j) envs outs) 1)
       (equal (rec-coord-at (+ -1 j) outs) 127)))
; The start of the record that a cycle n belongs to: the latest cycle up to
; n in which state_q = 9, write_head_q = 0 and write_word_q = 0.
(define kv-record-start (n outs) :verify-guards nil
  (rec-start n outs))
; In cycle k the controller is in a write state (state_q is 2, 3, 9, 10, 11
; or 12) and write_aborted_q is 0.
(define kv-record-being-written-at (k outs) :verify-guards nil
  (rec-live-p k outs))
; From cycle j to cycle n the record is being written in every cycle, and
; clear_i is 0 in every cycle.
(define kv-record-uninterrupted (j n envs outs) :verify-guards nil
  (and (rec-uninterrupted j n envs outs)
       (equal (rec-clear-at n envs) 0)))
; THE SNAPSHOT: the eighteen words, each (address data), of the record as the
; controller holds it in cycle j, computed from pending_layer_q,
; pending_position_q, pending_key_exponents_q, pending_value_exponents_q and
; the pair store g_pair_bank[0..7].words of that one cycle: words 0 to 7 of
; the K row, the K metadata word, words 0 to 7 of the V row, the V metadata
; word.
(define kv-record-words (j outs) :verify-guards nil
  (rec-words-at j outs))
; How many of the eighteen have been accepted, read off the controller in
; cycle k: nine if write_head_q is 1, plus write_word_q, plus one if the
; word waited on has left the boundary for the endpoint.
(define kv-record-progress-at (k outs) :verify-guards nil
  (rec-progress-at k outs))

; Take any execution of the probe module's state machine, from any initial
; state, with the reset, storage and environment hypotheses of the payload
; book holding through cycle n.  Suppose pending_persisted_q rises at cycle
; n.  Let j be the latest cycle up to n at which a record starts.  Then
;   - j is after the reset and j is a record's start, entered from staging by
;     the acceptance of the beat for coordinate 127;
;   - from j to n the controller is writing, never interrupted, and there is
;     no CLEAR in any of those cycles;
;   - the writes the typed DDR boundary's endpoint (private_kv_req_*)
;     accepted in cycles j to n, in order, are exactly the eighteen words of
;     the record as the controller held it in cycle j.
; How long the endpoint makes each word wait is not constrained, and neither
; is clear_i.
(defthm kv-write-record
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs))
             (and (natp j) (< (+ 2 r) j) (<= j n)
                  (kv-record-starts-at j envs outs)
                  (kv-record-uninterrupted j n envs outs)
                  (equal (kv-endpoint-writes j (+ 1 n) envs outs)
                         (kv-record-words j outs)))))
  :hints (("Goal"
           :use ((:instance rec-record-written)
                 (:instance rec-start-facts (j (rec-start n (fsm-eval envs initst (probe-fsm)))) (n (+ 1 n)))
                 (:instance kvj-reset-connects (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (kv-record-reported-complete-at kv-record-start kv-record-starts-at
                            kv-record-uninterrupted kv-record-words kv-endpoint-writes
                            kv-payload-storage-definite-at)
                           (kvj-reset-connects kvj-environment-from-connects
                            rec-start rec-start-p rec-uninterrupted rec-complete-at rec-words-at
                            rec-clear-at rec-beat-at rec-coord-at pay-log
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; WHILE A RECORD IS BEING WRITTEN, completed or not.  If in cycle n the
; controller is writing and not interrupted, then a record started at the
; latest start j, the record it holds in cycle n is the one it held in cycle
; j, and the writes the endpoint accepted in cycles j to n-1 are exactly the
; first kv-record-progress-at of that record's eighteen words.  So when
; CLEAR arrives the accepted writes of the record are a prefix of it, of the
; length the controller's own registers give.
(defthm kv-write-record-prefix
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) n envs outs)
                  (kv-record-being-written-at n outs))
             (and (natp j) (< (+ 2 r) j) (<= j n)
                  (kv-record-starts-at j envs outs)
                  (equal (kv-record-words n outs) (kv-record-words j outs))
                  (equal (kv-endpoint-writes j n envs outs)
                         (take (kv-record-progress-at n outs)
                               (kv-record-words j outs))))))
  :hints (("Goal"
           :use ((:instance rec-inv-holds)
                 (:instance rec-start-facts (j (rec-start n (fsm-eval envs initst (probe-fsm)))))
                 (:instance kvj-reset-connects (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (kv-record-being-written-at kv-record-start kv-record-starts-at
                            kv-record-words kv-record-progress-at kv-endpoint-writes
                            kv-payload-storage-definite-at rec-inv)
                           (kvj-reset-connects kvj-environment-from-connects
                            rec-start rec-start-p rec-uninterrupted rec-live-p rec-words-at
                            rec-progress-at rec-clear-at rec-beat-at rec-coord-at pay-log
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; AN INTERRUPTED RECORD IS NOT THE ONE REPORTED COMPLETE.  Suppose
; pending_persisted_q rises at cycle n, and m is a cycle up to n in which
; clear_i is 1, or in which the controller is not writing or its write is
; marked interrupted (write_aborted_q).  Then m is before the start of the
; record completed at n.  So a record that CLEAR touched is never the one
; credited with a completion, and a write the endpoint accepts for a
; cancelled record, which it can only accept while write_aborted_q is 1,
; is not in the list of any completed record.
(defthm kv-write-record-not-credited-when-interrupted
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n) (natp m) (<= m n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs)
                  (or (equal (kv-clear-at m envs) 1)
                      (not (kv-record-being-written-at m outs))))
             (< m j)))
  :hints (("Goal"
           :use ((:instance rec-record-written)
                 (:instance rec-uninterrupted-at
                  (j (rec-start n (fsm-eval envs initst (probe-fsm)))) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-reset-connects (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (kv-record-reported-complete-at kv-record-start kv-clear-at
                            kv-record-being-written-at kv-payload-storage-definite-at)
                           (kvj-reset-connects kvj-environment-from-connects
                            rec-start rec-start-p rec-uninterrupted rec-live-p rec-complete-at
                            rec-words-at rec-clear-at pay-log
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ===========================================================================
; A REACHABLE STALLED COMPLETION.  One cycle after another of the step run
; from the reset state, three reset cycles first, as in the payload book,
; with the endpoint refusing writes for long stretches.  This is a run of
; the slice with the forward pass and the endpoint scripted; it shows that
; the theorem's hypothesis, pending_persisted_q rising, is met under
; backpressure, and it evaluates the theorem's conclusion on that run.
; ===========================================================================

; THE SCRIPT.  The client stages the record of the payload book's run: layer
; 2, position 0, exponent bytes 5 and 250;
; coordinate c has key #x100 + 3c and value #x4000 + 5c; a beat on three
; cycles in four.  The endpoint is slow: it is not ready on three cycles in
; five, and while the controller is on word 0, 3 or 8 of either row it is
; also not ready on 48 cycles in every 64.  Word 8 of the K row and word 0 of
; the V row are the two sides of the step from one row to the other, and
; word 8 of the V row is the last before the record is reported complete.
(defun rec-ready (cycle st)
  (declare (xargs :mode :program))
  (if (or (< (mod cycle 5) 3)
          (and (member (pay-get 'k-write-word-q st) '(0 3 8))
               (< (mod cycle 64) 48)))
      0 1))
(defun rec-script (cycle st)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st))
       (c (pay-get 'k-expected-coordinate-q st))
       (base (list (cons 'h-epready (rec-ready cycle st))
                   (cons 'h-attn-ready 1)
                   (cons 'h-layer 2) (cons 'h-position 0)
                   (cons 'h-kexp 5) (cons 'h-vexp 250))))
    (cond ((and (equal s 0) (equal (pay-get 'k-stage-begin-consumed-q st) 0)
                (equal (pay-get 'k-lock-seen-q st) 1))
           (cons (cons 'h-sbegin 1) base))
          ((and (equal s 1) (equal (pay-get 'k-stage-payload-consumed-q st) 0)
                (not (equal (mod cycle 4) 2)))
           (list* (cons 'h-spayload 1) (cons 'h-index c)
                  (cons 'h-key (+ #x100 (* 3 c))) (cons 'h-value (+ #x4000 (* 5 c)))
                  base))
          (t base))))

; the eighteen words of the record as the registers hold it
(defun rec-held (st)
  (declare (xargs :mode :program))
  (rec-words (pay-get 'k-pending-layer-q st) (pay-get 'k-pending-position-q st)
             (pay-get 'k-pending-key-exponents-q st) (pay-get 'k-pending-value-exponents-q st)
             (pay-get 'k-bank0 st) (pay-get 'k-bank1 st) (pay-get 'k-bank2 st) (pay-get 'k-bank3 st) (pay-get 'k-bank4 st) (pay-get 'k-bank5 st) (pay-get 'k-bank6 st) (pay-get 'k-bank7 st)))

; One cycle after another from `st`; one entry per cycle:
;   (cycle state_q write_head_q write_word_q write_aborted_q
;    pending_persisted_q its-next-value accepted-write refused held-record)
; Stops when the controller reaches PENDING, on a signal that is not
; definite, on a fault, or at the limit.
(defun rec-run-loop (cycle limit st trace)
  (declare (xargs :mode :program))
  (b* (((when (<= limit cycle)) (list :limit (reverse trace)))
       (hy (rec-script cycle st))
       (out (svtv-run (payload-step-run)
                      (append (list (cons 'i-reset-n (if (< cycle 3) 0 1)) (cons 'i-clear 0))
                              (pay-state-env *pay-state-ids* st)
                              (pay-hyp-env *pay-hyp-ids* hy))
                      :quiet t))
       (nst (pay-next-state *pay-state-ids* out))
       ((unless (pay-all-natp nst)) (list :not-definite (reverse trace)))
       ((unless (and (equal (pay-get 'o-pfn out) 0) (equal (pay-get 'o-tfe out) 0)))
        (list :fault (reverse trace)))
       (offered (and (equal (pay-get 'o-epv out) 1) (equal (pay-get 'o-epw out) 1)))
       (ready (equal (pay-get 'h-epready hy) 1))
       (entry (list cycle
                    (pay-get 'k-state-q st) (pay-get 'k-write-head-q st)
                    (pay-get 'k-write-word-q st) (pay-get 'k-write-aborted-q st)
                    (pay-get 'k-pending-persisted-q st) (pay-get 'k-pending-persisted-q nst)
                    (and offered ready
                         (list (pay-get 'o-epaddr out) (pay-get 'o-epdata out)))
                    (if (and offered (not ready)) 1 0)
                    (rec-held st)))
       (trace (cons entry trace))
       ((when (equal (pay-get 'k-state-q nst) 4)) (list :complete (reverse trace))))
    (rec-run-loop (+ 1 cycle) limit nst trace)))

; Reading a trace.  The completion edge: the cycle whose pending_persisted_q
; is 0 with next value 1.
(defun rec-t-edge (trace)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((and (equal (nth 5 (car trace)) 0) (equal (nth 6 (car trace)) 1))
         (nth 0 (car trace)))
        (t (rec-t-edge (cdr trace)))))
; The latest cycle up to n with state_q = 9, write_head_q = h, write_word_q = 0.
(defun rec-t-start (trace n h best)
  (declare (xargs :mode :program))
  (cond ((atom trace) best)
        ((< n (nth 0 (car trace))) best)
        ((and (equal (nth 1 (car trace)) 9) (equal (nth 2 (car trace)) h)
              (equal (nth 3 (car trace)) 0))
         (rec-t-start (cdr trace) n h (nth 0 (car trace))))
        (t (rec-t-start (cdr trace) n h best))))
; The writes the endpoint accepted in cycles j to n, in order.
(defun rec-t-writes (trace j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((< (nth 0 (car trace)) j) (rec-t-writes (cdr trace) j n))
        ((< n (nth 0 (car trace))) nil)
        ((nth 7 (car trace)) (cons (nth 7 (car trace)) (rec-t-writes (cdr trace) j n)))
        (t (rec-t-writes (cdr trace) j n))))
; In how many cycles from j to n a write was offered and refused, and the
; longest run of such cycles.
(defun rec-t-refused (trace j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) 0)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-refused (cdr trace) j n))
        (t (+ (nth 8 (car trace)) (rec-t-refused (cdr trace) j n)))))
(defun rec-t-longest (trace j n run best)
  (declare (xargs :mode :program))
  (cond ((atom trace) (max run best))
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-longest (cdr trace) j n 0 (max run best)))
        ((equal (nth 8 (car trace)) 1) (rec-t-longest (cdr trace) j n (+ 1 run) best))
        (t (rec-t-longest (cdr trace) j n 0 (max run best)))))
; The record held in cycle j.
(defun rec-t-held (trace j)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((equal (nth 0 (car trace)) j) (nth 9 (car trace)))
        (t (rec-t-held (cdr trace) j))))
; Every cycle from j to n is a write cycle, not interrupted, and holds `held`.
(defun rec-t-steady (trace j n held)
  (declare (xargs :mode :program))
  (cond ((atom trace) t)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-steady (cdr trace) j n held))
        (t (and (member (nth 1 (car trace)) '(2 3 9 10 11 12))
                (equal (nth 4 (car trace)) 0)
                (or (null held) (equal (nth 9 (car trace)) held))
                (rec-t-steady (cdr trace) j n held)))))
; What the theorems below are stated about:
;   (outcome cycles n j jv writes held-at-j held-at-jv refused longest steady written)
; n the completion edge, j the record's start, jv the V row's start.
(defun rec-run-summary (limit)
  (declare (xargs :mode :program))
  (b* ((run (rec-run-loop 0 limit (pay-zero-state *pay-state-ids*) nil))
       (trace (second run))
       (n (rec-t-edge trace))
       (j (and n (rec-t-start trace n 0 nil)))
       (jv (and n (rec-t-start trace n 1 nil)))
       ((unless (and n j jv)) (list (first run) (len trace) n j jv nil nil nil 0 0 nil nil)))
    (list (first run) (len trace) n j jv
          (rec-t-writes trace j n)
          (rec-t-held trace j)
          (rec-t-held trace jv)
          (rec-t-refused trace j n)
          (rec-t-longest trace j n 0 0)
          (rec-t-steady trace j n (rec-t-held trace j))
          (rec-t-steady trace j n nil))))

(defconsts *rec-run* (rec-run-summary 6000))
(defconst *rec-run-outcome* (nth 0 *rec-run*))
(defconst *rec-run-cycles* (nth 1 *rec-run*))
; the completion edge, the record's start, the V row's start
(defconst *rec-run-n* (nth 2 *rec-run*))
(defconst *rec-run-j* (nth 3 *rec-run*))
(defconst *rec-run-jv* (nth 4 *rec-run*))
; the writes the endpoint accepted in cycles j to n
(defconst *rec-run-writes* (nth 5 *rec-run*))
; the record the registers hold at j, and at jv
(defconst *rec-run-held-at-start* (nth 6 *rec-run*))
(defconst *rec-run-held-at-v-start* (nth 7 *rec-run*))
; cycles from j to n in which a write was offered and refused; longest run
(defconst *rec-run-refused* (nth 8 *rec-run*))
(defconst *rec-run-longest-stall* (nth 9 *rec-run*))
; from j to n: a write state, not interrupted, in every cycle; and the same
; held record in every cycle
(defconst *rec-run-same-record-throughout* (nth 10 *rec-run*))
(defconst *rec-run-written-throughout* (nth 11 *rec-run*))

; The record the script stages, computed outside ACL2 from the staged keys,
; values and exponents and the address formula (the payload book's list).
(defconst *rec-expected*
  '((300800 #x12d012a012701240121011e011b011801150112010f010c0109010601030100)
    (300801 #x15d015a015701540151014e014b014801450142013f013c0139013601330130)
    (300802 #x18d018a018701840181017e017b017801750172016f016c0169016601630160)
    (300803 #x1bd01ba01b701b401b101ae01ab01a801a501a2019f019c0199019601930190)
    (300804 #x1ed01ea01e701e401e101de01db01d801d501d201cf01cc01c901c601c301c0)
    (300805 #x21d021a021702140211020e020b02080205020201ff01fc01f901f601f301f0)
    (300806 #x24d024a024702440241023e023b023802350232022f022c0229022602230220)
    (300807 #x27d027a027702740271026e026b026802650262025f025c0259025602530250)
    (300808 #x505)
    (300809 #x404b40464041403c40374032402d40284023401e40194014400f400a40054000)
    (300810 #x409b40964091408c40874082407d40784073406e40694064405f405a40554050)
    (300811 #x40eb40e640e140dc40d740d240cd40c840c340be40b940b440af40aa40a540a0)
    (300812 #x413b41364131412c41274122411d41184113410e4109410440ff40fa40f540f0)
    (300813 #x418b41864181417c41774172416d41684163415e41594154414f414a41454140)
    (300814 #x41db41d641d141cc41c741c241bd41b841b341ae41a941a4419f419a41954190)
    (300815 #x422b42264221421c42174212420d4208420341fe41f941f441ef41ea41e541e0)
    (300816 #x427b42764271426c42674262425d42584253424e42494244423f423a42354230)
    (300817 #xfafa)))

; The run ends with pending_persisted_q rising at cycle n; a record started
; at j, the latest start up to n; from j to n the controller is writing and
; not interrupted.
(defthm kv-write-record-run-completes
  (and (equal *rec-run-outcome* :complete)
       (natp *rec-run-n*) (natp *rec-run-j*) (natp *rec-run-jv*)
       (< *rec-run-j* *rec-run-jv*) (< *rec-run-jv* *rec-run-n*)
       (equal *rec-run-written-throughout* t))
  :rule-classes nil)

; The endpoint stalled it: in 114 of the cycles from j to n a write
; was offered and refused, 40 of them in a row.
(defthm kv-write-record-run-was-stalled
  (and (equal *rec-run-refused* 114)
       (equal *rec-run-longest-stall* 40))
  :rule-classes nil)

; The theorem's conclusion on this run: the writes accepted from j to n are
; the eighteen words of the record the registers held at j; the registers
; held that same record in every cycle from j to n; and it is the record
; the script staged.
(defthm kv-write-record-run-is-the-record
  (and (equal (len *rec-run-writes*) 18)
       (equal *rec-run-writes* *rec-run-held-at-start*)
       (equal *rec-run-same-record-throughout* t)
       (equal *rec-run-held-at-start* *rec-expected*))
  :rule-classes nil)

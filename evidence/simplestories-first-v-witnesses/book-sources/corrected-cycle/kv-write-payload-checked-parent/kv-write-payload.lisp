; The write path's payload: the invariant and the per-cycle facts in every execution, and a completed record.
;
; Written by make_payload_book.py; do not edit.  Private.
;
; Exports
;   kv-write-payload-guarantee     the invariant and the per-cycle facts in
;                                  every execution
;   kv-write-payload-row           the writes of a finished row are its nine
;                                  words, in order
;   kv-write-payload-run-...       a scripted run that stages one record and
;                                  writes it, with stalls
(in-package "SV")
(include-book "kv-write-payload-lift")
(acl2::set-slow-alist-action nil)
(value-triple (acl2::tshell-ensure))

; ---------------------------------------------------------------------------
; Read the lifted lemma's signal bindings back from the world, so that the
; induction uses exactly the terms the lemma was proved for; the conjuncts
; below are those of pay-step-concl, the lemma's conclusion.  envs is any
; list of per-cycle input assignments, initst any initial state, and
; outs = (fsm-eval envs initst (probe-fsm)) the per-cycle signal values.
; ---------------------------------------------------------------------------
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (decl `(declare (xargs :verify-guards nil) (ignorable ,@formals)))
      (idecl `(declare (ignorable ,@vars))))
   `(progn
      ; the payload registers hold definite values, read at cycle base-cycle+1
      (defun pay-definite-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and (pay-next-definite-k-bank0 n-k-bank0)
               (pay-next-definite-k-bank1 n-k-bank1)
               (pay-next-definite-k-bank2 n-k-bank2)
               (pay-next-definite-k-bank3 n-k-bank3)
               (pay-next-definite-k-bank4 n-k-bank4)
               (pay-next-definite-k-bank5 n-k-bank5)
               (pay-next-definite-k-bank6 n-k-bank6)
               (pay-next-definite-k-bank7 n-k-bank7)
               (pay-next-definite-k-rd0 n-k-rd0)
               (pay-next-definite-k-rd1 n-k-rd1)
               (pay-next-definite-k-rd2 n-k-rd2)
               (pay-next-definite-k-rd3 n-k-rd3)
               (pay-next-definite-k-rd4 n-k-rd4)
               (pay-next-definite-k-rd5 n-k-rd5)
               (pay-next-definite-k-rd6 n-k-rd6)
               (pay-next-definite-k-rd7 n-k-rd7)
               (pay-next-definite-k-offer n-k-offer)
               (pay-next-definite-q-memp0 n-q-memp0)
               (pay-next-definite-q-memp1 n-q-memp1)
               (pay-next-definite-q-memp2 n-q-memp2)
               (pay-next-definite-q-memp3 n-q-memp3)
               (pay-next-definite-q-memp4 n-q-memp4)
               (pay-next-definite-q-memp5 n-q-memp5)
               (pay-next-definite-q-memp6 n-q-memp6)
               (pay-next-definite-q-memp7 n-q-memp7)
               (pay-next-definite-q-memd0 n-q-memd0)
               (pay-next-definite-q-memd1 n-q-memd1)
               (pay-next-definite-q-memd2 n-q-memd2)
               (pay-next-definite-q-memd3 n-q-memd3)
               (pay-next-definite-q-memd4 n-q-memd4)
               (pay-next-definite-q-memd5 n-q-memd5)
               (pay-next-definite-q-memd6 n-q-memd6)
               (pay-next-definite-q-memd7 n-q-memd7)
               (pay-next-definite-q-mdd n-q-mdd)
               (pay-next-definite-q-mdp n-q-mdp)
               (pay-next-definite-a-saddr n-a-saddr)
               (pay-next-definite-a-sdata n-a-sdata)
               (pay-next-definite-a-oaddr n-a-oaddr)
               (pay-next-definite-a-odata n-a-odata))))
      ; the payload invariant, read at cycle base-cycle+1
      (defun pay-inv-raw ,formals ,decl
        (let* ,bindings ,idecl
          (pay-next-inv n-a-head n-a-oaddr n-a-odata n-a-offer n-a-reserved n-a-saddr n-a-sdata n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-offer n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-persisted-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-mdd n-q-mdp n-q-mdw n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mv n-q-rb n-q-wb)))
      ; what the cycle base-cycle does: the conjuncts after those
      (defun pay-facts-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and (pay-typed-accept-p o-wreqaddr o-wreqdata o-wreqr o-wreqv r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-head-q r-k-write-word-q)
               (pay-endpoint-accept-p h-epready o-epaddr o-epdata o-epv o-epw r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
               (pay-fact-stage-only-while-staging h-spayload o-spl o-spr r-k-state-q)
               (pay-fact-bank0-staged h-key h-spayload h-value n-k-bank0 o-spl o-spr r-k-bank0 r-k-expected-coordinate-q)
               (pay-fact-bank1-staged h-key h-spayload h-value n-k-bank1 o-spl o-spr r-k-bank1 r-k-expected-coordinate-q)
               (pay-fact-bank2-staged h-key h-spayload h-value n-k-bank2 o-spl o-spr r-k-bank2 r-k-expected-coordinate-q)
               (pay-fact-bank3-staged h-key h-spayload h-value n-k-bank3 o-spl o-spr r-k-bank3 r-k-expected-coordinate-q)
               (pay-fact-bank4-staged h-key h-spayload h-value n-k-bank4 o-spl o-spr r-k-bank4 r-k-expected-coordinate-q)
               (pay-fact-bank5-staged h-key h-spayload h-value n-k-bank5 o-spl o-spr r-k-bank5 r-k-expected-coordinate-q)
               (pay-fact-bank6-staged h-key h-spayload h-value n-k-bank6 o-spl o-spr r-k-bank6 r-k-expected-coordinate-q)
               (pay-fact-bank7-staged h-key h-spayload h-value n-k-bank7 o-spl o-spr r-k-bank7 r-k-expected-coordinate-q)
               (pay-fact-progress h-epready n-a-offer n-a-unissued n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
               (pay-fact-row-finished h-epready n-k-state-q n-k-write-head-q n-k-write-word-q o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
               (pay-fact-accepted-once h-epready n-a-offer n-a-unissued n-k-state-q n-q-rb n-q-wb o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-q-rb r-q-wb)
               (pay-fact-reported-complete i-clear n-k-pending-persisted-q r-a-offer r-a-unissued r-k-pending-persisted-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
               (pay-fact-clear i-clear n-k-pending-persisted-q n-k-state-q n-k-write-aborted-q r-k-state-q)
               (pay-fact-interrupted n-k-pending-persisted-q n-k-state-q n-k-write-aborted-q r-k-pending-persisted-q r-k-state-q r-k-write-aborted-q)
               (pay-fact-write-legal o-wlegal r-k-state-q r-q-mv)
               (pay-fact-carried-address h-epready n-a-head n-a-offer n-a-saddr n-a-unissued n-k-state-q n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-rb n-q-wb o-epaddr o-epv o-epw r-a-head r-a-offer r-a-saddr r-a-unissued r-k-state-q r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-rb r-q-wb))))
      (in-theory (disable pay-definite-raw pay-inv-raw pay-facts-raw)))))

; The payload registers hold definite values at cycle k.
(define pay-definite-at (k envs outs) :verify-guards nil
  (pay-definite-raw k k envs outs))
; The payload invariant holds at cycle k (and the registers are definite).
(define pay-j-at (k envs outs) :verify-guards nil
  (and (pay-definite-raw k k envs outs)
       (pay-inv-raw k k envs outs)))
; The facts about cycle k.
(define pay-facts-at (k envs outs) :verify-guards nil
  (pay-facts-raw k (+ 1 k) envs outs))

; One cycle: from the joined invariant, the payload invariant and the
; environment at cycle k to the payload invariant at k+1 and the facts at k.
(defthm pay-step-glue
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at k envs (fsm-eval envs initst (probe-fsm))))
           (and (pay-j-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm)))
                (pay-facts-at k envs (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal"
           :use ((:instance pay-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-write-payload-run-constraints))
           :in-theory (e/d (join-j-at join-env-at join-inv-raw join-resetalt-raw
                            join-env-raw joint-2valued-p
                            pay-j-at pay-facts-at pay-definite-raw pay-inv-raw
                            pay-facts-raw pay-step-all pay-step-concl
                            fgl::fgl-prove-fn pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7 pay-next-definite-k-rd0 pay-next-definite-k-rd1 pay-next-definite-k-rd2 pay-next-definite-k-rd3 pay-next-definite-k-rd4 pay-next-definite-k-rd5 pay-next-definite-k-rd6 pay-next-definite-k-rd7 pay-next-definite-k-offer pay-next-definite-q-memp0 pay-next-definite-q-memp1 pay-next-definite-q-memp2 pay-next-definite-q-memp3 pay-next-definite-q-memp4 pay-next-definite-q-memp5 pay-next-definite-q-memp6 pay-next-definite-q-memp7 pay-next-definite-q-memd0 pay-next-definite-q-memd1 pay-next-definite-q-memd2 pay-next-definite-q-memd3 pay-next-definite-q-memd4 pay-next-definite-q-memd5 pay-next-definite-q-memd6 pay-next-definite-q-memd7 pay-next-definite-q-mdd pay-next-definite-q-mdp pay-next-definite-a-saddr pay-next-definite-a-sdata pay-next-definite-a-oaddr pay-next-definite-a-odata pay-next-inv)
                           (pay-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

; In the reset state the payload invariant asks nothing: the controller is
; idle and nothing is reported complete.
(defthm pay-inv-when-reset
  (implies (and (equal st 0) (equal per 0))
           (pay-inv-p st w h ab per l p ke ve offer rd0 rd1 rd2 rd3 rd4 rd5 rd6 rd7 b0 b1 b2 b3 b4 b5 b6 b7 wb rb mv m0 m1 m2 m3 m4 m5 m6 m7 md d0 d1 d2 d3 d4 d5 d6 d7 mdd mw0 mw1 mw2 mw3 mw4 mw5 mw6 mw7 mdw res head offq saddr sdata oaddr odata))
  :hints (("Goal" :in-theory (enable pay-inv-p))))

; After reset: three reset cycles leave the controller idle with nothing
; reported, so the payload invariant holds once the payload registers hold
; definite values.
(defthm pay-reset-glue
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (pay-definite-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm))))
           (pay-j-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance join-reset-fsm-thm
                  (base-cycle r) (base-cycle+2 (+ 2 r))))
           :in-theory (e/d (join-reset-at join-reset-raw joint-reset-p
                            pay-j-at pay-definite-at pay-inv-raw
                            pay-next-inv fgl::fgl-prove-fn)
                           (join-reset-fsm-thm pay-inv-p unsigned-byte-p nth
                            nthcdr take len fsm-eval (probe-fsm) probe-fsm)))))

(defthm pay-inv-preserved
  (implies (and (natp j) (natp n) (<= j n)
                (join-j-at j envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at j envs (fsm-eval envs initst (probe-fsm)))
                (join-env-from j n envs (fsm-eval envs initst (probe-fsm))))
           (pay-j-at n envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :induct (join-env-from j n envs
                                  (fsm-eval envs initst (probe-fsm)))
           :in-theory (e/d (join-env-from)
                           (join-j-at join-env-at pay-j-at pay-facts-at
                            unsigned-byte-p nth nthcdr take len fsm-eval
                            (probe-fsm) probe-fsm)))))

; THE INVARIANT AT EVERY CYCLE.  In every execution of the probe's state
; machine, from any initial state: if cycles r, r+1 and r+2 are reset
; cycles, the payload registers hold definite values at r+2, and the
; environment behaves at every cycle from r+2 to n-1, then the payload
; invariant holds at cycle n.
(defthm pay-inv-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs))
             (pay-j-at n envs outs)))
  :hints (("Goal"
           :use ((:instance join-reset-glue)
                 (:instance pay-reset-glue)
                 (:instance pay-inv-preserved (j (+ 2 r))))
           :in-theory (disable join-reset-glue pay-reset-glue
                               pay-inv-preserved pay-step-glue join-step-glue
                               join-j-at join-reset-at pay-j-at
                               pay-definite-at join-env-from fsm-eval
                               (probe-fsm) probe-fsm))))

; ===========================================================================
; THE THEOREM, with the joined book's hypotheses.
;
; Take any execution of the probe module's state machine, from any initial
; state.  Suppose reset_n_i is low in cycles r, r+1 and r+2 (kv-reset-held-at,
; from the joined book), the payload registers hold definite values in cycle
; r+2, and the environment behaves in every cycle from r+2 up to but not
; including n (kv-environment-ok-from, from the joined book).  Then in
; cycle n:
;   - the payload registers hold definite values and the payload invariant
;     holds;
;   - and if the environment behaves in cycle n as well, every fact of the
;     step lemma holds of cycle n: a write accepted at the controller's typed
;     port or at the boundary's endpoint is the staged word at its address,
;     the store changes only by an accepted staging beat, progress counts the
;     endpoint's acceptances, and so on (the predicates pay-fact-... of the
;     lemma book).
; CLEAR is unconstrained throughout.
; ===========================================================================
(define kv-payload-storage-definite-at (k envs outs) :verify-guards nil
  (pay-definite-at k envs outs))
(define kv-payload-invariant-at (n envs outs) :verify-guards nil
  (pay-j-at n envs outs))
(define kv-write-payload-facts-at (n envs outs) :verify-guards nil
  (pay-facts-at n envs outs))

(defthm kv-write-payload-guarantee
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) n envs outs))
             (and (kv-payload-invariant-at n envs outs)
                  (implies (kv-environment-ok-at n envs outs)
                           (kv-write-payload-facts-at n envs outs)))))
  :hints (("Goal"
           :use ((:instance pay-inv-from-reset)
                 (:instance join-inv-from-reset)
                 (:instance kvj-reset-connects
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-connects
                  (k n) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance pay-step-glue (k n)))
           :in-theory (e/d (kv-payload-storage-definite-at
                            kv-payload-invariant-at kv-write-payload-facts-at)
                           (pay-inv-from-reset join-inv-from-reset pay-step-glue
                            join-step-glue pay-inv-preserved join-inv-preserved
                            pay-reset-glue join-reset-glue kvj-reset-connects
                            kvj-environment-from-connects
                            kvj-environment-connects join-j-at join-reset-at
                            join-env-from join-env-at pay-j-at pay-facts-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; A ROW AS A LIST OF WRITES.
; ---------------------------------------------------------------------------
; Every signal the step lemma reads holds a definite value in the cycle.
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (ints '((pay-int-o-pfn o-pfn)
              (pay-int-o-tpf o-tpf)
              (pay-int-o-epf o-epf)
              (pay-int-o-wreqv o-wreqv)
              (pay-int-o-wreqr o-wreqr)
              (pay-int-o-wreqaddr o-wreqaddr)
              (pay-int-o-wreqdata o-wreqdata)
              (pay-int-o-epv o-epv)
              (pay-int-o-epw o-epw)
              (pay-int-o-epaddr o-epaddr)
              (pay-int-o-epdata o-epdata)
              (pay-int-o-spr o-spr)
              (pay-int-o-spl o-spl)
              (pay-int-o-wlegal o-wlegal)
              (pay-int-n-k-state-q n-k-state-q)
              (pay-int-n-k-pending-layer-q n-k-pending-layer-q)
              (pay-int-n-k-pending-position-q n-k-pending-position-q)
              (pay-int-n-k-pending-key-exponents-q n-k-pending-key-exponents-q)
              (pay-int-n-k-pending-value-exponents-q n-k-pending-value-exponents-q)
              (pay-int-n-k-pending-persisted-q n-k-pending-persisted-q)
              (pay-int-n-k-write-head-q n-k-write-head-q)
              (pay-int-n-k-write-word-q n-k-write-word-q)
              (pay-int-n-k-write-aborted-q n-k-write-aborted-q)
              (pay-int-n-q-wb n-q-wb)
              (pay-int-n-q-rb n-q-rb)
              (pay-int-n-q-mv n-q-mv)
              (pay-int-n-q-mdw n-q-mdw)
              (pay-int-n-q-memw0 n-q-memw0)
              (pay-int-n-q-memw1 n-q-memw1)
              (pay-int-n-q-memw2 n-q-memw2)
              (pay-int-n-q-memw3 n-q-memw3)
              (pay-int-n-q-memw4 n-q-memw4)
              (pay-int-n-q-memw5 n-q-memw5)
              (pay-int-n-q-memw6 n-q-memw6)
              (pay-int-n-q-memw7 n-q-memw7)
              (pay-int-n-a-offer n-a-offer)
              (pay-int-n-a-reserved n-a-reserved)
              (pay-int-n-a-unissued n-a-unissued)
              (pay-int-n-a-head n-a-head)
              (pay-int-n-k-bank0 n-k-bank0)
              (pay-int-n-k-bank1 n-k-bank1)
              (pay-int-n-k-bank2 n-k-bank2)
              (pay-int-n-k-bank3 n-k-bank3)
              (pay-int-n-k-bank4 n-k-bank4)
              (pay-int-n-k-bank5 n-k-bank5)
              (pay-int-n-k-bank6 n-k-bank6)
              (pay-int-n-k-bank7 n-k-bank7)
              (pay-int-n-k-rd0 n-k-rd0)
              (pay-int-n-k-rd1 n-k-rd1)
              (pay-int-n-k-rd2 n-k-rd2)
              (pay-int-n-k-rd3 n-k-rd3)
              (pay-int-n-k-rd4 n-k-rd4)
              (pay-int-n-k-rd5 n-k-rd5)
              (pay-int-n-k-rd6 n-k-rd6)
              (pay-int-n-k-rd7 n-k-rd7)
              (pay-int-n-k-offer n-k-offer)
              (pay-int-n-q-memp0 n-q-memp0)
              (pay-int-n-q-memp1 n-q-memp1)
              (pay-int-n-q-memp2 n-q-memp2)
              (pay-int-n-q-memp3 n-q-memp3)
              (pay-int-n-q-memp4 n-q-memp4)
              (pay-int-n-q-memp5 n-q-memp5)
              (pay-int-n-q-memp6 n-q-memp6)
              (pay-int-n-q-memp7 n-q-memp7)
              (pay-int-n-q-memd0 n-q-memd0)
              (pay-int-n-q-memd1 n-q-memd1)
              (pay-int-n-q-memd2 n-q-memd2)
              (pay-int-n-q-memd3 n-q-memd3)
              (pay-int-n-q-memd4 n-q-memd4)
              (pay-int-n-q-memd5 n-q-memd5)
              (pay-int-n-q-memd6 n-q-memd6)
              (pay-int-n-q-memd7 n-q-memd7)
              (pay-int-n-q-mdd n-q-mdd)
              (pay-int-n-q-mdp n-q-mdp)
              (pay-int-n-a-saddr n-a-saddr)
              (pay-int-n-a-sdata n-a-sdata)
              (pay-int-n-a-oaddr n-a-oaddr)
              (pay-int-n-a-odata n-a-odata)))
      (formals '(base-cycle base-cycle+1 envs outs)))
   `(progn
      (defun pay-ints-raw ,formals
        (declare (xargs :verify-guards nil) (ignorable ,@formals))
        (let* ,bindings (declare (ignorable ,@vars)) (and ,@ints)))
      (in-theory (disable pay-ints-raw)))))
(define pay-ints-at (k envs outs) :verify-guards nil
  (pay-ints-raw k (+ 1 k) envs outs))
(defthm pay-ints-glue
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at k envs (fsm-eval envs initst (probe-fsm))))
           (pay-ints-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance pay-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-write-payload-run-constraints))
           :in-theory (e/d (join-j-at join-env-at join-inv-raw join-resetalt-raw
                            join-env-raw joint-2valued-p
                            pay-j-at pay-ints-at pay-definite-raw pay-inv-raw
                            pay-ints-raw pay-step-all fgl::fgl-prove-fn pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7 pay-next-definite-k-rd0 pay-next-definite-k-rd1 pay-next-definite-k-rd2 pay-next-definite-k-rd3 pay-next-definite-k-rd4 pay-next-definite-k-rd5 pay-next-definite-k-rd6 pay-next-definite-k-rd7 pay-next-definite-k-offer pay-next-definite-q-memp0 pay-next-definite-q-memp1 pay-next-definite-q-memp2 pay-next-definite-q-memp3 pay-next-definite-q-memp4 pay-next-definite-q-memp5 pay-next-definite-q-memp6 pay-next-definite-q-memp7 pay-next-definite-q-memd0 pay-next-definite-q-memd1 pay-next-definite-q-memd2 pay-next-definite-q-memd3 pay-next-definite-q-memd4 pay-next-definite-q-memd5 pay-next-definite-q-memd6 pay-next-definite-q-memd7 pay-next-definite-q-mdd pay-next-definite-q-mdp pay-next-definite-a-saddr pay-next-definite-a-sdata pay-next-definite-a-oaddr pay-next-definite-a-odata pay-next-inv)
                           (pay-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

; the signals of one cycle the statement reads, from the lifted lemma's
; own bindings
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (decl `(declare (xargs :verify-guards nil) (ignorable ,@formals)))
      (idecl `(declare (ignorable ,@vars))))
   `(progn
      ; the controller's state, word counter, row and interrupted flag
      (defun pay-st-raw ,formals ,decl (let* ,bindings ,idecl r-k-state-q))
      (defun pay-w-raw ,formals ,decl (let* ,bindings ,idecl r-k-write-word-q))
      (defun pay-h-raw ,formals ,decl (let* ,bindings ,idecl r-k-write-head-q))
      (defun pay-ab-raw ,formals ,decl (let* ,bindings ,idecl r-k-write-aborted-q))
      ; 1 when the word waited on has been accepted at the endpoint
      (defun pay-acc-raw ,formals ,decl
        (let* ,bindings ,idecl
          (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer)))
      ; 1 when the endpoint accepts a write in this cycle, and that write
      (defun pay-ep-raw ,formals ,decl
        (let* ,bindings ,idecl
          (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0)))
      (defun pay-epwrite-raw ,formals ,decl
        (let* ,bindings ,idecl (list o-epaddr o-epdata)))
      ; word w of the row being written, as (address data)
      (defun pay-word-raw (w ,@formals) ,decl
        (let* ,bindings ,idecl
          (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q w)
                (pay-data w r-k-write-head-q r-k-pending-key-exponents-q
                          r-k-pending-value-exponents-q
                          r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3
                          r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7))))
      (in-theory (disable pay-st-raw pay-w-raw pay-h-raw pay-ab-raw pay-acc-raw
                          pay-ep-raw pay-epwrite-raw pay-word-raw)))))

(define pay-st-at (k outs) :verify-guards nil (pay-st-raw k k nil outs))
(define pay-w-at (k outs) :verify-guards nil (pay-w-raw k k nil outs))
(define pay-h-at (k outs) :verify-guards nil (pay-h-raw k k nil outs))
(define pay-ab-at (k outs) :verify-guards nil (pay-ab-raw k k nil outs))
(define pay-acc-at (k outs) :verify-guards nil (pay-acc-raw k k nil outs))
(define pay-ep-at (k envs outs) :verify-guards nil (pay-ep-raw k k envs outs))
(define pay-epwrite-at (k envs outs) :verify-guards nil (pay-epwrite-raw k k envs outs))
(define pay-word-at (w k outs) :verify-guards nil (pay-word-raw w k k nil outs))

; the nine words of the row being written at cycle k
(define pay-row-at (k outs) :verify-guards nil
  (list (pay-word-at 0 k outs) (pay-word-at 1 k outs) (pay-word-at 2 k outs)
        (pay-word-at 3 k outs) (pay-word-at 4 k outs) (pay-word-at 5 k outs)
        (pay-word-at 6 k outs) (pay-word-at 7 k outs) (pay-word-at 8 k outs)))


; The staged word depends on the pair store only through its staged slots.
(define pay-data-s (w h ke ve s0 s1 s2 s3 s4 s5 s6 s7) :verify-guards nil
  (if (equal w 8)
      (loghead 16 (if (equal h 1) ve ke))
    (logapp 128
            (pay-half (cond
        ((equal w 0) (logapp 32 (logtail 480 s0) (logapp 32 (logtail 480 s1) (logapp 32 (logtail 480 s2) (logapp 32 (logtail 480 s3) (logapp 32 (logtail 480 s4) (logapp 32 (logtail 480 s5) (logapp 32 (logtail 480 s6) (loghead 32 (logtail 480 s7))))))))))
        ((equal w 1) (logapp 32 (logtail 416 s0) (logapp 32 (logtail 416 s1) (logapp 32 (logtail 416 s2) (logapp 32 (logtail 416 s3) (logapp 32 (logtail 416 s4) (logapp 32 (logtail 416 s5) (logapp 32 (logtail 416 s6) (loghead 32 (logtail 416 s7))))))))))
        ((equal w 2) (logapp 32 (logtail 352 s0) (logapp 32 (logtail 352 s1) (logapp 32 (logtail 352 s2) (logapp 32 (logtail 352 s3) (logapp 32 (logtail 352 s4) (logapp 32 (logtail 352 s5) (logapp 32 (logtail 352 s6) (loghead 32 (logtail 352 s7))))))))))
        ((equal w 3) (logapp 32 (logtail 288 s0) (logapp 32 (logtail 288 s1) (logapp 32 (logtail 288 s2) (logapp 32 (logtail 288 s3) (logapp 32 (logtail 288 s4) (logapp 32 (logtail 288 s5) (logapp 32 (logtail 288 s6) (loghead 32 (logtail 288 s7))))))))))
        ((equal w 4) (logapp 32 (logtail 224 s0) (logapp 32 (logtail 224 s1) (logapp 32 (logtail 224 s2) (logapp 32 (logtail 224 s3) (logapp 32 (logtail 224 s4) (logapp 32 (logtail 224 s5) (logapp 32 (logtail 224 s6) (loghead 32 (logtail 224 s7))))))))))
        ((equal w 5) (logapp 32 (logtail 160 s0) (logapp 32 (logtail 160 s1) (logapp 32 (logtail 160 s2) (logapp 32 (logtail 160 s3) (logapp 32 (logtail 160 s4) (logapp 32 (logtail 160 s5) (logapp 32 (logtail 160 s6) (loghead 32 (logtail 160 s7))))))))))
        ((equal w 6) (logapp 32 (logtail 96 s0) (logapp 32 (logtail 96 s1) (logapp 32 (logtail 96 s2) (logapp 32 (logtail 96 s3) (logapp 32 (logtail 96 s4) (logapp 32 (logtail 96 s5) (logapp 32 (logtail 96 s6) (loghead 32 (logtail 96 s7))))))))))
        (t (logapp 32 (logtail 32 s0) (logapp 32 (logtail 32 s1) (logapp 32 (logtail 32 s2) (logapp 32 (logtail 32 s3) (logapp 32 (logtail 32 s4) (logapp 32 (logtail 32 s5) (logapp 32 (logtail 32 s6) (loghead 32 (logtail 32 s7))))))))))) h)
            (pay-half (cond
        ((equal w 0) (logapp 32 (logtail 448 s0) (logapp 32 (logtail 448 s1) (logapp 32 (logtail 448 s2) (logapp 32 (logtail 448 s3) (logapp 32 (logtail 448 s4) (logapp 32 (logtail 448 s5) (logapp 32 (logtail 448 s6) (loghead 32 (logtail 448 s7))))))))))
        ((equal w 1) (logapp 32 (logtail 384 s0) (logapp 32 (logtail 384 s1) (logapp 32 (logtail 384 s2) (logapp 32 (logtail 384 s3) (logapp 32 (logtail 384 s4) (logapp 32 (logtail 384 s5) (logapp 32 (logtail 384 s6) (loghead 32 (logtail 384 s7))))))))))
        ((equal w 2) (logapp 32 (logtail 320 s0) (logapp 32 (logtail 320 s1) (logapp 32 (logtail 320 s2) (logapp 32 (logtail 320 s3) (logapp 32 (logtail 320 s4) (logapp 32 (logtail 320 s5) (logapp 32 (logtail 320 s6) (loghead 32 (logtail 320 s7))))))))))
        ((equal w 3) (logapp 32 (logtail 256 s0) (logapp 32 (logtail 256 s1) (logapp 32 (logtail 256 s2) (logapp 32 (logtail 256 s3) (logapp 32 (logtail 256 s4) (logapp 32 (logtail 256 s5) (logapp 32 (logtail 256 s6) (loghead 32 (logtail 256 s7))))))))))
        ((equal w 4) (logapp 32 (logtail 192 s0) (logapp 32 (logtail 192 s1) (logapp 32 (logtail 192 s2) (logapp 32 (logtail 192 s3) (logapp 32 (logtail 192 s4) (logapp 32 (logtail 192 s5) (logapp 32 (logtail 192 s6) (loghead 32 (logtail 192 s7))))))))))
        ((equal w 5) (logapp 32 (logtail 128 s0) (logapp 32 (logtail 128 s1) (logapp 32 (logtail 128 s2) (logapp 32 (logtail 128 s3) (logapp 32 (logtail 128 s4) (logapp 32 (logtail 128 s5) (logapp 32 (logtail 128 s6) (loghead 32 (logtail 128 s7))))))))))
        ((equal w 6) (logapp 32 (logtail 64 s0) (logapp 32 (logtail 64 s1) (logapp 32 (logtail 64 s2) (logapp 32 (logtail 64 s3) (logapp 32 (logtail 64 s4) (logapp 32 (logtail 64 s5) (logapp 32 (logtail 64 s6) (loghead 32 (logtail 64 s7))))))))))
        (t (logapp 32 (logtail 0 s0) (logapp 32 (logtail 0 s1) (logapp 32 (logtail 0 s2) (logapp 32 (logtail 0 s3) (logapp 32 (logtail 0 s4) (logapp 32 (logtail 0 s5) (logapp 32 (logtail 0 s6) (loghead 32 (logtail 0 s7))))))))))) h))))
(fgl::def-fgl-thm pay-data-is-of-staged
  (implies (and (unsigned-byte-p 1024 b0) (unsigned-byte-p 1024 b1)
                (unsigned-byte-p 1024 b2) (unsigned-byte-p 1024 b3)
                (unsigned-byte-p 1024 b4) (unsigned-byte-p 1024 b5)
                (unsigned-byte-p 1024 b6) (unsigned-byte-p 1024 b7)
                (unsigned-byte-p 4 w) (unsigned-byte-p 1 h)
                (unsigned-byte-p 16 ke) (unsigned-byte-p 16 ve))
           (equal (pay-data w h ke ve b0 b1 b2 b3 b4 b5 b6 b7)
                  (pay-data-s w h ke ve (pay-staged b0) (pay-staged b1) (pay-staged b2) (pay-staged b3) (pay-staged b4) (pay-staged b5) (pay-staged b6) (pay-staged b7)))))
(in-theory (disable pay-data-s pay-data-is-of-staged))

; a function per signal: its value in a cycle, by the lifted lemma's binding
(defun pay-accessor-names (names)
  (declare (xargs :mode :program))
  (if (atom names) nil
    (cons (intern-in-package-of-symbol
           (concatenate 'string "PAY$" (symbol-name (car names))) (car names))
          (pay-accessor-names (cdr names)))))
(defun pay-accessor-events (names formals bindings vars)
  (declare (xargs :mode :program))
  (if (atom names) nil
    (cons `(defun ,(intern-in-package-of-symbol
                    (concatenate 'string "PAY$" (symbol-name (car names))) (car names))
             ,formals
             (declare (xargs :verify-guards nil) (ignorable ,@formals))
             (let* ,bindings (declare (ignorable ,@vars)) ,(car names)))
          (pay-accessor-events (cdr names) formals bindings vars))))

; ---------------------------------------------------------------------------
; One cycle of a row, first as a statement about plain values.
; ---------------------------------------------------------------------------
(defthm pay-u-when-definite
  (implies (unsigned-byte-p n x) (equal (pay-u x) x))
  :hints (("Goal" :in-theory (enable pay-u 4vec->upper))))
(defthm pay-is-when-integer
  (implies (integerp x) (equal (pay-is x v) (equal x v)))
  :hints (("Goal" :in-theory (enable pay-is 4vec->upper 4vec->lower))))
(defthm pay-writing-is-not-staging
  (implies (pay-writing-p st) (not (equal st 1)))
  :hints (("Goal" :in-theory (enable pay-writing-p)))
  :rule-classes :forward-chaining)

; While a row is written without interruption: progress counts the
; endpoint's acceptances, the row's nine words do not change, and an
; accepted write is the word waited on.
(defthm pay-row-step-of-values
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
                (pay-writing-p r-k-state-q)
                (pay-writing-p n-k-state-q)
                (equal n-k-write-head-q r-k-write-head-q)
                (equal r-k-write-aborted-q 0)
                (equal n-k-write-aborted-q 0))
           (and (equal (+ n-k-write-word-q (pay-accepted n-k-state-q n-q-wb n-q-rb n-a-unissued n-a-offer))
                       (+ r-k-write-word-q (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 0)
            (pay-data 0 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 0)
            (pay-data 0 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 1)
            (pay-data 1 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 1)
            (pay-data 1 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 2)
            (pay-data 2 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 2)
            (pay-data 2 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 3)
            (pay-data 3 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 3)
            (pay-data 3 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 4)
            (pay-data 4 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 4)
            (pay-data 4 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 5)
            (pay-data 5 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 5)
            (pay-data 5 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 6)
            (pay-data 6 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 6)
            (pay-data 6 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 7)
            (pay-data 7 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 7)
            (pay-data 7 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
       (equal (list (pay-addr n-k-pending-layer-q n-k-pending-position-q n-k-write-head-q 8)
            (pay-data 8 n-k-write-head-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7))
              (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q 8)
            (pay-data 8 r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))
                (implies (equal (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0) 1)
                         (and (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 0)
                              (equal (list o-epaddr o-epdata)
                                     (list (pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q r-k-write-word-q)
            (pay-data r-k-write-word-q r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7)))))))
  :hints (("Goal"
           :in-theory (e/d (pay-fact-progress pay-fact-stage-only-while-staging pay-fact-accepted-once pay-endpoint-accept-p pay-fact-bank0-staged pay-fact-bank1-staged pay-fact-bank2-staged pay-fact-bank3-staged pay-fact-bank4-staged pay-fact-bank5-staged pay-fact-bank6-staged pay-fact-bank7-staged fgl::fgl-prove-fn
                            pay-data-is-of-staged)
                           (unsigned-byte-p pay-writing-p pay-accepted pay-addr
                            pay-data pay-data-s pay-staged pay-staged-put))))
  :rule-classes nil)
; ---------------------------------------------------------------------------
; The same about cycle k of an execution.  Each value is read by a function
; built from the lifted lemma's own bindings.
; ---------------------------------------------------------------------------
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (names '(h-epready h-key h-spayload h-value n-a-offer n-a-unissued n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-rb n-q-wb o-epaddr o-epdata o-epv o-epw o-spl o-spr r-a-head r-a-oaddr r-a-odata r-a-offer r-a-reserved r-a-saddr r-a-sdata r-a-unissued r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-expected-coordinate-q r-k-offer r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-persisted-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-rd0 r-k-rd1 r-k-rd2 r-k-rd3 r-k-rd4 r-k-rd5 r-k-rd6 r-k-rd7 r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-mdd r-q-mdp r-q-mdw r-q-memd0 r-q-memd1 r-q-memd2 r-q-memd3 r-q-memd4 r-q-memd5 r-q-memd6 r-q-memd7 r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3 r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 r-q-mv r-q-rb r-q-wb)))
   (cons 'progn
         (append
          (pay-accessor-events names formals bindings vars)
          (list `(in-theory (disable ,@(pay-accessor-names names))))))))

; Everything the list-level argument needs about cycle i.
(define pay-known-at (i envs outs) :verify-guards nil
  (and (join-j-at i envs outs)
       (join-j-at (+ 1 i) envs outs)
       (pay-j-at i envs outs)
       (pay-j-at (+ 1 i) envs outs)
       (pay-facts-at i envs outs)
       (pay-ints-at i envs outs)))

(defthm pay-row-step
  (implies (and (natp k)
                (pay-known-at k envs outs)
                (pay-writing-p (pay-st-at k outs))
                (pay-writing-p (pay-st-at (+ 1 k) outs))
                (equal (pay-h-at (+ 1 k) outs) (pay-h-at k outs))
                (equal (pay-ab-at k outs) 0)
                (equal (pay-ab-at (+ 1 k) outs) 0))
           (and (equal (+ (pay-w-at (+ 1 k) outs) (pay-acc-at (+ 1 k) outs))
                       (+ (pay-w-at k outs) (pay-acc-at k outs) (pay-ep-at k envs outs)))
                (equal (pay-row-at (+ 1 k) outs) (pay-row-at k outs))
                (implies (equal (pay-ep-at k envs outs) 1)
                         (and (equal (pay-acc-at k outs) 0)
                              (equal (pay-epwrite-at k envs outs)
                                     (pay-word-at (pay-w-at k outs) k outs))))))
  :hints (("Goal"
           :use ((:instance pay-row-step-of-values
                  (h-epready (pay$h-epready k (+ 1 k) envs outs))
                  (h-key (pay$h-key k (+ 1 k) envs outs))
                  (h-spayload (pay$h-spayload k (+ 1 k) envs outs))
                  (h-value (pay$h-value k (+ 1 k) envs outs))
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
           :in-theory (e/d (pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw pay-acc-at pay-acc-raw
                            pay-ep-at pay-ep-raw pay-epwrite-at pay-epwrite-raw
                            pay-word-at pay-word-raw pay-row-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1
                            pay-next-definite-k-bank2 pay-next-definite-k-bank3
                            pay-next-definite-k-bank4 pay-next-definite-k-bank5
                            pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay-int-o-epaddr pay-int-o-epdata
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb)
                           (unsigned-byte-p nth nthcdr take len)))))

; In a write state the word counter is at most 8.
(defthm 4vec->upper-when-definite
  (implies (unsigned-byte-p n x) (equal (4vec->upper x) x))
  :hints (("Goal" :in-theory (enable 4vec->upper))))
(defthm pay-word-bound-of-values
  (implies (and (pay-inv-p st w h ab per l p ke ve offer rd0 rd1 rd2 rd3 rd4 rd5 rd6 rd7 b0 b1 b2 b3 b4 b5 b6 b7 wb rb mv m0 m1 m2 m3 m4 m5 m6 m7 md d0 d1 d2 d3 d4 d5 d6 d7 mdd mw0 mw1 mw2 mw3 mw4 mw5 mw6 mw7 mdw res head offq saddr sdata oaddr odata)
                (pay-writing-p st)
                (unsigned-byte-p 4 st) (unsigned-byte-p 4 w))
           (<= w 8))
  :hints (("Goal" :in-theory (e/d (pay-inv-p pay-writing-p) (unsigned-byte-p))))
  :rule-classes nil)
(defthm pay-word-bound
  (implies (and (natp k)
                (pay-known-at k envs outs)
                (pay-writing-p (pay-st-at k outs)))
           (and (natp (pay-w-at k outs))
                (<= (pay-w-at k outs) 8)))
  :hints (("Goal"
           :use ((:instance pay-word-bound-of-values
                  (st (pay$r-k-state-q k (+ 1 k) envs outs))
                  (w (pay$r-k-write-word-q k (+ 1 k) envs outs))
                  (h (pay$r-k-write-head-q k (+ 1 k) envs outs))
                  (ab (pay$r-k-write-aborted-q k (+ 1 k) envs outs))
                  (per (pay$r-k-pending-persisted-q k (+ 1 k) envs outs))
                  (l (pay$r-k-pending-layer-q k (+ 1 k) envs outs))
                  (p (pay$r-k-pending-position-q k (+ 1 k) envs outs))
                  (ke (pay$r-k-pending-key-exponents-q k (+ 1 k) envs outs))
                  (ve (pay$r-k-pending-value-exponents-q k (+ 1 k) envs outs))
                  (offer (pay$r-k-offer k (+ 1 k) envs outs))
                  (rd0 (pay$r-k-rd0 k (+ 1 k) envs outs))
                  (rd1 (pay$r-k-rd1 k (+ 1 k) envs outs))
                  (rd2 (pay$r-k-rd2 k (+ 1 k) envs outs))
                  (rd3 (pay$r-k-rd3 k (+ 1 k) envs outs))
                  (rd4 (pay$r-k-rd4 k (+ 1 k) envs outs))
                  (rd5 (pay$r-k-rd5 k (+ 1 k) envs outs))
                  (rd6 (pay$r-k-rd6 k (+ 1 k) envs outs))
                  (rd7 (pay$r-k-rd7 k (+ 1 k) envs outs))
                  (b0 (pay$r-k-bank0 k (+ 1 k) envs outs))
                  (b1 (pay$r-k-bank1 k (+ 1 k) envs outs))
                  (b2 (pay$r-k-bank2 k (+ 1 k) envs outs))
                  (b3 (pay$r-k-bank3 k (+ 1 k) envs outs))
                  (b4 (pay$r-k-bank4 k (+ 1 k) envs outs))
                  (b5 (pay$r-k-bank5 k (+ 1 k) envs outs))
                  (b6 (pay$r-k-bank6 k (+ 1 k) envs outs))
                  (b7 (pay$r-k-bank7 k (+ 1 k) envs outs))
                  (wb (pay$r-q-wb k (+ 1 k) envs outs))
                  (rb (pay$r-q-rb k (+ 1 k) envs outs))
                  (mv (pay$r-q-mv k (+ 1 k) envs outs))
                  (m0 (pay$r-q-memp0 k (+ 1 k) envs outs))
                  (m1 (pay$r-q-memp1 k (+ 1 k) envs outs))
                  (m2 (pay$r-q-memp2 k (+ 1 k) envs outs))
                  (m3 (pay$r-q-memp3 k (+ 1 k) envs outs))
                  (m4 (pay$r-q-memp4 k (+ 1 k) envs outs))
                  (m5 (pay$r-q-memp5 k (+ 1 k) envs outs))
                  (m6 (pay$r-q-memp6 k (+ 1 k) envs outs))
                  (m7 (pay$r-q-memp7 k (+ 1 k) envs outs))
                  (md (pay$r-q-mdp k (+ 1 k) envs outs))
                  (d0 (pay$r-q-memd0 k (+ 1 k) envs outs))
                  (d1 (pay$r-q-memd1 k (+ 1 k) envs outs))
                  (d2 (pay$r-q-memd2 k (+ 1 k) envs outs))
                  (d3 (pay$r-q-memd3 k (+ 1 k) envs outs))
                  (d4 (pay$r-q-memd4 k (+ 1 k) envs outs))
                  (d5 (pay$r-q-memd5 k (+ 1 k) envs outs))
                  (d6 (pay$r-q-memd6 k (+ 1 k) envs outs))
                  (d7 (pay$r-q-memd7 k (+ 1 k) envs outs))
                  (mdd (pay$r-q-mdd k (+ 1 k) envs outs))
                  (mw0 (pay$r-q-memw0 k (+ 1 k) envs outs))
                  (mw1 (pay$r-q-memw1 k (+ 1 k) envs outs))
                  (mw2 (pay$r-q-memw2 k (+ 1 k) envs outs))
                  (mw3 (pay$r-q-memw3 k (+ 1 k) envs outs))
                  (mw4 (pay$r-q-memw4 k (+ 1 k) envs outs))
                  (mw5 (pay$r-q-memw5 k (+ 1 k) envs outs))
                  (mw6 (pay$r-q-memw6 k (+ 1 k) envs outs))
                  (mw7 (pay$r-q-memw7 k (+ 1 k) envs outs))
                  (mdw (pay$r-q-mdw k (+ 1 k) envs outs))
                  (res (pay$r-a-reserved k (+ 1 k) envs outs))
                  (head (pay$r-a-head k (+ 1 k) envs outs))
                  (offq (pay$r-a-offer k (+ 1 k) envs outs))
                  (saddr (pay$r-a-saddr k (+ 1 k) envs outs))
                  (sdata (pay$r-a-sdata k (+ 1 k) envs outs))
                  (oaddr (pay$r-a-oaddr k (+ 1 k) envs outs))
                  (odata (pay$r-a-odata k (+ 1 k) envs outs))))
           :in-theory (e/d (pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw pay-acc-at pay-acc-raw
                            pay-ep-at pay-ep-raw pay-epwrite-at pay-epwrite-raw
                            pay-word-at pay-word-raw pay-row-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1
                            pay-next-definite-k-bank2 pay-next-definite-k-bank3
                            pay-next-definite-k-bank4 pay-next-definite-k-bank5
                            pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay-int-o-epaddr pay-int-o-epdata
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb)
                           (nth nthcdr take len))))
  :rule-classes nil)

; A row is left finished only from word 8, after the endpoint accepted it,
; and not in a cycle in which the endpoint accepts a write.
(defthm pay-row-finished-of-values
  (implies (and (pay-fact-row-finished h-epready n-k-state-q n-k-write-head-q n-k-write-word-q o-epv o-epw r-a-offer r-a-unissued r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-rb r-q-wb)
                (pay-writing-p r-k-state-q)
                (equal r-k-write-aborted-q 0)
                (unsigned-byte-p 4 n-k-state-q) (unsigned-byte-p 1 n-k-write-head-q)
                (unsigned-byte-p 4 n-k-write-word-q)
                (pay-row-done-p r-k-write-head-q n-k-state-q n-k-write-head-q n-k-write-word-q))
           (and (equal r-k-write-word-q 8)
                (equal (pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer) 1)
                (equal (if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0) 0)))
  :hints (("Goal" :in-theory (e/d (pay-fact-row-finished fgl::fgl-prove-fn)
                                  (unsigned-byte-p pay-writing-p pay-accepted pay-row-done-p))))
  :rule-classes nil)
(defthm pay-row-finished
  (implies (and (natp k)
                (pay-known-at k envs outs)
                (pay-writing-p (pay-st-at k outs))
                (equal (pay-ab-at k outs) 0)
                (pay-row-done-p (pay-h-at k outs) (pay-st-at (+ 1 k) outs)
                                (pay-h-at (+ 1 k) outs) (pay-w-at (+ 1 k) outs)))
           (and (equal (pay-w-at k outs) 8)
                (equal (pay-acc-at k outs) 1)
                (equal (pay-ep-at k envs outs) 0)))
  :hints (("Goal"
           :use ((:instance pay-row-finished-of-values
                  (h-epready (pay$h-epready k (+ 1 k) envs outs))
                  (n-k-state-q (pay$n-k-state-q k (+ 1 k) envs outs))
                  (n-k-write-head-q (pay$n-k-write-head-q k (+ 1 k) envs outs))
                  (n-k-write-word-q (pay$n-k-write-word-q k (+ 1 k) envs outs))
                  (o-epv (pay$o-epv k (+ 1 k) envs outs))
                  (o-epw (pay$o-epw k (+ 1 k) envs outs))
                  (r-a-offer (pay$r-a-offer k (+ 1 k) envs outs))
                  (r-a-unissued (pay$r-a-unissued k (+ 1 k) envs outs))
                  (r-k-state-q (pay$r-k-state-q k (+ 1 k) envs outs))
                  (r-k-write-aborted-q (pay$r-k-write-aborted-q k (+ 1 k) envs outs))
                  (r-k-write-head-q (pay$r-k-write-head-q k (+ 1 k) envs outs))
                  (r-k-write-word-q (pay$r-k-write-word-q k (+ 1 k) envs outs))
                  (r-q-rb (pay$r-q-rb k (+ 1 k) envs outs))
                  (r-q-wb (pay$r-q-wb k (+ 1 k) envs outs))))
           :in-theory (e/d (pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw pay-acc-at pay-acc-raw
                            pay-ep-at pay-ep-raw pay-epwrite-at pay-epwrite-raw
                            pay-word-at pay-word-raw pay-row-at
                            fgl::fgl-prove-fn
                            pay-next-definite-k-bank0 pay-next-definite-k-bank1
                            pay-next-definite-k-bank2 pay-next-definite-k-bank3
                            pay-next-definite-k-bank4 pay-next-definite-k-bank5
                            pay-next-definite-k-bank6 pay-next-definite-k-bank7
                            pay-int-o-epaddr pay-int-o-epdata
                            pay$h-epready pay$h-key pay$h-spayload pay$h-value pay$n-a-offer pay$n-a-unissued pay$n-k-bank0 pay$n-k-bank1 pay$n-k-bank2 pay$n-k-bank3 pay$n-k-bank4 pay$n-k-bank5 pay$n-k-bank6 pay$n-k-bank7 pay$n-k-pending-key-exponents-q pay$n-k-pending-layer-q pay$n-k-pending-position-q pay$n-k-pending-value-exponents-q pay$n-k-state-q pay$n-k-write-aborted-q pay$n-k-write-head-q pay$n-k-write-word-q pay$n-q-rb pay$n-q-wb pay$o-epaddr pay$o-epdata pay$o-epv pay$o-epw pay$o-spl pay$o-spr pay$r-a-head pay$r-a-oaddr pay$r-a-odata pay$r-a-offer pay$r-a-reserved pay$r-a-saddr pay$r-a-sdata pay$r-a-unissued pay$r-k-bank0 pay$r-k-bank1 pay$r-k-bank2 pay$r-k-bank3 pay$r-k-bank4 pay$r-k-bank5 pay$r-k-bank6 pay$r-k-bank7 pay$r-k-expected-coordinate-q pay$r-k-offer pay$r-k-pending-key-exponents-q pay$r-k-pending-layer-q pay$r-k-pending-persisted-q pay$r-k-pending-position-q pay$r-k-pending-value-exponents-q pay$r-k-rd0 pay$r-k-rd1 pay$r-k-rd2 pay$r-k-rd3 pay$r-k-rd4 pay$r-k-rd5 pay$r-k-rd6 pay$r-k-rd7 pay$r-k-state-q pay$r-k-write-aborted-q pay$r-k-write-head-q pay$r-k-write-word-q pay$r-q-mdd pay$r-q-mdp pay$r-q-mdw pay$r-q-memd0 pay$r-q-memd1 pay$r-q-memd2 pay$r-q-memd3 pay$r-q-memd4 pay$r-q-memd5 pay$r-q-memd6 pay$r-q-memd7 pay$r-q-memp0 pay$r-q-memp1 pay$r-q-memp2 pay$r-q-memp3 pay$r-q-memp4 pay$r-q-memp5 pay$r-q-memp6 pay$r-q-memp7 pay$r-q-memw0 pay$r-q-memw1 pay$r-q-memw2 pay$r-q-memw3 pay$r-q-memw4 pay$r-q-memw5 pay$r-q-memw6 pay$r-q-memw7 pay$r-q-mv pay$r-q-rb pay$r-q-wb)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; A row as a list of writes.
; ---------------------------------------------------------------------------
; The writes accepted at the endpoint in cycles j .. k-1, in order.
(defund pay-log (j k envs outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix j))) :verify-guards nil))
  (if (zp (- (nfix k) (nfix j)))
      nil
    (append (pay-log j (- (nfix k) 1) envs outs)
            (if (equal (pay-ep-at (- (nfix k) 1) envs outs) 1)
                (list (pay-epwrite-at (- (nfix k) 1) envs outs))
              nil))))
; The controller is writing row h, uninterrupted, in every cycle from j to k.
(defund pay-row-live (j k h outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix j))) :verify-guards nil))
  (and (pay-writing-p (pay-st-at k outs))
       (equal (pay-h-at k outs) h)
       (equal (pay-ab-at k outs) 0)
       (or (zp (- (nfix k) (nfix j)))
           (pay-row-live j (- (nfix k) 1) h outs))))
; Everything known about every cycle from j up to but not including k.
(defund pay-known-from (j k envs outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix j))) :verify-guards nil))
  (if (zp (- (nfix k) (nfix j)))
      t
    (and (pay-known-at (- (nfix k) 1) envs outs)
         (pay-known-from j (- (nfix k) 1) envs outs))))

(defthm pay-take-snoc
  (implies (and (natp m) (< m (len x)))
           (equal (append (take m x) (list (nth m x)))
                  (take (+ 1 m) x)))
  :hints (("Goal" :induct (nth m x) :in-theory (enable take nth))))
(defthm pay-len-of-row
  (equal (len (pay-row-at k outs)) 9)
  :hints (("Goal" :in-theory (enable pay-row-at))))
(defthm pay-nth-of-row
  (implies (and (natp w) (<= w 8))
           (equal (nth w (pay-row-at k outs)) (pay-word-at w k outs)))
  :hints (("Goal" :cases ((equal w 0) (equal w 1) (equal w 2) (equal w 3) (equal w 4)
                          (equal w 5) (equal w 6) (equal w 7) (equal w 8))
           :in-theory (e/d (pay-row-at) (pay-word-at)))))
(defthm pay-take-9-of-row
  (equal (take 9 (pay-row-at k outs)) (pay-row-at k outs))
  :hints (("Goal" :in-theory (enable pay-row-at))))
(defthm pay-ep-at-is-a-bit
  (or (equal (pay-ep-at k envs outs) 0) (equal (pay-ep-at k envs outs) 1))
  :hints (("Goal" :in-theory (enable pay-ep-at pay-ep-raw)))
  :rule-classes nil)
(defthm pay-acc-at-when-not-waiting
  (implies (not (equal (pay-st-at k outs) 3))
           (equal (pay-acc-at k outs) 0))
  :hints (("Goal" :in-theory (enable pay-acc-at pay-acc-raw pay-st-at pay-st-raw pay-accepted))))

; The invariant of the argument: at cycle k the row's nine words are those of
; cycle j, and the writes accepted since j are the first w + accepted of them.
(defund pay-row-inv (j k envs outs)
  (declare (xargs :verify-guards nil))
  (and (equal (pay-row-at k outs) (pay-row-at j outs))
       (equal (pay-log j k envs outs)
              (take (+ (pay-w-at k outs) (pay-acc-at k outs))
                    (pay-row-at j outs)))))

(defthm pay-row-inv-base
  (implies (and (natp j)
                (equal (pay-st-at j outs) 9)
                (equal (pay-w-at j outs) 0))
           (pay-row-inv j j envs outs))
  :hints (("Goal" :in-theory (enable pay-row-inv pay-log))))

(defthm pay-row-inv-step
  (implies (and (natp j) (natp k) (< j k)
                (pay-known-at (+ -1 k) envs outs)
                (pay-writing-p (pay-st-at k outs))
                (equal (pay-ab-at k outs) 0)
                (pay-row-live j (+ -1 k) (pay-h-at k outs) outs)
                (pay-row-inv j (+ -1 k) envs outs))
           (pay-row-inv j k envs outs))
  :hints (("Goal"
           :use ((:instance pay-row-step (k (+ -1 k)))
                 (:instance pay-word-bound (k (+ -1 k)))
                 (:instance pay-ep-at-is-a-bit (k (+ -1 k)))
                 (:instance pay-take-snoc
                  (m (pay-w-at (+ -1 k) outs)) (x (pay-row-at j outs)))
                 (:instance pay-nth-of-row
                  (w (pay-w-at (+ -1 k) outs)) (k (+ -1 k))))
           :expand ((pay-log j k envs outs)
                    (pay-row-live j (+ -1 k) (pay-h-at k outs) outs))
           :in-theory (e/d (pay-row-inv)
                           (pay-row-step pay-take-snoc pay-nth-of-row
                            pay-known-at pay-row-at pay-word-at take nth)))))

(defthm pay-row-inv-holds
  (implies (and (natp j) (natp k) (<= j k)
                (pay-known-from j k envs outs)
                (pay-row-live j k h outs)
                (equal (pay-st-at j outs) 9)
                (equal (pay-w-at j outs) 0))
           (pay-row-inv j k envs outs))
  :hints (("Goal"
           :induct (pay-known-from j k envs outs)
           :in-theory (e/d (pay-known-from pay-row-live)
                           (pay-row-inv pay-known-at)))))

; THE ROW.  If the controller starts writing row h at cycle j, keeps writing
; it without interruption through cycle n, and has left it finished at cycle
; n+1, then the writes the endpoint accepted in cycles j .. n are the row's
; nine words, in order: eight words of coordinates and the metadata word,
; each (address data).
(defthm pay-row-is-written
  (implies (and (natp j) (natp n) (<= j n)
                (pay-known-from j (+ 1 n) envs outs)
                (equal (pay-st-at j outs) 9)
                (equal (pay-w-at j outs) 0)
                (pay-row-live j n h outs)
                (pay-row-done-p h (pay-st-at (+ 1 n) outs)
                                (pay-h-at (+ 1 n) outs) (pay-w-at (+ 1 n) outs)))
           (equal (pay-log j (+ 1 n) envs outs) (pay-row-at j outs)))
  :rule-classes nil
  :hints (("Goal"
           :use ((:instance pay-row-inv-holds (k n))
                 (:instance pay-row-finished (k n)))
           :expand ((pay-log j (+ 1 n) envs outs)
                    (pay-known-from j (+ 1 n) envs outs)
                    (pay-row-live j n h outs))
           :in-theory (e/d (pay-row-inv)
                           (pay-row-inv-holds pay-known-at pay-row-at take nth)))))

; ---------------------------------------------------------------------------
; From the reset and the environment to "everything known" at each cycle.
; ---------------------------------------------------------------------------
(defthm join-env-from-prefix
  (implies (and (natp j) (natp m) (natp n) (<= j m) (<= m n)
                (join-env-from j n envs outs))
           (join-env-from j m envs outs))
  :hints (("Goal"
           :induct (join-env-from j n envs outs)
           :in-theory (e/d (join-env-from) (join-env-at))))
  :rule-classes nil)

(defthm pay-known-at-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp i) (<= (+ 2 r) i)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) (+ 1 i) envs outs))
             (pay-known-at i envs outs)))
  :hints (("Goal"
           :use ((:instance join-env-from-shorter
                  (j (+ 2 r)) (n i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-inv-from-reset (n i))
                 (:instance pay-inv-from-reset (n i))
                 (:instance join-step-glue (k i))
                 (:instance pay-step-glue (k i))
                 (:instance pay-ints-glue (k i)))
           :in-theory (e/d (pay-known-at)
                           (join-inv-from-reset pay-inv-from-reset join-step-glue
                            pay-step-glue pay-ints-glue join-inv-preserved
                            pay-inv-preserved join-reset-glue pay-reset-glue
                            join-j-at pay-j-at pay-facts-at pay-ints-at
                            join-env-at join-env-from join-reset-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; the two facts in the shape the induction below uses
(defthm pay-known-at-from-reset-step
  (implies (and (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (natp r) (natp k) (< (+ 2 r) k)
                (pay-definite-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) k envs (fsm-eval envs initst (probe-fsm))))
           (pay-known-at (+ -1 k) envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance pay-known-at-from-reset (i (+ -1 k))))
           :in-theory (disable pay-known-at join-env-from join-reset-at
                               pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
(defthm join-env-from-one-shorter
  (implies (and (join-env-from j n envs outs)
                (natp j) (natp n) (< j n))
           (join-env-from j (+ -1 n) envs outs))
  :hints (("Goal"
           :use ((:instance join-env-from-prefix (m (+ -1 n))))
           :in-theory (disable join-env-from))))

(defthm pay-known-from-reset
  (implies (and (natp r) (natp j) (natp k) (<= (+ 2 r) j)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (pay-definite-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) k envs (fsm-eval envs initst (probe-fsm))))
           (pay-known-from j k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :induct (pay-known-from j k envs (fsm-eval envs initst (probe-fsm)))
           :in-theory (e/d (pay-known-from)
                           (pay-known-at join-env-from join-reset-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ===========================================================================
; THE ROW THEOREM.
;
; Take any execution of the probe module's state machine, with the reset,
; storage and environment hypotheses of kv-write-payload-guarantee holding
; through cycle n.  Suppose at cycle j the controller starts writing row h of
; the staged record (it is in its first prefetch state with the word counter
; at 0), it is writing that row without interruption in every cycle from j
; to n, and at cycle n+1 it has left the row finished.  Then the writes the
; typed DDR boundary's endpoint accepted in cycles j to n, in order, each
; (address data), are exactly the row's nine words as the controller holds
; them at cycle j: eight words of coordinates at their addresses and then
; the metadata word at its address.
; ===========================================================================
; the endpoint's accepted writes in cycles j .. k-1
(define kv-endpoint-writes (j k envs outs) :verify-guards nil
  (pay-log j k envs outs))
; the nine words of the row the controller is writing at cycle k
(define kv-row-words (k outs) :verify-guards nil
  (pay-row-at k outs))
; the controller starts writing row h at cycle j
(define kv-row-write-starts-at (j h outs) :verify-guards nil
  (and (equal (pay-st-at j outs) 9)
       (equal (pay-w-at j outs) 0)
       (equal (pay-h-at j outs) h)))
; it is writing row h, not interrupted by CLEAR, in every cycle from j to n
(define kv-row-written-through (j n h outs) :verify-guards nil
  (pay-row-live j n h outs))
; at cycle n+1 it has left row h finished: on to row 1, or, after row 1,
; to PENDING with the record reported complete
(define kv-row-finished-after (n h outs) :verify-guards nil
  (pay-row-done-p h (pay-st-at (+ 1 n) outs)
                  (pay-h-at (+ 1 n) outs) (pay-w-at (+ 1 n) outs)))

(defthm kv-write-payload-row
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp j) (natp n) (<= (+ 2 r) j) (<= j n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-row-write-starts-at j h outs)
                  (kv-row-written-through j n h outs)
                  (kv-row-finished-after n h outs))
             (equal (kv-endpoint-writes j (+ 1 n) envs outs)
                    (kv-row-words j outs))))
  :hints (("Goal"
           :use ((:instance pay-row-is-written
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance pay-known-from-reset (k (+ 1 n)))
                 (:instance kvj-reset-connects
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n))
                  (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (kv-endpoint-writes kv-row-words kv-row-write-starts-at
                            kv-row-written-through kv-row-finished-after
                            kv-payload-storage-definite-at)
                           (kvj-reset-connects kvj-environment-from-connects
                            pay-known-from pay-known-at pay-row-live pay-log
                            pay-row-at pay-row-done-p join-env-from join-reset-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ===========================================================================
; A COMPLETED RECORD.  One cycle after another of payload-step-run, from the
; state the reset leaves (every register 0), reset_n_i low for three cycles.
; A script plays the client and the endpoint; each cycle's registers are the
; previous cycle's next-state values.  The app side's verdict on a request's
; descriptor is not scripted: the RTL computes it.  The expected writes were
; computed outside ACL2 from the staged values and the address formula
; (dev/gen_run.py).
; ===========================================================================

(defconst *pay-state-ids* '(p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q k-pending-issued-q k-pending-returned-q k-pending-read-pending-q k-committed-prefix-q k-pending-layer-q k-pending-position-q k-pending-key-exponents-q k-pending-value-exponents-q k-expected-coordinate-q k-pending-persisted-q k-write-head-q k-write-word-q k-write-aborted-q k-response-kind-q k-response-head-q k-response-layer-q k-response-position-q k-response-fault-q k-response-from-pending-q k-read-word-q k-read-return-word-q k-read-outstanding-q k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q k-read-epoch-q k-read-received-mask-q k-cache-valid-q k-cache-kind-q k-cache-layer-q k-cache-position-q k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q k-cache-issued-q k-cache-returned-q k-cache-read-pending-q k-cache-copy-kind-q k-lock-seen-q k-fault-q k-stage-begin-consumed-q k-stage-payload-consumed-q k-commit-consumed-q k-attention-req-consumed-q b-crel b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6 s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4 q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer a-offer-write a-poison a-offer-slot a-reserved a-unissued a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1 a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0 a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6 a-rslot7 k-bank0 k-bank1 k-bank2 k-bank3 k-bank4 k-bank5 k-bank6 k-bank7 k-rd0 k-rd1 k-rd2 k-rd3 k-rd4 k-rd5 k-rd6 k-rd7 k-offer q-memp0 q-memp1 q-memp2 q-memp3 q-memp4 q-memp5 q-memp6 q-memp7 q-memd0 q-memd1 q-memd2 q-memd3 q-memd4 q-memd5 q-memd6 q-memd7 q-mdd q-mdp a-saddr a-sdata a-oaddr a-odata))
(defconst *pay-hyp-ids* '(h-arbfail h-shellterm h-shellfail h-layerfail h-auth h-mcdc h-kupf h-layer h-position h-kexp h-vexp h-sbegin h-spayload h-index h-key h-value h-commit h-attn h-attn-kind h-attn-pos h-attn-head h-attn-ready h-epready h-eprspv h-eprsperr h-eprspdata h-rspdata h-appup h-legal))
(defun pay-sym (prefix id)
  (declare (xargs :mode :program))
  (intern-in-package-of-symbol
   (concatenate 'string prefix (symbol-name id)) 'pay-sym))
(defun pay-get (k al)
  (declare (xargs :mode :program))
  (cdr (assoc-eq k al)))
; the run's inputs for one cycle: every register overridden with its value,
; every environment signal with the script's; the app side's verdict on a
; request's descriptor (h-legal) is left to the RTL
(defun pay-state-env (ids st)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (list* (cons (pay-sym "R-" (car ids)) (pay-get (car ids) st))
           (cons (pay-sym "C-" (car ids)) -1)
           (pay-state-env (cdr ids) st))))
(defun pay-hyp-env (ids hy)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (list* (cons (car ids) (nfix (pay-get (car ids) hy)))
           (cons (pay-sym "C-" (car ids)) (if (eq (car ids) 'h-legal) 0 -1))
           (pay-hyp-env (cdr ids) hy))))
(defun pay-next-state (ids out)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (cons (cons (car ids) (pay-get (pay-sym "N-" (car ids)) out))
          (pay-next-state (cdr ids) out))))
(defun pay-all-natp (al)
  (declare (xargs :mode :program))
  (or (atom al) (and (natp (cdar al)) (pay-all-natp (cdr al)))))
(defun pay-zero-state (ids)
  (declare (xargs :mode :program))
  (if (atom ids) nil (cons (cons (car ids) 0) (pay-zero-state (cdr ids)))))

; THE SCRIPT.  The client stages one record: layer 2, position
; 0, exponent bytes 5 and 250; coordinate c has key
; #x100 + 3c and value #x4000 + 5c.  It offers a beat on three cycles in
; four.  The endpoint is ready on six cycles in seven.
(defun pay-script (cycle st)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st))
       (c (pay-get 'k-expected-coordinate-q st))
       (base (list (cons 'h-epready (if (equal (mod cycle 7) 3) 0 1))
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

; One cycle after another, from `st`.  Collects the writes accepted at the
; boundary's endpoint and at the controller's typed port, in order, and stops
; when the controller reports the record complete (PENDING), on a signal that
; is not definite, or at the limit.
(defun pay-run-loop (cycle limit st ep typed)
  (declare (xargs :mode :program))
  (b* (((when (<= limit cycle)) (list :limit cycle (reverse ep) (reverse typed) st))
       (hy (pay-script cycle st))
       (out (svtv-run (payload-step-run)
                      (append (list (cons 'i-reset-n (if (< cycle 3) 0 1)) (cons 'i-clear 0))
                              (pay-state-env *pay-state-ids* st)
                              (pay-hyp-env *pay-hyp-ids* hy))
                      :quiet t))
       (nst (pay-next-state *pay-state-ids* out))
       ((unless (pay-all-natp nst)) (list :not-definite cycle (reverse ep) (reverse typed) st))
       ((unless (and (equal (pay-get 'o-pfn out) 0) (equal (pay-get 'o-tfe out) 0)))
        (list :fault cycle (reverse ep) (reverse typed) st))
       (ep (if (and (equal (pay-get 'o-epv out) 1) (equal (pay-get 'h-epready hy) 1)
                    (equal (pay-get 'o-epw out) 1))
               (cons (list cycle (pay-get 'o-epaddr out) (pay-get 'o-epdata out)) ep)
             ep))
       (typed (if (and (equal (pay-get 'o-wreqv out) 1) (equal (pay-get 'o-wreqr out) 1))
                  (cons (list cycle (pay-get 'o-wreqaddr out) (pay-get 'o-wreqdata out)) typed)
                typed))
       ((when (equal (pay-get 'k-state-q nst) 4))
        (list :complete (+ 1 cycle) (reverse ep) (reverse typed) nst)))
    (pay-run-loop (+ 1 cycle) limit nst ep typed)))

(defun pay-strip-cycles (l)
  (declare (xargs :mode :program))
  (if (atom l) nil (cons (cdr (car l)) (pay-strip-cycles (cdr l)))))
(defun pay-cycles (l)
  (declare (xargs :mode :program))
  (if (atom l) nil (cons (car (car l)) (pay-cycles (cdr l)))))

(defconsts *pay-run* (pay-run-loop 0 4000 (pay-zero-state *pay-state-ids*) nil nil))

; The record the script stages: eighteen (address data), the K row then the
; V row, eight words of sixteen coordinates and the metadata word each.
(defconst *pay-expected*
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

(defconst *pay-run-outcome* (first *pay-run*))
(defconst *pay-run-cycles* (second *pay-run*))
(defconst *pay-run-writes* (pay-strip-cycles (third *pay-run*)))
(defconst *pay-run-write-cycles* (pay-cycles (third *pay-run*)))
(defconst *pay-run-typed-writes* (pay-strip-cycles (fourth *pay-run*)))
(defconst *pay-run-reported-complete* (pay-get 'k-pending-persisted-q (fifth *pay-run*)))
(defconst *pay-run-fault* (pay-get 'k-fault-q (fifth *pay-run*)))

; The run ends with the record reported complete and no fault.
(defthm kv-write-payload-run-completes
  (and (equal *pay-run-outcome* :complete)
       (equal *pay-run-reported-complete* 1)
       (equal *pay-run-fault* 0))
  :rule-classes nil)

; The writes the endpoint accepted are the record, in order, and so are the
; writes the controller's typed port issued.
(defthm kv-write-payload-run-is-the-record
  (and (equal *pay-run-writes* *pay-expected*)
       (equal *pay-run-typed-writes* *pay-expected*))
  :rule-classes nil)

; The endpoint was not ready on one cycle in seven, so the writes were not
; evenly spaced: the cycles on which it accepted them.
(defthm kv-write-payload-run-was-stalled
  (and (equal (len *pay-run-write-cycles*) 18)
       (not (equal (- (nth 1 *pay-run-write-cycles*) (nth 0 *pay-run-write-cycles*))
                   (- (nth 8 *pay-run-write-cycles*) (nth 7 *pay-run-write-cycles*)))))
  :rule-classes nil)

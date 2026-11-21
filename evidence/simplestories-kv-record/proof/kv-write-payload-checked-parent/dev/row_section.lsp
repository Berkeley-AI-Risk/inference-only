; ---------------------------------------------------------------------------
; A ROW AS A LIST OF WRITES.
; ---------------------------------------------------------------------------
; Every signal the step lemma reads holds a definite value in the cycle.
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (imp (third body))
      (ints (butlast (cdr (third imp)) 1))
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
                            pay-ints-raw fgl::fgl-prove-fn pay-next-definite-k-bank0 pay-next-definite-k-bank1 pay-next-definite-k-bank2 pay-next-definite-k-bank3 pay-next-definite-k-bank4 pay-next-definite-k-bank5 pay-next-definite-k-bank6 pay-next-definite-k-bank7 pay-next-definite-k-rd0 pay-next-definite-k-rd1 pay-next-definite-k-rd2 pay-next-definite-k-rd3 pay-next-definite-k-rd4 pay-next-definite-k-rd5 pay-next-definite-k-rd6 pay-next-definite-k-rd7 pay-next-definite-k-offer pay-next-definite-q-memp0 pay-next-definite-q-memp1 pay-next-definite-q-memp2 pay-next-definite-q-memp3 pay-next-definite-q-memp4 pay-next-definite-q-memp5 pay-next-definite-q-memp6 pay-next-definite-q-memp7 pay-next-definite-q-memd0 pay-next-definite-q-memd1 pay-next-definite-q-memd2 pay-next-definite-q-memd3 pay-next-definite-q-memd4 pay-next-definite-q-memd5 pay-next-definite-q-memd6 pay-next-definite-q-memd7 pay-next-definite-q-mdd pay-next-definite-q-mdp pay-next-definite-a-saddr pay-next-definite-a-sdata pay-next-definite-a-oaddr pay-next-definite-a-odata pay-next-inv)
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

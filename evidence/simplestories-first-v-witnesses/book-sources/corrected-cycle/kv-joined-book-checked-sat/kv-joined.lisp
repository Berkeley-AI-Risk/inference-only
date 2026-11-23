; What the joined K/V slice of the repaired RTL guarantees across reads, writes and CLEAR.
;
; Private.  Part of the joined K/V book; see README.md in this directory.
; Written by make_book.py from the pilot's proof (../acl2-pilot/joined);
; edit that script, not this file.
;
; Exports one theorem, kv-joined-guarantee, at the end of this file.  The
; definitions it is stated with are in the section "THE STATEMENT, IN TERMS
; OF RTL SIGNALS" just before it.  Everything earlier in the file is the
; induction that proves it from the two lemmas of kv-joined-lemmas.lisp.
(in-package "SV")
(include-book "kv-joined-lemmas")
(include-book "std/testing/must-fail" :dir :system)
(acl2::set-slow-alist-action nil)
(value-triple (acl2::tshell-ensure))

; ---------------------------------------------------------------------------
; Read the two lifted lemmas back from the world and name their parts, so
; that the induction below uses exactly the terms the lemmas were proved for.
; envs is any list of per-cycle input assignments, initst any initial state,
; and outs = (fsm-eval envs initst (probe-fsm)) the per-cycle signal values.
; ---------------------------------------------------------------------------
(defun bct-subst (new old x)
  (declare (xargs :mode :program))
  (cond ((equal x old) new)
        ((atom x) x)
        (t (cons (bct-subst new old (car x)) (bct-subst new old (cdr x))))))

(defun bct-named-p (prefix x)
  (declare (xargs :mode :program))
  (and (symbolp x)
       (let ((n (symbol-name x)))
         (and (<= (length prefix) (length n))
              (equal (subseq n 0 (length prefix)) prefix)))))

; the conjunct of the step lemma's hypothesis that holds the user's part
(defun bct-inner-and (conjs)
  (declare (xargs :mode :program))
  (cond ((atom conjs) nil)
        ((and (consp (car conjs)) (eq (caar conjs) 'and)
              (assoc-eq 'joint-inv-p (cdar conjs)))
         (car conjs))
        (t (bct-inner-and (cdr conjs)))))

; ... without the invariant, the ranges of the invariant's own signals, and
; the reset alternative: what is left is the environment
(defun bct-env-conjuncts (conjs)
  (declare (xargs :mode :program))
  (cond ((atom conjs) nil)
        ((let ((c (car conjs)))
           (or (eq (car c) 'joint-inv-p)
               (and (eq (car c) 'unsigned-byte-p) (bct-named-p "R-" (caddr c)))
               (and (eq (car c) 'or) (equal (cadr c) '(equal i-reset-n 1)))))
         (bct-env-conjuncts (cdr conjs)))
        (t (cons (car conjs) (bct-env-conjuncts (cdr conjs))))))

(defun bct-reset-alternative (conjs)
  (declare (xargs :mode :program))
  (cond ((atom conjs) nil)
        ((and (eq (caar conjs) 'or) (equal (cadar conjs) '(equal i-reset-n 1)))
         (car conjs))
        (t (bct-reset-alternative (cdr conjs)))))

(defun bct-replace (old new lst)
  (declare (xargs :mode :program))
  (cond ((atom lst) nil)
        ((equal (car lst) old) (cons new (cdr lst)))
        (t (cons (car lst) (bct-replace old new (cdr lst))))))

(defun bct-n-terms (formals bindings n)
  (declare (xargs :mode :program))
  (if (atom formals)
      nil
    (cons (list (car formals)
                (bct-subst n 'base-cycle+1
                           (cadr (assoc-eq (intern-in-package-of-symbol
                                            (concatenate 'string "N-" (symbol-name (car formals)))
                                            'joint-inv-p)
                                           bindings))))
          (bct-n-terms (cdr formals) bindings n))))

(make-event
 (b* ((ev (acl2::get-event 'join-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (imp (third body))
      (top (cdr (second imp)))
      ; the antecedent of the conclusion: o-pfn, o-tpf and o-epf low
      (pfn-hyp (second (third imp)))
      (cconj (cdr (third (third imp))))
      (inner (bct-inner-and top))
      (env-inner (bct-env-conjuncts (cdr inner)))
      (env-top (bct-replace inner (cons 'and env-inner) top))
      (reset-alt (bct-reset-alternative (cdr inner)))
      (reset-n-next (bct-subst 'base-cycle+1 'base-cycle
                               (second (assoc-eq 'i-reset-n bindings))))
      (formals '(base-cycle base-cycle+1 envs outs))
      (decl `(declare (xargs :verify-guards nil) (ignorable ,@formals)))
      (idecl `(declare (ignorable ,@vars)))
      (- (acl2::cw "~%BCT-ENVIRONMENT-PER-CYCLE (signal names are bound as in the step lemma printed in the lemma log)~%~x0~%"
                   (append env-inner (list pfn-hyp)))))
   `(progn
      ; the invariant and two-valuedness, read at cycle base-cycle+1
      (defun join-inv-raw ,formals ,decl
        (let* ,bindings ,idecl (and ,(first cconj) ,(second cconj))))
      ; the three discharged facts, read at cycle base-cycle: the
      ; clause for a write completion, the clause for a read response,
      ; and terminal_fault_event low
      (defun join-clause-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and ,(third cconj) ,(fourth cconj) ,(fifth cconj))))
      ; "reset_n_i is 1 at base-cycle, or every reset register is zero"
      (defun join-resetalt-raw ,formals ,decl
        (let* ,bindings ,idecl ,reset-alt))
      ; the environment at cycle base-cycle, with no protocol violation
      ; by the client and no malformed metadata word from the endpoint
      ; then, and reset_n_i = 1 at the next cycle
      (defun join-env-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and ,@env-top ,pfn-hyp (equal ,reset-n-next 1))))
      ; the controller's fault_q and state_q, read at cycle base-cycle+1
      (defun join-kfault-raw ,formals ,decl
        ,(second (assoc-eq 'n-k-fault-q bindings)))
      (defun join-kstate-raw ,formals ,decl
        ,(second (assoc-eq 'n-k-state-q bindings)))
      (in-theory (disable join-inv-raw join-clause-raw join-resetalt-raw
                          join-env-raw join-kfault-raw join-kstate-raw)))))

(make-event
 (b* ((ev (acl2::get-event 'join-reset-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (imp (third body))
      (formals '(base-cycle base-cycle+2 envs outs))
      (- (acl2::cw "~%BCT-RESET-HYPOTHESIS ~x0~%" (second imp))))
   `(progn
      (defun join-reset-raw ,formals
        (declare (xargs :verify-guards nil) (ignorable ,@formals))
        (let* ,bindings (declare (ignorable ,@vars)) ,(second imp)))
      (in-theory (disable join-reset-raw)))))

; Cycles r, r+1 and r+2 are reset cycles (and the FIFO memory control
; bits are two-valued at r+2): the hypothesis of the reset lemma.
(define join-reset-at (r envs outs) :verify-guards nil
  (join-reset-raw r (+ 2 r) envs outs))

; The invariant holds at cycle k.
(define join-j-at (k envs outs) :verify-guards nil
  (and (join-inv-raw k k envs outs)
       (join-resetalt-raw k (+ 1 k) envs outs)))

; The environment behaves at cycle k.
(define join-env-at (k envs outs) :verify-guards nil
  (join-env-raw k (+ 1 k) envs outs))

; ... at every cycle from j up to but not including n.
(define join-env-from (j n envs outs)
  :verify-guards nil
  :measure (nfix (- (nfix n) (nfix j)))
  (if (zp (- (nfix n) (nfix j)))
      t
    (and (join-env-at (nfix j) envs outs)
         (join-env-from (+ 1 (nfix j)) n envs outs))))

; The clause holds at cycle k.
(define join-clause-at (k envs outs) :verify-guards nil
  (join-clause-raw k (+ 1 k) envs outs))

; The controller's fault_q and state_q at cycle k.
(define join-kfault-at (k outs) :verify-guards nil
  (join-kfault-raw k k nil outs))
(define join-kstate-at (k outs) :verify-guards nil
  (join-kstate-raw k k nil outs))

(defthm join-reset-glue
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm))))
           (join-j-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance join-reset-fsm-thm
                  (base-cycle r) (base-cycle+2 (+ 2 r))))
           :in-theory (e/d (join-reset-at join-reset-raw join-j-at
                            join-inv-raw join-resetalt-raw)
                           (join-reset-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

(defthm join-step-glue
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm))))
           (and (join-j-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm)))
                (join-clause-at k envs (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal"
           :use ((:instance join-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k))))
           :in-theory (e/d (join-j-at join-env-at join-clause-at
                            join-inv-raw join-resetalt-raw join-env-raw
                            join-clause-raw joint-2valued-p)
                           (join-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

(defthm join-inv-preserved
  (implies (and (natp j) (natp n) (<= j n)
                (join-j-at j envs (fsm-eval envs initst (probe-fsm)))
                (join-env-from j n envs (fsm-eval envs initst (probe-fsm))))
           (join-j-at n envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :induct (join-env-from j n envs
                                  (fsm-eval envs initst (probe-fsm)))
           :in-theory (e/d (join-env-from)
                           (join-j-at join-env-at join-clause-at
                            unsigned-byte-p nth nthcdr take len fsm-eval
                            (probe-fsm) probe-fsm)))))

(defthm join-env-from-shorter
  (implies (and (natp j) (natp n) (<= j n)
                (join-env-from j (+ 1 n) envs outs))
           (and (join-env-from j n envs outs)
                (join-env-at n envs outs)))
  :hints (("Goal"
           :induct (join-env-from j n envs outs)
           :expand ((join-env-from j (+ 1 n) envs outs)
                    (join-env-from j n envs outs)
                    (join-env-from n (+ 1 n) envs outs)
                    (join-env-from (+ 1 n) (+ 1 n) envs outs))
           :in-theory (e/d (join-env-from) (join-env-at))))
  :rule-classes nil)

; MAIN THEOREM.  In every execution of the probe's state machine, from
; any initial state: if cycles r, r+1 and r+2 are reset cycles and the
; environment behaves at every cycle from r+2 to n-1, then the joint
; invariant holds at cycle n.
(defthm join-inv-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (join-env-from (+ 2 r) n envs outs))
             (join-j-at n envs outs)))
  :hints (("Goal"
           :use ((:instance join-reset-glue)
                 (:instance join-inv-preserved (j (+ 2 r))))
           :in-theory (disable join-reset-glue join-inv-preserved
                               join-step-glue join-j-at join-reset-at
                               join-env-from fsm-eval (probe-fsm)
                               probe-fsm))))

; COROLLARY 1.  The clause the controller-only theorem had to assume
; holds at every such cycle at which the environment also behaves.
(defthm join-clause-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (join-env-from (+ 2 r) (+ 1 n) envs outs))
             (join-clause-at n envs outs)))
  :hints (("Goal"
           :use ((:instance join-inv-from-reset)
                 (:instance join-env-from-shorter
                  (j (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-step-glue (k n)))
           :in-theory (disable join-inv-from-reset join-step-glue
                               join-inv-preserved join-j-at join-reset-at
                               join-env-from join-env-at join-clause-at
                               fsm-eval (probe-fsm) probe-fsm))))

; The invariant, as a statement about plain numbers, implies that the
; controller has no fault latched and is in one of its defined states.
(fgl::def-fgl-thm joint-inv-implies-no-fault
  :hyp (and (joint-2valued-p
             p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
             k-pending-issued-q k-pending-returned-q
             k-pending-read-pending-q k-committed-prefix-q
             k-pending-layer-q k-pending-position-q
             k-pending-key-exponents-q k-pending-value-exponents-q
             k-expected-coordinate-q k-pending-persisted-q
             k-write-head-q k-write-word-q k-write-aborted-q
             k-response-kind-q k-response-head-q k-response-layer-q
             k-response-position-q k-response-fault-q
             k-response-from-pending-q k-read-word-q
             k-read-return-word-q k-read-outstanding-q
             k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
             k-read-epoch-q k-read-received-mask-q k-cache-valid-q
             k-cache-kind-q k-cache-layer-q k-cache-position-q
             k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
             k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
             k-cache-copy-kind-q k-lock-seen-q k-fault-q
             k-stage-begin-consumed-q k-stage-payload-consumed-q
             k-commit-consumed-q k-attention-req-consumed-q b-crel
             b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync
             b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
             b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
             b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2
             q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1
             q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full
             s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st
             s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6
             s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4
             q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
             a-offer-write a-poison a-offer-slot a-reserved a-unissued
             a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
             a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7
             a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5
             a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3
             a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
             a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
             a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6
             a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5
             a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3
             a-rslot4 a-rslot5 a-rslot6 a-rslot7)
            (joint-inv-p
             p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
             k-pending-issued-q k-pending-returned-q
             k-pending-read-pending-q k-committed-prefix-q
             k-pending-layer-q k-pending-position-q
             k-pending-key-exponents-q k-pending-value-exponents-q
             k-expected-coordinate-q k-pending-persisted-q
             k-write-head-q k-write-word-q k-write-aborted-q
             k-response-kind-q k-response-head-q k-response-layer-q
             k-response-position-q k-response-fault-q
             k-response-from-pending-q k-read-word-q
             k-read-return-word-q k-read-outstanding-q
             k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
             k-read-epoch-q k-read-received-mask-q k-cache-valid-q
             k-cache-kind-q k-cache-layer-q k-cache-position-q
             k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
             k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
             k-cache-copy-kind-q k-lock-seen-q k-fault-q
             k-stage-begin-consumed-q k-stage-payload-consumed-q
             k-commit-consumed-q k-attention-req-consumed-q b-crel
             b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync
             b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
             b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
             b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2
             q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1
             q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full
             s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st
             s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6
             s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4
             q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
             a-offer-write a-poison a-offer-slot a-reserved a-unissued
             a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
             a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7
             a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5
             a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3
             a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
             a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
             a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6
             a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5
             a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3
             a-rslot4 a-rslot5 a-rslot6 a-rslot7))
  :concl (and (equal k-fault-q 0)
              (kv-state-p k-state-q))
  :rule-classes nil)

; COROLLARY 2.  The controller's fault is never latched.
(make-event
 (b* ((ev (acl2::get-event 'join-step-fsm-thm (w state)))
      (bindings (cddr (second (third ev))))
      (inst (bct-n-terms (acl2::formals 'joint-inv-p (w state)) bindings 'n)))
   `(defthm join-no-fault-from-reset
      (b* ((outs (fsm-eval envs initst (probe-fsm))))
        (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                      (join-reset-at r envs outs)
                      (join-env-from (+ 2 r) n envs outs))
                 (and (equal (join-kfault-at n outs) 0)
                      (kv-state-p (join-kstate-at n outs)))))
      :hints (("Goal"
               :use ((:instance join-inv-from-reset)
                     (:instance joint-inv-implies-no-fault
                      ,@(bct-subst '(fsm-eval envs initst (probe-fsm))
                                   'outs inst)))
               :in-theory (e/d (join-j-at join-inv-raw join-kfault-at
                                join-kfault-raw join-kstate-at
                                join-kstate-raw)
                               (join-inv-from-reset
                                join-reset-at join-env-from
                                unsigned-byte-p nth nthcdr take len
                                fsm-eval (probe-fsm) probe-fsm)))))))
(value-triple (acl2::cw "~%BCT-JMAIN proved~%"))

; ---------------------------------------------------------------------------
; Guards against an invariant that nothing satisfies.  Each of these two
; statements says the invariant excludes a kind of state that the design does
; reach; each proof attempt must fail, and the solver's counterexample is
; such a state.  First: a write completion waiting at the head of the
; response FIFO with the controller not yet aborted.  Second: eight reads in
; flight with a response waiting.
; ---------------------------------------------------------------------------
(acl2::must-fail
 (fgl::def-fgl-thm joint-inv-vacuity-check
   :hyp (and (joint-2valued-p
              p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
              k-pending-issued-q k-pending-returned-q
              k-pending-read-pending-q k-committed-prefix-q
              k-pending-layer-q k-pending-position-q
              k-pending-key-exponents-q k-pending-value-exponents-q
              k-expected-coordinate-q k-pending-persisted-q
              k-write-head-q k-write-word-q k-write-aborted-q
              k-response-kind-q k-response-head-q k-response-layer-q
              k-response-position-q k-response-fault-q
              k-response-from-pending-q k-read-word-q
              k-read-return-word-q k-read-outstanding-q
              k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
              k-read-epoch-q k-read-received-mask-q k-cache-valid-q
              k-cache-kind-q k-cache-layer-q k-cache-position-q
              k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
              k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
              k-cache-copy-kind-q k-lock-seen-q k-fault-q
              k-stage-begin-consumed-q k-stage-payload-consumed-q
              k-commit-consumed-q k-attention-req-consumed-q b-crel
              b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync
              b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
              b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
              b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2
              q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1
              q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full
              s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st
              s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6
              s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4
              q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
              a-offer-write a-poison a-offer-slot a-reserved a-unissued
              a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
              a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7
              a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5
              a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3
              a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
              a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
              a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6
              a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5
              a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3
              a-rslot4 a-rslot5 a-rslot6 a-rslot7)
             (joint-inv-p
              p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
              k-pending-issued-q k-pending-returned-q
              k-pending-read-pending-q k-committed-prefix-q
              k-pending-layer-q k-pending-position-q
              k-pending-key-exponents-q k-pending-value-exponents-q
              k-expected-coordinate-q k-pending-persisted-q
              k-write-head-q k-write-word-q k-write-aborted-q
              k-response-kind-q k-response-head-q k-response-layer-q
              k-response-position-q k-response-fault-q
              k-response-from-pending-q k-read-word-q
              k-read-return-word-q k-read-outstanding-q
              k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
              k-read-epoch-q k-read-received-mask-q k-cache-valid-q
              k-cache-kind-q k-cache-layer-q k-cache-position-q
              k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
              k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
              k-cache-copy-kind-q k-lock-seen-q k-fault-q
              k-stage-begin-consumed-q k-stage-payload-consumed-q
              k-commit-consumed-q k-attention-req-consumed-q b-crel
              b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync
              b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
              b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
              b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2
              q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1
              q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full
              s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st
              s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6
              s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4
              q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
              a-offer-write a-poison a-offer-slot a-reserved a-unissued
              a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
              a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7
              a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5
              a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3
              a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
              a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
              a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6
              a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5
              a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3
              a-rslot4 a-rslot5 a-rslot6 a-rslot7))
   :concl (not (and (equal s-mv 1) (equal k-write-aborted-q 0)
                    (equal b-clr-pend 0))))
 :with-output-off nil)

(acl2::must-fail
 (fgl::def-fgl-thm joint-inv-vacuity-check-reads
   :hyp (and (joint-2valued-p
              p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
              k-pending-issued-q k-pending-returned-q
              k-pending-read-pending-q k-committed-prefix-q
              k-pending-layer-q k-pending-position-q
              k-pending-key-exponents-q k-pending-value-exponents-q
              k-expected-coordinate-q k-pending-persisted-q
              k-write-head-q k-write-word-q k-write-aborted-q
              k-response-kind-q k-response-head-q k-response-layer-q
              k-response-position-q k-response-fault-q
              k-response-from-pending-q k-read-word-q
              k-read-return-word-q k-read-outstanding-q
              k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
              k-read-epoch-q k-read-received-mask-q k-cache-valid-q
              k-cache-kind-q k-cache-layer-q k-cache-position-q
              k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
              k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
              k-cache-copy-kind-q k-lock-seen-q k-fault-q
              k-stage-begin-consumed-q k-stage-payload-consumed-q
              k-commit-consumed-q k-attention-req-consumed-q b-crel
              b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync
              b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
              b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
              b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2
              q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1
              q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full
              s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st
              s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6
              s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4
              q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
              a-offer-write a-poison a-offer-slot a-reserved a-unissued
              a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
              a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7
              a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5
              a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3
              a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
              a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
              a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6
              a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5
              a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3
              a-rslot4 a-rslot5 a-rslot6 a-rslot7)
             (joint-inv-p
              p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
              k-pending-issued-q k-pending-returned-q
              k-pending-read-pending-q k-committed-prefix-q
              k-pending-layer-q k-pending-position-q
              k-pending-key-exponents-q k-pending-value-exponents-q
              k-expected-coordinate-q k-pending-persisted-q
              k-write-head-q k-write-word-q k-write-aborted-q
              k-response-kind-q k-response-head-q k-response-layer-q
              k-response-position-q k-response-fault-q
              k-response-from-pending-q k-read-word-q
              k-read-return-word-q k-read-outstanding-q
              k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
              k-read-epoch-q k-read-received-mask-q k-cache-valid-q
              k-cache-kind-q k-cache-layer-q k-cache-position-q
              k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
              k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
              k-cache-copy-kind-q k-lock-seen-q k-fault-q
              k-stage-begin-consumed-q k-stage-payload-consumed-q
              k-commit-consumed-q k-attention-req-consumed-q b-crel
              b-arel b-lock-meta b-lock-sync b-afc-meta b-afc-sync
              b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
              b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
              b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2
              q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1
              q-mem2 q-mem3 q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full
              s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st
              s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6
              s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4
              q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
              a-offer-write a-poison a-offer-slot a-reserved a-unissued
              a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
              a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7
              a-epoch0 a-epoch1 a-epoch2 a-epoch3 a-epoch4 a-epoch5
              a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2 a-reject3
              a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
              a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
              a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6
              a-sfault7 a-word0 a-word1 a-word2 a-word3 a-word4 a-word5
              a-word6 a-word7 a-rslot0 a-rslot1 a-rslot2 a-rslot3
              a-rslot4 a-rslot5 a-rslot6 a-rslot7))
   :concl (not (and (equal k-state-q 6) (equal b-out 8) (equal s-mv 1)
                    (equal k-read-aborted-q 0) (equal b-clr-pend 0))))
 :with-output-off nil)

; ===========================================================================
; THE STATEMENT, IN TERMS OF RTL SIGNALS
;
; An execution is a list envs of input assignments, one per clock cycle, and
; an initial state initst.  outs = (fsm-eval envs initst (probe-fsm)) is the
; list of signal valuations it produces, one per cycle: (nth k outs) holds
; the value of every signal of the design in cycle k, and (nth k envs) the
; values given to the probe module's inputs in cycle k.
;
; (sig "a.b.c" w x) reads the w-bit signal c of instance a.b from x.  With
; :lsb n it reads w bits of that signal starting at bit n.  It abbreviates
; the library's (lhs-eval-zx '<name> x); ACL2 expands it, so what is proved
; is in terms of the library's own names.  Paths are relative to the probe
; module board1_context2048_shared_token_probe.
; ===========================================================================
(defun kvj-sig-scopes (parts)
  (declare (xargs :mode :program))
  (if (atom (cdr parts))
      (car parts)
    (cons (car parts) (kvj-sig-scopes (cdr parts)))))

(defun kvj-sig-lhs (path width lsb)
  (declare (xargs :mode :program))
  (b* ((parts (str::strtok path '(#\.)))
       (var (if (atom (cdr parts))
                (car parts)
              (list* :var (kvj-sig-scopes parts) 0)))
       (atom (if (eql lsb 0) var (cons var lsb))))
    (list (if (eql width 1) atom (cons width atom)))))

(defmacro sig (path width env &key (lsb '0))
  `(lhs-eval-zx ',(kvj-sig-lhs path width lsb) ,env))

; ---------------------------------------------------------------------------
; RESET.  reset_n_i is low in cycles r, r+1 and r+2.
; ---------------------------------------------------------------------------
; The run the reset lemma is about fixes exactly this:
(defthm kv-joined-reset-run-constraints
  (equal (join-reset-run-fsm-constraints)
         '(((("reset_n_i") 0) . 0)      ; reset_n_i is 0 in the first cycle,
           ((("reset_n_i") 1) . 0)      ; the second
           ((("reset_n_i") 2) . 0)))    ; and the third
  :rule-classes nil)

(define kv-reset-held-at (r envs outs)
  :verify-guards nil
  (b* ((in    (nth r envs))               ; the inputs of cycle r
       (third (nth (+ 2 r) outs))         ; the signals of cycle r+2
       (clear (sig "clear_i" 1 in))
       (q-mem0 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 2541))   ; RTL: u_boundary.request_fifo_i.memory_q[0][317:315]
       (q-mem1 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 2223))   ; RTL: u_boundary.request_fifo_i.memory_q[1][317:315]
       (q-mem2 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 1905))   ; RTL: u_boundary.request_fifo_i.memory_q[2][317:315]
       (q-mem3 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 1587))   ; RTL: u_boundary.request_fifo_i.memory_q[3][317:315]
       (q-mem4 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 1269))   ; RTL: u_boundary.request_fifo_i.memory_q[4][317:315]
       (q-mem5 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 951))   ; RTL: u_boundary.request_fifo_i.memory_q[5][317:315]
       (q-mem6 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 633))   ; RTL: u_boundary.request_fifo_i.memory_q[6][317:315]
       (q-mem7 (sig "u_boundary.request_fifo_i.memory_q" 3 third :lsb 315))   ; RTL: u_boundary.request_fifo_i.memory_q[7][317:315]
       (s-mem0 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 2076))   ; RTL: u_boundary.response_fifo_i.memory_q[0][259:256]
       (s-mem1 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 1816))   ; RTL: u_boundary.response_fifo_i.memory_q[1][259:256]
       (s-mem2 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 1556))   ; RTL: u_boundary.response_fifo_i.memory_q[2][259:256]
       (s-mem3 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 1296))   ; RTL: u_boundary.response_fifo_i.memory_q[3][259:256]
       (s-mem4 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 1036))   ; RTL: u_boundary.response_fifo_i.memory_q[4][259:256]
       (s-mem5 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 776))   ; RTL: u_boundary.response_fifo_i.memory_q[5][259:256]
       (s-mem6 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 516))   ; RTL: u_boundary.response_fifo_i.memory_q[6][259:256]
       (s-mem7 (sig "u_boundary.response_fifo_i.memory_q" 4 third :lsb 256))   ; RTL: u_boundary.response_fifo_i.memory_q[7][259:256]
       (q-memw0 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 2501))   ; RTL: u_boundary.request_fifo_i.memory_q[0][278:275]
       (q-memw1 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 2183))   ; RTL: u_boundary.request_fifo_i.memory_q[1][278:275]
       (q-memw2 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 1865))   ; RTL: u_boundary.request_fifo_i.memory_q[2][278:275]
       (q-memw3 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 1547))   ; RTL: u_boundary.request_fifo_i.memory_q[3][278:275]
       (q-memw4 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 1229))   ; RTL: u_boundary.request_fifo_i.memory_q[4][278:275]
       (q-memw5 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 911))   ; RTL: u_boundary.request_fifo_i.memory_q[5][278:275]
       (q-memw6 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 593))   ; RTL: u_boundary.request_fifo_i.memory_q[6][278:275]
       (q-memw7 (sig "u_boundary.request_fifo_i.memory_q" 4 third :lsb 275))   ; RTL: u_boundary.request_fifo_i.memory_q[7][278:275]
       (a-rslot0 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third :lsb 21))   ; RTL: u_boundary.app_boundary_i.read_slot_q[0]
       (a-rslot1 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third :lsb 18))   ; RTL: u_boundary.app_boundary_i.read_slot_q[1]
       (a-rslot2 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third :lsb 15))   ; RTL: u_boundary.app_boundary_i.read_slot_q[2]
       (a-rslot3 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third :lsb 12))   ; RTL: u_boundary.app_boundary_i.read_slot_q[3]
       (a-rslot4 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third :lsb 9))   ; RTL: u_boundary.app_boundary_i.read_slot_q[4]
       (a-rslot5 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third :lsb 6))   ; RTL: u_boundary.app_boundary_i.read_slot_q[5]
       (a-rslot6 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third :lsb 3))   ; RTL: u_boundary.app_boundary_i.read_slot_q[6]
       (a-rslot7 (sig "u_boundary.app_boundary_i.read_slot_q" 3 third))   ; RTL: u_boundary.app_boundary_i.read_slot_q[7]
       )
    (and
     ;; the execution has these three cycles
     (natp r)
     (>= (len envs) (+ r 3))
     ;; its inputs set no override of an internal signal in them
     (svex-envlists-ovtestsimilar (take 3 (nthcdr r envs)) '(nil nil nil))
     ;; reset_n_i is 0 in all three (the constraints shown above)
     (lhprobe-constraintlist-overridemux-eval (join-reset-run-fsm-constraints)
                                              (nthcdr r envs) (nthcdr r outs))
     ;; CLEAR is two-valued in the first
     (unsigned-byte-p 1 clear)
     ;; No reset touches the FIFO memories or the app side's queue of slots
     ;; awaiting a read.  In the third cycle the control bits of each cell
     ;; hold definite values, as unwritten RAM does.  Payload bits are not
     ;; constrained.
     (unsigned-byte-p 3 q-mem0)
     (unsigned-byte-p 3 q-mem1)
     (unsigned-byte-p 3 q-mem2)
     (unsigned-byte-p 3 q-mem3)
     (unsigned-byte-p 3 q-mem4)
     (unsigned-byte-p 3 q-mem5)
     (unsigned-byte-p 3 q-mem6)
     (unsigned-byte-p 3 q-mem7)
     (unsigned-byte-p 4 s-mem0)
     (unsigned-byte-p 4 s-mem1)
     (unsigned-byte-p 4 s-mem2)
     (unsigned-byte-p 4 s-mem3)
     (unsigned-byte-p 4 s-mem4)
     (unsigned-byte-p 4 s-mem5)
     (unsigned-byte-p 4 s-mem6)
     (unsigned-byte-p 4 s-mem7)
     (unsigned-byte-p 4 q-memw0)
     (unsigned-byte-p 4 q-memw1)
     (unsigned-byte-p 4 q-memw2)
     (unsigned-byte-p 4 q-memw3)
     (unsigned-byte-p 4 q-memw4)
     (unsigned-byte-p 4 q-memw5)
     (unsigned-byte-p 4 q-memw6)
     (unsigned-byte-p 4 q-memw7)
     (unsigned-byte-p 3 a-rslot0)
     (unsigned-byte-p 3 a-rslot1)
     (unsigned-byte-p 3 a-rslot2)
     (unsigned-byte-p 3 a-rslot3)
     (unsigned-byte-p 3 a-rslot4)
     (unsigned-byte-p 3 a-rslot5)
     (unsigned-byte-p 3 a-rslot6)
     (unsigned-byte-p 3 a-rslot7))))

; ---------------------------------------------------------------------------
; THE ENVIRONMENT IN CYCLE k.  CLEAR is free: clear_i may be 0 or 1 in any
; cycle.  The client may stage, commit and ask for rows as it likes.
; ---------------------------------------------------------------------------
; The run the step lemma is about fixes exactly this:
(defthm kv-joined-step-run-constraints
  (equal (join-step-run-fsm-constraints)
         '(((("private_model_locked_i") 0) . 1)    ; the lock input is 1 in cycle k
           ((("reset_n_i") 1) . 1)))               ; reset_n_i is 1 in cycle k+1
  :rule-classes nil)

(define kv-environment-ok-at (k envs outs)
  :verify-guards nil
  (b* ((in   (nth k envs))                ; the inputs of cycle k
       (next (nth (+ 1 k) envs))          ; the inputs of cycle k+1
       (now  (nth k outs))                ; the signals of cycle k
       (reset-n      (sig "reset_n_i" 1 in))
       (reset-n-next (sig "reset_n_i" 1 next))
       (clear        (sig "clear_i" 1 in))
       ;; no module outside the slice reports a fault
       (h-arbfail (sig "u_machine.arbiter_fail" 1 now))
       (h-shellterm (sig "u_machine.shell_terminal_latched" 1 now))
       (h-shellfail (sig "u_machine.shell_fail" 1 now))
       (h-layerfail (sig "u_machine.layer_fail" 1 now))
       (h-auth (sig "auth_fault" 1 now))
       (h-mcdc (sig "model_cdc_core_fault" 1 now))
       (h-kupf (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.upstream_fault_i" 1 now))
       ;; the client (the datapath) drives two-valued signals to the controller
       (h-layer (sig "u_machine.u_six_layers.u_datapath.current_layer_q" 3 now))
       (h-position (sig "u_machine.u_six_layers.u_datapath.current_position_q" 11 now))
       (h-kexp (sig "u_machine.u_six_layers.u_datapath.key_exponent_q" 8 now))
       (h-vexp (sig "u_machine.u_six_layers.u_datapath.value_exponent_q" 8 now))
       (h-sbegin (sig "u_machine.u_six_layers.u_datapath.kv_stage_begin_valid" 1 now))
       (h-spayload (sig "u_machine.u_six_layers.u_datapath.kv_stage_payload_valid" 1 now))
       (h-index (sig "u_machine.u_six_layers.u_datapath.input_index_q" 10 now))
       (h-key (sig "u_machine.u_six_layers.u_datapath.key_ram_read_data" 16 now))
       (h-value (sig "u_machine.u_six_layers.u_datapath.value_ram_read_data" 16 now))
       (h-commit (sig "u_machine.u_six_layers.u_datapath.kv_commit_valid" 1 now))
       (h-attn (sig "u_machine.u_six_layers.u_datapath.attention_cache_req_valid" 1 now))
       (h-attn-kind (sig "u_machine.u_six_layers.u_datapath.attention_cache_req_kind" 2 now))
       (h-attn-pos (sig "u_machine.u_six_layers.u_datapath.attention_cache_req_position" 11 now))
       (h-attn-head (sig "u_machine.u_six_layers.u_datapath.attention_cache_req_head" 1 now))
       (h-attn-ready (sig "u_machine.u_six_layers.u_datapath.attention_cache_rsp_ready" 1 now))
       ;; the endpoint behind the boundary, and the data word shown to the controller
       (h-epready (sig "private_kv_req_ready_i" 1 now))
       (h-eprspv (sig "private_kv_rsp_valid_i" 1 now))
       (h-eprsperr (sig "private_kv_rsp_error_i" 1 now))
       (h-eprspdata (sig "private_kv_rsp_data_i" 256 now))
       (h-rspdata (sig "kv_read_rsp_data" 256 now))   ; RTL: u_machine.u_six_layers.u_datapath.u_kv_cache.kv_read_rsp_data_i
       (h-appup (sig "u_boundary.app_upstream_fault_i" 1 now))
       ;; the app side's verdict on the descriptor of the request presented to it
       (h-legal (sig "u_boundary.app_boundary_i.request_descriptor_legal" 1 now))
       ;; three fault signals inside the slice that only the client or the
       ;; endpoint can raise
       (protocol-fault-now         (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.protocol_fault_now" 1 now))
       (typed-padding-fault        (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.typed_padding_fault" 1 now))
       (endpoint-padding-fault-now (sig "u_boundary.app_boundary_i.endpoint_padding_fault_now" 1 now))
       ;; two registers of the slice the conditions below refer to
       (request-presented (sig "u_boundary.request_fifo_i.m_valid_q" 1 now))
       (reads-at-endpoint (sig "u_boundary.app_boundary_i.read_count_q" 4 now)))
    (and
     ;; ---- the execution has a cycle k+1, and its inputs set no override of
     ;;      an internal signal in cycles k and k+1
     (natp k)
     (>= (len envs) (+ k 2))
     (svex-envlists-ovtestsimilar (take 2 (nthcdr k envs)) '(nil nil))
     ;; ---- the lock input is held in cycle k and reset is not asserted in
     ;;      cycle k+1 (the constraints shown above)
     (lhprobe-constraintlist-overridemux-eval (join-step-run-fsm-constraints)
                                              (nthcdr k envs) (nthcdr k outs))
     (equal reset-n-next 1)
     ;; ---- reset_n_i and clear_i are two-valued
     (unsigned-byte-p 1 reset-n)
     (unsigned-byte-p 1 clear)
     ;; ---- no module outside the slice reports a fault
     (unsigned-byte-p 1 h-arbfail)
     (unsigned-byte-p 1 h-shellterm)
     (unsigned-byte-p 1 h-shellfail)
     (unsigned-byte-p 1 h-layerfail)
     (unsigned-byte-p 1 h-auth)
     (unsigned-byte-p 1 h-mcdc)
     (unsigned-byte-p 1 h-kupf)
     (equal h-arbfail 0)
     (equal h-shellterm 0)
     (equal h-shellfail 0)
     (equal h-layerfail 0)
     (equal h-auth 0)
     (equal h-mcdc 0)
     (equal h-kupf 0)
     ;; ---- the client (the datapath) drives two-valued signals to the controller
     (unsigned-byte-p 3 h-layer)
     (unsigned-byte-p 11 h-position)
     (unsigned-byte-p 8 h-kexp)
     (unsigned-byte-p 8 h-vexp)
     (unsigned-byte-p 1 h-sbegin)
     (unsigned-byte-p 1 h-spayload)
     (unsigned-byte-p 10 h-index)
     (unsigned-byte-p 16 h-key)
     (unsigned-byte-p 16 h-value)
     (unsigned-byte-p 1 h-commit)
     (unsigned-byte-p 1 h-attn)
     (unsigned-byte-p 2 h-attn-kind)
     (unsigned-byte-p 11 h-attn-pos)
     (unsigned-byte-p 1 h-attn-head)
     (unsigned-byte-p 1 h-attn-ready)
     ;; and commits no protocol violation
     (equal protocol-fault-now 0)
     ;; ---- the endpoint behind the boundary, and the data word shown to the controller
     (unsigned-byte-p 1 h-epready)
     (unsigned-byte-p 1 h-eprspv)
     (unsigned-byte-p 1 h-eprsperr)
     (unsigned-byte-p 256 h-eprspdata)
     (unsigned-byte-p 256 h-rspdata)
     (unsigned-byte-p 1 h-appup)
     (equal h-eprsperr 0)
     (equal h-appup 0)
     ;; it answers only while a read is at the endpoint
     (or (equal h-eprspv 0) (<= 1 reads-at-endpoint))
     ;; and the metadata word of a row comes back well formed
     (equal typed-padding-fault 0)
     (equal endpoint-padding-fault-now 0)
     ;; ---- the app side's verdict on the descriptor of the request presented to it
     (unsigned-byte-p 1 h-legal)
     ;; is "legal" whenever the request FIFO presents an entry
     (or (equal request-presented 0) (equal h-legal 1)))))

; ... in every cycle from j up to but not including n.
(define kv-environment-ok-from (j n envs outs)
  :verify-guards nil
  :measure (nfix (- (nfix n) (nfix j)))
  (if (zp (- (nfix n) (nfix j)))
      t
    (and (kv-environment-ok-at (nfix j) envs outs)
         (kv-environment-ok-from (+ 1 (nfix j)) n envs outs))))

; ---------------------------------------------------------------------------
; THE INVARIANT IN CYCLE n: joint-inv-p (kv-joined-statements.lisp) of these
; 194 signals, each holding a definite value.
; ---------------------------------------------------------------------------
(define kv-invariant-at (n outs)
  :verify-guards nil
  (b* ((now (nth n outs))
       (p-lock-meta (sig "model_lock_core_meta_q" 1 now))
       (p-lock-sync (sig "model_lock_core_sync_q" 1 now))
       (p-cfb (sig "core_fault_to_boundary_q" 1 now))
       (p-apprel (sig "app_runtime_release_q" 3 now))
       (m-rel (sig "u_machine.machine_release_q" 2 now))
       (k-state-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" 4 now))
       (k-pending-issued-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_issued_q" 4 now))
       (k-pending-returned-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_returned_q" 3 now))
       (k-pending-read-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_read_pending_q" 1 now))
       (k-committed-prefix-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.committed_prefix_q" 72 now))
       (k-pending-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_layer_q" 3 now))
       (k-pending-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_position_q" 12 now))
       (k-pending-key-exponents-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_key_exponents_q" 16 now))
       (k-pending-value-exponents-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_value_exponents_q" 16 now))
       (k-expected-coordinate-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.expected_coordinate_q" 7 now))
       (k-pending-persisted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_persisted_q" 1 now))
       (k-write-head-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_head_q" 1 now))
       (k-write-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_word_q" 4 now))
       (k-write-aborted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_aborted_q" 1 now))
       (k-response-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_kind_q" 2 now))
       (k-response-head-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_head_q" 1 now))
       (k-response-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_layer_q" 3 now))
       (k-response-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_position_q" 12 now))
       (k-response-fault-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_fault_q" 1 now))
       (k-response-from-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_from_pending_q" 1 now))
       (k-read-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_word_q" 4 now))
       (k-read-return-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_return_word_q" 4 now))
       (k-read-outstanding-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_outstanding_q" 4 now))
       (k-read-issue-done-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_issue_done_q" 1 now))
       (k-read-aborted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_aborted_q" 1 now))
       (k-read-physical-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_physical_kind_q" 1 now))
       (k-read-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_epoch_q" 1 now))
       (k-read-received-mask-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_received_mask_q" 9 now))
       (k-cache-valid-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_valid_q" 1 now))
       (k-cache-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_kind_q" 1 now))
       (k-cache-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_layer_q" 3 now))
       (k-cache-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_position_q" 12 now))
       (k-cache-tag-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_tag_epoch_q" 1 now))
       (k-cache-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_epoch_q" 1 now))
       (k-cache-clear-seen-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_clear_seen_q" 1 now))
       (k-cache-issued-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_issued_q" 3 now))
       (k-cache-returned-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_returned_q" 3 now))
       (k-cache-read-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_read_pending_q" 1 now))
       (k-cache-copy-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_copy_kind_q" 1 now))
       (k-lock-seen-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.lock_seen_q" 1 now))
       (k-fault-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.fault_q" 1 now))
       (k-stage-begin-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_consumed_q" 1 now))
       (k-stage-payload-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_consumed_q" 1 now))
       (k-commit-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.commit_consumed_q" 1 now))
       (k-attention-req-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_consumed_q" 1 now))
       (b-crel (sig "u_boundary.core_release_q" 3 now))
       (b-arel (sig "u_boundary.app_release_q" 3 now))
       (b-lock-meta (sig "u_boundary.model_lock_core_meta_q" 1 now))
       (b-lock-sync (sig "u_boundary.model_lock_core_sync_q" 1 now))
       (b-afc-meta (sig "u_boundary.app_fault_core_meta_q" 1 now))
       (b-afc-sync (sig "u_boundary.app_fault_core_sync_q" 1 now))
       (b-cfa-meta (sig "u_boundary.core_fault_app_meta_q" 1 now))
       (b-cfa-sync (sig "u_boundary.core_fault_app_sync_q" 1 now))
       (b-fault (sig "u_boundary.core_fault_q" 1 now))
       (b-lock-seen (sig "u_boundary.core_lock_seen_q" 1 now))
       (b-clr-seen (sig "u_boundary.core_clear_seen_q" 1 now))
       (b-clr-pend (sig "u_boundary.core_clear_pending_q" 1 now))
       (b-clr-drained (sig "boundary_core_clear_drained" 1 now))   ; RTL: u_boundary.core_clear_drained_o
       (b-epoch (sig "u_boundary.core_epoch_q" 1 now))
       (b-out (sig "u_boundary.core_outstanding_q" 4 now))
       (b-mstall (sig "u_boundary.model_rsp_stalled_q" 1 now))
       (b-wstall (sig "u_boundary.kv_write_cpl_stalled_q" 1 now))
       (b-wstallf (sig "u_boundary.kv_write_cpl_stalled_fault_q" 1 now))
       (b-rstall (sig "u_boundary.kv_read_rsp_stalled_q" 1 now))
       (q-wb (sig "u_boundary.request_fifo_i.write_binary_q" 4 now))
       (q-wg (sig "u_boundary.request_fifo_i.write_gray_q" 4 now))
       (q-full (sig "u_boundary.request_fifo_i.write_full_q" 1 now))
       (q-rb (sig "u_boundary.request_fifo_i.read_binary_q" 4 now))
       (q-rg (sig "u_boundary.request_fifo_i.read_gray_q" 4 now))
       (q-rs1 (sig "u_boundary.request_fifo_i.read_gray_sync1_q" 4 now))
       (q-rs2 (sig "u_boundary.request_fifo_i.read_gray_sync2_q" 4 now))
       (q-ws1 (sig "u_boundary.request_fifo_i.write_gray_sync1_q" 4 now))
       (q-ws2 (sig "u_boundary.request_fifo_i.write_gray_sync2_q" 4 now))
       (q-mv (sig "u_boundary.request_fifo_i.m_valid_q" 1 now))
       (q-sf (sig "u_boundary.request_fifo_i.source_fault_q" 1 now))
       (q-spf (sig "u_boundary.request_fifo_i.source_payload_fault_q" 40 now))
       (q-df (sig "u_boundary.request_fifo_i.destination_fault_q" 1 now))
       (q-st (sig "u_boundary.request_fifo_i.source_stalled_q" 1 now))
       (q-md (sig "u_boundary.request_fifo_i.m_data_q" 3 now :lsb 315))   ; RTL: u_boundary.request_fifo_i.m_data_q[317:315]
       (q-mem0 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 2541))   ; RTL: u_boundary.request_fifo_i.memory_q[0][317:315]
       (q-mem1 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 2223))   ; RTL: u_boundary.request_fifo_i.memory_q[1][317:315]
       (q-mem2 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 1905))   ; RTL: u_boundary.request_fifo_i.memory_q[2][317:315]
       (q-mem3 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 1587))   ; RTL: u_boundary.request_fifo_i.memory_q[3][317:315]
       (q-mem4 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 1269))   ; RTL: u_boundary.request_fifo_i.memory_q[4][317:315]
       (q-mem5 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 951))   ; RTL: u_boundary.request_fifo_i.memory_q[5][317:315]
       (q-mem6 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 633))   ; RTL: u_boundary.request_fifo_i.memory_q[6][317:315]
       (q-mem7 (sig "u_boundary.request_fifo_i.memory_q" 3 now :lsb 315))   ; RTL: u_boundary.request_fifo_i.memory_q[7][317:315]
       (s-wb (sig "u_boundary.response_fifo_i.write_binary_q" 4 now))
       (s-wg (sig "u_boundary.response_fifo_i.write_gray_q" 4 now))
       (s-full (sig "u_boundary.response_fifo_i.write_full_q" 1 now))
       (s-rb (sig "u_boundary.response_fifo_i.read_binary_q" 4 now))
       (s-rg (sig "u_boundary.response_fifo_i.read_gray_q" 4 now))
       (s-rs1 (sig "u_boundary.response_fifo_i.read_gray_sync1_q" 4 now))
       (s-rs2 (sig "u_boundary.response_fifo_i.read_gray_sync2_q" 4 now))
       (s-ws1 (sig "u_boundary.response_fifo_i.write_gray_sync1_q" 4 now))
       (s-ws2 (sig "u_boundary.response_fifo_i.write_gray_sync2_q" 4 now))
       (s-mv (sig "u_boundary.response_fifo_i.m_valid_q" 1 now))
       (s-sf (sig "u_boundary.response_fifo_i.source_fault_q" 1 now))
       (s-spf (sig "u_boundary.response_fifo_i.source_payload_fault_q" 33 now))
       (s-df (sig "u_boundary.response_fifo_i.destination_fault_q" 1 now))
       (s-st (sig "u_boundary.response_fifo_i.source_stalled_q" 1 now))
       (s-md (sig "u_boundary.response_fifo_i.m_data_q" 4 now :lsb 256))   ; RTL: u_boundary.response_fifo_i.m_data_q[259:256]
       (s-mem0 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 2076))   ; RTL: u_boundary.response_fifo_i.memory_q[0][259:256]
       (s-mem1 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 1816))   ; RTL: u_boundary.response_fifo_i.memory_q[1][259:256]
       (s-mem2 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 1556))   ; RTL: u_boundary.response_fifo_i.memory_q[2][259:256]
       (s-mem3 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 1296))   ; RTL: u_boundary.response_fifo_i.memory_q[3][259:256]
       (s-mem4 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 1036))   ; RTL: u_boundary.response_fifo_i.memory_q[4][259:256]
       (s-mem5 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 776))   ; RTL: u_boundary.response_fifo_i.memory_q[5][259:256]
       (s-mem6 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 516))   ; RTL: u_boundary.response_fifo_i.memory_q[6][259:256]
       (s-mem7 (sig "u_boundary.response_fifo_i.memory_q" 4 now :lsb 256))   ; RTL: u_boundary.response_fifo_i.memory_q[7][259:256]
       (q-mdw (sig "u_boundary.request_fifo_i.m_data_q" 4 now :lsb 275))   ; RTL: u_boundary.request_fifo_i.m_data_q[278:275]
       (q-memw0 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 2501))   ; RTL: u_boundary.request_fifo_i.memory_q[0][278:275]
       (q-memw1 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 2183))   ; RTL: u_boundary.request_fifo_i.memory_q[1][278:275]
       (q-memw2 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 1865))   ; RTL: u_boundary.request_fifo_i.memory_q[2][278:275]
       (q-memw3 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 1547))   ; RTL: u_boundary.request_fifo_i.memory_q[3][278:275]
       (q-memw4 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 1229))   ; RTL: u_boundary.request_fifo_i.memory_q[4][278:275]
       (q-memw5 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 911))   ; RTL: u_boundary.request_fifo_i.memory_q[5][278:275]
       (q-memw6 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 593))   ; RTL: u_boundary.request_fifo_i.memory_q[6][278:275]
       (q-memw7 (sig "u_boundary.request_fifo_i.memory_q" 4 now :lsb 275))   ; RTL: u_boundary.request_fifo_i.memory_q[7][278:275]
       (a-fault (sig "u_boundary.app_boundary_i.fault_q" 1 now))
       (a-lock-seen (sig "u_boundary.app_boundary_i.lock_seen_q" 1 now))
       (a-offer (sig "u_boundary.app_boundary_i.offer_q" 1 now))
       (a-offer-write (sig "u_boundary.app_boundary_i.offer_write_q" 1 now))
       (a-poison (sig "u_boundary.app_boundary_i.offer_poison_q" 1 now))
       (a-offer-slot (sig "u_boundary.app_boundary_i.offer_slot_q" 3 now))
       (a-reserved (sig "u_boundary.app_boundary_i.reserved_q" 4 now))
       (a-unissued (sig "u_boundary.app_boundary_i.unissued_q" 4 now))
       (a-readcount (sig "u_boundary.app_boundary_i.read_count_q" 4 now))
       (a-head (sig "u_boundary.app_boundary_i.head_q" 3 now))
       (a-tail (sig "u_boundary.app_boundary_i.tail_q" 3 now))
       (a-issue (sig "u_boundary.app_boundary_i.issue_q" 3 now))
       (a-rhead (sig "u_boundary.app_boundary_i.read_head_q" 3 now))
       (a-rtail (sig "u_boundary.app_boundary_i.read_tail_q" 3 now))
       (a-kind0 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now :lsb 14))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[0]
       (a-kind1 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now :lsb 12))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[1]
       (a-kind2 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now :lsb 10))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[2]
       (a-kind3 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now :lsb 8))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[3]
       (a-kind4 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now :lsb 6))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[4]
       (a-kind5 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now :lsb 4))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[5]
       (a-kind6 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now :lsb 2))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[6]
       (a-kind7 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 now))   ; RTL: u_boundary.app_boundary_i.slot_kind_q[7]
       (a-epoch0 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now :lsb 7))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[7]
       (a-epoch1 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now :lsb 6))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[6]
       (a-epoch2 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now :lsb 5))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[5]
       (a-epoch3 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now :lsb 4))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[4]
       (a-epoch4 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now :lsb 3))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[3]
       (a-epoch5 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now :lsb 2))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[2]
       (a-epoch6 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now :lsb 1))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[1]
       (a-epoch7 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 now))   ; RTL: u_boundary.app_boundary_i.slot_epoch_q[0]
       (a-reject0 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now :lsb 7))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[7]
       (a-reject1 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now :lsb 6))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[6]
       (a-reject2 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now :lsb 5))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[5]
       (a-reject3 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now :lsb 4))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[4]
       (a-reject4 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now :lsb 3))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[3]
       (a-reject5 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now :lsb 2))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[2]
       (a-reject6 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now :lsb 1))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[1]
       (a-reject7 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 now))   ; RTL: u_boundary.app_boundary_i.slot_reject_q[0]
       (a-done0 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now :lsb 7))   ; RTL: u_boundary.app_boundary_i.slot_done_q[7]
       (a-done1 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now :lsb 6))   ; RTL: u_boundary.app_boundary_i.slot_done_q[6]
       (a-done2 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now :lsb 5))   ; RTL: u_boundary.app_boundary_i.slot_done_q[5]
       (a-done3 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now :lsb 4))   ; RTL: u_boundary.app_boundary_i.slot_done_q[4]
       (a-done4 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now :lsb 3))   ; RTL: u_boundary.app_boundary_i.slot_done_q[3]
       (a-done5 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now :lsb 2))   ; RTL: u_boundary.app_boundary_i.slot_done_q[2]
       (a-done6 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now :lsb 1))   ; RTL: u_boundary.app_boundary_i.slot_done_q[1]
       (a-done7 (sig "u_boundary.app_boundary_i.slot_done_q" 1 now))   ; RTL: u_boundary.app_boundary_i.slot_done_q[0]
       (a-sfault0 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now :lsb 7))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[7]
       (a-sfault1 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now :lsb 6))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[6]
       (a-sfault2 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now :lsb 5))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[5]
       (a-sfault3 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now :lsb 4))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[4]
       (a-sfault4 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now :lsb 3))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[3]
       (a-sfault5 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now :lsb 2))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[2]
       (a-sfault6 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now :lsb 1))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[1]
       (a-sfault7 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 now))   ; RTL: u_boundary.app_boundary_i.slot_fault_q[0]
       (a-word0 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now :lsb 28))   ; RTL: u_boundary.app_boundary_i.slot_word_q[0]
       (a-word1 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now :lsb 24))   ; RTL: u_boundary.app_boundary_i.slot_word_q[1]
       (a-word2 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now :lsb 20))   ; RTL: u_boundary.app_boundary_i.slot_word_q[2]
       (a-word3 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now :lsb 16))   ; RTL: u_boundary.app_boundary_i.slot_word_q[3]
       (a-word4 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now :lsb 12))   ; RTL: u_boundary.app_boundary_i.slot_word_q[4]
       (a-word5 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now :lsb 8))   ; RTL: u_boundary.app_boundary_i.slot_word_q[5]
       (a-word6 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now :lsb 4))   ; RTL: u_boundary.app_boundary_i.slot_word_q[6]
       (a-word7 (sig "u_boundary.app_boundary_i.slot_word_q" 4 now))   ; RTL: u_boundary.app_boundary_i.slot_word_q[7]
       (a-rslot0 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now :lsb 21))   ; RTL: u_boundary.app_boundary_i.read_slot_q[0]
       (a-rslot1 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now :lsb 18))   ; RTL: u_boundary.app_boundary_i.read_slot_q[1]
       (a-rslot2 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now :lsb 15))   ; RTL: u_boundary.app_boundary_i.read_slot_q[2]
       (a-rslot3 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now :lsb 12))   ; RTL: u_boundary.app_boundary_i.read_slot_q[3]
       (a-rslot4 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now :lsb 9))   ; RTL: u_boundary.app_boundary_i.read_slot_q[4]
       (a-rslot5 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now :lsb 6))   ; RTL: u_boundary.app_boundary_i.read_slot_q[5]
       (a-rslot6 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now :lsb 3))   ; RTL: u_boundary.app_boundary_i.read_slot_q[6]
       (a-rslot7 (sig "u_boundary.app_boundary_i.read_slot_q" 3 now))   ; RTL: u_boundary.app_boundary_i.read_slot_q[7]
       )
    (and
     (joint-inv-p
      p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
      k-pending-issued-q k-pending-returned-q k-pending-read-pending-q
      k-committed-prefix-q k-pending-layer-q k-pending-position-q
      k-pending-key-exponents-q k-pending-value-exponents-q
      k-expected-coordinate-q k-pending-persisted-q k-write-head-q
      k-write-word-q k-write-aborted-q k-response-kind-q k-response-head-q
      k-response-layer-q k-response-position-q k-response-fault-q
      k-response-from-pending-q k-read-word-q k-read-return-word-q
      k-read-outstanding-q k-read-issue-done-q k-read-aborted-q
      k-read-physical-kind-q k-read-epoch-q k-read-received-mask-q
      k-cache-valid-q k-cache-kind-q k-cache-layer-q k-cache-position-q
      k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
      k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
      k-cache-copy-kind-q k-lock-seen-q k-fault-q k-stage-begin-consumed-q
      k-stage-payload-consumed-q k-commit-consumed-q
      k-attention-req-consumed-q b-crel b-arel b-lock-meta b-lock-sync
      b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync b-fault b-lock-seen
      b-clr-seen b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
      b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2
      q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3 q-mem4
      q-mem5 q-mem6 q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1
      s-ws2 s-mv s-sf s-spf s-df s-st s-md s-mem0 s-mem1 s-mem2 s-mem3
      s-mem4 s-mem5 s-mem6 s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3
      q-memw4 q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
      a-offer-write a-poison a-offer-slot a-reserved a-unissued a-readcount
      a-head a-tail a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3
      a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2 a-epoch3
      a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2
      a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
      a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0 a-sfault1
      a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0
      a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0
      a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6 a-rslot7)
     (joint-2valued-p
      p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
      k-pending-issued-q k-pending-returned-q k-pending-read-pending-q
      k-committed-prefix-q k-pending-layer-q k-pending-position-q
      k-pending-key-exponents-q k-pending-value-exponents-q
      k-expected-coordinate-q k-pending-persisted-q k-write-head-q
      k-write-word-q k-write-aborted-q k-response-kind-q k-response-head-q
      k-response-layer-q k-response-position-q k-response-fault-q
      k-response-from-pending-q k-read-word-q k-read-return-word-q
      k-read-outstanding-q k-read-issue-done-q k-read-aborted-q
      k-read-physical-kind-q k-read-epoch-q k-read-received-mask-q
      k-cache-valid-q k-cache-kind-q k-cache-layer-q k-cache-position-q
      k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
      k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
      k-cache-copy-kind-q k-lock-seen-q k-fault-q k-stage-begin-consumed-q
      k-stage-payload-consumed-q k-commit-consumed-q
      k-attention-req-consumed-q b-crel b-arel b-lock-meta b-lock-sync
      b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync b-fault b-lock-seen
      b-clr-seen b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall
      b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2
      q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3 q-mem4
      q-mem5 q-mem6 q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1
      s-ws2 s-mv s-sf s-spf s-df s-st s-md s-mem0 s-mem1 s-mem2 s-mem3
      s-mem4 s-mem5 s-mem6 s-mem7 q-mdw q-memw0 q-memw1 q-memw2 q-memw3
      q-memw4 q-memw5 q-memw6 q-memw7 a-fault a-lock-seen a-offer
      a-offer-write a-poison a-offer-slot a-reserved a-unissued a-readcount
      a-head a-tail a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3
      a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2 a-epoch3
      a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2
      a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
      a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0 a-sfault1
      a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0
      a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0
      a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6 a-rslot7))))

; ---------------------------------------------------------------------------
; THE CONTROLLER HAS NO FAULT LATCHED and is in one of its fourteen states.
; ---------------------------------------------------------------------------
(define kv-no-fault-at (n outs)
  :verify-guards nil
  (b* ((now (nth n outs))
       (fault-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.fault_q" 1 now))
       (state-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" 4 now)))
    (and (equal fault-q 0)
         (kv-state-p state-q))))

; ---------------------------------------------------------------------------
; REQUEST OWNERSHIP.  Every request the controller has issued and not yet
; had answered is in exactly one of three places: the request FIFO, an
; app-side slot, or the response FIFO.  The boundary's count of outstanding
; requests is the sum of the three, it is at most eight, and it is what the
; controller is waiting for: one write in WRITE_WAIT, its own count of
; outstanding reads in READ_REQ and READ_WAIT, nothing otherwise
; (kv-in-flight).
; ---------------------------------------------------------------------------
(define kv-requests-owned-p (outstanding in-request-fifo in-app-slots
                             in-response-fifo awaited-by-controller)
  :verify-guards nil
  (and (<= outstanding 8)
       (equal outstanding (+ in-request-fifo in-app-slots in-response-fifo))
       (equal outstanding awaited-by-controller)))

(define kv-requests-owned-at (n outs)
  :verify-guards nil
  (b* ((now (nth n outs))
       (k-state-q            (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" 4 now))
       (k-read-outstanding-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_outstanding_q" 4 now))
       (b-out                (sig "u_boundary.core_outstanding_q" 4 now))
       (q-wb                 (sig "u_boundary.request_fifo_i.write_binary_q" 4 now))
       (q-rb                 (sig "u_boundary.request_fifo_i.read_binary_q" 4 now))
       (a-reserved           (sig "u_boundary.app_boundary_i.reserved_q" 4 now))
       (s-wb                 (sig "u_boundary.response_fifo_i.write_binary_q" 4 now))
       (s-rb                 (sig "u_boundary.response_fifo_i.read_binary_q" 4 now)))
    (kv-requests-owned-p b-out
                         (logand 15 (- q-wb q-rb))     ; entries in the request FIFO
                         a-reserved                    ; app-side slots in use
                         (logand 15 (- s-wb s-rb))     ; entries in the response FIFO
                         (kv-in-flight k-state-q k-read-outstanding-q))))

; ---------------------------------------------------------------------------
; A FAULT FLAG AT THE CONTROLLER'S PORTS IS EXPLAINED BY A CLEAR.  In cycle
; k, a write completion or a read response presented to the controller is
; flagged faulted only if CLEAR is high at the controller in that cycle or
; the controller has already seen a CLEAR while waiting (kv-clause-p); and
; the controller's terminal_fault_event is low.
; ---------------------------------------------------------------------------
(define kv-fault-flag-explained-at (k outs)
  :verify-guards nil
  (b* ((now (nth k outs))
       (write-cpl-valid      (sig "u_machine.child_kv_write_cpl_valid" 1 now))
       (write-cpl-fault      (sig "kv_write_cpl_fault" 1 now))
       (read-rsp-valid       (sig "u_machine.child_kv_read_rsp_valid" 1 now))
       (read-rsp-fault       (sig "kv_read_rsp_fault" 1 now))
       (clear                (sig "u_machine.layer_clear" 1 now))
       (write-aborted-q      (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_aborted_q" 1 now))
       (read-aborted-q       (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_aborted_q" 1 now))
       (terminal-fault-event (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.terminal_fault_event" 1 now)))
    (and (kv-clause-p write-cpl-valid write-cpl-fault clear write-aborted-q)
         (kv-clause-p read-rsp-valid read-rsp-fault clear read-aborted-q)
         (equal terminal-fault-event 0))))

(in-theory (disable kv-reset-held-at kv-environment-ok-at kv-environment-ok-from
                    kv-invariant-at kv-no-fault-at kv-requests-owned-p
                    kv-requests-owned-at kv-fault-flag-explained-at))

; ---------------------------------------------------------------------------
; The statements above are those of the two lemmas.  Each of the next five
; theorems says that a statement written here implies, or is implied by,
; the corresponding term taken from the lemma by the definitions earlier in
; this book.
; ---------------------------------------------------------------------------
(defthm kvj-reset-connects
  (implies (kv-reset-held-at r envs outs)
           (join-reset-at r envs outs))
  :hints (("Goal"
           :in-theory (e/d (kv-reset-held-at join-reset-at join-reset-raw)
                           (unsigned-byte-p nth nthcdr take len)))))

(defthm kvj-environment-connects
  (implies (kv-environment-ok-at k envs outs)
           (join-env-at k envs outs))
  :hints (("Goal"
           :in-theory (e/d (kv-environment-ok-at join-env-at join-env-raw joint-env-p)
                           (unsigned-byte-p nth nthcdr take len)))))

(defthm kvj-environment-from-connects
  (implies (kv-environment-ok-from j n envs outs)
           (join-env-from j n envs outs))
  :hints (("Goal"
           :induct (kv-environment-ok-from j n envs outs)
           :in-theory (e/d (kv-environment-ok-from join-env-from)
                           (kv-environment-ok-at join-env-at)))))

(defthm kvj-invariant-connects
  (implies (join-j-at n envs outs)
           (kv-invariant-at n outs))
  :hints (("Goal"
           :in-theory (e/d (kv-invariant-at join-j-at join-inv-raw)
                           (unsigned-byte-p nth nthcdr take len)))))

(defthm kvj-clause-connects
  (implies (join-clause-at k envs outs)
           (kv-fault-flag-explained-at k outs))
  :hints (("Goal"
           :in-theory (e/d (kv-fault-flag-explained-at join-clause-at join-clause-raw)
                           (unsigned-byte-p nth nthcdr take len)))))

; The invariant, as a statement about plain numbers, implies that the
; requests in flight are owned as described.  (That it implies no fault is
; joint-inv-implies-no-fault, above.)
(fgl::def-fgl-thm joint-inv-implies-requests-owned
  :hyp (and (joint-2valued-p
                  p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
                  k-pending-issued-q k-pending-returned-q
                  k-pending-read-pending-q k-committed-prefix-q
                  k-pending-layer-q k-pending-position-q
                  k-pending-key-exponents-q k-pending-value-exponents-q
                  k-expected-coordinate-q k-pending-persisted-q k-write-head-q
                  k-write-word-q k-write-aborted-q k-response-kind-q
                  k-response-head-q k-response-layer-q k-response-position-q
                  k-response-fault-q k-response-from-pending-q k-read-word-q
                  k-read-return-word-q k-read-outstanding-q
                  k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
                  k-read-epoch-q k-read-received-mask-q k-cache-valid-q
                  k-cache-kind-q k-cache-layer-q k-cache-position-q
                  k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
                  k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
                  k-cache-copy-kind-q k-lock-seen-q k-fault-q
                  k-stage-begin-consumed-q k-stage-payload-consumed-q
                  k-commit-consumed-q k-attention-req-consumed-q b-crel b-arel
                  b-lock-meta b-lock-sync b-afc-meta b-afc-sync b-cfa-meta
                  b-cfa-sync b-fault b-lock-seen b-clr-seen b-clr-pend
                  b-clr-drained b-epoch b-out b-mstall b-wstall b-wstallf
                  b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2
                  q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3
                  q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1
                  s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st s-md s-mem0
                  s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6 s-mem7 q-mdw
                  q-memw0 q-memw1 q-memw2 q-memw3 q-memw4 q-memw5 q-memw6
                  q-memw7 a-fault a-lock-seen a-offer a-offer-write a-poison
                  a-offer-slot a-reserved a-unissued a-readcount a-head a-tail
                  a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3
                  a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2
                  a-epoch3 a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0
                  a-reject1 a-reject2 a-reject3 a-reject4 a-reject5 a-reject6
                  a-reject7 a-done0 a-done1 a-done2 a-done3 a-done4 a-done5
                  a-done6 a-done7 a-sfault0 a-sfault1 a-sfault2 a-sfault3
                  a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0 a-word1
                  a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0
                  a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6
                  a-rslot7)
            (joint-inv-p
                  p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q
                  k-pending-issued-q k-pending-returned-q
                  k-pending-read-pending-q k-committed-prefix-q
                  k-pending-layer-q k-pending-position-q
                  k-pending-key-exponents-q k-pending-value-exponents-q
                  k-expected-coordinate-q k-pending-persisted-q k-write-head-q
                  k-write-word-q k-write-aborted-q k-response-kind-q
                  k-response-head-q k-response-layer-q k-response-position-q
                  k-response-fault-q k-response-from-pending-q k-read-word-q
                  k-read-return-word-q k-read-outstanding-q
                  k-read-issue-done-q k-read-aborted-q k-read-physical-kind-q
                  k-read-epoch-q k-read-received-mask-q k-cache-valid-q
                  k-cache-kind-q k-cache-layer-q k-cache-position-q
                  k-cache-tag-epoch-q k-cache-epoch-q k-cache-clear-seen-q
                  k-cache-issued-q k-cache-returned-q k-cache-read-pending-q
                  k-cache-copy-kind-q k-lock-seen-q k-fault-q
                  k-stage-begin-consumed-q k-stage-payload-consumed-q
                  k-commit-consumed-q k-attention-req-consumed-q b-crel b-arel
                  b-lock-meta b-lock-sync b-afc-meta b-afc-sync b-cfa-meta
                  b-cfa-sync b-fault b-lock-seen b-clr-seen b-clr-pend
                  b-clr-drained b-epoch b-out b-mstall b-wstall b-wstallf
                  b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2
                  q-mv q-sf q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3
                  q-mem4 q-mem5 q-mem6 q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1
                  s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st s-md s-mem0
                  s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6 s-mem7 q-mdw
                  q-memw0 q-memw1 q-memw2 q-memw3 q-memw4 q-memw5 q-memw6
                  q-memw7 a-fault a-lock-seen a-offer a-offer-write a-poison
                  a-offer-slot a-reserved a-unissued a-readcount a-head a-tail
                  a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3
                  a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2
                  a-epoch3 a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0
                  a-reject1 a-reject2 a-reject3 a-reject4 a-reject5 a-reject6
                  a-reject7 a-done0 a-done1 a-done2 a-done3 a-done4 a-done5
                  a-done6 a-done7 a-sfault0 a-sfault1 a-sfault2 a-sfault3
                  a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0 a-word1
                  a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0
                  a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6
                  a-rslot7))
  :concl (kv-requests-owned-p b-out
                              (logand 15 (- q-wb q-rb))
                              a-reserved
                              (logand 15 (- s-wb s-rb))
                              (kv-in-flight k-state-q k-read-outstanding-q))
  :rule-classes nil)

(defthm kvj-invariant-gives-no-fault-and-ownership
  (implies (kv-invariant-at n outs)
           (and (kv-no-fault-at n outs)
                (kv-requests-owned-at n outs)))
  :hints (("Goal"
           :use ((:instance joint-inv-implies-no-fault
                       (p-lock-meta (sig "model_lock_core_meta_q" 1 (nth n outs)))
                       (p-lock-sync (sig "model_lock_core_sync_q" 1 (nth n outs)))
                       (p-cfb (sig "core_fault_to_boundary_q" 1 (nth n outs)))
                       (p-apprel (sig "app_runtime_release_q" 3 (nth n outs)))
                       (m-rel (sig "u_machine.machine_release_q" 2 (nth n outs)))
                       (k-state-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" 4 (nth n outs)))
                       (k-pending-issued-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_issued_q" 4 (nth n outs)))
                       (k-pending-returned-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_returned_q" 3 (nth n outs)))
                       (k-pending-read-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_read_pending_q" 1 (nth n outs)))
                       (k-committed-prefix-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.committed_prefix_q" 72 (nth n outs)))
                       (k-pending-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_layer_q" 3 (nth n outs)))
                       (k-pending-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_position_q" 12 (nth n outs)))
                       (k-pending-key-exponents-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_key_exponents_q" 16 (nth n outs)))
                       (k-pending-value-exponents-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_value_exponents_q" 16 (nth n outs)))
                       (k-expected-coordinate-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.expected_coordinate_q" 7 (nth n outs)))
                       (k-pending-persisted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_persisted_q" 1 (nth n outs)))
                       (k-write-head-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_head_q" 1 (nth n outs)))
                       (k-write-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_word_q" 4 (nth n outs)))
                       (k-write-aborted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_aborted_q" 1 (nth n outs)))
                       (k-response-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_kind_q" 2 (nth n outs)))
                       (k-response-head-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_head_q" 1 (nth n outs)))
                       (k-response-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_layer_q" 3 (nth n outs)))
                       (k-response-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_position_q" 12 (nth n outs)))
                       (k-response-fault-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_fault_q" 1 (nth n outs)))
                       (k-response-from-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_from_pending_q" 1 (nth n outs)))
                       (k-read-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_word_q" 4 (nth n outs)))
                       (k-read-return-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_return_word_q" 4 (nth n outs)))
                       (k-read-outstanding-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_outstanding_q" 4 (nth n outs)))
                       (k-read-issue-done-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_issue_done_q" 1 (nth n outs)))
                       (k-read-aborted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_aborted_q" 1 (nth n outs)))
                       (k-read-physical-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_physical_kind_q" 1 (nth n outs)))
                       (k-read-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_epoch_q" 1 (nth n outs)))
                       (k-read-received-mask-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_received_mask_q" 9 (nth n outs)))
                       (k-cache-valid-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_valid_q" 1 (nth n outs)))
                       (k-cache-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_kind_q" 1 (nth n outs)))
                       (k-cache-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_layer_q" 3 (nth n outs)))
                       (k-cache-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_position_q" 12 (nth n outs)))
                       (k-cache-tag-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_tag_epoch_q" 1 (nth n outs)))
                       (k-cache-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_epoch_q" 1 (nth n outs)))
                       (k-cache-clear-seen-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_clear_seen_q" 1 (nth n outs)))
                       (k-cache-issued-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_issued_q" 3 (nth n outs)))
                       (k-cache-returned-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_returned_q" 3 (nth n outs)))
                       (k-cache-read-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_read_pending_q" 1 (nth n outs)))
                       (k-cache-copy-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_copy_kind_q" 1 (nth n outs)))
                       (k-lock-seen-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.lock_seen_q" 1 (nth n outs)))
                       (k-fault-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.fault_q" 1 (nth n outs)))
                       (k-stage-begin-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_consumed_q" 1 (nth n outs)))
                       (k-stage-payload-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_consumed_q" 1 (nth n outs)))
                       (k-commit-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.commit_consumed_q" 1 (nth n outs)))
                       (k-attention-req-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_consumed_q" 1 (nth n outs)))
                       (b-crel (sig "u_boundary.core_release_q" 3 (nth n outs)))
                       (b-arel (sig "u_boundary.app_release_q" 3 (nth n outs)))
                       (b-lock-meta (sig "u_boundary.model_lock_core_meta_q" 1 (nth n outs)))
                       (b-lock-sync (sig "u_boundary.model_lock_core_sync_q" 1 (nth n outs)))
                       (b-afc-meta (sig "u_boundary.app_fault_core_meta_q" 1 (nth n outs)))
                       (b-afc-sync (sig "u_boundary.app_fault_core_sync_q" 1 (nth n outs)))
                       (b-cfa-meta (sig "u_boundary.core_fault_app_meta_q" 1 (nth n outs)))
                       (b-cfa-sync (sig "u_boundary.core_fault_app_sync_q" 1 (nth n outs)))
                       (b-fault (sig "u_boundary.core_fault_q" 1 (nth n outs)))
                       (b-lock-seen (sig "u_boundary.core_lock_seen_q" 1 (nth n outs)))
                       (b-clr-seen (sig "u_boundary.core_clear_seen_q" 1 (nth n outs)))
                       (b-clr-pend (sig "u_boundary.core_clear_pending_q" 1 (nth n outs)))
                       (b-clr-drained (sig "boundary_core_clear_drained" 1 (nth n outs)))
                       (b-epoch (sig "u_boundary.core_epoch_q" 1 (nth n outs)))
                       (b-out (sig "u_boundary.core_outstanding_q" 4 (nth n outs)))
                       (b-mstall (sig "u_boundary.model_rsp_stalled_q" 1 (nth n outs)))
                       (b-wstall (sig "u_boundary.kv_write_cpl_stalled_q" 1 (nth n outs)))
                       (b-wstallf (sig "u_boundary.kv_write_cpl_stalled_fault_q" 1 (nth n outs)))
                       (b-rstall (sig "u_boundary.kv_read_rsp_stalled_q" 1 (nth n outs)))
                       (q-wb (sig "u_boundary.request_fifo_i.write_binary_q" 4 (nth n outs)))
                       (q-wg (sig "u_boundary.request_fifo_i.write_gray_q" 4 (nth n outs)))
                       (q-full (sig "u_boundary.request_fifo_i.write_full_q" 1 (nth n outs)))
                       (q-rb (sig "u_boundary.request_fifo_i.read_binary_q" 4 (nth n outs)))
                       (q-rg (sig "u_boundary.request_fifo_i.read_gray_q" 4 (nth n outs)))
                       (q-rs1 (sig "u_boundary.request_fifo_i.read_gray_sync1_q" 4 (nth n outs)))
                       (q-rs2 (sig "u_boundary.request_fifo_i.read_gray_sync2_q" 4 (nth n outs)))
                       (q-ws1 (sig "u_boundary.request_fifo_i.write_gray_sync1_q" 4 (nth n outs)))
                       (q-ws2 (sig "u_boundary.request_fifo_i.write_gray_sync2_q" 4 (nth n outs)))
                       (q-mv (sig "u_boundary.request_fifo_i.m_valid_q" 1 (nth n outs)))
                       (q-sf (sig "u_boundary.request_fifo_i.source_fault_q" 1 (nth n outs)))
                       (q-spf (sig "u_boundary.request_fifo_i.source_payload_fault_q" 40 (nth n outs)))
                       (q-df (sig "u_boundary.request_fifo_i.destination_fault_q" 1 (nth n outs)))
                       (q-st (sig "u_boundary.request_fifo_i.source_stalled_q" 1 (nth n outs)))
                       (q-md (sig "u_boundary.request_fifo_i.m_data_q" 3 (nth n outs) :lsb 315))
                       (q-mem0 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 2541))
                       (q-mem1 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 2223))
                       (q-mem2 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 1905))
                       (q-mem3 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 1587))
                       (q-mem4 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 1269))
                       (q-mem5 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 951))
                       (q-mem6 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 633))
                       (q-mem7 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 315))
                       (s-wb (sig "u_boundary.response_fifo_i.write_binary_q" 4 (nth n outs)))
                       (s-wg (sig "u_boundary.response_fifo_i.write_gray_q" 4 (nth n outs)))
                       (s-full (sig "u_boundary.response_fifo_i.write_full_q" 1 (nth n outs)))
                       (s-rb (sig "u_boundary.response_fifo_i.read_binary_q" 4 (nth n outs)))
                       (s-rg (sig "u_boundary.response_fifo_i.read_gray_q" 4 (nth n outs)))
                       (s-rs1 (sig "u_boundary.response_fifo_i.read_gray_sync1_q" 4 (nth n outs)))
                       (s-rs2 (sig "u_boundary.response_fifo_i.read_gray_sync2_q" 4 (nth n outs)))
                       (s-ws1 (sig "u_boundary.response_fifo_i.write_gray_sync1_q" 4 (nth n outs)))
                       (s-ws2 (sig "u_boundary.response_fifo_i.write_gray_sync2_q" 4 (nth n outs)))
                       (s-mv (sig "u_boundary.response_fifo_i.m_valid_q" 1 (nth n outs)))
                       (s-sf (sig "u_boundary.response_fifo_i.source_fault_q" 1 (nth n outs)))
                       (s-spf (sig "u_boundary.response_fifo_i.source_payload_fault_q" 33 (nth n outs)))
                       (s-df (sig "u_boundary.response_fifo_i.destination_fault_q" 1 (nth n outs)))
                       (s-st (sig "u_boundary.response_fifo_i.source_stalled_q" 1 (nth n outs)))
                       (s-md (sig "u_boundary.response_fifo_i.m_data_q" 4 (nth n outs) :lsb 256))
                       (s-mem0 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 2076))
                       (s-mem1 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1816))
                       (s-mem2 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1556))
                       (s-mem3 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1296))
                       (s-mem4 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1036))
                       (s-mem5 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 776))
                       (s-mem6 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 516))
                       (s-mem7 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 256))
                       (q-mdw (sig "u_boundary.request_fifo_i.m_data_q" 4 (nth n outs) :lsb 275))
                       (q-memw0 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 2501))
                       (q-memw1 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 2183))
                       (q-memw2 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 1865))
                       (q-memw3 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 1547))
                       (q-memw4 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 1229))
                       (q-memw5 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 911))
                       (q-memw6 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 593))
                       (q-memw7 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 275))
                       (a-fault (sig "u_boundary.app_boundary_i.fault_q" 1 (nth n outs)))
                       (a-lock-seen (sig "u_boundary.app_boundary_i.lock_seen_q" 1 (nth n outs)))
                       (a-offer (sig "u_boundary.app_boundary_i.offer_q" 1 (nth n outs)))
                       (a-offer-write (sig "u_boundary.app_boundary_i.offer_write_q" 1 (nth n outs)))
                       (a-poison (sig "u_boundary.app_boundary_i.offer_poison_q" 1 (nth n outs)))
                       (a-offer-slot (sig "u_boundary.app_boundary_i.offer_slot_q" 3 (nth n outs)))
                       (a-reserved (sig "u_boundary.app_boundary_i.reserved_q" 4 (nth n outs)))
                       (a-unissued (sig "u_boundary.app_boundary_i.unissued_q" 4 (nth n outs)))
                       (a-readcount (sig "u_boundary.app_boundary_i.read_count_q" 4 (nth n outs)))
                       (a-head (sig "u_boundary.app_boundary_i.head_q" 3 (nth n outs)))
                       (a-tail (sig "u_boundary.app_boundary_i.tail_q" 3 (nth n outs)))
                       (a-issue (sig "u_boundary.app_boundary_i.issue_q" 3 (nth n outs)))
                       (a-rhead (sig "u_boundary.app_boundary_i.read_head_q" 3 (nth n outs)))
                       (a-rtail (sig "u_boundary.app_boundary_i.read_tail_q" 3 (nth n outs)))
                       (a-kind0 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 14))
                       (a-kind1 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 12))
                       (a-kind2 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 10))
                       (a-kind3 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 8))
                       (a-kind4 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 6))
                       (a-kind5 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 4))
                       (a-kind6 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 2))
                       (a-kind7 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs)))
                       (a-epoch0 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 7))
                       (a-epoch1 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 6))
                       (a-epoch2 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 5))
                       (a-epoch3 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 4))
                       (a-epoch4 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 3))
                       (a-epoch5 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 2))
                       (a-epoch6 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 1))
                       (a-epoch7 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs)))
                       (a-reject0 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 7))
                       (a-reject1 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 6))
                       (a-reject2 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 5))
                       (a-reject3 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 4))
                       (a-reject4 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 3))
                       (a-reject5 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 2))
                       (a-reject6 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 1))
                       (a-reject7 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs)))
                       (a-done0 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 7))
                       (a-done1 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 6))
                       (a-done2 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 5))
                       (a-done3 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 4))
                       (a-done4 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 3))
                       (a-done5 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 2))
                       (a-done6 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 1))
                       (a-done7 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs)))
                       (a-sfault0 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 7))
                       (a-sfault1 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 6))
                       (a-sfault2 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 5))
                       (a-sfault3 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 4))
                       (a-sfault4 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 3))
                       (a-sfault5 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 2))
                       (a-sfault6 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 1))
                       (a-sfault7 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs)))
                       (a-word0 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 28))
                       (a-word1 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 24))
                       (a-word2 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 20))
                       (a-word3 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 16))
                       (a-word4 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 12))
                       (a-word5 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 8))
                       (a-word6 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 4))
                       (a-word7 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs)))
                       (a-rslot0 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 21))
                       (a-rslot1 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 18))
                       (a-rslot2 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 15))
                       (a-rslot3 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 12))
                       (a-rslot4 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 9))
                       (a-rslot5 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 6))
                       (a-rslot6 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 3))
                       (a-rslot7 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs))))
                 (:instance joint-inv-implies-requests-owned
                       (p-lock-meta (sig "model_lock_core_meta_q" 1 (nth n outs)))
                       (p-lock-sync (sig "model_lock_core_sync_q" 1 (nth n outs)))
                       (p-cfb (sig "core_fault_to_boundary_q" 1 (nth n outs)))
                       (p-apprel (sig "app_runtime_release_q" 3 (nth n outs)))
                       (m-rel (sig "u_machine.machine_release_q" 2 (nth n outs)))
                       (k-state-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.state_q" 4 (nth n outs)))
                       (k-pending-issued-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_issued_q" 4 (nth n outs)))
                       (k-pending-returned-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_returned_q" 3 (nth n outs)))
                       (k-pending-read-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_read_pending_q" 1 (nth n outs)))
                       (k-committed-prefix-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.committed_prefix_q" 72 (nth n outs)))
                       (k-pending-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_layer_q" 3 (nth n outs)))
                       (k-pending-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_position_q" 12 (nth n outs)))
                       (k-pending-key-exponents-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_key_exponents_q" 16 (nth n outs)))
                       (k-pending-value-exponents-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_value_exponents_q" 16 (nth n outs)))
                       (k-expected-coordinate-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.expected_coordinate_q" 7 (nth n outs)))
                       (k-pending-persisted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.pending_persisted_q" 1 (nth n outs)))
                       (k-write-head-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_head_q" 1 (nth n outs)))
                       (k-write-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_word_q" 4 (nth n outs)))
                       (k-write-aborted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.write_aborted_q" 1 (nth n outs)))
                       (k-response-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_kind_q" 2 (nth n outs)))
                       (k-response-head-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_head_q" 1 (nth n outs)))
                       (k-response-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_layer_q" 3 (nth n outs)))
                       (k-response-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_position_q" 12 (nth n outs)))
                       (k-response-fault-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_fault_q" 1 (nth n outs)))
                       (k-response-from-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.response_from_pending_q" 1 (nth n outs)))
                       (k-read-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_word_q" 4 (nth n outs)))
                       (k-read-return-word-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_return_word_q" 4 (nth n outs)))
                       (k-read-outstanding-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_outstanding_q" 4 (nth n outs)))
                       (k-read-issue-done-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_issue_done_q" 1 (nth n outs)))
                       (k-read-aborted-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_aborted_q" 1 (nth n outs)))
                       (k-read-physical-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_physical_kind_q" 1 (nth n outs)))
                       (k-read-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_epoch_q" 1 (nth n outs)))
                       (k-read-received-mask-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.read_received_mask_q" 9 (nth n outs)))
                       (k-cache-valid-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_valid_q" 1 (nth n outs)))
                       (k-cache-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_kind_q" 1 (nth n outs)))
                       (k-cache-layer-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_layer_q" 3 (nth n outs)))
                       (k-cache-position-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_position_q" 12 (nth n outs)))
                       (k-cache-tag-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_tag_epoch_q" 1 (nth n outs)))
                       (k-cache-epoch-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_epoch_q" 1 (nth n outs)))
                       (k-cache-clear-seen-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_clear_seen_q" 1 (nth n outs)))
                       (k-cache-issued-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_issued_q" 3 (nth n outs)))
                       (k-cache-returned-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_returned_q" 3 (nth n outs)))
                       (k-cache-read-pending-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_read_pending_q" 1 (nth n outs)))
                       (k-cache-copy-kind-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.cache_copy_kind_q" 1 (nth n outs)))
                       (k-lock-seen-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.lock_seen_q" 1 (nth n outs)))
                       (k-fault-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.fault_q" 1 (nth n outs)))
                       (k-stage-begin-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.stage_begin_consumed_q" 1 (nth n outs)))
                       (k-stage-payload-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.stage_payload_consumed_q" 1 (nth n outs)))
                       (k-commit-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.commit_consumed_q" 1 (nth n outs)))
                       (k-attention-req-consumed-q (sig "u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_consumed_q" 1 (nth n outs)))
                       (b-crel (sig "u_boundary.core_release_q" 3 (nth n outs)))
                       (b-arel (sig "u_boundary.app_release_q" 3 (nth n outs)))
                       (b-lock-meta (sig "u_boundary.model_lock_core_meta_q" 1 (nth n outs)))
                       (b-lock-sync (sig "u_boundary.model_lock_core_sync_q" 1 (nth n outs)))
                       (b-afc-meta (sig "u_boundary.app_fault_core_meta_q" 1 (nth n outs)))
                       (b-afc-sync (sig "u_boundary.app_fault_core_sync_q" 1 (nth n outs)))
                       (b-cfa-meta (sig "u_boundary.core_fault_app_meta_q" 1 (nth n outs)))
                       (b-cfa-sync (sig "u_boundary.core_fault_app_sync_q" 1 (nth n outs)))
                       (b-fault (sig "u_boundary.core_fault_q" 1 (nth n outs)))
                       (b-lock-seen (sig "u_boundary.core_lock_seen_q" 1 (nth n outs)))
                       (b-clr-seen (sig "u_boundary.core_clear_seen_q" 1 (nth n outs)))
                       (b-clr-pend (sig "u_boundary.core_clear_pending_q" 1 (nth n outs)))
                       (b-clr-drained (sig "boundary_core_clear_drained" 1 (nth n outs)))
                       (b-epoch (sig "u_boundary.core_epoch_q" 1 (nth n outs)))
                       (b-out (sig "u_boundary.core_outstanding_q" 4 (nth n outs)))
                       (b-mstall (sig "u_boundary.model_rsp_stalled_q" 1 (nth n outs)))
                       (b-wstall (sig "u_boundary.kv_write_cpl_stalled_q" 1 (nth n outs)))
                       (b-wstallf (sig "u_boundary.kv_write_cpl_stalled_fault_q" 1 (nth n outs)))
                       (b-rstall (sig "u_boundary.kv_read_rsp_stalled_q" 1 (nth n outs)))
                       (q-wb (sig "u_boundary.request_fifo_i.write_binary_q" 4 (nth n outs)))
                       (q-wg (sig "u_boundary.request_fifo_i.write_gray_q" 4 (nth n outs)))
                       (q-full (sig "u_boundary.request_fifo_i.write_full_q" 1 (nth n outs)))
                       (q-rb (sig "u_boundary.request_fifo_i.read_binary_q" 4 (nth n outs)))
                       (q-rg (sig "u_boundary.request_fifo_i.read_gray_q" 4 (nth n outs)))
                       (q-rs1 (sig "u_boundary.request_fifo_i.read_gray_sync1_q" 4 (nth n outs)))
                       (q-rs2 (sig "u_boundary.request_fifo_i.read_gray_sync2_q" 4 (nth n outs)))
                       (q-ws1 (sig "u_boundary.request_fifo_i.write_gray_sync1_q" 4 (nth n outs)))
                       (q-ws2 (sig "u_boundary.request_fifo_i.write_gray_sync2_q" 4 (nth n outs)))
                       (q-mv (sig "u_boundary.request_fifo_i.m_valid_q" 1 (nth n outs)))
                       (q-sf (sig "u_boundary.request_fifo_i.source_fault_q" 1 (nth n outs)))
                       (q-spf (sig "u_boundary.request_fifo_i.source_payload_fault_q" 40 (nth n outs)))
                       (q-df (sig "u_boundary.request_fifo_i.destination_fault_q" 1 (nth n outs)))
                       (q-st (sig "u_boundary.request_fifo_i.source_stalled_q" 1 (nth n outs)))
                       (q-md (sig "u_boundary.request_fifo_i.m_data_q" 3 (nth n outs) :lsb 315))
                       (q-mem0 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 2541))
                       (q-mem1 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 2223))
                       (q-mem2 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 1905))
                       (q-mem3 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 1587))
                       (q-mem4 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 1269))
                       (q-mem5 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 951))
                       (q-mem6 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 633))
                       (q-mem7 (sig "u_boundary.request_fifo_i.memory_q" 3 (nth n outs) :lsb 315))
                       (s-wb (sig "u_boundary.response_fifo_i.write_binary_q" 4 (nth n outs)))
                       (s-wg (sig "u_boundary.response_fifo_i.write_gray_q" 4 (nth n outs)))
                       (s-full (sig "u_boundary.response_fifo_i.write_full_q" 1 (nth n outs)))
                       (s-rb (sig "u_boundary.response_fifo_i.read_binary_q" 4 (nth n outs)))
                       (s-rg (sig "u_boundary.response_fifo_i.read_gray_q" 4 (nth n outs)))
                       (s-rs1 (sig "u_boundary.response_fifo_i.read_gray_sync1_q" 4 (nth n outs)))
                       (s-rs2 (sig "u_boundary.response_fifo_i.read_gray_sync2_q" 4 (nth n outs)))
                       (s-ws1 (sig "u_boundary.response_fifo_i.write_gray_sync1_q" 4 (nth n outs)))
                       (s-ws2 (sig "u_boundary.response_fifo_i.write_gray_sync2_q" 4 (nth n outs)))
                       (s-mv (sig "u_boundary.response_fifo_i.m_valid_q" 1 (nth n outs)))
                       (s-sf (sig "u_boundary.response_fifo_i.source_fault_q" 1 (nth n outs)))
                       (s-spf (sig "u_boundary.response_fifo_i.source_payload_fault_q" 33 (nth n outs)))
                       (s-df (sig "u_boundary.response_fifo_i.destination_fault_q" 1 (nth n outs)))
                       (s-st (sig "u_boundary.response_fifo_i.source_stalled_q" 1 (nth n outs)))
                       (s-md (sig "u_boundary.response_fifo_i.m_data_q" 4 (nth n outs) :lsb 256))
                       (s-mem0 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 2076))
                       (s-mem1 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1816))
                       (s-mem2 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1556))
                       (s-mem3 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1296))
                       (s-mem4 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 1036))
                       (s-mem5 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 776))
                       (s-mem6 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 516))
                       (s-mem7 (sig "u_boundary.response_fifo_i.memory_q" 4 (nth n outs) :lsb 256))
                       (q-mdw (sig "u_boundary.request_fifo_i.m_data_q" 4 (nth n outs) :lsb 275))
                       (q-memw0 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 2501))
                       (q-memw1 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 2183))
                       (q-memw2 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 1865))
                       (q-memw3 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 1547))
                       (q-memw4 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 1229))
                       (q-memw5 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 911))
                       (q-memw6 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 593))
                       (q-memw7 (sig "u_boundary.request_fifo_i.memory_q" 4 (nth n outs) :lsb 275))
                       (a-fault (sig "u_boundary.app_boundary_i.fault_q" 1 (nth n outs)))
                       (a-lock-seen (sig "u_boundary.app_boundary_i.lock_seen_q" 1 (nth n outs)))
                       (a-offer (sig "u_boundary.app_boundary_i.offer_q" 1 (nth n outs)))
                       (a-offer-write (sig "u_boundary.app_boundary_i.offer_write_q" 1 (nth n outs)))
                       (a-poison (sig "u_boundary.app_boundary_i.offer_poison_q" 1 (nth n outs)))
                       (a-offer-slot (sig "u_boundary.app_boundary_i.offer_slot_q" 3 (nth n outs)))
                       (a-reserved (sig "u_boundary.app_boundary_i.reserved_q" 4 (nth n outs)))
                       (a-unissued (sig "u_boundary.app_boundary_i.unissued_q" 4 (nth n outs)))
                       (a-readcount (sig "u_boundary.app_boundary_i.read_count_q" 4 (nth n outs)))
                       (a-head (sig "u_boundary.app_boundary_i.head_q" 3 (nth n outs)))
                       (a-tail (sig "u_boundary.app_boundary_i.tail_q" 3 (nth n outs)))
                       (a-issue (sig "u_boundary.app_boundary_i.issue_q" 3 (nth n outs)))
                       (a-rhead (sig "u_boundary.app_boundary_i.read_head_q" 3 (nth n outs)))
                       (a-rtail (sig "u_boundary.app_boundary_i.read_tail_q" 3 (nth n outs)))
                       (a-kind0 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 14))
                       (a-kind1 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 12))
                       (a-kind2 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 10))
                       (a-kind3 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 8))
                       (a-kind4 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 6))
                       (a-kind5 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 4))
                       (a-kind6 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs) :lsb 2))
                       (a-kind7 (sig "u_boundary.app_boundary_i.slot_kind_q" 2 (nth n outs)))
                       (a-epoch0 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 7))
                       (a-epoch1 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 6))
                       (a-epoch2 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 5))
                       (a-epoch3 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 4))
                       (a-epoch4 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 3))
                       (a-epoch5 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 2))
                       (a-epoch6 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs) :lsb 1))
                       (a-epoch7 (sig "u_boundary.app_boundary_i.slot_epoch_q" 1 (nth n outs)))
                       (a-reject0 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 7))
                       (a-reject1 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 6))
                       (a-reject2 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 5))
                       (a-reject3 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 4))
                       (a-reject4 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 3))
                       (a-reject5 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 2))
                       (a-reject6 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs) :lsb 1))
                       (a-reject7 (sig "u_boundary.app_boundary_i.slot_reject_q" 1 (nth n outs)))
                       (a-done0 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 7))
                       (a-done1 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 6))
                       (a-done2 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 5))
                       (a-done3 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 4))
                       (a-done4 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 3))
                       (a-done5 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 2))
                       (a-done6 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs) :lsb 1))
                       (a-done7 (sig "u_boundary.app_boundary_i.slot_done_q" 1 (nth n outs)))
                       (a-sfault0 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 7))
                       (a-sfault1 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 6))
                       (a-sfault2 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 5))
                       (a-sfault3 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 4))
                       (a-sfault4 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 3))
                       (a-sfault5 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 2))
                       (a-sfault6 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs) :lsb 1))
                       (a-sfault7 (sig "u_boundary.app_boundary_i.slot_fault_q" 1 (nth n outs)))
                       (a-word0 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 28))
                       (a-word1 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 24))
                       (a-word2 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 20))
                       (a-word3 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 16))
                       (a-word4 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 12))
                       (a-word5 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 8))
                       (a-word6 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs) :lsb 4))
                       (a-word7 (sig "u_boundary.app_boundary_i.slot_word_q" 4 (nth n outs)))
                       (a-rslot0 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 21))
                       (a-rslot1 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 18))
                       (a-rslot2 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 15))
                       (a-rslot3 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 12))
                       (a-rslot4 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 9))
                       (a-rslot5 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 6))
                       (a-rslot6 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs) :lsb 3))
                       (a-rslot7 (sig "u_boundary.app_boundary_i.read_slot_q" 3 (nth n outs)))))
           :in-theory (e/d (kv-invariant-at kv-no-fault-at kv-requests-owned-at)
                           (unsigned-byte-p nth nthcdr take len)))))

; ===========================================================================
; THE THEOREM.
;
; Take any execution of the probe module's state machine, from any initial
; state.  Suppose reset_n_i is low in cycles r, r+1 and r+2, and the
; environment behaves in every cycle from r+2 up to but not including n.
; Then in cycle n:
;   - the K/V controller has no fault latched and is in a defined state;
;   - every request in flight is owned by exactly one place, and the counts
;     agree;
;   - the whole invariant holds, of which those two are consequences;
;   - and if the environment behaves in cycle n as well, a fault flag on a
;     write completion or on a read response in that cycle is explained by a
;     CLEAR, and terminal_fault_event is low.
; CLEAR is unconstrained throughout, and so are the client's stage, commit
; and read requests.
; ===========================================================================
(defthm kv-joined-guarantee
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-environment-ok-from (+ 2 r) n envs outs))
             (and (kv-no-fault-at n outs)
                  (kv-requests-owned-at n outs)
                  (kv-invariant-at n outs)
                  (implies (kv-environment-ok-at n envs outs)
                           (kv-fault-flag-explained-at n outs)))))
  :hints (("Goal"
           :use ((:instance join-inv-from-reset)
                 (:instance kvj-reset-connects
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-invariant-connects
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-invariant-gives-no-fault-and-ownership
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-connects
                  (k n) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-step-glue (k n))
                 (:instance kvj-clause-connects
                  (k n) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (disable join-inv-from-reset join-step-glue join-inv-preserved
                               join-reset-glue kvj-reset-connects
                               kvj-environment-from-connects kvj-invariant-connects
                               kvj-invariant-gives-no-fault-and-ownership
                               kvj-environment-connects kvj-clause-connects
                               join-j-at join-reset-at join-env-from join-env-at
                               join-clause-at fsm-eval (probe-fsm) probe-fsm)))
  :rule-classes nil)

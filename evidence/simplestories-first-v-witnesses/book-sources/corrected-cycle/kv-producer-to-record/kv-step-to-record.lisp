; One accepted public STEP, its producer results, and the eighteen endpoint writes: the theorem.
;
; Written by make_step_book.py; do not edit.  Private.
;
; THE CLAIM.  Take any execution of the probe module
; (board1_context2048_shared_token_probe, pinned RTL), from any initial
; state, with the hypotheses of the three links.  Whenever the K/V
; controller reports a completed record, its eighteen accepted writes at
; private_kv_req_* encode the K rotary and V projection results that the
; datapath's normalizer handed over, and the datapath accepted, in one pass
; of the sequencer for the record's layer and position; and that pass was
; started by the shell while it was working on one accepted public STEP,
; identified by its handshake cycle.  This is kv-step-to-record, at the end
; of this file; kv-step-to-record-layer-0-position-0 is its case for layer 0
; and token position 0.
;
; THE LINKS.
;   kv-staging-to-record    (first link, certified on its own) the eighteen
;                           writes are the reference record of one accepted
;                           staging begin and its 128 accepted transfers
;   kv-producer-to-record   (second link, kv-producer-link.lisp) those
;                           transfers are the final accepted K and V
;                           results of one pass of the sequencer
;   shl-pass-is-in-a-step   (third link, here) that pass lies inside the
;                           shell's work on one accepted public STEP
(in-package "SV")
(include-book "kv-producer-link")
(include-book "kv-shell-lift")
(acl2::set-slow-alist-action nil)
(value-triple (acl2::tshell-ensure))

; ---------------------------------------------------------------------------
; THE SHELL'S SIGNALS OF A CYCLE, by the two lifted lemmas' own bindings.
; ---------------------------------------------------------------------------
(defun shl-accessor-events (prefix names formals bindings vars)
  (declare (xargs :mode :program) (irrelevant vars))
  (if (atom names) nil
    (cons `(defun ,(intern-in-package-of-symbol
                    (concatenate 'string prefix (symbol-name (car names))) (car names))
             ,formals
             (declare (xargs :verify-guards nil) (ignorable ,@formals))
             ,(cadr (assoc-eq (car names) bindings)))
          (shl-accessor-events prefix (cdr names) formals bindings vars))))
(defun shl-accessor-names (prefix names)
  (declare (xargs :mode :program))
  (if (atom names) nil
    (cons (intern-in-package-of-symbol
           (concatenate 'string prefix (symbol-name (car names))) (car names))
          (shl-accessor-names prefix (cdr names)))))
(make-event
 (b* ((ev (acl2::get-event 'shl0-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (names '(h-arbfail h-dbusy h-layerfail h-shellterm h-srman h-tabusy h-tchild h-tclpm h-tcpm h-tebusy h-tlock h-tpriv h-tpub h-trbusy h-twatch h-ufc i-append i-clear i-reset-n i-step o-appendready o-sdf o-sfire o-sfpos o-shellfail o-stepready r-d-fault r-l-coll r-m-rel r-p-lock-sync r-s-fault r-s-rexp r-s-sidx r-s-state r-t-cidx r-t-committed r-t-eread r-t-fail r-t-l5exp r-t-lastvalid r-t-owner r-t-replay r-t-sidx r-t-state r-t-tape)))
   (cons 'progn
         (append
          (shl-accessor-events "SHL0$" names formals bindings vars)
          (list `(in-theory (disable ,@(shl-accessor-names "SHL0$" names))))))))
(make-event
 (b* ((ev (acl2::get-event 'shl1-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (names '(h-arbfail h-dbusy h-layerfail h-shellterm h-srman h-tabusy h-tchild h-tclpm h-tcpm h-tebusy h-tlock h-tpriv h-tpub h-trbusy h-twatch h-ufc i-append i-clear i-reset-n i-step n-m-rel n-t-state o-dpclear o-dprst o-sdf o-sfire o-shellfail o-stepready r-d-fault r-l-coll r-m-rel r-p-lock-sync r-s-fault r-s-rexp r-s-sidx r-s-state r-t-cidx r-t-committed r-t-eread r-t-fail r-t-l5exp r-t-lastvalid r-t-owner r-t-replay r-t-sidx r-t-state r-t-tape)))
   (cons 'progn
         (append
          (shl-accessor-events "SHL1$" names formals bindings vars)
          (list `(in-theory (disable ,@(shl-accessor-names "SHL1$" names))))))))
; Each signal as a function of the cycle.
(define shl-h-arbfail-at (k outs) :verify-guards nil (shl1$h-arbfail k k nil outs))
(define shl-h-dbusy-at (k outs) :verify-guards nil (shl1$h-dbusy k k nil outs))
(define shl-h-layerfail-at (k outs) :verify-guards nil (shl1$h-layerfail k k nil outs))
(define shl-h-shellterm-at (k outs) :verify-guards nil (shl1$h-shellterm k k nil outs))
(define shl-h-srman-at (k outs) :verify-guards nil (shl1$h-srman k k nil outs))
(define shl-h-tabusy-at (k outs) :verify-guards nil (shl1$h-tabusy k k nil outs))
(define shl-h-tchild-at (k outs) :verify-guards nil (shl1$h-tchild k k nil outs))
(define shl-h-tclpm-at (k outs) :verify-guards nil (shl1$h-tclpm k k nil outs))
(define shl-h-tcpm-at (k outs) :verify-guards nil (shl1$h-tcpm k k nil outs))
(define shl-h-tebusy-at (k outs) :verify-guards nil (shl1$h-tebusy k k nil outs))
(define shl-h-tlock-at (k outs) :verify-guards nil (shl1$h-tlock k k nil outs))
(define shl-h-tpriv-at (k outs) :verify-guards nil (shl1$h-tpriv k k nil outs))
(define shl-h-tpub-at (k outs) :verify-guards nil (shl1$h-tpub k k nil outs))
(define shl-h-trbusy-at (k outs) :verify-guards nil (shl1$h-trbusy k k nil outs))
(define shl-h-twatch-at (k outs) :verify-guards nil (shl1$h-twatch k k nil outs))
(define shl-h-ufc-at (k outs) :verify-guards nil (shl1$h-ufc k k nil outs))
(define shl-i-append-at (k envs) :verify-guards nil (shl1$i-append k k envs nil))
(define shl-i-clear-at (k envs) :verify-guards nil (shl1$i-clear k k envs nil))
(define shl-i-reset-n-at (k envs) :verify-guards nil (shl1$i-reset-n k k envs nil))
(define shl-i-step-at (k envs) :verify-guards nil (shl1$i-step k k envs nil))
(define shl-m-rel-at (k outs) :verify-guards nil (shl1$r-m-rel k k nil outs))
(define shl-t-state-at (k outs) :verify-guards nil (shl1$r-t-state k k nil outs))
(define shl-o-appendready-at (k outs) :verify-guards nil (shl0$o-appendready k k nil outs))
(define shl-o-dpclear-at (k outs) :verify-guards nil (shl1$o-dpclear k k nil outs))
(define shl-o-dprst-at (k outs) :verify-guards nil (shl1$o-dprst k k nil outs))
(define shl-o-sdf-at (k outs) :verify-guards nil (shl1$o-sdf k k nil outs))
(define shl-o-sfire-at (k outs) :verify-guards nil (shl1$o-sfire k k nil outs))
(define shl-o-sfpos-at (k outs) :verify-guards nil (shl0$o-sfpos k k nil outs))
(define shl-o-shellfail-at (k outs) :verify-guards nil (shl1$o-shellfail k k nil outs))
(define shl-o-stepready-at (k outs) :verify-guards nil (shl1$o-stepready k k nil outs))
(define shl-d-fault-at (k outs) :verify-guards nil (shl1$r-d-fault k k nil outs))
(define shl-l-coll-at (k outs) :verify-guards nil (shl1$r-l-coll k k nil outs))
(define shl-p-lock-sync-at (k outs) :verify-guards nil (shl1$r-p-lock-sync k k nil outs))
(define shl-s-fault-at (k outs) :verify-guards nil (shl1$r-s-fault k k nil outs))
(define shl-s-rexp-at (k outs) :verify-guards nil (shl1$r-s-rexp k k nil outs))
(define shl-s-sidx-at (k outs) :verify-guards nil (shl1$r-s-sidx k k nil outs))
(define shl-s-state-at (k outs) :verify-guards nil (shl1$r-s-state k k nil outs))
(define shl-t-cidx-at (k outs) :verify-guards nil (shl1$r-t-cidx k k nil outs))
(define shl-t-committed-at (k outs) :verify-guards nil (shl1$r-t-committed k k nil outs))
(define shl-t-eread-at (k outs) :verify-guards nil (shl1$r-t-eread k k nil outs))
(define shl-t-fail-at (k outs) :verify-guards nil (shl1$r-t-fail k k nil outs))
(define shl-t-l5exp-at (k outs) :verify-guards nil (shl1$r-t-l5exp k k nil outs))
(define shl-t-lastvalid-at (k outs) :verify-guards nil (shl1$r-t-lastvalid k k nil outs))
(define shl-t-owner-at (k outs) :verify-guards nil (shl1$r-t-owner k k nil outs))
(define shl-t-replay-at (k outs) :verify-guards nil (shl1$r-t-replay k k nil outs))
(define shl-t-sidx-at (k outs) :verify-guards nil (shl1$r-t-sidx k k nil outs))
(define shl-t-tape-at (k outs) :verify-guards nil (shl1$r-t-tape k k nil outs))
(in-theory (disable shl-h-arbfail-at shl-h-dbusy-at shl-h-layerfail-at shl-h-shellterm-at shl-h-srman-at shl-h-tabusy-at shl-h-tchild-at shl-h-tclpm-at shl-h-tcpm-at shl-h-tebusy-at shl-h-tlock-at shl-h-tpriv-at shl-h-tpub-at shl-h-trbusy-at shl-h-twatch-at shl-h-ufc-at shl-i-append-at shl-i-clear-at shl-i-reset-n-at shl-i-step-at shl-m-rel-at shl-t-state-at shl-o-appendready-at shl-o-dpclear-at shl-o-dprst-at shl-o-sdf-at shl-o-sfire-at shl-o-sfpos-at shl-o-shellfail-at shl-o-stepready-at shl-d-fault-at shl-l-coll-at shl-p-lock-sync-at shl-s-fault-at shl-s-rexp-at shl-s-sidx-at shl-s-state-at shl-t-cidx-at shl-t-committed-at shl-t-eread-at shl-t-fail-at shl-t-l5exp-at shl-t-lastvalid-at shl-t-owner-at shl-t-replay-at shl-t-sidx-at shl-t-tape-at))
(defthm shl0$h-arbfail-is-at
  (equal (shl0$h-arbfail k (+ 1 k) envs outs) (shl-h-arbfail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-arbfail shl1$h-arbfail shl-h-arbfail-at) (nth nthcdr take len)))))
(defthm shl0$h-dbusy-is-at
  (equal (shl0$h-dbusy k (+ 1 k) envs outs) (shl-h-dbusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-dbusy shl1$h-dbusy shl-h-dbusy-at) (nth nthcdr take len)))))
(defthm shl0$h-layerfail-is-at
  (equal (shl0$h-layerfail k (+ 1 k) envs outs) (shl-h-layerfail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-layerfail shl1$h-layerfail shl-h-layerfail-at) (nth nthcdr take len)))))
(defthm shl0$h-shellterm-is-at
  (equal (shl0$h-shellterm k (+ 1 k) envs outs) (shl-h-shellterm-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-shellterm shl1$h-shellterm shl-h-shellterm-at) (nth nthcdr take len)))))
(defthm shl0$h-srman-is-at
  (equal (shl0$h-srman k (+ 1 k) envs outs) (shl-h-srman-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-srman shl1$h-srman shl-h-srman-at) (nth nthcdr take len)))))
(defthm shl0$h-tabusy-is-at
  (equal (shl0$h-tabusy k (+ 1 k) envs outs) (shl-h-tabusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tabusy shl1$h-tabusy shl-h-tabusy-at) (nth nthcdr take len)))))
(defthm shl0$h-tchild-is-at
  (equal (shl0$h-tchild k (+ 1 k) envs outs) (shl-h-tchild-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tchild shl1$h-tchild shl-h-tchild-at) (nth nthcdr take len)))))
(defthm shl0$h-tclpm-is-at
  (equal (shl0$h-tclpm k (+ 1 k) envs outs) (shl-h-tclpm-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tclpm shl1$h-tclpm shl-h-tclpm-at) (nth nthcdr take len)))))
(defthm shl0$h-tcpm-is-at
  (equal (shl0$h-tcpm k (+ 1 k) envs outs) (shl-h-tcpm-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tcpm shl1$h-tcpm shl-h-tcpm-at) (nth nthcdr take len)))))
(defthm shl0$h-tebusy-is-at
  (equal (shl0$h-tebusy k (+ 1 k) envs outs) (shl-h-tebusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tebusy shl1$h-tebusy shl-h-tebusy-at) (nth nthcdr take len)))))
(defthm shl0$h-tlock-is-at
  (equal (shl0$h-tlock k (+ 1 k) envs outs) (shl-h-tlock-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tlock shl1$h-tlock shl-h-tlock-at) (nth nthcdr take len)))))
(defthm shl0$h-tpriv-is-at
  (equal (shl0$h-tpriv k (+ 1 k) envs outs) (shl-h-tpriv-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tpriv shl1$h-tpriv shl-h-tpriv-at) (nth nthcdr take len)))))
(defthm shl0$h-tpub-is-at
  (equal (shl0$h-tpub k (+ 1 k) envs outs) (shl-h-tpub-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-tpub shl1$h-tpub shl-h-tpub-at) (nth nthcdr take len)))))
(defthm shl0$h-trbusy-is-at
  (equal (shl0$h-trbusy k (+ 1 k) envs outs) (shl-h-trbusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-trbusy shl1$h-trbusy shl-h-trbusy-at) (nth nthcdr take len)))))
(defthm shl0$h-twatch-is-at
  (equal (shl0$h-twatch k (+ 1 k) envs outs) (shl-h-twatch-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-twatch shl1$h-twatch shl-h-twatch-at) (nth nthcdr take len)))))
(defthm shl0$h-ufc-is-at
  (equal (shl0$h-ufc k (+ 1 k) envs outs) (shl-h-ufc-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$h-ufc shl1$h-ufc shl-h-ufc-at) (nth nthcdr take len)))))
(defthm shl0$i-append-is-at
  (equal (shl0$i-append k (+ 1 k) envs outs) (shl-i-append-at k envs))
  :hints (("Goal" :in-theory (e/d (shl0$i-append shl1$i-append shl-i-append-at) (nth nthcdr take len)))))
(defthm shl0$i-clear-is-at
  (equal (shl0$i-clear k (+ 1 k) envs outs) (shl-i-clear-at k envs))
  :hints (("Goal" :in-theory (e/d (shl0$i-clear shl1$i-clear shl-i-clear-at) (nth nthcdr take len)))))
(defthm shl0$i-reset-n-is-at
  (equal (shl0$i-reset-n k (+ 1 k) envs outs) (shl-i-reset-n-at k envs))
  :hints (("Goal" :in-theory (e/d (shl0$i-reset-n shl1$i-reset-n shl-i-reset-n-at) (nth nthcdr take len)))))
(defthm shl0$i-step-is-at
  (equal (shl0$i-step k (+ 1 k) envs outs) (shl-i-step-at k envs))
  :hints (("Goal" :in-theory (e/d (shl0$i-step shl1$i-step shl-i-step-at) (nth nthcdr take len)))))
(defthm shl0$o-appendready-is-at
  (equal (shl0$o-appendready k (+ 1 k) envs outs) (shl-o-appendready-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$o-appendready shl0$o-appendready shl-o-appendready-at) (nth nthcdr take len)))))
(defthm shl0$o-sdf-is-at
  (equal (shl0$o-sdf k (+ 1 k) envs outs) (shl-o-sdf-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$o-sdf shl1$o-sdf shl-o-sdf-at) (nth nthcdr take len)))))
(defthm shl0$o-sfire-is-at
  (equal (shl0$o-sfire k (+ 1 k) envs outs) (shl-o-sfire-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$o-sfire shl1$o-sfire shl-o-sfire-at) (nth nthcdr take len)))))
(defthm shl0$o-sfpos-is-at
  (equal (shl0$o-sfpos k (+ 1 k) envs outs) (shl-o-sfpos-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$o-sfpos shl0$o-sfpos shl-o-sfpos-at) (nth nthcdr take len)))))
(defthm shl0$o-shellfail-is-at
  (equal (shl0$o-shellfail k (+ 1 k) envs outs) (shl-o-shellfail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$o-shellfail shl1$o-shellfail shl-o-shellfail-at) (nth nthcdr take len)))))
(defthm shl0$o-stepready-is-at
  (equal (shl0$o-stepready k (+ 1 k) envs outs) (shl-o-stepready-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$o-stepready shl1$o-stepready shl-o-stepready-at) (nth nthcdr take len)))))
(defthm shl0$r-d-fault-is-at
  (equal (shl0$r-d-fault k (+ 1 k) envs outs) (shl-d-fault-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-d-fault shl1$r-d-fault shl-d-fault-at) (nth nthcdr take len)))))
(defthm shl0$r-l-coll-is-at
  (equal (shl0$r-l-coll k (+ 1 k) envs outs) (shl-l-coll-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-l-coll shl1$r-l-coll shl-l-coll-at) (nth nthcdr take len)))))
(defthm shl0$r-m-rel-is-at
  (equal (shl0$r-m-rel k (+ 1 k) envs outs) (shl-m-rel-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-m-rel shl1$r-m-rel shl-m-rel-at) (nth nthcdr take len)))))
(defthm shl0$r-p-lock-sync-is-at
  (equal (shl0$r-p-lock-sync k (+ 1 k) envs outs) (shl-p-lock-sync-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-p-lock-sync shl1$r-p-lock-sync shl-p-lock-sync-at) (nth nthcdr take len)))))
(defthm shl0$r-s-fault-is-at
  (equal (shl0$r-s-fault k (+ 1 k) envs outs) (shl-s-fault-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-s-fault shl1$r-s-fault shl-s-fault-at) (nth nthcdr take len)))))
(defthm shl0$r-s-rexp-is-at
  (equal (shl0$r-s-rexp k (+ 1 k) envs outs) (shl-s-rexp-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-s-rexp shl1$r-s-rexp shl-s-rexp-at) (nth nthcdr take len)))))
(defthm shl0$r-s-sidx-is-at
  (equal (shl0$r-s-sidx k (+ 1 k) envs outs) (shl-s-sidx-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-s-sidx shl1$r-s-sidx shl-s-sidx-at) (nth nthcdr take len)))))
(defthm shl0$r-s-state-is-at
  (equal (shl0$r-s-state k (+ 1 k) envs outs) (shl-s-state-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-s-state shl1$r-s-state shl-s-state-at) (nth nthcdr take len)))))
(defthm shl0$r-t-cidx-is-at
  (equal (shl0$r-t-cidx k (+ 1 k) envs outs) (shl-t-cidx-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-cidx shl1$r-t-cidx shl-t-cidx-at) (nth nthcdr take len)))))
(defthm shl0$r-t-committed-is-at
  (equal (shl0$r-t-committed k (+ 1 k) envs outs) (shl-t-committed-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-committed shl1$r-t-committed shl-t-committed-at) (nth nthcdr take len)))))
(defthm shl0$r-t-eread-is-at
  (equal (shl0$r-t-eread k (+ 1 k) envs outs) (shl-t-eread-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-eread shl1$r-t-eread shl-t-eread-at) (nth nthcdr take len)))))
(defthm shl0$r-t-fail-is-at
  (equal (shl0$r-t-fail k (+ 1 k) envs outs) (shl-t-fail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-fail shl1$r-t-fail shl-t-fail-at) (nth nthcdr take len)))))
(defthm shl0$r-t-l5exp-is-at
  (equal (shl0$r-t-l5exp k (+ 1 k) envs outs) (shl-t-l5exp-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-l5exp shl1$r-t-l5exp shl-t-l5exp-at) (nth nthcdr take len)))))
(defthm shl0$r-t-lastvalid-is-at
  (equal (shl0$r-t-lastvalid k (+ 1 k) envs outs) (shl-t-lastvalid-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-lastvalid shl1$r-t-lastvalid shl-t-lastvalid-at) (nth nthcdr take len)))))
(defthm shl0$r-t-owner-is-at
  (equal (shl0$r-t-owner k (+ 1 k) envs outs) (shl-t-owner-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-owner shl1$r-t-owner shl-t-owner-at) (nth nthcdr take len)))))
(defthm shl0$r-t-replay-is-at
  (equal (shl0$r-t-replay k (+ 1 k) envs outs) (shl-t-replay-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-replay shl1$r-t-replay shl-t-replay-at) (nth nthcdr take len)))))
(defthm shl0$r-t-sidx-is-at
  (equal (shl0$r-t-sidx k (+ 1 k) envs outs) (shl-t-sidx-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-sidx shl1$r-t-sidx shl-t-sidx-at) (nth nthcdr take len)))))
(defthm shl0$r-t-state-is-at
  (equal (shl0$r-t-state k (+ 1 k) envs outs) (shl-t-state-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-state shl1$r-t-state shl-t-state-at) (nth nthcdr take len)))))
(defthm shl0$r-t-tape-is-at
  (equal (shl0$r-t-tape k (+ 1 k) envs outs) (shl-t-tape-at k outs))
  :hints (("Goal" :in-theory (e/d (shl0$r-t-tape shl1$r-t-tape shl-t-tape-at) (nth nthcdr take len)))))
(defthm shl1$h-arbfail-is-at
  (equal (shl1$h-arbfail k (+ 1 k) envs outs) (shl-h-arbfail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-arbfail shl1$h-arbfail shl-h-arbfail-at) (nth nthcdr take len)))))
(defthm shl1$h-dbusy-is-at
  (equal (shl1$h-dbusy k (+ 1 k) envs outs) (shl-h-dbusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-dbusy shl1$h-dbusy shl-h-dbusy-at) (nth nthcdr take len)))))
(defthm shl1$h-layerfail-is-at
  (equal (shl1$h-layerfail k (+ 1 k) envs outs) (shl-h-layerfail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-layerfail shl1$h-layerfail shl-h-layerfail-at) (nth nthcdr take len)))))
(defthm shl1$h-shellterm-is-at
  (equal (shl1$h-shellterm k (+ 1 k) envs outs) (shl-h-shellterm-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-shellterm shl1$h-shellterm shl-h-shellterm-at) (nth nthcdr take len)))))
(defthm shl1$h-srman-is-at
  (equal (shl1$h-srman k (+ 1 k) envs outs) (shl-h-srman-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-srman shl1$h-srman shl-h-srman-at) (nth nthcdr take len)))))
(defthm shl1$h-tabusy-is-at
  (equal (shl1$h-tabusy k (+ 1 k) envs outs) (shl-h-tabusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tabusy shl1$h-tabusy shl-h-tabusy-at) (nth nthcdr take len)))))
(defthm shl1$h-tchild-is-at
  (equal (shl1$h-tchild k (+ 1 k) envs outs) (shl-h-tchild-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tchild shl1$h-tchild shl-h-tchild-at) (nth nthcdr take len)))))
(defthm shl1$h-tclpm-is-at
  (equal (shl1$h-tclpm k (+ 1 k) envs outs) (shl-h-tclpm-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tclpm shl1$h-tclpm shl-h-tclpm-at) (nth nthcdr take len)))))
(defthm shl1$h-tcpm-is-at
  (equal (shl1$h-tcpm k (+ 1 k) envs outs) (shl-h-tcpm-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tcpm shl1$h-tcpm shl-h-tcpm-at) (nth nthcdr take len)))))
(defthm shl1$h-tebusy-is-at
  (equal (shl1$h-tebusy k (+ 1 k) envs outs) (shl-h-tebusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tebusy shl1$h-tebusy shl-h-tebusy-at) (nth nthcdr take len)))))
(defthm shl1$h-tlock-is-at
  (equal (shl1$h-tlock k (+ 1 k) envs outs) (shl-h-tlock-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tlock shl1$h-tlock shl-h-tlock-at) (nth nthcdr take len)))))
(defthm shl1$h-tpriv-is-at
  (equal (shl1$h-tpriv k (+ 1 k) envs outs) (shl-h-tpriv-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tpriv shl1$h-tpriv shl-h-tpriv-at) (nth nthcdr take len)))))
(defthm shl1$h-tpub-is-at
  (equal (shl1$h-tpub k (+ 1 k) envs outs) (shl-h-tpub-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-tpub shl1$h-tpub shl-h-tpub-at) (nth nthcdr take len)))))
(defthm shl1$h-trbusy-is-at
  (equal (shl1$h-trbusy k (+ 1 k) envs outs) (shl-h-trbusy-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-trbusy shl1$h-trbusy shl-h-trbusy-at) (nth nthcdr take len)))))
(defthm shl1$h-twatch-is-at
  (equal (shl1$h-twatch k (+ 1 k) envs outs) (shl-h-twatch-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-twatch shl1$h-twatch shl-h-twatch-at) (nth nthcdr take len)))))
(defthm shl1$h-ufc-is-at
  (equal (shl1$h-ufc k (+ 1 k) envs outs) (shl-h-ufc-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$h-ufc shl1$h-ufc shl-h-ufc-at) (nth nthcdr take len)))))
(defthm shl1$i-append-is-at
  (equal (shl1$i-append k (+ 1 k) envs outs) (shl-i-append-at k envs))
  :hints (("Goal" :in-theory (e/d (shl1$i-append shl1$i-append shl-i-append-at) (nth nthcdr take len)))))
(defthm shl1$i-clear-is-at
  (equal (shl1$i-clear k (+ 1 k) envs outs) (shl-i-clear-at k envs))
  :hints (("Goal" :in-theory (e/d (shl1$i-clear shl1$i-clear shl-i-clear-at) (nth nthcdr take len)))))
(defthm shl1$i-reset-n-is-at
  (equal (shl1$i-reset-n k (+ 1 k) envs outs) (shl-i-reset-n-at k envs))
  :hints (("Goal" :in-theory (e/d (shl1$i-reset-n shl1$i-reset-n shl-i-reset-n-at) (nth nthcdr take len)))))
(defthm shl1$i-step-is-at
  (equal (shl1$i-step k (+ 1 k) envs outs) (shl-i-step-at k envs))
  :hints (("Goal" :in-theory (e/d (shl1$i-step shl1$i-step shl-i-step-at) (nth nthcdr take len)))))
(defthm shl1$n-m-rel-is-at
  (equal (shl1$n-m-rel k (+ 1 k) envs outs) (shl-m-rel-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (shl1$n-m-rel shl1$r-m-rel shl-m-rel-at) (nth nthcdr take len)))))
(defthm shl1$n-t-state-is-at
  (equal (shl1$n-t-state k (+ 1 k) envs outs) (shl-t-state-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (shl1$n-t-state shl1$r-t-state shl-t-state-at) (nth nthcdr take len)))))
(defthm shl1$o-dpclear-is-at
  (equal (shl1$o-dpclear k (+ 1 k) envs outs) (shl-o-dpclear-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$o-dpclear shl1$o-dpclear shl-o-dpclear-at) (nth nthcdr take len)))))
(defthm shl1$o-dprst-is-at
  (equal (shl1$o-dprst k (+ 1 k) envs outs) (shl-o-dprst-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$o-dprst shl1$o-dprst shl-o-dprst-at) (nth nthcdr take len)))))
(defthm shl1$o-sdf-is-at
  (equal (shl1$o-sdf k (+ 1 k) envs outs) (shl-o-sdf-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$o-sdf shl1$o-sdf shl-o-sdf-at) (nth nthcdr take len)))))
(defthm shl1$o-sfire-is-at
  (equal (shl1$o-sfire k (+ 1 k) envs outs) (shl-o-sfire-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$o-sfire shl1$o-sfire shl-o-sfire-at) (nth nthcdr take len)))))
(defthm shl1$o-shellfail-is-at
  (equal (shl1$o-shellfail k (+ 1 k) envs outs) (shl-o-shellfail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$o-shellfail shl1$o-shellfail shl-o-shellfail-at) (nth nthcdr take len)))))
(defthm shl1$o-stepready-is-at
  (equal (shl1$o-stepready k (+ 1 k) envs outs) (shl-o-stepready-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$o-stepready shl1$o-stepready shl-o-stepready-at) (nth nthcdr take len)))))
(defthm shl1$r-d-fault-is-at
  (equal (shl1$r-d-fault k (+ 1 k) envs outs) (shl-d-fault-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-d-fault shl1$r-d-fault shl-d-fault-at) (nth nthcdr take len)))))
(defthm shl1$r-l-coll-is-at
  (equal (shl1$r-l-coll k (+ 1 k) envs outs) (shl-l-coll-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-l-coll shl1$r-l-coll shl-l-coll-at) (nth nthcdr take len)))))
(defthm shl1$r-m-rel-is-at
  (equal (shl1$r-m-rel k (+ 1 k) envs outs) (shl-m-rel-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-m-rel shl1$r-m-rel shl-m-rel-at) (nth nthcdr take len)))))
(defthm shl1$r-p-lock-sync-is-at
  (equal (shl1$r-p-lock-sync k (+ 1 k) envs outs) (shl-p-lock-sync-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-p-lock-sync shl1$r-p-lock-sync shl-p-lock-sync-at) (nth nthcdr take len)))))
(defthm shl1$r-s-fault-is-at
  (equal (shl1$r-s-fault k (+ 1 k) envs outs) (shl-s-fault-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-s-fault shl1$r-s-fault shl-s-fault-at) (nth nthcdr take len)))))
(defthm shl1$r-s-rexp-is-at
  (equal (shl1$r-s-rexp k (+ 1 k) envs outs) (shl-s-rexp-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-s-rexp shl1$r-s-rexp shl-s-rexp-at) (nth nthcdr take len)))))
(defthm shl1$r-s-sidx-is-at
  (equal (shl1$r-s-sidx k (+ 1 k) envs outs) (shl-s-sidx-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-s-sidx shl1$r-s-sidx shl-s-sidx-at) (nth nthcdr take len)))))
(defthm shl1$r-s-state-is-at
  (equal (shl1$r-s-state k (+ 1 k) envs outs) (shl-s-state-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-s-state shl1$r-s-state shl-s-state-at) (nth nthcdr take len)))))
(defthm shl1$r-t-cidx-is-at
  (equal (shl1$r-t-cidx k (+ 1 k) envs outs) (shl-t-cidx-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-cidx shl1$r-t-cidx shl-t-cidx-at) (nth nthcdr take len)))))
(defthm shl1$r-t-committed-is-at
  (equal (shl1$r-t-committed k (+ 1 k) envs outs) (shl-t-committed-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-committed shl1$r-t-committed shl-t-committed-at) (nth nthcdr take len)))))
(defthm shl1$r-t-eread-is-at
  (equal (shl1$r-t-eread k (+ 1 k) envs outs) (shl-t-eread-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-eread shl1$r-t-eread shl-t-eread-at) (nth nthcdr take len)))))
(defthm shl1$r-t-fail-is-at
  (equal (shl1$r-t-fail k (+ 1 k) envs outs) (shl-t-fail-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-fail shl1$r-t-fail shl-t-fail-at) (nth nthcdr take len)))))
(defthm shl1$r-t-l5exp-is-at
  (equal (shl1$r-t-l5exp k (+ 1 k) envs outs) (shl-t-l5exp-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-l5exp shl1$r-t-l5exp shl-t-l5exp-at) (nth nthcdr take len)))))
(defthm shl1$r-t-lastvalid-is-at
  (equal (shl1$r-t-lastvalid k (+ 1 k) envs outs) (shl-t-lastvalid-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-lastvalid shl1$r-t-lastvalid shl-t-lastvalid-at) (nth nthcdr take len)))))
(defthm shl1$r-t-owner-is-at
  (equal (shl1$r-t-owner k (+ 1 k) envs outs) (shl-t-owner-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-owner shl1$r-t-owner shl-t-owner-at) (nth nthcdr take len)))))
(defthm shl1$r-t-replay-is-at
  (equal (shl1$r-t-replay k (+ 1 k) envs outs) (shl-t-replay-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-replay shl1$r-t-replay shl-t-replay-at) (nth nthcdr take len)))))
(defthm shl1$r-t-sidx-is-at
  (equal (shl1$r-t-sidx k (+ 1 k) envs outs) (shl-t-sidx-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-sidx shl1$r-t-sidx shl-t-sidx-at) (nth nthcdr take len)))))
(defthm shl1$r-t-state-is-at
  (equal (shl1$r-t-state k (+ 1 k) envs outs) (shl-t-state-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-state shl1$r-t-state shl-t-state-at) (nth nthcdr take len)))))
(defthm shl1$r-t-tape-is-at
  (equal (shl1$r-t-tape k (+ 1 k) envs outs) (shl-t-tape-at k outs))
  :hints (("Goal" :in-theory (e/d (shl1$r-t-tape shl1$r-t-tape shl-t-tape-at) (nth nthcdr take len)))))
(value-triple (acl2::cw "~%SHL-SIGNALS done~%"))

; ---------------------------------------------------------------------------
; THE SHELL FACTS AT CYCLE k OF AN EXECUTION.
; ---------------------------------------------------------------------------
(define shl0-facts-at (k envs outs) :verify-guards nil
  (shl0-step-all (shl0$o-appendready k (+ 1 k) envs outs)
                 (shl0$o-sdf k (+ 1 k) envs outs)
                 (shl0$o-sfire k (+ 1 k) envs outs)
                 (shl0$o-sfpos k (+ 1 k) envs outs)
                 (shl0$o-shellfail k (+ 1 k) envs outs)
                 (shl0$o-stepready k (+ 1 k) envs outs)
                 (shl0$r-s-state k (+ 1 k) envs outs)
                 (shl0$r-t-replay k (+ 1 k) envs outs)
                 (shl0$r-t-state k (+ 1 k) envs outs)))
(define shl1-facts-at (k envs outs) :verify-guards nil
  (shl1-step-all (shl1$h-layerfail k (+ 1 k) envs outs)
                 (shl1$i-clear k (+ 1 k) envs outs)
                 (shl1$i-step k (+ 1 k) envs outs)
                 (shl1$n-m-rel k (+ 1 k) envs outs)
                 (shl1$n-t-state k (+ 1 k) envs outs)
                 (shl1$o-dpclear k (+ 1 k) envs outs)
                 (shl1$o-dprst k (+ 1 k) envs outs)
                 (shl1$o-sdf k (+ 1 k) envs outs)
                 (shl1$o-sfire k (+ 1 k) envs outs)
                 (shl1$o-shellfail k (+ 1 k) envs outs)
                 (shl1$o-stepready k (+ 1 k) envs outs)
                 (shl1$r-m-rel k (+ 1 k) envs outs)
                 (shl1$r-t-state k (+ 1 k) envs outs)))
; Every signal the two step lemmas take a value for is two-valued in cycle k.
(define shl-env-at (k envs outs) :verify-guards nil
  (and (unsigned-byte-p 1 (shl1$r-p-lock-sync k (+ 1 k) envs outs))
       (unsigned-byte-p 2 (shl1$r-m-rel k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$r-l-coll k (+ 1 k) envs outs))
       (unsigned-byte-p 3 (shl1$r-s-state k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$r-s-fault k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (shl1$r-s-sidx k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (shl1$r-s-rexp k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$r-d-fault k (+ 1 k) envs outs))
       (unsigned-byte-p 5 (shl1$r-t-state k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$r-t-fail k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$r-t-owner k (+ 1 k) envs outs))
       (unsigned-byte-p 12 (shl1$r-t-tape k (+ 1 k) envs outs))
       (unsigned-byte-p 12 (shl1$r-t-committed k (+ 1 k) envs outs))
       (unsigned-byte-p 12 (shl1$r-t-replay k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$r-t-lastvalid k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (shl1$r-t-sidx k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (shl1$r-t-cidx k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (shl1$r-t-eread k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (shl1$r-t-l5exp k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-ufc k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-arbfail k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-shellterm k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-layerfail k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-dbusy k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tchild k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tlock k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-twatch k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tpub k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tpriv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tcpm k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tclpm k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tebusy k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-trbusy k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$h-tabusy k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (shl1$h-srman k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$i-reset-n k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$i-clear k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$i-step k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (shl1$i-append k (+ 1 k) envs outs))))
; The second lemma's hypothesis: the shell is in one of the seven states
; this link follows, or there is a public CLEAR, or the machine core is not
; released.
(define shl-covered-raw (k envs outs) :verify-guards nil
  (or (or (equal (shl1$r-t-state k (+ 1 k) envs outs) 0) (equal (shl1$r-t-state k (+ 1 k) envs outs) 5) (equal (shl1$r-t-state k (+ 1 k) envs outs) 6) (equal (shl1$r-t-state k (+ 1 k) envs outs) 7) (equal (shl1$r-t-state k (+ 1 k) envs outs) 8) (equal (shl1$r-t-state k (+ 1 k) envs outs) 9) (equal (shl1$r-t-state k (+ 1 k) envs outs) 23)) (equal (shl1$i-clear k (+ 1 k) envs outs) 1) (not (logbitp 1 (shl1$r-m-rel k (+ 1 k) envs outs)))))
(defthm shl0-step-glue
  (implies (and (natp k)
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (shl-env-at k envs (fsm-eval envs initst (probe-fsm))))
           (shl0-facts-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance shl0-step-fsm-thm
                  (base-cycle k))
                 (:instance kv-shell-run-constraints))
           :in-theory (e/d (join-env-at join-env-raw joint-env-p
                            shl-env-at shl0-facts-at
                            shl0$h-arbfail shl0$h-dbusy shl0$h-layerfail shl0$h-shellterm shl0$h-srman shl0$h-tabusy shl0$h-tchild shl0$h-tclpm shl0$h-tcpm shl0$h-tebusy shl0$h-tlock shl0$h-tpriv shl0$h-tpub shl0$h-trbusy shl0$h-twatch shl0$h-ufc shl0$i-append shl0$i-clear shl0$i-reset-n shl0$i-step shl0$o-appendready shl0$o-sdf shl0$o-sfire shl0$o-sfpos shl0$o-shellfail shl0$o-stepready shl0$r-d-fault shl0$r-l-coll shl0$r-m-rel shl0$r-p-lock-sync shl0$r-s-fault shl0$r-s-rexp shl0$r-s-sidx shl0$r-s-state shl0$r-t-cidx shl0$r-t-committed shl0$r-t-eread shl0$r-t-fail shl0$r-t-l5exp shl0$r-t-lastvalid shl0$r-t-owner shl0$r-t-replay shl0$r-t-sidx shl0$r-t-state shl0$r-t-tape
                            shl1$h-arbfail shl1$h-dbusy shl1$h-layerfail shl1$h-shellterm shl1$h-srman shl1$h-tabusy shl1$h-tchild shl1$h-tclpm shl1$h-tcpm shl1$h-tebusy shl1$h-tlock shl1$h-tpriv shl1$h-tpub shl1$h-trbusy shl1$h-twatch shl1$h-ufc shl1$i-append shl1$i-clear shl1$i-reset-n shl1$i-step shl1$n-m-rel shl1$n-t-state shl1$o-dpclear shl1$o-dprst shl1$o-sdf shl1$o-sfire shl1$o-shellfail shl1$o-stepready shl1$r-d-fault shl1$r-l-coll shl1$r-m-rel shl1$r-p-lock-sync shl1$r-s-fault shl1$r-s-rexp shl1$r-s-sidx shl1$r-s-state shl1$r-t-cidx shl1$r-t-committed shl1$r-t-eread shl1$r-t-fail shl1$r-t-l5exp shl1$r-t-lastvalid shl1$r-t-owner shl1$r-t-replay shl1$r-t-sidx shl1$r-t-state shl1$r-t-tape)
                           (shl0-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm
                            shl0$h-arbfail-is-at shl0$h-dbusy-is-at shl0$h-layerfail-is-at shl0$h-shellterm-is-at shl0$h-srman-is-at shl0$h-tabusy-is-at shl0$h-tchild-is-at shl0$h-tclpm-is-at shl0$h-tcpm-is-at shl0$h-tebusy-is-at shl0$h-tlock-is-at shl0$h-tpriv-is-at shl0$h-tpub-is-at shl0$h-trbusy-is-at shl0$h-twatch-is-at shl0$h-ufc-is-at shl0$i-append-is-at shl0$i-clear-is-at shl0$i-reset-n-is-at shl0$i-step-is-at shl0$o-appendready-is-at shl0$o-sdf-is-at shl0$o-sfire-is-at shl0$o-sfpos-is-at shl0$o-shellfail-is-at shl0$o-stepready-is-at shl0$r-d-fault-is-at shl0$r-l-coll-is-at shl0$r-m-rel-is-at shl0$r-p-lock-sync-is-at shl0$r-s-fault-is-at shl0$r-s-rexp-is-at shl0$r-s-sidx-is-at shl0$r-s-state-is-at shl0$r-t-cidx-is-at shl0$r-t-committed-is-at shl0$r-t-eread-is-at shl0$r-t-fail-is-at shl0$r-t-l5exp-is-at shl0$r-t-lastvalid-is-at shl0$r-t-owner-is-at shl0$r-t-replay-is-at shl0$r-t-sidx-is-at shl0$r-t-state-is-at shl0$r-t-tape-is-at shl1$h-arbfail-is-at shl1$h-dbusy-is-at shl1$h-layerfail-is-at shl1$h-shellterm-is-at shl1$h-srman-is-at shl1$h-tabusy-is-at shl1$h-tchild-is-at shl1$h-tclpm-is-at shl1$h-tcpm-is-at shl1$h-tebusy-is-at shl1$h-tlock-is-at shl1$h-tpriv-is-at shl1$h-tpub-is-at shl1$h-trbusy-is-at shl1$h-twatch-is-at shl1$h-ufc-is-at shl1$i-append-is-at shl1$i-clear-is-at shl1$i-reset-n-is-at shl1$i-step-is-at shl1$n-m-rel-is-at shl1$n-t-state-is-at shl1$o-dpclear-is-at shl1$o-dprst-is-at shl1$o-sdf-is-at shl1$o-sfire-is-at shl1$o-shellfail-is-at shl1$o-stepready-is-at shl1$r-d-fault-is-at shl1$r-l-coll-is-at shl1$r-m-rel-is-at shl1$r-p-lock-sync-is-at shl1$r-s-fault-is-at shl1$r-s-rexp-is-at shl1$r-s-sidx-is-at shl1$r-s-state-is-at shl1$r-t-cidx-is-at shl1$r-t-committed-is-at shl1$r-t-eread-is-at shl1$r-t-fail-is-at shl1$r-t-l5exp-is-at shl1$r-t-lastvalid-is-at shl1$r-t-owner-is-at shl1$r-t-replay-is-at shl1$r-t-sidx-is-at shl1$r-t-state-is-at shl1$r-t-tape-is-at)))))
(defthm shl1-step-glue
  (implies (and (natp k)
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (shl-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (shl-covered-raw k envs (fsm-eval envs initst (probe-fsm))))
           (shl1-facts-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance shl1-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-shell-run-constraints))
           :in-theory (e/d (join-env-at join-env-raw joint-env-p
                            shl-env-at shl1-facts-at shl-covered-raw
                            shl1$h-arbfail shl1$h-dbusy shl1$h-layerfail shl1$h-shellterm shl1$h-srman shl1$h-tabusy shl1$h-tchild shl1$h-tclpm shl1$h-tcpm shl1$h-tebusy shl1$h-tlock shl1$h-tpriv shl1$h-tpub shl1$h-trbusy shl1$h-twatch shl1$h-ufc shl1$i-append shl1$i-clear shl1$i-reset-n shl1$i-step shl1$n-m-rel shl1$n-t-state shl1$o-dpclear shl1$o-dprst shl1$o-sdf shl1$o-sfire shl1$o-shellfail shl1$o-stepready shl1$r-d-fault shl1$r-l-coll shl1$r-m-rel shl1$r-p-lock-sync shl1$r-s-fault shl1$r-s-rexp shl1$r-s-sidx shl1$r-s-state shl1$r-t-cidx shl1$r-t-committed shl1$r-t-eread shl1$r-t-fail shl1$r-t-l5exp shl1$r-t-lastvalid shl1$r-t-owner shl1$r-t-replay shl1$r-t-sidx shl1$r-t-state shl1$r-t-tape)
                           (shl1-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm logbitp
                            shl0$h-arbfail-is-at shl0$h-dbusy-is-at shl0$h-layerfail-is-at shl0$h-shellterm-is-at shl0$h-srman-is-at shl0$h-tabusy-is-at shl0$h-tchild-is-at shl0$h-tclpm-is-at shl0$h-tcpm-is-at shl0$h-tebusy-is-at shl0$h-tlock-is-at shl0$h-tpriv-is-at shl0$h-tpub-is-at shl0$h-trbusy-is-at shl0$h-twatch-is-at shl0$h-ufc-is-at shl0$i-append-is-at shl0$i-clear-is-at shl0$i-reset-n-is-at shl0$i-step-is-at shl0$o-appendready-is-at shl0$o-sdf-is-at shl0$o-sfire-is-at shl0$o-sfpos-is-at shl0$o-shellfail-is-at shl0$o-stepready-is-at shl0$r-d-fault-is-at shl0$r-l-coll-is-at shl0$r-m-rel-is-at shl0$r-p-lock-sync-is-at shl0$r-s-fault-is-at shl0$r-s-rexp-is-at shl0$r-s-sidx-is-at shl0$r-s-state-is-at shl0$r-t-cidx-is-at shl0$r-t-committed-is-at shl0$r-t-eread-is-at shl0$r-t-fail-is-at shl0$r-t-l5exp-is-at shl0$r-t-lastvalid-is-at shl0$r-t-owner-is-at shl0$r-t-replay-is-at shl0$r-t-sidx-is-at shl0$r-t-state-is-at shl0$r-t-tape-is-at shl1$h-arbfail-is-at shl1$h-dbusy-is-at shl1$h-layerfail-is-at shl1$h-shellterm-is-at shl1$h-srman-is-at shl1$h-tabusy-is-at shl1$h-tchild-is-at shl1$h-tclpm-is-at shl1$h-tcpm-is-at shl1$h-tebusy-is-at shl1$h-tlock-is-at shl1$h-tpriv-is-at shl1$h-tpub-is-at shl1$h-trbusy-is-at shl1$h-twatch-is-at shl1$h-ufc-is-at shl1$i-append-is-at shl1$i-clear-is-at shl1$i-reset-n-is-at shl1$i-step-is-at shl1$n-m-rel-is-at shl1$n-t-state-is-at shl1$o-dpclear-is-at shl1$o-dprst-is-at shl1$o-sdf-is-at shl1$o-sfire-is-at shl1$o-shellfail-is-at shl1$o-stepready-is-at shl1$r-d-fault-is-at shl1$r-l-coll-is-at shl1$r-m-rel-is-at shl1$r-p-lock-sync-is-at shl1$r-s-fault-is-at shl1$r-s-rexp-is-at shl1$r-s-sidx-is-at shl1$r-s-state-is-at shl1$r-t-cidx-is-at shl1$r-t-committed-is-at shl1$r-t-eread-is-at shl1$r-t-fail-is-at shl1$r-t-l5exp-is-at shl1$r-t-lastvalid-is-at shl1$r-t-owner-is-at shl1$r-t-replay-is-at shl1$r-t-sidx-is-at shl1$r-t-state-is-at shl1$r-t-tape-is-at)))))
(value-triple (acl2::cw "~%SHL-GLUE done~%"))

(defthm shl-pay-u-of-integer
  (implies (integerp x) (equal (pay-u x) x))
  :hints (("Goal" :in-theory (enable pay-u 4vec->upper))))
(defthm shl-p-ready-of-fact
  (implies (and (shl-fact-ready o-appendready o-stepready r-t-state)
                (shl0-int-o-appendready o-appendready)
                (shl0-int-o-stepready o-stepready))
           (shl-p-ready o-appendready o-stepready r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-ready fgl::fgl-prove-fn) (shl-p-ready))))
  :rule-classes nil)
(defthm shl-p-start-of-fact
  (implies (and (shl-fact-start o-sfire o-sfpos r-t-replay r-t-state)
                (shl0-int-o-sfire o-sfire)
                (shl0-int-o-sfpos o-sfpos))
           (shl-p-start o-sfire o-sfpos r-t-replay r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-start fgl::fgl-prove-fn) (shl-p-start))))
  :rule-classes nil)
(defthm shl-p-done-of-fact
  (implies (and (shl-fact-done o-sdf r-s-state r-t-state)
                (shl0-int-o-sdf o-sdf))
           (shl-p-done o-sdf r-s-state r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-done fgl::fgl-prove-fn) (shl-p-done))))
  :rule-classes nil)
(defthm shl-p-fail-of-fact
  (implies (and (shl-fact-fail o-shellfail r-t-state)
                (shl0-int-o-shellfail o-shellfail))
           (shl-p-fail o-shellfail r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-fail fgl::fgl-prove-fn) (shl-p-fail))))
  :rule-classes nil)
(defthm shl-p-inactive-of-fact
  (implies (and (shl-fact-inactive n-t-state r-m-rel)
                (shl1-int-n-t-state n-t-state))
           (shl-p-inactive n-t-state r-m-rel))
  :hints (("Goal" :in-theory (e/d (shl-fact-inactive fgl::fgl-prove-fn) (shl-p-inactive))))
  :rule-classes nil)
(defthm shl-p-reset-of-fact
  (implies (and (shl-fact-reset n-m-rel n-t-state o-dprst)
                (shl1-int-n-m-rel n-m-rel)
                (shl1-int-n-t-state n-t-state)
                (shl1-int-o-dprst o-dprst))
           (shl-p-reset n-m-rel n-t-state o-dprst))
  :hints (("Goal" :in-theory (e/d (shl-fact-reset fgl::fgl-prove-fn) (shl-p-reset))))
  :rule-classes nil)
(defthm shl-p-clear-of-fact
  (implies (and (shl-fact-clear i-clear n-t-state)
                (shl1-int-n-t-state n-t-state))
           (shl-p-clear i-clear n-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-clear fgl::fgl-prove-fn) (shl-p-clear))))
  :rule-classes nil)
(defthm shl-p-idle-of-fact
  (implies (and (shl-fact-idle h-layerfail i-step n-m-rel n-t-state o-dprst o-shellfail o-stepready r-t-state)
                (shl1-int-n-m-rel n-m-rel)
                (shl1-int-n-t-state n-t-state)
                (shl1-int-o-dprst o-dprst)
                (shl1-int-o-shellfail o-shellfail)
                (shl1-int-o-stepready o-stepready))
           (shl-p-idle h-layerfail i-step n-m-rel n-t-state o-dprst o-shellfail o-stepready r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-idle fgl::fgl-prove-fn) (shl-p-idle))))
  :rule-classes nil)
(defthm shl-p-drain-of-fact
  (implies (and (shl-fact-drain n-t-state r-t-state)
                (shl1-int-n-t-state n-t-state))
           (shl-p-drain n-t-state r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-drain fgl::fgl-prove-fn) (shl-p-drain))))
  :rule-classes nil)
(defthm shl-p-layer-start-of-fact
  (implies (and (shl-fact-layer-start n-m-rel n-t-state o-dpclear o-dprst o-sfire r-t-state)
                (shl1-int-n-m-rel n-m-rel)
                (shl1-int-n-t-state n-t-state)
                (shl1-int-o-dpclear o-dpclear)
                (shl1-int-o-dprst o-dprst)
                (shl1-int-o-sfire o-sfire))
           (shl-p-layer-start n-m-rel n-t-state o-dpclear o-dprst o-sfire r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-layer-start fgl::fgl-prove-fn) (shl-p-layer-start))))
  :rule-classes nil)
(defthm shl-p-layer-of-fact
  (implies (and (shl-fact-layer n-m-rel n-t-state o-dpclear o-dprst r-t-state)
                (shl1-int-n-m-rel n-m-rel)
                (shl1-int-n-t-state n-t-state)
                (shl1-int-o-dpclear o-dpclear)
                (shl1-int-o-dprst o-dprst))
           (shl-p-layer n-m-rel n-t-state o-dpclear o-dprst r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-layer fgl::fgl-prove-fn) (shl-p-layer))))
  :rule-classes nil)
(defthm shl-p-layer-done-of-fact
  (implies (and (shl-fact-layer-done n-m-rel n-t-state o-dpclear o-dprst o-sdf r-t-state)
                (shl1-int-n-m-rel n-m-rel)
                (shl1-int-n-t-state n-t-state)
                (shl1-int-o-dpclear o-dpclear)
                (shl1-int-o-dprst o-dprst)
                (shl1-int-o-sdf o-sdf))
           (shl-p-layer-done n-m-rel n-t-state o-dpclear o-dprst o-sdf r-t-state))
  :hints (("Goal" :in-theory (e/d (shl-fact-layer-done fgl::fgl-prove-fn) (shl-p-layer-done))))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-VALUES done~%"))

(define shl-covered-at (k envs outs) :verify-guards nil
  (or (or (equal (shl-t-state-at k outs) 0) (equal (shl-t-state-at k outs) 5) (equal (shl-t-state-at k outs) 6) (equal (shl-t-state-at k outs) 7) (equal (shl-t-state-at k outs) 8) (equal (shl-t-state-at k outs) 9) (equal (shl-t-state-at k outs) 23)) (equal (shl-i-clear-at k envs) 1) (not (logbitp 1 (shl-m-rel-at k outs)))))
; Everything the argument needs to know about cycle k of the shell.
(define shl-known-at (k envs outs) :verify-guards nil
  (and (join-env-at k envs outs)
       (shl-env-at k envs outs)
       (shl0-facts-at k envs outs)
       (or (not (shl-covered-at k envs outs))
           (shl1-facts-at k envs outs))))
; THE STEP, in any state of the shell,
(defthm shl-step0
  (implies (and (natp k) (shl-known-at k envs outs))
           (and (shl-p-ready (shl-o-appendready-at k outs) (shl-o-stepready-at k outs) (shl-t-state-at k outs))
                (shl-p-start (shl-o-sfire-at k outs) (shl-o-sfpos-at k outs) (shl-t-replay-at k outs) (shl-t-state-at k outs))
                (shl-p-done (shl-o-sdf-at k outs) (shl-s-state-at k outs) (shl-t-state-at k outs))
                (shl-p-fail (shl-o-shellfail-at k outs) (shl-t-state-at k outs))))
  :hints (("Goal"
           :use ((:instance shl-p-ready-of-fact (o-appendready (shl0$o-appendready k (+ 1 k) envs outs)) (o-stepready (shl0$o-stepready k (+ 1 k) envs outs)) (r-t-state (shl0$r-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-start-of-fact (o-sfire (shl0$o-sfire k (+ 1 k) envs outs)) (o-sfpos (shl0$o-sfpos k (+ 1 k) envs outs)) (r-t-replay (shl0$r-t-replay k (+ 1 k) envs outs)) (r-t-state (shl0$r-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-done-of-fact (o-sdf (shl0$o-sdf k (+ 1 k) envs outs)) (r-s-state (shl0$r-s-state k (+ 1 k) envs outs)) (r-t-state (shl0$r-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-fail-of-fact (o-shellfail (shl0$o-shellfail k (+ 1 k) envs outs)) (r-t-state (shl0$r-t-state k (+ 1 k) envs outs))))
           :in-theory (e/d (shl-known-at shl0-facts-at shl0-step-all shl0-step-concl)
                           (unsigned-byte-p nth nthcdr take len shl-fact-ready shl-fact-start shl-fact-done shl-fact-fail shl-fact-inactive shl-fact-reset shl-fact-clear shl-fact-idle shl-fact-drain shl-fact-layer-start shl-fact-layer shl-fact-layer-done shl-p-ready shl-p-start shl-p-done shl-p-fail shl-p-inactive shl-p-reset shl-p-clear shl-p-idle shl-p-drain shl-p-layer-start shl-p-layer shl-p-layer-done shl0-int-o-stepready shl0-int-o-appendready shl0-int-o-sfire shl0-int-o-sdf shl0-int-o-sfpos shl0-int-o-shellfail shl1-int-o-stepready shl1-int-o-sfire shl1-int-o-sdf shl1-int-o-shellfail shl1-int-o-dprst shl1-int-o-dpclear shl1-int-n-m-rel shl1-int-n-t-state))))
  :rule-classes nil)
; ... and in the states this link follows.
(defthm shl-step1
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs))
           (and (shl-p-inactive (shl-t-state-at (+ 1 k) outs) (shl-m-rel-at k outs))
                (shl-p-reset (shl-m-rel-at (+ 1 k) outs) (shl-t-state-at (+ 1 k) outs) (shl-o-dprst-at k outs))
                (shl-p-clear (shl-i-clear-at k envs) (shl-t-state-at (+ 1 k) outs))
                (shl-p-idle (shl-h-layerfail-at k outs) (shl-i-step-at k envs) (shl-m-rel-at (+ 1 k) outs) (shl-t-state-at (+ 1 k) outs) (shl-o-dprst-at k outs) (shl-o-shellfail-at k outs) (shl-o-stepready-at k outs) (shl-t-state-at k outs))
                (shl-p-drain (shl-t-state-at (+ 1 k) outs) (shl-t-state-at k outs))
                (shl-p-layer-start (shl-m-rel-at (+ 1 k) outs) (shl-t-state-at (+ 1 k) outs) (shl-o-dpclear-at k outs) (shl-o-dprst-at k outs) (shl-o-sfire-at k outs) (shl-t-state-at k outs))
                (shl-p-layer (shl-m-rel-at (+ 1 k) outs) (shl-t-state-at (+ 1 k) outs) (shl-o-dpclear-at k outs) (shl-o-dprst-at k outs) (shl-t-state-at k outs))
                (shl-p-layer-done (shl-m-rel-at (+ 1 k) outs) (shl-t-state-at (+ 1 k) outs) (shl-o-dpclear-at k outs) (shl-o-dprst-at k outs) (shl-o-sdf-at k outs) (shl-t-state-at k outs))))
  :hints (("Goal"
           :use ((:instance shl-p-inactive-of-fact (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)) (r-m-rel (shl1$r-m-rel k (+ 1 k) envs outs)))
                 (:instance shl-p-reset-of-fact (n-m-rel (shl1$n-m-rel k (+ 1 k) envs outs)) (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)) (o-dprst (shl1$o-dprst k (+ 1 k) envs outs)))
                 (:instance shl-p-clear-of-fact (i-clear (shl1$i-clear k (+ 1 k) envs outs)) (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-idle-of-fact (h-layerfail (shl1$h-layerfail k (+ 1 k) envs outs)) (i-step (shl1$i-step k (+ 1 k) envs outs)) (n-m-rel (shl1$n-m-rel k (+ 1 k) envs outs)) (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)) (o-dprst (shl1$o-dprst k (+ 1 k) envs outs)) (o-shellfail (shl1$o-shellfail k (+ 1 k) envs outs)) (o-stepready (shl1$o-stepready k (+ 1 k) envs outs)) (r-t-state (shl1$r-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-drain-of-fact (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)) (r-t-state (shl1$r-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-layer-start-of-fact (n-m-rel (shl1$n-m-rel k (+ 1 k) envs outs)) (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)) (o-dpclear (shl1$o-dpclear k (+ 1 k) envs outs)) (o-dprst (shl1$o-dprst k (+ 1 k) envs outs)) (o-sfire (shl1$o-sfire k (+ 1 k) envs outs)) (r-t-state (shl1$r-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-layer-of-fact (n-m-rel (shl1$n-m-rel k (+ 1 k) envs outs)) (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)) (o-dpclear (shl1$o-dpclear k (+ 1 k) envs outs)) (o-dprst (shl1$o-dprst k (+ 1 k) envs outs)) (r-t-state (shl1$r-t-state k (+ 1 k) envs outs)))
                 (:instance shl-p-layer-done-of-fact (n-m-rel (shl1$n-m-rel k (+ 1 k) envs outs)) (n-t-state (shl1$n-t-state k (+ 1 k) envs outs)) (o-dpclear (shl1$o-dpclear k (+ 1 k) envs outs)) (o-dprst (shl1$o-dprst k (+ 1 k) envs outs)) (o-sdf (shl1$o-sdf k (+ 1 k) envs outs)) (r-t-state (shl1$r-t-state k (+ 1 k) envs outs))))
           :in-theory (e/d (shl-known-at shl1-facts-at shl1-step-all shl1-step-concl)
                           (unsigned-byte-p nth nthcdr take len logbitp shl-fact-ready shl-fact-start shl-fact-done shl-fact-fail shl-fact-inactive shl-fact-reset shl-fact-clear shl-fact-idle shl-fact-drain shl-fact-layer-start shl-fact-layer shl-fact-layer-done shl-p-ready shl-p-start shl-p-done shl-p-fail shl-p-inactive shl-p-reset shl-p-clear shl-p-idle shl-p-drain shl-p-layer-start shl-p-layer shl-p-layer-done shl0-int-o-stepready shl0-int-o-appendready shl0-int-o-sfire shl0-int-o-sdf shl0-int-o-sfpos shl0-int-o-shellfail shl1-int-o-stepready shl1-int-o-sfire shl1-int-o-sdf shl1-int-o-shellfail shl1-int-o-dprst shl1-int-o-dpclear shl1-int-n-m-rel shl1-int-n-t-state))))
  :rule-classes nil)
(defthm shl-sizes
  (implies (shl-env-at k envs outs)
           (and (unsigned-byte-p 1 (shl-p-lock-sync-at k outs))
                (unsigned-byte-p 2 (shl-m-rel-at k outs))
                (unsigned-byte-p 1 (shl-l-coll-at k outs))
                (unsigned-byte-p 3 (shl-s-state-at k outs))
                (unsigned-byte-p 1 (shl-s-fault-at k outs))
                (unsigned-byte-p 8 (shl-s-sidx-at k outs))
                (unsigned-byte-p 8 (shl-s-rexp-at k outs))
                (unsigned-byte-p 1 (shl-d-fault-at k outs))
                (unsigned-byte-p 5 (shl-t-state-at k outs))
                (unsigned-byte-p 1 (shl-t-fail-at k outs))
                (unsigned-byte-p 1 (shl-t-owner-at k outs))
                (unsigned-byte-p 12 (shl-t-tape-at k outs))
                (unsigned-byte-p 12 (shl-t-committed-at k outs))
                (unsigned-byte-p 12 (shl-t-replay-at k outs))
                (unsigned-byte-p 1 (shl-t-lastvalid-at k outs))
                (unsigned-byte-p 8 (shl-t-sidx-at k outs))
                (unsigned-byte-p 8 (shl-t-cidx-at k outs))
                (unsigned-byte-p 16 (shl-t-eread-at k outs))
                (unsigned-byte-p 8 (shl-t-l5exp-at k outs))
                (unsigned-byte-p 1 (shl-h-ufc-at k outs))
                (unsigned-byte-p 1 (shl-h-arbfail-at k outs))
                (unsigned-byte-p 1 (shl-h-shellterm-at k outs))
                (unsigned-byte-p 1 (shl-h-layerfail-at k outs))
                (unsigned-byte-p 1 (shl-h-dbusy-at k outs))
                (unsigned-byte-p 1 (shl-h-tchild-at k outs))
                (unsigned-byte-p 1 (shl-h-tlock-at k outs))
                (unsigned-byte-p 1 (shl-h-twatch-at k outs))
                (unsigned-byte-p 1 (shl-h-tpub-at k outs))
                (unsigned-byte-p 1 (shl-h-tpriv-at k outs))
                (unsigned-byte-p 1 (shl-h-tcpm-at k outs))
                (unsigned-byte-p 1 (shl-h-tclpm-at k outs))
                (unsigned-byte-p 1 (shl-h-tebusy-at k outs))
                (unsigned-byte-p 1 (shl-h-trbusy-at k outs))
                (unsigned-byte-p 1 (shl-h-tabusy-at k outs))
                (unsigned-byte-p 16 (shl-h-srman-at k outs))
                (unsigned-byte-p 1 (shl-i-reset-n-at k envs))
                (unsigned-byte-p 1 (shl-i-clear-at k envs))
                (unsigned-byte-p 1 (shl-i-step-at k envs))
                (unsigned-byte-p 1 (shl-i-append-at k envs))))
  :hints (("Goal" :in-theory (e/d (shl-env-at) (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(defthm shl-known-next
  (implies (and (natp k)
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (shl-env-at k envs (fsm-eval envs initst (probe-fsm))))
           (shl-known-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal" :use ((:instance shl0-step-glue) (:instance shl1-step-glue))
           :in-theory (e/d (shl-known-at shl-covered-at shl-covered-raw)
                           (shl0-step-glue shl1-step-glue join-env-at shl-env-at shl0-facts-at
                            shl1-facts-at logbitp fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-STEP done~%"))

; ---------------------------------------------------------------------------
; THE SHELL FACTS, as they are used.
; ---------------------------------------------------------------------------
(defthm shl-ev-ready
  (implies (and (natp k) (shl-known-at k envs outs)
                (equal (shl-o-stepready-at k outs) 1))
           (equal (shl-t-state-at k outs) 0))
  :hints (("Goal"
           :use ((:instance shl-step0))
           :in-theory (e/d (shl-p-ready) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-append
  (implies (and (natp k) (shl-known-at k envs outs)
                (equal (shl-o-appendready-at k outs) 1))
           (equal (shl-t-state-at k outs) 0))
  :hints (("Goal"
           :use ((:instance shl-step0))
           :in-theory (e/d (shl-p-ready) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-start
  (implies (and (natp k) (shl-known-at k envs outs)
                (equal (shl-o-sfire-at k outs) 1))
           (and (equal (shl-t-state-at k outs) 5) (equal (shl-o-sfpos-at k outs) (loghead 11 (shl-t-replay-at k outs)))))
  :hints (("Goal"
           :use ((:instance shl-step0))
           :in-theory (e/d (shl-p-start) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-done
  (implies (and (natp k) (shl-known-at k envs outs)
                (equal (shl-o-sdf-at k outs) 1))
           (and (equal (shl-t-state-at k outs) 9) (equal (shl-s-state-at k outs) 5)))
  :hints (("Goal"
           :use ((:instance shl-step0))
           :in-theory (e/d (shl-p-done) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-fail
  (implies (and (natp k) (shl-known-at k envs outs)
                (equal (shl-o-shellfail-at k outs) 0))
           (not (equal (shl-t-state-at k outs) 31)))
  :hints (("Goal"
           :use ((:instance shl-step0))
           :in-theory (e/d (shl-p-fail) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-inactive
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (not (logbitp 1 (shl-m-rel-at k outs))))
           (equal (shl-t-state-at (+ 1 k) outs) 0))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-inactive) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-reset
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (not (and (equal (shl-o-dprst-at k outs) 1) (logbitp 1 (shl-m-rel-at (+ 1 k) outs)))))
           (equal (shl-t-state-at (+ 1 k) outs) 0))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-reset) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-clear
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (equal (shl-i-clear-at k envs) 1))
           (or (equal (shl-t-state-at (+ 1 k) outs) 23) (equal (shl-t-state-at (+ 1 k) outs) 0) (equal (shl-t-state-at (+ 1 k) outs) 31)))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-clear) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-idle
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (equal (shl-t-state-at k outs) 0) (equal (shl-o-dprst-at k outs) 1) (logbitp 1 (shl-m-rel-at (+ 1 k) outs))
                (equal (shl-h-layerfail-at k outs) 0) (equal (shl-o-shellfail-at k outs) 0))
           (or (equal (shl-t-state-at (+ 1 k) outs) 0) (equal (shl-t-state-at (+ 1 k) outs) 23) (equal (shl-t-state-at (+ 1 k) outs) 31)
               (and (equal (shl-i-step-at k envs) 1) (equal (shl-o-stepready-at k outs) 1))))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-idle) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-drain
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (equal (shl-t-state-at k outs) 23))
           (or (equal (shl-t-state-at (+ 1 k) outs) 23) (equal (shl-t-state-at (+ 1 k) outs) 0) (equal (shl-t-state-at (+ 1 k) outs) 31)))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-drain) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-layer-start
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (equal (shl-t-state-at k outs) 5) (equal (shl-o-dprst-at k outs) 1) (logbitp 1 (shl-m-rel-at (+ 1 k) outs)) (equal (shl-o-dpclear-at k outs) 0))
           (and (or (equal (shl-t-state-at (+ 1 k) outs) 5) (equal (shl-t-state-at (+ 1 k) outs) 6) (equal (shl-t-state-at (+ 1 k) outs) 31))
                (or (not (equal (shl-o-sfire-at k outs) 1)) (equal (shl-t-state-at (+ 1 k) outs) 6) (equal (shl-t-state-at (+ 1 k) outs) 31))))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-layer-start) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-layer
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (or (equal (shl-t-state-at k outs) 6) (equal (shl-t-state-at k outs) 7) (equal (shl-t-state-at k outs) 8))
                (equal (shl-o-dprst-at k outs) 1) (logbitp 1 (shl-m-rel-at (+ 1 k) outs)) (equal (shl-o-dpclear-at k outs) 0))
           (or (equal (shl-t-state-at (+ 1 k) outs) 6) (equal (shl-t-state-at (+ 1 k) outs) 7) (equal (shl-t-state-at (+ 1 k) outs) 8) (equal (shl-t-state-at (+ 1 k) outs) 9)
               (equal (shl-t-state-at (+ 1 k) outs) 31)))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-layer) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(defthm shl-ev-layer-done
  (implies (and (natp k) (shl-known-at k envs outs) (shl-covered-at k envs outs)
                (equal (shl-t-state-at k outs) 9) (equal (shl-o-dprst-at k outs) 1) (logbitp 1 (shl-m-rel-at (+ 1 k) outs)) (equal (shl-o-dpclear-at k outs) 0))
           (or (equal (shl-t-state-at (+ 1 k) outs) 9) (equal (shl-t-state-at (+ 1 k) outs) 31)
               (and (equal (shl-t-state-at (+ 1 k) outs) 10) (equal (shl-o-sdf-at k outs) 1))))
  :hints (("Goal"
           :use ((:instance shl-step1))
           :in-theory (e/d (shl-p-layer-done) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear))))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-EVENTS done~%"))

; ---------------------------------------------------------------------------
; THE SAME SIGNALS IN THE PRODUCER LINK AND HERE; what the environment gives.
; ---------------------------------------------------------------------------
(defthm shl-bridge
  (and (equal (shl-s-state-at k outs) (prd-s-state-at k outs))
       (equal (shl-o-sfire-at k outs) (prd-o-sfire-at k outs))
       (equal (shl-o-sfpos-at k outs) (prd-h-sfpos-at k outs))
       (equal (shl-o-sdf-at k outs) (prd-h-sdf-at k outs))
       (equal (shl-o-dprst-at k outs) (prd-o-dprst-at k outs))
       (equal (shl-o-dpclear-at k outs) (prd-o-dpclear-at k outs))
       (equal (shl-m-rel-at k outs) (prd-m-rel-at k outs))
       (equal (shl-i-clear-at k envs) (prd-i-clear-at k envs)))
  :hints (("Goal"
           :in-theory (e/d (shl-s-state-at shl-o-sfire-at shl-o-sfpos-at shl-o-sdf-at shl-o-dprst-at
                            shl-o-dpclear-at shl-m-rel-at shl-i-clear-at
                            shl1$r-s-state shl1$o-sfire shl0$o-sfpos shl1$o-sdf shl1$o-dprst
                            shl1$o-dpclear shl1$r-m-rel shl1$i-clear
                            prd-s-state-at prd-o-sfire-at prd-h-sfpos-at prd-h-sdf-at prd-o-dprst-at
                            prd-o-dpclear-at prd-m-rel-at prd-i-clear-at
                            prd$r-s-state prd$o-sfire prd$h-sfpos prd$h-sdf prd$o-dprst
                            prd$o-dpclear prd$r-m-rel prd$i-clear)
                           (nth nthcdr take len))))
  :rule-classes nil)
; the environment reports no fault of the shell or the layer block
(defthm shl-no-fault
  (implies (join-env-at k envs outs)
           (and (equal (shl-o-shellfail-at k outs) 0) (equal (shl-h-layerfail-at k outs) 0)))
  :hints (("Goal"
           :in-theory (e/d (join-env-at join-env-raw joint-env-p
                            shl-o-shellfail-at shl-h-layerfail-at shl1$o-shellfail shl1$h-layerfail)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-BRIDGE done~%"))

; ---------------------------------------------------------------------------
; THE PUBLIC COMMANDS, by the probe's ports.
; ---------------------------------------------------------------------------
; A public STEP is accepted in cycle k: step_valid_i and step_ready_o are
; both 1.
(define kv-step-accepted-at (k envs outs) :verify-guards nil
  (b* ((step-valid (sig "step_valid_i" 1 (nth k envs)))
       (step-ready (sig "step_ready_o" 1 (nth k outs))))
    (and (equal step-valid 1) (equal step-ready 1))))
; A public APPEND is accepted in cycle k.
(define kv-append-accepted-at (k envs outs) :verify-guards nil
  (b* ((append-valid (sig "append_valid_i" 1 (nth k envs)))
       (append-ready (sig "append_ready_o" 1 (nth k outs))))
    (and (equal append-valid 1) (equal append-ready 1))))
; (the public CLEAR input in cycle k is kv-clear-at, of the write-record book)
(defthm shl-commands-connect
  (and (equal (kv-step-accepted-at k envs outs)
              (and (equal (shl-i-step-at k envs) 1) (equal (shl-o-stepready-at k outs) 1)))
       (implies (kv-append-accepted-at k envs outs)
                (equal (shl-o-appendready-at k outs) 1))
       (equal (kv-clear-at k envs) (shl-i-clear-at k envs)))
  :hints (("Goal"
           :in-theory (e/d (kv-step-accepted-at kv-append-accepted-at kv-clear-at rec-clear-at pay$i-clear
                            shl-i-step-at shl-o-stepready-at shl-o-appendready-at shl-i-clear-at
                            shl1$i-step shl1$o-stepready shl0$o-appendready shl1$i-clear)
                           (nth nthcdr take len))))
  :rule-classes nil)
; The cycle of the latest accepted public STEP before cycle k; nil when
; there is none.
(defund shl-step-cycle (k envs outs)
  (declare (xargs :measure (nfix k) :verify-guards nil))
  (cond ((zp k) nil)
        ((kv-step-accepted-at (- k 1) envs outs) (- k 1))
        (t (shl-step-cycle (- k 1) envs outs))))
(defthm shl-step-cycle-next
  (implies (natp k)
           (equal (shl-step-cycle (+ 1 k) envs outs)
                  (if (kv-step-accepted-at k envs outs) k (shl-step-cycle k envs outs))))
  :hints (("Goal" :expand ((shl-step-cycle (+ 1 k) envs outs)))))
(defthm shl-step-cycle-bound
  (implies (shl-step-cycle k envs outs)
           (and (natp (shl-step-cycle k envs outs))
                (< (shl-step-cycle k envs outs) k)
                (kv-step-accepted-at (shl-step-cycle k envs outs) envs outs)))
  :hints (("Goal" :in-theory (enable shl-step-cycle)))
  :rule-classes nil)
; The shell is working on a STEP: it is in none of IDLE (0), CLEAR_DRAIN
; (23) and FAIL (31).
(define shl-pass-p (st) :verify-guards nil
  (not (or (equal st 0) (equal st 23) (equal st 31))))
; In every cycle a+1 .. k the shell is working on a STEP, and in every cycle
; a .. k-1 there is no public CLEAR.
(defund shl-busy-since (a k envs outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix a))) :verify-guards nil))
  (or (zp (- (nfix k) (nfix a)))
      (and (shl-pass-p (shl-t-state-at (nfix k) outs))
           (equal (shl-i-clear-at (- (nfix k) 1) envs) 0)
           (shl-busy-since a (- (nfix k) 1) envs outs))))
(defthm shl-busy-since-next
  (implies (and (natp a) (natp k) (<= a k))
           (equal (shl-busy-since a (+ 1 k) envs outs)
                  (and (shl-pass-p (shl-t-state-at (+ 1 k) outs))
                       (equal (shl-i-clear-at k envs) 0)
                       (shl-busy-since a k envs outs))))
  :hints (("Goal" :expand ((shl-busy-since a (+ 1 k) envs outs)))))
(defthm shl-busy-since-empty
  (shl-busy-since k k envs outs)
  :hints (("Goal" :in-theory (enable shl-busy-since))))
; THE INVARIANT: a shell working on a STEP has been doing so, without a
; public CLEAR, since an accepted STEP no earlier than cycle lo; and while
; the sequencer is busy the shell is in one of the four states that feed the
; layer block and take its result.
(defund shl-inv (lo k envs outs)
  (declare (xargs :verify-guards nil))
  (b* ((st (shl-t-state-at k outs))
       (s (shl-step-cycle k envs outs)))
    (and (or (not (shl-pass-p st))
             (and s (<= lo s) (shl-busy-since s k envs outs)))
         (or (equal (prd-s-state-at k outs) 0)
             (or (equal st 6) (equal st 7) (equal st 8) (equal st 9))))))
(value-triple (acl2::cw "~%SHL-INV defined~%"))

; one cycle of the first clause
(defthm shl-inv-step-pass
  (implies (and (natp k) (natp lo) (<= lo k)
                (shl-known-at k envs outs)
                (join-env-at k envs outs)
                (shl-inv lo k envs outs)
                (shl-pass-p (shl-t-state-at (+ 1 k) outs)))
           (and (shl-step-cycle (+ 1 k) envs outs)
                (<= lo (shl-step-cycle (+ 1 k) envs outs))
                (shl-busy-since (shl-step-cycle (+ 1 k) envs outs) (+ 1 k) envs outs)))
  :hints (("Goal"
           :cases ((equal (shl-i-clear-at k envs) 1))
           :use ((:instance shl-ev-ready) (:instance shl-ev-fail) (:instance shl-no-fault)
                 (:instance shl-ev-reset) (:instance shl-ev-clear) (:instance shl-ev-idle)
                 (:instance shl-ev-drain) (:instance shl-sizes)
                 (:instance shl-commands-connect)
                 (:instance shl-step-cycle-bound))
           :in-theory (e/d (shl-inv shl-pass-p shl-covered-at shl-known-at)
                           (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear shl-step-cycle shl-busy-since))))
  :rule-classes nil)
; ... and of the second
(defthm shl-inv-step-layer
  (implies (and (natp k)
                (shl-known-at k envs outs) (shl-known-at (+ 1 k) envs outs)
                (join-env-at k envs outs) (join-env-at (+ 1 k) envs outs)
                (prd-known-at k envs outs)
                (prd-nofault-at k outs) (prd-nofault-at (+ 1 k) outs) (prd-sinv-at k outs)
                (shl-inv lo k envs outs)
                (not (equal (prd-s-state-at (+ 1 k) outs) 0)))
           (or (equal (shl-t-state-at (+ 1 k) outs) 6) (equal (shl-t-state-at (+ 1 k) outs) 7) (equal (shl-t-state-at (+ 1 k) outs) 8) (equal (shl-t-state-at (+ 1 k) outs) 9)))
  :hints (("Goal"
           :cases ((prd-normal-at k outs))
           :use ((:instance prd-ev-reset) (:instance prd-ev-sequence) (:instance prd-ev-sequence-done)
                 (:instance shl-bridge) (:instance shl-bridge (k (+ 1 k)))
                 (:instance shl-ev-start) (:instance shl-ev-done)
                 (:instance shl-ev-fail (k (+ 1 k))) (:instance shl-no-fault (k (+ 1 k)))
                 (:instance shl-ev-layer-start) (:instance shl-ev-layer) (:instance shl-ev-layer-done))
           :in-theory (e/d (shl-inv shl-covered-at prd-guard-at prd-normal-at shl-known-at)
                           (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear shl-step-cycle shl-busy-since prd-known-at prd-nofault-at prd-sinv-at join-env-at shl-pass-p))))
  :rule-classes nil)
(defthm shl-inv-step
  (implies (and (natp k) (natp lo) (<= lo k)
                (shl-known-at k envs outs) (shl-known-at (+ 1 k) envs outs)
                (join-env-at k envs outs) (join-env-at (+ 1 k) envs outs)
                (prd-known-at k envs outs)
                (prd-nofault-at k outs) (prd-nofault-at (+ 1 k) outs) (prd-sinv-at k outs)
                (shl-inv lo k envs outs))
           (shl-inv lo (+ 1 k) envs outs))
  :hints (("Goal"
           :use ((:instance shl-inv-step-pass) (:instance shl-inv-step-layer))
           :expand ((shl-inv lo (+ 1 k) envs outs))
           :in-theory (disable shl-inv shl-pass-p shl-known-at prd-known-at prd-nofault-at prd-sinv-at
                               join-env-at shl-step-cycle shl-busy-since)))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-INV-STEP done~%"))

; ---------------------------------------------------------------------------
; THE PREMISE OF THIS LINK, by the RTL's own names.
; ---------------------------------------------------------------------------
; In cycle k each of these signals of the shell, the sequencer and the
; machine core, and the public inputs, is two-valued.  The definition is
; built from the lifted lemma's own reading of each signal.  As named in
; the RTL, with widths:
;   model_lock_core_sync_q                                  1  register
;   u_machine.machine_release_q                             2  register
;   u_machine.u_six_layers.service_start_collision_q        1  register
;   u_machine.u_six_layers.u_sequence.state_q               3  register
;   u_machine.u_six_layers.u_sequence.fault_q               1  register
;   u_machine.u_six_layers.u_sequence.stream_index_q        8  register
;   u_machine.u_six_layers.u_sequence.result_exponent_q     8  register
;   u_machine.u_six_layers.u_datapath.fault_q               1  register
;   u_machine.u_token_shell.state_q                         5  register
;   u_machine.u_token_shell.fail_q                          1  register
;   u_machine.u_token_shell.ddr_owner_q                     1  register
;   u_machine.u_token_shell.tape_count_q                   12  register
;   u_machine.u_token_shell.committed_count_q              12  register
;   u_machine.u_token_shell.replay_position_q              12  register
;   u_machine.u_token_shell.last_hidden_valid_q             1  register
;   u_machine.u_token_shell.stream_index_q                  8  register
;   u_machine.u_token_shell.capture_index_q                 8  register
;   u_machine.u_token_shell.embedding_read_q               16  register
;   u_machine.u_token_shell.layer5_exponent_q               8  register
;   u_machine.upstream_fail_closed_i                        1  wire
;   u_machine.arbiter_fail                                  1  wire
;   u_machine.shell_terminal_latched                        1  wire
;   u_machine.layer_fail                                    1  wire
;   u_machine.u_six_layers.datapath_busy                    1  wire
;   u_machine.u_token_shell.child_fault                     1  wire
;   u_machine.u_token_shell.lock_fault                      1  wire
;   u_machine.u_token_shell.watchdog_fault                  1  wire
;   u_machine.u_token_shell.public_protocol_fault           1  wire
;   u_machine.u_token_shell.private_protocol_fault          1  wire
;   u_machine.u_token_shell.committed_prefixes_match        1  wire
;   u_machine.u_token_shell.cleared_prefixes_match          1  wire
;   u_machine.u_token_shell.embed_busy                      1  wire
;   u_machine.u_token_shell.rms_busy                        1  wire
;   u_machine.u_token_shell.argmax_busy                     1  wire
;   u_machine.u_six_layers.u_sequence.private_result_mantissa_i   16  wire
;   reset_n_i                                               1  input
;   clear_i                                                 1  input
;   step_valid_i                                            1  input
;   append_valid_i                                          1  input
(make-event
 (b* ((ev (acl2::get-event 'shl1-step-fsm-thm (w state)))
      (bindings (cddr (second (third ev)))))
   `(define kv-shell-signals-ok-at (k envs outs)
      :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
      (let ((base-cycle k))
        (declare (ignorable base-cycle))
        (and ,@(prd-ubp-conjuncts '((r-p-lock-sync . 1) (r-m-rel . 2) (r-l-coll . 1) (r-s-state . 3) (r-s-fault . 1) (r-s-sidx . 8) (r-s-rexp . 8) (r-d-fault . 1) (r-t-state . 5) (r-t-fail . 1) (r-t-owner . 1) (r-t-tape . 12) (r-t-committed . 12) (r-t-replay . 12) (r-t-lastvalid . 1) (r-t-sidx . 8) (r-t-cidx . 8) (r-t-eread . 16) (r-t-l5exp . 8) (h-ufc . 1) (h-arbfail . 1) (h-shellterm . 1) (h-layerfail . 1) (h-dbusy . 1) (h-tchild . 1) (h-tlock . 1) (h-twatch . 1) (h-tpub . 1) (h-tpriv . 1) (h-tcpm . 1) (h-tclpm . 1) (h-tebusy . 1) (h-trbusy . 1) (h-tabusy . 1) (h-srman . 16) (i-reset-n . 1) (i-clear . 1) (i-step . 1) (i-append . 1)) bindings))))))
(define kv-shell-signals-ok-from (j n envs outs)
  :verify-guards nil
  :measure (nfix (- (nfix n) (nfix j)))
  (if (zp (- (nfix n) (nfix j)))
      t
    (and (kv-shell-signals-ok-at (nfix j) envs outs)
         (kv-shell-signals-ok-from (+ 1 (nfix j)) n envs outs))))
(defund shl-env-from (j n envs outs)
  (declare (xargs :measure (nfix (- (nfix n) (nfix j))) :verify-guards nil))
  (if (zp (- (nfix n) (nfix j)))
      t
    (and (shl-env-at (nfix j) envs outs)
         (shl-env-from (+ 1 (nfix j)) n envs outs))))
(defthm shl-signals-connect
  (implies (kv-shell-signals-ok-at k envs outs)
           (shl-env-at k envs outs))
  :hints (("Goal"
           :in-theory (e/d (kv-shell-signals-ok-at shl-env-at
                            shl1$r-p-lock-sync shl1$r-m-rel shl1$r-l-coll shl1$r-s-state shl1$r-s-fault shl1$r-s-sidx shl1$r-s-rexp shl1$r-d-fault shl1$r-t-state shl1$r-t-fail shl1$r-t-owner shl1$r-t-tape shl1$r-t-committed shl1$r-t-replay shl1$r-t-lastvalid shl1$r-t-sidx shl1$r-t-cidx shl1$r-t-eread shl1$r-t-l5exp shl1$h-ufc shl1$h-arbfail shl1$h-shellterm shl1$h-layerfail shl1$h-dbusy shl1$h-tchild shl1$h-tlock shl1$h-twatch shl1$h-tpub shl1$h-tpriv shl1$h-tcpm shl1$h-tclpm shl1$h-tebusy shl1$h-trbusy shl1$h-tabusy shl1$h-srman shl1$i-reset-n shl1$i-clear shl1$i-step shl1$i-append shl-d-fault-at shl-h-arbfail-at shl-h-dbusy-at shl-h-layerfail-at shl-h-shellterm-at shl-h-srman-at shl-h-tabusy-at shl-h-tchild-at shl-h-tclpm-at shl-h-tcpm-at shl-h-tebusy-at shl-h-tlock-at shl-h-tpriv-at shl-h-tpub-at shl-h-trbusy-at shl-h-twatch-at shl-h-ufc-at shl-i-append-at shl-i-clear-at shl-i-reset-n-at shl-i-step-at shl-l-coll-at shl-m-rel-at shl-p-lock-sync-at shl-s-fault-at shl-s-rexp-at shl-s-sidx-at shl-s-state-at shl-t-cidx-at shl-t-committed-at shl-t-eread-at shl-t-fail-at shl-t-l5exp-at shl-t-lastvalid-at shl-t-owner-at shl-t-replay-at shl-t-sidx-at shl-t-state-at shl-t-tape-at)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(defthm shl-signals-from-connect
  (implies (kv-shell-signals-ok-from j n envs outs)
           (shl-env-from j n envs outs))
  :hints (("Goal"
           :induct (kv-shell-signals-ok-from j n envs outs)
           :in-theory (e/d (kv-shell-signals-ok-from shl-env-from)
                           (kv-shell-signals-ok-at shl-env-at)))
          ("Subgoal *1/2" :use ((:instance shl-signals-connect (k (nfix j))))))
  :rule-classes nil)
(defthm shl-env-from-at
  (implies (and (shl-env-from j n envs outs) (natp j) (natp i) (natp n) (<= j i) (< i n))
           (shl-env-at i envs outs))
  :hints (("Goal" :induct (shl-env-from j n envs outs)
           :in-theory (e/d (shl-env-from) (shl-env-at))))
  :rule-classes nil)
(defthm shl-env-from-prefix
  (implies (and (natp j) (natp m) (natp n) (<= j m) (<= m n)
                (shl-env-from j n envs outs))
           (shl-env-from j m envs outs))
  :hints (("Goal"
           :induct (shl-env-from j n envs outs)
           :in-theory (e/d (shl-env-from) (shl-env-at))))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-PREMISE done~%"))

; ---------------------------------------------------------------------------
; FROM THE RESET TO THE INVARIANT AT EVERY CYCLE.
; ---------------------------------------------------------------------------
; what is known of the shell in any cycle of the range
(defthm shl-known-from-reset
  (implies (and (natp r) (natp i) (natp m) (<= (+ 2 r) i) (<= i m)
                (join-env-from (+ 2 r) (+ 1 m) envs (fsm-eval envs initst (probe-fsm)))
                (shl-env-from (+ 2 r) (+ 1 m) envs (fsm-eval envs initst (probe-fsm))))
           (and (shl-known-at i envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at i envs (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal"
           :use ((:instance shl-known-next (k i))
                 (:instance prd-join-env-from-at (j (+ 2 r)) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-env-from-at (j (+ 2 r)) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (disable shl-known-at join-env-at shl-env-at join-env-from shl-env-from
                               fsm-eval (probe-fsm) probe-fsm)))
  :rule-classes nil)
(defthm prd-ev-inactive
  (implies (and (natp k) (prd-known-at k envs outs)
                (equal (prd-m-rel-at k outs) 0))
           (equal (prd-o-dprst-at k outs) 0))
  :hints (("Goal" :use ((:instance prd-step))
           :in-theory (e/d (prd-p-inactive) (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear shl-step-cycle shl-busy-since))))
  :rule-classes nil)
; after the reset the shell and the sequencer are idle
(defthm shl-base
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prd-known-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm)))
                (shl-known-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm))))
           (shl-inv (+ 3 r) (+ 3 r) envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance prd-release-after-reset)
                 (:instance shl-bridge (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-ev-inactive (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-inactive (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-reset (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm)))))
           :expand ((shl-inv (+ 3 r) (+ 3 r) envs (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (shl-covered-at shl-pass-p prd-normal-at)
                           (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear shl-step-cycle shl-busy-since shl-known-at prd-known-at join-reset-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
; THE INVARIANT AT EVERY CYCLE AFTER THE RESET.
(defthm shl-inv-from-reset
  (implies (and (natp r) (natp i) (<= (+ 3 r) i)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at (+ 2 r) (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) (+ 1 i) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from (+ 2 r) (+ 1 i) envs (fsm-eval envs initst (probe-fsm)))
                (shl-env-from (+ 2 r) (+ 1 i) envs (fsm-eval envs initst (probe-fsm))))
           (shl-inv (+ 3 r) i envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal" :induct (prd-ind3 r i)
           :in-theory (disable shl-inv shl-known-at prd-known-at prd-nofault-at prd-sinv-at prd-inv
                               join-env-at join-reset-at prod-mem-at join-env-from prod-env-from
                               shl-env-from fsm-eval (probe-fsm) probe-fsm))
          ("Subgoal *1/2"
           :use ((:instance shl-inv-step (lo (+ 3 r)) (k (+ -1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-known-from-reset (m i))
                 (:instance shl-known-from-reset (m i) (i (+ -1 i)))
                 (:instance prd-all-from-reset)
                 (:instance prd-all-from-reset (i (+ -1 i)))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m i) (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m i) (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-env-from-prefix (j (+ 2 r)) (m i) (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm))))))
          ("Subgoal *1/1"
           :use ((:instance shl-base)
                 (:instance shl-known-from-reset (m i) (i (+ 2 r)))
                 (:instance prd-known-from (j (+ 2 r)) (i (+ 2 r)))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m (+ 3 r)) (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m (+ 3 r)) (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm)))))))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-FROM-RESET done~%"))

; ---------------------------------------------------------------------------
; THE SEQUENCER'S PASS LIES INSIDE THE SHELL'S WORK ON ONE ACCEPTED STEP.
; ---------------------------------------------------------------------------
(defthm shl-pass-is-in-a-step
  (implies (and (natp r) (natp b) (natp ps) (<= (+ 3 r) b) (< ps b)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at (+ 2 r) (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) (+ 1 b) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from (+ 2 r) (+ 1 b) envs (fsm-eval envs initst (probe-fsm)))
                (shl-env-from (+ 2 r) (+ 1 b) envs (fsm-eval envs initst (probe-fsm)))
                (equal (prd-o-sfire-at ps (fsm-eval envs initst (probe-fsm))) 1)
                (prd-busy-since ps b (fsm-eval envs initst (probe-fsm)))
                (not (equal (prd-s-state-at b (fsm-eval envs initst (probe-fsm))) 0)))
           (b* ((s (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))))
             (and (natp s) (<= (+ 3 r) s) (< s ps)
                  (kv-step-accepted-at s envs (fsm-eval envs initst (probe-fsm)))
                  (shl-busy-since s b envs (fsm-eval envs initst (probe-fsm)))
                  (equal (shl-t-state-at ps (fsm-eval envs initst (probe-fsm))) 5)
                  (equal (prd-h-sfpos-at ps (fsm-eval envs initst (probe-fsm)))
                         (loghead 11 (shl-t-replay-at ps (fsm-eval envs initst (probe-fsm))))))))
  :hints (("Goal"
           :cases ((< (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm))) ps)
                   (equal (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm))) ps))
           :use ((:instance shl-inv-from-reset (i b))
                 (:instance shl-step-cycle-bound (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-inv-from-reset (i (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m (+ 1 (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))))
                  (n (+ 1 b)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m (+ 1 (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))))
                  (n (+ 1 b)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-env-from-prefix (j (+ 2 r)) (m (+ 1 (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))))
                  (n (+ 1 b)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-busy-since-at (a ps) (j (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))) (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-known-from-reset (m b) (i (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))))
                 (:instance shl-known-from-reset (m b) (i ps))
                 (:instance shl-commands-connect (k (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-ev-ready (k (shl-step-cycle b envs (fsm-eval envs initst (probe-fsm)))) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-ev-start (k ps) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-bridge (k ps) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (shl-inv shl-pass-p)
                           (unsigned-byte-p nth nthcdr take len logbitp loghead
                            prd-pass-start prd-busy-since prd-no-clear shl-step-cycle shl-busy-since shl-known-at join-env-at join-reset-at prod-mem-at join-env-from
                            prod-env-from shl-env-from kv-step-accepted-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%SHL-STEP-LINK done~%"))

; ---------------------------------------------------------------------------
; THE THEOREM.
; ---------------------------------------------------------------------------
; the cycle of the latest accepted public STEP before cycle b
(define kv-step-cycle (b envs outs) :verify-guards nil
  (shl-step-cycle b envs outs))
; In every cycle s+1 .. b the shell is working on a STEP (it is in none of
; IDLE, CLEAR_DRAIN and FAIL), and in every cycle s .. b-1 there is no
; public CLEAR.
(define kv-shell-working-since (s b envs outs) :verify-guards nil
  (shl-busy-since s b envs outs))
; In cycle ps the shell starts the sequencer's pass for this position: it
; is in LAYER_START, and replay_position_q[10:0] is the position.
(define kv-pass-started-by-shell-at (ps position outs) :verify-guards nil
  (and (equal (shl-t-state-at ps outs) 5)
       (equal (loghead 11 (shl-t-replay-at ps outs)) position)))

; Take any execution of the probe module's state machine, from any initial
; state, with the hypotheses of the three links holding through cycle n.
; Suppose pending_persisted_q rises at cycle n.  Let j be the record's
; start, b the begin of its staging, ps the latest accepted sequencer start
; before b, and s the latest accepted public STEP before b.  Then
;   - s is after the reset and before ps; the STEP is accepted at s
;     (step_valid_i and step_ready_o both 1); from s+1 to b the shell is
;     working on that STEP, with no public CLEAR from s to b-1; at ps the
;     shell is in LAYER_START with the staged position as its replay
;     position;
;   - in the sequencer's pass started at ps the requests for the V
;     projection stage, the K rotary stage and the K/V stage of the staged
;     layer and position are accepted in that order, and the K and V
;     results accepted in those stages cover every index 0 .. 127;
;   - the eighteen writes the endpoint (private_kv_req_*) accepted in cycles
;     j to n, in order, are the reference record of the staged layer and
;     position, the exponents of the last K and V results, and for each
;     coordinate the mantissas of the final K and V results with that index.
(defthm kv-step-to-record
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (ps (kv-pass-start-cycle b outs))
       (s (kv-step-cycle b envs outs))
       (keys (kv-key-results b outs))
       (values (kv-value-results b outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-producer-storage-definite-at (+ 2 r) outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
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
           :use ((:instance kv-producer-to-record)
                 (:instance kv-staging-to-record)
                 (:instance kvj-reset-connects (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-signals-from-connect (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-signals-from-connect (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-storage-connects (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-prefix
                  (j (+ 2 r)) (m (+ 1 (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm))))) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix
                  (j (+ 2 r)) (m (+ 1 (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm))))) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-env-from-prefix
                  (j (+ 2 r)) (m (+ 1 (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm))))) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-busy-since-at (a (prd-pass-start (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm)))) (j (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm)))) (k (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm)))) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance shl-pass-is-in-a-step
                  (b (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm))))
                  (ps (prd-pass-start (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm))) (fsm-eval envs initst (probe-fsm))))))
           :in-theory (e/d (kv-step-cycle kv-shell-working-since kv-pass-started-by-shell-at
                            kv-producer-work-identified kv-pass-start-cycle kv-pass-started-at)
                           (kvj-reset-connects kvj-environment-from-connects
                            kv-record-start kv-staging-begin kv-staged-layer kv-staged-position
                            kv-reference-record kv-endpoint-writes kv-record-uninterrupted
                            kv-produced-transfers kv-staging-begin-accepted-at kv-staging-uninterrupted
                            kv-key-results kv-value-results kv-all-coordinates-produced
                            kv-stage-request-accepted-at kv-stage-request-cycle kv-step-accepted-at
                            shl-step-cycle shl-busy-since prd-pass-start prd-busy-since prd-no-clear
                            prd-start loghead
                            join-env-from prod-env-from shl-env-from join-reset-at prod-mem-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%KV-THEOREM done~%"))

; THE SAME FOR LAYER 0, TOKEN POSITION 0: when the completed record's
; staged layer and position are both 0.
(defthm kv-step-to-record-layer-0-position-0
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (ps (kv-pass-start-cycle b outs))
       (s (kv-step-cycle b envs outs))
       (keys (kv-key-results b outs))
       (values (kv-value-results b outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-producer-storage-definite-at (+ 2 r) outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
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
           :use ((:instance kv-step-to-record))
           :in-theory (theory 'minimal-theory)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KV-THEOREM-0 done~%"))

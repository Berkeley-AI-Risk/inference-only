; From the producer to the staging: the theorem.
;
; Written by make_step_book.py; do not edit.  Private.
;
; THE CLAIM.  Take any execution of the probe module's state machine with
; the first link's hypotheses and this link's premises.  When the
; controller's pending_persisted_q rises, the 128 transfers its record was
; staged from carry, coordinate by coordinate, the mantissa of the final K
; rotary result and of the final V projection result accepted for that
; index before the staging's begin, since the latest accepted request for
; each of those two stages; the staged exponents are the exponents of the
; last K and V results; and those stage requests and the K/V stage's lie, in
; order, in one pass of the sequencer for the staged layer and position.
; Composed with the first link: the eighteen endpoint writes are the
; reference record of those results.  This is kv-producer-to-record, at the
; end of this file.
;
; WHAT IT RESTS ON.  The first link's theorem, the producer facts of
; kv-producer-lift.lisp, and an induction over all cycles after the reset.
(in-package "SV")
(include-book "kv-producer-lift")
(acl2::set-slow-alist-action nil)
(value-triple (acl2::tshell-ensure))

; ---------------------------------------------------------------------------
; THE SIGNALS OF A CYCLE, by the lifted lemma's own bindings.
; ---------------------------------------------------------------------------
(defun prd-accessor-events (names formals bindings vars)
  (declare (xargs :mode :program) (irrelevant vars))
  (if (atom names) nil
    (cons `(defun ,(intern-in-package-of-symbol
                    (concatenate 'string "PRD$" (symbol-name (car names))) (car names))
             ,formals
             (declare (xargs :verify-guards nil) (ignorable ,@formals))
             ,(cadr (assoc-eq (car names) bindings)))
          (prd-accessor-events (cdr names) formals bindings vars))))
(defun prd-accessor-names (names)
  (declare (xargs :mode :program))
  (if (atom names) nil
    (cons (intern-in-package-of-symbol
           (concatenate 'string "PRD$" (symbol-name (car names))) (car names))
          (prd-accessor-names (cdr names)))))
(make-event
 (b* ((ev (acl2::get-event 'prod-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (names '(h-adv h-arl h-arv h-childfault h-dbusy h-grd h-haf h-hdf h-hsr h-hsv h-kcr h-kpc h-lli h-llr h-lrf h-lrv h-lsv h-ndv h-nre h-nri h-nrl h-nrm h-nrv h-paf h-pdv h-rdv h-rif h-rri h-rrl h-rrv h-rterm h-sbr h-sdf h-sfpos h-siexp h-sif h-sil h-spm h-spr h-srexp h-srf h-srman i-clear i-reset-n n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kexp n-d-kmem n-d-krd n-d-kvrv n-d-lseen n-d-odone n-d-oidx n-d-sdone n-d-tpos n-d-tseen n-d-vexp n-d-vmem n-d-vrd n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dpclear o-dprst o-kra o-kre o-kwe o-layerfail o-player o-ppos o-pstage o-sacc o-sbv o-sfire o-spv o-vra o-vre o-vwe r-d-arhead r-d-aslane r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-ephase r-d-est r-d-fault r-d-gexp r-d-idone r-d-iidx r-d-kexp r-d-kmem r-d-krd r-d-kvrv r-d-lseen r-d-nds r-d-odone r-d-oidx r-d-rhalf r-d-rhead r-d-rphase r-d-rsecond r-d-sdone r-d-sds r-d-sss r-d-svv r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-d-vrd r-l-coll r-m-rel r-p-lock-sync r-s-fault r-s-layer r-s-lseen r-s-pos r-s-rexp r-s-sidx r-s-stage r-s-state)))
   (cons 'progn
         (append
          (prd-accessor-events names formals bindings vars)
          (list `(in-theory (disable ,@(prd-accessor-names names))))))))
; Each signal as a function of the cycle.
(define prd-h-kpc-at (k outs) :verify-guards nil (prd$h-kpc k k nil outs))
(define prd-h-lsv-at (k outs) :verify-guards nil (prd$h-lsv k k nil outs))
(define prd-h-nre-at (k outs) :verify-guards nil (prd$h-nre k k nil outs))
(define prd-h-nri-at (k outs) :verify-guards nil (prd$h-nri k k nil outs))
(define prd-h-nrl-at (k outs) :verify-guards nil (prd$h-nrl k k nil outs))
(define prd-h-nrm-at (k outs) :verify-guards nil (prd$h-nrm k k nil outs))
(define prd-h-nrv-at (k outs) :verify-guards nil (prd$h-nrv k k nil outs))
(define prd-h-sdf-at (k outs) :verify-guards nil (prd$h-sdf k k nil outs))
(define prd-h-sfpos-at (k outs) :verify-guards nil (prd$h-sfpos k k nil outs))
(define prd-i-clear-at (k envs) :verify-guards nil (prd$i-clear k k envs nil))
(define prd-i-reset-n-at (k envs) :verify-guards nil (prd$i-reset-n k k envs nil))
(define prd-d-clay-at (k outs) :verify-guards nil (prd$r-d-clay k k nil outs))
(define prd-d-cpos-at (k outs) :verify-guards nil (prd$r-d-cpos k k nil outs))
(define prd-d-cst-at (k outs) :verify-guards nil (prd$r-d-cst k k nil outs))
(define prd-d-elay-at (k outs) :verify-guards nil (prd$r-d-elay k k nil outs))
(define prd-d-eng-at (k outs) :verify-guards nil (prd$r-d-eng k k nil outs))
(define prd-d-est-at (k outs) :verify-guards nil (prd$r-d-est k k nil outs))
(define prd-d-fault-at (k outs) :verify-guards nil (prd$r-d-fault k k nil outs))
(define prd-d-iidx-at (k outs) :verify-guards nil (prd$r-d-iidx k k nil outs))
(define prd-d-kexp-at (k outs) :verify-guards nil (prd$r-d-kexp k k nil outs))
(define prd-d-kmem-at (k outs) :verify-guards nil (prd$r-d-kmem k k nil outs))
(define prd-d-krd-at (k outs) :verify-guards nil (prd$r-d-krd k k nil outs))
(define prd-d-kvrv-at (k outs) :verify-guards nil (prd$r-d-kvrv k k nil outs))
(define prd-d-lseen-at (k outs) :verify-guards nil (prd$r-d-lseen k k nil outs))
(define prd-d-odone-at (k outs) :verify-guards nil (prd$r-d-odone k k nil outs))
(define prd-d-oidx-at (k outs) :verify-guards nil (prd$r-d-oidx k k nil outs))
(define prd-d-sdone-at (k outs) :verify-guards nil (prd$r-d-sdone k k nil outs))
(define prd-d-tpos-at (k outs) :verify-guards nil (prd$r-d-tpos k k nil outs))
(define prd-d-tseen-at (k outs) :verify-guards nil (prd$r-d-tseen k k nil outs))
(define prd-d-vexp-at (k outs) :verify-guards nil (prd$r-d-vexp k k nil outs))
(define prd-d-vmem-at (k outs) :verify-guards nil (prd$r-d-vmem k k nil outs))
(define prd-d-vrd-at (k outs) :verify-guards nil (prd$r-d-vrd k k nil outs))
(define prd-m-rel-at (k outs) :verify-guards nil (prd$r-m-rel k k nil outs))
(define prd-s-fault-at (k outs) :verify-guards nil (prd$r-s-fault k k nil outs))
(define prd-s-layer-at (k outs) :verify-guards nil (prd$r-s-layer k k nil outs))
(define prd-s-pos-at (k outs) :verify-guards nil (prd$r-s-pos k k nil outs))
(define prd-s-stage-at (k outs) :verify-guards nil (prd$r-s-stage k k nil outs))
(define prd-s-state-at (k outs) :verify-guards nil (prd$r-s-state k k nil outs))
(define prd-o-dpclear-at (k outs) :verify-guards nil (prd$o-dpclear k k nil outs))
(define prd-o-dprst-at (k outs) :verify-guards nil (prd$o-dprst k k nil outs))
(define prd-o-kra-at (k outs) :verify-guards nil (prd$o-kra k k nil outs))
(define prd-o-kre-at (k outs) :verify-guards nil (prd$o-kre k k nil outs))
(define prd-o-kwe-at (k outs) :verify-guards nil (prd$o-kwe k k nil outs))
(define prd-o-layerfail-at (k outs) :verify-guards nil (prd$o-layerfail k k nil outs))
(define prd-o-player-at (k outs) :verify-guards nil (prd$o-player k k nil outs))
(define prd-o-ppos-at (k outs) :verify-guards nil (prd$o-ppos k k nil outs))
(define prd-o-pstage-at (k outs) :verify-guards nil (prd$o-pstage k k nil outs))
(define prd-o-sacc-at (k outs) :verify-guards nil (prd$o-sacc k k nil outs))
(define prd-o-sbv-at (k outs) :verify-guards nil (prd$o-sbv k k nil outs))
(define prd-o-sfire-at (k outs) :verify-guards nil (prd$o-sfire k k nil outs))
(define prd-o-spv-at (k outs) :verify-guards nil (prd$o-spv k k nil outs))
(define prd-o-vra-at (k outs) :verify-guards nil (prd$o-vra k k nil outs))
(define prd-o-vre-at (k outs) :verify-guards nil (prd$o-vre k k nil outs))
(define prd-o-vwe-at (k outs) :verify-guards nil (prd$o-vwe k k nil outs))
(define prd-d-sss-at (k outs) :verify-guards nil (prd$r-d-sss k k nil outs))
(define prd-l-coll-at (k outs) :verify-guards nil (prd$r-l-coll k k nil outs))
(define prd-p-lock-sync-at (k outs) :verify-guards nil (prd$r-p-lock-sync k k nil outs))
(define prd-s-lseen-at (k outs) :verify-guards nil (prd$r-s-lseen k k nil outs))
(define prd-s-sidx-at (k outs) :verify-guards nil (prd$r-s-sidx k k nil outs))
(define prd-s-rexp-at (k outs) :verify-guards nil (prd$r-s-rexp k k nil outs))
(define prd-d-sds-at (k outs) :verify-guards nil (prd$r-d-sds k k nil outs))
(define prd-d-nds-at (k outs) :verify-guards nil (prd$r-d-nds k k nil outs))
(define prd-d-idone-at (k outs) :verify-guards nil (prd$r-d-idone k k nil outs))
(define prd-d-rphase-at (k outs) :verify-guards nil (prd$r-d-rphase k k nil outs))
(define prd-d-rhead-at (k outs) :verify-guards nil (prd$r-d-rhead k k nil outs))
(define prd-d-rhalf-at (k outs) :verify-guards nil (prd$r-d-rhalf k k nil outs))
(define prd-d-rsecond-at (k outs) :verify-guards nil (prd$r-d-rsecond k k nil outs))
(define prd-d-arhead-at (k outs) :verify-guards nil (prd$r-d-arhead k k nil outs))
(define prd-d-aslane-at (k outs) :verify-guards nil (prd$r-d-aslane k k nil outs))
(define prd-d-svv-at (k outs) :verify-guards nil (prd$r-d-svv k k nil outs))
(define prd-d-gexp-at (k outs) :verify-guards nil (prd$r-d-gexp k k nil outs))
(define prd-d-ephase-at (k outs) :verify-guards nil (prd$r-d-ephase k k nil outs))
(define prd-h-rterm-at (k outs) :verify-guards nil (prd$h-rterm k k nil outs))
(define prd-h-childfault-at (k outs) :verify-guards nil (prd$h-childfault k k nil outs))
(define prd-h-ndv-at (k outs) :verify-guards nil (prd$h-ndv k k nil outs))
(define prd-h-pdv-at (k outs) :verify-guards nil (prd$h-pdv k k nil outs))
(define prd-h-rrv-at (k outs) :verify-guards nil (prd$h-rrv k k nil outs))
(define prd-h-rri-at (k outs) :verify-guards nil (prd$h-rri k k nil outs))
(define prd-h-rrl-at (k outs) :verify-guards nil (prd$h-rrl k k nil outs))
(define prd-h-rdv-at (k outs) :verify-guards nil (prd$h-rdv k k nil outs))
(define prd-h-hdf-at (k outs) :verify-guards nil (prd$h-hdf k k nil outs))
(define prd-h-lrv-at (k outs) :verify-guards nil (prd$h-lrv k k nil outs))
(define prd-h-lrf-at (k outs) :verify-guards nil (prd$h-lrf k k nil outs))
(define prd-h-arv-at (k outs) :verify-guards nil (prd$h-arv k k nil outs))
(define prd-h-arl-at (k outs) :verify-guards nil (prd$h-arl k k nil outs))
(define prd-h-adv-at (k outs) :verify-guards nil (prd$h-adv k k nil outs))
(define prd-h-llr-at (k outs) :verify-guards nil (prd$h-llr k k nil outs))
(define prd-h-lli-at (k outs) :verify-guards nil (prd$h-lli k k nil outs))
(define prd-h-grd-at (k outs) :verify-guards nil (prd$h-grd k k nil outs))
(define prd-h-kcr-at (k outs) :verify-guards nil (prd$h-kcr k k nil outs))
(define prd-h-sbr-at (k outs) :verify-guards nil (prd$h-sbr k k nil outs))
(define prd-h-spr-at (k outs) :verify-guards nil (prd$h-spr k k nil outs))
(define prd-h-hsr-at (k outs) :verify-guards nil (prd$h-hsr k k nil outs))
(define prd-h-rif-at (k outs) :verify-guards nil (prd$h-rif k k nil outs))
(define prd-h-paf-at (k outs) :verify-guards nil (prd$h-paf k k nil outs))
(define prd-h-haf-at (k outs) :verify-guards nil (prd$h-haf k k nil outs))
(define prd-h-hsv-at (k outs) :verify-guards nil (prd$h-hsv k k nil outs))
(define prd-h-dbusy-at (k outs) :verify-guards nil (prd$h-dbusy k k nil outs))
(define prd-h-sif-at (k outs) :verify-guards nil (prd$h-sif k k nil outs))
(define prd-h-sil-at (k outs) :verify-guards nil (prd$h-sil k k nil outs))
(define prd-h-spm-at (k outs) :verify-guards nil (prd$h-spm k k nil outs))
(define prd-h-siexp-at (k outs) :verify-guards nil (prd$h-siexp k k nil outs))
(define prd-h-srf-at (k outs) :verify-guards nil (prd$h-srf k k nil outs))
(define prd-h-srexp-at (k outs) :verify-guards nil (prd$h-srexp k k nil outs))
(define prd-h-srman-at (k outs) :verify-guards nil (prd$h-srman k k nil outs))
(in-theory (disable prd-h-kpc-at prd-h-lsv-at prd-h-nre-at prd-h-nri-at prd-h-nrl-at prd-h-nrm-at prd-h-nrv-at prd-h-sdf-at prd-h-sfpos-at prd-i-clear-at prd-i-reset-n-at prd-d-clay-at prd-d-cpos-at prd-d-cst-at prd-d-elay-at prd-d-eng-at prd-d-est-at prd-d-fault-at prd-d-iidx-at prd-d-kexp-at prd-d-kmem-at prd-d-krd-at prd-d-kvrv-at prd-d-lseen-at prd-d-odone-at prd-d-oidx-at prd-d-sdone-at prd-d-tpos-at prd-d-tseen-at prd-d-vexp-at prd-d-vmem-at prd-d-vrd-at prd-m-rel-at prd-s-fault-at prd-s-layer-at prd-s-pos-at prd-s-stage-at prd-s-state-at prd-o-dpclear-at prd-o-dprst-at prd-o-kra-at prd-o-kre-at prd-o-kwe-at prd-o-layerfail-at prd-o-player-at prd-o-ppos-at prd-o-pstage-at prd-o-sacc-at prd-o-sbv-at prd-o-sfire-at prd-o-spv-at prd-o-vra-at prd-o-vre-at prd-o-vwe-at prd-d-sss-at prd-l-coll-at prd-p-lock-sync-at prd-s-lseen-at prd-s-sidx-at prd-s-rexp-at prd-d-sds-at prd-d-nds-at prd-d-idone-at prd-d-rphase-at prd-d-rhead-at prd-d-rhalf-at prd-d-rsecond-at prd-d-arhead-at prd-d-aslane-at prd-d-svv-at prd-d-gexp-at prd-d-ephase-at prd-h-rterm-at prd-h-childfault-at prd-h-ndv-at prd-h-pdv-at prd-h-rrv-at prd-h-rri-at prd-h-rrl-at prd-h-rdv-at prd-h-hdf-at prd-h-lrv-at prd-h-lrf-at prd-h-arv-at prd-h-arl-at prd-h-adv-at prd-h-llr-at prd-h-lli-at prd-h-grd-at prd-h-kcr-at prd-h-sbr-at prd-h-spr-at prd-h-hsr-at prd-h-rif-at prd-h-paf-at prd-h-haf-at prd-h-hsv-at prd-h-dbusy-at prd-h-sif-at prd-h-sil-at prd-h-spm-at prd-h-siexp-at prd-h-srf-at prd-h-srexp-at prd-h-srman-at))
; A signal the lemma reads in cycle k or k+1 is that function at k or k+1.
(defthm prd$h-adv-is-at
  (equal (prd$h-adv k (+ 1 k) envs outs) (prd-h-adv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-adv prd-h-adv-at) (nth nthcdr take len)))))
(defthm prd$h-arl-is-at
  (equal (prd$h-arl k (+ 1 k) envs outs) (prd-h-arl-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-arl prd-h-arl-at) (nth nthcdr take len)))))
(defthm prd$h-arv-is-at
  (equal (prd$h-arv k (+ 1 k) envs outs) (prd-h-arv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-arv prd-h-arv-at) (nth nthcdr take len)))))
(defthm prd$h-childfault-is-at
  (equal (prd$h-childfault k (+ 1 k) envs outs) (prd-h-childfault-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-childfault prd-h-childfault-at) (nth nthcdr take len)))))
(defthm prd$h-dbusy-is-at
  (equal (prd$h-dbusy k (+ 1 k) envs outs) (prd-h-dbusy-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-dbusy prd-h-dbusy-at) (nth nthcdr take len)))))
(defthm prd$h-grd-is-at
  (equal (prd$h-grd k (+ 1 k) envs outs) (prd-h-grd-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-grd prd-h-grd-at) (nth nthcdr take len)))))
(defthm prd$h-haf-is-at
  (equal (prd$h-haf k (+ 1 k) envs outs) (prd-h-haf-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-haf prd-h-haf-at) (nth nthcdr take len)))))
(defthm prd$h-hdf-is-at
  (equal (prd$h-hdf k (+ 1 k) envs outs) (prd-h-hdf-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-hdf prd-h-hdf-at) (nth nthcdr take len)))))
(defthm prd$h-hsr-is-at
  (equal (prd$h-hsr k (+ 1 k) envs outs) (prd-h-hsr-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-hsr prd-h-hsr-at) (nth nthcdr take len)))))
(defthm prd$h-hsv-is-at
  (equal (prd$h-hsv k (+ 1 k) envs outs) (prd-h-hsv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-hsv prd-h-hsv-at) (nth nthcdr take len)))))
(defthm prd$h-kcr-is-at
  (equal (prd$h-kcr k (+ 1 k) envs outs) (prd-h-kcr-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-kcr prd-h-kcr-at) (nth nthcdr take len)))))
(defthm prd$h-kpc-is-at
  (equal (prd$h-kpc k (+ 1 k) envs outs) (prd-h-kpc-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-kpc prd-h-kpc-at) (nth nthcdr take len)))))
(defthm prd$h-lli-is-at
  (equal (prd$h-lli k (+ 1 k) envs outs) (prd-h-lli-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-lli prd-h-lli-at) (nth nthcdr take len)))))
(defthm prd$h-llr-is-at
  (equal (prd$h-llr k (+ 1 k) envs outs) (prd-h-llr-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-llr prd-h-llr-at) (nth nthcdr take len)))))
(defthm prd$h-lrf-is-at
  (equal (prd$h-lrf k (+ 1 k) envs outs) (prd-h-lrf-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-lrf prd-h-lrf-at) (nth nthcdr take len)))))
(defthm prd$h-lrv-is-at
  (equal (prd$h-lrv k (+ 1 k) envs outs) (prd-h-lrv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-lrv prd-h-lrv-at) (nth nthcdr take len)))))
(defthm prd$h-lsv-is-at
  (equal (prd$h-lsv k (+ 1 k) envs outs) (prd-h-lsv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-lsv prd-h-lsv-at) (nth nthcdr take len)))))
(defthm prd$h-ndv-is-at
  (equal (prd$h-ndv k (+ 1 k) envs outs) (prd-h-ndv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-ndv prd-h-ndv-at) (nth nthcdr take len)))))
(defthm prd$h-nre-is-at
  (equal (prd$h-nre k (+ 1 k) envs outs) (prd-h-nre-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-nre prd-h-nre-at) (nth nthcdr take len)))))
(defthm prd$h-nri-is-at
  (equal (prd$h-nri k (+ 1 k) envs outs) (prd-h-nri-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-nri prd-h-nri-at) (nth nthcdr take len)))))
(defthm prd$h-nrl-is-at
  (equal (prd$h-nrl k (+ 1 k) envs outs) (prd-h-nrl-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-nrl prd-h-nrl-at) (nth nthcdr take len)))))
(defthm prd$h-nrm-is-at
  (equal (prd$h-nrm k (+ 1 k) envs outs) (prd-h-nrm-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-nrm prd-h-nrm-at) (nth nthcdr take len)))))
(defthm prd$h-nrv-is-at
  (equal (prd$h-nrv k (+ 1 k) envs outs) (prd-h-nrv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-nrv prd-h-nrv-at) (nth nthcdr take len)))))
(defthm prd$h-paf-is-at
  (equal (prd$h-paf k (+ 1 k) envs outs) (prd-h-paf-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-paf prd-h-paf-at) (nth nthcdr take len)))))
(defthm prd$h-pdv-is-at
  (equal (prd$h-pdv k (+ 1 k) envs outs) (prd-h-pdv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-pdv prd-h-pdv-at) (nth nthcdr take len)))))
(defthm prd$h-rdv-is-at
  (equal (prd$h-rdv k (+ 1 k) envs outs) (prd-h-rdv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-rdv prd-h-rdv-at) (nth nthcdr take len)))))
(defthm prd$h-rif-is-at
  (equal (prd$h-rif k (+ 1 k) envs outs) (prd-h-rif-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-rif prd-h-rif-at) (nth nthcdr take len)))))
(defthm prd$h-rri-is-at
  (equal (prd$h-rri k (+ 1 k) envs outs) (prd-h-rri-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-rri prd-h-rri-at) (nth nthcdr take len)))))
(defthm prd$h-rrl-is-at
  (equal (prd$h-rrl k (+ 1 k) envs outs) (prd-h-rrl-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-rrl prd-h-rrl-at) (nth nthcdr take len)))))
(defthm prd$h-rrv-is-at
  (equal (prd$h-rrv k (+ 1 k) envs outs) (prd-h-rrv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-rrv prd-h-rrv-at) (nth nthcdr take len)))))
(defthm prd$h-rterm-is-at
  (equal (prd$h-rterm k (+ 1 k) envs outs) (prd-h-rterm-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-rterm prd-h-rterm-at) (nth nthcdr take len)))))
(defthm prd$h-sbr-is-at
  (equal (prd$h-sbr k (+ 1 k) envs outs) (prd-h-sbr-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-sbr prd-h-sbr-at) (nth nthcdr take len)))))
(defthm prd$h-sdf-is-at
  (equal (prd$h-sdf k (+ 1 k) envs outs) (prd-h-sdf-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-sdf prd-h-sdf-at) (nth nthcdr take len)))))
(defthm prd$h-sfpos-is-at
  (equal (prd$h-sfpos k (+ 1 k) envs outs) (prd-h-sfpos-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-sfpos prd-h-sfpos-at) (nth nthcdr take len)))))
(defthm prd$h-siexp-is-at
  (equal (prd$h-siexp k (+ 1 k) envs outs) (prd-h-siexp-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-siexp prd-h-siexp-at) (nth nthcdr take len)))))
(defthm prd$h-sif-is-at
  (equal (prd$h-sif k (+ 1 k) envs outs) (prd-h-sif-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-sif prd-h-sif-at) (nth nthcdr take len)))))
(defthm prd$h-sil-is-at
  (equal (prd$h-sil k (+ 1 k) envs outs) (prd-h-sil-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-sil prd-h-sil-at) (nth nthcdr take len)))))
(defthm prd$h-spm-is-at
  (equal (prd$h-spm k (+ 1 k) envs outs) (prd-h-spm-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-spm prd-h-spm-at) (nth nthcdr take len)))))
(defthm prd$h-spr-is-at
  (equal (prd$h-spr k (+ 1 k) envs outs) (prd-h-spr-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-spr prd-h-spr-at) (nth nthcdr take len)))))
(defthm prd$h-srexp-is-at
  (equal (prd$h-srexp k (+ 1 k) envs outs) (prd-h-srexp-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-srexp prd-h-srexp-at) (nth nthcdr take len)))))
(defthm prd$h-srf-is-at
  (equal (prd$h-srf k (+ 1 k) envs outs) (prd-h-srf-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-srf prd-h-srf-at) (nth nthcdr take len)))))
(defthm prd$h-srman-is-at
  (equal (prd$h-srman k (+ 1 k) envs outs) (prd-h-srman-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$h-srman prd-h-srman-at) (nth nthcdr take len)))))
(defthm prd$i-clear-is-at
  (equal (prd$i-clear k (+ 1 k) envs outs) (prd-i-clear-at k envs))
  :hints (("Goal" :in-theory (e/d (prd$i-clear prd-i-clear-at) (nth nthcdr take len)))))
(defthm prd$i-reset-n-is-at
  (equal (prd$i-reset-n k (+ 1 k) envs outs) (prd-i-reset-n-at k envs))
  :hints (("Goal" :in-theory (e/d (prd$i-reset-n prd-i-reset-n-at) (nth nthcdr take len)))))
(defthm prd$n-d-clay-is-at
  (equal (prd$n-d-clay k (+ 1 k) envs outs) (prd-d-clay-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-clay prd$r-d-clay prd-d-clay-at) (nth nthcdr take len)))))
(defthm prd$n-d-cpos-is-at
  (equal (prd$n-d-cpos k (+ 1 k) envs outs) (prd-d-cpos-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-cpos prd$r-d-cpos prd-d-cpos-at) (nth nthcdr take len)))))
(defthm prd$n-d-cst-is-at
  (equal (prd$n-d-cst k (+ 1 k) envs outs) (prd-d-cst-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-cst prd$r-d-cst prd-d-cst-at) (nth nthcdr take len)))))
(defthm prd$n-d-elay-is-at
  (equal (prd$n-d-elay k (+ 1 k) envs outs) (prd-d-elay-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-elay prd$r-d-elay prd-d-elay-at) (nth nthcdr take len)))))
(defthm prd$n-d-eng-is-at
  (equal (prd$n-d-eng k (+ 1 k) envs outs) (prd-d-eng-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-eng prd$r-d-eng prd-d-eng-at) (nth nthcdr take len)))))
(defthm prd$n-d-est-is-at
  (equal (prd$n-d-est k (+ 1 k) envs outs) (prd-d-est-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-est prd$r-d-est prd-d-est-at) (nth nthcdr take len)))))
(defthm prd$n-d-fault-is-at
  (equal (prd$n-d-fault k (+ 1 k) envs outs) (prd-d-fault-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-fault prd$r-d-fault prd-d-fault-at) (nth nthcdr take len)))))
(defthm prd$n-d-iidx-is-at
  (equal (prd$n-d-iidx k (+ 1 k) envs outs) (prd-d-iidx-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-iidx prd$r-d-iidx prd-d-iidx-at) (nth nthcdr take len)))))
(defthm prd$n-d-kexp-is-at
  (equal (prd$n-d-kexp k (+ 1 k) envs outs) (prd-d-kexp-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-kexp prd$r-d-kexp prd-d-kexp-at) (nth nthcdr take len)))))
(defthm prd$n-d-kmem-is-at
  (equal (prd$n-d-kmem k (+ 1 k) envs outs) (prd-d-kmem-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-kmem prd$r-d-kmem prd-d-kmem-at) (nth nthcdr take len)))))
(defthm prd$n-d-krd-is-at
  (equal (prd$n-d-krd k (+ 1 k) envs outs) (prd-d-krd-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-krd prd$r-d-krd prd-d-krd-at) (nth nthcdr take len)))))
(defthm prd$n-d-kvrv-is-at
  (equal (prd$n-d-kvrv k (+ 1 k) envs outs) (prd-d-kvrv-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-kvrv prd$r-d-kvrv prd-d-kvrv-at) (nth nthcdr take len)))))
(defthm prd$n-d-lseen-is-at
  (equal (prd$n-d-lseen k (+ 1 k) envs outs) (prd-d-lseen-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-lseen prd$r-d-lseen prd-d-lseen-at) (nth nthcdr take len)))))
(defthm prd$n-d-odone-is-at
  (equal (prd$n-d-odone k (+ 1 k) envs outs) (prd-d-odone-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-odone prd$r-d-odone prd-d-odone-at) (nth nthcdr take len)))))
(defthm prd$n-d-oidx-is-at
  (equal (prd$n-d-oidx k (+ 1 k) envs outs) (prd-d-oidx-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-oidx prd$r-d-oidx prd-d-oidx-at) (nth nthcdr take len)))))
(defthm prd$n-d-sdone-is-at
  (equal (prd$n-d-sdone k (+ 1 k) envs outs) (prd-d-sdone-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-sdone prd$r-d-sdone prd-d-sdone-at) (nth nthcdr take len)))))
(defthm prd$n-d-tpos-is-at
  (equal (prd$n-d-tpos k (+ 1 k) envs outs) (prd-d-tpos-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-tpos prd$r-d-tpos prd-d-tpos-at) (nth nthcdr take len)))))
(defthm prd$n-d-tseen-is-at
  (equal (prd$n-d-tseen k (+ 1 k) envs outs) (prd-d-tseen-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-tseen prd$r-d-tseen prd-d-tseen-at) (nth nthcdr take len)))))
(defthm prd$n-d-vexp-is-at
  (equal (prd$n-d-vexp k (+ 1 k) envs outs) (prd-d-vexp-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-vexp prd$r-d-vexp prd-d-vexp-at) (nth nthcdr take len)))))
(defthm prd$n-d-vmem-is-at
  (equal (prd$n-d-vmem k (+ 1 k) envs outs) (prd-d-vmem-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-vmem prd$r-d-vmem prd-d-vmem-at) (nth nthcdr take len)))))
(defthm prd$n-d-vrd-is-at
  (equal (prd$n-d-vrd k (+ 1 k) envs outs) (prd-d-vrd-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-d-vrd prd$r-d-vrd prd-d-vrd-at) (nth nthcdr take len)))))
(defthm prd$n-m-rel-is-at
  (equal (prd$n-m-rel k (+ 1 k) envs outs) (prd-m-rel-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-m-rel prd$r-m-rel prd-m-rel-at) (nth nthcdr take len)))))
(defthm prd$n-s-fault-is-at
  (equal (prd$n-s-fault k (+ 1 k) envs outs) (prd-s-fault-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-s-fault prd$r-s-fault prd-s-fault-at) (nth nthcdr take len)))))
(defthm prd$n-s-layer-is-at
  (equal (prd$n-s-layer k (+ 1 k) envs outs) (prd-s-layer-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-s-layer prd$r-s-layer prd-s-layer-at) (nth nthcdr take len)))))
(defthm prd$n-s-pos-is-at
  (equal (prd$n-s-pos k (+ 1 k) envs outs) (prd-s-pos-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-s-pos prd$r-s-pos prd-s-pos-at) (nth nthcdr take len)))))
(defthm prd$n-s-stage-is-at
  (equal (prd$n-s-stage k (+ 1 k) envs outs) (prd-s-stage-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-s-stage prd$r-s-stage prd-s-stage-at) (nth nthcdr take len)))))
(defthm prd$n-s-state-is-at
  (equal (prd$n-s-state k (+ 1 k) envs outs) (prd-s-state-at (+ 1 k) outs))
  :hints (("Goal" :in-theory (e/d (prd$n-s-state prd$r-s-state prd-s-state-at) (nth nthcdr take len)))))
(defthm prd$o-dpclear-is-at
  (equal (prd$o-dpclear k (+ 1 k) envs outs) (prd-o-dpclear-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-dpclear prd-o-dpclear-at) (nth nthcdr take len)))))
(defthm prd$o-dprst-is-at
  (equal (prd$o-dprst k (+ 1 k) envs outs) (prd-o-dprst-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-dprst prd-o-dprst-at) (nth nthcdr take len)))))
(defthm prd$o-kra-is-at
  (equal (prd$o-kra k (+ 1 k) envs outs) (prd-o-kra-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-kra prd-o-kra-at) (nth nthcdr take len)))))
(defthm prd$o-kre-is-at
  (equal (prd$o-kre k (+ 1 k) envs outs) (prd-o-kre-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-kre prd-o-kre-at) (nth nthcdr take len)))))
(defthm prd$o-kwe-is-at
  (equal (prd$o-kwe k (+ 1 k) envs outs) (prd-o-kwe-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-kwe prd-o-kwe-at) (nth nthcdr take len)))))
(defthm prd$o-layerfail-is-at
  (equal (prd$o-layerfail k (+ 1 k) envs outs) (prd-o-layerfail-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-layerfail prd-o-layerfail-at) (nth nthcdr take len)))))
(defthm prd$o-player-is-at
  (equal (prd$o-player k (+ 1 k) envs outs) (prd-o-player-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-player prd-o-player-at) (nth nthcdr take len)))))
(defthm prd$o-ppos-is-at
  (equal (prd$o-ppos k (+ 1 k) envs outs) (prd-o-ppos-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-ppos prd-o-ppos-at) (nth nthcdr take len)))))
(defthm prd$o-pstage-is-at
  (equal (prd$o-pstage k (+ 1 k) envs outs) (prd-o-pstage-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-pstage prd-o-pstage-at) (nth nthcdr take len)))))
(defthm prd$o-sacc-is-at
  (equal (prd$o-sacc k (+ 1 k) envs outs) (prd-o-sacc-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-sacc prd-o-sacc-at) (nth nthcdr take len)))))
(defthm prd$o-sbv-is-at
  (equal (prd$o-sbv k (+ 1 k) envs outs) (prd-o-sbv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-sbv prd-o-sbv-at) (nth nthcdr take len)))))
(defthm prd$o-sfire-is-at
  (equal (prd$o-sfire k (+ 1 k) envs outs) (prd-o-sfire-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-sfire prd-o-sfire-at) (nth nthcdr take len)))))
(defthm prd$o-spv-is-at
  (equal (prd$o-spv k (+ 1 k) envs outs) (prd-o-spv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-spv prd-o-spv-at) (nth nthcdr take len)))))
(defthm prd$o-vra-is-at
  (equal (prd$o-vra k (+ 1 k) envs outs) (prd-o-vra-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-vra prd-o-vra-at) (nth nthcdr take len)))))
(defthm prd$o-vre-is-at
  (equal (prd$o-vre k (+ 1 k) envs outs) (prd-o-vre-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-vre prd-o-vre-at) (nth nthcdr take len)))))
(defthm prd$o-vwe-is-at
  (equal (prd$o-vwe k (+ 1 k) envs outs) (prd-o-vwe-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$o-vwe prd-o-vwe-at) (nth nthcdr take len)))))
(defthm prd$r-d-arhead-is-at
  (equal (prd$r-d-arhead k (+ 1 k) envs outs) (prd-d-arhead-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-arhead prd-d-arhead-at) (nth nthcdr take len)))))
(defthm prd$r-d-aslane-is-at
  (equal (prd$r-d-aslane k (+ 1 k) envs outs) (prd-d-aslane-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-aslane prd-d-aslane-at) (nth nthcdr take len)))))
(defthm prd$r-d-clay-is-at
  (equal (prd$r-d-clay k (+ 1 k) envs outs) (prd-d-clay-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-clay prd-d-clay-at) (nth nthcdr take len)))))
(defthm prd$r-d-cpos-is-at
  (equal (prd$r-d-cpos k (+ 1 k) envs outs) (prd-d-cpos-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-cpos prd-d-cpos-at) (nth nthcdr take len)))))
(defthm prd$r-d-cst-is-at
  (equal (prd$r-d-cst k (+ 1 k) envs outs) (prd-d-cst-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-cst prd-d-cst-at) (nth nthcdr take len)))))
(defthm prd$r-d-elay-is-at
  (equal (prd$r-d-elay k (+ 1 k) envs outs) (prd-d-elay-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-elay prd-d-elay-at) (nth nthcdr take len)))))
(defthm prd$r-d-eng-is-at
  (equal (prd$r-d-eng k (+ 1 k) envs outs) (prd-d-eng-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-eng prd-d-eng-at) (nth nthcdr take len)))))
(defthm prd$r-d-ephase-is-at
  (equal (prd$r-d-ephase k (+ 1 k) envs outs) (prd-d-ephase-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-ephase prd-d-ephase-at) (nth nthcdr take len)))))
(defthm prd$r-d-est-is-at
  (equal (prd$r-d-est k (+ 1 k) envs outs) (prd-d-est-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-est prd-d-est-at) (nth nthcdr take len)))))
(defthm prd$r-d-fault-is-at
  (equal (prd$r-d-fault k (+ 1 k) envs outs) (prd-d-fault-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-fault prd-d-fault-at) (nth nthcdr take len)))))
(defthm prd$r-d-gexp-is-at
  (equal (prd$r-d-gexp k (+ 1 k) envs outs) (prd-d-gexp-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-gexp prd-d-gexp-at) (nth nthcdr take len)))))
(defthm prd$r-d-idone-is-at
  (equal (prd$r-d-idone k (+ 1 k) envs outs) (prd-d-idone-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-idone prd-d-idone-at) (nth nthcdr take len)))))
(defthm prd$r-d-iidx-is-at
  (equal (prd$r-d-iidx k (+ 1 k) envs outs) (prd-d-iidx-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-iidx prd-d-iidx-at) (nth nthcdr take len)))))
(defthm prd$r-d-kexp-is-at
  (equal (prd$r-d-kexp k (+ 1 k) envs outs) (prd-d-kexp-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-kexp prd-d-kexp-at) (nth nthcdr take len)))))
(defthm prd$r-d-kmem-is-at
  (equal (prd$r-d-kmem k (+ 1 k) envs outs) (prd-d-kmem-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-kmem prd-d-kmem-at) (nth nthcdr take len)))))
(defthm prd$r-d-krd-is-at
  (equal (prd$r-d-krd k (+ 1 k) envs outs) (prd-d-krd-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-krd prd-d-krd-at) (nth nthcdr take len)))))
(defthm prd$r-d-kvrv-is-at
  (equal (prd$r-d-kvrv k (+ 1 k) envs outs) (prd-d-kvrv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-kvrv prd-d-kvrv-at) (nth nthcdr take len)))))
(defthm prd$r-d-lseen-is-at
  (equal (prd$r-d-lseen k (+ 1 k) envs outs) (prd-d-lseen-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-lseen prd-d-lseen-at) (nth nthcdr take len)))))
(defthm prd$r-d-nds-is-at
  (equal (prd$r-d-nds k (+ 1 k) envs outs) (prd-d-nds-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-nds prd-d-nds-at) (nth nthcdr take len)))))
(defthm prd$r-d-odone-is-at
  (equal (prd$r-d-odone k (+ 1 k) envs outs) (prd-d-odone-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-odone prd-d-odone-at) (nth nthcdr take len)))))
(defthm prd$r-d-oidx-is-at
  (equal (prd$r-d-oidx k (+ 1 k) envs outs) (prd-d-oidx-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-oidx prd-d-oidx-at) (nth nthcdr take len)))))
(defthm prd$r-d-rhalf-is-at
  (equal (prd$r-d-rhalf k (+ 1 k) envs outs) (prd-d-rhalf-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-rhalf prd-d-rhalf-at) (nth nthcdr take len)))))
(defthm prd$r-d-rhead-is-at
  (equal (prd$r-d-rhead k (+ 1 k) envs outs) (prd-d-rhead-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-rhead prd-d-rhead-at) (nth nthcdr take len)))))
(defthm prd$r-d-rphase-is-at
  (equal (prd$r-d-rphase k (+ 1 k) envs outs) (prd-d-rphase-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-rphase prd-d-rphase-at) (nth nthcdr take len)))))
(defthm prd$r-d-rsecond-is-at
  (equal (prd$r-d-rsecond k (+ 1 k) envs outs) (prd-d-rsecond-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-rsecond prd-d-rsecond-at) (nth nthcdr take len)))))
(defthm prd$r-d-sdone-is-at
  (equal (prd$r-d-sdone k (+ 1 k) envs outs) (prd-d-sdone-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-sdone prd-d-sdone-at) (nth nthcdr take len)))))
(defthm prd$r-d-sds-is-at
  (equal (prd$r-d-sds k (+ 1 k) envs outs) (prd-d-sds-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-sds prd-d-sds-at) (nth nthcdr take len)))))
(defthm prd$r-d-sss-is-at
  (equal (prd$r-d-sss k (+ 1 k) envs outs) (prd-d-sss-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-sss prd-d-sss-at) (nth nthcdr take len)))))
(defthm prd$r-d-svv-is-at
  (equal (prd$r-d-svv k (+ 1 k) envs outs) (prd-d-svv-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-svv prd-d-svv-at) (nth nthcdr take len)))))
(defthm prd$r-d-tpos-is-at
  (equal (prd$r-d-tpos k (+ 1 k) envs outs) (prd-d-tpos-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-tpos prd-d-tpos-at) (nth nthcdr take len)))))
(defthm prd$r-d-tseen-is-at
  (equal (prd$r-d-tseen k (+ 1 k) envs outs) (prd-d-tseen-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-tseen prd-d-tseen-at) (nth nthcdr take len)))))
(defthm prd$r-d-vexp-is-at
  (equal (prd$r-d-vexp k (+ 1 k) envs outs) (prd-d-vexp-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-vexp prd-d-vexp-at) (nth nthcdr take len)))))
(defthm prd$r-d-vmem-is-at
  (equal (prd$r-d-vmem k (+ 1 k) envs outs) (prd-d-vmem-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-vmem prd-d-vmem-at) (nth nthcdr take len)))))
(defthm prd$r-d-vrd-is-at
  (equal (prd$r-d-vrd k (+ 1 k) envs outs) (prd-d-vrd-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-d-vrd prd-d-vrd-at) (nth nthcdr take len)))))
(defthm prd$r-l-coll-is-at
  (equal (prd$r-l-coll k (+ 1 k) envs outs) (prd-l-coll-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-l-coll prd-l-coll-at) (nth nthcdr take len)))))
(defthm prd$r-m-rel-is-at
  (equal (prd$r-m-rel k (+ 1 k) envs outs) (prd-m-rel-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-m-rel prd-m-rel-at) (nth nthcdr take len)))))
(defthm prd$r-p-lock-sync-is-at
  (equal (prd$r-p-lock-sync k (+ 1 k) envs outs) (prd-p-lock-sync-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-p-lock-sync prd-p-lock-sync-at) (nth nthcdr take len)))))
(defthm prd$r-s-fault-is-at
  (equal (prd$r-s-fault k (+ 1 k) envs outs) (prd-s-fault-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-fault prd-s-fault-at) (nth nthcdr take len)))))
(defthm prd$r-s-layer-is-at
  (equal (prd$r-s-layer k (+ 1 k) envs outs) (prd-s-layer-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-layer prd-s-layer-at) (nth nthcdr take len)))))
(defthm prd$r-s-lseen-is-at
  (equal (prd$r-s-lseen k (+ 1 k) envs outs) (prd-s-lseen-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-lseen prd-s-lseen-at) (nth nthcdr take len)))))
(defthm prd$r-s-pos-is-at
  (equal (prd$r-s-pos k (+ 1 k) envs outs) (prd-s-pos-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-pos prd-s-pos-at) (nth nthcdr take len)))))
(defthm prd$r-s-rexp-is-at
  (equal (prd$r-s-rexp k (+ 1 k) envs outs) (prd-s-rexp-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-rexp prd-s-rexp-at) (nth nthcdr take len)))))
(defthm prd$r-s-sidx-is-at
  (equal (prd$r-s-sidx k (+ 1 k) envs outs) (prd-s-sidx-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-sidx prd-s-sidx-at) (nth nthcdr take len)))))
(defthm prd$r-s-stage-is-at
  (equal (prd$r-s-stage k (+ 1 k) envs outs) (prd-s-stage-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-stage prd-s-stage-at) (nth nthcdr take len)))))
(defthm prd$r-s-state-is-at
  (equal (prd$r-s-state k (+ 1 k) envs outs) (prd-s-state-at k outs))
  :hints (("Goal" :in-theory (e/d (prd$r-s-state prd-s-state-at) (nth nthcdr take len)))))
(value-triple (acl2::cw "~%PRD-SIGNALS done~%"))

; ---------------------------------------------------------------------------
; THE PRODUCER FACTS AT CYCLE k OF AN EXECUTION.
; ---------------------------------------------------------------------------
; The step lemma's conclusion about cycle k.
(define prod-facts-at (k envs outs) :verify-guards nil
  (prod-step-all (prd$h-kpc k (+ 1 k) envs outs)
                 (prd$h-lsv k (+ 1 k) envs outs)
                 (prd$h-nre k (+ 1 k) envs outs)
                 (prd$h-nri k (+ 1 k) envs outs)
                 (prd$h-nrl k (+ 1 k) envs outs)
                 (prd$h-nrm k (+ 1 k) envs outs)
                 (prd$h-nrv k (+ 1 k) envs outs)
                 (prd$h-sdf k (+ 1 k) envs outs)
                 (prd$h-sfpos k (+ 1 k) envs outs)
                 (prd$i-clear k (+ 1 k) envs outs)
                 (prd$i-reset-n k (+ 1 k) envs outs)
                 (prd$n-d-clay k (+ 1 k) envs outs)
                 (prd$n-d-cpos k (+ 1 k) envs outs)
                 (prd$n-d-cst k (+ 1 k) envs outs)
                 (prd$n-d-elay k (+ 1 k) envs outs)
                 (prd$n-d-eng k (+ 1 k) envs outs)
                 (prd$n-d-est k (+ 1 k) envs outs)
                 (prd$n-d-fault k (+ 1 k) envs outs)
                 (prd$n-d-iidx k (+ 1 k) envs outs)
                 (prd$n-d-kexp k (+ 1 k) envs outs)
                 (prd$n-d-kmem k (+ 1 k) envs outs)
                 (prd$n-d-krd k (+ 1 k) envs outs)
                 (prd$n-d-kvrv k (+ 1 k) envs outs)
                 (prd$n-d-lseen k (+ 1 k) envs outs)
                 (prd$n-d-odone k (+ 1 k) envs outs)
                 (prd$n-d-oidx k (+ 1 k) envs outs)
                 (prd$n-d-sdone k (+ 1 k) envs outs)
                 (prd$n-d-tpos k (+ 1 k) envs outs)
                 (prd$n-d-tseen k (+ 1 k) envs outs)
                 (prd$n-d-vexp k (+ 1 k) envs outs)
                 (prd$n-d-vmem k (+ 1 k) envs outs)
                 (prd$n-d-vrd k (+ 1 k) envs outs)
                 (prd$n-m-rel k (+ 1 k) envs outs)
                 (prd$n-s-fault k (+ 1 k) envs outs)
                 (prd$n-s-layer k (+ 1 k) envs outs)
                 (prd$n-s-pos k (+ 1 k) envs outs)
                 (prd$n-s-stage k (+ 1 k) envs outs)
                 (prd$n-s-state k (+ 1 k) envs outs)
                 (prd$o-dpclear k (+ 1 k) envs outs)
                 (prd$o-dprst k (+ 1 k) envs outs)
                 (prd$o-kra k (+ 1 k) envs outs)
                 (prd$o-kre k (+ 1 k) envs outs)
                 (prd$o-kwe k (+ 1 k) envs outs)
                 (prd$o-layerfail k (+ 1 k) envs outs)
                 (prd$o-player k (+ 1 k) envs outs)
                 (prd$o-ppos k (+ 1 k) envs outs)
                 (prd$o-pstage k (+ 1 k) envs outs)
                 (prd$o-sacc k (+ 1 k) envs outs)
                 (prd$o-sbv k (+ 1 k) envs outs)
                 (prd$o-sfire k (+ 1 k) envs outs)
                 (prd$o-spv k (+ 1 k) envs outs)
                 (prd$o-vra k (+ 1 k) envs outs)
                 (prd$o-vre k (+ 1 k) envs outs)
                 (prd$o-vwe k (+ 1 k) envs outs)
                 (prd$r-d-clay k (+ 1 k) envs outs)
                 (prd$r-d-cpos k (+ 1 k) envs outs)
                 (prd$r-d-cst k (+ 1 k) envs outs)
                 (prd$r-d-elay k (+ 1 k) envs outs)
                 (prd$r-d-eng k (+ 1 k) envs outs)
                 (prd$r-d-est k (+ 1 k) envs outs)
                 (prd$r-d-fault k (+ 1 k) envs outs)
                 (prd$r-d-iidx k (+ 1 k) envs outs)
                 (prd$r-d-kexp k (+ 1 k) envs outs)
                 (prd$r-d-kmem k (+ 1 k) envs outs)
                 (prd$r-d-krd k (+ 1 k) envs outs)
                 (prd$r-d-kvrv k (+ 1 k) envs outs)
                 (prd$r-d-lseen k (+ 1 k) envs outs)
                 (prd$r-d-odone k (+ 1 k) envs outs)
                 (prd$r-d-oidx k (+ 1 k) envs outs)
                 (prd$r-d-sdone k (+ 1 k) envs outs)
                 (prd$r-d-sss k (+ 1 k) envs outs)
                 (prd$r-d-tpos k (+ 1 k) envs outs)
                 (prd$r-d-tseen k (+ 1 k) envs outs)
                 (prd$r-d-vexp k (+ 1 k) envs outs)
                 (prd$r-d-vmem k (+ 1 k) envs outs)
                 (prd$r-d-vrd k (+ 1 k) envs outs)
                 (prd$r-l-coll k (+ 1 k) envs outs)
                 (prd$r-m-rel k (+ 1 k) envs outs)
                 (prd$r-s-fault k (+ 1 k) envs outs)
                 (prd$r-s-layer k (+ 1 k) envs outs)
                 (prd$r-s-pos k (+ 1 k) envs outs)
                 (prd$r-s-stage k (+ 1 k) envs outs)
                 (prd$r-s-state k (+ 1 k) envs outs)))
; Every signal the step lemma takes a value for, other than the two working
; memories, is two-valued in cycle k.
(define prod-env-at (k envs outs) :verify-guards nil
  (and (unsigned-byte-p 1 (prd$r-p-lock-sync k (+ 1 k) envs outs))
       (unsigned-byte-p 2 (prd$r-m-rel k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-l-coll k (+ 1 k) envs outs))
       (unsigned-byte-p 3 (prd$r-s-state k (+ 1 k) envs outs))
       (unsigned-byte-p 3 (prd$r-s-layer k (+ 1 k) envs outs))
       (unsigned-byte-p 5 (prd$r-s-stage k (+ 1 k) envs outs))
       (unsigned-byte-p 11 (prd$r-s-pos k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-s-fault k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-s-lseen k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$r-s-sidx k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$r-s-rexp k (+ 1 k) envs outs))
       (unsigned-byte-p 4 (prd$r-d-eng k (+ 1 k) envs outs))
       (unsigned-byte-p 5 (prd$r-d-cst k (+ 1 k) envs outs))
       (unsigned-byte-p 3 (prd$r-d-clay k (+ 1 k) envs outs))
       (unsigned-byte-p 11 (prd$r-d-cpos k (+ 1 k) envs outs))
       (unsigned-byte-p 5 (prd$r-d-est k (+ 1 k) envs outs))
       (unsigned-byte-p 3 (prd$r-d-elay k (+ 1 k) envs outs))
       (unsigned-byte-p 11 (prd$r-d-tpos k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-tseen k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-fault k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-lseen k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-sdone k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$r-d-kexp k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$r-d-vexp k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-sss k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-odone k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-sds k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-nds k (+ 1 k) envs outs))
       (unsigned-byte-p 10 (prd$r-d-iidx k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-idone k (+ 1 k) envs outs))
       (unsigned-byte-p 10 (prd$r-d-oidx k (+ 1 k) envs outs))
       (unsigned-byte-p 4 (prd$r-d-rphase k (+ 1 k) envs outs))
       (unsigned-byte-p 2 (prd$r-d-rhead k (+ 1 k) envs outs))
       (unsigned-byte-p 5 (prd$r-d-rhalf k (+ 1 k) envs outs))
       (unsigned-byte-p 5 (prd$r-d-rsecond k (+ 1 k) envs outs))
       (unsigned-byte-p 3 (prd$r-d-arhead k (+ 1 k) envs outs))
       (unsigned-byte-p 6 (prd$r-d-aslane k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-svv k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$r-d-gexp k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$r-d-kvrv k (+ 1 k) envs outs))
       (unsigned-byte-p 3 (prd$r-d-ephase k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (prd$r-d-krd k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (prd$r-d-vrd k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-rterm k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-childfault k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-nrv k (+ 1 k) envs outs))
       (unsigned-byte-p 10 (prd$h-nri k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (prd$h-nrm k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$h-nre k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-nrl k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-ndv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-pdv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-rrv k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$h-rri k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-rrl k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-rdv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-hdf k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-lrv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-lrf k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-arv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-arl k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-adv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-llr k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (prd$h-lli k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (prd$h-grd k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-kcr k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-sbr k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-spr k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-kpc k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-hsr k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-rif k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-paf k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-haf k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-hsv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-lsv k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-dbusy k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-sif k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-sil k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-spm k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$h-siexp k (+ 1 k) envs outs))
       (unsigned-byte-p 11 (prd$h-sfpos k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-sdf k (+ 1 k) envs outs))
       (unsigned-byte-p 1 (prd$h-srf k (+ 1 k) envs outs))
       (unsigned-byte-p 8 (prd$h-srexp k (+ 1 k) envs outs))
       (unsigned-byte-p 16 (prd$h-srman k (+ 1 k) envs outs))))
; The two working memories hold definite values in cycle k.
(define prod-mem-at (k outs) :verify-guards nil
  (and (unsigned-byte-p 2048 (prd-d-kmem-at k outs))
       (unsigned-byte-p 2048 (prd-d-vmem-at k outs))))

; One cycle: from the environment, two-valued producer signals and definite
; working memories at cycle k to the producer facts about cycle k.
(defthm prod-step-glue
  (implies (and (natp k)
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at k (fsm-eval envs initst (probe-fsm))))
           (prod-facts-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance prod-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-producer-run-constraints))
           :in-theory (e/d (join-env-at join-env-raw joint-env-p
                            prod-env-at prod-mem-at prod-facts-at
                            prd-d-kmem-at prd-d-vmem-at
                            prd$h-adv prd$h-arl prd$h-arv prd$h-childfault prd$h-dbusy prd$h-grd prd$h-haf prd$h-hdf prd$h-hsr prd$h-hsv prd$h-kcr prd$h-kpc prd$h-lli prd$h-llr prd$h-lrf prd$h-lrv prd$h-lsv prd$h-ndv prd$h-nre prd$h-nri prd$h-nrl prd$h-nrm prd$h-nrv prd$h-paf prd$h-pdv prd$h-rdv prd$h-rif prd$h-rri prd$h-rrl prd$h-rrv prd$h-rterm prd$h-sbr prd$h-sdf prd$h-sfpos prd$h-siexp prd$h-sif prd$h-sil prd$h-spm prd$h-spr prd$h-srexp prd$h-srf prd$h-srman prd$i-clear prd$i-reset-n prd$n-d-clay prd$n-d-cpos prd$n-d-cst prd$n-d-elay prd$n-d-eng prd$n-d-est prd$n-d-fault prd$n-d-iidx prd$n-d-kexp prd$n-d-kmem prd$n-d-krd prd$n-d-kvrv prd$n-d-lseen prd$n-d-odone prd$n-d-oidx prd$n-d-sdone prd$n-d-tpos prd$n-d-tseen prd$n-d-vexp prd$n-d-vmem prd$n-d-vrd prd$n-m-rel prd$n-s-fault prd$n-s-layer prd$n-s-pos prd$n-s-stage prd$n-s-state prd$o-dpclear prd$o-dprst prd$o-kra prd$o-kre prd$o-kwe prd$o-layerfail prd$o-player prd$o-ppos prd$o-pstage prd$o-sacc prd$o-sbv prd$o-sfire prd$o-spv prd$o-vra prd$o-vre prd$o-vwe prd$r-d-arhead prd$r-d-aslane prd$r-d-clay prd$r-d-cpos prd$r-d-cst prd$r-d-elay prd$r-d-eng prd$r-d-ephase prd$r-d-est prd$r-d-fault prd$r-d-gexp prd$r-d-idone prd$r-d-iidx prd$r-d-kexp prd$r-d-kmem prd$r-d-krd prd$r-d-kvrv prd$r-d-lseen prd$r-d-nds prd$r-d-odone prd$r-d-oidx prd$r-d-rhalf prd$r-d-rhead prd$r-d-rphase prd$r-d-rsecond prd$r-d-sdone prd$r-d-sds prd$r-d-sss prd$r-d-svv prd$r-d-tpos prd$r-d-tseen prd$r-d-vexp prd$r-d-vmem prd$r-d-vrd prd$r-l-coll prd$r-m-rel prd$r-p-lock-sync prd$r-s-fault prd$r-s-layer prd$r-s-lseen prd$r-s-pos prd$r-s-rexp prd$r-s-sidx prd$r-s-stage prd$r-s-state)
                           (prod-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm
                            prd$h-adv-is-at prd$h-arl-is-at prd$h-arv-is-at prd$h-childfault-is-at prd$h-dbusy-is-at prd$h-grd-is-at prd$h-haf-is-at prd$h-hdf-is-at prd$h-hsr-is-at prd$h-hsv-is-at prd$h-kcr-is-at prd$h-kpc-is-at prd$h-lli-is-at prd$h-llr-is-at prd$h-lrf-is-at prd$h-lrv-is-at prd$h-lsv-is-at prd$h-ndv-is-at prd$h-nre-is-at prd$h-nri-is-at prd$h-nrl-is-at prd$h-nrm-is-at prd$h-nrv-is-at prd$h-paf-is-at prd$h-pdv-is-at prd$h-rdv-is-at prd$h-rif-is-at prd$h-rri-is-at prd$h-rrl-is-at prd$h-rrv-is-at prd$h-rterm-is-at prd$h-sbr-is-at prd$h-sdf-is-at prd$h-sfpos-is-at prd$h-siexp-is-at prd$h-sif-is-at prd$h-sil-is-at prd$h-spm-is-at prd$h-spr-is-at prd$h-srexp-is-at prd$h-srf-is-at prd$h-srman-is-at prd$i-clear-is-at prd$i-reset-n-is-at prd$n-d-clay-is-at prd$n-d-cpos-is-at prd$n-d-cst-is-at prd$n-d-elay-is-at prd$n-d-eng-is-at prd$n-d-est-is-at prd$n-d-fault-is-at prd$n-d-iidx-is-at prd$n-d-kexp-is-at prd$n-d-kmem-is-at prd$n-d-krd-is-at prd$n-d-kvrv-is-at prd$n-d-lseen-is-at prd$n-d-odone-is-at prd$n-d-oidx-is-at prd$n-d-sdone-is-at prd$n-d-tpos-is-at prd$n-d-tseen-is-at prd$n-d-vexp-is-at prd$n-d-vmem-is-at prd$n-d-vrd-is-at prd$n-m-rel-is-at prd$n-s-fault-is-at prd$n-s-layer-is-at prd$n-s-pos-is-at prd$n-s-stage-is-at prd$n-s-state-is-at prd$o-dpclear-is-at prd$o-dprst-is-at prd$o-kra-is-at prd$o-kre-is-at prd$o-kwe-is-at prd$o-layerfail-is-at prd$o-player-is-at prd$o-ppos-is-at prd$o-pstage-is-at prd$o-sacc-is-at prd$o-sbv-is-at prd$o-sfire-is-at prd$o-spv-is-at prd$o-vra-is-at prd$o-vre-is-at prd$o-vwe-is-at prd$r-d-arhead-is-at prd$r-d-aslane-is-at prd$r-d-clay-is-at prd$r-d-cpos-is-at prd$r-d-cst-is-at prd$r-d-elay-is-at prd$r-d-eng-is-at prd$r-d-ephase-is-at prd$r-d-est-is-at prd$r-d-fault-is-at prd$r-d-gexp-is-at prd$r-d-idone-is-at prd$r-d-iidx-is-at prd$r-d-kexp-is-at prd$r-d-kmem-is-at prd$r-d-krd-is-at prd$r-d-kvrv-is-at prd$r-d-lseen-is-at prd$r-d-nds-is-at prd$r-d-odone-is-at prd$r-d-oidx-is-at prd$r-d-rhalf-is-at prd$r-d-rhead-is-at prd$r-d-rphase-is-at prd$r-d-rsecond-is-at prd$r-d-sdone-is-at prd$r-d-sds-is-at prd$r-d-sss-is-at prd$r-d-svv-is-at prd$r-d-tpos-is-at prd$r-d-tseen-is-at prd$r-d-vexp-is-at prd$r-d-vmem-is-at prd$r-d-vrd-is-at prd$r-l-coll-is-at prd$r-m-rel-is-at prd$r-p-lock-sync-is-at prd$r-s-fault-is-at prd$r-s-layer-is-at prd$r-s-lseen-is-at prd$r-s-pos-is-at prd$r-s-rexp-is-at prd$r-s-sidx-is-at prd$r-s-stage-is-at prd$r-s-state-is-at)))))
(value-triple (acl2::cw "~%PRD-GLUE done~%"))

; ---------------------------------------------------------------------------
; EACH FACT AS A STATEMENT ABOUT PLAIN VALUES.
; ---------------------------------------------------------------------------
(defthm prd-pay-u-of-integer
  (implies (integerp x) (equal (pay-u x) x))
  :hints (("Goal" :in-theory (enable pay-u 4vec->upper))))
(defthm prd-p-layerfail-of-fact
  (implies (and (prod-fact-layerfail o-layerfail r-d-fault r-l-coll r-s-fault)
                (prod-int-o-layerfail o-layerfail))
           (prd-p-layerfail o-layerfail r-d-fault r-l-coll r-s-fault))
  :hints (("Goal" :in-theory (e/d (prod-fact-layerfail fgl::fgl-prove-fn) (prd-p-layerfail prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-inactive-of-fact
  (implies (and (prod-fact-inactive o-dprst r-m-rel)
                (prod-int-o-dprst o-dprst))
           (prd-p-inactive o-dprst r-m-rel))
  :hints (("Goal" :in-theory (e/d (prod-fact-inactive fgl::fgl-prove-fn) (prd-p-inactive prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-children-reset-of-fact
  (implies (and (prod-fact-children-reset i-reset-n o-dprst r-m-rel)
                (prod-int-o-dprst o-dprst))
           (prd-p-children-reset i-reset-n o-dprst r-m-rel))
  :hints (("Goal" :in-theory (e/d (prod-fact-children-reset fgl::fgl-prove-fn) (prd-p-children-reset prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-release-of-fact
  (implies (and (prod-fact-release n-m-rel r-m-rel)
                (prod-int-n-m-rel n-m-rel))
           (prd-p-release n-m-rel r-m-rel))
  :hints (("Goal" :in-theory (e/d (prod-fact-release fgl::fgl-prove-fn) (prd-p-release prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-staging-valid-of-fact
  (implies (and (prod-fact-staging-valid o-sbv o-spv r-d-eng r-d-kvrv r-d-sss)
                (prod-int-o-sbv o-sbv)
                (prod-int-o-spv o-spv))
           (prd-p-staging-valid o-sbv o-spv r-d-eng r-d-kvrv r-d-sss))
  :hints (("Goal" :in-theory (e/d (prod-fact-staging-valid fgl::fgl-prove-fn) (prd-p-staging-valid prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-clear-of-fact
  (implies (and (prod-fact-clear i-clear o-dpclear)
                (prod-int-o-dpclear o-dpclear))
           (prd-p-clear i-clear o-dpclear))
  :hints (("Goal" :in-theory (e/d (prod-fact-clear fgl::fgl-prove-fn) (prd-p-clear prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-reset-of-fact
  (implies (and (prod-fact-reset n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst)
                (prod-int-n-d-clay n-d-clay)
                (prod-int-n-d-cpos n-d-cpos)
                (prod-int-n-d-cst n-d-cst)
                (prod-int-n-d-elay n-d-elay)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-lseen n-d-lseen)
                (prod-int-n-d-sdone n-d-sdone)
                (prod-int-n-d-tpos n-d-tpos)
                (prod-int-n-d-tseen n-d-tseen)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-n-s-layer n-s-layer)
                (prod-int-n-s-pos n-s-pos)
                (prod-int-n-s-stage n-s-stage)
                (prod-int-n-s-state n-s-state)
                (prod-int-o-dprst o-dprst))
           (prd-p-reset n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst))
  :hints (("Goal" :in-theory (e/d (prod-fact-reset fgl::fgl-prove-fn) (prd-p-reset prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-key-memory-definite-of-fact
  (implies (and (prod-fact-key-memory-definite n-d-kmem)
                (prod-int-n-d-kmem n-d-kmem))
           (prd-p-key-memory-definite n-d-kmem))
  :hints (("Goal" :in-theory (e/d (prod-fact-key-memory-definite fgl::fgl-prove-fn) (prd-p-key-memory-definite prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-value-memory-definite-of-fact
  (implies (and (prod-fact-value-memory-definite n-d-vmem)
                (prod-int-n-d-vmem n-d-vmem))
           (prd-p-value-memory-definite n-d-vmem))
  :hints (("Goal" :in-theory (e/d (prod-fact-value-memory-definite fgl::fgl-prove-fn) (prd-p-value-memory-definite prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-sinv-of-fact
  (implies (and (prod-fact-sinv n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-clay n-d-clay)
                (prod-int-n-d-cpos n-d-cpos)
                (prod-int-n-d-cst n-d-cst)
                (prod-int-n-d-elay n-d-elay)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-lseen n-d-lseen)
                (prod-int-n-d-sdone n-d-sdone)
                (prod-int-n-d-tpos n-d-tpos)
                (prod-int-n-d-tseen n-d-tseen)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-n-s-layer n-s-layer)
                (prod-int-n-s-pos n-s-pos)
                (prod-int-n-s-stage n-s-stage)
                (prod-int-n-s-state n-s-state)
                (prod-int-o-dprst o-dprst))
           (prd-p-sinv n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-lseen n-d-sdone n-d-tpos n-d-tseen n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state))
  :hints (("Goal" :in-theory (e/d (prod-fact-sinv fgl::fgl-prove-fn) (prd-p-sinv prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-accept-of-fact
  (implies (and (prod-fact-accept n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kvrv n-d-odone n-d-oidx n-d-tpos n-d-tseen n-m-rel n-s-fault o-dpclear o-dprst o-kwe o-player o-ppos o-pstage o-sacc o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-clay n-d-clay)
                (prod-int-n-d-cpos n-d-cpos)
                (prod-int-n-d-cst n-d-cst)
                (prod-int-n-d-elay n-d-elay)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-iidx n-d-iidx)
                (prod-int-n-d-kvrv n-d-kvrv)
                (prod-int-n-d-odone n-d-odone)
                (prod-int-n-d-oidx n-d-oidx)
                (prod-int-n-d-tpos n-d-tpos)
                (prod-int-n-d-tseen n-d-tseen)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-kwe o-kwe)
                (prod-int-o-player o-player)
                (prod-int-o-ppos o-ppos)
                (prod-int-o-pstage o-pstage)
                (prod-int-o-sacc o-sacc)
                (prod-int-o-vwe o-vwe))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-accept n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-iidx n-d-kvrv n-d-odone n-d-oidx n-d-tpos n-d-tseen o-dpclear o-kwe o-player o-ppos o-pstage o-sacc o-vwe r-d-elay r-d-eng r-d-est r-d-tpos r-d-tseen)))
  :hints (("Goal" :in-theory (e/d (prod-fact-accept fgl::fgl-prove-fn) (prd-p-accept prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-key-write-of-fact
  (implies (and (prod-fact-key-write h-nre h-nri h-nrl h-nrm h-nrv n-d-fault n-d-kexp n-d-kmem n-d-odone n-d-oidx n-m-rel n-s-fault o-dpclear o-dprst o-kwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-kexp r-d-kmem r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-kexp n-d-kexp)
                (prod-int-n-d-kmem n-d-kmem)
                (prod-int-n-d-odone n-d-odone)
                (prod-int-n-d-oidx n-d-oidx)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-kwe o-kwe))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-key-write h-nre h-nri h-nrl h-nrm h-nrv n-d-kexp n-d-kmem n-d-odone n-d-oidx o-dpclear o-kwe r-d-cst r-d-eng r-d-kexp r-d-kmem r-d-odone r-d-oidx)))
  :hints (("Goal" :in-theory (e/d (prod-fact-key-write fgl::fgl-prove-fn) (prd-p-key-write prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-value-write-of-fact
  (implies (and (prod-fact-value-write h-nre h-nri h-nrl h-nrm h-nrv n-d-fault n-d-odone n-d-oidx n-d-vexp n-d-vmem n-m-rel n-s-fault o-dpclear o-dprst o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-odone n-d-odone)
                (prod-int-n-d-oidx n-d-oidx)
                (prod-int-n-d-vexp n-d-vexp)
                (prod-int-n-d-vmem n-d-vmem)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-vwe o-vwe))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-value-write h-nre h-nri h-nrl h-nrm h-nrv n-d-odone n-d-oidx n-d-vexp n-d-vmem o-dpclear o-vwe r-d-cst r-d-eng r-d-odone r-d-oidx r-d-vexp r-d-vmem)))
  :hints (("Goal" :in-theory (e/d (prod-fact-value-write fgl::fgl-prove-fn) (prd-p-value-write prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-stage-entry-of-fact
  (implies (and (prod-fact-stage-entry n-d-cst n-d-eng n-d-fault n-m-rel n-s-fault o-dprst o-pstage o-sacc r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-cst n-d-cst)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-pstage o-pstage)
                (prod-int-o-sacc o-sacc))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-stage-entry n-d-cst n-d-eng o-pstage o-sacc r-d-cst r-d-eng)))
  :hints (("Goal" :in-theory (e/d (prod-fact-stage-entry fgl::fgl-prove-fn) (prd-p-stage-entry prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-key-stage-end-of-fact
  (implies (and (prod-fact-key-stage-end h-nrl n-d-cst n-d-eng n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst o-kwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-cst n-d-cst)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-kwe o-kwe))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-key-stage-end h-nrl n-d-cst n-d-eng n-d-est o-dpclear o-kwe r-d-cst r-d-eng r-d-est r-d-odone)))
  :hints (("Goal" :in-theory (e/d (prod-fact-key-stage-end fgl::fgl-prove-fn) (prd-p-key-stage-end prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-value-stage-end-of-fact
  (implies (and (prod-fact-value-stage-end h-nrl n-d-cst n-d-eng n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-odone r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-cst n-d-cst)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-vwe o-vwe))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-value-stage-end h-nrl n-d-cst n-d-eng n-d-est o-dpclear o-vwe r-d-cst r-d-eng r-d-est r-d-odone)))
  :hints (("Goal" :in-theory (e/d (prod-fact-value-stage-end fgl::fgl-prove-fn) (prd-p-value-stage-end prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-value-done-entry-of-fact
  (implies (and (prod-fact-value-done-entry n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-value-done-entry n-d-est o-dpclear r-d-cst r-d-eng r-d-est)))
  :hints (("Goal" :in-theory (e/d (prod-fact-value-done-entry fgl::fgl-prove-fn) (prd-p-value-done-entry prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-key-done-entry-of-fact
  (implies (and (prod-fact-key-done-entry n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-key-done-entry n-d-est o-dpclear r-d-cst r-d-eng r-d-est)))
  :hints (("Goal" :in-theory (e/d (prod-fact-key-done-entry fgl::fgl-prove-fn) (prd-p-key-done-entry prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-value-frozen-of-fact
  (implies (and (prod-fact-value-frozen n-d-fault n-m-rel n-s-fault o-dprst o-pstage o-sacc o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-pstage o-pstage)
                (prod-int-o-sacc o-sacc)
                (prod-int-o-vwe o-vwe))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-value-frozen o-pstage o-sacc o-vwe r-d-est)))
  :hints (("Goal" :in-theory (e/d (prod-fact-value-frozen fgl::fgl-prove-fn) (prd-p-value-frozen prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-key-frozen-of-fact
  (implies (and (prod-fact-key-frozen n-d-fault n-m-rel n-s-fault o-dprst o-kwe o-pstage o-sacc r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-kwe o-kwe)
                (prod-int-o-pstage o-pstage)
                (prod-int-o-sacc o-sacc))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-key-frozen o-kwe o-pstage o-sacc r-d-est)))
  :hints (("Goal" :in-theory (e/d (prod-fact-key-frozen fgl::fgl-prove-fn) (prd-p-key-frozen prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-transaction-of-fact
  (implies (and (prod-fact-transaction n-d-elay n-d-fault n-d-tpos n-d-tseen n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-elay n-d-elay)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-tpos n-d-tpos)
                (prod-int-n-d-tseen n-d-tseen)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-transaction n-d-elay n-d-tpos n-d-tseen o-dpclear r-d-elay r-d-est r-d-tpos r-d-tseen)))
  :hints (("Goal" :in-theory (e/d (prod-fact-transaction fgl::fgl-prove-fn) (prd-p-transaction prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-staging-stage-of-fact
  (implies (and (prod-fact-staging-stage h-kpc n-d-est n-d-fault n-m-rel n-s-fault o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-staging-stage h-kpc n-d-est o-dpclear r-d-eng r-d-est)))
  :hints (("Goal" :in-theory (e/d (prod-fact-staging-stage fgl::fgl-prove-fn) (prd-p-staging-stage prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-memory-read-of-fact
  (implies (and (prod-fact-memory-read n-d-fault n-d-krd n-d-vrd n-m-rel n-s-fault o-dprst o-kra o-kre o-vra o-vre r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-kmem r-d-krd r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-d-vmem r-d-vrd r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-krd n-d-krd)
                (prod-int-n-d-vrd n-d-vrd)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-kra o-kra)
                (prod-int-o-kre o-kre)
                (prod-int-o-vra o-vra)
                (prod-int-o-vre o-vre))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-memory-read n-d-krd n-d-vrd o-kra o-kre o-vra o-vre r-d-kmem r-d-krd r-d-vmem r-d-vrd)))
  :hints (("Goal" :in-theory (e/d (prod-fact-memory-read fgl::fgl-prove-fn) (prd-p-memory-read prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-staging-read-of-fact
  (implies (and (prod-fact-staging-read n-d-eng n-d-fault n-d-iidx n-d-kvrv n-m-rel n-s-fault o-dprst o-kra o-kre o-vra o-vre r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kvrv r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-d-iidx n-d-iidx)
                (prod-int-n-d-kvrv n-d-kvrv)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-kra o-kra)
                (prod-int-o-kre o-kre)
                (prod-int-o-vra o-vra)
                (prod-int-o-vre o-vre))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-staging-read n-d-eng n-d-iidx n-d-kvrv o-kra o-kre o-vra o-vre r-d-eng r-d-iidx r-d-kvrv)))
  :hints (("Goal" :in-theory (e/d (prod-fact-staging-read fgl::fgl-prove-fn) (prd-p-staging-read prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-sequence-of-fact
  (implies (and (prod-fact-sequence h-lsv h-sfpos n-d-fault n-m-rel n-s-fault n-s-pos n-s-state o-dpclear o-dprst o-sfire r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-n-s-pos n-s-pos)
                (prod-int-n-s-state n-s-state)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst)
                (prod-int-o-sfire o-sfire))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-sequence h-lsv h-sfpos n-s-pos n-s-state o-dpclear o-sfire r-s-pos r-s-state)))
  :hints (("Goal" :in-theory (e/d (prod-fact-sequence fgl::fgl-prove-fn) (prd-p-sequence prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-sequence-done-of-fact
  (implies (and (prod-fact-sequence-done h-sdf n-d-fault n-m-rel n-s-fault n-s-state o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-n-s-state n-s-state)
                (prod-int-o-dprst o-dprst))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-sequence-done h-sdf n-s-state r-s-state)))
  :hints (("Goal" :in-theory (e/d (prod-fact-sequence-done fgl::fgl-prove-fn) (prd-p-sequence-done prd-guard-plain))))
  :rule-classes nil)
(defthm prd-p-clear-resets-of-fact
  (implies (and (prod-fact-clear-resets n-d-eng n-d-est n-d-fault n-m-rel n-s-fault n-s-state o-dpclear o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                (prod-int-n-d-eng n-d-eng)
                (prod-int-n-d-est n-d-est)
                (prod-int-n-d-fault n-d-fault)
                (prod-int-n-m-rel n-m-rel)
                (prod-int-n-s-fault n-s-fault)
                (prod-int-n-s-state n-s-state)
                (prod-int-o-dpclear o-dpclear)
                (prod-int-o-dprst o-dprst))
           (implies (prd-guard-plain n-d-fault n-m-rel n-s-fault o-dprst r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-lseen r-d-sdone r-d-tpos r-d-tseen r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
                    (prd-p-clear-resets n-d-eng n-d-est n-s-state o-dpclear)))
  :hints (("Goal" :in-theory (e/d (prod-fact-clear-resets fgl::fgl-prove-fn) (prd-p-clear-resets prd-guard-plain))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-VALUES done~%"))

; Everything the argument needs to know about cycle k.
(define prd-known-at (k envs outs) :verify-guards nil
  (and (join-env-at k envs outs)
       (prod-env-at k envs outs)
       (prod-mem-at k outs)
       (prod-facts-at k envs outs)))

; THE STEP: the facts of cycle k, about the signals as functions of the
; cycle.  First one fact at a time.
(defthm prd-step-layerfail
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-layerfail (prd-o-layerfail-at k outs) (prd-d-fault-at k outs) (prd-l-coll-at k outs) (prd-s-fault-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-layerfail-of-fact (o-layerfail (prd$o-layerfail k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-l-coll (prd$r-l-coll k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-inactive
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-inactive (prd-o-dprst-at k outs) (prd-m-rel-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-inactive-of-fact (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-m-rel (prd$r-m-rel k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-children-reset
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-children-reset (prd-i-reset-n-at k envs) (prd-o-dprst-at k outs) (prd-m-rel-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-children-reset-of-fact (i-reset-n (prd$i-reset-n k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-m-rel (prd$r-m-rel k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-release
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-release (prd-m-rel-at (+ 1 k) outs) (prd-m-rel-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-release-of-fact (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (r-m-rel (prd$r-m-rel k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-staging-valid
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-staging-valid (prd-o-sbv-at k outs) (prd-o-spv-at k outs) (prd-d-eng-at k outs) (prd-d-kvrv-at k outs) (prd-d-sss-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-staging-valid-of-fact (o-sbv (prd$o-sbv k (+ 1 k) envs outs)) (o-spv (prd$o-spv k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-kvrv (prd$r-d-kvrv k (+ 1 k) envs outs)) (r-d-sss (prd$r-d-sss k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-clear
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-clear (prd-i-clear-at k envs) (prd-o-dpclear-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-clear-of-fact (i-clear (prd$i-clear k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-reset
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-reset (prd-d-clay-at (+ 1 k) outs) (prd-d-cpos-at (+ 1 k) outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-elay-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-d-fault-at (+ 1 k) outs) (prd-d-lseen-at (+ 1 k) outs) (prd-d-sdone-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-s-layer-at (+ 1 k) outs) (prd-s-pos-at (+ 1 k) outs) (prd-s-stage-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dprst-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-reset-of-fact (n-d-clay (prd$n-d-clay k (+ 1 k) envs outs)) (n-d-cpos (prd$n-d-cpos k (+ 1 k) envs outs)) (n-d-cst (prd$n-d-cst k (+ 1 k) envs outs)) (n-d-elay (prd$n-d-elay k (+ 1 k) envs outs)) (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-lseen (prd$n-d-lseen k (+ 1 k) envs outs)) (n-d-sdone (prd$n-d-sdone k (+ 1 k) envs outs)) (n-d-tpos (prd$n-d-tpos k (+ 1 k) envs outs)) (n-d-tseen (prd$n-d-tseen k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (n-s-layer (prd$n-s-layer k (+ 1 k) envs outs)) (n-s-pos (prd$n-s-pos k (+ 1 k) envs outs)) (n-s-stage (prd$n-s-stage k (+ 1 k) envs outs)) (n-s-state (prd$n-s-state k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-key-memory-definite
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-key-memory-definite (prd-d-kmem-at (+ 1 k) outs)))
  :hints (("Goal"
           :use ((:instance prd-p-key-memory-definite-of-fact (n-d-kmem (prd$n-d-kmem k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-value-memory-definite
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-value-memory-definite (prd-d-vmem-at (+ 1 k) outs)))
  :hints (("Goal"
           :use ((:instance prd-p-value-memory-definite-of-fact (n-d-vmem (prd$n-d-vmem k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-sinv
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-p-sinv (prd-d-clay-at (+ 1 k) outs) (prd-d-cpos-at (+ 1 k) outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-elay-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-d-fault-at (+ 1 k) outs) (prd-d-lseen-at (+ 1 k) outs) (prd-d-sdone-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-s-layer-at (+ 1 k) outs) (prd-s-pos-at (+ 1 k) outs) (prd-s-stage-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs)))
  :hints (("Goal"
           :use ((:instance prd-p-sinv-of-fact (n-d-clay (prd$n-d-clay k (+ 1 k) envs outs)) (n-d-cpos (prd$n-d-cpos k (+ 1 k) envs outs)) (n-d-cst (prd$n-d-cst k (+ 1 k) envs outs)) (n-d-elay (prd$n-d-elay k (+ 1 k) envs outs)) (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-lseen (prd$n-d-lseen k (+ 1 k) envs outs)) (n-d-sdone (prd$n-d-sdone k (+ 1 k) envs outs)) (n-d-tpos (prd$n-d-tpos k (+ 1 k) envs outs)) (n-d-tseen (prd$n-d-tseen k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (n-s-layer (prd$n-s-layer k (+ 1 k) envs outs)) (n-s-pos (prd$n-s-pos k (+ 1 k) envs outs)) (n-s-stage (prd$n-s-stage k (+ 1 k) envs outs)) (n-s-state (prd$n-s-state k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-accept
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-accept (prd-d-clay-at (+ 1 k) outs) (prd-d-cpos-at (+ 1 k) outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-elay-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-d-iidx-at (+ 1 k) outs) (prd-d-kvrv-at (+ 1 k) outs) (prd-d-odone-at (+ 1 k) outs) (prd-d-oidx-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-kwe-at k outs) (prd-o-player-at k outs) (prd-o-ppos-at k outs) (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-o-vwe-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-accept-of-fact (n-d-clay (prd$n-d-clay k (+ 1 k) envs outs)) (n-d-cpos (prd$n-d-cpos k (+ 1 k) envs outs)) (n-d-cst (prd$n-d-cst k (+ 1 k) envs outs)) (n-d-elay (prd$n-d-elay k (+ 1 k) envs outs)) (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-iidx (prd$n-d-iidx k (+ 1 k) envs outs)) (n-d-kvrv (prd$n-d-kvrv k (+ 1 k) envs outs)) (n-d-odone (prd$n-d-odone k (+ 1 k) envs outs)) (n-d-oidx (prd$n-d-oidx k (+ 1 k) envs outs)) (n-d-tpos (prd$n-d-tpos k (+ 1 k) envs outs)) (n-d-tseen (prd$n-d-tseen k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-kwe (prd$o-kwe k (+ 1 k) envs outs)) (o-player (prd$o-player k (+ 1 k) envs outs)) (o-ppos (prd$o-ppos k (+ 1 k) envs outs)) (o-pstage (prd$o-pstage k (+ 1 k) envs outs)) (o-sacc (prd$o-sacc k (+ 1 k) envs outs)) (o-vwe (prd$o-vwe k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-key-write
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-key-write (prd-h-nre-at k outs) (prd-h-nri-at k outs) (prd-h-nrl-at k outs) (prd-h-nrm-at k outs) (prd-h-nrv-at k outs) (prd-d-kexp-at (+ 1 k) outs) (prd-d-kmem-at (+ 1 k) outs) (prd-d-odone-at (+ 1 k) outs) (prd-d-oidx-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-kwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-kexp-at k outs) (prd-d-kmem-at k outs) (prd-d-odone-at k outs) (prd-d-oidx-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-key-write-of-fact (h-nre (prd$h-nre k (+ 1 k) envs outs)) (h-nri (prd$h-nri k (+ 1 k) envs outs)) (h-nrl (prd$h-nrl k (+ 1 k) envs outs)) (h-nrm (prd$h-nrm k (+ 1 k) envs outs)) (h-nrv (prd$h-nrv k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-kexp (prd$n-d-kexp k (+ 1 k) envs outs)) (n-d-kmem (prd$n-d-kmem k (+ 1 k) envs outs)) (n-d-odone (prd$n-d-odone k (+ 1 k) envs outs)) (n-d-oidx (prd$n-d-oidx k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-kwe (prd$o-kwe k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-kexp (prd$r-d-kexp k (+ 1 k) envs outs)) (r-d-kmem (prd$r-d-kmem k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-odone (prd$r-d-odone k (+ 1 k) envs outs)) (r-d-oidx (prd$r-d-oidx k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-value-write
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-value-write (prd-h-nre-at k outs) (prd-h-nri-at k outs) (prd-h-nrl-at k outs) (prd-h-nrm-at k outs) (prd-h-nrv-at k outs) (prd-d-odone-at (+ 1 k) outs) (prd-d-oidx-at (+ 1 k) outs) (prd-d-vexp-at (+ 1 k) outs) (prd-d-vmem-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-vwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-odone-at k outs) (prd-d-oidx-at k outs) (prd-d-vexp-at k outs) (prd-d-vmem-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-value-write-of-fact (h-nre (prd$h-nre k (+ 1 k) envs outs)) (h-nri (prd$h-nri k (+ 1 k) envs outs)) (h-nrl (prd$h-nrl k (+ 1 k) envs outs)) (h-nrm (prd$h-nrm k (+ 1 k) envs outs)) (h-nrv (prd$h-nrv k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-odone (prd$n-d-odone k (+ 1 k) envs outs)) (n-d-oidx (prd$n-d-oidx k (+ 1 k) envs outs)) (n-d-vexp (prd$n-d-vexp k (+ 1 k) envs outs)) (n-d-vmem (prd$n-d-vmem k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-vwe (prd$o-vwe k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-odone (prd$r-d-odone k (+ 1 k) envs outs)) (r-d-oidx (prd$r-d-oidx k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-d-vexp (prd$r-d-vexp k (+ 1 k) envs outs)) (r-d-vmem (prd$r-d-vmem k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-stage-entry
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-stage-entry (prd-d-cst-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-stage-entry-of-fact (n-d-cst (prd$n-d-cst k (+ 1 k) envs outs)) (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-pstage (prd$o-pstage k (+ 1 k) envs outs)) (o-sacc (prd$o-sacc k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-key-stage-end
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-key-stage-end (prd-h-nrl-at k outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-kwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-odone-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-key-stage-end-of-fact (h-nrl (prd$h-nrl k (+ 1 k) envs outs)) (n-d-cst (prd$n-d-cst k (+ 1 k) envs outs)) (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-kwe (prd$o-kwe k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-odone (prd$r-d-odone k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-value-stage-end
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-value-stage-end (prd-h-nrl-at k outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-vwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-odone-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-value-stage-end-of-fact (h-nrl (prd$h-nrl k (+ 1 k) envs outs)) (n-d-cst (prd$n-d-cst k (+ 1 k) envs outs)) (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-vwe (prd$o-vwe k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-odone (prd$r-d-odone k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-value-done-entry
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-value-done-entry (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-value-done-entry-of-fact (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-key-done-entry
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-key-done-entry (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-key-done-entry-of-fact (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-value-frozen
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-value-frozen (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-o-vwe-at k outs) (prd-d-est-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-value-frozen-of-fact (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-pstage (prd$o-pstage k (+ 1 k) envs outs)) (o-sacc (prd$o-sacc k (+ 1 k) envs outs)) (o-vwe (prd$o-vwe k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-key-frozen
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-key-frozen (prd-o-kwe-at k outs) (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-d-est-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-key-frozen-of-fact (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-kwe (prd$o-kwe k (+ 1 k) envs outs)) (o-pstage (prd$o-pstage k (+ 1 k) envs outs)) (o-sacc (prd$o-sacc k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-transaction
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-transaction (prd-d-elay-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-elay-at k outs) (prd-d-est-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-transaction-of-fact (n-d-elay (prd$n-d-elay k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-tpos (prd$n-d-tpos k (+ 1 k) envs outs)) (n-d-tseen (prd$n-d-tseen k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-staging-stage
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-staging-stage (prd-h-kpc-at k outs) (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-staging-stage-of-fact (h-kpc (prd$h-kpc k (+ 1 k) envs outs)) (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-memory-read
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-memory-read (prd-d-krd-at (+ 1 k) outs) (prd-d-vrd-at (+ 1 k) outs) (prd-o-kra-at k outs) (prd-o-kre-at k outs) (prd-o-vra-at k outs) (prd-o-vre-at k outs) (prd-d-kmem-at k outs) (prd-d-krd-at k outs) (prd-d-vmem-at k outs) (prd-d-vrd-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-memory-read-of-fact (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-krd (prd$n-d-krd k (+ 1 k) envs outs)) (n-d-vrd (prd$n-d-vrd k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-kra (prd$o-kra k (+ 1 k) envs outs)) (o-kre (prd$o-kre k (+ 1 k) envs outs)) (o-vra (prd$o-vra k (+ 1 k) envs outs)) (o-vre (prd$o-vre k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-kmem (prd$r-d-kmem k (+ 1 k) envs outs)) (r-d-krd (prd$r-d-krd k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-d-vmem (prd$r-d-vmem k (+ 1 k) envs outs)) (r-d-vrd (prd$r-d-vrd k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-staging-read
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-staging-read (prd-d-eng-at (+ 1 k) outs) (prd-d-iidx-at (+ 1 k) outs) (prd-d-kvrv-at (+ 1 k) outs) (prd-o-kra-at k outs) (prd-o-kre-at k outs) (prd-o-vra-at k outs) (prd-o-vre-at k outs) (prd-d-eng-at k outs) (prd-d-iidx-at k outs) (prd-d-kvrv-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-staging-read-of-fact (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-d-iidx (prd$n-d-iidx k (+ 1 k) envs outs)) (n-d-kvrv (prd$n-d-kvrv k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-kra (prd$o-kra k (+ 1 k) envs outs)) (o-kre (prd$o-kre k (+ 1 k) envs outs)) (o-vra (prd$o-vra k (+ 1 k) envs outs)) (o-vre (prd$o-vre k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-iidx (prd$r-d-iidx k (+ 1 k) envs outs)) (r-d-kvrv (prd$r-d-kvrv k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-sequence
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-sequence (prd-h-lsv-at k outs) (prd-h-sfpos-at k outs) (prd-s-pos-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-sfire-at k outs) (prd-s-pos-at k outs) (prd-s-state-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-sequence-of-fact (h-lsv (prd$h-lsv k (+ 1 k) envs outs)) (h-sfpos (prd$h-sfpos k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (n-s-pos (prd$n-s-pos k (+ 1 k) envs outs)) (n-s-state (prd$n-s-state k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (o-sfire (prd$o-sfire k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-sequence-done
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-sequence-done (prd-h-sdf-at k outs) (prd-s-state-at (+ 1 k) outs) (prd-s-state-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-sequence-done-of-fact (h-sdf (prd$h-sdf k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (n-s-state (prd$n-s-state k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step-clear-resets
  (implies (and (natp k) (prd-known-at k envs outs))
           (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                    (prd-p-clear-resets (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dpclear-at k outs))))
  :hints (("Goal"
           :use ((:instance prd-p-clear-resets-of-fact (n-d-eng (prd$n-d-eng k (+ 1 k) envs outs)) (n-d-est (prd$n-d-est k (+ 1 k) envs outs)) (n-d-fault (prd$n-d-fault k (+ 1 k) envs outs)) (n-m-rel (prd$n-m-rel k (+ 1 k) envs outs)) (n-s-fault (prd$n-s-fault k (+ 1 k) envs outs)) (n-s-state (prd$n-s-state k (+ 1 k) envs outs)) (o-dpclear (prd$o-dpclear k (+ 1 k) envs outs)) (o-dprst (prd$o-dprst k (+ 1 k) envs outs)) (r-d-clay (prd$r-d-clay k (+ 1 k) envs outs)) (r-d-cpos (prd$r-d-cpos k (+ 1 k) envs outs)) (r-d-cst (prd$r-d-cst k (+ 1 k) envs outs)) (r-d-elay (prd$r-d-elay k (+ 1 k) envs outs)) (r-d-eng (prd$r-d-eng k (+ 1 k) envs outs)) (r-d-est (prd$r-d-est k (+ 1 k) envs outs)) (r-d-fault (prd$r-d-fault k (+ 1 k) envs outs)) (r-d-lseen (prd$r-d-lseen k (+ 1 k) envs outs)) (r-d-sdone (prd$r-d-sdone k (+ 1 k) envs outs)) (r-d-tpos (prd$r-d-tpos k (+ 1 k) envs outs)) (r-d-tseen (prd$r-d-tseen k (+ 1 k) envs outs)) (r-s-fault (prd$r-s-fault k (+ 1 k) envs outs)) (r-s-layer (prd$r-s-layer k (+ 1 k) envs outs)) (r-s-pos (prd$r-s-pos k (+ 1 k) envs outs)) (r-s-stage (prd$r-s-stage k (+ 1 k) envs outs)) (r-s-state (prd$r-s-state k (+ 1 k) envs outs))))
           :in-theory (e/d (prd-known-at prod-facts-at prod-step-all prod-step-concl)
                           (unsigned-byte-p nth nthcdr take len prd-guard-plain
                            prod-fact-layerfail prod-fact-inactive prod-fact-children-reset prod-fact-release prod-fact-staging-valid prod-fact-clear prod-fact-reset prod-fact-key-memory-definite prod-fact-value-memory-definite prod-fact-sinv prod-fact-accept prod-fact-key-write prod-fact-value-write prod-fact-stage-entry prod-fact-key-stage-end prod-fact-value-stage-end prod-fact-value-done-entry prod-fact-key-done-entry prod-fact-value-frozen prod-fact-key-frozen prod-fact-transaction prod-fact-staging-stage prod-fact-memory-read prod-fact-staging-read prod-fact-sequence prod-fact-sequence-done prod-fact-clear-resets prd-p-layerfail prd-p-inactive prd-p-children-reset prd-p-release prd-p-staging-valid prd-p-clear prd-p-reset prd-p-key-memory-definite prd-p-value-memory-definite prd-p-sinv prd-p-accept prd-p-key-write prd-p-value-write prd-p-stage-entry prd-p-key-stage-end prd-p-value-stage-end prd-p-value-done-entry prd-p-key-done-entry prd-p-value-frozen prd-p-key-frozen prd-p-transaction prd-p-staging-stage prd-p-memory-read prd-p-staging-read prd-p-sequence prd-p-sequence-done prd-p-clear-resets prod-int-o-dprst prod-int-o-dpclear prod-int-o-sacc prod-int-o-pstage prod-int-o-player prod-int-o-ppos prod-int-o-kwe prod-int-o-vwe prod-int-o-kre prod-int-o-vre prod-int-o-kra prod-int-o-vra prod-int-o-sbv prod-int-o-spv prod-int-o-sfire prod-int-o-layerfail prod-int-n-m-rel prod-int-n-s-state prod-int-n-s-layer prod-int-n-s-stage prod-int-n-s-pos prod-int-n-s-fault prod-int-n-d-eng prod-int-n-d-cst prod-int-n-d-clay prod-int-n-d-cpos prod-int-n-d-est prod-int-n-d-elay prod-int-n-d-tpos prod-int-n-d-tseen prod-int-n-d-fault prod-int-n-d-lseen prod-int-n-d-sdone prod-int-n-d-kexp prod-int-n-d-vexp prod-int-n-d-odone prod-int-n-d-iidx prod-int-n-d-oidx prod-int-n-d-kvrv prod-int-n-d-kmem prod-int-n-d-vmem prod-int-n-d-krd prod-int-n-d-vrd))))
  :rule-classes nil)
(defthm prd-step
  (implies (and (natp k) (prd-known-at k envs outs))
           (and (prd-p-layerfail (prd-o-layerfail-at k outs) (prd-d-fault-at k outs) (prd-l-coll-at k outs) (prd-s-fault-at k outs))
                (prd-p-inactive (prd-o-dprst-at k outs) (prd-m-rel-at k outs))
                (prd-p-children-reset (prd-i-reset-n-at k envs) (prd-o-dprst-at k outs) (prd-m-rel-at k outs))
                (prd-p-release (prd-m-rel-at (+ 1 k) outs) (prd-m-rel-at k outs))
                (prd-p-staging-valid (prd-o-sbv-at k outs) (prd-o-spv-at k outs) (prd-d-eng-at k outs) (prd-d-kvrv-at k outs) (prd-d-sss-at k outs))
                (prd-p-clear (prd-i-clear-at k envs) (prd-o-dpclear-at k outs))
                (prd-p-reset (prd-d-clay-at (+ 1 k) outs) (prd-d-cpos-at (+ 1 k) outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-elay-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-d-fault-at (+ 1 k) outs) (prd-d-lseen-at (+ 1 k) outs) (prd-d-sdone-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-s-layer-at (+ 1 k) outs) (prd-s-pos-at (+ 1 k) outs) (prd-s-stage-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dprst-at k outs))
                (prd-p-key-memory-definite (prd-d-kmem-at (+ 1 k) outs))
                (prd-p-value-memory-definite (prd-d-vmem-at (+ 1 k) outs))
                (prd-p-sinv (prd-d-clay-at (+ 1 k) outs) (prd-d-cpos-at (+ 1 k) outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-elay-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-d-fault-at (+ 1 k) outs) (prd-d-lseen-at (+ 1 k) outs) (prd-d-sdone-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-s-layer-at (+ 1 k) outs) (prd-s-pos-at (+ 1 k) outs) (prd-s-stage-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                (implies (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs))
                         (and (prd-p-accept (prd-d-clay-at (+ 1 k) outs) (prd-d-cpos-at (+ 1 k) outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-elay-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-d-iidx-at (+ 1 k) outs) (prd-d-kvrv-at (+ 1 k) outs) (prd-d-odone-at (+ 1 k) outs) (prd-d-oidx-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-kwe-at k outs) (prd-o-player-at k outs) (prd-o-ppos-at k outs) (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-o-vwe-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs))
                     (prd-p-key-write (prd-h-nre-at k outs) (prd-h-nri-at k outs) (prd-h-nrl-at k outs) (prd-h-nrm-at k outs) (prd-h-nrv-at k outs) (prd-d-kexp-at (+ 1 k) outs) (prd-d-kmem-at (+ 1 k) outs) (prd-d-odone-at (+ 1 k) outs) (prd-d-oidx-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-kwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-kexp-at k outs) (prd-d-kmem-at k outs) (prd-d-odone-at k outs) (prd-d-oidx-at k outs))
                     (prd-p-value-write (prd-h-nre-at k outs) (prd-h-nri-at k outs) (prd-h-nrl-at k outs) (prd-h-nrm-at k outs) (prd-h-nrv-at k outs) (prd-d-odone-at (+ 1 k) outs) (prd-d-oidx-at (+ 1 k) outs) (prd-d-vexp-at (+ 1 k) outs) (prd-d-vmem-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-vwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-odone-at k outs) (prd-d-oidx-at k outs) (prd-d-vexp-at k outs) (prd-d-vmem-at k outs))
                     (prd-p-stage-entry (prd-d-cst-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs))
                     (prd-p-key-stage-end (prd-h-nrl-at k outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-kwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-odone-at k outs))
                     (prd-p-value-stage-end (prd-h-nrl-at k outs) (prd-d-cst-at (+ 1 k) outs) (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-vwe-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-odone-at k outs))
                     (prd-p-value-done-entry (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs))
                     (prd-p-key-done-entry (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-cst-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs))
                     (prd-p-value-frozen (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-o-vwe-at k outs) (prd-d-est-at k outs))
                     (prd-p-key-frozen (prd-o-kwe-at k outs) (prd-o-pstage-at k outs) (prd-o-sacc-at k outs) (prd-d-est-at k outs))
                     (prd-p-transaction (prd-d-elay-at (+ 1 k) outs) (prd-d-tpos-at (+ 1 k) outs) (prd-d-tseen-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-elay-at k outs) (prd-d-est-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs))
                     (prd-p-staging-stage (prd-h-kpc-at k outs) (prd-d-est-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs))
                     (prd-p-memory-read (prd-d-krd-at (+ 1 k) outs) (prd-d-vrd-at (+ 1 k) outs) (prd-o-kra-at k outs) (prd-o-kre-at k outs) (prd-o-vra-at k outs) (prd-o-vre-at k outs) (prd-d-kmem-at k outs) (prd-d-krd-at k outs) (prd-d-vmem-at k outs) (prd-d-vrd-at k outs))
                     (prd-p-staging-read (prd-d-eng-at (+ 1 k) outs) (prd-d-iidx-at (+ 1 k) outs) (prd-d-kvrv-at (+ 1 k) outs) (prd-o-kra-at k outs) (prd-o-kre-at k outs) (prd-o-vra-at k outs) (prd-o-vre-at k outs) (prd-d-eng-at k outs) (prd-d-iidx-at k outs) (prd-d-kvrv-at k outs))
                     (prd-p-sequence (prd-h-lsv-at k outs) (prd-h-sfpos-at k outs) (prd-s-pos-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dpclear-at k outs) (prd-o-sfire-at k outs) (prd-s-pos-at k outs) (prd-s-state-at k outs))
                     (prd-p-sequence-done (prd-h-sdf-at k outs) (prd-s-state-at (+ 1 k) outs) (prd-s-state-at k outs))
                     (prd-p-clear-resets (prd-d-eng-at (+ 1 k) outs) (prd-d-est-at (+ 1 k) outs) (prd-s-state-at (+ 1 k) outs) (prd-o-dpclear-at k outs))))))
  :hints (("Goal"
           :use ((:instance prd-step-layerfail)
                 (:instance prd-step-inactive)
                 (:instance prd-step-children-reset)
                 (:instance prd-step-release)
                 (:instance prd-step-staging-valid)
                 (:instance prd-step-clear)
                 (:instance prd-step-reset)
                 (:instance prd-step-key-memory-definite)
                 (:instance prd-step-value-memory-definite)
                 (:instance prd-step-sinv)
                 (:instance prd-step-accept)
                 (:instance prd-step-key-write)
                 (:instance prd-step-value-write)
                 (:instance prd-step-stage-entry)
                 (:instance prd-step-key-stage-end)
                 (:instance prd-step-value-stage-end)
                 (:instance prd-step-value-done-entry)
                 (:instance prd-step-key-done-entry)
                 (:instance prd-step-value-frozen)
                 (:instance prd-step-key-frozen)
                 (:instance prd-step-transaction)
                 (:instance prd-step-staging-stage)
                 (:instance prd-step-memory-read)
                 (:instance prd-step-staging-read)
                 (:instance prd-step-sequence)
                 (:instance prd-step-sequence-done)
                 (:instance prd-step-clear-resets))
           :in-theory (theory 'minimal-theory)))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-STEP done~%"))

; the sizes of the signals of a cycle
(defthm prd-sizes
  (implies (and (prod-env-at k envs outs) (prod-mem-at k outs))
           (and (unsigned-byte-p 1 (prd-p-lock-sync-at k outs))
                (unsigned-byte-p 2 (prd-m-rel-at k outs))
                (unsigned-byte-p 1 (prd-l-coll-at k outs))
                (unsigned-byte-p 3 (prd-s-state-at k outs))
                (unsigned-byte-p 3 (prd-s-layer-at k outs))
                (unsigned-byte-p 5 (prd-s-stage-at k outs))
                (unsigned-byte-p 11 (prd-s-pos-at k outs))
                (unsigned-byte-p 1 (prd-s-fault-at k outs))
                (unsigned-byte-p 1 (prd-s-lseen-at k outs))
                (unsigned-byte-p 8 (prd-s-sidx-at k outs))
                (unsigned-byte-p 8 (prd-s-rexp-at k outs))
                (unsigned-byte-p 4 (prd-d-eng-at k outs))
                (unsigned-byte-p 5 (prd-d-cst-at k outs))
                (unsigned-byte-p 3 (prd-d-clay-at k outs))
                (unsigned-byte-p 11 (prd-d-cpos-at k outs))
                (unsigned-byte-p 5 (prd-d-est-at k outs))
                (unsigned-byte-p 3 (prd-d-elay-at k outs))
                (unsigned-byte-p 11 (prd-d-tpos-at k outs))
                (unsigned-byte-p 1 (prd-d-tseen-at k outs))
                (unsigned-byte-p 1 (prd-d-fault-at k outs))
                (unsigned-byte-p 1 (prd-d-lseen-at k outs))
                (unsigned-byte-p 1 (prd-d-sdone-at k outs))
                (unsigned-byte-p 8 (prd-d-kexp-at k outs))
                (unsigned-byte-p 8 (prd-d-vexp-at k outs))
                (unsigned-byte-p 1 (prd-d-sss-at k outs))
                (unsigned-byte-p 1 (prd-d-odone-at k outs))
                (unsigned-byte-p 1 (prd-d-sds-at k outs))
                (unsigned-byte-p 1 (prd-d-nds-at k outs))
                (unsigned-byte-p 10 (prd-d-iidx-at k outs))
                (unsigned-byte-p 1 (prd-d-idone-at k outs))
                (unsigned-byte-p 10 (prd-d-oidx-at k outs))
                (unsigned-byte-p 4 (prd-d-rphase-at k outs))
                (unsigned-byte-p 2 (prd-d-rhead-at k outs))
                (unsigned-byte-p 5 (prd-d-rhalf-at k outs))
                (unsigned-byte-p 5 (prd-d-rsecond-at k outs))
                (unsigned-byte-p 3 (prd-d-arhead-at k outs))
                (unsigned-byte-p 6 (prd-d-aslane-at k outs))
                (unsigned-byte-p 1 (prd-d-svv-at k outs))
                (unsigned-byte-p 8 (prd-d-gexp-at k outs))
                (unsigned-byte-p 1 (prd-d-kvrv-at k outs))
                (unsigned-byte-p 3 (prd-d-ephase-at k outs))
                (unsigned-byte-p 16 (prd-d-krd-at k outs))
                (unsigned-byte-p 16 (prd-d-vrd-at k outs))
                (unsigned-byte-p 1 (prd-h-rterm-at k outs))
                (unsigned-byte-p 1 (prd-h-childfault-at k outs))
                (unsigned-byte-p 1 (prd-h-nrv-at k outs))
                (unsigned-byte-p 10 (prd-h-nri-at k outs))
                (unsigned-byte-p 16 (prd-h-nrm-at k outs))
                (unsigned-byte-p 8 (prd-h-nre-at k outs))
                (unsigned-byte-p 1 (prd-h-nrl-at k outs))
                (unsigned-byte-p 1 (prd-h-ndv-at k outs))
                (unsigned-byte-p 1 (prd-h-pdv-at k outs))
                (unsigned-byte-p 1 (prd-h-rrv-at k outs))
                (unsigned-byte-p 8 (prd-h-rri-at k outs))
                (unsigned-byte-p 1 (prd-h-rrl-at k outs))
                (unsigned-byte-p 1 (prd-h-rdv-at k outs))
                (unsigned-byte-p 1 (prd-h-hdf-at k outs))
                (unsigned-byte-p 1 (prd-h-lrv-at k outs))
                (unsigned-byte-p 1 (prd-h-lrf-at k outs))
                (unsigned-byte-p 1 (prd-h-arv-at k outs))
                (unsigned-byte-p 1 (prd-h-arl-at k outs))
                (unsigned-byte-p 1 (prd-h-adv-at k outs))
                (unsigned-byte-p 1 (prd-h-llr-at k outs))
                (unsigned-byte-p 16 (prd-h-lli-at k outs))
                (unsigned-byte-p 16 (prd-h-grd-at k outs))
                (unsigned-byte-p 1 (prd-h-kcr-at k outs))
                (unsigned-byte-p 1 (prd-h-sbr-at k outs))
                (unsigned-byte-p 1 (prd-h-spr-at k outs))
                (unsigned-byte-p 1 (prd-h-kpc-at k outs))
                (unsigned-byte-p 1 (prd-h-hsr-at k outs))
                (unsigned-byte-p 1 (prd-h-rif-at k outs))
                (unsigned-byte-p 1 (prd-h-paf-at k outs))
                (unsigned-byte-p 1 (prd-h-haf-at k outs))
                (unsigned-byte-p 1 (prd-h-hsv-at k outs))
                (unsigned-byte-p 1 (prd-h-lsv-at k outs))
                (unsigned-byte-p 1 (prd-h-dbusy-at k outs))
                (unsigned-byte-p 1 (prd-h-sif-at k outs))
                (unsigned-byte-p 1 (prd-h-sil-at k outs))
                (unsigned-byte-p 1 (prd-h-spm-at k outs))
                (unsigned-byte-p 8 (prd-h-siexp-at k outs))
                (unsigned-byte-p 11 (prd-h-sfpos-at k outs))
                (unsigned-byte-p 1 (prd-h-sdf-at k outs))
                (unsigned-byte-p 1 (prd-h-srf-at k outs))
                (unsigned-byte-p 8 (prd-h-srexp-at k outs))
                (unsigned-byte-p 16 (prd-h-srman-at k outs))
                (unsigned-byte-p 2048 (prd-d-kmem-at k outs))
                (unsigned-byte-p 2048 (prd-d-vmem-at k outs))))
  :hints (("Goal"
           :in-theory (e/d (prod-env-at prod-mem-at)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-SIZES done~%"))

; ---------------------------------------------------------------------------
; LOGS OF ACCEPTED RESULTS, and what a working memory holds of one.
; ---------------------------------------------------------------------------
(fgl::def-fgl-thm prd-slot-of-put
  (implies (and (unsigned-byte-p 7 c) (unsigned-byte-p 10 i)
                (unsigned-byte-p 16 m) (unsigned-byte-p 2048 mem))
           (equal (prod-slot c (prod-put i m mem))
                  (if (equal c (loghead 7 i)) m (prod-slot c mem)))))
(in-theory (disable prd-slot-of-put))

; ---- a log of accepted results: a list of (index mantissa exponent)
; some entry has index c
(defund prd-occurs (c log)
  (declare (xargs :verify-guards nil))
  (if (atom log) nil
    (or (equal (car (car log)) c) (prd-occurs c (cdr log)))))
; THE FINAL RESULT FOR INDEX c: the mantissa of the last entry with index c
(defund kv-final-result (c log)
  (declare (xargs :verify-guards nil))
  (cond ((atom log) 0)
        ((prd-occurs c (cdr log)) (kv-final-result c (cdr log)))
        ((equal (car (car log)) c) (second (car log)))
        (t 0)))
; THE FINAL EXPONENT: the exponent of the last entry
(defund kv-final-exponent (log)
  (declare (xargs :verify-guards nil))
  (third (car (last log))))
(defthm prd-occurs-of-snoc
  (equal (prd-occurs c (append log (list e)))
         (or (prd-occurs c log) (equal (car e) c)))
  :hints (("Goal" :in-theory (enable prd-occurs))))
(defthm kv-final-result-of-snoc
  (equal (kv-final-result c (append log (list e)))
         (if (equal (car e) c) (second e) (kv-final-result c log)))
  :hints (("Goal" :induct (kv-final-result c log)
           :in-theory (enable kv-final-result prd-occurs))))
(defthm kv-final-exponent-of-snoc
  (equal (kv-final-exponent (append log (list e))) (third e))
  :hints (("Goal" :in-theory (enable kv-final-exponent))))
; every index below n occurs
(defund prd-covers (n log)
  (declare (xargs :verify-guards nil))
  (if (zp n) t
    (and (prd-occurs (- n 1) log) (prd-covers (- n 1) log))))
(defthm prd-covers-of-snoc
  (implies (prd-covers n log)
           (prd-covers n (append log (list e))))
  :hints (("Goal" :in-theory (enable prd-covers))))
(defthm prd-covers-next
  (implies (and (prd-covers n log) (natp n) (equal (car e) n))
           (prd-covers (+ 1 n) (append log (list e))))
  :hints (("Goal" :do-not-induct t
           :expand ((prd-covers (+ 1 (car e)) (append log (list e)))))))
(defthm prd-covers-occurs
  (implies (and (prd-covers n log) (natp c) (natp n) (< c n))
           (prd-occurs c log))
  :hints (("Goal" :in-theory (enable prd-covers)))
  :rule-classes nil)
(defthm prd-covers-consp
  (implies (and (prd-covers n log) (posp n))
           (consp log))
  :hints (("Goal" :in-theory (enable prd-covers prd-occurs)))
  :rule-classes nil)
; for every index c below n that occurs, cell c of the memory holds the
; final result for c
(defund prd-mem-ok (n log mem)
  (declare (xargs :verify-guards nil))
  (if (zp n) t
    (and (or (not (prd-occurs (- n 1) log))
             (equal (prod-slot (- n 1) mem) (kv-final-result (- n 1) log)))
         (prd-mem-ok (- n 1) log mem))))
(defthm prd-mem-ok-of-nil
  (prd-mem-ok n nil mem)
  :hints (("Goal" :in-theory (enable prd-mem-ok prd-occurs))))
(defthm prd-index-size
  (implies (and (natp n) (< 0 n) (<= n 128))
           (unsigned-byte-p 7 (+ -1 n))))
(defthm prd-mem-ok-of-write
  (implies (and (prd-mem-ok n log mem)
                (natp n) (<= n 128)
                (unsigned-byte-p 10 i) (unsigned-byte-p 16 m) (unsigned-byte-p 2048 mem))
           (prd-mem-ok n (append log (list (list (loghead 7 i) m e)))
                       (prod-put i m mem)))
  :hints (("Goal" :induct (prd-mem-ok n log mem)
           :in-theory (e/d (prd-mem-ok prd-slot-of-put)
                           (prod-slot prod-put unsigned-byte-p loghead)))))
(defthm prd-mem-ok-lookup
  (implies (and (prd-mem-ok n log mem) (natp c) (natp n) (< c n)
                (prd-occurs c log))
           (equal (prod-slot c mem) (kv-final-result c log)))
  :hints (("Goal" :in-theory (enable prd-mem-ok)))
  :rule-classes nil)

(fgl::def-fgl-thm prd-index-small
  (implies (and (unsigned-byte-p 10 x) (<= x 127))
           (equal (loghead 7 x) x)))
(fgl::def-fgl-thm prd-index-next
  (implies (and (unsigned-byte-p 10 x) (<= x 126))
           (equal (loghead 10 (+ 1 x)) (+ 1 x))))
(fgl::def-fgl-thm prd-slot-of-index
  (implies (and (unsigned-byte-p 10 i) (unsigned-byte-p 2048 mem))
           (equal (prod-slot (loghead 7 i) mem) (prod-slot i mem))))
(in-theory (disable prd-index-small prd-index-next prd-slot-of-index))
(value-triple (acl2::cw "~%PRD-LISTS done~%"))

; ---------------------------------------------------------------------------
; THE STATE INVARIANT AND THE GUARD OF THE STEP FACTS, at a cycle.
; ---------------------------------------------------------------------------
(define prd-sinv-at (k outs) :verify-guards nil
  (prod-sinv (prd-d-eng-at k outs) (prd-d-cst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-est-at k outs) (prd-d-elay-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-d-sdone-at k outs) (prd-d-lseen-at k outs) (prd-s-state-at k outs) (prd-s-layer-at k outs) (prd-s-stage-at k outs) (prd-s-pos-at k outs)))
; no fault is registered in the sequencer or the datapath in cycle k
(define prd-nofault-at (k outs) :verify-guards nil
  (and (equal (prd-d-fault-at k outs) 0) (equal (prd-s-fault-at k outs) 0)))
; the children's reset is released in cycle k and the machine core is
; released in cycle k+1
(define prd-normal-at (k outs) :verify-guards nil
  (and (equal (prd-o-dprst-at k outs) 1) (logbitp 1 (prd-m-rel-at (+ 1 k) outs))))
(define prd-guard-at (k outs) :verify-guards nil
  (and (prd-normal-at k outs) (prd-nofault-at k outs) (prd-nofault-at (+ 1 k) outs)
       (prd-sinv-at k outs)))
(defthm prd-guard-is-plain
  (implies (prd-guard-at k outs)
           (prd-guard-plain (prd-d-fault-at (+ 1 k) outs) (prd-m-rel-at (+ 1 k) outs) (prd-s-fault-at (+ 1 k) outs) (prd-o-dprst-at k outs) (prd-d-clay-at k outs) (prd-d-cpos-at k outs) (prd-d-cst-at k outs) (prd-d-elay-at k outs) (prd-d-eng-at k outs) (prd-d-est-at k outs) (prd-d-fault-at k outs) (prd-d-lseen-at k outs) (prd-d-sdone-at k outs) (prd-d-tpos-at k outs) (prd-d-tseen-at k outs) (prd-s-fault-at k outs) (prd-s-layer-at k outs) (prd-s-pos-at k outs) (prd-s-stage-at k outs) (prd-s-state-at k outs)))
  :hints (("Goal" :in-theory (e/d (prd-guard-at prd-normal-at prd-nofault-at prd-sinv-at prd-guard-plain)
                                  (prod-sinv logbitp))))
  :rule-classes nil)
; what the state invariant says of a running stage, and of an expected
; stage other than the first
(defthm prd-sinv-busy
  (implies (and (prod-sinv eng cst clay cpos est elay tpos tseen sdone lseen sst slay sstage spos)
                (<= 1 eng) (<= eng 7))
           (and (equal est cst) (equal elay clay) (equal tpos cpos) (equal tseen 1)
                (equal sst 3) (equal spos cpos) (equal eng (prod-engine-of cst))))
  :hints (("Goal" :in-theory (enable prod-sinv prod-busy)))
  :rule-classes nil)
(defthm prd-sinv-expected
  (implies (and (prod-sinv eng cst clay cpos est elay tpos tseen sdone lseen sst slay sstage spos)
                (not (equal est 0)))
           (and (equal tseen 1) (not (equal sst 0)) (equal spos tpos)))
  :hints (("Goal" :in-theory (enable prod-sinv prod-busy)))
  :rule-classes nil)
(defthm prd-engine-of-stage
  (and (implies (equal (prod-engine-of cst) 4) (equal cst 6))
       (equal (prod-engine-of 5) 3) (equal (prod-engine-of 3) 2) (equal (prod-engine-of 6) 4))
  :hints (("Goal" :in-theory (enable prod-engine-of)))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; EVENTS OF A CYCLE.
; ---------------------------------------------------------------------------
; A stage request for stage s is accepted in cycle k: the datapath's
; stage_accept with private_stage_i = s.
(define prd-accept-at (s k outs) :verify-guards nil
  (and (equal (prd-o-sacc-at k outs) 1) (equal (prd-o-pstage-at k outs) s)))
; A K rotary result is accepted in cycle k: the key memory's write enable
; with current_stage_q = 5.  A V projection result is accepted in cycle k:
; the value memory's write enable.
(define prd-key-result-at (k outs) :verify-guards nil
  (and (equal (prd-o-kwe-at k outs) 1) (equal (prd-d-cst-at k outs) 5)))
(define prd-value-result-at (k outs) :verify-guards nil
  (equal (prd-o-vwe-at k outs) 1))
; The result accepted in cycle k, (index mantissa exponent): the write
; address output_index_q[6:0], norm_result_mantissa, norm_result_exponent.
(define prd-result-at (k outs) :verify-guards nil
  (list (loghead 7 (prd-d-oidx-at k outs)) (prd-h-nrm-at k outs) (prd-h-nre-at k outs)))

; THE K RESULTS before cycle k: the K rotary results accepted since the
; latest accepted request for the K rotary stage (stage 5), in order.
(defund prd-klog (k outs)
  (declare (xargs :measure (nfix k) :verify-guards nil))
  (cond ((zp k) nil)
        ((prd-accept-at 5 (- k 1) outs) nil)
        ((prd-key-result-at (- k 1) outs)
         (append (prd-klog (- k 1) outs) (list (prd-result-at (- k 1) outs))))
        (t (prd-klog (- k 1) outs))))
; THE V RESULTS before cycle k: the V projection results accepted since the
; latest accepted request for the V projection stage (stage 3), in order.
(defund prd-vlog (k outs)
  (declare (xargs :measure (nfix k) :verify-guards nil))
  (cond ((zp k) nil)
        ((prd-accept-at 3 (- k 1) outs) nil)
        ((prd-value-result-at (- k 1) outs)
         (append (prd-vlog (- k 1) outs) (list (prd-result-at (- k 1) outs))))
        (t (prd-vlog (- k 1) outs))))
; The cycle of the latest accepted request for stage s before cycle k; nil
; when there is none.
(defund prd-start (s k outs)
  (declare (xargs :measure (nfix k) :verify-guards nil))
  (cond ((zp k) nil)
        ((prd-accept-at s (- k 1) outs) (- k 1))
        (t (prd-start s (- k 1) outs))))
; The cycle of the latest accepted sequencer start before cycle k; nil when
; there is none.
(defund prd-pass-start (k outs)
  (declare (xargs :measure (nfix k) :verify-guards nil))
  (cond ((zp k) nil)
        ((equal (prd-o-sfire-at (- k 1) outs) 1) (- k 1))
        (t (prd-pass-start (- k 1) outs))))
; No CLEAR reaches the datapath in cycles a .. k-1.
(defund prd-no-clear (a k outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix a))) :verify-guards nil))
  (or (zp (- (nfix k) (nfix a)))
      (and (equal (prd-o-dpclear-at (- (nfix k) 1) outs) 0)
           (prd-no-clear a (- (nfix k) 1) outs))))

; The sequencer is busy in every cycle a+1 .. k.
(defund prd-busy-since (a k outs)
  (declare (xargs :measure (nfix (- (nfix k) (nfix a))) :verify-guards nil))
  (or (zp (- (nfix k) (nfix a)))
      (and (not (equal (prd-s-state-at (nfix k) outs) 0))
           (prd-busy-since a (- (nfix k) 1) outs))))

(defthm prd-klog-next
  (implies (natp k)
           (equal (prd-klog (+ 1 k) outs)
                  (cond ((prd-accept-at 5 k outs) nil)
                        ((prd-key-result-at k outs)
                         (append (prd-klog k outs) (list (prd-result-at k outs))))
                        (t (prd-klog k outs)))))
  :hints (("Goal" :expand ((prd-klog (+ 1 k) outs)))))
(defthm prd-vlog-next
  (implies (natp k)
           (equal (prd-vlog (+ 1 k) outs)
                  (cond ((prd-accept-at 3 k outs) nil)
                        ((prd-value-result-at k outs)
                         (append (prd-vlog k outs) (list (prd-result-at k outs))))
                        (t (prd-vlog k outs)))))
  :hints (("Goal" :expand ((prd-vlog (+ 1 k) outs)))))
(defthm prd-start-next
  (implies (natp k)
           (equal (prd-start s (+ 1 k) outs)
                  (if (prd-accept-at s k outs) k (prd-start s k outs))))
  :hints (("Goal" :expand ((prd-start s (+ 1 k) outs)))))
(defthm prd-pass-start-next
  (implies (natp k)
           (equal (prd-pass-start (+ 1 k) outs)
                  (if (equal (prd-o-sfire-at k outs) 1) k (prd-pass-start k outs))))
  :hints (("Goal" :expand ((prd-pass-start (+ 1 k) outs)))))
(defthm prd-start-bound
  (implies (prd-start s k outs)
           (and (natp (prd-start s k outs))
                (< (prd-start s k outs) k)
                (prd-accept-at s (prd-start s k outs) outs)))
  :hints (("Goal" :in-theory (enable prd-start)))
  :rule-classes nil)
(defthm prd-pass-start-bound
  (implies (prd-pass-start k outs)
           (and (natp (prd-pass-start k outs))
                (< (prd-pass-start k outs) k)
                (equal (prd-o-sfire-at (prd-pass-start k outs) outs) 1)))
  :hints (("Goal" :in-theory (enable prd-pass-start)))
  :rule-classes nil)
(defthm prd-no-clear-next
  (implies (and (natp a) (natp k) (<= a k))
           (equal (prd-no-clear a (+ 1 k) outs)
                  (and (equal (prd-o-dpclear-at k outs) 0)
                       (prd-no-clear a k outs))))
  :hints (("Goal" :expand ((prd-no-clear a (+ 1 k) outs)))))
(defthm prd-no-clear-empty
  (prd-no-clear k k outs)
  :hints (("Goal" :in-theory (enable prd-no-clear))))
(defthm prd-busy-since-next
  (implies (and (natp a) (natp k) (<= a k))
           (equal (prd-busy-since a (+ 1 k) outs)
                  (and (not (equal (prd-s-state-at (+ 1 k) outs) 0))
                       (prd-busy-since a k outs))))
  :hints (("Goal" :expand ((prd-busy-since a (+ 1 k) outs)))))
(defthm prd-busy-since-empty
  (prd-busy-since k k outs)
  :hints (("Goal" :in-theory (enable prd-busy-since))))
(defthm prd-busy-since-at
  (implies (and (prd-busy-since a k outs) (natp a) (natp j) (natp k) (< a j) (<= j k))
           (not (equal (prd-s-state-at j outs) 0)))
  :hints (("Goal" :induct (prd-busy-since a k outs)
           :in-theory (enable prd-busy-since)))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-GHOSTS done~%"))

; ---------------------------------------------------------------------------
; THE INVARIANT.
; ---------------------------------------------------------------------------
; In the K rotary stage: the results accepted so far cover the indices below
; the output index (all 128 once the last has been accepted), the key memory
; holds the final result for each of them, key_exponent_q is the latest
; result's exponent, the stage's request was for the expected layer and the
; transaction's position, and it came after the V projection stage's.
(defund prd-krun-ok (k outs)
  (declare (xargs :verify-guards nil))
  (b* ((o (prd-d-oidx-at k outs)) (d (prd-d-odone-at k outs))
       (log (prd-klog k outs)) (ks (prd-start 5 k outs)) (vs (prd-start 3 k outs)))
    (and (<= o 127) (or (equal d 0) (equal o 127))
         (prd-covers (if (equal d 0) o 128) log)
         (prd-mem-ok 128 log (prd-d-kmem-at k outs))
         (or (and (equal o 0) (equal d 0)) (equal (prd-d-kexp-at k outs) (kv-final-exponent log)))
         ks (equal (prd-o-player-at ks outs) (prd-d-elay-at k outs))
         (equal (prd-o-ppos-at ks outs) (prd-d-tpos-at k outs))
         vs (< vs ks))))
; With stage 6 expected: the K results cover all 128 indices, the key memory
; holds the final result for each, and key_exponent_q is the last one's
; exponent.
(defund prd-kdone-ok (k outs)
  (declare (xargs :verify-guards nil))
  (b* ((log (prd-klog k outs)) (ks (prd-start 5 k outs)) (vs (prd-start 3 k outs)))
    (and (prd-covers 128 log)
         (prd-mem-ok 128 log (prd-d-kmem-at k outs))
         (equal (prd-d-kexp-at k outs) (kv-final-exponent log))
         ks (equal (prd-o-player-at ks outs) (prd-d-elay-at k outs))
         (equal (prd-o-ppos-at ks outs) (prd-d-tpos-at k outs))
         vs (< vs ks))))
; The same of the V projection stage and the value memory; its request came
; after the sequencer's start of the pass.
(defund prd-vrun-ok (k outs)
  (declare (xargs :verify-guards nil))
  (b* ((o (prd-d-oidx-at k outs)) (d (prd-d-odone-at k outs))
       (log (prd-vlog k outs)) (vs (prd-start 3 k outs)) (ps (prd-pass-start k outs)))
    (and (<= o 127) (or (equal d 0) (equal o 127))
         (prd-covers (if (equal d 0) o 128) log)
         (prd-mem-ok 128 log (prd-d-vmem-at k outs))
         (or (and (equal o 0) (equal d 0)) (equal (prd-d-vexp-at k outs) (kv-final-exponent log)))
         vs (equal (prd-o-player-at vs outs) (prd-d-elay-at k outs))
         (equal (prd-o-ppos-at vs outs) (prd-d-tpos-at k outs))
         ps (< ps vs))))
(defund prd-vdone-ok (k outs)
  (declare (xargs :verify-guards nil))
  (b* ((log (prd-vlog k outs)) (vs (prd-start 3 k outs)) (ps (prd-pass-start k outs)))
    (and (prd-covers 128 log)
         (prd-mem-ok 128 log (prd-d-vmem-at k outs))
         (equal (prd-d-vexp-at k outs) (kv-final-exponent log))
         vs (equal (prd-o-player-at vs outs) (prd-d-elay-at k outs))
         (equal (prd-o-ppos-at vs outs) (prd-d-tpos-at k outs))
         ps (< ps vs))))
; A landed read in the K/V stage: each read register holds its memory's cell
; of the input index.
(defund prd-read-ok (k outs)
  (declare (xargs :verify-guards nil))
  (and (equal (prd-d-krd-at k outs) (prod-slot (prd-d-iidx-at k outs) (prd-d-kmem-at k outs)))
       (equal (prd-d-vrd-at k outs) (prod-slot (prd-d-iidx-at k outs) (prd-d-vmem-at k outs)))))
; In the K/V stage: its request was for the expected layer and the
; transaction's position, and came after the K rotary stage's.
(defund prd-kv-ok (k outs)
  (declare (xargs :verify-guards nil))
  (b* ((ss (prd-start 6 k outs)) (ks (prd-start 5 k outs)))
    (and ss ks (< ks ss)
         (equal (prd-o-player-at ss outs) (prd-d-elay-at k outs))
         (equal (prd-o-ppos-at ss outs) (prd-d-tpos-at k outs)))))
; While the sequencer is busy: its position is the one offered with its
; start, no CLEAR has reached the datapath since, and it has been busy in
; every cycle since.
(defund prd-seq-ok (k outs)
  (declare (xargs :verify-guards nil))
  (b* ((ps (prd-pass-start k outs)))
    (and ps (equal (prd-s-pos-at k outs) (prd-h-sfpos-at ps outs))
         (prd-no-clear ps k outs)
         (prd-busy-since ps k outs))))
(defund prd-inv (k outs)
  (declare (xargs :verify-guards nil))
  (b* ((e (prd-d-eng-at k outs)) (c (prd-d-cst-at k outs)) (x (prd-d-est-at k outs)))
    (and (or (not (and (equal e 3) (equal c 5))) (prd-krun-ok k outs))
         (or (not (equal x 6)) (prd-kdone-ok k outs))
         (or (not (and (equal e 2) (equal c 3))) (prd-vrun-ok k outs))
         (or (not (and (<= 4 x) (<= x 6))) (prd-vdone-ok k outs))
         (or (not (and (equal e 4) (equal (prd-d-kvrv-at k outs) 1))) (prd-read-ok k outs))
         (or (not (equal e 4)) (prd-kv-ok k outs))
         (or (equal (prd-s-state-at k outs) 0) (prd-seq-ok k outs)))))
(value-triple (acl2::cw "~%PRD-INV defined~%"))
(defthm prd-ev-accept
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-o-sacc-at k outs) 1))
           (and (equal (prd-d-eng-at k outs) 0) (equal (prd-o-dpclear-at k outs) 0) (equal (prd-o-pstage-at k outs) (prd-d-est-at k outs)) (equal (prd-o-player-at k outs) (prd-d-elay-at k outs))
                (equal (prd-d-cst-at (+ 1 k) outs) (prd-o-pstage-at k outs)) (equal (prd-d-tpos-at (+ 1 k) outs) (prd-o-ppos-at k outs)) (equal (prd-d-est-at (+ 1 k) outs) (prd-d-est-at k outs)) (equal (prd-d-elay-at (+ 1 k) outs) (prd-d-elay-at k outs))
                (equal (prd-d-oidx-at (+ 1 k) outs) 0) (equal (prd-d-odone-at (+ 1 k) outs) 0) (equal (prd-d-kvrv-at (+ 1 k) outs) 0)
                (equal (prd-d-eng-at (+ 1 k) outs) (prod-engine-of (prd-o-pstage-at k outs)))
                (equal (prd-o-kwe-at k outs) 0) (equal (prd-o-vwe-at k outs) 0)))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-accept)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-key-write
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-o-kwe-at k outs) 1))
           (and (equal (prd-o-dpclear-at k outs) 0) (equal (prd-h-nri-at k outs) (prd-d-oidx-at k outs))
                (or (and (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 2)) (and (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5)))
                (equal (prd-d-kmem-at (+ 1 k) outs) (prod-put (prd-d-oidx-at k outs) (prd-h-nrm-at k outs) (prd-d-kmem-at k outs))) (equal (prd-d-kexp-at (+ 1 k) outs) (prd-h-nre-at k outs))
                (implies (equal (prd-d-cst-at k outs) 5)
                         (and (equal (prd-h-nrl-at k outs) (if (equal (prd-d-oidx-at k outs) 127) 1 0))
                     (implies (equal (prd-h-nrl-at k outs) 1) (and (equal (prd-d-odone-at (+ 1 k) outs) 1) (equal (prd-d-oidx-at (+ 1 k) outs) (prd-d-oidx-at k outs))))
                     (implies (not (equal (prd-h-nrl-at k outs) 1))
                              (and (equal (prd-d-odone-at (+ 1 k) outs) (prd-d-odone-at k outs)) (equal (prd-d-oidx-at (+ 1 k) outs) (loghead 10 (+ 1 (prd-d-oidx-at k outs))))))))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-key-write)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-key-quiet
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (not (equal (prd-o-kwe-at k outs) 1)))
           (and (equal (prd-d-kmem-at (+ 1 k) outs) (prd-d-kmem-at k outs)) (equal (prd-d-kexp-at (+ 1 k) outs) (prd-d-kexp-at k outs))
                (implies (and (and (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5)) (equal (prd-o-dpclear-at k outs) 0))
                         (and (equal (prd-d-odone-at (+ 1 k) outs) (prd-d-odone-at k outs)) (equal (prd-d-oidx-at (+ 1 k) outs) (prd-d-oidx-at k outs))))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-key-write)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-value-write
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-o-vwe-at k outs) 1))
           (and (equal (prd-o-dpclear-at k outs) 0) (equal (prd-h-nri-at k outs) (prd-d-oidx-at k outs))
                (and (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3))
                (equal (prd-d-vmem-at (+ 1 k) outs) (prod-put (prd-d-oidx-at k outs) (prd-h-nrm-at k outs) (prd-d-vmem-at k outs))) (equal (prd-d-vexp-at (+ 1 k) outs) (prd-h-nre-at k outs))
                (and (equal (prd-h-nrl-at k outs) (if (equal (prd-d-oidx-at k outs) 127) 1 0))
                     (implies (equal (prd-h-nrl-at k outs) 1) (and (equal (prd-d-odone-at (+ 1 k) outs) 1) (equal (prd-d-oidx-at (+ 1 k) outs) (prd-d-oidx-at k outs))))
                     (implies (not (equal (prd-h-nrl-at k outs) 1))
                              (and (equal (prd-d-odone-at (+ 1 k) outs) (prd-d-odone-at k outs)) (equal (prd-d-oidx-at (+ 1 k) outs) (loghead 10 (+ 1 (prd-d-oidx-at k outs)))))))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-value-write)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-value-quiet
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (not (equal (prd-o-vwe-at k outs) 1)))
           (and (equal (prd-d-vmem-at (+ 1 k) outs) (prd-d-vmem-at k outs)) (equal (prd-d-vexp-at (+ 1 k) outs) (prd-d-vexp-at k outs))
                (implies (and (and (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3)) (equal (prd-o-dpclear-at k outs) 0))
                         (and (equal (prd-d-odone-at (+ 1 k) outs) (prd-d-odone-at k outs)) (equal (prd-d-oidx-at (+ 1 k) outs) (prd-d-oidx-at k outs))))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-value-write)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-entry
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                t)
           (and (implies (and (equal (prd-d-eng-at (+ 1 k) outs) 3) (equal (prd-d-cst-at (+ 1 k) outs) 5) (not (and (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5))))
                         (and (equal (prd-o-sacc-at k outs) 1) (equal (prd-o-pstage-at k outs) 5)))
                (implies (and (equal (prd-d-eng-at (+ 1 k) outs) 2) (equal (prd-d-cst-at (+ 1 k) outs) 3) (not (and (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3))))
                         (and (equal (prd-o-sacc-at k outs) 1) (equal (prd-o-pstage-at k outs) 3)))
                (implies (and (equal (prd-d-eng-at (+ 1 k) outs) 4) (not (equal (prd-d-eng-at k outs) 4)))
                         (and (equal (prd-o-sacc-at k outs) 1) (equal (prd-o-pstage-at k outs) 6)))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-stage-entry)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-key-stage
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5) (equal (prd-o-dpclear-at k outs) 0))
           (or (and (equal (prd-d-eng-at (+ 1 k) outs) 3) (equal (prd-d-cst-at (+ 1 k) outs) 5) (equal (prd-d-est-at (+ 1 k) outs) (prd-d-est-at k outs)))
               (and (equal (prd-d-eng-at (+ 1 k) outs) 0) (equal (prd-d-est-at (+ 1 k) outs) 6)
                    (or (equal (prd-d-odone-at k outs) 1) (and (equal (prd-o-kwe-at k outs) 1) (equal (prd-h-nrl-at k outs) 1))))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-key-stage-end)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-value-stage
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3) (equal (prd-o-dpclear-at k outs) 0))
           (or (and (equal (prd-d-eng-at (+ 1 k) outs) 2) (equal (prd-d-cst-at (+ 1 k) outs) 3) (equal (prd-d-est-at (+ 1 k) outs) (prd-d-est-at k outs)))
               (and (equal (prd-d-eng-at (+ 1 k) outs) 0) (equal (prd-d-est-at (+ 1 k) outs) 4)
                    (or (equal (prd-d-odone-at k outs) 1) (and (equal (prd-o-vwe-at k outs) 1) (equal (prd-h-nrl-at k outs) 1))))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-value-stage-end)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-value-done-entry
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (<= 4 (prd-d-est-at (+ 1 k) outs)) (<= (prd-d-est-at (+ 1 k) outs) 6) (not (and (<= 4 (prd-d-est-at k outs)) (<= (prd-d-est-at k outs) 6))))
           (and (equal (prd-d-est-at k outs) 3) (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3) (equal (prd-o-dpclear-at k outs) 0) (equal (prd-d-est-at (+ 1 k) outs) 4)))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-value-done-entry)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-key-done-entry
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-d-est-at (+ 1 k) outs) 6) (not (equal (prd-d-est-at k outs) 6)))
           (and (equal (prd-d-est-at k outs) 5) (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5) (equal (prd-o-dpclear-at k outs) 0)))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-key-done-entry)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-value-frozen
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (<= 4 (prd-d-est-at k outs)) (<= (prd-d-est-at k outs) 6))
           (and (equal (prd-o-vwe-at k outs) 0) (not (and (equal (prd-o-sacc-at k outs) 1) (equal (prd-o-pstage-at k outs) 3)))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-value-frozen)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-key-frozen
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-d-est-at k outs) 6))
           (and (equal (prd-o-kwe-at k outs) 0) (not (and (equal (prd-o-sacc-at k outs) 1) (equal (prd-o-pstage-at k outs) 5)))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-key-frozen)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-transaction
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (<= 3 (prd-d-est-at k outs)) (<= (prd-d-est-at k outs) 6) (equal (prd-o-dpclear-at k outs) 0))
           (and (equal (prd-d-elay-at (+ 1 k) outs) (prd-d-elay-at k outs)) (equal (prd-d-tpos-at (+ 1 k) outs) (prd-d-tpos-at k outs)) (equal (prd-d-tseen-at k outs) 1) (equal (prd-d-tseen-at (+ 1 k) outs) 1)))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-transaction)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-staging-stage
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-d-est-at k outs) 6) (equal (prd-o-dpclear-at k outs) 0))
           (or (equal (prd-d-est-at (+ 1 k) outs) 6) (and (equal (prd-d-est-at (+ 1 k) outs) 7) (equal (prd-h-kpc-at k outs) 1) (equal (prd-d-eng-at k outs) 4))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-staging-stage)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-memory-read
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                t)
           (and (if (equal (prd-o-kre-at k outs) 1)
                    (equal (prd-d-krd-at (+ 1 k) outs) (prod-slot (prd-o-kra-at k outs) (prd-d-kmem-at k outs)))
                  (equal (prd-d-krd-at (+ 1 k) outs) (prd-d-krd-at k outs)))
                (if (equal (prd-o-vre-at k outs) 1)
                    (equal (prd-d-vrd-at (+ 1 k) outs) (prod-slot (prd-o-vra-at k outs) (prd-d-vmem-at k outs)))
                  (equal (prd-d-vrd-at (+ 1 k) outs) (prd-d-vrd-at k outs)))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-memory-read)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-staging-read
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-d-eng-at k outs) 4) (equal (prd-d-eng-at (+ 1 k) outs) 4) (equal (prd-d-kvrv-at (+ 1 k) outs) 1))
           (and (equal (prd-d-iidx-at (+ 1 k) outs) (prd-d-iidx-at k outs))
                (or (and (equal (prd-d-kvrv-at k outs) 1) (equal (prd-o-kre-at k outs) 0) (equal (prd-o-vre-at k outs) 0))
                    (and (equal (prd-d-kvrv-at k outs) 0) (equal (prd-o-kre-at k outs) 1) (equal (prd-o-vre-at k outs) 1)
                         (equal (prd-o-kra-at k outs) (loghead 7 (prd-d-iidx-at k outs))) (equal (prd-o-vra-at k outs) (loghead 7 (prd-d-iidx-at k outs)))))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-staging-read)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-sequence
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                t)
           (and (implies (equal (prd-o-sfire-at k outs) 1)
                         (and (equal (prd-s-state-at k outs) 0) (equal (prd-s-state-at (+ 1 k) outs) 1) (equal (prd-s-pos-at (+ 1 k) outs) (prd-h-sfpos-at k outs))
                              (equal (prd-h-lsv-at k outs) 1) (equal (prd-o-dpclear-at k outs) 0)))
                (implies (and (equal (prd-s-state-at k outs) 0) (not (equal (prd-s-state-at (+ 1 k) outs) 0)))
                         (equal (prd-o-sfire-at k outs) 1))
                (implies (and (not (equal (prd-s-state-at k outs) 0)) (not (equal (prd-s-state-at (+ 1 k) outs) 0)))
                         (and (equal (prd-s-pos-at (+ 1 k) outs) (prd-s-pos-at k outs)) (equal (prd-o-sfire-at k outs) 0) (equal (prd-o-dpclear-at k outs) 0)))))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-sequence)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-sequence-done
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-s-state-at k outs) 5) (equal (prd-h-sdf-at k outs) 1))
           (equal (prd-s-state-at (+ 1 k) outs) 0))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-sequence-done)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-clear
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (not (equal (prd-o-dpclear-at k outs) 0)))
           (and (equal (prd-d-eng-at (+ 1 k) outs) 0) (equal (prd-d-est-at (+ 1 k) outs) 0) (equal (prd-s-state-at (+ 1 k) outs) 0)))
  :hints (("Goal"
           :use ((:instance prd-step) (:instance prd-guard-is-plain))
           :in-theory (e/d (prd-p-clear-resets)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-staging-valid
  (implies (and (natp k) (prd-known-at k envs outs)
                t)
           (and (implies (equal (prd-o-sbv-at k outs) 1) (and (equal (prd-d-eng-at k outs) 4) (equal (prd-d-sss-at k outs) 0)))
                (implies (equal (prd-o-spv-at k outs) 1) (and (equal (prd-d-eng-at k outs) 4) (equal (prd-d-kvrv-at k outs) 1)))))
  :hints (("Goal"
           :use ((:instance prd-step))
           :in-theory (e/d (prd-p-staging-valid)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-public-clear
  (implies (and (natp k) (prd-known-at k envs outs)
                (equal (prd-i-clear-at k envs) 0))
           (equal (prd-o-dpclear-at k outs) 0))
  :hints (("Goal"
           :use ((:instance prd-step))
           :in-theory (e/d (prd-p-clear)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-reset
  (implies (and (natp k) (prd-known-at k envs outs)
                (not (prd-normal-at k outs)))
           (and (equal (prd-d-eng-at (+ 1 k) outs) 0) (equal (prd-d-est-at (+ 1 k) outs) 0) (equal (prd-s-state-at (+ 1 k) outs) 0) (prd-sinv-at (+ 1 k) outs)))
  :hints (("Goal"
           :use ((:instance prd-step))
           :in-theory (e/d (prd-p-reset prd-normal-at prd-sinv-at)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-busy
  (implies (and (prd-sinv-at k outs) (<= 1 (prd-d-eng-at k outs)) (<= (prd-d-eng-at k outs) 7))
           (and (equal (prd-d-est-at k outs) (prd-d-cst-at k outs)) (equal (prd-d-elay-at k outs) (prd-d-clay-at k outs)) (equal (prd-d-tpos-at k outs) (prd-d-cpos-at k outs)) (equal (prd-d-tseen-at k outs) 1)
                (equal (prd-s-state-at k outs) 3) (equal (prd-s-pos-at k outs) (prd-d-cpos-at k outs))
                (equal (prd-d-eng-at k outs) (prod-engine-of (prd-d-cst-at k outs)))))
  :hints (("Goal" :use ((:instance prd-sinv-busy
                  (eng (prd-d-eng-at k outs))
                  (cst (prd-d-cst-at k outs))
                  (clay (prd-d-clay-at k outs))
                  (cpos (prd-d-cpos-at k outs))
                  (est (prd-d-est-at k outs))
                  (elay (prd-d-elay-at k outs))
                  (tpos (prd-d-tpos-at k outs))
                  (tseen (prd-d-tseen-at k outs))
                  (sdone (prd-d-sdone-at k outs))
                  (lseen (prd-d-lseen-at k outs))
                  (sst (prd-s-state-at k outs))
                  (slay (prd-s-layer-at k outs))
                  (sstage (prd-s-stage-at k outs))
                  (spos (prd-s-pos-at k outs))))
           :in-theory (e/d (prd-sinv-at) (prod-sinv prod-engine-of))))
  :rule-classes nil)
(defthm prd-ev-expected
  (implies (and (prd-sinv-at k outs) (not (equal (prd-d-est-at k outs) 0)))
           (and (equal (prd-d-tseen-at k outs) 1) (not (equal (prd-s-state-at k outs) 0)) (equal (prd-s-pos-at k outs) (prd-d-tpos-at k outs))))
  :hints (("Goal" :use ((:instance prd-sinv-expected
                  (eng (prd-d-eng-at k outs))
                  (cst (prd-d-cst-at k outs))
                  (clay (prd-d-clay-at k outs))
                  (cpos (prd-d-cpos-at k outs))
                  (est (prd-d-est-at k outs))
                  (elay (prd-d-elay-at k outs))
                  (tpos (prd-d-tpos-at k outs))
                  (tseen (prd-d-tseen-at k outs))
                  (sdone (prd-d-sdone-at k outs))
                  (lseen (prd-d-lseen-at k outs))
                  (sst (prd-s-state-at k outs))
                  (slay (prd-s-layer-at k outs))
                  (sstage (prd-s-stage-at k outs))
                  (spos (prd-s-pos-at k outs))))
           :in-theory (e/d (prd-sinv-at) (prod-sinv))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-EVENTS done~%"))
(defthm prd-krun-stay
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5) (equal (prd-d-eng-at (+ 1 k) outs) 3) (equal (prd-d-cst-at (+ 1 k) outs) 5)
                (prd-krun-ok k outs))
           (prd-krun-ok (+ 1 k) outs))
  :hints (("Goal"
           :cases ((equal (prd-o-kwe-at k outs) 1))
           :use ((:instance prd-ev-accept)
                 (:instance prd-ev-key-write)
                 (:instance prd-ev-key-quiet)
                 (:instance prd-ev-transaction)
                 (:instance prd-ev-busy)
                 (:instance prd-ev-clear)
                 (:instance prd-sizes)
                 (:instance prd-start-bound (s 3))
                 (:instance prd-start-bound (s 5))
                 (:instance prd-mem-ok-of-write (n 128) (log (prd-klog k outs)) (mem (prd-d-kmem-at k outs)) (i (prd-d-oidx-at k outs)) (m (prd-h-nrm-at k outs)) (e (prd-h-nre-at k outs))))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-krun-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-krun-enter
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (not (and (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5))) (equal (prd-d-eng-at (+ 1 k) outs) 3) (equal (prd-d-cst-at (+ 1 k) outs) 5)
                (or (not (and (<= 4 (prd-d-est-at k outs)) (<= (prd-d-est-at k outs) 6))) (prd-vdone-ok k outs)))
           (prd-krun-ok (+ 1 k) outs))
  :hints (("Goal"
           :use ((:instance prd-ev-entry)
                 (:instance prd-ev-accept)
                 (:instance prd-start-bound (s 3)))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-krun-ok prd-vdone-ok prd-covers)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-kdone-stay
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (equal (prd-d-est-at k outs) 6) (equal (prd-d-est-at (+ 1 k) outs) 6) (prd-kdone-ok k outs))
           (prd-kdone-ok (+ 1 k) outs))
  :hints (("Goal"
           :use ((:instance prd-ev-key-frozen)
                 (:instance prd-ev-value-frozen)
                 (:instance prd-ev-key-quiet)
                 (:instance prd-ev-transaction)
                 (:instance prd-ev-clear))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-kdone-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-kdone-enter
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (not (equal (prd-d-est-at k outs) 6)) (equal (prd-d-est-at (+ 1 k) outs) 6)
                (or (not (and (equal (prd-d-eng-at k outs) 3) (equal (prd-d-cst-at k outs) 5))) (prd-krun-ok k outs)))
           (prd-kdone-ok (+ 1 k) outs))
  :hints (("Goal"
           :cases ((equal (prd-o-kwe-at k outs) 1))
           :use ((:instance prd-ev-key-done-entry)
                 (:instance prd-ev-key-stage)
                 (:instance prd-ev-accept)
                 (:instance prd-ev-key-write)
                 (:instance prd-ev-key-quiet)
                 (:instance prd-ev-transaction)
                 (:instance prd-sizes)
                 (:instance prd-start-bound (s 3))
                 (:instance prd-start-bound (s 5))
                 (:instance prd-covers-consp (n 128) (log (prd-klog k outs)))
                 (:instance prd-mem-ok-of-write (n 128) (log (prd-klog k outs)) (mem (prd-d-kmem-at k outs)) (i (prd-d-oidx-at k outs)) (m (prd-h-nrm-at k outs)) (e (prd-h-nre-at k outs))))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-krun-ok prd-kdone-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-K done~%"))
(defthm prd-vrun-stay
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3) (equal (prd-d-eng-at (+ 1 k) outs) 2) (equal (prd-d-cst-at (+ 1 k) outs) 3)
                (prd-vrun-ok k outs))
           (prd-vrun-ok (+ 1 k) outs))
  :hints (("Goal"
           :cases ((equal (prd-o-vwe-at k outs) 1))
           :use ((:instance prd-ev-accept)
                 (:instance prd-ev-value-write)
                 (:instance prd-ev-value-quiet)
                 (:instance prd-ev-transaction)
                 (:instance prd-ev-busy)
                 (:instance prd-ev-busy (k (+ 1 k)))
                 (:instance prd-ev-sequence)
                 (:instance prd-ev-clear)
                 (:instance prd-sizes)
                 (:instance prd-start-bound (s 3))
                 (:instance prd-pass-start-bound)
                 (:instance prd-mem-ok-of-write (n 128) (log (prd-vlog k outs)) (mem (prd-d-vmem-at k outs)) (i (prd-d-oidx-at k outs)) (m (prd-h-nrm-at k outs)) (e (prd-h-nre-at k outs))))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-vrun-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-vrun-enter
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at (+ 1 k) outs)
                (not (and (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3))) (equal (prd-d-eng-at (+ 1 k) outs) 2) (equal (prd-d-cst-at (+ 1 k) outs) 3)
                (or (equal (prd-s-state-at k outs) 0) (prd-seq-ok k outs)))
           (prd-vrun-ok (+ 1 k) outs))
  :hints (("Goal"
           :use ((:instance prd-ev-entry)
                 (:instance prd-ev-accept)
                 (:instance prd-ev-busy (k (+ 1 k)))
                 (:instance prd-ev-sequence)
                 (:instance prd-pass-start-bound))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-vrun-ok prd-seq-ok prd-covers)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-vdone-stay
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (<= 4 (prd-d-est-at k outs)) (<= (prd-d-est-at k outs) 6) (<= 4 (prd-d-est-at (+ 1 k) outs)) (<= (prd-d-est-at (+ 1 k) outs) 6) (prd-vdone-ok k outs))
           (prd-vdone-ok (+ 1 k) outs))
  :hints (("Goal"
           :use ((:instance prd-ev-value-frozen)
                 (:instance prd-ev-value-quiet)
                 (:instance prd-ev-transaction)
                 (:instance prd-ev-clear)
                 (:instance prd-ev-expected)
                 (:instance prd-ev-expected (k (+ 1 k)))
                 (:instance prd-ev-sequence))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-vdone-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-vdone-enter
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (not (and (<= 4 (prd-d-est-at k outs)) (<= (prd-d-est-at k outs) 6))) (<= 4 (prd-d-est-at (+ 1 k) outs)) (<= (prd-d-est-at (+ 1 k) outs) 6)
                (or (not (and (equal (prd-d-eng-at k outs) 2) (equal (prd-d-cst-at k outs) 3))) (prd-vrun-ok k outs)))
           (prd-vdone-ok (+ 1 k) outs))
  :hints (("Goal"
           :cases ((equal (prd-o-vwe-at k outs) 1))
           :use ((:instance prd-ev-value-done-entry)
                 (:instance prd-ev-value-stage)
                 (:instance prd-ev-accept)
                 (:instance prd-ev-value-write)
                 (:instance prd-ev-value-quiet)
                 (:instance prd-ev-transaction)
                 (:instance prd-ev-expected)
                 (:instance prd-ev-expected (k (+ 1 k)))
                 (:instance prd-ev-sequence)
                 (:instance prd-sizes)
                 (:instance prd-start-bound (s 3))
                 (:instance prd-pass-start-bound)
                 (:instance prd-covers-consp (n 128) (log (prd-vlog k outs)))
                 (:instance prd-mem-ok-of-write (n 128) (log (prd-vlog k outs)) (mem (prd-d-vmem-at k outs)) (i (prd-d-oidx-at k outs)) (m (prd-h-nrm-at k outs)) (e (prd-h-nre-at k outs))))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-vrun-ok prd-vdone-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-V done~%"))
(defthm prd-read-step
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (equal (prd-d-eng-at (+ 1 k) outs) 4) (equal (prd-d-kvrv-at (+ 1 k) outs) 1)
                (or (not (and (equal (prd-d-eng-at k outs) 4) (equal (prd-d-kvrv-at k outs) 1))) (prd-read-ok k outs)))
           (prd-read-ok (+ 1 k) outs))
  :hints (("Goal"
           :use ((:instance prd-ev-entry)
                 (:instance prd-ev-accept)
                 (:instance prd-ev-staging-read)
                 (:instance prd-ev-memory-read)
                 (:instance prd-ev-busy)
                 (:instance prd-ev-key-frozen)
                 (:instance prd-ev-value-frozen)
                 (:instance prd-ev-key-quiet)
                 (:instance prd-ev-value-quiet)
                 (:instance prd-sizes)
                 (:instance prd-engine-of-stage (cst (prd-d-cst-at k outs)))
                 (:instance prd-slot-of-index (i (prd-d-iidx-at k outs)) (mem (prd-d-kmem-at k outs)))
                 (:instance prd-slot-of-index (i (prd-d-iidx-at k outs)) (mem (prd-d-vmem-at k outs))))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-read-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-kv-step
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (equal (prd-d-eng-at (+ 1 k) outs) 4)
                (or (not (equal (prd-d-eng-at k outs) 4)) (prd-kv-ok k outs))
                (or (not (equal (prd-d-est-at k outs) 6)) (prd-kdone-ok k outs)))
           (prd-kv-ok (+ 1 k) outs))
  :hints (("Goal"
           :use ((:instance prd-ev-entry)
                 (:instance prd-ev-accept)
                 (:instance prd-ev-busy)
                 (:instance prd-ev-transaction)
                 (:instance prd-ev-clear)
                 (:instance prd-start-bound (s 5))
                 (:instance prd-start-bound (s 6))
                 (:instance prd-engine-of-stage (cst (prd-d-cst-at k outs))))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-kv-ok prd-kdone-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-seq-step
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (not (equal (prd-s-state-at (+ 1 k) outs) 0))
                (or (equal (prd-s-state-at k outs) 0) (prd-seq-ok k outs)))
           (prd-seq-ok (+ 1 k) outs))
  :hints (("Goal"
           :use ((:instance prd-ev-sequence)
                 (:instance prd-pass-start-bound))
           :in-theory (e/d (prd-accept-at prd-key-result-at prd-value-result-at prd-result-at
                            prd-index-small prd-index-next prd-slot-of-index prd-known-at
                            prd-seq-ok)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-STEPS done~%"))

; ---------------------------------------------------------------------------
; FROM THE RESET TO THE INVARIANT AT EVERY CYCLE.
; ---------------------------------------------------------------------------
; The producer signals are two-valued in every cycle from j up to but not
; including n.
(defund prod-env-from (j n envs outs)
  (declare (xargs :measure (nfix (- (nfix n) (nfix j))) :verify-guards nil))
  (if (zp (- (nfix n) (nfix j)))
      t
    (and (prod-env-at (nfix j) envs outs)
         (prod-env-from (+ 1 (nfix j)) n envs outs))))
(defthm prod-env-from-at
  (implies (and (prod-env-from j n envs outs) (natp j) (natp i) (natp n) (<= j i) (< i n))
           (prod-env-at i envs outs))
  :hints (("Goal" :induct (prod-env-from j n envs outs)
           :in-theory (e/d (prod-env-from) (prod-env-at))))
  :rule-classes nil)
(defthm prod-env-from-shorter
  (implies (and (natp j) (natp n) (<= j n)
                (prod-env-from j (+ 1 n) envs outs))
           (and (prod-env-from j n envs outs)
                (prod-env-at n envs outs)))
  :hints (("Goal"
           :induct (prod-env-from j n envs outs)
           :expand ((prod-env-from j (+ 1 n) envs outs)
                    (prod-env-from j n envs outs)
                    (prod-env-from n (+ 1 n) envs outs)
                    (prod-env-from (+ 1 n) (+ 1 n) envs outs))
           :in-theory (e/d (prod-env-from) (prod-env-at))))
  :rule-classes nil)
(defthm prd-join-env-from-at
  (implies (and (join-env-from j n envs outs) (natp j) (natp i) (natp n) (<= j i) (< i n))
           (join-env-at i envs outs))
  :hints (("Goal" :induct (join-env-from j n envs outs)
           :in-theory (e/d (join-env-from) (join-env-at))))
  :rule-classes nil)

; the working memories stay definite
(defthm prd-mem-next
  (implies (and (natp k) (prd-known-at k envs outs))
           (prod-mem-at (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-step))
           :in-theory (e/d (prd-p-key-memory-definite prd-p-value-memory-definite prod-mem-at)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(defthm prd-known-next
  (implies (and (natp k)
                (prd-known-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm))))
           (prd-known-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal" :use ((:instance prd-mem-next (outs (fsm-eval envs initst (probe-fsm))))
                        (:instance prod-step-glue (k (+ 1 k))))
           :in-theory (e/d (prd-known-at)
                           (prod-step-glue join-env-at prod-env-at prod-mem-at prod-facts-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(defun prd-ind (j i)
  (declare (xargs :measure (nfix (- (nfix i) (nfix j)))))
  (if (zp (- (nfix i) (nfix j)))
      nil
    (prd-ind j (- (nfix i) 1))))
(defthm prd-known-from
  (implies (and (natp j) (natp i) (<= j i)
                (prod-mem-at j (fsm-eval envs initst (probe-fsm)))
                (join-env-from j (+ 1 i) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from j (+ 1 i) envs (fsm-eval envs initst (probe-fsm))))
           (prd-known-at i envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal" :induct (prd-ind j i)
           :in-theory (disable prd-known-at join-env-at prod-env-at prod-mem-at prod-facts-at
                               join-env-from prod-env-from prod-step-glue
                               fsm-eval (probe-fsm) probe-fsm))
          ("Subgoal *1/2"
           :use ((:instance prd-known-next (k (+ -1 i)))
                 (:instance prd-join-env-from-at (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-at (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-join-env-from-at (n (+ 1 i)) (i (+ -1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-at (n (+ 1 i)) (i (+ -1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-shorter (n i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-shorter (n i) (outs (fsm-eval envs initst (probe-fsm))))))
          ("Subgoal *1/1"
           :use ((:instance prod-step-glue (k i))
                 (:instance prd-join-env-from-at (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-at (n (+ 1 i)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (prd-known-at)
                           (join-env-at prod-env-at prod-mem-at prod-facts-at
                            join-env-from prod-env-from prod-step-glue
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-KNOWN done~%"))

; no fault is registered in a cycle in which the environment behaves
(defthm prd-layerfail-zero
  (implies (join-env-at k envs outs)
           (equal (prd-o-layerfail-at k outs) 0))
  :hints (("Goal" :in-theory (e/d (join-env-at join-env-raw joint-env-p
                                   prd-o-layerfail-at prd$o-layerfail)
                                  (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(defthm prd-nofault
  (implies (and (natp k) (prd-known-at k envs outs))
           (prd-nofault-at k outs))
  :hints (("Goal" :use ((:instance prd-step) (:instance prd-sizes) (:instance prd-layerfail-zero))
           :in-theory (e/d (prd-known-at prd-p-layerfail prd-nofault-at)
                           (nth nthcdr take len))))
  :rule-classes nil)
; one cycle of the state invariant
(defthm prd-sinv-next
  (implies (and (natp k) (prd-known-at k envs outs)
                (prd-nofault-at k outs) (prd-nofault-at (+ 1 k) outs)
                (prd-sinv-at k outs))
           (prd-sinv-at (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-step))
           :in-theory (e/d (prd-p-sinv prd-p-reset prd-sinv-at prd-nofault-at)
                           (prod-sinv unsigned-byte-p nth nthcdr take len logbitp))))
  :rule-classes nil)
; one cycle of the invariant, clause by clause
(defthm prd-inv-next-krun
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs)
                (equal (prd-d-eng-at (+ 1 k) outs) 3) (equal (prd-d-cst-at (+ 1 k) outs) 5))
           (prd-krun-ok (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-krun-stay) (:instance prd-krun-enter))
           :in-theory (e/d (prd-inv) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-inv-next-kdone
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs)
                (equal (prd-d-est-at (+ 1 k) outs) 6))
           (prd-kdone-ok (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-kdone-stay) (:instance prd-kdone-enter))
           :in-theory (e/d (prd-inv) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-inv-next-vrun
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs)
                (equal (prd-d-eng-at (+ 1 k) outs) 2) (equal (prd-d-cst-at (+ 1 k) outs) 3))
           (prd-vrun-ok (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-vrun-stay) (:instance prd-vrun-enter))
           :in-theory (e/d (prd-inv) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-inv-next-vdone
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs)
                (<= 4 (prd-d-est-at (+ 1 k) outs)) (<= (prd-d-est-at (+ 1 k) outs) 6))
           (prd-vdone-ok (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-vdone-stay) (:instance prd-vdone-enter))
           :in-theory (e/d (prd-inv) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-inv-next-read
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs)
                (equal (prd-d-eng-at (+ 1 k) outs) 4) (equal (prd-d-kvrv-at (+ 1 k) outs) 1))
           (prd-read-ok (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-read-step))
           :in-theory (e/d (prd-inv) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-inv-next-kv
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs)
                (equal (prd-d-eng-at (+ 1 k) outs) 4))
           (prd-kv-ok (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-kv-step))
           :in-theory (e/d (prd-inv) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-inv-next-seq
  (implies (and (natp k) (prd-known-at k envs outs) (prd-guard-at k outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs)
                (not (equal (prd-s-state-at (+ 1 k) outs) 0)))
           (prd-seq-ok (+ 1 k) outs))
  :hints (("Goal" :use ((:instance prd-seq-step))
           :in-theory (e/d (prd-inv) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-inv-next
  (implies (and (natp k) (prd-known-at k envs outs)
                (prd-nofault-at k outs) (prd-nofault-at (+ 1 k) outs)
                (prd-sinv-at k outs) (prd-sinv-at (+ 1 k) outs)
                (prd-inv k outs))
           (prd-inv (+ 1 k) outs))
  :hints (("Goal" :cases ((prd-normal-at k outs)))
          ("Subgoal 2"
           :use ((:instance prd-step))
           :expand ((prd-inv (+ 1 k) outs))
           :in-theory (e/d (prd-p-reset prd-normal-at)
                           (prd-inv prod-sinv unsigned-byte-p nth nthcdr take len logbitp)))
          ("Subgoal 1"
           :use ((:instance prd-inv-next-krun)
                 (:instance prd-inv-next-kdone)
                 (:instance prd-inv-next-vrun)
                 (:instance prd-inv-next-vdone)
                 (:instance prd-inv-next-read)
                 (:instance prd-inv-next-kv)
                 (:instance prd-inv-next-seq))
           :expand ((prd-inv (+ 1 k) outs))
           :in-theory (e/d (prd-guard-at)
                           (prd-inv prd-sinv-at prd-nofault-at prd-normal-at prd-known-at))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-NEXT done~%"))

; after three reset cycles the machine core is not released
(defthm prd-release-after-reset
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm))))
           (equal (prd-m-rel-at (+ 2 r) (fsm-eval envs initst (probe-fsm))) 0))
  :hints (("Goal"
           :use ((:instance join-reset-fsm-thm
                  (base-cycle r) (base-cycle+2 (+ 2 r))))
           :in-theory (e/d (join-reset-at join-reset-raw joint-reset-p
                            prd-m-rel-at prd$r-m-rel)
                           (join-reset-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(defthm prd-base
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prd-known-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm))))
           (and (prd-sinv-at (+ 3 r) (fsm-eval envs initst (probe-fsm)))
                (prd-inv (+ 3 r) (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal"
           :use ((:instance prd-step (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-release-after-reset))
           :expand ((prd-inv (+ 3 r) (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (prd-p-inactive prd-p-reset prd-sinv-at)
                           (prod-sinv unsigned-byte-p nth nthcdr take len logbitp
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-BASE done~%"))
(defun prd-ind3 (r i)
  (declare (xargs :measure (nfix (- (nfix i) (+ 3 (nfix r))))))
  (if (zp (- (nfix i) (+ 3 (nfix r))))
      nil
    (prd-ind3 r (- (nfix i) 1))))
; EVERY CYCLE AFTER THE RESET: what is known of the cycle, no fault, the
; state invariant and the invariant.
(defthm prd-all-from-reset
  (implies (and (natp r) (natp i) (<= (+ 3 r) i)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at (+ 2 r) (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) (+ 1 i) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from (+ 2 r) (+ 1 i) envs (fsm-eval envs initst (probe-fsm))))
           (and (prd-known-at i envs (fsm-eval envs initst (probe-fsm)))
                (prd-nofault-at i (fsm-eval envs initst (probe-fsm)))
                (prd-sinv-at i (fsm-eval envs initst (probe-fsm)))
                (prd-inv i (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal" :induct (prd-ind3 r i)
           :in-theory (disable prd-known-at prd-nofault-at prd-sinv-at prd-inv
                               join-reset-at prod-mem-at join-env-from prod-env-from
                               fsm-eval (probe-fsm) probe-fsm))
          ("Subgoal *1/2"
           :use ((:instance prd-known-from (j (+ 2 r)))
                 (:instance prd-known-from (j (+ 2 r)) (i (+ -1 i)))
                 (:instance prd-nofault (k i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-nofault (k (+ -1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-sinv-next (k (+ -1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-inv-next (k (+ -1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-shorter (j (+ 2 r)) (n i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-shorter (j (+ 2 r)) (n i) (outs (fsm-eval envs initst (probe-fsm))))))
          ("Subgoal *1/1"
           :use ((:instance prd-known-from (j (+ 2 r)))
                 (:instance prd-known-from (j (+ 2 r)) (i (+ 2 r)))
                 (:instance prd-nofault (k i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-base)
                 (:instance join-env-from-shorter (j (+ 2 r)) (n (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-shorter (j (+ 2 r)) (n (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-shorter (j (+ 2 r)) (n (+ 3 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-shorter (j (+ 2 r)) (n (+ 3 r)) (outs (fsm-eval envs initst (probe-fsm)))))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-ALL done~%"))

; ---------------------------------------------------------------------------
; THE SAME SIGNALS IN THE FIRST LINK AND HERE.
; ---------------------------------------------------------------------------
(defthm prd-bridge
  (and (equal (pay$h-sbegin k k envs outs) (prd-o-sbv-at k outs))
       (equal (pay$h-spayload k k envs outs) (prd-o-spv-at k outs))
       (equal (pay$h-index k k envs outs) (prd-d-iidx-at k outs))
       (equal (pay$h-key k k envs outs) (prd-d-krd-at k outs))
       (equal (pay$h-value k k envs outs) (prd-d-vrd-at k outs))
       (equal (stg-layer-at k outs) (prd-d-clay-at k outs))
       (equal (stg-position-at k outs) (prd-d-cpos-at k outs))
       (equal (stg-kexp-at k outs) (prd-d-kexp-at k outs))
       (equal (stg-vexp-at k outs) (prd-d-vexp-at k outs))
       (equal (rec-clear-at k envs) (prd-i-clear-at k envs)))
  :hints (("Goal"
           :in-theory (e/d (pay$h-sbegin pay$h-spayload pay$h-index pay$h-key pay$h-value
                            pay$h-layer pay$h-position pay$h-kexp pay$h-vexp pay$i-clear
                            stg-layer-at stg-position-at stg-kexp-at stg-vexp-at rec-clear-at
                            prd-o-sbv-at prd-o-spv-at prd-d-iidx-at prd-d-krd-at prd-d-vrd-at
                            prd-d-clay-at prd-d-cpos-at prd-d-kexp-at prd-d-vexp-at prd-i-clear-at
                            prd$o-sbv prd$o-spv prd$r-d-iidx prd$r-d-krd prd$r-d-vrd
                            prd$r-d-clay prd$r-d-cpos prd$r-d-kexp prd$r-d-vexp prd$i-clear)
                           (nth nthcdr take len))))
  :rule-classes nil)
; The joined invariant, about plain values: while the controller is not idle
; the machine core is released.
(make-event
 (b* ((formals (acl2::formals 'joint-inv-p (w state)))
      (formals2 (acl2::formals 'joint-2valued-p (w state))))
   `(fgl::def-fgl-thm prd-inv-active-of-values
      (implies (and (joint-2valued-p ,@formals2) (joint-inv-p ,@formals))
               (or (equal m-rel 3) (equal k-state-q 0))))))
(defun prd-inst-pairs (formals actuals bindings)
  (declare (xargs :mode :program))
  (if (atom formals) nil
    (cons (list (car formals)
                `(let ((base-cycle k) (base-cycle+1 k))
                   (declare (ignorable base-cycle base-cycle+1))
                   ,(cadr (assoc-eq (car actuals) bindings))))
          (prd-inst-pairs (cdr formals) (cdr actuals) bindings))))
(make-event
 (b* ((ev (acl2::get-event 'join-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (imp (third body))
      (cconj (cdr (third (third imp))))
      (inv (if (eq (car (first cconj)) 'joint-inv-p) (first cconj) (second cconj)))
      (formals (acl2::formals 'joint-inv-p (w state)))
      (subst (prd-inst-pairs formals (cdr inv) bindings)))
   `(defthm prd-active-when-controller-busy
      (implies (and (join-j-at k envs outs)
                    (not (equal (pay-st-at k outs) 0)))
               (equal (prd-m-rel-at k outs) 3))
      :hints (("Goal"
               :use ((:instance prd-inv-active-of-values ,@subst))
               :in-theory (e/d (join-j-at join-inv-raw pay-st-at pay-st-raw
                                prd-m-rel-at prd$r-m-rel)
                               (joint-inv-p joint-2valued-p unsigned-byte-p nth nthcdr take len))))
      :rule-classes nil)))

; reset_n_i is high in the cycle after one in which the environment behaves
(defthm prd-reset-high
  (implies (join-env-at k envs outs)
           (equal (prd-i-reset-n-at (+ 1 k) envs) 1))
  :hints (("Goal"
           :in-theory (e/d (join-env-at join-env-raw prd-i-reset-n-at prd$i-reset-n)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
; An idle or staging controller does not report its record complete.
(defthm prd-hold
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (or (equal (pay-st-at k (fsm-eval envs initst (probe-fsm))) 0)
                    (equal (pay-st-at k (fsm-eval envs initst (probe-fsm))) 1)))
           (equal (prd-h-kpc-at k (fsm-eval envs initst (probe-fsm))) 0))
  :hints (("Goal"
           :use ((:instance hold-fsm-thm (base-cycle k))
                 (:instance kv-producer-hold-run-constraints))
           :in-theory (e/d (join-j-at join-inv-raw joint-2valued-p join-env-at join-env-raw joint-env-p
                            pay-st-at pay-st-raw prd-h-kpc-at prd$h-kpc
                            hold-all hold-fact-not-complete fgl::fgl-prove-fn)
                           (hold-fsm-thm unsigned-byte-p nth nthcdr take len
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-BRIDGE done~%"))

; ---------------------------------------------------------------------------
; THE PREMISES OF THIS LINK, by the RTL's own names.
; ---------------------------------------------------------------------------
; In cycle k each of these signals of the machine core, the sequencer and the
; datapath is two-valued.  The definition is built from the lifted lemma's
; own reading of each signal, so it names each by the name the translation
; resolved it to (a port wire appears as the wire it is connected to).  As
; named in the RTL, with widths ("..." is u_machine.u_six_layers.):
;   model_lock_core_sync_q                          1  register
;   u_machine.machine_release_q                     2  register
;   ...service_start_collision_q                    1  register
;   ...u_sequence.state_q                           3  register
;   ...u_sequence.layer_q                           3  register
;   ...u_sequence.stage_q                           5  register
;   ...u_sequence.position_q                       11  register
;   ...u_sequence.fault_q                           1  register
;   ...u_sequence.lock_seen_q                       1  register
;   ...u_sequence.stream_index_q                    8  register
;   ...u_sequence.result_exponent_q                 8  register
;   ...u_datapath.engine_state_q                    4  register
;   ...u_datapath.current_stage_q                   5  register
;   ...u_datapath.current_layer_q                   3  register
;   ...u_datapath.current_position_q               11  register
;   ...u_datapath.expected_stage_q                  5  register
;   ...u_datapath.expected_layer_q                  3  register
;   ...u_datapath.transaction_position_q           11  register
;   ...u_datapath.transaction_seen_q                1  register
;   ...u_datapath.fault_q                           1  register
;   ...u_datapath.lock_seen_q                       1  register
;   ...u_datapath.stage_done_q                      1  register
;   ...u_datapath.key_exponent_q                    8  register
;   ...u_datapath.value_exponent_q                  8  register
;   ...u_datapath.service_start_seen_q              1  register
;   ...u_datapath.output_done_q                     1  register
;   ...u_datapath.service_done_seen_q               1  register
;   ...u_datapath.norm_done_seen_q                  1  register
;   ...u_datapath.input_index_q                    10  register
;   ...u_datapath.input_done_q                      1  register
;   ...u_datapath.output_index_q                   10  register
;   ...u_datapath.rope_phase_q                      4  register
;   ...u_datapath.rope_head_q                       2  register
;   ...u_datapath.rope_half_q                       5  register
;   ...u_datapath.rope_second_index_q               5  register
;   ...u_datapath.attention_result_head_q           3  register
;   ...u_datapath.attention_store_lane_q            6  register
;   ...u_datapath.silu_value_valid_q                1  register
;   ...u_datapath.gate_exponent_q                   8  register
;   ...u_datapath.kv_read_valid_q                   1  register
;   ...u_datapath.elem_phase_q                      3  register
;   ...u_datapath.key_ram_read_data                16  register
;   ...u_datapath.value_ram_read_data              16  register
;   u_machine.root_terminal                         1  wire
;   ...u_datapath.child_fault                       1  wire
;   ...u_datapath.norm_result_valid                 1  wire
;   ...u_datapath.norm_result_index                10  wire
;   ...u_datapath.norm_result_mantissa             16  wire
;   ...u_datapath.norm_result_exponent              8  wire
;   ...u_datapath.norm_result_last                  1  wire
;   ...u_datapath.norm_done_valid                   1  wire
;   ...u_datapath.projection_done_valid             1  wire
;   ...u_datapath.rms_result_valid                  1  wire
;   ...u_datapath.rms_result_index                  8  wire
;   ...u_datapath.rms_result_last                   1  wire
;   ...u_datapath.rms_done_valid                    1  wire
;   ...u_datapath.head_done_fire                    1  wire
;   ...u_datapath.lookup_response_valid             1  wire
;   ...u_datapath.lookup_response_fault             1  wire
;   ...u_datapath.attention_result_valid            1  wire
;   ...u_datapath.attention_result_last             1  wire
;   ...u_datapath.attention_done_valid              1  wire
;   ...u_datapath.lane_lut_request                  1  wire
;   ...u_datapath.lane_lut_index                   16  wire
;   ...u_datapath.gate_read_data                   16  wire
;   ...u_datapath.kv_commit_ready                   1  wire
;   ...u_datapath.kv_stage_begin_ready              1  wire
;   ...u_datapath.kv_stage_payload_ready            1  wire
;   ...u_datapath.kv_pending_complete               1  wire
;   ...u_datapath.private_head_start_ready_o        1  wire
;   ...u_datapath.rms_input_fire                    1  wire
;   ...u_datapath.projection_activation_fire        1  wire
;   ...u_datapath.head_activation_fire              1  wire
;   ...private_head_start_valid_i                   1  wire
;   ...start_valid_i                                1  wire
;   ...datapath_busy                                1  wire
;   ...u_sequence.input_fire                        1  wire
;   ...u_sequence.input_legal                       1  wire
;   ...u_sequence.prefixes_match                    1  wire
;   ...u_sequence.input_exponent_i                  8  wire
;   ...u_sequence.fixed_position_i                 11  wire
;   ...u_sequence.done_fire                         1  wire
;   ...u_sequence.result_fire                       1  wire
;   ...u_sequence.private_result_exponent_i         8  wire
;   ...u_sequence.private_result_mantissa_i        16  wire
(defun prd-ubp-conjuncts (pairs bindings)
  (declare (xargs :mode :program))
  (if (atom pairs) nil
    (cons `(unsigned-byte-p ,(cdr (car pairs)) ,(cadr (assoc-eq (car (car pairs)) bindings)))
          (prd-ubp-conjuncts (cdr pairs) bindings))))
(make-event
 (b* ((ev (acl2::get-event 'prod-step-fsm-thm (w state)))
      (bindings (cddr (second (third ev)))))
   `(define kv-producer-signals-ok-at (k envs outs)
      :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
      (let ((base-cycle k))
        (declare (ignorable base-cycle))
        (and ,@(prd-ubp-conjuncts '((r-p-lock-sync . 1) (r-m-rel . 2) (r-l-coll . 1) (r-s-state . 3) (r-s-layer . 3) (r-s-stage . 5) (r-s-pos . 11) (r-s-fault . 1) (r-s-lseen . 1) (r-s-sidx . 8) (r-s-rexp . 8) (r-d-eng . 4) (r-d-cst . 5) (r-d-clay . 3) (r-d-cpos . 11) (r-d-est . 5) (r-d-elay . 3) (r-d-tpos . 11) (r-d-tseen . 1) (r-d-fault . 1) (r-d-lseen . 1) (r-d-sdone . 1) (r-d-kexp . 8) (r-d-vexp . 8) (r-d-sss . 1) (r-d-odone . 1) (r-d-sds . 1) (r-d-nds . 1) (r-d-iidx . 10) (r-d-idone . 1) (r-d-oidx . 10) (r-d-rphase . 4) (r-d-rhead . 2) (r-d-rhalf . 5) (r-d-rsecond . 5) (r-d-arhead . 3) (r-d-aslane . 6) (r-d-svv . 1) (r-d-gexp . 8) (r-d-kvrv . 1) (r-d-ephase . 3) (r-d-krd . 16) (r-d-vrd . 16) (h-rterm . 1) (h-childfault . 1) (h-nrv . 1) (h-nri . 10) (h-nrm . 16) (h-nre . 8) (h-nrl . 1) (h-ndv . 1) (h-pdv . 1) (h-rrv . 1) (h-rri . 8) (h-rrl . 1) (h-rdv . 1) (h-hdf . 1) (h-lrv . 1) (h-lrf . 1) (h-arv . 1) (h-arl . 1) (h-adv . 1) (h-llr . 1) (h-lli . 16) (h-grd . 16) (h-kcr . 1) (h-sbr . 1) (h-spr . 1) (h-kpc . 1) (h-hsr . 1) (h-rif . 1) (h-paf . 1) (h-haf . 1) (h-hsv . 1) (h-lsv . 1) (h-dbusy . 1) (h-sif . 1) (h-sil . 1) (h-spm . 1) (h-siexp . 8) (h-sfpos . 11) (h-sdf . 1) (h-srf . 1) (h-srexp . 8) (h-srman . 16)) bindings))))))
; ... in every cycle from j up to but not including n.
(define kv-producer-signals-ok-from (j n envs outs)
  :verify-guards nil
  :measure (nfix (- (nfix n) (nfix j)))
  (if (zp (- (nfix n) (nfix j)))
      t
    (and (kv-producer-signals-ok-at (nfix j) envs outs)
         (kv-producer-signals-ok-from (+ 1 (nfix j)) n envs outs))))
; In cycle k the datapath's key and value working memories (u_key_state and
; u_value_state, 128 cells of 16 bits each) hold definite values.
(define kv-producer-storage-definite-at (k outs)
  :verify-guards nil
  (b* ((now (nth k outs))
       (key-memory (sig "u_machine.u_six_layers.u_datapath.u_key_state.payload_mem" 2048 now))
       (value-memory (sig "u_machine.u_six_layers.u_datapath.u_value_state.payload_mem" 2048 now)))
    (and (unsigned-byte-p 2048 key-memory)
         (unsigned-byte-p 2048 value-memory))))
(defthm prd-signals-connect
  (implies (kv-producer-signals-ok-at k envs outs)
           (prod-env-at k envs outs))
  :hints (("Goal"
           :in-theory (e/d (kv-producer-signals-ok-at prod-env-at
                            prd$r-p-lock-sync prd$r-m-rel prd$r-l-coll prd$r-s-state prd$r-s-layer prd$r-s-stage prd$r-s-pos prd$r-s-fault prd$r-s-lseen prd$r-s-sidx prd$r-s-rexp prd$r-d-eng prd$r-d-cst prd$r-d-clay prd$r-d-cpos prd$r-d-est prd$r-d-elay prd$r-d-tpos prd$r-d-tseen prd$r-d-fault prd$r-d-lseen prd$r-d-sdone prd$r-d-kexp prd$r-d-vexp prd$r-d-sss prd$r-d-odone prd$r-d-sds prd$r-d-nds prd$r-d-iidx prd$r-d-idone prd$r-d-oidx prd$r-d-rphase prd$r-d-rhead prd$r-d-rhalf prd$r-d-rsecond prd$r-d-arhead prd$r-d-aslane prd$r-d-svv prd$r-d-gexp prd$r-d-kvrv prd$r-d-ephase prd$r-d-kmem prd$r-d-vmem prd$r-d-krd prd$r-d-vrd prd$h-rterm prd$h-childfault prd$h-nrv prd$h-nri prd$h-nrm prd$h-nre prd$h-nrl prd$h-ndv prd$h-pdv prd$h-rrv prd$h-rri prd$h-rrl prd$h-rdv prd$h-hdf prd$h-lrv prd$h-lrf prd$h-arv prd$h-arl prd$h-adv prd$h-llr prd$h-lli prd$h-grd prd$h-kcr prd$h-sbr prd$h-spr prd$h-kpc prd$h-hsr prd$h-rif prd$h-paf prd$h-haf prd$h-hsv prd$h-lsv prd$h-dbusy prd$h-sif prd$h-sil prd$h-spm prd$h-siexp prd$h-sfpos prd$h-sdf prd$h-srf prd$h-srexp prd$h-srman prd-d-arhead-at prd-d-aslane-at prd-d-clay-at prd-d-cpos-at prd-d-cst-at prd-d-elay-at prd-d-eng-at prd-d-ephase-at prd-d-est-at prd-d-fault-at prd-d-gexp-at prd-d-idone-at prd-d-iidx-at prd-d-kexp-at prd-d-kmem-at prd-d-krd-at prd-d-kvrv-at prd-d-lseen-at prd-d-nds-at prd-d-odone-at prd-d-oidx-at prd-d-rhalf-at prd-d-rhead-at prd-d-rphase-at prd-d-rsecond-at prd-d-sdone-at prd-d-sds-at prd-d-sss-at prd-d-svv-at prd-d-tpos-at prd-d-tseen-at prd-d-vexp-at prd-d-vmem-at prd-d-vrd-at prd-h-adv-at prd-h-arl-at prd-h-arv-at prd-h-childfault-at prd-h-dbusy-at prd-h-grd-at prd-h-haf-at prd-h-hdf-at prd-h-hsr-at prd-h-hsv-at prd-h-kcr-at prd-h-kpc-at prd-h-lli-at prd-h-llr-at prd-h-lrf-at prd-h-lrv-at prd-h-lsv-at prd-h-ndv-at prd-h-nre-at prd-h-nri-at prd-h-nrl-at prd-h-nrm-at prd-h-nrv-at prd-h-paf-at prd-h-pdv-at prd-h-rdv-at prd-h-rif-at prd-h-rri-at prd-h-rrl-at prd-h-rrv-at prd-h-rterm-at prd-h-sbr-at prd-h-sdf-at prd-h-sfpos-at prd-h-siexp-at prd-h-sif-at prd-h-sil-at prd-h-spm-at prd-h-spr-at prd-h-srexp-at prd-h-srf-at prd-h-srman-at prd-l-coll-at prd-m-rel-at prd-p-lock-sync-at prd-s-fault-at prd-s-layer-at prd-s-lseen-at prd-s-pos-at prd-s-rexp-at prd-s-sidx-at prd-s-stage-at prd-s-state-at)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(defthm prd-signals-from-connect
  (implies (kv-producer-signals-ok-from j n envs outs)
           (prod-env-from j n envs outs))
  :hints (("Goal"
           :induct (kv-producer-signals-ok-from j n envs outs)
           :in-theory (e/d (kv-producer-signals-ok-from prod-env-from)
                           (kv-producer-signals-ok-at prod-env-at)))
          ("Subgoal *1/2" :use ((:instance prd-signals-connect (k (nfix j))))))
  :rule-classes nil)
(defthm prd-storage-connects
  (implies (kv-producer-storage-definite-at k outs)
           (prod-mem-at k outs))
  :hints (("Goal"
           :in-theory (e/d (kv-producer-storage-definite-at prod-mem-at
                            prd-d-kmem-at prd-d-vmem-at prd$r-d-kmem prd$r-d-vmem)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-PREMISES done~%"))

; ---------------------------------------------------------------------------
; FROM THE BEGIN TO THE LAST TRANSFER NOTHING THE RESULTS DEPEND ON MOVES.
; ---------------------------------------------------------------------------
(defthm prd-ev-children-reset
  (implies (and (natp k) (prd-known-at k envs outs))
           (equal (prd-o-dprst-at k outs) (if (and (equal (prd-i-reset-n-at k envs) 1) (logbitp 1 (prd-m-rel-at k outs))) 1 0)))
  :hints (("Goal" :use ((:instance prd-step))
           :in-theory (e/d (prd-p-children-reset) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-ev-release
  (implies (and (natp k) (prd-known-at k envs outs)
                (equal (prd-m-rel-at k outs) 0))
           (not (equal (prd-m-rel-at (+ 1 k) outs) 3)))
  :hints (("Goal" :use ((:instance prd-step))
           :in-theory (e/d (prd-p-release) (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
; staging cycles: the controller is staging and the cycle before had no CLEAR
(defthm prd-stg-quiet-at
  (implies (and (stg-quiet b m envs outs) (natp b) (natp k) (natp m) (< b k) (<= k m))
           (and (equal (pay-st-at k outs) 1)
                (equal (rec-clear-at (+ -1 k) envs) 0)))
  :hints (("Goal" :induct (stg-quiet b m envs outs)
           :in-theory (e/d (stg-quiet) (pay-st-at rec-clear-at stg-begin-at))))
  :rule-classes nil)
(defthm prd-stg-quiet-empty
  (implies (<= (nfix m) (nfix b))
           (stg-quiet b m envs outs))
  :hints (("Goal" :expand ((stg-quiet b m envs outs)))))
; One cycle with stage 6 expected, a controller that is idle or staging, and
; no CLEAR: stage 6 stays expected and neither list of results changes.
(defthm prd-frozen-step
  (implies (and (natp k) (<= 1 k)
                (prd-known-at k envs (fsm-eval envs initst (probe-fsm))) (prd-known-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm)))
                (prd-nofault-at k (fsm-eval envs initst (probe-fsm))) (prd-nofault-at (+ 1 k) (fsm-eval envs initst (probe-fsm)))
                (prd-sinv-at k (fsm-eval envs initst (probe-fsm)))
                (join-j-at k envs (fsm-eval envs initst (probe-fsm))) (join-j-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm))) (join-env-at (+ -1 k) envs (fsm-eval envs initst (probe-fsm)))
                (logbitp 1 (prd-m-rel-at k (fsm-eval envs initst (probe-fsm))))
                (equal (prd-d-est-at k (fsm-eval envs initst (probe-fsm))) 6)
                (or (equal (pay-st-at k (fsm-eval envs initst (probe-fsm))) 0) (equal (pay-st-at k (fsm-eval envs initst (probe-fsm))) 1))
                (equal (pay-st-at (+ 1 k) (fsm-eval envs initst (probe-fsm))) 1)
                (equal (rec-clear-at k envs) 0))
           (and (equal (prd-d-est-at (+ 1 k) (fsm-eval envs initst (probe-fsm))) 6)
                (equal (prd-klog (+ 1 k) (fsm-eval envs initst (probe-fsm))) (prd-klog k (fsm-eval envs initst (probe-fsm))))
                (equal (prd-vlog (+ 1 k) (fsm-eval envs initst (probe-fsm))) (prd-vlog k (fsm-eval envs initst (probe-fsm))))
                (logbitp 1 (prd-m-rel-at (+ 1 k) (fsm-eval envs initst (probe-fsm))))))
  :hints (("Goal"
           :use ((:instance prd-ev-children-reset (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-reset-high (k (+ -1 k)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-active-when-controller-busy (k (+ 1 k)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-bridge (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-hold)
                 (:instance prd-ev-public-clear (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-staging-stage (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-key-frozen (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-value-frozen (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (prd-guard-at prd-normal-at prd-accept-at prd-key-result-at prd-value-result-at)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs prd-known-at prd-nofault-at prd-sinv-at join-j-at join-env-at
                            pay-st-at rec-clear-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-FROZEN-STEP done~%"))

; ---------------------------------------------------------------------------
; EVERYTHING KNOWN OF A CYCLE AFTER THE RESET, and of a range of cycles.
; ---------------------------------------------------------------------------
(defund prd-cycle-ok (i envs outs)
  (declare (xargs :verify-guards nil))
  (and (prd-known-at i envs outs) (prd-nofault-at i outs) (prd-sinv-at i outs) (prd-inv i outs)
       (join-j-at i envs outs) (join-env-at i envs outs)
       (join-env-at (+ -1 i) envs outs) (prd-known-at (+ -1 i) envs outs)))
(defthm prod-env-from-prefix
  (implies (and (natp j) (natp m) (natp n) (<= j m) (<= m n)
                (prod-env-from j n envs outs))
           (prod-env-from j m envs outs))
  :hints (("Goal"
           :induct (prod-env-from j n envs outs)
           :in-theory (e/d (prod-env-from) (prod-env-at))))
  :rule-classes nil)
(defthm prd-cycle-ok-from-reset
  (implies (and (natp r) (natp i) (natp m) (<= (+ 3 r) i) (<= i m)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at (+ 2 r) (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) (+ 1 m) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from (+ 2 r) (+ 1 m) envs (fsm-eval envs initst (probe-fsm))))
           (prd-cycle-ok i envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance join-env-from-prefix (j (+ 2 r)) (m (+ 1 i)) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m (+ 1 i)) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m i) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m i) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-all-from-reset)
                 (:instance join-inv-from-reset (n i))
                 (:instance prd-join-env-from-at (j (+ 2 r)) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-join-env-from-at (j (+ 2 r)) (n (+ 1 m)) (i (+ -1 i)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-known-from (j (+ 2 r)) (i (+ -1 i))))
           :in-theory (e/d (prd-cycle-ok)
                           (join-inv-from-reset prd-known-at prd-nofault-at prd-sinv-at prd-inv
                            join-j-at join-env-at join-reset-at prod-mem-at join-env-from prod-env-from
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(defthm prd-cycle-ok-parts
  (implies (prd-cycle-ok i envs outs)
           (and (prd-known-at i envs outs) (prd-nofault-at i outs) (prd-sinv-at i outs) (prd-inv i outs)
                (join-j-at i envs outs) (join-env-at i envs outs)
                (join-env-at (+ -1 i) envs outs) (prd-known-at (+ -1 i) envs outs)))
  :hints (("Goal" :in-theory (enable prd-cycle-ok)))
  :rule-classes nil)
; cycles b .. m
(defund prd-ok-range (b m envs outs)
  (declare (xargs :measure (nfix (- (nfix m) (nfix b))) :verify-guards nil))
  (and (prd-cycle-ok (nfix m) envs outs)
       (or (zp (- (nfix m) (nfix b)))
           (prd-ok-range b (- (nfix m) 1) envs outs))))
(defthm prd-ok-range-at
  (implies (and (prd-ok-range b m envs outs) (natp b) (natp i) (natp m) (<= b i) (<= i m))
           (prd-cycle-ok i envs outs))
  :hints (("Goal" :induct (prd-ok-range b m envs outs)
           :in-theory (e/d (prd-ok-range) (prd-cycle-ok))))
  :rule-classes nil)
(defthm prd-ok-range-from-reset
  (implies (and (natp r) (natp b) (natp m) (<= (+ 3 r) b) (<= b m)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at (+ 2 r) (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) (+ 1 m) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from (+ 2 r) (+ 1 m) envs (fsm-eval envs initst (probe-fsm))))
           (prd-ok-range b m envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal" :induct (prd-ind b m)
           :in-theory (disable prd-cycle-ok join-reset-at prod-mem-at join-env-from prod-env-from
                               fsm-eval (probe-fsm) probe-fsm))
          ("Subgoal *1/2"
           :use ((:instance prd-cycle-ok-from-reset (i m))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m m) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m m) (n (+ 1 m)) (outs (fsm-eval envs initst (probe-fsm)))))
           :expand ((prd-ok-range b m envs (fsm-eval envs initst (probe-fsm)))))
          ("Subgoal *1/1"
           :use ((:instance prd-cycle-ok-from-reset (i m)))
           :expand ((prd-ok-range b m envs (fsm-eval envs initst (probe-fsm))))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-RANGE done~%"))

; ---------------------------------------------------------------------------
; FROM THE BEGIN THROUGH THE STAGING: stage 6 stays expected and the two
; lists of results are the lists as of the begin.
; ---------------------------------------------------------------------------
(defthm prd-ok-range-shorter
  (implies (and (prd-ok-range b m envs outs) (natp b) (natp m) (< b m))
           (prd-ok-range b (+ -1 m) envs outs))
  :hints (("Goal" :expand ((prd-ok-range b m envs outs))
           :in-theory (disable prd-cycle-ok)))
  :rule-classes nil)
(defthm prd-stg-quiet-shorter
  (implies (and (stg-quiet b m envs outs) (natp b) (natp m) (< b m))
           (stg-quiet b (+ -1 m) envs outs))
  :hints (("Goal" :expand ((stg-quiet b m envs outs))
           :in-theory (disable pay-st-at rec-clear-at stg-begin-at)))
  :rule-classes nil)
; at the begin
(defthm prd-frozen-base
  (implies (and (natp b) (<= 1 b)
                (prd-ok-range b b envs (fsm-eval envs initst (probe-fsm)))
                (equal (prd-d-eng-at b (fsm-eval envs initst (probe-fsm))) 4))
           (and (equal (prd-d-est-at b (fsm-eval envs initst (probe-fsm))) 6)
                (logbitp 1 (prd-m-rel-at b (fsm-eval envs initst (probe-fsm))))))
  :hints (("Goal"
           :use ((:instance prd-ok-range-at (m b) (i b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-cycle-ok-parts (i b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-reset (k (+ -1 b)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-busy (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-engine-of-stage (cst (prd-d-cst-at b (fsm-eval envs initst (probe-fsm))))))
           :in-theory (e/d (prd-normal-at)
                           (prd-cycle-ok prd-ok-range logbitp prd-known-at prd-nofault-at prd-sinv-at
                            prd-inv join-j-at join-env-at prod-engine-of
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
; one more cycle
(defthm prd-frozen-one-more
  (implies (and (natp b) (natp m) (<= 1 b) (< b m)
                (prd-ok-range b m envs (fsm-eval envs initst (probe-fsm)))
                (stg-quiet b m envs (fsm-eval envs initst (probe-fsm)))
                (equal (pay-st-at b (fsm-eval envs initst (probe-fsm))) 0)
                (equal (prd-d-est-at (+ -1 m) (fsm-eval envs initst (probe-fsm))) 6)
                (logbitp 1 (prd-m-rel-at (+ -1 m) (fsm-eval envs initst (probe-fsm)))))
           (and (equal (prd-d-est-at m (fsm-eval envs initst (probe-fsm))) 6)
                (equal (prd-klog m (fsm-eval envs initst (probe-fsm))) (prd-klog (+ -1 m) (fsm-eval envs initst (probe-fsm))))
                (equal (prd-vlog m (fsm-eval envs initst (probe-fsm))) (prd-vlog (+ -1 m) (fsm-eval envs initst (probe-fsm))))
                (logbitp 1 (prd-m-rel-at m (fsm-eval envs initst (probe-fsm))))))
  :hints (("Goal"
           :cases ((equal m (+ 1 b)))
           :use ((:instance prd-frozen-step (k (+ -1 m)))
                 (:instance prd-ok-range-at (i m) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ok-range-at (i (+ -1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-cycle-ok-parts (i m) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-cycle-ok-parts (i (+ -1 m)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-stg-quiet-at (k m) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-stg-quiet-at (k (+ -1 m)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (disable prd-cycle-ok prd-ok-range stg-quiet pay-st-at rec-clear-at logbitp
                               prd-klog prd-vlog prd-known-at prd-nofault-at prd-sinv-at prd-inv
                               prd-klog-next prd-vlog-next prd-stg-quiet-empty
                               join-j-at join-env-at stg-begin-at fsm-eval (probe-fsm) probe-fsm
                               (tau-system))))
  :rule-classes nil)
(defthm prd-frozen-from-begin
  (implies (and (natp b) (natp m) (<= 1 b) (<= b m)
                (prd-ok-range b m envs (fsm-eval envs initst (probe-fsm)))
                (equal (prd-d-eng-at b (fsm-eval envs initst (probe-fsm))) 4)
                (equal (pay-st-at b (fsm-eval envs initst (probe-fsm))) 0)
                (stg-quiet b m envs (fsm-eval envs initst (probe-fsm))))
           (and (equal (prd-d-est-at m (fsm-eval envs initst (probe-fsm))) 6)
                (equal (prd-klog m (fsm-eval envs initst (probe-fsm))) (prd-klog b (fsm-eval envs initst (probe-fsm))))
                (equal (prd-vlog m (fsm-eval envs initst (probe-fsm))) (prd-vlog b (fsm-eval envs initst (probe-fsm))))
                (logbitp 1 (prd-m-rel-at m (fsm-eval envs initst (probe-fsm))))))
  :hints (("Goal" :induct (prd-ind b m)
           :in-theory (disable prd-cycle-ok prd-ok-range stg-quiet pay-st-at rec-clear-at logbitp
                               prd-klog prd-vlog prd-klog-next prd-vlog-next prd-stg-quiet-empty
                               fsm-eval (probe-fsm) probe-fsm (tau-system)))
          ("Subgoal *1/2"
           :use ((:instance prd-frozen-one-more)
                 (:instance prd-ok-range-shorter (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-stg-quiet-shorter (outs (fsm-eval envs initst (probe-fsm))))))
          ("Subgoal *1/1"
           :use ((:instance prd-frozen-base))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-FROZEN done~%"))

; ---------------------------------------------------------------------------
; EACH ACCEPTED TRANSFER CARRIES THE FINAL RESULTS FOR ITS COORDINATE.
; ---------------------------------------------------------------------------
; ---- the transfers the producer's results stand for
(defund kv-produced-transfers-from (c klog vlog)
  (declare (xargs :measure (nfix (- 128 (nfix c))) :verify-guards nil))
  (if (zp (- 128 (nfix c)))
      nil
    (cons (list (nfix c) (kv-final-result (nfix c) klog) (kv-final-result (nfix c) vlog))
          (kv-produced-transfers-from (+ 1 (nfix c)) klog vlog))))
(define kv-produced-transfers (klog vlog) :verify-guards nil
  (kv-produced-transfers-from 0 klog vlog))
; every transfer of a list carries the final results for its coordinate
(defund prd-entries-ok (log klog vlog)
  (declare (xargs :verify-guards nil))
  (or (atom log)
      (and (equal (car log)
                  (list (car (car log))
                        (kv-final-result (car (car log)) klog)
                        (kv-final-result (car (car log)) vlog)))
           (prd-entries-ok (cdr log) klog vlog))))
(defthm prd-entries-ok-of-append
  (equal (prd-entries-ok (append a b) klog vlog)
         (and (prd-entries-ok a klog vlog) (prd-entries-ok b klog vlog)))
  :hints (("Goal" :in-theory (enable prd-entries-ok))))
(defthm prd-entries-are-produced
  (implies (and (prd-entries-ok log klog vlog)
                (stg-coords-from c log)
                (natp c) (true-listp log)
                (equal (+ c (len log)) 128))
           (equal log (kv-produced-transfers-from c klog vlog)))
  :hints (("Goal" :induct (stg-coords-from c log)
           :in-theory (enable prd-entries-ok stg-coords-from kv-produced-transfers-from)))
  :rule-classes nil)

(fgl::def-fgl-thm prd-index-range
  (implies (unsigned-byte-p 10 x)
           (and (natp (loghead 7 x)) (< (loghead 7 x) 128))))
(in-theory (disable prd-index-range))
(defthm prd-transfer-is-produced
  (implies (and (natp k)
                (prd-cycle-ok k envs outs)
                (equal (prd-d-est-at k outs) 6)
                (equal (rec-beat-at k envs outs) 1))
           (equal (stg-transfer-at k envs outs)
                  (list (loghead 7 (prd-d-iidx-at k outs))
                        (kv-final-result (loghead 7 (prd-d-iidx-at k outs)) (prd-klog k outs))
                        (kv-final-result (loghead 7 (prd-d-iidx-at k outs)) (prd-vlog k outs)))))
  :hints (("Goal"
           :use ((:instance prd-bridge)
                 (:instance prd-ev-staging-valid)
                 (:instance prd-sizes)
                 (:instance prd-index-range (x (prd-d-iidx-at k outs)))
                 (:instance prd-covers-occurs (n 128) (c (loghead 7 (prd-d-iidx-at k outs))) (log (prd-klog k outs)))
                 (:instance prd-covers-occurs (n 128) (c (loghead 7 (prd-d-iidx-at k outs))) (log (prd-vlog k outs)))
                 (:instance prd-mem-ok-lookup (n 128) (c (loghead 7 (prd-d-iidx-at k outs))) (log (prd-klog k outs)) (mem (prd-d-kmem-at k outs)))
                 (:instance prd-mem-ok-lookup (n 128) (c (loghead 7 (prd-d-iidx-at k outs))) (log (prd-vlog k outs)) (mem (prd-d-vmem-at k outs)))
                 (:instance prd-slot-of-index (i (prd-d-iidx-at k outs)) (mem (prd-d-kmem-at k outs)))
                 (:instance prd-slot-of-index (i (prd-d-iidx-at k outs)) (mem (prd-d-vmem-at k outs))))
           :in-theory (e/d (prd-cycle-ok prd-inv prd-kdone-ok prd-vdone-ok prd-read-ok prd-known-at
                            rec-beat-at stg-transfer-at)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs))))
  :rule-classes nil)
(defthm prd-stg-log-is-a-list
  (true-listp (stg-log j k envs outs))
  :hints (("Goal" :in-theory (enable stg-log)))
  :rule-classes :type-prescription)
(defthm prd-stg-log-empty
  (implies (<= (nfix k) (nfix j))
           (equal (stg-log j k envs outs) nil))
  :hints (("Goal" :expand ((stg-log j k envs outs)))))
(defthm prd-log-one-more
  (implies (and (natp b) (natp m) (<= 1 b) (< b m)
                (prd-ok-range b m envs (fsm-eval envs initst (probe-fsm)))
                (equal (prd-d-eng-at b (fsm-eval envs initst (probe-fsm))) 4)
                (equal (pay-st-at b (fsm-eval envs initst (probe-fsm))) 0)
                (stg-quiet b m envs (fsm-eval envs initst (probe-fsm)))
                (prd-entries-ok (stg-log (+ 1 b) m envs (fsm-eval envs initst (probe-fsm)))
                                (prd-klog b (fsm-eval envs initst (probe-fsm))) (prd-vlog b (fsm-eval envs initst (probe-fsm)))))
           (prd-entries-ok (stg-log (+ 1 b) (+ 1 m) envs (fsm-eval envs initst (probe-fsm)))
                           (prd-klog b (fsm-eval envs initst (probe-fsm))) (prd-vlog b (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal"
           :use ((:instance prd-frozen-from-begin)
                 (:instance prd-ok-range-at (i m) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-transfer-is-produced (k m) (outs (fsm-eval envs initst (probe-fsm)))))
           :expand ((stg-log (+ 1 b) (+ 1 m) envs (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (prd-entries-ok)
                           (prd-cycle-ok prd-ok-range stg-quiet stg-log pay-st-at rec-clear-at logbitp
                            rec-beat-at stg-transfer-at prd-klog prd-vlog loghead stg-begin-at
                            prd-klog-next prd-vlog-next prd-stg-quiet-empty prd-stg-log-empty
                            fsm-eval (probe-fsm) probe-fsm (tau-system)))))
  :rule-classes nil)
(defthm prd-log-is-produced
  (implies (and (natp b) (natp m) (<= 1 b) (<= b m)
                (prd-ok-range b m envs (fsm-eval envs initst (probe-fsm)))
                (equal (prd-d-eng-at b (fsm-eval envs initst (probe-fsm))) 4)
                (equal (pay-st-at b (fsm-eval envs initst (probe-fsm))) 0)
                (stg-quiet b m envs (fsm-eval envs initst (probe-fsm))))
           (prd-entries-ok (stg-log (+ 1 b) (+ 1 m) envs (fsm-eval envs initst (probe-fsm)))
                           (prd-klog b (fsm-eval envs initst (probe-fsm))) (prd-vlog b (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal" :induct (prd-ind b m)
           :in-theory (disable prd-cycle-ok prd-ok-range stg-quiet stg-log pay-st-at rec-clear-at
                               rec-beat-at stg-transfer-at prd-klog prd-vlog loghead logbitp
                               prd-klog-next prd-vlog-next prd-stg-quiet-empty
                               fsm-eval (probe-fsm) probe-fsm (tau-system)))
          ("Subgoal *1/2"
           :use ((:instance prd-log-one-more)
                 (:instance prd-ok-range-shorter (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-stg-quiet-shorter (outs (fsm-eval envs initst (probe-fsm))))))
          ("Subgoal *1/1"
           :in-theory (e/d (prd-entries-ok)
                           (prd-cycle-ok prd-ok-range stg-quiet pay-st-at rec-clear-at
                            rec-beat-at stg-transfer-at prd-klog prd-vlog loghead logbitp
                            fsm-eval (probe-fsm) probe-fsm (tau-system)))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-LOG done~%"))

; ---------------------------------------------------------------------------
; THE PRODUCER'S RESULTS AND THE IDENTITY OF ITS WORK.
; ---------------------------------------------------------------------------
; THE K RESULTS of the staging begun in cycle b: the K rotary results
; accepted since the latest accepted request for the K rotary stage before
; b, each (index mantissa exponent).  A K rotary result is accepted in a
; cycle when the key memory is written with current_stage_q = 5; it is
; (output_index_q[6:0] norm_result_mantissa norm_result_exponent).
(define kv-key-results (b outs) :verify-guards nil (prd-klog b outs))
; THE V RESULTS: the V projection results accepted since the latest accepted
; request for the V projection stage before b.  A V projection result is
; accepted in a cycle when the value memory is written.
(define kv-value-results (b outs) :verify-guards nil (prd-vlog b outs))
; every index 0 .. 127 has a result in the list
(define kv-all-coordinates-produced (log) :verify-guards nil (prd-covers 128 log))
; the cycle of the latest accepted request for stage s before cycle b
(define kv-stage-request-cycle (s b outs) :verify-guards nil (prd-start s b outs))
; the cycle of the latest accepted sequencer start before cycle b
(define kv-pass-start-cycle (b outs) :verify-guards nil (prd-pass-start b outs))
; In cycle k the datapath accepts the request for stage s of this layer at
; this position (stage_accept with private_stage_i, private_layer_i and
; private_position_i).
(define kv-stage-request-accepted-at (k s layer position outs) :verify-guards nil
  (and (prd-accept-at s k outs)
       (equal (prd-o-player-at k outs) layer)
       (equal (prd-o-ppos-at k outs) position)))
; In cycle k the sequencer accepts the start of a pass for this position
; (start_fire with fixed_position_i).
(define kv-pass-started-at (k position outs) :verify-guards nil
  (and (equal (prd-o-sfire-at k outs) 1)
       (equal (prd-h-sfpos-at k outs) position)))
; THE IDENTITY OF THE WORK behind the staging begun in cycle b.  One pass of
; the sequencer, started at ps for the staged position; in it, in this
; order, the accepted requests for the V projection stage (3), the K rotary
; stage (5) and the K/V stage (6), each for the staged layer and position;
; then the begin.  From ps to b the sequencer is busy in every cycle and no
; CLEAR reaches the datapath.
(define kv-producer-work-identified (b outs) :verify-guards nil
  (b* ((layer (kv-staged-layer b outs))
       (position (kv-staged-position b outs))
       (ps (kv-pass-start-cycle b outs))
       (vs (kv-stage-request-cycle 3 b outs))
       (ks (kv-stage-request-cycle 5 b outs))
       (ss (kv-stage-request-cycle 6 b outs)))
    (and (natp ps) (natp vs) (natp ks) (natp ss)
         (< ps vs) (< vs ks) (< ks ss) (< ss b)
         (kv-pass-started-at ps position outs)
         (kv-stage-request-accepted-at vs 3 layer position outs)
         (kv-stage-request-accepted-at ks 5 layer position outs)
         (kv-stage-request-accepted-at ss 6 layer position outs)
         (prd-no-clear ps b outs)
         (prd-busy-since ps b outs))))

; the begin is not in the last reset cycle
(defthm prd-begin-after-release
  (implies (and (natp r) (natp b) (natp j) (<= (+ 2 r) b) (<= (+ 2 b) j)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at (+ 2 r) (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) (+ 1 j) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from (+ 2 r) (+ 1 j) envs (fsm-eval envs initst (probe-fsm)))
                (stg-quiet b (+ -1 j) envs (fsm-eval envs initst (probe-fsm))))
           (<= (+ 3 r) b))
  :hints (("Goal"
           :use ((:instance prd-release-after-reset)
                 (:instance prd-stg-quiet-at (k (+ 1 b)) (m (+ -1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-inv-from-reset (n (+ 1 b)))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m (+ 1 b)) (n (+ 1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m (+ 3 r)) (n (+ 1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m (+ 3 r)) (n (+ 1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-active-when-controller-busy (k (+ 1 b)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-known-from (j (+ 2 r)) (i (+ 2 r)))
                 (:instance prd-ev-release (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (disable join-inv-from-reset prd-known-at join-j-at join-env-at join-reset-at
                               prod-mem-at join-env-from prod-env-from stg-quiet pay-st-at
                               rec-clear-at fsm-eval (probe-fsm) probe-fsm)))
  :rule-classes nil)
; THE STAGED TRANSFERS ARE THE PRODUCER'S FINAL RESULTS.
(defthm prd-staging-is-produced
  (implies (and (natp r) (natp b) (natp j) (<= (+ 2 r) b) (< b j)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (prod-mem-at (+ 2 r) (fsm-eval envs initst (probe-fsm)))
                (join-env-from (+ 2 r) (+ 1 j) envs (fsm-eval envs initst (probe-fsm)))
                (prod-env-from (+ 2 r) (+ 1 j) envs (fsm-eval envs initst (probe-fsm)))
                (equal (stg-begin-at b envs (fsm-eval envs initst (probe-fsm))) 1)
                (equal (pay-st-at b (fsm-eval envs initst (probe-fsm))) 0)
                (stg-quiet b (+ -1 j) envs (fsm-eval envs initst (probe-fsm)))
                (equal (len (stg-log (+ 1 b) j envs (fsm-eval envs initst (probe-fsm)))) 128)
                (stg-coords-from 0 (stg-log (+ 1 b) j envs (fsm-eval envs initst (probe-fsm)))))
           (and (<= (+ 3 r) b)
                (equal (stg-log (+ 1 b) j envs (fsm-eval envs initst (probe-fsm)))
                       (kv-produced-transfers (prd-klog b (fsm-eval envs initst (probe-fsm))) (prd-vlog b (fsm-eval envs initst (probe-fsm)))))
                (equal (stg-kexp-at b (fsm-eval envs initst (probe-fsm))) (kv-final-exponent (prd-klog b (fsm-eval envs initst (probe-fsm)))))
                (equal (stg-vexp-at b (fsm-eval envs initst (probe-fsm))) (kv-final-exponent (prd-vlog b (fsm-eval envs initst (probe-fsm)))))
                (prd-covers 128 (prd-klog b (fsm-eval envs initst (probe-fsm))))
                (prd-covers 128 (prd-vlog b (fsm-eval envs initst (probe-fsm))))
                (kv-producer-work-identified b (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal"
           :cases ((<= (+ 2 b) j))
           :use ((:instance prd-begin-after-release)
                 (:instance prd-ok-range-from-reset (m (+ -1 j)))
                 (:instance join-env-from-prefix (j (+ 2 r)) (m j) (n (+ 1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix (j (+ 2 r)) (m j) (n (+ 1 j)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ok-range-at (m (+ -1 j)) (i b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-bridge (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-staging-valid (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-ev-busy (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-engine-of-stage (cst (prd-d-cst-at b (fsm-eval envs initst (probe-fsm)))))
                 (:instance prd-log-is-produced (m (+ -1 j)))
                 (:instance prd-entries-are-produced (c 0)
                  (log (stg-log (+ 1 b) j envs (fsm-eval envs initst (probe-fsm))))
                  (klog (prd-klog b (fsm-eval envs initst (probe-fsm)))) (vlog (prd-vlog b (fsm-eval envs initst (probe-fsm)))))
                 (:instance prd-start-bound (s 3) (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-start-bound (s 5) (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-start-bound (s 6) (k b) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-pass-start-bound (k b) (outs (fsm-eval envs initst (probe-fsm)))))
           :in-theory (e/d (prd-cycle-ok prd-inv prd-kdone-ok prd-vdone-ok prd-kv-ok prd-seq-ok
                            kv-producer-work-identified kv-staged-layer kv-staged-position
                            kv-pass-start-cycle kv-stage-request-cycle kv-pass-started-at
                            kv-stage-request-accepted-at kv-produced-transfers stg-begin-at)
                           (prod-sinv prod-put prod-slot prod-engine-of loghead logtail logbitp unsigned-byte-p nth nthcdr take len
                            prd-klog prd-vlog prd-start prd-pass-start prd-no-clear prd-busy-since
                            prd-covers prd-mem-ok kv-final-exponent kv-final-result prd-occurs prd-known-at prd-nofault-at prd-sinv-at join-j-at join-env-at
                            join-reset-at prod-mem-at join-env-from prod-env-from stg-quiet stg-log
                            pay-st-at rec-clear-at stg-coords-from prd-ok-range
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-PRODUCED done~%"))

; ---------------------------------------------------------------------------
; THE SECOND LINK'S THEOREM, composed with the first.
; ---------------------------------------------------------------------------
; Take any execution of the probe module's state machine, from any initial
; state, with the first link's hypotheses and this link's premises holding
; through cycle n: the reset, definite storage in the controller's pair
; store and in the datapath's two working memories at the end of the reset,
; the environment, and two-valued producer signals.  Suppose
; pending_persisted_q rises at cycle n.  Let j be the record's start, b the
; begin of its staging, and keys and values the K rotary and V projection
; results accepted before b since the latest accepted request for each of
; those stages.  Then
;   - every index 0 .. 127 has a K result and a V result;
;   - the eighteen writes the endpoint (private_kv_req_*) accepted in cycles
;     j to n, in order, are the reference record of the staged layer and
;     position, the exponent of the last K result, the exponent of the last
;     V result, and for each coordinate c the mantissa of the final K
;     result and the final V result with index c;
;   - those results were accepted in one pass of the sequencer for that
;     position (kv-producer-work-identified).
(defthm kv-producer-to-record
  (b* ((outs (fsm-eval envs initst (probe-fsm)))
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (keys (kv-key-results b outs))
       (values (kv-value-results b outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-producer-storage-definite-at (+ 2 r) outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-producer-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs))
             (and (natp b) (< (+ 2 r) b) (< b j) (<= j n)
                  (kv-staging-begin-accepted-at b envs outs)
                  (kv-staging-uninterrupted b j envs outs)
                  (kv-record-uninterrupted j n envs outs)
                  (kv-all-coordinates-produced keys)
                  (kv-all-coordinates-produced values)
                  (kv-producer-work-identified b outs)
                  (equal (kv-endpoint-writes j (+ 1 n) envs outs)
                         (kv-reference-record (kv-staged-layer b outs)
                                              (kv-staged-position b outs)
                                              (kv-final-exponent keys)
                                              (kv-final-exponent values)
                                              (kv-produced-transfers keys values))))))
  :hints (("Goal"
           :use ((:instance kv-staging-to-record)
                 (:instance kvj-reset-connects (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-signals-from-connect (j (+ 2 r)) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-storage-connects (k (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-env-from-prefix
                  (j (+ 2 r)) (m (+ 1 (kv-record-start n (fsm-eval envs initst (probe-fsm))))) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prod-env-from-prefix
                  (j (+ 2 r)) (m (+ 1 (kv-record-start n (fsm-eval envs initst (probe-fsm))))) (n (+ 1 n)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance prd-staging-is-produced
                  (j (kv-record-start n (fsm-eval envs initst (probe-fsm))))
                  (b (kv-staging-begin (kv-record-start n (fsm-eval envs initst (probe-fsm))) envs (fsm-eval envs initst (probe-fsm))))))
           :in-theory (e/d (kv-staging-begin-accepted-at kv-staging-uninterrupted
                            kv-staged-transfers kv-transfers-in-order
                            kv-staged-key-exponent kv-staged-value-exponent
                            kv-key-results kv-value-results kv-all-coordinates-produced)
                           (kvj-reset-connects kvj-environment-from-connects
                            kv-record-start kv-staging-begin kv-staged-layer kv-staged-position
                            kv-producer-work-identified kv-reference-record kv-endpoint-writes
                            kv-record-uninterrupted kv-produced-transfers
                            stg-begin stg-begin-at stg-quiet stg-log stg-coords-from
                            stg-kexp-at stg-vexp-at stg-layer-at stg-position-at pay-st-at rec-clear-at
                            prd-klog prd-vlog prd-covers kv-final-exponent
                            join-env-from prod-env-from join-reset-at prod-mem-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
(value-triple (acl2::cw "~%PRD-THEOREM done~%"))

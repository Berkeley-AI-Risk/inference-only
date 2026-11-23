; From the producer to the staging: the producer facts in every cycle of every execution.
;
; Written by make_step_book.py; do not edit.  Private.
;
; kv-producer-step.lisp proves the producer facts of one symbolic cycle.
; This book carries them to any cycle of any execution of (probe-fsm):
;   prod-step-fsm-thm   for any envs and initst, with
;                       outs = (fsm-eval envs initst (probe-fsm)): if the
;                       signals the lemma takes a value for are two-valued
;                       in cycle k, the signals of cycles k and k+1 satisfy
;                       the lemma's conclusion
;   hold-fsm-thm        the same of the hold lemma
(in-package "SV")
(include-book "kv-producer-step")
(acl2::set-slow-alist-action nil)
(acl2::set-rewrite-stack-limit 20000)

(define prod-step-all (h-kpc h-lsv h-nre h-nri h-nrl h-nrm h-nrv h-sdf h-sfpos i-clear i-reset-n n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kexp n-d-kmem n-d-krd n-d-kvrv n-d-lseen n-d-odone n-d-oidx n-d-sdone n-d-tpos n-d-tseen n-d-vexp n-d-vmem n-d-vrd n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dpclear o-dprst o-kra o-kre o-kwe o-layerfail o-player o-ppos o-pstage o-sacc o-sbv o-sfire o-spv o-vra o-vre o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kexp r-d-kmem r-d-krd r-d-kvrv r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-sss r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-d-vrd r-l-coll r-m-rel r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (prod-int-o-dprst o-dprst)
       (prod-int-o-dpclear o-dpclear)
       (prod-int-o-sacc o-sacc)
       (prod-int-o-pstage o-pstage)
       (prod-int-o-player o-player)
       (prod-int-o-ppos o-ppos)
       (prod-int-o-kwe o-kwe)
       (prod-int-o-vwe o-vwe)
       (prod-int-o-kre o-kre)
       (prod-int-o-vre o-vre)
       (prod-int-o-kra o-kra)
       (prod-int-o-vra o-vra)
       (prod-int-o-sbv o-sbv)
       (prod-int-o-spv o-spv)
       (prod-int-o-sfire o-sfire)
       (prod-int-o-layerfail o-layerfail)
       (prod-int-n-m-rel n-m-rel)
       (prod-int-n-s-state n-s-state)
       (prod-int-n-s-layer n-s-layer)
       (prod-int-n-s-stage n-s-stage)
       (prod-int-n-s-pos n-s-pos)
       (prod-int-n-s-fault n-s-fault)
       (prod-int-n-d-eng n-d-eng)
       (prod-int-n-d-cst n-d-cst)
       (prod-int-n-d-clay n-d-clay)
       (prod-int-n-d-cpos n-d-cpos)
       (prod-int-n-d-est n-d-est)
       (prod-int-n-d-elay n-d-elay)
       (prod-int-n-d-tpos n-d-tpos)
       (prod-int-n-d-tseen n-d-tseen)
       (prod-int-n-d-fault n-d-fault)
       (prod-int-n-d-lseen n-d-lseen)
       (prod-int-n-d-sdone n-d-sdone)
       (prod-int-n-d-kexp n-d-kexp)
       (prod-int-n-d-vexp n-d-vexp)
       (prod-int-n-d-odone n-d-odone)
       (prod-int-n-d-iidx n-d-iidx)
       (prod-int-n-d-oidx n-d-oidx)
       (prod-int-n-d-kvrv n-d-kvrv)
       (prod-int-n-d-kmem n-d-kmem)
       (prod-int-n-d-vmem n-d-vmem)
       (prod-int-n-d-krd n-d-krd)
       (prod-int-n-d-vrd n-d-vrd)
       (prod-step-concl h-kpc h-lsv h-nre h-nri h-nrl h-nrm h-nrv h-sdf h-sfpos i-clear i-reset-n n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kexp n-d-kmem n-d-krd n-d-kvrv n-d-lseen n-d-odone n-d-oidx n-d-sdone n-d-tpos n-d-tseen n-d-vexp n-d-vmem n-d-vrd n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dpclear o-dprst o-kra o-kre o-kwe o-layerfail o-player o-ppos o-pstage o-sacc o-sbv o-sfire o-spv o-vra o-vre o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kexp r-d-kmem r-d-krd r-d-kvrv r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-sss r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-d-vrd r-l-coll r-m-rel r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)))
(in-theory (disable prod-step-all))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm prod-step-svtv-thm-folded
         :svtv producer-step-run
         :svtv-spec producer-step-spec
         :input-vars :all
         :output-vars (o-dprst o-dpclear o-sacc o-pstage o-player o-ppos o-kwe o-vwe o-kre o-vre o-kra o-vra o-sbv o-spv o-sfire o-layerfail n-m-rel n-s-state n-s-layer n-s-stage n-s-pos n-s-fault n-d-eng n-d-cst n-d-clay n-d-cpos n-d-est n-d-elay n-d-tpos n-d-tseen n-d-fault n-d-lseen n-d-sdone n-d-kexp n-d-vexp n-d-odone n-d-iidx n-d-oidx n-d-kvrv n-d-kmem n-d-vmem n-d-krd n-d-vrd)
         :unsigned-byte-hyps t
         :no-integerp t
         :override-vars (r-p-lock-sync r-m-rel r-l-coll r-s-state r-s-layer r-s-stage r-s-pos r-s-fault r-s-lseen r-s-sidx r-s-rexp r-d-eng r-d-cst r-d-clay r-d-cpos r-d-est r-d-elay r-d-tpos r-d-tseen r-d-fault r-d-lseen r-d-sdone r-d-kexp r-d-vexp r-d-sss r-d-odone r-d-sds r-d-nds r-d-iidx r-d-idone r-d-oidx r-d-rphase r-d-rhead r-d-rhalf r-d-rsecond r-d-arhead r-d-aslane r-d-svv r-d-gexp r-d-kvrv r-d-ephase r-d-kmem r-d-vmem r-d-krd r-d-vrd h-rterm h-childfault h-nrv h-nri h-nrm h-nre h-nrl h-ndv h-pdv h-rrv h-rri h-rrl h-rdv h-hdf h-lrv h-lrf h-arv h-arl h-adv h-llr h-lli h-grd h-kcr h-sbr h-spr h-kpc h-hsr h-rif h-paf h-haf h-hsv h-lsv h-dbusy h-sif h-sil h-spm h-siexp h-sfpos h-sdf h-srf h-srexp h-srman)
         :spec-override-vars ()
         :hyp t
         :concl (prod-step-all h-kpc h-lsv h-nre h-nri h-nrl h-nrm h-nrv h-sdf h-sfpos i-clear i-reset-n n-d-clay n-d-cpos n-d-cst n-d-elay n-d-eng n-d-est n-d-fault n-d-iidx n-d-kexp n-d-kmem n-d-krd n-d-kvrv n-d-lseen n-d-odone n-d-oidx n-d-sdone n-d-tpos n-d-tseen n-d-vexp n-d-vmem n-d-vrd n-m-rel n-s-fault n-s-layer n-s-pos n-s-stage n-s-state o-dpclear o-dprst o-kra o-kre o-kwe o-layerfail o-player o-ppos o-pstage o-sacc o-sbv o-sfire o-spv o-vra o-vre o-vwe r-d-clay r-d-cpos r-d-cst r-d-elay r-d-eng r-d-est r-d-fault r-d-iidx r-d-kexp r-d-kmem r-d-krd r-d-kvrv r-d-lseen r-d-odone r-d-oidx r-d-sdone r-d-sss r-d-tpos r-d-tseen r-d-vexp r-d-vmem r-d-vrd r-l-coll r-m-rel r-s-fault r-s-layer r-s-pos r-s-stage r-s-state)
         :no-lemmas t
         :hints (("Goal" :use ((:instance prod-step-svtv-thm))
                  :in-theory '(prod-step-all)))))
  (value-triple (acl2::cw "~%PROD-STEP-FOLDED proved~%")))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event
   '(def-svtv-to-fsm-thm prod-step-fsm-thm
     :svtv-spec-thmname prod-step-svtv-thm-folded
     :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%PROD-STEP-FSM proved~%")))
(define hold-all (o-kpc)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (hold-int-o-kpc o-kpc)
       (hold-fact-not-complete o-kpc)))
(in-theory (disable hold-all))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm hold-svtv-thm-folded
         :svtv producer-hold-run
         :svtv-spec producer-hold-spec
         :input-vars :all
         :output-vars (o-kpc)
         :unsigned-byte-hyps t
         :no-integerp t
         :override-vars (r-k-state-q)
         :spec-override-vars ()
         :hyp (or (equal r-k-state-q 0) (equal r-k-state-q 1))
         :concl (hold-all o-kpc)
         :no-lemmas t
         :hints (("Goal" :use ((:instance hold-svtv-thm))
                  :in-theory '(hold-all)))))
  (value-triple (acl2::cw "~%HOLD-FOLDED proved~%")))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event
   '(def-svtv-to-fsm-thm hold-fsm-thm
     :svtv-spec-thmname hold-svtv-thm-folded
     :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%HOLD-FSM proved~%")))

; From the public STEP to the producer: the shell facts in every cycle of every execution.
;
; Written by make_step_book.py; do not edit.  Private.
;
; kv-shell-step.lisp proves the shell facts of one symbolic cycle.  This
; book carries them to any cycle of any execution of (probe-fsm):
; shl0-step-fsm-thm and shl1-step-fsm-thm.
(in-package "SV")
(include-book "kv-shell-step")
(acl2::set-slow-alist-action nil)
(acl2::set-rewrite-stack-limit 20000)

(define shl0-step-all (o-appendready o-sdf o-sfire o-sfpos o-shellfail o-stepready r-s-state r-t-replay r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (shl0-int-o-stepready o-stepready)
       (shl0-int-o-appendready o-appendready)
       (shl0-int-o-sfire o-sfire)
       (shl0-int-o-sdf o-sdf)
       (shl0-int-o-sfpos o-sfpos)
       (shl0-int-o-shellfail o-shellfail)
       (shl0-step-concl o-appendready o-sdf o-sfire o-sfpos o-shellfail o-stepready r-s-state r-t-replay r-t-state)))
(in-theory (disable shl0-step-all))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm shl0-step-svtv-thm-folded
         :svtv shell-step-run
         :svtv-spec shell-step-spec
         :input-vars :all
         :output-vars (o-stepready o-appendready o-sfire o-sdf o-sfpos o-shellfail)
         :unsigned-byte-hyps t
         :no-integerp t
         :override-vars (r-p-lock-sync r-m-rel r-l-coll r-s-state r-s-fault r-s-sidx r-s-rexp r-d-fault r-t-state r-t-fail r-t-owner r-t-tape r-t-committed r-t-replay r-t-lastvalid r-t-sidx r-t-cidx r-t-eread r-t-l5exp h-ufc h-arbfail h-shellterm h-layerfail h-dbusy h-tchild h-tlock h-twatch h-tpub h-tpriv h-tcpm h-tclpm h-tebusy h-trbusy h-tabusy h-srman)
         :spec-override-vars ()
         :hyp t
         :concl (shl0-step-all o-appendready o-sdf o-sfire o-sfpos o-shellfail o-stepready r-s-state r-t-replay r-t-state)
         :no-lemmas t
         :hints (("Goal" :use ((:instance shl0-step-svtv-thm))
                  :in-theory '(shl0-step-all)))))
  (value-triple (acl2::cw "~%SHL0-STEP-FOLDED proved~%")))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event
   '(def-svtv-to-fsm-thm shl0-step-fsm-thm
     :svtv-spec-thmname shl0-step-svtv-thm-folded
     :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%SHL0-STEP-FSM proved~%")))
(define shl1-step-all (h-layerfail i-clear i-step n-m-rel n-t-state o-dpclear o-dprst o-sdf o-sfire o-shellfail o-stepready r-m-rel r-t-state)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (shl1-int-o-stepready o-stepready)
       (shl1-int-o-sfire o-sfire)
       (shl1-int-o-sdf o-sdf)
       (shl1-int-o-shellfail o-shellfail)
       (shl1-int-o-dprst o-dprst)
       (shl1-int-o-dpclear o-dpclear)
       (shl1-int-n-m-rel n-m-rel)
       (shl1-int-n-t-state n-t-state)
       (shl1-step-concl h-layerfail i-clear i-step n-m-rel n-t-state o-dpclear o-dprst o-sdf o-sfire o-shellfail o-stepready r-m-rel r-t-state)))
(in-theory (disable shl1-step-all))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm shl1-step-svtv-thm-folded
         :svtv shell-step-run
         :svtv-spec shell-step-spec
         :input-vars :all
         :output-vars (o-stepready o-sfire o-sdf o-shellfail o-dprst o-dpclear n-m-rel n-t-state)
         :unsigned-byte-hyps t
         :no-integerp t
         :override-vars (r-p-lock-sync r-m-rel r-l-coll r-s-state r-s-fault r-s-sidx r-s-rexp r-d-fault r-t-state r-t-fail r-t-owner r-t-tape r-t-committed r-t-replay r-t-lastvalid r-t-sidx r-t-cidx r-t-eread r-t-l5exp h-ufc h-arbfail h-shellterm h-layerfail h-dbusy h-tchild h-tlock h-twatch h-tpub h-tpriv h-tcpm h-tclpm h-tebusy h-trbusy h-tabusy h-srman)
         :spec-override-vars ()
         :hyp (or (or (equal r-t-state 0) (equal r-t-state 5) (equal r-t-state 6) (equal r-t-state 7) (equal r-t-state 8) (equal r-t-state 9) (equal r-t-state 23)) (equal i-clear 1) (not (logbitp 1 r-m-rel)))
         :concl (shl1-step-all h-layerfail i-clear i-step n-m-rel n-t-state o-dpclear o-dprst o-sdf o-sfire o-shellfail o-stepready r-m-rel r-t-state)
         :no-lemmas t
         :hints (("Goal" :use ((:instance shl1-step-svtv-thm))
                  :in-theory '(shl1-step-all)))))
  (value-triple (acl2::cw "~%SHL1-STEP-FOLDED proved~%")))
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event
   '(def-svtv-to-fsm-thm shl1-step-fsm-thm
     :svtv-spec-thmname shl1-step-svtv-thm-folded
     :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%SHL1-STEP-FSM proved~%")))

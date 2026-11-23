; The K/V write record: the two new facts in every cycle of every execution.
;
; Written by make_record_book.py; do not edit.  Private.
;
; kv-write-record-step.lisp proves the two facts of one symbolic cycle of
; the step run.  This book carries them to any cycle of any execution of
; (probe-fsm), the state machine of the probe module as translated from the
; pinned RTL:
;   rec-step-fsm-thm   for any envs and initst, with
;                      outs = (fsm-eval envs initst (probe-fsm)): if the
;                      signals of cycle k satisfy the step lemma's
;                      hypotheses, they and those of cycle k+1 satisfy its
;                      conclusion
; The conclusion is first folded into one predicate, as in the payload
; book: the library's lift costs one case per named signal for each conjunct
; of the conclusion.
(in-package "SV")
(include-book "kv-write-record-step")
(acl2::set-slow-alist-action nil)
(acl2::set-rewrite-stack-limit 20000)

; The whole conclusion of rec-step-svtv-thm, as one predicate.
(define rec-step-all (h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (pay-int-o-pfn o-pfn)
       (pay-int-o-tpf o-tpf)
       (pay-int-o-epf o-epf)
       (pay-int-o-spr o-spr)
       (pay-int-o-spl o-spl)
       (pay-int-n-k-state-q n-k-state-q)
       (pay-int-n-k-pending-layer-q n-k-pending-layer-q)
       (pay-int-n-k-pending-position-q n-k-pending-position-q)
       (pay-int-n-k-pending-key-exponents-q n-k-pending-key-exponents-q)
       (pay-int-n-k-pending-value-exponents-q n-k-pending-value-exponents-q)
       (pay-int-n-k-write-head-q n-k-write-head-q)
       (pay-int-n-k-write-word-q n-k-write-word-q)
       (pay-int-n-k-write-aborted-q n-k-write-aborted-q)
       (rec-step-concl h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)))
(in-theory (disable rec-step-all))

; The lemma again, with that conclusion.  It is the lemma itself: the proof
; only opens the definition above.
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm rec-step-svtv-thm-folded
      :svtv payload-step-run
      :svtv-spec payload-step-spec
      :input-vars :all
      :output-vars (o-pfn o-tpf o-epf o-spr o-spl n-k-state-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-write-head-q n-k-write-word-q n-k-write-aborted-q)
      :unsigned-byte-hyps t
      :no-integerp t
      :override-vars (r-p-lock-meta r-p-lock-sync r-p-cfb r-p-apprel r-m-rel r-k-state-q r-k-pending-issued-q r-k-pending-returned-q r-k-pending-read-pending-q r-k-committed-prefix-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-expected-coordinate-q r-k-pending-persisted-q r-k-write-head-q r-k-write-word-q r-k-write-aborted-q r-k-response-kind-q r-k-response-head-q r-k-response-layer-q r-k-response-position-q r-k-response-fault-q r-k-response-from-pending-q r-k-read-word-q r-k-read-return-word-q r-k-read-outstanding-q r-k-read-issue-done-q r-k-read-aborted-q r-k-read-physical-kind-q r-k-read-epoch-q r-k-read-received-mask-q r-k-cache-valid-q r-k-cache-kind-q r-k-cache-layer-q r-k-cache-position-q r-k-cache-tag-epoch-q r-k-cache-epoch-q r-k-cache-clear-seen-q r-k-cache-issued-q r-k-cache-returned-q r-k-cache-read-pending-q r-k-cache-copy-kind-q r-k-lock-seen-q r-k-fault-q r-k-stage-begin-consumed-q r-k-stage-payload-consumed-q r-k-commit-consumed-q r-k-attention-req-consumed-q r-b-crel r-b-arel r-b-lock-meta r-b-lock-sync r-b-afc-meta r-b-afc-sync r-b-cfa-meta r-b-cfa-sync r-b-fault r-b-lock-seen r-b-clr-seen r-b-clr-pend r-b-clr-drained r-b-epoch r-b-out r-b-mstall r-b-wstall r-b-wstallf r-b-rstall r-q-wb r-q-wg r-q-full r-q-rb r-q-rg r-q-rs1 r-q-rs2 r-q-ws1 r-q-ws2 r-q-mv r-q-sf r-q-spf r-q-df r-q-st r-q-md r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4 r-q-mem5 r-q-mem6 r-q-mem7 r-s-wb r-s-wg r-s-full r-s-rb r-s-rg r-s-rs1 r-s-rs2 r-s-ws1 r-s-ws2 r-s-mv r-s-sf r-s-spf r-s-df r-s-st r-s-md r-s-mem0 r-s-mem1 r-s-mem2 r-s-mem3 r-s-mem4 r-s-mem5 r-s-mem6 r-s-mem7 r-q-mdw r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3 r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 r-a-fault r-a-lock-seen r-a-offer r-a-offer-write r-a-poison r-a-offer-slot r-a-reserved r-a-unissued r-a-readcount r-a-head r-a-tail r-a-issue r-a-rhead r-a-rtail r-a-kind0 r-a-kind1 r-a-kind2 r-a-kind3 r-a-kind4 r-a-kind5 r-a-kind6 r-a-kind7 r-a-epoch0 r-a-epoch1 r-a-epoch2 r-a-epoch3 r-a-epoch4 r-a-epoch5 r-a-epoch6 r-a-epoch7 r-a-reject0 r-a-reject1 r-a-reject2 r-a-reject3 r-a-reject4 r-a-reject5 r-a-reject6 r-a-reject7 r-a-done0 r-a-done1 r-a-done2 r-a-done3 r-a-done4 r-a-done5 r-a-done6 r-a-done7 r-a-sfault0 r-a-sfault1 r-a-sfault2 r-a-sfault3 r-a-sfault4 r-a-sfault5 r-a-sfault6 r-a-sfault7 r-a-word0 r-a-word1 r-a-word2 r-a-word3 r-a-word4 r-a-word5 r-a-word6 r-a-word7 r-a-rslot0 r-a-rslot1 r-a-rslot2 r-a-rslot3 r-a-rslot4 r-a-rslot5 r-a-rslot6 r-a-rslot7 h-arbfail h-shellterm h-shellfail h-layerfail h-auth h-mcdc h-kupf h-layer h-position h-kexp h-vexp h-sbegin h-spayload h-index h-key h-value h-commit h-attn h-attn-kind h-attn-pos h-attn-head h-attn-ready h-epready h-eprspv h-eprsperr h-eprspdata h-rspdata h-appup h-legal r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-rd0 r-k-rd1 r-k-rd2 r-k-rd3 r-k-rd4 r-k-rd5 r-k-rd6 r-k-rd7 r-k-offer r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-memd0 r-q-memd1 r-q-memd2 r-q-memd3 r-q-memd4 r-q-memd5 r-q-memd6 r-q-memd7 r-q-mdd r-q-mdp r-a-saddr r-a-sdata r-a-oaddr r-a-odata)
      :spec-override-vars ()
      :hyp (and (and (joint-inv-p
                       r-p-lock-meta r-p-lock-sync r-p-cfb r-p-apprel r-m-rel
                       r-k-state-q r-k-pending-issued-q r-k-pending-returned-q
                       r-k-pending-read-pending-q r-k-committed-prefix-q
                       r-k-pending-layer-q r-k-pending-position-q
                       r-k-pending-key-exponents-q r-k-pending-value-exponents-q
                       r-k-expected-coordinate-q r-k-pending-persisted-q
                       r-k-write-head-q r-k-write-word-q r-k-write-aborted-q
                       r-k-response-kind-q r-k-response-head-q
                       r-k-response-layer-q r-k-response-position-q
                       r-k-response-fault-q r-k-response-from-pending-q
                       r-k-read-word-q r-k-read-return-word-q
                       r-k-read-outstanding-q r-k-read-issue-done-q
                       r-k-read-aborted-q r-k-read-physical-kind-q
                       r-k-read-epoch-q r-k-read-received-mask-q
                       r-k-cache-valid-q r-k-cache-kind-q r-k-cache-layer-q
                       r-k-cache-position-q r-k-cache-tag-epoch-q
                       r-k-cache-epoch-q r-k-cache-clear-seen-q
                       r-k-cache-issued-q r-k-cache-returned-q
                       r-k-cache-read-pending-q r-k-cache-copy-kind-q
                       r-k-lock-seen-q r-k-fault-q r-k-stage-begin-consumed-q
                       r-k-stage-payload-consumed-q r-k-commit-consumed-q
                       r-k-attention-req-consumed-q r-b-crel r-b-arel
                       r-b-lock-meta r-b-lock-sync r-b-afc-meta r-b-afc-sync
                       r-b-cfa-meta r-b-cfa-sync r-b-fault r-b-lock-seen
                       r-b-clr-seen r-b-clr-pend r-b-clr-drained r-b-epoch
                       r-b-out r-b-mstall r-b-wstall r-b-wstallf r-b-rstall
                       r-q-wb r-q-wg r-q-full r-q-rb r-q-rg r-q-rs1 r-q-rs2
                       r-q-ws1 r-q-ws2 r-q-mv r-q-sf r-q-spf r-q-df r-q-st
                       r-q-md r-q-mem0 r-q-mem1 r-q-mem2 r-q-mem3 r-q-mem4
                       r-q-mem5 r-q-mem6 r-q-mem7 r-s-wb r-s-wg r-s-full r-s-rb
                       r-s-rg r-s-rs1 r-s-rs2 r-s-ws1 r-s-ws2 r-s-mv r-s-sf
                       r-s-spf r-s-df r-s-st r-s-md r-s-mem0 r-s-mem1 r-s-mem2
                       r-s-mem3 r-s-mem4 r-s-mem5 r-s-mem6 r-s-mem7 r-q-mdw
                       r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3 r-q-memw4
                       r-q-memw5 r-q-memw6 r-q-memw7 r-a-fault r-a-lock-seen
                       r-a-offer r-a-offer-write r-a-poison r-a-offer-slot
                       r-a-reserved r-a-unissued r-a-readcount r-a-head r-a-tail
                       r-a-issue r-a-rhead r-a-rtail r-a-kind0 r-a-kind1
                       r-a-kind2 r-a-kind3 r-a-kind4 r-a-kind5 r-a-kind6
                       r-a-kind7 r-a-epoch0 r-a-epoch1 r-a-epoch2 r-a-epoch3
                       r-a-epoch4 r-a-epoch5 r-a-epoch6 r-a-epoch7 r-a-reject0
                       r-a-reject1 r-a-reject2 r-a-reject3 r-a-reject4
                       r-a-reject5 r-a-reject6 r-a-reject7 r-a-done0 r-a-done1
                       r-a-done2 r-a-done3 r-a-done4 r-a-done5 r-a-done6
                       r-a-done7 r-a-sfault0 r-a-sfault1 r-a-sfault2 r-a-sfault3
                       r-a-sfault4 r-a-sfault5 r-a-sfault6 r-a-sfault7 r-a-word0
                       r-a-word1 r-a-word2 r-a-word3 r-a-word4 r-a-word5
                       r-a-word6 r-a-word7 r-a-rslot0 r-a-rslot1 r-a-rslot2
                       r-a-rslot3 r-a-rslot4 r-a-rslot5 r-a-rslot6 r-a-rslot7)
                      (or (equal i-reset-n 1)
                          (joint-reset-p
                           r-p-lock-meta r-p-lock-sync r-p-cfb r-p-apprel
                           r-m-rel r-k-state-q r-k-pending-issued-q
                           r-k-pending-returned-q r-k-pending-read-pending-q
                           r-k-committed-prefix-q r-k-pending-layer-q
                           r-k-pending-position-q r-k-pending-key-exponents-q
                           r-k-pending-value-exponents-q
                           r-k-expected-coordinate-q r-k-pending-persisted-q
                           r-k-write-head-q r-k-write-word-q r-k-write-aborted-q
                           r-k-response-kind-q r-k-response-head-q
                           r-k-response-layer-q r-k-response-position-q
                           r-k-response-fault-q r-k-response-from-pending-q
                           r-k-read-word-q r-k-read-return-word-q
                           r-k-read-outstanding-q r-k-read-issue-done-q
                           r-k-read-aborted-q r-k-read-physical-kind-q
                           r-k-read-epoch-q r-k-read-received-mask-q
                           r-k-cache-valid-q r-k-cache-kind-q r-k-cache-layer-q
                           r-k-cache-position-q r-k-cache-tag-epoch-q
                           r-k-cache-epoch-q r-k-cache-clear-seen-q
                           r-k-cache-issued-q r-k-cache-returned-q
                           r-k-cache-read-pending-q r-k-cache-copy-kind-q
                           r-k-lock-seen-q r-k-fault-q
                           r-k-stage-begin-consumed-q
                           r-k-stage-payload-consumed-q r-k-commit-consumed-q
                           r-k-attention-req-consumed-q r-b-crel r-b-arel
                           r-b-lock-meta r-b-lock-sync r-b-afc-meta r-b-afc-sync
                           r-b-cfa-meta r-b-cfa-sync r-b-fault r-b-lock-seen
                           r-b-clr-seen r-b-clr-pend r-b-clr-drained r-b-epoch
                           r-b-out r-b-mstall r-b-wstall r-b-wstallf r-b-rstall
                           r-q-wb r-q-wg r-q-full r-q-rb r-q-rg r-q-rs1 r-q-rs2
                           r-q-ws1 r-q-ws2 r-q-mv r-q-sf r-q-spf r-q-df r-q-st
                           r-q-md r-s-wb r-s-wg r-s-full r-s-rb r-s-rg r-s-rs1
                           r-s-rs2 r-s-ws1 r-s-ws2 r-s-mv r-s-sf r-s-spf r-s-df
                           r-s-st r-s-md r-q-mdw r-a-fault r-a-lock-seen
                           r-a-offer r-a-offer-write r-a-poison r-a-offer-slot
                           r-a-reserved r-a-unissued r-a-readcount r-a-head
                           r-a-tail r-a-issue r-a-rhead r-a-rtail r-a-kind0
                           r-a-kind1 r-a-kind2 r-a-kind3 r-a-kind4 r-a-kind5
                           r-a-kind6 r-a-kind7 r-a-epoch0 r-a-epoch1 r-a-epoch2
                           r-a-epoch3 r-a-epoch4 r-a-epoch5 r-a-epoch6
                           r-a-epoch7 r-a-reject0 r-a-reject1 r-a-reject2
                           r-a-reject3 r-a-reject4 r-a-reject5 r-a-reject6
                           r-a-reject7 r-a-done0 r-a-done1 r-a-done2 r-a-done3
                           r-a-done4 r-a-done5 r-a-done6 r-a-done7 r-a-sfault0
                           r-a-sfault1 r-a-sfault2 r-a-sfault3 r-a-sfault4
                           r-a-sfault5 r-a-sfault6 r-a-sfault7 r-a-word0
                           r-a-word1 r-a-word2 r-a-word3 r-a-word4 r-a-word5
                           r-a-word6 r-a-word7))
                      (joint-env-p
                       h-arbfail h-shellterm h-shellfail h-layerfail h-auth
                       h-mcdc h-kupf h-layer h-position h-kexp h-vexp h-sbegin
                       h-spayload h-index h-key h-value h-commit h-attn
                       h-attn-kind h-attn-pos h-attn-head h-attn-ready h-epready
                       h-eprspv h-eprsperr h-eprspdata h-rspdata h-appup h-legal
                       r-q-mv r-a-readcount))
                  (pay-inv-p r-k-state-q r-k-write-word-q r-k-write-head-q r-k-write-aborted-q r-k-pending-persisted-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q r-k-offer r-k-rd0 r-k-rd1 r-k-rd2 r-k-rd3 r-k-rd4 r-k-rd5 r-k-rd6 r-k-rd7 r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-q-wb r-q-rb r-q-mv r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-mdp r-q-memd0 r-q-memd1 r-q-memd2 r-q-memd3 r-q-memd4 r-q-memd5 r-q-memd6 r-q-memd7 r-q-mdd r-q-memw0 r-q-memw1 r-q-memw2 r-q-memw3 r-q-memw4 r-q-memw5 r-q-memw6 r-q-memw7 r-q-mdw r-a-reserved r-a-head r-a-offer r-a-saddr r-a-sdata r-a-oaddr r-a-odata))
      :concl (rec-step-all h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
      :no-lemmas t
      :hints (("Goal" :use ((:instance rec-step-svtv-thm))
               :in-theory '(rec-step-all)))))
  (value-triple (acl2::cw "~%REC-STEP-FOLDED proved~%")))

; The same about any cycle of any execution of (probe-fsm).
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event '(def-svtv-to-fsm-thm rec-step-fsm-thm
                 :svtv-spec-thmname rec-step-svtv-thm-folded
                 :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%REC-STEP-FSM proved~%")))

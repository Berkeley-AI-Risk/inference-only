; The write path's payload: the step lemma lifted to every cycle of every execution.
;
; Written by make_payload_book.py; do not edit.  Private.
;
; A book of its own, so that the symbolic lemma (kv-write-payload-lemma,
; about an hour and a half) is not proved again when only this changes.
; Exports
;   pay-step-fsm-thm    in any execution of (probe-fsm), a cycle that starts
;                       in the joined invariant and the payload invariant,
;                       under the environment, ends in the payload invariant,
;                       and on that cycle the lemma's facts hold
(in-package "SV")
(include-book "kv-write-payload-lemma")
(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
(acl2::set-rewrite-stack-limit 20000)

; The lemma's whole conclusion as one predicate.  The library's lift works
; through the conclusion's conjuncts one at a time, each at a cost that grows
; with the number of named signals; with the lemma's eighty conjuncts left
; apart it would take about a day, and with one it takes under an hour.
(define pay-step-all (h-epready h-key h-spayload h-value i-clear n-a-head n-a-oaddr n-a-odata n-a-offer n-a-reserved n-a-saddr n-a-sdata n-a-unissued n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-offer n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-persisted-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-mdd n-q-mdp n-q-mdw n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mv n-q-rb n-q-wb o-epaddr o-epdata o-epf o-epv o-epw o-pfn o-spl o-spr o-tpf o-wlegal o-wreqaddr o-wreqdata o-wreqr o-wreqv r-a-head r-a-offer r-a-saddr r-a-unissued r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-persisted-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-mv r-q-rb r-q-wb)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and (pay-int-o-pfn o-pfn)
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
       (pay-int-n-a-odata n-a-odata)
       (pay-step-concl h-epready h-key h-spayload h-value i-clear n-a-head n-a-oaddr n-a-odata n-a-offer n-a-reserved n-a-saddr n-a-sdata n-a-unissued n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-offer n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-persisted-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-mdd n-q-mdp n-q-mdw n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mv n-q-rb n-q-wb o-epaddr o-epdata o-epf o-epv o-epw o-pfn o-spl o-spr o-tpf o-wlegal o-wreqaddr o-wreqdata o-wreqr o-wreqv r-a-head r-a-offer r-a-saddr r-a-unissued r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-persisted-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-mv r-q-rb r-q-wb)))
(in-theory (disable pay-step-all))

; The lemma again, with that conclusion.  It is the lemma itself: the proof
; only opens the definition above.
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm pay-step-svtv-thm-folded
      :svtv payload-step-run
      :svtv-spec payload-step-spec
      :input-vars :all
      :output-vars (o-pfn o-tpf o-epf o-wreqv o-wreqr o-wreqaddr o-wreqdata o-epv o-epw o-epaddr o-epdata o-spr o-spl o-wlegal n-k-state-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-pending-persisted-q n-k-write-head-q n-k-write-word-q n-k-write-aborted-q n-q-wb n-q-rb n-q-mv n-q-mdw n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-a-offer n-a-reserved n-a-unissued n-a-head n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-offer n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-mdd n-q-mdp n-a-saddr n-a-sdata n-a-oaddr n-a-odata)
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
      :concl (pay-step-all h-epready h-key h-spayload h-value i-clear n-a-head n-a-oaddr n-a-odata n-a-offer n-a-reserved n-a-saddr n-a-sdata n-a-unissued n-k-bank0 n-k-bank1 n-k-bank2 n-k-bank3 n-k-bank4 n-k-bank5 n-k-bank6 n-k-bank7 n-k-offer n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-persisted-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-rd0 n-k-rd1 n-k-rd2 n-k-rd3 n-k-rd4 n-k-rd5 n-k-rd6 n-k-rd7 n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q n-q-mdd n-q-mdp n-q-mdw n-q-memd0 n-q-memd1 n-q-memd2 n-q-memd3 n-q-memd4 n-q-memd5 n-q-memd6 n-q-memd7 n-q-memp0 n-q-memp1 n-q-memp2 n-q-memp3 n-q-memp4 n-q-memp5 n-q-memp6 n-q-memp7 n-q-memw0 n-q-memw1 n-q-memw2 n-q-memw3 n-q-memw4 n-q-memw5 n-q-memw6 n-q-memw7 n-q-mv n-q-rb n-q-wb o-epaddr o-epdata o-epf o-epv o-epw o-pfn o-spl o-spr o-tpf o-wlegal o-wreqaddr o-wreqdata o-wreqr o-wreqv r-a-head r-a-offer r-a-saddr r-a-unissued r-k-bank0 r-k-bank1 r-k-bank2 r-k-bank3 r-k-bank4 r-k-bank5 r-k-bank6 r-k-bank7 r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-persisted-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q r-q-memp0 r-q-memp1 r-q-memp2 r-q-memp3 r-q-memp4 r-q-memp5 r-q-memp6 r-q-memp7 r-q-mv r-q-rb r-q-wb)
      :no-lemmas t
      :hints (("Goal" :use ((:instance pay-step-svtv-thm))
               :in-theory '(pay-step-all)))))
  (value-triple (acl2::cw "~%PAY-STEP-FOLDED proved~%")))

; The same about any cycle of any execution of (probe-fsm).
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event '(def-svtv-to-fsm-thm pay-step-fsm-thm
                 :svtv-spec-thmname pay-step-svtv-thm-folded
                 :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%PAY-STEP-FSM proved~%")))

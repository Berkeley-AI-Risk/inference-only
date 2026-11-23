; The K/V write record: two more facts about one cycle.
;
; Written by make_record_book.py; do not edit.  Private.
;
; This book imports the certified write-payload book on the SAT-checked
; parent (../kv-write-payload-checked-parent) and proves two more facts of
; the same symbolic cycle, payload-step-run, from the same hypotheses: the
; joined control invariant, the payload invariant and the environment in
; one cycle.  The payload book's facts are about one row.  These two say how
; the controller moves through a whole record:
;   rec-fact-entry   a write state that is not interrupted, other than the
;                    record's start, is entered only from such a state, in a
;                    cycle without CLEAR, on the same row or by the one step
;                    from the K row's word 8 to the V row's word 0, which
;                    leaves the record's layer, position and exponents alone
;   rec-fact-start   the record's start is entered only from staging, by the
;                    acceptance of the beat for coordinate 127
;   rec-step-svtv-thm  both, of one symbolic cycle (kv-write-record-lift.lisp
;                    lifts it to every cycle of every execution)
; The RTL, the translation, the step run and its named signals are the
; imported book's; nothing is read from disk here.
(in-package "SV")
(include-book "../kv-write-payload-checked-parent/kv-write-payload")

(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
; The library's generated lemmas about a run with several hundred named
; signals nest deeper than the rewriter's default limit of 1000.
(acl2::set-rewrite-stack-limit 20000)

; The SAT solver, as in the payload book.  No answer of the solver is
; believed: with :lrat-check t the library reports "unsatisfiable" only
; after ACL2 has run its verified checker (projects/sat/lrat) on the proof
; the solver wrote, against the formula ACL2 itself wrote; "satisfiable"
; only after ACL2 has evaluated the formula under the assignment.
(defun rec-satlink-config ()
  (declare (xargs :guard t))
  (satlink::make-config :cmdline "sh sat/cadical-lrat.sh" :verbose nil
                        :mintime 0 :remove-temps t :lrat-check t))
(defthm kv-write-record-sat-proofs-are-checked
  (equal (satlink::config->lrat-check (rec-satlink-config)) t)
  :rule-classes nil)
(defattach fgl::fgl-satlink-config rec-satlink-config)
(value-triple (acl2::tshell-ensure))

; A write state that is not interrupted, other than the record's start, is
; entered only from a write state that is not interrupted, in a cycle
; without CLEAR: either on the same row, or by the one step that changes
; row, from the wait on word 8 of the K row to the first prefetch of word 0
; of the V row, and that step leaves the record's layer, position and
; exponent bytes as they were.
(define rec-fact-entry (i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "rec-fact-entry"
  (or (not (and (pay-writing-p (pay-u n-k-state-q)) (equal (pay-u n-k-write-aborted-q) 0)
                  (not (and (equal (pay-u n-k-state-q) 9) (equal (pay-u n-k-write-head-q) 0) (equal (pay-u n-k-write-word-q) 0)))))
      (and (pay-writing-p r-k-state-q) (equal r-k-write-aborted-q 0) (equal i-clear 0)
           (or (equal (pay-u n-k-write-head-q) r-k-write-head-q)
               (and (equal r-k-state-q 3) (equal r-k-write-head-q 0) (equal r-k-write-word-q 8)
                    (equal (pay-u n-k-state-q) 9) (equal (pay-u n-k-write-head-q) 1) (equal (pay-u n-k-write-word-q) 0)
                    (equal (pay-u n-k-pending-layer-q) r-k-pending-layer-q) (equal (pay-u n-k-pending-position-q) r-k-pending-position-q)
                    (equal (pay-u n-k-pending-key-exponents-q) r-k-pending-key-exponents-q) (equal (pay-u n-k-pending-value-exponents-q) r-k-pending-value-exponents-q)))))))
; The record's start, the first prefetch of word 0 of the K row, is entered
; only from staging, by the acceptance of the beat for coordinate 127, in a
; cycle without CLEAR, and it starts not interrupted.
(define rec-fact-start (h-spayload i-clear n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-spl o-spr r-k-expected-coordinate-q r-k-state-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "rec-fact-start"
  (or (not (and (equal (pay-u n-k-state-q) 9) (equal (pay-u n-k-write-head-q) 0) (equal (pay-u n-k-write-word-q) 0)))
      (and (equal r-k-state-q 1) (equal (if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0) 1) (equal r-k-expected-coordinate-q 127)
           (equal (pay-u n-k-write-aborted-q) 0) (equal i-clear 0)))))
(in-theory (disable rec-fact-entry rec-fact-start))

; THE CONCLUSION of the new step lemma: with no protocol violation by the
; client and no malformed metadata word from the endpoint in the cycle
; (the antecedent of the payload step lemma), both facts.
(define rec-step-concl (h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (if (and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))
      (and (rec-fact-entry i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q)
           (rec-fact-start h-spayload i-clear n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-spl o-spr r-k-expected-coordinate-q r-k-state-q))
    t))
(in-theory (disable rec-step-concl))

; ===========================================================================
; The step lemma for one symbolic cycle.  Each predicate above hands its
; body to the SAT solver on its own, under the antecedent.  The integer
; predicates pay-int-... are the payload book's.
; ===========================================================================
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm rec-step-svtv-thm
     :svtv payload-step-run
     :svtv-spec payload-step-spec
     :input-vars :all
     :output-vars (o-pfn o-tpf o-epf o-spr o-spl n-k-state-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-key-exponents-q n-k-pending-value-exponents-q n-k-write-head-q n-k-write-word-q n-k-write-aborted-q)
     :unsigned-byte-hyps t
     :no-integerp t
     :enable (pay-int-o-pfn-integerp pay-int-o-tpf-integerp pay-int-o-epf-integerp pay-int-o-spr-integerp pay-int-o-spl-integerp pay-int-n-k-state-q-integerp pay-int-n-k-pending-layer-q-integerp pay-int-n-k-pending-position-q-integerp pay-int-n-k-pending-key-exponents-q-integerp pay-int-n-k-pending-value-exponents-q-integerp pay-int-n-k-write-head-q-integerp pay-int-n-k-write-word-q-integerp pay-int-n-k-write-aborted-q-integerp)
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
     :concl (and (pay-int-o-pfn o-pfn)
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
          (rec-step-concl h-spayload i-clear n-k-pending-key-exponents-q n-k-pending-layer-q n-k-pending-position-q n-k-pending-value-exponents-q n-k-state-q n-k-write-aborted-q n-k-write-head-q n-k-write-word-q o-epf o-pfn o-spl o-spr o-tpf r-k-expected-coordinate-q r-k-pending-key-exponents-q r-k-pending-layer-q r-k-pending-position-q r-k-pending-value-exponents-q r-k-state-q r-k-write-aborted-q r-k-write-head-q r-k-write-word-q))))
  (value-triple (acl2::cw "~%REC-STEP-LEMMA proved~%")))

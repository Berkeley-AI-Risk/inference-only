; Print what was certified.  Input to ACL2, run by certify.sh from this
; directory after certification.  It loads the certified book and prints the
; exported theorems, the definitions their statements use, the stalled
; completion, and what the session rests on.  Lines that certify.sh looks
; for start KVJ-.
(include-book "kv-write-record")
(in-package "SV")
(acl2::set-slow-alist-action nil)

(acl2::cw "~%KVJ-STATEMENT the record theorem~%")
:pe kv-write-record
:pe kv-record-reported-complete-at
:pe kv-record-start
:pe kv-record-starts-at
:pe kv-record-uninterrupted
:pe kv-record-words
:pe kv-endpoint-writes
:pe kv-reset-held-at
:pe kv-payload-storage-definite-at
:pe kv-environment-ok-from

(acl2::cw "~%KVJ-STATEMENT the definitions under it~%")
:pe rec-complete-at
:pe rec-per-at
:pe rec-start
:pe rec-start-p
:pe rec-uninterrupted
:pe rec-live-p
:pe rec-clear-at
:pe rec-beat-at
:pe rec-coord-at
:pe rec-words-at
:pe rec-words
:pe rec-word
:pe pay-addr
:pe pay-data
:pe pay-log
:pe pay-ep-at
:pe pay-epwrite-at
:pe pay-st-at
:pe pay-h-at
:pe pay-w-at
:pe pay-ab-at
:pe pay-acc-at
:pe pay-accepted
:pe pay-writing-p

(acl2::cw "~%KVJ-STATEMENT a record that is being written, and one that CLEAR interrupts~%")
:pe kv-write-record-prefix
:pe kv-record-being-written-at
:pe kv-record-progress-at
:pe rec-progress-at
:pe kv-write-record-not-credited-when-interrupted
:pe kv-clear-at

(acl2::cw "~%KVJ-STATEMENT the two new facts about one cycle, and their lift~%")
:pe rec-fact-entry
:pe rec-fact-start
:pe rec-step-concl
:pe rec-step-all
:pe rec-step-fsm-thm

(acl2::cw "~%KVJ-STATEMENT the imported theorems~%")
:pe kv-write-payload-guarantee
:pe kv-write-payload-row
:pe kv-joined-guarantee
:pe kv-joined-sat-proofs-are-checked
:pe kv-joined-rtl-is-the-pinned-rtl
:pe kv-joined-rtl-was-translated-by-the-corrected-translator
(acl2::cw "~%KVJ-PIN RTL hashes equal the pinned list: ~x0~%"
          (equal *kvj-rtl-sha256-as-read* *kvj-rtl-sha256-pinned*))

(acl2::cw "~%KVJ-STATEMENT the stalled completion~%")
:pe kv-write-record-run-completes
:pe kv-write-record-run-was-stalled
:pe kv-write-record-run-is-the-record
(acl2::cw "~%KVJ-RUN ended ~x0 after ~x1 cycles: record start ~x2, V row start ~x3, completion edge ~x4~%"
          *rec-run-outcome* *rec-run-cycles* *rec-run-j* *rec-run-jv* *rec-run-n*)
(acl2::cw "~%KVJ-RUN refused ~x0 cycles, longest stall ~x1~%" *rec-run-refused* *rec-run-longest-stall*)
(acl2::cw "~%KVJ-RUN the writes (address data): ~x0~%" *rec-run-writes*)

(ld "book-records.lsp")
(ld "../acl2-pilot/nonblocking/library-report.lsp")
(acl2::cw "~%KVJ-DONE~%")

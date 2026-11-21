; Print what the negative control established.  Input to ACL2, run by
; certify.sh from this directory after certification, in a session of its
; own: this book and kv-write-record give the same names to two designs.
(include-book "kv-write-record-mismatched-rows")
(in-package "SV")
(acl2::set-slow-alist-action nil)

(acl2::cw "~%KVJ-STATEMENT the RTL read~%")
:pe kv-write-record-mismatched-rows-rtl-is-the-pinned-rtl
:pe kv-write-record-mismatched-rows-rtl-was-translated-by-the-corrected-translator
(acl2::cw "~%KVJ-STATEMENT the run~%")
:pe kv-write-record-mismatched-rows-run-completes
:pe kv-write-record-mismatched-rows-each-row-alone-passes
:pe kv-write-record-mismatched-rows-run-is-not-one-record
(acl2::cw "~%KVJ-RUN ended ~x0 after ~x1 cycles: record start ~x2, V row start ~x3, completion edge ~x4~%"
          *rec-run-outcome* *rec-run-cycles* *rec-run-j* *rec-run-jv* *rec-run-n*)
(acl2::cw "~%KVJ-RUN the writes (address data): ~x0~%" *rec-run-writes*)

(defun kvj-theorems-present (names state)
  (declare (xargs :mode :program :stobjs state))
  (cond ((atom names) state)
        (t (let ((co (standard-co state)))
             (pprogn (princ$ "KVJ-THEOREM " co state)
                     (princ$ (symbol-name (car names)) co state)
                     (princ$ (if (acl2::getpropc (car names) 'acl2::theorem nil (w state))
                                 ": in the certified book"
                               ": MISSING")
                             co state)
                     (newline co state)
                     (kvj-theorems-present (cdr names) state))))))
(pprogn (newline (standard-co state) state)
        (kvj-theorems-present
         '(kv-write-record-mismatched-rows-run-completes
           kv-write-record-mismatched-rows-each-row-alone-passes
           kv-write-record-mismatched-rows-run-is-not-one-record)
         state))
; The new step lemma must not be there: its proof is the one that has to fail.
(pprogn (newline (standard-co state) state)
        (princ$ "KVJ-ABSENT REC-STEP-SVTV-THM: " (standard-co state) state)
        (princ$ (if (acl2::getpropc 'rec-step-svtv-thm 'acl2::theorem nil (w state))
                    "PRESENT"
                  "not a theorem of this book")
                (standard-co state) state)
        (newline (standard-co state) state))
(acl2::cw "~%KVJ-PIN RTL hashes equal the pinned list: ~x0~%"
          (equal *kvj-rtl-sha256-as-read* *kvj-rtl-sha256-pinned*))
(ld "book-records.lsp")
(ld "../acl2-pilot/nonblocking/library-report.lsp")
(acl2::cw "~%KVJ-DONE~%")

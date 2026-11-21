; What ACL2 recorded for each book of this directory that the session has
; loaded, and what the session does with the SAT solver's answers.  Input to
; ACL2, read with ld by statement.lsp and
; statement-mismatched-rows.lsp.  One line per book, starting KVJ-BOOK, printed
; with princ$ so that no line is broken (cw breaks long lines, and certify.sh
; looks for these).
;
; ACL2 keeps, for every book a session includes, whether its certificate
; records a skipped proof or an axiom, and the certificate's check value; the
; check value is absent when the book was loaded without a valid certificate.
(in-package "SV")

(defun kvj-book-records (alist state)
  (declare (xargs :mode :program :stobjs state))
  (cond ((atom alist) state)
        ((or (acl2::search "kv-joined" (caddr (car alist))) (acl2::search "kv-write-" (caddr (car alist))))
         (let ((co (standard-co state))
               (notes (cadddr (car alist))))
           (pprogn (princ$ "KVJ-BOOK " co state)
                   (princ$ (caddr (car alist)) co state)
                   (princ$ ": skipped proofs " co state)
                   (princ$ (if (cdr (assoc-eq :skipped-proofsp notes)) "T" "NIL") co state)
                   (princ$ ", axioms " co state)
                   (princ$ (if (cdr (assoc-eq :axiomsp notes)) "T" "NIL") co state)
                   (princ$ ", certified " co state)
                   (princ$ (if (cddddr (car alist)) "T" "NIL") co state)
                   (newline co state)
                   (kvj-book-records (cdr alist) state))))
        (t (kvj-book-records (cdr alist) state))))

(acl2::cw "~%KVJ-STATEMENT what ACL2 recorded for each book~%")
(pprogn (newline (standard-co state) state)
        (kvj-book-records (acl2::global-val 'acl2::include-book-alist-all (w state)) state))

; Which imported books were loaded: the file each book of the joined control
; proof and of the write-payload proof came from, as ACL2 recorded it.
; certify.sh requires them to be in ../kv-joined-book-checked-sat and
; ../kv-write-payload-checked-parent.
(defun kvj-parent-files (alist state)
  (declare (xargs :mode :program :stobjs state))
  (cond ((atom alist) state)
        ((or (acl2::search "kv-joined" (caddr (car alist)))
             (acl2::search "kv-write-payload" (caddr (car alist))))
         (let ((co (standard-co state))
               (full (car (car alist))))
           (pprogn (princ$ "KVJ-PARENT " co state)
                   (princ$ (caddr (car alist)) co state)
                   (princ$ " loaded from " co state)
                   (princ$ (cond ((stringp full) full)
                                 ((and (consp full) (stringp (cdr full))) (cdr full))
                                 (t "?"))
                           co state)
                   (newline co state)
                   (kvj-parent-files (cdr alist) state))))
        (t (kvj-parent-files (cdr alist) state))))

(acl2::cw "~%KVJ-STATEMENT which parent was loaded~%")
(pprogn (newline (standard-co state) state)
        (kvj-parent-files (acl2::global-val 'acl2::include-book-alist-all (w state)) state))

; What the session does with the SAT solver's answers: the settings that
; fgl::fgl-satlink-config returns here, which is what the books attached.
(acl2::cw "~%KVJ-STATEMENT what is done with the SAT solver's answers~%")
:pe kv-write-record-sat-proofs-are-checked
(pprogn (newline (standard-co state) state)
        (princ$ "KVJ-SAT command in effect: " (standard-co state) state)
        (princ$ (satlink::config->cmdline (fgl::fgl-satlink-config)) (standard-co state) state)
        (newline (standard-co state) state)
        (princ$ "KVJ-SAT proof check in effect: " (standard-co state) state)
        (princ$ (if (satlink::config->lrat-check (fgl::fgl-satlink-config)) "T" "NIL")
                (standard-co state) state)
        (newline (standard-co state) state))

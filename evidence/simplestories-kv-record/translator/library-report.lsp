; Report what the current ACL2 session rests on.  Load it at the ACL2 prompt:
;
;   (ld "/path/to/nonblocking/library-report.lsp")
;
; It prints, for the session as it stands at that point:
;   - the directory the system books were taken from;
;   - how many books were loaded, local ones included, and which of them were
;     loaded without a valid certificate (ACL2 records no hash for those);
;   - whether any skip-proofs or redefinition has been seen in this session;
;   - the trust tags active, each of which marks code ACL2 does not check;
;   - the length and write date ACL2 recorded for the translator's source
;     file svstmt-compile.lisp, which identify the copy that was loaded.
; It does not detect code loaded in raw Lisp outside the ACL2 loop; that is
; visible only in the session's input.
(in-package "ACL2")

(defun bct-lib-uncertified (alist)
  ; entries are (full-name user-name familiar-name annotations . hash)
  (declare (xargs :mode :program))
  (cond ((atom alist) nil)
        ((cddddr (car alist)) (bct-lib-uncertified (cdr alist)))
        (t (cons (caar alist) (bct-lib-uncertified (cdr alist))))))

(defun bct-lib-named (familiar alist)
  (declare (xargs :mode :program))
  (cond ((atom alist) nil)
        ((equal (caddr (car alist)) familiar)
         (cons (cons (caar alist) (cddddr (car alist)))
               (bct-lib-named familiar (cdr alist))))
        (t (bct-lib-named familiar (cdr alist)))))

; The directory is printed with princ$: cw breaks a line at 79 columns, and a
; long path would then not be found by the scripts that look for this line.
(pprogn (newline (standard-co state) state)
        (princ$ "BCT-LIB system books: " (standard-co state) state)
        (princ$ (cdr (assoc-eq :system (project-dir-alist (w state))))
                (standard-co state) state)
        (newline (standard-co state) state))

(let* ((wrld (w state))
       (alist (global-val 'include-book-alist-all wrld))
       (bad (bct-lib-uncertified alist)))
  (prog2$
   nil
   (prog2$
    (cw "~%BCT-LIB books loaded: ~x0~%" (len alist))
    (prog2$
     (cw "BCT-LIB loaded without a certificate: ~x0~%" (len bad))
     (prog2$
      (cw "BCT-LIB skip-proofs seen: ~x0~%"
          (if (global-val 'skip-proofs-seen wrld) t nil))
      (prog2$
       (cw "BCT-LIB redefinition seen: ~x0~%"
           (if (global-val 'redef-seen wrld) t nil))
       (prog2$
        (cw "BCT-LIB trust tags: ~x0~%" (len (global-val 'ttags-seen wrld)))
        (prog2$
         (cw "BCT-LIB-DETAIL uncertified: ~x0~%" bad)
         (prog2$
          (cw "BCT-LIB-DETAIL trust tags: ~x0~%"
              (strip-cars (global-val 'ttags-seen wrld)))
          (cw "BCT-LIB-DETAIL svstmt-compile: ~x0~%"
              (bct-lib-named "svstmt-compile" alist)))))))))))

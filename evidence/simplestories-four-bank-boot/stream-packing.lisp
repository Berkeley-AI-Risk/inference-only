(in-package "SV")
(include-book "stream-source")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor packing-glcp))
(local (gl::gl-bdd-mode))

(defun packing-stream (old) (loghead 6 (ifix old)))
(defun packing-byte (old) (loghead 5 (logtail 6 (ifix old))))
(defun packing-word (old) (loghead 18 (logtail 11 (ifix old))))
(defun packing-buffer (old) (loghead 248 (logtail 29 (ifix old))))
(defun packing-slow-fault (old) (loghead 1 (logtail 277 (ifix old))))
(defun packing-build (stream byte word buffer slow-fault)
  (logapp 6 (ifix stream) (logapp 5 (ifix byte) (logapp 18 (ifix word)
    (logapp 248 (ifix buffer) (loghead 1 (ifix slow-fault)))))))

; Replace three cut inputs from the earlier control proof with the actual
; pre-edge owner counters and the FIFO's pre-edge ready output.
(defun packing-event (old event fifo-ready)
  (logapp 10 (ifix event) (logapp 1 (ifix fifo-ready) (logapp 1 (logtail 11 (ifix event))
    (logapp 5 (packing-byte old) (logapp 18 (packing-word old) (logtail 35 (ifix event))))))))

(defconst *packing-fields*
  '(("byte_q" . 5) ("word_q" . 18) ("word_buffer_q" . 248) ("slow_fault_q" . 1)))
(defconst *packing-reg-equations*
  (stream-expand-sampled (flash-drivers *packing-fields* *stream-assigns*)))

; write_valid_i is not a wire alias: its own source driver gates the parent's
; fifo_write_valid with the old registered slow fault. Retain that driver.
(defconst *packing-fifo-valid-lhs* '((:var ("u_loader_cdc" . "write_valid_i") . 0)))
(defconst *packing-ready-rhs* (cdr (assoc-equal "qspi_data_ready" *stream-expanded-gates*)))
(defconst *packing-data-rhs* (car (flash-drivers '(("fifo_write_data" . 256)) *stream-assigns*)))
(defun packing-inline (rhs gates)
  (with-fast-alist gates (svex-compose rhs gates)))
(defconst *packing-valid-rhs*
  (let ((entry (assoc-equal *packing-fifo-valid-lhs* *stream-assigns*))
        (gates *stream-expanded-gates*))
    (if (not entry) (er hard? 'packing-pin "Missing child write_valid_i driver")
      (packing-inline (svex-call 'concat (list 1 (driver->value (cdr entry)) 0)) gates))))

(defun packing-env (old event fifo-ready data)
  (let* ((names '(("word_buffer_q" . 248) ("slow_fault_q" . 1) ("qspi_data" . 8)))
         (values (list (packing-buffer old) (packing-slow-fault old) (loghead 8 (ifix data)))))
    (append (pairlis$ (strip-cars names) values) (flash-old-fields names values)
            (stream-env (packing-stream old) (packing-event old event fifo-ready)))))

; This evaluator is logically svexlist-eval. GL verifies the two-valued
; masks before using one symbolic Boolean per bit in these source drivers.
(defconst *packing-symbolic-params*
  (let ((keys (strip-cars (packing-env 0 0 0 0))))
    (list (cons :vars keys) (cons :simplify t)
          (cons :boolmasks (pairlis$ keys (repeat (len keys) -1))))))

(assert-event
 (let ((pairs (module->aliaspairs *owner-stream*)) (keys (strip-cars (packing-env 0 0 0 0))))
   (and (subsetp-equal
         '((((:var ("u_fixed_read" . "data_valid_o") . 0)) "qspi_data_valid")
           (((:var ("u_fixed_read" . "data_ready_i") . 0)) "qspi_data_ready")
           (((8 :var ("u_fixed_read" . "data_o") . 0)) (8 . "qspi_data"))
           (((:var ("u_fixed_read" . "data_last_o") . 0)) "qspi_data_last")
           (((256 :var ("u_loader_cdc" . "write_data_i") . 0)) (256 . "fifo_write_data"))
           (((:var ("u_loader_cdc" . "write_ready_o") . 0)) "fifo_write_ready")
           (((:var ("u_loader_cdc" . "write_clk_i") . 0)) "trusted_clk_i")
           (((:var ("u_loader_cdc" . "write_reset_n_i") . 0)) "trusted_reset_n_i"))
         pairs)
        (not (assoc-equal '("qspi_data_valid") *stream-assigns*))
        (not (assoc-equal '((8 . "qspi_data")) *stream-assigns*))
        (not (assoc-equal '("fifo_write_ready") *stream-assigns*))
        (no-duplicatesp-equal keys)
        (subsetp-equal (svexlist-vars *packing-reg-equations*) keys)
        (subsetp-equal (svexlist-vars (list *packing-ready-rhs* *packing-valid-rhs* *packing-data-rhs*)) keys))))

(defun packing-pins (old event fifo-ready data)
  (let* ((env (packing-env old event fifo-ready data))
         (pins (with-fast-alist env
                 (svexlist-eval-for-symbolic (list *packing-ready-rhs* *packing-valid-rhs* *packing-data-rhs*)
                                             env *packing-symbolic-params*))))
    (list (cdr (assoc-equal "qspi_data_valid" env)) (first pins)
          (cdr (assoc-equal "qspi_data" env)) (second pins) (third pins))))

(defun packing-raw (old event fifo-ready data)
  (let ((env (packing-env old event fifo-ready data)))
    (with-fast-alist env (svexlist-eval-for-symbolic *packing-reg-equations* env *packing-symbolic-params*))))
(defun packing-edge (old event fifo-ready data)
  (let ((extra (packing-raw old event fifo-ready data)))
    (packing-build (stream-edge (packing-stream old) (packing-event old event fifo-ready))
                   (first extra) (second extra) (third extra) (fourth extra))))

(defun packing-reader-ready-p (old fifo-ready)
  (and (equal (stream-state (packing-stream old)) 2)
       (or (not (equal (packing-byte old) 31)) (equal fifo-ready 1))))
(defun packing-accept-p (old event fifo-ready)
  (and (stream-rise-p event) (not (stream-trusted-reset-p event))
       (logbitp 8 (ifix event)) (packing-reader-ready-p old fifo-ready)))
(defun packing-spec-pins (old event fifo-ready data)
  (let ((valid (logbitp 8 (ifix event))) (st (stream-state (packing-stream old))))
    (list (if valid 1 0) (if (packing-reader-ready-p old fifo-ready) 1 0) data
          (if (and valid (equal st 2) (equal (packing-byte old) 31) (equal (packing-slow-fault old) 0)) 1 0)
          (logapp 248 (packing-buffer old) data))))

(defun packing-insert-byte (buffer byte data)
  (let ((offset (* 8 (nfix byte))))
    (logapp offset (ifix buffer) (logapp 8 (ifix data) (logtail (+ 8 offset) (ifix buffer))))))
(defun packing-last-p (old) (and (equal (packing-byte old) 31) (equal (packing-word old) 227061)))
(defun packing-fault-guard-p (old event fifo-ready)
  (let* ((s (packing-stream old)) (st (stream-state s)) (valid (logbitp 8 (ifix event)))
         (progress (or (equal (stream-start s) 1) (and valid (packing-reader-ready-p old fifo-ready)))))
    (or (logbitp 6 (ifix event)) (logbitp 11 (ifix event))
        (and (not (equal st 0)) (equal (stream-up2 s) 0))
        (and (equal st 2) (not (logbitp 7 (ifix event))) (equal (stream-start s) 0) (not valid))
        (and (not (equal st 3)) (not (equal st 7)) (not progress)
             (equal (loghead 25 (logtail 35 (ifix event))) 24999999)))))

; The pre-edge handshakes above are independent of this controller's fault
; priority. On a simultaneous fault or wrong LAST, the counters/buffer hold,
; even when the FIFO has just accepted the complete 32-byte word.
(defun packing-next-state (old event fifo-ready)
  (let ((st (stream-state (packing-stream old))))
    (cond ((stream-trusted-reset-p event) 0)
          ((not (stream-rise-p event)) st)
          ((packing-fault-guard-p old event fifo-ready) 7)
          ((equal st 0) (stream-up2 (packing-stream old)))
          ((equal st 1) 2)
          ((equal st 2)
           (cond ((not (packing-accept-p old event fifo-ready)) 2)
                 ((not (iff (logbitp 9 (ifix event)) (packing-last-p old))) 7)
                 ((packing-last-p old) 3)
                 (t 2)))
          ((equal st 3) 3)
          (t 7))))

(defun packing-spec-edge (old event fifo-ready data)
  (let* ((s (packing-stream old)) (st (stream-state s)) (byte (packing-byte old))
         (word (packing-word old)) (buf (packing-buffer old)) (next (packing-next-state old event fifo-ready))
         (reset (stream-trusted-reset-p event)) (rise (stream-rise-p event))
         (issue (and (not reset) rise (equal st 1) (equal next 2)))
         (clear (or reset issue))
         (commit (and (packing-accept-p old event fifo-ready) (not (equal next 7))))
         (boundary (and commit (equal byte 31)))
         (up1 (cond ((stream-app-reset-p event) 0) (rise 1) (t (stream-up1 s))))
         (up2 (cond ((stream-app-reset-p event) 0) (rise (stream-up1 s)) (t (stream-up2 s))))
         (start (cond (reset 0) (rise (if issue 1 0)) (t (stream-start s)))))
    (packing-build (logapp 3 next (logapp 1 start (logapp 1 up1 up2)))
      (cond ((or clear boundary) 0) (commit (+ 1 byte)) (t byte))
      (cond (clear 0) ((and boundary (not (packing-last-p old))) (+ 1 word)) (t word))
      (cond ((or clear boundary) 0) (commit (packing-insert-byte buf byte data)) (t buf))
      (cond (reset 0) ((and rise (equal next 7)) 1) (t (packing-slow-fault old))))))

(gl::def-gl-thm packing-source-step-law
  :hyp (and (unsigned-byte-p 278 old) (unsigned-byte-p 60 event)
            (unsigned-byte-p 1 fifo-ready) (unsigned-byte-p 8 data))
  :concl (and (equal (packing-pins old event fifo-ready data)
                     (packing-spec-pins old event fifo-ready data))
              (equal (packing-edge old event fifo-ready data)
                     (packing-spec-edge old event fifo-ready data))
              (let ((new (packing-edge old event fifo-ready data)))
                (and (unsigned-byte-p 278 new)
                     (equal (packing-stream new)
                            (stream-edge (packing-stream old) (packing-event old event fifo-ready)))
                     (equal (packing-raw old event fifo-ready data)
                            (list (packing-byte new) (packing-word new)
                                  (packing-buffer new) (packing-slow-fault new))))))
  :g-bindings (gl::auto-bindings (:nat event 60) (:nat fifo-ready 1) (:nat old 278) (:nat data 8))
  :rule-classes nil)

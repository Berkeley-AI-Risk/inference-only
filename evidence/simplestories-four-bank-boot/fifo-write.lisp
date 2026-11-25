(in-package "SV")
(include-book "stream-source")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor fifo-write-glcp))
(local (gl::gl-bdd-mode))

(defconst *fifo-write-module*
  (cdr (assoc-equal (cdr (assoc-equal "u_loader_cdc" (module->insts *owner-stream*)))
                    (design->modalist *owner-design*))))
(defconst *fifo-write-assigns* (module->assigns *fifo-write-module*))
(assert-event
 (and (equal (cdr (assoc-equal "u_loader_cdc" (module->insts *owner-stream*)))
             "board1_qspi_async_word_fifo4")
      (subsetp-equal
       '((((:var ("u_loader_cdc" . "write_clk_i") . 0)) "trusted_clk_i")
         (((:var ("u_loader_cdc" . "write_reset_n_i") . 0)) "trusted_reset_n_i")
         (((256 :var ("u_loader_cdc" . "write_data_i") . 0)) (256 . "fifo_write_data"))
         (((:var ("u_loader_cdc" . "write_ready_o") . 0)) "fifo_write_ready"))
       (module->aliaspairs *owner-stream*))
      (assoc-equal '((:var ("u_loader_cdc" . "write_valid_i") . 0)) *stream-assigns*)
      (not (assoc-equal '("fifo_write_ready") *stream-assigns*))
      (no-duplicatesp-equal (strip-cars *fifo-write-assigns*))
      (equal (module->aliaspairs *fifo-write-module*)
             '((((1024 . "storage_q")) (1024 :var ("storage_q" . :self) . 0))))))

; Inline all combinational gates sampled by these three write-domain drivers.
(defconst *fifo-write-gates*
  (stream-compose-gates '(("write_ready_o" . 1) ("write_transfer" . 1)
                          ("write_binary_next" . 3) ("write_gray_next" . 3) ("write_full_next" . 1))
                        *fifo-write-assigns* nil))
(defconst *fifo-write-equations*
  (let ((gates (stream-sampled-gates *fifo-write-gates*)))
    (with-fast-alist gates
      (svexlist-compose
       (flash-drivers '(("write_binary_q" . 3) ("write_full_q" . 1) ("storage_q" . 1024))
                      *fifo-write-assigns*)
       gates))))

(defun fifo-write-env (pointer full memory read-gray data valid event)
  (let* ((level (loghead 1 (logtail 5 (ifix event))))
         (fields '(("write_binary_q" . 3) ("write_full_q" . 1) ("storage_q" . 1024)
                   ("read_gray_write_sync2_q" . 3) ("write_data_i" . 256) ("write_valid_i" . 1)))
         (values (list pointer full memory read-gray data valid)))
    (append (list (cons "write_clk_i" (if (stream-rise-p event) 1 level))
                  (cons (flash-prev-key "write_clk_i") (if (stream-rise-p event) 0 level))
                  (cons "write_reset_n_i" (stream-current-trusted-reset-n event))
                  (cons (flash-prev-key "write_reset_n_i") (stream-previous-trusted-reset-n event)))
            (pairlis$ (strip-cars fields) values)
            (flash-old-fields fields values))))

(defconst *fifo-write-ready-equation* (cdr (assoc-equal "write_ready_o" *fifo-write-gates*)))
(defconst *fifo-write-transfer-equation* (cdr (assoc-equal "write_transfer" *fifo-write-gates*)))
(assert-event
 (and (no-duplicatesp-equal (strip-cars (fifo-write-env 0 0 0 0 0 0 0)))
      (subsetp-equal (svexlist-vars *fifo-write-equations*)
                     (strip-cars (fifo-write-env 0 0 0 0 0 0 0)))
      (set-equiv (svex-vars *fifo-write-ready-equation*) '("write_full_q"))
      (set-equiv (svex-vars *fifo-write-transfer-equation*) '("write_valid_i" "write_full_q"))))

(defun fifo-write-ready (full)
  (let ((env (list (cons "write_full_q" full))))
    (with-fast-alist env (svex-eval *fifo-write-ready-equation* env))))

; A sampled write_transfer on a trusted rising edge under released write reset.
; This is independent of whether the selected old and new words compare equal.
(defun fifo-write-strobe-p (full valid event)
  (let ((env (list (cons "write_full_q" full) (cons "write_valid_i" valid))))
    (and (stream-rise-p event) (equal (stream-current-trusted-reset-n event) 1)
         (equal (with-fast-alist env (svex-eval *fifo-write-transfer-equation* env)) 1))))

(defun fifo-write-edge (pointer full memory read-gray data valid event)
  (let ((env (fifo-write-env pointer full memory read-gray data valid event)))
    (with-fast-alist env (svexlist-eval *fifo-write-equations* env))))

; In storage_q[0:3] each word is [255:0]; VL places element 3 at offset 0.
(defun fifo-slot-offset (slot) (* 256 (- 3 (loghead 2 (ifix slot)))))
(defun fifo-slot (slot memory) (loghead 256 (logtail (fifo-slot-offset slot) (ifix memory))))
(defun fifo-write-memory (slot data memory)
  (let ((offset (fifo-slot-offset slot)))
    (logapp offset (ifix memory)
            (logapp 256 (ifix data) (logtail (+ 256 offset) (ifix memory))))))

(gl::def-gl-thm fifo-write-source-law
  :hyp (and (unsigned-byte-p 3 pointer) (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory)
            (unsigned-byte-p 3 read-gray) (unsigned-byte-p 256 data) (unsigned-byte-p 1 valid)
            (unsigned-byte-p 60 event))
  :concl
  (let* ((next (fifo-write-edge pointer full memory read-gray data valid event))
         (write (fifo-write-strobe-p full valid event))
         (advanced (loghead 3 (+ pointer (if write 1 0)))))
    (and (equal (fifo-write-ready full) (if (equal full 0) 1 0))
         (iff write (and (stream-rise-p event) (equal (stream-current-trusted-reset-n event) 1)
                         (equal full 0) (equal valid 1)))
         (unsigned-byte-p 3 (nth 0 next)) (unsigned-byte-p 1 (nth 1 next))
         (unsigned-byte-p 1024 (nth 2 next))
         (equal (nth 0 next) (if (stream-trusted-reset-p event) 0 advanced))
         (equal (nth 1 next)
                (cond ((stream-trusted-reset-p event) 0)
                      ((stream-rise-p event)
                       (if (equal (logxor advanced (ash advanced -1)) (logxor 6 read-gray)) 1 0))
                      (t full)))
         (equal (nth 2 next)
                (if write (fifo-write-memory (loghead 2 pointer) data memory) memory))))
  :g-bindings (gl::auto-bindings (:nat event 60) (:nat full 1) (:nat valid 1) (:nat pointer 3)
                                 (:nat read-gray 3) (:nat memory 1024) (:nat data 256))
  :rule-classes nil)

(gl::def-gl-thm fifo-write-memory-slot
  :hyp (and (unsigned-byte-p 2 slot) (unsigned-byte-p 2 observed) (unsigned-byte-p 256 data)
            (unsigned-byte-p 1024 memory))
  :concl (equal (fifo-slot observed (fifo-write-memory slot data memory))
                (if (equal observed slot) data (fifo-slot observed memory)))
  :g-bindings (gl::auto-bindings (:nat slot 2) (:nat observed 2) (:nat memory 1024) (:nat data 256))
  :rule-classes nil)

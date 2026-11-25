(in-package "SV")

(include-book "opcode")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor stream-glcp))
(local (gl::gl-bdd-mode))

; (depends-on "board1_context2048_qspi_image_stream.sv")
; (depends-on "board1_context2048_qspi_read03_master.sv")
; (depends-on "board1_qspi_async_word_fifo4.sv")
(defconsts (*owner-design* state)
  (b* (((mv (vl::vl-loadresult src) state)
        (vl::vl-load
         (vl::make-vl-loadconfig
          :start-files '("board1_context2048_qspi_image_stream.sv"
                         "board1_context2048_qspi_read03_master.sv"
                         "board1_qspi_async_word_fifo4.sv")
          :defines (vl::vl-add-define "SYNTHESIS"
                     (vl::make-vl-define :formals nil :body "1" :loc vl::*vl-fakeloc*) nil))))
       ((mv err design & &)
        (vl::vl-design->sv-design "board1_context2048_qspi_image_stream"
                                  src.design (vl::make-vl-simpconfig))))
    (and err (er hard? 'owner-design "VL translation failed: ~x0" err))
    (mv design state)))

(defconst *owner-stream*
  (cdr (assoc-equal "board1_context2048_qspi_image_stream" (design->modalist *owner-design*))))
(defconst *stream-assigns* (module->assigns *owner-stream*))
(defconst *stream-fields*
  '(("state_q" . 3) ("qspi_start_q" . 1) ("app_up_slow_sync1_q" . 1) ("app_up_slow_sync2_q" . 1)))

; Source leaves that may vary on each event. The byte, word and watchdog
; counters, child and FIFO status, and fault synchronizer are unconstrained
; old binary values. The owner state, start, and app-up stages are threaded.
(defconst *stream-status-fields*
  '(("qspi_fault" . 1) ("qspi_busy" . 1) ("qspi_data_valid" . 1) ("qspi_data_last" . 1)
    ("fifo_write_ready" . 1) ("app_fault_slow_sync2_q" . 1)
    ("byte_q" . 5) ("word_q" . 18) ("watchdog_q" . 25)))

; Inline each combinational driver into its consumers before representing the
; sampled wire in the register equation. All replacements still refer to the
; same old source registers and status bits. The final dependency assertion
; rejects any missing guard, out-of-order substitution, or new source input.
(defconst *stream-gates*
  '(("qspi_data_ready" . 1) ("qspi_transfer" . 1)
    ("fifo_write_valid" . 1) ("fifo_write_transfer" . 1)
    ("slow_progress" . 1) ("watchdog_active" . 1) ("watchdog_trip" . 1)
    ("qspi_idle_protocol_fault" . 1) ("slow_x_fault" . 1)))

(defun stream-compose-gates (gates assigns env)
  (if (endp gates) env
    (let* ((rhs (car (flash-drivers (list (car gates)) assigns)))
           (expanded (with-fast-alist env (svex-compose rhs env))))
      (stream-compose-gates (cdr gates) assigns (acons (caar gates) expanded env)))))

(defun stream-sampled-gates (gates)
  (if (endp gates) nil
    (acons (flash-prev-key (caar gates)) (cdar gates) (stream-sampled-gates (cdr gates)))))

(defconst *stream-expanded-gates* (stream-compose-gates *stream-gates* *stream-assigns* nil))
(defconst *stream-sampled-gate-equations* (stream-sampled-gates *stream-expanded-gates*))
(defun stream-expand-sampled (equations)
  (let ((gates *stream-sampled-gate-equations*))
    (with-fast-alist gates (svexlist-compose equations gates))))
(defconst *stream-equations*
  (stream-expand-sampled (flash-drivers *stream-fields* *stream-assigns*)))

(defun stream-state (old) (loghead 3 (ifix old)))
(defun stream-start (old) (loghead 1 (logtail 3 (ifix old))))
(defun stream-up1 (old) (loghead 1 (logtail 4 (ifix old))))
(defun stream-up2 (old) (loghead 1 (logtail 5 (ifix old))))

; On a trusted rising edge both resets are held at their current values. On
; a stationary clock (low or high) either reset may assert or release. This
; includes simultaneous reset changes but excludes reset changes exactly at
; a rising edge. Other input samples are binary and refer to pre-edge time.
(defun stream-rise-p (event) (logbitp 0 (ifix event)))
(defun stream-current-trusted-reset-n (event) (loghead 1 (logtail 1 (ifix event))))
(defun stream-current-app-reset-n (event) (loghead 1 (logtail 2 (ifix event))))
(defun stream-previous-trusted-reset-n (event)
  (if (stream-rise-p event) (stream-current-trusted-reset-n event)
    (loghead 1 (logtail 3 (ifix event)))))
(defun stream-previous-app-reset-n (event)
  (if (stream-rise-p event) (stream-current-app-reset-n event)
    (loghead 1 (logtail 4 (ifix event)))))
(defun stream-trusted-reset-p (event)
  (and (equal (stream-current-trusted-reset-n event) 0)
       (or (stream-rise-p event) (equal (stream-previous-trusted-reset-n event) 1))))
(defun stream-app-reset-p (event)
  (and (equal (stream-current-app-reset-n event) 0)
       (or (stream-rise-p event) (equal (stream-previous-app-reset-n event) 1))))

(defun stream-env (old event)
  (let* ((old-regs (flash-unpack *stream-fields* old))
         (status (flash-unpack *stream-status-fields* (logtail 6 (ifix event))))
         (level (loghead 1 (logtail 5 (ifix event)))))
    (append (list (cons "trusted_clk_i" (if (stream-rise-p event) 1 level))
                  (cons (flash-prev-key "trusted_clk_i") (if (stream-rise-p event) 0 level))
                  (cons "trusted_reset_n_i" (stream-current-trusted-reset-n event))
                  (cons (flash-prev-key "trusted_reset_n_i") (stream-previous-trusted-reset-n event))
                  (cons "app_reset_n_i" (stream-current-app-reset-n event))
                  (cons (flash-prev-key "app_reset_n_i") (stream-previous-app-reset-n event)))
            (pairlis$ (strip-cars *stream-fields*) old-regs)
            (pairlis$ (strip-cars *stream-status-fields*) status)
            (flash-old-fields *stream-fields* old-regs)
            (flash-old-fields *stream-status-fields* status))))

(assert-event
 (and (no-duplicatesp-equal (strip-cars *stream-assigns*))
      (no-duplicatesp-equal (strip-cars (stream-env 0 0)))
      (subsetp-equal (svexlist-vars *stream-equations*) (strip-cars (stream-env 0 0)))))

(defun stream-edge (old event)
  (let* ((env (stream-env old event))
         (regs (with-fast-alist env (svexlist-eval *stream-equations* env))))
    (logapp 3 (ifix (nth 0 regs))
            (logapp 1 (ifix (nth 1 regs)) (logapp 1 (ifix (nth 2 regs)) (ifix (nth 3 regs)))))))

(gl::def-gl-thm stream-owner-step-law
  :hyp (and (unsigned-byte-p 6 old) (unsigned-byte-p 60 event))
  :concl
  (let* ((new (stream-edge old event)) (st (stream-state old))
         (next (stream-state new)) (start (stream-start new)))
    (and (unsigned-byte-p 6 new)
         (cond ((stream-app-reset-p event) (and (equal (stream-up1 new) 0) (equal (stream-up2 new) 0)))
               ((stream-rise-p event) (and (equal (stream-up1 new) 1)
                                           (equal (stream-up2 new) (stream-up1 old))))
               (t (and (equal (stream-up1 new) (stream-up1 old))
                       (equal (stream-up2 new) (stream-up2 old)))))
         (cond ((stream-trusted-reset-p event) (and (equal next 0) (equal start 0)))
               ((not (stream-rise-p event)) (and (equal next st) (equal start (stream-start old))))
               ((equal st 0) (and (member-equal next '(0 1 7)) (equal start 0)
                                  (implies (equal next 1) (equal (stream-up2 old) 1))))
               ((equal st 1) (or (and (equal next 7) (equal start 0))
                                 (and (equal next 2) (equal start 1) (equal (stream-up2 old) 1))))
               ((equal st 2) (and (member-equal next '(2 3 7)) (equal start 0)))
               ((equal st 3) (and (member-equal next '(3 7)) (equal start 0)))
               (t (and (equal next 7) (equal start 0))))))
  :g-bindings (gl::auto-bindings (:nat old 6) (:nat event 60))
  :rule-classes nil)

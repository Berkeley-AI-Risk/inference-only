(in-package "SV")
(include-book "stream-source")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor boot-reader-glcp))
(local (gl::gl-bdd-mode))

; These are actual VL aliases. The hierarchical reader has the same assignments
; as the separately translated leaf used by every-flash-select-fall-starts-the-command.
(assert-event
 (let* ((leaf (cdr (assoc-equal "board1_context2048_qspi_read03_master"
                                (design->modalist *owner-design*))))
        (pairs (module->aliaspairs *owner-stream*)))
   (and (equal (cdr (assoc-equal "u_fixed_read" (module->insts *owner-stream*)))
               "board1_context2048_qspi_read03_master")
        (equal (module->assigns leaf) *flash-assigns*)
        (not (module->insts leaf)) (not (module->aliaspairs leaf))
        (not (assoc-equal '("qspi_cs_n_o") *stream-assigns*))
        (not (assoc-equal '("qspi_sck_o") *stream-assigns*))
        (subsetp-equal
         '((((:var ("u_fixed_read" . "clk_i") . 0)) "trusted_clk_i")
           (((:var ("u_fixed_read" . "reset_n_i") . 0)) "internal_reset_n")
           (((:var ("u_fixed_read" . "start_i") . 0)) "qspi_start_q")
           (((:var ("u_fixed_read" . "busy_o") . 0)) "qspi_busy")
           (((:var ("u_fixed_read" . "fault_o") . 0)) "qspi_fault")
           (((:var ("u_fixed_read" . "data_valid_o") . 0)) "qspi_data_valid")
           (((:var ("u_fixed_read" . "data_ready_i") . 0)) "qspi_data_ready")
           (((8 :var ("u_fixed_read" . "data_o") . 0)) (8 . "qspi_data"))
           (((:var ("u_fixed_read" . "data_last_o") . 0)) "qspi_data_last")
           (((:var ("u_fixed_read" . "qspi_cs_n_o") . 0)) "qspi_cs_n_o")
           (((:var ("u_fixed_read" . "qspi_sck_o") . 0)) "qspi_sck_o")
           (((:var ("u_fixed_read" . "qspi_dq1_i") . 0)) ("qspi_dq_i" . 1))
           (((4 :var ("u_fixed_read" . "qspi_dq_o") . 0)) (4 . "qspi_dq_o"))
           (((4 :var ("u_fixed_read" . "qspi_dq_oe_o") . 0)) (4 . "qspi_dq_oe_o")))
         pairs))))

(defconst *boot-reader-reset-equation*
  (car (flash-drivers '(("internal_reset_n" . 1)) *stream-assigns*)))
(defconst *boot-reader-fault-equations*
  (stream-expand-sampled (flash-drivers '(("slow_fault_q" . 1) ("app_fault_slow_sync2_q" . 1))
                                        *stream-assigns*)))
(defconst *boot-reader-ready-equation*
  (cdr (assoc-equal "qspi_data_ready" *stream-expanded-gates*)))

; EXTRA b0 slow_fault_q, b1 app_fault_slow_sync1_q, b2 external DQ1,
; b3:5 old data_bit_q, b6:29 old bytes_remaining_q. This header projection
; permits fresh binary cut values on successive stream events. Old VALID/LAST
; and app_fault_slow_sync2_q are shared with the owner's own event.
(defun boot-reader-fault-env (stream event extra)
  (acons (flash-prev-key "slow_fault_q") (loghead 1 (ifix extra))
    (acons (flash-prev-key "app_fault_slow_sync1_q") (loghead 1 (logtail 1 (ifix extra)))
           (stream-env stream event))))

(defun boot-reader-reset-env (trusted-n slow-fault app-fault)
  (list (cons "trusted_reset_n_i" trusted-n) (cons "slow_fault_q" slow-fault)
        (cons "app_fault_slow_sync2_q" app-fault)))

(assert-event
 (and (set-equiv (svex-vars *boot-reader-reset-equation*) (strip-cars (boot-reader-reset-env 0 0 0)))
      (subsetp-equal (svex-vars *boot-reader-ready-equation*) (strip-cars (stream-env 0 0)))
      (no-duplicatesp-equal (strip-cars (boot-reader-fault-env 0 0 0)))
      (subsetp-equal (svexlist-vars *boot-reader-fault-equations*)
                     (strip-cars (boot-reader-fault-env 0 0 0)))))

(defun boot-reader-reset-n (trusted-n slow-fault app-fault)
  (let ((env (boot-reader-reset-env trusted-n slow-fault app-fault)))
    (with-fast-alist env (svex-eval *boot-reader-reset-equation* env))))

(gl::def-gl-thm boot-reader-released-reset-is-source-authorized
  :hyp (and (unsigned-byte-p 1 trusted-n) (unsigned-byte-p 1 slow-fault)
            (unsigned-byte-p 1 app-fault))
  :concl (equal (boot-reader-reset-n trusted-n slow-fault app-fault)
                (if (and (equal trusted-n 1) (equal slow-fault 0) (equal app-fault 0)) 1 0))
  :g-bindings (gl::auto-bindings (:nat trusted-n 1) (:nat slow-fault 1) (:nat app-fault 1))
  :rule-classes nil)

(defun boot-reader-old-reset-n (event extra)
  (boot-reader-reset-n (stream-previous-trusted-reset-n event) (loghead 1 (ifix extra))
                       (loghead 1 (logtail 11 (ifix event)))))
(defun boot-reader-pre-reset-n (event extra)
  (boot-reader-reset-n (stream-current-trusted-reset-n event) (loghead 1 (ifix extra))
                       (loghead 1 (logtail 11 (ifix event)))))
(defun boot-reader-post-reset-n (stream event extra)
  (let* ((env (boot-reader-fault-env stream event extra))
         (faults (with-fast-alist env (svexlist-eval *boot-reader-fault-equations* env))))
    (boot-reader-reset-n (stream-current-trusted-reset-n event) (first faults) (second faults))))

(defun boot-reader-tail (stream event extra)
  (let* ((env (stream-env stream event))
         (ready (with-fast-alist env (svex-eval *boot-reader-ready-equation* env))))
    (logapp 1 (ifix ready)
            (logapp 1 (logtail 2 (ifix extra))
                    (logapp 2 (logtail 8 (ifix event)) (loghead 27 (logtail 3 (ifix extra))))))))

; NIL means no sensitivity-list edge; the numeric event 0 is a clock edge
; under asserted reset. The first microstep samples old owner and fault Qs.
; The second is a stationary-clock reset assertion if newly registered faults
; pull internal_reset_n low after the first edge's nonblocking updates.
(defun boot-reader-async-raw (event)
  (+ (ash 1 33) (if (or (stream-rise-p event) (logbitp 5 (ifix event))) (ash 1 34) 0)))
(defun boot-reader-clock-raw (stream event extra)
  (logapp 1 (ifix (boot-reader-pre-reset-n event extra))
          (logapp 1 (stream-start stream) (boot-reader-tail stream event extra))))
(defun boot-reader-first-raw (stream event extra)
  (cond ((stream-rise-p event) (boot-reader-clock-raw stream event extra))
        ((and (equal (boot-reader-old-reset-n event extra) 1)
              (equal (boot-reader-pre-reset-n event extra) 0))
         (boot-reader-async-raw event))
        (t nil)))
(defun boot-reader-settle-raw (stream event extra)
  (and (equal (boot-reader-pre-reset-n event extra) 1)
       (equal (boot-reader-post-reset-n stream event extra) 0)
       (boot-reader-async-raw event)))

(defun boot-reader-pack (fields regs)
  (if (endp fields) 0
    (logapp (cdar fields) (ifix (car regs)) (boot-reader-pack (cdr fields) (cdr regs)))))
(defun boot-reader-cs (regs) (loghead 1 (logtail 42 (ifix regs))))
(defun boot-reader-leaf-step (regs raw)
  (if raw
      (boot-reader-pack *flash-fields* (flash-edge (flash-unpack *flash-fields* regs) raw))
    regs))

(gl::def-gl-thm boot-reader-leaf-projection
  :hyp (and (unsigned-byte-p 52 regs) (unsigned-byte-p 35 raw))
  :concl (let ((old-header (flash-unpack *flash-fields* regs))
               (new (boot-reader-leaf-step regs raw)))
           (and (unsigned-byte-p 52 new)
                (equal (flash-unpack *flash-fields* new) (flash-edge old-header raw))
                (equal (nth 5 old-header) (boot-reader-cs regs))
                (equal (nth 5 (flash-edge old-header raw)) (boot-reader-cs new))
                (implies (or (logbitp 33 raw) (not (logbitp 0 raw)))
                         (equal (flash-unpack *flash-fields* new) '(0 0 0 0 0 1 0 12 0)))))
  :g-bindings (gl::auto-bindings (:nat regs 52) (:nat raw 35)) :rule-classes nil)

(defun boot-reader-middle (regs stream event extra)
  (boot-reader-leaf-step regs (boot-reader-first-raw stream event extra)))
(defun boot-reader-step (regs stream event extra)
  (boot-reader-leaf-step (boot-reader-middle regs stream event extra)
                         (boot-reader-settle-raw stream event extra)))
(defun boot-reader-fell (old new)
  (and (equal (boot-reader-cs old) 1) (equal (boot-reader-cs new) 0)))
(defun boot-reader-fall-p (regs stream event extra)
  (let ((middle (boot-reader-middle regs stream event extra)))
    (or (boot-reader-fell regs middle)
        (boot-reader-fell middle (boot-reader-step regs stream event extra)))))

; Apply the original #29 selection theorem to the same old registers and the
; same constructed event. Neither an asynchronous reset nor an idle microstep
; can create a falling CS. A genuine fall may be transient before settling.
(local (defthm boot-reader-one-fall
  (implies (and (unsigned-byte-p 52 regs) (unsigned-byte-p 35 raw)
                (boot-reader-fell regs (boot-reader-leaf-step regs raw)))
           (and (not (logbitp 33 raw)) (logbitp 0 raw) (logbitp 1 raw)
                (equal (flash-unpack *flash-fields* (boot-reader-leaf-step regs raw))
                       (flash-command-regs 0))))
  :hints (("Goal" :use (boot-reader-leaf-projection
                        (:instance every-flash-select-fall-starts-the-command (old regs) (event raw)))
           :in-theory '(boot-reader-fell)))
  :rule-classes nil))

(local (gl::def-gl-thm boot-reader-clock-raw-law
  :hyp (and (unsigned-byte-p 6 stream) (unsigned-byte-p 60 event) (unsigned-byte-p 30 extra))
  :concl (let ((raw (boot-reader-clock-raw stream event extra)))
           (and (unsigned-byte-p 35 raw) (not (logbitp 33 raw))
                (implies (logbitp 0 raw)
                         (and (not (stream-trusted-reset-p event))
                              (equal (stream-current-trusted-reset-n event) 1)
                              (equal (boot-reader-pre-reset-n event extra) 1)))
                (iff (logbitp 1 raw) (equal (stream-start stream) 1))))
  :g-bindings (gl::auto-bindings (:nat stream 6) (:nat event 60) (:nat extra 30)) :rule-classes nil))

(local (gl::def-gl-thm boot-reader-async-raw-law
  :hyp (unsigned-byte-p 60 event)
  :concl (and (unsigned-byte-p 35 (boot-reader-async-raw event))
              (logbitp 33 (boot-reader-async-raw event)))
  :g-bindings (gl::auto-bindings (:nat event 60)) :rule-classes nil))

(defthm boot-reader-microstep-events
  (implies (and (unsigned-byte-p 6 stream) (unsigned-byte-p 60 event) (unsigned-byte-p 30 extra))
           (let ((first (boot-reader-first-raw stream event extra))
               (settle (boot-reader-settle-raw stream event extra)))
           (and (or (not first) (unsigned-byte-p 35 first))
                (or (not settle) (and (unsigned-byte-p 35 settle) (logbitp 33 settle)))
                (implies (and first (not (logbitp 33 first)) (logbitp 0 first) (logbitp 1 first))
                         (and (stream-rise-p event) (not (stream-trusted-reset-p event))
                              (equal (stream-current-trusted-reset-n event) 1)
                              (equal (boot-reader-pre-reset-n event extra) 1)
                              (equal (stream-start stream) 1))))))
  :hints (("Goal" :use (boot-reader-clock-raw-law boot-reader-async-raw-law)
           :in-theory '(boot-reader-first-raw boot-reader-settle-raw)))
  :rule-classes nil)

(local (defthm boot-reader-held-leaf-step
  (equal (boot-reader-leaf-step regs nil) regs)
  :hints (("Goal" :in-theory (enable boot-reader-leaf-step)))))

(local (defthm boot-reader-one-width
  (implies (and (unsigned-byte-p 52 regs) (or (not raw) (unsigned-byte-p 35 raw)))
           (unsigned-byte-p 52 (boot-reader-leaf-step regs raw)))
  :hints (("Goal" :cases (raw) :use boot-reader-leaf-projection
           :in-theory '(boot-reader-held-leaf-step)))))

(defthm boot-reader-step-width
  (implies (and (unsigned-byte-p 52 regs) (unsigned-byte-p 6 stream)
                (unsigned-byte-p 60 event) (unsigned-byte-p 30 extra))
           (unsigned-byte-p 52 (boot-reader-step regs stream event extra)))
  :hints (("Goal" :use boot-reader-microstep-events
           :in-theory '(boot-reader-step boot-reader-middle boot-reader-one-width)))
  :rule-classes nil)

(local (defthm boot-reader-fall-in-first-microstep
  (implies (and (unsigned-byte-p 52 regs) (unsigned-byte-p 6 stream)
                (unsigned-byte-p 60 event) (unsigned-byte-p 30 extra)
                (boot-reader-fall-p regs stream event extra))
           (let ((raw (boot-reader-first-raw stream event extra))
                 (middle (boot-reader-middle regs stream event extra)))
             (and raw (unsigned-byte-p 35 raw) (not (logbitp 33 raw)) (logbitp 0 raw) (logbitp 1 raw)
                  (boot-reader-fell regs middle)
                  (equal (flash-unpack *flash-fields* middle) (flash-command-regs 0)))))
  :hints (("Goal" :cases ((boot-reader-first-raw stream event extra)
                          (boot-reader-settle-raw stream event extra))
           :use (boot-reader-microstep-events
                 (:instance boot-reader-one-fall (raw (boot-reader-first-raw stream event extra)))
                 (:instance boot-reader-one-fall (regs (boot-reader-middle regs stream event extra))
                            (raw (boot-reader-settle-raw stream event extra))))
           :in-theory '(boot-reader-step boot-reader-middle boot-reader-fall-p
                        boot-reader-held-leaf-step boot-reader-one-width boot-reader-fell)))
  :rule-classes nil))

(defthm boot-reader-fall-requires-owner-pulse
  (implies (and (unsigned-byte-p 52 regs) (unsigned-byte-p 6 stream)
                (unsigned-byte-p 60 event) (unsigned-byte-p 30 extra)
                (boot-reader-fall-p regs stream event extra))
           (and (stream-rise-p event) (not (stream-trusted-reset-p event))
                (equal (stream-current-trusted-reset-n event) 1)
                (equal (boot-reader-pre-reset-n event extra) 1) (equal (stream-start stream) 1)))
  :hints (("Goal" :use (boot-reader-fall-in-first-microstep boot-reader-microstep-events)
           :in-theory nil))
  :rule-classes nil)

(defthm boot-reader-fall-enters-fixed-command
  (implies (and (unsigned-byte-p 52 regs) (unsigned-byte-p 6 stream)
                (unsigned-byte-p 60 event) (unsigned-byte-p 30 extra)
                (boot-reader-fall-p regs stream event extra))
           (let ((middle (boot-reader-middle regs stream event extra)))
             (and (boot-reader-fell regs middle)
                  (equal (flash-unpack *flash-fields* middle) (flash-command-regs 0)))))
  :hints (("Goal" :use boot-reader-fall-in-first-microstep :in-theory nil))
  :rule-classes nil)

(in-package "SV")

(include-book "centaur/vl/loader/top" :dir :system)
(include-book "centaur/sv/vl/top" :dir :system)
(include-book "oslib/ls" :dir :system)
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor flash-glcp))
(local (gl::gl-bdd-mode))

; (depends-on "reader-vl.sv")
(defconsts (*flash-design* state)
  (b* (((mv (vl::vl-loadresult src) state)
        (vl::vl-load
         (vl::make-vl-loadconfig
          :start-files '("reader-vl.sv")
          :defines (vl::vl-add-define "SYNTHESIS"
                     (vl::make-vl-define :formals nil :body "1" :loc vl::*vl-fakeloc*) nil))))
       ((mv err design & &)
        (vl::vl-design->sv-design "board1_context2048_qspi_read03_master"
                                 src.design (vl::make-vl-simpconfig))))
    (and err (er hard? 'flash-design "VL translation failed: ~x0" err))
    (mv design state)))

; Complete registered drivers for the command cone, including all four DQ and OE bits.
(defconst *flash-fields*
  '(("state_q" . 3) ("phase_high_q" . 1) ("edge_wait_q" . 1) ("transmit_shift_q" . 31)
    ("send_bits_left_q" . 6) ("qspi_cs_n_o" . 1) ("qspi_sck_o" . 1)
    ("qspi_dq_o" . 4) ("qspi_dq_oe_o" . 4)))

(defun flash-lhs (name width)
  (list (if (equal width 1) name (cons width name))))

(defun flash-drivers (fields assigns)
  (if (endp fields) nil
    (let* ((lhs (flash-lhs (caar fields) (cdar fields)))
           (entry (assoc-equal lhs assigns)))
      (if (not entry)
          (er hard? 'flash-drivers "Missing complete register driver: ~x0" lhs)
        ; Only the low width bits of an RHS drive this bounded LHS.
        (cons (svex-call 'concat (list (svex-quote (cdar fields)) (driver->value (cdr entry)) 0))
              (flash-drivers (cdr fields) assigns))))))

(defconst *flash-assigns*
  (module->assigns (cdr (assoc-equal "board1_context2048_qspi_read03_master"
                                    (design->modalist *flash-design*)))))
(defconst *flash-equations* (flash-drivers *flash-fields* *flash-assigns*))

(defun flash-lhss (fields)
  (if (endp fields) nil
    (cons (flash-lhs (caar fields) (cdar fields)) (flash-lhss (cdr fields)))))

(defun flash-prev-key (name) (make-svar :name name :delay 1))
(defun flash-old-fields (fields values)
  (if (endp fields) nil
    (acons (flash-prev-key (caar fields)) (car values)
           (flash-old-fields (cdr fields) (cdr values)))))

(defun flash-unpack (fields word)
  (if (endp fields) nil
    (cons (loghead (cdar fields) (ifix word))
          (flash-unpack (cdr fields) (logtail (cdar fields) (ifix word))))))

; Bits 4..32 allow unrelated physical register contents to vary on every transition.
; Bit 33 selects a falling reset edge on a stationary clock (level in bit 34).
; On a rising clock, reset is held at bit 0 through the edge.
(defun flash-inputs (event)
  (let* ((asynch (logbitp 33 (ifix event)))
         (clk (if (logbitp 34 (ifix event)) 1 0))
         (rst (loghead 1 (ifix event))))
    (list (cons "clk_i" (if asynch clk 1)) (cons (flash-prev-key "clk_i") (if asynch clk 0))
          (cons "reset_n_i" (if asynch 0 rst)) (cons (flash-prev-key "reset_n_i") (if asynch 1 rst))
          (cons (flash-prev-key "start_i") (loghead 1 (logtail 1 (ifix event))))
          (cons (flash-prev-key "data_ready_i") (loghead 1 (logtail 2 (ifix event))))
          (cons (flash-prev-key "qspi_dq1_i") (loghead 1 (logtail 3 (ifix event))))
          (cons (flash-prev-key "data_valid_o") (loghead 1 (logtail 4 (ifix event))))
          (cons (flash-prev-key "data_last_o") (loghead 1 (logtail 5 (ifix event))))
          (cons (flash-prev-key "data_bit_q") (loghead 3 (logtail 6 (ifix event))))
          (cons (flash-prev-key "bytes_remaining_q") (loghead 24 (logtail 9 (ifix event)))))))

; Check that every variable actually used by the source equations has an explicit
; binding, and that all selected assignments come from a leaf module.
(assert-event
 (let ((leaf (cdr (assoc-equal "board1_context2048_qspi_read03_master"
                               (design->modalist *flash-design*)))))
  (and (not (module->insts leaf)) (not (module->aliaspairs leaf))
      (no-duplicatesp-equal (strip-cars *flash-assigns*))
      (set-equiv (strip-cars *flash-assigns*)
                 (flash-lhss (append *flash-fields*
                             '(("bytes_remaining_q" . 24) ("data_bit_q" . 3)
                               ("data_shift_q" . 7) ("busy_o" . 1) ("fault_o" . 1)
                               ("data_valid_o" . 1) ("data_o" . 8) ("data_last_o" . 1)))))
      (subsetp-equal (svexlist-vars *flash-equations*)
                     (strip-cars (append (flash-inputs 0)
                                         (flash-old-fields *flash-fields* nil)))))))

(defun flash-edge (regs event)
  (let ((env (append (flash-inputs event) (flash-old-fields *flash-fields* regs))))
    (with-fast-alist env (svexlist-eval *flash-equations* env))))

(defun flash-abortp (event)
  (or (logbitp 33 (ifix event)) (not (logbitp 0 (ifix event))) (logbitp 1 (ifix event))))

; Age zero is the falling-CS edge. The transmitter shifts at ages 4, 8, ...;
; command sampling uses the preceding rising SCK, at ages 2, 6, ..., 30.
(defun flash-command-regs (age)
  (let* ((age (nfix age)) (bit-index (ash age -2)) (hi (loghead 1 (ash age -1))))
    (list 1 hi (loghead 1 age) (loghead 31 (ash #x03801000 bit-index))
          (- 32 bit-index) 0 hi
          (+ 12 (if (logbitp (nfix (- 31 bit-index)) #x03801000) 1 0)) 13)))

(gl::def-gl-thm every-flash-select-fall-starts-the-command
  :hyp (and (unsigned-byte-p 52 old) (unsigned-byte-p 35 event))
  :concl
  (let* ((regs (flash-unpack *flash-fields* old)) (next (flash-edge regs event)))
    (implies (and (equal (nth 5 regs) 1) (equal (nth 5 next) 0))
             (and (equal (nth 0 regs) 0) (not (logbitp 33 event))
                  (logbitp 0 event) (logbitp 1 event)
                  (equal next (flash-command-regs 0)))))
  :g-bindings (gl::auto-bindings (:nat event 35) (:nat old 52))
  :rule-classes nil)

(gl::def-gl-thm flash-command-source-advance-or-abort
  :hyp (and (unsigned-byte-p 5 age) (< age 30) (unsigned-byte-p 35 event))
  :concl
  (let ((next (flash-edge (flash-command-regs age) event)))
    (if (flash-abortp event)
        (and (equal (nth 5 next) 1) (equal (nth 6 next) 0) (equal (nth 8 next) 0))
      (equal next (flash-command-regs (+ 1 age)))))
  :g-bindings (gl::auto-bindings (:nat age 5) (:nat event 35))
  :rule-classes nil)

; Independent bus observer: first 8 active, driven rising SCK edges, MSB first.
; No assumptions about the spacing or values of these edges enter the observer.
(defun flash-read-byte (events regs kept accum)
  (if (atom events) nil
    (let ((next (flash-edge regs (car events))))
      (cond ((not (equal (nth 5 next) 0)) nil)
            ((and (equal (nth 6 regs) 0) (equal (nth 6 next) 1))
             (cond ((not (equal (loghead 1 (nth 8 next)) 1)) :undriven)
                   (t (let ((byte (+ (* 2 (nfix accum)) (loghead 1 (nth 7 next)))))
                        (if (equal kept 7) byte
                          (flash-read-byte (cdr events) next (+ 1 (nfix kept)) byte))))))
            (t (flash-read-byte (cdr events) next kept accum))))))

(defun flash-eventsp (events)
  (if (atom events) (equal events nil)
    (and (unsigned-byte-p 35 (car events)) (flash-eventsp (cdr events)))))

; Prove the 30 pending suffixes backwards. Every lemma unfolds one original
; edge, for all input histories including reset or attempted restart.
(defun flash-suffix-events (age previous)
  (declare (xargs :mode :program))
  (if (not (natp age)) nil
    (let* ((name (acl2::packn-pos (list 'flash-suffix- age) 'flash-suffix-))
           (regs (flash-command-regs age))
           (kept (ash (+ age 2) -2))
           (accum (ash 3 (- kept 8)))
           (call (list 'flash-read-byte 'events (list 'quote regs) kept accum)))
      (cons
       `(local
         (defthm ,name
           (implies (flash-eventsp events) (member-equal ,call '(nil 3)))
           :hints (("Goal" :cases ((consp events))
                    :expand ((flash-eventsp events) ,call)
                    :use ((:instance flash-command-source-advance-or-abort
                                     (age ,age) (event (car events)))
                          ,@(and previous `((:instance ,previous (events (cdr events))))))
                    :in-theory (disable flash-edge flash-read-byte flash-abortp flash-eventsp)))
           :rule-classes nil))
       (flash-suffix-events (1- age) name)))))

(make-event (cons 'progn (flash-suffix-events 29 nil)))

(defthm every-completed-board-flash-command-emits-read-03
  (let* ((regs (flash-unpack *flash-fields* old))
         (next (flash-edge regs select-event)))
    (implies (and (unsigned-byte-p 52 old) (unsigned-byte-p 35 select-event)
                  (flash-eventsp events)
                  (equal (nth 5 regs) 1) (equal (nth 5 next) 0))
             (member-equal (flash-read-byte events next 0 0) '(nil 3))))
  :hints (("Goal" :use ((:instance every-flash-select-fall-starts-the-command
                                   (event select-event))
                        (:instance flash-suffix-0))
           :in-theory (disable flash-edge flash-read-byte flash-eventsp flash-unpack)))
  :rule-classes nil)

(in-package "SV")
(include-book "serial")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor pin-reader-glcp))
(local (gl::gl-bdd-mode))

; Low 81 bits are the same header, remaining-length, VALID, LAST and bit
; index as extent-edge. Append the seven shift bits and the registered byte.
; Neither busy_o nor fault_o is an operand of these fifteen register drivers.
(defconst *pin-reader-fields* '(("data_shift_q" . 7) ("data_o" . 8)))
(defconst *pin-reader-equations* (flash-drivers *pin-reader-fields* *flash-assigns*))
(defun pin-reader-extent (reader) (loghead 81 (ifix reader)))
(defun pin-reader-shift (reader) (loghead 7 (logtail 81 (ifix reader))))
(defun pin-reader-octet (reader) (loghead 8 (logtail 88 (ifix reader))))
(defun pin-reader-valid-p (reader) (extent-valid (pin-reader-extent reader)))
(defun pin-reader-env (reader raw)
  (append (flash-inputs (extent-event (pin-reader-extent reader) raw))
          (flash-old-fields *flash-fields* (extent-header reader))
          (flash-old-fields *pin-reader-fields*
                            (list (pin-reader-shift reader) (pin-reader-octet reader)))))
(assert-event
 (and (no-duplicatesp-equal (strip-cars (pin-reader-env 0 0)))
      (subsetp-equal (svexlist-vars *pin-reader-equations*) (strip-cars (pin-reader-env 0 0)))))

(defun pin-reader-edge (reader raw)
  (if (not raw) reader
    (let* ((old (pin-reader-extent reader)) (env (pin-reader-env reader raw))
           (data (with-fast-alist env (svexlist-eval *pin-reader-equations* env))))
      (logapp 81 (extent-edge old raw) (extent-pack *pin-reader-fields* data)))))

(defun pin-reader-take-p (reader raw)
  (and raw (extent-takep (pin-reader-extent reader) raw)))
(defun pin-reader-dq1 (raw) (loghead 1 (logtail 3 (ifix raw))))

; Independent reference state. The only data bit consumed here is external
; DQ1 sampled on a selected pin-level low-to-high SCK edge with OE=1100.
; An accepted old byte empties the accumulator, as does chip deselection.
; Neither the DUT's shifter nor its bit index supplies any monitored data.
(defun pin-monitor-count (count selected rise take)
  (cond ((or (not selected) take) 0) (rise (1+ (nfix count))) (t count)))
(defun pin-monitor-bits (bits selected rise take dq1)
  (cond ((or (not selected) take) 0)
        (rise (loghead 8 (+ (ash (ifix bits) 1) (loghead 1 (ifix dq1))))) (t bits)))
(defun pin-reader-selected-p (reader) (equal (extent-cs (pin-reader-extent reader)) 0))
(defun pin-reader-rise-p (reader next)
  (serial-data-rise-p (pin-reader-extent reader) (pin-reader-extent next)))
(defun pin-reader-next-count (reader raw count)
  (let ((next (pin-reader-edge reader raw)))
    (pin-monitor-count count (pin-reader-selected-p next) (pin-reader-rise-p reader next)
                       (pin-reader-take-p reader raw))))
(defun pin-reader-next-bits (reader raw bits)
  (let ((next (pin-reader-edge reader raw)))
    (pin-monitor-bits bits (pin-reader-selected-p next) (pin-reader-rise-p reader next)
                      (pin-reader-take-p reader raw) (pin-reader-dq1 raw))))

(defun pin-reader-invariant (reader count bits)
  (let ((old (pin-reader-extent reader)))
    (and (unsigned-byte-p 96 reader) (unsigned-byte-p 4 count) (<= count 8)
         (unsigned-byte-p 8 bits) (unsigned-byte-p count bits)
         (if (pin-reader-selected-p reader)
             (and (serial-livep old) (equal count (serial-pending old))
                  (equal bits (if (extent-valid old) (pin-reader-octet reader)
                                (loghead count (pin-reader-shift reader)))))
           (and (member-equal (extent-state old) '(0 7)) (not (extent-valid old)) (equal count 0))))))

; Expose the source matching already used by the range proof, for the very same
; reader event. A NIL microstep holds the registers and observes no SCK rise.
(gl::def-gl-thm pin-reader-source-projection
  :hyp (and (unsigned-byte-p 96 reader) (unsigned-byte-p 35 raw))
  :concl (let ((next (pin-reader-edge reader raw)))
           (and (unsigned-byte-p 96 next)
                (equal (pin-reader-extent next) (extent-edge (pin-reader-extent reader) raw))
                (equal (pin-reader-rise-p reader next)
                       (serial-data-rise-p (pin-reader-extent reader) (extent-edge (pin-reader-extent reader) raw)))
                (equal (cdr (assoc-equal (flash-prev-key "qspi_dq1_i") (pin-reader-env reader raw)))
                       (pin-reader-dq1 raw))))
  :g-bindings (gl::auto-bindings (:nat reader 96) (:nat raw 35)) :rule-classes nil)

(gl::def-gl-thm pin-reader-reset
  :hyp (and (unsigned-byte-p 96 reader) (unsigned-byte-p 35 raw)
            (or (logbitp 33 raw) (not (logbitp 0 raw))))
  :concl (let ((next (pin-reader-edge reader raw)))
           (and (pin-reader-invariant next 0 0) (not (pin-reader-selected-p next))
                (not (pin-reader-valid-p next)) (not (pin-reader-rise-p reader next))
                (not (pin-reader-take-p reader raw))))
  :g-bindings (gl::auto-bindings (:nat reader 96) (:nat raw 35)) :rule-classes nil)

(gl::def-gl-thm pin-reader-numeric-step
  :hyp (and (pin-reader-invariant reader count bits) (unsigned-byte-p 35 raw))
  :concl (let ((next (pin-reader-edge reader raw)))
           (and (pin-reader-invariant next (pin-reader-next-count reader raw count)
                                     (pin-reader-next-bits reader raw bits))
                (implies (pin-reader-rise-p reader next) (not (pin-reader-take-p reader raw)))))
  :g-bindings (gl::auto-bindings (:nat reader 96) (:nat raw 35) (:nat count 4) (:nat bits 8))
  :rule-classes nil)

(gl::def-gl-thm pin-reader-held-step
  :hyp (pin-reader-invariant reader count bits)
  :concl (and (equal (pin-reader-edge reader nil) reader) (not (pin-reader-rise-p reader reader))
              (not (pin-reader-take-p reader nil))
              (equal (pin-reader-next-count reader nil count) count)
              (equal (pin-reader-next-bits reader nil bits) bits))
  :g-bindings (gl::auto-bindings (:nat reader 96) (:nat count 4) (:nat bits 8))
  :rule-classes nil)

(gl::def-gl-thm pin-reader-valid-byte-is-observed
  :hyp (pin-reader-invariant reader count bits)
  :concl (and (unsigned-byte-p 96 reader) (unsigned-byte-p 8 bits) (unsigned-byte-p 4 count)
              (implies (pin-reader-valid-p reader)
                       (and (pin-reader-selected-p reader) (equal count 8)
                            (equal (pin-reader-octet reader) bits))))
  :g-bindings (gl::auto-bindings (:nat reader 96) (:nat count 4) (:nat bits 8))
  :rule-classes nil)

(defthm pin-reader-source-step
  (implies (and (pin-reader-invariant reader count bits) (or (not raw) (unsigned-byte-p 35 raw)))
           (let ((next (pin-reader-edge reader raw)))
             (and (pin-reader-invariant next (pin-reader-next-count reader raw count)
                                       (pin-reader-next-bits reader raw bits))
                  (implies (pin-reader-rise-p reader next) (not (pin-reader-take-p reader raw)))
                  (implies (pin-reader-valid-p reader)
                           (and (pin-reader-selected-p reader) (equal count 8)
                                (equal (pin-reader-octet reader) bits))))))
  :hints (("Goal" :cases (raw)
           :use (pin-reader-numeric-step pin-reader-held-step pin-reader-valid-byte-is-observed)
           :in-theory nil))
  :rule-classes nil)

(defthm pin-reader-reset-forgets-prior-bits
  (implies (and (unsigned-byte-p 96 reader) (unsigned-byte-p 35 raw)
                (or (logbitp 33 raw) (not (logbitp 0 raw))))
           (and (equal (pin-reader-next-count reader raw count) 0)
                (equal (pin-reader-next-bits reader raw bits) 0)))
  :hints (("Goal" :use pin-reader-reset
           :in-theory '(pin-reader-next-count pin-reader-next-bits pin-monitor-count pin-monitor-bits)))
  :rule-classes nil)

; The last two physical reader registers are redundant on reachable states.
; Evaluate their actual next-value equations with explicit old BUSY/FAULT.
; Reset establishes the encoding even from arbitrary old values. Each
; subsequent clock, reset or held microstep preserves it.
(defconst *pin-reader-status-fields* '(("busy_o" . 1) ("fault_o" . 1)))
(defconst *pin-reader-status-equations* (flash-drivers *pin-reader-status-fields* *flash-assigns*))
(defun pin-reader-status-env (reader busy fault raw)
  (append (flash-old-fields *pin-reader-status-fields* (list busy fault)) (pin-reader-env reader raw)))
(assert-event
 (and (no-duplicatesp-equal (strip-cars (pin-reader-status-env 0 0 0 0)))
      (subsetp-equal (svexlist-vars *pin-reader-status-equations*)
                     (strip-cars (pin-reader-status-env 0 0 0 0)))
      (set-equiv (strip-cars *flash-assigns*)
                 (flash-lhss (append *flash-fields* *extent-extra-fields*
                                     *pin-reader-fields* *pin-reader-status-fields*)))))

(defun pin-reader-status-edge (reader busy fault raw)
  (if (not raw) (list busy fault)
    (let ((env (pin-reader-status-env reader busy fault raw)))
      (with-fast-alist env (svexlist-eval *pin-reader-status-equations* env)))))
(defun pin-reader-busy (reader) (if (equal (extent-cs reader) 0) 1 0))
(defun pin-reader-fault (reader) (if (equal (extent-state reader) 7) 1 0))
(defun pin-reader-status (reader) (list (pin-reader-busy reader) (pin-reader-fault reader)))

(gl::def-gl-thm pin-reader-source-status-reset
  :hyp (and (unsigned-byte-p 96 reader) (unsigned-byte-p 1 busy) (unsigned-byte-p 1 fault)
            (unsigned-byte-p 35 raw) (or (logbitp 33 raw) (not (logbitp 0 raw))))
  :concl (and (equal (pin-reader-status-edge reader busy fault raw) '(0 0))
              (equal (pin-reader-status (pin-reader-edge reader raw)) '(0 0)))
  :g-bindings (gl::auto-bindings (:nat reader 96) (:nat busy 1) (:nat fault 1) (:nat raw 35))
  :rule-classes nil)

(local (gl::def-gl-thm pin-reader-source-status-numeric
  :hyp (and (pin-reader-invariant reader count bits) (unsigned-byte-p 35 raw))
  :concl (equal (pin-reader-status-edge reader (pin-reader-busy reader) (pin-reader-fault reader) raw)
                (pin-reader-status (pin-reader-edge reader raw)))
  :g-bindings (gl::auto-bindings (:nat reader 96) (:nat count 4) (:nat bits 8) (:nat raw 35))
  :rule-classes nil))

(defthm pin-reader-source-status-step
  (implies (and (pin-reader-invariant reader count bits) (or (not raw) (unsigned-byte-p 35 raw)))
           (equal (pin-reader-status-edge reader (pin-reader-busy reader) (pin-reader-fault reader) raw)
                  (pin-reader-status (pin-reader-edge reader raw))))
  :hints (("Goal" :cases (raw) :use pin-reader-source-status-numeric :in-theory nil)
          ("Subgoal 2" :in-theory '(pin-reader-status-edge pin-reader-edge pin-reader-status)))
  :rule-classes nil)

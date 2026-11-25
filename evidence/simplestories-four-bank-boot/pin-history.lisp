(in-package "SV")
(include-book "pin-reader")
(include-book "pin-wiring")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor pin-history-glcp))
(local (gl::gl-bdd-mode))

(local (gl::def-gl-thm pin-packet-source-fields
  :hyp (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer) (unsigned-byte-p 1 full)
            (unsigned-byte-p 1024 memory) (unsigned-byte-p 71 input))
  :concl (let* ((next (packet-step owner pointer full memory input))
                (row (nth 4 next)) (ready (fifo-write-ready full))
                (pins (packing-pins owner (packet-event input) ready (packet-data input))))
           (and (unsigned-byte-p 1 ready) (unsigned-byte-p 278 (nth 0 next))
                (unsigned-byte-p 3 (nth 1 next)) (unsigned-byte-p 1 (nth 2 next))
                (unsigned-byte-p 1024 (nth 3 next))
                (equal (nth 0 next) (packing-edge owner (packet-event input) ready (packet-data input)))
                (equal (nth 1 row) (packet-accept-p pins (packet-event input)))
                (equal (nth 2 row) (packet-data input)) (consp (cddr row))))
  :g-bindings (gl::auto-bindings (:nat full 1) (:nat pointer 3) (:nat input 71)
                                 (:nat owner 278) (:nat memory 1024))
  :rule-classes nil))

; Advance the physical reader and the independent DQ1 observer across the
; sampled edge and the possible asynchronous reset after the registers settle.
(defun pin-two-phases (reader first settle count bits)
  (let ((middle (pin-reader-edge reader first))
        (mid-count (pin-reader-next-count reader first count))
        (mid-bits (pin-reader-next-bits reader first bits)))
    (list (pin-reader-edge middle settle)
          (pin-reader-next-count middle settle mid-count)
          (pin-reader-next-bits middle settle mid-bits))))

; A snapshot has the physical stream registers, FIFO pointer/full/RAM, reader
; registers, external clock/reset and synchronizer state, then the independent
; observer's count and DQ1 bits. The observer never feeds the hardware.
(defun pin-cycle (snapshot input)
  (let* ((owner (nth 0 snapshot)) (pointer (nth 1 snapshot)) (full (nth 2 snapshot))
         (memory (nth 3 snapshot)) (reader (nth 4 snapshot)) (meta (nth 5 snapshot))
         (extent (pin-reader-extent reader)) (octet (pin-reader-octet reader))
         (wires (pin-wiring-step owner extent octet (fifo-write-ready full) meta input))
         (packet-input (nth 0 wires)) (first (nth 1 wires)) (settle (nth 2 wires))
         (packet (packet-step owner pointer full memory packet-input))
         (observer (pin-two-phases reader first settle (nth 6 snapshot) (nth 7 snapshot))))
    (list (list (nth 0 packet) (nth 1 packet) (nth 2 packet) (nth 3 packet)
                (nth 0 observer) (nth 3 wires) (nth 1 observer) (nth 2 observer))
          packet-input (nth 4 packet) (pin-reader-take-p reader first))))

; On transfer the consumer row uses the independently shifted pins as its data.
; At all other times the registered data bus may retain an old byte.
(defun pin-storage-row (step bits)
  (let ((row (nth 2 step)))
    (if (nth 3 step)
        (cons (car row) (cons (cadr row) (cons bits (cdddr row))))
      row)))

(defun pin-snapshot-p (s)
  (and (unsigned-byte-p 278 (nth 0 s)) (unsigned-byte-p 3 (nth 1 s))
       (unsigned-byte-p 1 (nth 2 s)) (unsigned-byte-p 1024 (nth 3 s))
       (unsigned-byte-p 5 (nth 5 s))
       (pin-wiring-live-p (nth 0 s) (pin-reader-extent (nth 4 s)) (nth 5 s))
       (pin-reader-invariant (nth 4 s) (nth 6 s) (nth 7 s))))

(defun pin-external-inputs-p (inputs)
  (if (atom inputs) (equal inputs nil)
    (and (unsigned-byte-p 63 (car inputs)) (pin-external-inputs-p (cdr inputs)))))

(defun pin-packet-inputs (s inputs)
  (declare (xargs :measure (len inputs) :hints (("Goal" :in-theory (disable pin-cycle)))))
  (if (atom inputs) nil
    (let ((step (pin-cycle s (car inputs))))
      (cons (nth 1 step) (pin-packet-inputs (nth 0 step) (cdr inputs))))))

(defun pin-storage-rows (s inputs)
  (declare (xargs :measure (len inputs) :hints (("Goal" :in-theory (disable pin-cycle)))))
  (if (atom inputs) nil
    (let ((step (pin-cycle s (car inputs))))
      (cons (pin-storage-row step (nth 7 s))
            (pin-storage-rows (nth 0 step) (cdr inputs))))))

(defun pin-handshakes-correct-p (s inputs)
  (declare (xargs :measure (len inputs) :hints (("Goal" :in-theory (disable pin-cycle)))))
  (if (atom inputs) t
    (let* ((step (pin-cycle s (car inputs))) (take (nth 3 step)) (row (nth 2 step)))
      (and (iff take (nth 1 row))
           (implies take (and (equal (nth 6 s) 8) (equal (nth 7 s) (nth 2 row))))
           (pin-handshakes-correct-p (nth 0 step) (cdr inputs))))))

(local (defthm pin-nth-cons
  (equal (nth i (cons a tail)) (if (zp i) a (nth (1- i) tail)))
  :hints (("Goal" :expand (nth i (cons a tail))))))
(local (defthm pin-small-nths
  (and (equal (nth 0 a) (car a)) (equal (nth 1 a) (cadr a))
       (equal (nth 2 a) (caddr a)) (equal (nth 3 a) (cadddr a)))
  :hints (("Goal" :in-theory (enable nth)))))
(local (deftheory pin-list-theory
  (union-theories '(pin-nth-cons pin-small-nths (:executable-counterpart zp) (:executable-counterpart binary-+)
                    car-cons cdr-cons)
                  (theory 'minimal-theory))))

; A NIL raw event is an untriggered sensitivity list. Projection through the
; two microsteps therefore commutes with the 81-bit range and wiring proofs.
(local (defthm pin-idle-reader
  (equal (pin-reader-edge reader nil) reader)
  :hints (("Goal" :expand (pin-reader-edge reader nil)))))
(local (defthm pin-one-phase-projection
  (implies (and (unsigned-byte-p 96 reader) (or (not raw) (unsigned-byte-p 35 raw)))
           (and (unsigned-byte-p 96 (pin-reader-edge reader raw))
                (equal (pin-reader-extent (pin-reader-edge reader raw))
                       (pin-wiring-extent-microstep (pin-reader-extent reader) raw))))
  :hints (("Goal" :cases (raw) :use pin-reader-source-projection
           :in-theory '(pin-wiring-extent-microstep pin-idle-reader)))
  :rule-classes nil))

(local (gl::def-gl-thm pin-source-port-bounds
  :hyp (and (unsigned-byte-p 96 reader) (unsigned-byte-p 1 full))
  :concl (and (unsigned-byte-p 81 (pin-reader-extent reader)) (unsigned-byte-p 8 (pin-reader-octet reader))
              (unsigned-byte-p 1 (fifo-write-ready full)))
  :g-bindings (gl::auto-bindings (:nat full 1) (:nat reader 96)) :rule-classes nil))

(local (defthm pin-two-phase-projection
  (implies (and (unsigned-byte-p 96 reader) (or (not first) (unsigned-byte-p 35 first))
                (or (not settle) (unsigned-byte-p 35 settle)))
           (let ((z (pin-two-phases reader first settle count bits)))
             (equal (pin-reader-extent (nth 0 z))
                    (pin-wiring-extent-next (pin-reader-extent reader) first settle))))
  :hints (("Goal" :use ((:instance pin-one-phase-projection (raw first))
                        (:instance pin-one-phase-projection (reader (pin-reader-edge reader first)) (raw settle)))
           :in-theory (union-theories '(pin-two-phases pin-wiring-extent-next) (theory 'pin-list-theory))))
  :rule-classes nil))

(local (defthm pin-two-phase-sampling
  (implies (and (pin-reader-invariant reader count bits) (or (not first) (unsigned-byte-p 35 first))
                (or (not settle) (unsigned-byte-p 35 settle)))
           (let ((z (pin-two-phases reader first settle count bits)))
             (pin-reader-invariant (nth 0 z) (nth 1 z) (nth 2 z))))
  :hints (("Goal" :use ((:instance pin-reader-source-step (raw first))
                        (:instance pin-reader-source-step (reader (pin-reader-edge reader first))
                          (raw settle) (count (pin-reader-next-count reader first count))
                          (bits (pin-reader-next-bits reader first bits))))
           :in-theory (union-theories '(pin-two-phases) (theory 'pin-list-theory))))
  :rule-classes nil))

(local (defthm pin-byte-at-transfer
  (implies (pin-reader-invariant reader count bits)
           (and (iff (extent-takep (pin-reader-extent reader) raw) (pin-reader-take-p reader raw))
                (implies (pin-reader-take-p reader raw)
                         (and (equal count 8) (equal (pin-reader-octet reader) bits)))))
  :hints (("Goal" :use pin-reader-valid-byte-is-observed
           :in-theory '(extent-takep pin-reader-take-p pin-reader-valid-p (:executable-counterpart ifix)
                        (:executable-counterpart logbitp))))
  :rule-classes nil))

(local (defthm pin-storage-row-agrees
  (implies (and (consp (cddr (nth 2 step)))
                (implies (nth 3 step) (equal bits (nth 2 (nth 2 step)))))
           (equal (pin-storage-row step bits) (nth 2 step)))
  :hints (("Goal" :in-theory (enable pin-storage-row)))))


(local (defthm pin-one-cycle-interfaces
  (implies
    (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer) (unsigned-byte-p 1 full)
         (unsigned-byte-p 1024 memory) (unsigned-byte-p 96 reader)
         (unsigned-byte-p 5 meta) (unsigned-byte-p 63 input)
         (pin-reader-invariant reader count bits)
         (pin-wiring-live-p owner (pin-reader-extent reader) meta)
         (equal extent (pin-reader-extent reader)) (equal octet (pin-reader-octet reader))
         (equal ready (fifo-write-ready full))
         (equal wires (pin-wiring-step owner extent octet ready meta input))
         (equal pkt (nth 0 wires)) (equal first (nth 1 wires)) (equal settle (nth 2 wires))
         (equal observed (pin-two-phases reader first settle count bits))
         (equal packet (packet-step owner pointer full memory pkt)))
    (and (unsigned-byte-p 71 pkt)
         (unsigned-byte-p 278 (nth 0 packet)) (unsigned-byte-p 3 (nth 1 packet))
         (unsigned-byte-p 1 (nth 2 packet)) (unsigned-byte-p 1024 (nth 3 packet))
         (unsigned-byte-p 5 (nth 3 wires)) (consp (cddr (nth 4 packet)))
         (pin-reader-invariant (nth 0 observed) (nth 1 observed) (nth 2 observed))
         (pin-wiring-live-p (nth 0 packet) (pin-reader-extent (nth 0 observed)) (nth 3 wires))
         (iff (pin-reader-take-p reader first) (nth 1 (nth 4 packet)))
         (implies (pin-reader-take-p reader first)
                  (and (equal count 8) (equal bits (nth 2 (nth 4 packet)))))))
  :hints (("Goal" :use (pin-source-port-bounds pin-wiring-packet-step-law
                        (:instance pin-packet-source-fields (input pkt))
                        (:instance pin-byte-at-transfer (raw first))
                        pin-two-phase-sampling pin-two-phase-projection)
           :in-theory (theory 'pin-list-theory)))
  :rule-classes nil))

; Expose one event without expanding the leaf/FIFO transition equations.
; The RAM write/data/strobe and both ready/valid paths remain the source terms.
(local (defthm pin-one-cycle
  (implies (and (pin-snapshot-p s) (unsigned-byte-p 63 input))
           (let* ((step (pin-cycle s input)) (next (nth 0 step))
                  (packet-input (nth 1 step)) (row (nth 2 step)) (take (nth 3 step))
                  (packet (packet-step (nth 0 s) (nth 1 s) (nth 2 s) (nth 3 s) packet-input)))
             (and (pin-snapshot-p next) (unsigned-byte-p 71 packet-input)
                  (equal (nth 0 next) (nth 0 packet)) (equal (nth 1 next) (nth 1 packet))
                  (equal (nth 2 next) (nth 2 packet)) (equal (nth 3 next) (nth 3 packet))
                  (equal (pin-storage-row step (nth 7 s)) (nth 4 packet))
                  (iff take (nth 1 row))
                  (implies take (and (equal (nth 6 s) 8) (equal (nth 7 s) (nth 2 row)))))))
  :hints (("Goal"
           :use ((:instance pin-reader-valid-byte-is-observed
                            (reader (nth 4 s)) (count (nth 6 s)) (bits (nth 7 s)))
                 (:instance pin-source-port-bounds (reader (nth 4 s)) (full (nth 2 s)))
                 (:instance pin-one-cycle-interfaces
                            (owner (nth 0 s)) (pointer (nth 1 s)) (full (nth 2 s))
                            (memory (nth 3 s)) (reader (nth 4 s)) (meta (nth 5 s))
                            (count (nth 6 s)) (bits (nth 7 s))
                            (extent (pin-reader-extent (nth 4 s))) (octet (pin-reader-octet (nth 4 s)))
                            (ready (fifo-write-ready (nth 2 s)))
                            (wires (pin-wiring-step (nth 0 s) (pin-reader-extent (nth 4 s))
                              (pin-reader-octet (nth 4 s)) (fifo-write-ready (nth 2 s)) (nth 5 s) input))
                            (pkt (nth 1 (pin-cycle s input)))
                            (first (nth 1 (pin-wiring-step (nth 0 s) (pin-reader-extent (nth 4 s))
                              (pin-reader-octet (nth 4 s)) (fifo-write-ready (nth 2 s)) (nth 5 s) input)))
                            (settle (nth 2 (pin-wiring-step (nth 0 s) (pin-reader-extent (nth 4 s))
                              (pin-reader-octet (nth 4 s)) (fifo-write-ready (nth 2 s)) (nth 5 s) input)))
                            (observed (let ((w (pin-wiring-step (nth 0 s) (pin-reader-extent (nth 4 s))
                              (pin-reader-octet (nth 4 s)) (fifo-write-ready (nth 2 s)) (nth 5 s) input)))
                                (pin-two-phases (nth 4 s) (nth 1 w) (nth 2 w) (nth 6 s) (nth 7 s))))
                            (packet (packet-step (nth 0 s) (nth 1 s) (nth 2 s) (nth 3 s)
                                                 (nth 1 (pin-cycle s input))))))
           :in-theory (union-theories '(pin-snapshot-p pin-cycle pin-storage-row-agrees)
                                      (theory 'pin-list-theory))))
  :rule-classes nil))

(local (in-theory (disable pin-cycle pin-snapshot-p pin-storage-row packet-step
                           packet-inputs-p pin-packet-inputs pin-storage-rows pin-handshakes-correct-p
                           packet-observations pin-external-inputs-p unsigned-byte-p)))

(local (defthm pin-history-projects-to-the-same-packet-history
  (implies (and (pin-snapshot-p s) (pin-external-inputs-p inputs))
           (and (packet-inputs-p (pin-packet-inputs s inputs))
                (pin-handshakes-correct-p s inputs)
                (equal (pin-storage-rows s inputs)
                       (packet-observations (nth 0 s) (nth 1 s) (nth 2 s) (nth 3 s)
                                            (pin-packet-inputs s inputs)))))
  :hints (("Goal" :induct (pin-packet-inputs s inputs)
           :in-theory (enable pin-packet-inputs pin-storage-rows pin-handshakes-correct-p
                              packet-inputs-p pin-external-inputs-p packet-observations))
          ("Subgoal *1/2" :use ((:instance pin-one-cycle (input (car inputs))))))
  :rule-classes nil))

; From arbitrary physical registers and RAM, initiate a trusted rising clock
; with both external reset levels already low. The reader, stream, FIFO
; pointer/full and the independent pin observer enter their reset states.
; Reset does not write the FIFO storage.
(gl::def-gl-thm pin-common-reset-initializes-history
  :hyp (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer)
            (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory) (unsigned-byte-p 96 reader))
  :concl
  (let* ((step (pin-cycle (list owner pointer full memory reader 0 0 0) 1))
         (s (nth 0 step)) (reset-input (nth 1 step)) (row (nth 2 step))
         (packet (packet-step owner pointer full memory reset-input)))
    (and (pin-snapshot-p s) (unsigned-byte-p 71 reset-input)
         (stream-trusted-reset-p (packet-event reset-input))
         (nth 0 row) (not (nth 1 row)) (not (nth 3 row)) (not (nth 3 step))
         (equal (nth 0 s) (nth 0 packet)) (equal (nth 1 s) (nth 1 packet))
         (equal (nth 2 s) (nth 2 packet)) (equal (nth 3 s) (nth 3 packet))
         (equal (nth 1 s) 0) (equal (nth 2 s) 0) (equal (nth 3 s) memory)
         (equal (nth 6 row) memory) (equal (nth 6 s) 0) (equal (nth 7 s) 0)))
  :g-bindings (gl::auto-bindings (:nat full 1) (:nat pointer 3) (:nat owner 278)
                                 (:nat reader 96) (:nat memory 1024))
  :rule-classes nil)

; Apply the FIFO storage theorem to exactly the input list recovered from
; the pin trace. Its reset input and four initial fields match the same
; physical cycle, so the memory here is the original, arbitrary FIFO RAM.
(local (defthm pin-apply-packet-storage-theorem
  (implies
   (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer)
        (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory) (unsigned-byte-p 96 reader)
        (equal step (pin-cycle (list owner pointer full memory reader 0 0 0) 1))
        (equal s (nth 0 step)) (packet-inputs-p (pin-packet-inputs s inputs))
        (equal (pin-storage-rows s inputs)
               (packet-observations (nth 0 s) (nth 1 s) (nth 2 s) (nth 3 s) (pin-packet-inputs s inputs))))
   (packet-history-correct-p (pin-storage-rows s inputs) 0 0 0 memory))
  :hints (("Goal" :use (pin-common-reset-initializes-history
                        (:instance every-boot-fifo-storage-write-contains-its-32-accepted-reader-bytes
                                   (reset-input (nth 1 step)) (inputs (pin-packet-inputs s inputs))))
           :in-theory nil))
  :rule-classes nil))

(defthm every-boot-fifo-write-contains-its-sampled-dq1-bits
  (implies (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer) (unsigned-byte-p 1 full)
                (unsigned-byte-p 1024 memory) (unsigned-byte-p 96 reader) (pin-external-inputs-p inputs))
    (let* ((step (pin-cycle (list owner pointer full memory reader 0 0 0) 1))
           (s (nth 0 step)) (row (nth 2 step)))
      (and (nth 0 row) (not (nth 1 row)) (not (nth 3 row)) (not (nth 3 step))
           (equal (nth 3 s) memory)
           (pin-handshakes-correct-p s inputs)
           (packet-history-correct-p (pin-storage-rows s inputs) 0 0 0 memory))))
  :hints (("Goal" :use (pin-common-reset-initializes-history
                        (:instance pin-history-projects-to-the-same-packet-history
                           (s (nth 0 (pin-cycle (list owner pointer full memory reader 0 0 0) 1))))
                        (:instance pin-apply-packet-storage-theorem
                           (step (pin-cycle (list owner pointer full memory reader 0 0 0) 1))
                           (s (nth 0 (pin-cycle (list owner pointer full memory reader 0 0 0) 1)))))
           :in-theory nil))
  :rule-classes nil)

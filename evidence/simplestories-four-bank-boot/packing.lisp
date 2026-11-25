(in-package "SV")
(include-book "stream-packing")
(include-book "fifo-write")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor packing-history-glcp))
(local (gl::gl-bdd-mode))

; A reference assembler which only observes the reader handshake and byte.
; Its first accepted byte occupies bits 7:0. On each later acceptance it
; appends the new byte above all earlier bytes. A trusted reset discards
; the partial word and restarts the FIFO write slot at zero.
(defun packet-complete-p (lane accepted)
  (and accepted (equal lane 31)))
(defun packet-append (lane prefix octet)
  (logapp (* 8 (nfix lane)) (ifix prefix) (loghead 8 (ifix octet))))
(defun packet-next-lane (lane reset accepted)
  (cond (reset 0) (accepted (loghead 5 (1+ (ifix lane)))) (t lane)))
(defun packet-next-prefix (lane prefix reset accepted octet)
  (cond ((or reset (packet-complete-p lane accepted)) 0)
        (accepted (packet-append lane prefix octet))
        (t prefix)))
(defun packet-next-slot (slot reset complete)
  (cond (reset 0) (complete (loghead 2 (1+ (ifix slot)))) (t slot)))

; READY and VALID on both sides below are the compiled source values. A FIFO
; write is the clock/reset-qualified update to its actual storage, even if the
; new word happens to match the old contents at that address.
(defun packet-accept-p (pins event)
  (and (stream-rise-p event) (equal (stream-current-trusted-reset-n event) 1)
       (equal (nth 0 pins) 1) (equal (nth 1 pins) 1)))
(defun packet-observation (pins event full pointer fifo-next)
  (list (stream-trusted-reset-p event) (packet-accept-p pins event) (nth 2 pins)
        (fifo-write-strobe-p full (nth 3 pins) event) (loghead 2 (ifix pointer))
        (nth 4 pins) (nth 2 fifo-next)))

; Rows report the reset event, raw reader acceptance and byte, actual FIFO
; storage write strobe, physical slot, physical write bus and resulting RAM.
; The specification checks every row, including clocks with no write.
(defun packet-row-correct-p (row lane prefix slot memory)
  (let* ((accepted (nth 1 row)) (complete (packet-complete-p lane accepted))
         (word (packet-append lane prefix (nth 2 row))))
    (and (iff (nth 3 row) complete)
         (implies complete (and (equal (nth 4 row) slot) (equal (nth 5 row) word)))
         (equal (nth 6 row) (if complete (fifo-write-memory slot word memory) memory)))))
(defun packet-history-correct-p (rows lane prefix slot memory)
  (if (atom rows) t
    (let* ((row (car rows)) (reset (nth 0 row)) (accepted (nth 1 row)) (octet (nth 2 row)))
      (and (packet-row-correct-p row lane prefix slot memory)
           (packet-history-correct-p
            (cdr rows) (packet-next-lane lane reset accepted)
            (packet-next-prefix lane prefix reset accepted octet)
            (packet-next-slot slot reset (packet-complete-p lane accepted)) (nth 6 row))))))

; The low 60 bits of an input carry a parent edge, the next eight carry the
; current byte on the reader interface, and the last three the sampled read
; Gray pointer at the write-side synchronizer. The write pointer, write-full
; register and readiness are threaded. Unrelated CDC histories can vary.
(defun packet-inputs-p (inputs)
  (if (atom inputs) (equal inputs nil)
    (and (unsigned-byte-p 71 (car inputs)) (packet-inputs-p (cdr inputs)))))
(defun packet-event (input) (loghead 60 (ifix input)))
(defun packet-data (input) (loghead 8 (logtail 60 (ifix input))))
(defun packet-gray (input) (loghead 3 (logtail 68 (ifix input))))
(defun packet-step (owner pointer full memory input)
  (let* ((event (packet-event input)) (octet (packet-data input))
         (ready (fifo-write-ready full)) (pins (packing-pins owner event ready octet))
         (fifo-next (fifo-write-edge pointer full memory (packet-gray input)
                                     (nth 4 pins) (nth 3 pins) event)))
    (list (packing-edge owner event ready octet) (nth 0 fifo-next) (nth 1 fifo-next)
          (nth 2 fifo-next) (packet-observation pins event full pointer fifo-next))))
(defun packet-observations (owner pointer full memory inputs)
  (declare (xargs :measure (len inputs) :hints (("Goal" :in-theory (disable packet-step)))))
  (if (atom inputs) nil
    (let ((next (packet-step owner pointer full memory (car inputs))))
      (cons (nth 4 next) (packet-observations (nth 0 next) (nth 1 next) (nth 2 next)
                                              (nth 3 next) (cdr inputs))))))

; While STREAM is live, only the lower already-accepted bytes of the physical
; buffer matter. After DONE or FAIL the independent observer can still hold
; a partial packet. No requirement on that partial packet is needed until
; reset starts a new epoch. WAIT_APP and START precede every accepted byte.
(defun packet-state (owner) (stream-state (packing-stream owner)))
(defun packet-live-state-p (owner)
  (and (unsigned-byte-p 278 owner) (member-equal (packet-state owner) '(0 1 2 3 7))
       (implies (member-equal (packet-state owner) '(0 1 2))
                (equal (packing-slow-fault owner) 0))))
(defun packet-source-lane (owner other)
  (case (packet-state owner) ((0 1) 0) (2 (packing-byte owner)) (otherwise other)))
(defun packet-source-prefix (owner other)
  (case (packet-state owner)
    ((0 1) 0)
    (2 (loghead (* 8 (packing-byte owner)) (packing-buffer owner)))
    (otherwise other)))
(defun packet-owner-invariant (owner lane prefix)
  (and (packet-live-state-p owner) (unsigned-byte-p 5 lane) (unsigned-byte-p 248 prefix)
       (equal lane (packet-source-lane owner lane))
       (equal prefix (packet-source-prefix owner prefix))))

; Prove the observer step on the small reference forms. Source equivalence
; is supplied by PACKING-SOURCE-STEP-LAW, not assumed by the final theorem.
; The arbitrary tail lane and tail bytes are used when the source is terminal.
; In a live stream the measured register prefix supplies the same bytes.
(local (gl::def-gl-thm packet-reference-step
  :hyp (and (packet-live-state-p owner) (unsigned-byte-p 60 event)
            (unsigned-byte-p 1 ready) (unsigned-byte-p 8 octet)
            (unsigned-byte-p 5 other-lane) (unsigned-byte-p 248 other-prefix))
  :concl
  (let* ((lane (packet-source-lane owner other-lane)) (prefix (packet-source-prefix owner other-prefix))
         (pins (packing-spec-pins owner event ready octet))
         (reset (stream-trusted-reset-p event)) (accepted (packet-accept-p pins event))
         (complete (packet-complete-p lane accepted))
         (strobe (and (stream-rise-p event) (equal (stream-current-trusted-reset-n event) 1)
                      (equal ready 1) (equal (nth 3 pins) 1))))
    (and (equal (nth 2 pins) octet) (unsigned-byte-p 1 (nth 3 pins))
         (unsigned-byte-p 256 (nth 4 pins)) (iff strobe complete)
         (implies complete (equal (nth 4 pins) (packet-append lane prefix octet)))
         (packet-owner-invariant (packing-spec-edge owner event ready octet)
                                 (packet-next-lane lane reset accepted)
                                 (packet-next-prefix lane prefix reset accepted octet))))
  ; Keep the two possible byte prefixes adjacent bit by bit in the BDD.
  :g-bindings (gl::flex-bindings
                ((:int controls 29) (:int fault-bit 1) (:nat other-lane 5)
                 (:nat event 60) (:nat ready 1) (:nat octet 8)
                 (:mix (:int buffer-bits 248) (:int history-bits 248))
                 (:int owner-sign 1) (:int history-sign 1))
                :arrange ((:int owner controls buffer-bits fault-bit owner-sign)
                          (:int other-prefix history-bits history-sign)
                          (:int event) (:int ready) (:int octet) (:int other-lane)))
  :rule-classes nil))

(local (gl::def-gl-thm packet-reference-reset
  :hyp (and (unsigned-byte-p 278 owner) (unsigned-byte-p 60 event) (stream-trusted-reset-p event)
            (unsigned-byte-p 1 ready) (unsigned-byte-p 8 octet))
  :concl
  (let ((pins (packing-spec-pins owner event ready octet)))
    (and (not (packet-accept-p pins event)) (unsigned-byte-p 1 (nth 3 pins))
         (unsigned-byte-p 256 (nth 4 pins))
         (packet-owner-invariant (packing-spec-edge owner event ready octet) 0 0)))
  :g-bindings (gl::auto-bindings (:nat event 60) (:nat ready 1) (:nat owner 278) (:nat octet 8))
  :rule-classes nil))

(local (defthm packet-owner-invariant-components
  (implies (packet-owner-invariant owner lane prefix)
           (and (packet-live-state-p owner) (unsigned-byte-p 278 owner)
                (unsigned-byte-p 5 lane) (unsigned-byte-p 248 prefix)
                (equal (packet-source-lane owner lane) lane)
                (equal (packet-source-prefix owner prefix) prefix)))
  :hints (("Goal" :in-theory '(packet-owner-invariant packet-live-state-p)))
  :rule-classes nil))

(local (defthm packet-source-equations
  (implies (and (unsigned-byte-p 278 old) (unsigned-byte-p 60 event)
                (unsigned-byte-p 1 fifo-ready) (unsigned-byte-p 8 data))
           (and (equal (packing-pins old event fifo-ready data) (packing-spec-pins old event fifo-ready data))
                (equal (packing-edge old event fifo-ready data) (packing-spec-edge old event fifo-ready data))))
  :hints (("Goal" :use packing-source-step-law :in-theory nil))
  :rule-classes nil))

(local (defthm packet-owner-edge
  (implies (and (packet-owner-invariant owner lane prefix) (unsigned-byte-p 60 event)
                (unsigned-byte-p 1 ready) (unsigned-byte-p 8 octet))
   (let* ((pins (packing-pins owner event ready octet))
          (reset (stream-trusted-reset-p event)) (accepted (packet-accept-p pins event))
          (complete (packet-complete-p lane accepted))
          (strobe (and (stream-rise-p event) (equal (stream-current-trusted-reset-n event) 1)
                       (equal ready 1) (equal (nth 3 pins) 1))))
     (and (equal (nth 2 pins) octet) (unsigned-byte-p 1 (nth 3 pins)) (unsigned-byte-p 256 (nth 4 pins))
          (iff strobe complete) (implies complete (equal (nth 4 pins) (packet-append lane prefix octet)))
          (packet-owner-invariant (packing-edge owner event ready octet)
                                  (packet-next-lane lane reset accepted)
                                  (packet-next-prefix lane prefix reset accepted octet)))))
  :hints (("Goal" :use (packet-owner-invariant-components
                        (:instance packet-source-equations (old owner) (fifo-ready ready) (data octet))
                        (:instance packet-reference-step (other-lane lane) (other-prefix prefix)))
           :in-theory nil))
  :rule-classes nil))

(local (gl::def-gl-thm packet-input-fields
  :hyp (unsigned-byte-p 71 input)
  :concl (and (unsigned-byte-p 60 (packet-event input)) (unsigned-byte-p 8 (packet-data input))
              (unsigned-byte-p 3 (packet-gray input)))
  :g-bindings (gl::auto-bindings (:nat input 71)) :rule-classes nil))
(local (gl::def-gl-thm packet-ready-width
  :hyp (unsigned-byte-p 1 full)
  :concl (and (unsigned-byte-p 1 (fifo-write-ready full))
              (iff (equal (fifo-write-ready full) 1) (equal full 0)))
  :g-bindings (gl::auto-bindings (:nat full 1)) :rule-classes nil))
(local (gl::def-gl-thm packet-pointer-slot
  :hyp (and (unsigned-byte-p 3 pointer) (booleanp reset) (booleanp complete))
  :concl (equal (loghead 2 (if reset 0 (loghead 3 (+ pointer (if complete 1 0)))))
                (packet-next-slot (loghead 2 pointer) reset complete))
  :g-bindings (gl::auto-bindings (:nat pointer 3) (:bool reset) (:bool complete)) :rule-classes nil))

(local (in-theory (disable packing-edge packing-pins packing-spec-edge packing-spec-pins
                           fifo-write-edge fifo-write-strobe-p fifo-write-ready fifo-write-memory
                           packet-owner-invariant packet-live-state-p packet-state packet-source-lane
                           packet-source-prefix packet-event packet-gray packet-data packet-accept-p
                           packet-complete-p packet-next-slot packet-next-prefix packet-next-lane
                           packet-append stream-rise-p stream-trusted-reset-p
                           stream-current-trusted-reset-n unsigned-byte-p loghead)))

(local (defthm packet-one-event
  (implies (and (packet-owner-invariant owner lane prefix) (unsigned-byte-p 3 pointer)
                (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory) (unsigned-byte-p 71 input)
                (equal slot (loghead 2 pointer)))
    (let* ((next (packet-step owner pointer full memory input)) (row (nth 4 next))
           (reset (nth 0 row)) (accepted (nth 1 row)) (complete (packet-complete-p lane accepted)))
      (and (packet-row-correct-p row lane prefix slot memory)
           (packet-owner-invariant (nth 0 next) (packet-next-lane lane reset accepted)
                                   (packet-next-prefix lane prefix reset accepted (nth 2 row)))
           (unsigned-byte-p 3 (nth 1 next)) (unsigned-byte-p 1 (nth 2 next))
           (unsigned-byte-p 1024 (nth 3 next)) (equal (nth 6 row) (nth 3 next))
           (equal (loghead 2 (nth 1 next)) (packet-next-slot slot reset complete)))))
  :hints (("Goal"
           :use (packet-input-fields packet-ready-width
                 (:instance packet-owner-edge (ready (fifo-write-ready full))
                            (event (packet-event input)) (octet (packet-data input)))
                 (:instance fifo-write-source-law (read-gray (packet-gray input)) (event (packet-event input))
                            (valid (nth 3 (packing-pins owner (packet-event input) (fifo-write-ready full)
                                                       (packet-data input))))
                            (data (nth 4 (packing-pins owner (packet-event input) (fifo-write-ready full)
                                                      (packet-data input)))))
                 (:instance packet-pointer-slot (reset (stream-trusted-reset-p (packet-event input)))
                            (complete (if (fifo-write-strobe-p full
                              (nth 3 (packing-pins owner (packet-event input) (fifo-write-ready full)
                                                   (packet-data input))) (packet-event input)) t nil))))
           :in-theory (enable packet-step packet-observation packet-row-correct-p)))
  :rule-classes nil))

(local (defun packet-history-induction (owner pointer full memory inputs lane prefix slot)
  (declare (xargs :measure (len inputs) :hints (("Goal" :in-theory (disable packet-step)))))
  (if (atom inputs) (list owner pointer full memory lane prefix slot)
    (let* ((next (packet-step owner pointer full memory (car inputs)))
           (row (nth 4 next)) (reset (nth 0 row)) (accepted (nth 1 row)))
      (packet-history-induction (nth 0 next) (nth 1 next) (nth 2 next) (nth 3 next) (cdr inputs)
                                (packet-next-lane lane reset accepted)
                                (packet-next-prefix lane prefix reset accepted (nth 2 row))
                                (packet-next-slot slot reset (packet-complete-p lane accepted)))))))

(defthm packet-source-history-preserves-every-storage-word
  (implies (and (packet-owner-invariant owner lane prefix) (unsigned-byte-p 3 pointer)
                (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory) (packet-inputs-p inputs)
                (equal slot (loghead 2 pointer)))
           (packet-history-correct-p (packet-observations owner pointer full memory inputs)
                                     lane prefix slot memory))
  :hints (("Goal" :induct (packet-history-induction owner pointer full memory inputs lane prefix slot)
           :in-theory (disable packet-step packet-row-correct-p))
          ("Subgoal *1/2" :use ((:instance packet-one-event (input (car inputs))))))
  :rule-classes nil)

; An actual initial trusted reset accepts no byte, performs no write and
; preserves the contents of all four RAM cells. No clean initial RAM, prior
; pointer, empty buffer, or supplied write sequence is required.
(local (defthm packet-initial-reset
  (implies (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer)
                (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory) (unsigned-byte-p 71 input)
                (stream-trusted-reset-p (packet-event input)))
   (let* ((next (packet-step owner pointer full memory input)) (row (nth 4 next)))
     (and (packet-owner-invariant (nth 0 next) 0 0) (equal (nth 1 next) 0) (equal (nth 2 next) 0)
          (equal (nth 3 next) memory) (not (nth 1 row)) (not (nth 3 row)))))
  :hints (("Goal" :use (packet-input-fields packet-ready-width
                        (:instance packet-source-equations (old owner) (event (packet-event input))
                                   (fifo-ready (fifo-write-ready full)) (data (packet-data input)))
                        (:instance packet-reference-reset (event (packet-event input))
                                   (ready (fifo-write-ready full)) (octet (packet-data input)))
                        (:instance fifo-write-source-law (event (packet-event input)) (read-gray (packet-gray input))
                          (valid (nth 3 (packing-pins owner (packet-event input) (fifo-write-ready full) (packet-data input))))
                          (data (nth 4 (packing-pins owner (packet-event input) (fifo-write-ready full) (packet-data input))))))
           :in-theory (enable packet-step packet-observation stream-trusted-reset-p)))
  :rule-classes nil))

(defthm every-boot-fifo-storage-write-contains-its-32-accepted-reader-bytes
  (implies (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer)
                (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory)
                (unsigned-byte-p 71 reset-input) (stream-trusted-reset-p (packet-event reset-input))
                (packet-inputs-p inputs))
    (let* ((next (packet-step owner pointer full memory reset-input)) (row (nth 4 next)))
      (and (not (nth 1 row)) (not (nth 3 row)) (equal (nth 3 next) memory)
           (packet-history-correct-p
             (packet-observations (nth 0 next) (nth 1 next) (nth 2 next) (nth 3 next) inputs)
             0 0 0 memory))))
  :hints (("Goal" :use ((:instance packet-initial-reset (input reset-input))
                        (:instance packet-source-history-preserves-every-storage-word
                          (owner (nth 0 (packet-step owner pointer full memory reset-input)))
                          (pointer 0) (full 0) (lane 0) (prefix 0) (slot 0)))
           :in-theory (disable packet-step packet-observations packet-history-correct-p packet-inputs-p)))
  :rule-classes nil)

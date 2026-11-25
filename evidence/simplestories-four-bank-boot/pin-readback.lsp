(in-package "ACL2")
(include-book "pin-reset-history" :uncertified-okp nil :skip-proofs-okp nil :defaxioms-okp nil :ttags :all)
(in-package "SV")
:pe every-boot-fifo-write-contains-its-sampled-dq1-bits-from-arbitrary-fault-stages
:pe every-boot-fifo-write-contains-its-sampled-dq1-bits
:pe pin-reader-valid-byte-is-observed
:pe pin-reader-source-step
:pe pin-reader-reset
:pe pin-reader-source-status-reset
:pe pin-reader-source-status-step
:pe pin-wiring-reader-status-and-reset-continuity

; Exercise the leaf without a ready consumer. Vary DQ1 before each physical
; payload rise until the receiver holds one complete non-palindromic byte.
(defun rb-serial-drive (fuel wanted octet reader count bits sampled)
  (if (or (zp fuel) (equal count wanted)) (list reader count bits (reverse sampled))
    (let* ((dq (if (logbitp (nfix (- 7 (nfix count))) (ifix octet)) 1 0))
           (raw (+ 1 (* 8 dq))) (next (pin-reader-edge reader raw)))
      (rb-serial-drive (1- fuel) wanted octet next (pin-reader-next-count reader raw count)
                       (pin-reader-next-bits reader raw bits)
                       (if (pin-reader-rise-p reader next) (cons dq sampled) sampled)))))
(defconst *rb-leaf-reset* (pin-reader-edge (1- (ash 1 96)) 0))
(defconst *rb-leaf-start* (pin-reader-edge *rb-leaf-reset* 3))
(defconst *rb-serial-byte* (rb-serial-drive 220 8 #x96 *rb-leaf-start* 0 0 nil))
(value-triple :check-msb-first-byte-and-held-valid)
(assert-event
 (let ((r (car *rb-serial-byte*)))
   (and (pin-reader-invariant r 8 #x96) (pin-reader-valid-p r)
        (equal (cdr *rb-serial-byte*) '(8 150 (1 0 0 1 0 1 1 0)))
        (equal (pin-reader-octet r) #x96) (not (equal (pin-reader-octet r) #x69))
        (equal (pin-reader-edge r 9) r) (equal (pin-reader-next-count r 9 8) 8)
        (equal (pin-reader-next-bits r 9 #x96) #x96)
        (pin-reader-take-p r 5) (pin-reader-invariant (pin-reader-edge r 5) 0 0))))
(defconst *rb-serial-three* (rb-serial-drive 180 3 #x96 *rb-leaf-start* 0 0 nil))
(value-triple :check-partial-reset-and-source-fault-status)
(assert-event
 (let ((three (car *rb-serial-three*)) (reset-raw (ash 1 33)) (r (car *rb-serial-byte*)))
   (and (equal (cdr *rb-serial-three*) '(3 4 (1 0 0)))
        (equal (pin-reader-next-count three reset-raw 3) 0)
        (equal (pin-reader-next-bits three reset-raw 4) 0)
        (pin-reader-invariant (pin-reader-edge three reset-raw) 0 0)
        (equal (pin-reader-status-edge three 1 0 reset-raw) '(0 0))
        (equal (pin-reader-status-edge *rb-leaf-reset* 0 0 3) '(1 0))
        (pin-reader-take-p r 7) (equal (pin-reader-status-edge r 1 0 7) '(0 1))
        (not (pin-reader-selected-p (pin-reader-edge r 7))) (not (pin-reader-take-p r 0)))))

; Test the complete native reader/controller/FIFO from nonzero RAM and an
; arbitrary previous configuration. Apply common reset at a rising clock,
; then release it on the falling clock before applying alternating levels.
(defconst *rb-ram-seed* #x3456789)
(defun rb-reset-system (memory)
  (car (pin-cycle (list (1- (ash 1 278)) 7 1 memory (1- (ash 1 96)) 0 0 0) 1)))
(defconst *rb-system-reset* (rb-reset-system *rb-ram-seed*))
(defconst *rb-system-low* (car (pin-cycle *rb-system-reset* 6)))
(value-triple :check-common-reset-and-stationary-reset-release)
(assert-event
 (and (pin-snapshot-p *rb-system-reset*) (pin-snapshot-p *rb-system-low*)
      (equal (nth 0 *rb-system-reset*) 0) (equal (nth 1 *rb-system-reset*) 0)
      (equal (nth 2 *rb-system-reset*) 0) (equal (nth 3 *rb-system-reset*) *rb-ram-seed*)
      (equal (nth 5 *rb-system-reset*) 1) (equal (nth 5 *rb-system-low*) 6)
      (equal (nth 6 *rb-system-low*) 0) (equal (nth 7 *rb-system-low*) 0)))

; The initial reset also forgets both previously sampled fault stages.
(defun rb-reset-fault-stages (stages)
  (pin-cycle (list (1- (ash 1 278)) 7 1 *rb-ram-seed* (1- (ash 1 96)) (ash stages 3) 0 0) 1))
(value-triple :check-common-reset-from-all-four-fault-stage-values)
(assert-event
 (and (equal (car (rb-reset-fault-stages 0)) *rb-system-reset*)
      (equal (car (rb-reset-fault-stages 1)) *rb-system-reset*)
      (equal (car (rb-reset-fault-stages 2)) *rb-system-reset*)
      (equal (car (rb-reset-fault-stages 3)) *rb-system-reset*)
      (not (nth 3 (nth 2 (rb-reset-fault-stages 3))))))

; The external test device presents bytes 0x96 through 0xb5, most-significant
; bit first. Advance the test device's counter only on observed bus rises.
; It does not consult the reader's data, VALID, accumulator or bit counter.
(defun rb-flash-bit (sampled)
  (let ((byte (loghead 8 (+ #x96 (ash (nfix sampled) -3))))
        (position (- 7 (loghead 3 (nfix sampled)))))
    (if (logbitp position byte) 1 0)))
(defun rb-first-store (fuel s previous sampled prior-inputs final-sample)
  (if (zp fuel) nil
    (let* ((clk (if (equal (pin-wiring-bit 0 (nth 5 s)) 0) 1 0))
           (dq (rb-flash-bit sampled)) (input (+ 6 clk (* 8 dq)))
           (step (pin-cycle s input)) (next (car step))
           (rise (pin-reader-rise-p (nth 4 s) (nth 4 next)))
           (number (+ (nfix sampled) (if rise 1 0)))
           (inputs (cons input prior-inputs))
           ; Save clock-high snapshots before the last low/high sampling pair
           ; and after its normal last high edge for the two fault branches.
           (boundary (if (and rise (equal number 256)) (list previous next dq) final-sample)))
      (if (nth 3 (nth 2 step)) (list (reverse inputs) step number boundary)
        (rb-first-store (1- fuel) next s number inputs boundary)))))
(defun rb-write-rows (rows)
  (if (atom rows) nil
    (if (nth 3 (car rows)) (cons (car rows) (rb-write-rows (cdr rows)))
      (rb-write-rows (cdr rows)))))
(defconst *rb-word* #xb5b4b3b2b1b0afaeadacabaaa9a8a7a6a5a4a3a2a1a09f9e9d9c9b9a99989796)
(defconst *rb-write-run* (rb-first-store 4000 *rb-system-low* *rb-system-reset* 0 nil nil))
(defconst *rb-write-inputs* (cons 6 (first *rb-write-run*)))
(defconst *rb-write-log* (pin-storage-rows *rb-system-reset* *rb-write-inputs*))
(value-triple :check-first-physical-fifo-store-from-256-dq1-rises)
(assert-event
 (let* ((step (second *rb-write-run*)) (next (car step)) (rows (rb-write-rows *rb-write-log*))
        (row (car rows)) (written (nth 3 next)))
   (and (pin-external-inputs-p *rb-write-inputs*)
        (pin-handshakes-correct-p *rb-system-reset* *rb-write-inputs*)
        (equal (third *rb-write-run*) 256)
        (equal (len rows) 1) (nth 3 step) (nth 1 row) (nth 3 row)
        (equal (nth 4 row) 0) (equal (nth 5 row) *rb-word*)
        (equal (nth 1 next) 1) (equal (fifo-slot 0 written) *rb-word*)
        (equal written (fifo-write-memory 0 *rb-word* *rb-ram-seed*))
        (equal (nth 6 row) written)
        (packet-history-correct-p *rb-write-log* 0 0 0 *rb-ram-seed*))))
(value-triple :check-wrong-external-bit-and-wrong-fifo-slot)
(assert-event
 (let* ((n (1- (len *rb-write-log*))) (row (nth n *rb-write-log*))
        (branch (fourth *rb-write-run*)) (other-dq (logxor 1 (third branch)))
        (low (car (pin-cycle (first branch) (+ 6 (* 8 other-dq)))))
        (flipped (car (pin-cycle low (+ 7 (* 8 other-dq)))))
        (take (pin-cycle (car (pin-cycle flipped 6)) 7))
        (wrong-word (logxor *rb-word* (ash 1 248))))
   (and (nth 3 take) (nth 3 (nth 2 take))
        (not (equal (nth 5 (nth 2 take)) *rb-word*))
        (equal (nth 5 (nth 2 take)) wrong-word)
        (equal (fifo-slot 0 (nth 3 (car take))) wrong-word)
        (not (packet-history-correct-p
              (update-nth n (update-nth 5 (logxor *rb-word* 1) row) *rb-write-log*) 0 0 0 *rb-ram-seed*))
        (not (packet-history-correct-p
              (update-nth n (update-nth 4 1 row) *rb-write-log*) 0 0 0 *rb-ram-seed*)))))

; Repeat the identical external trace from reset with slot zero preloaded
; with the expected word. Its source-qualified write strobe must still fire.
(value-triple :check-strobed-rewrite-with-all-ram-bits-unchanged)
(assert-event
 (let* ((memory (fifo-write-memory 0 *rb-word* *rb-ram-seed*))
        (rows (pin-storage-rows (rb-reset-system memory) *rb-write-inputs*))
        (writes (rb-write-rows rows)))
   (and (equal (len writes) 1) (equal (nth 5 (car writes)) *rb-word*)
        (equal (nth 6 (car writes)) memory) (packet-history-correct-p rows 0 0 0 memory))))

; Assert application reset on the falling clock immediately before bit 256.
; The first microstep samples that bit and raises VALID. The asynchronously
; asserted internal reset in the second microstep discards it before delivery.
(defconst *rb-last-edge* (fourth *rb-write-run*))
(defconst *rb-fault-low*
  (car (pin-cycle (first *rb-last-edge*) (+ 2 (* 8 (third *rb-last-edge*))))))
(value-triple :check-transient-eighth-bit-then-reset-before-transfer)
(assert-event
 (let* ((s *rb-fault-low*) (input (+ 3 (* 8 (third *rb-last-edge*)))) (reader (nth 4 s))
        (w (pin-wiring-step (nth 0 s) (pin-reader-extent reader) (pin-reader-octet reader)
                            (fifo-write-ready (nth 2 s)) (nth 5 s) input))
        (mid (pin-reader-edge reader (nth 1 w))) (step (pin-cycle s input)) (settled (car step)))
   (and (equal (nth 6 s) 7) (pin-reader-rise-p reader mid) (pin-reader-valid-p mid)
        (equal (pin-reader-octet mid) #xb5) (nth 2 w)
        (not (pin-reader-valid-p (nth 4 settled))) (not (pin-reader-selected-p (nth 4 settled)))
        (equal (nth 6 settled) 0) (equal (nth 7 settled) 0)
        (not (nth 3 step)) (not (nth 3 (nth 2 step))) (equal (nth 3 settled) *rb-ram-seed*))))

; Moving the application reset one trusted edge later changes what was already
; visible at the pre-edge handshake. The complete word is now written on the
; same edge on which the controller fails and asynchronously resets its reader.
(value-triple :check-boundary-write-before-new-fault-settles)
(assert-event
 (let* ((before (second *rb-last-edge*)) (low (car (pin-cycle before 2)))
        (step (pin-cycle low 3)) (next (car step)) (row (nth 2 step)))
   (and (equal (nth 6 low) 8) (equal (nth 7 low) #xb5)
        (nth 3 step) (nth 1 row) (nth 3 row) (equal (nth 5 row) *rb-word*)
        (equal (fifo-slot 0 (nth 3 next)) *rb-word*) (equal (packet-state (nth 0 next)) 7)
        (not (pin-reader-selected-p (nth 4 next))) (equal (nth 6 next) 0))))
(value-triple :pin-fifo-readback-passed)
:q

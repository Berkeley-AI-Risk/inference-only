(in-package "SV")
(include-book "pin-history")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor pin-reset-history-glcp))
(local (gl::gl-bdd-mode))

; The common reset edge clears both physical app-fault synchronizer stages.
; The packet input can still carry the OLD second stage. Compare the
; successor, storage observation and reader transfer across that edge.
(gl::def-gl-thm pin-common-reset-is-independent-of-old-fault-stages
  :hyp (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer)
            (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory)
            (unsigned-byte-p 96 reader) (unsigned-byte-p 2 old-fault-stages))
  :concl
  (let* ((base (pin-cycle (list owner pointer full memory reader 0 0 0) 1))
         (step (pin-cycle (list owner pointer full memory reader (ash old-fault-stages 3) 0 0) 1)))
    (and (equal (nth 0 step) (nth 0 base)) (equal (nth 2 step) (nth 2 base))
         (equal (nth 3 step) (nth 3 base)) (equal (nth 5 (nth 0 step)) 1)
         (unsigned-byte-p 71 (nth 1 step)) (stream-trusted-reset-p (packet-event (nth 1 step)))))
  :g-bindings (gl::auto-bindings (:nat old-fault-stages 2) (:nat full 1) (:nat pointer 3)
                                 (:nat owner 278) (:nat reader 96) (:nat memory 1024))
  :rule-classes nil)

(defthm every-boot-fifo-write-contains-its-sampled-dq1-bits-from-arbitrary-fault-stages
  (implies (and (unsigned-byte-p 278 owner) (unsigned-byte-p 3 pointer)
                (unsigned-byte-p 1 full) (unsigned-byte-p 1024 memory)
                (unsigned-byte-p 96 reader) (unsigned-byte-p 2 old-fault-stages)
                (pin-external-inputs-p inputs))
    (let* ((step (pin-cycle (list owner pointer full memory reader (ash old-fault-stages 3) 0 0) 1))
           (s (nth 0 step)) (row (nth 2 step)))
      (and (pin-snapshot-p s) (unsigned-byte-p 71 (nth 1 step))
           (stream-trusted-reset-p (packet-event (nth 1 step)))
           (nth 0 row) (not (nth 1 row)) (not (nth 3 row)) (not (nth 3 step))
           (equal (nth 1 s) 0) (equal (nth 2 s) 0) (equal (nth 3 s) memory)
           (equal (nth 5 s) 1) (equal (nth 6 s) 0) (equal (nth 7 s) 0)
           (equal (nth 6 row) memory)
           (pin-handshakes-correct-p s inputs)
           (packet-history-correct-p (pin-storage-rows s inputs) 0 0 0 memory))))
  :hints (("Goal" :use (pin-common-reset-is-independent-of-old-fault-stages
                        pin-common-reset-initializes-history
                        every-boot-fifo-write-contains-its-sampled-dq1-bits)
           :in-theory nil))
  :rule-classes nil)

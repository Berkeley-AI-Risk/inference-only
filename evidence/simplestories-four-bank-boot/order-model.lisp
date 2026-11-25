(in-package "SV")
(include-book "fifo-write")

; State order follows the two clock domains in board1_qspi_async_word_fifo4.
; The final field is the packed storage_q[0:3], with slot 0 in bits 1023:768.
(defun bo-fifo-state-p (s)
  (and (true-listp s) (equal (len s) 12)
       (unsigned-byte-p 3 (nth 0 s)) (unsigned-byte-p 3 (nth 1 s))
       (unsigned-byte-p 3 (nth 2 s)) (unsigned-byte-p 3 (nth 3 s))
       (unsigned-byte-p 1 (nth 4 s)) (unsigned-byte-p 3 (nth 5 s))
       (unsigned-byte-p 3 (nth 6 s)) (unsigned-byte-p 3 (nth 7 s))
       (unsigned-byte-p 3 (nth 8 s)) (unsigned-byte-p 1 (nth 9 s))
       (unsigned-byte-p 256 (nth 10 s)) (unsigned-byte-p 1024 (nth 11 s))))

(defun bo-fifo-init (memory) (list 0 0 0 0 0 0 0 0 0 1 0 memory))
(defun bo-fifo-push-p (s we wvalid) (and we (equal (nth 4 s) 0) (equal wvalid 1)))
(defun bo-fifo-pop-p (s re rready) (and re (equal (nth 9 s) 0) (equal rready 1)))
(defun bo-gray (pointer) (logxor (ifix pointer) (ash (ifix pointer) -1)))
(defun bo-advance (pointer transfer) (loghead 3 (+ (ifix pointer) (if transfer 1 0))))
(defun bo-slot (pointer memory) (fifo-slot (loghead 2 (ifix pointer)) memory))

; Both enabled domains sample the same registers and RAM before this event.
; The read process captures the old RAM at its post-pop address on EVERY read
; clock, including clocks with no pop. Its valid bit is registered separately.
(defun bo-fifo-step (s we re wvalid wdata rready)
  (let* ((push (bo-fifo-push-p s we wvalid)) (pop (bo-fifo-pop-p s re rready))
         (wp (bo-advance (nth 0 s) push)) (rp (bo-advance (nth 5 s) pop))
         (wg (bo-gray wp)) (rg (bo-gray rp)) (memory (nth 11 s)))
    (list (if we wp (nth 0 s)) (if we wg (nth 1 s))
          (if we (nth 6 s) (nth 2 s)) (if we (nth 2 s) (nth 3 s))
          (if we (if (equal wg (logxor 6 (ifix (nth 3 s)))) 1 0) (nth 4 s))
          (if re rp (nth 5 s)) (if re rg (nth 6 s))
          (if re (nth 1 s) (nth 7 s)) (if re (nth 7 s) (nth 8 s))
          (if re (if (equal rg (nth 8 s)) 1 0) (nth 9 s))
          (if re (bo-slot rp memory) (nth 10 s))
          (if push (fifo-write-memory (loghead 2 (ifix (nth 0 s))) wdata memory) memory))))

(defun bo-fifo-next-pending (pending push wdata pop)
  (let ((rest (if pop (cdr pending) pending)))
    (if push (append rest (list wdata)) rest)))

; Distances are taken in the eight-state binary pointer ring. The read-side
; synchronized write pointers see at most the real occupancy, and the
; write-side synchronized read pointers see at least the real occupancy.
(defun bo-ungray (g)
  (loghead 3 (logxor (ifix g) (ash (ifix g) -1) (ash (ifix g) -2))))
(defun bo-distance (w r) (loghead 3 (- (ifix w) (ifix r))))
(defun bo-pointer-order-p (s)
  (let* ((wp (nth 0 s)) (rp (nth 5 s)) (count (bo-distance wp rp))
         (seen-w1 (bo-distance (bo-ungray (nth 7 s)) rp))
         (seen-w2 (bo-distance (bo-ungray (nth 8 s)) rp))
         (seen-r1 (bo-distance wp (bo-ungray (nth 2 s))))
         (seen-r2 (bo-distance wp (bo-ungray (nth 3 s)))))
    (and (equal (nth 1 s) (bo-gray wp)) (equal (nth 6 s) (bo-gray rp))
         (<= seen-w2 seen-w1) (<= seen-w1 count)
         (<= count seen-r1) (<= seen-r1 seen-r2) (<= seen-r2 4)
         (or (equal (nth 4 s) 1) (< seen-r2 4))
         (or (equal (nth 9 s) 1) (< 0 seen-w2)))))

; Reading at most the four live slots excludes unwritten initial storage.
(defun bo-memory-queue (rp count memory)
  (let ((p (ifix rp)))
    (case count
      (1 (list (bo-slot p memory)))
      (2 (list (bo-slot p memory) (bo-slot (+ p 1) memory)))
      (3 (list (bo-slot p memory) (bo-slot (+ p 1) memory) (bo-slot (+ p 2) memory)))
      (4 (list (bo-slot p memory) (bo-slot (+ p 1) memory)
               (bo-slot (+ p 2) memory) (bo-slot (+ p 3) memory)))
      (otherwise nil))))

(defun bo-fifo-invariant (s pending)
  (and (bo-fifo-state-p s) (bo-pointer-order-p s)
       (equal pending (bo-memory-queue (nth 5 s) (bo-distance (nth 0 s) (nth 5 s)) (nth 11 s)))
       (or (equal (nth 9 s) 1) (equal (nth 10 s) (bo-slot (nth 5 s) (nth 11 s))))))

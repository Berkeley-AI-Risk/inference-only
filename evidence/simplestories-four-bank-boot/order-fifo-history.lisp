(in-package "SV")
(include-book "order-model")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor bo-order-glcp))
(local (gl::gl-bdd-mode))

(local (defthm bo-nth-cons
  (equal (nth i (cons x xs)) (if (zp i) x (nth (1- i) xs)))
  :hints (("Goal" :expand (nth i (cons x xs))))))

(local (deftheory bo-list-rules
  (union-theories '(bo-nth-cons (:executable-counterpart zp) (:executable-counterpart binary-+)
                    (:executable-counterpart len) (:executable-counterpart true-listp) car-cons cdr-cons)
                  (theory 'minimal-theory))))

(local (defun bo-pointer-widths (s)
  (and (unsigned-byte-p 3 (nth 0 s)) (unsigned-byte-p 3 (nth 1 s))
       (unsigned-byte-p 3 (nth 2 s)) (unsigned-byte-p 3 (nth 3 s))
       (unsigned-byte-p 1 (nth 4 s)) (unsigned-byte-p 3 (nth 5 s))
       (unsigned-byte-p 3 (nth 6 s)) (unsigned-byte-p 3 (nth 7 s))
       (unsigned-byte-p 3 (nth 8 s)) (unsigned-byte-p 1 (nth 9 s)))))

; Visibility can lag by either number of clocks. The pointer invariant makes
; both flags conservative. If a newly valid register is sampled at the same
; time as a physical write, the write is to a different slot.
(local (defun bo-pointer-facts (s next we re wvalid rready)
  (let* ((push (bo-fifo-push-p s we wvalid)) (pop (bo-fifo-pop-p s re rready))
         (wp (nth 0 s)) (rp (nth 5 s)) (count (bo-distance wp rp))
         (wp-next (bo-advance wp push)) (rp-next (bo-advance rp pop)))
    (and (bo-pointer-widths next) (bo-pointer-order-p next)
         (equal (nth 0 next) wp-next) (equal (nth 5 next) rp-next)
         (implies (not re) (equal rp-next rp))
         (<= count 4) (implies push (< count 4))
         (implies (equal (nth 9 s) 0) (< 0 count))
         (implies (equal (nth 9 next) 0)
                  (and (or re (equal (nth 9 s) 0))
                       (or (not push) (not (equal (loghead 2 (ifix wp))
                                                  (loghead 2 (ifix rp-next)))))))))))

(local (gl::def-gl-thm bo-pointer-step
  :hyp (and (unsigned-byte-p 3 wp) (unsigned-byte-p 3 wg)
            (unsigned-byte-p 3 rs1) (unsigned-byte-p 3 rs2) (unsigned-byte-p 1 full)
            (unsigned-byte-p 3 rp) (unsigned-byte-p 3 rg)
            (unsigned-byte-p 3 ws1) (unsigned-byte-p 3 ws2) (unsigned-byte-p 1 empty)
            (booleanp we) (booleanp re) (unsigned-byte-p 1 wvalid) (unsigned-byte-p 1 rready)
            (bo-pointer-order-p (list wp wg rs1 rs2 full rp rg ws1 ws2 empty 0 0)))
  :concl (let ((s (list wp wg rs1 rs2 full rp rg ws1 ws2 empty 0 0)))
           (bo-pointer-facts s (bo-fifo-step s we re wvalid 0 rready) we re wvalid rready))
  :g-bindings (gl::auto-bindings (:bool we) (:bool re) (:nat wvalid 1) (:nat rready 1)
                  (:nat full 1) (:nat empty 1) (:nat wp 3) (:nat rp 3)
                  (:nat wg 3) (:nat rg 3) (:nat rs1 3) (:nat rs2 3) (:nat ws1 3) (:nat ws2 3))
  :rule-classes nil))

(local (defthm bo-physical-pointer-facts
  (implies (and (bo-fifo-state-p s) (bo-pointer-order-p s)
                (booleanp we) (booleanp re) (unsigned-byte-p 1 wvalid) (unsigned-byte-p 1 rready))
           (bo-pointer-facts s (bo-fifo-step s we re wvalid wdata rready) we re wvalid rready))
  :hints (("Goal" :use ((:instance bo-pointer-step
                           (wp (nth 0 s)) (wg (nth 1 s)) (rs1 (nth 2 s)) (rs2 (nth 3 s))
                           (full (nth 4 s)) (rp (nth 5 s)) (rg (nth 6 s)) (ws1 (nth 7 s))
                           (ws2 (nth 8 s)) (empty (nth 9 s))))
           :in-theory (union-theories '(bo-fifo-state-p bo-pointer-facts bo-pointer-order-p bo-pointer-widths
                                       bo-fifo-step bo-fifo-push-p bo-fifo-pop-p)
                                      (theory 'bo-list-rules))))
  :rule-classes nil))

; For the four-entry RAM, compare the whole oldest-first list. This checks
; simultaneous push/pop, data equality, pointer wrap and every unwritten word.
(local (gl::def-gl-thm bo-memory-queue-step
  :hyp (and (unsigned-byte-p 3 wp) (unsigned-byte-p 3 rp) (booleanp push) (booleanp pop)
            (unsigned-byte-p 1024 memory) (unsigned-byte-p 256 wdata)
            (<= (bo-distance wp rp) 4)
            (implies push (< (bo-distance wp rp) 4))
            (implies pop (< 0 (bo-distance wp rp))))
  :concl
  (let* ((wp-next (bo-advance wp push)) (rp-next (bo-advance rp pop))
         (next-memory (if push (fifo-write-memory (loghead 2 (ifix wp)) wdata memory) memory))
         (old-queue (bo-memory-queue rp (bo-distance wp rp) memory)))
    (and (equal (bo-memory-queue rp-next (bo-distance wp-next rp-next) next-memory)
                (bo-fifo-next-pending old-queue push wdata pop))
         (implies (< 0 (bo-distance wp rp))
                  (and (consp old-queue) (equal (car old-queue) (bo-slot rp memory))))
         (implies (or (not push) (not (equal (loghead 2 (ifix wp)) (loghead 2 (ifix rp-next)))))
                  (equal (bo-slot rp-next next-memory) (bo-slot rp-next memory)))
         (unsigned-byte-p 1024 next-memory) (unsigned-byte-p 256 (bo-slot rp-next memory))))
  ; Keep corresponding bit positions of each possible slot and write word
  ; adjacent in the decision diagram for equality of two word lists.
  :g-bindings (gl::flex-bindings
               ((:nat wp 3) (:nat rp 3) (:bool push) (:bool pop)
                (:mix (:int d 256) (:int m3 256) (:int m2 256) (:int m1 256) (:int m0 256))
                (:int data-sign 1) (:int ram-sign 1))
               :arrange ((:int wp) (:int rp) (:bool push) (:bool pop)
                         (:int wdata d data-sign) (:int memory m3 m2 m1 m0 ram-sign)))
  :rule-classes nil))

(defthm bo-fifo-initial-invariant
  (implies (unsigned-byte-p 1024 memory) (bo-fifo-invariant (bo-fifo-init memory) nil))
  :hints (("Goal" :in-theory (enable bo-fifo-invariant bo-fifo-init bo-memory-queue bo-pointer-order-p)))
  :rule-classes nil)

(local (defthm bo-fixed-list-shape
  (let ((s (list a b c d e f g h i j k l))) (and (true-listp s) (equal (len s) 12)))
  :hints (("Goal" :in-theory (enable len true-listp)))))

(local (defthm bo-one-bit-alternatives
  (implies (unsigned-byte-p 1 x) (or (equal x 0) (equal x 1)))
  :hints (("Goal" :in-theory (enable unsigned-byte-p)))
  :rule-classes nil))

(defthm bo-fifo-refines-pending-step
  (implies
   (and (bo-fifo-invariant s pending) (booleanp we) (booleanp re)
        (unsigned-byte-p 1 wvalid) (unsigned-byte-p 256 wdata) (unsigned-byte-p 1 rready))
   (let* ((push (bo-fifo-push-p s we wvalid)) (pop (bo-fifo-pop-p s re rready))
          (next (bo-fifo-step s we re wvalid wdata rready)))
     (and (bo-fifo-invariant next (bo-fifo-next-pending pending push wdata pop))
          (implies (equal (nth 9 s) 0) (and (consp pending) (equal (nth 10 s) (car pending)))))))
  :hints (("Goal" :use (bo-physical-pointer-facts
                         (:instance bo-one-bit-alternatives (x (nth 9 s)))
                         (:instance bo-one-bit-alternatives
                                    (x (nth 9 (bo-fifo-step s we re wvalid wdata rready))))
                         (:instance bo-memory-queue-step
                           (wp (nth 0 s)) (rp (nth 5 s)) (memory (nth 11 s))
                           (push (bo-fifo-push-p s we wvalid)) (pop (bo-fifo-pop-p s re rready))))
           :in-theory (union-theories '(bo-fifo-invariant bo-pointer-facts bo-fifo-state-p
                                        bo-pointer-widths bo-fifo-step bo-fifo-push-p bo-fifo-pop-p
                                        bo-fixed-list-shape booleanp)
                                      (theory 'bo-list-rules))))
  :rule-classes nil)

; At each event the two strobes are computed independently, using only the
; physical old state and the input ports. The pending list does not feed back
; into either clock domain. Return all physical writes, all physical reads,
; and the unconsumed suffix, each in chronological order.
(defun bo-fifo-events-p (events)
  (if (atom events) (equal events nil)
    (let ((e (car events)))
      (and (true-listp e) (equal (len e) 5)
           (booleanp (nth 0 e)) (booleanp (nth 1 e))
           (unsigned-byte-p 1 (nth 2 e)) (unsigned-byte-p 256 (nth 3 e))
           (unsigned-byte-p 1 (nth 4 e)) (bo-fifo-events-p (cdr events))))))

(defun bo-fifo-history (s pending events)
  (declare (xargs :measure (len events)
                  :hints (("Goal" :in-theory (disable bo-fifo-step bo-fifo-next-pending)))))
  (if (atom events) (list nil nil pending)
    (let* ((e (car events)) (we (nth 0 e)) (re (nth 1 e))
           (valid (nth 2 e)) (data (nth 3 e)) (ready (nth 4 e))
           (push (bo-fifo-push-p s we valid)) (pop (bo-fifo-pop-p s re ready))
           (next (bo-fifo-step s we re valid data ready))
           (tail (bo-fifo-history next (bo-fifo-next-pending pending push data pop) (cdr events))))
      (list (if push (cons data (car tail)) (car tail))
            (if pop (cons (nth 10 s) (cadr tail)) (cadr tail))
            (caddr tail)))))

(local (defthm bo-pending-is-list
  (implies (bo-fifo-invariant s pending) (true-listp pending))
  :hints (("Goal" :in-theory '(bo-fifo-invariant bo-memory-queue true-listp
                              (:type-prescription true-listp))))
  :rule-classes nil))

(local (defthm bo-following-queue
  (implies (or (not pop) (and (consp pending) (equal word (car pending))))
           (equal (let ((rest (append (bo-fifo-next-pending pending push data pop) writes)))
                    (if pop (cons word rest) rest))
                  (append pending (if push (cons data writes) writes))))
  :hints (("Goal" :cases (push pop)
           :in-theory (enable bo-fifo-next-pending acl2::associativity-of-append)))))

(local (defthm bo-history-prefix
  (implies (and (bo-fifo-invariant s pending) (bo-fifo-events-p events))
    (let ((result (bo-fifo-history s pending events)))
      (equal (append (cadr result) (caddr result)) (append pending (car result)))))
  :hints (("Goal" :induct (bo-fifo-history s pending events)
           :in-theory (e/d (bo-fifo-history bo-fifo-events-p bo-fifo-next-pending
                            bo-fifo-pop-p acl2::associativity-of-append)
                           (bo-fifo-invariant bo-fifo-step bo-fifo-push-p unsigned-byte-p)))
          ("Subgoal *1/2" :use ((:instance bo-fifo-refines-pending-step
                    (we (nth 0 (car events))) (re (nth 1 (car events)))
                    (wvalid (nth 2 (car events))) (wdata (nth 3 (car events)))
                    (rready (nth 4 (car events))))))
          ("Subgoal *1/1" :use bo-pending-is-list))
  :rule-classes nil))

(defthm every-boot-fifo-pop-is-an-in-order-physical-write
  (implies (and (unsigned-byte-p 1024 memory) (bo-fifo-events-p events))
    (let ((result (bo-fifo-history (bo-fifo-init memory) nil events)))
      (equal (append (cadr result) (caddr result)) (car result))))
  :hints (("Goal" :use (bo-fifo-initial-invariant
                        (:instance bo-history-prefix (s (bo-fifo-init memory)) (pending nil)))
           :in-theory '(binary-append)))
  :rule-classes nil)

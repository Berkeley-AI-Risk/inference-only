(in-package "SV")
(local (include-book "centaur/bitops/ihsext-basics" :dir :system))
(include-book "order-cycle")
(include-book "order-fifo-history")

(defun bo-record (values occurred datum)
  (if occurred (append values (list datum)) values))

(defun bo-related (s a wp rp pending awaiting issued taken)
  (and (unsigned-byte-p 1 wp) (unsigned-byte-p 1 rp)
       (bo-fifo-invariant s pending) (bo-app-state-p a)
       (implies (bo-app-live-p a) (equal awaiting (bo-loader-queue a pending)))
       (true-listp taken) (equal issued (append taken awaiting))))

(local (defthm bo-fifo-inv-gives-shape
  (implies (bo-fifo-invariant s pending) (bo-fifo-state-p s))))
(local (defthm bo-event-and-ready-types
  (and (unsigned-byte-p 1 (bo-wn e)) (unsigned-byte-p 1 (bo-rn e))
       (unsigned-byte-p 1 (bo-wv e)) (unsigned-byte-p 256 (bo-word e))
       (unsigned-byte-p 1 (bo-app-ready a u f))
       (booleanp (bo-source-rise-p p n)))
  :hints (("Goal" :in-theory (disable loghead logtail unsigned-byte-p)))))
(local (defthm bo-record-listp
  (implies (true-listp xs) (true-listp (bo-record xs fire d)))))

(local (in-theory (disable bo-app-state-p bo-fifo-invariant bo-fifo-state-p
                           bo-fifo-step bo-app-step bo-fifo-next-pending bo-loader-queue
                           bo-source-rise-p bo-app-ready bo-app-live-p bo-app-take-p
                           bo-wn bo-rn bo-wv bo-word bo-ready bo-fail bo-up unsigned-byte-p
                           bo-model-cycle bo-rtl-cycle)))

(local (defthm bo-model-row-preserves
  (implies (bo-related s a wp rp pending awaiting issued taken)
    (let* ((row (bo-model-cycle s a wp rp e))
           (push (nth 2 row)) (take (nth 3 row)) (out (nth 4 row)) (pop (nth 5 row)))
      (bo-related (nth 0 row) (nth 1 row) (bo-wn e) (bo-rn e)
                  (bo-fifo-next-pending pending push (bo-word e) pop)
                  (bo-fifo-next-pending awaiting push (bo-word e) take)
                  (bo-record issued push (bo-word e)) (bo-record taken take out))))
  :hints (("Goal" :in-theory (enable bo-model-cycle)
           :use ((:instance bo-model-app-preserves-width)
                 (:instance bo-fifo-refines-pending-step
                            (we (bo-source-rise-p wp (bo-wn e))) (re (bo-source-rise-p rp (bo-rn e)))
                            (wvalid (bo-wv e)) (wdata (bo-word e))
                            (rready (bo-app-ready a (bo-up e) (bo-fail e))))
                 (:instance bo-app-refines-two-queues
                            (re (bo-source-rise-p rp (bo-rn e))) (up (bo-up e)) (fail (bo-fail e))
                            (ready (bo-ready e)) (valid (if (equal (nth 9 s) 0) 1 0))
                            (data (nth 10 s)) (push (bo-fifo-push-p s (bo-source-rise-p wp (bo-wn e)) (bo-wv e)))
                            (wdata (bo-word e)))
                 (:instance bo-ledger-preserved (delivered taken)
                            (push (bo-fifo-push-p s (bo-source-rise-p wp (bo-wn e)) (bo-wv e)))
                            (take (bo-app-take-p a (bo-source-rise-p rp (bo-rn e)) (bo-up e) (bo-fail e) (bo-ready e)))
                            (value (nth 1 a)) (wdata (bo-word e))))))
  :rule-classes nil))

(local (defthm bo-rtl-row-preserves
  (implies (bo-related s a wp rp pending awaiting issued taken)
    (let* ((row (bo-rtl-cycle s a wp rp e))
           (push (nth 2 row)) (take (nth 3 row)) (out (nth 4 row)) (pop (nth 5 row)))
      (bo-related (nth 0 row) (nth 1 row) (bo-wn e) (bo-rn e)
                  (bo-fifo-next-pending pending push (bo-word e) pop)
                  (bo-fifo-next-pending awaiting push (bo-word e) take)
                  (bo-record issued push (bo-word e)) (bo-record taken take out))))
  :hints (("Goal" :use (bo-model-row-preserves bo-rtl-cycle-refines-model)))
  :rule-classes nil))

; These two lists are generated only from actual RAM write and loader-port
; handshake observations. The pending queues appear exclusively in the proof.
(defun bo-observe-history (s a wp rp events issued taken)
  (if (atom events) (list issued taken)
    (let* ((e (car events)) (row (bo-rtl-cycle s a wp rp e)))
      (bo-observe-history (nth 0 row) (nth 1 row) (bo-wn e) (bo-rn e) (cdr events)
                          (bo-record issued (nth 2 row) (bo-word e))
                          (bo-record taken (nth 3 row) (nth 4 row))))))

(local (defun bo-ledger-induction (s a wp rp events pending awaiting issued taken)
  (if (atom events) (list pending awaiting issued taken)
    (let* ((e (car events)) (row (bo-rtl-cycle s a wp rp e))
           (push (nth 2 row)) (take (nth 3 row)) (pop (nth 5 row)))
      (bo-ledger-induction (nth 0 row) (nth 1 row) (bo-wn e) (bo-rn e) (cdr events)
                           (bo-fifo-next-pending pending push (bo-word e) pop)
                           (bo-fifo-next-pending awaiting push (bo-word e) take)
                           (bo-record issued push (bo-word e)) (bo-record taken take (nth 4 row)))))))

(local (defthm bo-related-implies-prefix
  (implies (bo-related s a wp rp pending awaiting issued taken)
           (bo-prefix-p taken issued))))

(local (defthm bo-history-ledger
  (implies (bo-related s a wp rp pending awaiting issued taken)
    (let ((observed (bo-observe-history s a wp rp events issued taken)))
      (bo-prefix-p (nth 1 observed) (nth 0 observed))))
  :hints (("Goal" :induct (bo-ledger-induction s a wp rp events pending awaiting issued taken)
           :in-theory (disable bo-related bo-record bo-prefix-p))
          ("Subgoal *1/2" :use ((:instance bo-rtl-row-preserves (e (car events))))))
  :rule-classes nil))

(defthm every-boot-loader-acceptance-is-an-in-order-storage-write
  (implies (and (unsigned-byte-p 1024 memory) (unsigned-byte-p 1 wp) (unsigned-byte-p 1 rp))
    (let ((observed (bo-observe-history (bo-fifo-init memory) (bo-app-init) wp rp events nil nil)))
      (bo-prefix-p (nth 1 observed) (nth 0 observed))))
  :hints (("Goal" :use (bo-fifo-initial-invariant
                         (:instance bo-history-ledger (s (bo-fifo-init memory)) (a (bo-app-init))
                                    (issued nil) (taken nil) (pending nil) (awaiting nil)))
           :in-theory (e/d (bo-related bo-app-state-p bo-app-live-p bo-loader-queue)
                           (bo-prefix-p bo-observe-history bo-fifo-init))))
  :rule-classes nil)

(in-package "SV")
(include-book "order-app")
(include-book "order-model")

; The loader can own one word ahead of the FIFO. On a terminal edge a
; still-owned word may be discarded, but the sticky terminal state prevents
; any later loader take. The independent ledger keeps the abandoned suffix.
(defun bo-loader-queue (a pending)
  (if (equal (nth 0 a) 1) (cons (nth 1 a) pending) pending))

(defthm bo-app-refines-two-queues
  (let* ((pop (and re (equal valid 1) (equal (bo-app-ready a up fail) 1)))
         (take (bo-app-take-p a re up fail ready))
         (new (bo-app-step a re up fail ready valid data)))
    (implies
     (and (implies (bo-app-live-p a) (equal awaiting (bo-loader-queue a pending)))
          (implies pop (and (consp pending) (equal (car pending) data))))
     (and (implies take (and (consp awaiting) (equal (car awaiting) (nth 1 a))))
          (implies (bo-app-live-p new)
                   (equal (bo-fifo-next-pending awaiting push wdata take)
                          (bo-loader-queue new (bo-fifo-next-pending pending push wdata pop)))))))
  :hints (("Goal" :cases ((bo-app-live-p a) (equal (nth 0 a) 1)
                          (equal (nth 0 a) 0) re (equal fail 1))))
  :rule-classes nil)

(defun bo-prefix-p (prefix words)
  (if (consp prefix)
      (and (consp words) (equal (car prefix) (car words))
           (bo-prefix-p (cdr prefix) (cdr words)))
    (null prefix)))

(defthm bo-prefix-of-append
  (implies (true-listp taken) (bo-prefix-p taken (append taken pending))))

(defthm bo-append-assoc
  (equal (append (append x y) z) (append x (append y z))))

(defthm bo-ledger-preserved
  (implies (and (equal issued (append delivered awaiting))
                (implies take (and (consp awaiting) (equal (car awaiting) value))))
           (equal (append (if take (append delivered (list value)) delivered)
                          (bo-fifo-next-pending awaiting push wdata take))
                  (if push (append issued (list wdata)) issued)))
  :hints (("Goal" :cases (take push)))
  :rule-classes nil)

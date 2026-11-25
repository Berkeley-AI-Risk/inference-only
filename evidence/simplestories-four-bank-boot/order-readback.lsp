(in-package "ACL2")
(include-book "order-reset" :uncertified-okp nil :skip-proofs-okp nil :defaxioms-okp nil :ttags :all)
(in-package "SV")
:pe bo-source-projects-packing-write
:pe bo-source-edge-is-step
:pe bo-app-source-laws
:pe bo-fifo-refines-pending-step
:pe bo-rtl-cycle-refines-model
:pe every-boot-loader-acceptance-is-an-in-order-storage-write
:pe every-boot-loader-acceptance-after-common-reset-is-an-in-order-storage-write

; Clock arguments are levels, carried forward by bo-rtl-cycle. Data is the
; word on the write input qualified by the source strobe.
(defun bo-rb-event (wn rn valid data ready fail)
  (+ wn (* 2 rn) (* 4 valid) (* 8 ready) 16 (* 32 fail) (* 64 data)))
(defun bo-rb-reads (n ready fail)
  (if (zp n) nil
    (list* (bo-rb-event 0 1 0 0 ready fail) (bo-rb-event 0 0 0 0 ready fail)
           (bo-rb-reads (1- n) ready fail))))
(defun bo-rb-state (s a wp rp events)
  (if (atom events) (list s a)
    (let* ((e (car events)) (row (bo-rtl-cycle s a wp rp e)))
      (bo-rb-state (car row) (cadr row) (bo-wn e) (bo-rn e) (cdr events)))))

(defconst *bo-rb-a* (+ (ash 1 255) #x1357))
(defconst *bo-rb-b* (+ (ash 1 129) #xabcd))
(defconst *bo-rb-c* (+ (ash 1 71) #x3200))
(defconst *bo-rb-memory* (+ (ash #xaca 768) (ash #xcab 512) (ash #xdef 256) #xfee))
(defconst *bo-rb-dirty* (list 7 3 6 4 1 5 2 1 7 0 #xa55a *bo-rb-memory*))
(defconst *bo-rb-dirty-skid* '(1 4386 1 1 17 1))
(defconst *bo-rb-reset* (bo-reset-edges *bo-rb-dirty* *bo-rb-dirty-skid* 0 0 1 0 #x94))
(defconst *bo-rb-release* (bo-reset-edges (car *bo-rb-reset*) (cadr *bo-rb-reset*) 0 0 0 1 #x130))
(defconst *bo-rb-first* (bo-rb-event 1 1 1 *bo-rb-a* 0 0))
(defconst *bo-rb-low* (bo-rb-event 0 0 0 0 0 0))
(defconst *bo-rb-writes*
  (list *bo-rb-first* *bo-rb-low*
        (bo-rb-event 1 0 1 *bo-rb-b* 0 0) *bo-rb-low*
        (bo-rb-event 1 0 1 *bo-rb-b* 0 0) *bo-rb-low*
        (bo-rb-event 1 0 1 *bo-rb-c* 0 0) *bo-rb-low*))
(defconst *bo-rb-expected* (list *bo-rb-a* *bo-rb-b* *bo-rb-b* *bo-rb-c*))
(defconst *bo-rb-parked*
  (append *bo-rb-writes* (list (bo-rb-event 1 0 1 #xdead 0 0) *bo-rb-low*)
          (bo-rb-reads 7 0 0)))
(defun bo-rb-observe (events)
  (bo-observe-history (car *bo-rb-release*) (cadr *bo-rb-release*) 0 0 events nil nil))

(value-triple :check-reset-clears-old-ownership-and-preserves-every-ram-bit)
(assert-event
 (and (bo-fifo-state-p *bo-rb-dirty*) (bo-app-state-p *bo-rb-dirty-skid*)
      (equal *bo-rb-reset* (list (bo-fifo-init *bo-rb-memory*) (bo-app-init)))
      (equal *bo-rb-release* *bo-rb-reset*)))

(value-triple :check-both-clocks-rise-on-reset-and-the-history-keeps-the-release-phase)
(assert-event
 (let* ((hold (bo-reset-edges *bo-rb-dirty* *bo-rb-dirty-skid* 0 0 1 0 3))
        ; The write clock stays high as reset releases. The read clock falls.
        (released (bo-reset-edges (car hold) (cadr hold) 1 1 0 1 1))
        (events (append *bo-rb-writes* (bo-rb-reads 12 1 0)))
        (observed (bo-observe-history (car released) (cadr released) 1 0 events nil nil))
        ; First offered A sees write clock high->high; the following B,B,C rise.
        (expected (list *bo-rb-b* *bo-rb-b* *bo-rb-c*)))
   (and (equal hold *bo-rb-reset*) (equal released hold)
        (equal observed (list expected expected)))))

(value-triple :check-simultaneous-rise-prefetches-the-old-word)
(assert-event
 (let* ((row (bo-rtl-cycle (car *bo-rb-release*) (cadr *bo-rb-release*) 0 0 *bo-rb-first*))
        (next (car row)))
   (and (nth 2 row) (not (nth 3 row)) (not (nth 5 row))
        (equal (fifo-slot 0 (nth 11 next)) *bo-rb-a*) (equal (nth 10 next) #xaca)
        (equal (nth 9 next) 1))))

(value-triple :check-four-writes-followed-by-a-rejected-fifth-and-a-held-skid)
(assert-event
 (let* ((full (bo-rb-state (car *bo-rb-release*) (cadr *bo-rb-release*) 0 0 *bo-rb-writes*))
        (hold (bo-rb-state (car *bo-rb-release*) (cadr *bo-rb-release*) 0 0 *bo-rb-parked*))
        (obs (bo-rb-observe *bo-rb-parked*)))
   (and (equal (nth 4 (car full)) 1) (equal (car (bo-source-ports (car full))) 0)
        (equal (nth 0 (cadr hold)) 1) (equal (nth 1 (cadr hold)) *bo-rb-a*)
        (equal obs (list *bo-rb-expected* nil)))))

(value-triple :check-a-single-acceptance-is-a-proper-prefix)
(assert-event
 (let ((obs (bo-rb-observe (append *bo-rb-parked* (bo-rb-reads 1 1 0)))))
   (and (equal obs (list *bo-rb-expected* (list *bo-rb-a*)))
        (bo-prefix-p (cadr obs) (car obs)))))

(defconst *bo-rb-result* (bo-rb-observe (append *bo-rb-parked* (bo-rb-reads 12 1 0))))
(value-triple :check-complete-drain-keeps-the-repeated-word)
(assert-event (equal *bo-rb-result* (list *bo-rb-expected* *bo-rb-expected*)))

(value-triple :check-wrong-order-and-missing-duplicate-are-rejected)
(assert-event
 (let ((issued (car *bo-rb-result*)) (actual (cadr *bo-rb-result*)))
   (and (bo-prefix-p actual issued)
        (not (bo-prefix-p (list *bo-rb-a* *bo-rb-b* *bo-rb-c* *bo-rb-b*) issued))
        (not (bo-prefix-p (list *bo-rb-a* *bo-rb-b* *bo-rb-c*) issued))
        (not (bo-prefix-p (append actual '(0)) issued)))))

(value-triple :check-fault-can-leave-all-four-writes-undelivered)
(assert-event
 (let* ((events (append *bo-rb-parked* (bo-rb-reads 1 1 1) (bo-rb-reads 9 1 0)))
        (end (bo-rb-state (car *bo-rb-release*) (cadr *bo-rb-release*) 0 0 events)))
   (and (equal (nth 2 (cadr end)) 1) (equal (bo-rb-observe events) (list *bo-rb-expected* nil)))))

(value-triple :boot-loader-order-readback-passed)
:q

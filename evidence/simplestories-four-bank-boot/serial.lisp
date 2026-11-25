(in-package "SV")
(include-book "extent")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor serial-glcp))
(local (gl::gl-bdd-mode))

; Independent pin observer: on a selected rising SCK the released DQ0 and DQ1
; (OE=1100, both /WP and /HOLD driven) identify the receive phase. No internal
; state, byte-valid, ready, bit-index or expected bit count enters this observer.
(defun serial-data-rise-p (old new)
  (let ((before (extent-header old)) (after (extent-header new)))
    (and (equal (extent-cs old) 0) (equal (extent-cs new) 0)
         (equal (nth 6 before) 0) (equal (nth 6 after) 1) (equal (nth 8 after) 12))))
(defthm serial-rise-needs-selected-data-drive
  (implies (serial-data-rise-p old new)
           (and (equal (extent-cs new) 0) (equal (nth 8 (extent-header new)) 12)))
  :hints (("Goal" :in-theory (e/d (serial-data-rise-p) (extent-header extent-cs))))
  :rule-classes nil)

(defun serial-bit-index (old) (loghead 3 (logtail 54 (ifix old))))
; In live DATA the pins are as much as one full byte ahead of the consumer.
; In TURN the prior VALID/READY edge already delivered the byte.
(defun serial-pending (old)
  (if (equal (extent-state old) 2) (if (extent-valid old) 8 (serial-bit-index old)) 0))
(defun serial-budget (old) (- (* 8 (extent-budget old)) (serial-pending old)))
(defun serial-livep (old)
  (let ((pins (extent-header old)))
    (and (extent-livep old) (equal (nth 1 pins) (nth 6 pins))
         (equal (nth 8 pins) (if (equal (extent-state old) 1) 13 12))
         (implies (or (extent-valid old) (equal (extent-state old) 3))
                  (and (equal (nth 6 pins) 1) (equal (serial-bit-index old) 0))))))

(gl::def-gl-thm serial-selection-starts-with-full-bit-budget
  :hyp (and (unsigned-byte-p 81 old) (unsigned-byte-p 35 raw))
  :concl (let ((new (extent-edge old raw)))
           (implies (and (equal (extent-cs old) 1) (equal (extent-cs new) 0))
                    (and (serial-livep new) (equal (serial-budget new) (* 8 *extent-image-bytes*))
                         (equal (serial-pending new) 0))))
  :g-bindings (gl::auto-bindings (:nat old 81) (:nat raw 35)) :rule-classes nil)

(gl::def-gl-thm serial-source-edge-accounts-for-observed-rises
  :hyp (and (serial-livep old) (unsigned-byte-p 35 raw))
  :concl (let* ((new (extent-edge old raw)) (rise (if (serial-data-rise-p old new) 1 0))
                (delivered (if (extent-takep old raw) 8 0))
                (credit (+ (serial-pending old) rise (- delivered))))
           (and (natp (serial-budget old)) (natp (serial-pending old)) (<= (serial-pending old) 8)
                (<= rise (serial-budget old)) (<= 0 credit) (<= credit 8)
                (if (equal (extent-cs new) 0)
                    (and (serial-livep new) (equal (serial-pending new) credit)
                         (equal (serial-budget old) (+ rise (serial-budget new))))
                  (implies (not (flash-abortp raw)) (equal (serial-budget old) rise)))))
  :g-bindings (gl::auto-bindings (:nat old 81) (:nat raw 35)) :rule-classes nil)

(local (in-theory (disable extent-edge extent-header extent-state extent-valid extent-livep extent-last
                           extent-cs extent-budget extent-takep flash-abortp serial-pending serial-livep
                           serial-budget serial-data-rise-p unsigned-byte-p)))
(defun serial-prefix (old events)
  (declare (xargs :measure (len events)))
  (if (atom events) 0
    (let* ((new (extent-edge old (car events))) (rise (if (serial-data-rise-p old new) 1 0)))
      (if (equal (extent-cs new) 0) (+ rise (serial-prefix new (cdr events))) rise))))

(local (defthm serial-credit-bounds
  (implies (serial-livep old) (and (natp (serial-budget old)) (natp (serial-pending old))
                                   (<= (serial-pending old) 8)))
  :hints (("Goal" :use ((:instance serial-source-edge-accounts-for-observed-rises (raw 0)))))))

(defthm serial-every-live-prefix-accounts-for-pin-and-consumer-edges
  (implies (and (serial-livep old) (flash-eventsp events))
           (let* ((bits (serial-prefix old events)) (transfer (extent-prefix old events))
                  (credit (+ (serial-pending old) bits (- (* 8 (cdr transfer))))))
             (and (natp bits) (<= bits (serial-budget old)) (<= 0 credit) (<= credit 8)
                  (implies (equal (car transfer) :normal) (equal bits (serial-budget old))))))
  :hints (("Goal" :induct (serial-prefix old events) :in-theory (enable extent-prefix))
          ("Subgoal *1/3" :use ((:instance serial-source-edge-accounts-for-observed-rises (raw (car events)))))
          ("Subgoal *1/2" :use ((:instance serial-source-edge-accounts-for-observed-rises (raw (car events))))))
  :rule-classes nil)

(defthm every-selected-flash-transaction-has-bounded-serial-payload
  (let ((new (extent-edge old select)))
    (implies (and (unsigned-byte-p 81 old) (unsigned-byte-p 35 select) (flash-eventsp events)
                  (equal (extent-cs old) 1) (equal (extent-cs new) 0))
             (let ((bits (serial-prefix new events)) (transfer (extent-prefix new events)))
               (and (natp bits) (<= bits (* 8 *extent-image-bytes*))
                    (<= (* 8 (cdr transfer)) bits) (<= bits (+ (* 8 (cdr transfer)) 8))
                    (implies (equal (car transfer) :normal) (equal bits (* 8 *extent-image-bytes*)))))))
  :hints (("Goal" :use ((:instance serial-selection-starts-with-full-bit-budget (raw select))
                        (:instance serial-every-live-prefix-accounts-for-pin-and-consumer-edges
                                   (old (extent-edge old select))))
           :in-theory (disable extent-prefix serial-prefix)))
  :rule-classes nil)

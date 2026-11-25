(in-package "SV")
(include-book "opcode")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor extent-glcp))
(local (gl::gl-bdd-mode))

; Retain every old register that can affect the header, VALID/LAST or length.
; The source dependency check below omits only data_o, data_shift_q, busy_o and
; fault_o, which do not feed any of the thirteen selected register drivers.
(defconst *extent-extra-fields*
  '(("data_valid_o" . 1) ("data_last_o" . 1) ("data_bit_q" . 3) ("bytes_remaining_q" . 24)))
(defconst *extent-extra-equations* (flash-drivers *extent-extra-fields* *flash-assigns*))
(assert-event (subsetp-equal (svexlist-vars *extent-extra-equations*)
                             (strip-cars (append (flash-inputs 0) (flash-old-fields *flash-fields* nil)))))
(defconst *extent-image-bytes* 7265984)

(defun extent-pack (fields regs)
  (if (endp fields) 0
    (logapp (cdar fields) (ifix (car regs)) (extent-pack (cdr fields) (cdr regs)))))
(defun extent-header (old) (flash-unpack *flash-fields* (loghead 52 (ifix old))))
(defun extent-event (old raw)
  (logapp 4 (ifix raw) (logapp 29 (logtail 52 (ifix old)) (loghead 2 (logtail 33 (ifix raw))))))
(defun extent-edge (old raw)
  (let* ((regs (extent-header old)) (event (extent-event old raw))
         (env (append (flash-inputs event) (flash-old-fields *flash-fields* regs)))
         (extra (with-fast-alist env (svexlist-eval *extent-extra-equations* env))))
    (logapp 52 (extent-pack *flash-fields* (flash-edge regs event))
            (extent-pack *extent-extra-fields* extra))))
(defun extent-events (regs events)
  (if (atom events) nil
    (cons (extent-event regs (car events)) (extent-events (extent-edge regs (car events)) (cdr events)))))

(defun extent-state (old) (loghead 3 (ifix old)))
(defun extent-cs (old) (loghead 1 (logtail 42 (ifix old))))
(defun extent-remaining (old) (loghead 24 (logtail 57 (ifix old))))
(defun extent-valid (old) (logbitp 52 (ifix old)))
(defun extent-last (old) (logbitp 53 (ifix old)))
; Sample before the edge. A busy-start fault cancels the continuation but
; cannot retract VALID && READY already seen on that edge with reset released.
(defun extent-takep (old raw)
  (and (not (logbitp 33 (ifix raw))) (logbitp 0 (ifix raw))
       (equal (extent-cs old) 0) (extent-valid old) (logbitp 2 (ifix raw))))
; ST_TURN holds the physical count for one edge after acceptance. Deduct this
; one outstanding decrement now, so the logical offset advances on the actual transfer.
(defun extent-budget (old)
  (- (extent-remaining old) (if (equal (extent-state old) 3) 1 0)))
(defun extent-livep (old)
  (and (unsigned-byte-p 81 old) (equal (extent-cs old) 0)
       (member-equal (extent-state old) '(1 2 3))
       (< 0 (extent-remaining old)) (<= (extent-remaining old) *extent-image-bytes*)
       (implies (extent-valid old) (equal (extent-state old) 2))
       (implies (or (extent-valid old) (equal (extent-state old) 3))
                (iff (extent-last old) (equal (extent-remaining old) 1)))))

(gl::def-gl-thm extent-edge-projects-to-flash-edge
  :hyp (and (unsigned-byte-p 81 old) (unsigned-byte-p 35 raw))
  :concl (and (equal (extent-header (extent-edge old raw))
                     (flash-edge (extent-header old) (extent-event old raw)))
              (equal (nth 5 (extent-header old)) (extent-cs old))
              (equal (nth 5 (extent-header (extent-edge old raw))) (extent-cs (extent-edge old raw)))
              (unsigned-byte-p 81 (extent-edge old raw)) (unsigned-byte-p 35 (extent-event old raw)))
  :g-bindings (gl::auto-bindings (:nat old 81) (:nat raw 35)) :rule-classes nil)

(gl::def-gl-thm extent-selection-initializes-remaining
  :hyp (and (unsigned-byte-p 81 old) (unsigned-byte-p 35 raw))
  :concl (let ((new (extent-edge old raw)))
           (implies (and (equal (extent-cs old) 1) (equal (extent-cs new) 0))
                    (and (extent-livep new) (equal (extent-budget new) *extent-image-bytes*))))
  :g-bindings (gl::auto-bindings (:nat old 81) (:nat raw 35)) :rule-classes nil)

(gl::def-gl-thm extent-source-transition-accounting
  :hyp (and (extent-livep old) (unsigned-byte-p 35 raw))
  :concl
  (let* ((new (extent-edge old raw)) (increment (if (extent-takep old raw) 1 0)))
    (and (natp (extent-budget old)) (<= increment (extent-budget old))
         (if (equal (extent-cs new) 0)
             (and (not (flash-abortp raw)) (extent-livep new)
                  (equal (extent-budget old) (+ increment (extent-budget new))))
           (implies (not (flash-abortp raw))
                    (and (equal (extent-state old) 3) (extent-last old)
                         (equal (extent-state new) 0) (equal (extent-budget old) increment))))))
  :g-bindings (gl::auto-bindings (:nat old 81) (:nat raw 35)) :rule-classes nil)

(local (in-theory (disable extent-edge extent-event extent-cs extent-budget extent-takep extent-livep
                           extent-state extent-last flash-abortp)))

(defun extent-prefix (old events)
  (declare (xargs :measure (len events)))
  (if (atom events) (cons :open 0)
    (let* ((raw (car events)) (new (extent-edge old raw))
           (inc (if (extent-takep old raw) 1 0)))
      (if (equal (extent-cs new) 0)
          (let ((tail (extent-prefix new (cdr events)))) (cons (car tail) (+ inc (cdr tail))))
        (cons (if (flash-abortp raw) :abort :normal) inc)))))

(local (defthm extent-edge-width
  (implies (and (unsigned-byte-p 81 old) (unsigned-byte-p 35 raw))
           (and (unsigned-byte-p 81 (extent-edge old raw)) (unsigned-byte-p 35 (extent-event old raw))))
  :hints (("Goal" :use extent-edge-projects-to-flash-edge
           :in-theory (disable extent-header flash-edge extent-edge extent-event extent-cs unsigned-byte-p)))))

(defthm extent-events-satisfy-flash-eventsp
  (implies (and (unsigned-byte-p 81 regs) (flash-eventsp events))
           (flash-eventsp (extent-events regs events)))
  :hints (("Goal" :induct (extent-events regs events)
           :in-theory (disable extent-edge extent-event unsigned-byte-p))))

(local (defthm extent-live-budget-natural
  (implies (extent-livep old) (natp (extent-budget old)))
  :hints (("Goal" :use ((:instance extent-source-transition-accounting (raw 0)))
           :in-theory (disable extent-edge extent-takep extent-state extent-cs extent-last
                               extent-budget extent-livep unsigned-byte-p)))))

(defthm extent-every-live-prefix-is-accounted
  (implies (and (extent-livep old) (flash-eventsp events))
           (let ((result (extent-prefix old events)))
             (and (natp (cdr result)) (<= (cdr result) (extent-budget old))
                  (implies (equal (car result) :normal) (equal (cdr result) (extent-budget old))))))
  :hints (("Goal" :induct (extent-prefix old events)
           :in-theory (disable extent-edge extent-takep extent-state extent-cs extent-last extent-budget
                               extent-livep flash-abortp unsigned-byte-p))
          ("Subgoal *1/3" :use ((:instance extent-source-transition-accounting (raw (car events)))))
          ("Subgoal *1/2" :use ((:instance extent-source-transition-accounting (raw (car events))))))
  :rule-classes nil)

(defthm every-selected-flash-transaction-has-bounded-extent
  (let ((new (extent-edge old select)))
    (implies (and (unsigned-byte-p 81 old) (unsigned-byte-p 35 select) (flash-eventsp events)
                  (equal (extent-cs old) 1) (equal (extent-cs new) 0))
             (let ((result (extent-prefix new events)))
               (and (natp (cdr result)) (<= (cdr result) *extent-image-bytes*)
                    (implies (equal (car result) :normal) (equal (cdr result) *extent-image-bytes*))))))
  :hints (("Goal" :use ((:instance extent-selection-initializes-remaining (raw select))
                        (:instance extent-every-live-prefix-is-accounted (old (extent-edge old select))))
           :in-theory (disable extent-edge extent-cs extent-prefix extent-livep extent-budget unsigned-byte-p)))
  :rule-classes nil)

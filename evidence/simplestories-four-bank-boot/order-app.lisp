(in-package "SV")
(include-book "stream-source")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor bo-app-glcp))
(local (gl::gl-bdd-mode))

; The destination skid register, sticky fault, started flag, count and done.
(defconst *bo-app-fields*
  '(("loader_skid_valid_q" . 1) ("loader_skid_data_q" . 256)
    ("app_fault_q" . 1) ("app_started_q" . 1) ("app_word_q" . 18) ("loader_done_q" . 1)))
(defconst *bo-app-inputs*
  '(("source_ready_sync2_q" . 1) ("slow_fault_sync2_q" . 1)
    ("loader_ready_i" . 1) ("fifo_read_valid" . 1) ("fifo_read_data" . 256)))
(defconst *bo-app-gates*
  (stream-compose-gates '(("app_x_fault" . 1) ("immediate_fail" . 1)
                          ("fifo_read_ready" . 1) ("fifo_read_transfer" . 1)
                          ("loader_valid_o" . 1) ("loader_transfer" . 1) ("loader_data_o" . 256))
                        *stream-assigns* nil))
(defconst *bo-app-equations*
  (let ((gates (stream-sampled-gates *bo-app-gates*)))
    (with-fast-alist gates (svexlist-compose (flash-drivers *bo-app-fields* *stream-assigns*) gates))))
(defconst *bo-app-ports*
  (list (cdr (assoc-equal "fifo_read_ready" *bo-app-gates*))
        (cdr (assoc-equal "loader_valid_o" *bo-app-gates*))
        (cdr (assoc-equal "loader_data_o" *bo-app-gates*))
        (cdr (assoc-equal "loader_transfer" *bo-app-gates*))
        (cdr (assoc-equal "fifo_read_transfer" *bo-app-gates*))))
(assert-event
 (subsetp-equal
  '((((:var ("u_loader_cdc" . "read_clk_i") . 0)) "app_clk_i")
    (((:var ("u_loader_cdc" . "read_reset_n_i") . 0)) "app_reset_n_i")
    (((256 :var ("u_loader_cdc" . "read_data_o") . 0)) (256 . "fifo_read_data"))
    (((:var ("u_loader_cdc" . "read_valid_o") . 0)) "fifo_read_valid")
    (((:var ("u_loader_cdc" . "read_ready_i") . 0)) "fifo_read_ready"))
  (module->aliaspairs *owner-stream*)))

(defun bo-app-env (a cp cn zp zn up fail ready valid data)
  (let ((inputs (list up fail ready valid data)))
    (append (list (cons "app_clk_i" cn) (cons (flash-prev-key "app_clk_i") cp)
                  (cons "app_reset_n_i" zn) (cons (flash-prev-key "app_reset_n_i") zp))
            (pairlis$ (strip-cars *bo-app-fields*) a) (flash-old-fields *bo-app-fields* a)
            (pairlis$ (strip-cars *bo-app-inputs*) inputs) (flash-old-fields *bo-app-inputs* inputs))))

(assert-event
 (let ((keys (strip-cars (bo-app-env '(0 0 0 0 0 0) 0 0 0 0 0 0 0 0 0))))
   (and (no-duplicatesp-equal keys)
        (subsetp-equal (svexlist-vars (append *bo-app-equations* *bo-app-ports*)) keys))))

(defun bo-app-rtl-edge (a cp cn zp zn up fail ready valid data)
  (let ((env (bo-app-env a cp cn zp zn up fail ready valid data)))
    (with-fast-alist env (svexlist-eval *bo-app-equations* env))))
(defun bo-app-rtl-ports (a up fail ready valid data)
  (let ((env (bo-app-env a 0 0 1 1 up fail ready valid data)))
    (with-fast-alist env (svexlist-eval *bo-app-ports* env))))

(defun bo-app-init () '(0 0 0 0 0 0))
(defun bo-app-live-p (a) (and (equal (nth 2 a) 0) (equal (nth 5 a) 0)))
(defun bo-app-ready (a up fail)
  (if (and (bo-app-live-p a) (equal fail 0) (equal up 1) (equal (nth 0 a) 0)) 1 0))
(defun bo-app-valid (a up fail)
  (if (and (bo-app-live-p a) (equal fail 0) (equal up 1) (equal (nth 0 a) 1)) 1 0))
(defun bo-app-take-p (a re up fail ready)
  (and re (equal ready 1) (equal (bo-app-valid a up fail) 1)))
(defun bo-app-step (a re up fail ready valid data)
  (if (not re) a
    (let* ((pop (and (equal valid 1) (equal (bo-app-ready a up fail) 1)))
           (take (bo-app-take-p a re up fail ready))
           (lost (and (equal (nth 3 a) 1) (equal up 0) (equal (nth 5 a) 0)))
           (last-word (equal (nth 4 a) 227061)))
      (list (cond ((or (not (bo-app-live-p a)) (equal fail 1)) 0)
                  (pop 1) (take 0) (t (nth 0 a)))
            (if pop data (nth 1 a))
            (if (or (equal fail 1) lost) 1 (nth 2 a))
            (if (equal up 1) 1 (nth 3 a))
            (if (and take (not last-word)) (loghead 18 (1+ (ifix (nth 4 a)))) (nth 4 a))
            (if (and take last-word) 1 (nth 5 a))))))

(defun bo-app-state-p (a)
  (and (true-listp a) (equal (len a) 6)
       (unsigned-byte-p 1 (nth 0 a)) (unsigned-byte-p 256 (nth 1 a))
       (unsigned-byte-p 1 (nth 2 a)) (unsigned-byte-p 1 (nth 3 a))
       (unsigned-byte-p 18 (nth 4 a)) (unsigned-byte-p 1 (nth 5 a))))

(local (defconst *bo-app-shapes*
  (gl::auto-bindings (:nat cp 1) (:nat cn 1) (:nat zp 1) (:nat zn 1) (:nat up 1)
                     (:nat fail 1) (:nat ready 1) (:nat valid 1)
                     (:nat v 1) (:nat bad 1) (:nat started 1) (:nat done 1)
                     (:nat count 18) (:nat skid 256) (:nat data 256))))
(local (defconst *bo-app-bindings*
  (append (take 8 *bo-app-shapes*) (list (assoc-eq 'data *bo-app-shapes*))
          (list (list 'a (acl2::strip-cadrs
                          (list (assoc-eq 'v *bo-app-shapes*) (assoc-eq 'skid *bo-app-shapes*)
                                (assoc-eq 'bad *bo-app-shapes*) (assoc-eq 'started *bo-app-shapes*)
                                (assoc-eq 'count *bo-app-shapes*) (assoc-eq 'done *bo-app-shapes*))))))))

(gl::def-gl-thm bo-app-source-laws
  :hyp (and (bo-app-state-p a) (unsigned-byte-p 1 cp) (unsigned-byte-p 1 cn)
            (unsigned-byte-p 1 zp) (unsigned-byte-p 1 zn)
            (unsigned-byte-p 1 up) (unsigned-byte-p 1 fail) (unsigned-byte-p 1 ready)
            (unsigned-byte-p 1 valid) (unsigned-byte-p 256 data))
  :concl
  (let ((re (and (equal cp 0) (equal cn 1))))
    (and (implies (and (equal zp 1) (equal zn 1))
                  (equal (bo-app-rtl-edge a cp cn zp zn up fail ready valid data)
                         (bo-app-step a re up fail ready valid data)))
         (implies (and (equal zp 1) (equal zn 0))
                  (equal (bo-app-rtl-edge a cp cn zp zn up fail ready valid data) (bo-app-init)))
         (equal (bo-app-rtl-ports a up fail ready valid data)
                (list (bo-app-ready a up fail) (bo-app-valid a up fail) (nth 1 a)
                      (if (bo-app-take-p a t up fail ready) 1 0)
                      (if (and (equal valid 1) (equal (bo-app-ready a up fail) 1)) 1 0)))
         (bo-app-state-p (bo-app-step a re up fail ready valid data))))
  :g-bindings *bo-app-bindings*
  :rule-classes nil)

; Keep reset release at stationary low clocks separate from the enabled-edge
; comparison so the symbolic evaluator need not compare unrelated data words.
(gl::def-gl-thm bo-app-quiet-reset-release
  :hyp (and (bo-app-state-p a) (unsigned-byte-p 1 up) (unsigned-byte-p 1 fail)
            (unsigned-byte-p 1 ready) (unsigned-byte-p 1 valid) (unsigned-byte-p 256 data))
  :concl (equal (bo-app-rtl-edge a 0 0 0 1 up fail ready valid data) a)
  :g-bindings (nthcdr 4 *bo-app-bindings*)
  :rule-classes nil)

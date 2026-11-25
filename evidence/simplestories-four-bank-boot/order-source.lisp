(in-package "SV")
(include-book "fifo-write")

; The register list is shared by both clock domains. The clocks are sampled
; independently. Both sets of nonblocking assignments read this same old list,
; including the old storage when read prefetch coincides with a write.
(defconst *bo-source-fields*
  '(("write_binary_q" . 3) ("write_gray_q" . 3)
    ("read_gray_write_sync1_q" . 3) ("read_gray_write_sync2_q" . 3)
    ("write_full_q" . 1) ("read_binary_q" . 3) ("read_gray_q" . 3)
    ("write_gray_read_sync1_q" . 3) ("write_gray_read_sync2_q" . 3)
    ("read_empty_q" . 1) ("read_data_q" . 256) ("storage_q" . 1024)))
(defconst *bo-source-inputs*
  '(("write_valid_i" . 1) ("write_data_i" . 256) ("read_ready_i" . 1)))
(defconst *bo-source-read-gates*
  '(("read_valid_o" . 1) ("read_transfer" . 1) ("read_binary_next" . 3)
    ("read_gray_next" . 3) ("read_empty_next" . 1)))
(defconst *bo-source-gates*
  (stream-compose-gates *bo-source-read-gates* *fifo-write-assigns* *fifo-write-gates*))
(defconst *bo-source-equations*
  (let ((sampled (stream-sampled-gates *bo-source-gates*)))
    (with-fast-alist sampled
      (svexlist-compose (flash-drivers *bo-source-fields* *fifo-write-assigns*) sampled))))
(defconst *bo-source-port-equations*
  (flash-drivers '(("write_ready_o" . 1) ("read_valid_o" . 1) ("read_data_o" . 256))
                 *fifo-write-assigns*))

(assert-event
 (and (set-equiv (strip-cars *fifo-write-assigns*)
                 (append (flash-lhss *bo-source-fields*) (list '((256 . "read_data_o")))
                         (flash-lhss *bo-source-read-gates*)
                         (flash-lhss '(("write_ready_o" . 1) ("write_transfer" . 1)
                                       ("write_binary_next" . 3) ("write_gray_next" . 3)
                                       ("write_full_next" . 1)))))
      (subsetp-equal
       '((((:var ("u_loader_cdc" . "read_clk_i") . 0)) "app_clk_i")
         (((:var ("u_loader_cdc" . "read_reset_n_i") . 0)) "app_reset_n_i")
         (((256 :var ("u_loader_cdc" . "read_data_o") . 0)) (256 . "fifo_read_data"))
         (((:var ("u_loader_cdc" . "read_valid_o") . 0)) "fifo_read_valid")
         (((:var ("u_loader_cdc" . "read_ready_i") . 0)) "fifo_read_ready"))
       (module->aliaspairs *owner-stream*))))

; wprev/wnow and rprev/rnow are the respective previous/current clock
; levels. Both FIFO reset_n ports have the same previous/current level
; only at this common-reset boundary and during the released epoch.
(defun bo-source-env (s wprev wnow rprev rnow rstprev rstnow wvalid wdata rready)
  (let ((inputs (list wvalid wdata rready)))
    (append (list (cons "write_clk_i" wnow) (cons (flash-prev-key "write_clk_i") wprev)
                  (cons "read_clk_i" rnow) (cons (flash-prev-key "read_clk_i") rprev)
                  (cons "write_reset_n_i" rstnow) (cons (flash-prev-key "write_reset_n_i") rstprev)
                  (cons "read_reset_n_i" rstnow) (cons (flash-prev-key "read_reset_n_i") rstprev))
            (pairlis$ (strip-cars *bo-source-fields*) s)
            (flash-old-fields *bo-source-fields* s)
            (pairlis$ (strip-cars *bo-source-inputs*) inputs)
            (flash-old-fields *bo-source-inputs* inputs))))

(assert-event
 (let ((keys (strip-cars (bo-source-env nil 0 0 0 0 0 0 0 0 0))))
   (and (no-duplicatesp-equal keys)
        (subsetp-equal (svexlist-vars *bo-source-equations*) keys)
        (set-equiv (svexlist-vars *bo-source-port-equations*)
                   '("write_full_q" "read_empty_q" "read_data_q")))))

(defun bo-source-edge (s wprev wnow rprev rnow rstprev rstnow wvalid wdata rready)
  (let ((env (bo-source-env s wprev wnow rprev rnow rstprev rstnow wvalid wdata rready)))
    (with-fast-alist env (svexlist-eval *bo-source-equations* env))))

(defun bo-source-ports (s)
  (let ((env (pairlis$ (strip-cars *bo-source-fields*) s)))
    (with-fast-alist env (svexlist-eval *bo-source-port-equations* env))))

(defun bo-source-rise-p (prev now)
  (and (equal prev 0) (equal now 1)))

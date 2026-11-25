(in-package "SV")
(include-book "order-source")
(include-book "order-model")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (gl::def-gl-clause-processor bo-source-glcp))
(local (gl::gl-bdd-mode))

; A shape for the complete register list. The symbols in state-shapes only
; name the twelve shapes; S is the single argument bound to their list.
(local (defconst *bo-source-shapes*
  (gl::auto-bindings (:nat wprev 1) (:nat wnow 1) (:nat rprev 1) (:nat rnow 1)
                     (:nat wvalid 1) (:nat rready 1) (:nat event 60)
                     (:nat wp 3) (:nat wg 3) (:nat rs1 3) (:nat rs2 3)
                     (:nat full 1) (:nat rp 3) (:nat rg 3) (:nat ws1 3) (:nat ws2 3)
                     (:nat empty 1) (:nat rddata 256) (:nat memory 1024) (:nat wdata 256))))
(local (defconst *bo-source-gl-bindings*
  (append (take 6 *bo-source-shapes*)
          (list (list 's (acl2::strip-cadrs (take 12 (nthcdr 7 *bo-source-shapes*)))))
          (list (assoc-eq 'wdata *bo-source-shapes*)))))

(gl::def-gl-thm bo-source-edge-is-step
  :hyp (and (bo-fifo-state-p s)
            (unsigned-byte-p 1 wprev) (unsigned-byte-p 1 wnow)
            (unsigned-byte-p 1 rprev) (unsigned-byte-p 1 rnow)
            (unsigned-byte-p 1 wvalid) (unsigned-byte-p 1 rready) (unsigned-byte-p 256 wdata))
  :concl (equal (bo-source-edge s wprev wnow rprev rnow 1 1 wvalid wdata rready)
                (bo-fifo-step s (bo-source-rise-p wprev wnow) (bo-source-rise-p rprev rnow)
                              wvalid wdata rready))
  :g-bindings *bo-source-gl-bindings*
  :rule-classes nil)

(gl::def-gl-thm bo-source-common-reset
  :hyp (and (bo-fifo-state-p s)
            (unsigned-byte-p 1 wprev) (unsigned-byte-p 1 wnow)
            (unsigned-byte-p 1 rprev) (unsigned-byte-p 1 rnow)
            (unsigned-byte-p 1 wvalid) (unsigned-byte-p 1 rready) (unsigned-byte-p 256 wdata))
  :concl (equal (bo-source-edge s wprev wnow rprev rnow 1 0 wvalid wdata rready)
                (bo-fifo-init (nth 11 s)))
  :g-bindings *bo-source-gl-bindings*
  :rule-classes nil)

(gl::def-gl-thm bo-source-reset-release
  :hyp (and (bo-fifo-state-p s)
            (unsigned-byte-p 1 wprev) (unsigned-byte-p 1 wnow)
            (unsigned-byte-p 1 rprev) (unsigned-byte-p 1 rnow)
            (not (bo-source-rise-p wprev wnow)) (not (bo-source-rise-p rprev rnow))
            (unsigned-byte-p 1 wvalid) (unsigned-byte-p 1 rready) (unsigned-byte-p 256 wdata))
  :concl (equal (bo-source-edge s wprev wnow rprev rnow 0 1 wvalid wdata rready) s)
  :g-bindings *bo-source-gl-bindings*
  :rule-classes nil)

(gl::def-gl-thm bo-source-port-law
  :hyp (bo-fifo-state-p s)
  :concl (equal (bo-source-ports s)
                (list (if (equal (nth 4 s) 0) 1 0) (if (equal (nth 9 s) 0) 1 0) (nth 10 s)))
  :g-bindings (list (assoc-eq 's *bo-source-gl-bindings*))
  :rule-classes nil)

; Match the exact write observation used by the pin-to-storage book (#45),
; including a same-data overwrite. Its 60-bit stream event fixes the two
; trusted clock and reset samples; the app clock is still arbitrary.
(gl::def-gl-thm bo-source-projects-packing-write
  :hyp (and (bo-fifo-state-p s) (unsigned-byte-p 60 event)
            (unsigned-byte-p 1 rprev) (unsigned-byte-p 1 rnow)
            (unsigned-byte-p 1 wvalid) (unsigned-byte-p 256 wdata) (unsigned-byte-p 1 rready))
  :concl
  (let* ((we (stream-rise-p event)) (level (loghead 1 (logtail 5 (ifix event))))
         (rst (stream-current-trusted-reset-n event))
         (next (bo-source-edge s (if we 0 level) (if we 1 level) rprev rnow
                               (stream-previous-trusted-reset-n event) rst wvalid wdata rready)))
    (and (equal (list (nth 0 next) (nth 4 next) (nth 11 next))
                (fifo-write-edge (nth 0 s) (nth 4 s) (nth 11 s) (nth 3 s) wdata wvalid event))
         (iff (and (equal rst 1) (bo-fifo-push-p s we wvalid))
              (fifo-write-strobe-p (nth 4 s) wvalid event))))
  :g-bindings
  (cons (assoc-eq 'event *bo-source-shapes*)
        (list (assoc-eq 'rprev *bo-source-gl-bindings*)
                (assoc-eq 'rnow *bo-source-gl-bindings*)
                (assoc-eq 'wvalid *bo-source-gl-bindings*)
                (assoc-eq 'rready *bo-source-gl-bindings*)
                (assoc-eq 's *bo-source-gl-bindings*)
                (assoc-eq 'wdata *bo-source-gl-bindings*)))
  :rule-classes nil)

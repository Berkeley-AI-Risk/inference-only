(in-package "SV")
(include-book "order-history")
(local (include-book "centaur/gl/gl" :dir :system))
(local (include-book "centaur/sv/svex/gl-rules" :dir :system))
(local (include-book "centaur/bitops/ihsext-basics" :dir :system))
(local (gl::def-gl-clause-processor bo-reset-glcp))
(local (gl::gl-bdd-mode))

; Complete the released, nonclocking cases for the application registers.
; order-app has the low -> low case. The two cases here have a high old
; clock, so the data input and the old 256-bit skid word may be independent.
(local (defconst *bo-release-shapes*
  (gl::auto-bindings (:nat up 1) (:nat fail 1) (:nat ready 1) (:nat valid 1)
                     (:nat v 1) (:nat bad 1) (:nat started 1) (:nat done 1)
                     (:nat count 18) (:nat skid 256) (:nat data 256))))
(local (defconst *bo-release-bindings*
  (append (take 4 *bo-release-shapes*) (list (assoc-eq 'data *bo-release-shapes*))
          (list (list 'a (acl2::strip-cadrs
                          (list (assoc-eq 'v *bo-release-shapes*) (assoc-eq 'skid *bo-release-shapes*)
                                (assoc-eq 'bad *bo-release-shapes*) (assoc-eq 'started *bo-release-shapes*)
                                (assoc-eq 'count *bo-release-shapes*) (assoc-eq 'done *bo-release-shapes*))))))))

(local (gl::def-gl-thm bo-app-high-clock-release
  :hyp (and (bo-app-state-p a) (unsigned-byte-p 1 up) (unsigned-byte-p 1 fail)
            (unsigned-byte-p 1 ready) (unsigned-byte-p 1 valid) (unsigned-byte-p 256 data))
  :concl (and (equal (bo-app-rtl-edge a 1 1 0 1 up fail ready valid data) a)
              (equal (bo-app-rtl-edge a 1 0 0 1 up fail ready valid data) a))
  :g-bindings *bo-release-bindings*
  :rule-classes nil))

(local (defthm bo-clock-values
  (implies (unsigned-byte-p 1 x) (or (equal x 0) (equal x 1)))
  :hints (("Goal" :in-theory (enable unsigned-byte-p)))
  :rule-classes nil))

(defthm bo-app-quiet-common-release
  (implies (and (bo-app-state-p a) (unsigned-byte-p 1 cp) (unsigned-byte-p 1 cn)
                (not (bo-source-rise-p cp cn))
                (unsigned-byte-p 1 up) (unsigned-byte-p 1 fail) (unsigned-byte-p 1 ready)
                (unsigned-byte-p 1 valid) (unsigned-byte-p 256 data))
           (equal (bo-app-rtl-edge a cp cn 0 1 up fail ready valid data) a))
  :hints (("Goal" :use (bo-app-quiet-reset-release bo-app-high-clock-release
                        (:instance bo-clock-values (x cp)) (:instance bo-clock-values (x cn)))
           :in-theory '(bo-source-rise-p)))
  :rule-classes nil)

; Use the same extracted pre-edge ports as the released raw-history cycle.
; Each event supplies its new trusted and app clock levels, independent data
; and all stream controls. Both physical reset_n ports share the transition.
(defun bo-reset-edges (s a wp rp zp zn e)
  (let* ((f (bo-source-ports s))
         (app (bo-app-rtl-ports a (bo-up e) (bo-fail e) (bo-ready e) (nth 1 f) (nth 2 f))))
    (list (bo-source-edge s wp (bo-wn e) rp (bo-rn e) zp zn
                          (bo-wv e) (bo-word e) (car app))
          (bo-app-rtl-edge a rp (bo-rn e) zp zn (bo-up e) (bo-fail e) (bo-ready e)
                           (nth 1 f) (nth 2 f)))))

(local (defthm bo-reset-input-widths
  (and (unsigned-byte-p 1 (bo-wn e)) (unsigned-byte-p 1 (bo-rn e))
       (unsigned-byte-p 1 (bo-wv e)) (unsigned-byte-p 1 (bo-ready e))
       (unsigned-byte-p 1 (bo-up e)) (unsigned-byte-p 1 (bo-fail e))
       (unsigned-byte-p 256 (bo-word e)) (unsigned-byte-p 1 (bo-app-ready a up fail)))
  :hints (("Goal" :in-theory (disable loghead logtail unsigned-byte-p)))))

(local (defthm bo-reset-storage-bounds
  (implies (bo-fifo-state-p s)
           (and (unsigned-byte-p 256 (nth 10 s)) (unsigned-byte-p 1024 (nth 11 s))))
  :hints (("Goal" :in-theory (enable bo-fifo-state-p)))))

(local (defthm bo-reset-states-shaped
  (implies (unsigned-byte-p 1024 m)
           (and (bo-fifo-state-p (bo-fifo-init m)) (bo-app-state-p (bo-app-init))))
  :hints (("Goal" :in-theory (enable bo-fifo-state-p bo-app-state-p)))))

(local (in-theory (disable bo-wn bo-rn bo-wv bo-word bo-ready bo-up bo-fail
                           bo-source-rise-p bo-fifo-init bo-app-init bo-app-state-p bo-fifo-state-p
                           bo-app-ready bo-app-valid bo-app-take-p bo-app-step
                           bo-app-rtl-ports bo-app-rtl-edge bo-source-edge bo-source-ports
                           unsigned-byte-p)))

(defthm bo-stream-common-assertion
  (implies (and (bo-fifo-state-p s) (bo-app-state-p a)
                (unsigned-byte-p 1 wp) (unsigned-byte-p 1 rp))
           (equal (bo-reset-edges s a wp rp 1 0 e)
                  (list (bo-fifo-init (nth 11 s)) (bo-app-init))))
  :hints (("Goal"
           :use (bo-source-port-law
                 (:instance bo-source-common-reset (wprev wp) (wnow (bo-wn e))
                            (rprev rp) (rnow (bo-rn e)) (wvalid (bo-wv e)) (wdata (bo-word e))
                            (rready (bo-app-ready a (bo-up e) (bo-fail e))))
                 (:instance bo-app-source-laws (cp rp) (cn (bo-rn e)) (zp 1) (zn 0)
                            (up (bo-up e)) (fail (bo-fail e)) (ready (bo-ready e))
                            (valid (if (equal (nth 9 s) 0) 1 0)) (data (nth 10 s))))))
  :rule-classes nil)

(defthm bo-stream-quiet-release
  (implies (and (bo-fifo-state-p s) (bo-app-state-p a)
                (unsigned-byte-p 1 wp) (unsigned-byte-p 1 rp)
                (not (bo-source-rise-p wp (bo-wn e))) (not (bo-source-rise-p rp (bo-rn e))))
           (equal (bo-reset-edges s a wp rp 0 1 e) (list s a)))
  :hints (("Goal"
           :use (bo-source-port-law
                 (:instance bo-source-reset-release (wprev wp) (wnow (bo-wn e))
                            (rprev rp) (rnow (bo-rn e)) (wvalid (bo-wv e)) (wdata (bo-word e))
                            (rready (bo-app-ready a (bo-up e) (bo-fail e))))
                 (:instance bo-app-source-laws (cp rp) (cn (bo-rn e)) (zp 1) (zn 1)
                            (up (bo-up e)) (fail (bo-fail e)) (ready (bo-ready e))
                            (valid (if (equal (nth 9 s) 0) 1 0)) (data (nth 10 s)))
                 (:instance bo-app-quiet-common-release (cp rp) (cn (bo-rn e))
                            (up (bo-up e)) (fail (bo-fail e)) (ready (bo-ready e))
                            (valid (if (equal (nth 9 s) 0) 1 0)) (data (nth 10 s))))))
  :rule-classes nil)

(defthm every-boot-loader-acceptance-after-common-reset-is-an-in-order-storage-write
  (implies (and (bo-fifo-state-p s) (bo-app-state-p a)
                (unsigned-byte-p 1 wp) (unsigned-byte-p 1 rp)
                (not (bo-source-rise-p (bo-wn assert-inputs) (bo-wn release-inputs)))
                (not (bo-source-rise-p (bo-rn assert-inputs) (bo-rn release-inputs))))
    (let* ((held (bo-reset-edges s a wp rp 1 0 assert-inputs))
           (released (bo-reset-edges (car held) (cadr held) (bo-wn assert-inputs)
                                     (bo-rn assert-inputs) 0 1 release-inputs))
           (observed (bo-observe-history (car released) (cadr released) (bo-wn release-inputs)
                                         (bo-rn release-inputs) events nil nil)))
      (and (equal held (list (bo-fifo-init (nth 11 s)) (bo-app-init)))
           (equal released held)
           (bo-prefix-p (nth 1 observed) (nth 0 observed)))))
  :hints (("Goal"
           :in-theory (disable bo-reset-edges bo-prefix-p bo-observe-history)
           :use ((:instance bo-stream-common-assertion (e assert-inputs))
                 (:instance bo-stream-quiet-release (e release-inputs) (wp (bo-wn assert-inputs))
                            (rp (bo-rn assert-inputs)) (s (bo-fifo-init (nth 11 s))) (a (bo-app-init)))
                 (:instance every-boot-loader-acceptance-is-an-in-order-storage-write
                            (memory (nth 11 s)) (wp (bo-wn release-inputs)) (rp (bo-rn release-inputs))))))
  :rule-classes nil)

; WHAT TWO DEFINITIONS OF THE SPECIFICATION COMPUTE.
;
; Private.  See README.md in this directory.
;
; ssv-spec defines the square root and the shared exponent by the steps the
; released oracle takes.  This book proves what those steps arrive at:
;
;   ssv-isqrt-is-the-floor-square-root
;       r = (ssv-isqrt n) is the natural number with r*r <= n < (r+1)*(r+1).
;
;   ssv-select-exponent-is-locally-finest
;       when some value is nonzero and the search does not run out of the
;       exponent range, the shared exponent e is in [-32, 31], every value
;       rounded to e is a legal mantissa, and -- unless e is -32 -- some
;       value rounded to e-1 is not.
(in-package "ACL2")
(include-book "ssv-spec")
(local (include-book "arithmetic/top-with-meta" :dir :system))
(local (include-book "centaur/bitops/integer-length" :dir :system))

; ---------------------------------------------------------------------------
; The square root.
; ---------------------------------------------------------------------------
(local
 (defthm ssv-two-halves
   (implies (posp bits)
            (equal (expt 2 bits) (+ (expt 2 (+ -1 bits)) (expt 2 (+ -1 bits)))))
   :hints (("Goal" :in-theory (enable expt)))
   :rule-classes nil))
(local
 (defthm ssv-isqrt-bits-invariant
   (implies (and (natp bits) (natp root) (natp n)
                 (<= (* root root) n)
                 (< n (* (+ root (expt 2 bits)) (+ root (expt 2 bits)))))
            (let ((r (ssv-isqrt-bits bits root n)))
              (and (natp r)
                   (<= (* r r) n)
                   (< n (* (+ r 1) (+ r 1))))))
   :hints (("Goal" :induct (ssv-isqrt-bits bits root n)
            :in-theory (e/d (ssv-isqrt-bits) (expt)))
           ("Subgoal *1/2" :use ((:instance ssv-two-halves))))
   :rule-classes nil))
(local
 (defthm ssv-below-two-to-its-length
   (implies (natp n) (< n (expt 2 (integer-length n))))
   :hints (("Goal" :use ((:instance bitops::integer-length-expt-upper-bound-n))
            :in-theory (disable bitops::integer-length-expt-upper-bound-n)))
   :rule-classes nil))
(local
 (defthm ssv-square-of-larger
   (implies (and (natp n) (natp m) (< n m)) (< n (* m m)))
   :hints (("Goal" :nonlinearp t))
   :rule-classes nil))
(defthm ssv-isqrt-is-the-floor-square-root
  (implies (natp n)
           (let ((r (ssv-isqrt n)))
             (and (natp r)
                  (<= (* r r) n)
                  (< n (* (+ r 1) (+ r 1))))))
  :hints (("Goal"
           :use ((:instance ssv-isqrt-bits-invariant
                            (bits (integer-length n)) (root 0))
                 (:instance ssv-below-two-to-its-length)
                 (:instance ssv-square-of-larger (m (expt 2 (integer-length n)))))
           :in-theory (e/d (ssv-isqrt) (ssv-isqrt-bits expt integer-length))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The shared exponent.
; ---------------------------------------------------------------------------
(local
 (defthm ssv-exponent-up-result
   (implies (and (integerp e) (<= e 31))
            (let ((u (ssv-exponent-up values exps e)))
              (and (integerp u)
                   (<= e u)
                   (or (equal u 32) (ssv-fits values exps u)))))
   :hints (("Goal" :induct (ssv-exponent-up values exps e)
            :in-theory (e/d (ssv-exponent-up) (ssv-fits))))
   :rule-classes nil))
(local
 (defthm ssv-exponent-down-result
   (implies (integerp e)
            (let ((d (ssv-exponent-down values exps e)))
              (and (integerp d)
                   (<= d e)
                   (or (equal d e) (ssv-fits values exps d))
                   (or (<= d -32) (<= e -32)
                       (not (ssv-fits values exps (- d 1)))))))
   :hints (("Goal" :induct (ssv-exponent-down values exps e)
            :in-theory (e/d (ssv-exponent-down) (ssv-fits))))
   :rule-classes nil))
(local
 (defthm ssv-exponent-down-stays-above
   (implies (and (integerp e) (<= -32 e))
            (<= -32 (ssv-exponent-down values exps e)))
   :hints (("Goal" :induct (ssv-exponent-down values exps e)
            :in-theory (e/d (ssv-exponent-down) (ssv-fits))))
   :rule-classes nil))
(local
 (defthm ssv-candidate-type
   (or (not (ssv-candidate values exps))
       (integerp (ssv-candidate values exps))
       (not (integer-listp exps)))
   :hints (("Goal" :induct (ssv-candidate values exps)
            :in-theory (enable ssv-candidate)))
   :rule-classes nil))
(defthm ssv-select-exponent-is-locally-finest
  (let ((e (ssv-select-exponent values exps)))
    (implies (and (integer-listp exps)
                  (ssv-candidate values exps)     ; some value is nonzero
                  (<= e 31))                      ; the search stayed in range
             (and (integerp e)
                  (<= -32 e)
                  (ssv-fits values exps e)
                  (or (equal e -32)
                      (not (ssv-fits values exps (- e 1)))))))
  :hints (("Goal"
           :use ((:instance ssv-candidate-type)
                 (:instance ssv-exponent-up-result
                            (e (max -32 (min 31 (ssv-candidate values exps)))))
                 (:instance ssv-exponent-down-result
                            (e (ssv-exponent-up values exps
                                                (max -32 (min 31 (ssv-candidate values exps))))))
                 (:instance ssv-exponent-down-stays-above
                            (e (ssv-exponent-up values exps
                                                (max -32 (min 31 (ssv-candidate values exps)))))))
           :in-theory (e/d (ssv-select-exponent)
                           (ssv-fits ssv-exponent-up ssv-exponent-down ssv-candidate))))
  :rule-classes nil)

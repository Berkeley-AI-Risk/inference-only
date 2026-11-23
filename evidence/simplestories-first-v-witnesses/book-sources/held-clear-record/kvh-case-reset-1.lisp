; A reset cycle, CLEAR held: the reset-reading registers agree at the sampling edge.
;
; Written by make_case_books.py; do not edit.  Private.  See README.md.
;
; One of four cases of a clock cycle.  In this one the cycle's reset_n_i is
; 0 and its clear_i is 1, and no override is set.
;
; The two alists compared are (kvh-oc ...) and (kvh-oh ...) of kvh-two-phase:
; the reset-reading registers and the reset nets in the clock-low phase of
; the corrected-cycle machine and of the held-input machine, as expressions
; over the stored state before the cycle, the inputs, and fresh variables
; for the stored data that is not kept between the phases.
;
;   kvh-reset-1-solver
;       For EVERY environment (every stored state, every input, every value
;       of the fresh variables): if the stored clock levels are low, the stored root reset and the
;       seven stored derived resets are asserted, and the sampled reset nets
;       and guard registers are two-valued,
;       then the 943 registers have the same values in both machines,
;       the three loop variables hold 6, 2 and 6, and the seven derived
;       resets are asserted.
;       FGL turns this into a propositional formula; the solver's answer of
;       "unsatisfiable" is accepted only after ACL2 has checked the solver's
;       proof (satlink with :lrat-check t).
;   kvh-reset-1-registers
;       The same, with the library's evaluator written out.
(in-package "SV")
(include-book "kvh-two-phase")

(value-triple (acl2::set-max-mem (* 96 (expt 2 30))))
(acl2::set-slow-alist-action nil)
(value-triple (acl2::tshell-ensure))

; the solver's proofs are checked (the configuration is the chain's)
(defthm kvh-reset-1-sat-proofs-are-checked
  (equal (satlink::config->lrat-check (bct-satlink-config)) t)
  :rule-classes nil)

(value-triple (acl2::cw "~%KVH-CASE kvh-reset-1: solver starts~%"))
(fgl::def-fgl-thm kvh-reset-1-solver
  (let ((oc (kvh-oc (kvh-reset-consts) (kvh-x 0 1)))
        (oh (kvh-oh (kvh-reset-consts) (kvh-x 0 1) (kvh-x 0 1))))
    (implies (and
                  (kvh-2vec-list-p
                   (svexlist-eval-for-symbolic (kvh-zx-exprs (kvh-rgw) oh)
                                               env '((:allvars)))))
             (and (equal (svexlist-eval-for-symbolic (kvh-lookup-exprs (kvh-q1) oc)
                                                     env '((:allvars)))
                         (svexlist-eval-for-symbolic (kvh-lookup-exprs (kvh-q1) oh)
                                                     env '((:allvars))))
                  (equal (svexlist-eval-for-symbolic
                          (kvh-lookup-exprs (strip-cars (kvh-loop3w)) oh)
                          env '((:allvars)))
                         '(6 2 6))
                  (equal (svexlist-eval-for-symbolic (kvh-zx-exprs (kvh-rnw) oh)
                                                     env '((:allvars)))
                         '(0 0 0 0 0 0 0))))))
(value-triple (acl2::cw "~%KVH-CASE kvh-reset-1: solver theorem proved~%"))

(defthm kvh-reset-1-registers
  (let ((oc (kvh-oc (kvh-reset-consts) (kvh-x 0 1)))
        (oh (kvh-oh (kvh-reset-consts) (kvh-x 0 1) (kvh-x 0 1))))
    (implies (and
                  (kvh-2vec-list-p (kvh-zx-vals (kvh-rgw) (svex-alist-eval oh env))))
             (and (equal (kvh-env-vals (kvh-q1) (svex-alist-eval oc env))
                         (kvh-env-vals (kvh-q1) (svex-alist-eval oh env)))
                  (equal (kvh-env-vals (strip-cars (kvh-loop3w)) (svex-alist-eval oh env))
                         '(6 2 6))
                  (equal (kvh-zx-vals (kvh-rnw) (svex-alist-eval oh env))
                         '(0 0 0 0 0 0 0)))))
  :hints (("Goal" :use ((:instance kvh-reset-1-solver))
           :in-theory '(svexlist-eval-for-symbolic
                        kvh-eval-of-zx-exprs
                        kvh-eval-of-zxvar-exprs
                        kvh-eval-of-lookup-exprs)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVH-CASE kvh-reset-1 done~%"))

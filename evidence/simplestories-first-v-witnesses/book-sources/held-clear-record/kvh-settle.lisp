; The register cut, for the probe: a phase step is determined by its inputs
; and its register values.
;
; Private.  See README.md in this directory.
;
;   kvh-p-is-transparent-for-registers
;       The phase machine is override-transparent for its 1,339 registers:
;       overriding a register with the value it has anyway changes nothing.
;       The library's own syntactic check establishes it.
;   kvh-settle-check-holds
;       With every register overridden, the next state and the signals that
;       are not registers read no stored variable.  ACL2 evaluates this check
;       on the machine's expressions.
;   kvh-probe-settles
;       THE CONSEQUENCE.  Two phase steps with the same inputs, from two
;       different stored states, that give the registers the same values
;       give every signal the same value and leave the same stored state.
(in-package "SV")
(include-book "kvh-machines")
(local (include-book "centaur/sv/svtv/fsm-override-smart-check" :dir :system))

(make-event
 '(def-override-transparent kvh-p-is-transparent-for-registers
    :fsm (kvh-p) :keys (kvh-regs)))

(define kvh-settle-check ()
  :verify-guards nil
  (and (svarlist-override-p (kvh-regs) nil)
       (not (intersectp-equal (svex-alist-vars (kvh-cut (kvh-nx) (kvh-regs)))
                              (kvh-statekeys)))
       (not (intersectp-equal
             (svex-alist-vars (kvh-cut (svex-alist-extract (kvh-others) (kvh-vals))
                                       (kvh-regs)))
             (kvh-statekeys)))
       (subsetp-equal (svex-alist-keys (kvh-vals))
                      (append (svarlist-fix (kvh-regs)) (svarlist-fix (kvh-others))))
       (no-duplicatesp-equal (svex-alist-keys (kvh-vals))))
  ///
  (in-theory (disable (:executable-counterpart kvh-settle-check))))

(defthm kvh-settle-check-holds
  (kvh-settle-check)
  :hints (("Goal" :in-theory '((:executable-counterpart kvh-settle-check))))
  :rule-classes nil)

(defthm kvh-probe-settles
  (implies (and (kv-plain-env-p e)
                (svex-envs-agree (kvh-regs)
                                 (fsm-step-outs e a (kvh-p))
                                 (fsm-step-outs e b (kvh-p))))
           (and (equal (fsm-step e a (kvh-nx))
                       (fsm-step e b (kvh-nx)))
                (equal (fsm-step-outs e a (kvh-p))
                       (fsm-step-outs e b (kvh-p)))))
  :hints (("Goal"
           :use ((:instance kvh-settle-nextstate
                  (nx (kvh-nx)) (vals (kvh-vals)) (keys (kvh-regs)))
                 (:instance kvh-settle-values
                  (nx (kvh-nx)) (vals (kvh-vals)) (keys (kvh-regs)) (others (kvh-others)))
                 (:instance kvh-settle-check-holds)
                 (:instance kvh-p-is-transparent-for-registers)
                 (:instance kvh-tests-unset-when-plain (keys (kvh-regs))))
           :in-theory '(fsm-step fsm-step-outs kvh-settle-check
                        fsm-overridekey-transparent-p
                        kvh-statekeys-are-not-overrides)))
  :rule-classes nil)

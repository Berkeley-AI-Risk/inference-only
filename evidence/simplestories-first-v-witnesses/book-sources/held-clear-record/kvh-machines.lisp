; The two clock models of the SimpleStories probe, and what is read off the
; translated design.
;
; Private.  See README.md in this directory.
;
; The design is the one of the corrected-cycle chain: this book loads that
; chain's certified book kv-joined-lemmas and translates nothing.
;
;   (kvh-p)             the phase-level machine of the probe: one step is half
;                       a clock cycle.  It is the machine the chain's cycle
;                       machine (probe-fsm) is made of.
;   (probe-fsm)         THE CORRECTED-CYCLE MACHINE, from the chain: a cycle is
;                       a clock-high phase in which reset_n_i is 1, clear_i is
;                       0 and every other input is unknown, then a clock-low
;                       phase in which the cycle's inputs are applied and the
;                       signals are recorded.
;   (probe-fsm-held)    THE HELD-INPUT MACHINE, defined here: the cycle's
;                       inputs are applied in both phases.
;
; The rest of the book names sets of signals of the design and records
; facts about the design's expressions that ACL2 establishes by evaluating a
; check on them.  The sets are found by untrusted code below; nothing rests
; on how they were found, only on the checks.
(in-package "SV")
(include-book "../corrected-cycle/kv-joined-book-checked-sat/kv-joined-lemmas")
(include-book "kvh-generic")
(local (include-book "centaur/sv/svtv/fsm-override-smart-check" :dir :system))
(local (include-book "std/lists/sets" :dir :system))

(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)

; ===========================================================================
; The phase machine and the two cycles.
; ===========================================================================
(define kvh-p ()
  :returns (x fsm-p)
  (svtv-spec->fsm (join-reset-spec))
  ///
  (in-theory (disable (:executable-counterpart kvh-p))))

(defmacro kvh-nx () '(fsm->nextstate (kvh-p)))
(defmacro kvh-vals () '(fsm->values (kvh-p)))
(defmacro kvh-statekeys () '(svex-alist-keys (fsm->nextstate (kvh-p))))

; the clock-high phase of the corrected cycle
(define kvh-c-hi ()
  :returns (ph svtv-cyclephase-p)
  (make-svtv-cyclephase :constants '(("core_clk_i" . 1) ("app_clk_i" . 1)
                                     ("reset_n_i" . 1) ("clear_i" . 0))
                        :inputs-free nil :outputs-captured nil)
  ///
  (in-theory (disable (:executable-counterpart kvh-c-hi))))

; the clock-high phase of the held-input cycle
(define kvh-h-hi ()
  :returns (ph svtv-cyclephase-p)
  (make-svtv-cyclephase :constants '(("core_clk_i" . 1) ("app_clk_i" . 1))
                        :inputs-free t :outputs-captured nil)
  ///
  (in-theory (disable (:executable-counterpart kvh-h-hi))))

; the clock-low phase of both
(define kvh-lo ()
  :returns (ph svtv-cyclephase-p)
  (make-svtv-cyclephase :constants '(("core_clk_i" . 0) ("app_clk_i" . 0))
                        :inputs-free t :outputs-captured t)
  ///
  (in-theory (disable (:executable-counterpart kvh-lo))))

; THE HELD-INPUT MACHINE.
(define probe-fsm-held ()
  :returns (fsm fsm-p)
  :verify-guards nil
  (fsm-to-cycle (list (kvh-h-hi) (kvh-lo)) (kvh-p) nil)
  ///
  (in-theory (disable (:executable-counterpart probe-fsm-held))))

; the corrected-cycle machine is the same construction with its own
; clock-high phase
(local
 (defthm kvh-corrected-cycle-phases
   (equal (svtv-spec->cycle-phases (join-reset-spec))
          (list (kvh-c-hi) (kvh-lo)))
   :hints (("Goal" :in-theory '((:executable-counterpart svtv-spec->cycle-phases$inline)
                                (:executable-counterpart join-reset-spec)
                                (:executable-counterpart kvh-c-hi)
                                (:executable-counterpart kvh-lo)
                                (:executable-counterpart cons)
                                (:executable-counterpart equal))))))

(defthm probe-fsm-is-the-corrected-cycle
  (equal (probe-fsm)
         (fsm-to-cycle (list (kvh-c-hi) (kvh-lo)) (kvh-p) nil))
  :hints (("Goal" :in-theory '(probe-fsm svtv-spec->cycle-fsm kvh-p
                               kvh-corrected-cycle-phases)))
  :rule-classes nil)

(defthm kvh-statekeys-have-no-duplicates
  (no-duplicatesp-equal (kvh-statekeys))
  :hints (("Goal" :in-theory '(kvh-p no-duplicate-state-keys-of-join-reset-spec))))

(defthm kvh-statekeys-are-not-overrides
  (svarlist-override-p (kvh-statekeys) nil)
  :hints (("Goal" :in-theory '(kvh-p nextstate-keys-non-override-of-join-reset-spec))))

; ===========================================================================
; Sets of signals, read off the design by untrusted code.
; ===========================================================================
(local
 (progn
   (defun kvhx-has-delayed (vars)
     (declare (xargs :mode :program))
     (if (atom vars) nil
       (or (not (eql 0 (svar->delay (car vars)))) (kvhx-has-delayed (cdr vars)))))
   ; registers: signals whose assignment reads a stored value
   (defun kvhx-registers (assigns acc)
     (declare (xargs :mode :program))
     (if (atom assigns) (reverse acc)
       (kvhx-registers (cdr assigns)
                       (if (kvhx-has-delayed (svex-vars (cdar assigns)))
                           (cons (caar assigns) acc) acc))))
   (defun kvhx-now-vars (vars acc)
     (declare (xargs :mode :program))
     (if (atom vars) acc
       (kvhx-now-vars (cdr vars) (if (eql 0 (svar->delay (car vars))) (cons (car vars) acc) acc))))
   (defun kvhx-leaf (v)
     (declare (xargs :mode :program))
     (let ((n (svar->name v))) (if (consp n) (cdr (last n)) n)))
   (defun kvhx-clock-p (v)
     (declare (xargs :mode :program))
     (and (member-equal (svar->name v) '("core_clk_i" "app_clk_i")) t))
   (defun kvhx-reset-net-p (v)
     (declare (xargs :mode :program))
     (and (stringp (kvhx-leaf v))
          (not (equal (svar->name v) "reset_n_i"))
          (search "reset_n" (kvhx-leaf v))
          t))
   (defun kvhx-all-clock (vs)
     (declare (xargs :mode :program))
     (if (atom vs) t (and (kvhx-clock-p (car vs)) (kvhx-all-clock (cdr vs)))))
   (defun kvhx-filter-reset-nets (vs)
     (declare (xargs :mode :program))
     (if (atom vs) nil
       (if (kvhx-reset-net-p (car vs))
           (cons (car vs) (kvhx-filter-reset-nets (cdr vs)))
         (kvhx-filter-reset-nets (cdr vs)))))
   ; q0: registers that read only a clock directly; q1: the others;
   ; rn: the reset nets the others read directly; now: everything read directly
   (defun kvhx-classify (regs assigns q0 q1 rn now)
     (declare (xargs :mode :program))
     (if (atom regs) (mv (reverse q0) (reverse q1) (mergesort rn) (mergesort now))
       (let ((n (mergesort (kvhx-now-vars (svex-vars (svex-lookup (car regs) assigns)) nil))))
         (if (kvhx-all-clock n)
             (kvhx-classify (cdr regs) assigns (cons (car regs) q0) q1 rn (append n now))
           (kvhx-classify (cdr regs) assigns q0 (cons (car regs) q1)
                          (append (kvhx-filter-reset-nets n) rn) (append n now))))))
   ; registers in the combinational fan-in of a list of nets
   (mutual-recursion
    (defun kvhx-fanin (net seen regs assigns regfal clk)
      (declare (xargs :mode :program))
      (cond ((zp clk) (mv seen regs))
            ((hons-get net seen) (mv seen regs))
            (t (let ((seen (hons-acons net t seen)))
                 (cond ((hons-get net regfal) (mv seen (cons net regs)))
                       ((not (svex-lookup net assigns)) (mv seen regs))
                       (t (kvhx-fanin-list (svex-vars (svex-lookup net assigns))
                                           seen regs assigns regfal (1- clk))))))))
    (defun kvhx-fanin-list (nets seen regs assigns regfal clk)
      (declare (xargs :mode :program))
      (if (or (zp clk) (atom nets)) (mv seen regs)
        (mv-let (seen regs) (kvhx-fanin (car nets) seen regs assigns regfal (1- clk))
          (kvhx-fanin-list (cdr nets) seen regs assigns regfal (1- clk))))))
   (defun kvhx-width (net delays)
     (declare (xargs :mode :program))
     (let ((e (svex-lookup (change-svar net :delay 1) delays)))
       (if (and e (svex-case e :call) (eq (svex-call->fn e) 'zerox)
                (svex-case (car (svex-call->args e)) :quote)
                (natp (svex-quote->val (car (svex-call->args e)))))
           (svex-quote->val (car (svex-call->args e)))
         (er hard? 'kvhx-width "no width for ~x0" net))))
   (defun kvhx-widths (nets delays)
     (declare (xargs :mode :program))
     (if (atom nets) nil
       (cons (cons (car nets) (kvhx-width (car nets) delays))
             (kvhx-widths (cdr nets) delays))))
   (defun kvhx-delay1 (nets)
     (declare (xargs :mode :program))
     (if (atom nets) nil
       (cons (change-svar (car nets) :delay 1) (kvhx-delay1 (cdr nets)))))
   (defun kvhx-keep (vars fal acc)
     (declare (xargs :mode :program))
     (if (atom vars) (reverse acc)
       (kvhx-keep (cdr vars) fal (if (hons-get (car vars) fal) (cons (car vars) acc) acc))))
   (defun kvhx-drop (vars fal acc)
     (declare (xargs :mode :program))
     (if (atom vars) (reverse acc)
       (kvhx-drop (cdr vars) fal (if (hons-get (car vars) fal) acc (cons (car vars) acc)))))
   (defun kvhx-tests (vars acc)
     (declare (xargs :mode :program))
     (if (atom vars) (reverse acc)
       (kvhx-tests (cdr vars) (if (svar-override-p (car vars) :test) (cons (car vars) acc) acc))))
   (defun kvhx-find (leaf part nets)
     (declare (xargs :mode :program))
     (if (atom nets) (er hard? 'kvhx-find "no signal ~x0 under ~x1" leaf part)
       (if (and (equal (kvhx-leaf (car nets)) leaf)
                (consp (svar->name (car nets)))
                (member-equal part (list-fix (svar->name (car nets)))))
           (car nets)
         (kvhx-find leaf part (cdr nets)))))))

(make-event
 (b* ((x (svtv-spec->fsm (join-reset-spec)))
      ((fsm x))
      (flatnorm (svtv-data-obj->flatnorm (join-reset-run-data)))
      (assigns (make-fast-alist (flatnorm-res->assigns flatnorm)))
      (delays (make-fast-alist (flatnorm-res->delays flatnorm)))
      (statekeys (svex-alist-keys x.nextstate))
      (statefal (make-fast-alist (pairlis$ statekeys nil)))
      (regs (kvhx-registers assigns nil))
      (regfal (make-fast-alist (pairlis$ regs nil)))
      ((mv q0 q1 rn now) (kvhx-classify regs assigns nil nil nil nil))
      ((mv ?seen gr) (kvhx-fanin-list rn nil nil assigns regfal 100000000))
      (gr (reverse gr))
      (others (kvhx-drop (svex-alist-keys x.values) regfal nil))
      (kept (remove-duplicates-equal
             (append (kvhx-delay1 q1) (kvhx-keep (kvhx-delay1 now) statefal nil))))
      (allvars (mergesort (append (svex-alist-vars x.nextstate) (svex-alist-vars x.values))))
      (nonstate (kvhx-drop allvars statefal nil))
      (tests (kvhx-tests allvars nil))
      (loop3 (list (kvhx-find "reset_layer" "u_kv_cache" q1)
                   (kvhx-find "h" "u_value_prefix" q1)
                   (kvhx-find "l" "u_value_prefix" q1))))
   `(progn
      (defconst *kvh-regs* ',regs)
      (defconst *kvh-q0* ',q0)
      (defconst *kvh-q0d* ',(kvhx-delay1 q0))
      (defconst *kvh-q1* ',q1)
      (defconst *kvh-others* ',others)
      (defconst *kvh-kept* ',kept)
      (defconst *kvh-nonstate* ',nonstate)
      (defconst *kvh-tests* ',tests)
      (defconst *kvh-rnw* ',(kvhx-widths rn delays))
      (defconst *kvh-grw* ',(kvhx-widths gr delays))
      (defconst *kvh-loop3w* ',(kvhx-widths loop3 delays)))))

(defmacro kvh-const (name val)
  `(progn (defun ,name () (declare (xargs :guard t)) ,val)
          (in-theory (disable ,name (:executable-counterpart ,name)
                              (:type-prescription ,name)))))

; ALL THE REGISTERS: the signals whose assignment reads a stored value.
(kvh-const kvh-regs *kvh-regs*)
; the registers that read nothing but a clock directly
(kvh-const kvh-q0 *kvh-q0*)
; the other registers: they read a reset
(kvh-const kvh-q1 *kvh-q1*)
; the signals that are not registers
(kvh-const kvh-others *kvh-others*)
; the stored variables kept between the two phases of a cycle
(kvh-const kvh-kept *kvh-kept*)
; every variable of the machine that is not a stored variable
(kvh-const kvh-nonstate *kvh-nonstate*)
; THE SEVEN DERIVED RESET NETS, with their widths
(kvh-const kvh-rnw *kvh-rnw*)
; THE REGISTERS THOSE NETS ARE COMPUTED FROM, with their widths
(kvh-const kvh-grw *kvh-grw*)
; both
(kvh-const kvh-rgw (append *kvh-rnw* *kvh-grw*))
; THE THREE LOOP VARIABLES whose values CLEAR depends on, with their widths
(kvh-const kvh-loop3w *kvh-loop3w*)
; the clocks and the root reset, with their widths
(kvh-const kvh-clkw '(("core_clk_i" . 1) ("app_clk_i" . 1)))
(kvh-const kvh-clkrstw '(("core_clk_i" . 1) ("app_clk_i" . 1) ("reset_n_i" . 1)))
; every override test of the machine left unset
(kvh-const kvh-test-x (pairlis$ *kvh-tests* (repeat (len *kvh-tests*) (4vec-x))))
; the signals whose clock-low values the cases compare or assume
(kvh-const kvh-qkeys (append *kvh-q1* (strip-cars *kvh-rnw*)))
(defmacro kvh-qvals () '(svex-alist-extract (kvh-qkeys) (fsm->values (kvh-p))))
; the stored copies of the clock-only registers
(kvh-const kvh-q0d *kvh-q0d*)

(defthm kvh-set-sizes
  (and (equal (len (kvh-statekeys)) 2601)
       (equal (len (kvh-vals)) 4515)
       (equal (len (kvh-regs)) 1339)
       (equal (len (kvh-q0)) 396)
       (equal (len (kvh-q1)) 943)
       (equal (len (kvh-rnw)) 7)
       (equal (len (kvh-grw)) 6)
       (equal (len (kvh-loop3w)) 3)
       (equal (len (kvh-kept)) (len (remove-duplicates-equal (kvh-kept)))))
  :hints (("Goal" :in-theory '((:executable-counterpart kvh-p)
                               (:executable-counterpart fsm->nextstate$inline)
                               (:executable-counterpart fsm->values$inline)
                               (:executable-counterpart svex-alist-keys)
                               (:executable-counterpart len)
                               (:executable-counterpart equal)
                               (:executable-counterpart remove-duplicates-equal)
                               (:executable-counterpart kvh-regs)
                               (:executable-counterpart kvh-q0)
                               (:executable-counterpart kvh-q1)
                               (:executable-counterpart kvh-rnw)
                               (:executable-counterpart kvh-grw)
                               (:executable-counterpart kvh-loop3w)
                               (:executable-counterpart kvh-kept))))
  :rule-classes nil)

; ===========================================================================
; The phases, spelled out.
; ===========================================================================
(defthm kvh-phase-flags
  (and (not (svtv-cyclephase->inputs-free (kvh-c-hi)))
       (not (svtv-cyclephase->outputs-captured (kvh-c-hi)))
       (svtv-cyclephase->inputs-free (kvh-h-hi))
       (not (svtv-cyclephase->outputs-captured (kvh-h-hi)))
       (svtv-cyclephase->inputs-free (kvh-lo))
       (svtv-cyclephase->outputs-captured (kvh-lo)))
  :hints (("Goal" :in-theory (enable kvh-c-hi kvh-h-hi kvh-lo))))

(defthm kvh-phase-constants
  (and (equal (svtv-cyclephase->constants (kvh-c-hi))
              '(("core_clk_i" . 1) ("app_clk_i" . 1) ("reset_n_i" . 1) ("clear_i" . 0)))
       (equal (svtv-cyclephase->constants (kvh-h-hi))
              '(("core_clk_i" . 1) ("app_clk_i" . 1)))
       (equal (svtv-cyclephase->constants (kvh-lo))
              '(("core_clk_i" . 0) ("app_clk_i" . 0))))
  :hints (("Goal" :in-theory (enable kvh-c-hi kvh-h-hi kvh-lo))))

; ===========================================================================
; The stored values the cases fix.
; ===========================================================================
(make-event
 (b* ((rk (strip-cars (kvh-delay-nw (append '(("core_clk_i" . 1) ("app_clk_i" . 1) ("reset_n_i" . 1))
                                            *kvh-rnw*))))
      (uk (strip-cars (kvh-delay-nw (append '(("core_clk_i" . 1) ("app_clk_i" . 1))
                                            *kvh-loop3w*)))))
   `(progn (defconst *kvh-reset-stored-keys* ',rk)
           (defconst *kvh-run-stored-keys* ',uk))))

; a state in reset: the stored clock levels are low, and the stored root
; reset and the seven stored derived resets are asserted
(kvh-const kvh-reset-consts (pairlis$ *kvh-reset-stored-keys* '(0 0 0 0 0 0 0 0 0 0)))
; a running state: the stored clock levels are low and the three loop
; variables hold the values their loops leave
(kvh-const kvh-run-consts (pairlis$ *kvh-run-stored-keys* '(0 0 6 2 6)))

; the sets are lists of variables
(defthm kvh-sets-are-variable-lists
  (and (svarlist-p (kvh-regs))
       (svarlist-p (kvh-q0))
       (svarlist-p (kvh-q0d))
       (svarlist-p (kvh-q1))
       (svarlist-p (kvh-others))
       (svarlist-p (kvh-kept))
       (svarlist-p (kvh-nonstate))
       (svarlist-p (kvh-qkeys))
       (svarlist-p (strip-cars (kvh-rnw)))
       (svarlist-p (strip-cars (kvh-grw)))
       (svarlist-p (strip-cars (kvh-rgw)))
       (svarlist-p (strip-cars (kvh-loop3w)))
       (svarlist-p (strip-cars (kvh-clkw)))
       (svarlist-p (strip-cars (kvh-clkrstw)))
       (svex-env-p (kvh-test-x))
       (svex-env-p (kvh-reset-consts))
       (svex-env-p (kvh-run-consts)))
  :hints (("Goal" :in-theory '((:executable-counterpart kvh-regs)
                               (:executable-counterpart kvh-q0)
                               (:executable-counterpart kvh-q0d)
                               (:executable-counterpart kvh-q1)
                               (:executable-counterpart kvh-others)
                               (:executable-counterpart kvh-kept)
                               (:executable-counterpart kvh-nonstate)
                               (:executable-counterpart kvh-qkeys)
                               (:executable-counterpart kvh-rnw)
                               (:executable-counterpart kvh-grw)
                               (:executable-counterpart kvh-rgw)
                               (:executable-counterpart kvh-loop3w)
                               (:executable-counterpart kvh-clkw)
                               (:executable-counterpart kvh-clkrstw)
                               (:executable-counterpart kvh-test-x)
                               (:executable-counterpart kvh-reset-consts)
                               (:executable-counterpart kvh-run-consts)
                               (:executable-counterpart strip-cars)
                               (:executable-counterpart svarlist-p)
                               (:executable-counterpart svex-env-p)))))

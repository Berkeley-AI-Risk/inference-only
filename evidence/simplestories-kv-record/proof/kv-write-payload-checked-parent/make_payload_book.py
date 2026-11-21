#!/usr/bin/env python3
"""Write the ACL2 books of this directory.

    python3 -I make_payload_book.py [--check]

kv-write-payload-lemma.lisp   the payload registers added to the certified
                              step run, the payload invariant and the
                              symbolic step lemma
kv-write-payload-lift.lisp    that lemma lifted to every execution
kv-write-payload.lisp         the induction, the two theorems, the record
kv-write-payload-early-metadata.lisp   the regression check
The pieces are in dev/: proto_run.py (the run), gen_lemma.py (predicates and
lemma), gen_run.py (the concrete record), payload_lib.py (signal names).
--check writes nothing and exits 1 if a file on disk differs.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "dev"))
import hashlib  # noqa: E402
import re  # noqa: E402
import proto_run  # noqa: E402
import gen_lemma  # noqa: E402
import gen_run  # noqa: E402

OUTPUTS = {}

BANNER = """; %s
;
; Written by make_payload_book.py; do not edit.  Private.
"""

SETTINGS = """(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
; The library's generated lemmas about a run with several hundred named
; signals nest deeper than the rewriter's default limit of 1000.
(acl2::set-rewrite-stack-limit 20000)

; The SAT solver.  No answer of the solver is believed: with :lrat-check t
; the library reports "unsatisfiable" only after ACL2 has run its verified
; checker (projects/sat/lrat) on the proof the solver wrote, against the
; formula ACL2 itself wrote; "satisfiable" only after ACL2 has evaluated the
; formula under the assignment.  The command is CaDiCaL behind a short
; script, run from this directory.  (The imported book attaches kissat with
; its answers trusted; this replaces that for every proof made here.)
(defun pay-satlink-config ()
  (declare (xargs :guard t))
  (satlink::make-config :cmdline "sh sat/cadical-lrat.sh" :verbose nil
                        :mintime 0 :remove-temps t :lrat-check t))
(defthm kv-write-payload-sat-proofs-are-checked
  (equal (satlink::config->lrat-check (pay-satlink-config)) t)
  :rule-classes nil)
(defattach fgl::fgl-satlink-config pay-satlink-config)
(value-triple (acl2::tshell-ensure))
"""


def lemma_book():
    text = gen_lemma.lemma()
    cut = text.index("(def-svtv-generalized-thm")
    defs, thm = text[:cut], text[cut:].rstrip("\n")
    return (BANNER % "The write path's payload: the step lemma, for one symbolic cycle and lifted to every execution."
            + """;
; Imports the certified joined K/V book: its design constant *sv-design* (the
; pinned RTL as translated by the corrected translator), its state machine
; (probe-fsm), its invariant and its environment.  Adds
;   payload-step-run    the certified step run with the payload registers
;                       named as well: the controller's pair store, its read
;                       registers and its write offer; the payload and
;                       descriptor of every request-FIFO entry; the app
;                       side's slots and its endpoint offer
;   pay-inv-p           the payload invariant
;   pay-step-svtv-thm   for one symbolic cycle: from the joined invariant, the
;                       payload invariant and the environment to the payload
;                       invariant in the next cycle and the facts listed
;                       below (kv-write-payload-lift.lisp lifts it to every
;                       cycle of every execution)
(in-package "SV")
(include-book "../kv-joined-book-checked-sat/kv-joined")

""" + SETTINGS + gen_lemma.predicates() + """
; ===========================================================================
; The step run.  The certified book's join-step-run, stage for stage and
; name for name, with the payload registers added to the overrides of stage
; `curr` and to the outputs of stage `next`, and with the signals of the
; controller's typed write port, the boundary's endpoint and the staging
; port read in stage `curr`.
; ===========================================================================
""" + proto_run.step_run_text() + """
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export payload-step-run-data)
  (make-event '(def-svtv-refinement payload-step-run payload-step-run-data
                 :svtv-spec payload-step-spec :inclusive-overridekeys t
                 :fsm probe-fsm)))
(value-triple (acl2::cw "~%PAY-REFINEMENT done~%"))

; The run fixes what the certified step run fixes: the lock input is 1 in
; the cycle and reset_n_i is 1 in the next.
(defthm kv-write-payload-run-constraints
  (equal (payload-step-run-fsm-constraints) (join-step-run-fsm-constraints))
  :rule-classes nil)

; ===========================================================================
; What the step lemma concludes, one predicate per conjunct.
; ===========================================================================
""" + defs + """
; ===========================================================================
; The step lemma for one symbolic cycle.  Each predicate above hands its
; body to the SAT solver on its own, under the antecedent.
; ===========================================================================
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '""" + thm.replace("\n", "\n    ") + """)
  (value-triple (acl2::cw "~%PAY-STEP-SVTV proved~%")))
""")


def lift_book():
    sh = gen_lemma.lemma_shape()
    allvars = sorted(set(sh["outs"]) | set(gen_lemma.VAR.findall(sh["concl_call"])))
    return (BANNER % "The write path's payload: the step lemma lifted to every cycle of every execution."
            + """;
; A book of its own, so that the symbolic lemma (kv-write-payload-lemma,
; about an hour and a half) is not proved again when only this changes.
; Exports
;   pay-step-fsm-thm    in any execution of (probe-fsm), a cycle that starts
;                       in the joined invariant and the payload invariant,
;                       under the environment, ends in the payload invariant,
;                       and on that cycle the lemma's facts hold
(in-package "SV")
(include-book "kv-write-payload-lemma")
(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
(acl2::set-rewrite-stack-limit 20000)

; The lemma's whole conclusion as one predicate.  The library's lift works
; through the conclusion's conjuncts one at a time, each at a cost that grows
; with the number of named signals; with the lemma's eighty conjuncts left
; apart it would take about a day, and with one it takes under an hour.
(define pay-step-all (%(allvars)s)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and %(ints)s
       %(concl)s))
(in-theory (disable pay-step-all))

; The lemma again, with that conclusion.  It is the lemma itself: the proof
; only opens the definition above.
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '(def-svtv-generalized-thm pay-step-svtv-thm-folded
      :svtv payload-step-run
      :svtv-spec payload-step-spec
      :input-vars :all
      :output-vars (%(outs)s)
      :unsigned-byte-hyps t
      :no-integerp t
      :override-vars (%(overrides)s)
      :spec-override-vars ()
      :hyp %(hyp)s
      :concl (pay-step-all %(allvars)s)
      :no-lemmas t
      :hints (("Goal" :use ((:instance pay-step-svtv-thm))
               :in-theory '(pay-step-all)))))
  (value-triple (acl2::cw "~%%PAY-STEP-FOLDED proved~%%")))

; The same about any cycle of any execution of (probe-fsm).
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event '(def-svtv-to-fsm-thm pay-step-fsm-thm
                 :svtv-spec-thmname pay-step-svtv-thm-folded
                 :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%%PAY-STEP-FSM proved~%%")))
""" % dict(allvars=" ".join(allvars), ints="\n       ".join(sh["int_calls"]), concl=sh["concl_call"],
           outs=" ".join(sh["outs"]), overrides=" ".join(sh["overrides"]),
           hyp=sh["hyp"].replace("\n", "\n      ")))


JOINED = os.path.normpath(os.path.join(HERE, "..", "kv-joined-book-checked-sat"))
KV_FILE = ("fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/"
           "board1_context2048_atomic_kv_typed_clear_consistent.sv")
LIBRARY_BOOKS = [
    "centaur/sv/svtv/svtv-to-fsm-defs", "centaur/fgl/top",
    "centaur/sv/svtv/svtv-stobj-defsvtv", "centaur/vl/loader/top",
    "centaur/sv/vl/top", "oslib/ls", "centaur/sv/svtv/svtv-stobj-debug",
    "centaur/misc/memory-mgmt",
]


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def mutant_files():
    """(path relative to this directory, sha256) of the RTL the regression
    book reads: the joined book's pinned files, with the controller taken
    from rtl-early-metadata/."""
    pinned = {}
    for line in open(os.path.join(JOINED, "SOURCES.sha256")):
        h, path = line.split()
        pinned[path] = h
    files = [l.strip() for l in open(os.path.join(JOINED, "rtl", "FILES.txt")) if l.strip()]
    out = []
    for f in files:
        if f == KV_FILE:
            mine = "rtl-early-metadata/" + f
            out.append((mine, sha256(os.path.join(HERE, mine))))
        else:
            out.append(("../kv-joined-book-checked-sat/rtl/" + f, pinned["rtl/" + f]))
    assert any(p.startswith("rtl-early-metadata/") for p, _ in out)
    return out


def design_forms(files):
    names = "\n".join('    "%s"' % p for p, _ in files)
    pins = "\n".join('    ("%s"\n     . "%s")' % (p, h) for p, h in files)
    return """; ---------------------------------------------------------------------------
; The RTL: the joined book's pinned files, with the K/V controller taken from
; rtl-early-metadata/ (early-metadata.patch: one line).
; ---------------------------------------------------------------------------
(defconst *kvj-rtl-files*
  '(
%s
    ))

(defconst *kvj-rtl-sha256-pinned*
  '(
%s
    ))

; The Verilog loader reads the files; the SHA-256 of each is computed from
; the very text the loader read.
(encapsulate nil
  (local
   (defconsts (*vl-design* *kvj-digests* state)
     (b* (((mv (vl::vl-loadresult loadres) state)
           (vl::vl-load (vl::make-vl-loadconfig :start-files *kvj-rtl-files*))))
       (mv loadres.design
           (kvj-read-and-pinned *kvj-rtl-files* loadres.filemap)
           state))))
  (local
   (defconsts (*kvj-sv-design* *vl-good* *vl-bad*)
     (b* (((mv errmsg svex good bad)
           (vl::vl-design->sv-design "board1_context2048_shared_token_probe"
                                     *vl-design* (vl::make-vl-simpconfig))))
       (and errmsg (raise "~@0~%%" errmsg))
       (mv svex good bad))))
  (make-event `(defconst *kvj-rtl-sha256-as-read* ',*kvj-digests*))
  (make-event `(defconst *sv-design* ',*kvj-sv-design*)))

(defthm kv-write-payload-early-metadata-rtl-is-the-pinned-rtl
  (equal *kvj-rtl-sha256-as-read* *kvj-rtl-sha256-pinned*)
  :rule-classes nil)

(defconsts (*kvj-translator-sha256-when-translating* state)
  (mv (kvj-translator-sha256 state) state))

(defthm kv-write-payload-early-metadata-rtl-was-translated-by-the-corrected-translator
  (equal *kvj-translator-sha256-when-translating* *kvj-translator-sha256-pinned*)
  :rule-classes nil)
""" % (names, pins)


RUN_HELPERS = """
(defun pay-strip-cycles (l)
  (declare (xargs :mode :program))
  (if (atom l) nil (cons (cdr (car l)) (pay-strip-cycles (cdr l)))))
(defun pay-cycles (l)
  (declare (xargs :mode :program))
  (if (atom l) nil (cons (car (car l)) (pay-cycles (cdr l)))))
"""


def early_metadata_book():
    text = gen_lemma.lemma()
    cut = text.index("(def-svtv-generalized-thm")
    defs, thm = text[:cut], text[cut:].rstrip("\n")
    exp = gen_run.expected()
    return (BANNER % "Regression check: with the metadata word written one word early, the payload property fails."
            + """;
; The RTL here is the joined book's pinned RTL with one line of the K/V
; controller changed (early-metadata.patch): after a write completes the
; controller goes to its metadata state when the word just completed is 6,
; not 7.  Word 7 of a row then carries the row's metadata and word 8, the
; metadata address, carries whatever the store holds past the staged slots.
; This is also what the released translator made of the unchanged RTL, by
; reading the word counter after its update.  The joined control invariant
; does not see it.  Two things are certified here.
;   1. The scripted run of kv-write-payload.lisp, on this RTL, completes and
;      reports the record complete, and its writes are not the record: the
;      eighth write of each row carries the metadata word.
;   2. The proof of the payload step lemma, the one that succeeds for the
;      pinned RTL, fails.
; If the patch were not applied this book would not certify.
(in-package "SV")
""" + "".join('(include-book "%s" :dir :system)\n' % b for b in LIBRARY_BOOKS)
            + """(include-book "std/testing/must-fail" :dir :system)
(include-book "../kv-joined-book-checked-sat/kv-joined-statements")
(include-book "../kv-joined-book-checked-sat/kv-joined-pins")

""" + SETTINGS + "\n" + design_forms(mutant_files()) + gen_lemma.predicates() + "\n"
            + proto_run.step_run_text() + """
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (def-svtv-data-export payload-step-run-data)
  (make-event '(def-svtv-refinement payload-step-run payload-step-run-data
                 :svtv-spec payload-step-spec :inclusive-overridekeys t
                 :fsm probe-fsm :define-fsm t)))
(value-triple (acl2::cw "~%PAY-REFINEMENT done~%"))

; ---------------------------------------------------------------------------
; 1. The scripted run.
; ---------------------------------------------------------------------------
""" + gen_run.run_text().replace('(in-package "SV")\n', "") + RUN_HELPERS + """
(defconsts *pay-run* (pay-run-loop 0 4000 (pay-zero-state *pay-state-ids*) nil nil))

; the record the script stages, as kv-write-payload.lisp states it
(defconst *pay-expected*
  """ + gen_run.expected_text() + """)

; how the run ended, the writes the endpoint accepted (address and data, in
; order), and the controller's reported-complete and fault registers then
(defconst *pay-run-outcome* (first *pay-run*))
(defconst *pay-run-writes* (pay-strip-cycles (third *pay-run*)))
(defconst *pay-run-reported-complete* (pay-get 'k-pending-persisted-q (fifth *pay-run*)))
(defconst *pay-run-fault* (pay-get 'k-fault-q (fifth *pay-run*)))

; The run ends with the record reported complete and no fault ...
(defthm kv-write-payload-early-metadata-run-completes
  (and (equal *pay-run-outcome* :complete)
       (equal *pay-run-reported-complete* 1)
       (equal *pay-run-fault* 0)
       (equal (len *pay-run-writes*) 18))
  :rule-classes nil)

; ... but what the endpoint accepted is not the record.  In each row the
; eighth write goes to word 7's address with the row's metadata word as its
; data, and the ninth goes to the metadata address with zero.
(defthm kv-write-payload-early-metadata-run-is-not-the-record
  (let ((writes *pay-run-writes*))
    (and (not (equal writes *pay-expected*))
         ; the first seven writes of the K row are as staged
         (equal (take 7 writes) (take 7 *pay-expected*))
         ; the eighth: word 7's address, the K metadata word
         (equal (nth 7 writes) (list %(a7)d #x%(km)x))
         ; the ninth: the metadata address, not the metadata
         (equal (nth 8 writes) (list %(a8)d 0))
         ; and the same in the V row
         (equal (nth 16 writes) (list %(v7)d #x%(vm)x))
         (equal (nth 17 writes) (list %(v8)d 0))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; 2. The step lemma is not provable.  The predicates and the statement below
;    are, character for character, those of kv-write-payload-lemma.lisp.
; ---------------------------------------------------------------------------
""" % dict(a7=exp[7][0], km=exp[8][1], a8=exp[8][0], v7=exp[16][0], vm=exp[17][1], v8=exp[17][0])
            + defs + """
(acl2::must-fail
 (encapsulate nil
   (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
   (make-event
    '""" + thm.replace("\n", "\n     ") + """))
 :with-output-off nil)
""")


def induction_text():
    """The induction over cycles: the same pattern as the certified book's."""
    concs = gen_lemma.conclusions(("2v", "inv", "typed", "endpoint", "facts"))
    names = [c[0] for c in concs]
    n_def = sum(1 for n in names if n.startswith("pay-next-definite-"))
    assert names[n_def] == "pay-next-inv" and n_def == len(names) - 20, (n_def, len(names))
    state_preds = " ".join(names[:n_def + 1])
    calls = ["(%s %s)" % (n, " ".join(f)) for n, _, _, f in concs]
    definite_calls = "\n               ".join(calls[:n_def])
    fact_calls = "\n               ".join(calls[n_def + 1:])
    return """
; ---------------------------------------------------------------------------
; Read the lifted lemma's signal bindings back from the world, so that the
; induction uses exactly the terms the lemma was proved for; the conjuncts
; below are those of pay-step-concl, the lemma's conclusion.  envs is any
; list of per-cycle input assignments, initst any initial state, and
; outs = (fsm-eval envs initst (probe-fsm)) the per-cycle signal values.
; ---------------------------------------------------------------------------
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (decl `(declare (xargs :verify-guards nil) (ignorable ,@formals)))
      (idecl `(declare (ignorable ,@vars))))
   `(progn
      ; the payload registers hold definite values, read at cycle base-cycle+1
      (defun pay-definite-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and %(definite_calls)s)))
      ; the payload invariant, read at cycle base-cycle+1
      (defun pay-inv-raw ,formals ,decl
        (let* ,bindings ,idecl
          %(inv_call)s))
      ; what the cycle base-cycle does: the conjuncts after those
      (defun pay-facts-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and %(fact_calls)s)))
      (in-theory (disable pay-definite-raw pay-inv-raw pay-facts-raw)))))

; The payload registers hold definite values at cycle k.
(define pay-definite-at (k envs outs) :verify-guards nil
  (pay-definite-raw k k envs outs))
; The payload invariant holds at cycle k (and the registers are definite).
(define pay-j-at (k envs outs) :verify-guards nil
  (and (pay-definite-raw k k envs outs)
       (pay-inv-raw k k envs outs)))
; The facts about cycle k.
(define pay-facts-at (k envs outs) :verify-guards nil
  (pay-facts-raw k (+ 1 k) envs outs))

; One cycle: from the joined invariant, the payload invariant and the
; environment at cycle k to the payload invariant at k+1 and the facts at k.
(defthm pay-step-glue
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at k envs (fsm-eval envs initst (probe-fsm))))
           (and (pay-j-at (+ 1 k) envs (fsm-eval envs initst (probe-fsm)))
                (pay-facts-at k envs (fsm-eval envs initst (probe-fsm)))))
  :hints (("Goal"
           :use ((:instance pay-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-write-payload-run-constraints))
           :in-theory (e/d (join-j-at join-env-at join-inv-raw join-resetalt-raw
                            join-env-raw joint-2valued-p
                            pay-j-at pay-facts-at pay-definite-raw pay-inv-raw
                            pay-facts-raw pay-step-all pay-step-concl
                            fgl::fgl-prove-fn %(state_preds)s)
                           (pay-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

; In the reset state the payload invariant asks nothing: the controller is
; idle and nothing is reported complete.
(defthm pay-inv-when-reset
  (implies (and (equal st 0) (equal per 0))
           (pay-inv-p %(inv_formals)s))
  :hints (("Goal" :in-theory (enable pay-inv-p))))

; After reset: three reset cycles leave the controller idle with nothing
; reported, so the payload invariant holds once the payload registers hold
; definite values.
(defthm pay-reset-glue
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm)))
                (pay-definite-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm))))
           (pay-j-at (+ 2 r) envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance join-reset-fsm-thm
                  (base-cycle r) (base-cycle+2 (+ 2 r))))
           :in-theory (e/d (join-reset-at join-reset-raw joint-reset-p
                            pay-j-at pay-definite-at pay-inv-raw
                            pay-next-inv fgl::fgl-prove-fn)
                           (join-reset-fsm-thm pay-inv-p unsigned-byte-p nth
                            nthcdr take len fsm-eval (probe-fsm) probe-fsm)))))

(defthm pay-inv-preserved
  (implies (and (natp j) (natp n) (<= j n)
                (join-j-at j envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at j envs (fsm-eval envs initst (probe-fsm)))
                (join-env-from j n envs (fsm-eval envs initst (probe-fsm))))
           (pay-j-at n envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :induct (join-env-from j n envs
                                  (fsm-eval envs initst (probe-fsm)))
           :in-theory (e/d (join-env-from)
                           (join-j-at join-env-at pay-j-at pay-facts-at
                            unsigned-byte-p nth nthcdr take len fsm-eval
                            (probe-fsm) probe-fsm)))))

; THE INVARIANT AT EVERY CYCLE.  In every execution of the probe's state
; machine, from any initial state: if cycles r, r+1 and r+2 are reset
; cycles, the payload registers hold definite values at r+2, and the
; environment behaves at every cycle from r+2 to n-1, then the payload
; invariant holds at cycle n.
(defthm pay-inv-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs))
             (pay-j-at n envs outs)))
  :hints (("Goal"
           :use ((:instance join-reset-glue)
                 (:instance pay-reset-glue)
                 (:instance pay-inv-preserved (j (+ 2 r))))
           :in-theory (disable join-reset-glue pay-reset-glue
                               pay-inv-preserved pay-step-glue join-step-glue
                               join-j-at join-reset-at pay-j-at
                               pay-definite-at join-env-from fsm-eval
                               (probe-fsm) probe-fsm))))

; ===========================================================================
; THE THEOREM, with the joined book's hypotheses.
;
; Take any execution of the probe module's state machine, from any initial
; state.  Suppose reset_n_i is low in cycles r, r+1 and r+2 (kv-reset-held-at,
; from the joined book), the payload registers hold definite values in cycle
; r+2, and the environment behaves in every cycle from r+2 up to but not
; including n (kv-environment-ok-from, from the joined book).  Then in
; cycle n:
;   - the payload registers hold definite values and the payload invariant
;     holds;
;   - and if the environment behaves in cycle n as well, every fact of the
;     step lemma holds of cycle n: a write accepted at the controller's typed
;     port or at the boundary's endpoint is the staged word at its address,
;     the store changes only by an accepted staging beat, progress counts the
;     endpoint's acceptances, and so on (the predicates pay-fact-... of the
;     lemma book).
; CLEAR is unconstrained throughout.
; ===========================================================================
(define kv-payload-storage-definite-at (k envs outs) :verify-guards nil
  (pay-definite-at k envs outs))
(define kv-payload-invariant-at (n envs outs) :verify-guards nil
  (pay-j-at n envs outs))
(define kv-write-payload-facts-at (n envs outs) :verify-guards nil
  (pay-facts-at n envs outs))

(defthm kv-write-payload-guarantee
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) n envs outs))
             (and (kv-payload-invariant-at n envs outs)
                  (implies (kv-environment-ok-at n envs outs)
                           (kv-write-payload-facts-at n envs outs)))))
  :hints (("Goal"
           :use ((:instance pay-inv-from-reset)
                 (:instance join-inv-from-reset)
                 (:instance kvj-reset-connects
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance kvj-environment-connects
                  (k n) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance pay-step-glue (k n)))
           :in-theory (e/d (kv-payload-storage-definite-at
                            kv-payload-invariant-at kv-write-payload-facts-at)
                           (pay-inv-from-reset join-inv-from-reset pay-step-glue
                            join-step-glue pay-inv-preserved join-inv-preserved
                            pay-reset-glue join-reset-glue kvj-reset-connects
                            kvj-environment-from-connects
                            kvj-environment-connects join-j-at join-reset-at
                            join-env-from join-env-at pay-j-at pay-facts-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
"""  % dict(ndef=n_def, nstate=n_def + 1, state_preds=state_preds,
            definite_calls=definite_calls, inv_call=calls[n_def], fact_calls=fact_calls,
            inv_formals=" ".join(gen_lemma.INV_FORMALS))


def row_section():
    """The list-level argument (dev/row_section.lsp).  It is kept as text; it
    names signals of the step lemma, so check that they are still there."""
    text = open(os.path.join(HERE, "dev", "row_section.lsp")).read()
    ints = "(ints '(%s))" % "\n              ".join(gen_lemma.lemma_shape()["int_calls"])
    old = "      (imp (third body))\n      (ints (butlast (cdr (third imp)) 1))"
    assert text.count(old) == 1
    text = text.replace(old, "      " + ints)
    old = "pay-ints-raw fgl::fgl-prove-fn"
    assert text.count(old) == 1
    text = text.replace(old, "pay-ints-raw pay-step-all fgl::fgl-prove-fn")
    lemma = gen_lemma.lemma()
    for v in set(re.findall(r"\(pay\$((?:r|n|o|h|i)-[a-z0-9-]+) ", text)):
        assert re.search(r"(?<![a-z0-9-])%s(?![a-z0-9-])" % re.escape(v), lemma), v
    return text


def theorem_book():
    exp = gen_run.expected()
    return (BANNER % "The write path's payload: the invariant and the per-cycle facts in every execution, and a completed record."
            + """;
; Exports
;   kv-write-payload-guarantee     the invariant and the per-cycle facts in
;                                  every execution
;   kv-write-payload-row           the writes of a finished row are its nine
;                                  words, in order
;   kv-write-payload-run-...       a scripted run that stages one record and
;                                  writes it, with stalls
(in-package "SV")
(include-book "kv-write-payload-lift")
(acl2::set-slow-alist-action nil)
(value-triple (acl2::tshell-ensure))
""" + induction_text() + "\n" + row_section() + """
; ===========================================================================
; A COMPLETED RECORD.  One cycle after another of payload-step-run, from the
; state the reset leaves (every register 0), reset_n_i low for three cycles.
; A script plays the client and the endpoint; each cycle's registers are the
; previous cycle's next-state values.  The app side's verdict on a request's
; descriptor is not scripted: the RTL computes it.  The expected writes were
; computed outside ACL2 from the staged values and the address formula
; (dev/gen_run.py).
; ===========================================================================
""" + gen_run.run_text().replace('(in-package "SV")\n', "") + RUN_HELPERS + """
(defconsts *pay-run* (pay-run-loop 0 4000 (pay-zero-state *pay-state-ids*) nil nil))

; The record the script stages: eighteen (address data), the K row then the
; V row, eight words of sixteen coordinates and the metadata word each.
(defconst *pay-expected*
  """ + gen_run.expected_text() + """)

(defconst *pay-run-outcome* (first *pay-run*))
(defconst *pay-run-cycles* (second *pay-run*))
(defconst *pay-run-writes* (pay-strip-cycles (third *pay-run*)))
(defconst *pay-run-write-cycles* (pay-cycles (third *pay-run*)))
(defconst *pay-run-typed-writes* (pay-strip-cycles (fourth *pay-run*)))
(defconst *pay-run-reported-complete* (pay-get 'k-pending-persisted-q (fifth *pay-run*)))
(defconst *pay-run-fault* (pay-get 'k-fault-q (fifth *pay-run*)))

; The run ends with the record reported complete and no fault.
(defthm kv-write-payload-run-completes
  (and (equal *pay-run-outcome* :complete)
       (equal *pay-run-reported-complete* 1)
       (equal *pay-run-fault* 0))
  :rule-classes nil)

; The writes the endpoint accepted are the record, in order, and so are the
; writes the controller's typed port issued.
(defthm kv-write-payload-run-is-the-record
  (and (equal *pay-run-writes* *pay-expected*)
       (equal *pay-run-typed-writes* *pay-expected*))
  :rule-classes nil)

; The endpoint was not ready on one cycle in seven, so the writes were not
; evenly spaced: the cycles on which it accepted them.
(defthm kv-write-payload-run-was-stalled
  (and (equal (len *pay-run-write-cycles*) 18)
       (not (equal (- (nth 1 *pay-run-write-cycles*) (nth 0 *pay-run-write-cycles*))
                   (- (nth 8 *pay-run-write-cycles*) (nth 7 *pay-run-write-cycles*)))))
  :rule-classes nil)
""")


def main():
    OUTPUTS["kv-write-payload-lemma.lisp"] = lemma_book()
    OUTPUTS["kv-write-payload-lift.lisp"] = lift_book()
    OUTPUTS["kv-write-payload-early-metadata.lisp"] = early_metadata_book()
    OUTPUTS["kv-write-payload.lisp"] = theorem_book()
    check = "--check" in sys.argv
    bad = 0
    for name, text in sorted(OUTPUTS.items()):
        path = os.path.join(HERE, name)
        old = open(path).read() if os.path.isfile(path) else None
        if check:
            if old != text:
                print("differs: " + name)
                bad += 1
        elif old != text:
            open(path, "w").write(text)
            print("wrote " + name)
    if check:
        print("checked %d files: %s" % (len(OUTPUTS), "all as generated" if not bad else "%d differ" % bad))
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

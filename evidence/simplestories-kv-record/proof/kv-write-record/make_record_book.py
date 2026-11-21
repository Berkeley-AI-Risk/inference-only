#!/usr/bin/env python3
"""Write the ACL2 books of this directory.

    python3 -I make_record_book.py [--check]

kv-write-record-step.lisp   two more facts about one symbolic cycle of the
                            payload book's step run
kv-write-record-lift.lisp   those facts lifted to every execution
kv-write-record.lisp        the record invariant, the record theorem and its
                            companions, the stalled completion
kv-write-record-mismatched-rows.lisp
                            the negative control: a controller that pairs a
                            K row with the V row of the next position
The pieces are in dev/: record_step.py (the new facts and their lemma),
record_main.py (the argument), record_run.py (the scripted run).  They use
the generator pieces of ../kv-write-payload-checked-parent/dev for the text
that has to be, character for character, the certified book's (the step
run, its hypothesis, the names of its signals).
--check writes nothing and exits 1 if a file on disk differs.
"""
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "dev"))
import record_step as R  # noqa: E402
import record_main  # noqa: E402
import record_run  # noqa: E402
import proto_run  # noqa: E402
import gen_lemma  # noqa: E402
import gen_run  # noqa: E402

sys.path.insert(0, R.PAYLOAD)
import make_payload_book as payload  # noqa: E402

PARENT = os.path.normpath(os.path.join(HERE, "..", "kv-joined-book-checked-sat"))
KV_FILE = payload.KV_FILE
OUTPUTS = {}

BANNER = """; %s
;
; Written by make_record_book.py; do not edit.  Private.
"""

SETTINGS = """(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))
(acl2::set-slow-alist-action nil)
; The library's generated lemmas about a run with several hundred named
; signals nest deeper than the rewriter's default limit of 1000.
(acl2::set-rewrite-stack-limit 20000)

; The SAT solver, as in the payload book.  No answer of the solver is
; believed: with :lrat-check t the library reports "unsatisfiable" only
; after ACL2 has run its verified checker (projects/sat/lrat) on the proof
; the solver wrote, against the formula ACL2 itself wrote; "satisfiable"
; only after ACL2 has evaluated the formula under the assignment.
(defun rec-satlink-config ()
  (declare (xargs :guard t))
  (satlink::make-config :cmdline "sh sat/cadical-lrat.sh" :verbose nil
                        :mintime 0 :remove-temps t :lrat-check t))
(defthm kv-write-record-sat-proofs-are-checked
  (equal (satlink::config->lrat-check (rec-satlink-config)) t)
  :rule-classes nil)
(defattach fgl::fgl-satlink-config rec-satlink-config)
(value-triple (acl2::tshell-ensure))
"""


def step_book():
    return (BANNER % "The K/V write record: two more facts about one cycle."
            + """;
; This book imports the certified write-payload book on the SAT-checked
; parent (../kv-write-payload-checked-parent) and proves two more facts of
; the same symbolic cycle, payload-step-run, from the same hypotheses: the
; joined control invariant, the payload invariant and the environment in
; one cycle.  The payload book's facts are about one row.  These two say how
; the controller moves through a whole record:
;   rec-fact-entry   a write state that is not interrupted, other than the
;                    record's start, is entered only from such a state, in a
;                    cycle without CLEAR, on the same row or by the one step
;                    from the K row's word 8 to the V row's word 0, which
;                    leaves the record's layer, position and exponents alone
;   rec-fact-start   the record's start is entered only from staging, by the
;                    acceptance of the beat for coordinate 127
;   rec-step-svtv-thm  both, of one symbolic cycle (kv-write-record-lift.lisp
;                    lifts it to every cycle of every execution)
; The RTL, the translation, the step run and its named signals are the
; imported book's; nothing is read from disk here.
(in-package "SV")
(include-book "../kv-write-payload-checked-parent/kv-write-payload")

""" + SETTINGS + "\n" + R.predicates() + """
; ===========================================================================
; The step lemma for one symbolic cycle.  Each predicate above hands its
; body to the SAT solver on its own, under the antecedent.  The integer
; predicates pay-int-... are the payload book's.
; ===========================================================================
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '""" + R.theorem().rstrip("\n").replace("\n", "\n   ") + """)
  (value-triple (acl2::cw "~%REC-STEP-LEMMA proved~%")))
""")


def lift_book():
    define, thm = R.folded()
    return (BANNER % "The K/V write record: the two new facts in every cycle of every execution."
            + """;
; kv-write-record-step.lisp proves the two facts of one symbolic cycle of
; the step run.  This book carries them to any cycle of any execution of
; (probe-fsm), the state machine of the probe module as translated from the
; pinned RTL:
;   rec-step-fsm-thm   for any envs and initst, with
;                      outs = (fsm-eval envs initst (probe-fsm)): if the
;                      signals of cycle k satisfy the step lemma's
;                      hypotheses, they and those of cycle k+1 satisfy its
;                      conclusion
; The conclusion is first folded into one predicate, as in the payload
; book: the library's lift costs one case per named signal for each conjunct
; of the conclusion.
(in-package "SV")
(include-book "kv-write-record-step")
(acl2::set-slow-alist-action nil)
(acl2::set-rewrite-stack-limit 20000)

; The whole conclusion of rec-step-svtv-thm, as one predicate.
""" + define + """
; The lemma again, with that conclusion.  It is the lemma itself: the proof
; only opens the definition above.
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (make-event
   '""" + thm + """)
  (value-triple (acl2::cw "~%REC-STEP-FOLDED proved~%")))

; The same about any cycle of any execution of (probe-fsm).
(encapsulate nil
  (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
  (local (include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system))
  (make-event '(def-svtv-to-fsm-thm rec-step-fsm-thm
                 :svtv-spec-thmname rec-step-svtv-thm-folded
                 :eliminate-override-vars :all))
  (value-triple (acl2::cw "~%REC-STEP-FSM proved~%")))
""")


def expected_shifted(by):
    exp = gen_run.expected()
    return "'(" + "\n    ".join("(%d #x%x)" % (a + by, d) for a, d in exp[9:]) + ")"


def record_defs():
    """rec-word and rec-words, as the main book defines them."""
    t = record_main.text()
    i = t.index("(define rec-word (")
    j = t.index("; The same of the record as the controller holds it in cycle k.")
    return t[i:j]


def theorem_book():
    return (BANNER % "The K/V write record: the theorem."
            + """;
; THE CLAIM.  Take any execution of the probe module's state machine
; satisfying the reset, storage and environment hypotheses of the payload
; book.  When the controller's pending_persisted_q rises, the writes the
; typed DDR boundary's endpoint (private_kv_req_*) accepted since the
; record's start are exactly eighteen: the eight coordinate words of the K
; row, the K metadata word, the eight coordinate words of the V row, the V
; metadata word, in that order, each at its address, and all eighteen
; address and data words are those of the record as the controller held it
; in one cycle, the record's start.  The record was not interrupted between
; its start and that edge.  This is kv-write-record, near the end of this
; file, stated in terms of RTL signals; kv-write-record-prefix and
; kv-write-record-not-credited-when-interrupted say what holds of a record
; that CLEAR interrupts.
;
; WHAT IT RESTS ON.  The imported book's facts about every cycle
; (kv-write-payload-guarantee and the lemmas under its row theorem), the
; two new facts of kv-write-record-lift.lisp, and an induction over the
; cycles of the execution that follows one record from its start.  No row is
; assumed to complete: the K row, the step to the V row, the V row and the
; identity of the record across all three are derived.
(in-package "SV")
(include-book "kv-write-record-lift")
(acl2::set-slow-alist-action nil)

""" + record_main.text() + record_main.text2() + record_main.text3() + """
; ===========================================================================
; A REACHABLE STALLED COMPLETION.  One cycle after another of the step run
; from the reset state, three reset cycles first, as in the payload book,
; with the endpoint refusing writes for long stretches.  This is a run of
; the slice with the forward pass and the endpoint scripted; it shows that
; the theorem's hypothesis, pending_persisted_q rising, is met under
; backpressure, and it evaluates the theorem's conclusion on that run.
; ===========================================================================
""" + record_run.run_text() + record_run.CONSTS + """
; The record the script stages, computed outside ACL2 from the staged keys,
; values and exponents and the address formula (the payload book's list).
(defconst *rec-expected*
  """ + gen_run.expected_text() + """)

; The run ends with pending_persisted_q rising at cycle n; a record started
; at j, the latest start up to n; from j to n the controller is writing and
; not interrupted.
(defthm kv-write-record-run-completes
  (and (equal *rec-run-outcome* :complete)
       (natp *rec-run-n*) (natp *rec-run-j*) (natp *rec-run-jv*)
       (< *rec-run-j* *rec-run-jv*) (< *rec-run-jv* *rec-run-n*)
       (equal *rec-run-written-throughout* t))
  :rule-classes nil)

; The endpoint stalled it: in %(refused)d of the cycles from j to n a write
; was offered and refused, %(longest)d of them in a row.
(defthm kv-write-record-run-was-stalled
  (and (equal *rec-run-refused* %(refused)d)
       (equal *rec-run-longest-stall* %(longest)d))
  :rule-classes nil)

; The theorem's conclusion on this run: the writes accepted from j to n are
; the eighteen words of the record the registers held at j; the registers
; held that same record in every cycle from j to n; and it is the record
; the script staged.
(defthm kv-write-record-run-is-the-record
  (and (equal (len *rec-run-writes*) 18)
       (equal *rec-run-writes* *rec-run-held-at-start*)
       (equal *rec-run-same-record-throughout* t)
       (equal *rec-run-held-at-start* *rec-expected*))
  :rule-classes nil)
""" % dict(refused=RUN_REFUSED, longest=RUN_LONGEST))


# What the scripted run does on the pinned RTL (certified by the theorem
# kv-write-record-run-was-stalled; a different number would fail there).
RUN_REFUSED = 114
RUN_LONGEST = 40


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def mutant_files():
    """(path relative to this directory, sha256) of the RTL the negative
    control reads: the parent's pinned files, with the controller taken from
    rtl-mismatched-rows/."""
    pinned = {}
    for line in open(os.path.join(PARENT, "SOURCES.sha256")):
        h, path = line.split()
        pinned[path] = h
    files = [l.strip() for l in open(os.path.join(PARENT, "rtl", "FILES.txt")) if l.strip()]
    out = []
    for f in files:
        if f == KV_FILE:
            mine = "rtl-mismatched-rows/" + f
            out.append((mine, sha256(os.path.join(HERE, mine))))
        else:
            out.append(("../kv-joined-book-checked-sat/rtl/" + f, pinned["rtl/" + f]))
    assert any(p.startswith("rtl-mismatched-rows/") for p, _ in out)
    return out


def mismatched_rows_book():
    design = payload.design_forms(mutant_files())
    design = design.replace("kv-write-payload-early-metadata", "kv-write-record-mismatched-rows")
    old = """; The RTL: the joined book's pinned files, with the K/V controller taken from
; rtl-early-metadata/ (early-metadata.patch: one line)."""
    assert design.count(old) == 1
    design = design.replace(old, """; The RTL: the parent's pinned files, with the K/V controller taken from
; rtl-mismatched-rows/ (mismatched-rows.patch: one line added).""")
    lemma = gen_lemma.lemma()
    pay_defs = lemma[:lemma.index("(def-svtv-generalized-thm")]
    return (BANNER % "Negative control: a controller that pairs a K row with the V row of another position."
            + """;
; The RTL here is the pinned RTL with one line added to the K/V controller
; (mismatched-rows.patch): at the step from the K row's last word to the V
; row, pending_position_q is incremented.  The V row of a record is then
; written to the V addresses of the next position.  Each row, taken alone,
; is still what the row theorem of the payload book asks: nine writes, in
; order, equal to the row's nine words as the controller holds them when
; that row starts.  The record is wrong: its two rows belong to different
; positions.  Three things are certified here.
;   1. The scripted run of kv-write-record.lisp, on this RTL, completes and
;      raises pending_persisted_q.
;   2. On that run each row alone passes, and the record fails: the
;      eighteen accepted writes are not the record held at the record's
;      start, the held record changes during the write, and the nine V
;      writes are the staged V words at addresses 18 too high.
;   3. The proof of the new step lemma, the one that succeeds for the pinned
;      RTL, fails, with a counterexample the prover verifies.
; If the patch were not applied this book would not certify.
(in-package "SV")
""" + "".join('(include-book "%s" :dir :system)\n' % b for b in payload.LIBRARY_BOOKS)
            + """(include-book "std/testing/must-fail" :dir :system)
(include-book "../kv-joined-book-checked-sat/kv-joined-statements")
(include-book "../kv-joined-book-checked-sat/kv-joined-pins")

""" + SETTINGS + "\n" + design + gen_lemma.predicates() + "\n"
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
; 1 and 2. The scripted run.  The helpers are the payload book's, the record
; and the run are kv-write-record.lisp's, character for character.
; ---------------------------------------------------------------------------
""" + gen_run.run_text().replace('(in-package "SV")\n', "") + "\n" + record_defs()
            + record_run.run_text() + record_run.CONSTS + """
; the record the script stages, as kv-write-record.lisp states it
(defconst *rec-expected*
  """ + gen_run.expected_text() + """)
; the staged V row at the V addresses of the next position: 18 higher
(defconst *rec-expected-v-row-misplaced*
  """ + expected_shifted(18) + """)

; The run ends with pending_persisted_q rising, after eighteen writes, with
; the controller writing and not interrupted from the record's start on.
(defthm kv-write-record-mismatched-rows-run-completes
  (and (equal *rec-run-outcome* :complete)
       (natp *rec-run-n*) (natp *rec-run-j*) (natp *rec-run-jv*)
       (equal (len *rec-run-writes*) 18)
       (equal *rec-run-written-throughout* t))
  :rule-classes nil)

; Each row alone is what the row theorem asks of it: the first nine writes
; are the K row as held when the K row starts, the last nine are the V row
; as held when the V row starts.
(defthm kv-write-record-mismatched-rows-each-row-alone-passes
  (and (equal (take 9 *rec-run-writes*) (take 9 *rec-run-held-at-start*))
       (equal (nthcdr 9 *rec-run-writes*) (nthcdr 9 *rec-run-held-at-v-start*)))
  :rule-classes nil)

; The record fails.  The eighteen writes are not the record held at the
; record's start; the held record does not stay the same; the K row is the
; staged K row at its addresses, and the V row is the staged V row at the
; addresses of the next position.
(defthm kv-write-record-mismatched-rows-run-is-not-one-record
  (and (not (equal *rec-run-writes* *rec-run-held-at-start*))
       (not (equal *rec-run-same-record-throughout* t))
       (not (equal *rec-run-writes* *rec-expected*))
       (equal (take 9 *rec-run-writes*) (take 9 *rec-expected*))
       (equal (nthcdr 9 *rec-run-writes*) *rec-expected-v-row-misplaced*))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; 3. The new step lemma is not provable.  The predicates and the statement
;    below are, character for character, those of kv-write-record-step.lisp.
; ---------------------------------------------------------------------------
; The payload book's predicates come first: the statement uses its integer
; predicates pay-int-...
""" + pay_defs + "\n" + R.predicates() + """
(acl2::must-fail
 (encapsulate nil
   (local (include-book "centaur/sv/svtv/svtv-generalize" :dir :system))
   (make-event
    '""" + R.theorem().rstrip("\n").replace("\n", "\n     ") + """))
 :with-output-off nil)
""")


def main():
    OUTPUTS["kv-write-record-step.lisp"] = step_book()
    OUTPUTS["kv-write-record-lift.lisp"] = lift_book()
    OUTPUTS["kv-write-record.lisp"] = theorem_book()
    OUTPUTS["kv-write-record-mismatched-rows.lisp"] = mismatched_rows_book()
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

"""The new facts about one cycle that the record theorem needs, and the step
lemma that proves them.

The certified payload book (../kv-write-payload-checked-parent) gives facts
about one cycle of one row.  A record is two rows.  What was missing is how
the controller gets from one cycle of writing to the next across the whole
record: that it enters a write state only at the record's start or from
another write state, that it changes row only at the step from the K row's
last word to the V row's first, and that this step leaves the record's
layer, position and exponents alone.  These are statements about the
controller's next state, so they are proved the way the payload facts were:
of one symbolic cycle of the same step run, from the same hypotheses.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PAYLOAD = os.path.normpath(os.path.join(HERE, "..", "..", "kv-write-payload-checked-parent"))
sys.path.insert(0, os.path.join(PAYLOAD, "dev"))
import proto_run  # noqa: E402
import gen_lemma  # noqa: E402
import payload_lib as L  # noqa: E402

V = dict(gen_lemma.FACT_VARS)
V.update(layer="r-k-pending-layer-q", nlayer="(pay-u n-k-pending-layer-q)",
         pos="r-k-pending-position-q", npos="(pay-u n-k-pending-position-q)",
         ke="r-k-pending-key-exponents-q", nke="(pay-u n-k-pending-key-exponents-q)",
         ve="r-k-pending-value-exponents-q", nve="(pay-u n-k-pending-value-exponents-q)")
ANTE = "(and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))"

FACTS = [
    ("rec-fact-entry",
     """A write state that is not interrupted, other than the record's start, is
; entered only from a write state that is not interrupted, in a cycle
; without CLEAR: either on the same row, or by the one step that changes
; row, from the wait on word 8 of the K row to the first prefetch of word 0
; of the V row, and that step leaves the record's layer, position and
; exponent bytes as they were.""",
     """(or (not (and (pay-writing-p %(nst)s) (equal %(nab)s 0)
                  (not (and (equal %(nst)s 9) (equal %(nh)s 0) (equal %(nw)s 0)))))
      (and (pay-writing-p %(st)s) (equal %(ab)s 0) (equal %(clear)s 0)
           (or (equal %(nh)s %(h)s)
               (and (equal %(st)s 3) (equal %(h)s 0) (equal %(w)s 8)
                    (equal %(nst)s 9) (equal %(nh)s 1) (equal %(nw)s 0)
                    (equal %(nlayer)s %(layer)s) (equal %(npos)s %(pos)s)
                    (equal %(nke)s %(ke)s) (equal %(nve)s %(ve)s)))))""" % V),
    ("rec-fact-start",
     """The record's start, the first prefetch of word 0 of the K row, is entered
; only from staging, by the acceptance of the beat for coordinate 127, in a
; cycle without CLEAR, and it starts not interrupted.""",
     """(or (not (and (equal %(nst)s 9) (equal %(nh)s 0) (equal %(nw)s 0)))
      (and (equal %(st)s 1) (equal %(beat)s 1) (equal %(coord)s 127)
           (equal %(nab)s 0) (equal %(clear)s 0)))""" % V),
]

VAR = gen_lemma.VAR


def shape():
    """Output variables, predicate calls and formals of the new step lemma."""
    used = set(re.findall(r"[a-z0-9-]+", ANTE + " ".join(b for _, _, b in FACTS)))
    next_ctrl = ["n-" + s for s in L.STATES]
    outs = [o for o in ["o-pfn", "o-tpf", "o-epf"] + L.OBS + next_ctrl if o in used]
    calls = []
    for name, _, body in FACTS:
        calls.append("(%s %s)" % (name, " ".join(sorted(set(VAR.findall(body))))))
    cformals = sorted(set(VAR.findall(ANTE + " ".join(calls))))
    base = gen_lemma.lemma_shape()
    return dict(outs=outs, calls=calls, cformals=cformals, overrides=base["overrides"], hyp=base["hyp"],
                int_calls=["(pay-int-%s %s)" % (o, o) for o in outs],
                concl_call="(rec-step-concl %s)" % " ".join(cformals))


def predicates():
    prove = '(fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "%s"\n  %s)'
    sh = shape()
    text = ""
    for name, comment, body in FACTS:
        formals = sorted(set(VAR.findall(body)))
        text += ("; %s\n(define %s (%s)\n  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t\n  %s)\n"
                 % (comment, name, " ".join(formals), prove % (name, body)))
    text += "(in-theory (disable %s))\n" % " ".join(n for n, _, _ in FACTS)
    text += ("\n; THE CONCLUSION of the new step lemma: with no protocol violation by the\n"
             "; client and no malformed metadata word from the endpoint in the cycle\n"
             "; (the antecedent of the payload step lemma), both facts.\n"
             "(define rec-step-concl (%s)\n  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t\n"
             "  (if %s\n      (and %s)\n    t))\n(in-theory (disable rec-step-concl))\n"
             % (" ".join(sh["cformals"]), ANTE, "\n           ".join(sh["calls"])))
    return text


def theorem(name="rec-step-svtv-thm"):
    sh = shape()
    return """(def-svtv-generalized-thm %s
  :svtv payload-step-run
  :svtv-spec payload-step-spec
  :input-vars :all
  :output-vars (%s)
  :unsigned-byte-hyps t
  :no-integerp t
  :enable (%s)
  :override-vars (%s)
  :spec-override-vars ()
  :hyp %s
  :concl (and %s
       %s))
""" % (name, " ".join(sh["outs"]), " ".join("pay-int-%s-integerp" % o for o in sh["outs"]),
       " ".join(sh["overrides"]), sh["hyp"], "\n       ".join(sh["int_calls"]), sh["concl_call"])


def folded(name="rec-step-svtv-thm-folded", proved=True):
    """The same lemma with its conclusion as one predicate, rec-step-all."""
    sh = shape()
    allvars = sorted(set(sh["outs"]) | set(sh["cformals"]))
    define = """(define rec-step-all (%s)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t
  (and %s
       %s))
(in-theory (disable rec-step-all))
""" % (" ".join(allvars), "\n       ".join(sh["int_calls"]), sh["concl_call"])
    thm = """(def-svtv-generalized-thm %s
      :svtv payload-step-run
      :svtv-spec payload-step-spec
      :input-vars :all
      :output-vars (%s)
      :unsigned-byte-hyps t
      :no-integerp t
      :override-vars (%s)
      :spec-override-vars ()
      :hyp %s
      :concl (rec-step-all %s)
      :no-lemmas t
      :hints (("Goal" :use ((:instance rec-step-svtv-thm))
               :in-theory '(rec-step-all))))""" % (
        name, " ".join(sh["outs"]), " ".join(sh["overrides"]), sh["hyp"].replace("\n", "\n      "),
        " ".join(allvars))
    return define, thm


if __name__ == "__main__":
    # development: the predicates and the lemma as a script for a session
    sys.stdout.write(predicates() + "\n" + theorem())

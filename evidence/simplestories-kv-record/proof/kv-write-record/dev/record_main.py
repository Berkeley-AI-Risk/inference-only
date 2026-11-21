"""The record argument: from the facts about one cycle to the theorem about a
whole record.  This writes the ACL2 text; make_record_book.py puts it in the
book.  The text is long mostly because each fact about one symbolic cycle has
to be restated about cycle k of an execution, signal by signal.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import record_step as R  # noqa: E402  (puts the payload book's dev/ on the path)
import gen_lemma  # noqa: E402
import payload_lib as L  # noqa: E402

PAYLOAD = R.PAYLOAD
BANKS = ["bank%d" % i for i in range(8)]
EP = "(if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0)"
BEAT = "(if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0)"


def accessor_names():
    """The signals the certified book already has a pay$ accessor for."""
    text = open(os.path.join(PAYLOAD, "dev", "row_section.lsp")).read()
    i = text.index("(names '(") + len("(names '(")
    return text[i:text.index(")", i)].split()


def pay_calls():
    return {n: "(%s %s)" % (n, " ".join(f)) for n, _, _, f in gen_lemma.conclusions(("2v", "inv", "typed", "endpoint", "facts"))}


def rec_calls():
    return dict(zip([n for n, _, _ in R.FACTS], R.shape()["calls"]))


def variables(*calls):
    return sorted(set(R.VAR.findall(" ".join(calls))))


def instance(lemma, names):
    return "(:instance %s\n%s)" % (lemma, "\n".join(
        "                  (%s (pay$%s k (+ 1 k) envs outs))" % (v, v) for v in names))


WIDTH = {"k-state-q": 4, "k-write-word-q": 4, "k-write-head-q": 1, "k-write-aborted-q": 1,
         "k-pending-layer-q": 3, "k-pending-position-q": 12, "k-pending-key-exponents-q": 16,
         "k-pending-value-exponents-q": 16, "k-pending-persisted-q": 1, "q-wb": 4, "q-rb": 4,
         "a-unissued": 4, "a-offer": 1}
WIDTH.update({"k-" + b: 1024 for b in BANKS})


def ubp(prefix, ids):
    return "\n                ".join("(unsigned-byte-p %d %s-%s)" % (WIDTH[i], prefix, i) for i in ids)


def record_args(prefix):
    return " ".join("%s-k-%s" % (prefix, s) for s in
                    ["pending-layer-q", "pending-position-q", "pending-key-exponents-q",
                     "pending-value-exponents-q"] + BANKS)


def at_args(k):
    return " ".join("(pay$r-k-%s %s %s nil outs)" % (s, k, k) for s in
                    ["pending-layer-q", "pending-position-q", "pending-key-exponents-q",
                     "pending-value-exponents-q"] + BANKS)


def text():
    pc = pay_calls()
    rc = rec_calls()
    acc = accessor_names()
    new_acc = ["i-clear", "n-k-pending-persisted-q"]
    all_acc = " ".join("pay$" + a for a in acc + new_acc)
    next_def = " ".join("pay-next-definite-%s" % p for p in L.PAYLOAD)
    words = "\n        ".join("(rec-word %d %d l p ke ve b0 b1 b2 b3 b4 b5 b6 b7)" % (h, w)
                              for h in (0, 1) for w in range(9))
    ctrl = ["k-state-q", "k-write-word-q", "k-write-head-q", "k-write-aborted-q", "k-pending-layer-q",
            "k-pending-position-q", "k-pending-key-exponents-q", "k-pending-value-exponents-q",
            "q-wb", "q-rb", "a-unissued", "a-offer"] + ["k-" + b for b in BANKS]
    step_facts = [pc["pay-fact-progress"], pc["pay-fact-stage-only-while-staging"], pc["pay-fact-accepted-once"],
                  pc["pay-endpoint-accept-p"], pc["pay-fact-row-finished"]] \
        + [pc["pay-fact-bank%d-staged" % b] for b in range(8)] + [rc["rec-fact-entry"]]
    step_vars = variables(*step_facts) + []
    for extra in ["o-epaddr", "o-epdata"]:
        assert extra in step_vars
    complete_facts = [pc["pay-fact-reported-complete"], pc["pay-fact-accepted-once"]]
    complete_vars = variables(*complete_facts)
    start_vars = variables(rc["rec-fact-start"])
    racc = "(pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer)"
    nacc = "(pay-accepted n-k-state-q n-q-wb n-q-rb n-a-unissued n-a-offer)"
    cycle_theory = """(e/d (rec-known-at pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-j-at pay-definite-raw pay-inv-raw pay-next-inv
                            pay-facts-at pay-facts-raw pay-ints-at pay-ints-raw
                            rec-facts-at rec-facts-raw
                            pay-st-at pay-st-raw pay-w-at pay-w-raw pay-h-at pay-h-raw
                            pay-ab-at pay-ab-raw pay-acc-at pay-acc-raw
                            pay-ep-at pay-ep-raw pay-epwrite-at pay-epwrite-raw
                            rec-word-at rec-words-at rec-clear-at rec-per-at rec-beat-at
                            rec-coord-at rec-progress-at rec-start-p rec-live-p rec-complete-at
                            fgl::fgl-prove-fn
                            %s
                            pay-int-o-epaddr pay-int-o-epdata
                            %s)
                           (unsigned-byte-p nth nthcdr take len rec-word rec-words))""" % (
        " ".join("pay-next-definite-k-" + b for b in BANKS), all_acc)
    return ("""; ---------------------------------------------------------------------------
; THE NEW FACTS AT CYCLE k OF AN EXECUTION.  The lifted lemma's own signal
; bindings are read back from the world, as the payload book does.
; ---------------------------------------------------------------------------
(make-event
 (b* ((ev (acl2::get-event 'rec-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (decl `(declare (xargs :verify-guards nil) (ignorable ,@formals)))
      (idecl `(declare (ignorable ,@vars))))
   `(progn
      (defun rec-facts-raw ,formals ,decl
        (let* ,bindings ,idecl
          (and %(rec_entry)s
               %(rec_start)s)))
      (in-theory (disable rec-facts-raw)))))
; The two new facts about cycle k.
(define rec-facts-at (k envs outs) :verify-guards nil
  (rec-facts-raw k (+ 1 k) envs outs))

; One cycle: from the joined invariant, the payload invariant and the
; environment at cycle k to the new facts about cycle k.
(defthm rec-step-glue
  (implies (and (natp k)
                (join-j-at k envs (fsm-eval envs initst (probe-fsm)))
                (join-env-at k envs (fsm-eval envs initst (probe-fsm)))
                (pay-j-at k envs (fsm-eval envs initst (probe-fsm))))
           (rec-facts-at k envs (fsm-eval envs initst (probe-fsm))))
  :hints (("Goal"
           :use ((:instance rec-step-fsm-thm
                  (base-cycle k) (base-cycle+1 (+ 1 k)))
                 (:instance kv-write-payload-run-constraints))
           :in-theory (e/d (join-j-at join-env-at join-inv-raw join-resetalt-raw
                            join-env-raw joint-2valued-p
                            pay-j-at rec-facts-at pay-definite-raw pay-inv-raw
                            rec-facts-raw rec-step-all rec-step-concl
                            fgl::fgl-prove-fn %(next_def)s pay-next-inv)
                           (rec-step-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm)))))

; Two signals the payload book did not need by name: clear_i in a cycle, and
; the next value of pending_persisted_q.
(make-event
 (b* ((ev (acl2::get-event 'pay-step-fsm-thm (w state)))
      (body (third ev))
      (bindings (cddr (second body)))
      (vars (strip-cars bindings))
      (formals '(base-cycle base-cycle+1 envs outs))
      (names '(%(new_acc)s)))
   (cons 'progn
         (append
          (pay-accessor-events names formals bindings vars)
          (list `(in-theory (disable ,@(pay-accessor-names names))))))))

; ---------------------------------------------------------------------------
; A RECORD.  The controller holds a staged record as a layer, a position, two
; exponent registers (one for the K row, one for the V row) and the pair
; store.  Word w of row h of it (h = 0 the K row, h = 1 the V row; w = 8 the
; metadata word) is an address and a data word, by the payload book's
; pay-addr and pay-data.  The record is its eighteen words in the order they
; are written: the K row's nine, then the V row's nine.
; ---------------------------------------------------------------------------
(define rec-word (h w l p ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (list (pay-addr l p h w)
        (pay-data w h ke ve b0 b1 b2 b3 b4 b5 b6 b7)))
(define rec-words (l p ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (list %(words)s))

; The same of the record as the controller holds it in cycle k.
(define rec-word-at (h w k outs) :verify-guards nil
  (rec-word h w %(at_k)s))
(define rec-words-at (k outs) :verify-guards nil
  (rec-words %(at_k)s))
; clear_i in cycle k
(define rec-clear-at (k envs) :verify-guards nil
  (pay$i-clear k k envs nil))
; pending_persisted_q in cycle k
(define rec-per-at (k outs) :verify-guards nil
  (pay$r-k-pending-persisted-q k k nil outs))
; 1 when a staging beat is accepted in cycle k, and the coordinate it is for
(define rec-beat-at (k envs outs) :verify-guards nil
  (if (and (equal (pay$h-spayload k k envs outs) 1)
           (equal (pay$o-spr k k envs outs) 1)
           (equal (pay$o-spl k k envs outs) 1))
      1 0))
(define rec-coord-at (k outs) :verify-guards nil
  (pay$r-k-expected-coordinate-q k k nil outs))
; The record's start: the first prefetch state with the K row selected and
; the word counter at 0.
(define rec-start-p (k outs) :verify-guards nil
  (and (equal (pay-st-at k outs) 9)
       (equal (pay-h-at k outs) 0)
       (equal (pay-w-at k outs) 0)))
; The controller is writing a record and CLEAR has not interrupted it.
(define rec-live-p (k outs) :verify-guards nil
  (and (pay-writing-p (pay-st-at k outs))
       (equal (pay-ab-at k outs) 0)))
; How many of the record's eighteen words the endpoint has accepted: nine for
; the K row once the V row is selected, the word counter, and one more when
; the word waited on has been accepted.
(define rec-progress-at (k outs) :verify-guards nil
  (+ (* 9 (pay-h-at k outs)) (pay-w-at k outs) (pay-acc-at k outs)))
; The completion edge: pending_persisted_q is 0 in cycle k and 1 in cycle k+1.
(define rec-complete-at (k outs) :verify-guards nil
  (and (equal (rec-per-at k outs) 0)
       (equal (rec-per-at (+ 1 k) outs) 1)))
; Everything known about cycle i: what the payload book knows, and the two
; new facts.
(define rec-known-at (i envs outs) :verify-guards nil
  (and (pay-known-at i envs outs)
       (rec-facts-at i envs outs)))

; ---------------------------------------------------------------------------
; ONE CYCLE OF A RECORD, first about plain values.  If the next state is a
; write state, not interrupted and not the record's start, then this state
; is one too, there is no CLEAR in the cycle, the record's eighteen words do
; not change, progress goes up exactly by the endpoint's acceptance, and an
; accepted write is the word that progress points at.  This covers the step
; from the K row to the V row: there the progress is nine before and after.
; ---------------------------------------------------------------------------
(defthm rec-accepted-when-not-waiting
  (implies (not (equal st 3))
           (equal (pay-accepted st wb rb uni offq) 0))
  :hints (("Goal" :in-theory (enable pay-accepted))))
(defthm rec-step-of-values
  (implies (and %(step_facts)s
                %(ubp_r)s
                %(ubp_n)s
                (integerp o-epaddr)
                (integerp o-epdata)
                (pay-writing-p n-k-state-q)
                (equal n-k-write-aborted-q 0)
                (not (and (equal n-k-state-q 9) (equal n-k-write-head-q 0)
                          (equal n-k-write-word-q 0))))
           (and (pay-writing-p r-k-state-q)
                (equal r-k-write-aborted-q 0)
                (equal i-clear 0)
                (equal (rec-words %(n_rec)s)
                       (rec-words %(r_rec)s))
                (equal (+ (* 9 n-k-write-head-q) n-k-write-word-q %(nacc)s)
                       (+ (* 9 r-k-write-head-q) r-k-write-word-q %(racc)s
                          %(ep)s))
                (implies (equal %(ep)s 1)
                         (and (equal %(racc)s 0)
                              (equal (list o-epaddr o-epdata)
                                     (rec-word r-k-write-head-q r-k-write-word-q %(r_rec)s))))))
  :hints (("Goal"
           :in-theory (e/d (pay-fact-progress pay-fact-stage-only-while-staging
                            pay-fact-accepted-once pay-endpoint-accept-p pay-fact-row-finished
                            %(bank_facts)s
                            rec-fact-entry fgl::fgl-prove-fn pay-data-is-of-staged
                            rec-words rec-word pay-row-done-p)
                           (unsigned-byte-p pay-writing-p pay-accepted pay-addr
                            pay-data pay-data-s pay-staged pay-staged-put))))
  :rule-classes nil)

; The same about cycle k of an execution.
(defthm rec-step
  (implies (and (natp k)
                (rec-known-at k envs outs)
                (rec-live-p (+ 1 k) outs)
                (not (rec-start-p (+ 1 k) outs)))
           (and (rec-live-p k outs)
                (equal (rec-clear-at k envs) 0)
                (equal (rec-words-at (+ 1 k) outs) (rec-words-at k outs))
                (equal (rec-progress-at (+ 1 k) outs)
                       (+ (rec-progress-at k outs) (pay-ep-at k envs outs)))
                (implies (equal (pay-ep-at k envs outs) 1)
                         (and (equal (pay-acc-at k outs) 0)
                              (equal (pay-epwrite-at k envs outs)
                                     (rec-word-at (pay-h-at k outs) (pay-w-at k outs) k outs))))))
  :hints (("Goal"
           :use (%(step_instance)s)
           :in-theory %(cycle_theory)s))
  :rule-classes nil)

; The record is reported complete only from the wait on word 8 of the V row,
; not interrupted, in a cycle without CLEAR, after the endpoint accepted
; that word and not in a cycle in which the endpoint accepts a write.
(defthm rec-complete-of-values
  (implies (and %(complete_facts)s
                (unsigned-byte-p 1 r-k-pending-persisted-q)
                (unsigned-byte-p 1 n-k-pending-persisted-q)
                (unsigned-byte-p 4 n-k-state-q)
                (unsigned-byte-p 4 n-q-wb) (unsigned-byte-p 4 n-q-rb)
                (unsigned-byte-p 4 n-a-unissued) (unsigned-byte-p 1 n-a-offer)
                (equal r-k-pending-persisted-q 0)
                (equal n-k-pending-persisted-q 1))
           (and (equal r-k-state-q 3)
                (equal r-k-write-head-q 1)
                (equal r-k-write-word-q 8)
                (equal r-k-write-aborted-q 0)
                (equal i-clear 0)
                (equal %(racc)s 1)
                (equal %(ep)s 0)))
  :hints (("Goal" :in-theory (e/d (pay-fact-reported-complete pay-fact-accepted-once fgl::fgl-prove-fn)
                                  (unsigned-byte-p pay-accepted))))
  :rule-classes nil)
(defthm rec-complete-step
  (implies (and (natp k)
                (rec-known-at k envs outs)
                (rec-complete-at k outs))
           (and (equal (pay-st-at k outs) 3)
                (equal (pay-h-at k outs) 1)
                (equal (pay-w-at k outs) 8)
                (equal (pay-ab-at k outs) 0)
                (equal (rec-clear-at k envs) 0)
                (equal (pay-acc-at k outs) 1)
                (equal (pay-ep-at k envs outs) 0)))
  :hints (("Goal"
           :use (%(complete_instance)s)
           :in-theory %(cycle_theory)s))
  :rule-classes nil)

; The record's start is entered only from staging, by the acceptance of the
; beat for coordinate 127, in a cycle without CLEAR.
(defthm rec-start-of-values
  (implies (and %(rec_start)s
                (unsigned-byte-p 4 n-k-state-q) (unsigned-byte-p 1 n-k-write-head-q)
                (unsigned-byte-p 4 n-k-write-word-q) (unsigned-byte-p 1 n-k-write-aborted-q)
                (equal n-k-state-q 9) (equal n-k-write-head-q 0) (equal n-k-write-word-q 0))
           (and (equal r-k-state-q 1)
                (equal %(beat)s 1)
                (equal r-k-expected-coordinate-q 127)
                (equal n-k-write-aborted-q 0)
                (equal i-clear 0)))
  :hints (("Goal" :in-theory (e/d (rec-fact-start fgl::fgl-prove-fn) (unsigned-byte-p))))
  :rule-classes nil)
(defthm rec-start-step
  (implies (and (natp k)
                (rec-known-at k envs outs)
                (rec-start-p (+ 1 k) outs))
           (and (equal (pay-st-at k outs) 1)
                (equal (rec-beat-at k envs outs) 1)
                (equal (rec-coord-at k outs) 127)
                (equal (rec-clear-at k envs) 0)
                (rec-live-p (+ 1 k) outs)))
  :hints (("Goal"
           :use (%(start_instance)s)
           :in-theory %(cycle_theory)s))
  :rule-classes nil)
""" % dict(rec_entry=rc["rec-fact-entry"], rec_start=rc["rec-fact-start"], next_def=next_def,
           new_acc=" ".join(new_acc), words=words, at_k=at_args("k"),
           step_facts="\n                ".join(step_facts),
           ubp_r=ubp("r", ctrl), ubp_n=ubp("n", ctrl), n_rec=record_args("n"), r_rec=record_args("r"),
           nacc=nacc, racc=racc, ep=EP, beat=BEAT,
           bank_facts=" ".join("pay-fact-bank%d-staged" % b for b in range(8)),
           step_instance=instance("rec-step-of-values", step_vars + ["i-clear"] if "i-clear" not in step_vars else step_vars),
           complete_facts="\n                ".join(complete_facts),
           complete_instance=instance("rec-complete-of-values", complete_vars),
           start_instance=instance("rec-start-of-values", start_vars),
           cycle_theory=cycle_theory))


def text2():
    cases = " ".join("(equal w %d)" % w for w in range(9))
    return r"""
; ---------------------------------------------------------------------------
; THE RECORD AS A LIST OF WRITES.
; ---------------------------------------------------------------------------
(defthm rec-len-of-words
  (equal (len (rec-words-at k outs)) 18)
  :hints (("Goal" :in-theory (enable rec-words-at rec-words))))
(defthm rec-nth-of-words
  (implies (and (natp w) (<= w 8) (or (equal h 0) (equal h 1)))
           (equal (nth (+ (* 9 h) w) (rec-words-at k outs))
                  (rec-word-at h w k outs)))
  :hints (("Goal" :cases (@@CASES@@)
           :in-theory (e/d (rec-words-at rec-words rec-word-at) (rec-word))))
  :rule-classes nil)
(defthm rec-take-18-of-words
  (equal (take 18 (rec-words-at k outs)) (rec-words-at k outs))
  :hints (("Goal" :in-theory (enable rec-words-at rec-words))))
(defthm rec-append-nil-of-words
  (equal (append (rec-words-at k outs) nil) (rec-words-at k outs))
  :hints (("Goal" :in-theory (enable rec-words-at rec-words))))
(defthm rec-bit-cases
  (implies (unsigned-byte-p 1 x) (or (equal x 0) (equal x 1)))
  :rule-classes nil)
; the row selector is a bit
(defthm rec-head-bit
  (implies (pay-known-at k envs outs)
           (or (equal (pay-h-at k outs) 0) (equal (pay-h-at k outs) 1)))
  :hints (("Goal"
           :use ((:instance rec-bit-cases (x (pay-h-at k outs))))
           :in-theory (e/d (pay-known-at join-j-at join-inv-raw joint-2valued-p
                            pay-h-at pay-h-raw)
                           (unsigned-byte-p nth nthcdr take len))))
  :rule-classes nil)

; The latest cycle up to n at which a record starts; nil when there is none.
(defund rec-start (n outs)
  (declare (xargs :measure (nfix n) :verify-guards nil))
  (cond ((rec-start-p (nfix n) outs) (nfix n))
        ((zp n) nil)
        (t (rec-start (- n 1) outs))))
; In every cycle from j to n the controller is writing and not interrupted,
; and there is no CLEAR in any cycle from j to n-1.
(defund rec-uninterrupted (j n envs outs)
  (declare (xargs :measure (nfix (- (nfix n) (nfix j))) :verify-guards nil))
  (and (rec-live-p (nfix n) outs)
       (or (zp (- (nfix n) (nfix j)))
           (and (equal (rec-clear-at (- (nfix n) 1) envs) 0)
                (rec-uninterrupted j (- (nfix n) 1) envs outs)))))
; The invariant of the argument, for a record that started at cycle j and is
; still being written at cycle n: it has not been interrupted, its eighteen
; words are those of cycle j, and the writes the endpoint accepted since j
; are the first `progress` of them.
(defund rec-inv (j n envs outs)
  (declare (xargs :verify-guards nil))
  (and (natp j) (<= j n)
       (rec-start-p j outs)
       (rec-uninterrupted j n envs outs)
       (equal (rec-words-at n outs) (rec-words-at j outs))
       (equal (pay-log j n envs outs)
              (take (rec-progress-at n outs) (rec-words-at j outs)))))

(defthm rec-inv-base
  (implies (and (natp j) (rec-start-p j outs) (rec-live-p j outs))
           (rec-inv j j envs outs))
  :hints (("Goal" :in-theory (enable rec-inv pay-log rec-uninterrupted rec-progress-at
                                     rec-start-p))))

(defthm rec-inv-step
  (implies (and (natp j) (natp k) (< j k)
                (rec-known-at (+ -1 k) envs outs)
                (rec-live-p k outs)
                (not (rec-start-p k outs))
                (rec-inv j (+ -1 k) envs outs))
           (rec-inv j k envs outs))
  :hints (("Goal"
           :use ((:instance rec-step (k (+ -1 k)))
                 (:instance pay-word-bound (k (+ -1 k)))
                 (:instance rec-head-bit (k (+ -1 k)))
                 (:instance pay-ep-at-is-a-bit (k (+ -1 k)))
                 (:instance pay-take-snoc
                  (m (rec-progress-at (+ -1 k) outs)) (x (rec-words-at j outs)))
                 (:instance rec-nth-of-words
                  (h (pay-h-at (+ -1 k) outs)) (w (pay-w-at (+ -1 k) outs)) (k (+ -1 k))))
           :expand ((pay-log j k envs outs)
                    (rec-uninterrupted j k envs outs))
           :in-theory (e/d (rec-inv rec-known-at rec-live-p rec-progress-at)
                           (pay-take-snoc pay-known-at rec-facts-at
                            rec-words-at rec-word-at take nth rec-start-p))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; From the reset and the environment to the invariant at every cycle.
; ---------------------------------------------------------------------------
; After three reset cycles the controller is idle.
(defthm rec-idle-after-reset
  (implies (and (natp r)
                (join-reset-at r envs (fsm-eval envs initst (probe-fsm))))
           (equal (pay-st-at (+ 2 r) (fsm-eval envs initst (probe-fsm))) 0))
  :hints (("Goal"
           :use ((:instance join-reset-fsm-thm
                  (base-cycle r) (base-cycle+2 (+ 2 r))))
           :in-theory (e/d (join-reset-at join-reset-raw joint-reset-p
                            pay-st-at pay-st-raw)
                           (join-reset-fsm-thm unsigned-byte-p nth nthcdr
                            take len fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

(defthm rec-known-at-from-reset
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp i) (<= (+ 2 r) i)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) (+ 1 i) envs outs))
             (rec-known-at i envs outs)))
  :hints (("Goal"
           :use ((:instance pay-known-at-from-reset)
                 (:instance join-env-from-shorter
                  (j (+ 2 r)) (n i) (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance join-inv-from-reset (n i))
                 (:instance pay-inv-from-reset (n i))
                 (:instance rec-step-glue (k i)))
           :in-theory (e/d (rec-known-at)
                           (join-inv-from-reset pay-inv-from-reset join-step-glue
                            pay-step-glue pay-ints-glue rec-step-glue join-inv-preserved
                            pay-inv-preserved join-reset-glue pay-reset-glue
                            join-j-at pay-j-at pay-facts-at pay-ints-at rec-facts-at
                            pay-known-at join-env-at join-env-from join-reset-at
                            pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; One more cycle of the induction.
(defthm rec-inv-holds-step
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (< (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs)
                  (rec-live-p n outs)
                  (implies (rec-live-p (+ -1 n) outs)
                           (and (natp (rec-start (+ -1 n) outs))
                                (< (+ 2 r) (rec-start (+ -1 n) outs))
                                (rec-inv (rec-start (+ -1 n) outs) (+ -1 n) envs outs))))
             (and (natp (rec-start n outs))
                  (< (+ 2 r) (rec-start n outs))
                  (rec-inv (rec-start n outs) n envs outs))))
  :hints (("Goal"
           :use ((:instance rec-known-at-from-reset (i (+ -1 n)))
                 (:instance rec-step (k (+ -1 n))
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance rec-inv-step (k n)
                  (j (rec-start (+ -1 n) (fsm-eval envs initst (probe-fsm))))
                  (outs (fsm-eval envs initst (probe-fsm))))
                 (:instance rec-inv-base (j n)
                  (outs (fsm-eval envs initst (probe-fsm)))))
           :expand ((rec-start n (fsm-eval envs initst (probe-fsm))))
           :in-theory (e/d (rec-inv)
                           (rec-inv-base rec-known-at rec-live-p rec-start-p
                            rec-uninterrupted pay-log rec-words-at rec-progress-at
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

(defun rec-ind (r n)
  (declare (xargs :measure (nfix n)))
  (if (or (zp n) (<= n (+ 2 (nfix r))))
      (list r n)
    (rec-ind r (- n 1))))

; THE INVARIANT AT EVERY CYCLE.  In every execution, with the reset, storage
; and environment hypotheses holding up to cycle n: if at cycle n the
; controller is writing a record, not interrupted, then a record started at
; some cycle j after the reset, j is the latest such cycle, and the
; invariant holds between j and n.
(defthm rec-inv-holds
  (b* ((outs (fsm-eval envs initst (probe-fsm))))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs)
                  (rec-live-p n outs))
             (and (natp (rec-start n outs))
                  (< (+ 2 r) (rec-start n outs))
                  (rec-inv (rec-start n outs) n envs outs))))
  :hints (("Goal"
           :induct (rec-ind r n)
           :in-theory (e/d (rec-ind)
                           (rec-inv rec-start rec-live-p rec-start-p join-env-from
                            join-reset-at pay-definite-at fsm-eval (probe-fsm) probe-fsm)))
          ("Subgoal *1/2"
           :use ((:instance rec-inv-holds-step)))
          ("Subgoal *1/1"
           :use ((:instance rec-idle-after-reset))
           :in-theory (e/d (rec-live-p)
                           (rec-inv rec-start rec-start-p join-env-from
                            join-reset-at pay-definite-at fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
""".replace("@@CASES@@", cases)


def text3():
    O = "(fsm-eval envs initst (probe-fsm))"
    J = "(rec-start n %s)" % O
    return r"""
; Inside an uninterrupted stretch every cycle is a write cycle, not
; interrupted, and none before the last has CLEAR.
(defthm rec-uninterrupted-at
  (implies (and (rec-uninterrupted j n envs outs)
                (natp j) (natp n) (natp m) (<= j m) (<= m n))
           (and (rec-live-p m outs)
                (implies (< m n) (equal (rec-clear-at m envs) 0))))
  :hints (("Goal"
           :induct (rec-uninterrupted j n envs outs)
           :in-theory (e/d (rec-uninterrupted) (rec-live-p rec-clear-at))))
  :rule-classes nil)

; A record's start, after the reset, is the cycle after staging accepted the
; beat for coordinate 127.
(defthm rec-start-facts
  (b* ((outs @@O@@))
    (implies (and (natp r) (natp j) (natp n) (< (+ 2 r) j) (<= j n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) n envs outs)
                  (rec-start-p j outs))
             (and (equal (pay-st-at (+ -1 j) outs) 1)
                  (equal (rec-beat-at (+ -1 j) envs outs) 1)
                  (equal (rec-coord-at (+ -1 j) outs) 127)
                  (equal (rec-clear-at (+ -1 j) envs) 0))))
  :hints (("Goal"
           :use ((:instance join-env-from-prefix
                  (j (+ 2 r)) (m j) (outs @@O@@))
                 (:instance rec-known-at-from-reset (i (+ -1 j)))
                 (:instance rec-start-step (k (+ -1 j)) (outs @@O@@)))
           :in-theory (disable rec-known-at rec-start-p rec-beat-at rec-coord-at rec-clear-at
                               rec-live-p join-env-from join-reset-at pay-definite-at
                               fsm-eval (probe-fsm) probe-fsm)))
  :rule-classes nil)

; THE RECORD, with the hypotheses in the form the induction uses.
(defthm rec-record-written
  (b* ((outs @@O@@)
       (j (rec-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (join-reset-at r envs outs)
                  (pay-definite-at (+ 2 r) envs outs)
                  (join-env-from (+ 2 r) (+ 1 n) envs outs)
                  (rec-complete-at n outs))
             (and (natp j) (< (+ 2 r) j) (<= j n)
                  (rec-start-p j outs)
                  (rec-uninterrupted j n envs outs)
                  (equal (rec-clear-at n envs) 0)
                  (equal (pay-log j (+ 1 n) envs outs) (rec-words-at j outs)))))
  :hints (("Goal"
           :use ((:instance rec-known-at-from-reset (i n))
                 (:instance rec-complete-step (k n) (outs @@O@@))
                 (:instance rec-inv-holds)
                 (:instance join-env-from-shorter
                  (j (+ 2 r)) (outs @@O@@)))
           :expand ((pay-log @@J@@ (+ 1 n) envs @@O@@))
           :in-theory (e/d (rec-inv rec-live-p rec-progress-at)
                           (rec-known-at rec-start-p rec-uninterrupted pay-log
                            rec-words-at rec-complete-at rec-start rec-clear-at
                            join-env-from join-reset-at pay-definite-at pay-writing-p
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; ===========================================================================
; THE RECORD THEOREM.
;
; The definitions it is stated with.  Every one reads RTL signals of the
; probe module board1_context2048_shared_token_probe; the controller is
; u_machine.u_six_layers.u_datapath.u_kv_cache.
; ===========================================================================
; clear_i in cycle k
(define kv-clear-at (k envs) :verify-guards nil
  (rec-clear-at k envs))
; THE COMPLETION EDGE: the controller's pending_persisted_q is 0 in cycle n
; and 1 in cycle n+1.
(define kv-record-reported-complete-at (n outs) :verify-guards nil
  (rec-complete-at n outs))
; THE RECORD'S START, as a condition on one cycle: the controller's state_q
; is its first write prefetch state (9), write_head_q is 0 (the K row) and
; write_word_q is 0; and in the cycle before, state_q is the staging state
; (1) and the staging beat for expected_coordinate_q = 127 is accepted
; (kv_stage_payload_valid, stage_payload_ready_o and stage_payload_legal).
(define kv-record-starts-at (j envs outs) :verify-guards nil
  (and (rec-start-p j outs)
       (equal (pay-st-at (+ -1 j) outs) 1)
       (equal (rec-beat-at (+ -1 j) envs outs) 1)
       (equal (rec-coord-at (+ -1 j) outs) 127)))
; The start of the record that a cycle n belongs to: the latest cycle up to
; n in which state_q = 9, write_head_q = 0 and write_word_q = 0.
(define kv-record-start (n outs) :verify-guards nil
  (rec-start n outs))
; In cycle k the controller is in a write state (state_q is 2, 3, 9, 10, 11
; or 12) and write_aborted_q is 0.
(define kv-record-being-written-at (k outs) :verify-guards nil
  (rec-live-p k outs))
; From cycle j to cycle n the record is being written in every cycle, and
; clear_i is 0 in every cycle.
(define kv-record-uninterrupted (j n envs outs) :verify-guards nil
  (and (rec-uninterrupted j n envs outs)
       (equal (rec-clear-at n envs) 0)))
; THE SNAPSHOT: the eighteen words, each (address data), of the record as the
; controller holds it in cycle j, computed from pending_layer_q,
; pending_position_q, pending_key_exponents_q, pending_value_exponents_q and
; the pair store g_pair_bank[0..7].words of that one cycle: words 0 to 7 of
; the K row, the K metadata word, words 0 to 7 of the V row, the V metadata
; word.
(define kv-record-words (j outs) :verify-guards nil
  (rec-words-at j outs))
; How many of the eighteen have been accepted, read off the controller in
; cycle k: nine if write_head_q is 1, plus write_word_q, plus one if the
; word waited on has left the boundary for the endpoint.
(define kv-record-progress-at (k outs) :verify-guards nil
  (rec-progress-at k outs))

; Take any execution of the probe module's state machine, from any initial
; state, with the reset, storage and environment hypotheses of the payload
; book holding through cycle n.  Suppose pending_persisted_q rises at cycle
; n.  Let j be the latest cycle up to n at which a record starts.  Then
;   - j is after the reset and j is a record's start, entered from staging by
;     the acceptance of the beat for coordinate 127;
;   - from j to n the controller is writing, never interrupted, and there is
;     no CLEAR in any of those cycles;
;   - the writes the typed DDR boundary's endpoint (private_kv_req_*)
;     accepted in cycles j to n, in order, are exactly the eighteen words of
;     the record as the controller held it in cycle j.
; How long the endpoint makes each word wait is not constrained, and neither
; is clear_i.
(defthm kv-write-record
  (b* ((outs @@O@@)
       (j (kv-record-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs))
             (and (natp j) (< (+ 2 r) j) (<= j n)
                  (kv-record-starts-at j envs outs)
                  (kv-record-uninterrupted j n envs outs)
                  (equal (kv-endpoint-writes j (+ 1 n) envs outs)
                         (kv-record-words j outs)))))
  :hints (("Goal"
           :use ((:instance rec-record-written)
                 (:instance rec-start-facts (j @@J@@) (n (+ 1 n)))
                 (:instance kvj-reset-connects (outs @@O@@))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n)) (outs @@O@@)))
           :in-theory (e/d (kv-record-reported-complete-at kv-record-start kv-record-starts-at
                            kv-record-uninterrupted kv-record-words kv-endpoint-writes
                            kv-payload-storage-definite-at)
                           (kvj-reset-connects kvj-environment-from-connects
                            rec-start rec-start-p rec-uninterrupted rec-complete-at rec-words-at
                            rec-clear-at rec-beat-at rec-coord-at pay-log
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; WHILE A RECORD IS BEING WRITTEN, completed or not.  If in cycle n the
; controller is writing and not interrupted, then a record started at the
; latest start j, the record it holds in cycle n is the one it held in cycle
; j, and the writes the endpoint accepted in cycles j to n-1 are exactly the
; first kv-record-progress-at of that record's eighteen words.  So when
; CLEAR arrives the accepted writes of the record are a prefix of it, of the
; length the controller's own registers give.
(defthm kv-write-record-prefix
  (b* ((outs @@O@@)
       (j (kv-record-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) n envs outs)
                  (kv-record-being-written-at n outs))
             (and (natp j) (< (+ 2 r) j) (<= j n)
                  (kv-record-starts-at j envs outs)
                  (equal (kv-record-words n outs) (kv-record-words j outs))
                  (equal (kv-endpoint-writes j n envs outs)
                         (take (kv-record-progress-at n outs)
                               (kv-record-words j outs))))))
  :hints (("Goal"
           :use ((:instance rec-inv-holds)
                 (:instance rec-start-facts (j @@J@@))
                 (:instance kvj-reset-connects (outs @@O@@))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (outs @@O@@)))
           :in-theory (e/d (kv-record-being-written-at kv-record-start kv-record-starts-at
                            kv-record-words kv-record-progress-at kv-endpoint-writes
                            kv-payload-storage-definite-at rec-inv)
                           (kvj-reset-connects kvj-environment-from-connects
                            rec-start rec-start-p rec-uninterrupted rec-live-p rec-words-at
                            rec-progress-at rec-clear-at rec-beat-at rec-coord-at pay-log
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)

; AN INTERRUPTED RECORD IS NOT THE ONE REPORTED COMPLETE.  Suppose
; pending_persisted_q rises at cycle n, and m is a cycle up to n in which
; clear_i is 1, or in which the controller is not writing or its write is
; marked interrupted (write_aborted_q).  Then m is before the start of the
; record completed at n.  So a record that CLEAR touched is never the one
; credited with a completion, and a write the endpoint accepts for a
; cancelled record, which it can only accept while write_aborted_q is 1,
; is not in the list of any completed record.
(defthm kv-write-record-not-credited-when-interrupted
  (b* ((outs @@O@@)
       (j (kv-record-start n outs)))
    (implies (and (natp r) (natp n) (<= (+ 2 r) n) (natp m) (<= m n)
                  (kv-reset-held-at r envs outs)
                  (kv-payload-storage-definite-at (+ 2 r) envs outs)
                  (kv-environment-ok-from (+ 2 r) (+ 1 n) envs outs)
                  (kv-record-reported-complete-at n outs)
                  (or (equal (kv-clear-at m envs) 1)
                      (not (kv-record-being-written-at m outs))))
             (< m j)))
  :hints (("Goal"
           :use ((:instance rec-record-written)
                 (:instance rec-uninterrupted-at
                  (j @@J@@) (outs @@O@@))
                 (:instance kvj-reset-connects (outs @@O@@))
                 (:instance kvj-environment-from-connects
                  (j (+ 2 r)) (n (+ 1 n)) (outs @@O@@)))
           :in-theory (e/d (kv-record-reported-complete-at kv-record-start kv-clear-at
                            kv-record-being-written-at kv-payload-storage-definite-at)
                           (kvj-reset-connects kvj-environment-from-connects
                            rec-start rec-start-p rec-uninterrupted rec-live-p rec-complete-at
                            rec-words-at rec-clear-at pay-log
                            join-env-from join-reset-at pay-definite-at
                            fsm-eval (probe-fsm) probe-fsm))))
  :rule-classes nil)
""".replace("@@O@@", O).replace("@@J@@", J)


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    parts = {"1": text, "2": text2, "3": text3}
    sys.stdout.write("".join(parts[c]() for c in ("123" if which == "all" else which)))

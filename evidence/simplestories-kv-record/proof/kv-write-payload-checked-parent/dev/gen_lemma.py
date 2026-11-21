#!/usr/bin/env python3
"""Development aid: write the payload predicates and the symbolic step lemma
as ACL2 input for the saved image (proto_run.py).

    python3 -I gen_lemma.py OUT.lsp [--refine]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import proto_run  # noqa: E402
import payload_lib as L  # noqa: E402

BANKS = ["b%d" % i for i in range(8)]
CELLS = ["m%d" % i for i in range(8)]

PREDICATES = r"""
; ---------------------------------------------------------------------------
; The staged record as the controller holds it, and where a word of it goes.
; A whole array is one number here; RTL element e of an array of n elements
; of width k is bits [(n-1-e)*k +: k] of it (checked by a concrete run).
; ---------------------------------------------------------------------------
(define pay-word32 (bank a) :verify-guards nil
  (loghead 32 (logtail (* 32 (- 31 a)) bank)))

; Slot a of the pair store: the eight banks' words at address a, bank 0 lowest.
(define pay-slot (a b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (logapp 32 (pay-word32 b0 a) (logapp 32 (pay-word32 b1 a)
  (logapp 32 (pay-word32 b2 a) (logapp 32 (pay-word32 b3 a)
  (logapp 32 (pay-word32 b4 a) (logapp 32 (pay-word32 b5 a)
  (logapp 32 (pay-word32 b6 a) (pay-word32 b7 a)))))))))

; The eight keys (h = 0) or the eight values (h = 1) of a slot: a pair is
; {value, key}, sixteen bits each.
(define pay-half (slot h) :verify-guards nil
  (if (equal h 1)
      (logapp 16 (logtail 16 slot) (logapp 16 (logtail 48 slot)
      (logapp 16 (logtail 80 slot) (logapp 16 (logtail 112 slot)
      (logapp 16 (logtail 144 slot) (logapp 16 (logtail 176 slot)
      (logapp 16 (logtail 208 slot) (loghead 16 (logtail 240 slot)))))))))
    (logapp 16 slot (logapp 16 (logtail 32 slot)
    (logapp 16 (logtail 64 slot) (logapp 16 (logtail 96 slot)
    (logapp 16 (logtail 128 slot) (logapp 16 (logtail 160 slot)
    (logapp 16 (logtail 192 slot) (loghead 16 (logtail 224 slot)))))))))))

; The first and second slot of row word w (w < 8): slots 8+2w and 9+2w.
(define pay-slot-a (w b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (cond ((equal w 0) (pay-slot 8 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 1) (pay-slot 10 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 2) (pay-slot 12 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 3) (pay-slot 14 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 4) (pay-slot 16 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 5) (pay-slot 18 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 6) (pay-slot 20 b0 b1 b2 b3 b4 b5 b6 b7))
        (t (pay-slot 22 b0 b1 b2 b3 b4 b5 b6 b7))))
(define pay-slot-b (w b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (cond ((equal w 0) (pay-slot 9 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 1) (pay-slot 11 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 2) (pay-slot 13 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 3) (pay-slot 15 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 4) (pay-slot 17 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 5) (pay-slot 19 b0 b1 b2 b3 b4 b5 b6 b7))
        ((equal w 6) (pay-slot 21 b0 b1 b2 b3 b4 b5 b6 b7))
        (t (pay-slot 23 b0 b1 b2 b3 b4 b5 b6 b7))))

; Word w of row h of the staged record: sixteen coordinates for w < 8, the
; row's two exponent bytes under 240 zero bits for w = 8.
(define pay-data (w h ke ve b0 b1 b2 b3 b4 b5 b6 b7) :verify-guards nil
  (if (equal w 8)
      (loghead 16 (if (equal h 1) ve ke))
    (logapp 128
            (pay-half (pay-slot-a w b0 b1 b2 b3 b4 b5 b6 b7) h)
            (pay-half (pay-slot-b w b0 b1 b2 b3 b4 b5 b6 b7) h))))

; Its address: 227072 + 9 * row + w, row = 2 * (2048 * layer + position) + h.
(define pay-addr (l p h w) :verify-guards nil
  (b* ((row (+ (ash (+ (ash l 11) (loghead 11 p)) 1) h)))
    (loghead 19 (+ 227072 (ash row 3) row w))))

; Element e of the app side's arrays, and the request FIFO's cell.
(define pay-el256 (e x) :verify-guards nil
  (cond ((equal e 0) (loghead 256 (logtail 1792 x)))
        ((equal e 1) (loghead 256 (logtail 1536 x)))
        ((equal e 2) (loghead 256 (logtail 1280 x)))
        ((equal e 3) (loghead 256 (logtail 1024 x)))
        ((equal e 4) (loghead 256 (logtail 768 x)))
        ((equal e 5) (loghead 256 (logtail 512 x)))
        ((equal e 6) (loghead 256 (logtail 256 x)))
        (t (loghead 256 x))))
(define pay-el19 (e x) :verify-guards nil
  (cond ((equal e 0) (loghead 19 (logtail 133 x)))
        ((equal e 1) (loghead 19 (logtail 114 x)))
        ((equal e 2) (loghead 19 (logtail 95 x)))
        ((equal e 3) (loghead 19 (logtail 76 x)))
        ((equal e 4) (loghead 19 (logtail 57 x)))
        ((equal e 5) (loghead 19 (logtail 38 x)))
        ((equal e 6) (loghead 19 (logtail 19 x)))
        (t (loghead 19 x))))
(define pay-cell (i m0 m1 m2 m3 m4 m5 m6 m7) :verify-guards nil
  (cond ((equal i 0) m0) ((equal i 1) m1) ((equal i 2) m2) ((equal i 3) m3)
        ((equal i 4) m4) ((equal i 5) m5) ((equal i 6) m6) (t m7)))

; An entry of the request FIFO that carries the word the controller waits on:
; desc is its descriptor (head, position, layer, model word), word its row
; word, x its address and data.  The entry is consistent in itself, whether
; or not CLEAR has interrupted the write: it is word w, its data is the
; offer, and its address is the one its own descriptor specifies.  Unless
; CLEAR has interrupted the write, the descriptor is the controller's.
(define pay-entry-p (desc word x offer w l p h ab) :verify-guards nil
  (b* ((eh (loghead 2 desc))
       (ep (loghead 12 (logtail 2 desc)))
       (el (loghead 3 (logtail 14 desc))))
    (and (equal (logtail 17 desc) 0)
         (< el 6) (< ep 2048) (< eh 2)
         (equal word w)
         (equal (loghead 256 x) offer)
         (equal (logtail 256 x) (pay-addr el ep eh w))
         (or (not (equal ab 0))
             (and (equal el l) (equal ep p) (equal eh h))))))

; The address the waited-on word carries, wherever it is: in the request
; FIFO, or in the app side's slot.
(define pay-carried-addr (wb rb cell head saddr) :verify-guards nil
  (if (equal wb rb) (pay-el19 head saddr) (logtail 256 cell)))

; A carried request is the word the controller offered, and, unless CLEAR has
; interrupted the write, sits at the word's address.
(define pay-carried-p (data19-256 offer addr ab) :verify-guards nil
  (and (equal (loghead 256 data19-256) offer)
       (or (not (equal ab 0))
           (equal (loghead 19 (logtail 256 data19-256)) addr))))

; THE PAYLOAD INVARIANT.
(define pay-inv-p (st w h ab per l p ke ve offer rd0 rd1 rd2 rd3 rd4 rd5 rd6 rd7
                   b0 b1 b2 b3 b4 b5 b6 b7
                   wb rb mv m0 m1 m2 m3 m4 m5 m6 m7 md
                   d0 d1 d2 d3 d4 d5 d6 d7 mdd mw0 mw1 mw2 mw3 mw4 mw5 mw6 mw7 mdw
                   res head offq saddr sdata oaddr odata)
  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t :normalize nil
  (b* (@@UPPER@@
       (rd (logapp 32 rd0 (logapp 32 rd1 (logapp 32 rd2 (logapp 32 rd3
           (logapp 32 rd4 (logapp 32 rd5 (logapp 32 rd6 (loghead 32 rd7)))))))))
       (addr (pay-addr l p h w))
       (data (pay-data w h ke ve b0 b1 b2 b3 b4 b5 b6 b7))
       (cell (pay-cell (loghead 3 rb) m0 m1 m2 m3 m4 m5 m6 m7))
       (dcell (pay-cell (loghead 3 rb) d0 d1 d2 d3 d4 d5 d6 d7))
       (wcell (pay-cell (loghead 3 rb) mw0 mw1 mw2 mw3 mw4 mw5 mw6 mw7)))
    (and
     ; nothing is reported complete while a record is staged or written
     (or (not (or (equal st 0) (equal st 1) (equal st 2) (equal st 3) (equal st 9)
                  (equal st 10) (equal st 11) (equal st 12)))
         (equal per 0))
     ; the word counter in each write state
     (or (not (or (equal st 9) (equal st 10) (equal st 11))) (<= w 7))
     (or (not (equal st 12)) (equal w 8))
     (or (not (or (equal st 2) (equal st 3))) (<= w 8))
     ; prefetch B: the store's read register holds the word's first slot
     (or (not (equal st 10))
         (equal rd (pay-slot-a w b0 b1 b2 b3 b4 b5 b6 b7)))
     ; pack: the offer's low half is packed, the read register holds the second slot
     (or (not (equal st 11))
         (and (equal (loghead 128 offer)
                     (pay-half (pay-slot-a w b0 b1 b2 b3 b4 b5 b6 b7) h))
              (equal rd (pay-slot-b w b0 b1 b2 b3 b4 b5 b6 b7))))
     ; request and wait: the offer is the staged word
     (or (not (or (equal st 2) (equal st 3))) (equal offer data))
     ; wait: wherever the request is, it carries the offer
     (or (not (equal st 3))
         (and ; in the request FIFO
              (or (equal wb rb) (pay-entry-p dcell wcell cell offer w l p h ab))
              ; the FIFO's output register is a copy of the entry
              (or (not (equal mv 1))
                  (and (not (equal wb rb)) (equal md cell) (equal mdd dcell) (equal mdw wcell)))
              ; in the app side's slot
              (or (equal res 0)
                  (pay-carried-p (logapp 256 (pay-el256 head sdata) (pay-el19 head saddr))
                                 offer addr ab))
              ; the endpoint offer is a copy of the slot
              (or (not (equal offq 1))
                  (and (not (equal res 0))
                       (equal oaddr (pay-el19 head saddr))
                       (equal odata (pay-el256 head sdata)))))))))

; ---------------------------------------------------------------------------
; What one cycle does: staging, progress, completion, CLEAR.
; ---------------------------------------------------------------------------
(define pay-u (x) :verify-guards nil (4vec->upper x))

; The controller is writing a row: prefetch A/B, pack, metadata, request, wait.
(define pay-writing-p (st) :verify-guards nil
  (or (equal st 2) (equal st 3) (equal st 9) (equal st 10) (equal st 11) (equal st 12)))

; 1 when the word the controller is waiting on has already been accepted at
; the endpoint: it is no longer in the request FIFO, in an unissued slot or
; on offer.
(define pay-accepted (st wb rb uni offq) :verify-guards nil
  (if (and (equal st 3) (equal wb rb) (equal uni 0) (equal offq 0)) 1 0))

; Row h has just been finished: the controller moves on to row 1, or, after
; row 1, to PENDING.
(define pay-row-done-p (h nst nh nw) :verify-guards nil
  (if (equal h 0)
      (and (equal nst 9) (equal nh 1) (equal nw 0))
    (equal nst 4)))

; The sixteen staged slots of one bank (addresses 8..23), and a pair written
; at address 8+i.
(define pay-staged (bank) :verify-guards nil (loghead 512 (logtail 256 bank)))
(define pay-staged-put (i pair field) :verify-guards nil
  (cond
        ((equal i 0) (logapp 480 field (logapp 32 pair (logtail 512 field))))
        ((equal i 1) (logapp 448 field (logapp 32 pair (logtail 480 field))))
        ((equal i 2) (logapp 416 field (logapp 32 pair (logtail 448 field))))
        ((equal i 3) (logapp 384 field (logapp 32 pair (logtail 416 field))))
        ((equal i 4) (logapp 352 field (logapp 32 pair (logtail 384 field))))
        ((equal i 5) (logapp 320 field (logapp 32 pair (logtail 352 field))))
        ((equal i 6) (logapp 288 field (logapp 32 pair (logtail 320 field))))
        ((equal i 7) (logapp 256 field (logapp 32 pair (logtail 288 field))))
        ((equal i 8) (logapp 224 field (logapp 32 pair (logtail 256 field))))
        ((equal i 9) (logapp 192 field (logapp 32 pair (logtail 224 field))))
        ((equal i 10) (logapp 160 field (logapp 32 pair (logtail 192 field))))
        ((equal i 11) (logapp 128 field (logapp 32 pair (logtail 160 field))))
        ((equal i 12) (logapp 96 field (logapp 32 pair (logtail 128 field))))
        ((equal i 13) (logapp 64 field (logapp 32 pair (logtail 96 field))))
        ((equal i 14) (logapp 32 field (logapp 32 pair (logtail 64 field))))
        (t (logapp 32 pair (logtail 32 field)))))

(define pay-is (x v) :verify-guards nil
  (and (equal (4vec->upper x) v) (equal (4vec->lower x) v)))

(in-theory (disable pay-word32 pay-slot pay-half pay-slot-a pay-slot-b pay-data
                    pay-addr pay-el256 pay-el19 pay-cell pay-carried-p pay-inv-p pay-is
                    pay-entry-p pay-carried-addr
                    pay-u pay-writing-p pay-accepted pay-row-done-p pay-staged pay-staged-put))
"""

INV_FORMALS = ("st w h ab per l p ke ve offer rd0 rd1 rd2 rd3 rd4 rd5 rd6 rd7 b0 b1 b2 b3 b4 b5 b6 b7 "
               "wb rb mv m0 m1 m2 m3 m4 m5 m6 m7 md d0 d1 d2 d3 d4 d5 d6 d7 mdd mw0 mw1 mw2 mw3 mw4 mw5 mw6 mw7 mdw "
               "res head offq saddr sdata oaddr odata").split()
# formal -> signal id
INV_ARGS = dict(st="k-state-q", w="k-write-word-q", h="k-write-head-q", ab="k-write-aborted-q",
                per="k-pending-persisted-q",
                l="k-pending-layer-q", p="k-pending-position-q",
                ke="k-pending-key-exponents-q", ve="k-pending-value-exponents-q",
                offer="k-offer", wb="q-wb", rb="q-rb", mv="q-mv", md="q-mdp",
                res="a-reserved", head="a-head", offq="a-offer", saddr="a-saddr",
                sdata="a-sdata", oaddr="a-oaddr", odata="a-odata")
INV_ARGS.update({"b%d" % i: "k-bank%d" % i for i in range(8)})
INV_ARGS.update({"rd%d" % i: "k-rd%d" % i for i in range(8)})
INV_ARGS.update({"m%d" % i: "q-memp%d" % i for i in range(8)})
INV_ARGS.update({"d%d" % i: "q-memd%d" % i for i in range(8)})
INV_ARGS.update({"mw%d" % i: "q-memw%d" % i for i in range(8)})
INV_ARGS.update(mdd="q-mdd", mdw="q-mdw")


def predicates():
    upper = "\n       ".join("(%s (4vec->upper %s))" % (f, f) for f in INV_FORMALS)
    return PREDICATES.replace("@@UPPER@@", upper)


def inv(prefix):
    return "(pay-inv-p %s)" % " ".join("%s-%s" % (prefix, INV_ARGS[f]) for f in INV_FORMALS)


def old_form():
    lemmas = open(os.path.join(proto_run.BOOK, "kv-joined-lemmas.lisp")).read()
    i = lemmas.index("'(def-svtv-generalized-thm join-step-svtv-thm")
    return lemmas[i + 1:proto_run.match_paren(lemmas, i + 1)]


def old_list(key):
    form = old_form()
    i = form.index(key + " (") + len(key) + 1
    return form[i + 1:proto_run.match_paren(form, i) - 1].split()


FACT_VARS = dict(
    st="r-k-state-q", w="r-k-write-word-q", h="r-k-write-head-q", ab="r-k-write-aborted-q",
    per="r-k-pending-persisted-q",
    acc="(pay-accepted r-k-state-q r-q-wb r-q-rb r-a-unissued r-a-offer)",
    nst="(pay-u n-k-state-q)", nw="(pay-u n-k-write-word-q)", nh="(pay-u n-k-write-head-q)",
    nab="(pay-u n-k-write-aborted-q)", nper="(pay-u n-k-pending-persisted-q)",
    nacc="(pay-accepted (pay-u n-k-state-q) (pay-u n-q-wb) (pay-u n-q-rb) (pay-u n-a-unissued) (pay-u n-a-offer))",
    ep="(if (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)) 1 0)",
    beat="(if (and (equal h-spayload 1) (equal o-spr 1) (equal o-spl 1)) 1 0)",
    pair="(logapp 16 h-key h-value)", coord="r-k-expected-coordinate-q", clear="i-clear")


def facts():
    v = FACT_VARS
    out = [("a staging beat is accepted only while staging",
            "(or (not (equal %(beat)s 1)) (equal %(st)s 1))" % v)]
    for b in range(8):
        out.append(("bank %d: the staged slots change only by an accepted beat" % b,
                    """(equal (pay-staged (pay-u n-k-bank%d))
                      (if (and (equal %s 1) (equal (loghead 3 %s) %d))
                          (pay-staged-put (logtail 3 %s) %s (pay-staged r-k-bank%d))
                        (pay-staged r-k-bank%d)))""" % (b, v["beat"], v["coord"], b, v["coord"], v["pair"], b, b)))
    out.append(("progress counts the endpoint's acceptances while a row is written",
                """(or (not (and (pay-writing-p %(st)s) (pay-writing-p %(nst)s) (equal %(nh)s %(h)s)
                              (equal %(ab)s 0) (equal %(nab)s 0)))
                    (and (equal (+ %(nw)s %(nacc)s) (+ %(w)s %(acc)s %(ep)s))
                         (equal (pay-u n-k-pending-layer-q) r-k-pending-layer-q)
                         (equal (pay-u n-k-pending-position-q) r-k-pending-position-q)
                         (equal (pay-u n-k-pending-key-exponents-q) r-k-pending-key-exponents-q)
                         (equal (pay-u n-k-pending-value-exponents-q) r-k-pending-value-exponents-q)))""" % v))
    out.append(("a row is finished only by the completion of its word 8, after the endpoint accepted it",
                """(or (not (and (pay-writing-p %(st)s) (equal %(ab)s 0)
                              (pay-row-done-p %(h)s %(nst)s %(nh)s %(nw)s)))
                    (and (equal %(st)s 3) (equal %(w)s 8) (equal %(acc)s 1) (equal %(ep)s 0)))""" % v))
    out.append(("an acceptance at the endpoint is of the word waited on, once",
                """(or (not (equal %(ep)s 1))
                    (and (equal %(st)s 3) (equal %(acc)s 0)
                         (or (not (equal %(nst)s 3)) (equal %(nacc)s 1))))""" % v))
    out.append(("the record is reported complete only at the unfaulted, uninterrupted completion of its last word",
                """(or (not (and (equal %(per)s 0) (equal %(nper)s 1)))
                    (and (equal %(st)s 3) (equal %(h)s 1) (equal %(w)s 8) (equal %(ab)s 0)
                         (equal %(clear)s 0) (equal %(acc)s 1)))""" % v))
    out.append(("CLEAR while a row is written ends the write or marks it interrupted",
                """(or (not (and (equal %(clear)s 1) (pay-writing-p %(st)s)))
                    (and (equal %(nper)s 0)
                         (or (equal %(nst)s 0)
                             (and (equal %(st)s 3) (equal %(nst)s 3) (equal %(nab)s 1)))))""" % v))
    out.append(("an interrupted wait stays interrupted and is never reported complete",
                """(or (not (and (equal %(st)s 3) (equal %(ab)s 1)))
                    (and (or (equal %(nst)s 0) (and (equal %(nst)s 3) (equal %(nab)s 1)))
                         (or (equal %(nper)s 0) (equal %(nper)s %(per)s))))""" % v))
    cells = " ".join("r-q-memp%d" % i for i in range(8))
    ncells = " ".join("(pay-u n-q-memp%d)" % i for i in range(8))
    v2 = dict(v)
    v2["car"] = "(pay-carried-addr r-q-wb r-q-rb (pay-cell (loghead 3 r-q-rb) %s) r-a-head r-a-saddr)" % cells
    v2["ncar"] = ("(pay-carried-addr (pay-u n-q-wb) (pay-u n-q-rb) (pay-cell (loghead 3 (pay-u n-q-rb)) %s) "
                  "(pay-u n-a-head) (pay-u n-a-saddr))" % ncells)
    out.append(("the app side judges the descriptor of a presented write legal",
                "(or (not (and (equal %(st)s 3) (equal r-q-mv 1))) (equal o-wlegal 1))" % v2))
    out.append(("the address a waited-on word carries does not change, and is the address the endpoint accepts",
                """(or (not (and (equal %(st)s 3) (equal %(acc)s 0)))
                    (and (or (not (equal %(ep)s 1)) (pay-is o-epaddr %(car)s))
                         (or (not (and (equal %(nst)s 3) (equal %(nacc)s 0)))
                             (equal %(ncar)s %(car)s))))""" % v2))
    return out


VAR = re.compile(r"(?<![a-z0-9-])((?:r|n|o|h|i)-[a-z0-9-]+)")


def conclusions(parts):
    """The conclusion's conjuncts as (predicate name, comment, body, formals)."""
    data = "(pay-data r-k-write-word-q r-k-write-head-q r-k-pending-key-exponents-q r-k-pending-value-exponents-q %s)" \
        % " ".join("r-k-bank%d" % i for i in range(8))
    addr = "(pay-addr r-k-pending-layer-q r-k-pending-position-q r-k-write-head-q r-k-write-word-q)"
    out = []
    if "2v" in parts:
        out += [("pay-next-definite-%s" % p, "the next value of %s is definite" % p,
                 "(unsigned-byte-p %d n-%s)" % (L.PAYLOAD_WIDTH[p], p)) for p in L.PAYLOAD]
    if "inv" in parts:
        out.append(("pay-next-inv", "the payload invariant holds of the next state", inv("n")))
    if "typed" in parts:
        out.append(("pay-typed-accept-p", "a write accepted at the controller's typed port",
                    """(or (not (and (equal o-wreqv 1) (equal o-wreqr 1)))
      (and (equal r-k-state-q 2)
           (pay-is o-wreqdata %s)
           (pay-is o-wreqaddr %s)))""" % (data, addr)))
    if "endpoint" in parts:
        out.append(("pay-endpoint-accept-p", "a write accepted at the boundary's endpoint",
                    """(or (not (and (equal o-epv 1) (equal h-epready 1) (equal o-epw 1)))
      (and (equal r-k-state-q 3)
           (pay-is o-epdata %s)
           (or (not (equal r-k-write-aborted-q 0))
               (pay-is o-epaddr %s))))""" % (data, addr)))
    if "facts" in parts:
        out += [("pay-fact-%s" % n, c, body) for n, (c, body) in zip(FACT_NAMES, facts())]
    res = []
    for name, comment, body in out:
        formals = sorted(set(VAR.findall(body)))
        res.append((name, comment, body, formals))
    return res


FACT_NAMES = (["stage-only-while-staging"] + ["bank%d-staged" % b for b in range(8)]
              + ["progress", "row-finished", "accepted-once", "reported-complete", "clear", "interrupted",
                 "write-legal", "carried-address"])


def lemma(name="pay-step-svtv-thm", parts=("2v", "inv", "typed", "endpoint", "facts")):
    concs = conclusions(parts)
    ante = "(and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))"
    used = set(re.findall(r"[a-z0-9-]+", ante + " ".join(b for _, _, b, _ in concs)))
    next_ctrl = ["n-" + s for s in L.STATES]
    outs = [o for o in ["o-pfn", "o-tpf", "o-epf"] + L.OBS + next_ctrl + ["n-" + p for p in L.PAYLOAD] if o in used]
    # Each predicate hands its body to the SAT solver when the symbolic
    # interpreter reaches it (fgl-prove returns its argument as a Boolean),
    # so the conjuncts are solved one at a time.
    prove = '(fgl::fgl-prove (fgl::make-fgl-satlink-monolithic-sat-config) "%s"\n  %s)'
    # Every signal the conclusion reads holds a definite value (an integer),
    # whatever the antecedent.  The library needs this of each output to carry
    # the lemma from this one symbolic run to every execution.
    defs = "".join("(define pay-int-%s (x) :verify-guards nil\n  %s)\n"
                   "(defthm pay-int-%s-integerp\n  (implies (pay-int-%s x) (integerp x))\n"
                   "  :hints ((\"Goal\" :in-theory (enable pay-int-%s fgl::fgl-prove-fn)))\n"
                   "  :rule-classes :forward-chaining)\n"
                   % (o, prove % ("pay-int-" + o, "(integerp x)"), o, o, o) for o in outs)
    defs += "(in-theory (disable %s))\n\n" % " ".join("pay-int-" + o for o in outs)
    defs += "".join("; %s\n(define %s (%s)\n  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t\n  %s)\n"
                    % (c, n, " ".join(f), prove % (n, b)) for n, c, b, f in concs)
    defs += "(in-theory (disable %s))\n" % " ".join(n for n, _, _, _ in concs)
    calls = ["(%s %s)" % (n, " ".join(f)) for n, _, _, f in concs]
    # The whole conclusion is one predicate, so that the library carries it
    # from the symbolic run to every execution in one step.  Inside it, `if`
    # and not `implies`: the interpreter then solves each conjunct under the
    # antecedent.
    cformals = sorted(set(VAR.findall(ante + " ".join(calls))))
    defs += ("\n; THE CONCLUSION of the step lemma: with no protocol violation by the\n"
             "; client and no malformed metadata word from the endpoint in the cycle,\n"
             "; every conjunct above.\n"
             "(define pay-step-concl (%s)\n  :verify-guards nil :ignore-ok t :irrelevant-formals-ok t\n"
             "  (if %s\n      (and %s)\n    t))\n(in-theory (disable pay-step-concl))\n"
             % (" ".join(cformals), ante, "\n           ".join(calls)))
    concl = "(and %s\n       (pay-step-concl %s))" % (
        "\n       ".join("(pay-int-%s %s)" % (o, o) for o in outs), " ".join(cformals))
    overrides = old_list(":override-vars") + ["r-" + p for p in L.PAYLOAD]
    return defs + """(def-svtv-generalized-thm %s
  :svtv payload-step-run
  :svtv-spec payload-step-spec
  :input-vars :all
  :output-vars (%s)
  :unsigned-byte-hyps t
  :no-integerp t
  :enable (%s)
  :override-vars (%s)
  :spec-override-vars ()
  :hyp (and %s
            %s)
  :concl %s)
""" % (name, " ".join(outs), " ".join("pay-int-%s-integerp" % o for o in outs), " ".join(overrides),
       proto_run.old_step_hyp(), inv("r"), concl)


def lemma_shape(parts=("2v", "inv", "typed", "endpoint", "facts")):
    """The pieces of the step lemma's statement that the books built on it
    need: its output variables, its override variables, its hypothesis, the
    calls of its integer predicates and the formals of its conclusion."""
    concs = conclusions(parts)
    ante = "(and (equal o-pfn 0) (equal o-tpf 0) (equal o-epf 0))"
    used = set(re.findall(r"[a-z0-9-]+", ante + " ".join(b for _, _, b, _ in concs)))
    next_ctrl = ["n-" + s for s in L.STATES]
    outs = [o for o in ["o-pfn", "o-tpf", "o-epf"] + L.OBS + next_ctrl + ["n-" + p for p in L.PAYLOAD] if o in used]
    calls = ["(%s %s)" % (n, " ".join(f)) for n, _, _, f in concs]
    cformals = sorted(set(VAR.findall(ante + " ".join(calls))))
    return dict(outs=outs,
                overrides=old_list(":override-vars") + ["r-" + p for p in L.PAYLOAD],
                hyp="(and %s\n            %s)" % (proto_run.old_step_hyp(), inv("r")),
                int_calls=["(pay-int-%s %s)" % (o, o) for o in outs],
                concl_call="(pay-step-concl %s)" % " ".join(cformals))


REFINE = """(def-svtv-data-export payload-step-run-data)
(def-svtv-refinement payload-step-run payload-step-run-data
  :svtv-spec payload-step-spec :inclusive-overridekeys t
  :fsm probe-fsm)
(acl2::cw "~%PAY-REFINEMENT done~%")
"""

if __name__ == "__main__":
    out = sys.argv[1]
    parts = ("2v", "inv", "typed", "endpoint", "facts")
    if "--parts" in sys.argv:
        parts = tuple(sys.argv[sys.argv.index("--parts") + 1].split(","))
    with open(out, "w") as f:
        f.write('(in-package "SV")\n(value-triple (acl2::tshell-start))\n')
        if "--kissat" in sys.argv:
            f.write('(defun pay-dev-config ()\n  (declare (xargs :guard t))\n'
                    '  (satlink::make-config :cmdline "sh %s/kissat-dev.sh" :verbose nil :mintime 0 :remove-temps t))\n'
                    "(defattach fgl::fgl-satlink-config pay-dev-config)\n" % HERE)
        f.write(predicates())
        f.write(lemma(parts=parts))
        f.write('(acl2::cw "~%PAY-LEMMA-DONE~%")\n')

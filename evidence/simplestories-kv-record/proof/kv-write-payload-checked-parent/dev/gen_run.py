#!/usr/bin/env python3
"""Development aid: a concrete run of the payload step run, cycle after
cycle from the reset state, in which a scripted client stages one record
and the endpoint accepts its eighteen writes with stalls.

    python3 -I gen_run.py OUT.lsp

The expected writes are computed here, from the staged values and the
address formula, independently of the RTL.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import payload_lib as L  # noqa: E402

LAYER, POSITION, KEXP, VEXP = 2, 0, 5, 250


def key(c):
    return 0x0100 + 3 * c


def value(c):
    return 0x4000 + 5 * c


def expected():
    """The eighteen writes of the record: (address, data)."""
    out = []
    for h in (0, 1):
        row = 2 * (2048 * LAYER + POSITION) + h
        for w in range(9):
            if w < 8:
                data = sum(((value(16 * w + j) if h else key(16 * w + j)) & 0xFFFF) << (16 * j) for j in range(16))
            else:
                e = VEXP if h else KEXP
                data = (e << 8) | e
            out.append((227072 + 9 * row + w, data))
    return out


RUN = r"""
(in-package "SV")
(defconst *pay-state-ids* '(@@STATE@@))
(defconst *pay-hyp-ids* '(@@HYPS@@))
(defun pay-sym (prefix id)
  (declare (xargs :mode :program))
  (intern-in-package-of-symbol
   (concatenate 'string prefix (symbol-name id)) 'pay-sym))
(defun pay-get (k al)
  (declare (xargs :mode :program))
  (cdr (assoc-eq k al)))
; the run's inputs for one cycle: every register overridden with its value,
; every environment signal with the script's; the app side's verdict on a
; request's descriptor (h-legal) is left to the RTL
(defun pay-state-env (ids st)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (list* (cons (pay-sym "R-" (car ids)) (pay-get (car ids) st))
           (cons (pay-sym "C-" (car ids)) -1)
           (pay-state-env (cdr ids) st))))
(defun pay-hyp-env (ids hy)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (list* (cons (car ids) (nfix (pay-get (car ids) hy)))
           (cons (pay-sym "C-" (car ids)) (if (eq (car ids) 'h-legal) 0 -1))
           (pay-hyp-env (cdr ids) hy))))
(defun pay-next-state (ids out)
  (declare (xargs :mode :program))
  (if (atom ids) nil
    (cons (cons (car ids) (pay-get (pay-sym "N-" (car ids)) out))
          (pay-next-state (cdr ids) out))))
(defun pay-all-natp (al)
  (declare (xargs :mode :program))
  (or (atom al) (and (natp (cdar al)) (pay-all-natp (cdr al)))))
(defun pay-zero-state (ids)
  (declare (xargs :mode :program))
  (if (atom ids) nil (cons (cons (car ids) 0) (pay-zero-state (cdr ids)))))

; THE SCRIPT.  The client stages one record: layer @@LAYER@@, position
; @@POSITION@@, exponent bytes @@KEXP@@ and @@VEXP@@; coordinate c has key
; #x100 + 3c and value #x4000 + 5c.  It offers a beat on three cycles in
; four.  The endpoint is ready on six cycles in seven.
(defun pay-script (cycle st)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st))
       (c (pay-get 'k-expected-coordinate-q st))
       (base (list (cons 'h-epready (if (equal (mod cycle 7) 3) 0 1))
                   (cons 'h-attn-ready 1)
                   (cons 'h-layer @@LAYER@@) (cons 'h-position @@POSITION@@)
                   (cons 'h-kexp @@KEXP@@) (cons 'h-vexp @@VEXP@@))))
    (cond ((and (equal s 0) (equal (pay-get 'k-stage-begin-consumed-q st) 0)
                (equal (pay-get 'k-lock-seen-q st) 1))
           (cons (cons 'h-sbegin 1) base))
          ((and (equal s 1) (equal (pay-get 'k-stage-payload-consumed-q st) 0)
                (not (equal (mod cycle 4) 2)))
           (list* (cons 'h-spayload 1) (cons 'h-index c)
                  (cons 'h-key (+ #x100 (* 3 c))) (cons 'h-value (+ #x4000 (* 5 c)))
                  base))
          (t base))))

; One cycle after another, from `st`.  Collects the writes accepted at the
; boundary's endpoint and at the controller's typed port, in order, and stops
; when the controller reports the record complete (PENDING), on a signal that
; is not definite, or at the limit.
(defun pay-run-loop (cycle limit st ep typed)
  (declare (xargs :mode :program))
  (b* (((when (<= limit cycle)) (list :limit cycle (reverse ep) (reverse typed) st))
       (hy (pay-script cycle st))
       (out (svtv-run (@@RUN@@)
                      (append (list (cons 'i-reset-n (if (< cycle 3) 0 1)) (cons 'i-clear 0))
                              (pay-state-env *pay-state-ids* st)
                              (pay-hyp-env *pay-hyp-ids* hy))
                      :quiet t))
       (nst (pay-next-state *pay-state-ids* out))
       ((unless (pay-all-natp nst)) (list :not-definite cycle (reverse ep) (reverse typed) st))
       ((unless (and (equal (pay-get 'o-pfn out) 0) (equal (pay-get 'o-tfe out) 0)))
        (list :fault cycle (reverse ep) (reverse typed) st))
       (ep (if (and (equal (pay-get 'o-epv out) 1) (equal (pay-get 'h-epready hy) 1)
                    (equal (pay-get 'o-epw out) 1))
               (cons (list cycle (pay-get 'o-epaddr out) (pay-get 'o-epdata out)) ep)
             ep))
       (typed (if (and (equal (pay-get 'o-wreqv out) 1) (equal (pay-get 'o-wreqr out) 1))
                  (cons (list cycle (pay-get 'o-wreqaddr out) (pay-get 'o-wreqdata out)) typed)
                typed))
       ((when (equal (pay-get 'k-state-q nst) 4))
        (list :complete (+ 1 cycle) (reverse ep) (reverse typed) nst)))
    (pay-run-loop (+ 1 cycle) limit nst ep typed)))
"""


def run_text(run="payload-step-run"):
    t = RUN
    for k, v in (("@@STATE@@", " ".join(L.STATES + L.PAYLOAD)), ("@@HYPS@@", " ".join(L.HYPS)),
                 ("@@LAYER@@", str(LAYER)), ("@@POSITION@@", str(POSITION)),
                 ("@@KEXP@@", str(KEXP)), ("@@VEXP@@", str(VEXP)), ("@@RUN@@", run)):
        t = t.replace(k, v)
    return t


def expected_text():
    return "'(" + "\n    ".join("(%d #x%x)" % e for e in expected()) + ")"


if __name__ == "__main__":
    with open(sys.argv[1], "w") as f:
        f.write(run_text())
        f.write("""
(defun pay-strip-cycles (l)
  (declare (xargs :mode :program))
  (if (atom l) nil (cons (cdr (car l)) (pay-strip-cycles (cdr l)))))
(defun pay-cycles (l)
  (declare (xargs :mode :program))
  (if (atom l) nil (cons (car (car l)) (pay-cycles (cdr l)))))
(defconst *pay-run* (pay-run-loop 0 4000 (pay-zero-state *pay-state-ids*) nil nil))
(defconst *pay-expected* %s)
(acl2::cw "RUN outcome ~x0 at cycle ~x1; endpoint writes ~x2; typed writes ~x3~%%"
          (first *pay-run*) (second *pay-run*) (len (third *pay-run*)) (len (fourth *pay-run*)))
(acl2::cw "RUN endpoint writes equal the expected record: ~x0~%%"
          (equal (pay-strip-cycles (third *pay-run*)) *pay-expected*))
(acl2::cw "RUN typed-port writes equal the expected record: ~x0~%%"
          (equal (pay-strip-cycles (fourth *pay-run*)) *pay-expected*))
(acl2::cw "RUN endpoint cycles ~x0~%%" (pay-cycles (third *pay-run*)))
(acl2::cw "RUN typed cycles ~x0~%%" (pay-cycles (fourth *pay-run*)))
(acl2::cw "RUN reported complete ~x0, fault ~x1~%%"
          (pay-get 'k-pending-persisted-q (fifth *pay-run*)) (pay-get 'k-fault-q (fifth *pay-run*)))
(acl2::cw "RUN first three endpoint writes ~x0~%%" (take 3 (third *pay-run*)))
""" % expected_text())

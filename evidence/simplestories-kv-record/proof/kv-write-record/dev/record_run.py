"""The scripted run used as the reachable stalled completion, and by the
negative control.  It is the payload book's script (the same staged record)
with a different schedule for the endpoint, and it keeps, for every cycle,
what the record theorem talks about: the controller's state, row and word
counter, the interrupted flag, pending_persisted_q now and next, the write
the endpoint accepted if any, whether a write was offered and refused, and
the eighteen words of the record as the registers hold it in that cycle.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import record_step as R  # noqa: E402  (puts the payload book's dev/ on the path)
import gen_run  # noqa: E402

BANKS = " ".join("(pay-get 'k-bank%d st)" % i for i in range(8))

RUN = r"""
; THE SCRIPT.  The client stages the record of the payload book's run: layer
; @@LAYER@@, position @@POSITION@@, exponent bytes @@KEXP@@ and @@VEXP@@;
; coordinate c has key #x100 + 3c and value #x4000 + 5c; a beat on three
; cycles in four.  The endpoint is slow: it is not ready on three cycles in
; five, and while the controller is on word 0, 3 or 8 of either row it is
; also not ready on 48 cycles in every 64.  Word 8 of the K row and word 0 of
; the V row are the two sides of the step from one row to the other, and
; word 8 of the V row is the last before the record is reported complete.
(defun rec-ready (cycle st)
  (declare (xargs :mode :program))
  (if (or (< (mod cycle 5) 3)
          (and (member (pay-get 'k-write-word-q st) '(0 3 8))
               (< (mod cycle 64) 48)))
      0 1))
(defun rec-script (cycle st)
  (declare (xargs :mode :program))
  (b* ((s (pay-get 'k-state-q st))
       (c (pay-get 'k-expected-coordinate-q st))
       (base (list (cons 'h-epready (rec-ready cycle st))
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

; the eighteen words of the record as the registers hold it
(defun rec-held (st)
  (declare (xargs :mode :program))
  (rec-words (pay-get 'k-pending-layer-q st) (pay-get 'k-pending-position-q st)
             (pay-get 'k-pending-key-exponents-q st) (pay-get 'k-pending-value-exponents-q st)
             @@BANKS@@))

; One cycle after another from `st`; one entry per cycle:
;   (cycle state_q write_head_q write_word_q write_aborted_q
;    pending_persisted_q its-next-value accepted-write refused held-record)
; Stops when the controller reaches PENDING, on a signal that is not
; definite, on a fault, or at the limit.
(defun rec-run-loop (cycle limit st trace)
  (declare (xargs :mode :program))
  (b* (((when (<= limit cycle)) (list :limit (reverse trace)))
       (hy (rec-script cycle st))
       (out (svtv-run (@@RUN@@)
                      (append (list (cons 'i-reset-n (if (< cycle 3) 0 1)) (cons 'i-clear 0))
                              (pay-state-env *pay-state-ids* st)
                              (pay-hyp-env *pay-hyp-ids* hy))
                      :quiet t))
       (nst (pay-next-state *pay-state-ids* out))
       ((unless (pay-all-natp nst)) (list :not-definite (reverse trace)))
       ((unless (and (equal (pay-get 'o-pfn out) 0) (equal (pay-get 'o-tfe out) 0)))
        (list :fault (reverse trace)))
       (offered (and (equal (pay-get 'o-epv out) 1) (equal (pay-get 'o-epw out) 1)))
       (ready (equal (pay-get 'h-epready hy) 1))
       (entry (list cycle
                    (pay-get 'k-state-q st) (pay-get 'k-write-head-q st)
                    (pay-get 'k-write-word-q st) (pay-get 'k-write-aborted-q st)
                    (pay-get 'k-pending-persisted-q st) (pay-get 'k-pending-persisted-q nst)
                    (and offered ready
                         (list (pay-get 'o-epaddr out) (pay-get 'o-epdata out)))
                    (if (and offered (not ready)) 1 0)
                    (rec-held st)))
       (trace (cons entry trace))
       ((when (equal (pay-get 'k-state-q nst) 4)) (list :complete (reverse trace))))
    (rec-run-loop (+ 1 cycle) limit nst trace)))

; Reading a trace.  The completion edge: the cycle whose pending_persisted_q
; is 0 with next value 1.
(defun rec-t-edge (trace)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((and (equal (nth 5 (car trace)) 0) (equal (nth 6 (car trace)) 1))
         (nth 0 (car trace)))
        (t (rec-t-edge (cdr trace)))))
; The latest cycle up to n with state_q = 9, write_head_q = h, write_word_q = 0.
(defun rec-t-start (trace n h best)
  (declare (xargs :mode :program))
  (cond ((atom trace) best)
        ((< n (nth 0 (car trace))) best)
        ((and (equal (nth 1 (car trace)) 9) (equal (nth 2 (car trace)) h)
              (equal (nth 3 (car trace)) 0))
         (rec-t-start (cdr trace) n h (nth 0 (car trace))))
        (t (rec-t-start (cdr trace) n h best))))
; The writes the endpoint accepted in cycles j to n, in order.
(defun rec-t-writes (trace j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((< (nth 0 (car trace)) j) (rec-t-writes (cdr trace) j n))
        ((< n (nth 0 (car trace))) nil)
        ((nth 7 (car trace)) (cons (nth 7 (car trace)) (rec-t-writes (cdr trace) j n)))
        (t (rec-t-writes (cdr trace) j n))))
; In how many cycles from j to n a write was offered and refused, and the
; longest run of such cycles.
(defun rec-t-refused (trace j n)
  (declare (xargs :mode :program))
  (cond ((atom trace) 0)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-refused (cdr trace) j n))
        (t (+ (nth 8 (car trace)) (rec-t-refused (cdr trace) j n)))))
(defun rec-t-longest (trace j n run best)
  (declare (xargs :mode :program))
  (cond ((atom trace) (max run best))
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-longest (cdr trace) j n 0 (max run best)))
        ((equal (nth 8 (car trace)) 1) (rec-t-longest (cdr trace) j n (+ 1 run) best))
        (t (rec-t-longest (cdr trace) j n 0 (max run best)))))
; The record held in cycle j.
(defun rec-t-held (trace j)
  (declare (xargs :mode :program))
  (cond ((atom trace) nil)
        ((equal (nth 0 (car trace)) j) (nth 9 (car trace)))
        (t (rec-t-held (cdr trace) j))))
; Every cycle from j to n is a write cycle, not interrupted, and holds `held`.
(defun rec-t-steady (trace j n held)
  (declare (xargs :mode :program))
  (cond ((atom trace) t)
        ((or (< (nth 0 (car trace)) j) (< n (nth 0 (car trace)))) (rec-t-steady (cdr trace) j n held))
        (t (and (member (nth 1 (car trace)) '(2 3 9 10 11 12))
                (equal (nth 4 (car trace)) 0)
                (or (null held) (equal (nth 9 (car trace)) held))
                (rec-t-steady (cdr trace) j n held)))))
; What the theorems below are stated about:
;   (outcome cycles n j jv writes held-at-j held-at-jv refused longest steady written)
; n the completion edge, j the record's start, jv the V row's start.
(defun rec-run-summary (limit)
  (declare (xargs :mode :program))
  (b* ((run (rec-run-loop 0 limit (pay-zero-state *pay-state-ids*) nil))
       (trace (second run))
       (n (rec-t-edge trace))
       (j (and n (rec-t-start trace n 0 nil)))
       (jv (and n (rec-t-start trace n 1 nil)))
       ((unless (and n j jv)) (list (first run) (len trace) n j jv nil nil nil 0 0 nil nil)))
    (list (first run) (len trace) n j jv
          (rec-t-writes trace j n)
          (rec-t-held trace j)
          (rec-t-held trace jv)
          (rec-t-refused trace j n)
          (rec-t-longest trace j n 0 0)
          (rec-t-steady trace j n (rec-t-held trace j))
          (rec-t-steady trace j n nil))))
"""


def run_text(run="payload-step-run"):
    t = RUN
    for k, v in (("@@LAYER@@", str(gen_run.LAYER)), ("@@POSITION@@", str(gen_run.POSITION)),
                 ("@@KEXP@@", str(gen_run.KEXP)), ("@@VEXP@@", str(gen_run.VEXP)),
                 ("@@RUN@@", run), ("@@BANKS@@", BANKS)):
        t = t.replace(k, v)
    return t


CONSTS = """
(defconsts *rec-run* (rec-run-summary 6000))
(defconst *rec-run-outcome* (nth 0 *rec-run*))
(defconst *rec-run-cycles* (nth 1 *rec-run*))
; the completion edge, the record's start, the V row's start
(defconst *rec-run-n* (nth 2 *rec-run*))
(defconst *rec-run-j* (nth 3 *rec-run*))
(defconst *rec-run-jv* (nth 4 *rec-run*))
; the writes the endpoint accepted in cycles j to n
(defconst *rec-run-writes* (nth 5 *rec-run*))
; the record the registers hold at j, and at jv
(defconst *rec-run-held-at-start* (nth 6 *rec-run*))
(defconst *rec-run-held-at-v-start* (nth 7 *rec-run*))
; cycles from j to n in which a write was offered and refused; longest run
(defconst *rec-run-refused* (nth 8 *rec-run*))
(defconst *rec-run-longest-stall* (nth 9 *rec-run*))
; from j to n: a write state, not interrupted, in every cycle; and the same
; held record in every cycle
(defconst *rec-run-same-record-throughout* (nth 10 *rec-run*))
(defconst *rec-run-written-throughout* (nth 11 *rec-run*))
"""

if __name__ == "__main__":
    sys.stdout.write(run_text() + CONSTS)

; HOW A VALUE VECTOR IS LAID OUT IN THE RECORD'S NINE V WORDS.
;
; Private.  See README.md in this directory.
;
; The V row of a K/V record is nine 256-bit words: eight data words, each
; with sixteen mantissas of sixteen bits in two's complement, the first
; lowest, and a metadata word whose bits [7:0] and [15:8] both hold the
; exponent in two's complement.  (The independent CPU check packs the same
; way: compare_record in
; coordination/architect/simplestories-fable-token1-kv-numerical-20261120/check.py.)
;
;   (ssv-v-record-words token image)
;       the nine words the specification's V vector of the token would be
;       stored as
(in-package "ACL2")
(include-book "ssv-spec")
(set-verify-guards-eagerness 0)

; the first n of a list of mantissas as one word
(defun ssv-pack16 (mantissas n)
  (if (zp n)
      0
    (+ (mod (car mantissas) 65536)
       (* 65536 (ssv-pack16 (cdr mantissas) (- n 1))))))
; k data words, sixteen mantissas each
(defun ssv-data-words (mantissas k)
  (if (zp k)
      nil
    (cons (ssv-pack16 mantissas 16)
          (ssv-data-words (nthcdr 16 mantissas) (- k 1)))))
(defun ssv-exponent-word (exponent)
  (+ (mod exponent 256) (* 256 (mod exponent 256))))
(defun ssv-v-record-words (token image)
  (let ((v (ssv-v-vector token image)))
    (append (ssv-data-words (cdr v) 8)
            (list (ssv-exponent-word (car v))))))

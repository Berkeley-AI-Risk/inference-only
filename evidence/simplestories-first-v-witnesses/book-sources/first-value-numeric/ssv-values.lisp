; THE SPECIFICATION'S FIRST VALUE COORDINATE FOR TOKENS 1 AND 2.
;
; Private.  See README.md in this directory.
;
; ACL2 evaluates the specification on the image: for token 1 the first V
; mantissa is -6191 and for token 2 it is 3076, both at exponent -16, and
; the oracle refuses neither token.  These are the numbers of the
; independent CPU check
; (coordination/architect/simplestories-held-clear-model-comparison-20261122/).
(in-package "ACL2")
(include-book "ssv-spec")
(include-book "ssv-image")

(defthm ssv-first-value-of-token-1
  (and (equal (ssv-v-mantissa 0 1 (ssv-image)) -6191)
       (equal (ssv-v-exponent 1 (ssv-image)) -16)
       (ssv-profile-ok 1 (ssv-image)))
  :hints (("Goal" :in-theory '((:e ssv-v-mantissa) (:e ssv-v-exponent)
                               (:e ssv-profile-ok) (:e ssv-image))))
  :rule-classes nil)

(defthm ssv-first-value-of-token-2
  (and (equal (ssv-v-mantissa 0 2 (ssv-image)) 3076)
       (equal (ssv-v-exponent 2 (ssv-image)) -16)
       (ssv-profile-ok 2 (ssv-image)))
  :hints (("Goal" :in-theory '((:e ssv-v-mantissa) (:e ssv-v-exponent)
                               (:e ssv-profile-ok) (:e ssv-image))))
  :rule-classes nil)

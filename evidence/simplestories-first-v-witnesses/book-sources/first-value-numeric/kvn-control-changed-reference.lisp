; NEGATIVE CONTROLS: A CHANGED NUMERICAL REFERENCE IS DETECTED.
;
; Private.  See README.md in this directory.
;
; The statement of kvn-token-1 is about the execution with the pinned image
; and the specification evaluated on the same image.  Here the reference is
; changed and the execution is not: the specification is evaluated on an
; image with one bit flipped, or for another token, and compared with the
; record the execution wrote.  Each time ACL2 proves that the record's first
; V mantissa is not the changed reference's, so the statement with the
; changed reference is false.
;
;   one bit of the token's embedding row      kvn-changed-embedding-bit-is-detected
;   one bit of the RMS normalization weights  kvn-changed-gamma-bit-is-detected
;   one bit of the value projection's row 0   kvn-changed-value-weight-bit-is-detected
;   the reference of token 2                  kvn-other-token-reference-is-detected
;
; and what the first coordinate cannot see: a bit of the value projection's
; row 1 leaves the first V mantissa as it is and changes the second
; (kvn-changed-row-1-bit-is-seen-by-the-second-coordinate).
(in-package "SV")
(include-book "kvn-token-1")

; the image with bit `bit` of word `w` flipped
(define kvn-flip (w bit image) :verify-guards nil
  (update-nth w (logxor (nfix (nth w image)) (ash 1 bit)) image))

; Word 171480 is the first word of the tied embedding group of tokens 0..63;
; its bits [19:10] are token 1's weight for input column 0.
(define kvn-image-embedding-bit () :verify-guards nil
  (kvn-flip 171480 10 (acl2::ssv-image))
  ///
  (in-theory (disable (:e kvn-image-embedding-bit))))
; Word 211800 holds the first RMS normalization weights; bits [9:0] are the
; weight of column 0.
(define kvn-image-gamma-bit () :verify-guards nil
  (kvn-flip 211800 0 (acl2::ssv-image))
  ///
  (in-theory (disable (:e kvn-image-gamma-bit))))
; Word 3840 is the first word of the value projection's first group; its
; bits [9:0] are the weight of row 0, column 0, and bits [19:10] that of
; row 1, column 0.
(define kvn-image-value-row-0-bit () :verify-guards nil
  (kvn-flip 3840 0 (acl2::ssv-image))
  ///
  (in-theory (disable (:e kvn-image-value-row-0-bit))))
(define kvn-image-value-row-1-bit () :verify-guards nil
  (kvn-flip 3840 10 (acl2::ssv-image))
  ///
  (in-theory (disable (:e kvn-image-value-row-1-bit))))

; ---------------------------------------------------------------------------
; The specification on the changed references, by evaluation.
; ---------------------------------------------------------------------------
(defthm kvn-changed-references-evaluated
  (and (equal (acl2::ssv-v-mantissa 0 1 (kvn-image-embedding-bit)) -6188)
       (equal (acl2::ssv-v-mantissa 0 1 (kvn-image-gamma-bit)) -6190)
       (equal (acl2::ssv-v-mantissa 0 1 (kvn-image-value-row-0-bit)) -6187)
       (equal (acl2::ssv-v-mantissa 0 1 (kvn-image-value-row-1-bit)) -6191)
       (not (equal (acl2::ssv-v-mantissa 1 1 (kvn-image-value-row-1-bit))
                   (acl2::ssv-v-mantissa 1 1 (acl2::ssv-image)))))
  :hints (("Goal" :in-theory '((:e acl2::ssv-v-mantissa) (:e acl2::ssv-image)
                               (:e kvn-image-embedding-bit) (:e kvn-image-gamma-bit)
                               (:e kvn-image-value-row-0-bit) (:e kvn-image-value-row-1-bit)
                               (:e equal) (:e not))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The record against each changed reference.
; ---------------------------------------------------------------------------
(defmacro kvn-token-1-writes ()
  '(b* ((envs (kvn-envs (kvn-tuples-token-1) (kvn-rom)))
        (initst (kvn-zero-state))
        (outs (fsm-eval envs initst (probe-fsm-held)))
        (j (kv-record-start 68596 outs)))
     (kv-endpoint-writes j (+ 1 68596) envs outs)))
(defmacro kvn-token-1-statement-with (token image)
  `(b* ((envs (kvn-envs (kvn-tuples-token-1) (kvn-rom)))
        (initst (kvn-zero-state))
        (outs (fsm-eval envs initst (probe-fsm-held))))
     (kvn-ordinary-step-statement ,token 68596 envs initst outs ,image (kvn-rom))))

(defthm kvn-changed-embedding-bit-is-detected
  (and (not (equal (kvn-record-v0 (kvn-token-1-writes))
                   (acl2::ssv-v-mantissa 0 1 (kvn-image-embedding-bit))))
       (not (kvn-token-1-statement-with 1 (kvn-image-embedding-bit))))
  :hints (("Goal" :use ((:instance kvn-token-1-first-value)
                        (:instance kvn-changed-references-evaluated))
           :in-theory '(kvn-ordinary-step-statement)))
  :rule-classes nil)

(defthm kvn-changed-gamma-bit-is-detected
  (and (not (equal (kvn-record-v0 (kvn-token-1-writes))
                   (acl2::ssv-v-mantissa 0 1 (kvn-image-gamma-bit))))
       (not (kvn-token-1-statement-with 1 (kvn-image-gamma-bit))))
  :hints (("Goal" :use ((:instance kvn-token-1-first-value)
                        (:instance kvn-changed-references-evaluated))
           :in-theory '(kvn-ordinary-step-statement)))
  :rule-classes nil)

(defthm kvn-changed-value-weight-bit-is-detected
  (and (not (equal (kvn-record-v0 (kvn-token-1-writes))
                   (acl2::ssv-v-mantissa 0 1 (kvn-image-value-row-0-bit))))
       (not (kvn-token-1-statement-with 1 (kvn-image-value-row-0-bit))))
  :hints (("Goal" :use ((:instance kvn-token-1-first-value)
                        (:instance kvn-changed-references-evaluated))
           :in-theory '(kvn-ordinary-step-statement)))
  :rule-classes nil)

(defthm kvn-other-token-reference-is-detected
  (and (not (equal (kvn-record-v0 (kvn-token-1-writes))
                   (acl2::ssv-v-mantissa 0 2 (acl2::ssv-image))))
       (not (kvn-token-1-statement-with 2 (acl2::ssv-image))))
  :hints (("Goal" :use ((:instance kvn-token-1-first-value)
                        (:instance acl2::ssv-first-value-of-token-2))
           :in-theory '(kvn-ordinary-step-statement)))
  :rule-classes nil)

; What the first coordinate does not depend on: row 1's weight.  The first
; V mantissa of the changed reference is still the record's; the second is
; not the pinned reference's, and the record's 128 mantissas are the pinned
; reference's, so the statement with this changed reference is false too.
(local
 (defthm kvn-second-of-equal-lists
   (implies (equal x y) (equal (nth 1 x) (nth 1 y)))
   :rule-classes nil))
(defthm kvn-changed-row-1-bit-is-seen-by-the-second-coordinate
  (and (equal (kvn-record-v0 (kvn-token-1-writes))
              (acl2::ssv-v-mantissa 0 1 (kvn-image-value-row-1-bit)))
       (not (equal (acl2::ssv-v-mantissa 1 1 (kvn-image-value-row-1-bit))
                   (acl2::ssv-v-mantissa 1 1 (acl2::ssv-image))))
       (not (kvn-token-1-statement-with 1 (kvn-image-value-row-1-bit))))
  :hints (("Goal" :use ((:instance kvn-token-1-first-value)
                        (:instance kvn-changed-references-evaluated)
                        (:instance kvn-second-of-equal-lists
                                   (x (kvn-record-v-list 0 (kvn-token-1-writes)))
                                   (y (cdr (acl2::ssv-v-vector 1 (acl2::ssv-image)))))
                        (:instance kvn-second-of-equal-lists
                                   (x (kvn-record-v-list 0 (kvn-token-1-writes)))
                                   (y (cdr (acl2::ssv-v-vector 1 (kvn-image-value-row-1-bit))))))
           :in-theory '(kvn-ordinary-step-statement acl2::ssv-v-mantissa)))
  :rule-classes nil)
(value-triple (acl2::cw "~%KVN-CONTROLS proved~%"))

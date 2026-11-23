; THE FIXED-POINT SPECIFICATION OF THE LAYER-0 VALUE VECTOR.
;
; Private.  See README.md in this directory.
;
; This book defines, with ACL2's built-in integer functions only, the value
; (V) vector the released SimpleStories integer arithmetic assigns to one
; token at layer 0, as a function of the token and of the model image:
;
;     (ssv-v-mantissa c token image)   the signed mantissa of coordinate c
;     (ssv-v-exponent token image)     the exponent shared by the 128 coordinates
;
; so that coordinate c of the V vector is mantissa * 2^exponent.  It loads no
; other book for its definitions, and nothing here mentions the circuit.
;
; SOURCES.  The arithmetic is that of the released integer oracle,
;   fpga-demo/public-release/demos/simplestories-v2-5m/reference/quantization/oracle.py
;   (SHA-256 9b048a8e8b82faba3d21fd6b259aa1c23d91f04662fe2734fc109602777b4a74),
; function by function; each definition below names the oracle function it
; follows.  The oracle works on a tensor archive.  Where each tensor of the
; archive lies in the model image is taken from the independent CPU check
;   coordination/architect/simplestories-fable-token1-kv-numerical-20261120/check.py
;   (direct_reference; SHA-256 d4e9b26ea0b75072c3e1b8066d7fe777dfd1ae7d0f9b2b16bdafff9736e2f74e),
; which decodes the image and agrees with the oracle run on the archive.
;
; THE IMAGE is a list of 256-bit words: word w is the little-endian integer
; of bytes [32w, 32w+32) of the image file.
;
; WHAT THE ORACLE REFUSES.  The oracle raises an error when a value leaves
; its declared range (accumulator widths, the exponent range, forbidden
; weight codes).  The functions here return numbers in every case;
; (ssv-profile-ok token image) says that none of those errors occurs for
; this token, and the theorems that use the specification state it.
(in-package "ACL2")
(set-verify-guards-eagerness 0)

; ---------------------------------------------------------------------------
; Bits of the image.
; ---------------------------------------------------------------------------
; the little-endian integer of a list of 256-bit words, the first lowest
(defun ssv-pack-words (words)
  (if (endp words)
      0
    (+ (nfix (car words))
       (* (expt 2 256) (ssv-pack-words (cdr words))))))
; the n words from word address w on, as one integer
(defun ssv-region (image w n)
  (ssv-pack-words (take n (nthcdr w image))))
; bits [pos, pos+width) of the natural x
(defun ssv-bits (x pos width)
  (logand (ash x (- pos)) (- (expt 2 width) 1)))
; a width-bit field read as a two's-complement number
(defun ssv-signed (x width)
  (if (< x (expt 2 (- width 1))) x (- x (expt 2 width))))

; A WEIGHT GROUP is 640 words: 256 stripes of 640 bits, stripe c holding, for
; each of 64 rows r, the signed ten-bit weight of row r and input column c
; in bits [10r, 10r+10)  (oracle: _unpack_int10, LSB first).
(defun ssv-stripe (group c) (ssv-bits group (* 640 c) 640))
(defun ssv-w10 (stripe row) (ssv-signed (ssv-bits stripe (* 10 row) 10) 10))
; stripes c .. 255 of a group
(defun ssv-stripes-from (group c)
  (declare (xargs :measure (nfix (- 256 (nfix c)))))
  (if (zp (- 256 (nfix c)))
      nil
    (cons (ssv-stripe group (nfix c))
          (ssv-stripes-from group (+ 1 (nfix c))))))
(defun ssv-stripes (image w) (ssv-stripes-from (ssv-region image w 640) 0))

; A METADATA GROUP is 8 words: for each of 64 rows, four bytes: a signed
; exponent byte, a 16-bit multiplier (low byte first), and a zero byte.
(defun ssv-meta-exponent (meta row) (ssv-signed (ssv-bits meta (* 32 row) 8) 8))
(defun ssv-meta-multiplier (meta row) (ssv-bits meta (+ 8 (* 32 row)) 16))
(defun ssv-meta-padding (meta row) (ssv-bits meta (+ 24 (* 32 row)) 8))

; ---------------------------------------------------------------------------
; Rounding (oracle: _round_div_even_scalar, _round_shift_even_scalar).
; ---------------------------------------------------------------------------
; numerator / denominator rounded to nearest, ties to even; denominator > 0
(defun ssv-rne-div (numerator denominator)
  (let* ((magnitude (abs numerator))
         (quotient (floor magnitude denominator))
         (remainder (- magnitude (* quotient denominator)))
         (twice (* 2 remainder))
         (quotient (if (or (> twice denominator)
                           (and (= twice denominator) (oddp quotient)))
                       (+ quotient 1)
                     quotient)))
    (if (< numerator 0) (- quotient) quotient)))
; value / 2^shift, rounded so; a negative shift multiplies exactly
(defun ssv-rne-shift (value shift)
  (cond ((< shift 0) (* value (expt 2 (- shift))))
        ((= shift 0) value)
        ((> shift 62) 0)
        (t (ssv-rne-div value (expt 2 shift)))))

; ---------------------------------------------------------------------------
; Block normalization (oracle: _select_exponent, _normalize_mixed).
; A vector of integers values[i] * 2^exps[i] is brought to one shared
; exponent with every mantissa in [-32767, 32767].
; ---------------------------------------------------------------------------
(defun ssv-i16-p (x) (and (<= -32767 x) (<= x 32767)))
; every nonzero value, rounded to exponent e, is a legal mantissa
(defun ssv-fits (values exps e)
  (cond ((endp values) t)
        ((= (car values) 0) (ssv-fits (cdr values) (cdr exps) e))
        (t (and (ssv-i16-p (ssv-rne-shift (car values) (- e (car exps))))
                (ssv-fits (cdr values) (cdr exps) e)))))
; the oracle's first guess: the largest of exps[i] + bit-length(|values[i]|) - 15
; over the nonzero values; nil when every value is zero
(defun ssv-candidate (values exps)
  (cond ((endp values) nil)
        ((= (car values) 0) (ssv-candidate (cdr values) (cdr exps)))
        (t (let ((here (+ (car exps) (integer-length (abs (car values))) -15))
                 (rest (ssv-candidate (cdr values) (cdr exps))))
             (if (and rest (> rest here)) rest here)))))
; "while not fits(candidate): candidate += 1"; 32 stands for the oracle's
; "BFP exponent overflow" error
(defun ssv-exponent-up (values exps e)
  (declare (xargs :measure (nfix (- 32 (ifix e)))))
  (cond ((not (integerp e)) 32)
        ((> e 31) 32)
        ((ssv-fits values exps e) e)
        (t (ssv-exponent-up values exps (+ e 1)))))
; "while candidate > -32 and fits(candidate - 1): candidate -= 1"
(defun ssv-exponent-down (values exps e)
  (declare (xargs :measure (nfix (+ 32 (ifix e)))))
  (cond ((not (integerp e)) -32)
        ((<= e -32) e)
        ((ssv-fits values exps (- e 1)) (ssv-exponent-down values exps (- e 1)))
        (t e)))
(defun ssv-select-exponent (values exps)
  (let ((candidate (ssv-candidate values exps)))
    (if (not candidate)
        0
      (ssv-exponent-down
       values exps
       (ssv-exponent-up values exps (max -32 (min 31 candidate)))))))
(defun ssv-clip (x) (max -32767 (min 32767 x)))
(defun ssv-mantissas (values exps e)
  (if (endp values)
      nil
    (cons (ssv-clip (ssv-rne-shift (car values) (- e (car exps))))
          (ssv-mantissas (cdr values) (cdr exps) e))))
; a normalized vector is (exponent . mantissas)
(defun ssv-normalize-mixed (values exps)
  (let ((e (ssv-select-exponent values exps)))
    (cons e (ssv-mantissas values exps e))))
(defun ssv-repeat (n x) (if (zp n) nil (cons x (ssv-repeat (- n 1) x))))
; oracle: _normalize, one exponent for every value
(defun ssv-normalize (values exponent)
  (ssv-normalize-mixed values (ssv-repeat (len values) exponent)))

; ---------------------------------------------------------------------------
; The embedding of a token (oracle: _embedding).
; Token t is row (t mod 64) of the tied embedding group (floor t/64), whose
; weights are at word 171480 + 640*group and whose metadata is at word
; 213744 + 8*group.
; ---------------------------------------------------------------------------
(defun ssv-scaled-row (stripes row multiplier)
  (if (endp stripes)
      nil
    (cons (* (ssv-w10 (car stripes) row) multiplier)
          (ssv-scaled-row (cdr stripes) row multiplier))))
(defun ssv-embedding (token image)
  (let* ((group (floor token 64))
         (row (mod token 64))
         (stripes (ssv-stripes image (+ 171480 (* 640 group))))
         (meta (ssv-region image (+ 213744 (* 8 group)) 8)))
    (ssv-normalize (ssv-scaled-row stripes row (ssv-meta-multiplier meta row))
                   (- (ssv-meta-exponent meta row) 15))))

; ---------------------------------------------------------------------------
; The input RMS normalization of layer 0 (oracle: _rms_norm, with
; RMS_UNIT_FRACTION = 12).  Its 256 ten-bit weights are at word 211800, ten
; bits each from bit 0 up, and their exponent and multiplier are row 0 of the
; metadata at word 214248.
; ---------------------------------------------------------------------------
; The floor of the square root (oracle: math.isqrt), one bit at a time from
; the top: `root` has the bits above `bits` already decided, and bit
; `bits`-1 is set when the square still does not exceed n.
; (ssv-spec-properties proves the result r has r*r <= n < (r+1)*(r+1).)
(defun ssv-isqrt-bits (bits root n)
  (if (zp bits)
      root
    (let ((try (+ root (expt 2 (- bits 1)))))
      (ssv-isqrt-bits (- bits 1) (if (<= (* try try) n) try root) n))))
(defun ssv-isqrt (n) (ssv-isqrt-bits (integer-length n) 0 n))

(defun ssv-sum-squares (xs)
  (if (endp xs) 0 (+ (* (car xs) (car xs)) (ssv-sum-squares (cdr xs)))))
; each value * 2^12 / rms, rounded and clipped
(defun ssv-unit-scale (xs rms)
  (if (endp xs)
      nil
    (cons (ssv-clip (ssv-rne-div (* (car xs) 4096) rms))
          (ssv-unit-scale (cdr xs) rms))))
; normalized[i] * weight[i] * multiplier
(defun ssv-gamma-products (xs gamma i multiplier)
  (if (endp xs)
      nil
    (cons (* (car xs) (ssv-signed (ssv-bits gamma (* 10 i) 10) 10) multiplier)
          (ssv-gamma-products (cdr xs) gamma (+ 1 i) multiplier))))
(defun ssv-rms-radicand (vector)
  (let* ((mean-square (ssv-rne-div (ssv-sum-squares (cdr vector)) (len (cdr vector))))
         (epsilon-shift (- -20 (* 2 (car vector))))
         (epsilon (if (< epsilon-shift 0)
                      (ssv-rne-shift 1 (- epsilon-shift))
                    (expt 2 epsilon-shift))))
    (max 1 (+ mean-square epsilon))))
(defun ssv-rms-unit (vector)
  (ssv-unit-scale (cdr vector) (ssv-isqrt (ssv-rms-radicand vector))))
(defun ssv-rms-norm (vector image)
  (let* ((gamma (ssv-region image 211800 10))
         (meta (ssv-region image 214248 8)))
    (ssv-normalize (ssv-gamma-products (ssv-rms-unit vector) gamma 0
                                       (ssv-meta-multiplier meta 0))
                   (- (ssv-meta-exponent meta 0) 27))))

; ---------------------------------------------------------------------------
; The value projection of layer 0 (oracle: _matvec).  Its 128 rows are two
; weight groups of 64, at words 3840 and 4480, with metadata at words 211968
; and 211976.  Row r of a group contributes
;     (sum over columns c of x[c] * weight[r][c]) * multiplier[r]
; at exponent  x's exponent + exponent[r] - 15, and the 128 contributions are
; normalized together.
; ---------------------------------------------------------------------------
(defun ssv-dot (xs stripes row)
  (if (endp xs)
      0
    (+ (* (car xs) (ssv-w10 (car stripes) row))
       (ssv-dot (cdr xs) (cdr stripes) row))))
; rows row .. 63 of one group: the scaled dot products
(defun ssv-group-values (xs stripes meta row)
  (declare (xargs :measure (nfix (- 64 (nfix row)))))
  (if (zp (- 64 (nfix row)))
      nil
    (cons (* (ssv-dot xs stripes (nfix row)) (ssv-meta-multiplier meta (nfix row)))
          (ssv-group-values xs stripes meta (+ 1 (nfix row))))))
; and their exponents
(defun ssv-group-exponents (x-exponent meta row)
  (declare (xargs :measure (nfix (- 64 (nfix row)))))
  (if (zp (- 64 (nfix row)))
      nil
    (cons (+ x-exponent (ssv-meta-exponent meta (nfix row)) -15)
          (ssv-group-exponents x-exponent meta (+ 1 (nfix row))))))
(defun ssv-v-projection (vector image)
  (let* ((stripes0 (ssv-stripes image 3840))
         (stripes1 (ssv-stripes image 4480))
         (meta0 (ssv-region image 211968 8))
         (meta1 (ssv-region image 211976 8)))
    (ssv-normalize-mixed
     (append (ssv-group-values (cdr vector) stripes0 meta0 0)
             (ssv-group-values (cdr vector) stripes1 meta1 0))
     (append (ssv-group-exponents (car vector) meta0 0)
             (ssv-group-exponents (car vector) meta1 0)))))

; ---------------------------------------------------------------------------
; THE VALUE VECTOR OF A TOKEN AT LAYER 0: embedding, input RMS
; normalization, value projection.
; ---------------------------------------------------------------------------
(defun ssv-v-vector (token image)
  (ssv-v-projection (ssv-rms-norm (ssv-embedding token image) image) image))
(defun ssv-v-exponent (token image) (car (ssv-v-vector token image)))
(defun ssv-v-mantissa (c token image) (nth c (cdr (ssv-v-vector token image))))

; ---------------------------------------------------------------------------
; WHAT THE ORACLE REFUSES, for this token.  (The oracle checks whole tensors
; when it loads them; this checks the rows the token's V vector reads.)  A
; token is legal when it is below the vocabulary size, 4019.  If
; (ssv-profile-ok token image) holds, the oracle raises none of its errors
; on the way to this token's layer-0 V vector.
; ---------------------------------------------------------------------------
(defun ssv-all-below (xs bound)   ; every |x| < bound
  (or (endp xs)
      (and (< (abs (car xs)) bound) (ssv-all-below (cdr xs) bound))))
; no weight of row `row` is the forbidden code -512
(defun ssv-row-codes-ok (stripes row)
  (or (endp stripes)
      (and (not (equal (ssv-w10 (car stripes) row) -512))
           (ssv-row-codes-ok (cdr stripes) row))))
(defun ssv-group-codes-ok (stripes row)
  (declare (xargs :measure (nfix (- 64 (nfix row)))))
  (or (zp (- 64 (nfix row)))
      (and (ssv-row-codes-ok stripes (nfix row))
           (ssv-group-codes-ok stripes (+ 1 (nfix row))))))
(defun ssv-gamma-codes-ok (gamma i)
  (declare (xargs :measure (nfix (- 256 (nfix i)))))
  (or (zp (- 256 (nfix i)))
      (and (not (equal (ssv-signed (ssv-bits gamma (* 10 (nfix i)) 10) 10) -512))
           (ssv-gamma-codes-ok gamma (+ 1 (nfix i))))))
; a metadata row: multiplier in 1 .. 32767, zero padding
(defun ssv-meta-row-ok (meta row)
  (and (<= 1 (ssv-meta-multiplier meta row))
       (<= (ssv-meta-multiplier meta row) 32767)
       (equal (ssv-meta-padding meta row) 0)))
(defun ssv-meta-rows-ok (meta row)
  (declare (xargs :measure (nfix (- 64 (nfix row)))))
  (or (zp (- 64 (nfix row)))
      (and (ssv-meta-row-ok meta (nfix row))
           (ssv-meta-rows-ok meta (+ 1 (nfix row))))))
(defun ssv-dots (xs stripes row)
  (declare (xargs :measure (nfix (- 64 (nfix row)))))
  (if (zp (- 64 (nfix row)))
      nil
    (cons (ssv-dot xs stripes (nfix row))
          (ssv-dots xs stripes (+ 1 (nfix row))))))
; A normalization is inside the oracle's range: the exponent search ends
; inside [-32, 31] with every mantissa legal, and no source exponent is above
; 30, so that no exponent the search tries, down to -32, asks for a left
; shift by more than 62.
(defun ssv-exponents-at-most (exps bound)
  (or (endp exps)
      (and (<= (car exps) bound) (ssv-exponents-at-most (cdr exps) bound))))
(defun ssv-normalization-ok (values exps)
  (let ((e (ssv-select-exponent values exps)))
    (and (<= -32 e) (<= e 31)
         (ssv-fits values exps e)
         (ssv-exponents-at-most exps 30))))
(defun ssv-profile-ok (token image)
  (let* ((group (floor token 64))
         (row (mod token 64))
         (e-stripes (ssv-stripes image (+ 171480 (* 640 group))))
         (e-meta (ssv-region image (+ 213744 (* 8 group)) 8))
         (e-values (ssv-scaled-row e-stripes row (ssv-meta-multiplier e-meta row)))
         (embedding (ssv-embedding token image))
         (gamma (ssv-region image 211800 10))
         (g-meta (ssv-region image 214248 8))
         (radicand (ssv-rms-radicand embedding))
         (unit (ssv-rms-unit embedding))
         (products (ssv-gamma-products unit gamma 0 (ssv-meta-multiplier g-meta 0)))
         (x (ssv-rms-norm embedding image))
         (stripes0 (ssv-stripes image 3840))
         (stripes1 (ssv-stripes image 4480))
         (meta0 (ssv-region image 211968 8))
         (meta1 (ssv-region image 211976 8))
         (dots (append (ssv-dots (cdr x) stripes0 0) (ssv-dots (cdr x) stripes1 0)))
         (values (append (ssv-group-values (cdr x) stripes0 meta0 0)
                         (ssv-group-values (cdr x) stripes1 meta1 0)))
         (exps (append (ssv-group-exponents (car x) meta0 0)
                       (ssv-group-exponents (car x) meta1 0))))
    (and (natp token) (< token 4019)
         ;; the token's embedding row
         (ssv-row-codes-ok e-stripes row)
         (ssv-meta-row-ok e-meta row)
         (ssv-normalization-ok e-values (ssv-repeat 256 (- (ssv-meta-exponent e-meta row) 15)))
         ;; the RMS normalization
         (ssv-gamma-codes-ok gamma 0)
         (ssv-meta-row-ok g-meta 0)
         (< (ssv-sum-squares (cdr embedding)) (expt 2 38))
         (< radicand (expt 2 45))
         (ssv-all-below (cdr embedding) (expt 2 15))      ; |value| * 2^12 < 2^27
         (ssv-all-below products (expt 2 39))
         (ssv-normalization-ok products (ssv-repeat 256 (- (ssv-meta-exponent g-meta 0) 27)))
         ;; the value projection
         (ssv-group-codes-ok stripes0 0)
         (ssv-group-codes-ok stripes1 0)
         (ssv-meta-rows-ok meta0 0)
         (ssv-meta-rows-ok meta1 0)
         (ssv-all-below dots (expt 2 34))
         (ssv-all-below values (expt 2 49))
         (ssv-normalization-ok values exps))))

; SHA-256 of files, computed inside ACL2, and the corrected translator.
;
; Private.  Part of the joined K/V book; see README.md in this directory.
; Written by make_book.py from the pilot's proof (../acl2-pilot/joined);
; edit that script, not this file.
;
; The digest function here is written out in full rather than taken from a
; library, so that the books of the proof load exactly the libraries the
; proof was developed with and nothing else.  It is checked three ways: the
; test vectors of FIPS 180-4 below, the pinned digests of this directory's 77
; source files (which were made with shasum), and the corrected translator's
; digest (the same).
(in-package "SV")
(include-book "std/util/bstar" :dir :system)
(include-book "std/util/defconsts" :dir :system)

; ---- SHA-256 (FIPS 180-4), on lists of bytes ------------------------------
(defconst *kvj-sha256-k*
  '(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3 #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13 #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208 #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

(defconst *kvj-sha256-h0*
  '(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))

(defun kvj-rotr (x n)                   ; rotate a 32-bit word right by n
  (declare (xargs :mode :program))
  (logand #xffffffff (logior (ash x (- n)) (ash x (- 32 n)))))

; Extend the message schedule by n words.  ws holds the words so far, the
; most recent first: W[t-2], W[t-7], W[t-15] and W[t-16] are at positions 1,
; 6, 14 and 15.
(defun kvj-schedule (ws n)
  (declare (xargs :mode :program))
  (if (zp n)
      ws
    (kvj-schedule
     (cons (logand #xffffffff
                   (+ (let ((x (nth 1 ws)))
                        (logxor (kvj-rotr x 17) (kvj-rotr x 19) (ash x -10)))
                      (nth 6 ws)
                      (let ((x (nth 14 ws)))
                        (logxor (kvj-rotr x 7) (kvj-rotr x 18) (ash x -3)))
                      (nth 15 ws)))
           ws)
     (- n 1))))

; The 64 rounds.  ws and ks are the schedule and the constants in order.
(defun kvj-rounds (ws ks a b c d e f g h)
  (declare (xargs :mode :program))
  (if (atom ws)
      (list a b c d e f g h)
    (let* ((t1 (+ h
                  (logxor (kvj-rotr e 6) (kvj-rotr e 11) (kvj-rotr e 25))
                  (logxor (logand e f) (logand (logxor e #xffffffff) g))
                  (car ks)
                  (car ws)))
           (t2 (+ (logxor (kvj-rotr a 2) (kvj-rotr a 13) (kvj-rotr a 22))
                  (logxor (logand a b) (logand a c) (logand b c)))))
      (kvj-rounds (cdr ws) (cdr ks)
                  (logand #xffffffff (+ t1 t2)) a b c
                  (logand #xffffffff (+ d t1)) e f g))))

; The first n big-endian 32-bit words of bytes, most recent first, and the
; bytes that follow them.
(defun kvj-block-words (bytes n acc)
  (declare (xargs :mode :program))
  (if (zp n)
      (mv acc bytes)
    (kvj-block-words (cddddr bytes) (- n 1)
                     (cons (+ (ash (car bytes) 24) (ash (cadr bytes) 16)
                              (ash (caddr bytes) 8) (cadddr bytes))
                           acc))))

(defun kvj-add32 (xs ys)
  (declare (xargs :mode :program))
  (if (atom xs)
      nil
    (cons (logand #xffffffff (+ (car xs) (car ys)))
          (kvj-add32 (cdr xs) (cdr ys)))))

; bytes is the padded message, a whole number of 64-byte blocks.
(defun kvj-blocks (bytes hs)
  (declare (xargs :mode :program))
  (if (atom bytes)
      hs
    (mv-let (ws rest) (kvj-block-words bytes 16 nil)
      (kvj-blocks rest
                  (kvj-add32 hs
                             (kvj-rounds (reverse (kvj-schedule ws 48)) *kvj-sha256-k*
                                         (nth 0 hs) (nth 1 hs) (nth 2 hs) (nth 3 hs)
                                         (nth 4 hs) (nth 5 hs) (nth 6 hs) (nth 7 hs)))))))

(defun kvj-zeros (n acc)
  (declare (xargs :mode :program))
  (if (zp n) acc (kvj-zeros (- n 1) (cons 0 acc))))

(defun kvj-length-bytes (bits n acc)    ; bits as n big-endian bytes, onto acc
  (declare (xargs :mode :program))
  (if (zp n)
      acc
    (kvj-length-bytes (ash bits -8) (- n 1) (cons (logand 255 bits) acc))))

; The padding for a message of len bytes: #x80, zeros up to 56 modulo 64, and
; the length in bits as eight bytes.
(defun kvj-padding (len)
  (declare (xargs :mode :program))
  (cons #x80 (kvj-zeros (mod (- 55 len) 64) (kvj-length-bytes (* 8 len) 8 nil))))

; The character codes of chars, in order, followed by tail.
(defun kvj-codes (chars acc tail)
  (declare (xargs :mode :program))
  (if (atom chars)
      (revappend acc tail)
    (kvj-codes (cdr chars) (cons (char-code (car chars)) acc) tail)))

(defun kvj-hex-chars (words acc)        ; eight hex digits per 32-bit word
  (declare (xargs :mode :program))
  (if (atom words)
      (reverse acc)
    (kvj-hex-chars
     (cdr words)
     (let ((w (car words)))
       (list* (char "0123456789abcdef" (logand 15 w))
              (char "0123456789abcdef" (logand 15 (ash w -4)))
              (char "0123456789abcdef" (logand 15 (ash w -8)))
              (char "0123456789abcdef" (logand 15 (ash w -12)))
              (char "0123456789abcdef" (logand 15 (ash w -16)))
              (char "0123456789abcdef" (logand 15 (ash w -20)))
              (char "0123456789abcdef" (logand 15 (ash w -24)))
              (char "0123456789abcdef" (logand 15 (ash w -28)))
              acc)))))

; The SHA-256 of a file's contents, given as a string with one character per
; byte, as 64 hexadecimal digits.
(defun kvj-sha256-hex (contents)
  (declare (xargs :mode :program))
  (coerce (kvj-hex-chars
           (kvj-blocks (kvj-codes (coerce contents 'list) nil
                                  (kvj-padding (length contents)))
                       *kvj-sha256-h0*)
           nil)
          'string))

; The test vectors of FIPS 180-4 and its examples: the empty message, a
; one-block message, and a two-block message.
(defconsts *kvj-sha256-of-test-vectors*
  (list (kvj-sha256-hex "")
        (kvj-sha256-hex "abc")
        (kvj-sha256-hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))

(defthm kv-joined-sha256-test-vectors
  (equal *kvj-sha256-of-test-vectors*
         '("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
           "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
           "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"))
  :rule-classes nil)

; ---- digests of the files the Verilog loader read ------------------------
; For each file name, in order, its digest.  filemap is what the loader
; returns: the name and the contents of every file it read.  A name the
; loader did not read gets :not-read, and a file it read that is not named is
; reported under :unexpected, so the result equals the pinned list only if
; the loader read exactly the pinned files.
(defun kvj-digests (names filemap)
  (declare (xargs :mode :program))
  (if (atom names)
      nil
    (cons (cons (car names)
                (let ((entry (assoc-equal (car names) filemap)))
                  (if entry (kvj-sha256-hex (cdr entry)) :not-read)))
          (kvj-digests (cdr names) filemap))))

(defun kvj-unexpected (names filemap)
  (declare (xargs :mode :program))
  (cond ((atom filemap) nil)
        ((member-equal (caar filemap) names) (kvj-unexpected names (cdr filemap)))
        (t (cons (caar filemap) (kvj-unexpected names (cdr filemap))))))

(defun kvj-read-and-pinned (names filemap)
  (declare (xargs :mode :program))
  (let ((extra (kvj-unexpected names filemap)))
    (if extra
        (cons (cons :unexpected extra) (kvj-digests names filemap))
      (kvj-digests names filemap))))

; ---- the corrected translator ---------------------------------------------
; The file is read from the books directory this session takes its library
; from, and its SHA-256 must be the pinned one: the released
; svstmt-compile.lisp with svstack replaced by st.blkst on lines 1103 and 1104
; (../acl2-pilot/nonblocking/svstmt-compile.patch).  ACL2 itself ties the
; certified book it loaded to this source file by the file's length and
; write date.
(defconst *kvj-translator-source* "centaur/sv/vl/svstmt-compile.lisp")

(defconst *kvj-translator-sha256-pinned*
  "99f4a19521edf7aa657744c3865bec70f05ffd4135696b7c04f0dc3a6c46486c")

(defun kvj-translator-sha256 (state)
  (declare (xargs :mode :program :stobjs state))
  (kvj-sha256-hex
   (acl2::read-file-into-string
    (concatenate 'string
                 (cdr (assoc-eq :system (acl2::project-dir-alist (w state))))
                 *kvj-translator-source*))))

(defconsts (*kvj-translator-sha256-as-read* state)
  (mv (kvj-translator-sha256 state) state))

(defthm kv-joined-translator-is-the-corrected-one
  (equal *kvj-translator-sha256-as-read* *kvj-translator-sha256-pinned*)
  :rule-classes nil)

(defconsts (*kvj-acl2-version* state)
  (mv (f-get-global 'acl2::acl2-version state) state))

(defthm kv-joined-acl2-version
  (equal *kvj-acl2-version* "ACL2 Version 8.7")
  :rule-classes nil)

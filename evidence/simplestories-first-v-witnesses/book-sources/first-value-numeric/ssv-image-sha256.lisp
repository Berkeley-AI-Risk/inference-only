; THE IMAGE CONSTANT HAS THE PINNED SHA-256.
;
; Private.  See README.md in this directory.
;
; ACL2 computes, with the community books' SHA-256 (kestrel/crypto/sha-2),
; the digest of the bytes of the image constant of ssv-image -- its 227,062
; words, each as 32 bytes, the lowest first, which is the image file byte
; for byte -- and proves it equal to
;   cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0.
(in-package "ACL2")
(include-book "ssv-image")
(include-book "kestrel/crypto/sha-2/sha-256" :dir :system)
(set-verify-guards-eagerness 0)

; the n lowest bytes of a word, the lowest first
(defun ssv-word-bytes (word n)
  (if (zp n)
      nil
    (cons (mod (nfix word) 256)
          (ssv-word-bytes (floor (nfix word) 256) (- n 1)))))
; the bytes of a list of 256-bit words
(defun ssv-image-bytes (words)
  (if (endp words)
      nil
    (append (ssv-word-bytes (car words) 32)
            (ssv-image-bytes (cdr words)))))
(defun ssv-image-sha256 ()
  (sha2::sha-256-bytes (ssv-image-bytes (ssv-image))))

(defthm ssv-image-has-the-pinned-sha256
  (equal (ssv-image-sha256)
         '(#xca #xd8 #xd0 #x15 #xdb #x37 #xa3 #x60
           #x3e #x34 #x0e #xdf #xc0 #x00 #x9f #x36
           #xd6 #xb1 #x2d #xe2 #xbc #x78 #x9d #x60
           #x68 #x70 #x11 #xfc #x70 #x0c #xc3 #xb0))
  :hints (("Goal" :in-theory '((:e ssv-image-sha256))))
  :rule-classes nil)

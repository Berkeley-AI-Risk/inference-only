; THE NORMALIZATION ROM HOLDS THE IMAGE'S RMS WEIGHTS.
;
; Private.  See README.md in this directory.
;
; The specification reads the weights of the layer-0 input RMS
; normalization from the model image (word 211800, with exponent and
; multiplier in row 0 of the metadata at word 214248).  The circuit reads
; them from a read-only memory, norm_rom, of 3,328 entries of 34 bits, whose
; contents are one of the bindings of kvn-rom.  Entry i holds, for i < 256,
;     bits [33:26]  the exponent byte
;     bits [25:10]  the multiplier
;     bits  [9:0]   the ten-bit weight of column i
; (the layout the independent CPU check asserts).
;
;   kvn-norm-rom-holds-the-image-rms-weights
;       ACL2 evaluates both: entries 0 .. 255 of the datapath's norm_rom, as
;       bound by kvn-rom, are the image's 256 RMS weights with the image's
;       exponent and multiplier, and the shell's norm_rom has the same
;       contents.
(in-package "SV")
(include-book "kvn-rom")
(include-book "ssv-spec")
(include-book "ssv-image")

; entry i of a read-only memory of `count` entries of `width` bits, entry 0
; in the highest bits
(define kvn-rom-entry (i count width mem) :verify-guards nil
  (loghead width (logtail (* width (- (- count 1) i)) mem)))
; the image's RMS weight of column i, as an entry of the ROM
(define kvn-rms-weight-entry (i image) :verify-guards nil
  (b* ((gamma (acl2::ssv-region image 211800 10))
       (meta (acl2::ssv-region image 214248 8)))
    (logior (ash (loghead 8 (acl2::ssv-meta-exponent meta 0)) 26)
            (ash (acl2::ssv-meta-multiplier meta 0) 10)
            (acl2::ssv-bits gamma (* 10 i) 10))))
; entries i .. 255 are the image's
(define kvn-norm-rom-matches-from (i mem image) :verify-guards nil
  :measure (nfix (- 256 (nfix i)))
  (or (zp (- 256 (nfix i)))
      (and (equal (kvn-rom-entry (nfix i) 3328 34 mem)
                  (kvn-rms-weight-entry (nfix i) image))
           (kvn-norm-rom-matches-from (+ 1 (nfix i)) mem image))))
(define kvn-norm-rom-of-the-datapath (rom) :verify-guards nil
  (cdr (assoc-equal '(:var ("u_machine" "u_six_layers" "u_datapath" "u_rmsnorm" "u_norm_rom" . "norm_rom") . 0)
                    rom)))
(define kvn-norm-rom-of-the-shell (rom) :verify-guards nil
  (cdr (assoc-equal '(:var ("u_machine" "u_token_shell" "u_final_rmsnorm" "u_norm_rom" . "norm_rom") . 0)
                    rom)))
(define kvn-norm-rom-checked () :verify-guards nil
  (and (natp (kvn-norm-rom-of-the-datapath (kvn-rom)))
       (kvn-norm-rom-matches-from 0 (kvn-norm-rom-of-the-datapath (kvn-rom)) (acl2::ssv-image))
       (equal (kvn-norm-rom-of-the-shell (kvn-rom))
              (kvn-norm-rom-of-the-datapath (kvn-rom))))
  ///
  (in-theory (disable (:e kvn-norm-rom-checked))))

(defthm kvn-norm-rom-checked-is-true
  (kvn-norm-rom-checked)
  :hints (("Goal" :in-theory '((:e kvn-norm-rom-checked))))
  :rule-classes nil)
(defthm kvn-norm-rom-holds-the-image-rms-weights
  (and (natp (kvn-norm-rom-of-the-datapath (kvn-rom)))
       (kvn-norm-rom-matches-from 0 (kvn-norm-rom-of-the-datapath (kvn-rom)) (acl2::ssv-image))
       (equal (kvn-norm-rom-of-the-shell (kvn-rom))
              (kvn-norm-rom-of-the-datapath (kvn-rom))))
  :hints (("Goal" :use ((:instance kvn-norm-rom-checked-is-true))
           :in-theory '(kvn-norm-rom-checked)))
  :rule-classes nil)

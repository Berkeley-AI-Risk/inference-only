; WHERE THE THREE STAGES OF THE SPECIFICATION ARE IN THE CIRCUIT.
;
; Private.  See README.md in this directory.
;
; Definitions for stating, on an execution, that the datapath's working
; state holds the specification's intermediate vectors when the request for
; the V projection stage is accepted:
;
;   the hidden-state memory and hidden_exponent_q      the token's embedding
;   the RMS scratch memory and rms_exponent_q          its input RMS normalization
;   the V results accepted afterwards                  the value projection of that
;
; kvn-stage-statement is the conjunction.  The token books prove it for one
; execution; nothing here proves it in general.
(in-package "SV")
(include-book "kvn-witness")

; Cells c .. count-1 of a working memory of `count` sixteen-bit cells, cell 0
; in the highest bits, each read as a two's-complement number.
(define kvn-cells-from (c count mem) :verify-guards nil
  :measure (nfix (- (nfix count) (nfix c)))
  (if (zp (- (nfix count) (nfix c)))
      nil
    (cons (logext 16 (logtail (* 16 (- (- (nfix count) 1) (nfix c))) mem))
          (kvn-cells-from (+ 1 (nfix c)) count mem))))
; the final V results with index c .. 127, each read so
(define kvn-final-results-from (c log) :verify-guards nil
  :measure (nfix (- 128 (nfix c)))
  (if (zp (- 128 (nfix c)))
      nil
    (cons (logext 16 (kv-final-result (nfix c) log))
          (kvn-final-results-from (+ 1 (nfix c)) log))))

(define kvn-stage-statement (token n envs outs image) :verify-guards nil
  (b* ((j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       ;; the cycle of the accepted request for the V projection stage
       (v-request (kv-stage-request-cycle 3 b outs))
       (then (nth v-request outs))
       (values (kv-value-results b outs))
       (embedding (acl2::ssv-embedding token image))
       (activation (acl2::ssv-rms-norm embedding image))
       (v (acl2::ssv-v-projection activation image)))
    (and (natp v-request)
         ;; the layer's input is the token's embedding
         (equal (kvn-cells-from
                 0 256
                 (sig "u_machine.u_six_layers.u_datapath.u_hidden_state.payload_mem" 4096 then))
                (cdr embedding))
         (equal (logext 8 (sig "u_machine.u_six_layers.u_datapath.hidden_exponent_q" 8 then))
                (car embedding))
         ;; the projection's input is its RMS normalization
         (equal (kvn-cells-from
                 0 256
                 (sig "u_machine.u_six_layers.u_datapath.u_rms_scratch.payload_mem" 4096 then))
                (cdr activation))
         (equal (logext 8 (sig "u_machine.u_six_layers.u_datapath.rms_exponent_q" 8 then))
                (car activation))
         ;; the V results are the value projection of that
         (equal (kvn-final-results-from 0 values) (cdr v))
         (equal (logext 8 (kv-final-exponent values)) (car v)))))

; ---------------------------------------------------------------------------
; The stage statement gives the equation about the V results: the three
; stages compose to the specification's V vector.
; ---------------------------------------------------------------------------
(local
 (defthm kvn-first-final-result
   (equal (car (kvn-final-results-from 0 log))
          (logext 16 (kv-final-result 0 log)))
   :hints (("Goal" :expand ((kvn-final-results-from 0 log))))))
(local
 (defthm kvn-first-of-equal-lists
   (implies (equal x y) (equal (car x) (car y)))
   :rule-classes nil))
(defthm kvn-stage-statement-gives-the-value-claim
  (b* ((j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (values (kv-value-results b outs)))
    (implies (kvn-stage-statement token n envs outs image)
             (kvn-value-claim token image values)))
  :hints (("Goal"
           :use ((:instance kvn-first-of-equal-lists
                            (x (kvn-final-results-from
                                0 (kv-value-results
                                   (kv-staging-begin (kv-record-start n outs) envs outs)
                                   outs)))
                            (y (cdr (acl2::ssv-v-projection
                                     (acl2::ssv-rms-norm (acl2::ssv-embedding token image) image)
                                     image)))))
           :in-theory (e/d (kvn-stage-statement kvn-value-claim
                            acl2::ssv-v-mantissa acl2::ssv-v-exponent acl2::ssv-v-vector)
                           (acl2::ssv-v-projection acl2::ssv-rms-norm acl2::ssv-embedding
                            kvn-final-results-from kv-final-result kv-final-exponent))))
  :rule-classes nil)

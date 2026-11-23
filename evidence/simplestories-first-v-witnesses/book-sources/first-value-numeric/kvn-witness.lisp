; THE STATEMENT ABOUT ONE EXECUTION WITH AN ORDINARY STEP.
;
; Private.  See README.md in this directory.
;
; Definitions only (and the lemmas that two helpers change no value).  The
; token books prove the statement, by evaluation, for the execution of one
; token.
;
;   kvn-env, kvn-envs       a cycle's inputs from eight numbers and the
;                           read-only memories' contents
;   kvn-zero-state          the machine's state with every stored variable 0
;   kvn-model-memory-ok     the contract on the raw memory port: the memory
;                           behind it holds the model image
;   kvn-roms-bound          the read-only memories hold the pinned contents
;   kvn-position-0-token    the token appended first after the last reset or
;                           CLEAR before a STEP
;   kvn-ordinary-step-statement
;                           THE STATEMENT
(in-package "SV")
(include-book "kvn-record-value")

; ---------------------------------------------------------------------------
; Inputs.  A tuple is
;   (reset_n append_valid step_valid req_ready rsp_valid rsp_data clear token).
; The other public inputs are constant: the model is locked, the token
; output is always taken, and no fault or response error is signalled.  The
; six memory variables are bound to `rom` in every cycle.
; ---------------------------------------------------------------------------
(define kvn-env (tuple rom) :verify-guards nil
  (list* (cons "reset_n_i" (nth 0 tuple))
         (cons "private_model_locked_i" 1)
         (cons "clear_i" (nth 6 tuple))
         (cons "append_valid_i" (nth 1 tuple))
         (cons "append_token_i" (nth 7 tuple))
         (cons "step_valid_i" (nth 2 tuple))
         (cons "token_ready_i" 1)
         (cons "private_endpoint_upstream_fault_i" 0)
         (cons "private_endpoint_req_ready_i" (nth 3 tuple))
         (cons "private_endpoint_rsp_valid_i" (nth 4 tuple))
         (cons "private_endpoint_rsp_data_i" (nth 5 tuple))
         (cons "private_endpoint_rsp_error_i" 0)
         rom))
(define kvn-envs (tuples rom) :verify-guards nil
  (if (atom tuples)
      nil
    (cons (kvn-env (car tuples) rom)
          (kvn-envs (cdr tuples) rom))))

; every stored variable of the machine 0
(define kvn-zero-state () :verify-guards nil
  (b* ((keys (svex-alist-keys (fsm->nextstate (probe-fsm-held)))))
    (pairlis$ keys (replicate (len keys) 0))))

; ---------------------------------------------------------------------------
; THE MODEL MEMORY.  Behind the probe's raw word port (private_endpoint_*)
; is a memory of 256-bit words that holds the model image at its word
; addresses and 0 above it.  A request is accepted in a cycle in which
; req_valid_o and req_ready_i are both 1.  An accepted write stores its data.
; An accepted read is answered with the word the memory holds when the read
; is accepted; the answers come in the order of the reads, each in a later
; cycle, and whenever an answer is offered (rsp_valid_i = 1) it is that word
; and no error is signalled.
;
; `queue` holds the words owed to the accepted reads not yet answered, the
; oldest first; `written` the accepted writes, the latest first.
; ---------------------------------------------------------------------------
(define kvn-memory-word (addr written image) :verify-guards nil
  (b* ((look (hons-assoc-equal addr written)))
    (if look (cdr look) (nfix (nth addr image)))))
(define kvn-memory-ok-from (envs outs queue written image) :verify-guards nil
  :measure (len envs)
  (b* (((when (atom envs)) t)
       (env (car envs))
       (out (car outs))
       (req-valid (sig "private_endpoint_req_valid_o" 1 out))
       (req-ready (sig "private_endpoint_req_ready_i" 1 env))
       (req-write (sig "private_endpoint_req_write_o" 1 out))
       (req-addr (sig "private_endpoint_req_word_address_o" 19 out))
       (req-data (sig "private_endpoint_req_write_data_o" 256 out))
       (rsp-valid (sig "private_endpoint_rsp_valid_i" 1 env))
       (rsp-ready (sig "private_endpoint_rsp_ready_o" 1 out))
       (rsp-data (sig "private_endpoint_rsp_data_i" 256 env))
       (rsp-error (sig "private_endpoint_rsp_error_i" 1 env))
       ((unless (or (equal rsp-valid 0)
                    (and (equal rsp-valid 1)
                         (consp queue)
                         (equal rsp-data (car queue))
                         (equal rsp-error 0))))
        nil)
       (queue (if (and (equal rsp-valid 1) (equal rsp-ready 1)) (cdr queue) queue))
       (accepted (and (equal req-valid 1) (equal req-ready 1)))
       ((unless (or (not accepted) (equal req-write 0) (equal req-write 1)))
        nil)
       (queue (if (and accepted (equal req-write 0))
                  (append queue (list (kvn-memory-word req-addr written image)))
                queue))
       (written (if (and accepted (equal req-write 1))
                    (cons (cons req-addr req-data) written)
                  written)))
    (kvn-memory-ok-from (cdr envs) (cdr outs) queue written image)))
(define kvn-model-memory-ok (image envs outs) :verify-guards nil
  (kvn-memory-ok-from envs outs nil nil image))

; ---------------------------------------------------------------------------
; THE READ-ONLY MEMORIES.  The translator drops the RTL's `initial` blocks,
; so the contents of the five read-only memories and of the exponent
; table's endpoint word are free variables of the model.  In every cycle
; each is bound to the contents the RTL loads.
; ---------------------------------------------------------------------------
(define kvn-rom-bound (rom env) :verify-guards nil
  (or (atom rom)
      (and (equal (svex-env-lookup (car (car rom)) env) (cdr (car rom)))
           (kvn-rom-bound (cdr rom) env))))
(define kvn-roms-bound (rom envs) :verify-guards nil
  (or (atom envs)
      (and (kvn-rom-bound rom (car envs))
           (kvn-roms-bound rom (cdr envs)))))

; ---------------------------------------------------------------------------
; THE TOKEN OF POSITION 0.  The shell keeps the appended tokens on a tape
; that a reset or a CLEAR empties; position 0 is the tape's first entry.  So
; the token of position 0 at a STEP accepted in cycle s is the token of the
; first APPEND accepted after the last cycle before s that asserts reset or
; CLEAR.  (This reading of the shell is used to name the token; nothing here
; proves it about the tape.)
; ---------------------------------------------------------------------------
; the last cycle below k that asserts reset or CLEAR; nil if there is none
(define kvn-last-restart (k envs) :verify-guards nil
  (b* (((when (zp k)) nil)
       (env (nth (- k 1) envs))
       ((when (or (equal (sig "reset_n_i" 1 env) 0)
                  (equal (sig "clear_i" 1 env) 1)))
        (- k 1)))
    (kvn-last-restart (- k 1) envs)))
; the first cycle in a .. s-1 with an accepted APPEND; nil if there is none
(define kvn-first-append (a s envs outs) :verify-guards nil
  :measure (nfix (- (nfix s) (nfix a)))
  (cond ((zp (- (nfix s) (nfix a))) nil)
        ((kv-append-accepted-at (nfix a) envs outs) (nfix a))
        (t (kvn-first-append (+ 1 (nfix a)) s envs outs))))
(define kvn-position-0-token (s envs outs) :verify-guards nil
  (b* ((c (kvn-last-restart s envs))
       (a (kvn-first-append (if c (+ 1 c) 0) s envs outs)))
    (and a (sig "append_token_i" 12 (nth a envs)))))

; ---------------------------------------------------------------------------
; The record's V words against a list of mantissas.
; ---------------------------------------------------------------------------
(define kvn-record-v-list (c writes) :verify-guards nil
  :measure (nfix (- 128 (nfix c)))
  (if (zp (- 128 (nfix c)))
      nil
    (cons (kvn-record-v (nfix c) writes)
          (kvn-record-v-list (+ 1 (nfix c)) writes))))

; ---------------------------------------------------------------------------
; THE STATEMENT, for a token, the cycle n at which the record is reported
; complete, the inputs, the start state, the execution, the image and the
; read-only memories' contents.
; ---------------------------------------------------------------------------
(define kvn-ordinary-step-statement (token n envs initst outs image rom) :verify-guards nil
  (b* ((r 0)
       (j (kv-record-start n outs))
       (b (kv-staging-begin j envs outs))
       (s (kv-step-cycle b envs outs))
       (values (kv-value-results b outs))
       (writes (kv-endpoint-writes j (+ 1 n) envs outs)))
    (and ;; (1) the clock, reset and input contract of the held-input model
         (kvh-reset-state-p initst)
         (consp envs)
         (kvh-reset-input-p (car envs))
         (kvh-legal-history-p envs outs)
         ;; (2) the hypotheses of the K/V record theorem, layer 0, position 0
         (natp n) (<= (+ 2 r) n)
         (kv-reset-held-at-evaluable r envs outs)
         (kv-payload-storage-definite-at (+ 2 r) envs outs)
         (kv-producer-storage-definite-at (+ 2 r) outs)
         (kv-environment-ok-from-evaluable (+ 2 r) (+ 1 n) envs outs)
         (kv-producer-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
         (kv-shell-signals-ok-from (+ 2 r) (+ 1 n) envs outs)
         (kv-record-reported-complete-at n outs)
         (equal (kv-staged-layer b outs) 0)
         (equal (kv-staged-position b outs) 0)
         ;; (3) the model memory and the read-only memories
         (kvn-model-memory-ok image envs outs)
         (kvn-roms-bound rom envs)
         ;; (4) the accepted STEP and its token
         (kv-step-accepted-at s envs outs)
         (equal (kvn-position-0-token s envs outs) token)
         (acl2::ssv-profile-ok token image)
         ;; (5) the record's value words are the specification's
         (equal (len writes) 18)
         (equal (kvn-write-address 9 writes) 227081)
         (equal (kvn-write-address 17 writes) 227089)
         (equal (kvn-record-v0 writes) (acl2::ssv-v-mantissa 0 token image))
         (equal (kvn-record-v-exponent writes) (acl2::ssv-v-exponent token image))
         ;; and so are all 128 V mantissas of the record
         (equal (kvn-record-v-list 0 writes) (cdr (acl2::ssv-v-vector token image)))
         ;; (6) the same about the producer's V results
         (kvn-value-claim token image values))))

; ---------------------------------------------------------------------------
; Two helpers for evaluating the statement.  Neither changes a value.
; ---------------------------------------------------------------------------
; The execution with every cycle's signals in a fast alist.
(define kvn-fast-all (x) :verify-guards nil
  (if (atom x)
      x
    (cons (make-fast-alist (car x)) (kvn-fast-all (cdr x)))))
(defthm kvn-fast-all-is-identity
  (equal (kvn-fast-all x) x)
  :hints (("Goal" :in-theory (enable kvn-fast-all))))
; (svex-envlist-p x), asked about the tails of x from the last to the first.
; The token books have ACL2 remember that function's answers; asking in this
; order, each question finds the answer for the next tail already there.
(define kvn-tails-rev (x acc) :verify-guards nil
  (if (atom x) (cons x acc) (kvn-tails-rev (cdr x) (cons x acc))))
(define kvn-warm-tails (tails) :verify-guards nil
  (if (atom tails)
      t
    (and (svex-envlist-p (car tails))
         (kvn-warm-tails (cdr tails)))))
(define kvn-envlist-ok (x) :verify-guards nil
  (kvn-warm-tails (kvn-tails-rev x nil)))

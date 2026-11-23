; The invariant, the environment's conditions and the clause, as predicates on numbers.
;
; Private.  Part of the joined K/V book; see README.md in this directory.
; Written by make_book.py from the pilot's proof (../acl2-pilot/joined);
; edit that script, not this file.
;
; Nothing here mentions the design.  joint-inv-p is the invariant; its
; arguments are the values of 194 named signals, in the order of
; ../acl2-pilot/joined/joint_signals_reads.py.
(in-package "SV")
(include-book "centaur/sv/svtv/svtv-to-fsm-defs" :dir :system)

; ===========================================================================
; The statements.
; ===========================================================================

; The K/V controller's invariant proper: it is in one of its fourteen defined
; states and has no fault latched.
(define kv-state-p (s) :verify-guards nil
  (and (natp s) (<= s 13)))
(define kv-good-p (s fault) :verify-guards nil
  (and (kv-state-p s) (equal fault 0)))

; 4-bit Gray code and its inverse; the position of index i counted from
; pointer p around a ring of eight; the mask with the n lowest bits set.
(define gray4 (b) :verify-guards nil
  (logand 15 (logxor b (ash b -1))))
(define ungray4 (g) :verify-guards nil
  (logand 15 (logxor g (logxor (ash g -1) (logxor (ash g -2) (ash g -3))))))
(define off8 (i p) :verify-guards nil
  (logand 7 (- i p)))
(define low-ones (n) :verify-guards nil
  (case n (0 0) (1 1) (2 3) (3 7) (4 15) (5 31) (6 63) (7 127) (8 255)
    (otherwise 511)))

; What the controller is doing, read off its state register:
;   it is collecting a row from DDR (READ_REQ or READ_WAIT);
(define kv-collecting (s) :verify-guards nil
  (or (equal s 5) (equal s 6)))
;   the kind of request it is waiting for: 1 a write (WRITE_WAIT), 2 reads,
;   0 nothing;
(define kv-kind (s) :verify-guards nil
  (cond ((equal s 3) 1) ((equal s 5) 2) ((equal s 6) 2) (t 0)))
;   how many requests it has in flight, given its count of outstanding reads;
(define kv-in-flight (s outstanding) :verify-guards nil
  (cond ((equal s 3) 1) ((equal s 5) outstanding) ((equal s 6) outstanding)
        (t 0)))
;   whether it has seen a CLEAR while waiting.
(define kv-aborted (s write-aborted read-aborted) :verify-guards nil
  (if (equal s 3) write-aborted read-aborted))

; Answering from the one-row cache (state CACHE_READ): the cached row is the
; one asked for, of the current epoch.
(define kv-cache-read-p (valid kind copy-kind layer rsp-layer position
                         rsp-position tag-epoch epoch rsp-kind read-epoch)
  :verify-guards nil
  (and (equal valid 1)
       (equal kind copy-kind)
       (equal layer rsp-layer)
       (equal position rsp-position)
       (equal tag-epoch epoch)
       (or (not (equal rsp-kind 0)) (equal read-epoch epoch))))

; Collecting a row from DDR with no CLEAR seen: the nine words are issued in
; order, the returns are counted, and each return has been recorded.
(define kv-collect-p (s done word return-word outstanding mask read-epoch epoch)
  :verify-guards nil
  (b* ((issued (if (equal done 1) 9 word))
       (returned (- issued outstanding)))
    (and (if (equal s 6) (equal done 1) (equal done 0))
         (or (equal done 0) (equal word 8))
         (<= outstanding issued)
         (equal mask (low-ones returned))
         (if (< returned 8)
             (equal return-word returned)
           (equal return-word 8))
         (equal read-epoch epoch))))

; One async FIFO of depth eight.
;   wb, rb       write and read pointers (binary); wg, rg their Gray copies
;   ws1, ws2     the write pointer as synchronised into the read side
;   rs1, rs2     the read pointer as synchronised into the write side
;   mv           the output register holds the entry at the read pointer
;   sf spf df st sticky faults and the stall flag: all low
;   la           1 for the FIFO built with output lookahead (the response FIFO)
; It holds c entries.  Of those, o1 and then o2 have reached the first and the
; second synchroniser stage on the read side.  p1 and p2 count the entries
; taken that the two stages on the write side have not yet seen.
(define fifo-inv-p (la wb wg rb rg rs1 rs2 ws1 ws2 mv sf spf df st)
  :verify-guards nil
  (b* ((c (logand 15 (- wb rb)))
       (o1 (logand 15 (- (ungray4 ws1) rb)))
       (o2 (logand 15 (- (ungray4 ws2) rb)))
       (p1 (logand 15 (- rb (ungray4 rs1))))
       (p2 (logand 15 (- rb (ungray4 rs2)))))
    (and (equal wg (gray4 wb)) (equal rg (gray4 rb))
         (equal sf 0) (equal spf 0) (equal df 0) (equal st 0)
         (<= c 8)
         (<= o2 o1) (<= o1 c) (<= o1 (+ 1 o2)) (<= c (+ 1 o1))
         (or (equal mv 0) (<= 1 o2))
         (<= p1 1) (<= p1 p2) (<= p2 (+ 1 p1))
         (if (equal la 1)
             ; its reader takes an entry on every cycle it is shown one, so
             ; at most two visible entries are ever waiting
             (and (<= o2 2) (or (equal mv 1) (<= o2 1)))
           ; without lookahead the output register empties after each take
           (and (<= p2 1) (or (equal p1 0) (equal mv 0)))))))

; The control bits of one request in flight, wherever it is.  kind is what
; the controller is waiting for (1 a write, 2 a read); epoch is the
; boundary's current epoch; pend says the boundary has a CLEAR pending.
;   in the request FIFO: {kind[1:0], epoch}
(define req-entry-p (e kind epoch pend) :verify-guards nil
  (and (equal (ash e -1) kind)
       (or (equal pend 1) (equal (logand 1 e) epoch))))
;   in the response FIFO: {kind[1:0], epoch, fault}
(define rsp-entry-p (e kind epoch pend) :verify-guards nil
  (and (equal (ash e -2) kind)
       (equal (logand 1 e) 0)
       (or (equal pend 1) (equal (logand 1 (ash e -1)) epoch))))
;   in the app-side slot at position off from the head, where r slots are
;   reserved and the first nd of them are done
(define slot-p (off r nd skind sepoch sreject sdone sfault kind epoch pend)
  :verify-guards nil
  (or (<= r off)
      (and (equal skind kind) (equal sreject 0) (equal sfault 0)
           (or (equal pend 1) (equal sepoch epoch))
           (if (< off nd) (equal sdone 1) (equal sdone 0)))))

; Every register of the boundary that its local reset clears is zero.
(define joint-boundary-zero-p
  (   b-lock-meta b-lock-sync b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync
   b-fault b-lock-seen b-clr-seen b-clr-pend b-clr-drained b-epoch b-out
   b-mstall b-wstall b-wstallf b-rstall q-wb q-wg q-full q-rb q-rg q-rs1
   q-rs2 q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md s-wb s-wg s-full s-rb
   s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df s-st s-md q-mdw a-fault
   a-lock-seen a-offer a-offer-write a-poison a-offer-slot a-reserved
   a-unissued a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
   a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1
   a-epoch2 a-epoch3 a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1
   a-reject2 a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0
   a-done1 a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
   a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7
   a-word0 a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7)
  :verify-guards nil
  (and
       (equal b-lock-meta 0)
       (equal b-lock-sync 0)
       (equal b-afc-meta 0)
       (equal b-afc-sync 0)
       (equal b-cfa-meta 0)
       (equal b-cfa-sync 0)
       (equal b-fault 0)
       (equal b-lock-seen 0)
       (equal b-clr-seen 0)
       (equal b-clr-pend 0)
       (equal b-clr-drained 0)
       (equal b-epoch 0)
       (equal b-out 0)
       (equal b-mstall 0)
       (equal b-wstall 0)
       (equal b-wstallf 0)
       (equal b-rstall 0)
       (equal q-wb 0)
       (equal q-wg 0)
       (equal q-full 0)
       (equal q-rb 0)
       (equal q-rg 0)
       (equal q-rs1 0)
       (equal q-rs2 0)
       (equal q-ws1 0)
       (equal q-ws2 0)
       (equal q-mv 0)
       (equal q-sf 0)
       (equal q-spf 0)
       (equal q-df 0)
       (equal q-st 0)
       (equal q-md 0)
       (equal s-wb 0)
       (equal s-wg 0)
       (equal s-full 0)
       (equal s-rb 0)
       (equal s-rg 0)
       (equal s-rs1 0)
       (equal s-rs2 0)
       (equal s-ws1 0)
       (equal s-ws2 0)
       (equal s-mv 0)
       (equal s-sf 0)
       (equal s-spf 0)
       (equal s-df 0)
       (equal s-st 0)
       (equal s-md 0)
       (equal q-mdw 0)
       (equal a-fault 0)
       (equal a-lock-seen 0)
       (equal a-offer 0)
       (equal a-offer-write 0)
       (equal a-poison 0)
       (equal a-offer-slot 0)
       (equal a-reserved 0)
       (equal a-unissued 0)
       (equal a-readcount 0)
       (equal a-head 0)
       (equal a-tail 0)
       (equal a-issue 0)
       (equal a-rhead 0)
       (equal a-rtail 0)
       (equal a-kind0 0)
       (equal a-kind1 0)
       (equal a-kind2 0)
       (equal a-kind3 0)
       (equal a-kind4 0)
       (equal a-kind5 0)
       (equal a-kind6 0)
       (equal a-kind7 0)
       (equal a-epoch0 0)
       (equal a-epoch1 0)
       (equal a-epoch2 0)
       (equal a-epoch3 0)
       (equal a-epoch4 0)
       (equal a-epoch5 0)
       (equal a-epoch6 0)
       (equal a-epoch7 0)
       (equal a-reject0 0)
       (equal a-reject1 0)
       (equal a-reject2 0)
       (equal a-reject3 0)
       (equal a-reject4 0)
       (equal a-reject5 0)
       (equal a-reject6 0)
       (equal a-reject7 0)
       (equal a-done0 0)
       (equal a-done1 0)
       (equal a-done2 0)
       (equal a-done3 0)
       (equal a-done4 0)
       (equal a-done5 0)
       (equal a-done6 0)
       (equal a-done7 0)
       (equal a-sfault0 0)
       (equal a-sfault1 0)
       (equal a-sfault2 0)
       (equal a-sfault3 0)
       (equal a-sfault4 0)
       (equal a-sfault5 0)
       (equal a-sfault6 0)
       (equal a-sfault7 0)
       (equal a-word0 0)
       (equal a-word1 0)
       (equal a-word2 0)
       (equal a-word3 0)
       (equal a-word4 0)
       (equal a-word5 0)
       (equal a-word6 0)
       (equal a-word7 0)))

; THE JOINT INVARIANT.
(define joint-inv-p
  (   p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q k-pending-issued-q
   k-pending-returned-q k-pending-read-pending-q k-committed-prefix-q
   k-pending-layer-q k-pending-position-q k-pending-key-exponents-q
   k-pending-value-exponents-q k-expected-coordinate-q k-pending-persisted-q
   k-write-head-q k-write-word-q k-write-aborted-q k-response-kind-q
   k-response-head-q k-response-layer-q k-response-position-q
   k-response-fault-q k-response-from-pending-q k-read-word-q
   k-read-return-word-q k-read-outstanding-q k-read-issue-done-q
   k-read-aborted-q k-read-physical-kind-q k-read-epoch-q
   k-read-received-mask-q k-cache-valid-q k-cache-kind-q k-cache-layer-q
   k-cache-position-q k-cache-tag-epoch-q k-cache-epoch-q
   k-cache-clear-seen-q k-cache-issued-q k-cache-returned-q
   k-cache-read-pending-q k-cache-copy-kind-q k-lock-seen-q k-fault-q
   k-stage-begin-consumed-q k-stage-payload-consumed-q k-commit-consumed-q
   k-attention-req-consumed-q b-crel b-arel b-lock-meta b-lock-sync
   b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
   b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall b-wstallf
   b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2 q-mv q-sf
   q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3 q-mem4 q-mem5 q-mem6
   q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf
   s-df s-st s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6 s-mem7
   q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4 q-memw5 q-memw6 q-memw7
   a-fault a-lock-seen a-offer a-offer-write a-poison a-offer-slot a-reserved
   a-unissued a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
   a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1
   a-epoch2 a-epoch3 a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1
   a-reject2 a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0
   a-done1 a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
   a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7
   a-word0 a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0
   a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6 a-rslot7)
  :verify-guards nil
  :ignore-ok t
  :irrelevant-formals-ok t
  :normalize nil
  (b* (; Read each signal as a number.  For a two-valued signal, which is all
       ; this predicate is ever asserted of, 4vec->upper is the identity; it
       ; is here only so the proof engine can do arithmetic on signal values.
       (p-lock-meta (4vec->upper p-lock-meta))
       (p-lock-sync (4vec->upper p-lock-sync))
       (p-cfb (4vec->upper p-cfb))
       (p-apprel (4vec->upper p-apprel))
       (m-rel (4vec->upper m-rel))
       (k-state-q (4vec->upper k-state-q))
       (k-pending-issued-q (4vec->upper k-pending-issued-q))
       (k-pending-returned-q (4vec->upper k-pending-returned-q))
       (k-pending-read-pending-q (4vec->upper k-pending-read-pending-q))
       (k-committed-prefix-q (4vec->upper k-committed-prefix-q))
       (k-pending-layer-q (4vec->upper k-pending-layer-q))
       (k-pending-position-q (4vec->upper k-pending-position-q))
       (k-pending-key-exponents-q (4vec->upper k-pending-key-exponents-q))
       (k-pending-value-exponents-q (4vec->upper k-pending-value-exponents-q))
       (k-expected-coordinate-q (4vec->upper k-expected-coordinate-q))
       (k-pending-persisted-q (4vec->upper k-pending-persisted-q))
       (k-write-head-q (4vec->upper k-write-head-q))
       (k-write-word-q (4vec->upper k-write-word-q))
       (k-write-aborted-q (4vec->upper k-write-aborted-q))
       (k-response-kind-q (4vec->upper k-response-kind-q))
       (k-response-head-q (4vec->upper k-response-head-q))
       (k-response-layer-q (4vec->upper k-response-layer-q))
       (k-response-position-q (4vec->upper k-response-position-q))
       (k-response-fault-q (4vec->upper k-response-fault-q))
       (k-response-from-pending-q (4vec->upper k-response-from-pending-q))
       (k-read-word-q (4vec->upper k-read-word-q))
       (k-read-return-word-q (4vec->upper k-read-return-word-q))
       (k-read-outstanding-q (4vec->upper k-read-outstanding-q))
       (k-read-issue-done-q (4vec->upper k-read-issue-done-q))
       (k-read-aborted-q (4vec->upper k-read-aborted-q))
       (k-read-physical-kind-q (4vec->upper k-read-physical-kind-q))
       (k-read-epoch-q (4vec->upper k-read-epoch-q))
       (k-read-received-mask-q (4vec->upper k-read-received-mask-q))
       (k-cache-valid-q (4vec->upper k-cache-valid-q))
       (k-cache-kind-q (4vec->upper k-cache-kind-q))
       (k-cache-layer-q (4vec->upper k-cache-layer-q))
       (k-cache-position-q (4vec->upper k-cache-position-q))
       (k-cache-tag-epoch-q (4vec->upper k-cache-tag-epoch-q))
       (k-cache-epoch-q (4vec->upper k-cache-epoch-q))
       (k-cache-clear-seen-q (4vec->upper k-cache-clear-seen-q))
       (k-cache-issued-q (4vec->upper k-cache-issued-q))
       (k-cache-returned-q (4vec->upper k-cache-returned-q))
       (k-cache-read-pending-q (4vec->upper k-cache-read-pending-q))
       (k-cache-copy-kind-q (4vec->upper k-cache-copy-kind-q))
       (k-lock-seen-q (4vec->upper k-lock-seen-q))
       (k-fault-q (4vec->upper k-fault-q))
       (k-stage-begin-consumed-q (4vec->upper k-stage-begin-consumed-q))
       (k-stage-payload-consumed-q (4vec->upper k-stage-payload-consumed-q))
       (k-commit-consumed-q (4vec->upper k-commit-consumed-q))
       (k-attention-req-consumed-q (4vec->upper k-attention-req-consumed-q))
       (b-crel (4vec->upper b-crel))
       (b-arel (4vec->upper b-arel))
       (b-lock-meta (4vec->upper b-lock-meta))
       (b-lock-sync (4vec->upper b-lock-sync))
       (b-afc-meta (4vec->upper b-afc-meta))
       (b-afc-sync (4vec->upper b-afc-sync))
       (b-cfa-meta (4vec->upper b-cfa-meta))
       (b-cfa-sync (4vec->upper b-cfa-sync))
       (b-fault (4vec->upper b-fault))
       (b-lock-seen (4vec->upper b-lock-seen))
       (b-clr-seen (4vec->upper b-clr-seen))
       (b-clr-pend (4vec->upper b-clr-pend))
       (b-clr-drained (4vec->upper b-clr-drained))
       (b-epoch (4vec->upper b-epoch))
       (b-out (4vec->upper b-out))
       (b-mstall (4vec->upper b-mstall))
       (b-wstall (4vec->upper b-wstall))
       (b-wstallf (4vec->upper b-wstallf))
       (b-rstall (4vec->upper b-rstall))
       (q-wb (4vec->upper q-wb))
       (q-wg (4vec->upper q-wg))
       (q-full (4vec->upper q-full))
       (q-rb (4vec->upper q-rb))
       (q-rg (4vec->upper q-rg))
       (q-rs1 (4vec->upper q-rs1))
       (q-rs2 (4vec->upper q-rs2))
       (q-ws1 (4vec->upper q-ws1))
       (q-ws2 (4vec->upper q-ws2))
       (q-mv (4vec->upper q-mv))
       (q-sf (4vec->upper q-sf))
       (q-spf (4vec->upper q-spf))
       (q-df (4vec->upper q-df))
       (q-st (4vec->upper q-st))
       (q-md (4vec->upper q-md))
       (q-mem0 (4vec->upper q-mem0))
       (q-mem1 (4vec->upper q-mem1))
       (q-mem2 (4vec->upper q-mem2))
       (q-mem3 (4vec->upper q-mem3))
       (q-mem4 (4vec->upper q-mem4))
       (q-mem5 (4vec->upper q-mem5))
       (q-mem6 (4vec->upper q-mem6))
       (q-mem7 (4vec->upper q-mem7))
       (s-wb (4vec->upper s-wb))
       (s-wg (4vec->upper s-wg))
       (s-full (4vec->upper s-full))
       (s-rb (4vec->upper s-rb))
       (s-rg (4vec->upper s-rg))
       (s-rs1 (4vec->upper s-rs1))
       (s-rs2 (4vec->upper s-rs2))
       (s-ws1 (4vec->upper s-ws1))
       (s-ws2 (4vec->upper s-ws2))
       (s-mv (4vec->upper s-mv))
       (s-sf (4vec->upper s-sf))
       (s-spf (4vec->upper s-spf))
       (s-df (4vec->upper s-df))
       (s-st (4vec->upper s-st))
       (s-md (4vec->upper s-md))
       (s-mem0 (4vec->upper s-mem0))
       (s-mem1 (4vec->upper s-mem1))
       (s-mem2 (4vec->upper s-mem2))
       (s-mem3 (4vec->upper s-mem3))
       (s-mem4 (4vec->upper s-mem4))
       (s-mem5 (4vec->upper s-mem5))
       (s-mem6 (4vec->upper s-mem6))
       (s-mem7 (4vec->upper s-mem7))
       (q-mdw (4vec->upper q-mdw))
       (q-memw0 (4vec->upper q-memw0))
       (q-memw1 (4vec->upper q-memw1))
       (q-memw2 (4vec->upper q-memw2))
       (q-memw3 (4vec->upper q-memw3))
       (q-memw4 (4vec->upper q-memw4))
       (q-memw5 (4vec->upper q-memw5))
       (q-memw6 (4vec->upper q-memw6))
       (q-memw7 (4vec->upper q-memw7))
       (a-fault (4vec->upper a-fault))
       (a-lock-seen (4vec->upper a-lock-seen))
       (a-offer (4vec->upper a-offer))
       (a-offer-write (4vec->upper a-offer-write))
       (a-poison (4vec->upper a-poison))
       (a-offer-slot (4vec->upper a-offer-slot))
       (a-reserved (4vec->upper a-reserved))
       (a-unissued (4vec->upper a-unissued))
       (a-readcount (4vec->upper a-readcount))
       (a-head (4vec->upper a-head))
       (a-tail (4vec->upper a-tail))
       (a-issue (4vec->upper a-issue))
       (a-rhead (4vec->upper a-rhead))
       (a-rtail (4vec->upper a-rtail))
       (a-kind0 (4vec->upper a-kind0))
       (a-kind1 (4vec->upper a-kind1))
       (a-kind2 (4vec->upper a-kind2))
       (a-kind3 (4vec->upper a-kind3))
       (a-kind4 (4vec->upper a-kind4))
       (a-kind5 (4vec->upper a-kind5))
       (a-kind6 (4vec->upper a-kind6))
       (a-kind7 (4vec->upper a-kind7))
       (a-epoch0 (4vec->upper a-epoch0))
       (a-epoch1 (4vec->upper a-epoch1))
       (a-epoch2 (4vec->upper a-epoch2))
       (a-epoch3 (4vec->upper a-epoch3))
       (a-epoch4 (4vec->upper a-epoch4))
       (a-epoch5 (4vec->upper a-epoch5))
       (a-epoch6 (4vec->upper a-epoch6))
       (a-epoch7 (4vec->upper a-epoch7))
       (a-reject0 (4vec->upper a-reject0))
       (a-reject1 (4vec->upper a-reject1))
       (a-reject2 (4vec->upper a-reject2))
       (a-reject3 (4vec->upper a-reject3))
       (a-reject4 (4vec->upper a-reject4))
       (a-reject5 (4vec->upper a-reject5))
       (a-reject6 (4vec->upper a-reject6))
       (a-reject7 (4vec->upper a-reject7))
       (a-done0 (4vec->upper a-done0))
       (a-done1 (4vec->upper a-done1))
       (a-done2 (4vec->upper a-done2))
       (a-done3 (4vec->upper a-done3))
       (a-done4 (4vec->upper a-done4))
       (a-done5 (4vec->upper a-done5))
       (a-done6 (4vec->upper a-done6))
       (a-done7 (4vec->upper a-done7))
       (a-sfault0 (4vec->upper a-sfault0))
       (a-sfault1 (4vec->upper a-sfault1))
       (a-sfault2 (4vec->upper a-sfault2))
       (a-sfault3 (4vec->upper a-sfault3))
       (a-sfault4 (4vec->upper a-sfault4))
       (a-sfault5 (4vec->upper a-sfault5))
       (a-sfault6 (4vec->upper a-sfault6))
       (a-sfault7 (4vec->upper a-sfault7))
       (a-word0 (4vec->upper a-word0))
       (a-word1 (4vec->upper a-word1))
       (a-word2 (4vec->upper a-word2))
       (a-word3 (4vec->upper a-word3))
       (a-word4 (4vec->upper a-word4))
       (a-word5 (4vec->upper a-word5))
       (a-word6 (4vec->upper a-word6))
       (a-word7 (4vec->upper a-word7))
       (a-rslot0 (4vec->upper a-rslot0))
       (a-rslot1 (4vec->upper a-rslot1))
       (a-rslot2 (4vec->upper a-rslot2))
       (a-rslot3 (4vec->upper a-rslot3))
       (a-rslot4 (4vec->upper a-rslot4))
       (a-rslot5 (4vec->upper a-rslot5))
       (a-rslot6 (4vec->upper a-rslot6))
       (a-rslot7 (4vec->upper a-rslot7))
       (oq (logand 15 (- q-wb q-rb)))         ; entries in the request FIFO
       (os (logand 15 (- s-wb s-rb)))         ; entries in the response FIFO
       (qr (logand 7 q-rb))                   ; its read pointer as an index
       (sr (logand 7 s-rb))
       ; entries taken from the request FIFO that the two synchroniser
       ; stages on its write side have not yet seen
       (qp1 (logand 15 (- q-rb (ungray4 q-rs1))))
       (qp2 (logand 15 (- q-rb (ungray4 q-rs2))))
       (local (equal b-crel 7))               ; boundary out of its local reset
       (active (equal m-rel 3))               ; machine core active
       ; the controller is collecting a row from DDR (READ_REQ, READ_WAIT)
       (collect (kv-collecting k-state-q))
       ; what the controller is waiting for: 1 a write, 2 reads, 0 nothing
       (kind (kv-kind k-state-q))
       ; it has seen a CLEAR while waiting
       (aborted (kv-aborted k-state-q k-write-aborted-q k-read-aborted-q))
       ; app-side slots that are done and wait to enter the response FIFO
       (nd (- a-reserved (+ a-unissued a-readcount))))
    (and
     ; ---- the K/V controller: a defined state, no fault latched
     (kv-good-p k-state-q k-fault-q)
     ; ---- its own bookkeeping stays inside what its address mappers accept,
     ;      and the lock it has once seen is still held
     (<= k-write-word-q 8)
     (< k-pending-layer-q 6)
     (< k-pending-position-q 2048)
     (<= k-read-word-q 8)
     (<= k-read-return-word-q 8)
     (<= k-read-outstanding-q 8)
     (< k-response-layer-q 6)
     (< k-response-position-q 2048)
     (or (equal k-lock-seen-q 0) (equal p-lock-sync 1))
     ; ---- answering from the staged row: the row is there
     (or (not (equal k-state-q 13)) (equal k-pending-persisted-q 1))
     ; ---- answering from the one-row cache: the cached row is the one asked
     ;      for, of the current epoch
     (or (not (equal k-state-q 8))
         (kv-cache-read-p k-cache-valid-q k-cache-kind-q k-cache-copy-kind-q
                          k-cache-layer-q k-response-layer-q
                          k-cache-position-q k-response-position-q
                          k-cache-tag-epoch-q k-cache-epoch-q
                          k-response-kind-q k-read-epoch-q))
     ; ---- collecting a row from DDR, no CLEAR seen: the nine words are
     ;      issued in order, the returns counted, and each return recorded
     (or (not collect) (equal k-read-aborted-q 1)
         (kv-collect-p k-state-q k-read-issue-done-q k-read-word-q
                       k-read-return-word-q k-read-outstanding-q
                       k-read-received-mask-q k-read-epoch-q
                       k-cache-epoch-q))
     (or collect (equal k-read-outstanding-q 0))

     ; ---- lock synchroniser and release chains
     (or (equal p-lock-sync 0) (equal p-lock-meta 1))
     (or (equal m-rel 0) (equal m-rel 1) (equal m-rel 3))
     (or (equal m-rel 0) (equal p-lock-sync 1))
     (or active (equal k-state-q 0))          ; inactive core holds the
                                              ; controller in reset
     (equal p-cfb 0)
     (or (equal p-apprel 0) (equal p-apprel 1)
         (equal p-apprel 3) (equal p-apprel 7))
     (equal b-arel b-crel)
     (or (equal b-crel 0) (equal b-crel 1) (equal b-crel 3) (equal b-crel 7))
     (or (equal p-apprel 7) (equal b-crel 0))
     (or local
         (joint-boundary-zero-p
          b-lock-meta b-lock-sync b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync
          b-fault b-lock-seen b-clr-seen b-clr-pend b-clr-drained b-epoch
          b-out b-mstall b-wstall b-wstallf b-rstall q-wb q-wg q-full q-rb
          q-rg q-rs1 q-rs2 q-ws1 q-ws2 q-mv q-sf q-spf q-df q-st q-md s-wb
          s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf s-df
          s-st s-md q-mdw a-fault a-lock-seen a-offer a-offer-write a-poison
          a-offer-slot a-reserved a-unissued a-readcount a-head a-tail
          a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3 a-kind4
          a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2 a-epoch3
          a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2
          a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1
          a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0 a-sfault1
          a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0
          a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7))

     ; ---- the boundary is healthy
     (equal b-fault 0)
     (equal b-afc-meta 0) (equal b-afc-sync 0)
     (equal b-cfa-meta 0) (equal b-cfa-sync 0)
     (equal b-mstall 0) (equal b-wstall 0) (equal b-rstall 0)
     (or (equal b-lock-sync 0) (equal b-lock-meta 1))
     (or (equal b-lock-seen 0) (equal b-lock-sync 1))

     ; ---- both FIFOs: pointers and synchronisers in order, never stalled or
     ;      faulted.  The response FIFO is never full; the request FIFO is
     ;      full only when eight requests are in flight, and then none is
     ;      admitted.
     (fifo-inv-p 0 q-wb q-wg q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2
                 q-mv q-sf q-spf q-df q-st)
     (fifo-inv-p 1 s-wb s-wg s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2
                 s-mv s-sf s-spf s-df s-st)
     (equal s-full 0)
     (or (equal q-full 0) (equal b-out 8))
     ; an entry whose departure the request FIFO's write side has not yet
     ; seen is still waiting, unissued, in an app-side slot
     (or (equal qp1 0)
         (and (<= 1 a-unissued) (or (equal a-offer 0) (<= 2 a-unissued))))
     (or (equal qp2 0) (<= 1 a-unissued))

     ; ---- the requests in flight are counted, and each is in exactly one
     ;      place: the boundary's outstanding count equals request-FIFO
     ;      entries plus app-side slots plus response-FIFO entries, and it
     ;      is what the controller is waiting for
     (<= b-out 8)
     (equal b-out (+ oq a-reserved os))
     (equal b-out (kv-in-flight k-state-q k-read-outstanding-q))
     ; ---- if the boundary has a CLEAR pending while any is in flight, the
     ;      controller has seen that CLEAR
     (or (equal b-out 0) (equal b-clr-pend 0) (equal aborted 1))

     ; ---- the app side: r slots reserved from the head; the first nd done,
     ;      then those whose read is at the endpoint, then the unissued
     (equal a-fault 0) (equal a-poison 0)
     (<= a-reserved 8)
     (<= (+ a-unissued a-readcount) a-reserved)
     (or (equal kind 2) (equal a-readcount 0))
     (equal a-tail (logand 7 (+ a-head a-reserved)))
     (equal a-issue (logand 7 (+ a-head (- a-reserved a-unissued))))
     (equal a-rtail (logand 7 (+ a-rhead a-readcount)))
     ; the request on offer to the endpoint is the first unissued slot's
     (or (equal a-offer 0)
         (and (<= 1 a-unissued)
              (equal a-offer-slot a-issue)
              (if (equal kind 1)
                  (equal a-offer-write 1)
                (equal a-offer-write 0))))
     ; every reserved slot holds a healthy request of the expected kind and
     ; epoch, and is marked done exactly if it is among the first nd
     (slot-p (off8 0 a-head) a-reserved nd a-kind0 a-epoch0 a-reject0
             a-done0 a-sfault0 kind b-epoch b-clr-pend)
     (slot-p (off8 1 a-head) a-reserved nd a-kind1 a-epoch1 a-reject1
             a-done1 a-sfault1 kind b-epoch b-clr-pend)
     (slot-p (off8 2 a-head) a-reserved nd a-kind2 a-epoch2 a-reject2
             a-done2 a-sfault2 kind b-epoch b-clr-pend)
     (slot-p (off8 3 a-head) a-reserved nd a-kind3 a-epoch3 a-reject3
             a-done3 a-sfault3 kind b-epoch b-clr-pend)
     (slot-p (off8 4 a-head) a-reserved nd a-kind4 a-epoch4 a-reject4
             a-done4 a-sfault4 kind b-epoch b-clr-pend)
     (slot-p (off8 5 a-head) a-reserved nd a-kind5 a-epoch5 a-reject5
             a-done5 a-sfault5 kind b-epoch b-clr-pend)
     (slot-p (off8 6 a-head) a-reserved nd a-kind6 a-epoch6 a-reject6
             a-done6 a-sfault6 kind b-epoch b-clr-pend)
     (slot-p (off8 7 a-head) a-reserved nd a-kind7 a-epoch7 a-reject7
             a-done7 a-sfault7 kind b-epoch b-clr-pend)
     ; the queue of slots whose read is at the endpoint lists them in order
     (or (<= a-readcount (off8 0 a-rhead))
         (equal a-rslot0 (logand 7 (+ a-head nd (off8 0 a-rhead)))))
     (or (<= a-readcount (off8 1 a-rhead))
         (equal a-rslot1 (logand 7 (+ a-head nd (off8 1 a-rhead)))))
     (or (<= a-readcount (off8 2 a-rhead))
         (equal a-rslot2 (logand 7 (+ a-head nd (off8 2 a-rhead)))))
     (or (<= a-readcount (off8 3 a-rhead))
         (equal a-rslot3 (logand 7 (+ a-head nd (off8 3 a-rhead)))))
     (or (<= a-readcount (off8 4 a-rhead))
         (equal a-rslot4 (logand 7 (+ a-head nd (off8 4 a-rhead)))))
     (or (<= a-readcount (off8 5 a-rhead))
         (equal a-rslot5 (logand 7 (+ a-head nd (off8 5 a-rhead)))))
     (or (<= a-readcount (off8 6 a-rhead))
         (equal a-rslot6 (logand 7 (+ a-head nd (off8 6 a-rhead)))))
     (or (<= a-readcount (off8 7 a-rhead))
         (equal a-rslot7 (logand 7 (+ a-head nd (off8 7 a-rhead)))))

     ; ---- every entry in either FIFO is of the expected kind, and of the
     ;      current epoch unless a CLEAR is pending; in the response FIFO it
     ;      carries no fault bit
     (or (<= oq (off8 0 qr)) (req-entry-p q-mem0 kind b-epoch b-clr-pend))
     (or (<= oq (off8 1 qr)) (req-entry-p q-mem1 kind b-epoch b-clr-pend))
     (or (<= oq (off8 2 qr)) (req-entry-p q-mem2 kind b-epoch b-clr-pend))
     (or (<= oq (off8 3 qr)) (req-entry-p q-mem3 kind b-epoch b-clr-pend))
     (or (<= oq (off8 4 qr)) (req-entry-p q-mem4 kind b-epoch b-clr-pend))
     (or (<= oq (off8 5 qr)) (req-entry-p q-mem5 kind b-epoch b-clr-pend))
     (or (<= oq (off8 6 qr)) (req-entry-p q-mem6 kind b-epoch b-clr-pend))
     (or (<= oq (off8 7 qr)) (req-entry-p q-mem7 kind b-epoch b-clr-pend))
     (or (equal q-mv 0) (req-entry-p q-md kind b-epoch b-clr-pend))
     (or (<= os (off8 0 sr)) (rsp-entry-p s-mem0 kind b-epoch b-clr-pend))
     (or (<= os (off8 1 sr)) (rsp-entry-p s-mem1 kind b-epoch b-clr-pend))
     (or (<= os (off8 2 sr)) (rsp-entry-p s-mem2 kind b-epoch b-clr-pend))
     (or (<= os (off8 3 sr)) (rsp-entry-p s-mem3 kind b-epoch b-clr-pend))
     (or (<= os (off8 4 sr)) (rsp-entry-p s-mem4 kind b-epoch b-clr-pend))
     (or (<= os (off8 5 sr)) (rsp-entry-p s-mem5 kind b-epoch b-clr-pend))
     (or (<= os (off8 6 sr)) (rsp-entry-p s-mem6 kind b-epoch b-clr-pend))
     (or (<= os (off8 7 sr)) (rsp-entry-p s-mem7 kind b-epoch b-clr-pend))
     (or (equal s-mv 0) (rsp-entry-p s-md kind b-epoch b-clr-pend)))))

; Every register the reset clears is zero.
(define joint-reset-p
  (   p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q k-pending-issued-q
   k-pending-returned-q k-pending-read-pending-q k-committed-prefix-q
   k-pending-layer-q k-pending-position-q k-pending-key-exponents-q
   k-pending-value-exponents-q k-expected-coordinate-q k-pending-persisted-q
   k-write-head-q k-write-word-q k-write-aborted-q k-response-kind-q
   k-response-head-q k-response-layer-q k-response-position-q
   k-response-fault-q k-response-from-pending-q k-read-word-q
   k-read-return-word-q k-read-outstanding-q k-read-issue-done-q
   k-read-aborted-q k-read-physical-kind-q k-read-epoch-q
   k-read-received-mask-q k-cache-valid-q k-cache-kind-q k-cache-layer-q
   k-cache-position-q k-cache-tag-epoch-q k-cache-epoch-q
   k-cache-clear-seen-q k-cache-issued-q k-cache-returned-q
   k-cache-read-pending-q k-cache-copy-kind-q k-lock-seen-q k-fault-q
   k-stage-begin-consumed-q k-stage-payload-consumed-q k-commit-consumed-q
   k-attention-req-consumed-q b-crel b-arel b-lock-meta b-lock-sync
   b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
   b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall b-wstallf
   b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2 q-mv q-sf
   q-spf q-df q-st q-md s-wb s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2
   s-mv s-sf s-spf s-df s-st s-md q-mdw a-fault a-lock-seen a-offer
   a-offer-write a-poison a-offer-slot a-reserved a-unissued a-readcount
   a-head a-tail a-issue a-rhead a-rtail a-kind0 a-kind1 a-kind2 a-kind3
   a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1 a-epoch2 a-epoch3
   a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1 a-reject2
   a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0 a-done1 a-done2
   a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0 a-sfault1 a-sfault2
   a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7 a-word0 a-word1 a-word2
   a-word3 a-word4 a-word5 a-word6 a-word7)
  :verify-guards nil
  (and
       (equal p-lock-meta 0)
       (equal p-lock-sync 0)
       (equal p-cfb 0)
       (equal p-apprel 0)
       (equal m-rel 0)
       (equal k-state-q 0)
       (equal k-pending-issued-q 0)
       (equal k-pending-returned-q 0)
       (equal k-pending-read-pending-q 0)
       (equal k-committed-prefix-q 0)
       (equal k-pending-layer-q 0)
       (equal k-pending-position-q 0)
       (equal k-pending-key-exponents-q 0)
       (equal k-pending-value-exponents-q 0)
       (equal k-expected-coordinate-q 0)
       (equal k-pending-persisted-q 0)
       (equal k-write-head-q 0)
       (equal k-write-word-q 0)
       (equal k-write-aborted-q 0)
       (equal k-response-kind-q 0)
       (equal k-response-head-q 0)
       (equal k-response-layer-q 0)
       (equal k-response-position-q 0)
       (equal k-response-fault-q 0)
       (equal k-response-from-pending-q 0)
       (equal k-read-word-q 0)
       (equal k-read-return-word-q 0)
       (equal k-read-outstanding-q 0)
       (equal k-read-issue-done-q 0)
       (equal k-read-aborted-q 0)
       (equal k-read-physical-kind-q 0)
       (equal k-read-epoch-q 0)
       (equal k-read-received-mask-q 0)
       (equal k-cache-valid-q 0)
       (equal k-cache-kind-q 0)
       (equal k-cache-layer-q 0)
       (equal k-cache-position-q 0)
       (equal k-cache-tag-epoch-q 0)
       (equal k-cache-epoch-q 0)
       (equal k-cache-clear-seen-q 0)
       (equal k-cache-issued-q 0)
       (equal k-cache-returned-q 0)
       (equal k-cache-read-pending-q 0)
       (equal k-cache-copy-kind-q 0)
       (equal k-lock-seen-q 0)
       (equal k-fault-q 0)
       (equal k-stage-begin-consumed-q 0)
       (equal k-stage-payload-consumed-q 0)
       (equal k-commit-consumed-q 0)
       (equal k-attention-req-consumed-q 0)
       (equal b-crel 0)
       (equal b-arel 0)
       (equal b-lock-meta 0)
       (equal b-lock-sync 0)
       (equal b-afc-meta 0)
       (equal b-afc-sync 0)
       (equal b-cfa-meta 0)
       (equal b-cfa-sync 0)
       (equal b-fault 0)
       (equal b-lock-seen 0)
       (equal b-clr-seen 0)
       (equal b-clr-pend 0)
       (equal b-clr-drained 0)
       (equal b-epoch 0)
       (equal b-out 0)
       (equal b-mstall 0)
       (equal b-wstall 0)
       (equal b-wstallf 0)
       (equal b-rstall 0)
       (equal q-wb 0)
       (equal q-wg 0)
       (equal q-full 0)
       (equal q-rb 0)
       (equal q-rg 0)
       (equal q-rs1 0)
       (equal q-rs2 0)
       (equal q-ws1 0)
       (equal q-ws2 0)
       (equal q-mv 0)
       (equal q-sf 0)
       (equal q-spf 0)
       (equal q-df 0)
       (equal q-st 0)
       (equal q-md 0)
       (equal s-wb 0)
       (equal s-wg 0)
       (equal s-full 0)
       (equal s-rb 0)
       (equal s-rg 0)
       (equal s-rs1 0)
       (equal s-rs2 0)
       (equal s-ws1 0)
       (equal s-ws2 0)
       (equal s-mv 0)
       (equal s-sf 0)
       (equal s-spf 0)
       (equal s-df 0)
       (equal s-st 0)
       (equal s-md 0)
       (equal q-mdw 0)
       (equal a-fault 0)
       (equal a-lock-seen 0)
       (equal a-offer 0)
       (equal a-offer-write 0)
       (equal a-poison 0)
       (equal a-offer-slot 0)
       (equal a-reserved 0)
       (equal a-unissued 0)
       (equal a-readcount 0)
       (equal a-head 0)
       (equal a-tail 0)
       (equal a-issue 0)
       (equal a-rhead 0)
       (equal a-rtail 0)
       (equal a-kind0 0)
       (equal a-kind1 0)
       (equal a-kind2 0)
       (equal a-kind3 0)
       (equal a-kind4 0)
       (equal a-kind5 0)
       (equal a-kind6 0)
       (equal a-kind7 0)
       (equal a-epoch0 0)
       (equal a-epoch1 0)
       (equal a-epoch2 0)
       (equal a-epoch3 0)
       (equal a-epoch4 0)
       (equal a-epoch5 0)
       (equal a-epoch6 0)
       (equal a-epoch7 0)
       (equal a-reject0 0)
       (equal a-reject1 0)
       (equal a-reject2 0)
       (equal a-reject3 0)
       (equal a-reject4 0)
       (equal a-reject5 0)
       (equal a-reject6 0)
       (equal a-reject7 0)
       (equal a-done0 0)
       (equal a-done1 0)
       (equal a-done2 0)
       (equal a-done3 0)
       (equal a-done4 0)
       (equal a-done5 0)
       (equal a-done6 0)
       (equal a-done7 0)
       (equal a-sfault0 0)
       (equal a-sfault1 0)
       (equal a-sfault2 0)
       (equal a-sfault3 0)
       (equal a-sfault4 0)
       (equal a-sfault5 0)
       (equal a-sfault6 0)
       (equal a-sfault7 0)
       (equal a-word0 0)
       (equal a-word1 0)
       (equal a-word2 0)
       (equal a-word3 0)
       (equal a-word4 0)
       (equal a-word5 0)
       (equal a-word6 0)
       (equal a-word7 0)))

; Every signal of the invariant holds a definite two-valued value.
(define joint-2valued-p
  (   p-lock-meta p-lock-sync p-cfb p-apprel m-rel k-state-q k-pending-issued-q
   k-pending-returned-q k-pending-read-pending-q k-committed-prefix-q
   k-pending-layer-q k-pending-position-q k-pending-key-exponents-q
   k-pending-value-exponents-q k-expected-coordinate-q k-pending-persisted-q
   k-write-head-q k-write-word-q k-write-aborted-q k-response-kind-q
   k-response-head-q k-response-layer-q k-response-position-q
   k-response-fault-q k-response-from-pending-q k-read-word-q
   k-read-return-word-q k-read-outstanding-q k-read-issue-done-q
   k-read-aborted-q k-read-physical-kind-q k-read-epoch-q
   k-read-received-mask-q k-cache-valid-q k-cache-kind-q k-cache-layer-q
   k-cache-position-q k-cache-tag-epoch-q k-cache-epoch-q
   k-cache-clear-seen-q k-cache-issued-q k-cache-returned-q
   k-cache-read-pending-q k-cache-copy-kind-q k-lock-seen-q k-fault-q
   k-stage-begin-consumed-q k-stage-payload-consumed-q k-commit-consumed-q
   k-attention-req-consumed-q b-crel b-arel b-lock-meta b-lock-sync
   b-afc-meta b-afc-sync b-cfa-meta b-cfa-sync b-fault b-lock-seen b-clr-seen
   b-clr-pend b-clr-drained b-epoch b-out b-mstall b-wstall b-wstallf
   b-rstall q-wb q-wg q-full q-rb q-rg q-rs1 q-rs2 q-ws1 q-ws2 q-mv q-sf
   q-spf q-df q-st q-md q-mem0 q-mem1 q-mem2 q-mem3 q-mem4 q-mem5 q-mem6
   q-mem7 s-wb s-wg s-full s-rb s-rg s-rs1 s-rs2 s-ws1 s-ws2 s-mv s-sf s-spf
   s-df s-st s-md s-mem0 s-mem1 s-mem2 s-mem3 s-mem4 s-mem5 s-mem6 s-mem7
   q-mdw q-memw0 q-memw1 q-memw2 q-memw3 q-memw4 q-memw5 q-memw6 q-memw7
   a-fault a-lock-seen a-offer a-offer-write a-poison a-offer-slot a-reserved
   a-unissued a-readcount a-head a-tail a-issue a-rhead a-rtail a-kind0
   a-kind1 a-kind2 a-kind3 a-kind4 a-kind5 a-kind6 a-kind7 a-epoch0 a-epoch1
   a-epoch2 a-epoch3 a-epoch4 a-epoch5 a-epoch6 a-epoch7 a-reject0 a-reject1
   a-reject2 a-reject3 a-reject4 a-reject5 a-reject6 a-reject7 a-done0
   a-done1 a-done2 a-done3 a-done4 a-done5 a-done6 a-done7 a-sfault0
   a-sfault1 a-sfault2 a-sfault3 a-sfault4 a-sfault5 a-sfault6 a-sfault7
   a-word0 a-word1 a-word2 a-word3 a-word4 a-word5 a-word6 a-word7 a-rslot0
   a-rslot1 a-rslot2 a-rslot3 a-rslot4 a-rslot5 a-rslot6 a-rslot7)
  :verify-guards nil
  (and
       (unsigned-byte-p 1 p-lock-meta)
       (unsigned-byte-p 1 p-lock-sync)
       (unsigned-byte-p 1 p-cfb)
       (unsigned-byte-p 3 p-apprel)
       (unsigned-byte-p 2 m-rel)
       (unsigned-byte-p 4 k-state-q)
       (unsigned-byte-p 4 k-pending-issued-q)
       (unsigned-byte-p 3 k-pending-returned-q)
       (unsigned-byte-p 1 k-pending-read-pending-q)
       (unsigned-byte-p 72 k-committed-prefix-q)
       (unsigned-byte-p 3 k-pending-layer-q)
       (unsigned-byte-p 12 k-pending-position-q)
       (unsigned-byte-p 16 k-pending-key-exponents-q)
       (unsigned-byte-p 16 k-pending-value-exponents-q)
       (unsigned-byte-p 7 k-expected-coordinate-q)
       (unsigned-byte-p 1 k-pending-persisted-q)
       (unsigned-byte-p 1 k-write-head-q)
       (unsigned-byte-p 4 k-write-word-q)
       (unsigned-byte-p 1 k-write-aborted-q)
       (unsigned-byte-p 2 k-response-kind-q)
       (unsigned-byte-p 1 k-response-head-q)
       (unsigned-byte-p 3 k-response-layer-q)
       (unsigned-byte-p 12 k-response-position-q)
       (unsigned-byte-p 1 k-response-fault-q)
       (unsigned-byte-p 1 k-response-from-pending-q)
       (unsigned-byte-p 4 k-read-word-q)
       (unsigned-byte-p 4 k-read-return-word-q)
       (unsigned-byte-p 4 k-read-outstanding-q)
       (unsigned-byte-p 1 k-read-issue-done-q)
       (unsigned-byte-p 1 k-read-aborted-q)
       (unsigned-byte-p 1 k-read-physical-kind-q)
       (unsigned-byte-p 1 k-read-epoch-q)
       (unsigned-byte-p 9 k-read-received-mask-q)
       (unsigned-byte-p 1 k-cache-valid-q)
       (unsigned-byte-p 1 k-cache-kind-q)
       (unsigned-byte-p 3 k-cache-layer-q)
       (unsigned-byte-p 12 k-cache-position-q)
       (unsigned-byte-p 1 k-cache-tag-epoch-q)
       (unsigned-byte-p 1 k-cache-epoch-q)
       (unsigned-byte-p 1 k-cache-clear-seen-q)
       (unsigned-byte-p 3 k-cache-issued-q)
       (unsigned-byte-p 3 k-cache-returned-q)
       (unsigned-byte-p 1 k-cache-read-pending-q)
       (unsigned-byte-p 1 k-cache-copy-kind-q)
       (unsigned-byte-p 1 k-lock-seen-q)
       (unsigned-byte-p 1 k-fault-q)
       (unsigned-byte-p 1 k-stage-begin-consumed-q)
       (unsigned-byte-p 1 k-stage-payload-consumed-q)
       (unsigned-byte-p 1 k-commit-consumed-q)
       (unsigned-byte-p 1 k-attention-req-consumed-q)
       (unsigned-byte-p 3 b-crel)
       (unsigned-byte-p 3 b-arel)
       (unsigned-byte-p 1 b-lock-meta)
       (unsigned-byte-p 1 b-lock-sync)
       (unsigned-byte-p 1 b-afc-meta)
       (unsigned-byte-p 1 b-afc-sync)
       (unsigned-byte-p 1 b-cfa-meta)
       (unsigned-byte-p 1 b-cfa-sync)
       (unsigned-byte-p 1 b-fault)
       (unsigned-byte-p 1 b-lock-seen)
       (unsigned-byte-p 1 b-clr-seen)
       (unsigned-byte-p 1 b-clr-pend)
       (unsigned-byte-p 1 b-clr-drained)
       (unsigned-byte-p 1 b-epoch)
       (unsigned-byte-p 4 b-out)
       (unsigned-byte-p 1 b-mstall)
       (unsigned-byte-p 1 b-wstall)
       (unsigned-byte-p 1 b-wstallf)
       (unsigned-byte-p 1 b-rstall)
       (unsigned-byte-p 4 q-wb)
       (unsigned-byte-p 4 q-wg)
       (unsigned-byte-p 1 q-full)
       (unsigned-byte-p 4 q-rb)
       (unsigned-byte-p 4 q-rg)
       (unsigned-byte-p 4 q-rs1)
       (unsigned-byte-p 4 q-rs2)
       (unsigned-byte-p 4 q-ws1)
       (unsigned-byte-p 4 q-ws2)
       (unsigned-byte-p 1 q-mv)
       (unsigned-byte-p 1 q-sf)
       (unsigned-byte-p 40 q-spf)
       (unsigned-byte-p 1 q-df)
       (unsigned-byte-p 1 q-st)
       (unsigned-byte-p 3 q-md)
       (unsigned-byte-p 3 q-mem0)
       (unsigned-byte-p 3 q-mem1)
       (unsigned-byte-p 3 q-mem2)
       (unsigned-byte-p 3 q-mem3)
       (unsigned-byte-p 3 q-mem4)
       (unsigned-byte-p 3 q-mem5)
       (unsigned-byte-p 3 q-mem6)
       (unsigned-byte-p 3 q-mem7)
       (unsigned-byte-p 4 s-wb)
       (unsigned-byte-p 4 s-wg)
       (unsigned-byte-p 1 s-full)
       (unsigned-byte-p 4 s-rb)
       (unsigned-byte-p 4 s-rg)
       (unsigned-byte-p 4 s-rs1)
       (unsigned-byte-p 4 s-rs2)
       (unsigned-byte-p 4 s-ws1)
       (unsigned-byte-p 4 s-ws2)
       (unsigned-byte-p 1 s-mv)
       (unsigned-byte-p 1 s-sf)
       (unsigned-byte-p 33 s-spf)
       (unsigned-byte-p 1 s-df)
       (unsigned-byte-p 1 s-st)
       (unsigned-byte-p 4 s-md)
       (unsigned-byte-p 4 s-mem0)
       (unsigned-byte-p 4 s-mem1)
       (unsigned-byte-p 4 s-mem2)
       (unsigned-byte-p 4 s-mem3)
       (unsigned-byte-p 4 s-mem4)
       (unsigned-byte-p 4 s-mem5)
       (unsigned-byte-p 4 s-mem6)
       (unsigned-byte-p 4 s-mem7)
       (unsigned-byte-p 4 q-mdw)
       (unsigned-byte-p 4 q-memw0)
       (unsigned-byte-p 4 q-memw1)
       (unsigned-byte-p 4 q-memw2)
       (unsigned-byte-p 4 q-memw3)
       (unsigned-byte-p 4 q-memw4)
       (unsigned-byte-p 4 q-memw5)
       (unsigned-byte-p 4 q-memw6)
       (unsigned-byte-p 4 q-memw7)
       (unsigned-byte-p 1 a-fault)
       (unsigned-byte-p 1 a-lock-seen)
       (unsigned-byte-p 1 a-offer)
       (unsigned-byte-p 1 a-offer-write)
       (unsigned-byte-p 1 a-poison)
       (unsigned-byte-p 3 a-offer-slot)
       (unsigned-byte-p 4 a-reserved)
       (unsigned-byte-p 4 a-unissued)
       (unsigned-byte-p 4 a-readcount)
       (unsigned-byte-p 3 a-head)
       (unsigned-byte-p 3 a-tail)
       (unsigned-byte-p 3 a-issue)
       (unsigned-byte-p 3 a-rhead)
       (unsigned-byte-p 3 a-rtail)
       (unsigned-byte-p 2 a-kind0)
       (unsigned-byte-p 2 a-kind1)
       (unsigned-byte-p 2 a-kind2)
       (unsigned-byte-p 2 a-kind3)
       (unsigned-byte-p 2 a-kind4)
       (unsigned-byte-p 2 a-kind5)
       (unsigned-byte-p 2 a-kind6)
       (unsigned-byte-p 2 a-kind7)
       (unsigned-byte-p 1 a-epoch0)
       (unsigned-byte-p 1 a-epoch1)
       (unsigned-byte-p 1 a-epoch2)
       (unsigned-byte-p 1 a-epoch3)
       (unsigned-byte-p 1 a-epoch4)
       (unsigned-byte-p 1 a-epoch5)
       (unsigned-byte-p 1 a-epoch6)
       (unsigned-byte-p 1 a-epoch7)
       (unsigned-byte-p 1 a-reject0)
       (unsigned-byte-p 1 a-reject1)
       (unsigned-byte-p 1 a-reject2)
       (unsigned-byte-p 1 a-reject3)
       (unsigned-byte-p 1 a-reject4)
       (unsigned-byte-p 1 a-reject5)
       (unsigned-byte-p 1 a-reject6)
       (unsigned-byte-p 1 a-reject7)
       (unsigned-byte-p 1 a-done0)
       (unsigned-byte-p 1 a-done1)
       (unsigned-byte-p 1 a-done2)
       (unsigned-byte-p 1 a-done3)
       (unsigned-byte-p 1 a-done4)
       (unsigned-byte-p 1 a-done5)
       (unsigned-byte-p 1 a-done6)
       (unsigned-byte-p 1 a-done7)
       (unsigned-byte-p 1 a-sfault0)
       (unsigned-byte-p 1 a-sfault1)
       (unsigned-byte-p 1 a-sfault2)
       (unsigned-byte-p 1 a-sfault3)
       (unsigned-byte-p 1 a-sfault4)
       (unsigned-byte-p 1 a-sfault5)
       (unsigned-byte-p 1 a-sfault6)
       (unsigned-byte-p 1 a-sfault7)
       (unsigned-byte-p 4 a-word0)
       (unsigned-byte-p 4 a-word1)
       (unsigned-byte-p 4 a-word2)
       (unsigned-byte-p 4 a-word3)
       (unsigned-byte-p 4 a-word4)
       (unsigned-byte-p 4 a-word5)
       (unsigned-byte-p 4 a-word6)
       (unsigned-byte-p 4 a-word7)
       (unsigned-byte-p 3 a-rslot0)
       (unsigned-byte-p 3 a-rslot1)
       (unsigned-byte-p 3 a-rslot2)
       (unsigned-byte-p 3 a-rslot3)
       (unsigned-byte-p 3 a-rslot4)
       (unsigned-byte-p 3 a-rslot5)
       (unsigned-byte-p 3 a-rslot6)
       (unsigned-byte-p 3 a-rslot7)))

; THE ENVIRONMENT on one cycle, as values of named signals (see the table of
; hypothesis signals in joint_signals_reads.py): no module outside the slice
; reports a fault; the endpoint reports no error and returns a response only
; while a read is at the endpoint (a-readcount, the app side's count of
; those); and whenever the request FIFO presents an entry to the app side
; (q-mv, its output-valid register) the app side judges the descriptor legal.
; The signals not constrained here are only required to be two-valued.
;
; Three more conditions belong to the environment but cannot be written as
; values of overridable signals, because each is computed and consumed inside
; one procedural block.  They are read in the step lemma and appear as the
; antecedent of its conclusion:
;   o-pfn  the controller's protocol_fault_now is low: the client presents no
;          request the controller classifies as a protocol violation;
;   o-epf  the app side's endpoint_padding_fault_now is low, and
;   o-tpf  the controller's typed_padding_fault is low: the metadata word the
;          endpoint returns for a row is well formed.
(define joint-env-p
  (   h-arbfail h-shellterm h-shellfail h-layerfail h-auth h-mcdc h-kupf h-layer
   h-position h-kexp h-vexp h-sbegin h-spayload h-index h-key h-value
   h-commit h-attn h-attn-kind h-attn-pos h-attn-head h-attn-ready h-epready
   h-eprspv h-eprsperr h-eprspdata h-rspdata h-appup h-legal
   q-mv a-readcount)
  :verify-guards nil
  :ignore-ok t
  :irrelevant-formals-ok t
  (and
       (equal h-arbfail 0)
       (equal h-shellterm 0)
       (equal h-shellfail 0)
       (equal h-layerfail 0)
       (equal h-auth 0)
       (equal h-mcdc 0)
       (equal h-kupf 0)
       (equal h-eprsperr 0)
       (equal h-appup 0)
       (or (equal q-mv 0) (equal h-legal 1))
       (or (equal h-eprspv 0) (<= 1 a-readcount))))

; THE THREE FACTS this invariant discharges, which the controller-only
; theorem had to assume.
;  (1) At the controller's own ports: a write completion is flagged faulted
;      only if CLEAR is high on that cycle or the controller has already seen
;      CLEAR while waiting.  That is kv-clause-p.
;  (2) The same for a read response.
;  (3) The controller's terminal_fault_event is low (o-tfe in the step
;      lemma).
(define kv-clause-p (valid fault clear aborted)
  (or (not (equal valid 1)) (not (equal fault 1))
      (equal clear 1) (equal aborted 1)))

(in-theory (disable kv-good-p kv-state-p kv-collecting kv-kind kv-in-flight
                    kv-aborted kv-cache-read-p kv-collect-p
                    gray4 ungray4 off8 low-ones
                    fifo-inv-p req-entry-p rsp-entry-p slot-p
                    joint-boundary-zero-p joint-inv-p joint-reset-p
                    joint-2valued-p joint-env-p kv-clause-p))

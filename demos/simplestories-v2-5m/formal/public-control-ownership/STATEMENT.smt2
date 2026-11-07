(declare-datatype PCState ((pc-state
 (pc-count (_ BitVec 12))
 (pc-cell (_ BitVec 12))
 (pc-generation Int)
 (pc-next-ticket Int)
 (pc-work-live Bool)
 (pc-work-ticket Int)
 (pc-work-generation Int)
 (pc-work-count (_ BitVec 12))
 (pc-work-cell (_ BitVec 12))
 (pc-held Bool)
 (pc-held-ticket Int)
 (pc-held-generation Int)
 (pc-held-token (_ BitVec 12))
 (pc-last-commit Int)
 (pc-last-publication Int)
 (pc-frame-valid Bool)
 (pc-frame-ticket Int)
 (pc-frame-generation Int)
 (pc-frame-token (_ BitVec 12)))))

(define-fun pc-append ((a |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n append_valid| a) (|public_control_whole_n append_ready| a)))

(define-fun pc-step ((a |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n step_valid| a) (|public_control_whole_n step_ready| a)))

(define-fun pc-clear ((a |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n u_public.cmd_valid| a) (|public_control_whole_n u_public.cmd_ready| a) (= (|public_control_whole_n u_public.cmd| a) (_ bv2 2))))

(define-fun pc-capture ((a |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (= (|public_control_whole_n u_public.f_phase| a) (_ bv2 3)) (not (|public_control_whole_n u_public.f_cancel_pending| a)) (|public_control_whole_n u_public.result_valid| a)))

(define-fun pc-byte ((a |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n u_public.f_send_byte| a) (|public_control_whole_n u_public.f_tx_accept| a)))

(define-fun pc-live ((a |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n u_core.u_native.machine_active| a) (not (|public_control_whole_n u_core.u_native.root_terminal| a)) (|public_control_whole_n u_core.u_native.u_token_shell.rst_n| a)))

(define-fun pc-stop ((a |public_control_whole_s|)) Bool
 (|public_control_whole_n u_core.u_native.root_terminal| a))

(define-fun pc-successful-commit ((a |public_control_whole_s|) (b |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n reset_n_i| b) (|public_control_whole_n u_core.u_native.u_token_shell.rst_n| a) (|public_control_whole_n u_core.u_native.u_token_shell.rst_n| b) (|public_control_whole_n u_core.u_native.u_token_shell.generated_commit| a) (not (|public_control_whole_n clear| a)) (not (|public_control_whole_n u_core.u_native.root_terminal| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.fail_q| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.private_head_result_valid_i| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.upstream_fault_i| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.child_fault| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.lock_fault| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.watchdog_fault| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.public_protocol_fault| a)) (not (|public_control_whole_n u_core.u_native.u_token_shell.private_protocol_fault| a))))

(define-fun pc-frame-active ((a |public_control_whole_s|)) Bool
 (and (|public_control_whole_n reset_n_i| a) (or (= (|public_control_whole_n u_public.f_phase| a) (_ bv3 3)) (= (|public_control_whole_n u_public.f_phase| a) (_ bv4 3))) (= (|public_control_whole_n u_public.f_reply_kind| a) (_ bv129 8))))

(define-fun pc-zero () PCState
 (pc-state (_ bv0 12) (_ bv0 12) 0 1 false 0 0 (_ bv0 12) (_ bv0 12) false 0 0 (_ bv0 12) 0 0 false 0 0 (_ bv0 12)))

(define-fun pc-next ((a |public_control_whole_s|) (b |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) PCState
 (ite (or (not (|public_control_whole_n reset_n_i| a)) (not (|public_control_whole_n reset_n_i| b))) pc-zero (pc-state (ite (pc-clear a) (_ bv0 12) (ite (or (pc-append a) (pc-successful-commit a b)) (bvadd (pc-count p) (_ bv1 12)) (pc-count p))) (ite (and (pc-append a) (= A (pc-count p))) (|public_control_whole_n append_token| a) (ite (and (pc-successful-commit a b) (= A (pc-count p))) (|public_control_whole_n u_core.u_native.u_token_shell.completing_winner| a) (pc-cell p))) (ite (pc-clear a) (+ (pc-generation p) 1) (pc-generation p)) (ite (pc-step a) (+ (pc-next-ticket p) 1) (pc-next-ticket p)) (ite (or (pc-clear a) (pc-stop a)) false (ite (pc-step a) true (ite (pc-capture a) false (pc-work-live p)))) (ite (pc-step a) (pc-next-ticket p) (pc-work-ticket p)) (ite (pc-step a) (pc-generation p) (pc-work-generation p)) (ite (pc-step a) (pc-count p) (pc-work-count p)) (ite (pc-step a) (pc-cell p) (pc-work-cell p)) (ite (or (or (pc-clear a) (pc-stop a)) (pc-step a) (pc-capture a)) false (ite (pc-successful-commit a b) true (pc-held p))) (ite (pc-successful-commit a b) (pc-work-ticket p) (pc-held-ticket p)) (ite (pc-successful-commit a b) (pc-work-generation p) (pc-held-generation p)) (ite (pc-successful-commit a b) (|public_control_whole_n u_core.u_native.u_token_shell.completing_winner| a) (pc-held-token p)) (ite (pc-successful-commit a b) (pc-work-ticket p) (pc-last-commit p)) (ite (pc-capture a) (pc-held-ticket p) (pc-last-publication p)) (ite (pc-capture a) true (pc-frame-valid p)) (ite (pc-capture a) (pc-held-ticket p) (pc-frame-ticket p)) (ite (pc-capture a) (pc-held-generation p) (pc-frame-generation p)) (ite (pc-capture a) (pc-held-token p) (pc-frame-token p)))))

(define-fun PC-domain ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (and (<= 0 (pc-generation p)) (<= 1 (pc-next-ticket p)) (bvule (pc-count p) (_ bv2049 12)) (<= 0 (pc-last-publication p)) (<= (pc-last-publication p) (pc-last-commit p)) (< (pc-last-commit p) (pc-next-ticket p))))

(define-fun PC-work-domain ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (pc-work-live p) (and (<= 1 (pc-work-ticket p)) (< (pc-work-ticket p) (pc-next-ticket p)) (= (pc-work-generation p) (pc-generation p)) (bvuge (pc-work-count p) (_ bv1 12)) (bvule (pc-work-count p) (_ bv2048 12)) (=> (not (pc-held p)) (and (> (pc-work-ticket p) (pc-last-commit p)) (= (pc-count p) (pc-work-count p)))) (=> (pc-held p) (= (pc-count p) (bvadd (pc-work-count p) (_ bv1 12)))))))

(define-fun PC-held-domain ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (pc-held p) (and (pc-work-live p) (= (pc-held-ticket p) (pc-work-ticket p)) (= (pc-held-generation p) (pc-generation p)) (= (pc-last-commit p) (pc-held-ticket p)) (bvult (pc-held-token p) (_ bv4019 12)) (> (pc-held-ticket p) (pc-last-publication p)))))

(define-fun PC-current-count ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (and (|public_control_whole_n reset_n_i| a) (not (|public_control_whole_n u_core.u_native.root_terminal| a))) (= (|public_control_whole_n u_core.u_native.u_token_shell.tape_count_q| a) (pc-count p))))

(define-fun PC-current-cell ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (and (pc-live a) (bvult A (pc-count p)) (bvult A (_ bv2049 12))) (= (|public_control_whole_n f_pc_tape_value_o| a) (pc-cell p))))

(define-fun PC-macro-lease ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (and (pc-live a) (|public_control_whole_n u_core.u_native.f_w_live| a) (not (|public_control_whole_n clear| a))) (and (pc-work-live p) (not (pc-held p)) (= (pc-work-count p) (|public_control_whole_n u_core.u_native.f_w_length| a)))))

(define-fun PC-native-held ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (and (pc-live a) (= (|public_control_whole_n u_core.u_native.u_token_shell.state_q| a) (_ bv22 5)) (not (|public_control_whole_n clear| a))) (and (pc-held p) (= (|public_control_whole_n u_core.u_native.u_token_shell.generated_token_q| a) (pc-held-token p)))))

(define-fun PC-awaiting-work ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (and (|public_control_whole_n reset_n_i| a) (not (|public_control_whole_n u_core.u_native.root_terminal| a)) (= (|public_control_whole_n u_public.f_phase| a) (_ bv2 3)) (not (|public_control_whole_n clear| a))) (pc-work-live p)))

(define-fun PC-frame-origin ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (pc-frame-active a) (and (pc-frame-valid p) (<= 1 (pc-frame-ticket p)) (= (pc-frame-ticket p) (pc-last-publication p)) (< (pc-frame-ticket p) (pc-next-ticket p)) (<= 0 (pc-frame-generation p)) (<= (pc-frame-generation p) (pc-generation p)) (= (|public_control_whole_n u_public.f_reply_token| a) (pc-frame-token p)))))

(define-fun PC-accepted-command-map ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (and (= (|public_control_whole_n clear| a) (pc-clear a)) (= (pc-append a) (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n u_public.cmd_valid| a) (|public_control_whole_n u_public.cmd_ready| a) (= (|public_control_whole_n u_public.cmd| a) (_ bv0 2)))) (= (pc-step a) (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n u_public.cmd_valid| a) (|public_control_whole_n u_public.cmd_ready| a) (= (|public_control_whole_n u_public.cmd| a) (_ bv1 2))))))

(define-fun PC-transfer-is-capture ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (= (pc-capture a) (and (|public_control_whole_n reset_n_i| a) (|public_control_whole_n token_valid| a) (|public_control_whole_n token_ready| a))))

(define-fun PC-publication-eligible ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (pc-capture a) (and (pc-held p) (pc-work-live p) (= (pc-held-generation p) (pc-generation p)) (= (|public_control_whole_n token| a) (pc-held-token p)) (> (pc-held-ticket p) (pc-last-publication p)) (not (pc-clear a)))))

(define-fun PC-I ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (and (PC-domain a p A) (PC-work-domain a p A) (PC-held-domain a p A) (PC-current-count a p A) (PC-current-cell a p A) (PC-macro-lease a p A) (PC-native-held a p A) (PC-awaiting-work a p A) (PC-frame-origin a p A) (PC-accepted-command-map a p A) (PC-transfer-is-capture a p A) (PC-publication-eligible a p A)))

(define-fun PC-commit-goal ((a |public_control_whole_s|) (b |public_control_whole_s|) (p PCState)) Bool
 (=> (pc-successful-commit a b) (and (pc-work-live p) (not (pc-held p)) (> (pc-work-ticket p) (pc-last-commit p)) (= (|public_control_whole_n u_core.u_native.u_token_shell.state_q| b) (_ bv22 5)) (= (|public_control_whole_n u_core.u_native.u_token_shell.generated_token_q| b) (|public_control_whole_n u_core.u_native.u_token_shell.completing_winner| a)) (= (|public_control_whole_n u_core.u_native.u_token_shell.tape_count_q| b) (bvadd (pc-count p) (_ bv1 12))))))

(define-fun PC-snapshot-goal ((a |public_control_whole_s|) (b |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (and (pc-step a) (|public_control_whole_n reset_n_i| b)) (and (= (pc-work-ticket (pc-next a b p A)) (pc-next-ticket p)) (= (pc-work-count (pc-next a b p A)) (pc-count p)) (=> (bvult A (pc-count p)) (= (pc-work-cell (pc-next a b p A)) (|public_control_whole_n f_pc_tape_value_o| a))))))

(define-fun pc-crc-stage-7 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) c) ((_ extract 7 7) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) c) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) c) (_ bv0 1))))

(define-fun pc-crc-stage-6 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) (pc-crc-stage-7 c d)) ((_ extract 6 6) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) (pc-crc-stage-7 c d)) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) (pc-crc-stage-7 c d)) (_ bv0 1))))

(define-fun pc-crc-stage-5 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) (pc-crc-stage-6 c d)) ((_ extract 5 5) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) (pc-crc-stage-6 c d)) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) (pc-crc-stage-6 c d)) (_ bv0 1))))

(define-fun pc-crc-stage-4 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) (pc-crc-stage-5 c d)) ((_ extract 4 4) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) (pc-crc-stage-5 c d)) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) (pc-crc-stage-5 c d)) (_ bv0 1))))

(define-fun pc-crc-stage-3 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) (pc-crc-stage-4 c d)) ((_ extract 3 3) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) (pc-crc-stage-4 c d)) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) (pc-crc-stage-4 c d)) (_ bv0 1))))

(define-fun pc-crc-stage-2 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) (pc-crc-stage-3 c d)) ((_ extract 2 2) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) (pc-crc-stage-3 c d)) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) (pc-crc-stage-3 c d)) (_ bv0 1))))

(define-fun pc-crc-stage-1 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) (pc-crc-stage-2 c d)) ((_ extract 1 1) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) (pc-crc-stage-2 c d)) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) (pc-crc-stage-2 c d)) (_ bv0 1))))

(define-fun pc-crc-stage-0 ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (ite (= (bvxor ((_ extract 7 7) (pc-crc-stage-1 c d)) ((_ extract 0 0) d)) (_ bv1 1)) (bvxor (concat ((_ extract 6 0) (pc-crc-stage-1 c d)) (_ bv0 1)) (_ bv7 8)) (concat ((_ extract 6 0) (pc-crc-stage-1 c d)) (_ bv0 1))))

(define-fun pc-crc-byte ((c (_ BitVec 8)) (d (_ BitVec 8))) (_ BitVec 8)
 (pc-crc-stage-0 c d))

(define-fun pc-message-byte ((value (_ BitVec 12)) (index (_ BitVec 3))) (_ BitVec 8)
 (ite (= index (_ bv0 3)) (_ bv90 8) (ite (= index (_ bv1 3)) (_ bv129 8) (ite (= index (_ bv2 3)) ((_ extract 7 0) value) (ite (= index (_ bv3 3)) (concat (_ bv0 4) ((_ extract 11 8) value)) (pc-crc-byte (pc-crc-byte (pc-crc-byte (pc-crc-byte (_ bv0 8) (_ bv90 8)) (_ bv129 8)) ((_ extract 7 0) value)) (concat (_ bv0 4) ((_ extract 11 8) value))))))))

(define-fun PC-byte-goal ((a |public_control_whole_s|) (p PCState)) Bool
 (=> (and (pc-frame-active a) (pc-byte a)) (and (pc-frame-valid p) (= (|public_control_whole_n u_public.f_reply_token| a) (pc-frame-token p)) (= (|public_control_whole_n u_public.f_send_data| a) (pc-message-byte (pc-frame-token p) (|public_control_whole_n u_public.f_sent| a))))))

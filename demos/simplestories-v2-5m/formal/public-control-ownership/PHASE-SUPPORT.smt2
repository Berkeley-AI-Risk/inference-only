; Actual production bridge enum: IDLE=0, OFFER=1, WAIT_RESULT=2.
; The independent reference uses AWAIT_RESULT=3; it is not this signal.
; This is a separately proved ghost/native relation, never a host premise.
(define-fun PHASE-I ((a |public_control_whole_s|) (p PCState) (A (_ BitVec 12))) Bool
 (=> (pc-work-live p)
     (= (|public_control_whole_n u_public.f_phase| a) (_ bv2 3))))

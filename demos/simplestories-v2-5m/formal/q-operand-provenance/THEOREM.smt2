; Main Q operand-provenance postcondition.
; Native source-bound induction and literal provider application are in
; qcomposition-PLAN.json; the four expanded predicates are in conclusions.smt2.
(define-fun Q-operands-theorem ((a |core_workflow_control_s|) (h ApiHistory) (w WordsHistory) (ch CaptureHistory) (model (Array (_ BitVec 18) (_ BitVec 256)))) Bool (and (Q-model-beats-at-tile-capture a h w ch model) (Q-current-activation-and-native-registers a h w ch model) (Q-model-coefficients-at-MAC-use a h w ch model) (Q-row-metadata-at-postscale a h w ch model)))

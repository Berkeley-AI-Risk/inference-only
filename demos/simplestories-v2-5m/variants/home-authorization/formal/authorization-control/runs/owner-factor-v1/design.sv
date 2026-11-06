module owner_factor(input wire [3:0] state_q,input wire fault_q,root_fault,lms_fault,SHARE_VERIFIER);
      localparam [3:0] RUN=8,AUTH_WAIT=7;
      wire fail_closed_o=fault_q || root_fault || (state_q==AUTH_WAIT && lms_fault);
      wire sealed_o=state_q==RUN && !fail_closed_o;
      wire original_owner=SHARE_VERIFIER && sealed_o;
      wire factored_owner=SHARE_VERIFIER && state_q==RUN && !fault_q && !root_fault;
      always_comb assert(original_owner==factored_owner);
    endmodule

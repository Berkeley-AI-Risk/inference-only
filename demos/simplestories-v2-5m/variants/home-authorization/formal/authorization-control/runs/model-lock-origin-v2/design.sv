module model_lock_origin(
      input wire sealed_i,slot_done_q,ingress_fault_i,boot_state_locked_i,
      input wire image_verified,lut_ok_q,norm_loaded,boot_fault_i,runtime_owned_i,handoff_fault_i,reset_n,memory_fault_i);
      wire source_ready=slot_done_q && sealed_i && !ingress_fault_i;
      wire boot_locked=boot_state_locked_i && source_ready && image_verified && lut_ok_q && norm_loaded && !boot_fault_i;
      wire handoff_locked=runtime_owned_i && boot_locked && !handoff_fault_i && reset_n;
      wire private_model_locked_o=handoff_locked && !memory_fault_i;
      always_comb begin
        if(private_model_locked_o) assert(sealed_i && source_ready && boot_locked && reset_n);
        if(!sealed_i) assert(!private_model_locked_o);
      end
    endmodule

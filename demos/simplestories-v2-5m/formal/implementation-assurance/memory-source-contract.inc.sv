    // Unconditional form of the source contract consumed by the transport.
    // Reset gating is part of the native handoff, not an environment promise.
    always_comb if (private_model_locked_o)
        assert(app_domain_reset_n && f_path_read_seen_q && f_path_return_seen_q);

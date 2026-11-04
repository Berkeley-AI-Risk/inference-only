module native_cdc_reset_view(input wire core_clk_i,reset_n_i,output wire domain_o,output wire[2:0]release_o);
    wire app_clk_i=core_clk_i;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) app_runtime_release_q<=0;
        else app_runtime_release_q<={app_runtime_release_q[1:0],1'b1};
    end
    wire app_runtime_reset_n=app_runtime_release_q[2];
    assign domain_o=app_runtime_reset_n;
    assign release_o=app_runtime_release_q;
endmodule
module native_memory_reset_view (
        input wire trusted_clk_i,trusted_reset_n_i,app_clk_i,app_reset_n_i,
        output wire f_common_o,f_domain_o,output wire [2:0] f_release_o
    );
    wire common_async_reset_n=trusted_reset_n_i && app_reset_n_i;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_release_q;
    always_ff @(posedge app_clk_i or negedge common_async_reset_n) begin
        if(!common_async_reset_n) app_release_q<=0;
        else app_release_q<={app_release_q[1:0],1'b1};
    end
    // Matches the boot composition's own app release, avoiding a startup
    // false fault from its intentionally closed output during hard reset.
    wire app_domain_reset_n=app_release_q[2];
    assign f_common_o=common_async_reset_n;
    assign f_domain_o=app_domain_reset_n;
    assign f_release_o=app_release_q;
endmodule
module native_transport_reset_view (
        input wire core_clk_i,core_reset_n_i,app_clk_i,app_reset_n_i,
        output wire f_common_o,f_core_o,f_app_o,
        output wire [2:0] f_core_release_o,f_app_release_o
    );
    wire common_reset_n = core_reset_n_i && app_reset_n_i;
    (* async_reg="true", syn_preserve=1 *) logic [2:0] core_release_q, app_release_q;
    always_ff @(posedge core_clk_i or negedge common_reset_n) begin
        if (!common_reset_n) core_release_q <= 0;
        else core_release_q <= {core_release_q[1:0],1'b1};
    end
    always_ff @(posedge app_clk_i or negedge common_reset_n) begin
        if (!common_reset_n) app_release_q <= 0;
        else app_release_q <= {app_release_q[1:0],1'b1};
    end
    wire core_reset_n = core_release_q[2];
    wire app_reset_n = app_release_q[2];
    assign f_common_o=common_reset_n;
    assign f_core_o=core_reset_n;
    assign f_app_o=app_reset_n;
    assign f_core_release_o=core_release_q;
    assign f_app_release_o=app_release_q;
endmodule
module board1_actual_reset_correspondence (
        input wire core_clk,app_clk,trusted_clk,board_reset_n,trusted_reset_n,app_reset_n
    );
    wire common_async_reset_n=board_reset_n && trusted_reset_n && app_reset_n;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] core_release_q;
    always_ff @(posedge core_clk or negedge common_async_reset_n) begin
        if(!common_async_reset_n) core_release_q<=0;
        else core_release_q<={core_release_q[1:0],1'b1};
    end
    wire core_reset_n=core_release_q[2];
    wire f_memory_common,f_memory_domain,f_transport_common,f_transport_core,f_transport_app;
    wire [2:0] f_memory_release,f_transport_core_release,f_transport_app_release;
    native_memory_reset_view u_memory_reset (
        .trusted_clk_i(trusted_clk),.trusted_reset_n_i(trusted_reset_n),
        .app_clk_i(core_clk),.app_reset_n_i(core_reset_n),
        .f_common_o(f_memory_common),.f_domain_o(f_memory_domain),.f_release_o(f_memory_release));
    native_transport_reset_view u_transport_reset (
        .core_clk_i(core_clk),.core_reset_n_i(core_reset_n),
        .app_clk_i(app_clk),.app_reset_n_i(app_reset_n),
        .f_common_o(f_transport_common),.f_core_o(f_transport_core),.f_app_o(f_transport_app),
        .f_core_release_o(f_transport_core_release),.f_app_release_o(f_transport_app_release));
    wire f_cdc_domain;wire[2:0]f_cdc_release;
    native_cdc_reset_view u_cdc_reset(.core_clk_i(core_clk),.reset_n_i(core_reset_n),.domain_o(f_cdc_domain),.release_o(f_cdc_release));
    logic f_core_released_seen_q;
    always_ff @(posedge core_clk or negedge common_async_reset_n) begin
        if (!common_async_reset_n) f_core_released_seen_q<=0;
        else if (core_reset_n) f_core_released_seen_q<=1;
    end
    always_comb begin
        assert(f_cdc_release==f_memory_release);
        assert(f_cdc_domain==f_memory_domain);
        assert(core_release_q==0 || core_release_q==1 || core_release_q==3 || core_release_q==7);
        assert(f_memory_release==0 || f_memory_release==1 || f_memory_release==3 || f_memory_release==7);
        assert(f_transport_core_release==0 || f_transport_core_release==1 || f_transport_core_release==3 || f_transport_core_release==7);
        assert(f_transport_app_release==0 || f_transport_app_release==1 || f_transport_app_release==3 || f_transport_app_release==7);
        if (core_reset_n) assert(common_async_reset_n);
        assert(f_memory_common==core_reset_n);
        assert(f_transport_common==core_reset_n);
        assert(f_memory_release==f_transport_core_release);
        assert(f_memory_domain==f_transport_core);
        if (common_async_reset_n && f_core_released_seen_q) assert(core_reset_n);
        if (f_memory_domain) assert(f_core_released_seen_q);
        cover(f_memory_domain && f_transport_app);
    end
endmodule

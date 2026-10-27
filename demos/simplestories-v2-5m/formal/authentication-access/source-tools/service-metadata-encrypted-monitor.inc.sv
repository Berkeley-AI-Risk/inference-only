        logic [11:0] f_route_metadata_address_q;
        always_ff @(posedge clk) if(metadata_read)
            f_route_metadata_address_q<=12'(head_word-18'd211920);
        always_ff @(posedge clk) if(reset_n && !fault_o && valid_q) begin
            assert(f_route_metadata_address_q<2328);
            assert(f_route_metadata_word_q==18'd211920+18'(f_route_metadata_address_q));
            assert(tail_q==f_route_metadata_address_q[11]);
            if(f_route_metadata_address_q[11]) assert(data_q==last_rows[f_route_metadata_address_q[10:0]]);
            else assert(data_q==first_rows[f_route_metadata_address_q[10:0]]);
            assert(metadata_data[0 +: 32]=={8'd0,data_q[0 +: 24]});
            assert(metadata_data[32 +: 32]=={8'd0,data_q[24 +: 24]});
            assert(metadata_data[64 +: 32]=={8'd0,data_q[48 +: 24]});
            assert(metadata_data[96 +: 32]=={8'd0,data_q[72 +: 24]});
            assert(metadata_data[128 +: 32]=={8'd0,data_q[96 +: 24]});
            assert(metadata_data[160 +: 32]=={8'd0,data_q[120 +: 24]});
            assert(metadata_data[192 +: 32]=={8'd0,data_q[144 +: 24]});
            assert(metadata_data[224 +: 32]=={8'd0,data_q[168 +: 24]});
        end

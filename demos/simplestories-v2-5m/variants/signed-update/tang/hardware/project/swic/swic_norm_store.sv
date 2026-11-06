`timescale 1ns/1ps
`default_nettype none
// Extract every normalization parameter from the SAME ordered DDR readback
// authenticated by the signed whole-image SHA. No model-compiled norm ROM.
// Runtime has two synchronous read ports, matching body/head RMS latency.
module swic_norm_store(
    input wire clk,reset_n,
    input wire word_valid_i,
    output wire word_ready_o,
    input wire [17:0] word_index_i,
    input wire [255:0] word_data_i,
    output wire loaded_o,
    output logic fault_o,
    input wire model_locked_i,
    input wire body_read_i,head_read_i,
    input wire [11:0] body_address_i,head_address_i,
    output wire [33:0] body_data_o,head_data_o
);
    (* ram_style="block" *) logic [9:0] coefficients_q[0:3327];
    logic [23:0] metadata_q[0:12];
    logic [12:0] coefficients_loaded_q,metadata_loaded_q;
    (* ram_style="block" *) logic [255:0] packed_words_q[0:9];
    logic [255:0] packed_read_q;
    logic [265:0] unpack_q;
    logic [8:0] unpack_bits_q;
    logic [3:0] packed_index_q;
    logic packed_clear_q;
    localparam [1:0] FETCH=0,MERGE=1,EMIT=2;
    logic [1:0] unpack_state_q;
    logic building_q;
    logic [3:0] selector_q;
    logic [7:0] row_q;
    logic [33:0] body_q,head_q;
    wire transformer_norm=word_index_i>=211800 && word_index_i<211920;
    wire final_norm=word_index_i>=214250 && word_index_i<214260;
    wire [6:0] transformer_offset=7'(word_index_i-211800);
    wire [3:0] vector_selector=final_norm ? 4'd12 : 4'(transformer_offset/10);
    wire [3:0] vector_word=final_norm ? 4'(word_index_i-214250) : 4'(transformer_offset%10);
    assign word_ready_o=!building_q && !packed_clear_q && !fault_o;
    assign loaded_o=(&coefficients_loaded_q) && (&metadata_loaded_q) && !fault_o;
    assign body_data_o=model_locked_i && !fault_o ? body_q : 34'd0;
    assign head_data_o=model_locked_i && !fault_o ? head_q : 34'd0;
    always_ff @(posedge clk) begin
        if(packed_clear_q)
            packed_words_q[packed_index_q]<=0;
        else if(word_valid_i && word_ready_o && (transformer_norm || final_norm))
            packed_words_q[vector_word]<=word_data_i;
        else if(building_q && unpack_state_q==FETCH && packed_index_q<10)
            packed_read_q<=packed_words_q[packed_index_q];
        if(building_q && unpack_state_q==EMIT && unpack_bits_q>=10 && !fault_o)
            coefficients_q[{selector_q,row_q}]<=unpack_q[9:0];
        if(body_read_i && model_locked_i && body_address_i<3328)
            body_q<={metadata_q[body_address_i[11:8]],coefficients_q[body_address_i]};
        if(head_read_i && model_locked_i && head_address_i<3328)
            head_q<={metadata_q[head_address_i[11:8]],coefficients_q[head_address_i]};
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            coefficients_loaded_q<=0;metadata_loaded_q<=0;unpack_q<=0;
            unpack_bits_q<=0;packed_index_q<=0;packed_clear_q<=1;unpack_state_q<=FETCH;
            building_q<=0;selector_q<=0;row_q<=0;fault_o<=0;
        end else if((word_valid_i && !word_ready_o) ||
                    (model_locked_i && ((body_read_i && body_address_i>=3328) ||
                                        (head_read_i && head_address_i>=3328)))) fault_o<=1;
        else begin
            if(packed_clear_q) begin
                if(packed_index_q==9) begin packed_clear_q<=0;packed_index_q<=0;end
                else packed_index_q<=packed_index_q+1;
            end
            if(building_q) begin
                case(unpack_state_q)
                    FETCH: begin
                        if(packed_index_q>=10) fault_o<=1;
                        else unpack_state_q<=MERGE;
                    end
                    MERGE: begin
                        if(unpack_bits_q>=10) fault_o<=1;
                        unpack_q<={256'd0,unpack_q[9:0]} | ({10'd0,packed_read_q} << unpack_bits_q[3:0]);
                        unpack_bits_q<=unpack_bits_q+9'd256;
                        packed_index_q<=packed_index_q+1;
                        unpack_state_q<=EMIT;
                    end
                    EMIT: begin
                        if(unpack_bits_q>=10) begin
                            if(unpack_q[9:0]==10'h200) fault_o<=1;
                            unpack_q<=unpack_q>>10;
                            unpack_bits_q<=unpack_bits_q-9'd10;
                            if(row_q==255) begin
                                building_q<=0;coefficients_loaded_q[selector_q]<=1;
                                packed_clear_q<=1;packed_index_q<=0;
                            end else row_q<=row_q+1;
                        end else unpack_state_q<=FETCH;
                    end
                    default: fault_o<=1;
                endcase
            end
            if(word_valid_i && word_ready_o) begin
                if(transformer_norm || final_norm) begin
                    if(vector_word==9) begin
                        selector_q<=vector_selector;row_q<=0;building_q<=1;
                        unpack_q<=0;unpack_bits_q<=0;packed_index_q<=0;unpack_state_q<=FETCH;
                    end
                end
                if(word_index_i==214248 || word_index_i==214249) begin
                    for(integer j=0;j<8;j=j+1) begin
                        if(word_index_i==214248 || j<4) begin
                            metadata_q[(word_index_i==214248 ? 0 : 8)+j]<=
                                {word_data_i[j*32 +:8],word_data_i[j*32+8 +:16]};
                            metadata_loaded_q[(word_index_i==214248 ? 0 : 8)+j]<=1;
                            if(word_data_i[j*32+24 +:8]!=0 || word_data_i[j*32+8 +:16]==0 || word_data_i[j*32+23]) fault_o<=1;
                        end else if(word_data_i[j*32 +:32]!=0) fault_o<=1;
                    end
                end
                if(word_index_i==214260) begin
                    metadata_q[12]<={word_data_i[7:0],word_data_i[23:8]};metadata_loaded_q[12]<=1;
                    if(word_data_i[255:24]!=0 || word_data_i[23:8]==0 || word_data_i[23]) fault_o<=1;
                end
            end
        end
    end
endmodule
`default_nettype wire

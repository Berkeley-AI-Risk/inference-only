// PRIVATE fixed model-memory address decoder for qwen3-private-model-layout-v1.
// No port on this module may be mapped to the application interface. Its input
// comes only from fixed internal scheduling. It does not enforce that schedule,
// issue HBM reads, authenticate bytes, or route arithmetic operands itself.
//
// One registered response, one accepted request per cycle when not stalled.
// Invalid encodings produce an error with zero address/length. CLEAR/reset
// discard this module's queued response; an external reader must separately
// drain/cancel any memory transactions it has already issued.
module qwen_model_address (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire request_valid,
    output wire request_ready,
    input wire [2:0] request_region,    // 0 codes, 1 scales, 2 norm, 3 embed, 4 rope
    input wire [2:0] request_operation, // projection kind / norm kind / zero
    input wire [4:0] request_layer,
    input wire [17:0] request_index,   // tile / zero / token ID / tape position
    output wire result_valid,
    input wire result_ready,
    output wire [31:0] result_address, // byte offset inside private model memory
    output wire [17:0] result_bytes,
    output wire result_error
);
    reg pending;
    reg [31:0] address_reg;
    reg [17:0] bytes_reg;
    reg error_reg;
    wire enabled = rst_n && !clear;
    assign request_ready = enabled && (!pending || result_ready);
    assign result_valid = enabled && pending;
    assign result_address = result_valid ? address_reg : 32'b0;
    assign result_bytes = result_valid ? bytes_reg : 18'b0;
    assign result_error = result_valid && error_reg;

    // Constant strides: shifts/adds, not software-selected dimensions.
    wire [31:0] layer_wide = {27'b0, request_layer};
    wire [31:0] index_wide = {14'b0, request_index};
    wire [31:0] layer_codes = (layer_wide << 25) + (layer_wide << 24);
    wire [31:0] layer_scales = (layer_wide << 16) + (layer_wide << 14);
    wire [31:0] layer_norms = (layer_wide << 13) + (layer_wide << 9);
    reg [31:0] codes_base, scales_base;
    reg [12:0] tile_count;
    reg [31:0] decoded_address;
    reg [17:0] decoded_bytes;
    reg decoded_error;

    always @* begin
        codes_base = layer_codes;
        scales_base = 32'd1720451072 + layer_scales;
        tile_count = 13'd64;
        case (request_operation)
            0: begin end
            1: begin
                codes_base = layer_codes + 32'd4194304;
                scales_base = scales_base + 32'd8192;
                tile_count = 13'd32;
            end
            2: begin
                codes_base = layer_codes + 32'd6291456;
                scales_base = scales_base + 32'd12288;
                tile_count = 13'd32;
            end
            3: begin
                codes_base = layer_codes + 32'd8388608;
                scales_base = scales_base + 32'd16384;
            end
            4: begin
                codes_base = layer_codes + 32'd12582912;
                scales_base = scales_base + 32'd24576;
                tile_count = 13'd192;
            end
            5: begin
                codes_base = layer_codes + 32'd25165824;
                scales_base = scales_base + 32'd49152;
                tile_count = 13'd192;
            end
            6: begin
                codes_base = layer_codes + 32'd37748736;
                scales_base = scales_base + 32'd73728;
            end
            7: begin
                // Tied output head is global: layer bits do not select data.
                codes_base = 32'd1409286144;
                scales_base = 32'd1722744832;
                tile_count = 13'd4748;
            end
        endcase
        decoded_address = 0;
        decoded_bytes = 0;
        decoded_error = 1;
        case (request_region)
            0, 1: begin
                if ((request_operation == 7 || request_layer < 28)
                        && request_index < {5'b0, tile_count}) begin
                    decoded_error = 0;
                    if (request_region == 1) begin
                        decoded_address = scales_base + (index_wide << 7);
                        decoded_bytes = 18'd128;
                    end else if (request_operation == 6) begin
                        decoded_address = codes_base + (index_wide << 17) + (index_wide << 16);
                        decoded_bytes = 18'd196608;
                    end else begin
                        decoded_address = codes_base + (index_wide << 16);
                        decoded_bytes = 18'd65536;
                    end
                end
            end
            2: begin
                if (request_index == 0 && (request_operation == 4
                        || (request_operation < 4 && request_layer < 28))) begin
                    decoded_error = 0;
                    decoded_address = 32'd1723400192 + layer_norms;
                    decoded_bytes = 18'd4096;
                    case (request_operation)
                        0: begin end
                        1: begin decoded_address = decoded_address + 32'd4096; decoded_bytes = 18'd256; end
                        2: begin decoded_address = decoded_address + 32'd4352; decoded_bytes = 18'd256; end
                        3: decoded_address = decoded_address + 32'd4608;
                        4: decoded_address = 32'd1723643904;
                        default: begin end
                    endcase
                end
            end
            3: begin
                if (request_operation == 0 && request_index < 151936) begin
                    decoded_error = 0;
                    decoded_address = 32'd1723662336 + (index_wide << 12);
                    decoded_bytes = 18'd4096;
                end
            end
            4: begin
                if (request_operation == 0 && request_index < 32768) begin
                    decoded_error = 0;
                    decoded_address = 32'd2345992192 + (index_wide << 8);
                    decoded_bytes = 18'd256;
                end
            end
            default: begin end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            pending <= 0;
            address_reg <= 0;
            bytes_reg <= 0;
            error_reg <= 0;
        end else if (request_ready) begin
            pending <= request_valid;
            if (request_valid) begin
                address_reg <= decoded_address;
                bytes_reg <= decoded_bytes;
                error_reg <= decoded_error;
            end
        end
    end
endmodule

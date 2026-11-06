`timescale 1ns/1ps
`default_nettype none
// Connected SWIC memory-admission prototype, single trusted clock domain.
// Private seams only. Not a complete Tang top or public command interface.
// Actual DDR-controller/CDC and token-machine integration remain separate.
module swic_verified_memory (
    input wire clk,reset_n,
    input wire boot_valid_i,boot_last_i,
    input wire [7:0] boot_byte_i,
    output wire boot_ready_o,
    input wire readback_valid_i,readback_last_i,
    input wire [7:0] readback_byte_i,
    output wire readback_ready_o,
    output wire model_ready_o,fault_o,
    input wire page_begin_i,
    output wire page_begin_ready_o,
    input wire [10:0] page_i,
    input wire page_fill_valid_i,page_fill_last_i,
    output wire page_fill_ready_o,
    input wire [255:0] page_fill_data_i,
    input wire cancel_read_i,page_read_i,
    input wire [6:0] page_word_i,
    output wire page_read_ready_o,
    output wire page_response_valid_o,
    input wire page_response_ready_i,
    output wire [255:0] page_response_data_o,
    input wire metadata_read_i,
    input wire [11:0] metadata_address_i,
    output wire [191:0] metadata_data_o
);
    wire sealed,admission_fault,image_verified,image_fault,bank_fault;
    wire [255:0] image_sha;
    logic image_started_q,local_fault_q;
    localparam [2:0] IDLE=0,DIGEST_REQUEST=1,DIGEST_CAPTURE=2,ALLOCATE=3,FAILED=7;
    logic [2:0] state_q;
    logic [2:0] digest_word_q;
    logic [10:0] page_q;
    logic [255:0] expected_q;
    wire [31:0] digest_data;
    wire boot_digest_read,page_verified,page_fault,image_ready,page_ready;
    wire [13:0] boot_digest_address;
    wire [191:0] metadata_data;
    wire bank_begin_ready,bank_fill_ready,bank_read_ready,bank_response_valid;
    wire bank_assigned,bank_verified;
    wire [10:0] bank_page;
    wire [255:0] bank_response_data;
    assign fault_o=local_fault_q || admission_fault || image_fault || bank_fault || page_fault;
    assign model_ready_o=sealed && image_verified && page_verified && !fault_o;
    assign page_begin_ready_o=model_ready_o && state_q==IDLE && bank_begin_ready;
    assign page_fill_ready_o=model_ready_o && bank_fill_ready;
    assign page_read_ready_o=model_ready_o && bank_read_ready;
    assign page_response_valid_o=model_ready_o && bank_response_valid;
    assign page_response_data_o=page_response_valid_o ? bank_response_data : 256'd0;
    assign metadata_data_o=model_ready_o ? metadata_data : 192'd0;
    swic_boot_admission u_admission(
        .clk(clk),.reset_n(reset_n),.boot_valid_i(boot_valid_i),.boot_ready_o(boot_ready_o),
        .boot_byte_i(boot_byte_i),.boot_last_i(boot_last_i),.sealed_o(sealed),
        .fail_closed_o(admission_fault),.expected_image_sha_o(image_sha),
        .digest_read_i(boot_digest_read || state_q==DIGEST_REQUEST),
        .digest_address_i(boot_digest_read ? boot_digest_address : {page_q,digest_word_q}),.digest_data_o(digest_data),
        .metadata_read_i(metadata_read_i && model_ready_o),.metadata_address_i(metadata_address_i),.metadata_data_o(metadata_data));
    su_image_check u_image(
        .clk(clk),.reset_n(reset_n),.start_i(sealed && !image_started_q && !fault_o),.expected_sha_i(image_sha),
        .readback_valid_i(readback_valid_i && page_ready),.readback_ready_o(image_ready),
        .readback_byte_i(readback_byte_i),.readback_last_i(readback_last_i),
        .verified_o(image_verified),.fault_o(image_fault));
    assign readback_ready_o=image_ready && page_ready;
    su_page_table_check u_pages(
        .clk(clk),.reset_n(reset_n),.start_i(sealed && !image_started_q && !fault_o),
        .readback_valid_i(readback_valid_i && image_ready),.readback_ready_o(page_ready),
        .readback_byte_i(readback_byte_i),.readback_last_i(readback_last_i),
        .digest_read_o(boot_digest_read),.digest_address_o(boot_digest_address),.digest_data_i(digest_data),
        .verified_o(page_verified),.fault_o(page_fault));
    board1_verified_page_bank u_bank(
        .clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_read_i),
        .begin_valid_i(state_q==ALLOCATE && model_ready_o),.begin_ready_o(bank_begin_ready),
        .begin_page_i(page_q),.expected_digest_i(expected_q),
        .fill_valid_i(page_fill_valid_i && model_ready_o),.fill_ready_o(bank_fill_ready),
        .fill_data_i(page_fill_data_i),.fill_last_i(page_fill_last_i),
        .read_valid_i(page_read_i && model_ready_o),.read_ready_o(bank_read_ready),.read_word_i(page_word_i),
        .response_valid_o(bank_response_valid),.response_ready_i(page_response_ready_i && model_ready_o),
        .response_data_o(bank_response_data),.assigned_o(bank_assigned),.verified_o(bank_verified),
        .page_o(bank_page),.fault_o(bank_fault));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin image_started_q<=0;local_fault_q<=0;state_q<=IDLE;digest_word_q<=0;page_q<=0;expected_q<=0;end
        else if(fault_o) begin state_q<=FAILED;local_fault_q<=1;end
        else begin
            if(sealed) image_started_q<=1;
            case(state_q)
                IDLE: if(page_begin_i && page_begin_ready_o) begin
                    if(page_i>=1774) begin local_fault_q<=1;state_q<=FAILED;end
                    else begin page_q<=page_i;digest_word_q<=0;expected_q<=0;state_q<=DIGEST_REQUEST;end
                end
                DIGEST_REQUEST: state_q<=DIGEST_CAPTURE;
                DIGEST_CAPTURE: begin
                    expected_q<={expected_q[223:0],digest_data};
                    if(digest_word_q==7) state_q<=ALLOCATE;
                    else begin digest_word_q<=digest_word_q+1;state_q<=DIGEST_REQUEST;end
                end
                ALLOCATE: if(bank_begin_ready) state_q<=IDLE;
                FAILED: local_fault_q<=1;
                default: begin state_q<=FAILED;local_fault_q<=1;end
            endcase
        end
    end
endmodule
`default_nettype wire

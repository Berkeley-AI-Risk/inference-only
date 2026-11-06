`timescale 1ns/1ps
module swic_qspi_boot_source(
    input wire trusted_clk_i,trusted_reset_n_i,core_clk_i,core_reset_n_i,
    input wire allow_model_i,
    output wire byte_valid_o,
    input wire byte_ready_i,
    output wire [7:0] byte_o,
    output wire byte_model_o,byte_last_o,
    output wire fail_closed_o,
    output wire qspi_cs_n_o,qspi_sck_o,
    input wire [3:0] qspi_dq_i,
    output wire [3:0] qspi_dq_o,qspi_dq_oe_o
);

    // TEST ONLY: replaces the fixed SPI/FIFO source with the identical tagged
    // byte sequence at core-clock speed. All crypto, DDR write/readback, norm
    // extraction, page authentication, UART and neural arithmetic remain real.
    // A separate regression uses the real SPI/FIFO and electrical-pin model.
    reg [7:0] image[0:7265983],slot[0:262143];
    reg [1:0] phase_q=0;
    reg [22:0] offset_q=0;
    integer case_id;string fixtures,path;
    initial begin
        if(!$value$plusargs("CASE=%d",case_id)) case_id=0;
        if(!$value$plusargs("FIXTURES=%s",fixtures)) $fatal(1,"fixtures missing");
        path=$sformatf("%s/case-%0d.image.hex",fixtures,case_id==2?0:case_id);$readmemh(path,image);
        path=$sformatf("%s/case-%0d.slot.hex",fixtures,case_id);$readmemh(path,slot);
    end
    assign byte_valid_o=core_reset_n_i && (phase_q==0 || phase_q==2);
    assign byte_o=phase_q==0 ? slot[offset_q[17:0]] : image[offset_q];
    assign byte_model_o=phase_q==2;
    assign byte_last_o=phase_q==0 ? offset_q==262143 : offset_q==7265983;
    assign fail_closed_o=0;
    assign qspi_cs_n_o=1;assign qspi_sck_o=0;assign qspi_dq_o=4'hc;assign qspi_dq_oe_o=0;
    always @(posedge core_clk_i or negedge core_reset_n_i) begin
        if(!core_reset_n_i) begin phase_q<=0;offset_q<=0;end
        else if(phase_q==1 && allow_model_i) begin phase_q<=2;offset_q<=0;end
        else if(byte_valid_o && byte_ready_i) begin
            if(phase_q==0 && offset_q==262143) begin phase_q<=1;offset_q<=0;end
            else if(phase_q==2 && offset_q==7265983) phase_q<=3;
            else offset_q<=offset_q+1;
        end
    end
endmodule
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none
// Two fixed legacy read-only SPI transactions. No package-controlled opcode,
// flash address, length, writes, program/erase operation or runtime selection.
// A tagged byte crosses the existing registered four-entry native async FIFO.
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
    localparam [2:0] WAIT_CORE=0,FRAME_START=1,FRAME=2,WAIT_SIGNATURE=3,
        MODEL_START=4,MODEL=5,DONE=6,FAILED=7;
    wire common_reset_n=trusted_reset_n_i && core_reset_n_i;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] slow_release_q,core_release_q;
    always_ff @(posedge trusted_clk_i or negedge common_reset_n)
        if(!common_reset_n) slow_release_q<=0;else slow_release_q<={slow_release_q[1:0],1'b1};
    always_ff @(posedge core_clk_i or negedge common_reset_n)
        if(!common_reset_n) core_release_q<=0;else core_release_q<={core_release_q[1:0],1'b1};
    wire slow_reset_n=slow_release_q[2],fifo_core_reset_n=core_release_q[2];
    (* async_reg="true",syn_preserve=1 *) logic core_up_meta_q,core_up_sync_q;
    (* async_reg="true",syn_preserve=1 *) logic allow_meta_q,allow_sync_q;
    (* async_reg="true",syn_preserve=1 *) logic fault_meta_q,fault_sync_q;
    logic [2:0] state_q;
    logic slow_fault_q;
    logic [25:0] watchdog_q;
    wire fbusy,ffault,fvalid,flast,mbusy,mfault,mvalid,mlast;
    wire [7:0] fdata,mdata;
    wire fcs,fsck,mcs,msck;
    wire [3:0] fdq,foe,mdq,moe;
    wire fifo_ready;
    wire in_model=state_q==MODEL;
    wire in_frame=state_q==FRAME;
    wire valid=(in_model && mvalid) || (in_frame && fvalid);
    wire last=in_model ? mlast : flast;
    wire [7:0] data=in_model ? mdata : fdata;
    wire transfer=valid && fifo_ready;
    wire [255:0] fifo_data;
    wire fifo_valid;
    swic_read03_master #(.READ_BASE(24'hf00000),.READ_BYTES(24'h040000)) u_frame(
        .clk_i(trusted_clk_i),.reset_n_i(slow_reset_n),.start_i(state_q==FRAME_START),
        .busy_o(fbusy),.fault_o(ffault),.data_valid_o(fvalid),.data_ready_i(fifo_ready && in_frame),
        .data_o(fdata),.data_last_o(flast),.qspi_cs_n_o(fcs),.qspi_sck_o(fsck),
        .qspi_dq1_i(qspi_dq_i[1]),.qspi_dq_o(fdq),.qspi_dq_oe_o(foe));
    swic_read03_master u_image(
        .clk_i(trusted_clk_i),.reset_n_i(slow_reset_n),.start_i(state_q==MODEL_START),
        .busy_o(mbusy),.fault_o(mfault),.data_valid_o(mvalid),.data_ready_i(fifo_ready && in_model),
        .data_o(mdata),.data_last_o(mlast),.qspi_cs_n_o(mcs),.qspi_sck_o(msck),
        .qspi_dq1_i(qspi_dq_i[1]),.qspi_dq_o(mdq),.qspi_dq_oe_o(moe));
    board1_qspi_async_word_fifo4 u_loader_cdc(
        .write_clk_i(trusted_clk_i),.write_reset_n_i(slow_reset_n),
        .write_data_i({246'd0,last,in_model,data}),.write_valid_i(valid && !slow_fault_q),.write_ready_o(fifo_ready),
        .read_clk_i(core_clk_i),.read_reset_n_i(fifo_core_reset_n),
        .read_data_o(fifo_data),.read_valid_o(fifo_valid),.read_ready_i(byte_ready_i && !fail_closed_o));
    assign byte_valid_o=fifo_valid && !fail_closed_o;
    assign byte_o=fifo_data[7:0];assign byte_model_o=fifo_data[8];assign byte_last_o=fifo_data[9];
    assign fail_closed_o=fault_sync_q;
    wire select_model=state_q>=MODEL_START && state_q<=DONE;
    assign qspi_cs_n_o=slow_fault_q ? 1'b1 : (select_model ? mcs : fcs);
    assign qspi_sck_o=slow_fault_q ? 1'b0 : (select_model ? msck : fsck);
    assign qspi_dq_o=select_model ? mdq : fdq;
    assign qspi_dq_oe_o=slow_fault_q ? 4'd0 : (select_model ? moe : foe);
    always_ff @(posedge core_clk_i or negedge common_reset_n) begin
        if(!common_reset_n) begin fault_meta_q<=0;fault_sync_q<=0;end
        else begin fault_meta_q<=slow_fault_q;fault_sync_q<=fault_meta_q;end
    end
    always_ff @(posedge trusted_clk_i or negedge slow_reset_n) begin
        if(!slow_reset_n) begin
            state_q<=WAIT_CORE;slow_fault_q<=0;watchdog_q<=0;
            core_up_meta_q<=0;core_up_sync_q<=0;allow_meta_q<=0;allow_sync_q<=0;
        end else begin
            core_up_meta_q<=fifo_core_reset_n;core_up_sync_q<=core_up_meta_q;
            allow_meta_q<=allow_model_i;allow_sync_q<=allow_meta_q;
            if(transfer || state_q==FRAME_START || state_q==MODEL_START) watchdog_q<=0;
            else if(state_q!=DONE && state_q!=FAILED) watchdog_q<=watchdog_q+1;
            if(ffault || mfault || (watchdog_q==26'd49999999 && !transfer)) begin state_q<=FAILED;slow_fault_q<=1;end
            else case(state_q)
                WAIT_CORE: if(core_up_sync_q) state_q<=FRAME_START;
                FRAME_START: state_q<=FRAME;
                FRAME: if(transfer && flast) state_q<=WAIT_SIGNATURE;
                WAIT_SIGNATURE: if(allow_sync_q && !fbusy && fcs) state_q<=MODEL_START;
                MODEL_START: state_q<=MODEL;
                MODEL: if(transfer && mlast) state_q<=DONE;
                DONE: begin end
                default: begin state_q<=FAILED;slow_fault_q<=1;end
            endcase
        end
    end
endmodule
`default_nettype wire

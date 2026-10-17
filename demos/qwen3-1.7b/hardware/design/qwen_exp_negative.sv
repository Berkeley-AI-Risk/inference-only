// PRIVATE fixed softmax exponential approximation exp(-distance).
// Nonnegative FP32 input, +infinity maps to zero; negative/NaN inputs fault.
// Fixed ROM, FP32 distance*log2(e), RNE UQ8.24, 1024-piece interpolation,
// FP32 power-of-two scaling including gradual underflow. Nine-cycle pipeline.
module qwen_exp_negative #(
    parameter ROM_FILE="softmax-exp2.hex"
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire in_valid,
    output wire in_ready,
    input wire [31:0] distance,
    output wire out_valid,
    input wire out_ready,
    output reg [31:0] result,
    output reg out_error
);
    reg [8:0] valid,bad,clipped;
    wire advance=(!valid[8] || out_ready) && rst_n && !clear;
    assign in_ready=advance;
    assign out_valid=valid[8] && rst_n && !clear;
    wire input_bad=(distance[31] && |distance[30:0]) ||
        ((&distance[30:23]) && |distance[22:0]);
    wire input_clip=!distance[31] && distance[30:0]>=31'h42d00000;
    wire [31:0] safe_distance=(input_bad || input_clip) ? 32'b0 : distance;
    wire [32:0] d_rec,log_rec,t_rec;
    wire t_error;
    wire [31:0] t_bits;
    fNToRecFN #(8,24) decode_d(.in(safe_distance),.out(d_rec));
    fNToRecFN #(8,24) decode_log(.in(32'h3fb8aa3b),.out(log_rec));
    qwen_fp32_mul_stage multiply_log(.clk(clk),.advance(advance),.a(d_rec),.b(log_rec),
        .in_error(1'b0),.result(t_rec),.out_error(t_error));
    recFNToFN #(8,24) encode_t(.in(t_rec),.out(t_bits));

    function automatic [31:0] fixed24(input [31:0] value);
        reg [23:0] mantissa;
        reg [4:0] shift;
        reg [31:0] q,mask;
        begin
            mantissa={1'b1,value[22:0]};shift=0;q=0;mask=0;
            if(value[30:23]>=8'd126 && value[30:23]<=8'd134)
                q={8'b0,mantissa} << (value[30:23]-8'd126);
            else if(value[30:23]>=8'd102 && value[30:23]<8'd126) begin
                shift=5'(8'd126-value[30:23]);q={8'b0,mantissa} >> shift;
                mask=(32'b1 << (shift-1'b1))-1'b1;
                if(mantissa[shift-1'b1] && ((|({8'b0,mantissa}&mask)) || q[0]))q=q+1'b1;
            end
            fixed24=q;
        end
    endfunction
    function automatic [31:0] fraction14(input [13:0] value);
        integer i,leading;
        reg [7:0] exponent;
        reg [31:0] shifted;
        begin
            leading=0;
            for(i=0;i<14;i=i+1)if(value[i])leading=i;
            exponent=8'(113+leading);shifted={18'b0,value} << (23-leading);
            fraction14=value==0 ? 32'b0 : {1'b0,exponent,shifted[22:0]};
        end
    endfunction
    function automatic [31:0] scale_power2(input [31:0] value,input [7:0] power);
        reg [7:0] exponent,shift;
        reg [23:0] mantissa;
        reg [31:0] q,mask;
        begin
            exponent=value[30:23];mantissa={1'b1,value[22:0]};shift=0;q=0;mask=0;
            if(power<exponent)scale_power2={1'b0,8'(exponent-power),value[22:0]};
            else begin
                shift=power-exponent+1'b1;
                if(shift<=24) begin
                    q={8'b0,mantissa} >> shift;mask=(32'b1 << (shift-1'b1))-1'b1;
                    if(mantissa[shift[4:0]-5'd1] && ((|({8'b0,mantissa}&mask)) || q[0]))q=q+1'b1;
                end
                scale_power2=q;
            end
        end
    endfunction

    reg [31:0] fixed2;
    reg error2,error3;
    (* rom_style="block" *) reg [63:0] coefficients [0:1023];
    initial $readmemh(ROM_FILE,coefficients);
    reg [63:0] coefficient3;
    reg [31:0] residual3;
    reg [7:0] power3,power4,power5,power6,power7;
    wire [32:0] base3,slope3,r3,interpolated,corrected;
    reg [32:0] base4,base5;
    wire interpolation_error,correction_error;
    wire [31:0] correction_bits;
    fNToRecFN #(8,24) decode_base(.in(coefficient3[63:32]),.out(base3));
    fNToRecFN #(8,24) decode_slope(.in(coefficient3[31:0]),.out(slope3));
    fNToRecFN #(8,24) decode_r(.in(residual3),.out(r3));
    qwen_fp32_mul_stage interpolate(.clk(clk),.advance(advance),.a(slope3),.b(r3),
        .in_error(error3),.result(interpolated),.out_error(interpolation_error));
    qwen_fp32_add_stage correct(.clk(clk),.advance(advance),.a(base5),.b(interpolated),
        .in_error(interpolation_error),.result(corrected),.out_error(correction_error));
    recFNToFN #(8,24) encode_correction(.in(corrected),.out(correction_bits));
    always @(posedge clk) begin
        if(!rst_n || clear)begin valid<=0;bad<=0;clipped<=0;result<=0;out_error<=0;end
        else if(advance) begin
            valid<={valid[7:0],in_valid};bad<={bad[7:0],input_bad};clipped<={clipped[7:0],input_clip};
            fixed2<=fixed24(t_bits);
            error2<=t_error || (t_bits[31] && |t_bits[30:0]) || t_bits[30:23]>8'd134;
            coefficient3<=coefficients[fixed2[23:14]];residual3<=fraction14(fixed2[13:0]);
            power3<=fixed2[31:24];error3<=error2;
            base4<=base3;base5<=base4;
            power4<=power3;power5<=power4;power6<=power5;power7<=power6;
            result<=clipped[7] ? 32'b0 : scale_power2(correction_bits,power7);
            out_error<=bad[7] || correction_error || correction_bits<32'h3f000000 || correction_bits>32'h3f800000;
        end
    end
endmodule

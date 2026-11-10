// Private 16-bit weight port over an untrusted 256-bit DDR read channel.
// The boot controller owns DDR reset. CLEAR drains an accepted DDR read
// before any new request can use its response. A page is accessible only
// after all 4096 bytes match the private ROM digest of this page number.
module authenticated_weight_page(
  input wire clk, input wire rst_n, input wire clear_i,
  input wire req_i, input wire [20:0] word_addr_i,
  output wire valid_o, output wire error_o, output wire signed [15:0] word_o,
  output wire mem_req_o, input wire mem_ready_i, output wire [21:0] mem_addr_o,
  input wire mem_valid_i, input wire [255:0] mem_data_i,
  output wire outstanding_o
);
  localparam IDLE=0, FETCH=1, WAIT_DATA=2, SHA_START=3, SHA_WAIT=4,
             COMPARE=5, HIT=6, FAULT=7, DRAIN=8;
  localparam [255:0] IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
  reg [3:0] state;
  reg [9:0] page;
  reg [6:0] beat;
  reg good, pad;
  reg [255:0] digest, first_half, second_half;
  reg [255:0] expected[0:767];
  reg [255:0] expect_q;
  reg [255:0] cache[0:127];
  reg [255:0] cache_q;
  reg [3:0] lane;
  initial $readmemh("page_digest.hex",expected);
  always @(posedge clk) begin
    expect_q <= expected[page];
    cache_q <= cache[word_addr_i[10:4]];
    if(state==WAIT_DATA && mem_valid_i && !clear_i && rst_n)
      cache[beat] <= mem_data_i;
  end
  function automatic [255:0] reverse_bytes(input [255:0] word_in);
    integer i;
    for(i=0;i<32;i=i+1) reverse_bytes[255-i*8 -:8] = word_in[i*8+:8];
  endfunction
  wire [511:0] sha_block = pad ? {8'h80,440'b0,64'd32768} : {first_half,second_half};
  wire sha_done;
  wire [255:0] hashed;
  moe_sha256_core sha(.clk(clk),.rst_n(rst_n),.clear(clear_i),.start(state==SHA_START),
    .block(sha_block),.state_in(digest),.done(sha_done),.state_out(hashed),.busy(),.nz());
  assign valid_o = state==HIT && !clear_i && rst_n;
  assign error_o = state==FAULT && !clear_i && rst_n;
  assign word_o = valid_o ? cache_q[16*lane+:16] : 16'sd0;
  assign mem_req_o = state==FETCH && !clear_i && rst_n;
  assign mem_addr_o = {page,beat,5'b0};
  assign outstanding_o = state==WAIT_DATA || state==DRAIN;
  always @(posedge clk) begin
    if(!rst_n) begin
      state<=IDLE; good<=0; pad<=0; page<=0; lane<=0; beat<=0;
      digest<=IV; first_half<=0; second_half<=0;
    end else if(clear_i) begin
      state<=outstanding_o && !mem_valid_i ? DRAIN : IDLE;
      good<=0; pad<=0;
    end else case(state)
      IDLE: if(req_i) begin
        lane<=word_addr_i[3:0];
        if(word_addr_i[20:11]>=768) state<=FAULT;
        else if(good && page==word_addr_i[20:11]) state<=HIT;
        else begin
          page<=word_addr_i[20:11]; beat<=0; digest<=IV; good<=0; pad<=0; state<=FETCH;
        end
      end
      FETCH: if(mem_ready_i) state<=WAIT_DATA;
      WAIT_DATA: if(mem_valid_i) begin
        if(beat[0]) begin second_half<=reverse_bytes(mem_data_i); state<=SHA_START; end
        else begin first_half<=reverse_bytes(mem_data_i); beat<=beat+1'b1; state<=FETCH; end
      end
      SHA_START: state<=SHA_WAIT;
      SHA_WAIT: if(sha_done) begin
        digest<=hashed;
        if(pad) state<=COMPARE;
        else if(beat==127) begin pad<=1; state<=SHA_START; end
        else begin beat<=beat+1'b1; state<=FETCH; end
      end
      COMPARE: if(digest==expect_q) begin good<=1; state<=HIT; end else state<=FAULT;
      HIT, FAULT: state<=IDLE;
      DRAIN: if(mem_valid_i) state<=IDLE;
      default: begin state<=FAULT; good<=0; end
    endcase
  end
endmodule

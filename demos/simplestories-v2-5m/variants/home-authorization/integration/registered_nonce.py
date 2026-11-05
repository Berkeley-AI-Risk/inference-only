"""Private registered nonce data; validity and public masked output unchanged."""

def once(text,old,new):
    assert text.count(old)==1,old
    return text.replace(old,new)


def frontend(text):
    text=once(text,'    output wire [255:0] nonce_o,',
              '    output wire [255:0] nonce_o,\n    output wire [255:0] private_nonce_data_o,')
    return once(text,"    assign nonce_o=nonce_valid_o ? nonce_q : 256'd0;",
                "    assign nonce_o=nonce_valid_o ? nonce_q : 256'd0;\n    assign private_nonce_data_o=nonce_q;")


def wrapper(text):
    text=once(text,'    wire [255:0] nonce;','    wire [255:0] nonce,registered_nonce;')
    text=once(text,'.private_nonce_i(nonce)', '.private_nonce_i(registered_nonce)')
    return once(text,'.nonce_valid_o(nonce_valid),.nonce_o(nonce),.fault_o(nonce_fault),',
                '.nonce_valid_o(nonce_valid),.nonce_o(nonce),.private_nonce_data_o(registered_nonce),.fault_o(nonce_fault),')


def testbench(text):
    text=once(text,'    wire [255:0]nonce,nonce_hash_digest;',
              '    wire [255:0]nonce,nonce_hash_digest,registered_nonce;')
    text=once(text,'.private_nonce_i(nonce)', '.private_nonce_i(registered_nonce)')
    text=once(text,'.nonce_valid_o(nv),.nonce_o(nonce),.fault_o(nonce_fault),',
              '.nonce_valid_o(nv),.nonce_o(nonce),.private_nonce_data_o(registered_nonce),.fault_o(nonce_fault),')
    assertion='''
    always @(negedge dut.core_clk) begin
        if(nv && nonce!==registered_nonce) $fatal(1,"valid nonce data differs");
        if(!nv && nonce!==256'd0) $fatal(1,"public nonce mask changed");
    end
'''
    return once(text,'\nendmodule','\n'+assertion+'endmodule')

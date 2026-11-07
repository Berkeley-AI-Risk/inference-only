"""Bind the unchanged AES controllers to a narrow portable lookup model."""
from pathlib import Path
import hashlib,json,re

def multiply(a,b):
    z=0
    for _ in range(8):
        if b&1:z^=a
        a=((a<<1)^(0x11b if a&128 else 0))&255;b>>=1
    return z
def truth(x):
    inv=next((n for n in range(1,256) if multiply(x,n)==1),0);out=0
    for bit in range(8):
        value=(0x63>>bit)&1
        for offset in (0,4,5,6,7):value^=(inv>>((bit+offset)%8))&1
        out|=value<<bit
    return out

def install(source,order):
    wrappers=[];receipt=[]
    expected=bytes(truth(i) for i in range(256))
    for file,module in [('tang_private_aes256.sv','tang_private_aes_sbox_rom2'),('tang_private_aes256_fixed2.sv','tang_private_kv_aes_sbox_rom2')]:
        path=source/file;text=path.read_text();start=text.index('module '+module+' (');end=text.index('endmodule',start)+len('endmodule');old=text[start:end]
        settings=[".READ_MODE0(1'b0)",".READ_MODE1(1'b0)",'.BIT_WIDTH_0(8)','.BIT_WIDTH_1(8)',
                  ".WREA(1'b0)",".WREB(1'b0)",".CEA(1'b1)",".CEB(1'b1)",".OCEA(1'b1)",".OCEB(1'b1)",
                  ".RESETA(1'b0)",".RESETB(1'b0)",".DIA(16'd0)",".DIB(16'd0)",".BLK_SEL_0(3'd0)",".BLK_SEL_1(3'd0)",'.CLKA(clk)','.CLKB(clk)',".BLKSELA(3'd0)",".BLKSELB(3'd0)",
                  ".ADA({3'd0,address_a_i,3'd0})",".ADB({3'd0,address_b_i,3'd0})"]
        if not all(old.count(s)==1 for s in settings):raise ValueError('Unsupported AES lookup binding '+module)
        chunks=re.findall(r"\.INIT_RAM_([0-9A-F]{2})\(256'h([a-fA-F0-9]{64})\)",old)
        if [int(i,16) for i,_ in chunks]!=list(range(8)):raise ValueError('Unexpected AES table initialization')
        table=b''.join(int(v,16).to_bytes(32,'little') for _,v in chunks)
        if table!=expected:raise ValueError('Published AES table differs from independent finite-field truth')
        changed=text[:start]+'// Read-only AES lookup binding is supplied by public_lookup_bindings.sv.\n'+text[end:]
        path.write_text(changed)
        wrappers.append('''module MODULE_NAME (
    input wire clk,
    input wire [7:0] address_a_i,address_b_i,
    output wire [7:0] value_a_o,value_b_o
);
    combined_public_aes_lookup_sim u_lookup(.clk(clk),.address_a_i(address_a_i),.address_b_i(address_b_i),
        .data_a_o(value_a_o),.data_b_o(value_b_o));
endmodule
'''.replace('MODULE_NAME',module))
        receipt.append({'source_file':file,'original_module':module,'original_file_sha256':hashlib.sha256(text.encode()).hexdigest(),
                        'AES_controller_source_unchanged':True,'table_sha256':hashlib.sha256(table).hexdigest(),
                        'generated_file_sha256':hashlib.sha256(changed.encode()).hexdigest(),'caller_settings_checked':settings})
    name='public_lookup_bindings.sv';(source/name).write_text('`timescale 1ns/1ps\n`default_nettype none\n'+'\n'.join(wrappers)+'\n`default_nettype wire\n');order.append(name)
    (source/'LOOKUP-BINDINGS.json').write_text(json.dumps({'scope':'Two always-enabled, read-only, synchronous eight-bit AES lookup ports; one read edge','entries':receipt,'generic_vendor_RAM_model':False},indent=2,sort_keys=True)+'\n')

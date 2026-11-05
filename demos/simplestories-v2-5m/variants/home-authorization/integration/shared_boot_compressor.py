"""Opt-in compressor sharing for DDR-image and fixed-LUT authentication.

Each SHA stream retains its own padding, block buffer and chaining state.
Only the 64-round compression datapath is arbitrated at block boundaries.
Both digest comparisons and the existing byte-stream interlock remain intact.
"""
from pathlib import Path
import xml.etree.ElementTree as ET

FILES = {'swic/su_sha256.sv', 'swic/su_image_check.sv', 'swic/swic_ddr_boot.sv'}
PORTS = '''
    output wire shared_request_o,
    output wire [511:0] shared_block_o,
    output wire [255:0] shared_state_o,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i'''

ARBITER = '''
// Private, two-client compression arbiter. Requests may wait under backpressure.
// The selected block and chaining state are sampled together at acceptance.
module swic_boot_compressor_mux(
    input wire clk,reset_n,
    input wire request0_i,request1_i,
    input wire [511:0] block0_i,block1_i,
    input wire [255:0] state0_i,state1_i,
    output wire accept0_o,accept1_o,done0_o,done1_o,
    output wire [255:0] digest_o,
    output wire fault_o
);
    logic occupied_q,owner_q,last_owner_q,fault_q;
    wire busy,done;
    wire choose1=request1_i && (!request0_i || !last_owner_q);
    wire available=!occupied_q && !busy && !done && !fault_q;
    assign accept0_o=reset_n && available && request0_i && !choose1;
    assign accept1_o=reset_n && available && request1_i && choose1;
    assign done0_o=reset_n && occupied_q && !owner_q && done && !fault_q;
    assign done1_o=reset_n && occupied_q && owner_q && done && !fault_q;
    assign fault_o=fault_q;
    board1_sha256_compact_compress u_compress(
        .clk_i(clk),.reset_n_i(reset_n),.start_i(accept0_o || accept1_o),
        .block_i(choose1 ? block1_i : block0_i),
        .state_i(choose1 ? state1_i : state0_i),
        .busy_o(busy),.done_o(done),.state_o(digest_o));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin occupied_q<=0;owner_q<=0;last_owner_q<=1;fault_q<=0;end
        else begin
            if((busy || done) && !occupied_q) fault_q<=1;
            if(accept0_o || accept1_o) begin
                occupied_q<=1;owner_q<=accept1_o;last_owner_q<=accept1_o;
            end
            if(done && occupied_q) occupied_q<=0;
        end
    end
endmodule
'''


def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)


def transform(name, text):
    if name == 'swic/su_sha256.sv':
        text = replace_once(text, '    parameter integer MAX_BYTES=8000000',
                            "    parameter bit USE_SHARED_COMPRESSOR=1'b0,\n    parameter integer MAX_BYTES=8000000")
        text = replace_once(text, '    output logic [255:0] digest_o\n);',
                            '    output logic [255:0] digest_o,' + PORTS + '\n);')
        first = text.index('    board1_sha256_compact_compress u_compress(')
        last = text.index('    always_ff ', first)
        local = text[first:last]
        replacement = '''    wire compressor_accept=USE_SHARED_COMPRESSOR ? shared_accept_i : 1'b1;
    assign shared_request_o=USE_SHARED_COMPRESSOR && state_q==LAUNCH && !fault_o;
    assign shared_block_o=block_q;
    assign shared_state_o=chain_q;
    generate if(USE_SHARED_COMPRESSOR) begin:g_shared_compressor
        assign compressor_busy=1'b0;
        assign compressor_done=shared_done_i;
        assign compressor_digest=shared_digest_i;
    end else begin:g_local_compressor
''' + local + '''    end endgenerate
'''
        text = text[:first] + replacement + text[last:]
        return replace_once(text, '                LAUNCH: state_q<=WAIT_HASH;',
                            '                LAUNCH: if(compressor_accept) state_q<=WAIT_HASH;')
    if name == 'swic/su_image_check.sv':
        text = replace_once(text, 'module su_image_check (',
                            "module su_image_check #(parameter bit USE_SHARED_COMPRESSOR=1'b0) (")
        text = replace_once(text, '    output wire fault_o\n);',
                            '    output wire fault_o,' + PORTS + '\n);')
        text = replace_once(text, 'su_sha256 #(.MAX_BYTES(IMAGE_BYTES)) u_sha(',
                            'su_sha256 #(.MAX_BYTES(IMAGE_BYTES),.USE_SHARED_COMPRESSOR(USE_SHARED_COMPRESSOR)) u_sha(')
        return replace_once(text, '.busy_o(sha_busy),.done_o(sha_done),.fault_o(sha_fault),.digest_o(sha_digest));',
                            '''.busy_o(sha_busy),.done_o(sha_done),.fault_o(sha_fault),.digest_o(sha_digest),
        .shared_request_o(shared_request_o),.shared_block_o(shared_block_o),.shared_state_o(shared_state_o),
        .shared_accept_i(shared_accept_i),.shared_done_i(shared_done_i),.shared_digest_i(shared_digest_i));''')
    if name == 'swic/swic_ddr_boot.sv':
        text = replace_once(text, ' || lut_fault || norm_fault;',
                            ' || lut_fault || norm_fault || compressor_mux_fault;')
        declaration = '''    wire image_compress_request,lut_compress_request;
    wire image_compress_accept,lut_compress_accept,image_compress_done,lut_compress_done;
    wire [511:0] image_compress_block,lut_compress_block;
    wire [255:0] image_compress_state,lut_compress_state,compress_digest;
    wire compressor_mux_fault;
    swic_boot_compressor_mux u_boot_compressor(
        .clk(clk),.reset_n(reset_n),
        .request0_i(image_compress_request),.request1_i(lut_compress_request),
        .block0_i(image_compress_block),.block1_i(lut_compress_block),
        .state0_i(image_compress_state),.state1_i(lut_compress_state),
        .accept0_o(image_compress_accept),.accept1_o(lut_compress_accept),
        .done0_o(image_compress_done),.done1_o(lut_compress_done),
        .digest_o(compress_digest),.fault_o(compressor_mux_fault));
'''
        text = replace_once(text, '    su_image_check u_image(', declaration +
                            "    su_image_check #(.USE_SHARED_COMPRESSOR(1'b1)) u_image(")
        text = replace_once(text, '.readback_byte_i(readback_byte),.readback_last_i(last_byte),.verified_o(image_verified),.fault_o(image_fault));',
                            '''.readback_byte_i(readback_byte),.readback_last_i(last_byte),.verified_o(image_verified),.fault_o(image_fault),
        .shared_request_o(image_compress_request),.shared_block_o(image_compress_block),.shared_state_o(image_compress_state),
        .shared_accept_i(image_compress_accept),.shared_done_i(image_compress_done),.shared_digest_i(compress_digest));''')
        text = replace_once(text, 'su_sha256 #(.MAX_BYTES(LUT_BYTES)) u_fixed_luts(',
                            "su_sha256 #(.MAX_BYTES(LUT_BYTES),.USE_SHARED_COMPRESSOR(1'b1)) u_fixed_luts(")
        text = replace_once(text, '.busy_o(lut_busy),.done_o(lut_done),.fault_o(lut_fault),.digest_o(lut_digest));',
                            '''.busy_o(lut_busy),.done_o(lut_done),.fault_o(lut_fault),.digest_o(lut_digest),
        .shared_request_o(lut_compress_request),.shared_block_o(lut_compress_block),.shared_state_o(lut_compress_state),
        .shared_accept_i(lut_compress_accept),.shared_done_i(lut_compress_done),.shared_digest_i(compress_digest));''')
        return text + '\n`default_nettype none\n' + ARBITER + '`default_nettype wire\n'
    return text


def apply(project):
    for name in sorted(FILES):
        path = Path(project) / name
        path.write_text(transform(name, path.read_text()))


def audit_resources(path):
    """Require one mapped compressor and both independent stream wrappers."""
    root = ET.parse(path).getroot()
    boots = [x for x in root.iter() if x.attrib.get('name') == 'u_boot']
    assert len(boots) == 1, 'Expected one DDR boot controller'
    boot = boots[0]
    image = [x for x in boot if x.attrib.get('name') == 'u_image']
    luts = [x for x in boot if x.attrib.get('name') == 'u_fixed_luts']
    mux = [x for x in boot if x.attrib.get('name') == 'u_boot_compressor']
    assert len(image) == len(luts) == len(mux) == 1
    assert not any(x.attrib.get('name') == 'u_compress' for x in image[0].iter())
    assert not any(x.attrib.get('name') == 'u_compress' for x in luts[0].iter())
    compressors = [x for x in boot.iter() if x.attrib.get('name') == 'u_compress']
    assert len(compressors) == 1, 'Expected exactly one boot compression datapath'
    assert compressors[0] in list(mux[0].iter())
    return {'result': 'PASS', 'boot_compressor_count': 1,
            'independent_image_and_lut_streams': True,
            'boot_resources': dict(boot.attrib),
            'compressor_resources': dict(compressors[0].attrib)}

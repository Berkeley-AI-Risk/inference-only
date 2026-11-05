"""Replace the boot-only normalization shift buffer with a synchronous RAM.

The public read ports and coefficient representation are unchanged. Loading
adds bounded backpressure while each packed word is fetched from RAM.
"""


def once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)


def transform(name, text, narrow_carry=False):
    if name != 'swic/swic_norm_store.sv':
        return text
    text = once(text, '    logic [2559:0] vector_q;', '''    (* ram_style="block" *) logic [255:0] packed_words_q[0:9];
    logic [255:0] packed_read_q;
    logic [265:0] unpack_q;
    logic [8:0] unpack_bits_q;
    logic [3:0] packed_index_q;
    logic packed_clear_q;
    localparam [1:0] FETCH=0,MERGE=1,EMIT=2;
    logic [1:0] unpack_state_q;''')
    text = once(text, 'assign word_ready_o=!building_q && !fault_o;',
                'assign word_ready_o=!building_q && !packed_clear_q && !fault_o;')
    text = once(text, '        if(building_q && !fault_o) coefficients_q[{selector_q,row_q}]<=vector_q[9:0];', '''        if(packed_clear_q)
            packed_words_q[packed_index_q]<=0;
        else if(word_valid_i && word_ready_o && (transformer_norm || final_norm))
            packed_words_q[vector_word]<=word_data_i;
        else if(building_q && unpack_state_q==FETCH && packed_index_q<10)
            packed_read_q<=packed_words_q[packed_index_q];
        if(building_q && unpack_state_q==EMIT && unpack_bits_q>=10 && !fault_o)
            coefficients_q[{selector_q,row_q}]<=unpack_q[9:0];''')
    text = once(text, 'coefficients_loaded_q<=0;metadata_loaded_q<=0;vector_q<=0;',
                'coefficients_loaded_q<=0;metadata_loaded_q<=0;unpack_q<=0;\n            unpack_bits_q<=0;packed_index_q<=0;packed_clear_q<=1;unpack_state_q<=FETCH;')
    text = once(text, '''            if(building_q) begin
                if(vector_q[9:0]==10'h200) fault_o<=1;
                vector_q<=vector_q>>10;
                if(row_q==255) begin building_q<=0;coefficients_loaded_q[selector_q]<=1;end
                else row_q<=row_q+1;
            end''', '''            if(packed_clear_q) begin
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
                        unpack_q<=unpack_q | ({10'd0,packed_read_q} << unpack_bits_q[3:0]);
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
            end''')
    text = once(text, '''                    vector_q[int'(vector_word)*256 +:256]<=word_data_i;
                    if(vector_word==9) begin selector_q<=vector_selector;row_q<=0;building_q<=1;end''', '''                    if(vector_word==9) begin
                        selector_q<=vector_selector;row_q<=0;building_q<=1;
                        unpack_q<=0;unpack_bits_q<=0;packed_index_q<=0;unpack_state_q<=FETCH;
                    end''')
    assert 'vector_q' not in text
    if narrow_carry:
        text=once(text, 'unpack_q<=unpack_q | ({10\'d0,packed_read_q} << unpack_bits_q[3:0]);',
                  'unpack_q<={256\'d0,unpack_q[9:0]} | ({10\'d0,packed_read_q} << unpack_bits_q[3:0]);')
    return text


def apply(project, narrow_carry=False):
    from pathlib import Path
    path=Path(project)/"swic/swic_norm_store.sv"
    path.write_text(transform("swic/swic_norm_store.sv",path.read_text(),narrow_carry))


def audit_resources(path):
    import xml.etree.ElementTree as ET
    nodes=[e for e in ET.parse(path).getroot().iter() if e.get('name')=='u_norms']
    assert len(nodes)==1, 'Expected one normalization store'
    counts={k:int(v.split('(')[0]) for k,v in nodes[0].attrib.items() if k.startswith('T_')}
    assert counts.get('T_Bsram',0)>=14, 'Packed words not mapped into the expected block RAM'
    assert counts.get('T_Register',10000)<1024, 'Large normalization shift register remains'
    assert counts.get('T_Lut',10000)<3060, 'No LUT reduction from original normalization loader'
    return {'result':'PASS','normalization_store':counts,
            'scope':'Synthesis resource check for the compact loader; not a complete gate-level memory or timing proof.'}

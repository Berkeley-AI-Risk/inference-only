"""Emit one immutable private decoder from validated build-time Qwen geometry.

Only the fixed internal sequencer may drive this interface. The decoder does
not itself implement or prove scheduling, authentication or host isolation.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from model_geometry import Geometry, bits_for_count, model_layout


def shift_sum(signal, constant, width):
    terms = [f'({signal} << {bit})' if bit else signal
             for bit in range(constant.bit_length()) if (constant >> bit) & 1]
    return ' + '.join(terms) if terms else f"{width}'d0"


def render(g):
    layout = model_layout(g)
    aw = layout['address_bits']
    lw = bits_for_count(g.layers)
    bw = bits_for_count(max(m['tile_bytes'] for m in layout['matrices'])+1)
    matrices = {m['kind']:m for m in layout['matrices'] if m['layer'] == 0}
    vectors = {v['kind']:v for v in layout['vectors'] if v['layer'] == 0}
    code_stride = sum(m['codes_bytes'] for k, m in matrices.items() if k != 7)
    scale_stride = sum(m['scales_bytes'] for k, m in matrices.items() if k != 7)
    norm_stride = sum(v['bytes'] for k, v in vectors.items() if k != 4)
    def literal(n):
        return f"{aw}'d{n}"
    rows = [f'''// Generated private fixed address decoder. No runtime model or shape input.
// One response register; reset/CLEAR cancels it, and stalls preserve it.
module qwen_model_address(
 input wire clk,input wire rst_n,input wire clear,
 input wire request_valid,output wire request_ready,
 input wire [2:0] request_region,input wire [2:0] request_operation,
 input wire [{lw-1}:0] request_layer,input wire [17:0] request_index,
 output wire result_valid,input wire result_ready,
 output wire [{aw-1}:0] result_address,output wire [{bw-1}:0] result_bytes,
 output wire result_error
);
 reg pending;
 reg [{aw-1}:0] address_reg,decoded_address,codes_base,scales_base,tile_stride;
 reg [{bw-1}:0] bytes_reg,decoded_bytes;
 reg [17:0] tile_count;
 reg error_reg,decoded_error;
 wire enabled=rst_n && !clear;
 assign request_ready=enabled && (!pending || result_ready);
 assign result_valid=enabled && pending;
 assign result_address=result_valid ? address_reg : {aw}'d0;
 assign result_bytes=result_valid ? bytes_reg : {bw}'d0;
 assign result_error=result_valid && error_reg;
 wire [{aw-1}:0] layer_wide={{{aw-lw}'b0,request_layer}};
 wire [{aw-1}:0] index_wide={{{aw-18}'b0,request_index}};
 wire [{aw-1}:0] layer_codes={shift_sum('layer_wide',code_stride,aw)};
 wire [{aw-1}:0] layer_scales={shift_sum('layer_wide',scale_stride,aw)};
 wire [{aw-1}:0] layer_norms={shift_sum('layer_wide',norm_stride,aw)};
 reg [{aw-1}:0] tile_offset;
 always @* begin
  codes_base=0;scales_base=0;tile_count=0;tile_stride=0;tile_offset=0;
  case(request_operation)''']
    for k, m in sorted(matrices.items()):
        code_layer = 'layer_codes + ' if k != 7 else ''
        scale_layer = 'layer_scales + ' if k != 7 else ''
        rows.append(f"  3'd{k}:begin codes_base={code_layer}{literal(m['codes_offset'])}; scales_base={scale_layer}{literal(m['scales_offset'])}; tile_count=18'd{m['tiles']}; tile_stride={literal(m['tile_bytes'])}; tile_offset={shift_sum('index_wide',m['tile_bytes'],aw)}; end")
    rows.append(f'''  default:begin end
  endcase
  decoded_address=0;decoded_bytes=0;decoded_error=1;
  case(request_region)
   3'd0,3'd1:if((request_operation==7 || request_layer<{lw}'d{g.layers}) && request_index<tile_count)begin
    decoded_error=0;
    if(request_region==1)begin decoded_address=scales_base+(index_wide<<7);decoded_bytes={bw}'d128;end
    else begin decoded_address=codes_base+tile_offset;decoded_bytes=tile_stride[{bw-1}:0];end
   end
   3'd2:if(request_index==0 && (request_operation==4 || (request_operation<4 && request_layer<{lw}'d{g.layers})))begin
    case(request_operation)''')
    for k, v in sorted(vectors.items()):
        layer = 'layer_norms + ' if k != 4 else ''
        rows.append(f"     3'd{k}:begin decoded_address={layer}{literal(v['offset'])};decoded_bytes={bw}'d{v['bytes']};decoded_error=0;end")
    rows.append(f'''     default:begin end
    endcase
   end
   3'd3:if(request_operation==0 && request_index<18'd{g.vocab})begin
    decoded_address={literal(layout['embedding']['offset'])}+{shift_sum('index_wide',g.width*2,aw)};
    decoded_bytes={bw}'d{g.width*2};decoded_error=0;
   end
   3'd4:if(request_operation==0 && request_index<18'd{g.positions})begin
    decoded_address={literal(layout['rotary']['offset'])}+{shift_sum('index_wide',g.head_dim*2,aw)};
    decoded_bytes={bw}'d{g.head_dim*2};decoded_error=0;
   end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n || clear)begin pending<=0;address_reg<=0;bytes_reg<=0;error_reg<=0;end
  else if(request_ready)begin
   pending<=request_valid;
   if(request_valid)begin address_reg<=decoded_address;bytes_reg<=decoded_bytes;error_reg<=decoded_error;end
  end
 end
endmodule
''')
    # Constants equal to a full encoding range need one extra comparison bit.
    result='\n'.join(rows)
    result=result.replace(f"request_layer<{lw}'d{g.layers}",f"{{1'b0,request_layer}}<{lw+1}'d{g.layers}")
    result=result.replace(f"request_index<18'd{g.vocab}",f"{{1'b0,request_index}}<19'd{g.vocab}")
    return result


def domains(g):
    """Golden descriptor table read from layout, not generated address equations."""
    layout=model_layout(g);layers=1<<bits_for_count(g.layers)
    table=[(0,0,0,0)]*(64*layers)
    def put(region,op,layer,base,count,size,stride):
        table[(region*8+op)*layers+layer]=(base,count,size,stride)
    for m in layout['matrices']:
        for layer in (range(layers) if m['kind']==7 else [m['layer']]):
            put(0,m['kind'],layer,m['codes_offset'],m['tiles'],m['tile_bytes'],m['tile_bytes'])
            put(1,m['kind'],layer,m['scales_offset'],m['tiles'],128,128)
    for v in layout['vectors']:
        for layer in (range(layers) if v['kind']==4 else [v['layer']]):
            put(2,v['kind'],layer,v['offset'],1,v['bytes'],0)
    for layer in range(layers):
        put(3,0,layer,layout['embedding']['offset'],g.vocab,g.width*2,g.width*2)
        put(4,0,layer,layout['rotary']['offset'],g.positions,g.head_dim*2,g.head_dim*2)
    return table


def generate(config, output):
    config,output=Path(config),Path(output)
    g=Geometry.from_config(json.loads(config.read_text()))
    output.mkdir(parents=True,exist_ok=False)
    source=render(g)
    (output/'qwen_model_address.sv').write_text(source)
    (output/'domains.txt').write_text(''.join(f'{i} {base} {count} {size} {stride}\n' for i,(base,count,size,stride) in enumerate(domains(g))))
    receipt=dict(generated_utc=datetime.now(timezone.utc).isoformat(),model_image_bytes=model_layout(g)['image_bytes'],
                 layer_encodings=1<<bits_for_count(g.layers),legal_requests=sum(row[1] for row in domains(g)),
                 source_sha256=hashlib.sha256(source.encode()).hexdigest(),
                 generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                 config_sha256=hashlib.sha256(config.read_bytes()).hexdigest(),
                 qualification='Generated only; tests, integration and physical checks are separate')
    (output/'GENERATED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    return receipt


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();print(json.dumps(generate(a.config,a.output),indent=2))

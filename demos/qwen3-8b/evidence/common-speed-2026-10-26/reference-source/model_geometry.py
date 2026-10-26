"""Build-time geometry for fixed dense Qwen3 machines, not a runtime model API.

Generate model addresses and budgets from a validated checkpoint configuration.
The deployed circuit must contain constants from one chosen specification; no
host port may supply these dimensions, layouts, model choices or schedules.
"""
from dataclasses import dataclass
import json
from pathlib import Path

PAGE_BYTES=65536
TILE_ROWS=32
PROJECTION_NAMES=('self_attn.q_proj','self_attn.k_proj','self_attn.v_proj',
                  'self_attn.o_proj','mlp.gate_proj','mlp.up_proj','mlp.down_proj')
NORM_NAMES=('input_layernorm','self_attn.q_norm','self_attn.k_norm','post_attention_layernorm')


def align_up(value,alignment=PAGE_BYTES):
    return (value+alignment-1)//alignment*alignment


def bits_for_count(count):
    if type(count) is not int or count<1:raise ValueError('Positive integer count required')
    return max(1,(count-1).bit_length())


@dataclass(frozen=True)
class Geometry:
    layers:int
    width:int
    ffn:int
    query_heads:int
    kv_heads:int
    head_dim:int
    vocab:int
    tied_embeddings:bool
    positions:int=32768

    def __post_init__(self):
        values=(self.layers,self.width,self.ffn,self.query_heads,self.kv_heads,
                self.head_dim,self.vocab,self.positions)
        if any(type(v) is not int or v<=0 for v in values):
            raise ValueError('Positive integer geometry required')
        if type(self.tied_embeddings) is not bool:raise ValueError('Explicit tied-embedding flag required')
        if self.width!=self.query_heads*self.head_dim or self.query_heads%self.kv_heads:
            raise ValueError('Unsupported attention geometry')
        if self.head_dim!=128 or self.kv_heads!=8 or self.positions>32768:
            raise ValueError('This specialization supports head128, eight KV heads and <=32768 positions')
        if self.layers>64 or self.vocab>262144 or self.width>8192 or self.ffn>32768:
            raise ValueError('Outside validated specialization envelope')
        if any(v%TILE_ROWS for v in (self.width,self.ffn,self.vocab)):
            raise ValueError('Projection rows must be tiled in groups of 32')
        if self.ffn%256:
            raise ValueError('The reused exact projection oracle requires 256-column chunks')

    @classmethod
    def from_config(cls,config,positions=32768):
        if (config.get('model_type')!='qwen3' or config.get('architectures')!=['Qwen3ForCausalLM']
            or config.get('attention_bias') is not False or config.get('hidden_act')!='silu'
            or config.get('use_sliding_window') is not False or config.get('sliding_window') is not None
            or config.get('rope_scaling') is not None or config.get('rms_norm_eps')!=1e-6
            or config.get('rope_theta')!=1000000 or positions>config['max_position_embeddings']):
            raise ValueError('Unsupported model operations/numerical constants')
        return cls(config['num_hidden_layers'],config['hidden_size'],config['intermediate_size'],
                   config['num_attention_heads'],config['num_key_value_heads'],config['head_dim'],
                   config['vocab_size'],config['tie_word_embeddings'],positions)

    @property
    def projection_rows(self):
        kv=self.kv_heads*self.head_dim
        return (self.width,kv,kv,self.width,self.ffn,self.ffn,self.width)

    @property
    def norm_widths(self):return (self.width,self.head_dim,self.head_dim,self.width)

    @property
    def parameter_count(self):
        layer=sum(r*(self.ffn if k==6 else self.width) for k,r in enumerate(self.projection_rows))
        layer+=sum(self.norm_widths)
        return self.layers*layer+self.width+self.vocab*self.width*(1 if self.tied_embeddings else 2)


def model_layout(g):
    matrices=[];vectors=[];cursor=0
    for layer in range(g.layers):
        for kind,label in enumerate(PROJECTION_NAMES):
            rows=g.projection_rows[kind];columns=g.ffn if kind==6 else g.width
            size=rows*columns
            matrices.append(dict(name=f'model.layers.{layer}.{label}.weight',kind=kind,layer=layer,
                rows=rows,columns=columns,codes_offset=cursor,codes_bytes=size,
                tiles=rows//TILE_ROWS,tile_bytes=TILE_ROWS*columns))
            cursor+=size
    head='model.embed_tokens.weight' if g.tied_embeddings else 'lm_head.weight'
    matrices.append(dict(name=head,kind=7,layer=0,rows=g.vocab,columns=g.width,
        codes_offset=cursor,codes_bytes=g.vocab*g.width,tiles=g.vocab//TILE_ROWS,tile_bytes=TILE_ROWS*g.width))
    cursor+=g.vocab*g.width
    regions=[dict(name='projection_codes',offset=0,bytes=cursor)]
    scale_start=align_up(cursor);cursor=scale_start
    for m in matrices:
        m.update(scales_offset=cursor,scales_bytes=m['rows']*4);cursor+=m['scales_bytes']
    regions.append(dict(name='row_scales',offset=scale_start,bytes=cursor-scale_start))
    norm_start=align_up(cursor);cursor=norm_start
    for layer in range(g.layers):
        for kind,(name,width) in enumerate(zip(NORM_NAMES,g.norm_widths)):
            vectors.append(dict(name=f'model.layers.{layer}.{name}.weight',kind=kind,layer=layer,
                                elements=width,offset=cursor,bytes=width*2));cursor+=width*2
    vectors.append(dict(name='model.norm.weight',kind=4,layer=0,elements=g.width,offset=cursor,bytes=g.width*2))
    cursor+=g.width*2
    regions.append(dict(name='normalization_vectors',offset=norm_start,bytes=cursor-norm_start))
    embedding=dict(offset=align_up(cursor),bytes=g.vocab*g.width*2,row_bytes=g.width*2,rows=g.vocab)
    regions.append(dict(name='derived_bf16_embedding' if g.tied_embeddings else 'source_bf16_embedding',**embedding))
    rotary=dict(offset=align_up(embedding['offset']+embedding['bytes']),
                bytes=g.positions*g.head_dim*2,position_bytes=g.head_dim*2)
    regions.append(dict(name='fixed_rotary_coefficients',**rotary))
    total=align_up(rotary['offset']+rotary['bytes'])
    return dict(schema='qwen3-private-model-layout-v1',address_bits=max(32,bits_for_count(total)),
                byte_order='little',page_alignment=PAGE_BYTES,
                codes_order='[tile32, column_group8, row_within32, byte_within8]',
                matrices=matrices,vectors=vectors,embedding=embedding,rotary=rotary,
                regions=regions,image_bytes=total)


def expected_tensor_shapes(g):
    layout=model_layout(g)
    shapes={m['name']:[m['rows'],m['columns']] for m in layout['matrices']}
    shapes.update({v['name']:[v['elements']] for v in layout['vectors']})
    shapes['model.embed_tokens.weight']=[g.vocab,g.width]
    shapes['lm_head.weight']=[g.vocab,g.width]
    return shapes


def budget(g,core_mhz=100,projection_products_per_cycle=256,hash_workers=4):
    layout=model_layout(g);image=layout['image_bytes'];pages=image//PAGE_BYTES
    kv_per_position=g.layers*2*g.kv_heads*g.head_dim*2
    kv_bytes=kv_per_position*g.positions
    # The compiled release ALREADY uses one shared immutable table. Its reported
    # 512 RAMB36s suggest power-of-two depth rounding. A flat 8B table would
    # therefore exceed the entire device: explicitly bank it before full P&R.
    roots=pages*32
    banked_root_ramb36=32*((pages+4095)//4096) # 4K-entry banks; 8 x 32-bit lanes.
    flat_root_ramb36=(1<<bits_for_count(pages))*256//32768
    model_multiplications=sum(m['codes_bytes'] for m in layout['matrices'])
    cycles_min=(model_multiplications+projection_products_per_cycle-1)//projection_products_per_cycle
    return dict(parameter_count=g.parameter_count,model_image_bytes=image,model_pages=pages,
                model_address_bits=bits_for_count(image),page_index_bits=bits_for_count(pages),
                layer_bits=bits_for_count(g.layers),tensor_index_bits=bits_for_count(g.ffn),
                private_request_length_bits=bits_for_count(max(m['tile_bytes'] for m in layout['matrices'])+1),
                kv_bytes_per_position=kv_per_position,context_positions=g.positions,kv_bytes=kv_bytes,
                combined_hbm_bytes=image+kv_bytes,hbm_capacity_bytes=16*1024**3,
                fits_hbm_capacity=image+kv_bytes<=16*1024**3,
                hbm_remaining_bytes=16*1024**3-image-kv_bytes,
                immutable_page_roots_bytes=roots,replicated_page_roots_bytes=roots*hash_workers,
                current_release_root_table_copies=1,
                estimated_flat_shared_root_ramb36=flat_root_ramb36,
                estimated_banked_shared_root_ramb36=banked_root_ramb36,
                hypothetical_four_copy_roots_not_current_implementation=True,
                estimated_replicated_banked_root_ramb36=banked_root_ramb36*hash_workers,
                current_release_reported_shared_root_ramb36=512,
                current_release_reported_total_ramb36_tiles=1179.5,
                banked_roots_plus_unchanged_other_ram_estimate=banked_root_ramb36+1179.5-512,
                ram_estimate_includes_larger_tensors_and_new_transport=False,
                total_device_ramb36=2016,
                decode_projection_products=model_multiplications,
                projection_only_minimum_cycles=cycles_min,
                projection_only_tokens_per_second_ceiling=core_mhz*1e6/cycles_min,
                core_mhz_assumed=core_mhz,projection_products_per_cycle=projection_products_per_cycle,
                weight_codes_bytes_per_decode=model_multiplications,
                prediction_is_hardware_measurement=False,
                qualification='capacity/arithmetic calculation only; excludes stalls, attention, hashing, scheduling, placement and routing')


def hbm_physical_address(logical_byte_address):
    """Candidate bijection over 16 GiB, with eight lanes per 64-KiB page.

    Rotate pages among four eight-channel groups. This is user-logic address
    selection, NOT the vendor IP's erratum-affected Customer Address Map option.
    An AXI request must still obey range/length/burst and fixed-owner guards.
    """
    a=logical_byte_address
    if type(a) is not int or not 0<=a<16*1024**3:raise ValueError('Outside HBM')
    channel=((a>>16)&3)*8+((a>>5)&7)
    offset=((a>>18)<<13)|(((a>>8)&255)<<5)|(a&31)
    return channel*512*1024**2+offset


def hbm_logical_address(physical_byte_address):
    p=physical_byte_address
    if type(p) is not int or not 0<=p<16*1024**3:raise ValueError('Outside HBM')
    channel=p>>29;offset=p&((1<<29)-1)
    return ((offset>>13)<<18)|((channel>>3)<<16)|(((offset>>5)&255)<<8)|((channel&7)<<5)|(offset&31)


def write_budget(config_path,output):
    g=Geometry.from_config(json.loads(Path(config_path).read_text()))
    output=Path(output);output.mkdir(parents=True,exist_ok=False)
    for name,value in (('layout.json',model_layout(g)),('budget.json',budget(g))):
        (output/name).write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
    print(json.dumps(budget(g),indent=2))


if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();write_budget(a.config,a.output)

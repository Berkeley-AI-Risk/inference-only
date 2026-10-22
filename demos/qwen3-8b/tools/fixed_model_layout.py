"""Fixed Qwen3 candidate memory layout, not a host-programmable tensor map.

Addresses are byte offsets inside a future private model-memory aperture.
HBM channel assignment, burst splitting and at-consumption authentication are
separate hardware work. This module does not implement any of those mechanisms.
"""
from functools import lru_cache

LAYERS = 28
WIDTH = 2048
FFN = 6144
VOCAB = 151936
POSITIONS = 32768
PAGE_BYTES = 65536
TILE_ROWS = 32
GROUP_COLUMNS = 8
PROJECTION_NAMES = ('self_attn.q_proj', 'self_attn.k_proj', 'self_attn.v_proj',
                    'self_attn.o_proj', 'mlp.gate_proj', 'mlp.up_proj', 'mlp.down_proj')
PROJECTION_ROWS = (2048, 1024, 1024, 2048, 6144, 6144, 2048)
NORM_NAMES = ('input_layernorm', 'self_attn.q_norm', 'self_attn.k_norm',
              'post_attention_layernorm')
NORM_WIDTHS = (2048, 128, 128, 2048)


def align_up(value, alignment=PAGE_BYTES):
    return (value + alignment - 1) // alignment * alignment


def model_layout():
    """Return a fresh fixed manifest; callers cannot select shapes or bases."""
    matrices = []
    vectors = []
    cursor = 0
    for layer in range(LAYERS):
        for kind, label in enumerate(PROJECTION_NAMES):
            rows = PROJECTION_ROWS[kind]
            columns = FFN if kind == 6 else WIDTH
            size = rows * columns
            matrices.append({'name': f'model.layers.{layer}.{label}.weight',
                             'kind': kind, 'layer': layer, 'rows': rows,
                             'columns': columns, 'codes_offset': cursor,
                             'codes_bytes': size, 'tiles': rows // TILE_ROWS,
                             'tile_bytes': TILE_ROWS * columns})
            cursor += size
    matrices.append({'name': 'model.embed_tokens.weight', 'kind': 7, 'layer': 0,
                     'rows': VOCAB, 'columns': WIDTH, 'codes_offset': cursor,
                     'codes_bytes': VOCAB * WIDTH, 'tiles': VOCAB // TILE_ROWS,
                     'tile_bytes': TILE_ROWS * WIDTH})
    cursor += VOCAB * WIDTH
    regions = [{'name': 'projection_codes', 'offset': 0, 'bytes': cursor}]
    scale_start = align_up(cursor)
    cursor = scale_start
    for item in matrices:
        item['scales_offset'] = cursor
        item['scales_bytes'] = item['rows'] * 4
        cursor += item['scales_bytes']
    regions.append({'name': 'row_scales', 'offset': scale_start, 'bytes': cursor - scale_start})
    norm_start = align_up(cursor)
    cursor = norm_start
    for layer in range(LAYERS):
        for kind, (label, width) in enumerate(zip(NORM_NAMES, NORM_WIDTHS)):
            vectors.append({'name': f'model.layers.{layer}.{label}.weight',
                            'kind': kind, 'layer': layer, 'elements': width,
                            'offset': cursor, 'bytes': width * 2})
            cursor += width * 2
    vectors.append({'name': 'model.norm.weight', 'kind': 4, 'layer': 0,
                    'elements': WIDTH, 'offset': cursor, 'bytes': WIDTH * 2})
    cursor += WIDTH * 2
    regions.append({'name': 'normalization_vectors', 'offset': norm_start,
                    'bytes': cursor - norm_start})
    embedding = {'offset': align_up(cursor), 'bytes': VOCAB * WIDTH * 2,
                 'row_bytes': WIDTH * 2, 'rows': VOCAB}
    regions.append({'name': 'derived_bf16_embedding', **embedding})
    rotary = {'offset': align_up(embedding['offset'] + embedding['bytes']),
              'bytes': POSITIONS * 64 * 2 * 2, 'position_bytes': 256}
    regions.append({'name': 'fixed_rotary_coefficients', **rotary})
    total = align_up(rotary['offset'] + rotary['bytes'])
    return {'schema': 'qwen3-private-model-layout-v1', 'address_bits': 32,
            'byte_order': 'little', 'page_alignment': PAGE_BYTES,
            'codes_order': '[tile32, column_group8, row_within32, byte_within8]',
            'matrices': matrices, 'vectors': vectors, 'embedding': embedding,
            'rotary': rotary, 'regions': regions, 'image_bytes': total}


def pack_codes(codes):
    """Only a byte permutation; row-major input -> 256-byte engine beats."""
    import numpy as np
    a = np.asarray(codes)
    if (a.dtype != np.int8 or a.ndim != 2 or a.shape[0] % TILE_ROWS
            or a.shape[1] % GROUP_COLUMNS):
        raise ValueError('Expected int8 matrix with 32-row/8-column tiling')
    rows, columns = a.shape
    return a.reshape(rows // 32, 32, columns // 8, 8).transpose(0, 2, 1, 3).copy()


def unpack_codes(packed, rows, columns):
    import numpy as np
    a = np.asarray(packed)
    if (a.dtype != np.int8 or rows % 32 or columns % 8
            or a.size != rows * columns):
        raise ValueError('Invalid packed code geometry')
    return a.reshape(rows // 32, columns // 8, 32, 8).transpose(0, 2, 1, 3).reshape(rows, columns)


def embedding_bits(codes, scales):
    """Exact existing embedding operation: FP32 product, then BF16 RNE.

    Export uses NumPy plus explicit bit rounding. Full-image verification uses
    the independent torch FP32 -> BF16 path used by FixedQwenEngine.
    """
    import numpy as np
    a, s = np.asarray(codes), np.asarray(scales)
    if (a.dtype != np.int8 or a.ndim != 2 or s.dtype != np.float32
            or s.shape != (a.shape[0], 1) or not np.isfinite(s).all() or (s <= 0).any()):
        raise ValueError('Invalid embedding codes/scales')
    value = np.multiply(a.astype(np.float32), s, dtype=np.float32)
    if not np.isfinite(value).all():
        raise ValueError('Nonfinite embedding product')
    raw = value.view(np.uint32)
    bits = ((raw + np.uint32(0x7fff) + ((raw >> 16) & 1)) >> 16).astype('<u2')
    if ((bits & 0x7f80) == 0x7f80).any():
        raise ValueError('Nonfinite rounded embedding')
    return bits


@lru_cache(maxsize=1)
def _indices():
    layout = model_layout()
    return (layout, {(m['kind'], m['layer']): m for m in layout['matrices']},
            {(v['kind'], v['layer']): v for v in layout['vectors']})


def resolve_request(region, operation, layer, index):
    """Private request -> fixed (byte offset, byte count), or ValueError.

    Regions: 0 projection codes, 1 row scales, 2 normalization vector,
    3 derived embedding row, 4 rotary position. Index is a tile, zero, a token
    ID or a tape position respectively. Global objects ignore the layer field,
    matching the numerical engine's tied-head behavior. Unused op/index fields
    must be zero. These are internal hardware signals, never application ports.
    """
    if (any(type(v) is not int for v in (region, operation, layer, index))
            or not 0 <= region < 8 or not 0 <= operation < 8
            or not 0 <= layer < 32 or not 0 <= index < 262144):
        raise ValueError('Private request encoding outside its bit widths')
    layout, matrices, vectors = _indices()
    if region in (0, 1):
        item = matrices.get((operation, 0 if operation == 7 else layer))
        if item is None or index >= item['tiles']:
            raise ValueError('Invalid projection kind/layer/tile')
        return ((item['codes_offset'] + index * item['tile_bytes'], item['tile_bytes'])
                if region == 0 else (item['scales_offset'] + index * 128, 128))
    if region == 2:
        item = vectors.get((operation, 0 if operation == 4 else layer))
        if item is None or index:
            raise ValueError('Invalid normalization kind/layer/index')
        return item['offset'], item['bytes']
    if region == 3 and operation == 0 and index < VOCAB:
        return layout['embedding']['offset'] + index * 4096, 4096
    if region == 4 and operation == 0 and index < POSITIONS:
        return layout['rotary']['offset'] + index * 256, 256
    raise ValueError('Invalid private model-memory request')

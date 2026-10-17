"""Exact W8 x A16 projection reference, with floating-point scaling around it.

This is not a complete bit-exact Qwen hardware model: attention, RMSNorm,
RoPE, SiLU and residual arithmetic still use the pinned framework implementation.
"""
import torch

CHUNK = 256
ACTIVATION_MAX = 32767


def quantize_activation(value):
    """Per-vector FP32 max/32767 scale; nearest-even, symmetric signed int16."""
    if value.ndim < 1:
        raise ValueError('An activation vector is required')
    value = value.float()
    if not torch.isfinite(value).all():
        raise ValueError('Non-finite activation before quantization')
    scale = value.abs().amax(dim=-1, keepdim=True) / ACTIVATION_MAX
    scale = torch.where(scale == 0, torch.ones_like(scale), scale)
    codes = torch.round(value / scale).clamp(-ACTIVATION_MAX, ACTIVATION_MAX).to(torch.int32)
    return codes, scale


def pack_weight_codes(codes, device):
    if codes.ndim != 2 or codes.dtype != torch.int8 or codes.shape[1] % CHUNK:
        raise ValueError('Expected an int8 matrix with columns divisible by 256')
    rows, columns = codes.shape
    return codes.reshape(rows, columns//CHUNK, CHUNK).permute(1,2,0).contiguous().to(
        device=device, dtype=torch.float32)


def integer_dots(activations, packed_weights):
    """Compute signed integer sums using bounded exact FP32 partial dot products.

    a = 256*hi + lo, where -128<=hi<=127 and 0<=lo<=255. Every 256-term
    partial sum has absolute bound 256*255*128 < 2**24. Products and sums
    therefore fit FP32's exact-integer range, independently of reduction order,
    PROVIDED the backend uses full FP32 multiplication/accumulation. Convert
    partials to int64 before recombination. No TF32 or reduced precision is
    allowed. Unit tests compare this path with separate CPU int64 products.
    The hardware directly multiplies the original int8/int16 values instead.
    """
    if activations.ndim != 2 or activations.dtype not in (torch.int16, torch.int32):
        raise ValueError('Expected a two-dimensional signed activation matrix')
    chunks, width, rows = packed_weights.shape
    if width != CHUNK or activations.shape[1] != chunks*CHUNK:
        raise ValueError('Integer projection geometry mismatch')
    high = torch.div(activations, 256, rounding_mode='floor')
    low = activations-high*256
    def partial(values):
        grouped = values.reshape(values.shape[0], chunks, CHUNK).permute(1,0,2).contiguous().float()
        return torch.bmm(grouped, packed_weights).to(torch.int64)
    return (partial(high)*256+partial(low)).sum(dim=0, dtype=torch.int64)


class IntegerProjection(torch.nn.Module):
    def __init__(self, codes, scales, device, name, capture=None):
        super().__init__()
        self.in_features = codes.shape[1]
        self.out_features = codes.shape[0]
        self.name = name
        self.capture = capture
        self.captured = False
        self.register_buffer('packed_weights', pack_weight_codes(codes, device))
        self.register_buffer('scales', scales.reshape(1,-1).to(device=device, dtype=torch.float32))
        # Retain small selected rows on CPU only when an RTL fixture is wanted.
        if capture is not None:
            indexes = sorted({0, 1, 2, 3, *[int(i*(codes.shape[0]-1)/11) for i in range(12)]})
            self.capture_rows = indexes
            self.capture_weights = codes[indexes].clone()

    def forward(self, value):
        original_shape = value.shape[:-1]
        flattened = value.reshape(-1, self.in_features)
        codes, scale = quantize_activation(flattened)
        accumulator = integer_dots(codes, self.packed_weights)
        if self.capture is not None and not self.captured:
            self.capture(self.name, codes[-1].detach().cpu().to(torch.int16),
                         self.capture_rows, self.capture_weights,
                         accumulator[-1,self.capture_rows].detach().cpu())
            self.captured = True
        # Specify the multiplication order; do not treat this as BF16 dequantized
        # weights fed to a BF16 matrix multiplication.
        scaled = (accumulator.float()*self.scales)*scale
        return scaled.to(value.dtype).reshape(*original_shape, self.out_features)



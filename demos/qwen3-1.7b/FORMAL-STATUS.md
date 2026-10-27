# Qwen3-1.7B: formal status

[Guide](README.md) · [Validation](VALIDATION.md) · [Reproduction](REPRODUCE.md)

**No formal-verification proof suite for this Qwen3-1.7B design is supplied in
this release.** The package does not claim a whole-machine refinement theorem,
a universal numerical-correctness theorem or a formally certified residual
training factor for this implementation.

## Published evidence and its boundary

The [validation guide](VALIDATION.md) links finite numerical/FPGA comparisons,
source bindings, installation records and vendor implementation reports.
The [hardware guide](HARDWARE.md) describes the fixed inference schedule,
private checked-weight storage, clock crossings and implementation checks.
Those records have their stated engineering scopes; they are not solver proofs
of the complete inference circuit or its cryptographic security.

The [interface assessment](README.md#interface-and-inference-only-scope)
describes the inference operations, restricted startup loader, status facilities
and attention-control diagnostic. Its inference-only interpretation assumes a
frozen configuration or eventual fixed ASIC. The reprogrammable AWS management
platform and physical attacks require separate assessment. K/V integrity and
weight encryption are not features of this released image.

## Relation to SimpleStories

The [SimpleStories formal package](../simplestories-v2-5m/FORMAL-STATUS.md)
establishes scoped properties for its named RTL, source/image bindings and
assumptions. Those results do not transfer to Qwen3-1.7B.

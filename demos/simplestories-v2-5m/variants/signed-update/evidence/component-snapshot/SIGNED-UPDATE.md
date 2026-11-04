# Signed-update protocol and claims

## Fixed policy

The inference architecture is SimpleStories-V2-5M, W10/A16/KV16, greedy selection, six layers, width 256, FFN width 682, four query heads, two K/V heads, vocabulary 4,019 and context limit 2,048. The image has 7,265,984 bytes, represented by 227,062 little-endian 256-bit words. Pages have 4,096 bytes; the final page is zero-padded for hashing. There are 1,774 expected page hashes and 2,328 projection-metadata words of 192 bits, serialized most-significant byte first.

The fixed SHA-256 geometry identifier covers the canonical description in the reference, including this layout and selector. Package fields cannot alter those constants, the verifier, trust anchors, geometry or inference circuit.

The prototype uses **two of three distinct public demo keys**, with RFC 8554 `LMS_SHA256_M32_H5` (type 5) and `LMOTS_SHA256_N32_W8` (type 4). Each signature is exactly 1,292 bytes. Other algorithm/type encodings are rejected. This is a deliberately bounded demo signer tree: 32 one-time leaves per authority. That signer capacity is not an enforced chip update counter; replay remains possible. Production authority lifetime and key rotation require a separate policy.

The signer must never sign different messages with the same one-time leaf. The demo CLI reserves leaf numbers under an exclusive file lock and flushes them before signing; a failed signing operation can consume a leaf. Corrupt existing state is rejected. The file is not protected against rollback, copying, deletion or physical tampering. Public demo keys and deterministic test fixtures provide no key secrecy. They must not be used to authorize a production model.

Reference: [RFC 8554](https://www.rfc-editor.org/rfc/rfc8554.html), sections 4–5 and Appendix F. The test fixture contains both LMS layers of its first published HSS example; the implemented package protocol accepts a single LMS signature per authority, not arbitrary HSS hierarchies.

## Canonical manifest

All integers are unsigned, big-endian. No JSON, optional fields, alternate encodings or caller-selected verification keys appear in the device frame.

| Byte offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 16 | `SWIC-SS-UPD-v1`, zero-padded to 16 bytes |
| 16 | 32 | Fixed geometry identifier |
| 48 | 4 | Image byte count, 7,265,984 |
| 52 | 4 | Page count, 1,774 |
| 56 | 4 | Metadata byte count, 55,872 |
| 60 | 4 | Policy word, exactly zero |
| 64 | 8 | Signed informational version |
| 72 | 32 | Model commitment root |
| 104 | 24 | Reserved, all zero |

Each signature covers exactly these 128 bytes, including domain, geometry, version and root. The version is not compared to persistent state and makes no rollback-prevention claim.

The commitment payload is exactly:

1. SHA-256 of the entire unpadded model image: 32 bytes.
2. The 1,774 SHA-256 page digests in ascending page order: 56,768 bytes.
3. The projection metadata: 55,872 bytes.

The root is `SHA256(root_domain || payload)`, where `root_domain` is `SWIC-SS-ROOT-v1` zero-padded to 16 bytes. The root is computed over the same private table/metadata storage used later by runtime, rather than over an external copy that can change after checking.

## Package and device frame

The offline package is:

```text
manifest[128]
signer_count[u32]                 # exactly 2 or 3
repeat signer_count times:
    authority_id[u32]             # 0, 1 or 2, strictly increasing
    lms_signature[1292]
commitment_payload[112672]
image[7265984]
```

The boot-admission frame contains everything before the image: 115,396 bytes for two signers or 116,692 for three. Its `last` marker must accompany exactly the final metadata byte. Early/late markers, excess bytes, invalid geometry/policy/reserved fields, unknown or duplicate authorities, altered roots and invalid signatures fail closed. An incomplete stream without a terminal marker remains unadmitted; the component has no admission-progress timeout.

The image is loaded into DDR through a separate loader and supplied to the image-check block as a complete ordered readback. Hashing only flash-side bytes would not establish the DDR contents; an actual loader/controller composition is still required.

## Connected RTL sequence

1. Reset revokes admission, image verification and all page validity. RAM payload is not reset, but cannot be used until a complete fresh frame is loaded and checked.
2. Load the fixed-length frame into private, quarantined storage. Runtime digest/metadata outputs remain zero. After loading, the payload RAM has no write path for the session.
3. Validate canonical manifest fields and hash the stored commitment payload. Compare with the signed root.
4. Verify every provided LMS signature using the selected fixed public key. Distinctness is checked before counting a signer; only the complete valid set can admit the payload.
5. Hash all 7,265,984 ordered DDR readback bytes, checking the exact final marker and signed image digest. `model_ready` stays low until completion.
6. For each requested runtime page, read its expected digest from sealed RAM, fill the native private bank, seal and hash that bank, then permit reads. The last page uses the native zero-tail convention.
7. Read projection metadata from sealed RAM. Read cancellation does not revoke integrity faults, alter the model or reopen the boot path. Extra boot traffic after the frame fails closed, including during runtime.

`swic_verified_memory` implements this connection for one native page bank in one trusted clock domain. Its ports are private hardware seams. They are not new user commands. Extending the complete APPEND/STEP/CLEAR implementation requires integration with the actual transport, flash layout, DDR ownership, four-bank arbitration and clock/reset boundaries. No whole-machine interface theorem follows from this component regression.

The RTL verifier performs SHA-256 message hashing, all LMOTS hash chains, the LMOTS public-key hash, the LMS leaf and all five Merkle levels. It compares the resulting root with a fixed authority root. Simulation tests do not replace that computation with a validity input.

## Security and capacity scope

Assume the FPGA configuration is frozen, or an eventual fixed ASIC implements the assessed circuit. An owner can otherwise replace an FPGA circuit. No physical-tamper, fault-injection, silicon-clock or key-management security is established here.

This variant intentionally has no deliberate admission delay, lifetime cap, consumed-model state or rollback protection. Older valid signed models can be reloaded after reset. With the signing threshold compromised, an adversary can approve arbitrary compatible full weights and make repeated boot-time updates. Signatures authorize models; they do not make an attacker's chosen model harmless or prove that the architecture has low residual training capacity.

The fixed-digest capacity assessment supplies conditional arithmetic/access proxies, not an inherited bound for this variant. Chosen-weight result recovery, training through repeated replacements, fleet execution and fixed-model assistance remain open. See the internal paper-only assessment in the enclosing development repository under `inference-only/analysis/signed-update-delay/` for the delay analysis. That internal memo is not part of a public release dependency.

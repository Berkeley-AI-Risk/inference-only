# Numerical range proof for the first SimpleStories value vector

For every legal vocabulary token in the published SimpleStories-V2-5M image, the token embedding, RMS normalization and layer-0 value projection at position zero satisfy the fixed-point reference model's arithmetic requirements. These include accumulator widths, admissible weight codes and the existence of a shared exponent that lets each vector fit the 16-bit mantissa range. The proof covers all 4,019 possible first tokens. [Numerical definitions](ssv-spec.lisp) · [ACL2 theorem](all-vocabulary-profiles.lisp)

This establishes one premise for a hardware conformance proof. Applying it to what the chip writes requires a further theorem connecting the RTL value producer to this numerical reference. [Related 18-write RTL theorem](../simplestories-kv-record/README.md)

## Reproduce the proof

Run this command from a checkout of the public repository with Python 3 and an ACL2 8.7 executable. Give `--out` a fresh directory. The run needs a few minutes on the reference Mac.

```sh
python3 evidence/simplestories-first-v-profile/replay.py \
    --acl2 /path/to/saved_acl2 --out /tmp/simplestories-first-v-proof
```

The script reads the [published model image](../../demos/simplestories-v2-5m/assets/board1-real-semantic-image2048.bin), checks its SHA-256 and reconstructs the 227,062 little-endian words used by ACL2. It certifies the numerical specification, the image constant and the theorem from source with an empty project certificate directory. A separate ACL2 process then loads the result and prints the quantified statement. A [checked run](CHECKED-RUN.json) records the source hashes and the four successful process exits. The output directory contains the four process logs, the certificates and `RESULT.json`. Certification permits zero trust tags, skipped proofs or introduced axioms. The computations are defined using ACL2's integer arithmetic. [Published integer reference](../../demos/simplestories-v2-5m/reference/quantization/oracle.py)

ACL2 admits the following statement.

```lisp
(implies (and (natp token) (< token 4019))
         (ssv-profile-ok token (ssv-image)))
```

The image and model-derived data carry the [SimpleStories MIT notice](../../LICENSES/SimpleStories-MIT.txt) and [model card](../../LICENSES/SimpleStories-MODEL-CARD.md).

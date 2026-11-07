# Combined SimpleStories security simulation

This separately selected S-AWIC simulation combines signed model admission,
periodic reauthorization, encrypted authenticated weight reads and authenticated
encrypted K/V. It runs the full six-layer SimpleStories integer datapath.
It supplies no FPGA image or hardware speed result.

The selected circuit accepts a model only after real 2-of-3 LMS verification,
AES-CTR decryption, full-image hashing, every signed page comparison and the
fixed SiLU/RoPE checks. Runtime page digests and normalization coefficients come
from that admitted package. Real AES-SIV protects external K/V with a distinct
model identity/key domain and a session/CLEAR epoch.

Home signs a context binding the admitted model, session epoch and key domain,
along with the existing device/challenge/geometry fields. On-time renewal
preserves inference state. Permission gates STEP admission, runtime memory
issue and delivery, and public token publication. A ledger retains ownership of
accepted physical reads through consumer reset and drops their late replies.
CLEAR cancels the active STEP and pending token, then holds new APPEND/STEP
admission until the live consumer and external read ledger complete their drain.
It preserves the admitted model and current authorization.

## Replay

The supported toolchain uses Python 3.12, NumPy 1.26.4, OpenSSL 3 with native AES-SIV,
Verilator 5.050, a C++ compiler and make. From the repository root:

```sh
python3 demos/simplestories-v2-5m/variants/combined-security-simulation/run.py --output /tmp/combined-simplestories-replay
```

The output directory must be new and outside the repository. The replay uses
one compiler worker by default and runs the cases serially. Set `--build-jobs N`
to choose compiler workers. It has no elapsed-time cutoff
or automatic retries. Full signature verification, model scanning and numerical
execution make this a substantially longer test than a component smoke test.
Failed and partial runs remain in the output directory.

For the pinned Linux toolchain, build the supplied image once, then use the same
replay entry point with the repository mounted read-only:

```sh
docker build -t combined-simplestories-toolchain demos/simplestories-v2-5m/variants/combined-security-simulation/toolchain
mkdir -p /tmp/combined-simplestories-output
docker run --rm --init --network none --cpus 1 --memory 4g --mount "type=bind,src=$PWD,dst=/repo,readonly" --mount type=bind,src=/tmp/combined-simplestories-output,dst=/out --entrypoint python3 combined-simplestories-toolchain -I -B /repo/demos/simplestories-v2-5m/variants/combined-security-simulation/run.py --output /out/replay
```

The image pins the official Verilator base and official NumPy wheel hashes for
ARM64 and x86-64. Only image preparation downloads dependencies; the replay
needs no network, proprietary simulator, vendor RAM library or Mac paths.

`RESULT.json` records overall acceptance. Its `driver` directory retains
tool versions, exact commands, selected-source seals, generated fixtures,
compiler output, native logs, binaries and per-case checks. Final aggregation
rechecks case identities, expected markers, commands and retained log hashes;
swapped-receipt and changed-log controls must fail. Verilator warnings
must match the narrow reviewed inherited source/message/count policy; new
warnings fail acceptance. These inherited warnings are not a width-correctness
proof. To schedule finite slices, use `--phase prepare`, `--phase build`,
`--phase case --case N` and finally `--phase summarize` against the same output.

The [recorded Linux validation](VALIDATION.json) binds all eleven native cases,
independent numerical and cryptographic checks, source hashes and compiler identities.
It also records the local replay's aggregate resource observations.

## Checks

| Case | Required observation |
| --- | --- |
| 0 | Model A produces `108, 32` across a genuine on-time renewal without resetting the consumer. |
| 1 | Expiry during an accepted STEP blocks publication and drops actual delayed memory responses. |
| 3 | A fresh epoch-2 A grant produces `108`; the actual encrypted K role is captured and independently authenticated. |
| 5 | Signed/encrypted A→B replacement produces A token `108`, then B tokens `0, 0`, with distinct model keys. |
| 6 | Authorized, populated B at epoch 2 rejects that authentic A epoch-2 K/V record at the same coordinates before any affected healthy plaintext reply or new token. |
| 2 | Reset and re-admit A with the same device/challenge: its old epoch-1 grant is refused in epoch 2. |
| 4 | Independently boot B at the same epoch/device/challenge as A: A's old grant is refused on model context. |
| 7 | Expire an active A STEP and drain its late replies; a fresh B session produces `0, 0` and no A token is published. |
| 8 | CLEAR cancels a STEP with real delayed reads; after drain, fresh APPEND/STEP produces `108` under the same lease. |
| 9 | CLEAR suppresses a held token and simultaneous APPEND/STEP handshakes; fresh APPEND/STEP produces `108`. |
| 10 | An offered K/V write stays stable through CLEAR until accepted; after drain, fresh APPEND/STEP produces `108`. |

The replay also checks all 65,536 two-port address pairs and one-edge read
latency of its portable AES lookup model against independent finite-field
truth. It preserves the existing AES controller logic and replaces only the
two read-only lookup wrappers. The [retained-model comparison](references/retained-lookup-comparison.json) has a
separate source-bound validation record.

Fixture generation signs genuine packages with public demonstration keys,
round-trips weight encryption with OpenSSL and runs a fresh independent integer
oracle. B changes only ten final-normalization words, preserving geometry and
fixed lookup tables. The A2 and B2 captured K role has identical plaintext but
different authenticated model/key domains. Captured RTL records are checked
with both native OpenSSL AES-SIV and an RFC 5297 composition, including wrong
model, key, epoch and altered-ciphertext controls.

## Scope and trust

The [input inventory](SOURCE-INPUTS.json) binds the reused public sources and
assets. Helpers derive compiler snapshots and record exact edits instead of
publishing another copy of the hardware trees. Existing FPGA source selections,
images and benchmark measurements are separate.

The test explicitly models a two-entry private key vault, a persistent nonzero
monotonic session epoch, trusted monotonic time, deterministic private challenges
and external memory. These are service contracts, not implementations of secret
provisioning, nonvolatile anti-rollback state, an entropy source or a trusted
physical clock. Unknown model roots are refused by this two-model vault fixture.
The simulation's cycle/tick periods are test parameters, not a wall-clock lease
specification. The active-STEP expiry check advances only the modeled trusted
time past the local absolute deadline; it does not exercise the inherited home
controller's separate core-cycle timeout branch.

This is finite RTL simulation with independent references. It does not establish
whole-device formal verification, physical freshness, timing closure, resistance
to tampering, production LMS key management or a residual-training certificate.
The project [formal argument](../../../../docs/FORMAL-ARGUMENT.md) distinguishes
the relevant proof obligations.

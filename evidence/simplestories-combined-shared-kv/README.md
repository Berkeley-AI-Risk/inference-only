# A shared K/V cipher for two signed SimpleStories models

One AES-SIV engine serves the two approved model domains in this simulation of the six-layer SimpleStories S-AWIC. A signed replacement selects a model’s identity and demonstration keys. Cache records bind to that identity and the session. Model A generated tokens `108, 32`. Replacing A with B produced B’s two expected tokens, `0, 0`. In a separate run, B received an authentic cache record that A had produced at the same epoch. The circuit detected the mismatch on the external reads, delivered none of the affected plaintext to attention, and published no further token. [Native replacement transcript](recorded/case-5.log) · [Cross-model transcript](recorded/case-6.log)

The eight commands exercise renewal, expiry during inference, expiry while AES is active, signed A-to-B replacement, cross-model K/V rejection, and CLEAR during computation, at a held token, and with a write pending. The checker verifies the ordered public tokens and lease contexts against the independent public fixture generator. It also authenticates both captured records with OpenSSL. The simulation supplies the demonstration keys, challenges, time, epoch and external memory behavior. [Expected observations](EXPECTED.json) · [Recorded process and input evidence](MEASUREMENT.json)

A fresh replay from a clean checkout regenerated ten demonstration fixtures and passed all eight cases. All three builds checked their 112 inputs. The fresh A and B role records matched the recorded bytes and passed the independent authentication and re-encryption check. The stale A record used in the B run caused one SIV fault after five reads, with zero affected plaintext uses and zero further tokens. [Fresh native replay receipt](FRESH-NATIVE-REPLAY.json)

## Replay

Run these commands from the repository root using the dependencies of the [combined-security simulation](../../demos/simplestories-v2-5m/variants/combined-security-simulation/README.md). Git must have the objects for commit `b12eadcffd05a6052d648ec23869bc369c4cd16a`. The two output directories must be fresh for initial preparation.

```sh
python3 -I -B demos/simplestories-v2-5m/variants/combined-security-simulation/run.py \
  --phase prepare --output /tmp/simplestories-public-inputs
python3 -I -B evidence/simplestories-combined-shared-kv/stage.py \
  --public-repo . --upstream /tmp/simplestories-public-inputs --output /tmp/simplestories-shared-kv
python3 -I -B evidence/simplestories-combined-shared-kv/run.py recorded \
  --staged /tmp/simplestories-shared-kv
```

The preparation regenerates the signed packages, encrypted model data, model identities and grants. Each of the three suites checks all 112 source inputs and its own fixture files. The recorded command checks the original simulator transcripts and both captured K/V records. [Inputs, patches and compiler arguments](DECK.json)

For a fresh Verilator build and all eight native runs, use the following command. Repeating it after an interruption reuses verified successful builds and cases in the same directory. The original runs took roughly an hour of simulation in total. The fresh run writes its own logs and results in the staged directory.

```sh
python3 -I -B evidence/simplestories-combined-shared-kv/run.py native \
  --staged /tmp/simplestories-shared-kv
```

The comparison covers digital simulation. Physical timing and board performance require their own implementation reports and board measurements. The model and project sources retain their existing notices. [License scope](../../LICENSE-SCOPE.md) · [SimpleStories license](../../LICENSES/SimpleStories-MIT.txt) · [Third-party notices](../../THIRD-PARTY-NOTICES.md) · [Packet checksums](SHA256SUMS)

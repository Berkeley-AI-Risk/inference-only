# SimpleStories on one or two simulated dies

One instance of the rank RTL and two copies sharing the same model both generated **200 → 15 → 103** from prompt token **378**. Each output became the next input. The three token IDs match the released FPGA capture. Both simulations also match the integer reference on all 4,019 vocabulary scores at each step. This hybrid simulation tests whether a second rank can contribute real arithmetic without changing the model’s answer. [Board qualification](../../../demos/simplestories-v2-5m/GREEDY-QUALIFICATION.md) · [Proposed reusable die](../../../docs/PROPOSED-REUSABLE-AWIC.md)

## Where the computation runs

Each rank contains 16 instances of the released W10 × A16 multiplier. The singleton computes every column of every matrix row locally. In the paired run, rank 0 sends half of the activation vector to rank 1. Each rank multiplies its columns by its own weight slice. Rank 1 sends its signed partial sums back, and rank 0 adds them before scaling or rounding. This split covers all six layers and the tied vocabulary head, including the 682-column down projection with 341 columns per rank. [Rank RTL](rank.sv)

The simulator checks the fixed board image and reconstructs its weight tables on the host. The released Python model handles embedding, nonlinear operations, scaling, K/V history and greedy selection. The host schedules work and verifies HMAC-SHA-256 tags with public test keys. Transmit and receive handshakes, sequence checks, partial-sum storage and addition run in RTL. The experiment leaves physical die performance, autonomous control, runtime memory authentication and production session provisioning open.

| Three dependent steps | One rank | Two ranks together |
| --- | ---: | ---: |
| Matrix row sums checked against independent integer arithmetic | 55,041 | 55,041 |
| Vocabulary scores compared | 12,057 | 12,057 |
| Accepted activation frames sent to rank 1 | 0 | 330 |
| Accepted partial-sum frames returned to rank 0 | 0 | 3,456 |

The comparison also covers intermediate vectors and accumulated K/V entries at each position. A control changes one weight slice used by rank 1 at the vocabulary head. The first output changes from 200 to 0, and the next step generates 94 from that 0. The independently modified reference produces the same sequence. [Machine-readable results](receipt.json)

## What happens to an old partial sum?

The test captures an authentic partial sum, restarts both ranks, and replays the frame at the same position, matrix, row and sequence number. The keys stay the same. The host verifier uses the new session identifier and rejects the old tag. The RTL keeps all 16 sum registers intact and records zero writes. On the next clock edge, the current frame commits all 16 rows. The restarted run produces token 200. Separate controls exercise replay within a session, a damaged tag and attempts to use both peer ports in singleton mode. [Transport fixture](transport.py)

## Reproduce the result

Use a little-endian host with NumPy 1.26.4, Verilator and a C++20 compiler. The recorded run used Python 3.10.6 and Verilator 5.050. From the repository root, run

```sh
python3 -I -B research/reusable-die/simplestories-tp1-tp2/run.py
```

The runner checks the [source and data hashes](PUBLIC-PINS.json), builds the RTL, reconstructs the model from the included image, and compares the new receipt byte for byte with the [recorded receipt](receipt.json). Generated files are written under the experiment’s local `build/` directory.

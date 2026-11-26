# SimpleStories S-AWIC inference on AWS F2

On one physical F2 boot, the chip admitted signed SimpleStories-V2-5M model A
and returned token 108 after the host appended token 1. The host then ran six
prompts twice. **All 1,026 generated tokens matched the reference**, excluding
the initial 108. Both passes returned token 15 after the full 512-token prefix.
[Recorded inputs and outputs](two-pass-wire-summary.json)

| Prompt | Input tokens per pass | Matching outputs in pass 1 | Matching outputs in pass 2 |
| --- | ---: | ---: | ---: |
| around128 | 1 | 128 | 128 |
| fox128 | 8 | 128 | 128 |
| help64 | 7 | 64 | 64 |
| moon64 | 9 | 64 | 64 |
| prefix128 | 128 | 128 | 128 |
| prefix512 | 512 | 1 | 1 |

The board acknowledged CLEAR before each prompt. The host read 2,370 successful
command replies across the trial, including the initial APPEND and STEP. By
the end of the second pass, the board had verified 51 authorization grants for
model A. This physical trial exercised signed admission, ordinary inference
with protected K/V, CLEAR, and renewal. Signed model replacement, denial and
stale K/V handling have separate [simulation evidence](../../demos/simplestories-v2-5m/variants/combined-security-simulation/README.md).

The private FPGA image met its routed 75 MHz inference and 250 MHz host clock
constraints. Worst setup slack was +0.071 ns and worst hold slack was +0.010 ns.
All 201,385 routable nets routed. Four critical clock crossings matched the
static shell reference and zero unresolved critical crossings remained in
project logic. The guest SDK did not provide a physical clock readback.

### First board image

An earlier private image completed five prompts on one boot and matched 512
outputs. Its signer reached a 25-grant cap before the host read the output for
the sixth prompt. The two-pass trial above used a different routed image.
[First board capture](wire-summary.json) · [First image qualification and timing](https://github.com/Berkeley-AI-Risk/inference-only/blob/6c35525d80f3e06c35d32f1a9575106aac7667f5/evidence/simplestories-combined-sawic-f2/README.md)

### Check the recorded tokens

From the repository root, compare both captures with the
[public reference sequences](../../demos/simplestories-v2-5m/tests/reference-cases.json).
The check runs offline.

```sh
python3 -I -B evidence/simplestories-combined-sawic-f2/check.py
```

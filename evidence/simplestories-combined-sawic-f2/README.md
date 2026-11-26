# SimpleStories S-AWIC inference on AWS F2

On one physical F2 boot, the design admitted signed SimpleStories-V2-5M model A
and an authorization grant. After the host appended token 1, the first STEP
returned 108. The board then matched every generated token in five complete
prompts while its periodic authorization was renewed. [Recorded inputs and outputs](wire-summary.json)

| Prompt | Input tokens acknowledged | Reference output tokens verified |
| --- | ---: | ---: |
| around128 | 1 | 128 |
| fox128 | 8 | 128 |
| help64 | 7 | 64 |
| moon64 | 9 | 64 |
| prefix128 | 128 | 128 |
| prefix512 | 512 | 0 of 1 |

The five completed prompts yielded 512 verified outputs, excluding the initial
108. On the sixth prompt the board accepted STEP after all 512 inputs. The
signer refused grant request 26 at its 25-grant cap (one initial grant and 24
renewals). The host stopped before reading the token. The planned second pass
did not run.

The FPGA image combines signed model updates, periodic reauthorization and
protected K/V. This trial exercised ordinary inference under model A. Model
replacement and rejection of stale K/V have separate [simulation evidence](../../demos/simplestories-v2-5m/variants/combined-security-simulation/README.md).

The routed design met its 75 MHz inference and 250 MHz host constraints, with
worst setup slack of +0.022 ns and hold slack of +0.010 ns. All 202,142 nets
routed. Four critical clock crossings matched the static shell reference
and zero unresolved critical crossings remained in project logic. The guest
SDK did not provide a physical clock readback. The FPGA image is private.

### Check the recorded tokens

From the repository root run the following offline comparison. It checks the
recorded prompt and output IDs against the [public reference sequences](../../demos/simplestories-v2-5m/tests/reference-cases.json),
including the unread sixth result.

```sh
python3 -I -B evidence/simplestories-combined-sawic-f2/check.py
```

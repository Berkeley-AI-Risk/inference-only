# Protected two-tape decoding at context 16

Two independently prefilled SimpleStories tapes issue one token request each, one core clock apart. Tape A returns 85 and tape B returns 490. Sharing all seven layer-0 projections and four 32-byte RoPE words across the two requests finished the pair **468,853 clocks earlier (6.043%)** than serial execution and returned A **184,247 clocks later (4.751%)**. Both latencies start at A’s public offer and end when the indicated token is accepted. The two strict layer-0 controls agreed on both executable revisions. [Fresh eight-case numerical and traffic receipt](RECIPIENT-NATIVE.json)

| Schedule | First token A, clocks | Both tokens, clocks | Verified projection bytes | Model response bytes | External model read bytes |
|---|---:|---:|---:|---:|---:|
| Serial | 3,878,200 | 7,758,818 | 13,555,200 | 14,155,008 | 13,983,744 |
| Shared layer 0 | 4,062,447 | 7,386,180 | 12,640,640 | 13,230,720 | 13,049,856 |
| Shared layer 0 and RoPE reuse | 4,062,447 | 7,289,965 | 12,640,640 | 13,169,280 | 13,000,704 |

Each schedule uses one projection engine, one normalizer, one modeled memory port and one outstanding raw read, with a 10 ns core clock and a 14 ns memory clock. The three byte columns count successive interfaces. External K/V traffic totaled 122,880 bytes read and 6,912 bytes written per healthy pair. Each tape matched its independent numerical reference, including all 4,019 vocabulary scores. Four directed CLEAR runs covered parked A, parked B, a held lookup hit and an outstanding lookup miss. In each case the survivor matched its reference, the canceled generation produced no later token and the fresh generation returned 15. These measurements cover the two fixed histories, with tape 0 oldest, in digital simulation.

## Replay

Use a full clone containing public dependency commit `a1d2b7b1b4aa0c469ca429cf0405d2f30d702173`. The archive contains the project RTL, harness, fixture oracle, source manifests and expected numerical inputs. The runner verifies those inputs and the model image from the pinned checkout. The measured toolchain used Verilator 5.050, GNU Make and a C++ compiler. Python 3.8+ runs the driver. Icarus 13 and vvp run the quick fixture check. Run the commands from the repository root with a fresh, space-free scratch directory. The two builds are reused across all eight simulations. [Replay source archive](protected-p16-source.tar.gz)

```sh
repo=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d /tmp/protected-p16.XXXXXXXX)
tar -xzf "$repo/demos/simplestories-v2-5m/simulation/protected-two-tape-p16/protected-p16-source.tar.gz" -C "$scratch"
cd "$scratch/p16" || exit 1
python3 -B replay.py prepare "$repo" "$scratch/work" || exit 1
python3 -B replay.py fixture "$scratch/work" rope || exit 1
for packet in strict rope; do
    python3 -B replay.py build "$scratch/work" "$packet" || exit 1
done
for arm in serial strict control treatment park-a park-b held miss; do
    python3 -B replay.py run "$scratch/work" "$arm" "$scratch/$arm.json" || exit 1
done
```

The archive’s `provenance.json` binds each member to its SHA-256 and identifies the source additions and pinned public Git blobs. The project’s code carries Apache-2.0 terms. The SimpleStories model and model-derived references retain the publisher’s MIT declaration. The archive includes the notices for both. [Project licence scope](../../../../LICENSE-SCOPE.md) · [Model notices](../../../../THIRD-PARTY-NOTICES.md#simplestories-model-and-tokenizer)

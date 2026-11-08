# Replay inputs, controls and interpretation

Use the public source bytes at commit `159528e36d46fc803326758b160aa5e84aebd72b`. The package's [public input hashes](../PUBLIC-INPUTS.json) fix seven archived inputs, including the build receipt, model manifest, netlist census, FPGA metrics and capture, and H100 selection. These bind the next inputs by SHA-256.

| Input | SHA-256 or role |
| --- | --- |
| SimpleStories greedy bitstream | `01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57` |
| Original hardware input inventory | `4f4cbc54676e9d976af7358386c19d8befdab34d819de30e4fb3e42beb3362fd` |
| Native post-synthesis Verilog, decompressed | `627b0ac326f5507a641e444ee6e89d58b3b98bc4e60ef447e1e65e9b9608d224` |
| Packed weights and expected greedy simulation | Model manifest fixes the image and test fixtures. The full boot replay checks all 68 production inputs individually against the original build inventory, including the 64 compiled sources. |
| Measured rate denominators | Two archived single-board final STEP times and the selected H100 raw trial, located by archive member and digest. Both refer to 128 occupied input positions. |
| Proof and trace evidence | [Local evidence manifest](../EVIDENCE-SHA256.json). The `records` mode reuses the temporal proof outcomes and the three previously observed traces. The `full` mode creates these from scratch. |

The build and measurement receipts are trusted statements about the hardware and GPU that ran. The checks rely on faithful HDL elaboration, sound SAT/PDR results, native primitive-enable semantics and the documented 25 MHz clock. Genuine clocked reset, the selected control topology and intact core registers are required. In the three example executions the memory system supplied the pinned model and honest cache history. The digital ownership proof overapproximates its data inputs. A hostile external memory can gain observations or alter unauthenticated state while respecting the same number of registered operations.

The complete command sequence and output summary are in [the reader](../README.md). Append `--keep /path/to/a/new-directory` to either command to retain detailed intermediate results. The dependency chain is

1. [Attention SAT](attention-accumulators/check.py) checks that each product bank can change its legal write and cannot affect the other state's ordinary registered sinks. [Cadence](attention-accumulators/cadence.py) checks an all-trace scheduling constraint.
2. [Projection induction](projection-lanes/check.py) checks accepted inputs, reset, cancellation, per-bank potential and in-flight work. [Joint controller](joint-cadence/check.py) checks the shared parent schedule. Its wrong-state exclusion fails on a reachable trace. Deliberately allowing an unscheduled score transition also breaks the real joint exclusion.
3. [Postscale/RMS/elementwise](remaining-datapath/check.py) checks enabled sinks against the actual arithmetic and owner controls. Moving the postscale product enable one tag early fails the native check.
4. [Support SAT and netlist](support-sites/check.py) compares all 90 named cell instances with the native Verilog, decodes the address-stride LUTs, checks all 291 valid source descriptors and rejects immediate public embedding readout. Controls include an actual sensitive normalizer input and concurrent remembered prefetch during a local metadata read. [Ownership PDR](support-sites/owners.py) checks disjoint shifted admission windows with reachable covers.
5. [Verilator replay](support-sites/replay.py) compiles a checked scratch copy of the normal four-bank production configuration. A passive monitor distinguishes internal arithmetic, page-level external memory observations and the public token handshake below the UART serializer. [Ledger](support-sites/ledger.py) decodes all 4,019 × 256 eligible fixed-embedding coordinates, checks the traces and calculates the bound.

The simulation fixture lists a different SHA-256 for 12 of the 68 production inputs. The replay checks the actual production bytes against **both** the selected public manifest and the original build inventory. The test source bytes match their fixture hashes. The proof uses local Yosys 0.68+post, its ABC executable, Verilator 5.050 and the platform's C++ compiler. CPU-only runs require no FPGA, H100 or credentials. The hashes allow another reviewer to identify every byte this calculation trusts. Source-to-physical implementation equivalence and converter/tool correctness still require their own evidence.

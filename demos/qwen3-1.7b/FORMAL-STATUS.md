# Qwen3-1.7B: formal status

[Guide](README.md) · [Validation](VALIDATION.md) · [Reproduction](REPRODUCE.md)

**Formal verification is in progress. Source-bound component results cover the
authentication path through the token machine's private model input. The
complete inference design is not formally verified.** No whole-machine
refinement theorem, universal numerical-correctness theorem or formally
certified residual training factor is claimed.

The [status record](evidence/formal/STATUS.json) identifies the checked source
files, production parameters, component-certificate hashes and open obligations
as of October 29, 2026. Its named source hashes match [SOURCE-INPUTS.json](SOURCE-INPUTS.json).
These are RTL results; equivalence to the complete synthesized FPGA image
remains a separate obligation.

## Verification objective

The intended whole-design result combines two claims:

1. **Functional correctness:** permitted operations behave as specified.
   `APPEND(token)` adds the supplied token to the logical tape; `STEP` computes
   the next token with the fixed model and its specified numerical rules,
   appends it to the tape and returns it;
   `CLEAR` resets the logical context. Arithmetic, ordering, storage,
   sequencing, clock crossings and reset behavior are part of this claim.
2. **Inference-only restrictions:** every possible application command
   sequence stays within the permitted interface. Inputs cannot replace the
   accepted weights, bypass authentication, select an alternative hardware
   execution program or obtain a general private tensor/matrix-operand port.

The target is that the configured circuit's observable behavior refines this
abstract interface under its declared environment contracts. Invalid commands,
backpressure, faults, cancellation and commands issued while busy must have
specified rejection, waiting or error behavior. Restricted fixed-model startup
provisioning, status registers and the 16-bit attention-status diagnostic are
also explicit parts of the interface; the complete engineering image has
facilities beyond the three normal inference operations.

`CLEAR` concerns logical state ownership and later inference: previous tape
contents and derived context must not be used after a completed clear. It does
not require every private memory cell to be physically overwritten with zeros.
Successful native boot and legal inference must also be shown reachable under
the external-service contract; completion guarantees require their stated
service assumptions. The hardware configuration is assumed frozen, as
described in the [interface assessment](README.md#interface-and-inference-only-scope).

**This joint whole-design theorem is the objective, not an achieved result.**
A proof of it would still leave the separate residual-training-factor analysis:
how much training work an external controller could obtain by combining the
permitted operations.

## Checked component scopes

| Component | Qualified result | Boundary |
| --- | --- | --- |
| SHA-256 and fixed-root page authentication | SHA/framing meaning, current-page byte preservation and ordered authenticated output through four workers with eight slots each. | Scoped checked composition with its stated compiler, solver and binding-checker trusted base. Excluding a distinct colliding model additionally uses the cryptographic resistance assumption. |
| Production AWS model reader | Authenticated cache publication, independent captured reads, request-relative payload/LAST/short formatting, response order, stalls, reuse and component cancellation. | Actual 64 weight + eight auxiliary cache lines and prefetch 32. Module-default proofs are not substituted for this configuration. |
| Parent verified-response queue | Both complete 2,049-bit words preserve the verified reader snapshot and FIFO order through invalid-cycle refresh, stalls, simultaneous events and reset/abort. | Native unit induction with Z3 and cvc5, complete compiled state/port refinement and checked composition to the token-machine private model input. |
| Fixed-core model-beat storage | Complete 2,048-bit physical capture/hold and all 128 sixteen-bit scalar slices. | Storage history and selection only. Native validity/index ownership and actual operand admission/use remain open. |

The reader's finite native applicability run checks all 72 cache slots,
566,528 response bytes and thirteen injected source faults, with 5,274 active
assertions. These tests qualify source applicability and fault sensitivity;
their assertion count is not a proof-coverage percentage. Exhaustive numerical
sweeps and finite FPGA/reference comparisons are separate evidence classes.

## How the proof layers support the objective

| Layer | Contribution to the whole-design argument |
| --- | --- |
| Arithmetic and data blocks | Establish the specified numerical functions and storage/transport behavior. These are ordinary functional-correctness obligations. |
| Authentication and owned copies | Establish which fixed-model bytes may be used and preserve those bytes through buffers and consumers. |
| Controllers, lifecycle and state ownership | Establish permitted operation sequences, operand/address authority, command/error handling and logical CLEAR/session behavior. |
| Source-bound composition and implementation mapping | Join the block contracts at actual ports and configurations, discharge abstractions and state the remaining platform/physical assumptions. Component results become a whole-design claim only after these joins are complete. |

Simulation, exhaustive finite-domain checks, reachable covers and source-fault
tests also qualify behavior and proof applicability. They retain their stated
domains and support the formal program alongside the universal RTL proofs.

## Verification method

The work retains native state and parameter dimensions, uses independent
history references, and checks reset bases plus unrestricted induction.
Compiled bindings connect the properties to actual clocks, state, memory
ports, complete payloads and instance parameters. Reachable covers and
deliberately altered source or bindings test the scope of each result.
Frozen inputs, raw solver queries/replies and fresh model regeneration support
the development audits. Resource-stopped or unresolved attempts receive no
proof credit.

Conservative child-interface abstractions have explicit boundaries. Composed
authentication claims discharge the child contracts they consume; the
physical core-buffer observation leaves its numerical children unproved.
The trusted base includes RTL/SMT translation, solver soundness, the binding
and composition checkers, and the stated mathematical lifting steps.

## Remaining obligations

- Connect authenticated inputs to the fixed core's actual scalar/projection
  operand admission, index histories, scheduling and use.
- Complete public command/lifecycle restrictions, model-write drain/lock and
  whole-path reset/clock-crossing composition.
- Establish current-owner histories for all remaining private state and
  relational session isolation after CLEAR and drain.
- Complete general arithmetic, vector and whole-model numerical refinement;
  general FP32 multiplication remains unresolved.
- Establish successful full-native boot/inference reachability and the
  synthesis, vendor-IP, memory, timing and image-equivalence boundaries.

The released circuit does not authenticate K/V or encrypt weights. These
component results do not qualify the separate protected K/V extension or
resistance to physical modification of the reprogrammable AWS platform.

## Evidence and reproduction boundary

This release contains the source-bound status summary, finite validation
records and implementation evidence. **It does not include the complete
development solver/evidence bundle.** Independent solver reproduction needs
that bundle, its source/model/tool bindings and the recorded commands.
Checking the status JSON or source hashes alone does not rerun a proof or
attest an FPGA currently loaded in another machine.

The [validation guide](VALIDATION.md) and [reproduction guide](REPRODUCE.md)
describe the evidence supplied here. [SimpleStories' scoped proofs](../simplestories-v2-5m/FORMAL-STATUS.md)
have their own RTL, bindings and assumptions and do not transfer to Qwen.

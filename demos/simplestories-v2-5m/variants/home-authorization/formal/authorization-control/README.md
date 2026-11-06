# Periodic reauthorization: authorization-control proof

The selected 25 MHz SimpleStories S-AWIC has a composed authorization-control
proof connecting its home lease controller, permit register, token UART and
runtime request gate. Twelve formal jobs (ten inductive and two auxiliary
combinational checks) and finite simulation controls support
the [conditional statement](THEOREM.md). The broader APPEND/STEP/CLEAR
whole-machine inference-only theorem remains open.

The boot proof retains its exact recorded child-wrapper source fingerprint.
For the selected fixed-wiring stream implementation, the source audit consumes
the separate [five-configuration equivalence packet](../../../signed-update/formal/stream-assembly/README.md),
binding both exact source snapshots. Solver designs, input queries and engine
receipts retain their original bytes; no cryptographic-algorithm theorem is
added by this wrapper substitution.

| Obligation | Result |
| --- | --- |
| Canonical grant transcript, model binding, nonce capture, lease expiry | Proved by temporal induction |
| Registered permission, runtime reset and request suppression | Proved by temporal induction |
| Token-result and first-byte publication admission | Proved by temporal induction |
| LMS start since reset and captured trust anchor | Proved by temporal induction |
| Every current-frame signature byte and synchronous verifier read | Proved with the real 1,292-byte RAM and an arbitrary constant byte address |
| Complete five-byte reply reaches UART quiet within 10,855 clocks | Proved with the real UART bridge, transmitter and receiver |
| Single use of a challenge, distinct renewal nonce, old deadline continuity | Proved by temporal induction |
| Joined authorization, UART deadline and runtime request gate | Proved by temporal induction |
| Joined real grant RAM/controller and real LMS controller after admission | Proved with abstract shared-SHA results |
| Runtime model lock implies sealed model admission | Proved over the actual Boolean guard chain, with hidden state arbitrary |
| Phase-exclusive ownership-expression factorization | Proved equivalent for all binary states/flags; permits the formal reset conversion without changing hardware |
| Actual boot-admission to home-authorization verifier handoff | Proved with the real admission/home/LMS controllers, signature/manifest RAM and shared-owner mux, with abstract shared-SHA outputs |

A response can start only with current permission for the admitted model and
more than 20,000 clocks remaining. At 217 clocks per UART bit, the complete
reply reaches quiet within 10,855 clocks (about 0.434 ms at 25 MHz). The joined
proof establishes sufficient remaining permission throughout a reply and
prevents a normal home-transport handoff from pausing it midway. An independent
terminal fault or reset can abort a reply and closes token publication.

Waiting for renewal does not refresh the old lease. Each challenge can grant
only once; a later grant uses a different nonce. Expiry/failure cannot be
cleared by late grant bytes or a retained verifier result. A pending response
for the unchanged model may resume after a successful renewal; it cannot
create permission by itself.

The [certificate and evidence inventory](CERTIFICATE.json) records exact
scopes and receipts. Production timer values are retained: 100,000,000 response
clocks, 250,000,000 lease clocks, and 125,000,000 renewal-lead clocks. A finite
controller simulation runs 375,000,140 actual clocks, accepts two abstract-valid
grants, completes renewal, withholds the next authorization and checks expiry,
the publication guard and rejection of late grants. A separate reachable
witness checks all 1,292 signature bytes. These are simulations with abstract
crypto results, not additional board or cryptographic-algorithm tests.

Eight deliberately broken formal variants are detected, covering header/model
binding, permit bypass, transmitter stall, publication runway and mid-frame
pause, model-admission gating and boot-verifier reset. Some failures are induction countermodels; they are not presented as
reachable base-case counterexamples. Reachable simulations separately detect
removed header/model guards and corrupt signature-RAM writes.

A separate 164,049-clock simulation loads the published signed model prefix,
observes a real shared-LMS boot verdict, verifies its clearing at the ownership
transition and obtains a home grant in a new lease verifier epoch. Its reset-
bypass control retains the boot verdict and is rejected. SHA digests are
abstract in this simulation; it is not a cryptographic or board test.

## Replay

From the repository root, check source, generated-design correspondence,
recorded prover receipts, controls and simulations using only Python:

```sh
python3 demos/simplestories-v2-5m/variants/home-authorization/formal/authorization-control/check_composition.py --out /tmp/home-auth-recorded
```

Add `--fresh` to rerun all twelve formal jobs with Yosys, yosys-smtbmc and cvc5.
For a selected fresh job, add `--fresh --jobs uart-deadline` (or another job
name in the certificate). Each output directory must be new. Recorded-only
replay checks integrity and reconstructs the proof inputs; it does not invoke
a solver or count recorded results as fresh proofs. Fresh engines run
sequentially with an 8 GiB process-tree RSS watchdog sampled once per second.
There is no fixed five-minute cutoff. The polling watchdog is not an OS hard
memory reservation.

The harnesses retain actual functional RTL, with observation ports, ghost
history and recorded cone cuts. The runtime join copies the selected permit
and reset blocks exactly, keeps the actual backend arbiter, and lets numerical
clients issue arbitrary binary data/requests. It does not prove their
arithmetic or three-command semantics. A separate source audit checks 75
connections through the selected wrappers and lease-owner mux, with 32
additional boot/model-lock and page-port connections checked. The complete handoff job
removes the assumption that the verifier is already owned by the lease service:
on entry it is held in reset, the boot verdict is cleared and a later home
verdict requires a lease-started epoch. Payload/authenticated-memory and
cryptographic algorithm correctness remain separate contracts.

The model/nonce/memory/cryptographic and physical assumptions are stated in
[THEOREM.md](THEOREM.md). In particular, this packet does not prove LMS/SHA
functional correctness or unforgeability, nonce entropy, analog reset/CDC
behavior, physical tamper resistance or an unconditional whole-chip theorem.
The separate hardware validation records retain their own scope; cold
electrical power cycling is not established by this proof packet. The
[reset/timing review](../../RESET-REVIEW.md) separates the observed SRAM
reload from electrical power cycling. A volatile image must be reloaded after
power loss; autonomous configuration-flash boot is not tested.


The current source inventories bind the page-consistency implementation.
`source-history/` retains the preceding committed inventories. Unchanged
extracted proof designs retain their recorded engine results; the strengthened
model-lock guard has a fresh Boolean proof. Source correspondence and recipe
checks reconstruct the current slice. Retained witnesses and mutation controls
are preserved evidence, not new executions of this source revision. The separate
[page-consistency packet](../../../signed-update/formal/page-consistency/README.md)
adds two component induction jobs and ordinary actual-SHA unit fixtures.

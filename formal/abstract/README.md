# Reading and checking the Lean specification

[Board1PublicSurface.lean](Board1PublicSurface.lean) defines the ideal
transaction-level public machine for the SimpleStories design. Lean checks
properties of that definition. It does **not** import SystemVerilog, a netlist,
model weights or a numerical transformer implementation, and supplies no
theorem connecting the circuit to this machine. The separate RTL component
proofs and their open connections are described in
[FORMAL-STATUS.md](../../FORMAL-STATUS.md).

## Read the definitions first

Everything is in the `Board1.PublicSurface` namespace. The file imports only
`Std.Tactic`; it has no external Lean package dependencies.

- `Token := Fin 4019` represents an already valid vocabulary ID, from 0 through
  4,018. This type does not prove that the UART parser enforces that range.
- `modelContext = 2048` and `tapeCapacity = 2049` distinguish the input-context
  limit from the extra slot needed to store the last generated token.
- `Command` has exactly `append`, `step` and `clear`. `Reply` has an APPEND
  acknowledgement, a generated token or a CLEAR acknowledgement. `State`
  contains only a token list, `tape`; `State.WellFormed` bounds its length.
  `initial` is the empty tape.
- `execute nextToken state command` specifies one transaction. APPEND succeeds
  below 2,048 tokens. STEP succeeds on lengths 1 through 2,048, appending and
  returning `nextToken state.tape`. CLEAR always returns the empty state and
  its acknowledgement. `some (nextState, reply)` means success; `none` means
  the command is not accepted in that state. Neither is a cycle-level protocol.
- `run` repeats `execute` over a finite command list, keeping the **same**
  `nextToken` function throughout. It returns a final state and reply list only
  if every transaction succeeds; otherwise it returns `none`.

`nextToken : List Token -> Token` is arbitrary. The theorems hold for any such
function, including functions unrelated to SimpleStories. Its role is to
stand for one fixed deterministic model, not to prove that model's algorithm,
weights or numerical rules. The host cannot select a new function through a
`Command`, but that is a fact about this abstract definition, not a completed
proof of the hardware restriction.

## Theorem map

These names refer to the declarations in
[the Lean source](Board1PublicSurface.lean), in source order.

| Theorem(s) | What Lean checks |
| --- | --- |
| `tapeCapacity_eq`, `initial_wellFormed` | The tape has one more slot than the context; the empty state satisfies the length bound. |
| `command_exhaustive` | Every value of the defined `Command` type is APPEND, STEP or CLEAR. This is not a theorem about arbitrary UART bytes. |
| `execute_preserves_wellFormed` | Every successful transaction produces a tape within capacity. |
| `append_effect`, `step_effect`, `clear_effect` | A successful transaction has the exact tape change and reply specified above. STEP's result is the abstract function value, not a proved numerical prediction. |
| `append_requires_capacity`, `step_requires_nonempty_model_context` | Successful APPEND and STEP imply their respective input-length conditions. |
| `clear_always_accepted` | CLEAR succeeds from every abstract state. This does not establish hardware cancellation latency or erasure. |
| `run_preserves_wellFormed` | A successful finite run from a well-formed state ends in a well-formed state. |
| `run_reply_count` | A successful finite run has one reply per command. This conditional statement does not prove hardware progress or eventual replies. |

The run theorems apply to arbitrary finite command lists, not just the prompts
used in simulation. The model deliberately omits private K/V and scratch
contents, memory authentication, concurrency, stalls, faults, reset timing and
physical state. In particular, abstract CLEAR replaces the tape with `[]`;
showing that the circuit safely invalidates or drains all relevant old work
is a separate implementation obligation. No physical-tamper guarantee,
cryptographic theorem or residual-training-capacity number follows from this
file. Its fixed vocabulary and context also do not describe or qualify Qwen.

## Lightweight replay

The project pins `leanprover/lean4:v4.33.1` in
[lean-toolchain](lean-toolchain); [lakefile.lean](lakefile.lean) declares the
`Board1PublicSurface` library. Install that exact toolchain before an offline
check. If using the `elan` launcher, first use `elan toolchain list` to confirm
it is already installed; otherwise invoking Lean may download it.

From the package root, run:

```sh
cd formal/abstract
lean +leanprover/lean4:v4.33.1 --version
lean +leanprover/lean4:v4.33.1 Board1PublicSurface.lean
```

The version check must report 4.33.1. A successful source check exits with
status zero and no errors; it needs only the installed Lean standard library,
not model assets, Yosys, SMT solvers, vendor tools or an FPGA. This direct check
does not need `lake build` or generate a package build directory. It rechecks
only the abstract Lean declarations, not any RTL assertion.

The full [package replay](../../REPRODUCE.md#one-offline-verification-command)
copies this directory into a fresh work directory and invokes
`lean Board1PublicSurface.lean` there. Its Lean job is recorded in
[the offline receipt](../../evidence/offline-replay.json) and
[the runnable-package receipt](../../evidence/runnable-replay.json). Those
records identify completed runs, not extra theorems or coverage of later
hardware revisions. The exact hardware source bindings and solver limitations
remain in the separate proof inventories.

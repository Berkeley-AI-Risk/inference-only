# Actual events and interruption rules

All observations are pre-edge values in the frozen single-clock digital RTL.
An accepted transfer means VALID && READY on that edge; a held VALID also has
the specified value even when READY is low. Histories update only at transfers.
The names below are relative to `u_native.u_six_layers.u_datapath`.

| Event | Actual seam and obligation |
| --- | --- |
| Q starts | `projection_start_valid && projection_start_ready` and `norm_start_valid && norm_start_ready`; separate start-seen bits, same stable E_PROJ/STAGE_Q/layer/generation |
| Raw input to normalization | `projection_result_valid && projection_result_ready`; direct norm index/raw/exponent/last wiring and norm input readiness |
| Normalized offer | `norm_result_valid`; held value, invocation and row order |
| Normalized transfer | `norm_result_fire`, equivalently VALID && READY; one prefix increment, including a deadline-edge transfer |
| Q write | `query_ram_write_enable`; E_PROJ/STAGE_Q, projection_norm_result_order_ok, no fault_q/CLEAR/lock loss/upstream/child_fault; address output_index_q[7:0], data norm_result_mantissa |
| Q exponent | E_PROJ/STAGE_Q update on the accepted ordered normalizer result; must equal current vector's exponent |
| Stage completion | stage_done_q after output_done/last, actual projection DONE and actual norm DONE, current invocation and all256 ordered writes |

The concrete normalizer receives `upstream_fault_i || fault_q`; the Q-write gate
additionally tests immediate `child_fault`. Do not identify these different masks.
Normalizer interface_live is rst_n && !clear_i && model_lock_i &&
!upstream_fault_i && !range_fault_o && compute_cycles_q<MAX_COMPUTE_CYCLES.
MAX_COMPUTE_CYCLES is the actual default 2,000,000, not a smaller proof value.

| Cause | Native handling and theorem obligation |
| --- | --- |
| Arithmetic rejection | Shift<-62, checked left-shift overflow, no fitting candidate through31 or invalid WRITE fit: retain only the correct already emitted prefix; no successful DONE |
| Invalid descriptor/metadata | Actual layer/job/record/exponent checks; name the failed check, never assume a desired result |
| Stream/protocol violation | Actual unexpected start/input/index/last/order checks; distinguish offered and accepted beats |
| Model-lock loss | Immediate interface gates; active-state fault latch according to native priority |
| External/platform fault | Actual upstream signal and guards; no future-health assumption used to remove earlier offers from the theorem |
| Unrelated abstract child fault | Immediate Q-write suppression; registered datapath fault propagation to normalizer; no numerical rejection inference |
| Deadline | Counts all active cycles, including capture/output/DONE waits. At count MAX-1 an interface transfer can occur before the priority fault latch. Count and validate that transfer. Finite stalls can reach the deadline |
| CLEAR | Immediate interface suppression. Normalizer CLEAR precedes sticky fault/watchdog; projection job fault branch precedes CLEAR. Revoke ownership according to each actual priority. Unreset payload bits and discarded arithmetic may remain |
| Hard reset | Actual reset control; MAC product/accumulator are resetless. Establish owned histories from FIRST, not zero physical payload |

Numeric and nonnumeric causes may truncate a correct prefix. They never grant
permission to emit an incorrect value or associate old payload with a new owner.
These are value-safety rules, not a claim that every native fault/timing decision
is allowed by the eventual architectural inference-only specification.

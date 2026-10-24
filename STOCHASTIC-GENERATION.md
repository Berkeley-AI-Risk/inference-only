# Seeded SimpleStories generation on Tang Mega

The optional **seeded-sampling** image generates varied continuations from the
same fixed SimpleStories-V2-5M model. Choose temperature **0, 0.5, 1 or 2** and
a public 128-bit seed. Repeating a prompt with the same settings reproduces
the tokens; temperature 0 keeps the original exact greedy rule.

Use the local browser app to enter text and choose generation settings.
The optimized seeded image uses the same model and authenticated weights;
it has no K/V cryptographic integrity or memory encryption. The baseline,
K/V-protected and encrypted-memory versions remain separate available images.
Current package status is **Runnable release**. See the
[qualification record](CURRENT-QUALIFICATION.md) for current validation and
[timing details](CURRENT-QUALIFICATION.md#recorded-timing), then follow the
installation and generation instructions below.

## Load and check the seeded image

Use the same supported Tang Mega 138K non-Pro/device-C board and 16-MiB flash
as the [standard installation](PROGRAMMING.md). For a first installation,
complete that guide's identity, backup, plaintext-model installation and full
readback checks. Its model-installation step erases flash. If the plaintext
model is already installed and verified, switching from the baseline to this
image requires only an SRAM load; it does not require a flash write.
An encrypted-memory installation has different flash contents; follow
[its restoration guide](ENCRYPTED-MEMORY.md#install-or-restore) before using a
plaintext image.

From the repository root, verify the package:

```sh
python3.12 -I -S -B tools/verify_release.py
```

Stop the browser app and every other serial/JTAG user. Retain the exact
known-good SRAM image you intend to reload when returning to your previous
version. Use the current cable index and USB location from the programming
guide's fresh scan. For its tested cable index 4:

```sh
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs"
```

Require the intended target, successful **SRAM Program**, successful tool exit
and `Finished.`. Keep the board powered and wait at least 120 seconds after actual
SRAM load completes. The new image is volatile; reload it after power loss.
Its SHA-256 is
`d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725`;
[BUILD.json](prebuilt/seeded-sampling/BUILD.json) binds it to the selected
sources. Its scope field records the qualification status at native-build
time; later board, browser and proof results are recorded separately in
[VALIDATION.md](VALIDATION.md) and the
[qualification record](variants/seeded-sampling/QUALIFICATION.md). These
identities do not independently attest a connected FPGA.

Install the host app dependencies as described in
[host-app/README.md](host-app/README.md), then register the loaded seeded image
from the `host-app` directory:

```sh
.venv/bin/python -B qualify_board.py \
  --build-receipt ../prebuilt/seeded-sampling/BUILD.json \
  --device /dev/cu.usbserial-YOUR_BOARD \
  --confirm-loaded-source-build --acknowledge-unqualified-timing
```

Use your actual serial device. Add `--replace-profile` when a profile already
exists. The extended check requires 19 exact tokens across greedy generation,
all three positive temperatures, CLEAR replay and changed-seed fixtures,
with 45 command results. It finishes with greedy settings and CLEAR. A legacy
seven-command result cannot qualify the seeded profile. Success saves the
local profile and evidence; failure leaves generation disabled.
No reset, reflash or automatic retry follows a fault. The check discards any
current conversation and acknowledges exploratory timing, not timing signoff.

Start the app from that same directory:

```sh
.venv/bin/python -B start_local_server.py
```

Open **http://127.0.0.1:8507**. The page shows sampling controls only for a
qualified seeded profile. A successful wait or local file hash alone cannot
enable generation or establish a successful boot.

To switch back to another hardware version, stop the app, reload that version's
known-good SRAM image and rerun its matching qualification. The browser does
not switch hardware images or change flash. Choosing temperature 0 in the
seeded app itself needs no reprogramming.

## Choose settings and generate

Enter a story prompt in the browser and choose a temperature. **0** is the
default and reproduces the original greedy rule. The positive choices are
**0.5, 1 and 2**. Leave the seed automatic for a fresh continuation or supply
a 128-bit seed to reproduce an earlier run. The last-run display and
downloadable run record show the actual temperature and seed used.

Each Generate clears the tape, applies the chosen settings, uploads the
tokenized prompt and streams the continuation. Completion and Stop finish
with CLEAR. Repeating the same prompt, temperature and seed reproduces the
continuation. The tokenizer and conservative browser limits are unchanged:
at most 2,048 prompt tokens, 128 new tokens and 2,049 combined tokens for seeded sampling. The three original greedy profiles retain 128 prompt tokens, 128 new tokens and 256 combined tokens. These limits do not
constitute a full-context test of the new image.

CLEAR retains temperature and seed and restarts the generator from that seed.
Reset restores temperature 0. A different seed can produce a different
continuation, but need not change every token. The generator is deterministic
and noncryptographic; a seed is a public reproducibility setting, not a key
or a source of independent physical randomness.

## Optional token-ID diagnostics

The CLI is for direct wire tests and diagnostics. Stop or disconnect the
browser app before using the same serial device. From the repository root,
prepare a known-answer request without opening a device:

```sh
python3.12 -B variants/seeded-sampling/tools/generate.py --temperature 1 --seed 0x99aabbccddeeff001122334455667788 --tokens 378 --steps 3
```

Add `--execute` and your actual device to run it, optionally using a new
private log file:

```sh
python3.12 -B variants/seeded-sampling/tools/generate.py --temperature 1 --seed 0x99aabbccddeeff001122334455667788 --tokens 378 --steps 3 --execute --device "$FPGA_UART" --record "$FPGA_RECOVERY/seeded-check.jsonl"
```

The returned token IDs must be **357, 3898, 104**. A second invocation with the
same settings must reproduce them. The CLI prints JSON lines and accepts
token IDs rather than text. Temperature defaults to 0; a positive temperature
without `--seed` chooses and displays a fresh seed before opening the device.
It is a dry run until `--execute` is present and never programs the board.
Stop on rejection, timeout, malformed response or mismatch; uncertain commands
are not automatically retried.

For prompt token 378 and seed `0x99aabbccddeeff001122334455667788`, the
board-checked first three outputs are:

| Temperature | Token IDs |
| --- | --- |
| 0 | 200, 15, 103 |
| 0.5 | 247, 130, 32 |
| 1 | 357, 3898, 104 |
| 2 | 3436, 4007, 141 |

## Board evidence and limits

**Historical 0e6 details below.** These unchanged reports describe the archived
image, including its old benchmark and ten-case browser census. Current optimized seeded
records and completion are separately bound in [CURRENT-QUALIFICATION.md](CURRENT-QUALIFICATION.md); no old PASS or timing is transferred.

### Repeated 128-output workloads

The archived image's performance campaign used prompt token `[378]` followed by
**128 generated tokens**, the same prompt/output count used for the quoted
greedy SimpleStories measurements. Each supported temperature was run twice
with seed `0x99aabbccddeeff001122334455667788`; the second run replayed after
CLEAR without resending settings. All 1,024 outputs were recorded, and the
two complete token sequences at each temperature matched exactly. The fixed-work
wire benchmark sends all 128 STEP commands, including after an end-of-story
token; the ordinary browser app stops when that token is returned.

| Temperature | Run 1 cached command tokens/s | Run 2 cached command tokens/s |
| --- | ---: | ---: |
| 0 | 8.41 | 8.66 |
| 0.5 | 8.70 | 8.63 |
| 1 | 8.67 | 8.68 |
| 2 | 7.73 | 8.67 |

That archived campaign's headline was **about 8.7 tokens/s at temperature 1**, using 127 cached
STEP command/reply times per run and excluding the first STEP. Timings include
host/UART and evidence recording and exclude connection and prompt upload.
All repetitions are retained, including the slower first temperature-2 run.
A subsequent independent whole-model comparison checked every one of the
1,024 outputs, including all 768 positive-temperature outputs, and matched
exactly. The original capture receipt retains the narrower checks available
at capture time; the separate comparison records the later full reference
check. [The complete archive](evidence/seeded-sampling/matched128.json) retains
all wire events and reference outputs; [the evidence guide](evidence/seeded-sampling/README.md)
provides offline checking commands.

### Context and boundary qualification

The same image passed **16 context cases**: prompt lengths 128, 512, 2,047
and 2,048 at each supported temperature, with respectively 128, 4, 2 and 1
outputs. Every one of the **540 main outputs** matched the complete integer
reference. Each case also passed the baseline-style 12-token CLEAR/replay
checks without resending SETTINGS, adding **192 exact replay outputs**.
The longest cases checked the final output slot and rejection of further
APPEND/STEP operations. All cases ended with acknowledged CLEAR; the campaign
restored empty greedy state and released USB ownership.

The [complete context record](evidence/seeded-sampling/full-context.json)
retains wire bytes, timings, reference bindings and the original failure
provenance. A host output-pipe failure interrupted an earlier case after its
correct first reply, before its boundary/replay checks. That incomplete case
is not credited. Three fully completed original cases were independently
reaudited and retained byte for byte; the other 13 were run from CLEAR with
durable recording. All 16 completed captures received independent raw-wire
and model-reference audits. The continuation pins 38 runtime inputs; this is
separate from the 91-input native-build inventory. Each command had a
3,600-second deadline; these results do not claim baseline deadline parity.

Eight separate [one-token-prompt control trials](evidence/seeded-sampling/around-control.json)
also passed: two 128-output trials at each temperature, each with the baseline
campaign's 12 known-answer CLEAR/replay outputs and invalid-operation checks.
Their 1,024 main outputs and 96 probe outputs all matched the reference;
three final greedy outputs checked restoration. Together with the 16 context
cases, this is **24 baseline-style qualification trials, 1,564 main outputs
and 288 per-trial replay outputs**, four times the baseline's six-trial
matrix. These control trials are separate from the earlier performance
benchmark; its measured rates and original captures remain unchanged.

The [additional seed campaign](evidence/seeded-sampling/seed-domain.json)
passed 12 cases: a second fixed seed with one-token and 128-token prompts
at every positive temperature, plus zero and all-ones seeds with 32-output
streams at every positive temperature. All **960 main outputs**, **96 replay
outputs** and three final greedy outputs matched the integer reference.
Zero uses the documented nonzero PRNG-state mapping; these deterministic
streams do not establish independent physical entropy.

The [early-CLEAR campaign](evidence/seeded-sampling/recovery.json) passed
three cases: clearing halfway through a 128-token upload, and sending CLEAR
shortly after STEP for 128- and 2,048-token prompts. The observed delays in
the latter cases were about 60 ms; neither returned a token before CLEAR.
Every case then reproduced and replayed an eight-token reference stream,
for **48 exact recovery outputs**, followed by three final greedy outputs.
These are physical host/wire observations, not observations of internal
read ownership or the exact cancellation edge. The scoped RTL proofs and
simulations establish their separately stated digital drain obligations.

### Clean recipient and ordinary-browser rehearsal

A clean **1,316-file** manifest-only package passed strict verification before
local runtime files were created. A fresh physical read of all **16 MiB**
matched the expected plaintext model and every erased-region byte, with CRC32
`28e34a2f`. The same seeded image was then loaded into SRAM from that package,
followed by the startup wait and a fresh **45-command, 19-token** registration.
No flash write, erase or replacement model was used.

The ordinary listening app at `http://127.0.0.1:8507` then passed **10 Chrome
cases**, with **104 generated tokens and 144 wire commands**. They cover all
four temperatures, repeated/chosen seeds, two distinct automatic seeds,
greedy after sampling, Stop after visible output, greedy restart and Disconnect.
All outputs matched the exact model reference; the six automatic-seed outputs
were independently regenerated with the scalar reference. In the Stop case,
75 outputs were visible while generating; it finished with 77 of the requested
128, acknowledged CLEAR and released USB. This does not claim instantaneous
stopping or observation of an internal command edge.

[The browser record](evidence/seeded-sampling/browser.json) binds the displayed
settings and text, actual downloads, raw UART frames, source identities,
fresh readback/reload/registration and live server health. Disconnect left no
UART owner. These are operator/Cua browser observations checked against the
actual records, not independent attestation of browser actions or silicon.
Browser download waits are outside FPGA command timings; this rehearsal does
not replace the separate 128-output performance benchmark. A long interrupted
wait for the first completed run's download was preserved separately; its
already completed generation was not repeated or credited as a new trial.
The host and board were the existing tested setup; another owner's installation
and other platforms remain untested.

### Initial short trial and application checks

The initial 2026-10-23 UTC physical trial returned **107 tokens**, with **46 exact
reference checks**: three startup-greedy outputs before any settings, 40
greedy/seeded/replay checks, and the first three outputs of a 64-output
temperature-1 run. The other 61 performance tokens were recorded with valid
token encoding; they were not all compared to a numerical reference.

The short checks covered all four temperatures, CLEAR replay without
resending settings, changed-seed fixtures, greedy seed independence,
bad-CRC/invalid/nonempty settings rejection, settings sent behind STEP, and
STEP/CLEAR followed by replay. The wire trace observed cancellation of that
STEP and successful replay. It cannot show the exact internal busy edge or
whether private reads were outstanding at CLEAR. No physical fault injection
or full-context trial was performed in that initial campaign.

Separate application checks passed the extended **45-command, 19-token**
registration test, then drove the rendered Streamlit controls through the
real FPGA backend with **19 expected UI outputs checked**. This covered all
temperatures, fixed-seed replay, greedy after sampling, a changed seed, two
distinct automatic seeds, early Stop/CLEAR, subsequent greedy generation and
Disconnect releasing USB. The initial Stop case occurred before prompt upload.
A supplemental 64-token request at temperature 1 requested Stop after one
output was observed during generation. It ended with 13 outputs, acknowledged
CLEAR and a released connection, then successfully resumed greedy generation.
The first three stopped outputs and three resumed outputs add **six exact
checks** separately from the original 19 UI checks. This does not observe the
internal STEP edge at the click or establish instantaneous stopping.
Streamlit AppTest drove the UI without a listening web server or browser
automation, and no mocked
UART or software model supplied the outputs. See
[the application evidence](evidence/seeded-sampling/app.json).
A clean manifest-only recipient export also passed strict inventory and the
offline app/package checks. No complete installation on a second owner's
setup is claimed. That earlier framework test is separate from the ordinary
browser rehearsal recorded above.

In that historical one-token-prompt, 64-output trial at temperature 1, the first
STEP took **85.38 ms** and the following 63 command/reply intervals totaled
**6.09747 seconds**, or **10.33 tokens/s**. These durations include host/UART
and evidence recording and exclude connection and prompt upload. The workload
was shorter than the 128-output campaigns and is no longer the advertised
generation rate. It does not establish a speedup from sampling or a matched
comparison with Qwen.

The routed image uses 58,758 CLS and 225 BSRAM, 525 CLS and 29 BSRAM above the
current baseline. Reported inference-clock setup/hold margins are
+0.092/+0.144 ns at 25 MHz. There remain 145 setup/recovery and ten
hold/removal violated endpoints in vendor DDR. A successful board run does
not establish complete timing signoff, correctness for every prompt,
physical-security qualification or a residual training-capacity bound.

See the [evidence guide](evidence/seeded-sampling/README.md),
[trial receipt](evidence/seeded-sampling/receipt.json),
[native summary](evidence/seeded-sampling/native.json), and
[formal boundaries](FORMAL-STATUS.md).

## Fixed sampling and protocol contract

The model and authenticated logits are unchanged. Temperature 0 bypasses
sampling and PRNG state and retains the original greedy tie behavior.
For positive temperatures, the circuit buffers the logits, subtracts their
maximum, obtains fixed Q30 masses from its immutable exponential table, and
selects through an integer cumulative distribution. This is a finite-precision
distribution rather than exact floating-point softmax. All sampling arithmetic
and state are private; the host cannot supply logits or probability tables.

The generator is xoroshiro128++; seed zero maps to the nonzero initial state
`(1, 0)`. APPEND, prefill, idle cycles and stalls do not advance it. A draw
commits when its selected token is accepted; CLEAR discards uncommitted work
and rewinds to the configured seed. Faults remain terminal through CLEAR.

The new image adds `SETTINGS` (opcode 03) alongside the original five-byte
APPEND/STEP/CLEAR frames. Its 20-byte request contains magic `A5`, opcode,
temperature code (0=greedy, 1=0.5, 2=1, 3=2), the 16-byte little-endian seed
and CRC8. Acceptance replies with kind `83` and the temperature code;
rejection uses `C3`; recognized malformed SETTINGS or bad CRC uses `CF`.
CRC is error detection.
Settings apply atomically only when the tape is empty and idle. They cannot
overtake an active STEP or modify in-flight inference. Send one complete
request and wait for its response; there is no exactly-once retransmission
guarantee. A partial SETTINGS frame times out after 40 UART bit-times without
another byte (about 347 microseconds at 115200 baud). It cannot partially
apply settings; after timeout and reply drain, a later valid legacy frame can
be parsed as a new request. Do not continue an abandoned frame or interleave
requests. The CLI implements this framing and stops on faults.

The source is in [variants/seeded-sampling/hardware](variants/seeded-sampling/hardware/).
The pinned 91-input inventory is
[hardware-inputs-seeded-sampling.json](host-app/hardware-inputs-seeded-sampling.json);
four vendor files must be acquired separately under
[VENDOR-SETUP.md](VENDOR-SETUP.md). The original three-command receipts do not
cover the changed controller. Separate [seeded formal proofs and public replay](formal/seeded-sampling/README.md)
now check SETTINGS, sampler/seed ownership and CLEAR/replay with the stated
private-service boundaries. The connected Z3 proof passes 196 assertions;
cvc5 passes its base and 194 conclusions, with two CRC conclusions unresolved.
The public replay verifies 87 distributed source files and image bytes; it does
not verify or prove the four omitted vendor files, whole-machine refinement,
numerical CDF equivalence or mapped/timing correctness.

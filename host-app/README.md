# Local FPGA story app

This app tokenizes a prompt, sends `APPEND`, `STEP` and `CLEAR` to the FPGA,
and displays text and timings. For the optional seeded-sampling image, it
also sets a bounded temperature and seed at the start of each generation.
Inference runs on the board. There is no
software-model fallback, weight upload, memory/arithmetic command, programming
button or automatic retry. The restriction is in the frozen FPGA design,
not in this editable application.

The app uses separate local profiles for the three original greedy images and
the optimized seeded image. The original 0e6 Streamlit AppTest/ten-case browser
receipts remain historical. The current clean recipient completed twelve
ordinary Chrome cases with all 100 outputs matching the reference, including
independent integer-oracle checks of both automatic-seed runs.
The current unchanged host suite passed 70 offline tests, including rendering
and synthetic AppTest fixtures. AppTest does not count as an opened-browser
rehearsal or a hardware test.
See the [current qualification record](../CURRENT-QUALIFICATION.md).
The encrypted-memory image retains K/V integrity/replay protection and encrypts
both weights and K/V with public demonstration keys; use its distinct flash
payload. The seeded image uses plaintext model flash and has no K/V
cryptographic integrity or encryption.

The current browser contract retains the original ten cases and adds an exact
2,048-token greedy prompt and a 2,047-token temperature 1/seed A run stopped while
its first STEP is pending. In the completed long Stop, exactly that first
reply was drained, CLEAR was acknowledged and UART ownership was automatically
released, with no second STEP. The short Stop returned 71 outputs and a later
greedy run resumed successfully.
Fresh whole-flash model readback passed with a separate exact payload/source
join to the registered package. After the reader replaced SRAM, the exact
recipient inference image was reloaded, settled for at least 120 seconds and
passed 45-command/19-token registration. Matching replies do not independently
attest the loaded configuration.

The browser's full 2,048-token greedy case showed its first token at 388.94
seconds, including setup and prompt upload. The separate temperature-1 context
campaign measured a 352.237119291-second first hardware STEP; neither value is
the 9.942238076 cached-command tokens/s benchmark. See the
[recorded timing](../CURRENT-QUALIFICATION.md#recorded-timing).

The app keeps a healthy USB connection open between successful runs. This
avoids repeated connection setup, not FPGA computation. Each run still clears
the tape; it does not reuse another run's prompt or generated answers.

Keep the host awake during speed measurements. Host sleep can delay serial
processing and make elapsed-clock measurements misleading; a trial affected
by sleep should be repeated rather than used to claim a speedup.

Complete vendor-DDR timing and physical-security certification remain open.
All 16 current context cases passed, covering 128-, 512-, 2,047- and 2,048-token
prompts at each supported temperature. These finite cases do not establish
every possible prompt. The seeded profile supports up to
2,048 prompt tokens, 128 new tokens and 2,049 combined tokens. The original three
greedy profiles retain 128 prompt tokens, 128 new tokens and 256 combined tokens.
The supported tested host is macOS; no new platform/other-owner claim is added.

## Install

From this directory, using Python 3.12:

```sh
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -B fetch_tokenizer.py
.venv/bin/python -B -m unittest discover -v
```

The exact tokenizer is included in `assets/`; the fetch command verifies its
hash and downloads nothing when the file matches. It never fetches a software
LLM. The tests use offline fixtures and never open a physical UART. Streamlit
is pinned to 1.64.0, checked on 2026-09-16; see
[the package release](https://pypi.org/project/streamlit/1.64.0/).
Use a separate environment; do not upgrade a running demo in place.

## Program, then register your board

First follow [the programming and recovery guide](../PROGRAMMING.md).
It preserves the factory configuration, installs the model in flash and loads
the inference circuit into SRAM. **Ordinary use needs no compiler:** the
configuration and its maintainer build receipt are included under `prebuilt/`.
For optional source rebuilding, see [VENDOR-SETUP.md](../VENDOR-SETUP.md).

Keep the programmed board powered. For the optimized seeded image, wait at least 120 seconds after actual SRAM load completes. Follow each original greedy image's startup instructions for that image. Stop all other serial/JTAG tools and apps.
Identify your board's actual serial path; do not copy another person's suffix.
Then run, replacing the example device path:

```sh
.venv/bin/python -B qualify_board.py \
  --build-receipt ../prebuilt/inference/BUILD.json \
  --device /dev/cu.usbserial-YOUR_BOARD \
  --confirm-loaded-source-build --acknowledge-unqualified-timing
```

That command registers the **baseline without K/V checks**. If you loaded
the K/V-protected image instead, use
`--build-receipt ../prebuilt/kv-protected/BUILD.json`. The receipt selects a
separately pinned source inventory; a baseline/protected mismatch is rejected.
The app displays the locally selected variant, not an independently measured
identity of the circuit. See [the comparison](../KV-PROTECTION.md).

For the **seeded-sampling** image, use this matching receipt instead:

```sh
.venv/bin/python -B qualify_board.py \
  --build-receipt ../prebuilt/seeded-sampling/BUILD.json \
  --device /dev/cu.usbserial-YOUR_BOARD \
  --confirm-loaded-source-build --acknowledge-unqualified-timing
```

This selects an extended greedy/seeded/replay known-answer check before the
profile is registered. A failed or incomplete check cannot enable generation.
Add `--replace-profile` when replacing an existing profile. The command
deliberately clears the tape; it does not load an image or change flash.

The flag `--confirm-loaded-source-build` also applies to this
included source-built image: you are confirming the exact file you just loaded,
not claiming that you personally ran the compiler. A fresh local build can use
its own `BUILD.json` path instead.

For the three greedy images this is a seven-command hardware test, including
CLEAR at both ends. It
discards the current conversation, appends token 378 (`around`) and requires
exactly `[200, 15, 103, 157]`. Success creates a local board profile and raw
serial record. The timing acknowledgement permits exploratory use; it does
not assert that timing passed. No reset, reflash or retry follows a fault.

If a profile exists, `--replace-profile` preserves and invalidates it before
retesting; a failed retest cannot leave the old profile apparently valid.
Profiles and logs are local deployment guards, not security roots.
Requalify after power cycling, reprogramming, replacing the board or an
unexplained fault. Never edit a profile to bypass a failed check.

To switch between baseline, K/V-protected and seeded-sampling images, stop the app,
explicitly load the other image into SRAM using the programming guide,
and rerun this check with its matching receipt and `--replace-profile`.
These three use the same plaintext model in flash.

Switching to or from `encrypted-memory` also requires the **matching flash
contents**, not just an SRAM reload. Follow the
[encrypted-memory installation/restoration instructions](../ENCRYPTED-MEMORY.md#install-or-restore),
then requalify with the matching receipt and `--replace-profile`.
The tokenizer is unchanged across all four versions. The browser cannot
switch variants or program the board.

## Start and use

```sh
.venv/bin/python -B start_local_server.py
```

Open **http://127.0.0.1:8507**. The server listens only on loopback and refuses
an occupied port. Hot reload is disabled. The local launch record identifies
the server PID. Before programming or requalifying, follow
[Stop the server](#stop-the-server) below.

Generate clears the tape, uploads your prompt and streams tokens. Stop lets
the in-flight command finish, then clears the tape; successful completion
also clears it. A successful run retains its exclusive connection to avoid
repeating the one-second startup listen. Before reuse, the app rechecks the
profile and device and rejects pending or unexpected bytes without flushing
them. Errors close the session and prevent automatic reuse or retry. Stop
releases the connection after the in-flight command and final CLEAR finish.
Use **Disconnect USB** while idle to release it for another program, or stop
the server before programming/requalifying the board. A newly opened
connection always performs the original startup check.
One cached controller owns the board across browser tabs.
A second tab cannot view another tab's prompt/output. Opening the page alone
does not begin inference.

With a **seeded-sampling** profile, the page also shows temperature and seed
controls. Temperature defaults to **0**, the original greedy rule. Positive
temperatures are **0.5, 1 and 2**. Choose an automatic seed for a fresh
continuation or supply a 128-bit seed to reproduce one. The last-run display
and downloadable record retain the actual seed and temperature used.
Each Generate clears the tape, applies the chosen settings, appends your
prompt and streams tokens; completion and Stop finish with CLEAR. Repeating
the same prompt, temperature and seed replays the same continuation. These
controls appear only for a seeded profile; they do not reprogram another image.

Streaming tokens/s excludes the first token. Time to first token includes
connection checking, prompt upload and prompt evaluation. Per-STEP times and
a downloadable run record are available. Logs include prompts and raw replies;
keep them private. No prompts are sent to an online model.

The configuration lives in **volatile SRAM**. After power loss, reload the
inference bitstream and requalify before starting the app. The model remains
in flash; reinstalling it each time is unnecessary. The app itself cannot
reload the FPGA or restore a factory demo.

## Stop the server

The launcher starts a detached server: closing the terminal or browser tab
does **not** stop it. Before switching configurations or requalifying:

1. If generation is active, click **Stop** and wait for the in-flight command
   and CLEAR to finish. While idle, click **Disconnect USB** if a connection
   is still retained. Do not reprogram during an unfinished command.
2. Find the `pid` and `argv` in the launch record printed when you started
   this server, also saved as `runtime/server-<launch-id>.json`. Use that
   launch's record, not a guessed PID or an unrelated Python process.
3. Replace `YOUR_SERVER_PID` below with the positive PID from that record:

   ```sh
   ps -p YOUR_SERVER_PID -o pid=,command=
   ```

   Confirm that the process is running this checkout's `streamlit_app.py`
   on port 8507 and matches the recorded command. If it is absent or different,
   do not send it a signal; a stopped server's PID can be reused.
4. Only after that check, request a graceful shutdown of the same process:

   ```sh
   kill -TERM YOUR_SERVER_PID
   ```

5. Check that the app port is no longer listening:

   ```sh
   lsof -nP -iTCP:8507 -sTCP:LISTEN
   ```

   No output means no listener was found. If a listener remains, investigate
   it before programming or requalifying; do not kill every Python process.

Stopping the server does not reset the FPGA, change flash or reload its
configuration. Keep the board powered if you want to keep the current SRAM
configuration.

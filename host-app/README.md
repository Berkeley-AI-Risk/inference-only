# Local FPGA story app

This app tokenizes a prompt, sends only `APPEND`, `STEP` and `CLEAR` to the
FPGA, and displays text and timings. Inference runs on the board. There is no
software-model fallback, weight upload, memory/arithmetic command, programming
button or automatic retry. The restriction is in the frozen FPGA design,
not in this editable application.

The app supports all three supplied configurations through separate local
profiles. For `encrypted-memory`, use `prebuilt/encrypted-memory/BUILD.json`
and install its distinct
[ciphertext flash payload](../ENCRYPTED-MEMORY.md#install-or-restore) first.

The [validation record](../VALIDATION.md#host-and-installation-checks)
distinguishes physical hardware tests, backend qualification and offline UI
tests. It does not claim a complete human browser-click rehearsal of all
three supplied images on another owner's setup. Neither build receipts nor
matching outputs independently attest the configuration.

The app keeps a healthy USB connection open between successful runs. This
avoids repeated connection setup, not FPGA computation. Each run still clears
the tape; it does not reuse another run's prompt or generated answers.

Keep the host awake during speed measurements. Host sleep can delay serial
processing and make elapsed-clock measurements misleading; a trial affected
by sleep should be repeated rather than used to claim a speedup.

All three hardware variants still have unresolved vendor-DDR timing paths.
All three supplied images have passed full-context board tests. None of those tests
is complete timing signoff. This app conservatively allows at most 128 prompt
tokens, 128 new tokens and 256 total. The tested platform is macOS; other
platforms are not yet validated.

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

Keep the programmed board powered, wait at least 60 seconds after the SRAM
load for startup/model checks, and stop all other serial/JTAG tools and apps.
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

The flag `--confirm-loaded-source-build` also applies to this
included source-built image: you are confirming the exact file you just loaded,
not claiming that you personally ran the compiler. A fresh local build can use
its own `BUILD.json` path instead.

This is a seven-command hardware test, including CLEAR at both ends. It
discards the current conversation, appends token 378 (`around`) and requires
exactly `[200, 15, 103, 157]`. Success creates a local board profile and raw
serial record. The timing acknowledgement permits exploratory use; it does
not assert that timing passed. No reset, reflash or retry follows a fault.

If a profile exists, `--replace-profile` preserves and invalidates it before
retesting; a failed retest cannot leave the old profile apparently valid.
Profiles and logs are local deployment guards, not security roots.
Requalify after power cycling, reprogramming, replacing the board or an
unexplained fault. Never edit a profile to bypass a failed check.

To switch between the baseline and K/V-protected versions, stop the app,
explicitly load the other image into SRAM using the programming guide,
and rerun this check with its matching receipt and `--replace-profile`.
Those two versions use the same plaintext model in flash.

Switching to or from `encrypted-memory` also requires the **matching flash
contents**, not just an SRAM reload. Follow the
[encrypted-memory installation/restoration instructions](../ENCRYPTED-MEMORY.md#install-or-restore),
then requalify with the matching receipt and `--replace-profile`.
The tokenizer is unchanged across all three versions. The browser cannot
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

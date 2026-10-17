# Qwen browser app

[Qwen guide](README.md) · [FPGA installation](INSTALL.md)

The browser app uses the same simple layout as the SimpleStories app: a prompt,
an output-length control, streaming text, tokens per second and time to first
token. Inference runs on the AWS F2 FPGA, not on the computer running the app.
The computer only tokenizes text, sends token commands and displays the replies.

Install the FPGA image and model and pass the known-answer test in
[INSTALL.md](INSTALL.md) first. The app does not rent an instance, load an image,
upload weights or change clocks. Give it exclusive use of the configured FPGA
slot; do not run another client against that slot during a request.

## Run locally, including on a Mac

From the repository root:

```sh
cd demos/qwen3-1.7b/host
python3.12 -m venv .venv-browser
.venv-browser/bin/python -m pip install -r requirements-browser.txt
```

Create a private `connection.json` in this directory. For an app running on
your computer and a client installed on an F2 instance, use this structure,
replacing the client path and SSH alias with your own:

```json
{
  "host_client": "/opt/qwen/host/qwen_host",
  "slot": 0,
  "sudo": true,
  "ssh_argv": [
    "ssh", "-T", "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15",
    "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
    "qwen-fpga"
  ]
}
```

Configure `qwen-fpga` in your normal SSH configuration and verify its host key
through a trusted channel. Test that login separately before starting the app.
Keep your SSH private key in your normal SSH/key-agent setup, not in this file
or the repository. The remote account must be able to run the installed client
with `sudo -n`; the app cannot answer a password or passphrase prompt. Connection
settings are operator-controlled, not browser inputs. `connection.json` is
gitignored because its hostnames and paths are private deployment details.

For an app running on the F2 host itself, set `ssh_argv` to `[]`. The client
path must still be absolute. In either case:

```sh
chmod 600 connection.json
export QWEN_CONNECTION="$PWD/connection.json"
.venv-browser/bin/python -m streamlit run streamlit_app.py
```

Open **http://127.0.0.1:8508**. The app binds to loopback only. If running it on
F2, use an SSH port forward to reach that loopback port; do not expose the
Streamlit port to the Internet. The browser is an operator demo, not an
authenticated multi-user service. Start only one app server for a given slot.

## Using the demo

Enter a prompt, set **Max new tokens** to 1–128 and press **Generate on FPGA**.
The default uses the pinned model's single-user, non-thinking chat format.
Select **Raw text completion** to continue an unfinished passage instead.
Each request starts a fresh tape; earlier responses are not conversation history.
The interactive prompt limit is 512 tokens, including chat-formatting tokens.

Generation stops at the first end-of-response marker or the selected limit,
whichever comes first. The host client waits for the terminating STEP to
finish, then issues no further STEPs. Special formatting tokens are omitted
from displayed text; token counts and timing include the end marker itself.
The benchmark command `generate` remains fixed-length; the browser uses
`generate-until-end`. There is no mid-run Stop button.
Let generation finish before closing the app or using another client. If a
request fails, the app disables further generation instead of silently retrying,
resetting the circuit or switching to a software model. Inspect the operator
terminal and FPGA status before restarting the app.

**Streaming tokens/s** measures intervals after the first token, using the
remote client's clock. **Time to first token** includes prompt processing and
the first STEP, but excludes CLEAR, model upload, tokenization and SSH/browser
delivery. The details panel also shows app elapsed time to receipt of the first
token, including the connection/status checks. These numbers answer different
questions; a long prompt can have a long initial wait despite steady streaming.

Downloaded run records include the prompt, response, token IDs and timings.
They omit the connection configuration. Review their text before sharing them.
Output matching does not independently attest the loaded FPGA configuration.

## Checks

Offline controller and presentation tests do not contact an FPGA:

```sh
.venv-browser/bin/python -B -m unittest discover -s . -p 'test_*.py' -v
```

To exercise the actual controller on an already installed FPGA, when nobody
else is using it:

```sh
.venv-browser/bin/python -B check_hardware.py \
  --connection connection.json --exercise-fpga --output hardware-check.json
```

This sends five generation requests, checks 390 returned token IDs against
the packaged reference records, and ends with CLEAR if every case passes.
It records prompt latency and cached decode separately. It does not regenerate
the numerical oracle, configure the FPGA, upload the model, or test browser
rendering. It refuses to overwrite an existing result file.

# Run Qwen3-1.7B on AWS F2

[Qwen guide](README.md) · [Browser app](BROWSER.md) · [Hardware/build details](HARDWARE.md)

The FPGA runs the model. The Linux host loads the fixed weights and sends token
commands; your Mac can provide the browser interface over SSH. This is an AWS
F2 design, not a Tang Mega image. AWS access, instance availability, quotas and
charges are the operator's responsibility. None of the supplied Python tools
starts an instance or extends a rental automatically.

## What you need

- One FPGA slot on an AWS F2 instance in a supported region. The measured
  deployment used `f2.6xlarge` in `us-east-1`, with Ubuntu 24.04 on x86-64.
- The AWS FPGA SDK and its matching Linux permissions. Start with the
  [AWS runtime setup instructions](https://awsdocs-fpga-f2.readthedocs-hosted.com/latest/sdk/README.html).
- Python 3.11 or later for preparation; the recorded preparation used 3.12.
  The C++ client needs a C++17 compiler and OpenSSL development headers.
- About 10 GB of free disk for the upstream model, reconstructed image and
  preparation files, plus space for Python dependencies. Preparing the model
  can be done on a Mac or another computer before renting FPGA time.

Clone this repository and work from `demos/qwen3-1.7b`. Use the exact source
revision recorded in `SOURCE-INPUTS.json` when setting up `aws-fpga`:

```sh
git clone https://github.com/aws/aws-fpga.git /path/to/aws-fpga
git -C /path/to/aws-fpga checkout b603a81f65666e0cf7a67ee5cf18b148eb6b08c3
```

This checkout command is for the newly cloned upstream dependency, not an
existing working tree with local changes. Runtime use needs the SDK; rebuilding
the FPGA image additionally needs the HDK and Vivado described in `HARDWARE.md`.

## Prepare the fixed model

From `demos/qwen3-1.7b`:

```sh
python3.12 -m venv .venv-model
.venv-model/bin/python -m pip install -r model/requirements.txt
.venv-model/bin/python tools/prepare_model.py \
  --source local/upstream --download --output local/model-memory.bin --threads 8
```

The explicit `--download` fetches the pinned public Qwen checkpoint and tokenizer,
not the current contents of a moving model branch. Omit it if `--source` already
contains the complete pinned snapshot. The preparer verifies the upstream files,
checks that the output head and embeddings agree, uses the specified quantization
and layout, and refuses to accept an output with any other hash.

The result must be **2,354,380,800 bytes**, with SHA-256:

```text
90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1
```

Keep the image outside Git. If prepared elsewhere, transfer it to your F2 host
using your usual authenticated SSH/SCP connection. There is no encryption key
to provision. The hash is a public model-identity commitment, not a secret.

## Install the FPGA image

The tested prebuilt image is **`agfi-026c1333e063cf04f`**, with regional identifier
`afi-0dcab1e1ac1a1dade` in `us-east-1` and shell `0x10212415`.
Its public load permission is recorded in [deployment.json](deployment.json).
No hardware source rebuild is needed to run this image.

On your F2 host, with the AWS SDK installed and sourced, check that the image
is still available using your own AWS credentials:

```sh
aws ec2 describe-fpga-images --region us-east-1 \
  --fpga-image-ids afi-0dcab1e1ac1a1dade \
  --query 'FpgaImages[0].{State:State.Code,Public:Public,GlobalId:FpgaImageGlobalId,Shell:ShellVersion}'
```

Expect `available`, `true`, the global ID above and shell `0x10212415`.
Loading an image resets the FPGA slot and discards its current state. Stop
applications using slot zero and obtain exclusive use before continuing:

```sh
sudo fpga-clear-local-image -S 0
sudo fpga-load-local-image -S 0 -I agfi-026c1333e063cf04f
sudo fpga-describe-local-image -S 0
```

The last command must report the expected global ID, `loaded`, `ok` and the
matching shell version. Stop on an error. Public load permission was verified
through AWS; installation was rehearsed in the image owner's account, not a
second account. AWS availability and permissions can change.

## Build the host client and load the model

On the F2 Linux host, install a C++ compiler, `make` and OpenSSL development
headers if needed, then source the separately installed SDK:

```sh
source /path/to/aws-fpga/sdk_setup.sh
cd /path/to/inference-only/demos/qwen3-1.7b
make -C host
sudo host/qwen_host --slot 0 status
sudo host/qwen_host --slot 0 load /path/to/model-memory.bin
sudo host/qwen_host --slot 0 self-test
sudo host/qwen_host --slot 0 clear
```

The client verifies the image hash before starting an upload; hardware checks
the received fixed image independently. Upload is a startup operation, not
part of the reported token-generation latency. The client reports upload
progress and waits for model readiness. A fresh FPGA load is required before
another complete startup upload; `CLEAR` clears the token tape, not the weights.

The self-test starts with CLEAR and must return tokens **25, 358, 1184**
after appending token **9707**; the next command clears the completed test tape.
Stop on an error; do not substitute a software
model or ignore a failed hardware status. The model remains available for
later inference requests until reconfiguration, reset or power loss.

## Generate text or use the browser

Install the small tokenizer dependency and run the text client:

```sh
python3.12 -m venv .venv-text
.venv-text/bin/python -m pip install -r host/requirements-text.txt
sudo .venv-text/bin/python host/qwen_text.py \
  --host-client "$PWD/host/qwen_host" --slot 0 \
  --prompt 'Explain what an FPGA is in two sentences.' --count 128 --stop-at-end
```

`--count` is a maximum when `--stop-at-end` is supplied. Without that option,
the CLI produces a fixed count, as used for benchmarks. Use `--raw` for plain
text completion rather than the pinned non-thinking chat format.

For streaming text and speed displays, follow [BROWSER.md](BROWSER.md).
The browser can run locally on a Mac, with only the C++ client on the F2 host.
Do not run the CLI and browser against the same slot concurrently.

## Verification and shutdown

- [Numerical reference](reference/README.md): regenerate expected tokens without
  an FPGA, rather than merely comparing two saved files.
- `host/check_hardware.py`: compare fresh hardware replies with the packaged
  known-answer cases; see [the browser guide](BROWSER.md#checks).
- [Recorded measurements](README.md#measured-generation-speed): separate prompt
  latency from sustained cached generation and startup/model-upload time.

After use, stop your instance through your AWS account and check its state.
Stopping an app or closing an SSH session does not stop EC2 billing. Persistent
storage and other retained resources can continue to incur charges separately.

# Run the measured Qwen3-8B design

The measured FPGA image is publicly loadable. Its identity and observed
permission are recorded in [deployment.json](deployment.json), and a
[package installation rehearsal](evidence/installation.json) passed on an F2
host with the SDK already installed. The rehearsal used the image owner's
account; public permission was checked through AWS, without a second-account
installation test.

This design requires AWS F2, not Tang Mega. The measured deployment used one
slot of an `f2.6xlarge` in `us-east-1`, Ubuntu 24.04, and the AWS FPGA SDK from
revision `b603a81f65666e0cf7a67ee5cf18b148eb6b08c3`. Runtime installation does not
require rebuilding the FPGA source. AWS quotas, availability and charges are
the operator's responsibility.

## Check image access before renting

With your own AWS credentials, inspect the tested image:

```sh
aws ec2 describe-fpga-images --region us-east-1 \
  --fpga-image-ids afi-0e6c7942e44ab3234 \
  --query 'FpgaImages[0].{State:State.Code,Public:Public,GlobalId:FpgaImageGlobalId,Shell:ShellVersion}'
```

The selected global ID is `agfi-0b8b13da723c187a7`, shell `0x10212415`.
Expect state `available` and `Public: true`. Check this before renting;
availability and permissions can change.

## Prepare the model and host client

Follow [the model preparation instructions](README.md#prepare-the-fixed-model).
The reconstructed `model.bin` must match the fixed image hash there. Transfer
it to the F2 host using your usual authenticated connection. Do not upload
credentials or private keys to this repository.

On the Linux F2 host, install the AWS SDK, a C++17 compiler, `make`, and
OpenSSL development headers, then source the SDK and build the exact client:

```sh
cd /path/to/aws-fpga
source sdk_setup.sh
cd /path/to/inference-only/demos/qwen3-8b
python3.12 tools/prepare_hardware.py
make -C host
```

Run the SDK setup from its own checkout, not from this demo directory. If that
SDK is already installed on the host, leave the installation unchanged and
build the client with `make -C host SDK_DIR=/path/to/aws-fpga/sdk` instead.

## Load and test

Obtain exclusive use of slot zero and stop applications using it. Loading a
configuration discards the slot's existing inference state:

```sh
sudo fpga-clear-local-image -S 0
sudo fpga-load-local-image -S 0 -I agfi-0b8b13da723c187a7
sudo fpga-describe-local-image -S 0
```

Check the global ID above, `loaded`, `ok`, and the matching shell. Stop on
any error; do not proceed with another image. Then run:

```sh
sudo host/qwen_host --slot 0 status
sudo host/qwen_host --slot 0 load /path/to/model.bin
sudo host/qwen_host --slot 0 self-test
sudo host/qwen_host --slot 0 clear
sudo host/qwen_host --slot 0 generate 9707 16
```

`self-test` appends token 9707 and must return **11, 358, 2776**. The example
generation command returns raw token IDs and timings. This candidate does
not yet include an 8B browser interface. The C++ client performs no inference;
the FPGA produces the output IDs.

The full model upload is a separate startup cost. A fresh configuration is
required for another complete upload. `CLEAR` resets the conversation, not
the fixed model. Do not use multiple clients on the same slot concurrently.

When finished, stop the EC2 instance and check its state. Closing an app or
SSH session does not stop billing; retained storage can incur charges too.

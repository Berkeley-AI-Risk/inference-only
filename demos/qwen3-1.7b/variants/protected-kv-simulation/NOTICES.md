# Protected K/V simulation source notices

Project-owned K/V RTL, the separate machine-selection top and test controls use
the repository's [Apache 2.0 license](../../../../LICENSE). This is an adaptation
of the project's existing Qwen K/V implementation, not an upstream Qwen hardware
implementation. Original source comments and derivation notices are retained.

The variant reuses, rather than republishes, the public 1.7B arithmetic, SHA-256
pipeline and transport sources. Berkeley HardFloat retains its existing
[BSD-style notice](../../hardware/licenses/HardFloat-COPYING.txt). The independent
scalar SHA test oracle is project test code, separate from the synthesizable
pipeline, and checks the standard empty-string and `abc` known-answer vectors.

No AWS adapter, SDK, vendor IP, model weights, credentials or compiled FPGA image
is added here. Existing AWS-specific files keep their separate terms; this
variant grants no license to vendor IP. See the parent
[dependency notices](../../NOTICES.md) and repository
[license scope](../../../../LICENSE-SCOPE.md).

The short test generates finite synthetic BF16 values and uses the already
published softmax table. Reproducing the optional recorded full-model experiment
requires separately obtained model assets subject to their existing Qwen terms.
Source identities and unchanged dependencies are listed in `SOURCE-INPUTS.json`.

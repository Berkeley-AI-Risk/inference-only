# Qwen demonstration: dependencies and license scope

Project-owned HDL, runtime, verification code and documentation use the
repository's [Apache-2.0 license](../../LICENSE). The owner-supplied demonstration
video is included under that grant. That grant does not replace the terms below.

- **Qwen3-1.7B:** the pinned checkpoint, tokenizer and model-derived data come
  from `Qwen/Qwen3-1.7B`, revision `70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`,
  under [its supplied Apache-2.0 license](licenses/QWEN-LICENSE.txt).
  The memory image is a quantized and serialized derivative, not an independently
  trained model. The Python reference retains its Qwen/Transformers attribution.
- **Berkeley HardFloat:** John R. Hauser's
  [Verilog arithmetic library](https://www.jhauser.us/arithmetic/HardFloat.html).
  The included floating-point modules and their include
  files retain their upstream notices and [BSD-style license](hardware/licenses/HardFloat-COPYING.txt).
  They are third-party arithmetic implementations, not original project work.
- **AWS FPGA HDK:** dependency revision
  `b603a81f65666e0cf7a67ee5cf18b148eb6b08c3`. The top-level upstream
  [Apache-2.0 notice](hardware/licenses/AWS-LICENSE.txt) does **not** override
  individual files marked with the [Amazon Software License](licenses/Amazon-Software-License.txt).
  In this package those include `hardware/design/cl_mem_hbm_wrapper.sv`, the
  adapted `aws_build_dcp_from_cl.py`, `build_all.tcl`, `build_level_1_cl.tcl`,
  and the derived placement scripts. Their retained notices govern those files.
  ASL-covered material and its derivatives are for use with Amazon services
  or platforms; we do not relicense them for arbitrary FPGA boards or ASICs.
- **AMD and AWS platform tools/IP:** Vivado, separately installed IP, the AWS
  static shell and SDK dependencies remain subject to their own terms. They
  are not included as a vendor-tool installation. The compiled FPGA design is
  specific to AWS F2; redistribution of project source is not a grant to extract
  or reuse third-party platform IP elsewhere.
- **Python/C++ dependencies:** PyTorch, NumPy, safetensors, tokenizers,
  huggingface-hub, Streamlit, OpenSSL and AWS SDK libraries are installed
  separately under their own licenses.

The original notices in frozen inputs are preserved byte-for-byte. Our AWS build
adaptations select the fixed Qwen sources and clocks, resolve bounded CDC
constraints, check reset and memory mappings, and select the documented
placement/routing flow. Those scripts are not unmodified AWS examples. The
project's architecture and authentication ideas are distinct from these
AWS-specific integration files.

The [Amazon Software License](https://aws.amazon.com/asl/) permits redistribution
subject to its license-copy, notice and Amazon-platform-use requirements.
This is the project's distribution assessment, not a warranty of production
signoff or a license to separately redistribute a vendor installation.

# Qwen3-8B dependencies

Project-owned RTL, host and verification code, and documentation use the
repository's Apache-2.0 license. Third-party components retain their own terms.

- The checkpoint, tokenizer and model-derived data come from `Qwen/Qwen3-8B`,
  revision `b968826d9c46dd6066d109eabc6255188de91218`, under the supplied
  [Apache-2.0 license](licenses/QWEN-LICENSE.txt). The exported memory image is
  a quantized and serialized derivative of that checkpoint.
- Included Berkeley HardFloat modules retain John R. Hauser's copyright
  notices and [BSD-style license](hardware/licenses/HardFloat-COPYING.txt).
- AWS integration files retain their upstream notices. The HDK's
  [top-level license](hardware/licenses/AWS-LICENSE.txt) does not override files
  marked with the [Amazon Software License](licenses/Amazon-Software-License.txt),
  including the HBM wrapper and derived build/placement scripts. Those files
  are not relicensed for arbitrary FPGA boards or ASICs.
- Vivado, the AWS static shell, separately installed vendor IP and the AWS SDK
  retain their own terms. This package is not a vendor-tool installation or
  permission to extract third-party platform IP for another use.
- Python/C++ dependencies, including PyTorch, NumPy, safetensors,
  huggingface-hub, OpenSSL and the AWS runtime SDK, are installed separately
  under their respective licenses.

The software reference reuses arithmetic helpers from the 1.7B demonstration.
Their model-specific classes are not the 8B execution path; the 8B schedule is
in `reference/dense_qwen_reference.py`. The preserved helper notices credit
the Qwen/Transformers algorithms. Changing model geometry here is an offline
engineering operation, not a runtime command accepted by the FPGA.

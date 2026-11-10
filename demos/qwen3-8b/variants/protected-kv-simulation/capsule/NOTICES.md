# Component dependencies and licenses

Project-owned RTL, test fixtures, independent scalar oracle, Python tools and
documentation are copyright 2026 Wes Holliday and use the repository's
[Apache License 2.0](licenses/Project-Apache-2.0.txt).

Berkeley HardFloat files retain John R. Hauser's source notices and
[BSD-style license](licenses/HardFloat-COPYING.txt).

AWS-derived platform files retain their source notices and
[AWS repository license](licenses/AWS-LICENSE.txt). Files marked with the
[Amazon Software License](licenses/Amazon-Software-License.txt), including the
HBM wrapper, retain those separate terms; the repository-wide project license
does not relicense them for arbitrary FPGA boards or ASICs. Platform files in
the original compiled-input census are preserved even when not elaborated by
this same-clock component test. This package contains neither proprietary
vendor IP nor the AWS static shell.

The softmax numerical table and model identity derive from the fixed Qwen
implementation, whose upstream model is distributed under the supplied
[Qwen Apache-2.0 license](licenses/QWEN-LICENSE.txt). The K/V operand fixtures
are deterministic test patterns, not model weights. Verilator, Python, make
and the C++ compiler are installed separately under their own licenses.

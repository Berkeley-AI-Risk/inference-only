# Historical tool data and replay runtime

The project-owned material follows the accompanying Apache-2.0 `LICENSE`,
`NOTICE` and `LICENSE-SCOPE.md`. That grant does not relicense third-party tools.

The separately provisioned file
`z-tools/z3-4.14.1-macos-recorded` is a historical **third-party Z3 executable**,
SHA-256 `ea69d1d234e0060fd480bf9b21a51f62244ed642ed2469d4373306e6e8ab6102`,
15,715,120 bytes. It was installed from the Z3 4.14.1 Homebrew distribution and
used by the original recorded native runs. The unmodified installed Z3 MIT
license is reproduced as `z-tools/LICENSE-Z3.txt`. Z3's upstream is
<https://github.com/Z3Prover/z3/tree/z3-4.14.1>.

This file is distributed in a separate historical-tool-data archive. It is not
project-owned code, a Linux solver installation, or a freshly executed solver.
The portable checker only opens it read-only and checks its exact digest, as the
inherited checker requires. Its Mach-O executable permissions are removed in the
archive. A different Z3 binary is not an acceptable replacement for that hash.

CPython 3.12.12 is installed separately and is the only program this replay
executes. The qualification record pins the actual Linux runtime and container
image used. No Python runtime, vendor tool, dependency library, model image,
weights, signing state, credentials or physical-device configuration is bundled
with the project export. Historical tool paths appearing in old records are
relocated labels, not commands that the replay will execute.

The original solver receipts remain recorded evidence, not an independently
checked UNSAT proof certificate. A new Linux solve would need its own tool
identity and native receipts and is not performed by this command.

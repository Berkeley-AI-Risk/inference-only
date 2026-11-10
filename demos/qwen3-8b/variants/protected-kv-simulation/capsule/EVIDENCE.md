# Recorded Linux component replay

The final package passed fresh plain, protected and transport-boundary builds and simulations in a local network-disabled Linux aarch64 container. The independent checker ran from a different package path. All three compiler and simulator exits were zero; no host guard stopped a case. Ten offline negative controls were rejected.

Run `python3.12 -B check_recorded.py` to check the supplied source, logs and independent oracle without compiling. This checks recorded evidence; use the three explicit commands in README.md for a fresh native replay. Historical binaries and generated C++ build trees are not supplied.

Two earlier build-only packaging failures remain documented: a read-only compiler-cache location and a missing relocated C++ include path. Neither launched a simulator. Their private raw receipts remain preserved; the final revision changed no RTL, fixture value or assertion.

The 16.125 times first-position write traffic is not whole-model overhead. The deployed F2 image remains plain K/V. No full-model numerical, physical CDC/reset, vendor HBM, fit, timing or board qualification is inferred.

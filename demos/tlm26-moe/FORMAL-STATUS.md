# TLM26 MoE formal status

This demo supplies numerical comparisons, RTL simulations and finite board tests. It includes no formal proof campaign, exhaustive verification or composed inference-only theorem. Proofs for the repository's SimpleStories and Qwen designs do not transfer to this circuit.

The hardware fixes the architecture, page-digest ROM, address schedule and APPEND/STEP/CLEAR interface. Its [validation](VALIDATION.md) checks selected normal, changed-weight and cancellation cases. General command confinement, authenticated operand provenance, cancellation ownership and numerical correctness across all supported histories remain proof obligations for this implementation.

Physical timing qualification also remains open as described in the [native build results](README.md#tang-build-and-provisioning).

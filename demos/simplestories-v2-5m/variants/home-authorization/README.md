# SimpleStories S-AWIC with periodic reauthorization

This Tang Mega design requires model-specific approval from home base at startup and periodically during operation. Continued inference requires fresh approval; permission expires unless renewed. It combines signed model updates, private physical nonce generation, real LMS signature checks and fixed inference circuitry. The model architecture stays fixed; compatible new weights can be authorized without replacing that circuitry.

**Authorities can de-whitelist one set of weights and distribute a signed replacement.** The deployment host installs the replacement package using the signed-update workflow. The chip checks its update signatures and weights, then obtains fresh home permission for that exact model commitment. Withholding renewal stops inference with the old model no later than the current approval deadline. Model-update signatures and current permission to run are separate requirements.

Fresh authorization depends on a fresh challenge. The [nonce freshness boundary](HARDWARE.md#nonce-freshness) explains why the immediate-repeat check does not retain nonce history across reset or an intervening nonce. With forced repeated accepted samples, an identical request can admit an old valid grant. Physical entropy qualification remains open.

The [physical replacement campaign](VALIDATION.md#physical-model-replacement) tests this sequence with the base model and a signed synthetic replacement that changes the final normalization weights. Both produce their reference outputs; the withdrawn base model remains blocked after it is reinstalled and the FPGA is reconfigured.

The update starts a fresh session. The prototype has no automatic remote-update agent, deliberate update delay, update cap or rollback prevention independent of home policy. Deauthorization does not erase external weight memory. Compatible fine-tunes can be admitted under the same fixed architecture.

The design runs at **25 MHz** and measures **~7.6 tokens/s** on the common paired 128-output greedy benchmark, including renewal and host handover gaps. All 256 benchmark outputs match the integer reference. The selected-image board campaign checks approval, renewal with context preserved, revocation, a fresh reconfiguration nonce and old-grant replay rejection. The [validation record](VALIDATION.md) states the exact timing, entropy and proof limits.

| Document | Purpose |
| --- | --- |
| [Installation](INSTALL.md) | Run the prebuilt image and local authorization service |
| [Hardware](HARDWARE.md) | Authentication, permission gate, nonce and clock boundaries |
| [Validation](VALIDATION.md) | Board observations, numerical checks and limitations |
| [Reproduction](REPRODUCE.md) | Software, RTL, native build and evidence checks |
| [Formal status](FORMAL-STATUS.md) | Scoped proofs and remaining obligations |

Boot compares every signed page digest with the same ordered readback used for the whole image and fixed-function tables. Runtime page authentication uses that sealed table; [hardware](../signed-update/tang/HARDWARE.md#boot-to-runtime-page-binding) states the binding.

The physical target is Tang Mega **138K Basic / non-Pro, GW5AST-138C / PG484A**. The token application remains APPEND, STEP and CLEAR. This variant uses unprotected external K/V memory and greedy decoding. It is a functional FPGA demonstration; public test keys and an unqualified entropy source do not establish deployment security.

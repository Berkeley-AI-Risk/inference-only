# Prebuilt periodic-reauthorization image

`home_product.fs` is the selected, board-tested SRAM configuration for Tang Mega 138K Basic / GW5AST-138C at 25 MHz.

SHA-256: `92b334d6f160511542b1889df5f88ac1770c2fd0289e6ff707cf88d6a84f2323`.

It requires the matching signed base-model flash data and a live authorization relay. The public demonstration key supports 32 unique home grants per signing tree; signer state must persist and must not be rolled back. Use [INSTALL.md](../INSTALL.md) with a freshly discovered cable location. The FPGA file is a volatile configuration, not flash model data. [Validation](../VALIDATION.md), [source identity](../SOURCE-IDENTITY.json) and [reset review](../RESET-REVIEW.md) state the qualification limits, including the small reported timing margin.

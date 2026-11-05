# Prebuilt home-authorization image

`home_product.fs` is the tested SRAM configuration for the Tang Mega 138K Basic / GW5AST-138C, at 25 MHz. SHA256:

```text
cb0f7d60bbedca7ec504973d26f5093445049a4dbac3435df591231c2ae1922e
```

It needs the signed base-model flash data and a live authorization relay before startup. Its public test keys support 32 unique home grants per signing tree. Use [INSTALL.md](../INSTALL.md). It is not a flash data file. [Validation](../VALIDATION.md) and the [reset review](../RESET-REVIEW.md) limit its timing/security claims.

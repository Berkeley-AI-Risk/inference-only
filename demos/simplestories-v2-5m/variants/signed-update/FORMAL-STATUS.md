# S-AWIC formal scope

**No new formal proof has been completed for this variant.** The evidence in [VALIDATION.md](VALIDATION.md) and the [complete Tang target](tang/VALIDATION.md) is executable reference testing, RTL simulation and native compilation with real cryptographic computation. The complete composition's obligations are listed in [tang/FORMAL-STATUS.md](tang/FORMAL-STATUS.md).

The unmodified native SHA compressor and verified page bank are frozen copies, with identities in [native-sources.json](evidence/native-sources.json). Their presence does not transfer the baseline's proof conclusions to the signed-update composition. Private input ownership, expected-digest provenance and model-lock assumptions differ.

| Obligation | Current evidence | Formal status |
| --- | --- | --- |
| At least two distinct fixed authorities authorize the manifest | Published-vector and connected RTL positive/negative tests | Open |
| Canonical domain, geometry, policy and lengths | Reference and RTL rejection tests | Open |
| Runtime table/metadata are the authenticated bytes and cannot be rewritten | Connected tests, source structure and output masking | Open |
| No model readiness before complete signed admission and image readback | Connected simulation monitors, full-size positive/negative cases | Open |
| Reset discards partial/current admission and page validity | Directed reset cases | Open |
| Actual page data verified before consumer output | Native bank used in connected regression, including changed and corrupt pages | New composition open |
| Whole APPEND/STEP/CLEAR machine refines the intended model | Directed complete Tang UART traces against an independent model oracle | Open |
| A chosen-weight adversary has low residual training capacity | No bound or achieved attack established | Open |
| Physical/key-management security and production timing/resource closure | Not evaluated | Open |

There is no monotonic-version, update-cap or delay theorem to prove for this signature-only policy. They are not implemented. Subsequent proofs should bind the actual new sources and include successful admission/inference reachability, rather than prove only that a permanently disabled model is safe.

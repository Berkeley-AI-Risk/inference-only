# Corrected SV translator

The original proof used ACL2 8.7 Community Books with a two-line correction to `centaur/sv/vl/svstmt-compile.lisp`. In the assignment translation, the LHS index expressions and RHS use `st.blkst` in place of `svstack`. The supplied patch and the hash checks retain this exact change. [Two-line patch](svstmt-compile.patch) · [Retained translator notice](../notices/SVSTM-COMPILE-MIT.txt)

| File identity | SHA-256 |
| --- | --- |
| Stock ACL2 8.7 translator | `264b13524d49ead3427f791f53cdc0b672729636cf5b03790b67ad4a70963735` |
| Corrected translator source | `99f4a19521edf7aa657744c3865bec70f05ffd4135696b7c04f0dc3a6c46486c` |
| Translator certificate loaded by the archived recipient | `da79f66d8b69d0108eff4c24cbb10698051045d684647d37f74b56438fcd680b` |

The [reader command](../README.md#reproduce-the-sources) verifies the corrected source digest when given the stock file. The [library build recipe](build_corrected_library.sh) copies a certified ACL2 8.7 books installation to a fresh destination, applies the patch, checks the exact eight dependent cert targets and runs a library load check. It requires a compatible local `saved_acl2`, a built stock Community Books tree, Perl, Make and the ordinary shell tools listed in the script. Use source and installation paths without spaces for that recipe. Setup and certification of the external library are separate from the reader command.

The historical proof runs used SBCL 2.6.10 and CaDiCaL 3.0.0. The retained SAT adapters preserve ACL2's checked LRAT use. The installed Common Lisp libraries used by ACL2, including Quicklisp/ASDF dependencies, retain their upstream terms. A fresh proof replay requires independently building and certifying the corrected library and checked-parent, payload and record books on the chosen platform. The archived certificate digests identify the earlier run. [Tool notices](../notices/README.md) · [Recorded proof evidence](../evidence/RECORDED-RESULTS.json)

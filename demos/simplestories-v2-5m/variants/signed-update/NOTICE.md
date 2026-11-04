# Incorporated source and test data

`rtl/vendor/sha.sv` and `rtl/vendor/bank.sv` are unmodified copies of the baseline SimpleStories sources from `demos/simplestories-v2-5m/hardware/project/`. Their identities are in `evidence/native-sources.json`. They remain subject to the repository's Apache 2.0 [license](../../../../LICENSE). New source files in this variant use the repository license.

`tests/rfc8554-case1.json` contains numeric public-key, message and signature test data extracted from RFC 8554, Appendix F, Test Case 1. It records the source URL and downloaded document hash. The reference and RTL implement the fixed LMS/LMOTS parameter sets described in that RFC; this is not a general HSS or NIST certification claim.

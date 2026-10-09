# Licensing

The project-owned custom RTL, reference code, host app, tests, proofs,
documentation and board photograph are released under **Apache-2.0**. See
[LICENSE](LICENSE), [NOTICE](NOTICE) and [the scope of that grant](LICENSE-SCOPE.md).

The fixed SimpleStories model and tokenizer are distributed on the basis of
the model publisher's explicit **MIT** declaration at the pinned revision.
The model image and model-derived normalization/scaling tables retain that
provenance; they are not represented as wholly original project material.
The encrypted model copy retains the same model provenance; encrypting
it does not create a new license grant.
The declaration and MIT terms are preserved in `LICENSES/`.

The encrypted-memory AES S-box adapts BearSSL's MIT-licensed Boolean circuit.
Its copyright and permission notice are retained in both affected RTL files
and [LICENSES/BearSSL-MIT.txt](LICENSES/BearSSL-MIT.txt); our Apache-2.0 grant
does not replace that attribution.

The board constraints adapt Sipeed's Apache-2.0 example. Both its Sipeed
notice and the original GOWIN notice are preserved in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) and beside the constraint file.
The tested constraint bytes are unchanged.

## FPGA configurations and vendor dependencies

The release includes three inference configurations and a separate
backup-reader configuration for the specified GOWIN device. These are
device-targeted FPGA outputs, **not copies of the GOWIN compiler, programmer,
vendor libraries or an encrypted source-IP distribution**. The project
license covers our contributions, not a purported relicensing of every
third-party element embodied in those outputs.
The GOWIN notices embedded in the bitstream headers are retained unchanged;
our Apache-2.0 grant does not relicense GOWIN's contributions.

All four configurations (including the backup reader) were generated with **GOWIN V1.9.11.03 Education
(81398)**. We checked the release note bundled with that exact installer:
*RN100-1.9.11.03 EducationE*, July 10, 2025, section 1. It limits use of that
tool edition to education, research and other noncommercial purposes. Our
academic demonstration is a research use. This is a vendor-tool condition,
not a new noncommercial restriction on our Apache-2.0 source code.

GOWIN's published [2024.10 software agreement](https://cdn.gowinsemi.com.cn/END_USER_LICENCE_AGREEMENT_FOR_GOWIN_SOFTWARE%28version%EF%BC%9A2024.10%29.pdf)
distinguishes the supplied software from generated output data (sections 1,
3 and 5(4)). Neither that agreement nor the checked release note expressly
prohibits sharing generated FPGA configurations, but neither supplies a
blanket redistribution grant for all IP embodied in them. This review is
not commercial-use clearance or a replacement for applicable vendor/IP terms.

Our practical distribution judgment follows the ordinary sharing of FPGA
configurations for this board: the official Sipeed repository itself supplies
prebuilt configurations alongside the same DDR example. We have not identified
a specific applicable restriction that requires removing these runnable
outputs. This is not a bespoke permission letter from GOWIN or a legal
guarantee about every downstream use. See the
[pinned official example](https://github.com/sipeed/TangMega-138K-example/tree/06e7d8b118d345915ab6f257b7c22226f81575cd/ddr_memory).
We retain the configurations for reproducing this research demonstration.
For commercial tool use or deployment, check the applicable terms with GOWIN.

The GOWIN tools are obtained separately under their terms. The openFPGALoader
utility used for factory-backup restoration is also obtained separately from
its publisher/package distributor, under its own license; its executable and
libraries are not bundled here. The four
exact DDR/clock source dependencies needed only for a source rebuild are
fetched directly from Sipeed's public repository with hash verification;
they are not rebundled here. Their availability has been checked, not assumed.
See [VENDOR-SETUP.md](VENDOR-SETUP.md).

No paid hardware-development license is needed for the documented **prebuilt
run** workflow. Rebuilding requires the separately obtained vendor tools and
acceptance of their applicable terms. Host dependencies are installed from
their package publishers and retain their own licenses.

An eventual ASIC would need appropriate replacements or licenses for the
FPGA-specific vendor IP; this release does not grant ASIC manufacturing rights
in GOWIN's independently supplied components.

This is an experimental hardware release without warranties. Licensing does
not certify timing, security, electrical safety, or resistance to physical
tampering. Read [PROGRAMMING.md](PROGRAMMING.md) before altering a board.

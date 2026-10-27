# References and implementation lineage

Yang Liu, Yi Chen, Yongwei Zhao, et al. **Hardwired-Neurons Language Processing
Units as General-Purpose Cognitive Substrates.** arXiv:2508.16151v2, revised
January 13, 2026. [Paper](https://arxiv.org/abs/2508.16151v2),
[full text](https://arxiv.org/html/2508.16151v2),
[DOI](https://doi.org/10.48550/arXiv.2508.16151).

Sections 3–4 supply the architectural motivation: fixed coefficients,
coefficient grouping, bit serialization and model-dependent metal connections.
Section 6 describes their implementation/evaluation methodology. Their reported
results are not measurements of our circuit. This source checkpoint contains
none of the authors' RTL, layout generator or foundry process kit.

The present complete-model implementation instead derives from this project's
AWIC token core and exact SimpleStories integer reference. It fixes model reads
behind ROM and keeps dynamic K/V inside the token-machine boundary. The compact
640-bit ROM, clustered projection pipeline and exact normalization changes are
identified by source hash in [PROVENANCE.json](PROVENANCE.json). Reused module
names retain their AWIC history; they do not imply that this ASIC has been
implemented using FPGA vendor primitives.

HNLPU-style custom physical weight routing remains a comparison candidate. The
ROM baseline was selected to obtain executable end-to-end correctness and reuse
existing arithmetic; no comparative result yet establishes its superiority.

```bibtex
@misc{liu2026hnlpu,
  title = {{Hardwired-Neurons Language Processing Units as General-Purpose Cognitive Substrates}},
  author = {Yang Liu and Yi Chen and Yongwei Zhao and others},
  year = {2026},
  eprint = {2508.16151},
  archivePrefix = {arXiv},
  primaryClass = {cs.AR},
  doi = {10.48550/arXiv.2508.16151},
  url = {https://arxiv.org/abs/2508.16151v2},
  note = {Version 2, January 13, 2026}
}
```

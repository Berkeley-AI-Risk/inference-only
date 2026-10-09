# Replay the K/V guard

These tests use the exact guard, hash wrapper and SHA RTL in
`variants/kv-protected/hardware/project/`. An independent Python/hashlib model
generates data, expected digests and command outcomes. This is a **simulation
of the private guard**, not a physical-memory attack, full-model replay or
unbounded proof. The test bench's memory-control commands are verification
fixtures, not ports exposed to users of the inference circuit.

The historical `role-pages-v2/model.py` reference in the hash RTL's comment
corresponds to the model supplied here as [role-pages/model.py](role-pages/model.py).
The RTL comment is retained to preserve the source identity of the tested image.

From the repository root, with Python 3.12, Icarus Verilog (`iverilog`, `vvp`)
and Verilator 5.050 available on `PATH`:

```sh
python3.12 -I -S -B simulation/kv-protected/role-pages/run_guard.py \
  --out /absolute/fresh-work/guard-four-state
python3.12 -I -S -B simulation/kv-protected/role-pages/run_guard.py \
  --verilator --synthesis --full-geometry \
  --out /absolute/fresh-work/guard-full-geometry
```

Output directories must be fresh and outside this release. Use a whitespace-
free path for the Verilator/GNU Make build. The first run checks 5,407 commands,
including unknown-data handling, corruption, location/role substitution, stale
data, sealed copies and cancellation. The second checks 275,913 commands,
populating all positions through ordinary writes in all six layers. Both
exercise ten write-state, thirteen read-state and four tag-commit CLEAR cases.
Generated inputs, local source snapshots, raw logs and cycle CSVs are retained
in the requested directory. A compile warning/error, missing success marker
or failed expected response fails the run.

Three intentionally faulty simulation copies check the test bench itself:

```sh
python3.12 -I -S -B simulation/kv-protected/role-pages/run_guard.py \
  --verilator --synthesis --mutant accept-bad-digest \
  --out /absolute/fresh-work/bad-digest
python3.12 -I -S -B simulation/kv-protected/role-pages/run_guard.py \
  --verilator --synthesis --mutant ignore-cache-role \
  --out /absolute/fresh-work/bad-role
python3.12 -I -S -B simulation/kv-protected/role-pages/run_guard.py \
  --verilator --synthesis --mutant publish-first-tag \
  --out /absolute/fresh-work/bad-tag-commit
```

These commands pass only when the expected faulty simulation is rejected;
they never modify the shipped RTL or a physical device. The ordinary run must
also pass. A timeout or arbitrary compile failure is not a successful faulty-
control result. The original Python ownership-model tests are retained as a
dependency of the role-page model; their four-position default is not the
protected image's sixteen-position hash layout.

The runner differs from its recorded engineering version only in explicit
path/tool portability changes. It takes its default guard/hash/SHA from the
shipped protected project, not a hand-edited substitute. All three match the
selected native input hashes. See [the design and limits](../../KV-PROTECTION.md).

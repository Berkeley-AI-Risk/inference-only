"""Shared pieces for the write-payload development scripts: the names of the
run's input variables and a concrete environment built from the certified
book's recorded cycle (../kv-joined-book-checked-sat/counterexample-cycle.txt)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "acl2-pilot", "joined"))
sys.path.insert(0, HERE)
import joint_signals_reads as tables  # noqa: E402
import proto_run  # noqa: E402

STATES = [s[0] for s in tables.state_signals()]
HYPS = [h[0] for h in tables.hyp_signals()]
PAYLOAD = [s[0] for s in proto_run.payload_state()]
PAYLOAD_WIDTH = {s[0]: s[2] for s in proto_run.payload_state()}
OBS = [o[0] for o in proto_run.observations()]


def recorded_cycle():
    path = os.path.join(ROOT, "kv-joined-book-checked-sat", "counterexample-cycle.txt")
    lines = [l for l in open(path).read().split("\n") if l.strip() and not l.startswith("#")]
    return dict(l.split() for l in lines)


IDLE = {"p-lock-meta": 1, "p-lock-sync": 1, "p-apprel": 7, "m-rel": 3,
        "b-crel": 7, "b-arel": 7, "b-lock-meta": 1, "b-lock-sync": 1,
        "b-lock-seen": 1, "k-lock-seen-q": 1, "a-lock-seen": 1,
        "h-attn-ready": 1, "h-epready": 1, "h-legal": 1}


def env_alist(changes=None, reset_n=1, clear=0):
    """An ACL2 alist for one cycle: everything released, locked and idle,
    every other register and environment signal 0, with `changes`
    (id -> value) laid over it."""
    vals = {k: 0 for k in STATES + HYPS + PAYLOAD}
    vals.update(IDLE)
    vals.update(changes or {})
    parts = ["(i-reset-n . %d) (i-clear . %d)" % (reset_n, clear)]
    parts += ["(r-%s . %d) (c-%s . -1)" % (s, vals[s], s) for s in STATES + PAYLOAD]
    parts += ["(%s . %d) (c-%s . -1)" % (h, vals[h], h) for h in HYPS]
    return "'(" + "\n    ".join(parts) + ")"

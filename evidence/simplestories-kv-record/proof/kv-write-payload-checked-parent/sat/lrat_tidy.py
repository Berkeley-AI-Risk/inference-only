#!/usr/bin/env python3
"""Put a solver's LRAT proof into the form ACL2's checker accepts.

    python3 -I lrat_tidy.py FORMULA.cnf PROOF.in PROOF.out

Nothing here is trusted.  ACL2 checks PROOF.out against the formula it wrote
itself; if this program spoiled a proof, ACL2 would refuse it.

An LRAT proof is a list of steps.  Each adds a clause and names, as hints,
the earlier clauses that justify it: assume every literal of the new clause
false, visit the hints in order, and each one must then have exactly one
literal left undecided (which becomes true) until the last, which must have
none left (a conflict).  ACL2's checker (projects/sat/lrat/sorted) holds a
proof to exactly that, and to one thing more: after its first literal, the
literals of an added clause must be in order of variable number.

CaDiCaL's proofs are valid but not always that tidy.  Two things are done:

  1. The literals of each added clause, after the first, are sorted by
     variable number.  The first is left in place: in a step that is not
     justified by unit propagation alone (a RAT step) it is the pivot.

  2. In a step justified by unit propagation, hints are replayed.  A hint
     that is already satisfied when it is reached, or that names a deleted
     clause, is dropped; a hint that still has two or more literals undecided
     is tried again after the others; hints after the conflict are dropped.
     If no conflict is reached the step is passed on unchanged, and ACL2 will
     refuse it.

Steps with no hints or with negative hints (RAT steps) and deletion lines
are passed on as they are, apart from item 1.
"""
import sys


def tidy_hints(clause, hints, db):
    """The hints in an order that unit propagation can follow, or None."""
    false = set(clause)
    out = []
    pending = hints
    while pending:
        deferred = []
        for h in pending:
            c = db.get(h)
            if c is None:
                continue
            undecided = None
            count = 0
            satisfied = False
            for lit in c:
                if -lit in false:
                    satisfied = True
                    break
                if lit not in false:
                    undecided = lit
                    count += 1
            if satisfied:
                continue
            if count == 0:
                out.append(h)
                return out
            if count == 1:
                out.append(h)
                false.add(-undecided)
            else:
                deferred.append(h)
        if len(deferred) == len(pending):
            return None
        pending = deferred
    return None


def main():
    formula, proof_in, proof_out = sys.argv[1:4]
    db = {}
    n = 0
    with open(formula) as f:
        for line in f:
            if line[:1] in ("p", "c") or not line.strip():
                continue
            n += 1
            db[n] = [int(x) for x in line.split()[:-1]]
    with open(proof_in) as f, open(proof_out, "w") as g:
        for line in f:
            fields = line.split()
            if not fields:
                continue
            if fields[1] == "d":
                for x in fields[2:-1]:
                    db.pop(int(x), None)
                g.write(line)
                continue
            nums = [int(x) for x in fields]
            end = nums.index(0, 1)
            clause = nums[1:end]
            hints = nums[end + 1:-1]
            if hints and min(hints) > 0:
                hints = tidy_hints(clause, hints, db) or hints
            ordered = clause[:1] + sorted(clause[1:], key=abs)
            g.write(" ".join(map(str, [nums[0]] + ordered + [0] + hints + [0])) + "\n")
            db[nums[0]] = clause


if __name__ == "__main__":
    main()

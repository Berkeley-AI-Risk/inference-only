"""Small fail-closed checks shared by the offline proof auditors."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import re


def distinct_negative_paths(proof, negatives):
    paths = [p.resolve() for p in negatives]
    assert len(paths) == 2 and len(set(paths)) == 2
    assert proof.resolve() not in paths
    return paths


def unrestricted_state_predicates(smt, top):
    for suffix in ("i", "h", "u"):
        needle = f"(define-fun |{top}_{suffix}| ((state |{top}_s|)) Bool true)"
        definitions = re.findall(r"^\(define-fun \|" + re.escape(top + "_" + suffix) + r"\| .*", smt, re.M)
        assert definitions == [needle], (suffix, definitions)
    assert "; yosys-smt2-assume " not in smt


def exact_answers(raw, expected):
    # Do not filter unknown, errors, diagnostic prose or duplicate answers.
    # All nonempty lines must be exactly the expected solver answers.
    lines = [line.strip() for line in raw.decode("utf-8").splitlines() if line.strip()]
    assert lines == expected, (lines, expected)
    return lines

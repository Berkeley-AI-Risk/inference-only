#!/bin/sh
# usage: sh sat/cadical-lrat.sh FILE
#
# Run CaDiCaL on the DIMACS file FILE.  When its answer is "unsatisfiable",
# leave its proof, in the text LRAT format, in FILE.lrat, which is where
# ACL2's satlink looks for it.
#
# Nothing here is trusted.  ACL2 checks whatever proof it finds in FILE.lrat
# against the formula it wrote itself, and reports "unsatisfiable" only if
# the check passes.  A wrong answer, a wrong proof or a mistake in this
# script can make a proof attempt fail; it cannot make one succeed.
#
# --factor=0 turns off the one technique of CaDiCaL that adds variables to
# the formula (bounded variable addition), so that every step of the proof
# is a step of unit propagation.  lrat_tidy.py then puts the proof into the
# form ACL2's checker asks for; what it does and why is at its head.
#
# If KVJ_SAT_LOG names a file, one line is appended to it for each call: the
# solver's exit status (10 satisfiable, 20 unsatisfiable), the size of the
# formula, and the number of clauses the proof adds.
for f in "$@"; do :; done
rm -f "$f.lrat" "$f.lrat.raw"
cadical -q --lrat --no-binary --factor=0 "$@" "$f.lrat.raw"
status=$?
steps=0
if [ "$status" -eq 20 ]; then
    python3 -I "$(dirname "$0")/lrat_tidy.py" "$f" "$f.lrat.raw" "$f.lrat"
    steps=$(grep -c -v ' d ' "$f.lrat")
fi
rm -f "$f.lrat.raw"
if [ -n "${KVJ_SAT_LOG:-}" ]; then
    echo "exit $status; $(grep -m1 '^p cnf' "$f"); proof steps $steps; $(basename "$f")" >> "$KVJ_SAT_LOG"
fi
exit "$status"

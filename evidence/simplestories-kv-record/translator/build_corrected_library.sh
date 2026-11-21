#!/bin/sh
# Build a certified copy of the ACL2 8.7 books in which the SystemVerilog
# translator reads nonblocking assignments the standard way.
#
#   sh translator/build_corrected_library.sh [destination]
#
# The destination (default ~/acl2-8.7-nonblocking-corrected) must not exist.
# It receives a copy of ~/acl2-8.7/books with one source file changed in two
# lines (svstmt-compile.patch) and the eight certified books that depend on
# that file certified again by ACL2.  The original installation is only
# read.  Nothing is downloaded.  Takes a few minutes and about 0.1 GB of new
# disk space on APFS, where the copy shares storage with the original.
#
# To use the result, run the same ACL2 executable with
#   ACL2_SYSTEM_BOOKS=<destination>/books
# in the environment.  See translator/README.md.
#
# Environment:
#   ACL2_HOME  the installation to copy from (default ~/acl2-8.7)
#   JOBS       parallel certifications (default 4)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd -L)"
STOCK="${ACL2_HOME:-$HOME/acl2-8.7}"
DEST="${1:-$HOME/acl2-8.7-nonblocking-corrected}"
JOBS="${JOBS:-4}"
FILE=centaur/sv/vl/svstmt-compile.lisp
STOCK_SHA=264b13524d49ead3427f791f53cdc0b672729636cf5b03790b67ad4a70963735
FIXED_SHA=99f4a19521edf7aa657744c3865bec70f05ffd4135696b7c04f0dc3a6c46486c
# The certified books whose certificates depend on that file, in dependency
# order.  The pilot loads the first seven; centaur/sv/top is certified again
# so that the copy holds no stale certificate.
BOOKS="centaur/sv/vl/svstmt-compile
centaur/sv/vl/vl-svstmt
centaur/sv/vl/elaborate
centaur/sv/vl/moddb
centaur/vl/transforms/unparam/override
centaur/vl/transforms/unparam/top
centaur/sv/vl/top
centaur/sv/top"
# The library books the pilot's inputs load.
LOADED="centaur/fgl/top centaur/misc/memory-mgmt centaur/sv/svtv/svtv-generalize
centaur/sv/svtv/svtv-stobj-debug centaur/sv/svtv/svtv-stobj-defsvtv
centaur/sv/svtv/svtv-to-fsm centaur/sv/svtv/svtv-to-fsm-defs centaur/sv/vl/top
centaur/vl/loader/top oslib/ls std/testing/must-fail"

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
die() { echo "$*" >&2; exit 2; }
for p in "$HERE" "$STOCK" "$DEST"; do
    case "$p" in *" "*) die "path contains a space: $p";; esac
done
[ -x "$STOCK/saved_acl2" ] || die "no ACL2 executable at $STOCK/saved_acl2"
[ -e "$DEST" ] && die "$DEST already exists; name another destination"
[ "$(sha "$STOCK/books/$FILE")" = "$STOCK_SHA" ] || die "$STOCK/books/$FILE is not the released file"

mkdir -p "$DEST"
echo "copying $STOCK/books to $DEST/books"
# -c shares storage with the original where the file system allows it; -p
# keeps file times, which ACL2 uses to recognise a certified book's source.
cp -c -R -p "$STOCK/books" "$DEST/books" 2>/dev/null || {
    rm -rf "$DEST/books"
    cp -R -p "$STOCK/books" "$DEST/books"
}
patch -s "$DEST/books/$FILE" "$HERE/svstmt-compile.patch"
rm -f "$DEST/books/$FILE.orig"
[ "$(sha "$DEST/books/$FILE")" = "$FIXED_SHA" ] || die "patched file has an unexpected hash"

export ACL2_SYSTEM_BOOKS="$DEST/books"
export ACL2_CUSTOMIZATION=NONE
unset MAKEFLAGS || true
cd "$DEST/books"

# What would be rebuilt?  It must be exactly the eight books.
./build/cert.pl -a "$STOCK/saved_acl2" -b "$DEST/books" --make-args -n \
    centaur/sv/vl/top centaur/sv/top > "$DEST/dry-run.log" 2>&1 || true
sed -n "s/.*make_cert_help\.pl '\([^']*\)'.*/\1/p" "$DEST/dry-run.log" | sort > "$DEST/dry-run-books.txt"
echo "$BOOKS" | sort > "$DEST/expected-books.txt"
cmp -s "$DEST/dry-run-books.txt" "$DEST/expected-books.txt" || {
    echo "the dry run would certify a different set of books:" >&2
    cat "$DEST/dry-run-books.txt" >&2
    exit 1
}

echo "certifying the eight books ($JOBS at a time)"
START=$(date +%s)
./build/cert.pl -j "$JOBS" -a "$STOCK/saved_acl2" -b "$DEST/books" \
    centaur/sv/vl/top centaur/sv/top > "$DEST/certify.log" 2>&1 || { tail -30 "$DEST/certify.log" >&2; exit 1; }
END=$(date +%s)
for b in $BOOKS; do
    [ "$b.cert" -nt "$b.lisp" ] || die "no fresh certificate for $b"
    [ "$b.cert" -nt "centaur/sv/vl/svstmt-compile.lisp" ] || die "certificate for $b is older than the corrected file"
    if grep -q -E "ACL2 Error|\*\*\*\* FAILED|HARD ACL2 ERROR" "$b.cert.out"; then
        die "certification transcript of $b reports an error"
    fi
done

# Load every library book the pilot and the joined K/V book use from the copy
# and report on it.
{
    for b in $LOADED; do echo "(include-book \"$b\" :dir :system)"; done
    echo "(ld \"$HERE/library-report.lsp\")"
} > "$DEST/load-check.lsp"
"$STOCK/saved_acl2" < "$DEST/load-check.lsp" > "$DEST/load-check.log" 2>&1 || true
grep -q -F "BCT-LIB system books: $DEST/books" "$DEST/load-check.log" || die "load check: wrong books directory"
grep -q -F "BCT-LIB loaded without a certificate: 0" "$DEST/load-check.log" || die "load check: a book loaded without a certificate"
grep -q -F "BCT-LIB skip-proofs seen: NIL" "$DEST/load-check.log" || die "load check: skip-proofs seen"

{
    echo "Corrected copy of the ACL2 8.7 books"
    echo
    echo "Built $(date -u +%Y-%m-%dT%H:%M:%SZ) by translator/build_corrected_library.sh for the"
    echo "checked-parent SimpleStories K/V record proof."
    echo
    echo "Copied from:        $STOCK/books"
    echo "ACL2 executable:    $STOCK/saved_acl2"
    echo "File changed:       books/$FILE (two lines; see the pilot's"
    echo "                    translator/svstmt-compile.patch)"
    echo "  released SHA-256: $STOCK_SHA"
    echo "  corrected:        $FIXED_SHA"
    echo "Certified again:    the eight books listed below, in $((END-START)) s"
    echo "Use:                ACL2_SYSTEM_BOOKS=$DEST/books $STOCK/saved_acl2"
    echo
    echo "ACL2 recognises a certified book's source by its length and write"
    echo "date, so copy this tree only with file times preserved (cp -p)."
    echo "No other book with a certificate in this tree depends on the"
    echo "changed file."
    echo
    echo "SHA-256 of the eight books' sources and certificates:"
    for b in $BOOKS; do
        echo "$(sha "$b.lisp")  books/$b.lisp"
        echo "$(sha "$b.cert")  books/$b.cert"
    done
    echo
    grep -E "^BCT-LIB " "$DEST/load-check.log"
} > "$DEST/CORRECTED-LIBRARY.txt"
cat "$DEST/CORRECTED-LIBRARY.txt"

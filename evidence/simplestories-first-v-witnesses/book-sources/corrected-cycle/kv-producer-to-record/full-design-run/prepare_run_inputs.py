#!/usr/bin/env python3
"""Pack the ROM contents and the model image for the full-design run.

usage: python3 -I prepare_run_inputs.py AUDIT_DIR REPO_DIR OUT_DIR

  AUDIT_DIR  .../claude/simplestories-proof-audit
  REPO_DIR   the checkout's root
  OUT_DIR    an existing, empty directory for the packed files

The corrected translator drops `initial` blocks, so in the translated design
the contents of the five read-only memories and of the exponent table's
endpoint word are free variables.  The run binds them, in every cycle, to
the contents the RTL loads:

  u_auth.digest_rom                 digests32.memh        (service.sv, DIGEST_HEX)
  u_auth.g_metadata.memory          metadata192.memh      (service.sv, METADATA_HEX)
  ...u_rmsnorm.u_norm_rom.norm_rom  norm_rom34.memh       (NORM_ROM_FILE), twice
  ...u_exp_lut.value_mem            the assignments in the module's initial block
  ...u_exp_lut.endpoint_value       the assignment in the same block

An unpacked array `logic [W-1:0] m [0:N-1]` is one vector of N*W bits in the
translated design with element 0 in the most significant W bits (the same
layout the certified payload book derives for the controller's pair store).

Writes rom.lsp (one alist: variable -> value), image.lsp (one list: the
image's 256-bit words, word w = little-endian integer of bytes [32w, 32w+32))
and PREPARED.txt.  Every file read is checked against the SHA-256 below.
"""
import hashlib
import os
import re
import sys

ROM_ROOT = ("claude/simplestories-proof-audit/snapshot/SimpleStories-private-proof-audit/"
            "tang-greedy-speed/session-isolation/runs/native-hierarchy-r1/project")
IMAGE = ("tang-greedy-speed/build/current-release-final-r1/assets/"
         "board1-real-semantic-image2048.bin",
         "cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0")
DIGESTS = (ROM_ROOT + "/digests32.memh",
           "2c4bb7908d6e957b8a20e99b230c6e8a3d7fafddeb391581dfcbcb1cce7bf672")
METADATA = (ROM_ROOT + "/metadata192.memh",
            "1535aa2d84de71c736b71e40694940f1b291dfd1db6c9f02d10b8605552ccdb9")
NORM = (ROM_ROOT + "/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh",
        "2f57bc170e24c059c3fbd4023979405ff058399ba424c50e54d80105f8b1a5d4")
EXP_MEMH = ROM_ROOT + "/model_rtl_evidence/attention_sublayer/exp_neg_q30.memh"
# the pinned RTL of the proof, and its list of hashes
RTL_ROOT = "acl2-pilot/results/joined-repaired"
SOURCES = "kv-joined-book-checked-sat/SOURCES.sha256"
EXP_RTL = "fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv"

IMAGE_WORDS = 227062


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fail(msg):
    sys.stderr.write("prepare_run_inputs: " + msg + "\n")
    sys.exit(1)


def read_pinned(path, want, notes):
    got = sha(path)
    if got != want:
        fail("%s has SHA-256 %s, expected %s" % (path, got, want))
    notes.append("%s  %s" % (got, path))
    with open(path, "rb") as f:
        return f.read()


def memh(data, count, width, name):
    words = [int(line, 16) for line in data.decode("ascii").split() if line]
    if len(words) != count:
        fail("%s has %d words, expected %d" % (name, len(words), count))
    if any(w >> width for w in words):
        fail("%s has a word wider than %d bits" % (name, width))
    return words


def pack(words, width):
    """element 0 in the most significant bits"""
    v = 0
    for w in words:
        v = (v << width) | w
    return v


def main():
    if len(sys.argv) != 4:
        fail("usage: prepare_run_inputs.py AUDIT_DIR REPO_DIR OUT_DIR")
    audit, repo, out = sys.argv[1:]
    if os.listdir(out):
        fail("OUT_DIR is not empty")
    notes = []

    image = read_pinned(os.path.join(repo, IMAGE[0]), IMAGE[1], notes)
    if len(image) != 32 * IMAGE_WORDS:
        fail("the image has %d bytes, expected %d" % (len(image), 32 * IMAGE_WORDS))
    digests = memh(read_pinned(os.path.join(repo, DIGESTS[0]), DIGESTS[1], notes),
                   14192, 32, "digests32.memh")
    metadata = memh(read_pinned(os.path.join(repo, METADATA[0]), METADATA[1], notes),
                    2328, 192, "metadata192.memh")
    norm = memh(read_pinned(os.path.join(repo, NORM[0]), NORM[1], notes),
                3328, 34, "norm_rom34.memh")

    # The exponent table: from the pinned RTL itself.
    pinned = {}
    with open(os.path.join(audit, SOURCES)) as f:
        for line in f:
            h, p = line.split()
            pinned[p] = h
    exp_path = os.path.join(audit, RTL_ROOT, EXP_RTL)
    exp_text = read_pinned(exp_path, pinned["rtl/" + EXP_RTL], notes).decode("ascii")
    cells = {}
    for m in re.finditer(r"value_mem\[(\d+)\]\s*=\s*32'h([0-9a-fA-F]{8});", exp_text):
        i = int(m.group(1))
        if i in cells:
            fail("the exponent table assigns cell %d twice" % i)
        cells[i] = int(m.group(2), 16)
    if sorted(cells) != list(range(4096)):
        fail("the exponent table's initial block does not assign cells 0..4095 once each")
    ends = re.findall(r"endpoint_value\s*=\s*32'h([0-9a-fA-F]{8});", exp_text)
    if len(ends) != 1:
        fail("the exponent table's initial block does not assign endpoint_value once")
    exp = [cells[i] for i in range(4096)]
    endpoint = int(ends[0], 16)
    # cross-check with the file the module's parameter names (not pinned by the proof)
    with open(os.path.join(repo, EXP_MEMH)) as f:
        file_words = [int(x, 16) for x in f.read().split()]
    same = file_words == exp + [endpoint]
    notes.append("exponent table in the RTL's initial block %s exp_neg_q30.memh (%s)"
                 % ("equals" if same else "DIFFERS FROM", sha(os.path.join(repo, EXP_MEMH))))
    if not same:
        fail("the RTL's exponent table differs from exp_neg_q30.memh")

    def var(scopes, name):
        return '(:var (%s . "%s") . 0)' % (" ".join('"%s"' % s for s in scopes), name)

    dp = ["u_machine", "u_six_layers", "u_datapath"]
    rom = [
        (var(["u_auth"], "digest_rom"), pack(digests, 32)),
        (var(["u_auth", "g_metadata"], "memory"), pack(metadata, 192)),
        (var(dp + ["u_rmsnorm", "u_norm_rom"], "norm_rom"), pack(norm, 34)),
        (var(["u_machine", "u_token_shell", "u_final_rmsnorm", "u_norm_rom"], "norm_rom"),
         pack(norm, 34)),
        (var(dp + ["u_attention", "u_exp_lut"], "value_mem"), pack(exp, 32)),
        (var(dp + ["u_attention", "u_exp_lut"], "endpoint_value"), endpoint),
    ]
    with open(os.path.join(out, "rom.lsp"), "w") as f:
        f.write("(\n")
        for k, v in rom:
            f.write(" (%s . #x%x)\n" % (k, v))
        f.write(")\n")
    with open(os.path.join(out, "image.lsp"), "w") as f:
        f.write("(\n")
        for w in range(IMAGE_WORDS):
            f.write("#x%x\n" % int.from_bytes(image[32 * w:32 * w + 32], "little"))
        f.write(")\n")
    notes.append("image words: %d; digest words: %d; metadata words: %d; norm words: %d; "
                 "exponent cells: 4096 and the endpoint word #x%x"
                 % (IMAGE_WORDS, len(digests), len(metadata), len(norm), endpoint))
    notes.append("%s  rom.lsp (packed, not kept)" % sha(os.path.join(out, "rom.lsp")))
    notes.append("%s  image.lsp (packed, not kept)" % sha(os.path.join(out, "image.lsp")))
    with open(os.path.join(out, "PREPARED.txt"), "w") as f:
        f.write("\n".join(notes) + "\n")
    sys.stdout.write("\n".join(notes) + "\n")


if __name__ == "__main__":
    main()

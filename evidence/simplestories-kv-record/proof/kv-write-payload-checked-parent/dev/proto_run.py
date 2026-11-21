#!/usr/bin/env python3
"""Development aid for the write-payload book: write the ACL2 input that
defines the payload step run on the certified design and saves an image.

    python3 -I proto_run.py OUT.lsp IMAGE

The run is the certified book's join-step-run (kv-joined-lemmas.lisp) with
the payload registers added: same stages, same names for every signal the
certified lemma names.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BOOK = os.path.normpath(os.path.join(HERE, "..", "..", "kv-joined-book-checked-sat"))
KV = "u_machine.u_six_layers.u_datapath.u_kv_cache"
RQ = "u_boundary.request_fifo_i"
AP = "u_boundary.app_boundary_i"


def match_paren(text, i):
    depth = 0
    in_str = False
    j = i
    while j < len(text):
        c = text[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == ";":
            j = text.index("\n", j)
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    raise ValueError("unbalanced")


def payload_state():
    """(id, path, width) of the payload registers."""
    s = [("k-bank%d" % b, "%s.g_pair_bank[%d].words" % (KV, b), 1024) for b in range(8)]
    # the store's read register, one per bank (the 256-bit cache_read_data_q
    # is their concatenation, bank 0 lowest)
    s += [("k-rd%d" % b, "%s.g_pair_bank[%d].read_data_q" % (KV, b), 32) for b in range(8)]
    s += [("k-offer", KV + ".write_offer_q", 256)]
    s += [("q-memp%d" % i, "%s.memory_q[%d][274:0]" % (RQ, i), 275) for i in range(8)]
    # the descriptor of each entry: head [280:279], position [292:281],
    # layer [295:293], model word [314:296].  The app side recomputes the
    # address from them and checks the descriptor.
    s += [("q-memd%d" % i, "%s.memory_q[%d][314:279]" % (RQ, i), 36) for i in range(8)]
    s += [("q-mdd", RQ + ".m_data_q[314:279]", 36)]
    s += [("q-mdp", RQ + ".m_data_q[274:0]", 275),
          ("a-saddr", AP + ".slot_address_q", 152),
          ("a-sdata", AP + ".slot_data_q", 2048),
          ("a-oaddr", AP + ".offer_address_q", 19),
          ("a-odata", AP + ".offer_write_data_q", 256)]
    return s


def observations():
    """(id, path, width): signals of the current cycle that are only read."""
    return [
        ("o-wreqv", KV + ".kv_write_req_valid_o", 1),
        ("o-wreqr", KV + ".kv_write_req_ready_i", 1),
        ("o-wreqaddr", KV + ".kv_write_req_shadow_address_o", 19),
        ("o-wreqdata", KV + ".kv_write_req_data_o", 256),
        ("o-epv", "private_kv_req_valid_o", 1),
        ("o-epw", "private_kv_req_write_o", 1),
        ("o-epaddr", "private_kv_req_word_address_o", 19),
        ("o-epdata", "private_kv_req_write_data_o", 256),
        ("o-spr", KV + ".stage_payload_ready_o", 1),
        ("o-spl", KV + ".stage_payload_legal", 1),
        ("o-wcplr", KV + ".kv_write_cpl_ready_o", 1),
        ("o-wlegal", AP + ".kv_write_descriptor_legal", 1),
    ]


def step_run_text(name="payload-step-run"):
    lemmas = open(os.path.join(BOOK, "kv-joined-lemmas.lisp")).read()
    i = lemmas.index("(defsvtv$ join-step-run")
    form = lemmas[i:match_paren(lemmas, i)]
    form = form.replace("join-step-run", name, 1)
    # payload overrides go at the end of stage curr's :overrides list
    anchor = '("u_boundary.app_boundary_i.request_descriptor_legal" h-legal :cond c-h-legal :output p-h-legal))'
    assert form.count(anchor) == 1
    extra = "".join('\n             ("%s" r-%s :cond c-%s :output p-%s)' % (p, s, s, s)
                    for s, p, _ in payload_state())
    form = form.replace(anchor, anchor[:-1] + extra + ")")
    # observations: appended to stage curr's :outputs
    anchor = '("u_machine.u_six_layers.u_datapath.u_kv_cache.terminal_fault_event" o-tfe)'
    assert form.count(anchor) == 1
    extra = "".join('\n                      ("%s" %s)' % (p, s) for s, p, _ in observations())
    form = form.replace(anchor, anchor + extra)
    # next-state payload: appended to stage next's :outputs (the last list)
    # The form ends: last entry ")", the :outputs list, the stage, :stages, the form.
    assert form.rstrip().endswith("n-a-rslot7)))))")
    extra = "".join('\n             ("%s" n-%s)' % (p, s) for s, p, _ in payload_state())
    form = form.rstrip()[:-4] + extra + "))))\n"
    return form


def old_step_hyp():
    """The certified step lemma's hypothesis, as text."""
    lemmas = open(os.path.join(BOOK, "kv-joined-lemmas.lisp")).read()
    i = lemmas.index("'(def-svtv-generalized-thm join-step-svtv-thm")
    form = lemmas[i + 1:match_paren(lemmas, i + 1)]
    h = form.index(":hyp ") + 5
    return form[h:match_paren(form, h)]


def cert_acl2_includes():
    text = open(os.path.join(BOOK, "cert.acl2")).read()
    return "".join(l + "\n" for l in text.split("\n") if l.startswith("(include-book"))


if __name__ == "__main__":
    out, image = sys.argv[1:3]
    sat = os.path.normpath(os.path.join(HERE, "..", "..", "kv-joined-book-checked-sat", "sat", "cadical-lrat.sh"))
    with open(out, "w") as f:
        f.write(cert_acl2_includes())
        f.write('(include-book "%s/kv-joined")\n' % BOOK)
        f.write('(in-package "SV")\n')
        f.write('(include-book "centaur/sv/svtv/svtv-generalize" :dir :system)\n')
        f.write('(include-book "centaur/sv/svtv/svtv-to-fsm" :dir :system)\n')
        f.write("(value-triple (acl2::set-max-mem (* 64 (expt 2 30))))\n(acl2::set-slow-alist-action nil)\n"
                "(acl2::set-rewrite-stack-limit 20000)\n")
        f.write('(defun pay-satlink-config ()\n  (declare (xargs :guard t))\n'
                '  (satlink::make-config :cmdline "sh %s" :verbose nil\n'
                '                        :mintime 0 :remove-temps t :lrat-check t))\n'
                "(defattach fgl::fgl-satlink-config pay-satlink-config)\n" % sat)
        f.write(step_run_text())
        f.write('(acl2::cw "~%PAY-RUN defined~%")\n')
        f.write(":q\n(acl2::save-exec \"%s\" \"payload step run defined\")\n" % image)

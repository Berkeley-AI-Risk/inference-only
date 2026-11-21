"""Signal tables for the joint invariant with reads allowed
(gen_joint_reads.py), over the K/V controller, the machine core's gating and
the typed DDR boundary, inside the probe module.  Compared with
joint_signals.py they add the app side's queue of reads at the endpoint and
its per-slot word number, the row-word field of the request FIFO's entries,
and the environment's read-path signals.

Index order.  For an array of ONE-BIT elements declared [0:7] in the RTL, the
name "x[i]" in an SV signal path selects RTL element 7-i: it is read as a raw
bit of the flattened array, whose first element is the top bit.  (Found by a
counterexample in which a write to element 5 changed "x[2]".)  Arrays of wider
elements are addressed by RTL element number (found by a counterexample in
which a read of memory element 7 returned "memory_q[7]").  The ids below use
RTL element numbers throughout: a-done5 is RTL slot_done_q[5], and its path
says [2].  A wrong mapping cannot make the step lemma provable, because the
RTL itself reads these arrays at the pointers the invariant uses.  The
simulator comparison (gen_sim_check.py), which names the same registers by
RTL element number, agrees with this mapping on every cycle of its run.

Paths are relative to board1_context2048_shared_token_probe.  Each state entry
is (id, path, width, reset_zero): reset_zero is False only for the FIFO memory
cells and the app side's queue of slots awaiting a read return, which no reset
touches.  Each hypothesis entry is (id, path, width,
value): value None means "two-valued, otherwise free".
"""

KV = "u_machine.u_six_layers.u_datapath.u_kv_cache"
DP = "u_machine.u_six_layers.u_datapath"
B = "u_boundary"
AP = "u_boundary.app_boundary_i"
FIFOS = (  # (id prefix, instance, payload-fault slices, control bits, width)
    ("q", "u_boundary.request_fifo_i", 40, "[317:315]", 3),
    ("s", "u_boundary.response_fifo_i", 33, "[259:256]", 4),
)

KV_REGS = [
    ("state_q", 4), ("pending_issued_q", 4), ("pending_returned_q", 3),
    ("pending_read_pending_q", 1), ("committed_prefix_q", 72),
    ("pending_layer_q", 3), ("pending_position_q", 12),
    ("pending_key_exponents_q", 16), ("pending_value_exponents_q", 16),
    ("expected_coordinate_q", 7), ("pending_persisted_q", 1),
    ("write_head_q", 1), ("write_word_q", 4), ("write_aborted_q", 1),
    ("response_kind_q", 2), ("response_head_q", 1), ("response_layer_q", 3),
    ("response_position_q", 12), ("response_fault_q", 1),
    ("response_from_pending_q", 1), ("read_word_q", 4),
    ("read_return_word_q", 4), ("read_outstanding_q", 4),
    ("read_issue_done_q", 1), ("read_aborted_q", 1),
    ("read_physical_kind_q", 1), ("read_epoch_q", 1),
    ("read_received_mask_q", 9), ("cache_valid_q", 1), ("cache_kind_q", 1),
    ("cache_layer_q", 3), ("cache_position_q", 12), ("cache_tag_epoch_q", 1),
    ("cache_epoch_q", 1), ("cache_clear_seen_q", 1), ("cache_issued_q", 3),
    ("cache_returned_q", 3), ("cache_read_pending_q", 1),
    ("cache_copy_kind_q", 1), ("lock_seen_q", 1), ("fault_q", 1),
    ("stage_begin_consumed_q", 1), ("stage_payload_consumed_q", 1),
    ("commit_consumed_q", 1), ("attention_req_consumed_q", 1),
]


def _sym(name):
    return name.replace("_", "-")


def state_signals():
    s = [
        # probe-level glue
        ("p-lock-meta", "model_lock_core_meta_q", 1, True),
        ("p-lock-sync", "model_lock_core_sync_q", 1, True),
        ("p-cfb", "core_fault_to_boundary_q", 1, True),
        ("p-apprel", "app_runtime_release_q", 3, True),
        ("m-rel", "u_machine.machine_release_q", 2, True),
    ]
    # the K/V controller's control registers
    s += [("k-" + _sym(n), KV + "." + n, w, True) for n, w in KV_REGS]
    # the typed boundary, core side
    s += [
        ("b-crel", B + ".core_release_q", 3, True),
        ("b-arel", B + ".app_release_q", 3, True),
        ("b-lock-meta", B + ".model_lock_core_meta_q", 1, True),
        ("b-lock-sync", B + ".model_lock_core_sync_q", 1, True),
        ("b-afc-meta", B + ".app_fault_core_meta_q", 1, True),
        ("b-afc-sync", B + ".app_fault_core_sync_q", 1, True),
        ("b-cfa-meta", B + ".core_fault_app_meta_q", 1, True),
        ("b-cfa-sync", B + ".core_fault_app_sync_q", 1, True),
        ("b-fault", B + ".core_fault_q", 1, True),
        ("b-lock-seen", B + ".core_lock_seen_q", 1, True),
        ("b-clr-seen", B + ".core_clear_seen_q", 1, True),
        ("b-clr-pend", B + ".core_clear_pending_q", 1, True),
        ("b-clr-drained", B + ".core_clear_drained_o", 1, True),
        ("b-epoch", B + ".core_epoch_q", 1, True),
        ("b-out", B + ".core_outstanding_q", 4, True),
        ("b-mstall", B + ".model_rsp_stalled_q", 1, True),
        ("b-wstall", B + ".kv_write_cpl_stalled_q", 1, True),
        ("b-wstallf", B + ".kv_write_cpl_stalled_fault_q", 1, True),
        ("b-rstall", B + ".kv_read_rsp_stalled_q", 1, True),
    ]
    # the two FIFOs
    for f, inst, slices, ctl, cw in FIFOS:
        s += [
            (f + "-wb", inst + ".write_binary_q", 4, True),
            (f + "-wg", inst + ".write_gray_q", 4, True),
            (f + "-full", inst + ".write_full_q", 1, True),
            (f + "-rb", inst + ".read_binary_q", 4, True),
            (f + "-rg", inst + ".read_gray_q", 4, True),
            (f + "-rs1", inst + ".read_gray_sync1_q", 4, True),
            (f + "-rs2", inst + ".read_gray_sync2_q", 4, True),
            (f + "-ws1", inst + ".write_gray_sync1_q", 4, True),
            (f + "-ws2", inst + ".write_gray_sync2_q", 4, True),
            (f + "-mv", inst + ".m_valid_q", 1, True),
            (f + "-sf", inst + ".source_fault_q", 1, True),
            (f + "-spf", inst + ".source_payload_fault_q", slices, True),
            (f + "-df", inst + ".destination_fault_q", 1, True),
            (f + "-st", inst + ".source_stalled_q", 1, True),
            (f + "-md", inst + ".m_data_q" + ctl, cw, True),
        ]
        s += [(f + "-mem%d" % i, inst + ".memory_q[%d]%s" % (i, ctl), cw, False)
              for i in range(8)]
    # The row-word field of each request-FIFO entry.  The app side keeps it
    # per slot and consults it when a read returns, so it has to be known
    # to hold a definite value; nothing else is claimed of it.
    rq = FIFOS[0][1]
    s += [("q-mdw", rq + ".m_data_q[278:275]", 4, True)]
    s += [("q-memw%d" % i, rq + ".memory_q[%d][278:275]" % i, 4, False)
          for i in range(8)]
    # the typed boundary, app side
    s += [
        ("a-fault", AP + ".fault_q", 1, True),
        ("a-lock-seen", AP + ".lock_seen_q", 1, True),
        ("a-offer", AP + ".offer_q", 1, True),
        ("a-offer-write", AP + ".offer_write_q", 1, True),
        ("a-poison", AP + ".offer_poison_q", 1, True),
        ("a-offer-slot", AP + ".offer_slot_q", 3, True),
        ("a-reserved", AP + ".reserved_q", 4, True),
        ("a-unissued", AP + ".unissued_q", 4, True),
        ("a-readcount", AP + ".read_count_q", 4, True),
        ("a-head", AP + ".head_q", 3, True),
        ("a-tail", AP + ".tail_q", 3, True),
        ("a-issue", AP + ".issue_q", 3, True),
        ("a-rhead", AP + ".read_head_q", 3, True),
        ("a-rtail", AP + ".read_tail_q", 3, True),
    ]
    for arr, pre, w in (("slot_kind_q", "a-kind", 2), ("slot_epoch_q", "a-epoch", 1),
                        ("slot_reject_q", "a-reject", 1), ("slot_done_q", "a-done", 1),
                        ("slot_fault_q", "a-sfault", 1), ("slot_word_q", "a-word", 4)):
        # one-bit elements are addressed as raw bits of the flattened array
        s += [("%s%d" % (pre, i), "%s.%s[%d]" % (AP, arr, 7 - i if w == 1 else i), w, True)
              for i in range(8)]
    # the queue of slots whose read is at the endpoint (not reset)
    s += [("a-rslot%d" % i, "%s.read_slot_q[%d]" % (AP, i), 3, False)
          for i in range(8)]
    return s


def hyp_signals():
    return [
        # No module outside the slice reports a fault.  Each of these is the
        # fault output of one such module: the arbiter, the shell (twice),
        # the six-layer block, the sealed-page service, the model CDC, and
        # the datapath as seen at the controller's upstream-fault port.
        ("h-arbfail", "u_machine.arbiter_fail", 1, 0),
        ("h-shellterm", "u_machine.shell_terminal_latched", 1, 0),
        ("h-shellfail", "u_machine.shell_fail", 1, 0),
        ("h-layerfail", "u_machine.layer_fail", 1, 0),
        ("h-auth", "auth_fault", 1, 0),
        ("h-mcdc", "model_cdc_core_fault", 1, 0),
        ("h-kupf", KV + ".upstream_fault_i", 1, 0),
        # the client (the datapath) drives two-valued signals
        ("h-layer", DP + ".current_layer_q", 3, None),
        ("h-position", DP + ".current_position_q", 11, None),
        ("h-kexp", DP + ".key_exponent_q", 8, None),
        ("h-vexp", DP + ".value_exponent_q", 8, None),
        ("h-sbegin", DP + ".kv_stage_begin_valid", 1, None),
        ("h-spayload", DP + ".kv_stage_payload_valid", 1, None),
        ("h-index", DP + ".input_index_q", 10, None),
        ("h-key", DP + ".key_ram_read_data", 16, None),
        ("h-value", DP + ".value_ram_read_data", 16, None),
        ("h-commit", DP + ".kv_commit_valid", 1, None),
        ("h-attn", DP + ".attention_cache_req_valid", 1, None),
        ("h-attn-kind", DP + ".attention_cache_req_kind", 2, None),
        ("h-attn-pos", DP + ".attention_cache_req_position", 11, None),
        ("h-attn-head", DP + ".attention_cache_req_head", 1, None),
        ("h-attn-ready", DP + ".attention_cache_rsp_ready", 1, None),
        # the endpoint side of the boundary
        ("h-epready", "private_kv_req_ready_i", 1, None),
        # a response only while a read is at the endpoint (see joint-env-p),
        # and never an error
        ("h-eprspv", "private_kv_rsp_valid_i", 1, None),
        ("h-eprsperr", "private_kv_rsp_error_i", 1, 0),
        ("h-eprspdata", "private_kv_rsp_data_i", 256, None),
        # The data word the boundary presents to the controller with a read
        # response.  Payload is not followed through the slice, so that this
        # word holds a definite value is an assumption made here.
        ("h-rspdata", KV + ".kv_read_rsp_data_i", 256, None),
        ("h-appup", B + ".app_upstream_fault_i", 1, 0),
        # The app side's verdict on the descriptor presented to it.  It is
        # required to be "legal" only while a request is presented; see
        # joint-env-p.  (The hypothesis sits here, and not on
        # policy_fault_now, because that signal is computed and consumed
        # inside one procedural block, where an override has no effect.)
        ("h-legal", AP + ".request_descriptor_legal", 1, None),
    ]


def state_rtl_paths():
    """id -> the signal as a Verilog expression inside the probe, for a
    simulator.  The same signals as state_signals(), with RTL element
    numbers: a one-bit array element a-done5 is slot_done_q[5] here, and the
    array of six committed prefixes is spelled out with element 0 first, the
    order in which the translation lays it out."""
    out = {}
    one_bit = {"a-epoch": "slot_epoch_q", "a-reject": "slot_reject_q",
               "a-done": "slot_done_q", "a-sfault": "slot_fault_q"}
    for sid, path, width, _ in state_signals():
        stem, num = sid.rstrip("0123456789"), sid[len(sid.rstrip("0123456789")):]
        if stem in one_bit and num:
            out[sid] = "%s.%s[%s]" % (AP, one_bit[stem], num)
        elif sid == "k-committed-prefix-q":
            out[sid] = "{%s}" % ", ".join("%s.committed_prefix_q[%d]" % (KV, i)
                                          for i in range(6))
        else:
            out[sid] = path
    return out

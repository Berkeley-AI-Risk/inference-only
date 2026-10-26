"""Source-bound projection of the production guard/atomic-KV integration.

Retains the two complete controllers and the actual core reset/reply gates.
Arithmetic, attention scheduling and other fault producers are unrestricted
private inputs. The real attention input *connections* are checked here; its
arithmetic/state machine is not elaborated by this projection.
"""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import hashlib
import json
from pathlib import Path
import re

TOP = "kv_parent_composition"
PROJECT = "variants/kv-protected/hardware/project/"
BASE = "fpga/token_only_model0_ddr_board1/"
PATHS = {
    "shared": "shared_token_probe.sv",
    "core": BASE + "context2048_token_machine2/rtl/board1_context2048_token_machine_core.sv",
    "shell": BASE + "context2048_token_machine2/rtl/board1_context2048_token_shell.sv",
    "layer": BASE + "context2048_token_machine0/rtl/board1_context2048_semantic_layer.sv",
    "datapath": BASE + "context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv",
    "attention": BASE + "context2048_token_machine0/rtl/board1_context2048_attention.sv",
    "atomic": BASE + "context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv",
    "mapper": "mapper_portable.sv",
    "guard": "kv_integrity_guard.sv",
    "page_hash": "kv_page_hash.sv",
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def ports(source):
    # Strict parser for these pinned ANSI headers, not a general SV parser.
    header = source[:source.index("\n);")]
    header = header[header.index("module "):]
    header = header[header.index("input "):]
    header = re.sub(r"//[^\n]*", "", header)
    out = {}
    for part in header.split(","):
        match = re.fullmatch(r"\s*(input|output)\s+(?:wire|logic)\s*(signed\s+)?(\[[^\]]+\]\s*)?(\w+)\s*", part)
        if match:
            direction, signed, shape, name = match.groups()
        else:
            assert out and re.fullmatch(r"\s*\w+\s*", part), part
            name = part.strip()
        assert name not in out
        out[name] = (direction, ((signed or "") + (shape or "")).replace("ADDR_W", "19"))
    return out


def instance(source, module, name):
    match = re.search(r"^    " + re.escape(module) + r"\b", source, re.M)
    assert match, (module, name)
    start = match.start()
    match = re.search(r"\b" + re.escape(name) + r"\s*\(", source[start:])
    assert match
    opening = start + match.end() - 1
    cursor, depth = opening + 1, 1
    while depth:
        depth += (source[cursor] == "(") - (source[cursor] == ")")
        cursor += 1
    assert source[cursor] == ";"
    body = re.sub(r"//[^\n]*", "", source[opening+1:cursor-1])
    matches = list(re.finditer(r"\.(\w+)\s*\(([^()]*)\)", body))
    assert re.sub(r"[\s,]", "", re.sub(r"\.(\w+)\s*\(([^()]*)\)", "", body)) == ""
    bindings = {m[1]: re.sub(r"\s+", " ", m[2]).strip() for m in matches}
    assert len(bindings) == len(matches)
    return source[start:cursor+1], bindings


def rename(text, mapping):
    return re.sub(r"\b[A-Za-z_]\w*\b", lambda m: mapping.get(m[0], m[0]), text)


def expression(text, mapping):
    # Parentheses preserve the precedence of expressions substituted for ports.
    return rename(text, {k: v if re.fullmatch(r"\w+", v) else "(" + v + ")" for k, v in mapping.items()})


def fragment(source, first, last):
    assert source.count(first) == source.count(last) == 1
    return source[source.index(first):source.index(last)]


def add_taps(source, taps):
    assert source.count("\nendmodule") == 1
    extra = "".join(",\n    output wire " + shape + "f_parent_" + name + "_o" for name, (shape, _) in taps.items())
    result = source.replace("\n);", extra + "\n);", 1)
    return result.replace("\nendmodule", "\n" + "\n".join(
        "    assign f_parent_" + name + "_o = " + expr + ";" for name, (_, expr) in taps.items()) + "\nendmodule")


GUARD_TAPS = {name: (shape, name) for name, shape in {
    "state_q": "[4:0] ", "owner_q": "[1:0] ", "epoch_q": "[63:0] ",
    "aborted_q": "", "cache_valid_q": "", "cache_epoch_q": "[63:0] ",
    "f_verified": "", "layer_q": "[2:0] ", "position_q": "[11:0] ",
    "head_q": "", "row_word_q": "[3:0] ", "terminal_now": "",
    "read_fire": "", "write_fire": "", "clear_seen_q": "",
    "f_stage_request": "", "f_stage_request_epoch": "[63:0] ",
    "f_stage_request_layer": "[2:0] ", "f_stage_request_position": "[11:0] ",
    "f_stage_request_head": "", "f_stage_request_word": "[3:0] ",
}.items()}
GUARD_TAPS["prefixes"] = ("[71:0] ", "{prefix_q[5],prefix_q[4],prefix_q[3],prefix_q[2],prefix_q[1],prefix_q[0]}")
ATOMIC_TAPS = {name: (shape, name) for name, shape in {
    "state_q": "[3:0] ", "read_word_q": "[3:0] ", "read_aborted_q": "",
    "write_aborted_q": "", "pending_persisted_q": "", "pending_layer_q": "[2:0] ",
    "pending_position_q": "[11:0] ", "response_position_q": "[11:0] ",
    "response_head_q": "", "response_kind_q": "[1:0] ",
    "response_from_pending_q": "", "terminal_fault_event": "", "fault_q": "",
    "response_fault_q": "",
    "f_read_piece": "", "f_read_begin": "", "f_read_mask": "[8:0] ",
    "f_required_read_mask": "[8:0] ", "f_stage_filled": "",
    "f_completed_writes": "[4:0] ", "f_read_expected": "[2063:0] ",
    "kv_read_rsp_data_i": "[255:0] ",
    "f_read_bitmask": "[2063:0] ", "f_attention": "", "f_attention_owned": "",
    "attention_layer_i": "[2:0] ", "attention_position_i": "[11:0] ",
    "attention_kv_head_i": "[1:0] ", "attention_req_kind_i": "[1:0] ",
    "f_key_exponents": "[15:0] ", "f_value_exponents": "[15:0] ",
    "write_word_q": "[3:0] ", "write_head_q": "",
    "kv_write_req_valid_o": "", "kv_write_req_data_o": "[255:0] ",
}.items()}


def derive(package, prior, here, mutation=None):
    manifest_raw = (package / "MANIFEST.json").read_bytes()
    manifest = json.loads(manifest_raw)["files"]
    source, files, origins = {}, {}, {}
    for key, relative in PATHS.items():
        name = PROJECT + relative
        raw = (package / name).read_bytes()
        assert sha(raw) == manifest[name]["sha256"] and len(raw) == manifest[name]["bytes"]
        source[key] = raw.decode()
        files["production-" + key + ".sv"] = raw
        origins[key] = {"package_source": name, "sha256": sha(raw)}
    previous = json.loads((prior / "INPUTS.json").read_bytes())
    finished = json.loads((prior / "FINISHED.json").read_bytes())
    assert finished["production_proof"] and finished["assertions"] == previous["assertions"] == 221
    assert finished["inputs_sha256"] == sha((prior / "INPUTS.json").read_bytes())
    assert previous["manifest_sha256"] == sha(manifest_raw) and previous["mutation"] is None
    selected = ["guard.sv", "page_hash.sv", "compress_boundary.sv"] + [
        name for name in previous["files"] if name.endswith("monitor.inc.sv")]
    for name in selected:
        raw = (prior / name).read_bytes()
        assert sha(raw) == previous["files"][name]["sha256"]
        files[name] = raw
    assert (prior / "production.sv").read_text() == source["guard"]
    assert (prior / "production-page-hash.sv").read_text() == source["page_hash"]
    files["guard.sv"] = add_taps(files["guard.sv"].decode(), GUARD_TAPS).encode()
    epoch_path = "formal/kv-epoch/epoch_monitor.inc.sv"
    epoch = (package / epoch_path).read_bytes()
    assert sha(epoch) == manifest[epoch_path]["sha256"] and epoch.count(b"assert(") == 59
    files["epoch_monitor.inc.sv"] = epoch
    atomic = add_taps(source["atomic"], ATOMIC_TAPS)
    files["atomic.sv"] = ("`undef FORMAL\n" + atomic.replace("\nendmodule", "\n" + epoch.decode() + "\nendmodule")).encode()
    files["mapper.sv"] = ("`undef FORMAL\n" + source["mapper"]).encode()

    # Compose each typed-KV port through the actual instance bindings. The
    # only non-identity middle-stage expression is the private fault OR.
    _, shared_core = instance(source["shared"], "board1_context2048_token_machine_core", "u_machine")
    _, core_layer = instance(source["core"], "board1_context2048_semantic_layer", "u_six_layers")
    _, layer_dp = instance(source["layer"], "board1_context2048_semantic_datapath", "u_datapath")
    _, dp_cache = instance(source["datapath"], "board1_context2048_atomic_kv_typed", "u_kv_cache")
    _, dp_attention = instance(source["datapath"], "board1_context2048_attention", "u_attention")
    guard_raw, shared_guard = instance(source["shared"], "board1_kv_integrity_guard", "u_kv_integrity")
    _, core_shell = instance(source["core"], "board1_context2048_token_shell", "u_token_shell")
    assert core_shell["clear_i"] == "clear_i && machine_active"
    assert core_shell["private_layer_clear_o"] == "layer_clear"
    assert re.findall(r"\bprivate_layer_clear_o\s*=(?!=)\s*([^;]*);", source["shell"]) == ["clear_i"]
    core_map = {key: val for key, val in shared_core.items() if key.startswith("kv_")}
    core_map.update({"clk": "core_clk_i", "reset_n": "reset_n_i",
                     "model_locked_i": "model_lock_core_sync_q",
                     "upstream_fail_closed_i": "(" + shared_core["upstream_fail_closed_i"] + ")"})
    layer_map = {p: expression(e, core_map) for p, e in core_layer.items()}
    dp_map = {p: expression(e, layer_map) for p, e in layer_dp.items()}
    # Private datapath state and schedule outputs are unconstrained, but
    # repeated uses remain the SAME signal (including layer/position).
    cache_bindings = {p: expression(e, dp_map) for p, e in dp_cache.items()}
    assert set(cache_bindings) == set(ports(source["atomic"]))
    assert set(shared_guard) == set(ports(source["guard"]))
    connection_pairs = {
        "private_cache_response_valid_i": "attention_rsp_valid_o",
        "private_cache_response_ready_o": "attention_rsp_ready_i",
        "private_cache_response_key_vector_i": "attention_rsp_key_vector_o",
        "private_cache_response_key_exponent_i": "attention_rsp_key_exponent_o",
        "private_cache_response_value_vector_i": "attention_rsp_value_vector_o",
        "private_cache_response_value_exponent_i": "attention_rsp_value_exponent_o",
        "private_cache_response_fault_i": "attention_rsp_fault_o",
        "private_cache_request_valid_o": "attention_req_valid_i",
        "private_cache_request_kind_o": "attention_req_kind_i",
        "private_cache_request_ready_i": "attention_req_ready_o",
    }
    for att, kv in connection_pairs.items():
        assert dp_attention[att] == dp_cache[kv]
    assert dp_cache["attention_position_i"] == "{1'b0, " + dp_attention["private_cache_request_position_o"] + "}"
    assert dp_cache["attention_kv_head_i"] == "{1'b0, " + dp_attention["private_cache_request_kv_head_o"] + "}"
    for att, kv in (("rst_n", "reset_n"), ("clk", "clk"), ("clear_i", "clear_i"),
                    ("model_lock_i", "model_locked_i"), ("upstream_fault_i", "upstream_fault_i")):
        assert dp_attention[att] == dp_cache[kv]

    core_fragments = [
        fragment(source["core"], "    logic [1:0] machine_release_q;", "    wire shell_append_ready;"),
        fragment(source["core"], "    wire root_terminal =", "    // Only private request/reply handshakes"),
        fragment(source["core"], "    always_ff @(posedge clk or negedge reset_n) begin", "    board1_context2048_token_shell #("),
    ]
    controls = "\n".join(rename(s, core_map) for s in core_fragments)
    shared_control = fragment(source["shared"], "    always_ff @(posedge core_clk_i or negedge reset_n_i) begin", "    // Actual sealed-page service.")
    controls += "\n" + shared_control
    # This equation is derived through the checked shell input/output chain.
    controls += "\n    wire layer_clear = clear_i && machine_active;\n"
    if mutation == "lost-clear":
        controls = controls.replace("wire layer_clear = clear_i && machine_active;", "wire layer_clear = 1'b0;")
    assert mutation in (None, "lost-clear", "raw-read-bypass")
    if mutation == "raw-read-bypass":
        cache_bindings["kv_read_rsp_data_i"] = "guard_rd_data"

    inputs = {"core_clk_i": "", "reset_n_i": "", "clear_i": "",
              "private_model_locked_i": "", "boundary_core_fault": "", "auth_fault": "",
              "model_cdc_core_fault": "", "core_machine_fault": "", "arbiter_fail": "",
              "shell_terminal_latched": "", "sequence_fault": "", "service_start_collision_q": "", "fault_q": "",
              "current_layer_q": "[2:0] ", "current_position_q": "[10:0] ",
              "key_exponent_q": "[7:0] ", "value_exponent_q": "[7:0] ",
              "input_index_q": "[9:0] ", "key_ram_read_data": "[15:0] ", "value_ram_read_data": "[15:0] ",
              "attention_cache_req_position": "[10:0] ", "attention_cache_req_head": ""}
    wires = {"model_lock_core_meta_q": "", "model_lock_core_sync_q": "", "core_fault_to_boundary_q": ""}
    declarations = "\n".join("    logic " + shape + name + ";" for name, shape in wires.items())
    # The exact gate fragment above declares these wires itself.
    declared = set(re.findall(r"\b(?:wire|logic)\s+(?:\[[^\]]+\]\s*)?(\w+)", controls)) | set(wires)
    declared |= set(re.findall(r",\s*(child_kv_\w+)\s*;", controls))
    def connection_ports(table, bindings, boundary):
        for port, (direction, shape) in table.items():
            value = bindings[port]
            if not value or not re.fullmatch(r"\w+", value) or value in declared or value in inputs:
                continue
            # Inputs on the far DDR boundary and on the upstream private
            # stage/attention boundary are free, never assumptions.
            is_input = direction == "input" and boundary(port)
            if is_input:
                inputs[value] = shape
            else:
                wires[value] = shape
            declared.add(value)
    connection_ports(ports(source["guard"]), shared_guard, lambda p: p.startswith("m_"))
    connection_ports(ports(source["atomic"]), cache_bindings, lambda p: not p.startswith("kv_"))
    # Remove initial logic declarations already emitted above.
    declarations += "\n" + "\n".join("    wire " + shape + name + ";" for name, shape in wires.items()
        if name not in ("model_lock_core_meta_q", "model_lock_core_sync_q", "core_fault_to_boundary_q"))
    def tapped_instance(module, name, bindings, taps, prefix):
        nonlocal declarations
        declarations += "\n" + "\n".join("    wire " + shape + prefix + key + ";" for key, (shape, _) in taps.items())
        bindings = dict(bindings, **{"f_parent_" + key + "_o": prefix + key for key in taps})
        return "    " + module + " " + name + " (\n" + ",\n".join("        ." + p + "(" + e + ")" for p, e in bindings.items()) + "\n    );\n"
    instances = tapped_instance("board1_kv_integrity_guard", "u_guard", shared_guard, GUARD_TAPS, "g_")
    instances += tapped_instance("board1_context2048_atomic_kv_typed", "u_atomic", cache_bindings, ATOMIC_TAPS, "a_")
    monitor = (here / "parent_monitor.inc.sv").read_text()
    files["parent_monitor.inc.sv"] = monitor.encode()
    files["parent.sv"] = ("`default_nettype none\nmodule " + TOP + " (\n" + ",\n".join(
        "    input wire " + shape + name for name, shape in inputs.items()) + "\n);\n" + declarations +
        "\n" + controls + "\n" + instances + "\n" + monitor + "\nendmodule\n`default_nettype wire\n").encode()
    binding = {"manifest_sha256": sha(manifest_raw), "source_origins": origins,
               "previous_guard_inputs_sha256": sha((prior / "INPUTS.json").read_bytes()),
               "previous_guard_finished_sha256": sha((prior / "FINISHED.json").read_bytes()),
               "guard_bindings": shared_guard, "atomic_bindings": cache_bindings,
               "attention_input_connection_pairs": connection_pairs,
               "parent_private_boundary_inputs": inputs, "mutation": mutation,
               "guard_taps": GUARD_TAPS, "atomic_taps": ATOMIC_TAPS,
               "clear_projection": "layer_clear = public clear_i && machine_active; child_reset_n = reset_n_i && machine_active",
               "attention_implementation_elaborated": False, "whole_model_arithmetic_elaborated": False}
    return files, binding

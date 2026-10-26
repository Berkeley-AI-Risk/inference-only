"""Full attention controller/aligner with explicit arithmetic-child boundaries."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import importlib.util
import json
from pathlib import Path
import re


def helper(here):
    spec = importlib.util.spec_from_file_location("attention_parent_helpers", here / "parent_model.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ABSTRACT = (
    "board1_unified_projection_head_dynamic_mul_exact",
    "board1_context2048_attention_vector256x16", "board1_context2048_attention_vector256x18",
    "board1_context2048_attention_workspace3x18", "board1_fixed_attention_rne_shift_iterative",
    "board1_fixed_attention_exp_lut_sync", "board1_fixed_attention_rne_div_signed64",
)
TOP = "board1_context2048_attention"


def derive(package, here):
    model = helper(here)
    manifest = json.loads((package / "MANIFEST.json").read_bytes())["files"]
    path = model.PROJECT + model.PATHS["attention"]
    production = (package / path).read_bytes()
    assert model.sha(production) == manifest[path]["sha256"]
    files = {"production-attention.sv": production}
    origins = {path: model.sha(production)}
    modules = {}
    for name in manifest:
        if name.startswith(model.PROJECT) and name.endswith(".sv"):
            raw = (package / name).read_bytes()
            for module in ABSTRACT:
                matches = list(re.finditer(r"\bmodule\s+" + module + r"\b[\s\S]*?\bendmodule\b", raw.decode()))
                if matches:
                    assert len(matches) == 1 and module not in modules
                    assert model.sha(raw) == manifest[name]["sha256"]
                    origins[name] = model.sha(raw)
                    modules[module] = matches[0][0]
                    files["production-child-" + module + ".sv"] = raw
    assert set(modules) == set(ABSTRACT)
    boundaries = {}
    for module, source in modules.items():
        # Preserve the exact declared parameter/port header. Replace only
        # this complete child implementation with arbitrary output replies.
        header = source[:source.index("\n);") + 3]
        declared = model.ports(header)
        lines, outputs = [], {}
        for name, (direction, shape) in declared.items():
            if direction == "output":
                lines += ["    (* anyseq *) reg " + shape + "f_arbitrary_" + name + ";",
                          "    assign " + name + " = f_arbitrary_" + name + ";"]
                outputs[name] = shape
        files["boundary-" + module + ".sv"] = (header + "\n" + "\n".join(lines) + "\nendmodule\n").encode()
        boundaries[module] = outputs
    monitor = (here / "attention_monitor.inc.sv").read_bytes()
    assert b"assume(" not in monitor
    files["attention_monitor.inc.sv"] = monitor
    # Expose the real aligner input pins as read-only observation taps. The
    # original input expressions and the complete aligner logic are retained.
    instrumented = production.decode()
    child = re.search(r"module board1_fixed_attention_align8\b[\s\S]*?\bendmodule", instrumented)[0]
    taps = {"request_vector_i": ("[127:0] ", "request_vector_i"),
            "request_shift_i": ("[8:0] ", "request_shift_i")}
    instrumented = instrumented.replace(child, model.add_taps(child, taps))
    instances = re.findall(r"    board1_fixed_attention_align8 u_align8 \([\s\S]*?\n    \);", instrumented)
    assert len(instances) == 1
    instance = instances[0]
    extended = instance[:-2] + ",\n        .f_parent_request_vector_i_o(f_att_aligner_vector),\n        .f_parent_request_shift_i_o(f_att_aligner_shift)\n    );"
    instrumented = instrumented.replace(instance,
        "    wire [127:0] f_att_aligner_vector;\n    wire [8:0] f_att_aligner_shift;\n" + extended)
    files["attention.sv"] = b"`undef FORMAL\n" + instrumented.encode().replace(b"\nendmodule", b"\n" + monitor + b"\nendmodule", 1)
    return files, {"source_origins": origins, "abstract_children": boundaries,
        "attention_controller_retained": True, "eight_lane_value_aligner_retained": True,
        "norm_candidate_stage_retained": True, "timeout_reduced": False,
        "scope": "Actual attention controller, capture, score prefetch and value-align data path; other child outputs arbitrary. Not full numerical attention correctness or guard composition."}

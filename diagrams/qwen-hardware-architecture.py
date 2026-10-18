#!/usr/bin/env python3
"""Render the released Qwen circuit in the SimpleStories diagram's visual style.

Regenerates the accompanying SVG, PNG and checked source inventory.
Requires matplotlib. Run from any directory with Python 3.8 or newer.
The public frozen-source manifest and routed resource report are checked before
rendering. Functional labels come from inspected RTL, not old candidate comments.
DSP counts are hardware resources, not a count of independently usable lanes.
"""
from pathlib import Path
import hashlib
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

ROOT = Path(__file__).resolve().parents[1]
STEM = Path(__file__).resolve().with_suffix("")
RELEASE = ROOT / "demos/qwen3-1.7b"
CHECKPOINT = "11d8d9997e6b032f6cd208ac63de03c13a969957fecfcb18d98b2051c03b0b2e"
SOURCE_MANIFEST = "adf4303dd3020ecff692b75db92bd2117d041c08eb521efacbb4e66505d469d6"


def inventory():
    selected = json.loads((RELEASE / "SOURCE-INPUTS.json").read_text())
    deployment = json.loads((RELEASE / "deployment.json").read_text())
    assert selected["source_bundle_manifest_sha256"] == SOURCE_MANIFEST
    assert deployment["routed_checkpoint_sha256"] == CHECKPOINT
    assert deployment["core_clock_mhz"] == 62.5
    checked = {}
    # Bind all released design files, including the fixed tables, not only the
    # handful whose names appear as illustrative labels in the drawing.
    for name, expected in selected["source_files"].items():
        if not name.startswith("hardware/design/"):
            continue
        raw = (RELEASE / name).read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        assert len(raw) == expected["bytes"] and digest == expected["sha256"], name
        checked[name] = digest
    assert len(checked) > 50

    reports_dir = RELEASE / "evidence/implementation"
    report_name = "utilization-hierarchical.rpt"
    raw = (reports_dir / report_name).read_bytes()
    expected = json.loads((reports_dir / "REPORTS.json").read_text())["reports"][report_name]["public"]
    report_hash = hashlib.sha256(raw).hexdigest()
    assert len(raw) == expected["bytes"] and report_hash == expected["sha256"]
    rows = []
    for line in raw.decode().splitlines():
        if not line.startswith("|"):
            continue
        cells = [part.strip() for part in line.split("|")[1:-1]]
        if len(cells) == 13 and cells[-1].isdigit():
            rows.append(cells)

    def resource(instance, module, column=-1):
        matches = [r for r in rows if r[0] == instance and
                   (r[1] == module or r[1].startswith(module + "__"))]
        assert len(matches) == 1, (instance, module, len(matches))
        return int(matches[0][column])

    dsps = {name: resource(name, module) for name, module in (
        ("projection", "qwen_projection_engine"),
        ("attention", "qwen_attention_layer"),
        ("norm", "qwen_rms_norm"),
        ("rotary", "qwen_rotary_head"),
        ("elementwise", "qwen_bf16_elementwise"))}
    assert dsps == {"projection": 648, "attention": 336, "norm": 6,
                    "rotary": 8, "elementwise": 2}, dsps
    assert sum(dsps.values()) == resource("fixed_machine", "qwen_aws_host_machine") == 1000
    for bank in ("tile_short", "tile_long"):
        assert resource(bank, "qwen_projection_tile32") == 324
    attention = {}
    for head in range(2):
        for part, module, count in (("qk", "qwen_qk_dot128", 34),
                                     ("softmax", "qwen_softmax", 6),
                                     ("av", "qwen_av_stream16", 128)):
            instance = "heads[{}].{}".format(head, part)
            attention[instance] = resource(instance, module)
            assert attention[instance] == count
    assert sum(attention.values()) == dsps["attention"]
    assert resource("verifier", "qwen_model_page_auth_parallel_shared", -2) == 128
    assert resource("model_reader", "qwen_model_reader", -2) == 288

    # Check central elaboration facts directly as well as mapped resource sums.
    def rtl(name):
        return (RELEASE / "hardware/design" / name).read_text()

    projection = rtl("qwen_projection_engine.sv")
    assert ".GROUPS(256)) tile_short" in projection
    assert ".GROUPS(768)) tile_long" in projection
    assert "long_vector=kind==6" in projection
    assert "!long_vector" in projection and "&& long_vector" in projection
    assert "row<32" in rtl("qwen_projection_tile32.sv")
    assert "lane<16" in rtl("qwen_qk_dot128.sv")
    assert ".LANES(64)" in rtl("qwen_attention_pair.sv")
    assert "ATTENTION_CORES=1" in rtl("qwen_fixed_core.sv")
    assert ".WORKERS(4),.SLOTS(8)" in rtl("qwen_model_reader.sv")
    assert ".WEIGHT_PAGES(64),.AUTH_SLOTS(32)" in rtl("qwen_model_verified_machine.sv")
    assert "AUX_PAGES=8" in rtl("qwen_model_reader.sv")
    assert ".MODEL_PREFETCH_PAGES(32)" in rtl("cl_qwen.sv")
    assert "qwen_kv_plain_store #" in rtl("qwen_verified_machine.sv")

    result = {
        "scope": "Diagram of the released A0 Qwen3-1.7B baseline.",
        "source_repository": "https://github.com/Berkeley-AI-Risk/inference-only",
        "source_bundle_manifest_sha256": SOURCE_MANIFEST,
        "routed_checkpoint_sha256": CHECKPOINT,
        "model_sha256": deployment["model_sha256"],
        "model_bytes": deployment["model_bytes"],
        "clocks_mhz": {"inference": 62.5, "memory": 125, "host": 250},
        "report": "evidence/implementation/" + report_name,
        "report_sha256": report_hash,
        "dsp_blocks_by_disjoint_subsystem": dsps,
        "total_mapped_dsp48e2": sum(dsps.values()),
        "attention_dsp_blocks": attention,
        "projection": {"physical_banks": 2, "simultaneously_selected_banks": 1,
                       "rows_per_bank": 32, "products_per_row_per_accepted_beat": 8,
                       "useful_products_per_accepted_beat": 256,
                       "dsp_blocks_per_bank_including_rescaling": 324,
                       "weight_bits": 8, "activation_code_bits": 16,
                       "accumulator_bits": 40},
        "verification": {"workers": 4, "page_bytes": 65536, "slots_per_worker": 8,
                         "verifier_uram_blocks": 128, "verified_cache_pages": 72,
                         "verified_cache_bytes": 72 * 65536, "cache_uram_blocks": 160},
        "limitations": [
            "The application commands are APPEND, STEP and CLEAR; the engineering image also exposes status and a 16-bit attention-control diagnostic.",
            "The released baseline does not authenticate K/V or encrypt weights.",
            "Private refers to circuit-controlled interfaces, not physical secrecy of external HBM.",
            "32,768 is the design tape capacity, not a full-context hardware qualification result.",
            "DSP blocks are not equivalent to independent multipliers or accessible training throughput; some implement additions and floating-point functions use several blocks.",
            "The frozen-circuit interpretation excludes the cloud host and AWS reconfiguration/management plane.",
            "The drawing summarizes functional paths, not every net, physical placement, a timing proof or a tamper-resistance proof."
        ],
        "checked_design_files": checked,
    }
    STEM.with_suffix(".inventory.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def draw(data):
    W, H = 3600, 3100
    plt.rcParams.update({"font.family": "DejaVu Sans", "svg.fonttype": "none", "svg.hashsalt": "qwen-architecture-v1"})
    fig = plt.figure(figsize=(36, 31), facecolor="white")
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(H, 0)
    ax.axis("off")
    colors = {
        "ink": "#172f46", "muted": "#52687a", "border": "#b5c3ce",
        "panel": "#f7f9fc", "control": "#8155a4", "controlfill": "#f1ebf7",
        "model": "#2867aa", "modelfill": "#e9f1fc",
        "data": "#137c75", "datafill": "#e7f5f1",
        "kv": "#c57516", "kvfill": "#fff3df",
        "dynamic": "#ac3562", "dynamicfill": "#fcebf2",
        "gray": "#738493", "grayfill": "#eef2f5",
    }
    boxed_text = []

    def text(x, y, value, size=21, kind="ink", bold=False, ha="left", **kwargs):
        return ax.text(x, y, value, fontsize=size * .72, color=colors.get(kind, kind),
                       weight="bold" if bold else "normal", ha=ha, va="top",
                       linespacing=1.32, **kwargs)

    def rect(x, y, w, h, fill="white", stroke="border", lw=1.6, radius=15):
        item = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0,rounding_size={}".format(radius),
                             facecolor=colors.get(fill, fill), edgecolor=colors.get(stroke, stroke),
                             linewidth=lw, zorder=2)
        ax.add_patch(item)

    def box(x, y, w, h, title, body="", kind="gray", title_size=23, body_size=21, rtl=None):
        rect(x, y, w, h, kind + "fill", kind)
        items = [text(x + 22, y + 18, title, title_size, bold=True)]
        if body:
            items.append(text(x + 22, y + 60, body, body_size))
        if rtl:
            items.append(text(x + 22, y + h - 24, rtl, 16, "muted"))
        boxed_text.append((title, x, y, w, h, items))

    def line(points, kind="gray", both=False, arrow=True, dashed=False, width=3):
        xs, ys = zip(*points)
        ax.add_line(Line2D(xs, ys, color=colors[kind], linewidth=width,
                           linestyle=(0, (7, 5)) if dashed else "solid", zorder=2.5))
        if arrow:
            ax.add_patch(FancyArrowPatch(points[-2], points[-1], arrowstyle="-|>",
                                        mutation_scale=17, color=colors[kind], lw=width, zorder=2.6))
        if both:
            ax.add_patch(FancyArrowPatch(points[1], points[0], arrowstyle="-|>",
                                        mutation_scale=17, color=colors[kind], lw=width, zorder=2.6))

    def label(x, y, value, kind="muted", size=18, ha="left"):
        text(x, y, value, size, kind, ha=ha, zorder=4,
             bbox={"facecolor": "white", "edgecolor": "none", "pad": 2, "alpha": .97})

    text(60, 40, "Inside a fixed-model inference chip", 47, bold=True)
    text(60, 108, "Qwen3-1.7B  •  released AWS F2 baseline  •  same visual conventions as the SimpleStories diagram", 25, "muted")
    rect(60, 165, 3480, 126, "#f4f7fb", "#c4d0dc")
    text(88, 182, "1,000 mapped DSP blocks = 648 projection + 336 attention + 16 normalization / rotary / elementwise", 28, bold=True)
    text(88, 235, "DSP blocks are FPGA arithmetic resources, not 1,000 independent multiplier lanes or an estimate of accessible training throughput.", 21, "muted")

    rect(50, 335, 1510, 2310, "panel", radius=18)
    rect(1620, 335, 1930, 2310, "panel", radius=18)
    text(80, 360, "1  Follow the data through the chip", 30, bold=True)
    text(1650, 360, "2  Expand the arithmetic hardware", 30, bold=True)

    box(110, 440, 1380, 115, "Host computer + AWS shell", "Tokenization and display; token commands and replies; fixed-model upload at startup.", body_size=23)
    rect(85, 620, 1440, 1795, "white", "#7c96af", lw=2)
    text(110, 638, "FIXED CIRCUIT", 21, "muted", bold=True)
    text(560, 638, "Frozen configuration assumed", 21, "muted")
    box(130, 710, 680, 170, "PCIe token-command registers", "APPEND, STEP, CLEAR + status replies.\nAlso: 16-bit attention-control diagnostic.\nNo tensor / arbitrary-memory command.", "control", body_size=21, rtl="qwen_ocl_control → token-command clock crossing")
    box(960, 710, 520, 190, "Restricted startup controller", "Loads the fixed model into HBM;\nchecks the fixed image digest.\nDoes not authorize arbitrary weights.", "control", title_size=22, body_size=21, rtl="qwen_pcis_model_hbm_boot")
    box(150, 1010, 1280, 155, "Token tape + fixed 28-layer sequencer", "Owns operation order, layer, token position and internal tensor selection.\nEmbedding → 28 transformer layers → final normalization → vocabulary head → greedy token.", "control", body_size=21, rtl="fixed_qwen_sequencer / qwen_token_machine")
    box(340, 1260, 940, 155, "Shared arithmetic + private working memory", "BF16 activations and K/V; specified FP32 work inside the engine.\nPrivate tensor RAM; no host-visible intermediate-result port.", "data", body_size=21, rtl="qwen_fixed_core + qwen_private_tensors; expanded at right →")
    box(150, 1500, 600, 190, "Verified model cache + prefetch", "64 weight + 8 auxiliary pages, 64 KiB each.\n4.5 MiB useful cache; 160 UltraRAM blocks.\nAddresses and prefetch are fixed-purpose.", "model", title_size=22, body_size=20, rtl="qwen_model_reader; 32-page prefetch window")
    box(150, 1790, 600, 190, "4 parallel verification workers", "Copy → SHA-256 check → checked cache.\n32 retained 64 KiB page slots in total.\nFixed root table; no secret auth key.", "model", title_size=22, body_size=21, rtl="shared verifier; 128 UltraRAM blocks for payloads")
    box(920, 1500, 560, 230, "Private attention-cache controller", "Stores and fetches computed BF16 K/V.\nOwns addresses, staging and valid prefix.\nExternal K/V has NO integrity check\nin this released baseline.", "kv", title_size=21, body_size=21, rtl="qwen_kv_plain_store / reader / writer")
    box(150, 2070, 600, 145, "Model clock crossing + transport", "Eight 256-bit HBM read ports\nassemble one 2,048-bit internal beat.", "model", title_size=21, body_size=21, rtl="qwen_model_hbm_cdc_reader")
    box(920, 2070, 560, 145, "K/V clock crossing + transport", "Fixed read / write ownership.\nTransfers and cancellation are internal.", "kv", title_size=21, body_size=21, rtl="qwen_kv_hbm_cdc_transport")
    box(150, 2290, 1330, 100, "Fixed HBM port ownership + vendor memory controller", "Model: ports 0–7. K/V payload: 8–15. Retained ports 16–23 are unused by this plain-K/V schedule.", title_size=22, body_size=19)
    box(150, 2490, 1330, 110, "External HBM — separate model and attention-cache regions", "2.354 GB fixed model image, including tables/scales; mutable BF16 K/V. Neither is encrypted.", title_size=23, body_size=21)

    line([(450, 555), (450, 710)], both=True)
    label(470, 578, "PCIe / AXI-Lite control", size=18)
    line([(1210, 555), (1210, 710)])
    label(1230, 578, "restricted PCIe upload", size=18)
    line([(450, 880), (450, 1010)], "control", both=True, dashed=True)
    label(470, 940, "validated token commands / replies", "control", 18)
    line([(750, 1165), (750, 1260)], "control", both=True, dashed=True)
    label(775, 1200, "fixed operation / completion", "control", 18)
    line([(450, 1415), (450, 1500)], "model", both=True)
    label(160, 1445, "requests / verified 2,048-bit replies", "model", 18)
    line([(1150, 1415), (1150, 1500)], "kv", both=True)
    label(1030, 1445, "computed K/V", "kv", 18)
    line([(450, 1690), (450, 1790)], "model", both=True)
    label(470, 1728, "page identity / checked bytes", "model", 17)
    line([(450, 1980), (450, 2070)], "model", both=True)
    label(470, 2010, "64 KiB page refill", "model", 18)
    line([(1190, 1730), (1190, 2070)], "kv", both=True)
    label(945, 1860, "private K/V transfers\n(no host-selected addresses)", "kv", 18)
    line([(450, 2215), (450, 2290)], "model", both=True)
    line([(1190, 2215), (1190, 2290)], "kv", both=True)
    line([(1480, 805), (1500, 805), (1500, 2260), (1390, 2260), (1390, 2290)], width=2)
    label(1255, 1930, "startup-only\nmodel writes", size=17)
    line([(815, 2390), (815, 2490)], both=True)
    label(840, 2425, "HBM controller / physical interface", size=18)

    # Two physical projection banks, but only the selected one accumulates.
    rect(1660, 440, 1850, 895, "white", "#a7bdd6")
    text(1690, 462, "648 DSP blocks  •  fixed-weight projection hardware", 27, "model", bold=True)
    text(1690, 509, "Used for Q/K/V, attention output, feed-forward projections and the tied vocabulary head.", 21)
    text(1690, 551, "A fixed selector chooses ONE bank per projection; these are not two concurrent matrix jobs.", 21, "control", bold=True)
    box(1730, 620, 780, 100, "Computed activation word", "128 bits = eight signed 16-bit activation codes.", "data", body_size=21)
    box(2640, 620, 780, 100, "Authenticated weight word", "2,048 bits = 32 rows × eight signed 8-bit weights.", "model", body_size=21)
    line([(2110, 720), (2110, 775), (3300, 775)], "data", arrow=False)
    line([(3020, 720), (3020, 790), (1810, 790)], "model", arrow=False)
    for idx, x in enumerate((1730, 2630)):
        rect(x, 835, 800, 285, "modelfill", "model")
        text(x + 400, 852, "{}-column bank  •  32 rows".format("2,048" if idx == 0 else "6,144"), 24, ha="center", bold=True)
        for row in range(32):
            cx = x + 28 + (row % 8) * 94
            cy = 908 + (row // 8) * 43
            rect(cx, cy, 84, 34, "white", "model", radius=5)
            text(cx + 42, cy + 5, "r{} ×8".format(row), 16, ha="center")
        text(x + 400, 1090, "Each box: 8 W8 × A16 products → 40-bit sum", 20, ha="center")
        line([(x + 110, 775), (x + 110, 835)], "data")
        line([(x + 650, 790), (x + 650, 835)], "model")
        line([(x + 400, 1120), (x + 400, 1165)], "data")
        box(x, 1165, 800, 115, "Shared row rescaling → BF16 output", "Integer sum × computed vector scale × authenticated row scale.", "model", title_size=23, body_size=20, rtl="324 mapped DSP blocks per bank, including accumulation and scaling")
    text(1690, 1300, "Useful projection work: 256 products per accepted beat, not 512; stalls and other stages reduce average throughput.", 20)

    # One GQA pair engine serves the eight K/V heads sequentially.
    rect(1660, 1380, 1850, 730, "white", "dynamic", lw=2)
    text(1690, 1405, "336 DSP blocks  •  internal attention", 27, "dynamic", bold=True)
    text(1690, 1452, "One pair engine: two query heads share one K/V head. Reused across all eight K/V heads, in every layer.", 21)
    text(1690, 1493, "Q and attention probabilities stay internal; K/V is fetched from the unprotected external cache.", 20, "muted")
    for head, y in enumerate((1580, 1830)):
        text(1730, y - 40, "Query head {} of the current pair".format(head), 21, "muted", bold=True)
        box(1730, y, 520, 170, "Q × K score", "16 FP32 product lanes,\neight chunks per 128-wide dot.\n34 DSP blocks including scaling.", "dynamic", body_size=21, rtl="qwen_qk_dot128")
        box(2310, y, 510, 170, "Private scores + softmax", "Score RAM; exponent / normalization.\nProduces attention probabilities.\n6 DSP blocks.", "data", title_size=22, body_size=20, rtl="qwen_softmax")
        box(2880, y, 550, 170, "Probability × V", "64 FP32 product lanes.\nTwo 64-value beats per position.\n128 DSP blocks.", "dynamic", body_size=21, rtl="qwen_av_stream16, LANES=64")
        line([(2250, y + 80), (2310, y + 80)], "data")
        line([(2820, y + 80), (2880, y + 80)], "data")
    text(1690, 2045, "Pink = runtime-operand arithmetic, not user-programmable arithmetic. Results return to private tensor memory.", 20)

    rect(1660, 2155, 1850, 440, "white", "gray")
    text(1690, 2178, "16 DSP blocks  •  other fixed-role arithmetic", 26, bold=True)
    box(1730, 2250, 520, 225, "RMS normalization  •  6 DSP", "Squares and normalizes activations;\napplies fixed model norm weights.\nShared across layer, Q/K-head\nand final normalization work.", "dynamic", title_size=22, body_size=21, rtl="qwen_rms_norm; 3 FP32 multiplier stages")
    box(2310, 2250, 510, 225, "Rotary position  •  8 DSP", "Combines pairs of activations\nwith authenticated sine/cosine\ntables for their token position.", "model", title_size=22, body_size=21, rtl="qwen_rotary_head; 4 FP32 multipliers")
    box(2880, 2250, 550, 225, "Elementwise  •  2 DSP", "Multiplies the feed-forward branches;\nalso performs residual additions.\nInputs and operation selection\ncome from the fixed controller.", "dynamic", title_size=22, body_size=21, rtl="qwen_bf16_elementwise; 1 FP32 multiplier")
    text(1690, 2515, "Also present: fixed SiLU tables, activation quantization, adders, dividers and greedy argmax; not all use DSP blocks.", 20)
    text(1690, 2555, "Floating-point multipliers may use multiple DSP blocks; integer adders can also map into DSP blocks.", 20, "muted")

    text(65, 2690, "How to read this diagram", 27, bold=True)
    legend = [("model", "Model weights / verified model-read path"),
              ("data", "Computed activations / results"),
              ("kv", "Cached attention keys and values"),
              ("control", "Controller commands / status")]
    for index, (kind, value) in enumerate(legend):
        x = 65 + index % 2 * 1750
        y = 2740 + index // 2 * 51
        line([(x, y + 10), (x + 100, y + 10)], kind, dashed=kind == "control")
        text(x + 125, y - 4, value, 22)
    text(65, 2860, "Clocks in this image: 62.5 MHz inference / 125 MHz memory / 250 MHz host. 28 layers; hidden size 2,048; 16 Q heads / 8 K/V heads; head width 128.", 21)
    text(65, 2905, "HBM = high-bandwidth memory. BF16 / FP32 = floating-point formats. Private = no ordinary host operand/address interface, not physical memory secrecy.", 20)
    text(65, 2950, "Scope: selected paths in the released baseline, not every wire or a physical layout. 32,768-token design capacity is not full-context hardware qualification.", 20, "muted")
    text(65, 2995, "The AWS host and configuration plane are outside the inference-only claim. Mapped resources and a schematic do not prove physical-tamper resistance.", 20, "muted")
    text(65, 3040, "Sources: released Qwen RTL + HARDWARE.md + routed utilization-hierarchical.rpt; checkpoint 11d8d999… . Full identities and resource checks: companion inventory JSON.", 19, "muted")

    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    for title, x, y, width, height, items in boxed_text:
        extents = []
        for item in items:
            bounds = item.get_window_extent(renderer).transformed(ax.transData.inverted())
            if bounds.x0 < x - 1 or bounds.x1 > x + width + 1 or bounds.y0 < y - 1 or bounds.y1 > y + height + 1:
                raise RuntimeError("Text overflow in {!r}: {!r}".format(title, item.get_text()))
            for prior in extents:
                if bounds.overlaps(prior):
                    raise RuntimeError("Overlapping text in {!r}".format(title))
            extents.append(bounds)
    for item in ax.texts:
        bounds = item.get_window_extent(renderer).transformed(ax.transData.inverted())
        if bounds.x0 < 0 or bounds.x1 > W or bounds.y0 < 0 or bounds.y1 > H:
            raise RuntimeError("Text outside canvas: " + item.get_text())

    title = "Qwen3-1.7B released hardware architecture"
    description = "Frozen A0 baseline; routed checkpoint " + CHECKPOINT
    fig.savefig(STEM.with_suffix(".svg"), format="svg", facecolor="white",
                metadata={"Title": title, "Description": description, "Date": None})
    fig.savefig(STEM.with_suffix(".png"), dpi=150, facecolor="white",
                metadata={"Title": title, "Source": description})
    plt.close(fig)
    print(json.dumps({"svg": STEM.with_suffix(".svg").name,
                      "png": STEM.with_suffix(".png").name,
                      "inventory": STEM.with_suffix(".inventory.json").name,
                      "mapped_dsp_blocks": data["total_mapped_dsp48e2"],
                      "useful_projection_products_per_accepted_beat": 256,
                      "checked_source_files": len(data["checked_design_files"]),
                      "boxed_text_checks": len(boxed_text)}))


if __name__ == "__main__":
    draw(inventory())

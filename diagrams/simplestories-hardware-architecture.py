#!/usr/bin/env python3
"""Render a source-checked, introductory diagram of the SimpleStories hardware.

Run from any directory: python3 simplestories-hardware-architecture.py
Requires matplotlib. Checks the recorded census against the public image and
implementation inventory; does not rerun synthesis or require private artifacts.
Public RTL: Berkeley-AI-Risk/inference-only, commit d784685f3a0a22c87e594702d4dd3c6090785d8d.
"""
from pathlib import Path
from collections import Counter
import hashlib
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle
from matplotlib.lines import Line2D

ROOT = Path(__file__).resolve().parents[1]
STEM = Path(__file__).resolve().with_suffix("")
EXPECTED_IMAGE = "6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09"
COMMIT = "d784685f3a0a22c87e594702d4dd3c6090785d8d"


def inventory():
    data = json.loads(STEM.with_suffix(".inventory.json").read_text())
    implementation = json.loads((ROOT / "evidence/baseline-current/implementation.json").read_text())
    build = json.loads((ROOT / "prebuilt/inference/BUILD.json").read_text())
    assert data["mapped_image_sha256"] == implementation["image_sha256"] == build["image_sha256"] == EXPECTED_IMAGE
    assert data["primitive_counts"] == implementation["mapped_multiplier_primitives"]
    assert dict(Counter(e["primitive"] for e in data["mapped_instances"])) == data["primitive_counts"]
    assert dict(Counter(e["role"] for e in data["mapped_instances"])) == data["functional_group_counts"]
    assert data["functional_group_counts"] == {"projection_lanes": 64, "projection_scaling": 2,
                                               "dynamic_roles": 5, "embedding_and_address_support": 5}
    return data


data = inventory()
assert sum(data["functional_group_counts"].values()) == 76

# Logical drawing units are pixels; export at 1.5x for comfortable zooming.
W, H = 3600, 2950
plt.rcParams.update({"font.family": "DejaVu Sans", "svg.fonttype": "none", "svg.hashsalt": "simplestories-architecture-v1"})
fig = plt.figure(figsize=(36, 29.5), facecolor="white")
ax = fig.add_axes([0, 0, 1, 1])
ax.set_xlim(0, W)
ax.set_ylim(H, 0)
ax.axis("off")

C = {
    "ink": "#172f46", "muted": "#52687a", "border": "#b5c3ce",
    "panel": "#f7f9fc", "control": "#8155a4", "controlfill": "#f1ebf7",
    "model": "#2867aa", "modelfill": "#e9f1fc",
    "data": "#137c75", "datafill": "#e7f5f1",
    "kv": "#c57516", "kvfill": "#fff3df",
    "dynamic": "#ac3562", "dynamicfill": "#fcebf2",
    "gray": "#738493", "grayfill": "#eef2f5",
}
text_boxes = []


def text(x, y, s, size=21, color=None, weight="normal", ha="left", va="top", **kw):
    return ax.text(x, y, s, fontsize=size * .72, color=color or C["ink"], weight=weight,
                   ha=ha, va=va, linespacing=1.32, **kw)


def rect(x, y, w, h, fill="white", stroke=None, lw=1.6, radius=15, dashed=False):
    p = FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad=0,rounding_size={radius}",
                      facecolor=fill, edgecolor=stroke or C["border"], linewidth=lw,
                      linestyle=(0, (7, 5)) if dashed else "solid", zorder=2)
    ax.add_patch(p)
    return p


def box(x, y, w, h, title, body="", kind="gray", title_size=23, body_size=20, rtl=None):
    rect(x, y, w, h, C.get(kind + "fill", "white"), C.get(kind, C["border"]))
    items = [text(x + 22, y + 18, title, title_size, weight="bold")]
    if body:
        body_top = 52 if rtl and h <= 120 else 60
        items.append(text(x + 22, y + body_top, body, body_size))
    if rtl:
        items.append(text(x + 22, y + h - 22, rtl, 15, C["muted"]))
    text_boxes.append((title, x, y, w, h, items))


def line(points, color="gray", width=3, dashed=False, arrow=True, both=False):
    col = C.get(color, color)
    xs, ys = zip(*points)
    ax.add_line(Line2D(xs, ys, color=col, linewidth=width,
                       linestyle=(0, (7, 5)) if dashed else "solid", zorder=2.5))
    if arrow:
        ax.add_patch(FancyArrowPatch(points[-2], points[-1], arrowstyle="-|>",
                                    mutation_scale=17, color=col, lw=width, zorder=2.6))
    if both:
        ax.add_patch(FancyArrowPatch(points[1], points[0], arrowstyle="-|>",
                                    mutation_scale=17, color=col, lw=width, zorder=2.6))


def label(x, y, s, color="muted", size=18, ha="left"):
    text(x, y, s, size, C.get(color, color), ha=ha,
         bbox={"facecolor": "white", "edgecolor": "none", "pad": 2, "alpha": .96}, zorder=4)


def badge(x, y, s, w=80, kind="dynamic"):
    rect(x, y, w, 42, C[kind + "fill"], C[kind], radius=10)
    text(x + w / 2, y + 8, s, 22, C[kind], weight="bold", ha="center")


# Header: explain the purpose and reconcile the counts before introducing the wiring.
text(60, 40, "Inside a fixed-model inference chip", 47, weight="bold")
text(60, 108, "SimpleStories-V2-5M  •  released baseline  •  controllers, private buses, memories and multiplier resources", 25, C["muted"])
rect(60, 165, 3480, 126, "#f4f7fb", "#c4d0dc")
text(88, 182, "76 mapped multipliers = 64 projection + 2 projection-scaling + 5 dynamic-role + 5 supporting units", 28, weight="bold")
text(88, 235, "The five dynamic units are included in the 76. Both operands are runtime values in at least one scheduled role; the units are not user-programmable.", 21, C["muted"])

# Two panels provide a readable architectural overview and a count-complete expansion.
rect(50, 335, 1510, 2205, C["panel"], radius=18)
rect(1620, 335, 1930, 2205, C["panel"], radius=18)
text(80, 360, "1  Follow the data through the chip", 30, weight="bold")
text(1650, 360, "2  Expand the arithmetic hardware", 30, weight="bold")

# Panel 1: external interfaces, fixed controllers and separate model/cache channels.
box(110, 440, 840, 115, "Host computer", "Sends input tokens; receives one generated token at a time.", body_size=21)
box(1110, 440, 380, 115, "External flash", "Stores the model weights.", body_size=19)
rect(85, 620, 1440, 1670, "white", "#7c96af", lw=2)
text(110, 635, "FIXED CIRCUIT BOUNDARY", 20, weight="bold", color=C["muted"])
box(130, 695, 640, 110, "UART command decoder", "Accepts APPEND, STEP and CLEAR.", "control", rtl="u_fixed_uart / u_three_operations")
box(1120, 695, 360, 175, "Boot controller", "Loads model to DDR;\nchecks the image;\nthen enables inference.", "control", body_size=19, rtl="u_fixed_qspi_boot / u_boot")
box(130, 895, 640, 190, "Token controller", "Owns the token tape and current position.\nRuns embedding lookup, final normalization\nand next-token selection.", "control", body_size=20, rtl="u_token_shell  •  final normalization uses D5")
box(890, 945, 590, 140, "Layer / stage sequencer", "Schedules six layers on shared hardware.\nSelects jobs, lengths and internal addresses.", "control", body_size=20, rtl="u_sequence")
box(350, 1200, 920, 185, "Shared arithmetic + private working memory", "Computes activations, queries and intermediate results.\nVector / scratch RAM keeps these values inside the chip.\nThe hardware inside this block is expanded at right →", "data", body_size=21, rtl="u_datapath; token-shell arithmetic also appears in panel 2")
box(150, 1490, 560, 120, "Model-read queues + owner arbiter", "Routes embedding and layer weight requests.", "model", body_size=20, rtl="u_private_ddr_arbiter")
box(150, 1690, 560, 190, "Weight-page authentication controller", "Four 4 KiB on-chip buffers.\nCopy → seal → SHA-256 digest check → use.\nExpected digests are fixed inside the circuit.", "model", title_size=22, body_size=20, rtl="u_auth / g_bank[].u_bank")
box(920, 1490, 560, 180, "Attention-cache controller", "Stores and fetches past keys and values (K/V).\nOwns row staging, valid prefix and addresses.\nBaseline K/V data have no integrity check.", "kv", title_size=22, body_size=20, rtl="u_kv_cache + u_boundary")
rect(945, 1730, 510, 135, C["kvfill"], C["kv"], dashed=True)
text(965, 1744, "Protected-variant addition", 22, weight="bold", color=C["kv"])
text(965, 1782, "An integrity guard is inserted on this path.\nIt checks K/V against private expected digests.\nIt is outside the baseline count shown here.", 18)
box(150, 1980, 1330, 110, "Shared DDR arbiter + runtime memory adapter", "Combines model reads and typed K/V reads / writes while retaining transaction ownership.", "gray", body_size=20, rtl="u_shared → u_runtime_adapter → u_handoff")
box(150, 2165, 1330, 95, "Clock-crossing queues + DDR controller / PHY", "25 MHz inference control ↔ 100 MHz DDR application interface; 400 MHz PHY clock source.", "gray", body_size=20, rtl="u_transport → u_raw_controller")
box(150, 2375, 1330, 115, "One external DDR memory chip", "Separate address regions: fixed model image (~7.3 MB) and mutable attention cache (~7.1 MB).", body_size=20)

line([(450,555),(450,695)], "gray", both=True)
label(470,580,"UART serial link; token IDs use 12 bits", size=18)
line([(450,805),(450,895)], "control", dashed=True, both=True)
label(470,835,"validated commands / token replies", "control",17)
line([(1300,555),(1300,695)], "gray")
label(1320,578,"QSPI reads", size=17)
line([(770,985),(890,985)], "control", dashed=True, both=True)
label(800,910,"start / done", "control",17)
line([(1180,1085),(1180,1150),(1090,1150),(1090,1200)], "control", dashed=True)
label(1195,1117,"fixed schedule", "control",17)
line([(420,1085),(420,1200)], "data", both=True)
label(140,1120,"activations / final result", "data",18)
line([(630,1385),(630,1490)], "model", both=True)
label(180,1435,"model reads / verified 256-bit replies", "model",18)
line([(430,1610),(430,1690)], "model", both=True)
label(450,1635,"page requests / checked bytes", "model",17)
line([(1200,1385),(1200,1490)], "kv", both=True)
label(1005,1434,"internally generated K/V", "kv",17)
line([(430,1880),(430,1980)], "model", both=True)
label(180,1915,"refill reads: 19-bit word address / 256-bit data", "model",17)
line([(1200,1670),(1500,1670),(1500,1935),(1240,1935),(1240,1980)], "kv", both=True)
label(955,1898,"typed K/V words: 256-bit data", "kv",17)
line([(1480,790),(1510,790),(1510,1950),(1410,1950),(1410,1980)], "gray", width=2)
label(1230,1160,"boot-only path", size=17)
line([(815,2090),(815,2165)], "gray", both=True)
label(840,2110,"29-bit DDR app address + 256-bit data", size=17)
line([(815,2260),(815,2375)], "gray", both=True)
label(840,2315,"physical DDR bus: 32 data wires + control", size=17)

# Panel 2A: explicitly draw 64 projection lanes, then the two scaling multipliers.
rect(1660, 440, 1850, 845, "white", "#a7bdd6")
text(1690, 462, "64 + 2  Fixed-weight projection engine", 27, weight="bold", color=C["model"])
text(1690, 508, "Used for Q/K/V projections, output projection, the feed-forward network and the vocabulary head.", 20)
text(1690, 548, "The controller reuses the same hardware across all layers; it does not select a general matrix program.", 19, C["muted"])
box(1730, 600, 710, 96, "Computed activation", "One signed 16-bit value, broadcast to every lane.", "data", body_size=20)
box(2710, 600, 710, 96, "Authenticated weight stream", "640 bits = 64 signed 10-bit model coefficients.", "model", body_size=20)
line([(2080,696),(2080,735),(3380,735)],"data",arrow=False)
line([(3070,696),(3070,750),(1780,750)],"model",arrow=False)

# Each of the 64 small cells is exactly one mapped projection multiplier.
for tile in range(4):
    tx=1730+tile*430
    rect(tx,785,405,290,C["modelfill"],C["model"],radius=10)
    text(tx+202.5,802,f"Group {tile+1}: 16 parallel lanes",20,ha="center",weight="bold")
    for lane in range(16):
        cx=tx+24+(lane%4)*94
        cy=850+(lane//4)*49
        rect(cx,cy,76,36,"white",C["model"],radius=5)
        text(cx+38,cy+5,f"× {tile*16+lane+1}",17,ha="center")
    text(tx+202.5,1050,"Each lane: W10 × A16 + accumulator",17,ha="center")
    line([(tx+95,735),(tx+95,785)],"data")
    line([(tx+305,750),(tx+305,785)],"model")
for tile in range(4):
    line([(1932.5+tile*430,1075),(1932.5+tile*430,1110)],"data",arrow=False)
line([(1932.5,1110),(3222.5,1110)],"data",arrow=False)
line([(2575,1110),(2575,1147)],"data",arrow=False)
box(1760, 1150, 770, 100, "P65  Low-part row scaling  ×", "Fixed row scale × low part of accumulated result.","model",title_size=22,body_size=19,rtl="u_scale_low  •  1 MULTALU27X18")
box(2620, 1150, 770, 100, "P66  High-part row scaling  ×", "Fixed row scale × high part; recombine as 50-bit result.","model",title_size=22,body_size=19,rtl="u_scale_high  •  1 MULTALU27X18")
line([(2575,1147),(2145,1147),(2145,1150)],"data")
line([(2575,1147),(3005,1147),(3005,1150)],"data")
text(1695,1260,"35-bit lane accumulators → one row at a time → scaled 50-bit result → private vector normalization.",18)

# Panel 2B: five clearly marked dynamic roles, with the attention path shown explicitly.
rect(1660, 1320, 1850, 650,"white",C["dynamic"],lw=2)
text(1690,1344,"5  Dynamic-role multipliers — highlighted in pink",27,weight="bold",color=C["dynamic"])
text(1690,1390,"These are five individual multipliers distributed across attention, feed-forward and normalization hardware.",20)
text(1690,1426,"Queries, attention probabilities and intermediate results stay in private on-chip memory.",19,C["muted"])

box(1730,1500,500,155,"D1  Attention score  ×","query Q × cached key K\n16-bit × 16-bit; accumulate Q·K","dynamic",title_size=23,body_size=21,rtl="u_attention.u_score_lane")
box(2300,1500,490,155,"Score RAM + softmax","Converts scores into attention\nprobabilities (the A values).","data",title_size=23,body_size=21,rtl="No multiplier counted in this box")
box(2860,1500,570,155,"D2  Weighted value  ×","attention probability A × cached value V\n16-bit × 16-bit; accumulate weighted values","dynamic",title_size=23,body_size=20,rtl="u_attention.u_lane")
line([(2230,1575),(2300,1575)],"data")
line([(2790,1575),(2860,1575)],"data")
label(1750,1460,"Q from private state; K from cache", "data",17)
label(2880,1460,"V from cache; output to private state", "data",17)

box(1730,1740,520,185,"D3  Feed-forward product  ×","Nonlinear gate × parallel branch value.\nThe same unit also applies fixed\nrotary-position coefficients.","dynamic",title_size=22,body_size=21,rtl="u_elementwise_lane / u_product_dsp")
box(2310,1740,520,185,"D4  Layer normalization  ×","Squares each activation: x × x.\nAlso applies fixed normalization\nweights and row scales.","dynamic",title_size=22,body_size=21,rtl="u_datapath.u_rmsnorm")
box(2890,1740,540,185,"D5  Final normalization  ×","A separate x × x unit in token control.\nAlso applies fixed normalization\nweights and row scales.","dynamic",title_size=22,body_size=21,rtl="u_token_shell.u_final_rmsnorm")

# Panel 2C: the remaining five mapped multipliers are support work, not hidden GEMM lanes.
rect(1660,2010,1850,370,"white",C["gray"])
text(1690,2032,"5  Supporting multipliers — embedding conversion and address generation",25,weight="bold")
text(1690,2079,"These are part of the 76 even though they do not form the main matrix engine.",20,C["muted"])
support=[
    ("S1  ×","Embedding value\n× fixed row scale","1 large primitive"),
    ("S2  ×","Layer number\n× weight-block stride","1 large primitive"),
    ("S3  ×","Group number\n× column count","1 small primitive"),
    ("S4  ×","Embedding metadata\naddress calculation","1 small primitive"),
    ("S5  ×","Projection metadata\naddress calculation","1 small primitive"),
]
for i,(title,body,rtl) in enumerate(support):
    box(1720+i*350,2140,320,190,title,body,"gray",title_size=23,body_size=20,rtl=rtl)
text(1690,2410,"Mapped-resource check: 73 large MULTALU27X18 + 3 small MULT12X12 = 76 instances.",23,weight="bold")
text(1690,2455,"A large primitive can include an adder / accumulator. Vendor DSP accounting is 74.5 blocks.",20,C["muted"])

# Footer: decoding the colors, ordinary-language definitions, and evidence boundaries.
text(65,2590,"How to read this diagram",27,weight="bold")
legend=[("model","Model weights / verified model-read path"),("data","Computed activations / results"),("kv","Cached attention keys and values"),("control","Controller commands / status")]
for i,(kind,s) in enumerate(legend):
    x=65+(i%2)*1750; y=2646+(i//2)*51
    line([(x,y+10),(x+100,y+10)],kind,dashed=(kind=="control"))
    text(x+125,y-4,s,22)
text(65,2760,"Weight = a learned model number.  Activation = a number computed while processing tokens.  Controller = fixed logic that chooses the next operation.",20)
text(65,2800,"Bus = a group of wires carrying data; labels give the payload width. Arrows summarize selected transfers, including requests and returns where marked.",20)
text(65,2840,"Scope: baseline architecture with a frozen circuit assumed. The 76 count is verified in the mapped FPGA build; ASIC synthesis may map the arithmetic differently.",19,C["muted"])
text(65,2880,"Sources: Berkeley-AI-Risk/inference-only @ d784685 • ARCHITECTURE.md; evidence/baseline-current/implementation.json; matching mapped netlist / image 6ba3caa4…",18,C["muted"])

# Detect accidental text overflow in node boxes before producing the deliverables.
fig.canvas.draw()
renderer=fig.canvas.get_renderer()
for title,x,y,w,h,items in text_boxes:
    for item in items:
        bb=item.get_window_extent(renderer).transformed(ax.transData.inverted())
        if bb.x0 < x-1 or bb.x1 > x+w+1 or bb.y0 < y-1 or bb.y1 > y+h+1:
            raise RuntimeError(f"Text overflow in {title!r}: {item.get_text()!r}")

fig.savefig(STEM.with_suffix(".svg"),format="svg",facecolor="white",metadata={"Date":None,"Title":"SimpleStories hardware architecture and multiplier inventory","Description":f"Source {COMMIT}; baseline image {EXPECTED_IMAGE}"})
fig.savefig(STEM.with_suffix(".png"),dpi=150,facecolor="white",metadata={"Title":"SimpleStories hardware architecture and multiplier inventory","Source":f"Berkeley-AI-Risk/inference-only @ {COMMIT}; image {EXPECTED_IMAGE}"})
print(json.dumps({"png":str(STEM.with_suffix('.png')),"svg":str(STEM.with_suffix('.svg')),"size_pixels":[5400,4425],"mapped_multipliers":76,"dynamic_roles":5}))

"""Callback replay of original seven-case greedy browser evidence.

All filesystem/capsule resolution is supplied by read_origin; original provenance
strings are never rewritten. The caller validates Root policy/native/source
closure and final catalog compatibility, supplies the actual derived CLI replay,
and constructs tokenizers0.23.2 from the exact pinned tokenizer JSON bytes.
No browser, server, device, compiler, process, or network operation is invoked.
"""
from datetime import datetime
import hashlib
import json
import math
from pathlib import PurePosixPath
import re

FINAL_DECLARED_SOURCE_PROVENANCE_OMISSIONS = {'baseline': {'/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}}, 'kv-protected': {'/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin.jsonl': {'bytes': 1152, 'sha256': 'a317f2d382e46be08d2ec294fd74b7710cee719609c063785a8fee5c0f473f05'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin.jsonl': {'bytes': 1152, 'sha256': 'b5ae01168b9692e5be2120ef7bdf434275ae5c2480a88198970a5048d933c556'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin.jsonl': {'bytes': 1152, 'sha256': 'a317f2d382e46be08d2ec294fd74b7710cee719609c063785a8fee5c0f473f05'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin.jsonl': {'bytes': 1152, 'sha256': 'b5ae01168b9692e5be2120ef7bdf434275ae5c2480a88198970a5048d933c556'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/data/spi/spi.ini': {'bytes': 296, 'sha256': '7b3019cff501726f66baa9baeae3996c7e7eba4316805677e7fd8420a55b2f95'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/programmer_cli': {'bytes': 11414528, 'sha256': '41a967c1d18ec73b420801d52bf83ad40b92ca032683231d55a5ef158d523cfb'}, '/opt/homebrew/Cellar/openfpgaloader/1.1.1/bin/openFPGALoader': {'bytes': 3993648, 'sha256': 'f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b'}}, 'encrypted-memory': {'/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin.jsonl': {'bytes': 1152, 'sha256': 'a317f2d382e46be08d2ec294fd74b7710cee719609c063785a8fee5c0f473f05'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin.jsonl': {'bytes': 1152, 'sha256': 'b5ae01168b9692e5be2120ef7bdf434275ae5c2480a88198970a5048d933c556'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin.jsonl': {'bytes': 1152, 'sha256': 'a317f2d382e46be08d2ec294fd74b7710cee719609c063785a8fee5c0f473f05'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin.jsonl': {'bytes': 1152, 'sha256': 'b5ae01168b9692e5be2120ef7bdf434275ae5c2480a88198970a5048d933c556'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/data/spi/spi.ini': {'bytes': 296, 'sha256': '7b3019cff501726f66baa9baeae3996c7e7eba4316805677e7fd8420a55b2f95'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/programmer_cli': {'bytes': 11414528, 'sha256': '41a967c1d18ec73b420801d52bf83ad40b92ca032683231d55a5ef158d523cfb'}, '/opt/homebrew/Cellar/openfpgaloader/1.1.1/bin/openFPGALoader': {'bytes': 3993648, 'sha256': 'f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b'}}}
DECLARED_RECOVERY_PROVENANCE_OMISSIONS = {'/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin.jsonl': {'bytes': 1152, 'sha256': 'a317f2d382e46be08d2ec294fd74b7710cee719609c063785a8fee5c0f473f05'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/FPGA-Recovery/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin.jsonl': {'bytes': 1152, 'sha256': 'b5ae01168b9692e5be2120ef7bdf434275ae5c2480a88198970a5048d933c556'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read1.bin.jsonl': {'bytes': 1152, 'sha256': 'a317f2d382e46be08d2ec294fd74b7710cee719609c063785a8fee5c0f473f05'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin': {'bytes': 16777216, 'sha256': '093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/factory-backups/tang-mega-138k-2026-09-05/factory-flash-sram-read2.bin.jsonl': {'bytes': 1152, 'sha256': 'b5ae01168b9692e5be2120ef7bdf434275ae5c2480a88198970a5048d933c556'}}
FORBIDDEN_FACTORY_RECOVERY_RAW_SHA256 = ['093ef4c2f4d0aaceff2b01a5e2b012a3ef36a02c1e36c1e962aebe3567be552a', 'a317f2d382e46be08d2ec294fd74b7710cee719609c063785a8fee5c0f473f05', 'b5ae01168b9692e5be2120ef7bdf434275ae5c2480a88198970a5048d933c556']
COLLECTORS = {'baseline': {'root-greedy-sram-selection-v2': ('greedy_browser_v15_shared_baseline_r2.py', '0885cca52f7f7e657aa60cfe727e66c70c3573cf7a2829cf4816aeaa98c0fb8a')}, 'encrypted-memory': {'root-greedy-sram-selection-v5-coordinate': ('greedy_browser_v15_shared_encrypted_v5_r2.py', '5bb053f3f62158d2c2f555c07df8c20ac72b5c9d97a525e082c2086d39e877e3')}, 'kv-protected': {'root-greedy-sram-selection-v15-compact-prefix': ('greedy_browser_v15_shared_protected_p3r0_r2.py', 'eadb8d708dd51117909a6cc6f016e68407cc73c5ff28eb1895417503ec3d766e'), 'root-greedy-sram-selection-v6-four-lane-coordinate': ('greedy_browser_v7_protected_v6_r2.py', '499e984aee172940f25d187d667081489e4ac4d5da4876891b3f55998dc9fb9d'), 'root-greedy-sram-selection-v7-projection-fourway': ('greedy_browser_v8_protected_v7.py', '3dcc86afa570ead5772172cc43b50075bec903ca41faec8e7c917efccc539942'), 'root-greedy-sram-selection-v8-sha-direct-add': ('greedy_browser_v9_protected_v8.py', 'ad3db16973e12a88015dadf81c61b89db2fbd21a55f35cc25046decb76574f62'), 'root-greedy-sram-selection-v9-dense-sha': ('greedy_browser_v12_shared_protected_v9_r1.py', '689f01c3bc2743f74f4e280ac79dfe1dd8f34081d1d304ce813afdc404d92f71')}}
CASES = (('around4', 'around128', 4), ('repeat4', 'around128', 4),
         ('prefix128-eight', 'prefix128', 8), ('prefix512-four', 'prefix512', 4),
         ('prefix2048-one', 'prefix2048', 1), ('prefix2047-stop', 'prefix2047', 2),
         ('resumed4', 'around128', 4))
NATIVE_COUNTS = {'baseline': (90, 87), 'kv-protected': (93, 89), 'encrypted-memory': (100, 96)}
MODEL_SHA256 = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
TOKENIZER_PIN = {'bytes': 86463, 'sha256': '01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51'}
GOLDEN_PINS = {
    'around128': {'bytes': 11047, 'sha256': 'f517af7880aa9160379c71fb1804a234a40e509051b4f629cdea7f78b0e73e6e'},
    'prefix128': {'bytes': 12127, 'sha256': 'e8e13774ee692ce2a7c233f8553508194f1a677436f2f4e454879a8afc6dba6a'},
    'prefix512': {'bytes': 5455, 'sha256': 'e27b7312917709dbc18f2b897da4cf3ac88e2a9188fdec2797d949a280f502f5'},
    'prefix2047': {'bytes': 18600, 'sha256': '76206692eb418e29428166cdd0d3f64b3e8a3f25103fefb9159a54dd05da2271'},
    'prefix2048': {'bytes': 18529, 'sha256': '1d85e9b9c7b0116862a3de3a20cde80b1f3534069bdf04a4feff53ab82fefcca'},
}
WIRE_EVENTS = {'command_intent', 'raw_chunk', 'decoded', 'command_result'}
ALLOWED_VENDOR_PROVENANCE_IDENTITIES = {'ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, 'gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, 'gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, 'pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}}
ALLOWED_LIBRARY_TOOL_PROVENANCE_OMISSIONS = {'/Volumes/GowinIDE/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/simlib/gw5a/prim_sim.v': {'bytes': 709304, 'sha256': 'a5c5193b4b1cd1d86084e2c3a6a3d15d3fbacb931faa6cd08aa8c9c793fa37bd'}, '/opt/homebrew/Caskroom/cvc5/1.3.1/cvc5-macOS-arm64-static/bin/cvc5': {'bytes': 21099528, 'sha256': '6b93983220a5aefe7ff80238b0312274aa6c51e442e8adbdc00f47979adc60a8'}, '/opt/homebrew/Cellar/icarus-verilog/13.0/bin/iverilog': {'bytes': 92776, 'sha256': '5df81b269e1ff2c965dd00ad5a8071ca17717f416003b3661a18b2dde430e73c'}, '/opt/homebrew/Cellar/icarus-verilog/13.0/bin/vvp': {'bytes': 1231008, 'sha256': '1a9bdf1f40102f64f015514f5069f99a5dd9f9f38de343743ef4c169fb358392'}, '/opt/homebrew/Cellar/yosys/0.68/bin/yosys': {'bytes': 19221008, 'sha256': 'f59e100c4df830cf7898bc69da624225f15c25e09b1c5747c9b510a15a7a69f5'}, '/opt/homebrew/Cellar/z3/4.14.1/bin/z3': {'bytes': 15715120, 'sha256': 'ea69d1d234e0060fd480bf9b21a51f62244ed642ed2469d4373306e6e8ab6102'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/data/spi/spi.ini': {'bytes': 296, 'sha256': '7b3019cff501726f66baa9baeae3996c7e7eba4316805677e7fd8420a55b2f95'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/programmer_cli': {'bytes': 11414528, 'sha256': '41a967c1d18ec73b420801d52bf83ad40b92ca032683231d55a5ef158d523cfb'}, '/opt/homebrew/Cellar/openfpgaloader/1.1.1/bin/openFPGALoader': {'bytes': 3993648, 'sha256': 'f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b'}}



def need(ok, message):
    if not ok:
        raise ValueError(message)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def crc8(body):
    crc = 0
    for value in body:
        crc ^= value
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return crc

def frame(magic, kind, token=0):
    body = bytes((magic, kind, token & 255, token >> 8))
    return (body + bytes((crc8(body),))).hex()

def wire_check(rows, result, timeout):
    commands = [('clear', 0, None)] + [('append', token, None) for token in result['prompt_tokens']]
    commands += [('step', 0, token) for token in result['generated']] + [('clear', 0, None)]
    wire = [row for row in rows if row['event'] in WIRE_EVENTS]
    cursor = 0; durations = []
    def take(event):
        nonlocal cursor
        need(cursor < len(wire) and wire[cursor]['event'] == event, 'Truncated or reordered wire ownership')
        row = wire[cursor]; cursor += 1
        return row
    for operation, operand, token in commands:
        opcode = {'append': 0, 'step': 1, 'clear': 2}[operation]
        kind = {'append': 0x80, 'step': 0x81, 'clear': 0x82}[operation]
        tx = frame(0xa5, opcode, operand); rx = frame(0x5a, kind, token if operation == 'step' else 0)
        intent = take('command_intent'); sent = take('raw_chunk')
        need(intent['label'] == operation and intent['hex'] == tx
             and sent['direction'] == 'tx' and sent['hex'] == tx and len(bytes.fromhex(tx)) == 5,
             'Non-greedy, noncanonical or unowned request')
        received = bytearray()
        while cursor < len(wire) and wire[cursor]['event'] == 'raw_chunk':
            chunk = take('raw_chunk')
            need(chunk['direction'] == 'rx', 'Extra TX before response completion')
            raw = bytes.fromhex(chunk['hex'])
            need(0 < len(raw) <= 5 - len(received), 'Noise, extra or empty response bytes')
            received.extend(raw)
        need(received.hex() == rx, 'Actual raw reply, CRC or token differs')
        decoded = take('decoded')
        need(decoded['kind'] == 'normal' and decoded['response'] == kind
             and decoded['token'] == (token if operation == 'step' else 0)
             and decoded['frame_hex'] == rx, 'Decoded reply differs from raw frame')
        completed = take('command_result')
        seconds = completed['seconds']
        need(completed['operation'] == operation and completed['operand'] == operand
             and completed['token'] == token and type(seconds) in (int, float)
             and math.isfinite(seconds) and 0 < seconds <= (timeout if operation == 'step' else 10) + 1,
             'Command result or actual bounded timing differs')
        if operation == 'step':
            durations.append(seconds)
    need(cursor == len(wire) and durations == result['step_seconds'], 'Extra wire event or timing mismatch')
    return dict(commands=len(commands), wire_events=len(wire), step_requests=len(durations), settings=0)


def case_data(prepared, package, label, files, tok, verify_sources):
    need(label in prepared['fixtures'], 'Unknown browser scenario')
    fixture = prepared['fixtures'][label]; consumed = {}
    def consume(name, path):
        raw = files[name]; byte_identity(raw); consumed[name] = raw
        return raw
    download = json.loads(consume('download.json', None))
    need(re.fullmatch('[0-9a-f]{32}', download.get('job_id', '')) is not None, 'Missing backend job ID')
    expected_log = package / 'host-app/logs' / (download['job_id'] + '.jsonl')
    need(origin(download['log_path']) == expected_log, 'Download points to another package/backend')
    rows = [json.loads(line) for line in consume('backend.jsonl', expected_log).splitlines()]
    need(len(rows) >= 3 and rows[0]['event'] == 'run' and rows[-1]['event'] == 'finished'
         and rows[1]['event'] in ('deployment_guard', 'connection_reused')
         and all(row['event'] in WIRE_EVENTS for row in rows[2:-1]),
         'Incomplete, failed, duplicate or reordered backend event ownership')
    previous = -1
    for row in rows:
        need(type(row['monotonic_ns']) is int and row['monotonic_ns'] >= previous, 'Reordered backend timeline')
        previous = row['monotonic_ns']
    result = rows[-1]['result']
    need(re.fullmatch('[0-9a-f]{32}', result.get('owner', '')) is not None,
         'Missing actual browser/controller owner')
    need({k: v for k, v in download.items() if k != 'streaming_tokens_per_second'} == result,
         'Actual downloaded JSON differs from backend FINISHED result')
    need(result['prompt'] == fixture['prompt'] and result['prompt_tokens'] == fixture['prompt_tokens']
         and result['requested'] == fixture['requested'] and result['temperature'] == '0'
         and result['seed'] is None and result['seed_used'] is False
         and result['sampling_settings_applied'] is False and result['error'] == ''
         and result['clear_acknowledged'] is True and result['uploaded'] == len(fixture['prompt_tokens']),
         'Wrong prompt, settings, upload, cleanup or error result')
    generated = result['generated']
    need(isinstance(generated, list) and all(type(t) is int and 0 <= t < 4019 for t in generated)
         and generated == fixture['generated_tokens'][:len(generated)], 'Returned token differs from independent T0 golden')
    if fixture['stop_case']:
        need(result['state'] == 'stopped' and result['stop_reason'] == 'Stopped by you'
             and len(generated) == 1, 'Pending first-STEP Stop must preserve exactly its completed correct token')
    else:
        need(result['state'] == 'complete' and len(generated) == fixture['requested']
             and result['stop_reason'] == 'Requested token limit reached', 'Incomplete ordinary browser generation')
    start = rows[0]
    need(start['tokens'] == fixture['prompt_tokens'] and start['prompt'] == fixture['prompt']
         and start['backend_source_sha256'] == prepared['source_pins'][str(package / 'host-app/fpga_backend.py')]['sha256']
         and start['tokenizer_sha256'] == prepared['source_pins'][str(package / 'host-app/assets/tokenizer.json')]['sha256']
         and start['software_inference'] is False and start['temperature'] == '0'
         and start['seed'] is None and start['seed_used'] is False,
         'Backend start/source/generation mode differs')
    connections = [row for row in rows if row['event'] in ('deployment_guard', 'connection_reused')]
    need(len(connections) == 1, 'Missing or repeated actual deployment/connection guard')
    connection = connections[0]
    need(connection['image_sha256'] == prepared['image']['sha256'] and connection['variant'] == prepared['variant']
         and connection['hardware_configuration_not_independently_attested'] is True,
         'Actual deployment guard selects another image or variant')
    if label in ('around4', 'resumed4'):
        need(connection['event'] == 'deployment_guard'
             and connection['build_receipt_sha256'] == prepared['build']['sha256'],
             'Initial and post-Stop cases must open the selected actual build')
    else:
        need(connection['event'] == 'connection_reused'
             and connection['previous_run_ended_with_acknowledged_clear'] is True,
             'Repeated browser case did not reuse the cleared selected connection')
    ownership = wire_check(rows, result, prepared['runtime_limits']['step_timeout_seconds'])
    need(tok.encode(result['prompt'], add_special_tokens=False).ids == fixture['prompt_tokens']
         and tok.decode([t for t in result['prompt_tokens'] + generated if t != 1],
                        skip_special_tokens=False) == result['text'], 'Actual tokenizer/text reconstruction differs')
    arrivals = result['arrivals_seconds']
    need(len(arrivals) == len(generated) and len(result['step_seconds']) == len(generated)
         and all(type(x) in (int, float) and math.isfinite(x) and x > 0 for x in arrivals)
         and all(a < b for a, b in zip(arrivals, arrivals[1:]))
         and result['first_token_seconds'] == arrivals[0]
         and type(result['elapsed_seconds']) in (int, float)
         and math.isfinite(result['elapsed_seconds']) and result['elapsed_seconds'] >= arrivals[-1],
         'Invalid returned receive timings')
    rate = (len(arrivals) - 1) / (arrivals[-1] - arrivals[0]) if len(arrivals) > 1 else None
    need(download['streaming_tokens_per_second'] == rate, 'Downloaded displayed rate differs')
    observation = json.loads(consume('observation.json', None))
    need(observation['schema'] == 'greedy-browser-observation-v1' and observation['label'] == label
         and observation['browser'] == 'Chrome' and observation['url'] == prepared['browser_url']
         and observation['prompt_value'] == fixture['prompt']
         and observation['maximum_new_tokens_value'] == fixture['requested']
         and observation['story_displayed'] == result['text']
         and observation['tokens_generated_displayed'] == len(generated)
         and observation['download_clicked'] is True, 'Actual UI observation disagrees with download/scenario')
    observed = datetime.fromisoformat(observation['observed_utc'])
    need(observed.tzinfo is not None, 'Observation timestamp has no timezone')
    snapshot = consume('ui.txt', observation['ui_snapshot_path']).decode()
    need('FPGA story lab' in snapshot and 'Download run record' in snapshot and result['text'] in snapshot
         and result['job_id'][:8] in snapshot and 'Temperature' not in snapshot,
         'Actual AX snapshot lacks the result/download/job or exposes seeded controls')
    active_stop = None
    if fixture['stop_case']:
        before = consume('before-stop-ui.txt', observation['before_stop_snapshot_path']).decode()
        before_rows = [json.loads(line) for line in consume('before-stop-backend.jsonl', observation['before_stop_backend_snapshot_path']).splitlines()]
        indices = [i for i, row in enumerate(rows) if row['event'] == 'command_intent' and row['label'] == 'step']
        need(len(indices) == 1 and before_rows == rows[:indices[0] + 2]
             and before_rows[-1]['event'] == 'raw_chunk' and before_rows[-1]['direction'] == 'tx'
             and before_rows[-1]['hex'] == frame(0xa5, 1)
             and observation['before_stop_tokens_generated'] == 0
             and observation['before_stop_state'] == 'generating' and observation['stop_clicked'] is True
             and observation['stop_clicked_while_first_step_pending'] is True
             and 'generating' in before.lower() and 'Stop' in before,
             'Stop was not observed at actual pending first STEP before its reply')
        active_stop = dict(before_backend_sha256=sha(consumed['before-stop-backend.jsonl']),
            before_ui_sha256=sha(consumed['before-stop-ui.txt']), first_step_pending=True,
            completed_step_checked_against_independent_golden=True)
    verify_sources()
    public = dict(label=label, result=result, downloaded_streaming_rate=rate, observation=observation,
        connection_started=connection['event'], ownership=ownership, reference=fixture['golden'],
        active_step_stop=active_stop, independent_reference_outputs=len(generated),
        source_download_sha256=sha(consumed['download.json']), source_backend_sha256=sha(consumed['backend.jsonl']),
        source_ui_snapshot_sha256=sha(consumed['ui.txt']), no_settings=True)
    return public, consumed


def byte_identity(data):
    need(type(data) is bytes and 0 < len(data) <= 128 * 1024 * 1024,
         'Nonempty bounded original bytes required')
    return dict(bytes=len(data), sha256=sha(data))


def origin(path):
    need(type(path) is str and path.startswith('/') and '\x00' not in path,
         'Original absolute POSIX provenance path required')
    value = PurePosixPath(path)
    need(str(value) == path and '..' not in value.parts, 'Noncanonical original provenance path')
    return value


def json_object(data):
    byte_identity(data)
    def pairs(values):
        result = {}
        for key, value in values:
            need(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    def bad_constant(value):
        raise ValueError('Nonfinite JSON constant: ' + value)
    value = json.loads(data, object_pairs_hook=pairs, parse_constant=bad_constant)
    need(type(value) is dict, 'JSON object required')
    return value


def source_provenance_omissions(variant):
    """Return only reviewed exact private/library/tool metadata rows, never core data."""
    mapping=FINAL_DECLARED_SOURCE_PROVENANCE_OMISSIONS
    need(type(mapping)is dict and set(mapping)==set(NATIVE_COUNTS)
         and all(type(rows)is dict for rows in mapping.values()),
         'Actual per-variant browser provenance-omission source contract pending')
    for rows in mapping.values():
        for name,wanted in rows.items():
            path=origin(name)
            need(type(wanted)is dict and set(wanted)=={'bytes','sha256'},
                 'Exact browser provenance digest metadata required')
            permitted=(name in DECLARED_RECOVERY_PROVENANCE_OMISSIONS
                and wanted==DECLARED_RECOVERY_PROVENANCE_OMISSIONS[name])
            permitted=permitted or(name in ALLOWED_LIBRARY_TOOL_PROVENANCE_OMISSIONS
                and wanted==ALLOWED_LIBRARY_TOOL_PROVENANCE_OMISSIONS[name])
            permitted=permitted or('/project/official/'in name
                and path.name in ALLOWED_VENDOR_PROVENANCE_IDENTITIES
                and wanted==ALLOWED_VENDOR_PROVENANCE_IDENTITIES[path.name])
            need(permitted,'Owned/current model/image/golden/raw data cannot be omitted as private provenance')
    return mapping[variant]


def validate_campaign(*, prepared_pin, completed_pin, cli_uart_replay, read_origin,
                      tokenizer_factory, variant, image_sha256):
    """Validate original copied evidence through a capsule-only byte resolver.

    read_origin(origin, expected=None) returns original bytes, never an original
    absolute filesystem read. tokenizer_factory(bytes) must construct the pinned
    tokenizers0.23.2 Tokenizer; the caller checks its installed version. Its return
    value exposes encode(...).ids and decode(...), matching the original collector.
    cli_uart_replay is the actual da315-derived pure UART replay result, checked
    separately by the caller against the selected closed Root policy/source graph.
    """
    need(variant in COLLECTORS and type(image_sha256) is str
         and re.fullmatch('[0-9a-f]{64}', image_sha256) is not None
         and callable(read_origin) and callable(tokenizer_factory),
         'Explicit supported variant, image and callable byte/tokenizer adapters required')
    consumed_pins = {}
    omitted_source_pins = source_provenance_omissions(variant)
    omitted_pins = {}
    def read_file(path, expected):
        origin(path)
        need(type(expected) is dict and set(expected) in ({'bytes', 'sha256'}, {'path', 'bytes', 'sha256'})
             and ('path' not in expected or expected['path'] == path)
             and type(expected['bytes']) is int,
             'Exact original two/three-key file identity required')
        wanted = {key: expected[key] for key in ('bytes', 'sha256')}
        need(wanted['sha256']not in FORBIDDEN_FACTORY_RECOVERY_RAW_SHA256,
             'Private factory recovery bytes/logs cannot be consumed as public payload under any alias')
        data = read_origin(path, expected)
        need(type(data)is bytes and len(data)<=128*1024*1024
             and dict(bytes=len(data),sha256=sha(data))==wanted,
             'Capsule bytes differ from original evidence pin: ' + path)
        need(path not in consumed_pins or consumed_pins[path] == wanted, 'Conflicting original evidence pins')
        consumed_pins[path] = wanted
        return data
    def pinned(row):
        need(type(row) is dict and set(row) == {'path', 'bytes', 'sha256'}, 'Original three-key pin required')
        return read_file(row['path'], row)
    prepared_bytes = pinned(prepared_pin); completed_bytes = pinned(completed_pin)
    prepared = json_object(prepared_bytes); completed = json_object(completed_bytes)
    package = origin(prepared['package']); run = origin(prepared_pin['path']).parent
    need(origin(prepared_pin['path']).name == 'INPUTS.json', 'Original INPUTS filename required')
    need(prepared['schema'] == 'greedy-browser-prepared-inputs-v2'
         and prepared['variant'] == variant and prepared['image']['sha256'] == image_sha256
         and prepared['tokenizers_version'] == '0.23.2' and prepared['streamlit_version'] == '1.64.0'
         and prepared['hardware_access'] is False and prepared['browser_actions_performed'] is False
         and prepared['inherited_seeded_browser_qualification'] is False
         and prepared['matched128_cli_campaign_separate'] is True
         and (prepared['selected_native_input_count'], prepared['selected_packaged_owned_source_count'])
             == NATIVE_COUNTS[variant], 'Prepared browser source/variant/image/census scope differs')
    need(completed['schema'] == 'greedy-browser-actual-seven-case-check-v2'
         and completed['passed'] is True and completed['complete'] is True
         and completed['prepared_inputs'] == prepared_pin and completed['variant'] == variant
         and completed['image'] == prepared['image'] and completed['policy'] == prepared['policy']
         and completed['physical_cli_record'] == prepared['physical_cli_record']
         and completed['case_count'] == 7 and completed['actual_download_backend_ax_replayed'] is True
         and completed['settings_commands'] == 0 and completed['matched128_cli_campaign_separate'] is True
         and completed['source_inputs_unchanged'] is True and completed['hardware_access'] is False
         and completed['browser_actions_performed_by_collector'] is False
         and completed['physical_configuration_independently_attested'] is False
         and completed['inherited_seeded_browser_qualification'] is False
         and completed['release_qualified'] is False,
         'Missing closed seven-case browser evidence or completion/source binding differs')
    limits = prepared['runtime_limits']
    need(tuple(limits[key] for key in ('max_prompt', 'max_new', 'total', 'max_chars'))
             == (2048, 128, 2049, 32768)
         and type(limits['step_timeout_seconds']) in (int, float)
         and math.isfinite(limits['step_timeout_seconds'])
         and 120 <= limits['step_timeout_seconds'] <= 14400,
         'Recorded actual greedy browser limits differ')
    sources = prepared['source_pins']
    need(type(sources) is dict and sources, 'Original prepared source identities required')
    actual_policy = json_object(pinned(prepared['policy']))
    need(actual_policy['variant'] == variant and actual_policy['image'] == prepared['image']
         and actual_policy['schema'] in COLLECTORS[variant],
         'Actual prepared policy has unknown or mixed variant/source epoch')
    collector_name, collector_sha = COLLECTORS[variant][actual_policy['schema']]
    need(type(collector_name)is str and type(collector_sha)is str and len(collector_sha)==64,
         'Reviewed actual current browser collector source contract pending')
    collector_paths = [name for name in sources if origin(name).name == collector_name]
    need(len(collector_paths) == 1 and sources[collector_paths[0]]['sha256'] == collector_sha,
         'Recorded browser collector is not the exact variant-specific reviewed source')
    need(set(omitted_source_pins)<=set(sources),'Reviewed browser omission row is absent from actual prepared sources')
    def verify_sources():
        for name, expected in sources.items():
            if name in omitted_source_pins:
                need(expected==omitted_source_pins[name],
                     'Actual private/library/tool source metadata differs from reviewed exact omission')
                omitted_pins[name]=expected
            else:
                read_file(name, expected)
    verify_sources()
    need(byte_identity(pinned(prepared['policy'])) == sources[prepared['policy']['path']],
         'Prepared policy is outside recorded source identities')
    build = json_object(pinned(prepared['build']))
    need(build['schema'] == 'fixed-fpga-local-build-v1' and build['variant'] == variant
         and build['image_sha256'] == image_sha256
         and build['hardware_inputs_sha256'] == prepared['inventory_sha256'],
         'Actual prepared BUILD/image/inventory binding differs')
    physical_bytes = pinned(prepared['physical_cli_record']); physical = json_object(physical_bytes)
    need(cli_uart_replay['schema'] == 'greedy-current-portable-byte-uart-replay-v1'
         and cli_uart_replay['passed'] is True and cli_uart_replay['complete_campaign'] is True
         and cli_uart_replay['finished'] == byte_identity(physical_bytes)
         and cli_uart_replay['variant'] == variant and cli_uart_replay['image'] == prepared['image']
         and cli_uart_replay['case_count'] == 10 and cli_uart_replay['main_reference_outputs'] == 395
         and cli_uart_replay['all_supplied_raw_bytes_and_FINISHED_case_results_replayed'] is True
         and cli_uart_replay['original_plan'] == physical['plan']
         and cli_uart_replay['original_raw_uart'] == physical['raw_uart']
         and physical['variant'] == variant and physical['image'] == prepared['image'],
         'Browser preparation is detached from the actual complete same-image UART replay')
    physical_plan = json_object(pinned(physical['plan']))
    need(physical_plan['schema'] == 'greedy-selected-physical-plan-v1'
         and physical_plan['policy'] == prepared['policy'] and physical_plan['variant'] == variant
         and physical_plan['image'] == prepared['image'], 'Physical PLAN selects another browser policy/image')
    tokenizer_path = str(package / 'host-app/assets/tokenizer.json')
    need(sources[tokenizer_path] == TOKENIZER_PIN, 'Original fixed tokenizer source pin differs')
    tokenizer_bytes = read_file(tokenizer_path, TOKENIZER_PIN)
    tok = tokenizer_factory(tokenizer_bytes)
    need(callable(getattr(tok, 'encode', None)) and callable(getattr(tok, 'decode', None)),
         'Tokenizer factory must construct encode/decode object from exact pinned JSON')
    labels = [item[0] for item in CASES]
    need(set(prepared['fixtures']) == set(labels) and set(completed['case_captures']) == set(labels),
         'All seven exact browser fixtures and captures required')
    for label, family, count in CASES:
        fixture = prepared['fixtures'][label]; golden_bytes = pinned(fixture['golden'])
        need(byte_identity(golden_bytes) == GOLDEN_PINS[family], 'Independent original354 T0 golden differs')
        golden = json_object(golden_bytes)
        prompt = tok.decode(golden['prompt_tokens'], skip_special_tokens=False)
        need(golden['temperature'] == '0' and golden['stop_at_eos'] is False
             and golden['model_image_sha256'] == MODEL_SHA256
             and fixture['label'] == label and fixture['requested'] == count
             and fixture['stop_case'] is (label == 'prefix2047-stop')
             and fixture['prompt_tokens'] == golden['prompt_tokens']
             and fixture['prompt'] == prompt and len(prompt) <= limits['max_chars']
             and 1 not in golden['prompt_tokens']
             and tok.encode(prompt, add_special_tokens=False).ids == golden['prompt_tokens']
             and fixture['generated_tokens'] == golden['generated_tokens'][:count],
             'Prepared fixture does not reconstruct independent T0 prompt/output with exact tokenizer')
    cases = []; captures = {}
    for label, _, _ in CASES:
        capture_pin = completed['case_captures'][label]
        need(capture_pin['path'] == str(run / label / 'CAPTURE.json'), 'Capture is detached from original run/case')
        capture = json_object(pinned(capture_pin))
        need(capture['schema'] == 'greedy-browser-actual-case-capture-v2'
             and capture['prepared_inputs'] == prepared_pin
             and capture['hardware_access'] is False
             and capture['browser_actions_performed_by_collector'] is False,
             'Original capture preparation or access scope differs')
        file_roles = {'download.json', 'backend.jsonl', 'observation.json', 'ui.txt'}
        if label == 'prefix2047-stop':
            file_roles |= {'before-stop-ui.txt', 'before-stop-backend.jsonl'}
        need(type(capture['files']) is dict and set(capture['files']) == file_roles,
             'Missing or extra actual download/backend/AX/Stop file role')
        files = {name: read_file(str(run / label / name), expected)
                 for name, expected in capture['files'].items()}
        public, consumed = case_data(prepared, package, label, files, tok, verify_sources)
        need(public == capture['public_case'] and capture['files'] ==
             {name: byte_identity(data) for name, data in consumed.items()},
             'Copied browser roles no longer reconstruct the actual capture')
        cases.append(public); captures[label] = dict(capture_pin)
    need(cases[0]['result']['generated'] == cases[1]['result']['generated'] == cases[-1]['result']['generated']
         and len({case['result']['owner'] for case in cases}) == 1
         and len({case['result']['job_id'] for case in cases}) == len(CASES),
         'Browser owner/job uniqueness or initial/repeat/post-Stop outputs differ')
    outputs = sum(row['independent_reference_outputs'] for row in cases)
    need(outputs == completed['independently_checked_outputs'] == 26 and cases == completed['cases'],
         'Completed seven-case output census/cases differ from actual raw replay')
    verify_sources()
    return dict(schema='greedy-current-portable-callback-browser-replay-v3', passed=True,
        complete=True, variant=variant, image=dict(prepared['image']), prepared_inputs=dict(prepared_pin),
        completed=dict(completed_pin), physical_cli_record=dict(prepared['physical_cli_record']),
        collector_source=collector_paths[0], collector_source_sha256=collector_sha,
        collector_policy_schema=actual_policy['schema'],
        actual_recorded_host_sources={name: dict(expected) for name, expected in sources.items()
            if name.startswith(str(package / 'host-app') + '/')},
        tokenizer_source=dict(path=tokenizer_path, **TOKENIZER_PIN),
        tokenizer_factory_is_caller_supplied=True, caller_must_check_tokenizers_version='0.23.2',
        declared_source_provenance_omissions=omitted_pins,omitted_source_bytes_redistributed_or_rehashed=False,operator_backup_content_independently_replayed=False,consumed_original_file_identities=consumed_pins, case_count=7, cases=cases,
        independently_checked_outputs=outputs, settings_commands=0,
        actual_download_backend_ax_and_raw_wire_replayed=True,
        original_paths_and_argv_rewritten=False, original_filesystem_access=False,
        Root_policy_native_model_closure_rechecked_here=False,
        final_host_catalog_compatibility_rechecked_here=False,
        hardware_access=False, browser_or_server_access=False,
        independent_UI_or_physical_configuration_attestation=False, release_qualified=False,
        scope='Callback-only replay of the original seven captured downloads/AX/backend/UART/Stop roles, exact golden/tokenizer inputs and closed CLI binding. Caller checks Root selection/source closure, installed tokenizer and final catalog compatibility. No new browser actions or independent UI/silicon attestation.')

"""Opt-in sharing of the home gate's message-byte selector.

SEND and RECEIVE consume index_q; the verifier consumes message_address
only in START/VERIFY, when its reset is released. No storage or policy changes.
"""
from pathlib import Path

FILE = 'home/home_boot_gate.sv'


def transform(name, text):
    if name != FILE:
        return text
    marker = '    wire active_window='
    assert text.count(marker) == 1
    wires = '''    // Receive/transmit and signature verification are disjoint phases.
    wire [7:0] selected_message_address =
        (state_q==SEND || state_q==RECEIVE) ? index_q[7:0] : message_address;
    wire [7:0] selected_message_byte = message_byte(selected_message_address);

'''
    text = text.replace(marker, wires + marker)
    replacements = [
        ("request_valid_o ? message_byte(int'(index_q)) : 8'd0", "request_valid_o ? selected_message_byte : 8'd0"),
        ("assign shared_message_byte_o=message_byte(int'(message_address));", "assign shared_message_byte_o=selected_message_byte;"),
        (".message_byte_i(message_byte(int'(message_address))),", ".message_byte_i(selected_message_byte),"),
        ("grant_byte_i!=message_byte(int'(index_q))", "grant_byte_i!=selected_message_byte"),
    ]
    for old, new in replacements:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    return text


def apply(project):
    path=Path(project)/FILE
    path.write_text(transform(FILE,path.read_text()))

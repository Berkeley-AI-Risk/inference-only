"""Strict framed UART transport for the fixed token protocol."""
import os
import select
import time


class StrictChannel:
    """Canonical five-byte frames; no discarded noise or parser resync."""
    def __init__(self, session, client, observe):
        self.session, self.client, self.observe = session, client, observe
        self.pending = bytearray()

    def send(self, frame, label):
        assert not self.pending, 'Unsolicited buffered bytes before command'
        self.observe({'event': 'command_intent', 'label': label, 'hex': frame.hex()})
        self.session._send(frame)
        self.observe({'event': 'raw_chunk', 'direction': 'tx', 'hex': frame.hex()})

    def next(self, timeout):
        deadline = time.monotonic() + timeout
        while True:
            if self.pending:
                if self.pending[0] != 0x5a:
                    raise RuntimeError('Unexpected UART bytes: ' + bytes(self.pending).hex())
                if len(self.pending) >= 5:
                    frame = bytes(self.pending[:5]); del self.pending[:5]
                    kind, token = self.client.decode_response(frame)
                    self.client.TokenMachineSession._validate_response_token(kind, token)
                    event = {'kind': 'normal', 'response': kind, 'token': token,
                             'frame_hex': frame.hex()}
                    self.observe(dict(event, event='decoded'))
                    return event
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            ready, _, _ = select.select((self.session.fd,), (), (), remaining)
            if not ready:
                return None
            chunk = os.read(self.session.fd, 4096)
            if not chunk:
                raise OSError('UART closed')
            self.observe({'event': 'raw_chunk', 'direction': 'rx', 'hex': chunk.hex()})
            self.pending.extend(chunk)

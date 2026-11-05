#!/usr/bin/env python3
"""Loopback-only, model-specific authorization service. PUBLIC DEMO KEY ONLY."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))

from home_auth import HomeBase, Reject, REQUEST_BYTES


def make_server(policy, state, port=0):
    home = HomeBase(policy, state)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            self.connection.settimeout(5)
            try:
                if self.path != "/authorize":
                    self.send_error(404)
                    return
                if (self.headers.get("Content-Type") != "application/octet-stream"
                        or self.headers.get("Transfer-Encoding") is not None
                        or self.headers.get("Content-Length") != str(REQUEST_BYTES)):
                    self.send_error(400)
                    return
                request = self.rfile.read(REQUEST_BYTES)
                if len(request) != REQUEST_BYTES:
                    self.send_error(400)
                    return
                grant = home.authorize(request)
            except Reject:
                self.send_error(403, "Authorization denied")
                return
            except Exception:
                self.send_error(503, "Authorization unavailable")
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(grant)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(grant)

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.home = home
    return server


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--policy", type=Path, required=True)
    p.add_argument("--signer-state", type=Path, required=True)
    p.add_argument("--port", type=int, default=8765)
    a = p.parse_args()
    s = make_server(a.policy, a.signer_state, a.port)
    print(json.dumps({"listen": "127.0.0.1", "port": s.server_port,
                      "PUBLIC_DEMO_ONLY": True, "home_public_key": s.home.public_key.hex()}), flush=True)
    try:
        s.serve_forever()
    finally:
        s.server_close()

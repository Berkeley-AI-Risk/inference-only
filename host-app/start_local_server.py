#!/usr/bin/env python3
"""Start the requested localhost-only app and retain a private launch record.

No FPGA command, configuration or process termination occurs here. Port
collisions fail closed. The child survives this short launcher so the user
can keep using the app after the engineering session ends.
"""
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import uuid
from urllib.request import build_opener, ProxyHandler

ROOT = Path(__file__).resolve().parent
with socket.socket() as probe:
    probe.settimeout(1)
    if probe.connect_ex(('127.0.0.1', 8507)) == 0:
        raise SystemExit('Port 8507 is already occupied. No process was changed.')
runtime = ROOT / 'runtime'; runtime.mkdir(exist_ok=True, mode=0o700)
identifier = uuid.uuid4().hex
log_path = runtime / ('server-' + identifier + '.log')
fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
argv = [sys.executable, '-B', '-m', 'streamlit', 'run', str(ROOT / 'streamlit_app.py'),
        '--server.address', '127.0.0.1', '--server.port', '8507', '--server.headless', 'true']
with os.fdopen(fd, 'wb') as log:
    process = subprocess.Popen(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
record = {'pid':process.pid, 'argv':argv, 'log':str(log_path), 'url':'http://127.0.0.1:8507',
    'hardware_access_by_launcher':False, 'listens_only_on_loopback':True,
    'source_sha256':{name:hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in
        ('streamlit_app.py', 'fpga_backend.py', 'runtime_profile.py', 'token_machine_uart.py',
         'uart_channel.py', 'assets/tokenizer.json', '.streamlit/config.toml')},
    'dependencies':{name:importlib.metadata.version(name) for name in ('streamlit', 'tokenizers')}}
with (runtime / ('server-' + identifier + '.json')).open('x') as out:
    json.dump(record, out, indent=2); out.write('\n')
opener = build_opener(ProxyHandler({}))
for _ in range(50):
    if process.poll() is not None:
        raise SystemExit('App exited before becoming ready. See ' + str(log_path))
    try:
        with opener.open('http://127.0.0.1:8507/_stcore/health', timeout=0.5) as response:
            if response.status == 200:
                print(json.dumps(record, sort_keys=True), flush=True)
                break
    except OSError: pass
    time.sleep(0.1)
else:
    raise SystemExit('App launched, but health was not confirmed yet. See ' + str(log_path))

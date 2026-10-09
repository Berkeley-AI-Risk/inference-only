#!/usr/bin/env python3
"""Explicit local board check after programming; never loads a configuration.

Requires a source-bound local build receipt and operator confirmation. The
known-answer test is a practical deployment check, not cryptographic attestation.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import time
import uuid

from fpga_backend import BoardError, LiveUART, utc
import runtime_profile as profile


class QualificationUART(LiveUART):
    def __init__(self, observe, deployment):
        super().__init__(observe)
        self.deployment = deployment

    def _deployment(self): return self.deployment


def app_is_running() -> bool:
    with socket.socket() as probe:
        probe.settimeout(0.25)
        return probe.connect_ex(('127.0.0.1', 8507)) == 0


def qualify(build_receipt: Path, device: str, *, confirm_loaded: bool,
            acknowledge_timing: bool, replace_profile: bool = False,
            profile_path: Path | None = None, link_factory=QualificationUART) -> dict:
    if not confirm_loaded:
        raise ValueError('Confirm that you loaded this exact source build; this program cannot attest or load it.')
    if app_is_running(): raise RuntimeError('Stop the app on port 8507 before qualifying; no board command was sent.')
    deployment = profile.check_build(build_receipt)
    if not deployment['timing_qualified'] and not acknowledge_timing:
        raise ValueError('This prototype lacks complete timing signoff. Explicit exploratory acknowledgement is required.')
    deployment['device'] = profile.check_device(device)
    destination = profile.PROFILE if profile_path is None else Path(profile_path)
    old = None
    if destination.exists() or destination.is_symlink():
        if not replace_profile: raise FileExistsError('Existing profile preserved; use --replace-profile to archive it and requalify.')
        old = profile.read_regular(destination)
    run = destination.parent / ('qualification-' + uuid.uuid4().hex)
    run.mkdir(parents=True, exist_ok=False, mode=0o700)
    if old is not None:
        # Recoverable invalidation before any command: a failed new check must
        # not leave an apparently usable old qualification behind.
        if profile.read_regular(destination) != old: raise RuntimeError('Profile changed during preflight.')
        destination.rename(run / 'previous-board-profile.json')
        print('Previous local profile preserved in ' + str(run / 'previous-board-profile.json'), flush=True)
    log_path = run / 'uart.jsonl'
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(fd, 'w') as log:
        def observe(event):
            row = dict(event, utc=utc(), monotonic_ns=time.monotonic_ns())
            log.write(json.dumps(row, sort_keys=True) + '\n'); log.flush(); os.fsync(log.fileno())
        observe({'event': 'qualification_start', 'deployment': deployment,
            'operator_confirmed_loaded_build': True, 'hardware_configuration_not_independently_attested': True})
        try:
            with link_factory(observe, deployment) as link:
                def command(op, operand=0):
                    started = time.monotonic()
                    token = link.command(op, operand)
                    observe({'event': 'qualification_result', 'operation': op, 'operand': operand,
                        'token': token, 'seconds': time.monotonic() - started})
                    return token
                command('clear'); command('append', 378)
                for expected in profile.EXPECTED_TOKENS:
                    actual = command('step')
                    if actual != expected:
                        raise BoardError(f'Known-answer mismatch: expected {expected}, received {actual}. No retry/reset follows.')
                command('clear')
                if link.channel.next(0.1) is not None or link.channel.pending:
                    raise BoardError('Unexpected bytes after the final CLEAR acknowledgement.')
            profile.check_device(device, deployment['device'])
            if profile.check_build(build_receipt) != {k: v for k, v in deployment.items() if k != 'device'}:
                raise RuntimeError('Build association changed during qualification.')
            observe({'event': 'qualification_complete', 'generated_tokens': profile.EXPECTED_TOKENS})
        except BaseException as error:
            observe({'event': 'qualification_failed', 'error': str(error),
                'no_automatic_retry_reset_or_reconfiguration': True})
            raise
    record = dict(deployment, schema=profile.PROFILE_SCHEMA, passed=True, created_utc=utc(),
        operator_confirmed_loaded_build=True, operator_acknowledged_unqualified_timing=acknowledge_timing,
        hardware_configuration_not_independently_attested=True,
        qualification_log_path=str(log_path.absolute()), qualification_log_sha256=profile.sha(profile.read_regular(log_path)),
        known_answer={'prompt_tokens': [378], 'generated_tokens': profile.EXPECTED_TOKENS,
            'initial_clear_acknowledged': True, 'final_clear_acknowledged': True})
    archived = run / 'board-profile.json'
    profile.private_write(archived, profile.encode(record))
    # Atomic, no-clobber publication of a local profile; all prior records stay.
    os.link(archived, destination)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-receipt', required=True, type=Path)
    parser.add_argument('--device', required=True, help='Explicit serial path, for example /dev/cu.usbserial-...')
    parser.add_argument('--confirm-loaded-source-build', action='store_true')
    parser.add_argument('--acknowledge-unqualified-timing', action='store_true')
    parser.add_argument('--replace-profile', action='store_true', help='Preserve and invalidate the old local profile before retesting.')
    args = parser.parse_args()
    record = qualify(args.build_receipt, args.device, confirm_loaded=args.confirm_loaded_source_build,
        acknowledge_timing=args.acknowledge_unqualified_timing, replace_profile=args.replace_profile)
    print(json.dumps({'passed': True, 'profile': str(profile.PROFILE), 'image_sha256': record['image_sha256'],
        'variant': record['variant'],
        'generated_tokens': record['known_answer']['generated_tokens'], 'final_clear_acknowledged': True,
        'configuration_not_attested': True}, sort_keys=True), flush=True)


if __name__ == '__main__': main()

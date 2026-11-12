"""Finite runner/parser controls, never a full-model numerical test."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import tempfile
import subprocess
import time
import unittest
from unittest import mock
import sys

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('portable_long18',HERE/'replay.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)


def synthetic_transcript():
    rows=['COMMAND accepted opcode=3 token=0',f"COMMAND accepted opcode=1 token={r.reference()['initial_token']}"]
    for p,token in enumerate(r.reference()['expected_tokens']):
        rows.append('COMMAND accepted opcode=2 token=0')
        rows += [f'PASS layer position={p} layer={l} cycles=1' for l in range(28)]
        rows.append(f'PASS token position={p} token={token} step_cycles=1')
    rows.append('COMMAND accepted opcode=3 token=0')
    rows.append('PASS working_qwen_profile '+' '.join(f'{k}={v}' for k,v in r.reference()['review']['counts'].items()))
    return '\n'.join(rows)+'\n'


class Controls(unittest.TestCase):
    def test_child_preserves_receipt_fields_and_restores_handlers(self):
        previous={sig:signal.getsignal(sig) for sig in (signal.SIGTERM,signal.SIGINT)}
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);out=root/'child'
            argv=[sys.executable,'-I','-S','-B','-c','print("disposable helper")']
            terminal=r.child(argv,root,out,5)
            started=r.read(out/'STARTED.json')
            self.assertEqual(set(started),{'argv','started_utc','timeout_seconds','automatic_retry',
                                           'actual_child_exit','stop_reason','error'})
            for key in ('argv','started_utc','timeout_seconds','automatic_retry'):
                self.assertEqual(terminal[key],started[key])
            self.assertIsNone(started['actual_child_exit'])
            self.assertIsNone(started['stop_reason'])
            self.assertIsNone(started['error'])
            self.assertEqual(terminal,r.read(out/'EXIT.json'))
            self.assertEqual(terminal['actual_child_exit'],0)
            self.assertTrue(terminal['passed'])
            self.assertTrue(terminal['owned_child_reaped'])
            self.assertIn('elapsed_seconds',terminal)
            self.assertIn('ended_utc',terminal)
            r.check_child_logs(out,terminal)
        self.assertEqual({sig:signal.getsignal(sig) for sig in previous},previous)

    def test_parent_signals_and_timeout_reap_helper_and_preserve_interrupted_receipt(self):
        helper='''from pathlib import Path
import json, os, sys, time
root=Path(sys.argv[1])
(root/'ready.tmp').write_text(json.dumps({'pid':os.getpid(),'pgid':os.getpgrp()}))
(root/'ready.tmp').replace(root/'ready.json')
deadline=time.monotonic()+5
while not (root/'release-helper').exists() and time.monotonic()<deadline:
    time.sleep(0.01)
if (root/'release-helper').exists():
    (root/'late-work').write_text('work continued after driver exit')
'''
        driver='''import importlib.util, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('full_machine_helper_runner',sys.argv[1])
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
root=Path(sys.argv[2])
r.child([sys.executable,'-I','-S','-B',str(root/'helper.py'),str(root)],
        root,root/'case',float(sys.argv[3]))
'''
        for signum in (signal.SIGTERM,signal.SIGINT,None):
            with self.subTest(signum=signum),tempfile.TemporaryDirectory() as d:
                root=Path(d).resolve();(root/'helper.py').write_text(helper)
                seconds=2 if signum is None else 30
                process=subprocess.Popen([sys.executable,'-I','-S','-B','-c',driver,
                                          str(HERE/'replay.py'),str(root),str(seconds)],
                                         cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                                         text=True,start_new_session=True)
                try:
                    deadline=time.monotonic()+5
                    while not (root/'ready.json').exists():
                        if process.poll() is not None:
                            stdout,stderr=process.communicate()
                            self.fail('Driver exited before helper admission: '+stdout+stderr)
                        self.assertLess(time.monotonic(),deadline,'Helper did not reach admission')
                        time.sleep(0.01)
                    admitted=r.read(root/'ready.json')
                    self.assertEqual(admitted['pid'],admitted['pgid'])
                    if signum is not None:process.send_signal(signum)
                    stdout,stderr=process.communicate(timeout=6)
                    self.assertNotEqual(process.returncode,0,stdout+stderr)
                    self.assertNotEqual(process.returncode,-signal.SIGTERM,'Driver skipped Python cleanup')
                    # If the old driver left its helper alive, releasing it now
                    # produces a marker and lets this bounded helper exit itself.
                    (root/'release-helper').write_text('driver exited')
                    deadline=time.monotonic()+0.5
                    while not (root/'late-work').exists() and time.monotonic()<deadline:
                        time.sleep(0.01)
                    self.assertFalse((root/'late-work').exists(),'Helper continued after driver exit')
                    started=r.read(root/'case/STARTED.json');terminal=r.read(root/'case/EXIT.json')
                    for key in ('argv','started_utc','timeout_seconds','automatic_retry'):
                        self.assertEqual(terminal[key],started[key])
                    self.assertIsNone(started['actual_child_exit'])
                    self.assertIsNone(started['stop_reason'])
                    self.assertIsNone(started['error'])
                    self.assertEqual(terminal['pid'],admitted['pid'])
                    self.assertEqual(terminal['actual_child_exit'],-signal.SIGTERM)
                    self.assertTrue(terminal['owned_child_reaped'])
                    self.assertFalse(terminal['passed'])
                    self.assertFalse(terminal['automatic_retry'])
                    reason='process_timeout' if signum is None else 'parent_signal_'+signal.Signals(signum).name
                    self.assertEqual(terminal['stop_reason'],reason)
                    if signum is not None:
                        self.assertEqual(terminal['interrupted_signal'],signal.Signals(signum).name)
                    r.check_child_logs(root/'case',terminal)
                    self.assertIn('ended_utc',terminal)
                    self.assertGreater(terminal['elapsed_seconds'],0)
                    with self.assertRaises(ProcessLookupError):os.kill(admitted['pid'],0)
                finally:
                    (root/'release-helper').touch()
                    if process.poll() is None:process.kill()  # Only this test's unreaped driver.
                    process.communicate(timeout=6)

    def test_control_only_rebind_preserves_original_build_and_inputs(self):
        with tempfile.TemporaryDirectory() as d:
            output=Path(d);(output/'source').mkdir()
            source='variants/protected-kv-simulation/rtl/qwen_kvp_reader.sv'
            control='variants/protected-kv-simulation/full-machine/replay.py'
            data=b'unchanged compiler input\n';(output/'source/qwen_kvp_reader.sv').write_bytes(data)
            binary=output/'long18-test';binary.write_bytes(b'fixed synthetic build\n')
            jobs=output/'jobs.txt';jobs.write_bytes(b'unchanged jobs\n')
            compiler={'qwen_kvp_reader.sv':r.pin(output/'source/qwen_kvp_reader.sv')}
            previous={source:compiler['qwen_kvp_reader.sv'],control:dict(bytes=1,sha256='1'*64)}
            current=dict(previous);current[control]=dict(bytes=2,sha256='2'*64)
            prepared=dict(source_inputs=previous,source_files=compiler,runtime_files={},jobs=r.pin(jobs))
            (output/'PREPARED.json').write_text(json.dumps(prepared))
            built=dict(prepared=r.pin(output/'PREPARED.json'),binary=r.pin(binary),compiler_source_files=compiler)
            (output/'BUILT.json').write_text(json.dumps(built))
            original={name:(output/name).read_bytes() for name in ('PREPARED.json','BUILT.json','long18-test','jobs.txt')}
            with mock.patch.object(r,'sources',return_value=current),\
                 mock.patch.object(r,'staged_sources',return_value={'qwen_kvp_reader.sv':data}):
                r.rebind_control(output)
                r.prepared(output)
            rebound=r.read(output/'CONTROL-REBIND.json')
            self.assertTrue(rebound['compiler_input_map_unchanged'])
            self.assertFalse(rebound['old_receipts_rewritten'])
            self.assertEqual(rebound['changed_control_inputs'],[control])
            for name,raw in original.items():self.assertEqual((output/name).read_bytes(),raw)

    def test_public_inputs(self):
        self.assertGreater(len(r.sources()),100)
    def test_staged_selection(self):
        actual=r.staged_sources()
        original=(r.MODEL/'hardware/design/qwen_hbm_cdc_verified_machine.sv').read_bytes()
        self.assertEqual(actual['qwen_hbm_cdc_verified_machine.sv'],original.replace(
            b'    qwen_verified_machine #(',b'    qwen_protected_machine #('))
        self.assertEqual(actual['qwen_verified_machine.sv'],(r.MODEL/'hardware/design/qwen_verified_machine.sv').read_bytes())
    def test_unlisted_compiler_source_refused_before_output_creation(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);variant=root/'variants/protected-kv-simulation';here=variant/'full-machine'
            for folder in [root/'hardware/design',variant/'rtl',here/'tests',variant/'tests']:
                folder.mkdir(parents=True,exist_ok=True)
            wrapper=root/'hardware/design/qwen_hbm_cdc_verified_machine.sv'
            wrapper.write_bytes(b'    qwen_verified_machine #(\n')
            helper=variant/'tests/sha256_reference.h';helper.write_bytes(b'pinned helper\n')
            locked={p.relative_to(root).as_posix():r.pin(p) for p in [wrapper,helper]}
            extra=root/'hardware/design/unlisted.sv';extra.write_bytes(b'module unlisted; endmodule\n')
            with mock.patch.object(r,'MODEL',root),mock.patch.object(r,'VARIANT',variant),\
                 mock.patch.object(r,'HERE',here),mock.patch.object(r,'sources',return_value=locked):
                with self.assertRaisesRegex(ValueError,'Unpinned compiler source'):
                    r.staged_sources()
                output=root/'new-run'
                with mock.patch.object(r,'model_image',return_value={}),\
                     mock.patch.object(r,'verify_oracle',return_value=({},'jobs','independent')):
                    with self.assertRaisesRegex(ValueError,'Unpinned compiler source'):
                        r.prepare(root/'model',root/'oracle',output)
                self.assertFalse(output.exists())
                extra.unlink()
                self.assertEqual(set(r.staged_sources()),{'qwen_hbm_cdc_verified_machine.sv','sha256_reference.h'})
    def test_prefetch_fixtures_excluded_from_full_machine_stage(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);variant=root/'variants/protected-kv-simulation';here=variant/'full-machine'
            for folder in (root/'hardware/design',variant/'rtl',here/'tests',variant/'tests',
                           variant/'prefetch/numeric',variant/'prefetch/fault'):
                folder.mkdir(parents=True,exist_ok=True)
            wrapper=root/'hardware/design/qwen_hbm_cdc_verified_machine.sv'
            wrapper.write_bytes(b'    qwen_verified_machine #(\n')
            helper=variant/'tests/sha256_reference.h';helper.write_bytes(b'pinned helper\n')
            locked={p.relative_to(root).as_posix():r.pin(p) for p in (wrapper,helper)}
            # These intentionally unlisted fixtures must not join the full-model
            # compiler stage merely because they exist under the same variant.
            for folder in ('numeric','fault'):
                (variant/'prefetch'/folder/'top.sv').write_bytes(b'module fixture_only; endmodule\n')
                (variant/'prefetch'/folder/'test.cpp').write_bytes(b'fixture-only test\n')
            with mock.patch.object(r,'MODEL',root),mock.patch.object(r,'VARIANT',variant),\
                 mock.patch.object(r,'HERE',here),mock.patch.object(r,'sources',return_value=locked):
                selected=r.staged_sources()
            self.assertEqual(set(selected),{'qwen_hbm_cdc_verified_machine.sv','sha256_reference.h'})
            self.assertNotIn('top.sv',selected)
            self.assertNotIn('test.cpp',selected)
    def test_portable_oracle_with_stale_sources_rejected_before_tensors(self):
        with tempfile.TemporaryDirectory() as d:
            oracle=Path(d)
            source='variants/protected-kv-simulation/rtl/qwen_kvp_reader.sv'
            previous={source:dict(bytes=10,sha256='1'*64)}
            current={source:dict(bytes=20,sha256='2'*64)}
            record=dict(schema='qwen-portable-long18-oracle-v1',run_completed=True,
                        steps=[{} for _ in range(18)],source_inputs=previous,
                        model_image=dict(bytes=r.IMAGE_BYTES,sha256=r.reference()['model_image_sha256']))
            (oracle/'FINISHED.json').write_text(json.dumps(record))
            # No tensor files exist. A stale full-source identity must be refused
            # before any tensor or historical-receipt pin is consulted.
            with mock.patch.object(r,'sources',return_value=current),\
                 mock.patch.object(r,'pin',side_effect=AssertionError('tensor access before source rejection')):
                with self.assertRaisesRegex(ValueError,'Oracle source identity changed'):
                    r.verify_oracle(oracle)
            self.assertEqual(json.loads((oracle/'FINISHED.json').read_text()),record)
    def test_reader_change_cannot_rebind_an_existing_binary(self):
        with tempfile.TemporaryDirectory() as d:
            output=Path(d);(output/'source').mkdir()
            source='variants/protected-kv-simulation/rtl/qwen_kvp_reader.sv'
            old_reader=b'old reader compiler input\n'
            new_reader=b'new reader compiler input\n'
            path=output/'source/qwen_kvp_reader.sv';path.write_bytes(old_reader)
            binary=output/'long18-test';binary.write_bytes(b'preserved old binary\n')
            previous={source:r.pin(path)}
            prepared=dict(source_inputs=previous,source_files={'qwen_kvp_reader.sv':r.pin(path)})
            (output/'PREPARED.json').write_text(json.dumps(prepared))
            built=dict(prepared=r.pin(output/'PREPARED.json'),binary=r.pin(binary),
                       compiler_source_files=prepared['source_files'])
            (output/'BUILT.json').write_text(json.dumps(built))
            replacement=output/'candidate.sv';replacement.write_bytes(new_reader)
            current={source:r.pin(replacement)}
            with mock.patch.object(r,'sources',return_value=current),\
                 mock.patch.object(r,'staged_sources',return_value={'qwen_kvp_reader.sv':new_reader}):
                with self.assertRaisesRegex(ValueError,'Compiler inputs changed; a new build is required'):
                    r.rebind_control(output)
            self.assertFalse((output/'CONTROL-REBIND.json').exists())
            self.assertEqual(path.read_bytes(),old_reader)
            self.assertEqual(binary.read_bytes(),b'preserved old binary\n')
    def test_wrong_model_size(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'not-a-model';p.write_bytes(b'wrong model')
            with self.assertRaisesRegex(ValueError,'Wrong fixed model'):r.model_image(p)
    def test_same_size_wrong_model_digest(self):
        # Sparse zero file: exercises the actual SHA gate without distributing weights.
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'wrong-model'
            with p.open('xb') as f:f.truncate(r.IMAGE_BYTES)
            with self.assertRaisesRegex(ValueError,'Wrong fixed model'):r.model_image(p)
    def test_synthetic_parser_positive_only(self):
        self.assertEqual(r.check_transcript(synthetic_transcript())['ordered_layers'],504)
    def test_missing_layer(self):
        with self.assertRaisesRegex(ValueError,'layer checks'):
            r.check_transcript(synthetic_transcript().replace('PASS layer position=17 layer=27 cycles=1\n',''))
    def test_wrong_token(self):
        with self.assertRaisesRegex(ValueError,'token mismatch'):
            r.check_transcript(synthetic_transcript().replace('position=17 token=315','position=17 token=316'))
    def test_missing_boundary(self):
        with self.assertRaisesRegex(ValueError,'boundary16_commits'):
            r.check_transcript(synthetic_transcript().replace('boundary16_commits=28','boundary16_commits=27'))
    def test_missing_application_clear(self):
        with self.assertRaisesRegex(ValueError,'APPEND/STEP/CLEAR'):
            r.check_transcript(synthetic_transcript().replace('COMMAND accepted opcode=3 token=0\n','',1))
    def test_missing_actual_append(self):
        with self.assertRaisesRegex(ValueError,'APPEND/STEP/CLEAR'):
            r.check_transcript(synthetic_transcript().replace('COMMAND accepted opcode=1 token=9707','COMMAND accepted opcode=1 token=25'))
    def test_duplicate_terminal(self):
        text=synthetic_transcript()
        with self.assertRaisesRegex(ValueError,'terminal PASS'):r.check_transcript(text+text.splitlines()[-1]+'\n')
    def test_failure_after_pass(self):
        with self.assertRaisesRegex(ValueError,'FAIL'):r.check_transcript(synthetic_transcript()+'FAIL later error\n')
    def test_no_actual_memory_activity(self):
        with self.assertRaisesRegex(ValueError,'memory activity'):
            r.check_transcript(synthetic_transcript().replace('raw_pages=474120','raw_pages=0'))
    def test_tensor_tape_hash_binds_values(self):
        event=dict(operation=1,layer=0,tensor='X',elements=2048,file='00-000.bin',sha256='0'*64)
        changed=dict(event,sha256='1'*64)
        self.assertNotEqual(r.tensor_tape([event]),r.tensor_tape([changed]))
    def test_stdout_changed_after_successful_child_exit(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);out=root/'child'
            terminal=r.child([sys.executable,'-I','-S','-B','-c','print("actual child output")'],root,out,5)
            self.assertEqual(terminal['actual_child_exit'],0)
            r.check_child_logs(out,r.read(out/'EXIT.json'))
            with (out/'stdout.log').open('ab') as f:f.write(b'changed after successful exit\n')
            with self.assertRaisesRegex(ValueError,'Changed stdout after recorded child exit'):
                r.check_child_logs(out,r.read(out/'EXIT.json'))
    def test_stderr_changed_after_successful_child_exit(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);out=root/'child'
            r.child([sys.executable,'-I','-S','-B','-c','pass'],root,out,5)
            with (out/'stderr.log').open('ab') as f:f.write(b'changed stderr\n')
            with self.assertRaisesRegex(ValueError,'Changed stderr after recorded child exit'):
                r.check_child_logs(out,r.read(out/'EXIT.json'))


if __name__=='__main__':unittest.main()

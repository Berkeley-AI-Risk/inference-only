"""Finite runner/parser controls, never a full-model numerical test."""
import importlib.util
from pathlib import Path
import tempfile
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

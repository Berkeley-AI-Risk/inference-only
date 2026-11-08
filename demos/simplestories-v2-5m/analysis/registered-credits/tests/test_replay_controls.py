"""CPU-only checks for optimized Python and preserved compiler/model errors."""
import ast
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REFUSAL = b"Assertions required: run without -O or -OO"


class ReplayControls(unittest.TestCase):
    def test_all_executable_proof_helpers_refuse_optimized_python(self):
        entries = []
        for path in [ROOT / "reproduce.py", *sorted((ROOT / "evidence").rglob("*.py"))]:
            tree = ast.parse(path.read_text())
            if not any(isinstance(n, ast.If) and ast.unparse(n.test) == "__name__ == '__main__'"
                       for n in tree.body):
                continue
            entries.append(path)
            self.assertEqual(ast.unparse(tree.body[1].test), "__name__ == '__main__' and (not __debug__)")
        self.assertEqual(len(entries), 10)
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp)
            env = dict(os.environ, TMPDIR=tmp, PATH=tmp)
            for path in entries:
                for flag in ("-O", "-OO"):
                    with self.subTest(script=str(path.relative_to(ROOT)), flag=flag):
                        if path == ROOT / "reproduce.py":
                            args = ["full", "missing-checkout", "--keep", "should-not-exist"]
                        elif path.name in ("replay.py", "ledger.py"):
                            args = ["missing-checkout", "should-not-exist"]
                        else:
                            args = ["missing-checkout"]
                        run = subprocess.run([sys.executable, "-I", "-S", "-B", flag, str(path), *args],
                                             cwd=empty, env=env, capture_output=True, timeout=10)
                        self.assertEqual(run.returncode, 1)
                        self.assertEqual(run.stdout, b"")
                        self.assertEqual(run.stderr.strip(), REFUSAL)
                        self.assertEqual(list(empty.iterdir()), [])

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.out = self.work / "kept"

    def put_executable(self, path, body):
        path.write_text("#!" + sys.executable + "\n" + body)
        path.chmod(0o755)

    def failed_replay(self):
        pin = os.environ.get("SIMPLESTORIES_FROZEN")
        if not pin:
            self.skipTest("set SIMPLESTORIES_FROZEN to the pinned release tree")
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        run = subprocess.run([sys.executable, "-I", "-S", "-B", str(ROOT / "evidence/support-sites/replay.py"),
                              pin, str(self.out)], cwd=self.work, env=env, capture_output=True, timeout=60)
        self.assertNotEqual(run.returncode, 0)
        return run

    def checked_receipt(self, label, status):
        logs = self.out / "native-runs"
        receipt = json.loads((logs / (label + ".json")).read_bytes())
        self.assertEqual(receipt["status"], "exited")
        self.assertEqual(receipt["returncode"], status)
        argv = json.dumps(receipt["argv"], ensure_ascii=True, separators=(",", ":")).encode()
        self.assertEqual(hashlib.sha256(argv).hexdigest(), receipt["argv_sha256"])
        log = (logs / receipt["merged_log"]).read_bytes()
        self.assertEqual(hashlib.sha256(log).hexdigest(), receipt["merged_log_sha256"])
        self.assertEqual(len(log), receipt["merged_log_bytes"])
        return receipt, log

    def test_compiler_failure_preserves_argv_status_and_both_streams(self):
        self.put_executable(self.bin / "verilator",
                            'import sys\nprint("control-stdout",flush=True)\nprint("compiler-error-37",file=sys.stderr)\nsys.exit(37)\n')
        run = self.failed_replay()
        self.assertIn(b"compiler-error-37", run.stderr)
        receipt, log = self.checked_receipt("build", 37)
        self.assertEqual(receipt["argv"][0], str(self.bin / "verilator"))
        self.assertIn("-GAUTH_BANKS=4", receipt["argv"])
        self.assertEqual(log, b"control-stdout\ncompiler-error-37\n")
        self.assertEqual(list(self.out.glob("*.trace")), [])

    def test_model_failure_keeps_its_raw_output_and_sibling_runs(self):
        self.put_executable(self.bin / "c++", 'print("fixture compiler invoked")\n')
        model_text = ("import sys\ntoken=int(sys.argv[-1].split('=')[1])\n"
                      "print('BOOT_AUTHENTICATED test-only-fixture',flush=True)\n"
                      "if token == 1:\n print('native-error-46',file=sys.stderr)\n sys.exit(46)\n"
                      "print('PUBLIC_TOKEN',token,{0:15,64:60}[token])\n")
        front = ("import os,shlex,subprocess,sys\nfrom pathlib import Path\n"
                 "flags=shlex.split(sys.argv[sys.argv.index('-MAKEFLAGS')+1])\n"
                 "driver=next(s.split('=',1)[1] for s in flags if s.startswith('CXX='))\n"
                 "subprocess.run([driver,'-c','fixture.cpp'],check=True)\n"
                 "obj=Path(sys.argv[sys.argv.index('--Mdir')+1]); obj.mkdir()\n"
                 "exe=obj/'Vtb_board1_booted_shared_semantic'\n"
                 f"exe.write_text({('#!' + sys.executable + chr(10) + model_text)!r})\n"
                 "exe.chmod(0o755)\n")
        self.put_executable(self.bin / "verilator", front)
        run = self.failed_replay()
        self.assertIn(b"native-error-46", run.stderr)
        build, _ = self.checked_receipt("build", 0)
        self.assertEqual(len(build["compiler_receipts"]), 1)
        failed, log = self.checked_receipt("token-1", 46)
        self.assertEqual(failed["argv"][-1], "+TOKEN=1")
        self.assertEqual(log, b"BOOT_AUTHENTICATED test-only-fixture\nnative-error-46\n")
        self.assertFalse((self.out / "token-1.trace").exists())
        for token in (0, 64):
            receipt, log = self.checked_receipt(f"token-{token}", 0)
            self.assertEqual(receipt["executable_sha256"], build["model_binary_sha256"])
            self.assertEqual((self.out / f"token-{token}.trace").read_bytes(), log)

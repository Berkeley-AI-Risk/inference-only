"""Fast tests; no formal tools, network, FPGA or generated artifacts needed."""
import importlib.util
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "tools/check_kv_integrity.py"


class ReplayRunnerTests(unittest.TestCase):
    def test_wrapper_rejects_optimized_python(self):
        for flag in ("-O", "-OO"):
            p = subprocess.run([sys.executable, "-I", "-S", "-B", flag, str(WRAPPER), "--help"], capture_output=True, text=True)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn("require assertions", p.stderr)

    def test_every_formal_helper_rejects_optimized_python(self):
        for script in sorted((ROOT / "formal/kv-integrity").glob("*.py")):
            with self.subTest(script=script.name):
                p = subprocess.run([sys.executable, "-I", "-S", "-B", "-O", str(script), "--help"], capture_output=True, text=True)
                self.assertNotEqual(p.returncode, 0)
                self.assertIn("require assertions", p.stderr)

    def test_wrapper_rejects_nonisolated_python(self):
        p = subprocess.run([sys.executable, "-S", "-B", str(WRAPPER), "--help"], capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("-I -S -B", p.stderr)

    @staticmethod
    def module():
        spec = importlib.util.spec_from_file_location("replay_wrapper_under_test", WRAPPER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_accept_exact_toolchain(self):
        module = self.module()
        versions = {name: name + " recorded build" for name in ("yosys", "z3", "cvc5")}
        def result(argv, **kwargs):
            return subprocess.CompletedProcess(argv, 0, stdout=versions[argv[0]] + "\n", stderr="")
        with patch.object(module.subprocess, "run", side_effect=result):
            self.assertEqual(module.check_tool_versions(versions, {n: n for n in versions}), versions)

    def test_reject_toolchain_before_proofs(self):
        module = self.module()
        versions = {name: name + " recorded build" for name in ("yosys", "z3", "cvc5")}
        with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="wrong build\n", stderr="")):
            with self.assertRaisesRegex(SystemExit, "no proofs started"):
                module.check_tool_versions(versions, {n: n for n in versions})


class BuildBindingTests(unittest.TestCase):
    def setUp(self):
        self.module = ReplayRunnerTests.module()
        self.source = "variants/kv-protected/hardware/project/example.sv"
        self.image = "prebuilt/kv-protected/project/impl/pnr/shared_product.fs"
        self.expected = {"production_sources": {self.source: "a" * 64}}
        self.inventory = {"project/example.sv": "a" * 64}
        canonical = (json.dumps(self.inventory, sort_keys=True, separators=(",", ":")) + "\n").encode()
        self.image_bytes = b"test image, not an FPGA configuration"
        self.build = {"schema": "fixed-fpga-local-build-v1", "variant": "kv-protected",
            "flow_completed": True, "source_inputs_verified": True, "source_inputs_unchanged": True,
            "hardware_inputs_sha256": hashlib.sha256(canonical).hexdigest(),
            "image_relative_path": "project/impl/pnr/shared_product.fs",
            "image_sha256": hashlib.sha256(self.image_bytes).hexdigest()}
        self.manifest = {self.image: {"sha256": self.build["image_sha256"]}}

    def check(self):
        files = {"host-app/hardware-inputs-kv-protected.json": json.dumps(self.inventory).encode(),
                 "prebuilt/kv-protected/BUILD.json": json.dumps(self.build).encode(),
                 self.image: self.image_bytes}
        return self.module.check_image_binding(files.__getitem__, self.expected, self.manifest)

    def test_complete_binding(self):
        result = self.check()
        self.assertEqual(result["proof_sources_in_build"], 1)
        self.assertFalse(result["attestation"])
        self.assertFalse(result["synthesis_equivalence_proved"])

    def test_wrong_proof_source(self):
        self.expected["production_sources"][self.source] = "b" * 64
        with self.assertRaises(AssertionError):
            self.check()

    def test_wrong_inventory_receipt(self):
        self.build["hardware_inputs_sha256"] = "0" * 64
        with self.assertRaises(AssertionError):
            self.check()

    def test_wrong_image_receipt(self):
        self.build["image_sha256"] = "0" * 64
        with self.assertRaises(AssertionError):
            self.check()

    def test_wrong_image_bytes(self):
        self.image_bytes += b"changed"
        with self.assertRaises(AssertionError):
            self.check()

    def test_wrong_variant(self):
        self.build["variant"] = "baseline"
        with self.assertRaises(AssertionError):
            self.check()


class FaultTargetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("fault_targets", ROOT / "formal/kv-integrity/check_fault_controls.py")
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)
        spec = importlib.util.spec_from_file_location("fault_contract", ROOT / "formal/kv-integrity/audit_contract.py")
        cls.contract = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.contract)

    def test_exact_target(self):
        smt = "; yosys-smt2-assert 7 cell guard.sv:1.1-1.25\n"
        self.assertEqual(self.module.target_index(smt, "guard.sv", "assert(ready);", "assert(ready);"), 7)

    def test_filename_suffix_rejected(self):
        for filename in ("otherguard.sv", "elsewhere/guard.sv"):
            with self.subTest(filename=filename), self.assertRaises(AssertionError):
                self.module.target_index(f"; yosys-smt2-assert 7 cell {filename}:1.1-1.25\n",
                                         "guard.sv", "assert(ready);", "assert(ready);")

    def test_duplicate_target_rejected(self):
        smt = "".join(f"; yosys-smt2-assert {i} cell guard.sv:1.1-1.25\n" for i in (7, 8))
        with self.assertRaises(AssertionError):
            self.module.target_index(smt, "guard.sv", "assert(ready);", "assert(ready);")

    def test_distinct_negative_directories(self):
        paths = self.contract.distinct_negative_paths(ROOT / "positive", [ROOT / "negative-a", ROOT / "negative-b"])
        self.assertEqual(len(paths), 2)

    def test_duplicate_negative_directory_rejected(self):
        with self.assertRaises(AssertionError):
            self.contract.distinct_negative_paths(ROOT / "positive", [ROOT / "negative-a", ROOT / "negative-a"])

    def test_positive_used_as_negative_rejected(self):
        with self.assertRaises(AssertionError):
            self.contract.distinct_negative_paths(ROOT / "positive", [ROOT / "positive", ROOT / "negative-b"])

if __name__ == "__main__":
    unittest.main()

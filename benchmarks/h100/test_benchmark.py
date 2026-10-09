"""Run with: python -B test_benchmark.py --model-dir PATH -v."""

import argparse
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import benchmark as bench
import model_snapshot as snapshot

MODEL_DIR = None


class BookkeepingTests(unittest.TestCase):
    def test_token_accounting(self):
        result = bench.summarize_samples([
            {"wall_seconds": 2.0}, {"wall_seconds": 1.0}, {"wall_seconds": 3.0}
        ], batch=16, iterations=100)
        self.assertEqual(result["tokens_counted_per_trial"], 1600)
        self.assertEqual(result["aggregate_tokens_per_second"], 800)
        self.assertEqual(result["tokens_per_second_per_sequence"], 50)
        self.assertEqual(result["milliseconds_per_decode_step"], 20)

    def test_invalid_timings_rejected(self):
        for value in (0, -1, float("nan"), float("inf")):
            with self.assertRaises(ValueError):
                bench.summarize_samples([{"wall_seconds": value}], 1, 1)
        with self.assertRaises(ValueError):
            bench.summarize_samples([], 1, 1)

    def test_default_plan(self):
        args = bench.parse_args(["--plan"])
        plan = bench.build_plan(args)
        self.assertEqual(len(plan), 15)
        self.assertEqual(plan[0], {"context": 128, "batch": 1, "mode": "eager"})
        self.assertEqual(plan[-1], {"context": 128, "batch": 1024, "mode": "compile-graph"})

    def test_plan_needs_no_model(self):
        args = bench.parse_args(["--plan", "--model-dir", "/does/not/exist"])
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(bench.controller(args), 0)
        self.assertEqual(json.loads(output.getvalue())["revision"], snapshot.REVISION)

    def test_invalid_arguments(self):
        for arguments in (["--contexts", "2049"], ["--batches", "0"],
                          ["--batches", "1,1"], ["--seconds", "nan"],
                          ["--seconds", "0"], ["--generation-tokens", "1"],
                          ["--max-runtime", "0"], ["--worker"]):
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    bench.parse_args(arguments)

    def test_invalid_modes(self):
        for modes in ("eager,eager", "unknown", ""):
            with self.assertRaises(ValueError):
                bench.build_plan(bench.parse_args(["--modes", modes]))

    def test_greedy_rounding_is_explicit_opt_in(self):
        self.assertFalse(bench.parse_args([]).allow_greedy_rounding)
        self.assertTrue(bench.parse_args(['--allow-greedy-rounding']).allow_greedy_rounding)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            bench.parse_args(['--allow-greedy-rounding', '--dtype', 'float32'])

    def test_modified_model_rejected(self):
        with self.assertRaises(ValueError):
            snapshot.check_bytes("config.json", b"{}")

    def test_existing_download_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "README.md"
            path.write_text("do not replace me")
            with self.assertRaises(ValueError):
                snapshot.fetch(directory)
            self.assertEqual(path.read_text(), "do not replace me")


class AcceptanceTests(unittest.TestCase):
    def test_strict_rejects_tie_change_but_opt_in_records_it(self):
        torch, _, _, _ = bench.load_stack()
        expected = torch.tensor([[8.0, 8.0]])
        actual = torch.tensor([[8.0, 8.0078125]])
        with self.assertRaises(ValueError):
            bench.check_optimized_outputs(actual, actual.argmax(-1), expected, expected.argmax(-1))
        comparison = bench.check_optimized_outputs(actual, actual.argmax(-1), expected,
                                                 expected.argmax(-1), allow_greedy_rounding=True)
        self.assertEqual(comparison['greedy_mismatch_count'], 1)
        self.assertEqual(comparison['argmax_agreement_fraction'], 0)
        self.assertEqual(comparison['acceptance_policy'], 'logit_tolerance_with_reported_greedy_rounding')

    def test_opt_in_still_rejects_bad_logits_and_nonfinite(self):
        torch, _, _, _ = bench.load_stack()
        expected = torch.tensor([[8.0, 8.0]])
        for actual in (torch.tensor([[8.0, 9.0]]), torch.tensor([[float('nan'), 8.0]])):
            with self.subTest(actual=actual), self.assertRaises((ValueError, AssertionError)):
                bench.check_optimized_outputs(actual, actual.argmax(-1), expected,
                                              expected.argmax(-1), allow_greedy_rounding=True)


class ModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if MODEL_DIR is None:
            raise unittest.SkipTest("pass --model-dir for real-checkpoint CPU tests")
        snapshot.verify(MODEL_DIR)
        cls.torch, _, _, _ = bench.load_stack()
        cls.torch.set_num_threads(4)
        cls.model = bench.load_model(MODEL_DIR, "float32", "cpu")

    def test_cached_matches_full_model(self):
        with self.torch.inference_mode():
            for batch, context in ((1, 1), (1, 3), (4, 16), (2, 128)):
                with self.subTest(batch=batch, context=context):
                    inputs = bench.make_inputs(batch, context, 123, "cpu")
                    check = bench.check_cached_against_full(self.model, inputs)
                    self.assertEqual(check["argmax_agreement_fraction"], 1)

    def test_cache_does_not_advance_or_corrupt_prefix(self):
        with self.torch.inference_mode():
            inputs = bench.make_inputs(2, 16, 123, "cpu")
            step = bench.FixedDecode(self.model, inputs)
            prefixes = [key[:, :, :-1].clone() for key in step.cache.key_cache]
            first, first_tokens = step()
            first = first.clone()
            for _ in range(3):
                latest, latest_tokens = step()
                self.torch.testing.assert_close(first, latest, rtol=0, atol=0)
                self.assertTrue(self.torch.equal(first_tokens, latest_tokens))
            for old, key in zip(prefixes, step.cache.key_cache):
                self.assertTrue(self.torch.equal(old, key[:, :, :-1]))
            self.assertEqual(step.position.item(), 15)

    def test_final_input_is_really_used(self):
        with self.torch.inference_mode():
            inputs = bench.make_inputs(2, 8, 123, "cpu")
            step = bench.FixedDecode(self.model, inputs)
            before, _ = step()
            before = before.clone()
            inputs[:, -1] = (inputs[:, -1] + 3) % 4019
            step.input_ids.copy_(inputs[:, -1:])
            after, _ = step()
            expected = self.model(input_ids=inputs, use_cache=False, num_logits_to_keep=1).logits[:, -1, :]
            self.assertFalse(self.torch.equal(before, after))
            self.torch.testing.assert_close(after, expected, rtol=0.01, atol=0.002)

    def test_real_generation(self):
        with self.torch.inference_mode():
            result = bench.actual_generation(self.model, MODEL_DIR, "cpu", 8, 2)
        self.assertEqual(len(result["trials"]), 2)
        self.assertEqual(len(result["trials"][0]["token_ids"]), 8)
        self.assertEqual(result["trials"][0]["token_ids"], result["trials"][1]["token_ids"])
        self.assertGreater(result["trials"][0]["first_token_seconds"], 0)

    def test_fullgraph_tracing_and_mutable_input(self):
        # Exercise Dynamo's whole-graph capture on CPU. CUDA code generation and
        # CUDA graph replay still require the real GPU acceptance run.
        with self.torch.inference_mode():
            inputs = bench.make_inputs(2, 16, 123, "cpu")
            step = bench.FixedDecode(self.model, inputs)
            traced = self.torch.compile(step, backend="eager", fullgraph=True, dynamic=False)
            eager_logits, eager_tokens = step()
            traced_logits, traced_tokens = traced()
            self.torch.testing.assert_close(traced_logits, eager_logits, rtol=0, atol=0)
            self.assertTrue(self.torch.equal(traced_tokens, eager_tokens))
            step.input_ids.add_(1).remainder_(4019)
            new_logits, _ = traced()
            expected, _ = step()
            self.torch.testing.assert_close(new_logits, expected, rtol=0, atol=0)
            self.assertFalse(self.torch.equal(new_logits, traced_logits))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--model-dir", type=Path)
    known, remaining = parser.parse_known_args()
    MODEL_DIR = known.model_dir
    unittest.main(argv=[__file__, *remaining])

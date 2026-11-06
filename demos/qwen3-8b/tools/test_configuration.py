"""Run the common finite selection tests against the released 8B configuration."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT.parent / 'qwen3-1.7b/tools/test_configuration.py'


if __name__ == '__main__':
    spec = importlib.util.spec_from_file_location('common_qwen_configuration_tests', HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.main(model='qwen3-8b', root=ROOT)

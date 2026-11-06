"""Read-only 8B entry point for the common released-Qwen selection checker."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT.parent / 'qwen3-1.7b/tools/check_configuration.py'


def common():
    spec = importlib.util.spec_from_file_location('common_qwen_configuration', HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


if __name__ == '__main__':
    common().main(model='qwen3-8b', root=ROOT)

#!/usr/bin/env python3
"""Build or verify deterministic fixed-weight ROM images."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from quantization import (  # noqa: E402
    QuantizationError,
    build_artifacts,
    check_artifacts,
    publish_artifacts,
)
from reference import load_model  # noqa: E402


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="quantize the pinned SimpleStories checkpoint into canonical ROMs"
    )
    result.add_argument(
        "model_directory", help="authenticated upstream snapshot directory"
    )
    result.add_argument("output_directory", help="external ROM artifact directory")
    result.add_argument(
        "--check",
        action="store_true",
        help="verify byte identity without changing the output directory",
    )
    return result


def main(arguments: list[str] | None = None) -> int:
    options = parser().parse_args(arguments)
    try:
        model = load_model(options.model_directory)
        artifacts = build_artifacts(model)
        if options.check:
            check_artifacts(options.output_directory, artifacts)
            action = "verified"
        else:
            publish_artifacts(options.output_directory, artifacts)
            check_artifacts(options.output_directory, artifacts)
            action = "published and verified"
    except (QuantizationError, ValueError, OSError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    total = sum(len(payload) for payload in artifacts.values())
    print(
        f"PASS: {action} {len(artifacts)} canonical artifacts "
        f"({total} bytes) at {Path(options.output_directory).resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

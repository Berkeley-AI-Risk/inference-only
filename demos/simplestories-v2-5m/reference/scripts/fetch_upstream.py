#!/usr/bin/env python3
"""Fetch or verify the exact SimpleStories V2 5M upstream snapshot.

This importer deliberately understands only regular data files listed in the
committed manifest.  It does not import model Python, deserialize pickle/Torch
objects, or invoke Hugging Face libraries.
"""

from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
import errno
import hashlib
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from typing import Any, Iterable, Sequence
from urllib.error import URLError
from urllib.request import Request, urlopen


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "upstream" / "manifest.json"
PINNED_REPOSITORY = "SimpleStories/SimpleStories-V2-5M"
PINNED_REVISION = "c4b3a4bb81297f5316697098e1d4b65c1249daf8"
PINNED_LICENSE = "MIT"
PINNED_PATHS = (
    "README.md",
    "config.json",
    "model.safetensors",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer_config.json",
)
MANIFEST_KEYS = {"schema_version", "repository", "revision", "license", "files"}
FILE_KEYS = {"path", "size", "sha256", "url"}
RECEIPT_SCHEMA_VERSION = 1
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
REVISION_RE = re.compile(r"[0-9a-f]{40}\Z")
CHUNK_BYTES = 1024 * 1024
USER_AGENT = "simplestories-pinned-importer/1"
DARWIN_RENAME_EXCL = 0x00000004
DARWIN_RENAME_NOFOLLOW_ANY = 0x00000010


class UpstreamError(Exception):
    """A manifest, download, or snapshot verification failure."""


@dataclass(frozen=True)
class FileSpec:
    path: str
    size: int
    sha256: str
    url: str


@dataclass(frozen=True)
class Manifest:
    repository: str
    revision: str
    license: str
    files: tuple[FileSpec, ...]


@dataclass(frozen=True)
class FetchResult:
    downloaded: tuple[str, ...]
    reused: tuple[str, ...]


def _object_without_duplicate_keys(pairs: Iterable[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise UpstreamError(f"manifest contains duplicate key {key!r}")
        result[key] = value
    return result


def _require_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise UpstreamError(
            f"{label} keys differ: missing={missing!r}, unexpected={extra!r}"
        )


def _exact_url(repository: str, revision: str, path: str) -> str:
    return f"https://huggingface.co/{repository}/resolve/{revision}/{path}"


def load_manifest(path: Path = MANIFEST_PATH) -> Manifest:
    """Load and strictly validate the committed import manifest."""

    try:
        raw = path.read_bytes()
    except OSError as error:
        raise UpstreamError(f"cannot read manifest {path}: {error}") from error
    if len(raw) > 1024 * 1024:
        raise UpstreamError("manifest is unexpectedly larger than 1 MiB")
    try:
        document = json.loads(
            raw.decode("utf-8"), object_pairs_hook=_object_without_duplicate_keys
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise UpstreamError(f"manifest is not strict UTF-8 JSON: {error}") from error
    if not isinstance(document, dict):
        raise UpstreamError("manifest root must be an object")
    _require_exact_keys(document, MANIFEST_KEYS, "manifest")
    if type(document["schema_version"]) is not int or document["schema_version"] != 1:
        raise UpstreamError("manifest schema_version must be integer 1")
    repository = document["repository"]
    revision = document["revision"]
    license_name = document["license"]
    if repository != PINNED_REPOSITORY:
        raise UpstreamError(f"repository is not pinned to {PINNED_REPOSITORY}")
    if revision != PINNED_REVISION or not isinstance(revision, str):
        raise UpstreamError(f"revision is not pinned to {PINNED_REVISION}")
    if not REVISION_RE.fullmatch(revision):
        raise UpstreamError("revision must be a full lowercase 40-digit commit")
    if license_name != PINNED_LICENSE:
        raise UpstreamError(f"license declaration must be {PINNED_LICENSE!r}")
    raw_files = document["files"]
    if not isinstance(raw_files, list):
        raise UpstreamError("manifest files must be an array")

    files: list[FileSpec] = []
    for index, item in enumerate(raw_files):
        label = f"manifest file {index}"
        if not isinstance(item, dict):
            raise UpstreamError(f"{label} must be an object")
        _require_exact_keys(item, FILE_KEYS, label)
        file_path = item["path"]
        size = item["size"]
        digest = item["sha256"]
        url = item["url"]
        if (
            not isinstance(file_path, str)
            or not file_path
            or Path(file_path).name != file_path
            or file_path in {".", ".."}
        ):
            raise UpstreamError(f"{label} path must be a single safe file name")
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            raise UpstreamError(f"{label} size must be a positive integer")
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            raise UpstreamError(f"{label} sha256 must be 64 lowercase hex digits")
        expected_url = _exact_url(repository, revision, file_path)
        if url != expected_url:
            raise UpstreamError(f"{label} URL must be exact: {expected_url}")
        files.append(FileSpec(file_path, size, digest, url))

    paths = tuple(spec.path for spec in files)
    if paths != tuple(sorted(paths)):
        raise UpstreamError("manifest files must be ordered by path")
    if paths != PINNED_PATHS:
        raise UpstreamError(
            f"manifest file inventory must be exactly {list(PINNED_PATHS)!r}"
        )
    return Manifest(repository, revision, license_name, tuple(files))


def _repository_root() -> Path:
    for candidate in (PROJECT_ROOT, *PROJECT_ROOT.parents):
        if (candidate / ".git").exists():
            return candidate.resolve()
    return PROJECT_ROOT.resolve()


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def validate_destination(directory: Path) -> Path:
    """Require a dedicated destination outside the source repository."""

    try:
        resolved = directory.expanduser().resolve(strict=False)
        repository_root = _repository_root()
        home = Path.home().resolve()
    except (OSError, RuntimeError, ValueError) as error:
        raise UpstreamError(f"cannot resolve destination: {error}") from error
    if resolved == resolved.parent:
        raise UpstreamError("destination cannot be a filesystem root")
    if resolved == home:
        raise UpstreamError("destination cannot be the home directory")
    if _is_within(resolved, repository_root):
        raise UpstreamError(
            f"destination must be outside the source repository {repository_root}"
        )
    return resolved


def _scan_directory(directory: Path, manifest: Manifest) -> set[str]:
    if not directory.exists():
        raise UpstreamError(f"snapshot directory does not exist: {directory}")
    if directory.is_symlink() or not directory.is_dir():
        raise UpstreamError(
            f"snapshot destination is not a real directory: {directory}"
        )
    allowed = {spec.path for spec in manifest.files}
    present: set[str] = set()
    try:
        with os.scandir(directory) as iterator:
            entries = list(iterator)
    except OSError as error:
        raise UpstreamError(f"cannot inspect snapshot directory: {error}") from error
    for entry in entries:
        if entry.name not in allowed:
            raise UpstreamError(f"unexpected snapshot entry: {entry.name!r}")
        try:
            mode = entry.stat(follow_symlinks=False).st_mode
        except OSError as error:
            raise UpstreamError(f"cannot inspect {entry.name!r}: {error}") from error
        if not stat.S_ISREG(mode):
            raise UpstreamError(f"snapshot entry is not a regular file: {entry.name!r}")
        present.add(entry.name)
    return present


def _hash_file(path: Path, expected_size: int) -> tuple[int, str]:
    digest = hashlib.sha256()
    total = 0
    descriptor: int | None = None
    try:
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path, flags)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise UpstreamError(f"pinned path is not a regular file: {path.name!r}")
        with os.fdopen(descriptor, "rb") as source:
            descriptor = None
            while True:
                block = source.read(CHUNK_BYTES)
                if not block:
                    break
                total += len(block)
                if total > expected_size:
                    raise UpstreamError(
                        f"{path.name}: size exceeds expected {expected_size} bytes"
                    )
                digest.update(block)
    except UpstreamError:
        raise
    except OSError as error:
        raise UpstreamError(f"cannot read {path.name!r}: {error}") from error
    finally:
        if descriptor is not None:
            os.close(descriptor)
    return total, digest.hexdigest()


def verify_file(path: Path, spec: FileSpec) -> None:
    try:
        mode = os.stat(path, follow_symlinks=False).st_mode
    except FileNotFoundError as error:
        raise UpstreamError(f"missing pinned file: {spec.path}") from error
    except OSError as error:
        raise UpstreamError(f"cannot inspect {spec.path!r}: {error}") from error
    if not stat.S_ISREG(mode):
        raise UpstreamError(f"pinned path is not a regular file: {spec.path!r}")
    size, digest = _hash_file(path, spec.size)
    if size != spec.size:
        raise UpstreamError(
            f"{spec.path}: size mismatch (expected {spec.size}, found {size})"
        )
    if digest != spec.sha256:
        raise UpstreamError(
            f"{spec.path}: SHA-256 mismatch (expected {spec.sha256}, found {digest})"
        )


def check_snapshot(directory: Path, manifest: Manifest) -> None:
    """Verify a complete exact snapshot without performing network access."""

    present = _scan_directory(directory, manifest)
    missing = [spec.path for spec in manifest.files if spec.path not in present]
    if missing:
        raise UpstreamError(f"missing pinned files: {missing!r}")
    for spec in manifest.files:
        verify_file(directory / spec.path, spec)


def _content_length(response: Any, spec: FileSpec) -> None:
    raw_length = response.headers.get("Content-Length")
    if raw_length is not None:
        try:
            length = int(raw_length, 10)
        except (TypeError, ValueError) as error:
            raise UpstreamError(
                f"{spec.path}: invalid HTTP Content-Length {raw_length!r}"
            ) from error
        if length != spec.size:
            raise UpstreamError(
                f"{spec.path}: HTTP Content-Length mismatch "
                f"(expected {spec.size}, found {length})"
            )
    encoding = response.headers.get("Content-Encoding")
    if encoding is not None and encoding.lower() != "identity":
        raise UpstreamError(f"{spec.path}: unsupported Content-Encoding {encoding!r}")


def _darwin_rename_exclusive(
    directory_descriptor: int, source_name: str, target_name: str
) -> None:
    """Atomically rename one directory entry without replacing another on macOS."""

    library = ctypes.CDLL(None, use_errno=True)
    try:
        renameatx_np = library.renameatx_np
    except AttributeError as error:  # pragma: no cover - pre-10.12 macOS only
        raise OSError(errno.ENOSYS, "renameatx_np is unavailable") from error
    renameatx_np.argtypes = (
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    )
    renameatx_np.restype = ctypes.c_int
    result = renameatx_np(
        directory_descriptor,
        os.fsencode(source_name),
        directory_descriptor,
        os.fsencode(target_name),
        DARWIN_RENAME_EXCL | DARWIN_RENAME_NOFOLLOW_ANY,
    )
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number), target_name)


def _portable_rename_exclusive(
    directory_descriptor: int, source_name: str, target_name: str
) -> None:
    """No-clobber fallback using an atomic hard-link creation.

    Both names are relative to the same already-open directory.  ``os.link``
    fails with EEXIST for every existing destination type, including a
    symlink, so this fallback never silently degrades to replacement.
    """

    os.link(
        source_name,
        target_name,
        src_dir_fd=directory_descriptor,
        dst_dir_fd=directory_descriptor,
        follow_symlinks=False,
    )
    os.unlink(source_name, dir_fd=directory_descriptor)


def _rename_exclusive(
    directory_descriptor: int, source_name: str, target_name: str
) -> None:
    if sys.platform == "darwin":
        try:
            _darwin_rename_exclusive(
                directory_descriptor, source_name, target_name
            )
            return
        except OSError as error:
            if error.errno not in {errno.ENOSYS, errno.ENOTSUP}:
                raise
    _portable_rename_exclusive(directory_descriptor, source_name, target_name)


def _publish_no_clobber(stage_path: Path, target: Path) -> None:
    """Publish ``stage_path`` atomically, or leave an existing target intact."""

    if stage_path.parent != target.parent:
        raise UpstreamError("staged file and target are not in the same directory")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    directory_descriptor: int | None = None
    try:
        directory_descriptor = os.open(stage_path.parent, flags)
        _rename_exclusive(directory_descriptor, stage_path.name, target.name)
        # The file data was fsynced before publication.  Persist the directory
        # entry as well before reporting success.
        os.fsync(directory_descriptor)
    except FileExistsError as error:
        raise UpstreamError(
            f"{target.name}: destination appeared during download; "
            "refusing overwrite"
        ) from error
    except UpstreamError:
        raise
    except OSError as error:
        raise UpstreamError(
            f"{target.name}: exclusive publication failed: {error}"
        ) from error
    finally:
        if directory_descriptor is not None:
            os.close(directory_descriptor)


def _download_one(directory: Path, spec: FileSpec) -> None:
    request = Request(
        spec.url,
        headers={"Accept-Encoding": "identity", "User-Agent": USER_AGENT},
        method="GET",
    )
    stage_path: Path | None = None
    try:
        try:
            response_context = urlopen(request, timeout=60)
        except (OSError, URLError, HTTPException) as error:
            raise UpstreamError(f"{spec.path}: download failed: {error}") from error
        with response_context as response:
            status_code = getattr(response, "status", None)
            if status_code != 200:
                raise UpstreamError(
                    f"{spec.path}: expected HTTP 200, found {status_code!r}"
                )
            _content_length(response, spec)
            digest = hashlib.sha256()
            total = 0
            with tempfile.NamedTemporaryFile(
                mode="wb",
                dir=directory,
                prefix=".fetch-",
                suffix=".part",
                delete=False,
            ) as stage:
                stage_path = Path(stage.name)
                while True:
                    try:
                        block = response.read(CHUNK_BYTES)
                    except (OSError, HTTPException) as error:
                        raise UpstreamError(
                            f"{spec.path}: response read failed: {error}"
                        ) from error
                    if not block:
                        break
                    total += len(block)
                    if total > spec.size:
                        raise UpstreamError(
                            f"{spec.path}: response exceeds {spec.size} bytes"
                        )
                    digest.update(block)
                    stage.write(block)
                stage.flush()
                os.fsync(stage.fileno())
            if total != spec.size:
                raise UpstreamError(
                    f"{spec.path}: downloaded size mismatch "
                    f"(expected {spec.size}, found {total})"
                )
            actual_digest = digest.hexdigest()
            if actual_digest != spec.sha256:
                raise UpstreamError(
                    f"{spec.path}: downloaded SHA-256 mismatch "
                    f"(expected {spec.sha256}, found {actual_digest})"
                )

        target = directory / spec.path
        _publish_no_clobber(stage_path, target)
        stage_path = None
    except UpstreamError:
        raise
    except OSError as error:
        raise UpstreamError(f"{spec.path}: local staging failed: {error}") from error
    finally:
        if stage_path is not None:
            try:
                stage_path.unlink()
            except FileNotFoundError:
                pass
            except OSError as error:
                raise UpstreamError(
                    f"cannot remove staged file {stage_path.name!r}: {error}"
                ) from error


def fetch_snapshot(directory: Path, manifest: Manifest) -> FetchResult:
    """Fetch missing files, reusing only exact existing files."""

    try:
        directory.mkdir(mode=0o755, parents=True, exist_ok=True)
    except OSError as error:
        raise UpstreamError(f"cannot create snapshot directory: {error}") from error
    present = _scan_directory(directory, manifest)
    downloaded: list[str] = []
    reused: list[str] = []
    for spec in manifest.files:
        if spec.path in present:
            verify_file(directory / spec.path, spec)
            reused.append(spec.path)
        else:
            _download_one(directory, spec)
            downloaded.append(spec.path)
    check_snapshot(directory, manifest)
    return FetchResult(tuple(downloaded), tuple(reused))


def _sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for block in iter(lambda: source.read(CHUNK_BYTES), b""):
                digest.update(block)
    except OSError as error:
        raise UpstreamError(f"cannot hash evidence input {path}: {error}") from error
    return digest.hexdigest()


def canonical_receipt(directory: Path, manifest: Manifest) -> bytes:
    """Return a deterministic receipt for an already verified snapshot.

    The receipt deliberately contains no path, host, or timestamp.  Independent
    imports of the same bytes with the same verifier therefore produce the same
    evidence artifact.
    """

    check_snapshot(directory, manifest)
    document = {
        "files": [
            {
                "path": spec.path,
                "sha256": spec.sha256,
                "size": spec.size,
            }
            for spec in manifest.files
        ],
        "license": manifest.license,
        "repository": manifest.repository,
        "result": "PASS",
        "revision": manifest.revision,
        "schema_version": RECEIPT_SCHEMA_VERSION,
        "source_manifest_sha256": _sha256_path(MANIFEST_PATH),
        "total_bytes": sum(spec.size for spec in manifest.files),
        "verifier_sha256": _sha256_path(Path(__file__).resolve()),
    }
    return (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _write_atomic(path: Path, payload: bytes) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as stage:
            stage_path = Path(stage.name)
            stage.write(payload)
            stage.flush()
            os.fsync(stage.fileno())
        try:
            os.replace(stage_path, path)
            directory_descriptor = os.open(
                path.parent,
                os.O_RDONLY | getattr(os, "O_DIRECTORY", 0),
            )
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
        finally:
            try:
                stage_path.unlink()
            except FileNotFoundError:
                pass
    except OSError as error:
        raise UpstreamError(f"cannot publish receipt {path}: {error}") from error


def write_receipt(path: Path, directory: Path, manifest: Manifest) -> None:
    _write_atomic(path, canonical_receipt(directory, manifest))


def verify_receipt(path: Path, directory: Path, manifest: Manifest) -> None:
    expected = canonical_receipt(directory, manifest)
    try:
        actual = path.read_bytes()
    except OSError as error:
        raise UpstreamError(f"cannot read receipt {path}: {error}") from error
    if actual != expected:
        raise UpstreamError(
            f"receipt is stale or noncanonical: {path}; regenerate it explicitly"
        )


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "fetch and verify the exact pinned SimpleStories V2 5M data files "
            "into a dedicated directory outside this repository"
        )
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="offline verification only; never open the network",
    )
    receipt_group = parser.add_mutually_exclusive_group()
    receipt_group.add_argument(
        "--write-receipt",
        type=Path,
        metavar="PATH",
        help="atomically write a deterministic PASS receipt after verification",
    )
    receipt_group.add_argument(
        "--verify-receipt",
        type=Path,
        metavar="PATH",
        help="require an existing receipt to equal the canonical current receipt",
    )
    parser.add_argument(
        "directory", type=Path, help="external snapshot/cache directory"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _argument_parser().parse_args(argv)
    try:
        manifest = load_manifest()
        directory = validate_destination(arguments.directory)
        if arguments.check:
            check_snapshot(directory, manifest)
            action = "offline-verified"
        else:
            result = fetch_snapshot(directory, manifest)
            action = (
                f"verified (downloaded={len(result.downloaded)}, "
                f"reused={len(result.reused)})"
            )
        if arguments.write_receipt is not None:
            write_receipt(arguments.write_receipt, directory, manifest)
            action += f"; wrote receipt {arguments.write_receipt}"
        elif arguments.verify_receipt is not None:
            verify_receipt(arguments.verify_receipt, directory, manifest)
            action += f"; verified receipt {arguments.verify_receipt}"
        total_bytes = sum(spec.size for spec in manifest.files)
        print(
            f"PASS: {action} {len(manifest.files)} pinned files "
            f"({total_bytes} bytes) at {directory}"
        )
        return 0
    except UpstreamError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

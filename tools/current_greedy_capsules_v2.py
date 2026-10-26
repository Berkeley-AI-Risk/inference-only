"""Bounded portable reads of unchanged raw evidence, never original-machine IO.

An explicit capsule maps each original absolute provenance path to packaged
bytes. Paths and argv inside raw records are untouched. Canonical-origin labels
are export observations used only for declared same-file cross-bindings; equal
content at different original files does not establish alias ownership.
"""
import gzip
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import re
import stat

MAX_OBJECT = 100 * 1024**2
MAX_EXPANDED = 128 * 1024**2
MAX_JSON = 16 * 1024**2
MAX_FILES = 4096
MAX_TOTAL = 2 * 1024**3


def need(ok, message):
    if not ok:
        raise ValueError(message)


def raw_identity(raw):
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def expected(row, maximum=MAX_EXPANDED):
    need(type(row) is dict and set(row) == {'bytes', 'sha256'}
         and type(row['bytes']) is int and 0 <= row['bytes'] <= maximum
         and type(row['sha256']) is str and re.fullmatch('[0-9a-f]{64}', row['sha256']),
         'Bounded exact byte/SHA identity required')
    return row


def file_pin(row, maximum=MAX_OBJECT):
    need(type(row) is dict and set(row) == {'path', 'bytes', 'sha256'}
         and type(row['path']) is str, 'Exact three-key portable file identity required')
    expected({key: row[key] for key in ('bytes', 'sha256')}, maximum)
    return row


def original_path(name):
    need(type(name) is str and name and '\x00' not in name and '\\' not in name,
         'Original POSIX provenance path required')
    path = PurePosixPath(name)
    need(path.is_absolute() and str(path) == name and '..' not in path.parts,
         'Canonical-form absolute provenance path required')
    return name


def member(package, name):
    need(type(name) is str and name and '\x00' not in name and '\\' not in name and ':' not in name,
         'Safe relative portable path required')
    relative = PurePosixPath(name)
    need(str(relative) == name and not relative.is_absolute() and '..' not in relative.parts,
         'Safe relative portable member required')
    package = Path(package).resolve(strict=True)
    path = package / relative
    need(not any(p.is_symlink() for p in (path, *path.parents) if p.is_relative_to(package)),
         'Linked portable member refused')
    return path


def identity(path, maximum=MAX_OBJECT):
    path = Path(path)
    before = path.lstat()
    need(stat.S_ISREG(before.st_mode) and before.st_size <= maximum, 'Bounded regular portable file required')
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    after = path.lstat()
    keys = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
    need(all(getattr(before, key) == getattr(after, key) for key in keys), 'Portable file changed during read')
    return dict(bytes=before.st_size, sha256=digest)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'Duplicate evidence JSON key')
        result[key] = value
    return result


def finite_tree(value, depth=0):
    need(depth <= 64, 'Evidence JSON nesting bound exceeded')
    if isinstance(value, float):
        need(math.isfinite(value), 'Nonfinite evidence number')
    elif isinstance(value, dict):
        for item in value.values():
            finite_tree(item, depth + 1)
    elif isinstance(value, list):
        for item in value:
            finite_tree(item, depth + 1)


def decode(raw):
    need(len(raw) <= MAX_JSON, 'Evidence JSON exceeds explicit bound')
    try:
        result = json.loads(raw, object_pairs_hook=unique_object,
                            parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite JSON constant')))
        finite_tree(result)
    except (RecursionError, UnicodeError) as error:
        raise ValueError('Malformed/big evidence JSON') from error
    return result


class Capsule:
    def __init__(self, package, capsule_pin):
        self.package = Path(package).resolve(strict=True)
        file_pin(capsule_pin)
        path = member(self.package, capsule_pin['path'])
        need(identity(path) == {key: capsule_pin[key] for key in ('bytes', 'sha256')}, 'Portable capsule changed')
        raw = path.read_bytes()
        need(raw_identity(raw) == {key: capsule_pin[key] for key in ('bytes', 'sha256')}
             and identity(path) == raw_identity(raw), 'Portable capsule changed while decoding')
        self.capsule_path = path
        self.capsule_identity = raw_identity(raw)
        self.data = decode(raw)
        need(self.data['schema'] == 'current-greedy-portable-evidence-capsule-v1', 'Known portable capsule schema required')
        self.variant = self.data['variant']
        self.bindings = self.data['bindings']
        need(type(self.bindings) is dict and 0 < len(self.bindings) <= MAX_FILES, 'Bounded origin map required')
        total = 0
        portable = {}
        for origin, row in self.bindings.items():
            original_path(origin)
            need(set(row) == {'original', 'canonical_origin', 'portable', 'encoding'}, 'Exact portable binding fields required')
            need(file_pin(row['original'], MAX_EXPANDED)['path'] == origin, 'Original origin identity differs')
            original_path(row['canonical_origin'])
            file_pin(row['portable'])
            member(self.package, row['portable']['path'])
            need(row['encoding'] in ('plain', 'gzip'), 'Only explicit plain/gzip evidence supported')
            if row['encoding'] == 'plain':
                need({key: row['portable'][key] for key in ('bytes', 'sha256')} ==
                     {key: row['original'][key] for key in ('bytes', 'sha256')}, 'Plain snapshot identity differs')
            name = row['portable']['path']
            wanted = {key: row['original'][key] for key in ('bytes', 'sha256')}
            need(name not in portable or portable[name] == wanted, 'Portable object reused for different raw identities')
            portable[name] = wanted
            total += row['original']['bytes']
        need(total <= MAX_TOTAL, 'Expanded capsule bound exceeded')
        need(type(self.data['roles']) is dict and all(value is None or value in self.bindings
             for value in self.data['roles'].values()), 'Role has no actual origin binding')
        self.consumed = {}

    def read(self, origin, wanted=None, maximum=MAX_EXPANDED):
        original_path(origin)
        need(origin in self.bindings, 'Original evidence path is not exported: ' + origin)
        row = self.bindings[origin]
        raw_wanted = {key: row['original'][key] for key in ('bytes', 'sha256')}
        expected(raw_wanted, maximum)
        if wanted is not None:
            expected({key: wanted[key] for key in ('bytes', 'sha256')}, maximum)
            need(raw_wanted == {key: wanted[key] for key in ('bytes', 'sha256')}, 'Raw origin pin differs')
            if 'path' in wanted:
                need(wanted['path'] == origin, 'Raw original path was retargeted')
        path = member(self.package, row['portable']['path'])
        encoded = {key: row['portable'][key] for key in ('bytes', 'sha256')}
        need(identity(path) == encoded, 'Packaged evidence object changed')
        with path.open('rb') as stream:
            reader = gzip.GzipFile(fileobj=stream) if row['encoding'] == 'gzip' else stream
            try:
                raw = reader.read(raw_wanted['bytes'] + 1)
                need(len(raw) <= raw_wanted['bytes'] and reader.read(1) == b'', 'Expanded evidence exceeds exact bound')
            except (OSError, EOFError) as error:
                raise ValueError('Corrupt compressed evidence') from error
            finally:
                if reader is not stream:
                    reader.close()
        need(raw_identity(raw) == raw_wanted and identity(path) == encoded, 'Raw evidence bytes/SHA differ')
        self.consumed[origin] = dict(original=row['original'], portable=row['portable'], encoding=row['encoding'])
        return raw

    def json(self, origin, wanted=None):
        return decode(self.read(origin, wanted, MAX_JSON))

    def role(self, name):
        need(name in self.data['roles'] and self.data['roles'][name] is not None,
             'Required current role is pending: ' + name)
        return self.json(self.data['roles'][name])

    def pin(self, origin):
        need(origin in self.bindings, 'Missing exported origin')
        return self.bindings[origin]['original']

    def same_file(self, first, second):
        need(first in self.bindings and second in self.bindings, 'Same-file origin absent')
        a, b = self.bindings[first], self.bindings[second]
        return (a['canonical_origin'] == b['canonical_origin'] and
                {key: a['original'][key] for key in ('bytes', 'sha256')} ==
                {key: b['original'][key] for key in ('bytes', 'sha256')})

    def unchanged(self):
        need(identity(self.capsule_path) == self.capsule_identity, 'Capsule manifest changed during replay')
        for row in self.consumed.values():
            need(identity(member(self.package, row['portable']['path'])) ==
                 {key: row['portable'][key] for key in ('bytes', 'sha256')}, 'Consumed portable evidence changed')

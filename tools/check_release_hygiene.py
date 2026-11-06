"""Read-only local-link and metadata inventory; never emits matched content.

No network, subprocess, HDL, proof, archive rewriting or publication actions.
Link parsing covers inline Markdown and HTML href/src, not reference definitions.
Metadata scanning covers file bytes and one gzip layer, not nested zip archives.
"""
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone
import argparse
import gzip
import hashlib
import html
import json
import os
import re
import resource
import signal
import time
import unicodedata
from urllib.parse import unquote, urlsplit

PATTERNS = {
    'user_home_path': re.compile(rb'/Users/[A-Za-z0-9_.-]{1,64}(?:/|(?=[\x00\s\"\']))'),
    'unix_home_path': re.compile(rb'/home/[A-Za-z0-9_.-]{1,64}(?:/|(?=[\x00\s\"\']))'),
    'provider_folder_name': re.compile(rb'Dropbox'),
    'possible_AWS_access_key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'possible_private_key_header': re.compile(rb'-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----'),
}


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def without_fences(text):
    fence = None
    result = []
    for line in text.splitlines(True):
        mark = re.match(r'^\s{0,3}(`{3,}|~{3,})', line)
        if mark:
            token = mark[1][0]
            if fence is None:
                fence = token
            elif token == fence:
                fence = None
            result.append('\n')
        else:
            result.append('\n' if fence else line)
    return ''.join(result)


def anchors(text):
    text = without_fences(text)
    found = set(re.findall(r'<a\b[^>]*\b(?:id|name)=["\']([^"\']+)', text, re.I))
    counts = Counter()
    lines = text.splitlines()
    for i, line in enumerate(lines):
        match = re.match(r'^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$', line)
        heading = match[1] if match else None
        if heading is None and i + 1 < len(lines) and re.fullmatch(r' {0,3}(?:=+|-+)\s*', lines[i + 1]):
            heading = line.strip()
        if not heading:
            continue
        heading = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', heading)
        heading = html.unescape(re.sub(r'<[^>]*>', '', heading)).lower().replace('`', '')
        slug = ''.join(ch for ch in heading if ch in ' _-' or unicodedata.category(ch)[0] in 'LNM')
        slug = slug.replace(' ', '-')
        number = counts[slug]
        counts[slug] += 1
        found.add(slug + ('-' + str(number) if number else ''))
    return found


def links(path, root, cache, members=None):
    if path.stat().st_size > 8 << 20:
        return [], 0, ['Markdown exceeds8MiB parsing limit']
    text = without_fences(path.read_text(encoding='utf-8'))
    # Inline code can contain example links rather than repository references.
    text = re.sub(r'`[^`\n]*`', '', text)
    matches = []
    for match in re.finditer(r'!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))(?:\s+["\'][^\n]*?["\'])?\s*\)', text):
        matches.append((match.start(), match[1] or match[2]))
    for match in re.finditer(r'<(?:a|img)\b[^>]*\b(?:href|src)=["\']([^"\']+)', text, re.I):
        matches.append((match.start(), match[1]))
    problems, checked, limitations = [], 0, []
    for offset, target in matches:
        target = html.unescape(target)
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc:
            continue
        checked += 1
        relative = unquote(parsed.path)
        destination = (path if not relative else root / relative.lstrip('/') if relative.startswith('/') else path.parent / relative).resolve()
        fragment = unquote(parsed.fragment)
        reason = None
        if not destination.is_relative_to(root):
            reason = 'outside_release_root'
        elif not destination.exists():
            reason = 'missing_path'
        elif members is not None and destination != root and not (str(destination.relative_to(root)) in members or destination.is_dir() and any(name.startswith(str(destination.relative_to(root)) + '/') for name in members)):
            reason = 'target_not_in_release_contract'
        elif fragment and fragment not in ['gh-light-mode-only', 'gh-dark-mode-only']:
            if destination.suffix.lower() == '.md' and destination.is_file():
                if destination not in cache:
                    cache[destination] = anchors(destination.read_text(encoding='utf-8'))
                if fragment not in cache[destination]:
                    reason = 'missing_markdown_anchor'
            elif destination.suffix.lower() == '.svg' and destination.is_file():
                if destination not in cache:
                    cache[destination] = set(re.findall(r'\bid=["\']([^"\']+)', destination.read_text(encoding='utf-8')))
                if fragment not in cache[destination]:
                    reason = 'missing_SVG_anchor'
            else:
                limitations.append('Fragment on non-Markdown/non-SVG target')
        if reason:
            safe = not any(pattern.search(target.encode()) for pattern in PATTERNS.values())
            problems.append(dict(source=str(path.relative_to(root)), line=text.count('\n', 0, offset) + 1,
                target=target if safe else '[redacted metadata target]', target_sha256=hashlib.sha256(target.encode()).hexdigest(), reason=reason))
    return problems, checked, limitations


def metadata(path, root, budget, per_file_limit):
    before = path.stat()
    found, inspected, tail, complete = {}, 0, b'', True
    opener = gzip.open if path.suffix.lower() == '.gz' else open
    digest = sha(path)
    error = None
    try:
        with opener(path, 'rb') as stream:
            while True:
                chunk = stream.read(min(1 << 20, per_file_limit - inspected + 1))
                if not chunk:
                    break
                inspected += len(chunk)
                budget[0] -= len(chunk)
                if inspected > per_file_limit or budget[0] < 0:
                    complete, error = False, 'expanded_byte_limit'
                    break
                data = tail + chunk
                for category, pattern in PATTERNS.items():
                    match = pattern.search(data)
                    if match and category not in found:
                        found[category] = inspected - len(chunk) - len(tail) + match.start()
                tail = data[-256:]
    except (OSError, EOFError) as exc:
        complete, error = False, type(exc).__name__
    after = path.stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
        complete, error = False, 'file_changed_during_scan'
    row = dict(file=str(path.relative_to(root)), source_bytes=before.st_size, source_sha256=digest,
        kind='gzip-expanded' if path.suffix.lower() == '.gz' else 'file-bytes', inspected_bytes=inspected,
        categories=sorted(found), first_offsets=found)
    if not complete:
        row['incomplete_reason'] = error
    return row, complete


def inspect(root, *, metadata_enabled=True, links_enabled=True, total_limit=20 << 30, per_file_limit=512 << 20, members=None):
    root = Path(root).resolve(strict=True)
    started = time.monotonic()
    paths, symlinks = [], []
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d != '.git')
        for name in dirs[:]:
            f = Path(directory) / name
            if f.is_symlink():
                symlinks.append(str(f.relative_to(root)))
                dirs.remove(name)
        for name in sorted(files):
            f = Path(directory) / name
            if f.is_symlink():
                symlinks.append(str(f.relative_to(root)))
            elif f.is_file():
                paths.append(f)
    if members is not None:
        paths = [path for path in paths if str(path.relative_to(root)) in members]
    report = dict(recorded_utc=datetime.now(timezone.utc).isoformat(), root=str(root), files_enumerated=len(paths),
        symlinks_not_followed=symlinks, metadata_findings=[], metadata_incomplete=[], broken_links=[],
        files_scanned=0, gzip_files_scanned=0, Markdown_files_checked=0, relative_links_checked=0,
        bytes_inspected=0, link_parser_limitations=[], complete=True,
        scope='Read-only inventory, not a credential-free guarantee or security/physical certification. File bytes and one gzip layer; nested compressed ZIP/tar members are not recursively decoded. Links: inline Markdown and HTML href/src, ATX/setext headings and HTML anchors; reference-link definitions and external URLs are not checked.',
        matched_content_emitted=False, source_files_changed=False, new_EDA_jobs=0, network_actions=0)
    budget, cache = [total_limit], {}
    for path in paths:
        if time.monotonic() - started > 840:
            report['complete'] = False
            report['stop_reason'] = 'elapsed_limit'
            break
        if links_enabled and path.suffix.lower() == '.md':
            broken, count, limited = links(path, root, cache, members)
            report['Markdown_files_checked'] += 1
            report['relative_links_checked'] += count
            report['broken_links'].extend(broken)
            report['link_parser_limitations'].extend(limited)
        if metadata_enabled:
            row, complete = metadata(path, root, budget, per_file_limit)
            report['files_scanned'] += 1
            report['gzip_files_scanned'] += path.suffix.lower() == '.gz'
            report['bytes_inspected'] += row['inspected_bytes']
            if row['categories']:
                report['metadata_findings'].append(row)
            if not complete:
                report['metadata_incomplete'].append(row)
                report['source_files_changed'] |= row.get('incomplete_reason') == 'file_changed_during_scan'
                report['complete'] = False
            if budget[0] < 0:
                report['stop_reason'] = 'total_expanded_byte_limit'
                break
    report['wall_seconds'] = time.monotonic() - started
    report['link_parser_limitations'] = dict(Counter(report['link_parser_limitations']))
    report['metadata_files_by_category'] = dict(Counter(category for row in report['metadata_findings'] for category in row['categories']))
    report['broken_links_by_reason'] = dict(Counter(row['reason'] for row in report['broken_links']))
    return report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--links-only', action='store_true')
    ap.add_argument('--contract', type=Path)
    ap.add_argument('--fail-on-findings', action='store_true')
    args = ap.parse_args()
    assert not args.output.resolve().is_relative_to(args.root.resolve())
    assert not args.output.exists()
    resource.setrlimit(resource.RLIMIT_CPU, (600, 605))
    signal.alarm(900)
    # Existing verify_release.py excludes these three generated integrity
    # members from its own payload contract to avoid hash cycles.
    members = set(json.loads(args.contract.read_bytes())['files']) | {'MANIFEST.json', 'tools/release-contract.json', 'tools/verify_release.py'} if args.contract else None
    report = inspect(args.root, metadata_enabled=not args.links_only, members=members)
    if args.contract:
        report['release_contract_sha256'] = sha(args.contract)
        report['members_expected'] = len(members)
        report['missing_members'] = sorted(name for name in members if not (args.root / name).is_file())
        report['complete'] &= not report['missing_members']
        report['scope'] += ' Selected contract members only, using current workspace bytes; changed documentation is not assumed published.'
    report['program_sha256'] = sha(__file__)
    with args.output.open('x') as stream:
        json.dump(report, stream, indent=2)
        stream.write('\n')
    print(json.dumps({key: report[key] for key in ['complete', 'files_enumerated', 'files_scanned', 'gzip_files_scanned', 'bytes_inspected', 'relative_links_checked', 'metadata_files_by_category', 'broken_links_by_reason', 'wall_seconds']}))
    blocking = set(report['metadata_files_by_category']) - {'provider_folder_name'}
    if args.fail_on_findings and (not report['complete'] or report['broken_links'] or blocking):
        raise SystemExit(1)


if __name__ == '__main__':
    main()

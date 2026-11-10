"""CSV mechanics and evidence ledger; never infer translation semantics."""
import argparse
import base64
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import tempfile
from collections import Counter, defaultdict
from dataclasses import dataclass
import xml.etree.ElementTree as ET


LOCALE = re.compile(r"[a-z]{2,3}(?:-[a-z0-9]{2,8})*\Z")
PARAMETER = re.compile(r"\{(?:[A-Za-z_][A-Za-z_0-9]*|[0-9]+)(?::(?:int|fixed|num|HEX|hex|datetime|iso8601|shorttime|shortdatetime|shortdate|translate))?\}")
TAGS = {
    **{tag: set() for tag in ('b', 'i', 'u', 's', 'br', 'uppercase', 'uc', 'smallcaps', 'sc')},
    'font': {'color', 'size', 'face', 'family', 'weight', 'transparency'},
    'stroke': {'color', 'thickness', 'th', 'transparency', 'tr', 'joins', 'sizing'},
    'mark': {'color', 'transparency'},
}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def identity(row):
    return ('key', row['Key']) if row['Key'] else ('source', row['Source'], row['Context'])


@dataclass
class Table:
    raw: bytes
    columns: list
    rows: list
    records: list
    bom: bool

    @property
    def languages(self):
        return [c for c in self.columns if LOCALE.fullmatch(c)]


def parse(raw):
    text = raw.decode('utf-8-sig')
    # csv.reader counts CR/LF physical lines, not Unicode paragraph separators.
    lines = io.StringIO(text, newline='').readlines()
    old_limit = csv.field_size_limit()
    try:
        csv.field_size_limit(max(old_limit, len(text)))
        reader = csv.reader(io.StringIO(text, newline=''), strict=True)
        records, values, start = [], [], 0
        for cells in reader:
            records.append(''.join(lines[start:reader.line_num]))
            values.append(cells)
            start = reader.line_num
    except csv.Error as exc:
        raise ValueError(f'CSV parse failed: {exc}') from exc
    finally:
        csv.field_size_limit(old_limit)
    columns = values[0] if values else []
    if (not {'Key', 'Source', 'Context'} <= set(columns)
            or len(columns) != len(set(columns)) or any(not c.strip() for c in columns)):
        raise ValueError('Missing required, empty, or duplicate CSV headers')
    if any(len(cells) != len(columns) for cells in values[1:]):
        raise ValueError('CSV record field count differs from header')
    result = Table(raw, columns, [dict(zip(columns, r)) for r in values[1:]], records,
                   raw.startswith(b'\xef\xbb\xbf'))
    if not result.languages:
        raise ValueError('No existing target language columns')
    return result


def render(table, rows):
    if len(rows) != len(table.rows):
        raise ValueError('Row count changed')
    records = [table.records[0]]
    for old, new, record in zip(table.rows, rows, table.records[1:]):
        if set(old) != set(new) or any(old[c] != new[c] for c in table.columns if c not in table.languages):
            raise ValueError('Non-translation cell changed')
        if old == new:
            records.append(record)
            continue
        ending = '\r\n' if record.endswith('\r\n') else record[-1:] if record.endswith(('\n', '\r')) else ''
        out = io.StringIO(newline='')
        csv.writer(out, lineterminator='\r\n').writerow([new[c] for c in table.columns])
        records.append(out.getvalue()[:-2] + ending)
    raw = ''.join(records).encode('utf-8-sig' if table.bom else 'utf-8')
    check = parse(raw)
    if check.columns != table.columns or check.rows != rows:
        raise ValueError('Candidate CSV round-trip changed cell values')
    return raw


def placeholders(text):
    tokens = Counter(m.group() for m in PARAMETER.finditer(text))
    remaining = PARAMETER.sub('', text)
    # The project delegates directly to Translator; do not import Python-style
    # {{...}} or backslash escapes into that grammar without runtime evidence.
    if '{' in remaining or '}' in remaining or re.search(r'\\\{', text):
        raise ValueError('Unconfirmed template brace/escape or format specifier')
    return tokens


def richtext(text):
    if not re.search(r'<[A-Za-z/!?]', text):
        return Counter()
    markup = re.sub(r'<!--.*?-->', '', text, flags=re.DOTALL)
    if any(tag != 'br' for tag in re.findall(r'<([A-Za-z]+)\b[^<>]*?/\s*>', markup)):
        raise ValueError('Only br may be self-closing in Roblox rich text')
    try:
        root = ET.fromstring('<root>' + text + '</root>')
    except ET.ParseError as exc:
        raise ValueError(f'Invalid rich-text nesting/escaping: {exc}') from exc
    signature = Counter()
    for node in root.iter():
        if node is root:
            continue
        if node.tag not in TAGS or set(node.attrib) - TAGS[node.tag]:
            raise ValueError(f'Unsupported rich-text tag/attribute: {node.tag}')
        for name, value in node.attrib.items():
            if not value:
                raise ValueError(f'Empty rich-text attribute: {name}')
            if name == 'color' and not (re.fullmatch(r'#[0-9a-fA-F]{6}', value) or
                    (re.fullmatch(r'rgb\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)', value)
                     and all(0 <= int(n) <= 255 for n in re.findall(r'\d+', value)))):
                raise ValueError('Invalid rich-text color')
            if name in ('size', 'thickness', 'th', 'transparency', 'tr'):
                if not re.fullmatch(r'\d+(?:\.\d+)?', value) or (
                        float(value) > 1 if name in ('transparency', 'tr') else float(value) <= 0):
                    raise ValueError(f'Invalid numeric rich-text attribute: {name}')
            if name == 'weight' and value.lower() not in {
                    'thin', 'extralight', 'light', 'regular', 'medium', 'semibold', 'bold', 'extrabold', 'heavy',
                    *(str(n) for n in range(100, 901, 100))}:
                raise ValueError('Invalid font weight')
            if name == 'joins' and value not in ('round', 'bevel', 'miter'):
                raise ValueError('Invalid stroke joins')
            if name == 'sizing' and value not in ('fixed', 'scaled'):
                raise ValueError('Invalid stroke sizing')
        if node.tag == 'br':
            if len(node) or node.text:
                raise ValueError('Line-break tag cannot contain text')
        else:
            signature[(node.tag, tuple(sorted(node.attrib.items())))] += 1
    return signature


def mechanical(table):
    issues = []
    for number, row in enumerate(table.rows, 1):
        source = row['Source']
        if not source.strip():
            issues.append({'row': number, 'column': 'Source', 'kind': 'source', 'message': 'Empty Source'})
        for language in table.languages:
            value = row[language]
            if not value.strip():
                issues.append({'row': number, 'column': language, 'kind': 'missing', 'message': 'Missing translation'})
            for kind, validator in (('placeholder', placeholders), ('richtext', richtext)):
                try:
                    expected = validator(source)
                    if value.strip() and validator(value) != expected:
                        raise ValueError(f'{kind} differs from current Source')
                    if kind == 'placeholder' and PARAMETER.fullmatch(source) and value.strip() and value != source:
                        raise ValueError('Pure parameter must remain verbatim')
                except ValueError as exc:
                    issues.append({'row': number, 'column': language, 'kind': kind, 'message': str(exc)})
    return issues


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def match_sources(table, entries):
    if not isinstance(entries, list):
        raise ValueError('Context index must be an array')
    by_id = defaultdict(list)
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get('key', ''), str):
            raise ValueError('Invalid context identity')
        if not all(isinstance(entry.get(k, ''), str) for k in ('source', 'context')):
            raise ValueError('Invalid context Source/Context')
        row = {'Key': entry.get('key', ''), 'Source': entry.get('source', ''), 'Context': entry.get('context', '')}
        by_id[identity(row)].append(entry)
    counts = Counter(identity(row) for row in table.rows)
    result = []
    for row in table.rows:
        matches = by_id.get(identity(row), [])
        problems = []
        if counts[identity(row)] > 1:
            problems.append('Duplicate CSV identity')
        if len(matches) != 1:
            problems.append('Missing context identity' if not matches else 'Duplicate context identity')
        sources = []
        for entry in matches:
            if ('source' in entry and entry['source'] != row['Source']) or (
                    'context' in entry and entry['context'] != row['Context']):
                problems.append('Stale index Source/Context')
            origins = entry.get('sources')
            if not isinstance(origins, list) or not origins:
                problems.append('Missing source locations')
                continue
            for origin in origins:
                if not isinstance(origin, str) or not re.fullmatch(r'(?:code|node|config):.+', origin):
                    problems.append('Invalid source location')
                elif origin not in sources:
                    sources.append(origin)
        result.append({'problems': problems, 'sources': sources})
    return result


def atomic_write(path, raw, expected=None):
    path = Path(path)
    if path.is_symlink():
        raise ValueError('Refusing symlink output')
    name = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.' + path.name + '-', suffix='.tmp', delete=False) as handle:
            name = Path(handle.name)
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        if expected is not None and path.read_bytes() != expected:
            raise ValueError('Input changed during save; original not replaced')
        os.replace(name, path)
    finally:
        if name is not None and name.exists():
            name.unlink()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def init(csv_path, index_path, state_path):
    csv_path, index_path, state_path = map(lambda p: Path(p).resolve(), (csv_path, index_path, state_path))
    if state_path.exists() or state_path in (csv_path, index_path):
        raise ValueError('Review file already exists or aliases an input')
    table = parse(csv_path.read_bytes())
    index_raw = index_path.read_bytes()
    matches = match_sources(table, json.loads(index_raw.decode('utf-8-sig')))
    state = {'version': 1, 'csv': str(csv_path), 'index': str(index_path),
             'baseline_b64': base64.b64encode(table.raw).decode('ascii'),
             'baseline_sha256': digest(table.raw), 'applied_sha256': digest(table.raw),
             'index_sha256': digest(index_raw), 'glossary': {}, 'rows': []}
    for number, (row, match) in enumerate(zip(table.rows, matches), 1):
        state['rows'].append({'row': number, 'identity': list(identity(row)),
            'sources': [{'location': location, 'checked': False, 'observed_source': None,
                         'evidence': ''} for location in match['sources']],
            'usage': '', 'evidence': '', 'playtest_required': False, 'playtests': [],
            'languages': {language: {'value': row[language], 'reviewed': False, 'evidence': '', 'pending': ''}
                          for language in table.languages}})
    atomic_write(state_path, json_bytes(state))
    return state


def load(state_path):
    state = read_json(state_path)
    if state.get('version') != 1:
        raise ValueError('Unsupported review version')
    table = parse(base64.b64decode(state['baseline_b64'], validate=True))
    if digest(table.raw) != state['baseline_sha256']:
        raise ValueError('Baseline changed')
    index_raw = Path(state['index']).read_bytes()
    if digest(index_raw) != state['index_sha256']:
        raise ValueError('Context index changed; reconcile against a fresh review')
    matches = match_sources(table, json.loads(index_raw.decode('utf-8-sig')))
    if len(state['rows']) != len(table.rows):
        raise ValueError('Review row count changed')
    for number, (record, row, match) in enumerate(zip(state['rows'], table.rows, matches), 1):
        if record['row'] != number or record['identity'] != list(identity(row)):
            raise ValueError(f'Review identity/order changed at row {number}')
        if [s['location'] for s in record['sources']] != match['sources']:
            raise ValueError(f'Review source coverage changed at row {number}')
        if set(record['languages']) != set(table.languages):
            raise ValueError(f'Review language coverage changed at row {number}')
        for cell in record['languages'].values():
            if not all(isinstance(cell.get(k), str) for k in ('value', 'evidence', 'pending')):
                raise ValueError(f'Invalid review cell at row {number}')
    return state, table, matches


def source_checked(source, current):
    return (source.get('checked') is True and source.get('observed_source') == current
            and isinstance(source.get('evidence'), str) and bool(source['evidence'].strip()))


def playtested(record):
    return bool(record['playtests']) and all(
        t.get('observed') is True and t.get('state', '').strip() and t.get('evidence', '').strip()
        for t in record['playtests'])


def ready(record, row, match):
    return (not match['problems'] and bool(record['sources'])
            and all(source_checked(s, row['Source']) for s in record['sources'])
            and bool(record['usage'].strip()) and bool(record['evidence'].strip())
            and (not record['playtest_required'] or playtested(record)))


def evaluate(state, table, matches):
    rows, blocked, unreviewed, pending = [], [], [], []
    counts = Counter({'filled': 0, 'corrected': 0, 'retained': 0, 'pending': 0, 'unreviewed': 0})
    reviewed = 0
    for record, old, match in zip(state['rows'], table.rows, matches):
        row = old.copy()
        scene_ready = ready(record, old, match)
        for language, cell in record['languages'].items():
            ref = {'row': record['row'], 'identity': record['identity'], 'column': language}
            done = (scene_ready and cell['reviewed'] is True and bool(cell['evidence'].strip())
                    and bool(cell['value'].strip()) and not cell['pending'])
            if cell['pending']:
                counts['pending'] += 1
                pending.append({**ref, 'reason': cell['pending']})
            elif done:
                counts['filled' if not old[language].strip() else 'retained' if cell['value'] == old[language] else 'corrected'] += 1
                reviewed += 1
            else:
                counts['unreviewed'] += 1
                unreviewed.append(ref)
            if cell['value'] != old[language] and not done:
                blocked.append({**ref, 'reason': 'Changed cell lacks resolved identity, all sources, usage, playtest or semantic evidence'})
            row[language] = cell['value']
        rows.append(row)
    candidate = parse(render(table, rows))
    issues = mechanical(candidate)
    checked = sum(source_checked(s, row['Source']) for r, row in zip(state['rows'], table.rows) for s in r['sources'])
    identities = [{'row': i, 'identity': list(identity(row)), 'problems': match['problems']}
                  for i, (row, match) in enumerate(zip(table.rows, matches), 1) if match['problems']]
    report = {'entries': len(rows), 'languages': table.languages,
        'sources_total': sum(len(r['sources']) for r in state['rows']), 'sources_checked': checked,
        'cells_total': len(rows) * len(table.languages), 'semantic_reviewed': reviewed,
        'outcomes': dict(counts), 'unreviewed': unreviewed, 'pending': pending,
        'identity_issues': identities, 'blocked_changes': blocked,
        'source_review': [{'row': r['row'], 'identity': r['identity'],
                          'usage': r['usage'], 'evidence': r['evidence'],
                          'sources': [{**s, 'verified': source_checked(s, row['Source'])} for s in r['sources']]}
                         for r, row in zip(state['rows'], table.rows)],
        'validation': {'structure': 'passed', 'non_translation_columns': 'passed',
                       'failures': dict(Counter(i['kind'] for i in issues if i['kind'] != 'missing')),
                       'missing': sum(i['kind'] == 'missing' for i in issues)}, 'issues': issues,
        'playtests': [{'row': r['row'], **t} for r in state['rows'] for t in r['playtests']],
        'playtest_unverified': [r['row'] for r in state['rows'] if r['playtest_required'] and not playtested(r)],
        'csv': state['csv'], 'cloud_uploaded': False}
    report['review_complete'] = (reviewed == report['cells_total'] and checked == report['sources_total']
                                 and not identities and not issues and not blocked)
    return candidate, report


def report_file(state_path):
    state, table, matches = load(state_path)
    candidate, report = evaluate(state, table, matches)
    current = parse(Path(state['csv']).read_bytes())
    if current.columns != table.columns or len(current.rows) != len(table.rows) or any(
            any(a[c] != b[c] for c in table.columns if c not in table.languages)
            for a, b in zip(current.rows, table.rows)):
        raise ValueError('Actual CSV structure/non-translation columns changed')
    report['actual_issues'] = mechanical(current)
    report['input_conflict'] = digest(current.raw) not in (state['applied_sha256'], digest(candidate.raw))
    report['unapplied'] = [{'row': n, 'column': lang} for n, (a, b) in enumerate(zip(current.rows, candidate.rows), 1)
                           for lang in table.languages if a[lang] != b[lang]]
    report['complete'] = report['review_complete'] and not report['unapplied'] and not report['input_conflict']
    return report


def apply(state_path):
    state_path = Path(state_path)
    state_raw = state_path.read_bytes()
    state, table, matches = load(state_path)
    candidate, report = evaluate(state, table, matches)
    if report['blocked_changes'] or any(i['kind'] != 'missing' for i in report['issues']):
        raise ValueError('Candidate validation failed; CSV unchanged. Run report for all issues.')
    csv_path = Path(state['csv'])
    current = csv_path.read_bytes()
    if digest(current) not in (state['applied_sha256'], digest(candidate.raw)):
        raise ValueError('CSV input conflict since last init/apply; nothing overwritten')
    if state_path.read_bytes() != state_raw or digest(Path(state['index']).read_bytes()) != state['index_sha256']:
        raise ValueError('Review or index changed during apply')
    if current != candidate.raw:
        atomic_write(csv_path, candidate.raw, expected=current)
    state['applied_sha256'] = digest(candidate.raw)
    try:
        atomic_write(state_path, json_bytes(state), expected=state_raw)
    except (OSError, ValueError) as exc:
        raise ValueError('CSV saved, review checkpoint not saved; inspect files and retry same apply') from exc
    return report_file(state_path)


def batch(state_path, start, limit):
    state, table, matches = load(state_path)
    _, report = evaluate(state, table, matches)
    outstanding = {r['row'] for r in report['unreviewed'] + report['pending'] + report['issues'] + report['identity_issues']}
    return [{'input': row, 'review': record, 'identity_problems': match['problems']}
            for record, row, match in zip(state['rows'], table.rows, matches)
            if record['row'] >= start and record['row'] in outstanding][:limit]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('init')
    p.add_argument('--csv', required=True)
    p.add_argument('--index', required=True)
    p.add_argument('--review', required=True)
    for name in ('report', 'apply', 'batch'):
        p = sub.add_parser(name)
        p.add_argument('--review', required=True)
        if name == 'batch':
            p.add_argument('--start', type=int, default=1)
            p.add_argument('--limit', type=int, default=10)
    args = parser.parse_args()
    try:
        if args.command == 'init':
            init(args.csv, args.index, args.review)
            result = report_file(args.review)
        elif args.command == 'batch':
            if args.start < 1 or args.limit < 1:
                raise ValueError('start and limit must be positive')
            result = batch(args.review, args.start, args.limit)
        else:
            result = (apply if args.command == 'apply' else report_file)(args.review)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if args.command != 'batch' and not result['complete']:
            return 2
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(json.dumps({'error': str(exc)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

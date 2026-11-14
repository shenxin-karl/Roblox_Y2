"""Behavioral regression tests using isolated CSV/index/review fixtures."""
import base64
import csv
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import translation_review as review


COLUMNS = ['Key', 'Example', 'Source', 'Context', 'Game Locations', 'ja', 'ja translator type', 'en-us', 'metadata']


def csv_bytes(rows, bom=True, ending='\r\n'):
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, COLUMNS, lineterminator=ending)
    writer.writeheader()
    writer.writerows([{c: row.get(c, '') for c in COLUMNS} for row in rows])
    return stream.getvalue().encode('utf-8-sig' if bom else 'utf-8')


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.csv = root / 'translation-upload.csv'
        self.index = root / 'translation-ai-context.json'
        self.state = root / 'review.json'

    def fixture(self, rows, entries=None, bom=True, ending='\r\n'):
        self.csv.write_bytes(csv_bytes(rows, bom, ending))
        if entries is None:
            entries = [dict({'key': r['Key']} if r.get('Key') else
                            {'source': r['Source'], 'context': r.get('Context', '')},
                            sources=[f'code:../Scripts/Test.luau:{n}', f'node:StarterGui.Test.Text{n}'])
                       for n, r in enumerate(rows, 1)]
        self.index.write_bytes(review.json_bytes(entries))
        review.init(self.csv, self.index, self.state)
        return review.read_json(self.state)

    def save(self, state):
        self.state.write_bytes(review.json_bytes(state))

    def finish(self, state, number=0, languages=None):
        row = review.parse(base64.b64decode(state['baseline_b64'])).rows[number]
        record = state['rows'][number]
        for source in record['sources']:
            source.update(checked=True, observed_source=row['Source'], evidence='Read definition/call and actual UI')
        record.update(usage='Test button in shop', evidence='Read call and parameter origin')
        for lang in languages or record['languages']:
            cell = record['languages'][lang]
            cell.update(reviewed=True, evidence='Reviewed in context')
            if not cell['value']:
                cell['value'] = row['Source']

    def test_roundtrip_encodings_multiline_and_unicode(self):
        for bom, ending in ((True, '\r\n'), (False, '\n'), (True, '\r')):
            with self.subTest(bom=bom, ending=repr(ending)):
                rows = [{'Key': 'A', 'Source': 'Hello, "世界"\nNext\u2028line',
                         'Example': '例子,"quoted"', 'metadata': 'unchanged', 'ja': '古い', 'en-us': 'Old'},
                        {'Source': 'Open', 'Context': 'Menu', 'ja': '開く', 'en-us': 'Open'}]
                raw = csv_bytes(rows, bom, ending)
                table = review.parse(raw)
                self.assertEqual(review.render(table, table.rows), raw)
                changed = [r.copy() for r in table.rows]
                changed[0]['ja'] = 'こんにちは,"世界"\n次'
                result = review.render(table, changed)
                self.assertEqual(review.parse(result).rows, changed)
                self.assertEqual(result.startswith(b'\xef\xbb\xbf'), bom)
                self.assertTrue(result.endswith(table.records[-1].encode('utf-8')))
                for column in set(COLUMNS) - {'ja', 'en-us'}:
                    self.assertEqual(table.rows[0][column], review.parse(result).rows[0][column])

    def test_no_final_newline_and_structural_failures(self):
        raw = csv_bytes([{'Source': 'Open', 'ja': '旧'}], False).rstrip(b'\r\n')
        table = review.parse(raw)
        changed = [dict(table.rows[0], ja='新')]
        self.assertFalse(review.render(table, changed).endswith(b'\n'))
        for raw in (b'Key,Source,Context,ja,ja\n,,,,\n', b'Key,Source,Context,ja\nA,Open,,x,extra\n',
                    b'Key,Source,Context,ja\nA,"unterminated,,x', b'Key,Source,Context,\nA,x,,y\n'):
            with self.assertRaises(ValueError):
                review.parse(raw)
        with self.assertRaises(ValueError):
            review.render(table, [dict(table.rows[0], Source='Changed')])

    def test_matching_exact_key_unkeyed_duplicates_missing_stale(self):
        table = review.parse(csv_bytes([{'Key': 'K', 'Source': 'Current'}, {'Key': 'K', 'Source': 'Other'},
            {'Source': 'Open', 'Context': 'menu'}, {'Source': 'Open', 'Context': 'menu'},
            {'Source': ' Open', 'Context': 'menu'}, {'Key': 'S', 'Source': 'New'}, {'Key': 'M', 'Source': 'Missing'},
            {'Key': 'Good', 'Source': 'Fine'}]))
        entries = [{'key': 'K', 'sources': ['code:a:1']}, {'key': 'K', 'sources': ['code:b:2']},
            {'source': 'Open', 'context': 'menu', 'sources': ['node:Gui.Text']},
            {'key': 'S', 'source': 'Old', 'sources': ['code:s:1']}, {'key': 'Good', 'sources': ['code:g:1']}]
        result = review.match_sources(table, entries)
        self.assertIn('Duplicate CSV identity', result[0]['problems'])
        self.assertIn('Duplicate context identity', result[0]['problems'])
        self.assertIn('Duplicate CSV identity', result[2]['problems'])
        self.assertIn('Missing context identity', result[4]['problems'])
        self.assertIn('Stale index Source/Context', result[5]['problems'])
        self.assertIn('Missing context identity', result[6]['problems'])
        self.assertEqual(result[7]['problems'], [])

    def test_placeholder_changes_and_valid_reordering(self):
        source = '{level:int} {name} {name} {1:num} {code:HEX}'
        self.assertEqual(review.placeholders(source), review.placeholders('{code:HEX} {name} {1:num} {level:int} {name}'))
        for target in (source.replace('level', 'Level'), source.replace('level', 'rank'),
                       source.replace(':int', ''), source.replace('{name} ', '', 1), source.replace(':HEX', ':hex')):
            table = review.parse(csv_bytes([{'Source': source, 'ja': target, 'en-us': source}]))
            self.assertIn('placeholder', [x['kind'] for x in review.mechanical(table)])
        for text in ('{{name}}', r'\{name}', '{name:string}', '{broken', 'broken}'):
            with self.assertRaises(ValueError):
                review.placeholders(text)
        self.assertEqual(review.placeholders('&#123;literal&#125;'), {})
        table = review.parse(csv_bytes([{'Source': '{price}', 'ja': '+${price}', 'en-us': '{price}'}]))
        self.assertIn('Pure parameter', str(review.mechanical(table)))

    def test_richtext_nesting_attributes_entities_and_movement(self):
        a = '<font color="#FF0000"><b>{name}</b></font> wins<br/>'
        b = '勝者 <font color="#FF0000"><b>{name}</b></font>'
        self.assertEqual(review.richtext(a), review.richtext(b))
        self.assertEqual(review.richtext('&lt;b&gt;literal&lt;/b&gt;'), {})
        self.assertEqual(review.richtext('<stroke thickness="2" transparency="0.5">a</stroke>'),
                         review.richtext('<stroke transparency="0.5" thickness="2">b</stroke>'))
        for text in ('<b><i>bad</b></i>', '<font color="red">bad</font>', '<font size="0">bad</font>',
                     '<a>bad</a>', '<b bad="1">bad</b>', '<font color="#FF0000" color="#FF0000">x</font>',
                     '<stroke transparency="2">x</stroke>', '<br>bad</br>', '<b/>'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                review.richtext(text)
        table = review.parse(csv_bytes([{'Source': a, 'ja': a.replace('#FF0000', '#00FF00'), 'en-us': b}]))
        self.assertEqual([i['column'] for i in review.mechanical(table)], ['ja'])

    def test_batches_coverage_and_final_baseline_statistics(self):
        state = self.fixture([{'Key': 'A', 'Source': 'Open', 'ja': '', 'en-us': 'Open'},
                              {'Key': 'B', 'Source': 'Close', 'ja': '古い', 'en-us': 'Close'}])
        self.finish(state, 0)
        state['rows'][0]['languages']['ja']['value'] = '開く'
        self.save(state)
        report = review.apply(self.state)
        self.assertEqual(report['outcomes']['filled'], 1)
        self.assertEqual(report['semantic_reviewed'], 2)
        self.assertEqual([x['review']['row'] for x in review.batch(self.state, 1, 10)], [2])
        state = review.read_json(self.state)
        self.finish(state, 1)
        state['rows'][1]['languages']['ja']['value'] = '閉じる'
        self.save(state)
        report = review.apply(self.state)
        self.assertTrue(report['complete'])
        self.assertEqual(report['outcomes'], {'filled': 1, 'corrected': 1, 'retained': 2, 'pending': 0, 'unreviewed': 0})
        state = review.read_json(self.state)
        state['rows'][1]['languages']['ja']['value'] = '閉じます'
        self.save(state)
        self.assertEqual(review.apply(self.state)['outcomes']['corrected'], 1)
        self.assertEqual(review.apply(self.state)['outcomes']['corrected'], 1)

    def test_missing_language_source_and_existing_translation_review(self):
        state = self.fixture([{'Key': 'A', 'Source': 'Open', 'ja': '開く', 'en-us': 'Open'}])
        self.finish(state, languages=['ja'])
        self.save(state)
        report = review.report_file(self.state)
        self.assertEqual(report['semantic_reviewed'], 1)
        self.assertEqual(report['outcomes']['unreviewed'], 1)
        state['rows'][0]['sources'][1]['checked'] = False
        self.save(state)
        self.assertEqual(review.report_file(self.state)['semantic_reviewed'], 0)
        state['rows'][0]['languages'].pop('en-us')
        self.save(state)
        with self.assertRaisesRegex(ValueError, 'language coverage'):
            review.report_file(self.state)

    def test_omitted_rows_sources_and_changed_order_are_detected(self):
        import copy

        state = self.fixture([{'Key': 'A', 'Source': 'Open'}, {'Key': 'B', 'Source': 'Close'}])
        missing_row = copy.deepcopy(state)
        missing_row['rows'].pop()
        missing_source = copy.deepcopy(state)
        missing_source['rows'][0]['sources'].pop()
        wrong_order = copy.deepcopy(state)
        wrong_order['rows'].reverse()
        for broken, message in ((missing_row, 'row count'), (missing_source, 'source coverage'),
                                (wrong_order, 'identity/order')):
            self.save(broken)
            with self.assertRaisesRegex(ValueError, message):
                review.report_file(self.state)

    def test_stale_actual_source_playtest_and_pending_preservation(self):
        state = self.fixture([{'Key': 'A', 'Source': 'Open', 'ja': '開く', 'en-us': 'Open'}])
        self.finish(state)
        record = state['rows'][0]
        record['sources'][0]['observed_source'] = 'Old'
        self.save(state)
        report = review.report_file(self.state)
        self.assertEqual(report['semantic_reviewed'], 0)
        self.assertFalse(report['source_review'][0]['sources'][0]['verified'])
        record['sources'][0]['observed_source'] = 'Open'
        record['playtest_required'] = True
        self.save(state)
        self.assertEqual(review.report_file(self.state)['playtest_unverified'], [1])
        record['playtests'] = [{'state': 'Shop opens', 'observed': True, 'evidence': 'Button displays Open'}]
        record['playtests'].append({'state': 'Shop sold out', 'observed': False, 'evidence': 'Cannot trigger'})
        self.save(state)
        self.assertEqual(review.report_file(self.state)['playtest_unverified'], [1])
        self.assertEqual(review.report_file(self.state)['semantic_reviewed'], 0)
        record['playtests'].pop()
        record['languages']['ja'].update(reviewed=False, pending='MCP unavailable; need actual button width')
        self.save(state)
        before = self.csv.read_bytes()
        report = review.apply(self.state)
        self.assertEqual(report['outcomes']['pending'], 1)
        self.assertFalse(report['complete'])
        self.assertEqual(self.csv.read_bytes(), before)
        record['languages']['ja']['value'] = 'Guess'
        self.save(state)
        with self.assertRaises(ValueError):
            review.apply(self.state)
        self.assertEqual(self.csv.read_bytes(), before)

    def test_ambiguous_rows_do_not_prevent_unrelated_apply(self):
        state = self.fixture([{'Key': 'A', 'Source': 'Open'}, {'Key': 'A', 'Source': 'Open'},
                              {'Key': 'B', 'Source': 'Close', 'ja': '古い', 'en-us': 'Close'}])
        self.finish(state, 2)
        state['rows'][2]['languages']['ja']['value'] = '閉じる'
        self.save(state)
        report = review.apply(self.state)
        self.assertEqual(len(report['identity_issues']), 2)
        self.assertEqual(review.parse(self.csv.read_bytes()).rows[2]['ja'], '閉じる')
        self.finish(state, 0)
        self.save(state)
        before = self.csv.read_bytes()
        with self.assertRaises(ValueError):
            review.apply(self.state)
        self.assertEqual(self.csv.read_bytes(), before)

    def test_existing_unmodified_errors_prevent_save(self):
        state = self.fixture([{'Key': 'A', 'Source': '{count:int}', 'ja': '{count}', 'en-us': '<b>{count:int}'}])
        before = self.csv.read_bytes()
        report = review.report_file(self.state)
        self.assertEqual(report['validation']['failures'], {'placeholder': 2, 'richtext': 1})
        with self.assertRaisesRegex(ValueError, 'validation failed'):
            review.apply(self.state)
        self.assertEqual(self.csv.read_bytes(), before)

    def test_conflicts_and_failed_replace_preserve_original(self):
        state = self.fixture([{'Key': 'A', 'Source': 'Open', 'ja': '旧', 'en-us': 'Open'}])
        self.finish(state)
        state['rows'][0]['languages']['ja']['value'] = '開く'
        self.save(state)
        before = self.csv.read_bytes()
        external = before.replace('旧'.encode(), '別'.encode())
        self.csv.write_bytes(external)
        with self.assertRaisesRegex(ValueError, 'conflict'):
            review.apply(self.state)
        self.assertEqual(self.csv.read_bytes(), external)
        self.csv.write_bytes(before)
        with patch.object(review.os, 'replace', side_effect=PermissionError('locked')):
            with self.assertRaises(PermissionError):
                review.apply(self.state)
        self.assertEqual(self.csv.read_bytes(), before)
        self.assertEqual(list(self.csv.parent.glob('*.tmp')), [])
        self.index.write_bytes(b'[]')
        with self.assertRaisesRegex(ValueError, 'index changed'):
            review.apply(self.state)

    def test_conflict_after_candidate_written_and_checkpoint_recovery(self):
        state = self.fixture([{'Key': 'A', 'Source': 'Open', 'ja': '旧', 'en-us': 'Open'}])
        self.finish(state)
        state['rows'][0]['languages']['ja']['value'] = '開く'
        self.save(state)
        real_fsync = review.os.fsync

        def concurrent_edit(fd):
            real_fsync(fd)
            self.csv.write_bytes(b'concurrent edit')

        with patch.object(review.os, 'fsync', side_effect=concurrent_edit):
            with self.assertRaisesRegex(ValueError, 'changed during save'):
                review.apply(self.state)
        self.assertEqual(self.csv.read_bytes(), b'concurrent edit')
        self.csv.write_bytes(base64.b64decode(state['baseline_b64']))
        real_replace = review.os.replace

        def checkpoint_fail(src, dst):
            if Path(dst) == self.state:
                raise PermissionError('review locked')
            real_replace(src, dst)

        with patch.object(review.os, 'replace', side_effect=checkpoint_fail):
            with self.assertRaisesRegex(ValueError, 'CSV saved'):
                review.apply(self.state)
        self.assertEqual(review.parse(self.csv.read_bytes()).rows[0]['ja'], '開く')
        self.assertTrue(review.apply(self.state)['complete'])

    def test_cli_init_batch_apply_and_report(self):
        import subprocess
        import sys

        self.csv.write_bytes(csv_bytes([{'Key': 'A', 'Source': 'Open', 'ja': '開く', 'en-us': 'Open'}]))
        self.index.write_bytes(review.json_bytes([{'key': 'A', 'sources': ['code:../Scripts/Test.luau:1']}]))
        script = str(Path(review.__file__).resolve())

        def run(*args):
            result = subprocess.run([sys.executable, '-X', 'utf8', '-B', script, *args],
                                    capture_output=True, encoding='utf-8', check=False)
            self.assertEqual(result.stderr, '')
            return result.returncode, json.loads(result.stdout)

        code, data = run('init', '--csv', str(self.csv), '--index', str(self.index), '--review', str(self.state))
        self.assertEqual(code, 2)
        self.assertEqual(data['cells_total'], 2)
        code, data = run('batch', '--review', str(self.state), '--limit', '1')
        self.assertEqual((code, len(data)), (0, 1))
        state = review.read_json(self.state)
        self.finish(state)
        self.save(state)
        code, data = run('apply', '--review', str(self.state))
        self.assertEqual(code, 0)
        self.assertTrue(data['complete'])
        self.assertEqual(run('report', '--review', str(self.state))[0], 0)
        self.assertEqual(run('init', '--csv', str(self.csv), '--index', str(self.index), '--review', str(self.state))[0], 1)

    def test_compaction_preserves_legacy_evidence_reports_and_csv(self):
        state = self.fixture([{'Key': str(n), 'Source': 'Open', 'ja': '開く', 'en-us': 'Open'}
                              for n in range(8)])
        shared = '已读取定义与调用位置，参数及显示条件有实际来源；' * 8
        for n, record in enumerate(state['rows']):
            self.finish(state, n)
            for lang, cell in record['languages'].items():
                cell['evidence'] = f'{lang}: {n}\n' + shared + ' 保留末尾\r\n'
        state['rows'][0]['languages']['ja'].update(reviewed=False, pending='Need candidate preview')
        # Simulate the old fully expanded format, including its original baseline.
        original = (json.dumps(state, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
        self.state.write_bytes(original)
        csv_before = self.csv.read_bytes()
        report_before = review.report_file(self.state)
        stats = review.compact(self.state)
        self.assertLess(stats['bytes_after'], stats['bytes_before'] / 2)
        self.assertEqual(review.read_json(self.state), state)
        self.assertEqual(review.report_file(self.state), report_before)
        self.assertEqual(self.csv.read_bytes(), csv_before)
        packed = self.state.read_bytes()
        review.compact(self.state)
        self.assertEqual(self.state.read_bytes(), packed)
        review.apply(self.state)
        self.assertEqual(self.state.read_bytes(), packed)
        self.assertEqual(review.batch(self.state, 1, 1)[0]['review'], state['rows'][0])

    def test_invalid_evidence_reference_blocks_apply(self):
        state = self.fixture([{'Key': 'A', 'Source': 'Open', 'ja': '開く', 'en-us': 'Open'}])
        self.finish(state)
        packed = review.pack_review(state)
        packed['rows'][0]['languages']['ja']['evidence'] = {'parts': [{'ref': 'missing'}]}
        self.state.write_text(json.dumps(packed), encoding='utf-8')
        csv_before = self.csv.read_bytes()
        with self.assertRaisesRegex(ValueError, 'evidence reference'):
            review.apply(self.state)
        self.assertEqual(self.csv.read_bytes(), csv_before)

    def test_compaction_refuses_concurrent_review_edit(self):
        self.fixture([{'Key': 'A', 'Source': 'Open'}])
        real_fsync = review.os.fsync

        def concurrent_edit(fd):
            real_fsync(fd)
            self.state.write_bytes(b'concurrent edit')

        with patch.object(review.os, 'fsync', side_effect=concurrent_edit):
            with self.assertRaisesRegex(ValueError, 'changed during save'):
                review.compact(self.state)
        self.assertEqual(self.state.read_bytes(), b'concurrent edit')


if __name__ == '__main__':
    unittest.main()

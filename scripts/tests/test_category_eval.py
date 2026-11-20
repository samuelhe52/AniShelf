import io
import json
from http.client import BadStatusLine, IncompleteRead
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import category_eval


def corpus():
    entries = [dict(id='a', title='A', kind='movie', year=2020, finishYear=None, score=None,
                    watchStatus='watched', favorite=False, card='A · 2020 · movie')]
    cases = [dict(request=request, items=[dict(id='a', title='A', label='match')])
             for request in ('first', 'second')]
    return dict(version=1, entries=entries, labels=cases)


def response(content):
    result = io.BytesIO(json.dumps({'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(content)}}]}).encode())
    result.status = 200
    return result


class BrokenBody(io.BytesIO):
    def read(self, *args):
        raise IncompleteRead(b'partial secret-key', 100)


class CategoryEvaluationTests(unittest.TestCase):
    def run_evaluation(self, directory, args):
        with patch.object(sys, 'argv', ['category_eval.py', *args]), patch.dict(
            'os.environ', {'OPENROUTER_OPENCLAW_API_KEY': 'secret-key', 'BAILIAN_API_KEY': 'secret-key'}
        ):
            status = category_eval.main()
        run, = directory.glob('run-*')
        return status, run, json.loads((run / 'scores.json').read_text())

    def test_truncated_batch_response_persists_unchecked_for_success_and_http_error(self):
        for http_error in (False, True):
            with self.subTest(http_error=http_error), tempfile.TemporaryDirectory() as temp:
                directory = Path(temp)
                data = directory / 'input.json'
                data.write_text(json.dumps(corpus()))
                plan = dict(category_eval.PLAN_EXAMPLE, semanticCriterion='music')
                broken = BrokenBody()
                broken.status = 200
                failure = HTTPError('https://example.invalid', 502, 'failed', {}, broken) if http_error else broken
                calls = [response(plan), failure]
                with patch.object(category_eval, 'urlopen', side_effect=calls):
                    status, run, scores = self.run_evaluation(directory, [
                        '--data', str(data), '--live', '--model', 'luna', '--case', '1', '--rounds', '1',
                        '--max-calls', '2'])
                self.assertEqual(status, 1)
                self.assertIsNone(scores['routes']['luna']['macro']['precision'])
                self.assertEqual(scores['routes']['luna']['cases'][0]['unchecked'], 1)
                result = json.loads((run / 'luna-1-1.json').read_text())
                attempt = result['batches'][0]['attempt']
                self.assertEqual(result['decisions']['a'], 'unchecked')
                self.assertEqual(attempt['read_error'], 'IncompleteRead')
                self.assertEqual(attempt['status'], 502 if http_error else 200)
                self.assertEqual(attempt['response'], 'partial [redacted]')

    def test_protocol_error_persists_unchecked_instead_of_aborting(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            data = directory / 'input.json'
            data.write_text(json.dumps(corpus()))
            plan = dict(category_eval.PLAN_EXAMPLE, semanticCriterion='music')
            with patch.object(category_eval, 'urlopen', side_effect=[response(plan), BadStatusLine('garbage')]):
                status, run, _ = self.run_evaluation(directory, [
                    '--data', str(data), '--live', '--model', 'luna', '--case', '1', '--rounds', '1',
                    '--max-calls', '2'])
            self.assertEqual(status, 1)
            result = json.loads((run / 'luna-1-1.json').read_text())
            self.assertEqual(result['decisions']['a'], 'unchecked')
            self.assertEqual(result['batches'][0]['attempt']['read_error'], 'BadStatusLine')

    def test_score_bounds_apply_independently_like_the_app(self):
        entry = corpus()['entries'][0]
        plan = dict(category_eval.PLAN_EXAMPLE, minimumScore=3, maximumScore=-1)
        self.assertTrue(category_eval.passes(dict(entry, score=4), plan))
        self.assertFalse(category_eval.passes(dict(entry, score=None), plan))
        self.assertFalse(category_eval.passes(dict(entry, score=None), dict(plan, minimumScore=0, maximumScore=4)))

    def test_offline_load_rejects_entries_missing_filter_fields(self):
        data = corpus()
        del data['entries'][0]['finishYear']
        with self.assertRaisesRegex(ValueError, 'missing filter or card fields'):
            category_eval.load_data(json.dumps(data))

    def test_default_data_and_macro_keep_matching_case_denominators(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            reviewed = directory / 'benchmark-reviewed-borderlines.json'
            reviewed.write_text(json.dumps(corpus()))
            # A stale historical file must not be read by default.
            (directory / 'benchmark.json').write_text('not JSON')

            def evaluate(client, route, entries, case):
                selected = route == 'luna' or case['request'] == 'first'
                return {'request': case['request'], 'decisions': {'a': 'include' if selected else 'exclude_check'}}

            with patch.object(category_eval, 'PRIVATE', directory), patch.object(category_eval, 'evaluate', evaluate):
                status, run, scores = self.run_evaluation(directory, [
                    '--live', '--model', 'luna', '--model', 'qwen', '--rounds', '2', '--max-calls', '4'])
            self.assertEqual(status, 0)
            luna, qwen = scores['routes']['luna'], scores['routes']['qwen']
            self.assertEqual(luna['macro']['precision'], 1.0)
            self.assertEqual(qwen['macro']['precision'], 0.5)
            self.assertEqual(qwen['cases'][1]['precision'], 0.0)
            self.assertEqual(qwen['scored_cases']['precision'], 2)
            self.assertEqual(luna['scored_cases']['precision'], 2)
            manifest = json.loads((run / 'manifest.json').read_text())
            self.assertEqual(manifest['dataset_sha256'], category_eval.sha256(reviewed.read_bytes()).hexdigest())

    def test_no_positive_and_no_prediction_makes_precision_undefined(self):
        case = {'items': [{'id': 'a', 'label': 'non-match'}]}
        result = category_eval.score([{'decisions': {'a': 'exclude_check'}}], case)
        self.assertIsNone(result['precision'])
        self.assertIsNone(result['recall'])

    def test_undefined_case_withholds_macro_instead_of_dropping_case(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            data = directory / 'input.json'
            fixture = corpus()
            fixture['labels'][1]['items'][0]['label'] = 'non-match'
            data.write_text(json.dumps(fixture))

            def evaluate(client, route, entries, case):
                decision = 'include' if case['request'] == 'first' else 'exclude_check'
                return {'request': case['request'], 'decisions': {'a': decision}}

            with patch.object(category_eval, 'evaluate', evaluate):
                _, _, scores = self.run_evaluation(directory, [
                    '--data', str(data), '--live', '--model', 'luna', '--rounds', '2', '--max-calls', '2'])
            result = scores['routes']['luna']
            self.assertIsNone(result['macro']['precision'])
            self.assertEqual(result['scored_cases']['precision'], 1)
            self.assertEqual(len(result['cases']), 2)


if __name__ == '__main__':
    unittest.main()

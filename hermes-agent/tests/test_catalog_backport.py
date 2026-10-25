"""Backport behavior against the pinned release's actual model-discovery code."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'hermes-agent/files/home/.local/bin/hermes-codex-catalog-compat.py'
spec = importlib.util.spec_from_file_location('catalog_compat', SCRIPT)
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)
SOURCE = os.environ.get('HERMES_SOURCE')


class PatchSafetyTests(unittest.TestCase):
    def test_unknown_source_is_rejected_without_writing(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)
            target = source / 'hermes_cli/codex_models.py'
            target.parent.mkdir()
            target.write_text('# different upstream implementation\n')
            with self.assertRaises(ValueError):
                compat.backport(source)
            self.assertEqual(target.read_text(), '# different upstream implementation\n')

    def test_kit_variants_ship_identical_backport(self):
        other = ROOT / 'hermes-agent-mixin/files/home/.local/bin' / SCRIPT.name
        self.assertEqual(SCRIPT.read_bytes(), other.read_bytes())


@unittest.skipUnless(SOURCE, 'set HERMES_SOURCE to the pinned release checkout')
class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.source = Path(SOURCE).resolve()
        text = (self.source / 'hermes_cli/codex_models.py').read_text()
        if compat.OLD not in text:
            self.skipTest('backport targets the older kit pin, not this release')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        target = self.root / 'hermes_cli/codex_models.py'
        target.parent.mkdir()
        target.write_text(text)
        self.assertTrue(compat.backport(self.root))
        self.assertFalse(compat.backport(self.root))
        self.patched = target

    def discover(self, responses):
        env = dict(os.environ, PYTHONPATH=str(self.source), HERMES_HOME=str(self.root / 'state'),
                   PATCHED_MODELS=str(self.patched), RESPONSES=json.dumps(responses))
        result = subprocess.run([sys.executable, '-c', r'''
import importlib.util
import json
import os
from urllib.parse import parse_qs, urlparse
from unittest.mock import patch
import httpx
spec = importlib.util.spec_from_file_location('patched_codex', os.environ['PATCHED_MODELS'])
models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(models)
responses = iter(json.loads(os.environ['RESPONSES']))
calls = []
def get(url, *, headers, timeout):
    parsed = urlparse(url)
    assert parsed.hostname == 'chatgpt.com'
    assert parsed.path == '/backend-api/codex/models'
    assert headers['Authorization'] == 'Bearer oai-oat01-proxy-managed'
    assert timeout == 10
    calls.append(parse_qs(parsed.query)['client_version'][0])
    response = next(responses)
    return httpx.Response(response['status'], json=response.get('body', {}))
with patch.object(httpx, 'get', side_effect=get):
    discovered = models._fetch_models_from_api('oai-oat01-proxy-managed')
print(json.dumps({'models': discovered, 'versions': calls}))
'''], env=env, cwd=self.root, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_discovers_new_catalog_models_and_preserves_visibility(self):
        wanted = ['gpt-6.1-sol', 'gpt-6-sol', 'gpt-6-luna']
        result = self.discover([{'status': 200, 'body': {'models': [
            *[{'slug': model, 'visibility': 'list'} for model in wanted],
            {'slug': 'hidden-fixture', 'visibility': 'hidden'},
        ]}}])
        self.assertEqual(result['versions'], ['99.0.0'])
        for model in wanted:
            self.assertIn(model, result['models'])
        self.assertNotIn('hidden-fixture', result['models'])

    def test_nonempty_newest_catalog_is_not_replaced_by_legacy(self):
        result = self.discover([{'status': 200, 'body': {'models': [{'slug': 'account-model-fixture'}]}}])
        self.assertEqual(result['models'], ['account-model-fixture'])
        self.assertEqual(result['versions'], ['99.0.0'])

    def test_empty_newest_catalog_falls_back(self):
        result = self.discover([
            {'status': 200, 'body': {'models': []}},
            {'status': 200, 'body': {'models': [{'slug': 'legacy-fixture'}]}},
        ])
        self.assertEqual(result['models'], ['legacy-fixture'])
        self.assertEqual(result['versions'], ['99.0.0', '0.0.0'])

    def test_rejected_newest_version_falls_back(self):
        result = self.discover([
            {'status': 400}, {'status': 200, 'body': {'models': [{'slug': 'legacy-fixture'}]}},
        ])
        self.assertEqual(result['models'], ['legacy-fixture'])
        self.assertEqual(result['versions'], ['99.0.0', '0.0.0'])

    def test_auth_and_throttling_errors_do_not_retry(self):
        for status in (401, 403, 429, 500):
            with self.subTest(status=status):
                result = self.discover([{'status': status}])
                self.assertEqual(result['models'], [])
                self.assertEqual(result['versions'], ['99.0.0'])

    def test_empty_catalog_does_not_invent_requested_models(self):
        result = self.discover([
            {'status': 200, 'body': {'models': []}},
            {'status': 200, 'body': {'models': []}},
        ])
        self.assertEqual(result['models'], [])

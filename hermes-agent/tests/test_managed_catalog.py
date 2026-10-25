"""Run with HERMES_SOURCE pointing at the upstream v0.22.5 checkout."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2] / "hermes-agent"
SCRIPT = ROOT / 'files/home/.local/bin/hermes-managed-catalog-compat.py'
spec = importlib.util.spec_from_file_location('compat', SCRIPT)
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)
catalog_spec = importlib.util.spec_from_file_location(
    'catalog_compat', SCRIPT.with_name('hermes-codex-catalog-compat.py'))
catalog_compat = importlib.util.module_from_spec(catalog_spec)
catalog_spec.loader.exec_module(catalog_compat)
SOURCE = os.environ.get('HERMES_SOURCE')


class SafetyTests(unittest.TestCase):
    def test_kit_variants_ship_identical_managed_adapter(self):
        other = ROOT.parent / 'hermes-agent-mixin/files/home/.local/bin' / SCRIPT.name
        self.assertEqual(SCRIPT.read_bytes(), other.read_bytes())

    def test_unknown_source_is_rejected_without_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'agent').mkdir()
            target = root / 'agent/model_metadata.py'
            target.write_text('def unrelated():\n    pass\n')
            with self.assertRaises(ValueError):
                compat.install(root)
            self.assertEqual(target.read_text(), 'def unrelated():\n    pass\n')


@unittest.skipUnless(SOURCE, 'set HERMES_SOURCE to upstream v0.22.5')
class RuntimeTests(unittest.TestCase):
    def test_bound_discovery_and_credential_route_guards(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for directory in ('agent', 'hermes_cli'):
                (root / directory).mkdir()
            target = root / 'agent/model_metadata.py'
            upstream = (Path(SOURCE) / 'agent/model_metadata.py').read_text()
            if 'def _codex_catalog_probe_allowed' not in upstream:
                self.skipTest('this release has no JWT catalog gate')
            target.write_text(upstream)
            codex_models = root / 'hermes_cli/codex_models.py'
            original_models = (Path(SOURCE) / 'hermes_cli/codex_models.py').read_text()
            codex_models.write_text(original_models)
            self.assertTrue(catalog_compat.backport(root))
            self.assertFalse(catalog_compat.backport(root))
            self.assertEqual(codex_models.read_text(), original_models)
            env = dict(os.environ, HOME=temp, HERMES_HOME=str(root / '.hermes'),
                       PYTHONPATH=str(Path(SOURCE).resolve()), PATCHED_SOURCE=temp,
                       HERMES_DISABLE_LAZY_INSTALLS='1')
            result = subprocess.run([sys.executable, '-c', r'''
import base64
import importlib.util
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch
import httpx
import agent
import hermes_cli

root = Path(os.environ['PATCHED_SOURCE'])
for name, path in [('hermes_cli.docker_codex_catalog', root / 'hermes_cli/docker_codex_catalog.py'),
                   ('agent.model_metadata', root / 'agent/model_metadata.py')]:
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    package, attr = name.rsplit('.', 1)
    setattr(sys.modules[package], attr, module)
gate = agent.model_metadata._codex_catalog_probe_allowed
token = 'oai-oat01-proxy-managed'
canonical = 'https://chatgpt.com/backend-api/codex'
seed = root / '.docker/hermes-openai-oauth.json'
seed.parent.mkdir()
assert not gate(token, canonical)
seed.write_text(json.dumps({'access_token': token, 'refresh_token': 'wrong'}))
assert not gate(token, canonical)
seed.write_text(json.dumps({'access_token': token, 'refresh_token': 'oai-ort01-proxy-managed'}))
assert gate(token, canonical)
assert gate(token, '')
for route in ('http://chatgpt.com/backend-api/codex', 'https://chatgpt.com.evil.test/backend-api/codex',
              'https://chatgpt.com/other', canonical + '?x=1', canonical + '#fragment',
              'https://user@chatgpt.com/backend-api/codex', 'https://gateway.example/v1'):
    assert not gate(token, route), route
assert not gate('opaque-native-key', canonical)
assert not gate('', canonical)
assert gate('opaque-gateway-key', 'https://gateway.example/v1')
encoded = base64.urlsafe_b64encode(json.dumps({'sub': 'fixture'}).encode()).decode().rstrip('=')
assert gate('e30.' + encoded + '.fixture', canonical)

# Exercise real upstream discovery; its native newest-client query, sorting,
# filtering and picker model synthesis remain intact.
from hermes_cli.codex_models import _fetch_models_from_api
state = Path(os.environ['HERMES_HOME'])
state.mkdir(exist_ok=True)
(state / 'auth.json').write_text(json.dumps({'version': 1, 'active_provider': 'openai-codex',
    'providers': {'openai-codex': {'auth_mode': 'chatgpt', 'tokens': {
        'access_token': token, 'refresh_token': 'oai-ort01-proxy-managed'}}}}))
calls = []
def get(url, **kwargs):
    calls.append(url)
    assert url == canonical + '/models?client_version=99.0.0'
    assert kwargs['headers']['Authorization'] == 'Bearer ' + token
    return httpx.Response(200, json={'models': [
        {'slug': 'gpt-6.1-sol', 'visibility': 'list', 'priority': 1},
        {'slug': 'gpt-6-astra', 'visibility': 'list', 'priority': 2},
        {'slug': 'hidden-fixture', 'visibility': 'hide'}]})
with patch.object(httpx, 'get', side_effect=get):
    models = _fetch_models_from_api(token, canonical)
    assert 'gpt-6.1-sol' in models and 'gpt-6-astra' in models
    assert 'hidden-fixture' not in models
    assert len(calls) == 1
    from hermes_cli.models import cached_provider_model_ids
    picker_models = cached_provider_model_ids('openai-codex', force_refresh=True)
    assert 'gpt-6.1-sol' in picker_models and 'gpt-6-astra' in picker_models
    assert 'hidden-fixture' not in picker_models
    before_unbind = len(calls)
    seed.unlink()
    assert not gate(token, canonical)
    assert not _fetch_models_from_api(token, canonical)
    assert len(calls) == before_unbind, 'unbound placeholder made a catalog request'

seed.write_text('not-json')
assert not gate(token, canonical)
seed.unlink()
seed.symlink_to(root / 'missing')
assert not gate(token, canonical)
'''], env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()

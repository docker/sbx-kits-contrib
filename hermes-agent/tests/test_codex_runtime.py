"""Optional real-Hermes contract tests, in addition to the stdlib unit suite.

Set HERMES_SOURCE to a Hermes checkout and run with that release's Python/deps:
HERMES_SOURCE=/path/to/hermes python -m unittest discover -s hermes-agent/tests -v
HTTP responses here simulate Docker's masking contract, not its implementation.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / 'hermes-agent/files/home/.local/bin/hermes-codex-auth.py'
SOURCE = os.environ.get('HERMES_SOURCE')


@unittest.skipUnless(SOURCE, 'set HERMES_SOURCE to run real-Hermes contract tests')
class RuntimeTests(unittest.TestCase):

    def test_resolver_picker_status_and_masked_refresh(self):
        # A subprocess avoids module/global home caches crossing profile boundaries.
        with tempfile.TemporaryDirectory() as temp:
            env = dict(os.environ, HERMES_HOME=temp, PYTHONPATH=str(Path(SOURCE).resolve()),
                       BRIDGE_PATH=str(BRIDGE), HERMES_DISABLE_LAZY_INSTALLS='1')
            result = subprocess.run([sys.executable, '-c', r'''
import importlib.util
import inspect
import json
import os
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs
import httpx

spec = importlib.util.spec_from_file_location('bridge', os.environ['BRIDGE_PATH'])
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
state = Path(os.environ['HERMES_HOME'])
seed = state / 'seed.json'
seed.write_text(json.dumps({'access_token': bridge.ACCESS, 'refresh_token': bridge.REFRESH}))
bridge.bridge(state, seed)

from hermes_cli import auth
from agent.codex_headers import codex_cloudflare_headers
assert not auth._codex_access_token_is_expiring(bridge.ACCESS, 120)
headers = codex_cloudflare_headers(bridge.ACCESS)
assert 'ChatGPT-Account-ID' not in headers  # Documented metadata gap.
assert 'x-openai-internal-codex-residency' not in headers

# Real resolver: no HTTP request should occur during ordinary sentinel resolution.
with patch.object(httpx.Client, 'send', side_effect=AssertionError('unexpected HTTP')):
    resolved = auth.resolve_codex_runtime_credentials()
    assert resolved['api_key'] == bridge.ACCESS
    assert resolved['auth_mode'] == 'chatgpt'
    assert resolved['base_url'] == 'https://chatgpt.com/backend-api/codex'
    assert auth.get_codex_auth_status()['logged_in'] is True

# Exercise the actual model-picker provider discovery, not just the auth resolver.
# An empty remote catalog proves fallback visibility without claiming entitlement.
from hermes_cli.models import list_available_providers
from hermes_cli.model_switch_providers import list_picker_providers
import socket

def picker_rows():
    with patch('agent.models_dev.fetch_models_dev', return_value={}), \
         patch.object(httpx, 'get', return_value=httpx.Response(200, json={'models': []})), \
         patch.object(socket.socket, 'connect', side_effect=OSError('network disabled in contract test')):
        kwargs = {}
        if 'probe_custom_providers' in inspect.signature(list_picker_providers).parameters:
            kwargs['probe_custom_providers'] = False
        return list_picker_providers(**kwargs)

available = {row['id']: row for row in list_available_providers()}
assert available['openai-codex']['authenticated'] is True
rows = picker_rows()
codex = next(row for row in rows if row['slug'] == 'openai-codex')
assert codex['models'], 'bound OAuth provider missing model-picker choices'
assert bridge.ACCESS not in json.dumps(rows)
assert bridge.REFRESH not in json.dumps(rows)

# Simulate an intercepted refresh response; exercise actual Hermes POST/parsing/save.
seen = []
def intercepted(request):
    assert request.url.host == 'auth.openai.com'
    assert request.url.path == '/oauth/token'
    payload = parse_qs(request.content.decode())
    assert payload['grant_type'] == ['refresh_token']
    assert payload['refresh_token'] == [bridge.REFRESH]
    seen.append(True)
    return httpx.Response(200, json={'access_token': bridge.ACCESS,
                                    'refresh_token': bridge.REFRESH, 'expires_in': 3600})
client = httpx.Client(transport=httpx.MockTransport(intercepted))
with patch.object(httpx, 'Client', return_value=client):
    refreshed = auth.resolve_codex_runtime_credentials(force_refresh=True)
assert seen == [True]
assert refreshed['api_key'] == bridge.ACCESS
saved = json.loads((state / 'auth.json').read_text())
assert saved['providers']['openai-codex']['tokens']['refresh_token'] == bridge.REFRESH
assert saved['providers']['openai-codex']['tokens']['access_token'] == bridge.ACCESS
seed.unlink()
bridge.bridge(state, seed)
try:
    auth.resolve_codex_runtime_credentials()
except auth.AuthError:
    pass
else:
    raise AssertionError('removed binding still resolves')
assert not any(row['slug'] == 'openai-codex' for row in picker_rows())
assert not next(row for row in list_available_providers() if row['id'] == 'openai-codex')['authenticated']
print('Hermes resolver, picker visibility, status, simulated masked refresh, and removal passed')
'''], env=env, cwd=temp, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

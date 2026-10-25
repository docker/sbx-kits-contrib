"""Native Hermes credential mutation alongside a Docker-managed Codex binding.

Actual Hermes command/store paths, with fixture OAuth results and no network.
This does not test Docker's host proxy or real additional-account login.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = os.environ.get('HERMES_SOURCE')
BRIDGE = Path(__file__).resolve().parents[1] / 'files/home/.local/bin/hermes-codex-auth.py'


@unittest.skipUnless(SOURCE, 'set HERMES_SOURCE to a supported Hermes checkout')
class AccountConflictTests(unittest.TestCase):
    def run_scenario(self, scenario):
        with tempfile.TemporaryDirectory() as temp:
            env = dict(os.environ, HOME=temp, HERMES_HOME=temp + '/.hermes',
                       PYTHONPATH=str(Path(SOURCE).resolve()), BRIDGE_PATH=str(BRIDGE),
                       SCENARIO=scenario, HERMES_DISABLE_LAZY_INSTALLS='1')
            result = subprocess.run([sys.executable, '-c', r'''
import base64
import contextlib
import dataclasses
import importlib.util
import inspect
import io
import json
import os
from pathlib import Path
import socket
import time
from types import SimpleNamespace
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bridge', os.environ['BRIDGE_PATH'])
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
state = Path(os.environ['HERMES_HOME'])
seed = Path.home() / '.docker/hermes-openai-oauth.json'
seed.parent.mkdir()
seed.write_text(json.dumps({'access_token': bridge.ACCESS, 'refresh_token': bridge.REFRESH}))
bridge.bridge(state, seed)
store_path = state / 'auth.json'
from hermes_cli import auth
def resolved_key():
    kwargs = {'read_only': True} if 'read_only' in inspect.signature(auth.resolve_codex_runtime_credentials).parameters else {'refresh_if_expiring': False}
    return auth.resolve_codex_runtime_credentials(**kwargs)['api_key']

claims = {'sub': 'native-fixture', 'exp': int(time.time()) + 3600,
          'https://api.openai.com/auth': {'chatgpt_account_id': 'native-fixture'}}
encoded = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip('=')
native = {'access_token': 'e30.' + encoded + '.fixture',
          'refresh_token': 'native-refresh-fixture'}
login_result = {'tokens': native, 'base_url': 'https://chatgpt.com/backend-api/codex'}

with patch.object(socket.socket, 'connect', side_effect=AssertionError('network forbidden')):
    assert resolved_key() == bridge.ACCESS
    if os.environ['SCENARIO'] == 'login':
        # Force the real login command past its existing-credential reuse prompt.
        # Mock only the external OAuth exchange and output/config side effects.
        if 'codex_oauth_login' in inspect.getsource(auth._login_openai_codex):
            from hermes_cli import auth_codex_browser
            flow = patch.object(auth_codex_browser, 'codex_oauth_login', return_value=login_result)
        else:
            flow = patch.object(auth, '_codex_device_code_login', return_value=login_result)
        with flow, patch.object(auth, '_update_config_for_provider', return_value='fixture-config'), \
             patch.object(auth, '_print_login_success'), contextlib.redirect_stdout(io.StringIO()):
            auth._login_openai_codex(SimpleNamespace(), None, force_new_login=True)
        stored = json.loads(store_path.read_text())
        assert stored['providers']['openai-codex']['tokens'] == native
        assert resolved_key() == native['access_token']
    else:
        # Exercise actual `hermes auth add openai-codex` and its pool persistence.
        from hermes_cli import auth_commands
        original = auth_commands._OAUTH_ADD_SPECS['openai-codex']
        mocked = dataclasses.replace(original, login=lambda args: login_result)
        with patch.dict(auth_commands._OAUTH_ADD_SPECS, {'openai-codex': mocked}), \
             contextlib.redirect_stdout(io.StringIO()):
            auth_commands.auth_add_command(SimpleNamespace(provider='openai-codex', auth_type='oauth',
                                                           label='native-fixture', priority=None))
        stored = json.loads(store_path.read_text())
        assert bridge.managed(stored['providers']['openai-codex'])
        assert any(row.get('access_token') == native['access_token']
                   for row in stored['credential_pool']['openai-codex'])
        # Singleton resolution still sees the managed identity. Pool selection by
        # inference, rotation, and Docker injection are separate runtime paths.
        assert resolved_key() == bridge.ACCESS

    before = store_path.read_bytes()
    try:
        bridge.bridge(state, seed)
    except bridge.BridgeError:
        pass
    else:
        raise AssertionError('mixed native/managed credentials accepted at next startup')
    assert store_path.read_bytes() == before, 'conflict handling modified credentials'
    assert seed.read_text() == json.dumps({'access_token': bridge.ACCESS, 'refresh_token': bridge.REFRESH})
'''], env=env, cwd=temp, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_native_login_can_replace_singleton_then_startup_rejects_conflict(self):
        self.run_scenario('login')

    def test_native_auth_add_persists_pool_entry_then_startup_rejects_conflict(self):
        self.run_scenario('pool')


if __name__ == '__main__':
    unittest.main()

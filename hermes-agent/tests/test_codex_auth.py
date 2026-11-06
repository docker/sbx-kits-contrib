"""Run with: python3 -m unittest discover -s hermes-agent/tests -v."""
import fcntl
import importlib.util
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'hermes-agent/files/home/.local/bin/hermes-codex-auth.py'
spec = importlib.util.spec_from_file_location('codex_bridge', SCRIPT)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
TOKENS = {'access_token': bridge.ACCESS, 'refresh_token': bridge.REFRESH}


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.state = self.home / '.hermes'
        self.seed = self.home / '.docker/hermes-openai-oauth.json'

    def bind(self, value=None):
        self.seed.parent.mkdir(exist_ok=True)
        self.seed.write_text(json.dumps(TOKENS if value is None else value))

    def write_store(self, value):
        self.state.mkdir(exist_ok=True)
        (self.state / 'auth.json').write_text(json.dumps(value))

    def read_store(self):
        return json.loads((self.state / 'auth.json').read_text())

    def test_no_binding_does_not_create_auth_store(self):
        self.assertFalse(bridge.bridge(self.state, self.seed))
        self.assertFalse(self.state.exists())

    def test_binding_materializes_only_sentinels_idempotently(self):
        self.bind()
        self.assertTrue(bridge.bridge(self.state, self.seed))
        auth = self.state / 'auth.json'
        self.assertEqual(auth.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.read_store()['providers']['openai-codex']['tokens'], TOKENS)
        self.assertEqual(self.read_store()['active_provider'], 'openai-codex')
        before = auth.stat().st_mtime_ns
        bridge.bridge(self.state, self.seed)
        self.assertEqual(auth.stat().st_mtime_ns, before)

    def test_preserves_other_credentials_and_active_choice(self):
        original = {'version': 1, 'active_provider': 'anthropic',
                    'providers': {'anthropic': {'tokens': {'access_token': 'other-identity'}}},
                    'credential_pool': {'openrouter': [{'api_key': 'unrelated'}]}}
        self.write_store(original)
        self.bind()
        bridge.bridge(self.state, self.seed)
        result = self.read_store()
        self.assertEqual(result['active_provider'], original['active_provider'])
        self.assertEqual(result['providers']['anthropic'], original['providers']['anthropic'])
        self.assertEqual(result['credential_pool'], original['credential_pool'])

    def test_rejects_real_tokens_from_seed_without_writing_them(self):
        self.bind({'access_token': 'real-access-fixture', 'refresh_token': 'real-refresh-fixture'})
        with self.assertRaises(ValueError):
            bridge.bridge(self.state, self.seed)
        self.assertFalse(self.state.exists())

    def test_refuses_to_overwrite_native_singleton_or_pool(self):
        for store in [
            {'providers': {'openai-codex': {'tokens': {'access_token': 'native'}}}},
            {'credential_pool': {'openai-codex': [{'access_token': 'native'}]}},
        ]:
            with self.subTest(store=store):
                self.write_store(store)
                self.bind()
                before = (self.state / 'auth.json').read_bytes()
                with self.assertRaises(ValueError):
                    bridge.bridge(self.state, self.seed)
                self.assertEqual((self.state / 'auth.json').read_bytes(), before)

    def test_removes_managed_singleton_and_pool_when_binding_removed(self):
        self.bind()
        bridge.bridge(self.state, self.seed)
        store = self.read_store()
        store['credential_pool'] = {'openai-codex': [dict(TOKENS, source='device_code')]}
        self.write_store(store)
        self.seed.unlink()
        self.assertFalse(bridge.bridge(self.state, self.seed))
        result = self.read_store()
        self.assertNotIn('openai-codex', result['providers'])
        self.assertNotIn('openai-codex', result['credential_pool'])
        self.assertNotIn('active_provider', result)

    def test_unbound_cleanup_preserves_independent_accounts(self):
        native = {'access_token': 'native', 'refresh_token': 'native-refresh'}
        self.write_store({'providers': {'openai-codex': {'tokens': native}},
                          'active_provider': 'openai-codex',
                          'credential_pool': {'openai-codex': [TOKENS, native]}})
        bridge.bridge(self.state, self.seed)
        result = self.read_store()
        self.assertEqual(result['providers']['openai-codex']['tokens'], native)
        self.assertEqual(result['credential_pool']['openai-codex'], [native])
        self.assertEqual(result['active_provider'], 'openai-codex')

    def test_malformed_store_is_not_replaced(self):
        self.bind()
        self.state.mkdir()
        auth = self.state / 'auth.json'
        for text in ['{broken', '[]', '{"providers": []}', '{"version": 2}',
                     '{"credential_pool": {"openai-codex": {}}}']:
            auth.write_text(text)
            with self.subTest(text=text), self.assertRaises(ValueError):
                bridge.bridge(self.state, self.seed)
            self.assertEqual(auth.read_text(), text)

    def test_seed_and_auth_symlinks_are_rejected(self):
        target = self.home / 'target'
        target.write_text(json.dumps(TOKENS))
        self.seed.parent.mkdir()
        self.seed.symlink_to(target)
        with self.assertRaises(ValueError):
            bridge.bridge(self.state, self.seed)
        self.seed.unlink()
        self.bind()
        self.state.mkdir()
        (self.state / 'auth.json').symlink_to(target)
        with self.assertRaises(ValueError):
            bridge.bridge(self.state, self.seed)
        self.assertEqual(json.loads(target.read_text()), TOKENS)

    def test_waits_for_hermes_auth_lock_before_read_modify_write(self):
        self.bind()
        self.state.mkdir()
        env = dict(os.environ, HOME=str(self.home), HERMES_HOME=str(self.state))
        with (self.state / 'auth.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = subprocess.Popen([sys.executable, str(SCRIPT)], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.wait(timeout=0.3)
                self.write_store({'providers': {'anthropic': {'unchanged': True}}})
                fcntl.flock(lock, fcntl.LOCK_UN)
                stdout, stderr = process.communicate(timeout=10)
                self.assertEqual(process.returncode, 0, stderr)
                self.assertEqual(stdout.strip(), 'oauth')
                self.assertEqual(self.read_store()['providers']['anthropic'], {'unchanged': True})
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()

    def test_errors_do_not_echo_secret_file_contents(self):
        self.bind({'access_token': 'sensitive-fixture'})
        result = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True,
                                env=dict(os.environ, HOME=str(self.home), HERMES_HOME=str(self.state)))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('sensitive-fixture', result.stderr + result.stdout)

    def run_startup(self, mode, **extra):
        binary = self.home / '.local/bin'
        binary.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SCRIPT, binary / SCRIPT.name)
        interpreter = self.home / '.hermes/hermes-agent/venv/bin/python'
        interpreter.parent.mkdir(parents=True, exist_ok=True)
        if not interpreter.exists():
            interpreter.symlink_to(sys.executable)
        shim = binary / 'hermes-kit-python'
        if not shim.exists():
            shim.symlink_to(interpreter)
        env = dict(os.environ, HOME=str(self.home), HERMES_HOME=str(self.state),
                   SBX_CRED_OPENAI_MODE=mode, SBX_CRED_OPENROUTER_MODE='none',
                   SBX_CRED_ANTHROPIC_MODE='none', SBX_CRED_COPILOT_MODE='none')
        env.update(extra)
        return subprocess.run(['sh', str(SCRIPT.parent / 'hermes-credential-auth.sh')],
                              env=env, capture_output=True, text=True)

    def test_startup_api_key_oauth_and_none_modes(self):
        # The shell must drop an API-key placeholder in OAuth mode, including
        # engines that report none for a materialized OAuth binding.
        for mode, oauth, should_unset in [
            ('apikey', False, False), ('none', False, True),
            ('oauth', True, True), ('none', True, True),
        ]:
            with self.subTest(mode=mode, oauth=oauth):
                if oauth:
                    self.bind()
                elif self.seed.exists():
                    self.seed.unlink()
                result = self.run_startup(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                auth_env = (self.state / 'credential-auth.env').read_text()
                self.assertEqual('unset OPENAI_API_KEY' in auth_env, should_unset)
                self.assertIn('unset OPENROUTER_API_KEY', auth_env)
                self.assertIn('unset ANTHROPIC_API_KEY', auth_env)

    def test_startup_preserves_other_bound_provider_modes(self):
        result = self.run_startup('apikey',
                                  SBX_CRED_OPENROUTER_MODE='apikey',
                                  SBX_CRED_ANTHROPIC_MODE='apikey',
                                  SBX_CRED_COPILOT_MODE='apikey')
        self.assertEqual(result.returncode, 0, result.stderr)
        auth_env = (self.state / 'credential-auth.env').read_text()
        self.assertNotIn('unset ', auth_env)
        self.assertIn('export COPILOT_GITHUB_TOKEN=github_pat_proxy_managed', auth_env)


    def test_startup_fails_on_conflicting_native_codex_account(self):
        self.write_store({'providers': {'openai-codex': {'tokens': {'access_token': 'native'}}}})
        self.bind()
        result = self.run_startup('oauth')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('bridge failed', result.stderr)
        self.assertEqual(self.read_store()['providers']['openai-codex']['tokens']['access_token'], 'native')

    def test_both_kits_ship_the_same_bridge_and_startup(self):
        other = ROOT / 'hermes-agent-mixin/files/home/.local/bin'
        self.assertEqual(SCRIPT.read_bytes(), (other / SCRIPT.name).read_bytes())
        name = 'hermes-credential-auth.sh'
        self.assertEqual((SCRIPT.parent / name).read_bytes(), (other / name).read_bytes())


if __name__ == '__main__':
    unittest.main()

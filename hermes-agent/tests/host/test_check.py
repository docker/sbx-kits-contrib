"""Offline tests of the diagnostic's secret-handling boundary."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from urllib.parse import parse_qs
from unittest.mock import patch

import httpx
import check


class GuardTests(unittest.TestCase):
    def test_form_probe_classifies_oauth_error_and_never_saves_response(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HERMES_HOME': temp}):
            store = Path(temp) / 'auth.json'
            store.write_text('{}')
            constants = types.ModuleType('hermes_cli.auth_constants')
            constants.CODEX_OAUTH_CLIENT_ID = 'fixture-client'
            constants.CODEX_OAUTH_USER_AGENT = 'fixture-agent'

            def send(client, request, **kwargs):
                self.assertEqual(request.headers['content-type'], 'application/x-www-form-urlencoded')
                fields = parse_qs(request.content.decode())
                self.assertEqual(fields['refresh_token'], [check.REFRESH])
                self.assertEqual(fields['client_id'], ['fixture-client'])
                self.assertEqual(request.headers['user-agent'], 'fixture-agent')
                return httpx.Response(401, json={'error': 'invalid_client',
                    'error_description': 'Client authentication failed private-fixture'})

            with patch.dict('sys.modules', {'hermes_cli.auth_constants': constants}), \
                    patch.object(httpx.Client, 'send', send):
                report = check.refresh_json_probe('form')
            self.assertEqual(report['encoding'], 'form')
            self.assertEqual(report['recognized_oauth_error'], 'invalid_client')
            self.assertEqual(report['recognized_client_error_detail'], 'client authentication failed')
            self.assertNotIn('private-fixture', json.dumps(report))
            self.assertEqual(store.read_text(), '{}')

    def test_json_probe_classifies_rejection_without_echoing_body_or_writing_store(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HERMES_HOME': temp}):
            store = Path(temp) / 'auth.json'
            store.write_text('{}')
            constants = types.ModuleType('hermes_cli.auth_constants')
            constants.CODEX_OAUTH_CLIENT_ID = 'fixture-client'
            constants.CODEX_OAUTH_USER_AGENT = 'fixture-agent'

            def send(client, request, **kwargs):
                self.assertTrue(client.trust_env)
                self.assertEqual(str(request.url), 'https://auth.openai.com/oauth/token')
                self.assertEqual(request.headers['content-type'], 'application/json')
                self.assertEqual(json.loads(request.content), {'grant_type': 'refresh_token',
                    'refresh_token': check.REFRESH, 'client_id': 'fixture-client'})
                return httpx.Response(401, text='proxy: OAuth request denied (unrecognized grant) private-fixture')

            with patch.dict('sys.modules', {'hermes_cli.auth_constants': constants}), \
                    patch.object(httpx.Client, 'send', send):
                report = check.refresh_json_probe()
            self.assertTrue(report['proxy_oauth_denial'])
            self.assertEqual(report['recognized_proxy_reason'], 'unrecognized grant')
            self.assertTrue(report['auth_store_unchanged'])
            self.assertFalse(report['response_persisted'])
            self.assertNotIn('private-fixture', json.dumps(report))

    def test_json_probe_rejects_unmasked_success_without_writing_store(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HERMES_HOME': temp}):
            store = Path(temp) / 'auth.json'
            store.write_text('{}')
            constants = types.ModuleType('hermes_cli.auth_constants')
            constants.CODEX_OAUTH_CLIENT_ID = 'fixture-client'
            constants.CODEX_OAUTH_USER_AGENT = 'fixture-agent'
            with patch.dict('sys.modules', {'hermes_cli.auth_constants': constants}), \
                    patch.object(httpx.Client, 'send', return_value=httpx.Response(
                        200, json={'access_token': 'private-fixture', 'refresh_token': 'private-fixture'})):
                with self.assertRaises(check.CheckFailure) as caught:
                    check.refresh_json_probe()
            self.assertEqual(store.read_text(), '{}')
            self.assertNotIn('private-fixture', str(caught.exception))

    def request(self, url='https://auth.openai.com/oauth/token'):
        return httpx.Request('POST', url, data={
            'grant_type': 'refresh_token', 'refresh_token': check.REFRESH})

    def test_unmasked_response_never_reaches_caller(self):
        for payload in ({'access_token': 'private-fixture', 'refresh_token': check.REFRESH},
                        {'access_token': check.ACCESS, 'refresh_token': 'private-fixture'},
                        {'access_token': check.ACCESS, 'refresh_token': check.REFRESH,
                         'id_token': 'private-fixture'}):
            with self.subTest(payload_shape=list(payload)):
                send = check.guarded_send(lambda *a, **k: httpx.Response(200, json=payload))
                with self.assertRaises(check.CheckFailure) as caught:
                    send(None, self.request())
                self.assertNotIn('private-fixture', str(caught.exception))
                self.assertEqual(send.checked_responses, 0)

    def test_masked_response_is_returned_without_following_redirects(self):
        def original(client, request, **kwargs):
            self.assertFalse(kwargs['follow_redirects'])
            return httpx.Response(200, json={
                'access_token': check.ACCESS, 'refresh_token': check.REFRESH})
        send = check.guarded_send(original)
        self.assertEqual(send(None, self.request()).status_code, 200)
        self.assertEqual(send.checked_responses, 1)

    def test_wrong_route_is_blocked_before_network(self):
        def forbidden(*args, **kwargs):
            self.fail('unexpected network call')
        with self.assertRaises(check.CheckFailure):
            check.guarded_send(forbidden)(None, self.request('https://example.com/oauth/token'))

    def test_http_error_body_does_not_reach_caller(self):
        send = check.guarded_send(lambda *a, **k: httpx.Response(401, text='private-fixture'))
        with self.assertRaises(check.CheckFailure) as caught:
            send(None, self.request())
        self.assertEqual(str(caught.exception), 'refresh_http_401')

    def test_bound_and_removed_state_and_permissions(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {
                'HOME': temp, 'HERMES_HOME': temp + '/.hermes', 'OPENAI_API_KEY': ''}):
            home = Path(temp)
            seed = home / '.docker/hermes-openai-oauth.json'
            seed.parent.mkdir()
            tokens = {'access_token': check.ACCESS, 'refresh_token': check.REFRESH}
            seed.write_text(json.dumps(tokens))
            auth = home / '.hermes/auth.json'
            auth.parent.mkdir()
            auth.write_text(json.dumps({'providers': {'openai-codex': {'tokens': tokens}}}))
            auth.chmod(0o600)
            self.assertTrue(check.state('bound')['credential_state_passed'])
            auth.chmod(0o644)
            with self.assertRaises(check.CheckFailure):
                check.state('bound')
            auth.write_text('{}')
            with self.assertRaises(check.CheckFailure):
                check.state('unbound')
            seed.unlink()
            self.assertTrue(check.state('unbound')['credential_state_passed'])

    def test_main_suppresses_library_output_and_exception_secrets(self):
        def bad_state(*args):
            print('private-fixture')
            raise ValueError('private-fixture')
        output = io.StringIO()
        with patch('sys.argv', ['check.py', 'state']), patch.object(check, 'state', bad_state), \
                contextlib.redirect_stdout(output):
            self.assertEqual(check.main(), 1)
        self.assertNotIn('private-fixture', output.getvalue())


if __name__ == '__main__':
    unittest.main()

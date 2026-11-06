#!/usr/bin/env python3
"""Run inside a disposable sandbox. Output contains only fixed labels/model IDs.

state/catalog never request refresh. refresh invokes Hermes' real resolver but
rejects an unmasked HTTP response before Hermes can persist it. No bypasses.
"""
import argparse
import contextlib
import inspect
import io
import json
import logging
import os
from pathlib import Path
import re
import stat
import sys
from urllib.parse import parse_qs, urlsplit
from unittest.mock import patch

ACCESS = 'oai-oat01-proxy-managed'
REFRESH = 'oai-ort01-proxy-managed'
BASE = 'https://chatgpt.com/backend-api/codex'
STAGE = 'credential_state'


class CheckFailure(Exception):
    pass


def require(condition, label):
    if not condition:
        raise CheckFailure(label)


def pair(record):
    tokens = record.get('tokens', record)
    return (tokens.get('access_token') == ACCESS
            and tokens.get('refresh_token') == REFRESH
            and not tokens.get('id_token'))


def read(path):
    require(not path.is_symlink(), 'credential_path_is_symlink')
    return json.loads(path.read_text()) if path.exists() else {}


def state(expected):
    home = Path.home()
    root = Path(os.environ.get('HERMES_HOME', home / '.hermes'))
    seed = read(home / '.docker/hermes-openai-oauth.json')
    auth_path = root / 'auth.json'
    store = read(auth_path)
    provider = store.get('providers', {}).get('openai-codex')
    pool = store.get('credential_pool', {}).get('openai-codex', [])
    if expected == 'bound':
        require(pair(seed), 'rendered_seed_not_exact_managed_pair')
        require(provider is not None and pair(provider), 'singleton_not_exact_managed_pair')
        require(all(pair(row) for row in pool), 'independent_codex_pool_entry')
        require(stat.S_IMODE(auth_path.stat().st_mode) == 0o600, 'auth_store_not_0600')
        require(not os.environ.get('OPENAI_API_KEY'), 'api_key_shadows_oauth')
    else:
        require(not seed, 'rendered_seed_still_present')
        require(provider is None and not pool, 'codex_credentials_still_present')
    # Check the other common OpenAI store without displaying its contents.
    codex = read(home / '.codex/auth.json')
    if codex:
        tokens = codex.get('tokens', {})
        require(not tokens or pair(tokens), 'independent_codex_cli_tokens_present')
    return {'expected_binding': expected, 'credential_state_passed': True,
            'scope': 'rendered_seed_hermes_codex_records_and_optional_codex_cli_store'}


def resolved(auth):
    kwargs = {'read_only': True} if 'read_only' in inspect.signature(
        auth.resolve_codex_runtime_credentials).parameters else {'refresh_if_expiring': False}
    value = auth.resolve_codex_runtime_credentials(**kwargs)
    require(value.get('api_key') == ACCESS, 'resolver_did_not_return_placeholder')
    require(value.get('base_url', '').rstrip('/') == BASE, 'resolver_noncanonical_route')
    return value


def model_ids(values):
    require(isinstance(values, (list, tuple)), 'invalid_model_list_shape')
    require(all(isinstance(v, str) and re.fullmatch(r'[a-zA-Z0-9._:/-]{1,160}', v)
                for v in values), 'invalid_model_id')
    return sorted(set(values))


def catalog():
    global STAGE
    STAGE = 'catalog_imports'
    import httpx
    from hermes_cli import auth
    from hermes_cli.models import cached_provider_model_ids
    STAGE = 'catalog_resolver'
    resolved(auth)
    STAGE = 'live_catalog_request'
    with httpx.Client(trust_env=True, timeout=20, follow_redirects=False) as client:
        response = client.get(BASE + '/models', params={'client_version': '99.0.0'},
                              headers={'Authorization': 'Bearer ' + ACCESS})
    require(response.status_code == 200, 'live_catalog_http_' + str(response.status_code))
    STAGE = 'live_catalog_decode'
    payload = response.json()
    live = model_ids([r['slug'] for r in payload.get('models', [])
                      if isinstance(r, dict) and r.get('visibility') != 'hide' and 'slug' in r])
    require(bool(live), 'live_catalog_empty')
    STAGE = 'hermes_picker_refresh'
    picker = model_ids(cached_provider_model_ids('openai-codex', force_refresh=True))
    # A curated fallback alone must never count as a successful live catalog test.
    require(set(live).issubset(picker), 'live_models_missing_from_picker')
    return {'live_model_ids': live, 'picker_model_ids': picker, 'catalog_passed': True}


def guarded_send(original):
    """Guard the real response before the real resolver sees it or saves tokens."""
    def send(client, request, **kwargs):
        target = urlsplit(str(request.url))
        require(request.method == 'POST' and target.scheme == 'https'
                and target.netloc == 'auth.openai.com' and target.path == '/oauth/token'
                and not target.query and not target.fragment, 'unexpected_refresh_route')
        form = parse_qs(request.content.decode())
        require(form.get('refresh_token') == [REFRESH]
                and form.get('grant_type') == ['refresh_token'], 'unexpected_refresh_payload')
        kwargs['follow_redirects'] = False
        response = original(client, request, **kwargs)
        require(response.status_code == 200, 'refresh_http_' + str(response.status_code))
        require(pair(response.json()), 'refresh_response_not_masked_STOP')
        send.checked_responses += 1
        return response
    send.checked_responses = 0
    return send


def refresh_request():
    """Capture the actual pure-refresh request before HTTP send; no refresh occurs."""
    import httpx
    import socket
    from hermes_cli import auth
    from hermes_cli.auth_constants import CODEX_OAUTH_CLIENT_ID

    class Captured(Exception):
        pass

    report = {}

    def capture(client, request, **kwargs):
        target = urlsplit(str(request.url))
        require(request.method == 'POST' and str(request.url) ==
                'https://auth.openai.com/oauth/token', 'unexpected_refresh_route')
        content_type = request.headers.get('content-type', '').split(';', 1)[0]
        if content_type == 'application/x-www-form-urlencoded':
            fields = {key: values[0] for key, values in parse_qs(request.content.decode()).items()
                      if len(values) == 1}
            encoding = 'form'
        elif content_type == 'application/json':
            fields = json.loads(request.content)
            encoding = 'json'
        else:
            raise CheckFailure('unexpected_refresh_encoding')
        report.update({'method': 'POST', 'endpoint': 'auth.openai.com/oauth/token',
                       'encoding': encoding,
                       'refresh_grant': fields.get('grant_type') == 'refresh_token',
                       'managed_refresh_placeholder': fields.get('refresh_token') == REFRESH,
                       'expected_client_id': fields.get('client_id') == CODEX_OAUTH_CLIENT_ID,
                       'client_trusts_environment': client.trust_env,
                       'http_send_prevented': True})
        raise Captured()

    root = Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    store = root / 'auth.json'
    before = store.read_bytes()
    with patch.object(httpx.Client, 'send', capture), patch.object(
            socket.socket, 'connect', side_effect=CheckFailure('unexpected_network_attempt')):
        try:
            auth.refresh_codex_oauth_pure(ACCESS, REFRESH, timeout_seconds=15)
        except Captured:
            pass
    require(bool(report), 'refresh_request_not_captured')
    require(store.read_bytes() == before, 'request_inspection_changed_auth_store')
    report['auth_store_unchanged'] = True
    return report


def refresh():
    import httpx
    from hermes_cli import auth
    resolved(auth)
    send = guarded_send(httpx.Client.send)
    with patch.object(httpx.Client, 'send', send):
        result = auth.resolve_codex_runtime_credentials(force_refresh=True)
    require(send.checked_responses == 1, 'expected_one_live_refresh_response')
    require(result.get('api_key') == ACCESS, 'refreshed_resolver_not_masked')
    state('bound')
    return {'refresh_response_masked': True, 'refresh_store_still_masked': True,
            'note': 'Forced refresh only; natural expiry still requires a separate timed test.'}


def refresh_json_probe(encoding='json'):
    """One refresh through the proxy; never persist its response."""
    import httpx
    from hermes_cli.auth_constants import CODEX_OAUTH_CLIENT_ID, CODEX_OAUTH_USER_AGENT
    root = Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    store = root / 'auth.json'
    before = store.read_bytes()
    fields = {
            'grant_type': 'refresh_token', 'refresh_token': REFRESH,
            'client_id': CODEX_OAUTH_CLIENT_ID}
    with httpx.Client(trust_env=True, timeout=20, follow_redirects=False,
                      headers={'Accept': 'application/json', 'User-Agent': CODEX_OAUTH_USER_AGENT}) as client:
        if encoding == 'form':
            response = client.post('https://auth.openai.com/oauth/token', data=fields)
        else:
            response = client.post('https://auth.openai.com/oauth/token', json=fields)
    report = {'encoding': encoding, 'http_status': response.status_code,
              'client_matches_host_login': CODEX_OAUTH_CLIENT_ID == 'app_EMoamEEZ73f0CkXaXp7hrann',
              'auth_store_unchanged': store.read_bytes() == before,
              'response_persisted': False}
    require(report['auth_store_unchanged'], 'probe_auth_store_changed')
    if response.status_code == 200:
        require(pair(response.json()), 'refresh_response_not_masked_STOP')
        report['refresh_response_masked'] = True
    else:
        # Fixed categories only. Never echo the server's error/description/body.
        text = response.text.lower()
        report['proxy_oauth_denial'] = 'proxy:' in text and 'oauth' in text and 'denied' in text
        reasons = ('unrecognized grant', 'invalid refresh token', 'unknown refresh token',
                   'missing refresh token', 'refresh token not recognized',
                   'no oauth credential', 'refresh failed')
        report['recognized_proxy_reason'] = next((v for v in reasons if v in text), 'unclassified')
        code = None
        try:
            payload = response.json()
            error = payload.get('error')
            code = error.get('code', error.get('type')) if isinstance(error, dict) else error
        except (ValueError, AttributeError):
            pass
        known = ('invalid_grant', 'invalid_client', 'invalid_token', 'invalid_request',
                 'refresh_token_reused', 'unsupported_grant_type', 'unauthorized_client')
        report['recognized_oauth_error'] = code if isinstance(code, str) and code in known else 'unclassified'
        descriptions = ('client authentication failed', 'invalid client id', 'invalid client_id',
                        'unknown or invalid client', 'unknown client', 'missing client_id',
                        'client_id is required', 'client secret is required',
                        'client_secret is required', 'invalid client credentials')
        report['recognized_client_error_detail'] = next((v for v in descriptions if v in text),
                                                        'unclassified')
    return report


def negative_policy():
    import httpx
    # No Authorization header or credential is sent to the unrelated host.
    with httpx.Client(trust_env=True, timeout=15, follow_redirects=False) as client:
        response = client.get('https://example.com/')
    body = response.text.lower()
    require(response.status_code == 403 and any(label in body for label in
            ('blocked by', 'blocked http', 'approval required', 'network policy')),
            'unrelated_host_not_confirmed_blocked')
    # A connection failure is not proof that direct traffic is policy-blocked.
    # Record it separately; the host policy log must corroborate enforcement.
    try:
        with httpx.Client(trust_env=False, timeout=5, follow_redirects=False) as client:
            direct = client.get('https://example.com/')
        direct_result = 'http_' + str(direct.status_code)
    except httpx.HTTPError:
        direct_result = 'connection_failed_requires_host_policy_confirmation'
    return {'proxy_policy_denied_unrelated_host': True, 'direct_path': direct_result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('state', 'unbound', 'catalog', 'refresh',
                                        'refresh-request', 'refresh-json-probe',
                                        'refresh-form-probe', 'negative-policy'))
    args = parser.parse_args()
    # Discard imported-library diagnostics; they may include response details.
    logging.disable(logging.CRITICAL)
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            if args.mode == 'unbound':
                result = state('unbound')
            elif args.mode == 'negative-policy':
                result = negative_policy()
            else:
                result = state('bound')
                if args.mode == 'catalog':
                    result.update(catalog())
                elif args.mode == 'refresh':
                    result.update(refresh())
                elif args.mode == 'refresh-request':
                    result.update(refresh_request())
                elif args.mode == 'refresh-json-probe':
                    result.update(refresh_json_probe())
                elif args.mode == 'refresh-form-probe':
                    result.update(refresh_json_probe('form'))
        print(json.dumps(result, indent=2))
        return 0
    except CheckFailure as exc:
        print(json.dumps({'passed': False, 'failure': str(exc)}))
    except Exception as exc:
        allowed = (ModuleNotFoundError, ImportError, TypeError, ValueError, KeyError,
                   AttributeError, FileNotFoundError, PermissionError)
        kind = next((cls.__name__ for cls in allowed if isinstance(exc, cls)), 'OtherError')
        print(json.dumps({'passed': False, 'failure': 'unexpected_error_details_suppressed',
                          'stage': STAGE, 'exception_type': kind,
                          'virtualenv_active': sys.prefix != sys.base_prefix}))
    return 1


if __name__ == '__main__':
    raise SystemExit(main())

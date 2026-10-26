#!/usr/bin/env python3
"""One form-refresh probe in a fresh native OpenCode control, using curl/stdlib.

No Hermes imports, native login, host-secret access, or response persistence.
"""
import json
from pathlib import Path
import subprocess
from urllib.parse import urlencode

ACCESS = 'oai-oat01-proxy-managed'
REFRESH = 'oai-ort01-proxy-managed'
CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann'


def run():
    store = Path.home() / '.local/share/opencode/auth.json'
    if store.is_symlink() or not store.is_file():
        return {'passed': False, 'failure': 'native_opencode_seed_missing_or_symlink'}
    before = store.read_bytes()
    record = json.loads(before).get('openai', {})
    if (record.get('type'), record.get('access'), record.get('refresh')) != ('oauth', ACCESS, REFRESH):
        return {'passed': False, 'failure': 'native_opencode_seed_not_exact_managed_placeholders'}
    # -q disables .curlrc; no redirects, retries, verbose logs, or response files.
    # Curl inherits the sandbox's normal proxy and CA environment.
    result = subprocess.run(['curl', '-q', '--silent', '--show-error',
        '--proto', '=https', '--connect-timeout', '5', '--max-time', '20',
        '--max-redirs', '0', '--request', 'POST',
        '--header', 'Content-Type: application/x-www-form-urlencoded',
        '--header', 'Accept: application/json', '--data-binary', '@-',
        '--write-out', '\n%{http_code}', 'https://auth.openai.com/oauth/token'],
        input=urlencode({'grant_type': 'refresh_token', 'refresh_token': REFRESH,
                         'client_id': CLIENT_ID}), capture_output=True, text=True, timeout=30)
    if result.returncode:
        return {'passed': False, 'failure': 'control_transport_failed_details_suppressed'}
    body, status_text = result.stdout.rsplit('\n', 1)
    status = int(status_text)
    report = {'native_opencode_seed_masked': True, 'encoding': 'form',
              'http_status': status, 'auth_store_unchanged': store.read_bytes() == before,
              'response_persisted': False}
    try:
        payload = json.loads(body)
    except ValueError:
        payload = {}
    if status == 200:
        report['refresh_response_masked'] = (
            payload.get('access_token') == ACCESS and payload.get('refresh_token') == REFRESH
            and not payload.get('id_token'))
        if not report['refresh_response_masked']:
            report['failure'] = 'refresh_response_not_masked_STOP'
    else:
        error = payload.get('error') if isinstance(payload, dict) else None
        code = error.get('code', error.get('type')) if isinstance(error, dict) else error
        known = ('invalid_client', 'invalid_grant', 'invalid_token', 'invalid_request',
                 'refresh_token_reused', 'unsupported_grant_type', 'unauthorized_client')
        report['recognized_oauth_error'] = code if isinstance(code, str) and code in known else 'unclassified'
        report['proxy_oauth_denial'] = ('proxy:' in body.lower() and 'oauth' in body.lower()
                                       and 'denied' in body.lower())
    return report


if __name__ == '__main__':
    try:
        report = run()
    except Exception:
        report = {'passed': False, 'failure': 'control_error_details_suppressed'}
    print(json.dumps(report, indent=2))

#!/usr/bin/env python3
"""Permit the bound Docker OAuth placeholder through Hermes 0.22.5's catalog gate."""
import argparse
import ast
from pathlib import Path


HELPER = '''"""Docker managed-OAuth discovery exception; credentials remain on the host."""
import json
from pathlib import Path
from urllib.parse import urlsplit


def bound_catalog_route(base_url):
    # Match only the official route; never send this placeholder to a gateway.
    try:
        route = urlsplit((base_url or "https://chatgpt.com/backend-api/codex").strip().rstrip("/"))
        if (route.scheme != "https" or route.netloc != "chatgpt.com"
                or route.path != "/backend-api/codex" or route.query or route.fragment):
            return False
        seed = Path.home() / ".docker/hermes-openai-oauth.json"
        if seed.is_symlink():
            return False
        value = json.loads(seed.read_text())
        return (isinstance(value, dict)
                and value.get("access_token") == "oai-oat01-proxy-managed"
                and value.get("refresh_token") == "oai-ort01-proxy-managed")
    except (OSError, ValueError):
        return False
'''

OLD = '''    if not access_token:
        return False
'''
NEW = OLD + '''    # Docker's host proxy replaces this bound placeholder with real OAuth.
    # Keep upstream's JWT guard for every other credential.
    if access_token == "oai-oat01-proxy-managed":
        from hermes_cli.docker_codex_catalog import bound_catalog_route
        return bound_catalog_route(base_url)
'''


def install(source):
    target = source / 'agent/model_metadata.py'
    helper = source / 'hermes_cli/docker_codex_catalog.py'
    text = target.read_text()
    tree = ast.parse(text)
    function = next((node for node in tree.body if isinstance(node, ast.FunctionDef)
                     and node.name == '_codex_catalog_probe_allowed'), None)
    if function is None:
        raise ValueError('unsupported Hermes catalog implementation')
    lines = text.splitlines(keepends=True)
    body = ''.join(lines[function.lineno - 1:function.end_lineno])
    if NEW in body:
        if not helper.exists() or helper.read_text() != HELPER:
            raise ValueError('managed catalog helper differs; review required')
        return False
    if (body.count(OLD) != 1
            or 'return bool(_decode_jwt_claims(access_token))' not in body
            or 'base_url_host_matches(base, "chatgpt.com")' not in body
            or 'CODEX_NEWEST_CLIENT_VERSION' not in text):
        raise ValueError('unsupported Hermes catalog implementation')
    if helper.exists():
        raise ValueError('managed catalog helper already exists; review required')
    lines[function.lineno - 1:function.end_lineno] = [body.replace(OLD, NEW, 1)]
    updated = ''.join(lines)
    compile(updated, str(target), 'exec')
    compile(HELPER, str(helper), 'exec')
    helper.write_text(HELPER)
    target.write_text(updated)
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, nargs='?', default=Path.home() / '.hermes/hermes-agent')
    args = parser.parse_args()
    try:
        changed = install(args.source)
    except (OSError, ValueError, SyntaxError) as exc:
        parser.exit(1, f'Managed catalog compatibility failed: {exc}\n')
    print('Managed catalog compatibility applied' if changed else 'Managed catalog compatibility already applied')

#!/usr/bin/env python3
"""Adapt known Hermes catalog implementations for Docker-managed OAuth.

Apply at image build time, or explicitly to an existing test sandbox. This
changes discovery only; it does not add model names or alter credentials.
"""
import argparse
import importlib.util
from pathlib import Path

OLD = """        resp = httpx.get(CODEX_MODELS_CATALOG_URL, headers=headers, timeout=10)
        if resp.status_code != 200:
            return []
        data = resp.json()
        entries = data.get("models", []) if isinstance(data, dict) else []
"""
NEW = """        # The old 0.0.0 query now returns a frozen legacy catalog. Ask for
        # the current account catalog first, preserving the legacy fallback.
        newest_url = CODEX_MODELS_CATALOG_URL.replace(
            "client_version=0.0.0", "client_version=99.0.0")
        entries = []
        for catalog_url in dict.fromkeys((newest_url, CODEX_MODELS_CATALOG_URL)):
            resp = httpx.get(catalog_url, headers=headers, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                entries = data.get("models", []) if isinstance(data, dict) else []
                if isinstance(entries, list) and entries:
                    break
            elif resp.status_code not in (400, 404, 422):
                # Do not retry revoked credentials, throttling, or server errors.
                return []
        if not isinstance(entries, list):
            return []
"""


def backport(source):
    target = source / "hermes_cli/codex_models.py"
    text = target.read_text()
    if NEW in text:
        return False
    # Hermes 0.22.5 already negotiates catalog versions. Keep that code and
    # adapt only its JWT gate for Docker's bound OAuth placeholder.
    if ("fetch_codex_catalog_entries(" in text
            and "_codex_catalog_probe_allowed(access_token, catalog_base)" in text):
        metadata = (source / "agent/model_metadata.py").read_text()
        if 'CODEX_NEWEST_CLIENT_VERSION = "99.0.0"' not in metadata:
            raise ValueError("unexpected native catalog version negotiation")
        helper = Path(__file__).with_name("hermes-managed-catalog-compat.py")
        spec = importlib.util.spec_from_file_location("managed_catalog_compat", helper)
        adapter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(adapter)
        return adapter.install(source)
    if text.count(OLD) != 1:
        raise ValueError("unexpected Hermes catalog implementation; review the backport for this version")
    updated = text.replace(OLD, NEW, 1)
    compile(updated, str(target), "exec")
    # Image build runs before Hermes starts. No runtime monkeypatch or token read.
    target.write_text(updated)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?",
                        default=Path.home() / ".hermes/hermes-agent")
    args = parser.parse_args()
    try:
        changed = backport(args.source)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Codex catalog backport failed: {exc}\n")
    print("Codex catalog compatibility applied" if changed else "Codex catalog compatibility already applied")


if __name__ == "__main__":
    main()

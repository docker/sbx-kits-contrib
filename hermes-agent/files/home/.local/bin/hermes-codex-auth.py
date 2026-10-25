#!/usr/bin/env python3
"""Bridge Docker-rendered OAuth sentinels into Hermes, before agent startup.

This handles placeholders only. Enrollment and refresh belong to the host.
"""
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile
import time

ACCESS = "oai-oat01-proxy-managed"
REFRESH = "oai-ort01-proxy-managed"
PROVIDER = "openai-codex"


class BridgeError(ValueError):
    """A fixed, safe-to-display diagnostic; never includes credential data."""


def managed(record):
    if not isinstance(record, dict):
        return False
    tokens = record.get("tokens", record)
    return (isinstance(tokens, dict)
            and tokens.get("access_token") == ACCESS
            and tokens.get("refresh_token") == REFRESH)


def reconcile(store, bound):
    """Preserve independent identities; only own the exact managed token pair."""
    if not isinstance(store, dict) or store.get("version", 1) != 1:
        raise BridgeError("unsupported Hermes auth store")
    providers = store.setdefault("providers", {})
    pools = store.get("credential_pool", {})
    if not isinstance(providers, dict) or not isinstance(pools, dict):
        raise BridgeError("invalid Hermes auth store sections")
    current = providers.get(PROVIDER)
    entries = pools.get(PROVIDER, [])
    if not isinstance(entries, list):
        raise BridgeError("invalid Hermes Codex credential pool")
    if bound:
        if (current is not None and not managed(current)) or any(not managed(e) for e in entries):
            raise BridgeError("native Codex credentials exist; use a fresh sandbox for host-managed OAuth")
        providers[PROVIDER] = {
            "auth_mode": "chatgpt",
            "tokens": {"access_token": ACCESS, "refresh_token": REFRESH},
        }
        # Match Hermes login's default selection without changing a prior choice.
        store.setdefault("active_provider", PROVIDER)
    elif managed(current):
        del providers[PROVIDER]
        if store.get("active_provider") == PROVIDER:
            store.pop("active_provider", None)
    if not bound and PROVIDER in pools:
        # Hermes can copy singleton tokens into its pool during normal use.
        pools[PROVIDER] = [e for e in entries if not managed(e)]
        if not pools[PROVIDER]:
            del pools[PROVIDER]
    return store


def read_object(path, default=None):
    if path.is_symlink():
        raise BridgeError("credential paths must not be symlinks")
    if not path.exists():
        return default
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise BridgeError("credential file must be a JSON object")
    return value


def bridge(state_dir, seed):
    seed_data = read_object(seed)
    bound = seed_data is not None
    if bound and not managed(seed_data):
        raise BridgeError("Docker OAuth file does not contain the expected sentinels")
    auth = state_dir / "auth.json"
    # A fresh unauthenticated sandbox should not acquire an empty auth store.
    if not bound and not auth.exists():
        return False
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = auth.with_suffix(".lock")  # Hermes' cross-process flock path.
    if lock_path.is_symlink():
        raise BridgeError("credential paths must not be symlinks")
    with lock_path.open("a") as lock:
        deadline = time.monotonic() + 15
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise BridgeError("timed out waiting for Hermes auth lock")
                time.sleep(0.05)
        store = read_object(auth, {"version": 1, "providers": {}})
        before = json.dumps(store, sort_keys=True)
        reconcile(store, bound)
        if json.dumps(store, sort_keys=True) != before:
            fd, tmp = tempfile.mkstemp(prefix=".auth-", dir=state_dir)
            try:
                with os.fdopen(fd, "w") as stream:
                    json.dump(store, stream, indent=2)
                    stream.write("\n")
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(tmp, auth)  # mkstemp is 0600; never a partial store.
            finally:
                if os.path.exists(tmp):
                    os.unlink(tmp)
    return bound


def main():
    home = Path.home()
    state = Path(os.environ.get("HERMES_HOME", home / ".hermes"))
    try:
        bound = bridge(state, home / ".docker/hermes-openai-oauth.json")
    except BridgeError as exc:
        print(f"Hermes Docker OAuth bridge failed: {exc}.", file=sys.stderr)
        return 1
    except (ValueError, OSError):
        # JSON/OS errors are kept generic: never echo file contents or tokens.
        print("Hermes Docker OAuth bridge failed: unreadable or malformed credential file.", file=sys.stderr)
        return 1
    print("oauth" if bound else "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())

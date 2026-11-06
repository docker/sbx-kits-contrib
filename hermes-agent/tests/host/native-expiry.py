#!/usr/bin/env python3
"""Read only the rendered OpenCode expiry metadata; no requests or token output."""
from datetime import datetime, timezone
import json
from pathlib import Path
import time


def expiry_seconds(value):
    if isinstance(value, bool):
        raise ValueError('invalid expiry')
    if isinstance(value, (int, float)) or (isinstance(value, str) and value.isdigit()):
        number = float(value)
        return number / 1000 if number > 100_000_000_000 else number
    if isinstance(value, str):
        date = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if date.tzinfo is None:
            raise ValueError('ambiguous expiry')
        return date.timestamp()
    raise ValueError('missing expiry')


def main():
    path = Path.home() / '.local/share/opencode/auth.json'
    try:
        if path.is_symlink():
            raise ValueError('symlink')
        entry = json.loads(path.read_bytes()).get('openai', {})
        # Do not inspect or print access/refresh values; this mode reads metadata.
        expires = expiry_seconds(entry.get('expires'))
        now = time.time()
        return {'source': 'opencode_rendered_client_expiry_metadata',
                'current_time_utc': datetime.fromtimestamp(now, timezone.utc).isoformat(),
                'rendered_expiry_utc': datetime.fromtimestamp(expires, timezone.utc).isoformat(),
                'remaining_seconds': int(expires - now),
                'already_expired': expires <= now,
                'http_requests_sent': 0, 'auth_store_modified': False}
    except Exception:
        return {'passed': False, 'failure': 'expiry_metadata_unavailable_or_unrecognized',
                'http_requests_sent': 0, 'auth_store_modified': False}


if __name__ == '__main__':
    print(json.dumps(main(), indent=2))

#!/bin/bash
# smoke-test.sh — run this inside the sandbox after `sbx run` to verify the kit
# Usage: bash scripts/smoke-test.sh

set -euo pipefail

PASS="\033[32m✓\033[0m"
FAIL="\033[31m✗\033[0m"
WARN="\033[33m⚠\033[0m"
ok=0
fail=0

check() {
  local desc="$1"; shift
  if "$@" &>/dev/null; then
    printf "$PASS %s\n" "$desc"
    ((ok++)) || true
  else
    printf "$FAIL %s\n" "$desc"
    ((fail++)) || true
  fi
}

echo "=== aws-strands-agent smoke test ==="
echo

# Venv
check "venv exists at /opt/strands"          test -d /opt/strands
check "strands-python on PATH"               which strands-python
check "strands-python runs"                  strands-python -c "import sys; assert sys.version_info >= (3, 10)"

# Packages
check "strands-agents importable"            strands-python -c "import strands"
check "strands-agents-tools importable"      strands-python -c "import strands_tools"
check "boto3 importable"                     strands-python -c "import boto3"

# Versions
STRANDS_VER=$(strands-python -c "import importlib.metadata; print(importlib.metadata.version('strands-agents'))" 2>/dev/null || echo "unknown")
echo "  strands-agents version: $STRANDS_VER"

# Env
check "STRANDS_VENV is set"                  test -n "${STRANDS_VENV:-}"

# Bedrock SigV4 colon-encoding guard (Python 3.14 regression).
# Offline: drives boto3's real serializer + SigV4 signer but short-circuits
# 'before-send', so nothing is sent. Asserts the SIGNED canonical path is
# double-encoded (%253A), which is what AWS expects. Passes natively on
# Python <=3.13 and via the shipped patch on 3.14+. The region/model are an
# arbitrary colon-bearing fixture and imply no required region.
if strands-python - <<'PYCHK' &>/dev/null
import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSResponse
cap = {}
_orig = SigV4Auth.canonical_request
def _cap(self, request):
    cr = _orig(self, request)
    cap['cr'] = cr
    return cr
SigV4Auth.canonical_request = _cap
def _stop(request, **kw):
    resp = AWSResponse(request.url, 200, {'Content-Type': 'application/json'}, None)
    resp._content = b'{"output":{"message":{"content":[{"text":"ok"}]}}}'
    return resp
c = boto3.client('bedrock-runtime', region_name='us-east-1',
                 aws_access_key_id='AKIA', aws_secret_access_key='x')
c.meta.events.register('before-send.bedrock-runtime', _stop)
try:
    c.converse(modelId='us.anthropic.claude-sonnet-4-20250514-v1:0',
               messages=[{'role': 'user', 'content': [{'text': 'hi'}]}])
except Exception:
    pass
assert cap['cr'].split('\n')[1].endswith('v1%253A0/converse')
PYCHK
then
  printf "$PASS Bedrock SigV4 colon-encoding correct (%%253A)\n"
  ((ok++)) || true
else
  printf "$FAIL Bedrock SigV4 colon-encoding broken — model IDs with ':' will fail signing\n"
  ((fail++)) || true
fi

if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
  printf "$PASS AWS_DEFAULT_REGION is set ($AWS_DEFAULT_REGION)\n"
  ((ok++)) || true
else
  printf "$WARN  AWS_DEFAULT_REGION not set — boto3 will fall back to ~/.aws/config or us-east-1\n"
fi

# AWS credentials — warning only, not a failure.
# SBX proxy injection doesn't expose env vars; export them manually or use an IAM role.
if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  printf "$PASS AWS credentials present\n"
  ((ok++)) || true
else
  printf "$WARN  AWS credentials not in environment — export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY before running agents\n"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "All $ok checks passed."
else
  echo "$ok passed, $fail failed."
  exit 1
fi

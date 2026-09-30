#!/bin/bash
# smoke-test.sh - run this inside the sandbox after `sbx run` to verify the kit.
# Usage: bash scripts/smoke-test.sh

set -euo pipefail

PASS="\033[32m✓\033[0m"
FAIL="\033[31m✗\033[0m"
WARN="\033[33m⚠\033[0m"
ok=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" &>/dev/null; then
    printf "$PASS %s\n" "$desc"
    ((ok++)) || true
  else
    printf "$FAIL %s\n" "$desc"
    ((fail++)) || true
  fi
}

echo "=== google-adk smoke test ==="
echo

check "venv exists at /opt/google-adk" test -d /opt/google-adk
check "adk CLI on PATH" which adk
check "adk-python on PATH" which adk-python
check "adk --help runs" adk --help
check "adk-python runs" adk-python -c "import sys; assert sys.version_info >= (3, 10)"
check "google.adk importable" adk-python -c "import google.adk"
check "Agent importable" adk-python -c "from google.adk import Agent"

ADK_VER=$(adk-python -c "import importlib.metadata; print(importlib.metadata.version('google-adk'))" 2>/dev/null || echo "unknown")
echo "  google-adk version: $ADK_VER"

check "GOOGLE_ADK_VENV is set" test -n "${GOOGLE_ADK_VENV:-}"

if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
  printf "$PASS GOOGLE_API_KEY placeholder is set\n"
  ((ok++)) || true
else
  printf "$WARN  GOOGLE_API_KEY not set - configure sbx secret set google-gemini before Gemini API calls\n"
fi

if [[ -n "${GOOGLE_GENAI_USE_VERTEXAI:-}" ]]; then
  printf "$PASS GOOGLE_GENAI_USE_VERTEXAI is set ($GOOGLE_GENAI_USE_VERTEXAI)\n"
  ((ok++)) || true
else
  printf "$WARN  GOOGLE_GENAI_USE_VERTEXAI not set - this is fine for Gemini Developer API usage\n"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "All $ok checks passed."
else
  echo "$ok passed, $fail failed."
  exit 1
fi

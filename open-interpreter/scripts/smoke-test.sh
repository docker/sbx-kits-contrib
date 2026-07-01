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

echo "=== open-interpreter smoke test ==="
echo

check "venv exists at /opt/open-interpreter" test -d /opt/open-interpreter
check "interpreter CLI on PATH" which interpreter
check "i alias on PATH" which i
check "open-interpreter-python on PATH" which open-interpreter-python
check "interpreter --help runs" interpreter --help
check "open-interpreter-python runs" open-interpreter-python -c "import sys; assert sys.version_info >= (3, 9)"
check "interpreter package importable" open-interpreter-python -c "import interpreter"

OI_VER=$(open-interpreter-python -c "import importlib.metadata; print(importlib.metadata.version('open-interpreter'))" 2>/dev/null || echo "unknown")
echo "  open-interpreter version: $OI_VER"

check "OPEN_INTERPRETER_VENV is set" test -n "${OPEN_INTERPRETER_VENV:-}"

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  printf "$PASS OPENAI_API_KEY placeholder is set (default gpt-4o path)\n"
  ((ok++)) || true
else
  printf "$WARN  OPENAI_API_KEY not set - run 'sbx secret set -g openai' before using the default model\n"
fi

if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  printf "$PASS OPENROUTER_API_KEY placeholder is set\n"
  ((ok++)) || true
else
  printf "$WARN  OPENROUTER_API_KEY not set - optional; 'sbx secret set -g openrouter' enables openrouter/* models\n"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "All $ok checks passed."
else
  echo "$ok passed, $fail failed."
  exit 1
fi

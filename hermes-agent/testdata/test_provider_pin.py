"""Provider pin in hermes-credential-auth.sh, run against a stub `hermes`.

Needs no container and no root: each case gets a throwaway HOME. The stub keeps
`config get|set|unset` in a flat file, so the assertions read the provider,
model and base URL the script left behind. Run from the repo root:

    python3 -m unittest hermes-agent/testdata/test_provider_pin.py

It runs against the hermes-agent kit's copy of the script and the mixin's.
HERMES_AUTH_SCRIPT points the suite at one other copy instead, for example
`git show origin/v3:...` output, to see which cases an older version got wrong.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parent.parent.parent
HOOK_PATH = "files/home/.local/bin/hermes-credential-auth.sh"
# The kit and its mixin each ship a copy of the script.
HOOKS = [Path(os.environ["HERMES_AUTH_SCRIPT"])] if "HERMES_AUTH_SCRIPT" in os.environ else [
    REPO / "hermes-agent" / HOOK_PATH,
    REPO / "hermes-agent-mixin" / HOOK_PATH,
]
# The script only greps this placeholder out of the login file, so the file
# body is just a marker line.
LOGIN_MARKER = "sk-ant-oat01-proxy-managed"
# (model.provider, model.default, model.base_url); None = key not set. The
# template's base_url is OpenRouter's.
OPENROUTER_URL = "https://openrouter.ai/api/v1"
PRISTINE = ("auto", "anthropic/claude-opus-4.6", OPENROUTER_URL)
ANTHROPIC = ("anthropic", "claude-opus-4-6", "https://api.anthropic.com")
OPENAI = ("openai-api", "gpt-6-sol", "https://api.openai.com/v1")
COPILOT = ("copilot", "gpt-5-mini", None)
UNSET = (None, None, None)

STUB = """#!/bin/sh
# Minimal `hermes config get|set|unset <key> [value]` over $HOME/stub-config
# (key=value lines). Like Hermes, `get` on a missing key exits 1. Every write is
# logged to $HOME/stub-writes.
f="$HOME/stub-config"
[ "$1" = config ] || exit 2
case "$2" in
    get) grep "^$3=" "$f" 2>/dev/null | cut -d= -f2- | grep '' || exit 1 ;;
    set) echo "$*" >> "$HOME/stub-writes"
         { grep -v "^$3=" "$f" 2>/dev/null || true; echo "$3=$4"; } > "$f.tmp" && mv "$f.tmp" "$f" ;;
    unset) echo "$*" >> "$HOME/stub-writes"
         { grep -v "^$3=" "$f" 2>/dev/null || true; } > "$f.tmp" && mv "$f.tmp" "$f" ;;
esac
"""
KEYS = ("model.provider", "model.default", "model.base_url")

# name, bound credentials, preset (provider, model, base_url), expected (same)
# bound credentials: a, o, r, c = Anthropic key, OpenAI, OpenRouter, Copilot;
# "A" = Anthropic OAuth login (credential file) instead of a key.
CASES = [
    ("Anthropic only", "a", PRISTINE, ANTHROPIC),
    ("OpenAI only", "o", PRISTINE, OPENAI),
    ("Anthropic + OpenAI", "ao", PRISTINE, ANTHROPIC),
    ("Anthropic + OpenAI + OpenRouter", "aor", PRISTINE, PRISTINE),
    ("OpenRouter only", "r", PRISTINE, PRISTINE),
    ("Copilot only", "c", PRISTINE, COPILOT),
    ("Anthropic OAuth only", "A", PRISTINE, ANTHROPIC),
    ("Anthropic OAuth + OpenAI", "Ao", PRISTINE, ANTHROPIC),
    ("Anthropic + Copilot", "ac", PRISTINE, ANTHROPIC),
    ("OpenAI + Copilot", "oc", PRISTINE, OPENAI),
    ("Nothing bound", "", PRISTINE, PRISTINE),
    ("Empty config, Anthropic + OpenAI", "ao", ("", "", ""), ANTHROPIC),
    ("Empty config, OpenAI only", "o", ("", "", ""), OPENAI),
    # An empty base_url already means "none" to Hermes, so it is left as is.
    ("Empty config, Copilot only", "c", ("", "", ""), COPILOT[:2] + ("",)),
    ("No model keys, OpenAI only", "o", UNSET, OPENAI),
    ("No model keys, Copilot only", "c", UNSET, COPILOT),
    # A pin from an earlier credential set.
    ("Anthropic pin, OpenAI bound later", "o", ANTHROPIC, OPENAI),
    ("OpenRouter bound later resets the pin", "aor", ANTHROPIC, PRISTINE),
    # What #458 left behind: the pin with the template's base_url.
    ("OpenAI pin from #458", "o", OPENAI[:2] + (OPENROUTER_URL,), OPENAI),
    ("Anthropic pin from #458", "a", ANTHROPIC[:2] + (OPENROUTER_URL,), ANTHROPIC),
    # Leaving the OpenAI pin must not leave its base_url behind.
    ("OpenAI pin, Anthropic bound later", "a", OPENAI, ANTHROPIC),
    ("OpenAI pin, OpenRouter bound later", "or", OPENAI, PRISTINE),
    ("OpenAI pin, Copilot bound later", "c", OPENAI, COPILOT),
    ("OpenAI pin, nothing bound later", "", OPENAI, PRISTINE),
    ("Copilot pin, OpenAI bound later", "o", COPILOT, OPENAI),
    ("Copilot pin, Anthropic bound later", "a", COPILOT, ANTHROPIC),
    # Choices made with `hermes model` are never overwritten.
    ("User picked another provider", "ao", ("openrouter", "some/model", OPENROUTER_URL),
     ("openrouter", "some/model", OPENROUTER_URL)),
    ("User picked another model", "ao", ("anthropic", "claude-sonnet-4-5", OPENROUTER_URL),
     ("anthropic", "claude-sonnet-4-5", OPENROUTER_URL)),
    ("User picked another provider, same model", "o", ("nous", "anthropic/claude-opus-4.6", OPENROUTER_URL),
     ("nous", "anthropic/claude-opus-4.6", OPENROUTER_URL)),
    ("User picked another base_url", "o", ("auto", "anthropic/claude-opus-4.6", "http://localhost:11434/v1"),
     ("auto", "anthropic/claude-opus-4.6", "http://localhost:11434/v1")),
    ("User picked another base_url for OpenAI", "a", ("openai-api", "gpt-6-sol", "https://proxy.example/v1"),
     ("openai-api", "gpt-6-sol", "https://proxy.example/v1")),
]


def run_case(hook, bound, preset):
    """Run the script once; return ((provider, model, base_url), writes, returncode, stderr)."""
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        stub = home / ".local/bin/hermes"
        stub.parent.mkdir(parents=True)
        stub.write_text(STUB)
        stub.chmod(0o755)
        (home / "stub-config").write_text(
            "".join(f"{k}={v}\n" for k, v in zip(KEYS, preset) if v is not None))
        env = {"PATH": os.environ["PATH"], "HOME": str(home)}
        # The kit injects the sentinels unconditionally; the script must cope.
        for var in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY"):
            env[var] = "proxy-managed"
        for code, service in (("a", "ANTHROPIC"), ("o", "OPENAI"), ("r", "OPENROUTER"), ("c", "COPILOT")):
            if code in bound:
                env[f"SBX_CRED_{service}_MODE"] = "apikey"
        if "A" in bound:
            (home / ".claude").mkdir()
            (home / ".claude/.credentials.json").write_text(f"login={LOGIN_MARKER}\n")
        done = subprocess.run(["sh", str(hook)], env=env, capture_output=True, text=True)
        values = dict(line.split("=", 1) for line in
                      (home / "stub-config").read_text().splitlines() if "=" in line)
        writes = home / "stub-writes"
        writes = writes.read_text().splitlines() if writes.exists() else []
        return tuple(values.get(k) for k in KEYS), writes, done.returncode, done.stderr


class ProviderPinTest(unittest.TestCase):
    def test_pin_per_credential_set(self):
        for hook in HOOKS:
            for name, bound, preset, expected in CASES:
                with self.subTest(f"{hook.parent.parent.parent.parent.parent.name}: {name}"):
                    pin, _, rc, err = run_case(hook, bound, preset)
                    self.assertEqual(rc, 0, err)
                    self.assertEqual(pin, expected)

    def test_second_run_changes_nothing(self):
        for hook in HOOKS:
            for name, bound, preset, expected in CASES:
                with self.subTest(f"{hook.parent.parent.parent.parent.parent.name}: {name}"):
                    # Feed the first run's result back in as the preset. A
                    # real `config set` rewrites config.yaml, so a rerun must
                    # not write at all.
                    first = run_case(hook, bound, preset)[0]
                    second, writes = run_case(hook, bound, first)[:2]
                    self.assertEqual(second, first)
                    self.assertEqual(writes, [])


if __name__ == "__main__":
    unittest.main()

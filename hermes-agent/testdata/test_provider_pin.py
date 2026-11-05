"""Provider pin in hermes-credential-auth.sh, run against a stub `hermes`.

Needs no container and no root: each case gets a throwaway HOME. The stub keeps
`config get|set` in a flat file, so the assertions read the provider/model the
script left behind. Run from the repo root:

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
PRISTINE = ("auto", "anthropic/claude-opus-4.6")
ANTHROPIC = ("anthropic", "claude-opus-4-6")
OPENAI = ("openai-api", "gpt-6-sol")
COPILOT = ("copilot", "gpt-5-mini")

STUB = """#!/bin/sh
# Minimal `hermes config get|set <key> [value]` over $HOME/stub-config (key=value lines).
f="$HOME/stub-config"
[ "$1" = config ] || exit 2
case "$2" in
    get) grep "^$3=" "$f" 2>/dev/null | cut -d= -f2- ;;
    set) { grep -v "^$3=" "$f" 2>/dev/null || true; echo "$3=$4"; } > "$f.tmp" && mv "$f.tmp" "$f" ;;
esac
"""

# name, bound credentials, preset (provider, model), expected (provider, model)
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
    ("Empty config, Anthropic + OpenAI", "ao", ("", ""), ANTHROPIC),
    # A pin from an earlier credential set.
    ("Anthropic pin, OpenAI bound later", "o", ANTHROPIC, OPENAI),
    ("OpenRouter bound later resets the pin", "aor", ANTHROPIC, PRISTINE),
    # Choices made with `hermes model` are never overwritten.
    ("User picked another provider", "ao", ("openrouter", "some/model"), ("openrouter", "some/model")),
    ("User picked another model", "ao", ("anthropic", "claude-sonnet-4-5"), ("anthropic", "claude-sonnet-4-5")),
    ("User picked another provider, same model", "o", ("nous", "anthropic/claude-opus-4.6"),
     ("nous", "anthropic/claude-opus-4.6")),
]


def run_case(hook, bound, preset):
    """Run the script once; return (provider, model, returncode, stderr)."""
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        stub = home / ".local/bin/hermes"
        stub.parent.mkdir(parents=True)
        stub.write_text(STUB)
        stub.chmod(0o755)
        (home / "stub-config").write_text(
            f"model.provider={preset[0]}\nmodel.default={preset[1]}\n")
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
        return values.get("model.provider"), values.get("model.default"), done.returncode, done.stderr


class ProviderPinTest(unittest.TestCase):
    def test_provider_and_model_per_credential_set(self):
        for hook in HOOKS:
            for name, bound, preset, expected in CASES:
                with self.subTest(f"{hook.parent.parent.parent.parent.parent.name}: {name}"):
                    provider, model, rc, err = run_case(hook, bound, preset)
                    self.assertEqual(rc, 0, err)
                    self.assertEqual((provider, model), expected)

    def test_second_run_changes_nothing(self):
        for hook in HOOKS:
            for name, bound, preset, expected in CASES:
                with self.subTest(f"{hook.parent.parent.parent.parent.parent.name}: {name}"):
                    # Feed the first run's result back in as the preset.
                    first = run_case(hook, bound, preset)[:2]
                    self.assertEqual(run_case(hook, bound, first)[:2], first)


if __name__ == "__main__":
    unittest.main()

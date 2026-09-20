## ECC (Everything Claude Code)

This sandbox has ECC's rules under `~/.claude/rules/ecc/`, plus its
agents and commands. The rules load automatically. ECC's
continuous-learning hooks runtime is not installed; to add it, run
ECC's installer with `--profile core` from inside the session — that
profile is a superset of `minimal` and writes the skills too, so it
needs a writable skills store (see below), or `--modules` with the
skills module left out.

ECC's skills are installed under `~/.claude/skills/ecc/` only when
`~/.claude/skills` is writable — for example the sandbox was created
with `--skills readwrite` or `--skills off` (no store mounted, so the
installer creates the directory itself), the host's
`skills.defaultMode` setting makes that the default, or the sbx
predates v0.43.0. Check with `ls ~/.claude/skills/ecc`; if the skills
are missing and you need them, ask the user to recreate the sandbox
with `--skills readwrite` — it is a host-side flag you cannot set
from in here.

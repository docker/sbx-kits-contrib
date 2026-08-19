# ecc

A mixin installing
[affaan-m/ECC](https://github.com/affaan-m/ECC) — "Everything Claude
Code": a large agent-harness content pack of skills, agents, rules, and
commands. Pinned to `v2.0.0`, installed with upstream's **minimal
profile**. The content is Claude-Code-specific, so the kit declares
`requires.agent: claude`.

## Usage

```console
sbx run --kit "docker.io/sbx/ecc-kit:latest" claude
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=ecc" claude
```

The installer places rules under `~/.claude/rules/ecc/`, skills under
`~/.claude/skills/ecc/`, plus agents and commands, and tracks every file
in `~/.claude/ecc/install-state.json` (reversible via upstream's
`uninstall.js`).

## Design notes

- **Minimal profile**: installs the content (rules/skills/agents/
  commands) but not the hooks runtime ("instincts"/continuous-learning
  memory). Upstream documents that the installer leaves
  `~/.claude/settings.json` untouched, so there's no conflict with the
  platform-seeded settings. Want the hooks? Re-run upstream's installer
  with `--profile core` from inside the session.
- Upstream warns **"do not stack install methods"** — this kit uses only
  the manual path; don't additionally `/plugin install ecc@ecc` in the
  same sandbox.
- ECC is a big pack (260+ skills upstream; minimal installs a subset) —
  expect some context-window cost from the rules it loads.
- No telemetry found upstream; github.com + registry.npmjs.org are
  contacted at install time only.

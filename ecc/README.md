# ecc

A mixin installing
[affaan-m/ECC](https://github.com/affaan-m/ECC) — "Everything Claude
Code": a large agent-harness content pack of skills, agents, rules, and
commands. Pinned to `v2.0.0`, installed from upstream's **minimal
profile**; the skills part of it needs a writable skills store (see the
design note below). The content is Claude-Code-specific, so the kit
declares `requires.agent: claude`.

## Usage

```console
sbx run --kit "docker.io/sbx/ecc-kit:latest" claude
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=ecc" claude
```

The installer places rules under `~/.claude/rules/ecc/`, plus agents and
commands, and tracks every file in `~/.claude/ecc/install-state.json`
(reversible via upstream's `uninstall.js`). Skills land under
`~/.claude/skills/ecc/` only when the sandbox's skills store is
writable.

## Design notes

- **No hooks runtime**: the minimal profile installs the content
  (rules/agents/commands, plus skills when the skills store is writable)
  but not the hooks runtime ("instincts"/continuous-learning memory).
  Upstream documents that the installer leaves
  `~/.claude/settings.json` untouched, so there's no conflict with the
  platform-seeded settings. Want the hooks? Re-run upstream's installer
  with `--profile core` from inside the session — `core` is a superset
  of `minimal`, so it writes the skills too and needs a writable skills
  store; without one, pass `--modules` and leave the skills module out.
- **Read-only skills store**: since sbx v0.43.0 the shared skills store
  is bind-mounted read-only at `~/.claude/skills` by default, and
  upstream's installer aborts at its first read-only write, leaving a
  partial install. So when the store is read-only the kit installs the
  modules `rules-core,agents-core,commands-core,platform-configs`
  instead of the whole minimal profile, dropping `workflow-quality` —
  ECC's skills, and nothing else. For the full profile, create the
  sandbox with a writable store:

  ```console
  sbx run --skills readwrite --kit "docker.io/sbx/ecc-kit:latest" claude
  ```

  `--skills off` also works: no store is mounted, so the installer
  creates `~/.claude/skills` itself.
- Upstream warns **"do not stack install methods"** — this kit uses only
  the manual path; don't additionally `/plugin install ecc@ecc` in the
  same sandbox.
- ECC is a big pack (260+ skills upstream; this kit installs a subset of
  the content) — expect some context-window cost from the rules it
  loads.
- No telemetry found upstream; github.com + registry.npmjs.org are
  contacted at install time only.

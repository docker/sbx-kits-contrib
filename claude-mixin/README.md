# claude-mixin

[Claude Code](https://code.claude.com) as a **mixin** (`kind: mixin`,
`schemaVersion: "3"`) — the same agent the [`claude`](../claude) workload kit
ships, packaged as an overlay you layer onto a shell base instead of booting as
the whole environment.

Use this one when the sandbox already has a workload you want to keep (a shell,
a language toolchain, another team's base image) and you want `claude` in it.
Use [`claude`](../claude) when Claude Code *is* the environment.

## Composing it

```console
sbx run --kit ./claude-mixin/ <base-agent>
```

The two are mutually exclusive: both `provides: ["claude"]`, and a composition
with two providers of one name is refused — the workload already carries the
agent this mixin installs.

## What it carries

Everything the workload declares that belongs to the agent rather than to the
environment:

- the `anthropic` credential, covering both a console API key and a Claude
  subscription, with the same deliberate omission of `proxyManaged` (see the
  workload's [README](../claude/README.md#why-the-api-key-is-not-proxymanaged));
- the same egress allow-list, including the apt hosts the background
  `apt-get update` needs;
- the same five `~/.claude/` session-state volumes;
- the same install and startup hooks — trust flags, `settings.json` seeded from
  the surfaced auth mode, MCP gateway registration;
- a body for the composed `CLAUDE.md`.

The install itself is the unmodified upstream one, run over the workload's base
in a build stage and staged into a `scratch` overlay. Anthropic's installer is
not relocatable and the install *method* is what `claude update` drives, so the
mixin keeps it rather than swapping in a `--prefix` build.

## What it deliberately leaves to the base workload

| Left out | Why |
|---|---|
| `ENTRYPOINT` | The base's launch command stays; you run `claude` from the shell. |
| `sbx@1` | A mixin's image config is not the composed image's, so the identity and shells that type is a claim about are the base's. |
| `agent-context` `filename:` | `CLAUDE.md` names the profile, which belongs to the workload. This kit contributes a body to it. |
| `agent-sessions@1` | The session verbs are argv tails on a launch command this kit does not own. |
| `IS_SANDBOX` and the telemetry switches as image `ENV` | A mixin's `ENV` does not become the composed image's, so they ride the overlay as `/etc/profile.d/claude-mixin-env.sh` exports instead. |

## Related

- [`claude`](../claude) — the same agent as a standalone workload kit.
- [`claude-mem`](../claude-mem), [`claude-acp`](../claude-acp),
  [`claude-sbx-statusline`](../claude-sbx-statusline), [`ecc`](../ecc),
  [`claude-model-runner`](../claude-model-runner) — mixins that
  `requires: ["claude"]` and therefore compose onto either shape.

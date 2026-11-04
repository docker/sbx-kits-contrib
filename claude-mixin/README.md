> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# claude-mixin

[Claude Code](https://code.claude.com) as a **mixin** (`kind: mixin`,
`schemaVersion: "3"`) — the same agent the [`claude`](https://github.com/docker-hardened-images/catalog/tree/main/image/claude) workload kit
(now a Docker Hardened Image) ships, packaged as an overlay you layer onto a shell base instead of booting as
the whole environment.

Use this one when the sandbox already has a workload you want to keep (a shell,
a language toolchain, another team's base image) and you want `claude` in it.
Use [`claude`](https://github.com/docker-hardened-images/catalog/tree/main/image/claude) when Claude Code *is* the environment.

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
  subscription, with the same deliberate omission of `proxyManaged` (see
  [below](#why-the-api-key-is-not-proxymanaged));
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

## Why the API key is *not* `proxyManaged`

This is the one deviation from the pattern every other apiKey credential in
this repo follows, and it is load-bearing rather than an oversight carried
forward.

With `proxyManaged: true` the engine sets `ANTHROPIC_API_KEY` to the literal
`proxy-managed` inside the container. Claude Code resolves auth in a fixed
order in which an `ANTHROPIC_API_KEY` in the environment outranks the OAuth
credentials file — so that sentinel would shadow a bound Claude subscription on
every sandbox, and the session would try to authenticate as a console API key
that may not exist.

Without it, the variable is simply not populated, and the sentinel Claude Code
is meant to send arrives by a different route: a lifecycle install hook writes
`"apiKeyHelper": "echo proxy-managed"` into `~/.claude/settings.json` when the
bound credential is an API key, and the credential's `inject` rules swap the
real value in at request time. The container never holds a usable key either
way.

## What it deliberately leaves to the base workload

| Left out | Why |
|---|---|
| `ENTRYPOINT` | The base's launch command stays; you run `claude` from the shell. |
| `sbx@1` | A mixin's image config is not the composed image's, so the identity and shells that type is a claim about are the base's. |
| `agent-context` `filename:` | `CLAUDE.md` names the profile, which belongs to the workload. This kit contributes a body to it. |
| `agent-sessions@1` | The session verbs are argv tails on a launch command this kit does not own. |
| `IS_SANDBOX` and the telemetry switches as image `ENV` | A mixin's `ENV` does not become the composed image's, so they ride the overlay as `/etc/profile.d/claude-mixin-env.sh` exports instead. |

## Related

- [`claude`](https://github.com/docker-hardened-images/catalog/tree/main/image/claude) — the same agent as a standalone workload, in the DHI
  catalog.
- [`claude-mem`](../claude-mem), [`claude-acp`](../claude-acp),
  [`claude-sbx-statusline`](../claude-sbx-statusline), [`ecc`](../ecc),
  [`claude-model-runner`](../claude-model-runner) — mixins that
  `requires: ["claude"]` and therefore compose onto either shape.

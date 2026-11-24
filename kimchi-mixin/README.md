> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# kimchi-mixin

The [Kimchi](https://kimchi.dev) coding agent as a **mixin** — the pinned CLI
in an overlay, with the Kimchi credential and its egress, layered onto a base
workload that is not Kimchi.

Use [`../kimchi`](../kimchi) instead when you want Kimchi to *be* the
sandbox: that kit is a workload, it owns the root filesystem, and attaching
drops you straight into the harness. This kit is for the other case — a base
you already want, with Kimchi added to it.

## Usage

```console
sbx run "docker.io/sbx/kimchi-mixin:latest" --kit shell .
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=kimchi-mixin" --kit shell .
```

Or with a local clone of this repo:

```console
sbx run ./kimchi-mixin/ --kit shell .
```

## What this kit does and does not carry

A mixin is a delta, not a root filesystem, so the split from the workload is
not arbitrary. What rides along:

- the pinned Kimchi CLI and its share tree, in an overlay;
- the `kimchi` credential, declared optional;
- the egress Kimchi needs.

What stays with the base:

- **the launch command.** A mixin's image config never becomes the composed
  image's, so the base workload's entrypoint is what launches. You run
  `kimchi` from the shell. There is no `agent-sessions@1` here either, because
  that capability describes a launch argv this kit does not own — pass `-p`
  yourself when you want a headless prompt.
- **the agent-context profile filename.** This kit contributes a context body
  (`contentFile`) but not a `filename`, because the profile belongs to the
  kit that owns the environment.
- **`sbx@1`.** The identity the host honors is the base's.

## How the install relocates

The workload installs Kimchi into the agent's own home, because it owns its
root filesystem and the faithful thing there is the install v2's hook
performed, under `$HOME`. An overlay lands on a base this repo does not
control, so the install has to move somewhere the base cannot take away:
`/opt/kimchi`, with a symlink in `/usr/local/bin` for the launch.

That works because the installer was written for it. `install.sh` takes the
prefix from `KIMCHI_INSTALL_DIR` and `XDG_DATA_HOME`, and the CLI resolves its
own auxiliary files in this order:

1. `<binary path>/../../share/kimchi` — relative to the executable;
2. `$XDG_DATA_HOME/kimchi`;
3. `$HOME/.local/share/kimchi`.

A binary at `/opt/kimchi/bin/kimchi` therefore finds `/opt/kimchi/share/kimchi`
by the **first** rule, with no environment variable set at all. The overlay
ships both halves under one prefix and needs nothing from the composed base's
environment. The build checks this explicitly: the version check runs with
`XDG_DATA_HOME` unset, because a build that only passed with it set would
ship an overlay whose CLI cannot find its own resources.

## The version pin

The Kimchi release is pinned, in this kit and in [`../kimchi`](../kimchi)
alike — the two must be bumped together, since they provide the same name.
The descriptor's `version` arg holds it, the recipe hands it to the
installer, and the kit publishes `provides: ["kimchi@<version>"]` plus a
top-level `version:` from that same arg. The build runs `kimchi --version`
and fails if the installed binary reports anything else.

To bump the pin, set the arg's default to what the latest release is:

```console
curl -fsSL https://api.github.com/repos/getkimchi/kimchi/releases/latest
```

## How auth works

Identical to the workload's, and for the same reason. The credential is
declared `optional`, because in v3 a credential entry is required unless it
opts out, and this one must not be: with no key bound, Kimchi's own
first-run login selector is the documented onboarding path.

It is **not** declared `proxyManaged`. Kimchi's harness reads
`KIMCHI_API_KEY` directly and uses it as the bearer token for its own
requests; a sentinel there would be rejected ("KIMCHI_API_KEY environment
variable contains an invalid API key"). The proxy still presents the real
value outbound on the two hosts the key is injected into.

```console
sbx secret set kimchi
```

## Network policy

The same host list as the workload's, and for the same reason — this overlay
ships the same CLI, so it needs the same hosts:

| Host | Why |
|---|---|
| `llm.kimchi.dev` | Inference and the model-metadata feed. |
| `api.cast.ai` | Platform API: organization policy, key verification, the organization list, OTLP telemetry. |
| `app.kimchi.dev` | The console: browser login and account pages. |
| `login.kimchi.dev` | The OAuth authorization and token endpoint. |
| `api.github.com`, `github.com` | The background update probe's release metadata and assets. |

The full reasoning for each entry is in [`../kimchi/README.md`](../kimchi/README.md).

## Cleanup

Nothing is written to the host.

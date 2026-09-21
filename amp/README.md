# amp

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for the
[Amp](https://ampcode.com/) coding agent. The kit ships Amp in its layers,
wires its API auth through the sandbox proxy, and runs
`amp --dangerously-allow-all` as the entrypoint when you attach.

Its content ([amp.dockerfile](./amp.dockerfile)) is the
`docker/sandbox-templates:shell-docker` template, Amp's own installer run at
build time, and the launch command in the image config. Everything else this
kit does it does through declarations rather than layers.

The Amp release is pinned. The descriptor's `version` arg holds it, the recipe
exports it as `AMP_VERSION` for Amp's installer to read, and the kit publishes
`provides: ["amp@<version>"]` plus a top-level `version:` from that same arg —
so the publish tag names the Amp release the image carries. The build then runs
`amp --version` and fails if the installed binary reports anything else. Amp
publishes continuously (`0.0.<timestamp>-g<commit>`, a new build most hours), so
expect the pin to sit behind upstream; past versions stay on the CDN, so it
keeps building. To bump it, set the arg's default to what Amp's own pointer
returns:

```console
curl -fsSL https://static.ampcode.com/cli/cli-version.txt
```

[`../amp-mixin`](../amp-mixin) installs the same release and must be bumped with
it.

There is also an [`amp-mixin`](../amp-mixin) variant, for layering Amp onto a
shell workload instead of running a sandbox of its own.

It's also the worked example for
[Build your own agent kit](https://docs.docker.com/ai/sandboxes/customize/build-an-agent/)
in the Docker Sandboxes docs — see that page for the design rationale
behind each section of the descriptor.

## Prerequisites

- An [Amp](https://ampcode.com/) account and API key.
- `$AMP_API_KEY` exported on your host (the value gets stored in
  sbx's secret store; it never enters the sandbox).

## Setup

Register your Amp API key with `sbx secret set-custom`. The command
stores the value in the host secret store and exposes a placeholder
inside every sandbox launched from this kit:

```console
sbx secret set-custom -g \
    --host ampcode.com \
    --env AMP_API_KEY \
    --placeholder "sgamp-{rand}" \
    --value "$AMP_API_KEY"
```

`{rand}` expands to a random suffix; the resulting placeholder
(`sgamp-<random>`) is what `AMP_API_KEY` is set to inside the sandbox.
Amp accepts it as a syntactically valid key, and the proxy substitutes
the real secret on outbound requests to `ampcode.com`.

> [!NOTE]
> `sbx secret set-custom` is an experimental command and isn't listed
> in `sbx secret --help`. It works today but may change in future
> releases of sbx.

## Usage

Run the kit. Pass the kit's name (`amp`) as the agent argument. The primary
form is its published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/docker/sbx-kit-amp:latest" amp
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=amp" amp
```

Or with a local clone of this repo:

```console
sbx run --kit ./amp/ amp
```

Amp is already installed in the kit's image — its `curl | bash` script runs
when the kit is built, not when a sandbox is created — so a launch only
applies the kit's network and proxy auth wiring. That is also why the kit
declares no install-phase egress at all: `ampcode.com` and its wildcard are
granted for the running agent only. Subsequent launches reuse the sandbox.

## How auth works

The kit's `network` block declares two things:

- `serviceDomains: ampcode.com -> amp` and `serviceAuth.amp` tell the
  proxy to inject `Authorization: Bearer <key>` on outbound requests
  to `ampcode.com`. The `<key>` value comes from the secret store
  entry registered above, matched by host.
- `allowedDomains` covers both the apex (`ampcode.com`) and the
  install/CDN subdomains (`*.ampcode.com`).

`serviceDomains` is intentionally narrow: a wildcard there would push
the proxy into TLS-intercepting mode for every `*.ampcode.com` host,
including the binary CDN the install script downloads from, which
corrupts the install. List only the host that needs auth injection.

See
[Plan authentication](https://docs.docker.com/ai/sandboxes/customize/build-an-agent/#plan-authentication)
in the docs for the full picture.

## Removing the stored secret

To remove the entry created by `set-custom`, pass the host to
`sbx secret rm`:

```console
sbx secret rm -g --host ampcode.com
```

The `--host` flag on `sbx secret rm` isn't listed in
`sbx secret rm --help`, but it's the only way to remove entries
created with `set-custom`. Like `set-custom` itself, it's experimental
and may change.

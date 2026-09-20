# amp

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for the
[Amp](https://ampcode.com/) coding agent. The kit installs Amp into the
sandbox at creation time with a `lifecycle@1` install hook, wires its API auth
through the sandbox proxy, and runs `amp --dangerously-allow-all` as the
entrypoint when you attach.

Its content ([amp.dockerfile](./amp.dockerfile)) is the thinnest a workload
gets: the `docker/sandbox-templates:shell-docker` template as its base and the
launch command in the image config, because everything else this kit does it
does through declarations rather than layers.

There is also an [`amp-mixin`](../amp-mixin) variant, for layering Amp onto a
shell workload instead of running a sandbox of its own. It is
declaration-only — with the install happening at create time there is no build
output for an overlay to carry.

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
sbx run --kit "docker.io/sbx/amp-kit:latest" amp
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=amp" amp
```

Or with a local clone of this repo:

```console
sbx run --kit ./amp/ amp
```

The first launch installs Amp via its `curl | bash` script and applies
the kit's network and proxy auth wiring. Subsequent launches reuse the
sandbox.

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

> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# trivy-mixin

[Trivy](https://github.com/aquasecurity/trivy) as a **mixin** — the same
scanner as the [`trivy`](../trivy) workload kit, packaged as an overlay you
layer onto a shell base instead of running as the sandbox's own image.

## Usage

```console
sbx run --kit ./trivy-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=trivy-mixin" <shell-workload>
```

The base workload keeps its own launch command; `trivy` is simply on `PATH`:

```console
trivy fs .
```

## What it carries

- The pinned, SHA256-verified `trivy` release binary at
  `/usr/local/bin/trivy`. One static Go binary with nothing to relocate,
  which is why this overlay takes the plain `FROM <base> AS build` → `/out` →
  `FROM scratch` shape.
- The runtime egress its vulnerability-database pull needs: `mirror.gcr.io`,
  `ghcr.io`, `pkg-containers.githubusercontent.com`.

## Why there is no install hook here

The workload kit installs trivy from a lifecycle install hook at sandbox
create, and opens `github.com` plus the two release-asset hosts for exactly
as long as that hook runs. An overlay ships the verified binary in its layers,
so the download happens at build time, in the builder — there is nothing left
to install and no install phase to open. The version and both digests moved
into `trivy-mixin.dockerfile` unchanged; keep them in step with
`../trivy/trivy.yaml`.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **`sbx@1`.** A mixin's image config never becomes the composed image's, so
  there is no identity for the host to honor here.

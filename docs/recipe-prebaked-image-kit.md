# Pre-baked-image kits: transitional notes

> **These are notes on a transitional approach, not a recipe to copy.**
> Moving an agent's install-time work into a custom image (so the kit's
> `spec.yaml` only applies *policy*) is the right shape, and the boot-time
> win is real. But agents that orchestrate their own containers — nanoclaw,
> hermes, openclaw, paperclip, gstack — all hit the same "inner images"
> problem and each hand-rolls the same workaround to get those images into
> the sandbox's Docker daemon. That's a product gap in sbx, not a pattern
> worth propagating: the durable fix is **kit-declared inner images seeded
> by the runtime** (tracked in [sbx#TODO](https://github.com/docker/sbx/issues/TODO)).
> Until that lands, this page documents the least-bad interim approach
> (digest-pinned first-boot pulls) and the gotchas worth knowing.

This is the process used to build the `nanoclaw/` kit (modelled on
[shelajev/hermes-sbx-kits](https://github.com/shelajev/hermes-sbx-kits)).
The goal: move every install-time step into a custom Docker image so the
kit's `spec.yaml` only applies *policy* (network, credentials, ports, env),
and a fresh sandbox is usable in seconds instead of minutes.

## 0. Understand what the agent needs at runtime

Read the agent's install path end-to-end before writing anything. Catalog:

- **Toolchain**: language runtimes and versions (check `package.json`
  `engines`/`packageManager`, `.nvmrc`, etc.), build tools, native modules.
- **Install steps**: what its installer/setup wizard actually does — clone,
  dependency install, compile, service registration, container builds.
- **Inner containers**: does the agent spawn containers itself (needs a
  `*-docker` template base + Docker-in-Docker)? Which images does it build
  or pull at runtime? Those are your pre-seeding targets.
- **Network**: every domain touched at runtime (model APIs, package
  registries, container registries, chat platforms, telemetry). Run it once
  and check `sbx policy log` for blocked domains you missed.
- **Ports**: every port it listens on that the host or external services
  must reach (webhooks, dashboards, gateways).
- **Escape hatches**: env overrides that let you bypass install-time work
  (e.g. nanoclaw's `CONTAINER_IMAGE` override and `NANOCLAW_SKIP` step
  list). These determine how cleanly you can pre-bake.

## 1. Split the work: image vs. kit

| Belongs in the image | Belongs in spec.yaml |
|---|---|
| Toolchain upgrades (Node 22, pnpm, …) | `network:` allow/deny lists, `serviceDomains`/`serviceAuth` |
| Source checkout @ pinned ref + dependency install + build | `credentials:` and `oauth:` policy |
| CLI binaries the setup wizard would download | `environment.variables` (incl. overrides like `CONTAINER_IMAGE`) |
| Entrypoint/helper scripts | `network.publishedPorts` |
| Inner container images (published to a registry, pulled by digest at first boot) | tiny idempotent `commands.startup` glue |
| PATH/profile setup (`/etc/sandbox-persistent.sh`) | — |

Rule of thumb: if it downloads, compiles, or installs, bake it. If it
configures *this sandbox's* relationship to the host (auth, network,
ports), it's kit policy. Anything left in `commands:` should be idempotent
and near-instant.

## 2. Write the Dockerfile

- Base on the `docker/sandbox-templates` image the old kit used
  (`shell-docker` for plain agents, `claude-code-docker` when the agent
  shells out to Claude Code, `*-docker` whenever the agent needs
  Docker-in-Docker). These bases match the sandbox runtime's user model
  (`agent`, uid 1000, groups `sudo`+`docker`) and proxy/CA machinery —
  don't build from scratch.
- Pin everything: upstream repo ref (`ARG NANOCLAW_REF=<commit>`), package
  manager version, inner-image versions. Unpinned = unreproducible.
- Do root work (`USER root`) first — toolchain, profile lines — then switch
  to `USER agent` for the checkout/build so file ownership is right.
- Bake the entrypoint as a real script under `scripts/` and `COPY` it in,
  instead of `printf`-escaping it through spec.yaml install commands.
- End with `USER agent` and a sane `CMD`.

### Seeding inner Docker images

The agent's inner images (the agent container it spawns, plus any gateway/
database images) must be in the sandbox's Docker daemon before it runs.

The interim approach: **digest-pinned `docker pull` at first boot**, in the
background. The kit's `spec.yaml` already opens egress to the registries
these come from (`registry-1.docker.io`, `ghcr.io`, …), so an idempotent
`seed-images.sh` waits for the inner daemon, then for each ref checks
`docker image inspect` and pulls under a lock (first boot pulls; later
boots no-op). Refs are pinned by digest (`image@sha256:…`), so what runs is
exactly what policy/scanning/signing can point at — the whole reason not to
embed an opaque `docker save` tar.

Every inner image must therefore be **published to a registry**. Images the
agent only builds locally (nanoclaw builds its agent container from a
`container/` dir) have nowhere to pull from — publish them first (upstream
ideally, or self-publish a digest-pinned copy as a stopgap) rather than
embedding them.

> **Why not embed a `docker save` tar?** It's invisible to policy,
> scanning, and signing (tooling only understands image refs); it stores
> every inner image twice per sandbox (in the tar, then again in the daemon
> after load); and the tar is arch-specific, forcing per-arch staging. An
> earlier version of this kit did this — the digest-pinned-pull approach
> above keeps nearly all the speedup without any of those costs. The one
> tradeoff: first boot now depends on registry reachability instead of
> being self-contained.

If the agent derives image names dynamically (nanoclaw uses a per-checkout
slug), find the env override (`CONTAINER_IMAGE`) and set it in
`environment.variables` so it uses your pre-loaded tag.

## 3. Write the build script

`scripts/build-image.sh` does, in order: clone upstream @ pinned ref →
build the inner agent image (and push it, so first boot can pull it) →
`docker build` the sandbox image, baking the digest-pinned list of inner
images the seed script will pull. Everything overridable via env
(`NANOCLAW_REF`, `IMAGE`, …). No `docker save`, no `images/` tar — the
inner images live in registries, not in the sandbox image.

## 4. Write spec.yaml (v2 naming)

```yaml
schemaVersion: "1"       # stays "1" — the TCK pins it; "2" only switches the OCI distribution format
kind: sandbox            # v2 rename of kind: agent
sandbox:                 # v2 rename of the agent: block
  image: "docker.io/<ns>/<agent>-sbx:latest"
  entrypoint:
    run: ["/usr/local/bin/<agent>-start"]
network:
  publishedPorts:        # every port the agent needs reachable
    - container: 3000
      name: webhook
```

Carry over the old kit's `serviceDomains`/`serviceAuth`/`oauth`/
`credentials` blocks unchanged — auth policy is orthogonal to the image
switch. Trim `allowedDomains` of build-time-only domains (e.g. `nodejs.org`
once Node is baked), keep runtime ones (registries the agent installs from
at runtime, chat platforms, telemetry). Replace `commands.install` with at
most a couple of `commands.startup` entries (socket perms, background
image-load kick-off).

## 5. Validate and test locally

```console
$ sbx kit validate ./<kit>/                # CLI-side validation (needs sbx ≥ 0.32 for v2)
$ go test -v -count=1 ./<kit>/...          # repo TCK (uses spec/ library)
$ ./<kit>/scripts/build-image.sh           # build the image
$ docker save <image> -o /tmp/img.tar && sbx template load /tmp/img.tar
$ sbx create --kit ./<kit> --name <name> <agent> .
$ sbx ports <name>                          # published ports assigned?
$ sbx exec <name> -- <smoke checks>         # service up, inner images loaded
$ sbx run <name>                            # interactive attach
$ sbx policy log                            # any blocked domains?
```

`sbx` keeps its own template store separate from Docker Desktop's image
store — the `docker save | sbx template load` step is what makes a locally
built image visible to `sbx create`.

Smoke checks worth scripting: service process up, its socket/health
endpoint responding, `docker images` inside the sandbox showing the
pre-seeded images, and a real end-to-end message if credentials are
available.

## 6. Publish

1. Publish the inner agent image (`docker push
   docker.io/<ns>/<agent>-agent:<tag>`, multi-arch) so first boot can pull
   it by digest, then `docker push docker.io/<ns>/<agent>-sbx:latest` (the
   sandbox image bakes the digest list but no longer embeds the images).
   Multi-arch via a CI matrix of native runners, or single-arch to start.
2. Optionally `sbx kit push ./<kit> docker.io/<ns>/sbx-<agent>-kit:latest`
   to publish the kit itself as an OCI artifact. Stage a clean copy first —
   `sbx kit push` doesn't honor `.gitignore`, so a leftover `images/` tar
   would get packaged.
3. PR into this repo: commits need DCO sign-off (`git commit -s`) and a
   cryptographic signature (see CONTRIBUTING.md).

## Gotchas hit while converting kits (nanoclaw, openclaw, paperclip, gstack)

- **The sandbox microVM uses 16KB pages on Apple Silicon** (Docker
  Desktop's VM uses 4KB). Prebuilt arm64 native libs linked for 4KB pages
  fail at runtime with "ELF load command address/offset not page-aligned"
  — and amd64 CI can't catch it. Hit by paperclip's `embedded-postgres`;
  fixed by substituting the distro package (Ubuntu/Debian arm64 builds
  are page-size agnostic). Smoke-test bundled native binaries inside a
  real sandbox, not just `docker run`.
- **Playwright's distro dependency map lags new Ubuntu releases**: on the
  templates' Ubuntu 26.04, `playwright install --with-deps chromium`
  refuses. `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-<x64|arm64>`
  (switch on `TARGETARCH`) makes it proceed with the closest supported
  dep list.
- **Startup commands and entrypoints run with a minimal PATH** — npm
  global bin dirs aren't on it. Symlink baked binaries into
  `/usr/local/bin` in the Dockerfile.
- **The sandbox runtime may seed agent config at create time**, clobbering
  files you baked into the image (it writes its own
  `~/.openclaw/openclaw.json`, dropping `gateway.mode`). Don't rely on
  baked config files the runtime also manages — re-assert required keys
  idempotently in a startup command (`openclaw config set gateway.mode
  local`).
- **Loopback-only guardrails vs the port-forwarder**: apps whose
  zero-auth mode hard-requires a loopback bind (paperclip's
  `local_trusted`) can't be reached through published ports. Run their
  authenticated mode (usually the upstream Docker default) and
  generate/persist the required secret in the entrypoint.

- **`sbx` CLI version skew**: the v2 names and `publishedPorts` need
  sbx ≥ 0.32.0; 0.31.x rejects both at `sbx kit validate` time. Keep
  `schemaVersion: "1"` — the repo TCK pins it, and "2" only opts into the
  v2 OCI artifact format at distribution time. And as of
  0.32.0 the runtime validates `publishedPorts` but doesn't auto-bind them
  at sandbox start — document `sbx ports <sandbox> --publish ...` as the
  interim path.
- **`COPY --chmod` applies the file mode to directories it implicitly
  creates** — a 0644 file mode leaves the parent directory without execute
  bits, unreadable by everyone. `RUN install -d -m 0755 <dir>` first.
  (Historical: when this kit still embedded a `docker save` tar, that tar
  was written 0600, so it needed an explicit `--chmod=0644` on the COPY.
  No longer relevant now that inner images are pulled, not embedded.)
- **Install-state tripwires**: agents that record their installed version
  (nanoclaw's `data/upgrade-state.json`) refuse to start from a bare baked
  checkout. Stamp the state at image build time, the same way the agent's
  sanctioned installer would.
- **Per-checkout image names**: agents that tag images from a path hash
  break when you pre-load a fixed tag — always look for the env override.
- **The setup wizard re-doing baked work**: find the skip mechanism
  (nanoclaw: `NANOCLAW_SKIP=environment,container,service`) so the wizard
  only runs the steps that genuinely need the user (auth, channel pairing).
- **Docker socket perms reset on every boot** — restore them in a startup
  command, not just install time.
- **Shallow clones break runtime skills** that fetch other branches; clone
  full history if the agent self-updates from git.
- **Proxy env for runtime installs**: baked toolchains still need
  `npm config set proxy` (or equivalent) at startup since proxy env isn't
  known at image-build time.

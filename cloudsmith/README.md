> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# cloudsmith - Cloudsmith artifact management

A mixin kit that installs the official [Cloudsmith](https://cloudsmith.io/) CLI wired to Cloudsmith's cloud API, so an agent can push, pull, list, and manage packages across 30+ formats (Docker, npm, PyPI, Maven, Debian, RPM, Helm, Cargo, Go, NuGet, and more). The API key stays on the host; the sandbox only ever sees a placeholder.

Pairs with any base agent.

## Usage

Store a Cloudsmith API key (read + write) once on the host:

```console
sbx secret set cloudsmith
```

Then create a sandbox with the kit:

```console
sbx run --kit "docker.io/docker/sbx-kit-cloudsmith:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=cloudsmith" claude
sbx run --kit ./cloudsmith/ claude
```

Inside the sandbox:

```console
cloudsmith whoami                                  # verify auth
cloudsmith list packages OWNER/REPO                # list packages
cloudsmith push python OWNER/REPO dist/pkg.whl     # upload a Python wheel
cloudsmith push docker OWNER/REPO image.tar        # upload a Docker image tarball
```

`OWNER` is your Cloudsmith workspace (organization) slug and `REPO` is the repository slug. Run `cloudsmith push --help` for the full list of formats.

## How auth works

The kit declares a `cloudsmith` credential with one inject rule for `api.cloudsmith.io`. Cloudsmith uses `Authorization: token <key>` (not Bearer, not Basic), so the header and format are spelled out by hand rather than via the `scheme:` sugar. Inside the container `CLOUDSMITH_API_KEY` is the placeholder `proxy-managed`; the proxy swaps in the real token on outbound requests to `api.cloudsmith.io`, so the key never touches the sandbox filesystem or environment. Run the CLI directly; do not try to read or echo the key.

The egress allowlist also covers the Cloudsmith content hosts (`dl.cloudsmith.io`, `docker.cloudsmith.io`, `npm.cloudsmith.io`). The pinned CLI is baked into the v3 kit image, so sandbox creation does not need PyPI access.

The v3 descriptor is `cloudsmith.yaml`, its overlay recipe is `cloudsmith.dockerfile`, and agent guidance lives in `cloudsmith-context.md`.

## Cleanup

```console
sbx secret rm --service cloudsmith
```

# Senpi

Standalone sandbox kit for [senpi](https://github.com/code-yeongyu/senpi),
the extension-first coding agent, for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

The kit publishes two OCI artifacts:

| Artifact | Hub repo | What it is |
|---|---|---|
| `docker.io/sbx/senpi-kit` | the kit (this repo, `senpi/`) | `spec.yaml` plus READMEs -- what you reference with `--kit` |
| `docker.io/sbx/senpi-image` | built by CI from `senpi/Dockerfile` | the base image, pre-baked with the `senpi` binary |

## Launch

From the project you want mounted:

```bash
sbx --cloud run senpi
```

or, for a community kit from Docker Hub:

```bash
sbx --cloud run docker.io/sbx/senpi-kit:latest senpi
```

The current directory becomes the sandbox workspace, mounted at `/workspace`.

## Credentials

Senpi calls the Anthropic API. Store your key on the host **before** you create
the sandbox -- it never enters the container raw:

```bash
sbx secret rm anthropic   # only if a stale binding exists
sbx secret set anthropic
# paste your Anthropic API key when prompted
```

The kit declares the `anthropic` service credential as `ANTHROPIC_API_KEY` and
the proxy substitutes it into `x-api-key` on egress to `api.anthropic.com`.
The sandbox receives a sentinel value, not the real key. senpi also reads
`ANTHROPIC_OAUTH_TOKEN` and prefers it over an API key, so OAuth binding works
with no extra configuration.

Scripted use:

```bash
sbx exec senpi -- senpi -p "list the failing tests"
```

Do not authenticate from inside the sandbox (`senpi /login` writes a real token
into the container and defeats the proxy model).

## Network policy

Only these domains are reachable from the sandbox:

- `api.anthropic.com` -- senpi's model endpoint (and where the credential is injected)
- `registry.npmjs.org` -- so senpi can install extensions/tools at runtime
  (`senpi install npm:@scope/pkg`)

Widen the policy in the web UI under Policies if your workflow needs more.

## Base image

`sbx/senpi-image` is built on `docker.io/sbx/shell-image`: the standard
sandbox tool chain (Node, npm, git, ripgrep, ...). On top of that it installs
Node 24 (senpi's engines require Node >= 24) and `@code-yeongyu/senpi` from
npm into the agent-owned global prefix, then symlinks `senpi` onto
`/usr/local/bin`. It runs as the non-root `agent` user with `CMD ["senpi"]`.

Build args:

- `BASE_IMAGE` -- re-point or digest-pin the base (`docker.io/sbx/shell-image:latest`).
- `SENPI_VERSION` -- pin a published `@code-yeongyu/senpi` version (`2026.10.27-2`, no leading `v`). Left empty, npm resolves `latest`.

## Kit vs image

You reference the **kit** (`--kit docker.io/sbx/senpi-kit:latest`) when
launching. The kit points at the **image** (`docker.io/sbx/senpi-image:latest`)
via `sandbox.image` in `senpi/spec.yaml`. Rebuilds of the image are published
by `.github/workflows/build-and-publish-kits.yml`; no bespoke workflow is
needed.

## Related

- Kit authoring: https://docs.docker.com/ai/sandboxes/customize/kits/
- Senpi Docker Sandboxes: https://github.com/code-yeongyu/senpi/blob/main/packages/coding-agent/docs/containerization.md#docker-sandboxes
- Publish/release conventions: ../PUBLISHING.md

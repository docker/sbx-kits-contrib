# oh-my-openagent

Standalone sandbox kit for [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent),
the OmO agent harness, for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

The kit publishes two OCI artifacts:

| Artifact | Hub repo | What it is |
|---|---|---|
| `docker.io/sbx/oh-my-openagent-kit` | the kit (this repo, `oh-my-openagent/`) | `spec.yaml` plus READMEs -- what you reference with `--kit` |
| `docker.io/sbx/oh-my-openagent-image` | built by CI from `oh-my-openagent/Dockerfile` | the base image, pre-baked with the `oh-my-openagent` binary |

## Launch

From the project you want mounted:

```bash
sbx --cloud run oh-my-openagent
```

or, for a community kit from Docker Hub:

```bash
sbx --cloud run docker.io/sbx/oh-my-openagent-kit:latest oh-my-openagent
```

The current directory becomes the sandbox workspace, mounted at `/workspace`.

## Credentials

oh-my-openagent calls provider APIs. Store your key on the host **before** you create
the sandbox -- it never enters the container raw:

```bash
sbx secret rm anthropic   # only if a stale binding exists
sbx secret set anthropic
# paste your Anthropic API key when prompted
```

The kit declares the `anthropic` service credential as `ANTHROPIC_API_KEY` and
the proxy substitutes it into `x-api-key` on egress to `api.anthropic.com`.
The sandbox receives a sentinel value, not the real key.

Scripted use:

```bash
sbx exec oh-my-openagent -- oh-my-openagent -p "list the failing tests"
```

Do not authenticate from inside the sandbox -- writing a real token into the
container defeats the proxy model.

## Network policy

Only these domains are reachable from the sandbox:

- `api.anthropic.com` -- oh-my-openagent's model endpoint (and where the credential is injected)
- `registry.npmjs.org` -- so oh-my-openagent can install extensions/tools at runtime

Widen the policy in the web UI under Policies if your workflow needs more.

## Base image

`sbx/oh-my-openagent-image` is built on `docker.io/sbx/shell-image`: the standard
sandbox tool chain (Node, npm, git, ripgrep, ...). On top of that it installs
Node 24 and the `oh-my-openagent` npm package (plus its platform-specific binary
package) into the agent-owned global prefix, then symlinks `oh-my-openagent` onto
`/usr/local/bin`. It runs as the non-root `agent` user with `CMD ["oh-my-openagent"]`.

Build args:

- `BASE_IMAGE` -- re-point or digest-pin the base (`docker.io/sbx/shell-image:latest`).
- `OH_MY_OPENAGENT_VERSION` -- pin a published `oh-my-openagent` version (`5.1.48`, no leading `v`). Left empty, npm resolves `latest`.

## Kit vs image

You reference the **kit** (`--kit docker.io/sbx/oh-my-openagent-kit:latest`) when
launching. The kit points at the **image** (`docker.io/sbx/oh-my-openagent-image:latest`)
via `sandbox.image` in `oh-my-openagent/spec.yaml`. Rebuilds of the image are published
by `.github/workflows/build-and-publish-kits.yml`; no bespoke workflow is needed.

## Related

- Kit authoring: https://docs.docker.com/ai/sandboxes/customize/kits/
- oh-my-openagent: https://github.com/code-yeongyu/oh-my-openagent
- Publish/release conventions: ../PUBLISHING.md

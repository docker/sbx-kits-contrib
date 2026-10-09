> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# claude-vertex-mixin

Points Claude Code at Claude on Google Vertex AI, as a **mixin**
(`kind: mixin`, `schemaVersion: "3"`). Layered on the [`claude`](../claude)
workload, the sandbox talks to Vertex with the Application Default Credentials
you created on the host. The real refresh token stays outside the container.

It replaces the built-in `claude-vertex` agent.

## Prerequisite

On the host, once:

```console
gcloud auth application-default login
```

Login never happens inside the sandbox. `accounts.google.com` is not reachable.

## Composing it

```console
sbx run --kit ./claude-vertex-mixin/ claude
```

Supply the project and region as kit args (`vertex_project` is required,
`vertex_region` defaults to `global`). They are exported as
`ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION`.

It declares `requires: ["claude", "deb/jq"]` and `provides: ["claude-vertex"]`.
The `provides` entry is unversioned because the overlay ships no binary.

## Engine support

The `vertex` credential must be honoured for any kit that declares it, not only
for the built-in agent. Until an `sbx` release does that, the mixin composes but
the token refresh and credential-file steps do not run. The release number is
not known yet and will be named here once it exists.

## What the sandbox gets

| Piece | Value |
|---|---|
| Credential | `vertex`, from gcloud ADC. `SBX_CRED_VERTEX_MODE` is `none` when nothing is stored. |
| Credential file | `~/.config/gcloud/application_default_credentials.json`, with a placeholder `refresh_token` |
| Environment | `CLAUDE_CODE_USE_VERTEX=1`, plus the project and region args |
| Settings | `apiKeyHelper` is added to `~/.claude/settings.json` when a credential resolved |
| Egress | `aiplatform.googleapis.com`, `oauth2.googleapis.com` |

The `client_id` and `client_secret` in the credential file are gcloud's public
installer values (see `google-auth-library-python`, `google/auth/_cloud_sdk.py`).
They are not secret.

## What the allowlist leaves out

- `googleapis.com` as a whole.
- `storage.googleapis.com` and `bigquery.googleapis.com`. Vertex is here for
  inference.
- `accounts.google.com`. Login happens on the host.

Region-specific Vertex hosts are not in the static list. The engine adds the
ones for your region at create time; this is not verified for a mixin yet.

## What it deliberately leaves to the base workload

| Left out | Why |
|---|---|
| Claude Code install | The `claude` workload owns it. |
| `~/.claude.json` and the base `settings.json` | Seeded by the workload; this kit only adds `apiKeyHelper`. |
| Session volumes, MCP gateway, `CLAUDE.md` profile | Workload concerns. |
| `ENTRYPOINT` | The base's launch command stays. |
| `CLAUDE_CODE_USE_VERTEX` as image `ENV` only | A mixin's `ENV` does not become the composed image's, so it also rides as a `/etc/profile.d/claude-vertex-env.sh` export. |

## One thing to know about egress

Allow-lists union per phase across a composition. With the `claude` workload
underneath, Anthropic's own hosts stay reachable next to Vertex, even though
Claude Code is routed at Vertex.

> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# claude-bedrock-mixin

Points Claude Code at Amazon Bedrock, as a **mixin** (`kind: mixin`,
`schemaVersion: "3"`). Layered on the [`claude`](../claude) workload, the sandbox
talks to Bedrock with the AWS profile you stored on the host, and to nothing
else in AWS.

It provides `claude-bedrock`, which [`aidlc-claude`](../aidlc-claude) requires.

## Engine release

This needs an `sbx` release that honours the `bedrock` credential service on
any kit that declares it. Until that release exists, the mixin composes but the
credential refresh and settings steps do not run. The release will be named here
once it ships.

## Composing it

```console
sbx secret set bedrock
sbx run claude --kit ./claude-bedrock-mixin/
```

`sbx secret set bedrock` takes an AWS profile name, not keys. `sbx create` does
not read `AWS_PROFILE` from your shell. The daemon resolves the profile on the
host and writes the STS credentials to `~/.aws/sbx-bedrock-credentials.json` in
the container, refreshing the file in place before expiry.

It declares `requires: ["claude", "deb/jq"]`. The `provides` entry stays
unversioned because the overlay ships no binary.

## What it adds

| Piece | Value |
|---|---|
| Environment | `CLAUDE_CODE_USE_BEDROCK=1`, `ANTHROPIC_DEFAULT_SONNET_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| Settings keys | `apiKeyHelper` (stops the `/login` prompt) and `awsCredentialExport` (reads the sidecar file) |
| Egress | `bedrock-runtime.*.amazonaws.com:443`, `bedrock.*.amazonaws.com:443` |

Claude Code runs `awsCredentialExport` again about five minutes before the
reported expiry, so a running session picks up a refresh without a restart. The
default `~/.aws/credentials` would not, because the AWS SDK caches it.

With no `bedrock` secret stored, `SBX_CRED_BEDROCK_MODE` is `none` and
`awsCredentialExport` is not set.

The kit sets no AWS region, so it comes from the profile.

## What the allowlist leaves out

| Left out | Why |
|---|---|
| FIPS endpoints (`bedrock-runtime-fips.*`) | Not needed by default. Add them in a fork. |
| Bedrock Agents (`bedrock-agent.*`, `bedrock-agent-runtime.*`) | Claude Code does not use them. |
| `sts.*`, `oidc.*`, `portal.sso.*` | The daemon resolves credentials on the host, so the container never calls them. |
| The rest of `*.amazonaws.com` | A leaked STS credential can then only call Bedrock. |

There is no `oauth` block: Bedrock auth is IAM or SSO.

## What it leaves to the workload

| Left out | Why |
|---|---|
| `ENTRYPOINT`, `sbx@1` | The workload owns the launch command and image config. |
| `agent-context` `filename:` | `CLAUDE.md` names the profile, which belongs to the workload. |
| `~/.claude.json` and the base `settings.json` | The `claude` workload seeds them. This kit only merges two keys in. |
| Session volumes, MCP gateway registration | Owned by the workload. |

# pulumi — Pulumi CLI

A mixin kit that installs the [Pulumi](https://www.pulumi.com/) CLI (version and SHA256 pinned) and wires the Pulumi Cloud access token through the sandbox proxy. `pulumi login`, `pulumi up` and `pulumi env` (Pulumi ESC) work without the token ever entering the container. Pairs with any base agent (claude, codex, gemini, ...).

The kit installs Pulumi only. Cloud CLIs, Terraform and OpenTofu are separate kits, so a sandbox composes just what a project needs.

## Usage

Store your Pulumi Cloud access token once on the host (optional; Pulumi with a local or self-managed backend works without it):

```console
printf '%s\n' "$PULUMI_ACCESS_TOKEN" | sbx secret set -g pulumi
```

Then create a sandbox with the kit:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=pulumi" claude
```

Verify inside the sandbox:

```console
pulumi version
pulumi whoami          # with a bound token
```

A credential-free starter lands in `~/runbooks/pulumi-random-ts`:

```console
cd ~/runbooks/pulumi-random-ts
npm install
pulumi stack init dev   # or `pulumi login --local` first, without a bound token
pulumi preview
```

## How auth works

- The kit declares a `pulumi` credential with `proxyManaged: true`. Inside the container, `PULUMI_ACCESS_TOKEN` is set to a placeholder, which is enough for the CLI to consider itself logged in to Pulumi Cloud.
- On any request to `api.pulumi.com`, the sandbox proxy replaces the `Authorization` header with `token <your-real-PAT>`. The real token never enters the sandbox filesystem or environment.
- The credential is `required: false`. Without a bound token, run `pulumi login --local` (or point `pulumi login` at an S3/Azure Blob/GCS backend you have allowed in the network policy).

## Pulumi ESC

`pulumi env` is part of the CLI, so ESC environments (`pulumi env open`, `pulumi env run -- <cmd>`) work through the same proxy-injected token. This is the intended way to hand cloud credentials to a Pulumi program in the sandbox without baking them into a kit.

## Pulumi MCP (optional)

`mcp.ai.pulumi.com` is on the allow-list. To give Claude Code the hosted Pulumi MCP server (registry lookups, resource-schema and code validation, Pulumi Neo), run once inside the sandbox:

```console
claude mcp add --transport http -s user pulumi https://mcp.ai.pulumi.com/mcp
```

Other agents register it through their own MCP configuration.

## Network policy

Beyond the install and Pulumi Cloud hosts, the kit allows the package registries a Pulumi program pulls SDKs from (npm, PyPI, the Go module proxy). Cloud control-plane endpoints for the providers you deploy to are not included; add them per provider and region, for example `sbx policy allow network sts.amazonaws.com`.

## Why the install is pinned

The install hook downloads a specific Pulumi release tarball from GitHub and verifies its SHA256 against a checksum recorded in this spec (same pattern as the `trivy` and `glab` kits) rather than piping `get.pulumi.com` to a shell. To bump the version, update `PULUMI_VERSION` and both per-arch checksums from `https://get.pulumi.com/releases/sdk/pulumi-<version>-checksums.txt`.

## Cleanup

```console
sbx secret rm -g pulumi
```

## Upstream

Maintained at [dirien/infrastructure-sandbox-kit](https://github.com/dirien/infrastructure-sandbox-kit), which also carries a `kind: sandbox` bundle with a prebuilt image and longer notes on [network policy](https://github.com/dirien/infrastructure-sandbox-kit/blob/main/docs/network.md) and [credentials](https://github.com/dirien/infrastructure-sandbox-kit/blob/main/docs/credentials.md).

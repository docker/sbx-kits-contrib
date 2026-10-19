> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# az-devops

A mixin that enables Azure DevOps API access from a sandbox by wiring
`dev.azure.com` and `*.visualstudio.com` requests through the sandbox
credential proxy.

Use it with any built-in agent or agent kit when your workflow needs to
call Azure DevOps REST APIs or MCP endpoints while keeping credentials
managed on the host.

## Prerequisites

- An Azure DevOps Personal Access Token (PAT).
- A sandbox secret `az-devops` available on your host before launching the sandbox.

Create the secret once with a base64-encoded `:<your-PAT>` value.

### Bash (Linux/macOS)

```console
$ sbx secret set -g az-devops "$(printf ':%s' "<your-PAT>" | base64 | tr -d '\n')"
```

### PowerShell

```console
PS C:\> echo "$([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":<your-PAT>")))" | sbx secret set -g az-devops
```

## Usage

Run with any agent:

```console
$ sbx run --kit docker.io/sbx/az-devops:latest <agent>
```

Or directly from this repository:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=az-devops" <agent>
```

Or with a local clone of this repo — a local reference has to be an explicit
path (`./az-devops`, not `az-devops`):

```console
$ sbx run --kit ./az-devops <agent>
```

Kit v3 needs an `sbx` release candidate or nightly build from
[docker/sbx-releases](https://github.com/docker/sbx-releases/releases);
the stable line does not load v3 kits.

## Using the Azure DevOps MCP server

Register the local Azure DevOps MCP server with your agent, replacing
`<organization>` with your Azure DevOps organization name. For agents that read
a project-level `.mcp.json`:

```json
{
   "mcpServers": {
      "azure-devops": {
         "command": "npx",
         "args": ["-y", "@azure-devops/mcp", "<organization>"]
      }
   }
}
```

The first launch downloads the server from npm. Its Azure DevOps requests pass
through the sandbox proxy, which replaces the Basic authorization value with
the host-managed `az-devops` secret.

## How auth works

The kit declares a `com.docker.sandbox/credential@1` capability for the
`az-devops` service whose `apiKey.inject` rules cover the Azure DevOps hosts
(`dev.azure.com`, `*.dev.azure.com`, `mcp.dev.azure.com`,
`vssps.dev.azure.com`, `*.visualstudio.com`). On requests to those hosts the
proxy injects:

- `Authorization: Basic %s`

The `%s` value comes from a secret with the right name `az-devops`, created
in the way explained above.

The credential is managed as secret on the host so tools
inside the sandbox can make calls to Azure DevOps while the real
credential stays under proxy control for outbound requests. The credential
is inject-only: no environment variable, not even a placeholder, is set
inside the sandbox.

## Network policy

The `runtime` allow list is intentionally narrow and currently includes:

- `dev.azure.com`
- `*.dev.azure.com`
- `mcp.dev.azure.com`
- `vssps.dev.azure.com`
- `*.visualstudio.com`
- `dc.services.visualstudio.com`
- `aka.ms`
- `registry.npmjs.org`
- `github.com`
- `release-assets.githubusercontent.com`

The npm and GitHub hosts let `npx` download the Azure DevOps MCP package and its
native dependencies.
`mcp.dev.azure.com` and `vssps.dev.azure.com` are listed explicitly beside
`*.dev.azure.com` because every credential inject domain has to appear
literally in the same phase's allow list.

If your workflow needs additional Azure hosts, fork this kit and extend the
`runtime` allow list of the `com.docker.sandbox/network-policy@1` capability
in `az-devops.yaml`.

## Install behavior

**libsecret ships in the kit's image layer; nothing is apt-installed in
your sandbox.** The Azure DevOps MCP depends on `keytar`, a native addon
that fails to load with
`libsecret-1.so.0: cannot open shared object file` when libsecret is
missing, which it is on the sandbox-templates bases.

`az-devops.dockerfile` runs at build time:

1. apt-installs `libsecret-1-0` on top of the base image and records which
   packages apt had to add (libsecret plus dependencies the base lacks,
   such as glib).
2. Stages the files of exactly those packages, minus documentation.
3. Copies the staged files onto a fresh base and checks with `ldd` that
   every library libsecret needs resolves, so a broken overlay fails the
   build rather than your sandbox.

The kit's `com.docker.sandbox/lifecycle@1` `install` hook also ensures
`/usr/local/share/npm-global/lib` exists by running `mkdir -p` as root:

```sh
mkdir -p /usr/local/share/npm-global/lib
```

## Cleanup

Remove the stored secret when you no longer need it:

```console
$ sbx secret rm -g az-devops
```

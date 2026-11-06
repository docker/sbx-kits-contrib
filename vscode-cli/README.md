> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# vscode-cli

A mixin that installs the standalone
[VS Code CLI](https://code.visualstudio.com/docs/editor/command-line) as
`code` in the sandbox. The CLI is a single binary that doesn't need VS Code
itself.

The kit only installs the CLI and doesn't start anything; you run `code`
when you need it. The network policy also opens the hosts the CLI's
VS Code Server features reach, so commands such as `code tunnel` work from
inside the sandbox. See [Example: `code tunnel`](#example-code-tunnel).

## Usage

Run with any agent:

```console
$ sbx run --kit docker.io/sbx/vscode-cli:latest <agent>
```

Or directly from this repository:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vscode-cli" <agent>
```

Or with a local clone of this repo. A local reference has to be an explicit
path (`./vscode-cli`, not `vscode-cli`):

```console
$ sbx run --kit ./vscode-cli <agent>
```

Kit v3 needs an `sbx` release candidate or nightly build from
[docker/sbx-releases](https://github.com/docker/sbx-releases/releases);
the stable line does not load v3 kits.

Check the install:

```console
$ sbx exec <sandbox-name> -- code --version
```

### Arguments

| Arg | Default | Purpose |
| --- | --- | --- |
| `version` | `1.142.0` | VS Code CLI release built into the overlay. Resolved at build. |

## Example: `code tunnel`

One thing you can do with the CLI is open the sandbox from
[vscode.dev](https://vscode.dev) or a local VS Code through
[Remote - Tunnels](https://code.visualstudio.com/docs/remote/tunnels). The
tunnel is outbound only, so no port has to be published. Open an
interactive session in the sandbox and run `code tunnel`:

```console
$ sbx exec -it <sandbox-name> -- code tunnel
```

The first time, the CLI asks you to:

1. Log in with a GitHub or Microsoft account through a device code prompt.
2. Accept the [VS Code Server license terms](https://aka.ms/vscode-server-license).
3. Name the tunnel.

It then prints a `https://vscode.dev/tunnel/<name>/...` link. Open it in a
browser, or connect from a local VS Code with **Remote-Tunnels: Connect to
Tunnel...**. The login is stored under `~/.vscode/cli` in the sandbox, so
later runs skip it.

The tunnel runs as long as `code tunnel` does. Stop it with `Ctrl+C`, or by
ending the `sbx exec` session.

## How it works

**The CLI ships in the kit's image layer; nothing is downloaded at sandbox
create.** `vscode-cli.dockerfile` runs at build time:

1. Downloads the static (musl) CLI build for the target architecture from
   `update.code.visualstudio.com`. It runs on glibc bases too.
2. Checks that `code --version` exactly matches the pinned release, so a bad
   or mismatched download fails the build rather than your sandbox.
3. Copies the binary to `/usr/local/bin/code` on a scratch overlay.

## Network policy

The `runtime` allow list covers what the CLI's VS Code Server features,
such as `code tunnel`, reach:

| Hosts | Why |
| --- | --- |
| `update.code.visualstudio.com`, `vscode.download.prss.microsoft.com` | The CLI downloads the VS Code Server that matches it on first use. |
| `global.rel.tunnels.api.visualstudio.com`, `*.rel.tunnels.api.visualstudio.com`, `**.devtunnels.ms` | Dev tunnels management API and relay. Relay hosts are cluster scoped. |
| `github.com`, `api.github.com`, `login.microsoftonline.com` | Device code login for GitHub or Microsoft accounts. |
| `marketplace.visualstudio.com`, `*.gallery.vsassets.io`, `*.gallerycdn.vsassets.io` | Installing extensions into the remote VS Code Server. |

VS Code telemetry endpoints are not on the list and stay blocked.

> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# vscode-tunnel

A mixin that starts a [VS Code tunnel](https://code.visualstudio.com/docs/remote/tunnels)
when the sandbox boots, so you can open the sandbox from
[vscode.dev](https://vscode.dev) or a local VS Code without any prompt in
the sandbox. It builds on [`vscode-cli`](../vscode-cli), which has to be in
the same kit set.

The tunnel logs in with your GitHub token through the sandbox credential
proxy. The sandbox only sees a placeholder; the real token stays on the
host.

## Prerequisites

Store a GitHub token on the host under the `vscode-tunnel` service:

```console
$ sbx secret set -g vscode-tunnel -t "$(gh auth token)"
```

The kit uses its own service rather than `github`, which kits such as
`copilot` already claim. The CLI's token check on `api.github.com` still
relies on the `github` secret through sbx's built-in injection, so keep
that one set too.

## Usage

```console
$ sbx run \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vscode-cli" \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vscode-tunnel" \
    <agent>
```

The tunnel is named after the sandbox hostname, cut to 20 characters,
unless you set the `name` arg. Open `https://vscode.dev/tunnel/<name>`, or
connect from a local VS Code with **Remote-Tunnels: Connect to Tunnel...**,
signed in to the same GitHub account.

The tunnel's output goes to `~/.vscode-tunnel.log`:

```console
$ sbx exec <sandbox-name> -- cat /home/agent/.vscode-tunnel.log
```

### Arguments

| Arg | Default | Purpose |
| --- | --- | --- |
| `name` | *(hostname)* | Tunnel name: lowercase letters, digits, and hyphens, at most 20 characters. |

## How it works

At every boot, a background startup hook:

1. Waits up to 60 seconds for `api.github.com/user` to answer through the
   proxy. If it never does, the hook logs that and exits rather than
   leave the CLI waiting on a device code login nobody sees.
2. Runs `code tunnel user login --provider github --access-token proxy-managed`.
   That stores a placeholder token, so the CLI never starts the device
   code login.
3. Runs `code tunnel --accept-server-license-terms --name <name>`.

The CLI sends the placeholder in two places, and the proxy replaces it
with a real token in both:

| Hosts | Header the proxy sets | From |
| --- | --- | --- |
| `global.rel.tunnels.api.visualstudio.com`, `*.rel.tunnels.api.visualstudio.com` | `Authorization: github client_id=01ab8ac9400c4e429b23 <token>`, the form the CLI uses for the dev tunnels API | This kit, from the `vscode-tunnel` secret |
| `api.github.com` | The sandbox's GitHub token. The CLI checks a stored token against `GET /user` before using it, and falls back to the device code login if the check fails. | sbx's built-in GitHub injection, from the `github` secret |

The kit deliberately has no rule for `api.github.com`. Declaring one
replaced the built-in injection there and left the check unauthenticated.
Both secrets have to hold a token for the same GitHub account.

The kit also declares `long-running@1`: VS Code connects through the
tunnel, not through an sbx session, so the sandbox must not auto-stop when
the last sbx session ends.

## Composing with other kits

Kit v3 allows one owner per credential service and phase. The
`vscode-tunnel` service keeps this kit clear of kits that claim `github`,
such as `copilot`, `opencode`, or `github-clone`.

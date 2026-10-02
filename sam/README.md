> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# SAM

A mixin that puts a [SAM](https://github.com/google/sam) mesh node inside the
sandbox, next to the agent, and registers it with the agent as an MCP server
named `sam-mesh`. The agent reaches the mesh's services by name, under the
mesh's policy and audit, and the mesh admin can revoke access without touching
the sandbox. It pairs with any agent workload.

## Usage

You need a SAM control plane reachable over HTTPS on a hostname, and a
single-use bootstrap token for the sandbox. [Your own
mesh](https://sam-mesh.dev/docs/getting-started/your-own-mesh/) covers both.

Put the two values in an args file, one `name=value` per line. Keep the token
in the file: a `--kit-arg` value lands in shell history and `ps` output.

```console
printf 'controlPlane=<host>\ntoken=<bootstrap token>\n' > sam-kit-args
```

Run it with an agent workload, from its published OCI artifact on Docker Hub:

```console
sbx run docker/sbx-kit-claude --kit "docker.io/docker/sbx-kit-sam:latest" --kit-args-file sam-kit-args
```

Or from a git URL targeting this repo:

```console
sbx run docker/sbx-kit-claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=sam" --kit-args-file sam-kit-args
```

For local development, point `--kit` at this directory:

```console
sbx run docker/sbx-kit-claude --kit ./sam/ --kit-args-file sam-kit-args
```

`sbx` asks once to approve one network allow entry: the control plane host.

To give the node [labels](#labels), add a `labels` line with comma-separated
`key=value` pairs:

```console
printf 'controlPlane=<host>\ntoken=<bootstrap token>\nlabels=site=laptop,team=ml\n' > sam-kit-args
```

## Labels

A label is a `key=value` pair that describes a node, for example `site=laptop`
or `team=ml`. SAM defines no fixed keys, so the mesh admin picks them. The node
declares its labels when it enrolls, on the sandbox's first boot. Then the
control plane writes each label into the node's credential, but only if the
token's role permits that label in `allowed_labels`. A label the role does not
permit makes the enrollment fail, and `~/.sam/sam-node.log` says why.

Because the control plane attests the labels, a service can trust them. For
example, a tool can accept calls only from nodes labelled `team=ml`, so the
sandbox's agent reaches that tool only when the sandbox has that label.

See [Labels](https://sam-mesh.dev/docs/concepts/authorization/#labels) in the
SAM documentation for the policy syntax.

## Network policy

The kit allows one host at runtime: the control plane named by `controlPlane`.
The node reaches the rest of the mesh through that same host, over WSS on port
443. So the kit adds no install-phase hosts, and the sandbox's network policy
stays the boundary for everything else.

## How it works

- **The binary comes from SAM's release image.** `sam.dockerfile` copies
  `sam-node` out of `ghcr.io/google/sam-node`, pinned by the `samVersion` build
  arg, into a `FROM scratch` overlay. Nothing is downloaded at sandbox create.
- **One startup hook does everything.** `files/usr/local/lib/sam/startup.sh` runs on every boot
  as the agent. It registers `sam-mesh` with whichever agents the workload
  ships (Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Devin, Cursor,
  Copilot, Droid, Kiro), enrolls the node on the first boot, then starts it.
  Registering at startup rather than install means an agent kit that seeds its
  config at install cannot drop the entry.
- **Agents are found through PID 1's `PATH`.** Hooks run with a stock `PATH`,
  while agent kits install their CLIs under the home directory or npm's prefix.
  PID 1 keeps the image's environment, so the hook reads `PATH` from there.
- **A node that fails does not block the sandbox.** The hook logs to
  `~/.sam/hooks.log` and exits 0; `~/.sam/sam-node.log` says why.
- **The token is single-use.** The first boot spends it and the node keeps its
  identity in `~/.sam`, so restarts need nothing. A recreated sandbox needs a
  fresh token. It is an arg rather than a credential because it travels in the
  enrollment request body, where the proxy cannot inject it.

> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit v3 specification](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md).

# devin-enterprise-mixin

The overlay form of [`devin-enterprise`](../devin-enterprise): the same
pinned Devin CLI, enterprise wrapper, org argument, enterprise network
policy, configuration seed and MCP/enterprise-host startup hooks. Layer it
onto a shell workload and run `devin`.

## Usage

```console
sbx run <shell-workload> --kit docker.io/sbx/devin-enterprise-mixin:latest --kit-arg devin-enterprise-mixin.org=acme .
```

Or from the v3 branch:

```console
sbx run <shell-workload> --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v3&dir=devin-enterprise-mixin" --kit-arg devin-enterprise-mixin.org=acme .
```

Or from a local checkout:

```console
sbx run <shell-workload> --kit ./devin-enterprise-mixin --kit-arg devin-enterprise-mixin.org=acme .
```

`<shell-workload>` must be a v3 `kind: workload` kit reference whose
entrypoint opens a shell. The built-in `shell` agent does not currently
supply a workload kit for v3 compositions.

Inside the shell, launch:

```console
devin --permission-mode dangerous --respect-workspace-trust=false
```

The shell workload retains its entrypoint, user and working directory. Its
apt mirrors/cache-refresh hook and Docker-in-Docker request stay with it.
The mixin declares no `sbx@1` or session launch capabilities and contributes
context without choosing the workload's `AGENTS.md` destination. Both shapes
provide `devin`, so use one at a time rather than composing them together.

## How auth works

The required `org` argument is your deployment's slug: `acme` for
`acme.devinenterprise.com`. A root startup hook pins
`/etc/devin/system.json` to that enterprise host on every boot. The first
launch prints an enterprise sign-in URL; open it, sign in, and paste the
code back into the terminal.

The `devin` wrapper keeps the base Devin kit's credential-state checks,
empty-key cleanup and post-login validation. `devin-cli` is the underlying
CLI. The wrapper omits the proxy-sentinel securing step because enterprise
credential handoff still does not fire for enterprise hosts; the report is
[docker/sbx-releases#683](https://github.com/docker/sbx-releases/issues/683),
closed after this kit supplied a workaround.
No `credential@1` capability is declared.

**Trade-off:** the durable key remains readable by the agent in
`~/.local/share/devin/credentials.toml`. Credentials survive sandbox
stop/start, but a recreated sandbox signs in again. Switch to managed
credentials once enterprise handoff works.

The same config seed as the base kit disables background updates when the
settings file is absent; an existing settings file is preserved.
The MCP gateway uses the same startup registration hook. Runtime egress
allows enterprise API/model hosts, `windsurf.com`, `server.codeium.com` for
login-time verification, `unleash.codeium.com` for feature flags, and the
Devin update hosts. GitHub, npm and crash-reporting hosts require additional
grants.

## Version and build

The `version` build argument defaults to `3000.10.31`, matching the v3 Devin
kit. The recipe downloads Cognition's versioned setup script and checks that
the installed binary reports the requested release. Both enterprise shapes
provide `devin` at that version and must keep their defaults in sync.

The v2 kit reused `docker.io/sbx/devin-image:latest`. These v3 recipes carry
the same installation as the existing Devin workload/mixin pair, including
the `devin-cli` rename, so they do not depend on the legacy image publisher.
The workload retains its underlying `docker/sandbox-templates:shell-docker`
base. The mixin stages the whole CLI prefix into a scratch overlay, with
`/home` owned by root and `/home/agent` by uid 1000.

The wrapper copies in both enterprise directories must stay byte-identical;
each kit directory is its own build context.

```console
cd devin-enterprise-mixin
docker buildx build . -f devin-enterprise-mixin.yaml --output type=cacheonly
```

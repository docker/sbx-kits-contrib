> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit v3 specification](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md).

# devin-enterprise

[Devin CLI](https://devin.ai) for a Devin Enterprise deployment
(`<org>.devinenterprise.com`), as a standalone v3 workload. Ported from
[#351](https://github.com/docker/sbx-kits-contrib/pull/351) with the same
enterprise auth behavior. The sibling [`devin`](../devin) targets SaaS;
[`devin-enterprise-mixin`](../devin-enterprise-mixin) layers this enterprise
CLI onto a shell workload.

## Usage

```console
sbx run docker.io/sbx/devin-enterprise:latest --kit-arg org=acme .
```

Or from the v3 branch:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#ref=v3&dir=devin-enterprise" --kit-arg org=acme .
```

Or from a local checkout:

```console
sbx run ./devin-enterprise --kit-arg org=acme .
```

The entrypoint uses the same `--permission-mode dangerous` and
`--respect-workspace-trust=false` arguments as the base Devin kit.

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

The workload retains the base image's Docker-in-Docker request and apt
mirror grants/cache-refresh hook. Its launch command comes from
[`devin-enterprise.dockerfile`](./devin-enterprise.dockerfile); runtime policy
and startup hooks are in [`devin-enterprise.yaml`](./devin-enterprise.yaml).

```console
cd devin-enterprise
docker buildx build . -f devin-enterprise.yaml --output type=cacheonly
```

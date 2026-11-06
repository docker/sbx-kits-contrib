> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# go

A mixin kit (`kind: mixin`) that installs a pinned, checksum-verified [Go](https://go.dev/) toolchain and the [`gopls`](https://go.dev/gopls) language server, and declares the network access Go needs to download modules.

## Usage

```console
sbx run --kit "docker.io/sbx/go:latest" claude
agent@...$ go version
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=go" claude
```

Or with a local clone:

```console
sbx run --kit ./go/ claude
```

`go`, `gofmt` and `gopls` are on `PATH` from the moment the sandbox exists, and
so is `~/go/bin`, where `go install` puts binaries. Agents with LSP support
pick up `gopls` on their own; any agent can call it from the shell.

## How the install works

Go arrives in the kit's **layers**, not from a hook at sandbox create.
`go.dockerfile` downloads the pinned release tarball at build time, checks it
against a per-architecture SHA256, and unpacks it to `/opt/go`. It then builds
`gopls` from its pinned module version with that toolchain, so its dependencies
are verified against `sum.golang.org`.

The build fails unless the overlay works on a fresh base, as the agent user,
with the network off: `go` must report the pinned version, compile and run a
program, and `gopls check` must pass on it.

The toolchain goes to `/opt/go` rather than `/usr/local/go` because the
`shell-docker` templates already ship a Go there, and a layer cannot delete the
base's files. Installing over it would mix two releases' standard libraries
once the versions differ. Links in `/usr/local/bin` put this kit's Go first on
every base's `PATH`. On a base without a C compiler, such as `dhi.io/claude`,
`go` turns cgo off by itself and pure-Go code builds normally.

## Versioning

The kit installs Go 1.27.3 and gopls 0.24.0. To update Go, change the `version`
default in `go.yaml` and both SHA256 values in `go.dockerfile`, from
<https://go.dev/dl/?mode=json>. To update gopls, change `gopls_version` in
`go.yaml`; its checksums come from `sum.golang.org`, so there is no digest to
edit. The build checks that both binaries report the pinned versions.

## Network policy

The kit allows `proxy.golang.org` and `sum.golang.org` in the **runtime** phase
only, plus `GET` and `HEAD` on `storage.googleapis.com/proxy-golang-org-prod/**`.

The proxy answers large modules (`github.com/aws/aws-sdk-go`,
`google.golang.org/api`) and every toolchain download with a redirect into that
Cloud Storage bucket. Without it, `go mod download` fails on those modules
under a deny-by-default policy. The host serves every public bucket on Google
Cloud, so the grant is bounded to the one bucket the proxy uses.

There is no install phase: the builder fetches the toolchain, and a policy that
governs sandboxes does not govern the builder. VCS hosts such as `github.com`
are not allowed, since public modules come through the proxy. For private
modules, set `GOPRIVATE` and add the VCS host to the `runtime` allow list in a
fork, along with credentials for it.

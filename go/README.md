# go

A mixin that installs the **[Go](https://go.dev)** toolchain (`go`, `gofmt`)
into the sandbox, so the agent can build, test, and run Go code. It composes
onto any agent: it doesn't replace the base image, it just adds the toolchain.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=go" claude ~/my-project
$ sbx run --kit ./go/ claude ~/my-project
```

`claude` is just an example; pair the mixin with whatever agent you run.

Verify inside the sandbox:

```console
$ go version
$ go build ./...
```

## How it works

The install hook downloads the official Go release tarball from `go.dev/dl`
(version and per-arch SHA256 pinned in `spec.yaml`), verifies the digest,
extracts it to `/usr/local/go`, and symlinks `go` and `gofmt` into
`/usr/local/bin` so they're on `PATH` for every shell. A second hook adds
`/usr/local/go/bin` and `~/go/bin` (where `go install` drops binaries) to
`PATH` in `~/.bashrc`.

Module fetches use Go's defaults: the proxy at `proxy.golang.org` with checksum
verification via `sum.golang.org`. Those two hosts plus the install hosts
(`go.dev`, `dl.google.com`) are the kit's entire network contract. Public
modules are served through the proxy, so VCS hosts like `github.com` don't need
allowing, unless you set `GOPROXY=direct` or pull private modules, in which
case add those hosts to `network.allowedDomains` in a forked copy.

To upgrade Go, change `GO_VERSION` and the two SHA256 values in `spec.yaml`
(sourced from <https://go.dev/dl/?mode=json>).

## Related

- [Go downloads](https://go.dev/dl/)
- [Go module proxy](https://proxy.golang.org)

## Go toolchain

Go is installed at `/opt/go` with `go`, `gofmt` and the `gopls` language
server on `PATH`. Run `go version` to see the release. Binaries from
`go install` land in `~/go/bin`, which is also on `PATH`.

Use `gopls` for type-aware questions instead of text search, for example
`gopls references file.go:LINE:COL`, `gopls definition file.go:LINE:COL`,
`gopls check file.go` and `gopls rename -w file.go:LINE:COL NewName`. Run `go vet ./...` and `go test ./...` before calling Go work
done.

Modules download through the default proxy (`proxy.golang.org`) and are
verified against the checksum database (`sum.golang.org`). Do not set
`GOPROXY=direct`, `GONOSUMDB` or `GOFLAGS=-insecure` to work around a failed
download: VCS hosts such as `github.com` are not reachable from this sandbox,
so direct fetches fail. If a module is private or missing from the proxy,
report that to the user instead.

If `go.mod` asks for a newer Go than the installed one, `go` downloads the
matching toolchain through the same proxy on first use (`GOTOOLCHAIN=auto`).

cgo needs a C compiler. When the image has none, `go` builds with
`CGO_ENABLED=0`, which works for pure-Go code.

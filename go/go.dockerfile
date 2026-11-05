# syntax=docker/dockerfile:1
# The Go toolchain as an overlay.
#
# Everything this kit installs is static content: one official release
# tarball, pinned by version and per-arch SHA256. So it is fetched and checked
# here, at image build, and shipped as layers. Nothing is downloaded into the
# sandbox at create, which is why go.yaml declares no install phase at all.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN, handed in by the frontend from the descriptor's `version` arg
# (buildArg: GO_VERSION), which go.yaml also expands into `provides` and into
# its own `version:`, so the release is stated in exactly one place.
#
# No default on purpose: the descriptor always supplies one, and an empty
# fallback would build a nonsense URL. The guard below fails instead.
#
# The digests are pinned to that release, so an installer-supplied `version`
# fails the checksum rather than installing quietly under a descriptor that
# claims something else. Bumping Go is the arg's default in go.yaml plus both
# digests here, with the values from https://go.dev/dl/?mode=json.
ARG GO_VERSION
ARG TARGETARCH

USER root

# TARGETARCH rather than `dpkg --print-architecture`: buildx sets it per
# platform, so a multi-platform build resolves each leg to its own tarball.
#
# Fetched from dl.google.com directly, which is where go.dev/dl/ redirects.
#
# Unpacked to /opt/go, NOT /usr/local/go. The docker/sandbox-templates bases
# already ship a Go there, and a layer cannot delete the base's files: landing
# on top would leave a GOROOT holding two releases' standard libraries as soon
# as the pins differ, and stale .go files in a std package break compiles.
# /opt/go is a path no sandbox base uses, so the kit's toolchain is whole on
# every base and the base's own copy is simply left unused.
RUN <<'EOF'
set -eu
[ -n "${GO_VERSION}" ] || { echo "GO_VERSION must be set" >&2; exit 1; }
case "${TARGETARCH}" in
  amd64) sha256=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40 ;;
  arm64) sha256=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/go.tgz \
  "https://dl.google.com/go/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz"
echo "${sha256}  /tmp/go.tgz" | sha256sum -c -
mkdir -p /out/opt /out/usr/local/bin
tar -C /out/opt -xzf /tmp/go.tgz
rm /tmp/go.tgz
# The links are what put this Go first. /usr/local/bin precedes /usr/bin
# (where the DHI shell base keeps its Debian Go) on every base's PATH, and on
# the docker/sandbox-templates bases these replace the links to their own
# /usr/local/go. Relative, so they resolve inside this overlay's own layers
# whatever base it lands on (SPEC-v3 section 10). The toolchain follows the
# link back to /opt/go/bin and finds its GOROOT from there.
ln -s ../../../opt/go/bin/go /out/usr/local/bin/go
ln -s ../../../opt/go/bin/gofmt /out/usr/local/bin/gofmt
EOF

# gopls, the Go language server. Agents with built-in LSP support (OpenCode,
# Claude Code's gopls plugin) start it on their own when it is on PATH,
# and that is what gives them type-aware navigation and diagnostics instead of
# grep. Built here from the pinned module with the toolchain above, so its
# go.sum is verified against sum.golang.org at build and nothing is fetched
# in the sandbox. CGO off keeps the binary independent of the base's libc.
ARG GOPLS_VERSION
RUN <<'EOF'
set -eu
[ -n "${GOPLS_VERSION}" ] || { echo "GOPLS_VERSION must be set" >&2; exit 1; }
export GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS=-trimpath \
  GOPATH=/tmp/gopath GOCACHE=/tmp/gocache GOBIN=/out/usr/local/bin
/out/opt/go/bin/go install "golang.org/x/tools/gopls@v${GOPLS_VERSION}"
rm -rf /tmp/gopath /tmp/gocache
chown -R 0:0 /out/opt /out/usr
EOF

# THE GATE. The overlay is copied onto a fresh base and exercised as the
# agent user with no network, the way the composed sandbox will run it. That
# catches what checking the build stage would hide: a link that only resolved
# in the stage that made it, or a toolchain that needs to download something
# before it can compile.
#
# It goes past `go version`: it compiles and runs a program, so the standard
# library, the compiler and the linker are all proven present. The version is
# compared as a whole field so 1.27.3 does not match 1.27.30.
FROM ${BASE_IMAGE} AS verified
USER root
COPY --from=build /out /out
COPY --from=build /out /
USER agent
WORKDIR /tmp/gate
ARG GO_VERSION
ARG GOPLS_VERSION
RUN --network=none <<'EOF'
set -eu
command -v go
reported="$(go version)"
echo "go version: ${reported}"
printf '%s\n' "${reported}" | tr ' ' '\n' | grep -Fxq "go${GO_VERSION}" || {
  echo "pin mismatch: descriptor says ${GO_VERSION}, toolchain reports '${reported}'" >&2
  exit 1
}
# This stage's base ships its own Go at /usr/local/go, so these two lines are
# the proof that the kit's toolchain wins on a base that already has one.
[ "$(readlink -f "$(command -v go)")" = /opt/go/bin/go ] || { echo "go resolves to $(readlink -f "$(command -v go)")" >&2; exit 1; }
[ "$(go env GOROOT)" = /opt/go ] || { echo "unexpected GOROOT: $(go env GOROOT)" >&2; exit 1; }
export GOCACHE=/tmp/gate/cache GOPATH=/tmp/gate/gopath GOTOOLCHAIN=local
cat > main.go <<'GO'
package main

import "fmt"

func main() { fmt.Println("go kit ok") }
GO
[ -z "$(gofmt -l main.go)" ]
go mod init gate >/dev/null 2>&1
[ "$(go run .)" = "go kit ok" ]
# gopls: the pinned version, and a real analysis of the module above, so the
# server is proven to load packages offline and not only to start.
gopls version | tee /dev/stderr | grep -q "golang.org/x/tools/gopls v${GOPLS_VERSION}\$" || {
  echo "gopls pin mismatch: expected v${GOPLS_VERSION}" >&2; exit 1; }
gopls check main.go
cd / && rm -rf /tmp/gate/*
EOF

# The overlay: the toolchain under /opt/go, and go, gofmt and gopls in
# /usr/local/bin. Nothing under /home, which may be a mounted volume on the
# composed base. No ENTRYPOINT: the base workload's launch command stays.
#
# PATH gains ~/go/bin, where `go install` puts binaries. A mixin's PATH merges
# into the composed image by appending the elements the recipe added
# (SPEC-v3 section 10), so this reaches the agent process itself and not only
# login shells, which a profile.d or ~/.bashrc line would not.
FROM scratch
COPY --from=verified /out /
ENV PATH=/home/agent/go/bin

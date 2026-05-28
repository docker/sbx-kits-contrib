# sbx-kits-contrib

Community-contributed kits for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

Each top-level directory is a **kit** — a declarative artifact containing a `spec.yaml` and optional `files/` directory that extends sandbox agents with additional capabilities.

## Documentation

- [Kits overview](https://docs.docker.com/ai/sandboxes/customize/kits/) — what kits are and how to use them
- [Kit examples](https://docs.docker.com/ai/sandboxes/customize/kit-examples/) — reference examples for common kit patterns
- [Build your own agent kit](https://docs.docker.com/ai/sandboxes/customize/build-an-agent/) — step-by-step tutorial using the `amp` kit in this repo

Contributing a kit or a fix? Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) first — this repo enforces verified commit signatures, so you'll need GPG or SSH signing set up before your PR can be merged.

> [!NOTE]
> Kits are experimental. The kit file format, CLI commands, and experience
> for creating, loading, and managing kits are subject to change as the
> feature evolves. Bugs and feature requests for the kits in this repo
> belong in [its issue tracker](https://github.com/docker/sbx-kits-contrib/issues);
> general feedback on the kit feature itself goes to
> [docker/sbx-releases](https://github.com/docker/sbx-releases).

## Using a kit

Kits are passed to `sbx run` (or `sbx create`) via `--kit`. The flag accepts a local path, an OCI registry reference, a ZIP archive, or a `git+...` URL.

The most common form is a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=code-server" claude
```

The fragment after `#` accepts two parameters, both optional:

| Parameter | Purpose | Example |
| --- | --- | --- |
| `dir` | Subdirectory inside the repo containing the kit | `#dir=code-server` |
| `ref` | Git ref to check out — branch, tag, or commit SHA | `#ref=v1.0.0` |

Combine them with `&`:

```console
# Pin to a tag — the recommended form for production use
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v0.2.0&dir=code-server" claude

# Track a branch (less stable; the kit may change under you)
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=main&dir=code-server" claude

# Pin to an exact commit SHA — fully reproducible
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=abc1234&dir=code-server" claude
```

Without `ref`, sbx clones the default branch shallowly. With a branch or tag, sbx clones at that ref shallowly. With a commit SHA, sbx clones fully and checks out the commit.

You can also use SSH instead of HTTPS for private repos:

```console
$ sbx run --kit "git+ssh://git@github.com/docker/sbx-kits-contrib.git#dir=code-server" claude
```

For local development, point `--kit` at a directory:

```console
$ sbx run --kit ./code-server/ claude
```

## Repository Structure

```
sbx-kits-contrib/
├── spec/          # Kit artifact types, loading, and validation (importable library)
├── tck/           # Technology Compatibility Kit — test suite using testcontainers-go
├── pi/            # Pi coding agent kit
├── nanobot/       # Nanobot assistant kit
├── openclaw/      # OpenClaw assistant kit
├── nanoclaw/      # NanoClaw WhatsApp bridge kit
└── .github/       # CI workflows
```

## Adding a New Kit

1. Create a directory at the repo root with your kit name (lowercase, alphanumeric + hyphens):

```
my-kit/
├── spec.yaml
├── my_kit_tck_test.go
└── files/
    └── home/          # Files copied to /home/agent/ in the container
        └── config.json
```

2. Write your `spec.yaml`:

```yaml
schemaVersion: "1"
kind: mixin
name: my-kit
displayName: My Kit
description: "Short description of what this kit does"

network:
  allowedDomains:
    - example.com
  deniedDomains:
    - tracker.example.com

environment:
  variables:
    MY_CONFIG: "/home/agent/config.json"

commands:
  install:
    - command: "pip install my-tool"
      user: "1000"
      description: Install my-tool
  startup:
    - command: ["my-tool", "serve"]
      user: "1000"
      background: true
      description: Start my-tool
```

3. Write a TCK test file (`my_kit_tck_test.go`):

```go
package my_kit_test

import (
    "testing"

    "github.com/docker/sbx-kits-contrib/tck"
    "github.com/stretchr/testify/require"
)

func TestMyKitTCK(t *testing.T) {
    suite, err := tck.NewSuiteFromDir(".")
    require.NoError(t, err)
    suite.RunAll(t)
}
```

4. Run the TCK locally:

```bash
cd my-kit
go test -v -count=1 -timeout 10m ./...
```

## TCK Test Coverage

The TCK validates your kit automatically:

- **Validation** — `spec.yaml` parses correctly with required fields
- **Network policy** — allowed domains and service auth are well-formed
- **Credential policy** — credential sources are properly defined
- **Commands** — install/startup commands are well-formed
- **Environment variables** — declared env vars are set in the container
- **Container files** — files from `files/` are injected at the correct paths
- **Security** — tmpfs mounts (e.g., `/run/secrets`) are present

## End-to-end (e2e) Tests

The default TCK runs every kit assertion against a fabricated `testcontainers-go` container — fast, deterministic, no `sbx` needed. The optional e2e layer goes further: it boots a **real `sbx` sandbox** from the kit, then verifies the kit's content actually landed inside the running container. It catches things the default TCK can't — install commands that fail under the non-root agent user, `${WORKDIR}` placeholders that resolve differently than expected, agent-kit name mismatches, or memory blocks the engine never writes out.

### What the e2e test does

`tck/e2e_test.go` (build-tag `e2e`, function `TestE2ECreateSandbox`) drives one kit per run:

1. Loads the kit at `$KIT_UNDER_TEST` and picks the agent argument — kit name for `kind: agent`, `claude` for `kind: mixin`.
2. Runs `sbx create --kit <kit> --name <unique> <agent> <tmpdir>` against a temporary workspace.
3. Verifies, via `sbx exec`, that the running sandbox contains:
   - every `environment.variables` entry,
   - every file under `files/home` and every `commands.initFiles` (with `${WORKDIR}` resolved to `/home/agent/workspace`, the real sandbox workdir),
   - every declared `tmpfs` mount (plus the implicit `/run/secrets`),
   - the rendered memory file — `Manifest.AIFilename` for agent kits (inlined memory) or `kits-memory/<kit-name>.md` for mixin kits.
4. Cleans up with `sbx rm -f <name>`.

### Prerequisites

- `sbx` on `PATH`. Install the latest release from [`docker/sbx-releases`](https://github.com/docker/sbx-releases/releases/latest).
- An authenticated `sbx` session against Docker Hub. The non-interactive form:
  ```bash
  printf '%s' "$DOCKERHUB_TOKEN" | sbx login --username "$DOCKERHUB_USERNAME" --password-stdin
  ```
- Linux with `/dev/kvm` accessible (for the sailor microVM). On Linux runners and most workstations this is already the case; in CI the workflow does `sudo chmod 666 /dev/kvm` to relax permissions.

### Running locally

The test is hidden behind the `e2e` build tag so kit authors running `go test ./...` see no behavior change. Opt in explicitly:

```bash
# From the repo root, pointing at one kit
KIT_UNDER_TEST="$PWD/code-server" \
  go test -tags=e2e -v -timeout 25m -count=1 -run TestE2ECreateSandbox ./tck/...
```

`KIT_UNDER_TEST` must be an **absolute path**: `go test` runs each binary with its working directory set to the package directory (`./tck/`), so a relative path resolves against `./tck/`, not the repo root. Prefix with `$PWD` (or use `realpath`) when calling from the repo root.

To run every kit, use `find` (works in both bash and zsh; raw globs error under zsh's default `nomatch` when no `.yml` kits exist):

```bash
for spec in $(find "$PWD" -mindepth 2 -maxdepth 2 \( -name spec.yaml -o -name spec.yml \)); do
  KIT_UNDER_TEST="$(dirname "$spec")" \
    go test -tags=e2e -v -timeout 25m -count=1 -run TestE2ECreateSandbox ./tck/...
done
```

Each subtest (`env`, `files/<path>`, `tmpfs/<path>`, `memory`) reports independently, so a failure pinpoints which piece of kit content didn't make it into the container.

### Running in CI

The `test-kit-e2e` job in [`.github/workflows/tck.yml`](.github/workflows/tck.yml) runs alongside the default `test-kit` job. It downloads the latest `sbx` release, signs in to Docker Hub using `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` repo secrets, then runs the e2e test once per detected kit. The job is skipped on fork PRs because the secrets aren't exposed there.

## Extending a Parent Agent

By default, mixins use the `shell` template image. To extend a specific agent (e.g., Claude, Gemini), add the `extends` field:

```yaml
schemaVersion: "1"
kind: mixin
name: my-claude-extension
extends: claude
# ...
```

The TCK resolves the parent's template image automatically for well-known agents (shell, claude, codex, copilot, cursor, docker-agent, droid, gemini, kiro, opencode). For other parents, use `WithImage`:

```go
suite, err := tck.NewSuiteFromDir(".", tck.WithImage("my-custom/template:latest"))
```

## Packages

### `spec` — Kit Artifact Format

Importable library for parsing, validating, and working with kit artifacts:

```go
import "github.com/docker/sbx-kits-contrib/spec"

artifact, err := spec.LoadFromDirectory("./my-kit")
```

### `tck` — Technology Compatibility Kit

Test framework that validates kit artifacts against real containers:

```go
import "github.com/docker/sbx-kits-contrib/tck"

suite, err := tck.NewSuiteFromDir(".")
suite.RunAll(t)
```

## CI

Pull requests trigger TCK tests automatically:

- **Kit changes**: only the modified kit is tested
- **TCK/spec changes**: all kits are tested
- Each kit runs in a separate CI runner on Linux
- The optional `test-kit-e2e` job exercises every detected kit against a real `sbx` CLI — see [End-to-end (e2e) Tests](#end-to-end-e2e-tests). Skipped on fork PRs (no Docker Hub secrets).

## Prerequisites

- Go 1.23+
- Docker (for container-based TCK tests)

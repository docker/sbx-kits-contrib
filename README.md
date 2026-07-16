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
├── <kit-name>/    # Individual kits (amp, code-server, pi, etc.)
└── .github/       # CI workflows
```

## Adding a New Kit

1. Create a directory at the repo root with your kit name (lowercase, alphanumeric + hyphens):

```
my-kit/
├── spec.yaml
└── files/
    └── home/          # Files copied to /home/agent/ in the container
        └── config.json
```

There's no per-kit test file to write — the shared `TestKitTCK` in `tck/kit_test.go` reads a `KIT` env var pointing at the kit directory and runs the full TCK suite against it.

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

3. Run the TCK locally — from inside the kit's directory:

```bash
cd my-kit
../scripts/test-kit.sh
```

Or from the repo root, naming the kit:

```bash
./scripts/test-kit.sh my-kit
```

Extra flags are forwarded to `go test`, so `../scripts/test-kit.sh -v -run …`
works as expected. If you'd rather invoke `go test` directly, the equivalent is:

```bash
KIT="$PWD/my-kit" go test -v -count=1 -timeout 10m -run TestKitTCK ./tck/...
```

`KIT` must be an absolute path because `go test` runs the binary with its
working directory set to the package directory (`./tck/`).

**Windows users**: the wrapper is a bash script — run it from **Git Bash** (ships with Git for Windows) or **WSL**, not from `cmd.exe` or PowerShell. If you'd rather skip the wrapper, the direct `go test` invocation above works in PowerShell too — just substitute `$env:KIT = "$PWD\my-kit"` for the env-var syntax.

## Declare every domain your kit needs

A kit's `network.allowedDomains` is its **complete** outbound network contract. The CI e2e job runs with a `deny-all` default policy, so anything not in your `allowedDomains` is blocked at request time — and any failed request inside an install hook surfaces as `sbx create` failing.

The non-obvious trap is **package managers refreshing every configured source**, not just the one you added:

- `apt-get update` re-fetches metadata for every file in `/etc/apt/sources.list[.d/]` — including sources the base template added. If *any* of those returns non-2xx, `apt-get` exits non-zero even if the package you want is in a different source. For kits built on `shell-docker` / `*-docker` templates that means `download.docker.com` (Docker's apt repo, pre-added by the template) needs to be in your `allowedDomains` even if you're only installing something from Ubuntu's main archive.
- Ubuntu hosts amd64 packages on `archive.ubuntu.com` + `security.ubuntu.com` and arm64 packages on `ports.ubuntu.com`. List all three for cross-arch coverage; CI is amd64, your Mac is likely arm64.
- `npm install`, `pip install`, `cargo`, `go get`, etc. each have their own registry/mirror hosts — declare them too.

The fastest way to find out what your install hooks reach is to run the e2e wrapper. It applies a `deny-all` global policy on a scoped daemon (`--app-name sbx-kits-contrib-tck`) for you, then runs `TestE2EKit` — so you get the network contract *and* every other e2e assertion from one command:

```bash
./scripts/test-kit-e2e.sh my-kit
```

On failure, dump what the proxy blocked:

```bash
APP=sbx-kits-contrib-tck
sbx --app-name $APP ls                            # find the tck-e2e-* sandbox
sbx --app-name $APP policy log tck-e2e-<short-uuid>
```

Every `Blocked requests` row is a domain your install or startup hook reached for under `deny-all`. Add the host (column `HOST`, e.g. `download.docker.com:443`) to `allowedDomains` and re-run until the block list is empty.

If you'd rather hand-build a probe sandbox without invoking the test harness (useful when iterating on install scripts without touching the spec), the manual flow is:

```bash
APP=sbx-kits-contrib-tck
sbx --app-name $APP policy init deny-all
sbx --app-name $APP create --name probe-my-kit --kit "$PWD/my-kit" <agent> /tmp/sbx-kit-debug || true
sbx --app-name $APP policy log probe-my-kit
sbx --app-name $APP reset --force                 # wipe the scoped daemon
```

Same `--app-name` keeps the state isolated from your main sbx and lets `sbx --app-name $APP reset --force` clean up without touching your day-to-day setup.

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
- The scoped daemon must be logged in to Docker Hub once per machine. Interactive form:
  ```bash
  sbx --app-name sbx-kits-contrib-tck login
  ```
  Non-interactive (matches CI):
  ```bash
  printf '%s' "$DOCKERHUB_TOKEN" | sbx --app-name sbx-kits-contrib-tck login --username "$DOCKERHUB_USERNAME" --password-stdin
  ```
- Linux with `/dev/kvm` accessible (for the sailor microVM). On Linux runners and most workstations this is already the case; in CI the workflow does `sudo chmod 666 /dev/kvm` to relax permissions.

### Running locally

The test is hidden behind the `e2e` build tag so kit authors running `go test ./...` see no behavior change. Opt in via the wrapper — the script handles the `--app-name` scoping and `deny-all` policy for you:

```bash
# From inside the kit's directory:
cd my-kit
../scripts/test-kit-e2e.sh

# Or from the repo root, naming the kit:
./scripts/test-kit-e2e.sh my-kit
```

Idempotent and non-interactive. Re-running converges on the same state — set the same default policy, run the test, leave the scoped daemon as it was. Overrides via env: `APP_NAME` (default `sbx-kits-contrib-tck`) and `POLICY` (default `deny-all`; set `POLICY=` to skip the policy step). Extra positional flags are forwarded to `go test`.

If you'd rather drop to `go test` directly (note: this skips the policy-set step, so you need to apply `deny-all` yourself or the network contract isn't tested):

```bash
KIT_UNDER_TEST="$PWD/my-kit" \
  go test -tags=e2e -v -timeout 25m -count=1 -run TestE2ECreateSandbox ./tck/...
```

`KIT_UNDER_TEST` must be an **absolute path**: `go test` runs each binary with its working directory set to the package directory (`./tck/`), so a relative path resolves against `./tck/`, not the repo root.

To run every kit locally:

```bash
for spec in $(find "$PWD" -mindepth 2 -maxdepth 2 \( -name spec.yaml -o -name spec.yml \)); do
  ./scripts/test-kit-e2e.sh "$(dirname "$spec")"
done
```

Each subtest (`env`, `files/<path>`, `tmpfs/<path>`, `memory`) reports independently, so a failure pinpoints which piece of kit content didn't make it into the container.

### Running in CI

The e2e legs in [`.github/workflows/tck.yml`](.github/workflows/tck.yml) run alongside the default `test-kit` job, via the reusable [`.github/workflows/e2e.yml`](.github/workflows/e2e.yml). Each signs in to Docker Hub using `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` repo secrets, then runs the e2e test once per detected kit — against two `sbx` channels:

- **`e2e-release`** downloads the latest tagged `sbx` release. This is the channel users have today, so it **gates the PR** through the stable `e2e` job (the required status check).
- **`e2e-nightly`** downloads the rolling `nightly` build, so kits are also exercised against what `sbx` will ship next. It is **informational only** — a broken nightly shows a red check but never blocks merge. The `e2e-nightly-report` job echoes its outcome to the run log and the job summary.

**All e2e legs are skipped on fork PRs** because GitHub does not expose secrets to fork-triggered workflows — so for the typical contributor, e2e never runs in CI on their PR, and the reviewer sees a green check that does **not** cover the e2e assertions.

That makes a local e2e run **mandatory** before opening a PR from a fork. Run `./scripts/test-kit-e2e.sh <kit>` — the script applies the same `deny-all` baseline CI uses on a scoped daemon (`--app-name sbx-kits-contrib-tck`), so the network contract gets tested without touching your main sbx state. See [Declare every domain your kit needs](#declare-every-domain-your-kit-needs) for the recurring "read the proxy log, add a host, re-run" loop.

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
- The optional e2e legs exercise every detected kit against a real `sbx` CLI — `e2e-release` (latest release, gates the PR) and `e2e-nightly` (rolling nightly, informational only). See [End-to-end (e2e) Tests](#end-to-end-e2e-tests). Skipped on fork PRs (no Docker Hub secrets).

## Prerequisites

- Go 1.23+
- Docker (for container-based TCK tests)

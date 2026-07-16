# Testing Kits

Four layers. Run **all four locally** before opening a PR — only the first two run on CI for fork PRs.

**Why fork contributors must run e2e locally.** The repo's CI e2e legs (`e2e-release`, which gates the PR, and the informational `e2e-nightly`) need `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` to pull the template image, and GitHub does not expose secrets to workflows triggered from forks. So if you're contributing from a fork (the common case), the e2e legs are **skipped silently** on your PR — the reviewer sees a green check that does not include `TestE2EKit`. The only place those assertions ever run is on your laptop. See [`.github/workflows/tck.yml`](../../../.github/workflows/tck.yml) and the "Running in CI" note in [the README](../../../README.md#running-in-ci).

## 1. Spec-level validation

Fastest feedback. No Docker required.

```bash
sbx kit validate ./my-kit/
sbx kit inspect ./my-kit/ --output json | jq
```

Validation runs automatically inside every `spec.Load*` path. If a kit cannot pass `validate`, no other layer will work.

## 2. TCK (Technology Compatibility Kit)

This repository ships a TCK package at [`tck/`](../../../tck/). It validates:

1. Spec parses with required fields
2. Network policy (`permissions.network` allow/deny entries are well-formed)
3. Credentials (each `credentials[]` entry is well-formed; injection rules valid)
4. Environment variables (declared, set in container)
5. Setup (`setup.install` / `setup.startup` are well-formed)
6. Container files (files from `files/` are injected at the correct paths)
7. Volumes (block-backed and `type: tmpfs` entries — plus the implicit `/run/secrets` tmpfs)
8. Published ports (`ports[]` entries validate)

### Writing a TCK test

You **don't** write a per-kit test file. The shared `TestKitTCK` in [`tck/kit_test.go`](../../../tck/kit_test.go) reads a `KIT` env var pointing at your kit directory and runs the full suite. The pattern, if you want to invoke it programmatically:

```go
import "github.com/docker/sbx-kits-contrib/tck"

suite, err := tck.NewSuiteFromDir("./my-kit")
require.NoError(t, err)
suite.RunAll(t)
```

### Schema version awareness

The TCK loads via `spec.LoadFromDirectory`, so it accepts both v1 and v2 spec.yaml. For v1 kits, `Artifact.Warnings` is populated during load — the TCK does **not** fail on warnings, but a clean kit should aim for an empty warnings slice. The e2e wrapper script asserts a green run end-to-end including warning cleanup.

### Extending a non-default parent

For mixins that `extends:` a non-default parent agent, pass the parent's template image explicitly:

```go
suite, err := tck.NewSuiteFromDir(".", tck.WithImage("my-custom/template:latest"))
```

The TCK auto-resolves well-known parent agents (shell, claude, codex, copilot, cursor, docker-agent, droid, gemini, kiro, opencode) via their template images.

### Running TCK

```bash
# From inside the kit directory:
cd my-kit
../scripts/test-kit.sh

# Or from the repo root, naming the kit:
./scripts/test-kit.sh my-kit

# Or invoke go test directly:
KIT="$PWD/my-kit" go test -v -count=1 -timeout 10m -run TestKitTCK ./tck/...
```

`KIT` must be an absolute path because `go test` runs binaries with `cwd` set to the package directory (`./tck/`).

Requires Docker (or `docker-next` inside `sbx`).

## 3. End-to-end (e2e) tests

**Required before opening a PR from a fork** (see the "Why fork contributors must run e2e locally" note at the top of this file). The e2e layer boots a **real `sbx` sandbox** from the kit and verifies the kit's content actually landed inside the running container. It catches things the default TCK can't — install commands that fail under the non-root agent user, `${WORKDIR}` placeholders that resolve differently than expected, agent-kit name mismatches, or memory blocks the engine never writes out.

```bash
# From inside the kit's directory:
cd my-kit
../scripts/test-kit-e2e.sh

# Or from the repo root, naming the kit:
./scripts/test-kit-e2e.sh my-kit

# Or invoke go test directly:
KIT_UNDER_TEST="$PWD/my-kit" \
  go test -tags=e2e -v -timeout 25m -count=1 ./tck/...
```

Prerequisites: `sbx` on `PATH`, authenticated against Docker Hub, Linux with `/dev/kvm` accessible. See the repository [README](../../../README.md#end-to-end-e2e-tests) for the full setup and the precise assertions performed.

### `TestE2EKit` — the single e2e test

There is one e2e test function, `TestE2EKit`, that handles all kit kinds. It creates one sandbox and runs subtests selectively:

| Subtest | Applies to | What it checks |
|---|---|---|
| `env` | all kits | declared `environment.variables` are set in the container |
| `files` | all kits | files from `files/home` and `setup.files` exist and are non-empty |
| `tmpfs` | all kits | declared tmpfs paths (plus `/run/secrets`) are mounted |
| `agentContext` | all kits | `agentInstructions.content` rendered into the AI profile file (skipped when undeclared) |
| `prompt` | `kind: sandbox` only | non-interactive prompt sent to the agent; asserts non-empty response |

Every `sbx` call carries `--app-name sbx-kits-contrib-tck` so all commands route to the same authenticated daemon instance.

### `testdata/tck.yaml` — kit-specific e2e config

`kind: sandbox` kits **should** ship a `testdata/tck.yaml` file alongside their `spec.yaml` to opt in to the `prompt` subtest. The file is optional — the subtest is simply absent when the file is missing or `promptArgs` is empty. Kits whose agent requires a long async installation (e.g. nanoclaw, hermes-agent) may omit it until the installation reliably completes within the test timeout.

**Full schema:**

```yaml
# <kit-dir>/testdata/tck.yaml

# promptArgs: arguments prepended before the prompt message when invoking the
# agent binary non-interactively. The test runs:
#   sbx exec <sandbox> -- <binary> <promptArgs...> "what version are you running"
# Absent or empty promptArgs → prompt subtest does not run (e.g. trivy).
promptArgs: ["-p"]

# readyFile: absolute path of a sentinel file written inside the sandbox when a
# background installation finishes. When set, TestE2EKit polls
# `sbx exec -- test -f <readyFile>` before running the prompt subtest.
# Leave absent for kits whose install commands run synchronously inside sbx create.
readyFile: "/home/agent/nanoclaw/.installed"

# binary: override the agent binary name used in `sbx exec`. When absent, the
# test uses filepath.Base(Manifest.Binary), which the spec loader derives
# automatically from sandbox.entrypoint[0]. Only set this when the
# entrypoint is a wrapper script whose underlying binary has a different name.
binary: "claude"
```

#### How `binary` is resolved

The spec loader sets `Manifest.Binary = sandbox.entrypoint[0]` when loading any kit (from `sandbox.entrypoint.run[0]` on the v1 path). The e2e test uses `filepath.Base(Manifest.Binary)` as the default binary name. You **do not** need to set `binary:` in `tck.yaml` unless the entrypoint is a wrapper script whose name differs from the real binary:

| Kit | Entrypoint `[0]` | Derived binary | `tck.yaml binary` needed? |
|---|---|---|---|
| `amp`, `crush`, `junie`, `nanobot`, `pi` | same as kit name | same as kit name | no |
| `opencode-model-runner` | `opencode` | `opencode` | no |
| `claude-ollama` | `/home/agent/.local/bin/claude-ollama` | `claude-ollama` (wrapper) | yes → `claude` |
| `nanoclaw` | `/usr/local/bin/nanoclaw-start` | `nanoclaw-start` (wrapper) | yes → `claude` |
| `hermes-agent` | `/usr/local/bin/hermes-start` | `hermes-start` (wrapper) | yes → `hermes` |
| `openclaw` | `/usr/local/bin/openclaw-start` | `openclaw-start` (wrapper) | yes → `openclaw` |

Do **not** add `binary:` to `spec.yaml` — the loader rejects `binary` at the flat manifest level (v1-only field); it must come from `sandbox.entrypoint[0]`.

#### `promptArgs` reference

| Agent | `promptArgs` | Notes |
|---|---|---|
| `claude`, `nanoclaw`, `claude-ollama`, `pi` | `["-p"]` | Claude Code / pi use `-p` for non-interactive prompt |
| `nanobot` | `["-m"]` | |
| `amp` | `["-x"]` | `-x` / `--execute` |
| `crush` | `["run"]` | subcommand, prompt is a positional arg |
| `hermes` | `["chat", "-q"]` | `-q` / `--query` under the `chat` subcommand |
| `junie` | `["--task"]` | non-interactive task flag |
| `openclaw` | `["agent", "--message"]` | `agent` subcommand with `--message` flag |
| `opencode` | `["run"]` | `run` subcommand, prompt is a positional arg |
| `trivy` | *(absent)* | security scanner — no chat mode, prompt subtest skipped |

`TestE2ERunAgent` skips any kit whose `tck.yaml` is absent or has no `promptArgs`.

### Running e2e

```bash
cd my-kit
../scripts/test-kit-e2e.sh
```

That's the whole recipe — no manual policy dance. The script:

- Scopes every `sbx` call to `--app-name sbx-kits-contrib-tck`, the same app-name the e2e harness uses internally ([`tck/e2e_test.go:415`](../../../tck/e2e_test.go#L415)). The test daemon's sandboxes, policy, secrets, and cache are isolated from your day-to-day sbx state.
- Sets the scoped daemon's default network policy to `deny-all` — the same baseline CI uses, so any host your install or startup hooks reach for must be in `permissions.network.allow` or the request is blocked.
- Runs `go test -tags=e2e` with `KIT_UNDER_TEST` exported.
- On non-zero exit, prints a hint pointing at `sbx --app-name sbx-kits-contrib-tck policy log <sandbox>`.

The script is idempotent (re-runs converge on the same state) and non-interactive. Overrides: `APP_NAME` (default `sbx-kits-contrib-tck`) and `POLICY` (default `deny-all`; set `POLICY=` to skip the policy step).

One-time setup per machine — the scoped daemon has its own credential store:

```bash
sbx --app-name sbx-kits-contrib-tck login
```

When the test fails, the recurring fix is the same loop: read the proxy log, add the blocked host to `permissions.network.allow`, re-run.

```bash
APP=sbx-kits-contrib-tck
sbx --app-name $APP ls                            # find the tck-e2e-* sandbox
sbx --app-name $APP policy log tck-e2e-<short-uuid>
```

Every row under `Blocked requests` is a host your kit reached for under `deny-all`. Add the host (column `HOST`, e.g. `download.docker.com:443`) to `permissions.network.allow` and re-run until the block list is empty *and* the e2e test passes.

If the scoped daemon ever gets wedged: `sbx --app-name sbx-kits-contrib-tck reset --force` wipes only that daemon's state — your main sbx is untouched.

Common hosts that surface only under `deny-all` (easy to forget):

- `download.docker.com` — pre-added to apt sources on `shell-docker` / `*-docker` templates; any `apt-get update` re-fetches it even if you're installing from Ubuntu's main archive.
- `archive.ubuntu.com` + `security.ubuntu.com` (amd64) **and** `ports.ubuntu.com` (arm64) — list all three so the kit works on both CI (amd64) and Apple Silicon.
- Registry hosts for each package manager you call: `registry.npmjs.org`, `pypi.org` + `files.pythonhosted.org`, `crates.io` + `static.crates.io`, `proxy.golang.org` + `sum.golang.org`, etc.

## 4. End-to-end manual verification

For mixins and any time you want to see real container behavior:

```bash
# 1. Create a sandbox with the kit
sbx run claude --kit ./my-kit/ --name probe .

# 2. Verify the binary / file / env you expect
sbx exec probe -- which my-binary
sbx exec probe -- cat /home/agent/.my-kit/config.json
sbx exec probe -- printenv MY_VAR

# 3. Trigger a real outbound request and confirm proxy enforcement
sbx exec probe -- curl -sS https://api.myservice.com/health

# 4. Clean up
sbx rm probe
```

For mutable changes you can also use `sbx kit add` on an existing sandbox:

```bash
sbx kit add probe ./my-kit/
```

Faster iteration loop, but immutable settings (privileged, volumes, tmpfs) won't apply — recreate for those.

## Verifying `permissions.network.allow`

The proxy enforces allow/deny at request time. The fastest way to surface exactly what your kit reaches for is to run the e2e suite — see [Running e2e](#running-e2e) above. The script applies `deny-all` to the scoped daemon for you.

For ad-hoc probing of a single sandbox without running e2e, `sbx policy log` works directly:

```bash
sbx policy log <sandbox>
```

Every entry in the "Blocked requests" section is a domain your install or startup hook reached for. Add it to `permissions.network.allow` (or accept the block) and re-probe. The repository [README](../../../README.md#declare-every-domain-your-kit-needs) has the hand-built probe-sandbox variant of this recipe.

## Common pitfall: "install commands completed" ≠ success

`Install commands completed` in the create output only proves **exit code 0**, not that the install did the right thing. Always verify with a real check:

```bash
sbx exec probe -- <binary> --version           # binary on PATH
sbx exec probe -- test -f /expected/file       # file present
sbx exec probe -- printenv EXPECTED_VAR        # env var set
```

A broken install pipe can still exit 0 (e.g., `curl | bash` where the curl fails after partial output but bash exits 0 on empty input). Verify outcomes, not exit codes.

## `setup.startup` runs on every container start

Startup commands run on **every** container start (initial create, stop/start cycles, daemon restarts, host reboots), not just once at creation. Author them to be **idempotent**: use patterns like `apt-get update -qq -y > /dev/null 2>&1 || true &` and `mkdir -p '<dir>'`. Your test should assert the post-start state, not "did the command run exactly once".

See [Pitfalls — `setup.startup` runs on every container start](pitfalls.md#2-setupstartup-runs-on-every-container-start) for the mechanism.

## CI

The repository's CI runs the TCK on every PR — the matrix tests only the modified kit on PRs that touch a kit directory, and every kit on PRs that touch `tck/` or `spec/`. Two e2e legs exercise every detected kit against a real `sbx` CLI: `e2e-release` (latest tagged release, gates the PR via the required `e2e` check) and `e2e-nightly` (rolling nightly, informational only — never blocks merge). Both **are skipped on PRs opened from forks** because the `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets aren't exposed to fork-triggered workflows. Fork contributors are the common case, so you should treat e2e + `deny-all` as a **mandatory local step** before opening the PR — don't rely on a green CI check to mean "e2e passed". See [`.github/workflows/tck.yml`](../../../.github/workflows/tck.yml) and the reusable [`.github/workflows/e2e.yml`](../../../.github/workflows/e2e.yml).

# gitguardian - GitGuardian secret scanning (ggshield)

A mixin kit that installs [GitGuardian](https://www.gitguardian.com/)'s [`ggshield`](https://github.com/GitGuardian/ggshield) secret scanner into a Claude Code sandbox and wires it in as the **agent's own AI hook**, so the agent's actions are scanned for hardcoded secrets automatically, and the GitGuardian API key never enters the container.

`ggshield` inside the microVM only ever holds a placeholder value for `GITGUARDIAN_API_KEY`. When it calls the GitGuardian API, the sbx proxy rewrites the `Authorization: Token …` header with the real key (sourced from the host) on the wire, and denies any egress outside the kit's allowlist. The real key never enters the sandbox: not in the environment, shell history, or `ps` output.

This kit is **Claude Code-specific**: ggshield's AI hook writes Claude Code's own hook file (`~/.claude/settings.json`), so the kit declares `requires: ["claude"]` and the engine rejects composing it onto another agent. Codex, Copilot, and Cursor are served by separate sibling kits.

## Usage

Store a GitGuardian API key once on the host (a Personal or Service Account key with the `scan` scope):

```console
sbx secret set gitguardian
```

Then create a Claude sandbox with the kit:

```console
sbx run --kit "docker.io/docker/sbx-kit-gitguardian:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitguardian" claude
sbx run --kit ./gitguardian/ claude
```

## How auth works

The kit declares a `gitguardian` credential with one inject rule. Inside the container `GITGUARDIAN_API_KEY` is a sentinel (`proxy-managed`); on any request to `api.gitguardian.com` the proxy sets `Authorization: Token <your-real-key>`. The real key never reaches the sandbox filesystem or environment.

`gitguardian` is a custom (non-registry) service. Under the v2 grammar sbx did not auto-export the key sentinel into the container — it only set `SBX_CRED_GITGUARDIAN_MODE` — and since ggshield refuses to run when `GITGUARDIAN_API_KEY` is unset, the kit materialized the placeholder itself through an `environment.variables` entry. The v3 descriptor states it directly instead: `proxyManaged: true` on the credential's `apiKey` is what puts the sentinel in the container under that name. Credentials are phase-scoped in v3, and this one is `runtime`, so the install hook that registers the Claude Code AI hook defaults the variable itself rather than relying on the sentinel being present that early.

## What it installs

1. **`ggshield`**, which **ships in the kit's image layers** rather than being downloaded into your sandbox. `gitguardian.dockerfile` fetches a pinned, digest-verified GitHub release (no `curl | sh`) at build time and stages the PyInstaller bundle under `/opt/ggshield` with a symlink on `PATH`. To bump, change the `version` argument's default in `gitguardian.yaml` and both per-arch checksums in `gitguardian.dockerfile`.
2. **The Claude Code AI hook**, via `ggshield machine setup --agent claude-code --no-git-hooks --no-honeytokens`, run as the agent user at sandbox create. This registers `PreToolUse` / `PostToolUse` / `UserPromptSubmit` handlers that run `ggshield secret scan ai-hook` inside the agent's own tool loop.

The split is not arbitrary. The scanner is the same ~100 MB bundle for every sandbox, so downloading it once at publish means the digest is fixed in a layer you can scan, a withdrawn or re-rolled release fails the kit's build instead of a user's sandbox creation, every `sbx run` saves the fetch, and — most visibly — **the kit no longer asks for any install-phase network access at all**. The three GitHub hosts it used to need are gone from its permission surface; `api.gitguardian.com` at runtime is all that remains.

The hook registration cannot move, and it is worth knowing why: `machine setup` edits `~/.claude/settings.json`, a file Claude Code owns and writes itself. An image layer *replaces* a file rather than merging into it, so shipping a `settings.json` would register this scanner by discarding the agent's own configuration. Appending to somebody else's file is create-time work by nature. It needs no network to do it (verified with networking disabled).

A blocked action means a real secret was detected: remove and rotate it, don't retry or bypass. Manual scans remain available as an escape hatch:

```console
ggshield secret scan path -r .      # scan the workspace files
ggshield secret scan repo .         # scan full git history + working tree
```

## Other agents

ggshield's AI-hook support also covers Codex, Copilot, and Cursor, but each reads a different hook file, so automatic enforcement for those agents lives in separate kits (`gitguardian-codex`, `gitguardian-copilot`, `gitguardian-cursor`). Layering *this* kit onto a non-Claude agent is rejected at composition time by the kit's `requires: ["claude"]` entry.

## EU workspace / self-hosted instances

The EU workspace and self-hosted GitGuardian instances use a different API host. Set `GITGUARDIAN_INSTANCE` for ggshield, and in `gitguardian.yaml` add that host to both the network policy's `runtime.allow` list and the credential's `inject` block; the proxy only injects on, and only allows egress to, the hosts listed there. The two go together — an inject domain missing from the matching phase's allow list is a validation error, not a silent no-op.

## Cleanup

```console
sbx secret rm -g --service gitguardian
```

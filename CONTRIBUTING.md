# Contributing

This repo collects community-contributed kits for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/). New kits, fixes to existing ones, and improvements to the shared `spec/` and `tck/` packages are all welcome.

If you're new to sandbox customization, start with the docs:

- [Customize sandboxes](https://docs.docker.com/ai/sandboxes/customize/) — overview of every customization surface (templates, kits, network policies).
- [Kits](https://docs.docker.com/ai/sandboxes/customize/kits/) — full spec reference for the kit format used here.

The [`README.md`](./README.md) covers the mechanical setup — directory layout, `spec.yaml` skeleton, TCK boilerplate, how CI runs. This page covers the conventions for getting a contribution accepted.

## Migrating an existing kit to v2

If you maintain a kit that was authored against schemaVersion 1, the [`scripts/migrate-v1-to-v2.go`](./scripts/migrate-v1-to-v2.go) helper rewrites your `spec.yaml` mechanically:

```bash
go run scripts/migrate-v1-to-v2.go <path-to-your-kit>
```

It applies the v2 renames (`memory:` → `agentContext:`, `kind: agent` → `kind: sandbox`, `agent:` → `sandbox:`), writes a `spec.yaml.bak` of the original, and prints a summary of what changed. The script grows as later phases of the v2 migration land — see [`scripts/README.md`](./scripts/README.md) for the current scope and the [v2 migration roadmap](https://github.com/docker/sandboxes/blob/main/docs/specs/2026-05-27-unified-kit-spec-v2.md) for what's still pending.

## Before you start

Pick an existing kit closest in shape to what you want to build and read it end-to-end as a template:

- **[`code-server/`](./code-server)** — mixin: `extends: claude`, `initFiles` with `${WORKDIR}` substitution, shipped config in `files/`.
- **[`amp/`](./amp)** — `kind: agent` kit: custom image, `serviceDomains`/`serviceAuth` for proxy-injected credentials, paired with a one-time `sbx secret set-custom` step.

## Per-kit README

Every kit should ship a `README.md`. The structure isn't mandatory, but the existing kits converge on:

- **Title and one-paragraph description** of what the kit does and what agent it pairs with.
- **Usage** — the `sbx run` invocation and any host-side prerequisites.
- **How _X_ works** — short sections explaining non-obvious decisions in the spec, so the next reviewer doesn't have to reverse-engineer the YAML.
- **Cleanup**, if the kit creates state on the host.

For kits that have a corresponding tutorial on [docs.docker.com](https://docs.docker.com/), link to it instead of duplicating the design rationale.

## Network policy: declare every domain

Your kit's `network.allowedDomains` is the **complete** outbound contract — the CI e2e job runs under `deny-all`, so anything you don't list is blocked.

Watch out for package managers: `apt-get update`, `npm install`, `pip install`, etc. each refresh metadata for every configured source, not just yours. For kits built on `shell-docker` / `*-docker` templates that means `download.docker.com` must be in your list even if you only `apt-get install` from Ubuntu's main archive — `apt-get update` fails the install otherwise. List `archive.ubuntu.com`, `security.ubuntu.com`, **and** `ports.ubuntu.com` so the kit works on both amd64 (CI) and arm64 (Apple Silicon).

See [Declare every domain your kit needs](./README.md#declare-every-domain-your-kit-needs) in the README for the probe recipe that surfaces the exact set of domains your install hooks reach for under `deny-all`.

## Verifying locally

Before opening a PR, run **all four** of these:

```console
$ sbx kit validate ./my-kit/
$ cd my-kit && ../scripts/test-kit.sh
$ ../scripts/test-kit-e2e.sh           # under deny-all — see below
$ sbx run --kit . <agent>              # quick manual smoke
```

The first two are what CI runs on every PR. **The third is not run on CI for PRs opened from a fork** — the CI e2e legs (`e2e-release`, which gates the PR, and the informational `e2e-nightly`) need `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN`, and GitHub doesn't expose secrets to fork-triggered workflows, so they are skipped silently and the reviewer sees a green check that does **not** include the e2e assertions. If you're contributing from a fork (the common case), your laptop is the only place those assertions ever run before merge.

`scripts/test-kit.sh` resolves the kit directory (default: `$PWD`), sets `KIT` to its absolute path, and runs `go test -run TestKitTCK ./tck/...` against the repo-root `tck` package. Forwards extra flags to `go test`, so `../scripts/test-kit.sh -v -run TestKitTCK/my-kit/validation` works.

### Running e2e

The wrapper script does the dance for you:

```console
$ cd my-kit && ../scripts/test-kit-e2e.sh
```

That single command:

- scopes every `sbx` call to `--app-name sbx-kits-contrib-tck`, so the test daemon (sandboxes, policy, cache) is isolated from your main sbx state and nothing the script does touches your day-to-day setup,
- sets the scoped daemon's default network policy to `deny-all` — the same baseline CI uses, so any host your install or startup hooks reach for must be in `network.allowedDomains` or the request is blocked, and
- runs `TestE2EKit` (env, files, tmpfs, agentContext, and — for `kind: sandbox` kits with a `testdata/tck.yaml` — a non-interactive prompt to the agent).

The script is idempotent (re-runs converge on the same state) and non-interactive (no prompts).

One-time setup per machine — the scoped daemon has its own credential store, separate from any login on your main daemon:

```console
$ sbx --app-name sbx-kits-contrib-tck login
```

When the test fails, the script prints how to dump the proxy log. The recurring fix is the same loop: read the log, add the blocked host to `network.allowedDomains`, re-run.

```console
$ sbx --app-name sbx-kits-contrib-tck ls                          # find the tck-e2e-* sandbox
$ sbx --app-name sbx-kits-contrib-tck policy log <sandbox-name>
```

Every row under `Blocked requests` is a host your kit reached for under `deny-all`. See [Declare every domain your kit needs](./README.md#declare-every-domain-your-kit-needs) for the cross-arch gotchas (`archive.ubuntu.com`, `security.ubuntu.com`, **and** `ports.ubuntu.com`) and the package-manager refresh trap (`apt-get update` re-fetches every configured source).

If the scoped daemon ever gets wedged: `sbx --app-name sbx-kits-contrib-tck reset --force` wipes only that daemon's state.

Prerequisites for e2e (`/dev/kvm`, Secret Service on Linux, etc.) are in [End-to-end (e2e) Tests](./README.md#end-to-end-e2e-tests) in the README.

## Sign-off and signing

Every commit needs **two** things, which are unrelated:

1. A **DCO sign-off** — a `Signed-off-by:` trailer in the commit message, certifying you have the right to submit the work under the repo license. Added with `git commit -s`.
2. A **cryptographic signature** — a GPG or SSH signature on the commit itself, which is what produces the green **Verified** badge on GitHub. Added with `git commit -S` (or by configuring git to sign by default).

Both are required. A signed commit without `-s` will fail DCO check; a signed-off commit without a signature won't show as Verified.

The fastest path is to configure git once so every `git commit` does both automatically:

```bash
git config --global commit.gpgsign true
```

Then commits only need `-s`:

```bash
git commit -s -m "fix(amp): bump install timeout"
```

### Option A — GPG signing

1. Generate a key (skip if you already have one — list with `gpg --list-secret-keys --keyid-format=long`):

   ```bash
   gpg --full-generate-key
   # Choose: ECC (sign and encrypt) or RSA 4096, 0 = does not expire (or pick an expiry),
   # use the same email as your GitHub account.
   ```

2. Tell git which key to use:

   ```bash
   KEY_ID=$(gpg --list-secret-keys --keyid-format=long | awk '/^sec/ {split($2,a,"/"); print a[2]; exit}')
   git config --global user.signingkey "$KEY_ID"
   git config --global commit.gpgsign true
   ```

3. Export the public key and add it to GitHub under **Settings → SSH and GPG keys → New GPG key**:

   ```bash
   gpg --armor --export "$KEY_ID"
   ```

4. On macOS, install `pinentry-mac` so the passphrase prompt works in non-interactive shells:

   ```bash
   brew install gnupg pinentry-mac
   echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
   gpgconf --kill gpg-agent
   ```

### Option B — SSH signing

If you already use SSH for git, you can sign with the same key and skip GPG entirely. Requires git ≥ 2.34.

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

Then add the **same** public key to GitHub a second time under **Settings → SSH and GPG keys → New SSH key**, with key type **Signing Key** (an Authentication key alone won't verify commits).

### Verifying it works

```bash
git commit -s --allow-empty -m "test: verify signing"
git log -1 --show-signature
```

You should see `Good signature` (GPG) or `Good "git" signature` (SSH), and a `Signed-off-by:` trailer at the bottom of the message. After pushing, GitHub will show the commit as **Verified**.

For deeper background, see GitHub's docs on [managing commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification).

## Pull requests

- **New kit**: capitalized `Add <kit-name> kit`.
- **Fix or tweak**: conventional commits — `chore(<kit>): …`, `fix(tck): …`, `feat(spec): …`.

A useful PR description has:

- **Summary** — what changed.
- **Spec choices worth flagging for review** — decisions a reviewer should sanity-check (an unusual image choice, a deliberately narrow `allowedDomains`, a workaround for a known bug).
- **Test plan** — what CI covers, plus any manual end-to-end you ran.
- **Origin** — where the kit came from. One sentence is enough.

## Asking questions

Open an issue.

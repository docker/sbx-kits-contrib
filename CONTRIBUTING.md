# Contributing

This repo collects community-contributed kits for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/). New kits, fixes to existing ones, and improvements to the shared tooling are all welcome.

Kits here use the **v3 kit descriptor**, which is specified upstream:

- [SPEC-v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md) — the grammar, publishing rules, and the OCI layout a kit produces.
- [Capability pages](https://github.com/docker/sandbox-kit-spec/tree/main/docs/spec/capabilities/com.docker.sandbox) — one page per capability type, normative for its own config schema and runtime behavior.

Both are the authority. Where this page and the specification disagree, the specification wins, and the disagreement is a bug in this page.

The [`README.md`](./README.md) covers the mechanical setup — directory layout, the descriptor skeleton, local verification, how CI runs, the kit index. This page covers the conventions for getting a contribution accepted.

## Migrating a kit to v3

Every kit in this repo was migrated from the v2 `spec.yaml` grammar. If you maintain a kit outside it that is still on v2, the shape of the work is:

| v2 | v3 |
| --- | --- |
| `spec.yaml` | `<kit>/<kit>.yaml`, first line `# syntax=docker/sandbox-kit:3` |
| `Dockerfile` | `<kit>/<kit>.dockerfile`, found by filename stem |
| `schemaVersion: "2"` | `schemaVersion: "3"` |
| `name: claude` | dropped — a kit's identity is the reference it is consumed by |
| `kind: sandbox` | `kind: workload` — never write `sandbox` |
| `sourceURL` | `sourceUrl` |
| `requires: {agent: claude}` | `requires: ["claude"]`, plus the real dependencies |
| `sandbox.image` | the recipe's `FROM` |
| `sandbox.entrypoint` / `sandbox.command.default` | the recipe's `ENTRYPOINT` / `CMD` |
| `sandbox.command.interactive` | `lifecycle@1.interactive` |
| `environment.variables` | the recipe's `ENV` (a mixin: `/etc/profile.d`) |
| `permissions.network` | `network-policy@1`, phase-scoped into `install` and `runtime` |
| `credentials[]` | one `credential@1` per service |
| `volumes[]` / `ports[]` | one `volume@1` per path / one `port@1` per port |
| `setup.install` / `.startup` / `.files` | one `lifecycle@1` |
| `agentInstructions` | `agent-context@1`, body in `<kit>-context.md` |
| — | `sbx@1` on every workload |
| `${argname}` | `${{ kit.args.argname }}` |

There is a migration skill with the full field-by-field mapping, including the reasoning behind each row, in the [`docker/sandbox-kit-spec`](https://github.com/docker/sandbox-kit-spec) repository under `.cursor/skills/migrate-kit-to-v3/` — read its `FIELD-MAPPING.md` before starting, because the table above is the shape of the work and not the whole of it.

The renames are the easy half. What actually takes review is the judgment:

- **Split the network policy by phase without losing a host.** An absent phase grants nothing. Hosts reached by install hooks go in `install`; hosts reached by the agent in steady state *or by startup hooks* go in `runtime`, because startup hooks run at boot. A host reached by both goes in both. Write entries portless.
- **Declare every variable each hook reads.** A v3 hook's environment is deny-by-default. This is the single most common migration bug, and it extends to variables the hook's *children* read — a hook that never mentions `$HTTPS_PROXY` but shells out to `curl` still has to declare it.
- **Add `optional: true` to every credential that was effectively optional in v2.** v2 credentials defaulted to not-required; v3 entries are required unless they opt out, so a faithful migration opts out.
- **Check that each `inject[].domain` appears in the same phase's allow list.** Validation enforces it, as an exact host match — a `*.example.com` wildcard does not satisfy an inject domain of `api.example.com`. This is worth doing before the build tells you, because it routinely surfaces v2 inject rules that were dead all along.
- **Move the interactive/launch contract into the recipe, and delete the v2 `CMD` that mirrored it.** v2 recipes commonly carried a `CMD` echoing the kit's entrypoint so a plain `docker run` behaved like the sandbox. Beside a migrated `ENTRYPOINT` that `CMD` becomes a stray trailing argument. Keep a `CMD` only where it carries default *arguments*, which is exactly what `sandbox.command.default` was.
- **Pin the version, and make the build enforce the pin.** See [Versions](./README.md#versions) in the README.

Mark every deliberate delta from the v2 behavior with a `# MIGRATION NOTE:` comment in the descriptor, and carry the v2 comments across. The kits in this repo do, and it is why a reviewer can tell a transcription from a decision.

`scripts/migrate-v1-to-v2.go` is two migrations stale. It rewrites a v1 spec into a v2 one and knows nothing about v3; do not reach for it.

## Before you start

Pick an existing kit closest in shape to what you want to build and read it end-to-end as a template. The kits here are commented at length on purpose — the comments are where the reasoning lives:

- **[`mise/`](./mise)** — a declaration-only mixin: no recipe at all, just a pinned install expressed as lifecycle hooks, a phase-split network policy, and `requires: ["deb/dpkg"]`.
- **[`claude-mixin/`](./claude-mixin)** — an overlay mixin: a non-relocatable install run over the workload's base, staged under `/out`, shipped `FROM scratch`, with its environment landing in `/etc/profile.d` because a mixin's image config is not the composed image's.
- **[`claude/`](./claude)** — a workload: the whole environment, with `sbx@1`, an `agent-context@1` that owns the `CLAUDE.md` filename, session-state volumes, and a credential covering both an API key and a subscription.
- **[`openclaw/`](./openclaw) and [`openclaw-mixin/`](./openclaw-mixin)** — a workload/mixin pair whose recipes `COPY` shipped assets out of a `files/` directory, and the clearest illustration of what the two shapes can and cannot share.

## Per-kit README

Every kit should ship a `README.md`. The structure isn't mandatory, but the existing kits converge on:

- **Title and one-paragraph description** of what the kit does and, for a mixin, what it pairs with.
- **Usage** — the `sbx run` invocation and any host-side prerequisites. Lead with the published image, `docker.io/docker/sbx-kit-<kit>:latest` — every kit here publishes automatically (see [`PUBLISHING.md`](./PUBLISHING.md)), so it is the primary way to consume one — then the git-URL form, then the local-path form.
- **How *X* works** — short sections explaining the non-obvious decisions, so the next reviewer doesn't have to reverse-engineer the descriptor. Pinning choices, why a host is or isn't in the allow list, why an install runs the way it does.
- **Cleanup**, if the kit creates state on the host.

A workload and its `-mixin` sibling each get their own README. They differ in exactly the ways the two shapes differ — how you run it, and what the mixin cannot carry — so a shared README would have to hedge every sentence.

For kits that have a corresponding tutorial on [docs.docker.com](https://docs.docker.com/), link to it instead of duplicating the design rationale.

## Network policy: declare every domain

A kit's `network-policy@1` is its **complete** outbound contract — anything not listed is blocked at request time, and a blocked request inside an install hook surfaces as sandbox creation failing.

The policy is **phase-scoped**, and an absent phase grants nothing:

```yaml
- type: com.docker.sandbox/network-policy@1
  config:
    install:
      allow: [github.com, objects.githubusercontent.com]
    runtime:
      allow: [api.example.com]
```

Watch out for package managers: `apt-get update` re-fetches metadata for every configured source, not just yours, and exits non-zero if any one of them fails. For kits on `shell-docker` / `*-docker` templates that means `download.docker.com` must be listed even if you only install from Ubuntu's main archive. List `archive.ubuntu.com`, `security.ubuntu.com`, **and** `ports.ubuntu.com` so the kit works on both amd64 (CI) and arm64 (Apple Silicon). Write hosts portless, so a mirror answering over HTTPS doesn't break the kit.

Adding a host on speculation is how an allow-list stops describing anything. If a host is only reached on a path most sessions never take — an `npx`-launched MCP server, a plugin marketplace — leave it out and say so in a comment, so the omission reads as a decision rather than an oversight.

See [Declare every domain your kit needs](./README.md#declare-every-domain-your-kit-needs) in the README for the rest of the traps.

## Verifying locally

Before opening a PR, build the kit — which is what validates it — from inside its directory:

```console
cd my-kit
docker buildx build . -f my-kit.yaml --output type=cacheonly
```

Then, from the repo root, read back what it resolved to and run it:

```console
sbx kit inspect ./my-kit
sbx run ./my-workload .                     # a workload
sbx run ./my-workload --kit ./my-mixin .    # a mixin, composed
```

And the conformance suite, against the built artifact:

```console
go install github.com/docker/sandbox-kit-spec/v3/cmd/kit-tck@latest
cd my-kit
docker buildx build . -f my-kit.yaml --output type=oci,dest=/tmp/k,tar=false -t my-kit:1.4.2
kit-tck kit --layout /tmp/k 1.4.2
```

`kit-tck` takes the **tag alone** as its last argument, not `my-kit:1.4.2`.

Two things to know before you spend time on a confusing failure:

- **`kit-tck` comes from a private repository.** `docker/sandbox-kit-spec` is not public yet, and the public module proxy answers 404 for it, so that `go install` resolves direct and needs a git credential plus `GOPRIVATE=github.com/docker/*`. Without access, build your kit and stop there — the frontend validates the descriptor during the build, which is the check that catches most mistakes. CI works the same way: a pull request from a fork validates but cannot run the conformance suite.
- **Kit v3 needs an `sbx` release candidate or nightly**, not the stable line. A stable `sbx` has no v3 load path.
- **`sbx kit validate` does not accept a v3 source kit.** It fails with *"is a v3 source kit and this load path has no kit builder configured"* on every kit in this repo. That is the wrong tool, not a broken kit — use `sbx kit inspect`, or just build it.

Running the mixin is not optional cleanup at the end. Building an overlay proves that the files were produced; composing it onto a base and running the tool proves they landed somewhere the tool can be launched from. An installer that relocates a launcher but not its payload passes every build-time check and ships a dangling symlink, and this repo shipped three kits that way before it was caught.

A fork PR does not receive repository secrets, so any CI leg that needs Docker Hub credentials is skipped on it and the reviewer sees a green check that does not cover those assertions. If you are contributing from a fork — the common case — your laptop is the only place they ever run before merge.

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

- **New kit**: capitalized `Add <kit-name> kit`. A workload and its `-mixin` sibling land together.
- **Fix or tweak**: conventional commits — `chore(<kit>): …`, `fix(<kit>): …`, `feat(<kit>): …`.

A useful PR description has:

- **Summary** — what changed.
- **Declaration choices worth flagging for review** — decisions a reviewer should sanity-check: a deliberately narrow or deliberately wide allow list, a capability you chose *not* to declare, a provide left unversioned and why, a `requires` entry you had to verify exists.
- **Test plan** — the build, the conformance run, and the composed run you did by hand.
- **Origin** — where the kit came from. One sentence is enough.

## Asking questions

Open an issue.

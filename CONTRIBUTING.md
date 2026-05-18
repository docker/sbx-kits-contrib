# Contributing

This repo collects community-contributed kits for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/). New kits, fixes to existing ones, and improvements to the shared `spec/` and `tck/` packages are all welcome.

If you're new to sandbox customization, start with the docs:

- [Customize sandboxes](https://docs.docker.com/ai/sandboxes/customize/) — overview of every customization surface (templates, kits, network policies).
- [Kits](https://docs.docker.com/ai/sandboxes/customize/kits/) — full spec reference for the kit format used here.

The [`README.md`](./README.md) covers the mechanical setup — directory layout, `spec.yaml` skeleton, TCK boilerplate, how CI runs. This page covers the conventions for getting a contribution accepted.

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

## Verifying locally

Before opening a PR:

```console
$ sbx kit validate ./my-kit/
$ cd my-kit && go test -v -count=1 -timeout 10m ./...
$ sbx run --kit ./my-kit/ <agent>
```

The first two are what CI runs. The third catches things the TCK doesn't — install scripts hitting unexpected hosts, startup wrappers crashing silently, agents not authenticating.

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

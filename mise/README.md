> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# mise

A mixin that installs [mise](https://mise.jdx.dev) (mise-en-place), the
polyglot dev-tool version manager, and wires up shell activation so the
agent can resolve and install per-project tool versions from
`.mise.toml` / `.tool-versions` files inside the sandbox.

## Usage

`mise` is agent-agnostic — pair it with whichever agent you're using:

```console
sbx run claude --kit "docker.io/docker/sbx-kit-mise:latest" ~/my-project
```

Or from a git URL targeting this repo:

```console
sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=mise" ~/my-project
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=mise" ~/my-project
```

Once attached, any interactive shell has `mise` on PATH and shell hooks
active:

```console
agent@sandbox:~$ mise --version
2026.5.2 ...
agent@sandbox:~$ cd ~/my-project   # auto-resolves .mise.toml
agent@sandbox:~$ mise install      # installs the project's pinned versions
```

## How the install works

**mise ships in the kit's image layers; nothing is downloaded into your
sandbox.** `mise.dockerfile` fetches a pinned release tarball from
GitHub at build time, verifies its SHA256 against a digest captured in
the recipe, and extracts only the `mise` binary into
`/usr/local/bin/`. The `/etc/profile.d/mise-env.sh` export ships in the
same layer.

That is a change from earlier versions of this kit, which downloaded
mise at every sandbox create. Building it means the digest is fixed in
a layer you can scan, a withdrawn or re-rolled release fails the kit's
build instead of a user's sandbox creation, every `sbx run` saves the
fetch, and — most visibly — **the kit asks for no install-phase network
access at all**. GitHub is still in the `runtime` allow list, but for
your `mise install` calls rather than the kit's own.

The version and per-arch digests are sourced from the release's
`SHASUMS256.txt` and live in git. Bumping mise is the `version`
argument's default in `mise.yaml` plus both digests in
`mise.dockerfile`: the version is stated in that one place — the
recipe, the `mise@<version>` the kit provides and the tag it publishes
under all read it — and the build runs the installed binary and fails
if what it reports disagrees.

We avoid the upstream `curl https://mise.run | sh` flow on purpose:
that pattern is fine on a developer workstation but it gives a sandbox
no visibility into what binary actually got placed on PATH. Pinning
lets reviewers see what changed when you bump the kit.

## Shell activation

This is the one piece that still runs at sandbox create, and it has to.
A lifecycle install hook appends two lines to the agent user's `~/.bashrc`:

```bash
export MISE_TRUSTED_CONFIG_PATHS="/"
eval "$(mise activate bash)"
```

It cannot be baked into the kit's layers the way the binary and the
`/etc/profile.d` export are, because an image layer *replaces* a file
rather than merging into it — shipping a `.bashrc` would throw away
whatever the agent image put in its own, and what this kit needs is one
line added to that file, not the file. (`/etc/profile.d/mise-env.sh` is
different in exactly this respect: no one else writes it, so replacing
it is correct.) `/home/agent` may also be a mounted volume, which would
cover anything baked there.

`mise activate` is the canonical hook that puts mise's shims on PATH,
auto-installs missing versions when you `cd` into a project, and
re-resolves whenever the active `.mise.toml` changes. The append is
guarded with `grep -qF` so re-running the install (e.g., during local
TCK iteration) doesn't duplicate the line.

If you bring your own shell (zsh, fish), wire activation yourself in
`~/.zshrc` / `~/.config/fish/config.fish` — see the
[mise getting-started](https://mise.jdx.dev/getting-started.html) page
for the exact snippets.

## About `MISE_TRUSTED_CONFIG_PATHS=/`

mise normally prompts before sourcing a `.mise.toml` it hasn't seen
before, since these files can run arbitrary shell. Inside a sandbox
you've already accepted that boundary by attaching the workspace, so
the kit pre-trusts the whole filesystem to keep the agent
non-interactive. It is set twice, deliberately: in
`/etc/profile.d/mise-env.sh`, which ships in the kit's layers and
reaches login shells, and again in the `~/.bashrc` lines above, which
reach the interactive non-login shells activation is actually wired
into. An unset value in either is a trust prompt, which is the one
thing the variable exists to prevent.

If that's too coarse for your threat model, fork the kit and narrow
`MISE_TRUSTED_CONFIG_PATHS` to the workspace mount point (typically the
value of `${WORKSPACE_DIR}`).

## Network policy and runtime tool installs

The kit's `com.docker.sandbox/network-policy@1` capability declares a
`runtime` phase and **no `install` phase at all**. Since mise itself is
built into the kit's layers, nothing this kit does before the agent
starts touches the network, and an absent phase grants nothing. What
remains is the GitHub-hosted path mise's `ubi` backend uses for most
tools — your traffic, not the kit's:

- `github.com` — release download URLs for `mise install
  <github-hosted-tool>`
- `api.github.com` — version resolution. mise hits this for any
  `<tool>@latest`, `<tool>@<major>`, etc., and even validates exact
  tags through it. Without this, github-hosted tool installs fail at
  the resolve step with a 403 from the sandbox proxy
- `objects.githubusercontent.com` — the actual 302 target a github.com
  release-download URL lands on, confirmed by hand against a real
  request back when the kit still fetched its own release this way
- `release-assets.githubusercontent.com` — kept alongside it since a
  release asset's redirect target isn't guaranteed to be the same host
  for every repo, and `ubi` fetches from arbitrary repos

Note that wildcard subdomains (`*.github.com`) match subdomains only,
not the apex — so listing the apex and the subdomains explicitly is
required, not redundant.

`mise install <tool>` at runtime also hits per-language CDNs beyond
GitHub for non-github-hosted tools, and these vary by what you ask
for. The kit deliberately doesn't pre-allow all of them — each widens
the trust footprint. Add what you need in a fork, under the `runtime`
phase since that is when `mise install` runs. A starter set covering the
most common backends:

```yaml
capabilities:
  - type: com.docker.sandbox/network-policy@1
    config:
      runtime:
        allow:
          - github.com
          - api.github.com
          - objects.githubusercontent.com   # confirmed release-asset redirect target
          - release-assets.githubusercontent.com
          - codeload.github.com             # source tarballs (some asdf plugins)
          - nodejs.org                      # node
          - registry.npmjs.org              # npm-backed plugins
          - dl.google.com                   # go (golang.org redirects here)
          - go.dev
          - www.python.org                  # python
          - files.pythonhosted.org          # pip
          - pypi.org
          - static.crates.io                # rust
          - crates.io
```

If `mise install` fails with a DNS / connection refused error, the
denied host is almost always in the error message — add it and retry.

## Scope of this kit

This is a thin install-and-activate layer. It does **not** ship a
default `.mise.toml`, opinionated tool selection, or pre-installed
language runtimes — those decisions belong in your project repo, not
in a generic kit. If you want a heavier "batteries-included Python +
Node" environment, layer this kit underneath your own.

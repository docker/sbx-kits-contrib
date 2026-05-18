# mise

A mixin that installs [mise](https://mise.jdx.dev) (mise-en-place), the
polyglot dev-tool version manager, and wires up shell activation so the
agent can resolve and install per-project tool versions from
`.mise.toml` / `.tool-versions` files inside the sandbox.

## Usage

`mise` is agent-agnostic — pair it with whichever agent you're using:

```console
$ sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=mise" ~/my-project
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=mise" ~/my-project
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

The kit downloads a pinned mise release tarball from GitHub, verifies
its SHA256 against a digest captured in `spec.yaml`, and extracts only
the `mise` binary into `/usr/local/bin/`. The version and per-arch
digest are sourced from the release's `SHASUMS256.txt` and live in git
— bumping mise is a one-line edit + a digest update.

We avoid the upstream `curl https://mise.run | sh` flow on purpose:
that pattern is fine on a developer workstation but it gives a sandbox
no visibility into what binary actually got placed on PATH. Pinning
lets reviewers see what changed when you bump the kit.

## Shell activation

The install step appends a single line to the agent user's `~/.bashrc`:

```bash
eval "$(mise activate bash)"
```

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
non-interactive. If that's too coarse for your threat model, fork the
kit and narrow `MISE_TRUSTED_CONFIG_PATHS` to the workspace mount
point (typically the value of `${WORKDIR}`).

## Network policy and runtime tool installs

The kit ships with a baseline that covers the install step **and** the
GitHub-hosted runtime path that mise's `ubi` backend uses for most
tools:

- `github.com` — release tag URL for both the kit's pinned mise
  install and `mise install <github-hosted-tool>` at runtime
- `api.github.com` — version resolution. mise hits this for any
  `<tool>@latest`, `<tool>@<major>`, etc., and even validates exact
  tags through it. Without this, github-hosted tool installs fail at
  the resolve step with a 403 from the sandbox proxy
- `release-assets.githubusercontent.com` — 302 target for binary
  downloads from those release URLs

Note that wildcard subdomains (`*.github.com`) match subdomains only,
not the apex — so listing the apex and the subdomains explicitly is
required, not redundant.

`mise install <tool>` at runtime also hits per-language CDNs beyond
GitHub for non-github-hosted tools, and these vary by what you ask
for. The kit deliberately doesn't pre-allow all of them — each widens
the trust footprint. Add what you need in a fork. A starter set
covering the most common backends:

```yaml
network:
  allowedDomains:
    - github.com
    - api.github.com
    - release-assets.githubusercontent.com
    - objects.githubusercontent.com   # older release asset host
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

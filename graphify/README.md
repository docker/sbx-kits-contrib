# graphify

A mixin installing a pinned [Graphify](https://github.com/Graphify-Labs/graphify)
0.9.57 runtime — code-graph extraction and query over a codebase, via
[tree-sitter](https://tree-sitter.github.io/tree-sitter/) parsing and
[NetworkX](https://networkx.org/). The kit installs the runtime into a
root-owned venv at `/opt/graphify`, with `graphify` on `PATH` and
`graphify-mcp` left unsymlinked inside the venv. It composes with any base
sandbox (no `requires.agent`, no image, credentials, ports, volumes, or
startup hooks) — combine it with whichever agent kit you run.

## Requirements

- A base image with Python 3.10+ and a working `venv` module. Dependencies
  install as prebuilt wheels only (no source builds), which PyPI covers for
  `linux/amd64` and `linux/arm64`.
- Network: the kit allows `pypi.org:443` and `files.pythonhosted.org:443`
  under deny-all.

## Usage

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=graphify" ~/my-project
```

Or from its published OCI artifact on Docker Hub:

```console
sbx run claude --kit "docker.io/sbx/graphify-kit:latest" ~/my-project
```

Graphs are never built automatically. Run `graphify extract <path>` to build
one, then `graphify query` against it. Code-only extraction needs no API key
and makes no network call.

To install a different Graphify release than the kit's default, override the
version and its matching wheel hash together at create time (the install
fails closed if they don't match):

```console
sbx run claude --kit <ref> --kit-arg version=<v> --kit-arg sha256=<wheel sha256> ~/my-project
```

The hash is the wheel's sha256 from `https://pypi.org/pypi/graphifyy/<v>/json`.

## Agent integration is up to you

This kit deliberately ships no project integration — no installed skill, no
CLAUDE.md wiring, no git hooks. Upstream's own installer
(`graphify install --project --platform <id>`) works fine against this
runtime, but you own what it does once you run it. Review it first:

- The installed skill's bootstrap self-installs or upgrades Graphify,
  unpinned, via `pip` or `uv`. This kit's PyPI network allowance makes that
  path reachable and it will silently replace the pinned runtime.
- Upstream's docs suggest `post-commit` / `post-checkout` git hooks. On a
  directly mounted sandbox, those hooks land in the **host** repository, not
  a sandbox-local copy.
- Some of upstream's per-platform installers write to `$HOME` or to global
  (not project-local) configuration.

## Direct mount vs. `--clone`

On a directly mounted project, `graphify extract <path>` writes
`graphify-out/` into the directory it scans, and upstream's skill (if you
installed it) writes `.graphify_python` there on every invocation — both land
in your host checkout. On a `sbx run --clone` sandbox, the same writes stay
inside the sandbox's private clone.

## Updating the pinned version

Only relevant when changing this kit in sbx-kits-contrib, not when using it
(users can already override per sandbox with `--kit-arg`, above). Edit the
`version` and `sha256` defaults in `spec.yaml`'s `args:` block.

## Licensing

Graphify is licensed Apache-2.0. This kit installs it from PyPI and ships no
upstream text of its own.

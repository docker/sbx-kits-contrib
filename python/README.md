# Python

A mixin that adds CPython 3.14 and [uv](https://github.com/astral-sh/uv) to a
workload that ships no Python toolchain. The interpreter comes from
[python-build-standalone](https://github.com/astral-sh/python-build-standalone),
the relocatable builds `uv python install` uses. It lands in `/opt/python`, and
`uv` and `uvx` land in `/usr/local/bin`.

## Usage

```sh
sbx run docker.io/sbx/claude:latest --kit docker.io/sbx/python:latest .
```

From git, or from a local checkout:

```sh
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=main&dir=python" .
sbx run ./claude --kit ./python .
```

Inside the sandbox, `python3 --version` and `uv --version` report the kit's
versions.

## How it works

- **A standalone build, not the official image.** The official `python`
  image's interpreter links that image's own system libraries, so it cannot
  travel in an overlay. A python-build-standalone build carries its
  dependencies with it.
- **Both versions are enforced.** The `version` and `uvVersion` args pick what
  is installed, and the build fails unless the interpreter and `uv` report
  exactly those versions, so the two provides are claims about the content.
- **PyPI is allowed at runtime**, `pypi.org` and `files.pythonhosted.org`, so
  `uv` and `pip` can install packages. Nothing else is.
- **A base Python wins.** `PATH` merges by appending, so on a workload that
  ships its own `python3`, that one stays first; `/opt/python/bin/python3` is
  always there by full path.

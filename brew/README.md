# brew

A mixin kit (`kind: mixin`) for [Homebrew](https://brew.sh/) — the
package manager for macOS and Linux. The kit installs Homebrew at
sandbox creation time and configures the environment so `brew` is
available in the PATH.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=brew" brew
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./brew/ brew
```

Once the sandbox is running, you can use `brew` to install packages:

```console
$ brew install gcc
$ brew install python
```

## How it works

The kit installs Homebrew to `/home/linuxbrew/.linuxbrew` and sets
the required environment variables (`HOMEBREW_PREFIX`,
`HOMEBREW_CELLAR`, `HOMEBREW_REPOSITORY`, and updates `PATH`).

The kit's `allowedDomains` covers `ghcr.io`, `github.com`,
`homebrew.bintray.com`, and `formulae.brew.sh` for downloading
Homebrew packages and formulae.

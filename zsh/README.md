# zsh

A mixin kit (`kind: mixin`) for [Zsh](https://www.zsh.org/) — an extended Bourne shell with improvements. The kit installs Zsh at sandbox creation time and configures it as the default shell for the agent user.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=zsh" shell
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./zsh/ shell
```

Once the sandbox is running, Zsh is the default shell. You can verify:

```console
$ echo $SHELL
/usr/bin/zsh
```

## How it works

The kit installs Zsh via `apt-get`, sets it as the default shell for the `agent` user with `chsh`, and creates a basic `.zshrc` configuration file in `/home/agent/.zshrc`. The configuration includes:

- **History**: 10,000 entries with shared, incremental append
- **Autocd**: type a directory name to `cd` into it
- **Spell correction**: suggests command fixes
- **Emacs key bindings**: `Ctrl+A`/`Ctrl+E` for line start/end
- **Convenient aliases**: `ll`, `la`, `l` for `ls` variants

The kit's `allowedDomains` covers `sourceforge.net` for any Zsh plugin downloads.

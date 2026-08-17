# neovim

A mixin that installs the latest stable [Neovim](https://neovim.io) release and injects a bundled `~/.config/nvim` into the sandbox.

## Usage

Pair with any agent. The primary form is its published OCI artifact on Docker Hub:

```console
$ sbx run claude --kit "docker.io/sbx/neovim-kit:latest" ~/my-project
```

Or from a git URL targeting this repo:

```console
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=neovim" ~/my-project
$ sbx run shell  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=neovim" ~/my-project
```

## Bringing your own config

The kit ships a minimal starter `init.lua`. To use your personal config, run the bundled `sync-config.sh` once from the kit directory:

```bash
git clone https://github.com/docker/sbx-kits-contrib.git
cd sbx-kits-contrib/neovim
./sync-config.sh
sbx run claude --kit . ~/my-project
```

`sync-config.sh` copies `~/.config/nvim` into `files/home/.config/nvim/`. Everything under that directory is injected verbatim into `/home/agent/.config/nvim/` when the sandbox is created. Re-run the script whenever your local config changes, then recreate the sandbox to pick up the update.

> **Note**: sandboxes only have access to the mounted workspace directory, not the host home directory. `sync-config.sh` bridges this by copying the config into the kit's `files/` tree on the host before sandbox creation.

If your config uses a plugin manager (lazy.nvim, packer, etc.) that fetches plugins on first launch, add the plugin registry hosts to `permissions.network.allow` in `spec.yaml`.

## How the install works

The `setup.install` step downloads the latest stable Neovim tarball from GitHub releases — `nvim-linux-x86_64.tar.gz` on amd64, `nvim-linux-arm64.tar.gz` on arm64 — extracts it to `/opt`, and symlinks the binary to `/usr/local/bin/nvim`. No system packages are modified.

## Cleanup

The kit leaves no persistent state on the host. Removing the sandbox (`sbx rm <name>`) removes the Neovim install.

> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# neovim

A mixin that installs a pinned [Neovim](https://neovim.io) release and injects a bundled `~/.config/nvim` into the sandbox.

## Usage

Pair with any agent. The primary form is its published OCI artifact on Docker Hub:

```console
sbx run claude --kit "docker.io/docker/sbx-kit-neovim:latest" ~/my-project
```

Or from a git URL targeting this repo:

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=neovim" ~/my-project
sbx run shell  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=neovim" ~/my-project
```

## Bringing your own config

The kit ships a minimal starter `init.lua`. To use your personal config, run the bundled `sync-config.sh` once from the kit directory:

```bash
git clone https://github.com/docker/sbx-kits-contrib.git
cd sbx-kits-contrib/neovim
./sync-config.sh
sbx run claude --kit . ~/my-project
```

`sync-config.sh` copies `~/.config/nvim` into `files/home/.config/nvim/`. `neovim.dockerfile` carries everything under that directory into the kit's overlay layer at `/home/agent/.config/nvim/`, so it is in place before the agent starts. Re-run the script whenever your local config changes, then recreate the sandbox to pick up the update.

> **Note**: sandboxes only have access to the mounted workspace directory, not the host home directory. `sync-config.sh` bridges this by copying the config into the kit's `files/` tree on the host before sandbox creation.

If your config uses a plugin manager (lazy.nvim, packer, etc.) that fetches plugins on first launch, add the plugin registry hosts to a `runtime.allow` list under a `com.docker.sandbox/network-policy@1` capability in `neovim.yaml`. The kit as shipped declares no network policy at all — the starter `init.lua` runs no plugin manager and needs no egress — and an absent phase grants nothing.

## How the install works

Neovim arrives in the kit's **layers**, not from a hook at sandbox create. `neovim.dockerfile` downloads the pinned release tarball at build time — `nvim-linux-x86_64.tar.gz` on amd64, `nvim-linux-arm64.tar.gz` on arm64, selected from buildx's `TARGETARCH` — extracts it to `/opt`, symlinks the binary to `/usr/local/bin/nvim`, and fails the build unless `nvim --version` reports the version the kit declares. No system packages are involved at all, at build or at create.

Earlier revisions did that download in a `lifecycle@1` install hook, because a v2 mixin had no way to carry content and this recipe therefore only carried the static files. Nothing about the work needed sandbox-create time, so moving it to build removes a download from every sandbox creation, fixes the release in a scannable published layer, turns a bad release into a red build instead of a sandbox that fails to come up — and removes the kit's network policy and its `deb/dpkg` requirement outright, since the three GitHub hosts existed only for that hook and only the hook ever asked dpkg anything.

The pin lives in the descriptor's `version` arg and the kit publishes `provides: ["neovim@${{ kit.args.version }}"]`. The arg carries `buildArg: NVIM_VERSION`, which now reaches the recipe the ordinary way as a build argument; a build-phase arg is also expanded through the *whole* published descriptor, so the same value lands in the provide and in the descriptor's top-level `version:`, which references the arg rather than carrying a release number of the kit's own. A create-phase (`env:`) arg could not do that — a published descriptor is refused while any arg reference remains in a `provides` entry — so the provide would have to float instead.

Bump it by resolving GitHub's `stable` alias to the release it currently names, and dropping the `v` (versions carry no prefix; the hook adds it back):

```console
curl -fsS https://api.github.com/repos/neovim/neovim/releases/latest \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
```

`EDITOR` and `VISUAL` are set to `nvim` from `/etc/profile.d/neovim-env.sh`, which the overlay ships and the base's login shell sources. A mixin cannot set container environment variables directly — its image config is not the composed image's.

## Cleanup

The kit leaves no persistent state on the host. Removing the sandbox (`sbx rm <name>`) removes the Neovim install.

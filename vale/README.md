> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# vale

A mixin kit (`kind: mixin`) that installs a pinned, checksum-verified [Vale](https://vale.sh/) prose linter from GitHub releases.

## Usage

```console
sbx run --kit "docker.io/docker/sbx-kit-vale:latest" claude
agent@...$ vale --version
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vale" claude
```

Or with a local clone:

```console
sbx run --kit ./vale/ claude
```

Vale is on `PATH` from the moment the sandbox exists. To lint a directory:

```console
agent@...$ vale sync        # download styles referenced by .vale.ini
agent@...$ vale ./docs/
```

## How the install works

`vale` arrives in the kit's **layers**, not from a hook at sandbox create.
`vale.dockerfile` downloads the pinned release tarball at build time, checks it
against a per-architecture SHA256, extracts the single static binary to
`/usr/local/bin/vale`, and then fails the build unless that binary reports the
version the descriptor promises. The overlay is that one file.

Earlier revisions did the download in a `lifecycle@1` install hook, because a v2
mixin had no way to carry content at all. Nothing about the work needed
sandbox-create time, so moving it to build removes a download from every sandbox
creation, pins the binary by digest in a scannable published layer, turns a bad
release into a red build instead of a broken sandbox, and drops the kit's
install-phase network grant.

## Versioning

The kit installs Vale v3.14.2. To update, change `VALE_VERSION` and both SHA256
values in `vale.dockerfile`, and the version in `vale.yaml`'s `provides`.

The build selects its asset from buildx's `TARGETARCH`, so a
`--platform linux/amd64,linux/arm64` build resolves each leg to its own tarball.
The kit also no longer requires `deb/dpkg` of the base it composes onto: that
requirement existed because the hook asked `dpkg --print-architecture`, and
nothing asks dpkg anything any more.

## Network policy

The kit allows `github.com`, `objects.githubusercontent.com` and
`release-assets.githubusercontent.com` in the **runtime** phase only.

There is no install phase. It used to name the same three hosts for the release
tarball, and the builder fetches that now — a policy that governs sandboxes does
not govern the builder. The runtime grant is a genuinely different one that
happens to name the same hosts: `vale sync` fetches the styles a `.vale.ini`
references from GitHub releases over the same redirect chain, from the agent's
steady state. Phase lists grant nothing where a host is absent, so dropping it
along with the install phase would have left `vale sync` failing with a proxy
error.

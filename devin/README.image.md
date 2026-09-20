# sbx/devin-image

Base image for the Devin CLI kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- [Devin CLI](https://devin.ai), installed with Cognition's own install script
  from `cli.devin.ai`. It is a per-user installer, so the tree lands under
  `/home/agent` owned by the non-root `agent` user that will run it.
- `devin-cli` — the real binary, reachable under that name.
- `devin` — an authentication wrapper script, which is what the sandbox
  entrypoint resolves. See below.

## Why `devin` is a wrapper and `devin-cli` is the binary

Devin CLI authenticates from `~/.local/share/devin/credentials.toml`, and that
file cannot be provisioned ahead of time: the durable credential only exists
after an account has signed in. So something has to run before the agent does —
check whether a usable credential is present, drive Devin's own login flow when
it is not, and replace whatever key that login leaves on disk with the sandbox
proxy's placeholder so the container never holds a usable secret.

That something is the wrapper, and it takes the name `devin` so the image
config's `ENTRYPOINT` stays the obvious `[devin, ...]`.

The rename in [`devin.dockerfile`](./devin.dockerfile) has two steps that look
fussy and are not:

- `devin-cli` is created with `readlink` **without** `-f`. That copies the
  installer's symlink *target* — its "current version" pointer — rather than
  resolving it all the way to the version directory that happened to be current
  at build time, so `devin update` moves `devin-cli` with it instead of leaving
  it pinned. (`devin` is the wrapper, a regular file; the installer refuses to
  overwrite a non-symlink at that path rather than clobbering it.)
- The installer's own `devin` symlink is **removed** before the wrapper is
  `COPY`ed over that path. `COPY` onto an existing symlink writes *through* it,
  which would overwrite the real CLI binary inside the version directory — and
  the wrapper would then exec itself.

`devin --version` runs between the install and the rename. That check is not
decoration: the install script ends with an interactive `devin setup` wizard
that cannot complete without a TTY and exits non-zero, so the pipeline's status
has to be discarded with `|| true` and the outcome asserted separately. The
download is also unauthenticated and unpinned — no credential is sent, and the
script itself is verified by nothing — it does checksum the bundle it
downloads, but against a manifest from the same origin — and `curl | bash`
exits 0 whenever curl dies after producing *some* output, so a truncated
response would otherwise ship a broken image and report success.

## Build args

- `BASE_IMAGE` — re-point or digest-pin the base.

There is deliberately **no** version arg. The installer takes its target from a
manifest it fetches itself, and its `PINNED_VERSION` is a literal the script
overwrites unconditionally, not an environment variable a caller can set — so
an argument the script quietly ignored would read as a pin while pinning
nothing. Cognition publishes per-version setup scripts
(`<base>/cli/<version>/setup.sh`); wiring one in here is the supported way to
pin, if a release needs it. Pin the whole image by digest instead in the
meantime.

Runs as the non-root `agent` user, with
`CMD ["devin", "--permission-mode", "dangerous", "--respect-workspace-trust=false"]`
— the same argv the kit's entrypoint uses, so a plain `docker run` of this
image behaves the way the sandbox does.

## Kit

[`docker.io/sbx/devin-kit`](https://hub.docker.com/r/sbx/devin-kit)

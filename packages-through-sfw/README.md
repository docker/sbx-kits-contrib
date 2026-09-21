# Packages through SFW

A mixin that installs [Socket Firewall Free](https://socket.dev/) (`sfw`)
and routes `npm`, `pip`, `pip3`, and `python3 -m pip` package-manager
commands through it inside a Docker Sandbox when they are resolved through
`PATH`.

Socket Firewall Free runs without Socket API keys or configuration files.
This kit targets public npm and PyPI package installs. Private registries,
custom registries, and organization policy features require Socket Firewall
Enterprise or a forked kit with the right network and credential wiring.

## Usage

Run it with any agent kit or built-in agent, from its published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/docker/sbx-kit-packages-through-sfw:latest" <agent>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=packages-through-sfw" <agent>
```

For local development, point `--kit` at this directory:

```console
sbx run --kit ./packages-through-sfw/ <agent>
```

After the sandbox starts, package-manager commands invoked by name are routed
through `sfw`:

```console
sfw --version
npm view is-odd version
python3 -m pip index versions pyfiglet
pip index versions pyfiglet
```

## How the install works

`packages-through-sfw.dockerfile` downloads Socket Firewall Free v1.10.0
from the upstream GitHub release **at build time**, verifies the binary
against the per-arch SHA256 captured beside the download, and stages it as
`/usr/local/bin/sfw` in an overlay together with the shims and the
`/etc/profile.d` snippet. Creating a sandbox therefore downloads nothing,
and GitHub is not on the kit's network policy at all.

Two lifecycle install hooks remain, because neither is content:

- **apt prerequisites** — Node.js, npm, Python pip, curl and CA
  certificates come from the composed base's own apt repositories. apt
  packages cannot travel in an overlay: they need the base's real dpkg
  database, and an overlay cannot carry a package's shared-library
  closure. The shims wrap the tools this hook installs.
- **the `~/.bashrc` line** — an overlay's files *replace* the base's
  rather than merging with them, so shipping `/home/agent/.bashrc` would
  shadow whatever the composed workload put there instead of adding one
  line to it. Appending to a file this kit does not own is create-time
  work by nature.

The build supports Linux `amd64` and `arm64`, which cover the normal
Docker Desktop sandbox architectures; a multi-platform build resolves each
leg to its own pinned asset.

## How the wrappers work

The kit installs PATH shims in `/usr/local/bin` for `npm`, `pip`, `pip3`,
and `python3`. That catches non-interactive agent tool calls as long as the
tool is invoked by name:

```sh
npm:  PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw npm "$@"
pip:  exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip "$@"
pip3: exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip3 "$@"
python3 -m pip: exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip "$@"
```

The restricted `PATH` keeps `sfw` from recursively calling the shim. The
`python3` shim only intercepts `python3 -m pip ...`; all other Python
commands delegate to the real interpreter. The pip shims clear Python CA
override variables so Socket Firewall can provide the certificate environment
for its local wrapper proxy under the sandbox egress proxy.

For interactive shells, the overlay also ships shell functions in
`/etc/profile.d/packages-through-sfw.sh`, and an install hook sources that
file from the agent user's `~/.bashrc`. Those functions delegate to the
PATH shims.

## Scope and bypasses

Direct absolute paths such as `/usr/bin/npm`, `/usr/bin/python3 -m pip`, or
`venv/bin/python -m pip` bypass Socket Firewall because they do not resolve
through `PATH`. Virtualenv entrypoints such as `venv/bin/pip` do the same.
The kit does not rewrite venv interpreters or entrypoints because that can
break Python tooling. Docker Sandbox egress policy still controls which hosts
those commands can reach, but Socket Firewall analysis only applies when the
package-manager command goes through `sfw`.

## Network policy

The kit's `com.docker.sandbox/network-policy@1` capability is phase-scoped,
and for this kit the split is the point rather than a formality. Everything
the *installation* needs closes before the agent starts; what stays open is
exactly the package-manager egress the kit exists to mediate.

`install` covers:

- the apt sources `apt-get update` refreshes for the prerequisites — all
  three Ubuntu hosts for cross-arch coverage, plus Docker's repo, which the
  `shell-docker` base pre-adds

The GitHub release hosts used to be here too. They are gone: the `sfw`
download happens on the builder now, which this policy does not govern.

`runtime` covers:

- Socket API hosts used by Socket Firewall Free, consulted on every install
- the public npm registry
- PyPI package metadata and file hosts

Add any extra package registries to `runtime` in a fork, or with a
per-sandbox policy rule.

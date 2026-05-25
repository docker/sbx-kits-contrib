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

Run it with any agent kit or built-in agent:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=packages-through-sfw" <agent>
```

For local development, point `--kit` at this directory:

```console
$ sbx run --kit ./packages-through-sfw/ <agent>
```

After the sandbox starts, package-manager commands invoked by name are routed
through `sfw`:

```console
$ sfw --version
$ npm view is-odd version
$ python3 -m pip index versions pyfiglet
$ pip index versions pyfiglet
```

## How the install works

The kit installs Node.js, npm, Python pip, curl, and CA certificates from
the base image's apt repositories. It then downloads Socket Firewall Free
v1.10.0 from the upstream GitHub release, verifies the binary against a
SHA256 captured in `spec.yaml`, and installs it as `/usr/local/bin/sfw`.

The initial install supports Linux `amd64` and `arm64`, which cover the
normal Docker Desktop sandbox architectures.

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

For interactive shells, the kit also writes shell functions to
`/etc/profile.d/packages-through-sfw.sh` and sources that file from the agent
user's `~/.bashrc`. Those functions delegate to the PATH shims.

## Scope and bypasses

Direct absolute paths such as `/usr/bin/npm`, `/usr/bin/python3 -m pip`, or
`venv/bin/python -m pip` bypass Socket Firewall because they do not resolve
through `PATH`. Virtualenv entrypoints such as `venv/bin/pip` do the same.
The kit does not rewrite venv interpreters or entrypoints because that can
break Python tooling. Docker Sandbox egress policy still controls which hosts
those commands can reach, but Socket Firewall analysis only applies when the
package-manager command goes through `sfw`.

## Network policy

The kit's network allowlist covers:

- GitHub release hosts for the pinned `sfw` binary download
- Socket API hosts used by Socket Firewall Free
- the public npm registry
- PyPI package metadata and file hosts

Add any extra package registries in a fork or with a per-sandbox policy rule.

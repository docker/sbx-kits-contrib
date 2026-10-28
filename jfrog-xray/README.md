# jfrog-xray - JFrog Xray security and license scanning

A mixin kit that installs the [JFrog CLI](https://jfrog.com/getting-started-with-jfrog-cli/) (`jf`) pre-wired to your JFrog Platform, so an agent can run **Xray** security and license scans (`jf audit`, `jf scan`, `jf docker scan`) against dependencies, binaries, and container images. Because Xray shares package metadata with Artifactory, a scan reports not just a CVE but its full impact path through your dependency graph.

The JFrog access token never enters the container: `JF_ACCESS_TOKEN` is a proxy-managed placeholder, and the sbx proxy injects the real token on the wire for requests to your JFrog host.

Pairs with any base agent.

## Prerequisites

- A JFrog Platform host: SaaS (`mycompany.jfrog.io`) or self-hosted (`artifactory.internal.example.com`).
- A JFrog **access token** with Xray read and scan scopes.

Store the token once on the host (the kit declares the `jfrog` credential):

```console
sbx secret set jfrog
```

## Usage

Your JFrog host is per-user, so pass it with `--kit-arg jfrog-xray.jfrog_host=...`:

```console
sbx run --kit "docker.io/sbx/jfrog-xray-kit:latest" --kit-arg jfrog-xray.jfrog_host=mycompany.jfrog.io claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=jfrog-xray" --kit-arg jfrog-xray.jfrog_host=mycompany.jfrog.io claude
sbx run --kit ./jfrog-xray/ --kit-arg jfrog-xray.jfrog_host=mycompany.jfrog.io claude
```

`jfrog_host` defaults to a placeholder (`your-company.jfrog.io`), so the kit installs and validates without the arg, but scans have no real host to reach until you set it.

Common scans inside the sandbox:

```console
jf audit                       # scan the current project's declared dependencies
jf audit --licenses            # also report license-compliance results
jf audit --format=json         # machine-readable output
jf scan <path>                 # scan a file, folder, or binary
jf docker scan <image>         # scan a local container image
jf rt ping                     # verify connectivity
```

## How auth and egress work

The kit declares a `jfrog` credential with one inject rule for your host, using the `bearer` scheme (`Authorization: Bearer <token>`). `jf` reads `JF_URL` and `JF_ACCESS_TOKEN` directly, so no `jf config add` is needed. `JF_ACCESS_TOKEN` is the proxy-managed sentinel inside the container; the proxy swaps in the real token on outbound requests to your JFrog host and nowhere else.

The network allowlist is limited to:
- `releases.jfrog.io` and `releases-cdn.jfrog.io` - install-time download of the pinned `jf` binary (the release host 302-redirects the blob to the CDN, so both are needed).
- your `jfrog_host` - the Xray and Artifactory REST API at runtime.

If a scan reports "Xray is not entitled", the token lacks Xray scopes or the platform does not have Xray enabled.

## Self-hosted platforms

Self-hosted Artifactory/Xray works the same way: pass its hostname as `jfrog_host`. If the platform also serves other hosts you need (for example a separate registry domain), add them to `permissions.network.allow`.

## Version pinning

`jf` is installed from a version- and SHA256-pinned JFrog release (no `curl | sh`). To bump, change `JF_VERSION` and both per-arch checksums in `spec.yaml`; the checksums are the sha256 of the raw `jf` binary at `https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/<version>/jfrog-cli-linux-<arch>/jf`.

## Cleanup

```console
sbx secret rm -g --service jfrog
```

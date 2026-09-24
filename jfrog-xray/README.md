> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

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
sbx run --kit "docker.io/docker/sbx-kit-jfrog-xray:latest" --kit-arg jfrog-xray.jfrog_host=mycompany.jfrog.io claude
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

The kit declares a `jfrog` credential with one inject rule for your host, using the `bearer` scheme (`Authorization: Bearer <token>`). The `jf` wrapper derives `JF_URL` from `jfrog_host`, and the CLI reads the proxy-managed `JF_ACCESS_TOKEN` sentinel. The proxy swaps in the real token on outbound requests to your JFrog host and nowhere else, so no `jf config add` is needed.

The runtime network allowlist is limited to your `jfrog_host` for the Xray
and Artifactory REST APIs. The pinned CLI is downloaded while building the
kit, so its JFrog release hosts are not sandbox grants.

If a scan reports "Xray is not entitled", the token lacks Xray scopes or the platform does not have Xray enabled.

## Self-hosted platforms

Self-hosted Artifactory/Xray works the same way: pass its hostname as `jfrog_host`. If the platform also serves other hosts you need (for example a separate registry domain), add them to the runtime allowlist in `jfrog-xray.yaml`.

## Version pinning

`jf` is installed from a version- and SHA256-pinned JFrog release (no `curl | sh`). To bump, change the `version` arg default in `jfrog-xray.yaml` and both per-arch checksums in `jfrog-xray.dockerfile`; the checksums are the sha256 of the raw `jf` binary at `https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/<version>/jfrog-cli-linux-<arch>/jf`.

## Cleanup

```console
sbx secret rm -g --service jfrog
```

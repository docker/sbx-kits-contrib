# trivy

A standalone agent kit (`kind: agent`) for the [Trivy](https://trivy.dev/)
open-source vulnerability scanner from [Aqua Security](https://aquasec.com/).
The kit installs `trivy` from a pinned, digest-verified GitHub release at
sandbox creation time and drops you into a bash shell with the binary on
`PATH` and your workspace mounted as the working directory.

## Why this kit exists

In March 2026 the threat actor [TeamPCP compromised Trivy](https://www.wiz.io/blog/trivy-compromised-teampcp-supply-chain-attack)
itself — force-pushing GitHub Action tags, shipping an infected v0.69.4
binary, and using the resulting credential harvest to weaponize 47+ npm
packages downstream. Microsoft's
[response guidance](https://www.microsoft.com/en-us/security/blog/2026/03/24/detecting-investigating-defending-against-trivy-supply-chain-compromise/)
prescribes "governed execution pipelines" with "vault isolation and egress
filtering". This kit puts that prescription one `sbx run` away: scanner
runs in a microVM, your `~/.aws` / `~/.ssh` / `~/.docker/config.json` are
not mounted, egress is allowlisted to four hosts (release fetch + vuln DB),
and the install is digest-pinned against tag-rewrite attacks.

## Usage

```console
$ cd ~/work/some-project
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=trivy" trivy .
agent@trivy-some-project:/Users/mark/work/some-project$ trivy fs .
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./trivy/ trivy .
```

The first launch downloads, verifies, and installs Trivy. Subsequent
launches reuse the sandbox; the vuln DB is cached on a persistent volume.

## How auth and egress work

Trivy is fully open source — **no API key needed** for the standard scan
flows (`fs`, `repo`, plain `image`). Aqua's commercial feeds (premium
indicators, SaaS reporting) are out of scope for this kit; if you need
them, fork and add the appropriate `serviceDomains` and `credentials`.

The kit's `allowedDomains` covers exactly five hosts:

| Host | Why |
| --- | --- |
| `github.com` | Release page entry point for the install tarball (302-redirects) |
| `release-assets.githubusercontent.com` | Where GitHub release blobs actually live (the redirect target) |
| `mirror.gcr.io` | Trivy's default *primary* vuln DB source (`mirror.gcr.io/aquasec/trivy-db`) |
| `ghcr.io` | Trivy's *fallback* vuln DB source (`ghcr.io/aquasecurity/trivy-db`) |
| `pkg-containers.githubusercontent.com` | GHCR blob storage backend |

Both DB sources are declared in the allowlist rather than redirecting Trivy
to one specific source via env vars. The reason: env-var-based security
config is fragile — anything running as the agent user inside the sandbox
can override or unset it. Declaring all required egress at the policy
layer keeps the trust footprint observable and survives a compromised
agent process trying to subvert it.

Tightening this footprint — both the install channel (currently a pinned
GitHub release) and the DB source (currently Trivy's defaults) — is the
v2 path: install via a hardened-distribution channel where the entire
build pipeline is observable and signed. Deferred until that integration
lands cleanly at the runtime layer.

Anything else — registries you want to scan images from, custom vuln DB
mirrors, your reporting endpoint — should be added with a per-sandbox or
operator-level allow rule, *not* in the kit:

```console
$ sbx policy allow network --sandbox trivy-some-project "registry-1.docker.io,auth.docker.io,production.cloudflare.docker.com"
```

This keeps the kit's default footprint minimal and forces deliberate
opt-in to anything image-registry-shaped.

## Image scanning

By default the kit does **not** mount the host Docker socket. Image
scanning has three workable modes:

1. **`trivy image --input <tarball>`** *(recommended)* — `docker save`
   the image to a tarball on the host, mount the tarball into the
   workspace, scan it inside the sandbox. Zero socket exposure.
2. **`trivy image <registry>/<repo>:<tag>`** — Trivy pulls the image
   itself directly. Add the registry's hosts to a per-sandbox allow
   rule (see above). Requires no socket.
3. **Bind-mount `/var/run/docker.sock`** — works but defeats the
   isolation. Don't.

For routine scanning of *what's in front of you*, prefer
`trivy fs .` against the workspace mount.

## Version pinning

The install command pins:

- `TRIVY_VERSION=0.70.0` (published 2026-04-17, post-TeamPCP)
- SHA256 per-arch: `Linux-64bit` and `Linux-ARM64`

To bump: edit `spec.yaml`, update both the version string and the
SHA256s sourced from the release's `checksums.txt`. Sigstore signature
verification is a worthwhile follow-up but out of scope for v1.

## Cleanup

`sbx rm trivy-<basename>` removes the sandbox and its persistent vuln
DB cache. The workspace bind-mount on the host is untouched.

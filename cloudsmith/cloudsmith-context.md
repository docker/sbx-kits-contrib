Cloudsmith artifact management: the `cloudsmith` CLI is installed and the
CLOUDSMITH_API_KEY credential is injected by the sbx proxy on requests to
api.cloudsmith.io. Use it to publish and manage packages across 30+ formats
(Docker, npm, PyPI, Maven, Debian, RPM, Helm, Cargo, Go, NuGet, and more).

The key is never present in the sandbox -- the env var reads `proxy-managed`,
and the proxy swaps in the real token on egress. So run the CLI directly; do
not try to read or echo the key.

    cloudsmith whoami                                  # verify auth
    cloudsmith list packages OWNER/REPO                # list packages (alias: ls pkg)
    cloudsmith push python OWNER/REPO dist/pkg.whl     # upload a Python wheel
    cloudsmith push docker OWNER/REPO image.tar        # upload a Docker image tarball
    cloudsmith push deb OWNER/REPO/ubuntu/24.04 pkg.deb
    cloudsmith status OWNER/REPO/<slug>                # check a package's sync status
    cloudsmith delete OWNER/REPO/<slug>                # remove a package

`OWNER` is your Cloudsmith workspace (organization) slug and `REPO` is the
repository slug. Run `cloudsmith push --help` for the full list of formats and
per-format arguments.

Reach for this whenever a task involves publishing a build artifact, inspecting
what's already in a repository, or wiring a project's package manager to a
Cloudsmith-hosted registry.

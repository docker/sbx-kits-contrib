## Trivy

This sandbox carries [Trivy](https://github.com/aquasecurity/trivy), Aqua's
open source vulnerability scanner, as a mixin: the binary is on `PATH`, but
the sandbox's launch command belongs to the base workload.

```console
trivy fs .            # scan the workspace
trivy image <ref>     # scan an image
```

The first scan pulls the vulnerability database as an OCI artifact from
`mirror.gcr.io`, falling back to `ghcr.io`. Those two hosts and
`pkg-containers.githubusercontent.com` are the only egress this kit grants;
a scan that needs anything else will be refused by the sandbox's network
policy rather than silently reaching it.

The scanner runs sandboxed on purpose: a vulnerability scanner parses
untrusted input from whatever it is pointed at, and this confinement is what
keeps that from reaching the host.

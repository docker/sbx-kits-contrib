## JFrog Xray

The JFrog CLI `jf` is installed and pre-wired to your JFrog Platform. Its
wrapper sets `JF_URL` from the configured host for each invocation, and
`JF_ACCESS_TOKEN` is a **proxy-managed placeholder** - never the real token.
The sandbox proxy injects the real value on outbound requests to your JFrog
host, so there is no `jf config add` step and the token never lives inside
the sandbox.

Xray is the JFrog Platform's security & compliance engine. Because it shares
package metadata with Artifactory, a scan reports not just a CVE but its full
impact path through your dependency graph - enabling real risk assessment and
remediation, not just a flat vulnerability list.

Common scans:
- `jf audit` - scan the current project's declared dependencies (npm, pip,
  Go, Maven, Gradle, NuGet, …) for vulnerabilities and license violations.
- `jf audit --licenses` - also report license-compliance results.
- `jf audit --format=json` - machine-readable output you can parse.
- `jf scan <path>` - scan an arbitrary file, folder, or binary.
- `jf docker scan <image>` - scan a local container image.
- `jf build-scan <build-name> <build-number>` - scan a published build.

Verify connectivity with `jf rt ping`; inspect config with `jf config show`.
If a scan reports "Xray is not entitled", the token lacks Xray scopes or the
platform doesn't have Xray enabled.

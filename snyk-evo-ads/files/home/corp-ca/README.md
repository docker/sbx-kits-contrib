# Corporate root CA certificates

For the published kit, pass `-e SNYK_CORP_CA_PEM="$(cat /path/to/ca.pem)"`
at sandbox creation. The value can contain one or more PEM certificates;
the kit splits them into individual `.crt` files in the system trust store
before Snyk downloads run. Recreate existing sandboxes to apply changes.
See the [repo README](../../../README.md#staging-the-corporate-ca-certificate)
for the macOS keychain command and launch examples.

For a local checkout (`--kit .`), every `*.crt` file in this directory is
also installed:

```text
files/home/corp-ca/zscaler-root-ca.crt → /home/agent/corp-ca/zscaler-root-ca.crt
```

Use one PEM certificate per `.crt` file. No `snyk-evo-ads.yaml` changes
are needed: its `lifecycle@1` install hook globs `*.crt` and explicitly
allows `SNYK_CORP_CA_PEM`. Environment PEM bundles are split per certificate
and CRLF is normalized; incomplete or non-PEM input fails installation.
Skip both methods if your network does not intercept TLS; missing
certificates print a warning and setup continues.

## Certificate rules

- **PEM, not DER** — starts with `-----BEGIN CERTIFICATE-----`. Convert DER
  with `openssl x509 -inform der -in in.cer -out out.crt`.
- **Root CA, not a server leaf** — use your proxy's trusted root certificate.
- **`.crt` extension for staged files** — other files here are ignored.
- **Certificates only, never private keys** — the root CA is public, not a secret.

Validate a certificate before creating a sandbox:

```bash
openssl x509 -in /path/to/ca.pem -noout -text \
  | grep -A1 'Basic Constraints'                 # must read CA:TRUE
```

`*.crt` here is gitignored. To share a root CA with your team, check your
organization's policy before force-adding it with `git add -f`.

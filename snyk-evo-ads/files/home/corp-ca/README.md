# Put your corporate root CA certificate(s) here

Every `*.crt` file in this directory is installed into the sandbox's system trust store
before the Snyk downloads below run.

```
files/home/corp-ca/zscaler-root-ca.crt   →   /home/agent/corp-ca/zscaler-root-ca.crt
```

Drop in as many certs as your proxy chain needs. You do not edit `spec.yaml` to add one —
the install step globs `*.crt`.

**Skip this entirely if your network does not intercept TLS.** The CA step is non-fatal by
design; it prints a warning and carries on.

## Export the cert

macOS, Zscaler, from the System keychain:

```bash
security find-certificate -a -c "Zscaler Root CA" -p \
  /Library/Keychains/System.keychain \
  > files/home/corp-ca/zscaler-root-ca.crt
```

Other export routes — Linux paths, and pulling the root out of the live TLS chain — are in
the [repo README](../../../README.md#staging-the-corporate-ca-certificate), along with a
one-liner to check whether you need a cert at all before assuming either way.

## Four rules

| Rule | What happens if you break it |
| --- | --- |
| **PEM, not DER** — file starts with `-----BEGIN CERTIFICATE-----` | A binary `.cer` is staged into the VM and then silently ignored by `update-ca-certificates`. Convert: `openssl x509 -inform der -in in.cer -out out.crt` |
| **`.crt` extension** | `update-ca-certificates` only reads `*.crt`. A `zscaler.pem` does nothing. |
| **The ROOT, not the leaf** | Trusting the intercepted server cert doesn't establish the chain. You want the self-signed CA at the top. |
| **Nothing but certs in here** | The install step installs every `*.crt` it finds. Non-`.crt` files (like this README) are ignored and safe. |

## Check before you spend a sandbox create

```bash
head -1 files/home/corp-ca/*.crt        # must be BEGIN CERTIFICATE
openssl x509 -in files/home/corp-ca/your-ca.crt -noout -text \
  | grep -A1 'Basic Constraints'                 # CA:TRUE
```

## A note on committing certs

`*.crt` in this directory is **gitignored** by default — see the repo `.gitignore`.

A corporate root CA is a public key, not a secret, so committing one to share with your team
is usually fine. If that's what you want, force-add it and check your org's policy first:

```bash
git add -f files/home/corp-ca/zscaler-root-ca.crt
```

Requires `sbx` 0.38.0 or later — that's when `files/` staging landed. The
kit as a whole requires 0.39.0 or later (see the repo README) for the
sandbox identity variables its startup commands depend on; that floor, not
this one, is what actually gates using the kit.

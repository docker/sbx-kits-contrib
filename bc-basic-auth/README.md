> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# bc-basic-auth

A declaration-only mixin that allows access to a Microsoft Dynamics 365
Business Central backend and injects Basic authentication through the sandbox
credential proxy. The username and password stay on the host.

## Prerequisites

Store the credentials on the host under the `microsoft-bc` service as base64-encoded
`username:password`:

```console
$ sbx secret set -g microsoft-bc "$(printf '%s:%s' '<username>' '<password>' | base64 | tr -d '\n')"
```

The credential is required: sandbox creation fails when the `microsoft-bc` secret is not
available.

## Usage

Set `host` to the Business Central backend hostname, without a scheme, port, or
path:

```console
$ sbx run \
    --kit docker.io/sbx/bc-basic-auth:latest \
    --kit-arg bc-basic-auth.host=bc.example.com \
    <agent>
```

Or directly from this repository:

```console
$ sbx run \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=bc-basic-auth" \
    --kit-arg bc-basic-auth.host=bc.example.com \
    <agent>
```

Or from a local clone:

```console
$ sbx run \
    --kit ./bc-basic-auth \
    --kit-arg bc-basic-auth.host=bc.example.com \
    <agent>
```

Kit v3 needs an `sbx` release candidate or nightly build from
[docker/sbx-releases](https://github.com/docker/sbx-releases/releases); the
stable line does not load v3 kits.

## How authentication works

The kit contributes no files and runs no lifecycle hooks. It declares the
backend host in the runtime network policy and registers a required credential
for the same host.

When a process sends a request to the configured backend, the sandbox proxy
sets this header:

```text
Authorization: Basic <base64(username:password)>
```

The container never receives the real credential or a placeholder environment
variable. Requests to other hosts are not given the credential.

## Network policy

The runtime allow list contains only the hostname supplied through the required
`host` argument. Add any separate identity, API, or download hosts needed by
your environment through another kit or a per-sandbox network rule.

## Cleanup

Remove the stored credential when it is no longer needed:

```console
$ sbx secret rm -g microsoft-bc
```

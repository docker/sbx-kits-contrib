# azure-cli - Microsoft Azure CLI

A mixin kit that installs the official [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/) (`az`) from Microsoft's own apt repository.

Pairs with any base agent.

## Authentication

Same situation as the `kiro` kit in this repo: there is no API-key or environment-variable path for a human Azure account, so nothing is pre-authenticated. Run inside the sandbox:

```console
az login --use-device-code
```

This prints a URL and a verification code rather than trying to open a browser (there isn't one in the sandbox):

1. Open the URL on your host.
2. Sign in and approve the request.
3. Copy the code it shows back into the sandbox shell.

Auth state then lives in `~/.azure` and survives restarts of this sandbox, but not recreation of it.

Set a default subscription once signed in:

```console
az account set --subscription <id-or-name>
```

### Service principals (fully unattended)

For a sandbox that needs to run unattended (no human to click through a device-code prompt), use a service principal instead of a user login. The kit doesn't wire this up for you - Azure's service-principal credential is an app-id/secret/tenant triple, not a single header-injectable value, so it's outside the credential-injection model this repo's other kits use. Pass the three values in yourself (e.g. as kit args on a fork, or set on the host and read via `sbx run --env`) and run:

```console
az login --service-principal -u <app-id> -p <password-or-cert> --tenant <tenant-id>
```

## Usage

```console
sbx run --kit "docker.io/sbx/azure-cli-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=azure-cli" claude
sbx run --kit ./azure-cli/ claude
```

## What this kit does not do

`permissions.network.allow` covers the device-code login/token-refresh hosts and the handful of APIs a freshly-authenticated session touches first (`management.azure.com`, Microsoft Graph). It cannot enumerate every Azure service host a given workload might call (Storage, Key Vault, Cosmos DB, ...) - a fork or a follow-up PR extending the allowlist is the right move for a specific workload. Flagging this as a real limitation rather than a complete kit, consistent with the TODO in the `codex` kit's own network-policy comments in this repo.

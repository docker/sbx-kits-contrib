# gcloud - Google Cloud CLI

A mixin kit that installs the official [Google Cloud CLI](https://cloud.google.com/sdk/gcloud) (`gcloud`, plus `gsutil` and `bq`) from Google's own apt repository.

Pairs with any base agent.

## Authentication

Same situation as the `kiro` kit in this repo: there is no API-key or environment-variable path for a human Google account, so nothing is pre-authenticated. Run inside the sandbox:

```console
gcloud auth login --no-launch-browser
```

This prints a URL and a verification code rather than trying to open a browser (there isn't one in the sandbox):

1. Open the URL on your host.
2. Sign in and approve the request.
3. Copy the code it shows back into the sandbox shell.

Auth state then lives in `~/.config/gcloud` and survives restarts of this sandbox, but not recreation of it.

Set a default project once signed in:

```console
gcloud config set project <your-project-id>
```

### Service accounts (fully unattended)

For a sandbox that needs to run unattended (no human to click through a device-flow prompt), use a service account key instead of a user login. The kit doesn't wire this up for you - copy the key file into the sandbox's workspace yourself (it's outside the credential-injection model this repo's other kits use, since gcloud's own key-file format isn't a single header-injectable value), then:

```console
gcloud auth activate-service-account --key-file=/path/to/key.json
```

## Usage

```console
sbx run --kit "docker.io/sbx/gcloud-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gcloud" claude
sbx run --kit ./gcloud/ claude
```

## What this kit does not do

`permissions.network.allow` covers the device-flow login/token-refresh hosts and the handful of APIs a freshly-authenticated session touches first (`cloudresourcemanager`, `iam`, `storage`). It cannot enumerate every `*.googleapis.com` host a given workload might call (Compute, BigQuery, Pub/Sub, ...) - add the ones you need with `--kit-arg` is not supported here (egress is a fixed list, not parameterized), so a fork or a follow-up PR extending the allowlist is the right move for a specific workload. Flagging this as a real limitation rather than a complete kit, consistent with the TODO in the `codex` kit's own network-policy comments in this repo.

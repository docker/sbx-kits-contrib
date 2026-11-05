# gcloud

Google Cloud CLI mixin with host-managed authentication. Pairs with a v3
workload on a glibc Linux base; the overlay includes Google's bundled Python.
Only the `gcloud` launcher is exposed.

## Usage

On the host, authenticate using your own Google account or a dedicated,
least-privilege service account. Keep the host CLI and its configuration outside
all sandbox-writable mounts. Replace the executable path and account below:

```sh
gcloud auth login
sbx secret set gcloud --command '/absolute/host/path/to/gcloud auth print-access-token --account=user@example.com' --refresh 5m
```

For service-account impersonation, replace `--account` with
`--impersonate-service-account=sandbox-reader@YOUR_PROJECT.iam.gserviceaccount.com`.
The host identity needs permission to impersonate that service account.

Compose with a v3 workload (built-in v2 aliases are incompatible):

```sh
sbx run docker.io/docker/sbx-kit-claude:latest --kit docker.io/sbx/gcloud:latest .
sbx run docker.io/docker/sbx-kit-claude:latest --kit 'git+https://github.com/docker/sbx-kits-contrib.git#ref=v3&dir=gcloud' .
sbx run docker.io/docker/sbx-kit-claude:latest --kit ./gcloud --kit-arg run_region=us-central1 .
```

The credential is optional so the CLI can run unauthenticated for local commands
such as `gcloud version`. Authenticated API calls require the host secret.

Approve the `gcloud` credential binding for the exact domains in the descriptor, including the selected regional Cloud Run host.
For sandbox-scoped secrets, add `--sandbox YOUR_SANDBOX` to the host command and
create the sandbox with the same name. Command-based secrets require a recent
sbx version supporting `--command` and `--refresh`.

Inside the sandbox:

```sh
gcloud projects describe YOUR_PROJECT --format='value(projectId)'
```

## Authentication and permissions

Google APIs accept an HTTPS Authorization bearer header. `CLOUDSDK_AUTH_ACCESS_TOKEN`
lets gcloud send requests without loading a local credential database. The v3
`credential@1` capability gives it a placeholder; the boundary proxy substitutes
the real token only for the declared API hosts. sbx refreshes the host command's
result every five minutes as needed. No real token or refresh token is mounted
or written into the sandbox by this kit.

The `apiKey` capability describes bearer-header presentation, even though the
value comes from Google OAuth. Native OAuth login interception would also need
secure capture of the initial authorization-code exchange and a host-side
Google OAuth provider. This kit does not claim to implement that bootstrap.
Do not run `gcloud auth login` inside the sandbox or mount host gcloud config.

Resource Manager, Compute, Cloud Run, and Storage JSON API hosts are explicitly
allowed. Cloud Run CLI uses `REGION-run.googleapis.com`; allowing only
`run.googleapis.com` does not authenticate regional CLI requests. The
`run_region` create-time argument defaults to `us-central1`, sets
`CLOUDSDK_RUN_REGION`, and adds exactly that regional host to both lists.
Supply `--kit-arg run_region=YOUR_REGION` when creating the sandbox. Selecting a
different `--region` in gcloud does not widen credential injection. Recreate with
the matching kit argument, or explicitly extend the descriptor and binding for
multiple regions. The global v2 REST API remains available at `run.googleapis.com`.

An empty `gcloud auth list` or missing ADC is expected with this authentication
method. Test a read-only API operation with an explicit project instead.

IAM (`iam.googleapis.com`) and Cloud SQL (`sqladmin.googleapis.com`) are outside
the default contract. Add further hosts to both the network policy and credential injection
rules, then approve the updated binding. No wildcard Google API access is granted.
Other composed kits can widen the effective network policy.

The agent can perform any operation permitted by the supplied identity on these
APIs. Credential isolation does not make those operations read-only or constrain
project IDs. Prefer a dedicated account with minimal IAM permissions. APIs that
mint tokens, sign data, or return secrets require separate review because their
responses can disclose credentials.

ADC, gsutil, bq, SSH, registry login, signed URLs, and native gRPC clients are not
configured. Host refresh-token revocation or Google reauthentication requirements
must be handled by signing in again on the host.

## Build

```sh
cd gcloud
docker buildx build . -f gcloud.yaml --build-arg version=592.0.0 --output type=cacheonly
```

The version defaults to `592.0.0`; `version` maps to `GCLOUD_VERSION`, selects the
Google CLI image, and sets the published version and provide. The recipe checks
the relocated command's version without network access as uid 1000.

## Cleanup

Remove a provisioned host secret when no longer needed:

```sh
sbx secret rm gcloud
# For a scoped secret:
sbx secret rm gcloud --sandbox YOUR_SANDBOX
```

[Google authentication](https://docs.cloud.google.com/sdk/docs/authenticate) ·
[Docker credential management](https://docs.docker.com/ai/sandboxes/configuration/credentials)

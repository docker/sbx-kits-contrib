# cloudsmith-cli

Installs the [`cloudsmith` CLI](https://github.com/cloudsmith-io/cloudsmith-cli) and sends a Cloudsmith API key to `api.cloudsmith.io` through the sandbox proxy. Companion to [`cloudsmith-repo`](https://github.com/docker/sbx-kits-contrib/tree/main/cloudsmith-repo), which pulls packages and carries no API access. Compose this kit only when the agent needs the API (list, inspect, publish). Works with any base agent.

## Usage

Store the API key once (optional; without it the CLI installs and `cloudsmith whoami` reports no user):

```console
sbx secret set cloudsmith-api-key
```

Create a sandbox, usually with the pull kit:

```console
sbx run claude --kit "docker.io/sbx/cloudsmith-repo-kit:latest" --kit "docker.io/sbx/cloudsmith-cli-kit:latest" --kit-arg cloudsmith-repo.path=/acme/prod .
```

The Git examples require `github.com/docker/` in Docker's `kit.allowedSources` setting. Preserve any existing allowed sources when adding it; see [Restrict kit sources](https://docs.docker.com/ai/sandboxes/customize/kits/#restrict-kit-sources).

Or from git or a local clone:

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=cloudsmith-cli" .
sbx run claude --kit ./cloudsmith-cli/ .
```

Inside the sandbox:

```console
cloudsmith --version
cloudsmith whoami
cloudsmith list packages ORG/REPO
```

## Arguments

`--kit-arg cloudsmith-cli.<name>=<value>`.

| Argument | Default | Value |
| --- | --- | --- |
| `cli-version` | `1.27.0` | A release number, or `latest` |

## Authentication

On first use, approve `api.cloudsmith.io` in the credential-binding prompt. For unattended runs, create the binding beforehand by running interactively once or configuring [credential bindings](https://docs.docker.com/ai/sandboxes/configuration/credentials/#credential-bindings). Without an approved binding, the API key is withheld.

The optional `cloudsmith-api-key` is stored on the host as shown in [Usage](#usage). The proxy adds `X-Api-Key: <key>` to requests to `api.cloudsmith.io`, from the CLI or any other process. Inside the sandbox, `CLOUDSMITH_API_KEY` holds `proxy-managed`.

Bind a least-privilege service-account key: every process in the sandbox can exercise its permissions. Without a key, the CLI still installs, but authenticated API operations are unavailable. API access is separate from the repository entitlement token used by `cloudsmith-repo`.

## How it works

```mermaid
flowchart TB
    subgraph SETUP["SETUP · Sandbox creation"]
        direction LR
        FETCH("Download installer<br/>Verify SHA256")
        INSTALL("Install CLI<br/>Verify release archive")
        READY(["CLI ready<br/>cloudsmith --version"])
        FETCH --> INSTALL --> READY
    end

    subgraph REQUEST["RUNTIME · API command"]
        direction LR
        CLI("cloudsmith command")
        PROXY("Sandbox proxy<br/>Inject bound API key")
        API("Cloudsmith API<br/>Apply key permissions")
        RESULT(["API response"])
        CLI --> PROXY --> API --> RESULT
    end

    SETUP --> REQUEST

    classDef neutral fill:#f8fafc,stroke:#94a3b8,color:#0f172a;
    classDef accent fill:#ecfdf5,stroke:#10b981,color:#065f46,stroke-width:2px;
    classDef success fill:#ecfdf5,stroke:#34d399,color:#065f46;
    class FETCH,CLI neutral;
    class INSTALL,PROXY,API accent;
    class READY,RESULT success;
    style SETUP fill:transparent,stroke:#94a3b8,stroke-dasharray:4 4
    style REQUEST fill:transparent,stroke:#94a3b8,stroke-dasharray:4 4
```

- **Install.** The kit downloads Cloudsmith's [installer script](https://github.com/cloudsmith-io/cloudsmith-cli-install-script) (version and SHA256 pinned in the spec) to a file and checks the digest. The script fetches the release manifest for `cli-version` from the public `cloudsmith/cli` repository, verifies the archive against it, and installs under `/opt/cloudsmith-cli`. The kit symlinks `/usr/local/bin/cloudsmith`. Nothing is piped into `sh`, nothing comes from PyPI.
- **Bumping.** Installer: change `INSTALLER_VERSION` and `INSTALLER_SHA256` from its `SHA256SUMS`. CLI: change the `cli-version` default.

### Why these domains

| Domain | Why |
| --- | --- |
| `api.cloudsmith.io` | Cloudsmith API, key added as `X-Api-Key` |
| `dl.cloudsmith.io` | Installer script, release manifest and CLI archive from Cloudsmith's public repositories |

`dl.cloudsmith.io` is a literal so the install works when the pull kit uses a custom download domain. It is shared by every public Cloudsmith repository.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `cloudsmith whoami` shows no user | No key bound, or the key was rejected | `sbx secret set cloudsmith-api-key -t <api-key>`, recreate |
| CLI commands fail to connect | `api.cloudsmith.io` denied by a policy above the kit | `sbx policy log <sandbox>` |
| Install step exits 1 | Download or checksum failure, or `cli-version` does not exist | `sbx policy log <sandbox>`; check the version under `https://dl.cloudsmith.io/public/cloudsmith/cli/` |

## Cleanup

```console
sbx secret rm cloudsmith-api-key -f
```

`/opt/cloudsmith-cli` disappears with `sbx rm <sandbox>`.

# Terraform Ops Kit

A mixin kit for sbx that adds a complete Terraform infrastructure-as-code
toolkit to any agent (Claude, Gemini, Copilot, Shell, etc.). Pre-installs
**terraform**, **terragrunt**, **tflint**, **infracost**, **aws-cli**, and
**checkov** so AI agents can autonomously plan, validate, lint, security-scan,
and cost-estimate Terraform infrastructure.

## Usage

Pair with any sbx agent:

```console
# Claude Code
sbx create --kit ./terraform-ops-kit/ claude /path/to/terraform-project

# Any other agent (Gemini, Copilot, Shell)
sbx create --kit ./terraform-ops-kit/ gemini /path/to/terraform-project

# Or use as a mixin on an existing sandbox
sbx run claude --kit ./terraform-ops-kit/ /path/to/terraform-project
```

Inside the sandbox, ask the agent:

```
"Initialize this Terraform project, run a plan, and scan for security issues"
```

The agent will run `terraform init`, `terraform plan`, `checkov -d .`, and
return a validated plan + security report — no manual CLI work needed.

## How It Works

### Installation Flow

At sandbox creation time the kit runs six install commands in sequence:

1. **Terraform** — HashiCorp official APT repo (`apt-get install terraform`).
   Ubuntu release detected from `/etc/os-release` (works on focal, jammy,
   noble). Installs the latest stable version.

2. **Terragrunt** v0.59.3 — Binary downloaded from GitHub releases. Pinned
   to a specific version because the GitHub API is rate-limited inside
   sandboxes (no auth token), making "latest" detection unreliable.

3. **tflint** — Installed via the official install script from
   `terraform-linters/tflint`.

4. **checkov** — Installed via `apt-get install python3-checkov`. Falls
   back gracefully if not available in the distro.

5. **Infracost** v0.10.31 — Binary downloaded directly from GitHub releases.
   Pinned for stability; the upstream `install.sh` script redirects to a
   new CLI repository for v1+.

6. **AWS CLI v2** — Downloaded as a zip from `awscli.amazonaws.com`,
   extracted, and installed with `./aws/install --update`.

All binaries land in system PATH (`/usr/local/bin`).

### Why Pinned Versions?

| Tool | Pinned? | Reason |
|------|---------|--------|
| terraform | No (apt) | HashiCorp repo always serves latest stable |
| terragrunt | v0.59.3 | GitHub API rate-limited without auth |
| tflint | No (script) | Install script always gets latest |
| checkov | No (apt) | APT picks distro-packaged version |
| infracost | v0.10.31 | Upstream moved to new CLI repo |
| aws-cli | No (installer) | Installer always gets latest v2 |

Tools without a pin always install the latest version available at sandbox
creation time. To upgrade, create a new sandbox.

### Configuration Files

The kit pre-seeds two config files via `initFiles`:

- **`~/.tflint.hcl`** — tflint plugin rules and best-practice checks
- **`~/.checkov.yml`** — checkov framework selection and skip exclusions

Both are optional — agents can override or skip them.

### Network Policy

The kit declares every outbound domain needed at install time:

| Domain | Purpose |
|--------|---------|
| `apt.releases.hashicorp.com` | Terraform APT repo |
| `github.com` / `raw.githubusercontent.com` / `release-assets.githubusercontent.com` | Terragrunt, tflint downloads |
| `awscli.amazonaws.com` | AWS CLI v2 zip |
| `github.com` (infracost) | Infracost binary release |
| `archive.ubuntu.com` / `security.ubuntu.com` / `ports.ubuntu.com` | APT metadata (amd64 + arm64) |
| `download.docker.com` | APT `apt-get update` metadata |

These are the **complete** outbound contract — CI runs under `deny-all`, so
anything not listed is blocked. `ports.ubuntu.com` is included so the kit
works on both amd64 (CI) and arm64 (Apple Silicon).

## AI-Powered Workflows

Agents execute the tools and parse results — no manual command-line work:

### Validate + Cost + Security

```
"Review this Terraform project — validate, check security, estimate costs"

→ Agent runs: terraform init, terraform validate, tflint .,
  terraform plan, checkov -d ., infracost breakdown --path .

→ Returns: validation status, linting warnings,
  security issues, monthly cost breakdown
```

### Multi-Environment Orchestration (Terragrunt)

```
"Plan all Terragrunt environments and show me the cost delta"

→ Agent runs: terragrunt run-all plan, infracost per directory

→ Returns: aggregated plan + cost breakdown by environment
```

## AWS Credentials

The sandbox inherits AWS credentials from the host:

```bash
# Option A: Mount ~/.aws directory
sbx create --kit ./terraform-ops-kit/ claude /path/to/tf \
  --mount ~/.aws:/home/agent/.aws:ro

# Option B: Environment variables
AWS_PROFILE=my-profile sbx create --kit ./terraform-ops-kit/ claude /path/to/tf
```

Verify inside the sandbox:

```bash
aws sts get-caller-identity
```

## Tools

| Tool | Version (at install) | From |
|------|---------------------|------|
| terraform | Latest stable | apt.releases.hashicorp.com |
| terragrunt | v0.59.3 | GitHub release |
| tflint | Latest | install script |
| checkov | Distro version | apt (python3-checkov) |
| infracost | v0.10.31 | GitHub release |
| aws-cli | Latest v2 | awscli.amazonaws.com |

## Customization

### Add GCP or Azure

The kit ships **aws-cli** only. Fork and add to `spec.yaml`:

```yaml
- command: |
    apt-get install -y google-cloud-cli
  user: "0"
  description: "Install GCP CLI"
```

Or ask the agent to run `gcloud auth login` / `az login` inside the sandbox.

### Adjust Lint Rules

Edit `~/.tflint.hcl` to enable/disable rules, then `tflint .` picks up the
changes immediately.

## Cleanup

This kit creates no state on the host outside the sandbox. All installed
tools live inside the container. To clean up:

```console
$ sbx rm <sandbox-name>
```

No persistent files, caches, or credentials are left behind.

## Troubleshooting

| Symptom | Likely cause |
|---------|-------------|
| `terraform: command not found` | APT install failed — check network policy and run `apt-get install -y terraform` |
| `checkov: command not found` | `python3-checkov` not in distro — use `pip install checkov` in a project venv |
| `aws: command not found` | AWS CLI zip download failed — verify `awscli.amazonaws.com` is in `allowedDomains` |
| AWS auth fails | Credentials not mounted — use `--mount ~/.aws:/home/agent/.aws:ro` |
| `terragrunt: not found` | GitHub release download failed — check `github.com` is in `allowedDomains` |
| `infracost: not found` | GitHub release download failed — pinned URL may be stale |

## Origin

Created as a community contribution to
[docker/sbx-kits-contrib](https://github.com/docker/sbx-kits-contrib)
for AI-assisted infrastructure-as-code development.

## Testing

```bash
# From the repo root
sbx kit validate ./terraform-ops-kit/
../scripts/test-kit.sh terraform-ops-kit
../scripts/test-kit-e2e.sh terraform-ops-kit  # Requires sbx login
```

## License

Apache 2.0 (same as sbx-kits-contrib)

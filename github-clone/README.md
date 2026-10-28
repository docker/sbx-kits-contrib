# github-clone

A mixin that clones a GitHub repository into the sandbox at sandbox-create
time, at a directory you choose (`/project` by default), using the
[`gh` CLI](https://cli.github.com/) with a **proxy-managed `GH_TOKEN`
sentinel** so private repos and authenticated writes work without ever
handing the real token to the container.

## Usage

Public repo — no host-side setup required. Prefer the published OCI
artifact on Docker Hub:

```console
$ sbx run \
    --kit "docker.io/sbx/github-clone-kit:latest" \
    --arg repo=docker/sbx-kits-contrib \
    claude
```

Or from a git URL targeting this repo:

```console
$ sbx run \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-clone" \
    --arg repo=docker/sbx-kits-contrib \
    claude
```

From a local checkout:

```console
$ sbx run --kit ./github-clone --arg repo=docker/sbx-kits-contrib claude
```

Private repo (or if you want authenticated pushes/pulls from inside the
sandbox) — bind a GitHub token on the host once:

```console
$ echo "$GITHUB_TOKEN" | sbx secret set -g github
```

then run the same `sbx run …` command. The sandbox proxy substitutes the
real token onto every outbound request to `api.github.com` and `github.com`;
`gh` and `git` only ever see a synthetic sentinel — for GitHub that is
`GH_TOKEN=gho_sbxproxymanaged000000000000000000000`, never the real token.

### Arguments

| Arg    | Required | Default    | Notes |
|--------|----------|------------|-------|
| `repo` | yes      | —          | `owner/name` shorthand, or a full `https://github.com/…` or `git@github.com:…` URL. |
| `ref`  | no       | *(default branch)* | Branch, tag, or 7–40 hex commit SHA to check out. Mutually exclusive with `pr`. |
| `pr`   | no       | *(none)*   | Pull request number to check out with `gh pr checkout`. Mutually exclusive with `ref`. |
| `dir`  | no       | `/project` | Absolute path inside the sandbox to clone into. |

Examples:

```console
# Clone a specific ref into /workspace/src instead of /project
$ sbx run \
    --kit "docker.io/sbx/github-clone-kit:latest" \
    --arg repo=docker/sbx-kits-contrib \
    --arg ref=main \
    --arg dir=/workspace/src \
    claude

# Land the agent on PR #42, ready to review or push follow-up commits
$ sbx run \
    --kit "docker.io/sbx/github-clone-kit:latest" \
    --arg repo=docker/sbx-kits-contrib \
    --arg pr=42 \
    claude

# Clone a full HTTPS URL — same result as the shorthand above
$ sbx run \
    --kit "docker.io/sbx/github-clone-kit:latest" \
    --arg repo=https://github.com/docker/sbx-kits-contrib.git \
    claude
```

## How it works

- **When**: three `setup.install` hooks run once before the agent launches.
  As `root`, the first ensures `gh` (and `git`) are installed; the second
  creates the destination, assigns it to `agent`, and writes a `--system`
  git credential-helper entry pointing at `gh auth git-credential`. The
  third runs the clone and any checkout as uid 1000, avoiding Git's dubious
  ownership check and making the working tree agent-owned from the outset.
- **Auto-install**: if `gh` is missing from the base image, the mixin adds
  GitHub's official apt source (`cli.github.com`) and
  `apt-get install`s it. Skipped entirely on bases that already carry
  `gh`, so the apt-get network cost is paid only when needed. On
  non-Debian bases the mixin fails with an actionable error pointing at
  layering a companion install mixin instead.
- **Auth**: `credentials: - service: github` with `apiKey.name: GH_TOKEN`,
  `proxyManaged: true`, and `inject` entries for `api.github.com` (the
  `gh` REST path) and `github.com` (the git HTTPS transport). The
  in-container `GH_TOKEN` is a synthetic sentinel
  (`gho_sbxproxymanaged000000000000000000000`); the sandbox proxy swaps in
  the real token on outbound requests.

  The host side must allow both domains too — a binding is intersected
  with what the kit requests, so a host list of only `api.github.com`
  silently drops the `github.com` injection.
- **Re-run safety**: if `dir` already exists and is non-empty (e.g. on
  `sbx create` retries), the clone is skipped rather than failing or
  clobbering.
- **`ref` handling**: branches and tags use `--depth 1 --branch`; if that
  fails (commit SHAs aren't valid `--branch` args) it falls back to a full
  clone + `git checkout`.
- **`pr` handling**: clones the full history — not `--depth 1` — then runs
  `gh pr checkout <number>` from inside the clone. Full history is what makes
  `git diff <base>...HEAD` and `git log <base>..HEAD` work; a shallow clone
  leaves the PR head with no merge base against the target branch. The PR
  lands on a local branch, so `git push` updates it, and PRs from forks work
  because `gh` points the branch at the contributor's fork. Only a PR number
  is accepted: a PR URL could name a different repository than `repo`, which
  would leave the clone and the checked-out branch unrelated. Passing both
  `ref` and `pr` fails at create time rather than letting one silently win.
  No extra network access is needed — `gh` reaches the PR over
  `api.github.com` and fetches over `github.com`, both already allowed.
- **Network contract**: two groups, both listed in
  `permissions.network.allow`:
  - **Runtime** (`gh` + `git`): `api.github.com`, `github.com`,
    `codeload.github.com`, `raw.githubusercontent.com`.
  - **apt-install path** (only used when the base lacks `gh`):
    `cli.github.com`, `archive.ubuntu.com`, `security.ubuntu.com`,
    `ports.ubuntu.com`, `download.docker.com`. The Ubuntu + Docker hosts
    are the usual `apt-get update` cascade — `apt-get update` refreshes
    every configured source, so all four must be reachable even though
    we only fetch from `cli.github.com`. That is the complete outbound
    contract — under a `deny-all` host policy nothing else is reachable.

## SSH clones

Pass `repo=git@github.com:owner/name.git` and layer the
[`github-ssh`](../github-ssh/) mixin so GitHub's host keys are
pre-populated and the host's `ssh-agent` is forwarded. In that mode the
`GH_TOKEN` sentinel is unused for the clone itself, though `gh api`
inside the sandbox still routes through the proxy.

```console
$ sbx run \
    --kit "docker.io/sbx/github-clone-kit:latest" \
    --kit "docker.io/sbx/github-ssh-kit:latest" \
    --arg repo=git@github.com:docker/sbx-kits-contrib.git \
    claude
```

## References

- [Kit spec](spec.yaml)
- [v2 spec grammar](../spec/SPEC-v2.md) — `args:` (§2.1), `credentials:` (§5.4), `setup:` (§5.6)
- [Kit-author bindings guide](../skills/kit-author/topics/bindings.md) — how the `github` credential binding is discovered on the host
- [`github-ssh`](../github-ssh/) — companion mixin for SSH-based clones

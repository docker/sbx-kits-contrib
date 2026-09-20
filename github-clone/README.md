# github-clone

A v2 mixin that clones a GitHub repository into the sandbox at
sandbox-create time, at a directory you choose (`/project` by default),
using the [`gh` CLI](https://cli.github.com/) with a **proxy-managed
`GH_TOKEN` sentinel** so private repos and authenticated writes work
without ever handing the real token to the container.

## Usage

Public repo — no host-side setup required:

```console
$ sbx run \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-clone" \
    --arg repo=docker/sbx-kits-contrib \
    claude
```

Private repo (or if you want authenticated pushes/pulls from inside the
sandbox) — bind a GitHub token on the host once:

```console
$ echo "$GITHUB_TOKEN" | sbx secret set -g github
```

then run the same `sbx run …` command. The sandbox proxy substitutes the
real token onto every outbound request to `api.github.com` and `github.com`;
`gh` and `git` only ever see the literal string `proxy-managed`.

### Arguments

| Arg    | Required | Default    | Notes |
|--------|----------|------------|-------|
| `repo` | yes      | —          | `owner/name` shorthand, or a full `https://github.com/…` or `git@github.com:…` URL. |
| `ref`  | no       | *(default branch)* | Branch, tag, or 7–40 hex commit SHA to check out. |
| `dir`  | no       | `/project` | Absolute path inside the sandbox to clone into. |

Examples:

```console
# Clone a specific tag into /workspace/src instead of /project
$ sbx run \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-clone" \
    --arg repo=docker/sbx-kits-contrib \
    --arg ref=v0.2.0 \
    --arg dir=/workspace/src \
    claude

# Clone a full HTTPS URL — same result as the shorthand above
$ sbx run \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-clone" \
    --arg repo=https://github.com/docker/sbx-kits-contrib.git \
    claude
```

## How it works

- **When**: two `lifecycle@1` install hooks run once, as `root`, before the agent
  launches. The first ensures `gh` (and `git`) are installed; the second
  runs `gh repo clone`, `chown`s the resulting tree to the `agent` user,
  and writes a `--system` git credential-helper entry pointing at
  `gh auth git-credential` (so any later `git push` / `git pull` from the
  sandbox picks up the same proxy-managed `GH_TOKEN` sentinel).
- **Auto-install**: if `gh` is missing from the base image, the mixin adds
  GitHub's official apt source (`cli.github.com`) and
  `apt-get install`s it. Skipped entirely on bases that already carry
  `gh`, so the apt-get network cost is paid only when needed. On
  non-Debian bases the mixin fails with an actionable error pointing at
  layering a companion install mixin instead.
- **Auth**: the mixin declares no credential of its own. It consumes the
  `github` binding another kit in the composition declares — the `gh`
  kit, or a base agent that asks for the service — so the in-container
  `GH_TOKEN` is that kit's `proxy-managed` sentinel and the sandbox proxy
  swaps in the real token on outbound requests. Two consequences: a
  composition with no `github` binding clones public repositories only,
  and because v3 credentials are phase-scoped, a provider that binds the
  token at `runtime` (the normal choice) leaves this install-time clone
  unauthenticated. The clone hook declares `env: [GH_TOKEN]` so the
  variable reaches `gh` wherever it is available.
- **Re-run safety**: if `dir` already exists and is non-empty (e.g. on
  `sbx create` retries), the clone is skipped rather than failing or
  clobbering.
- **`ref` handling**: branches and tags use `--depth 1 --branch`; if that
  fails (commit SHAs aren't valid `--branch` args) it falls back to a full
  clone + `git checkout`.
- **Network contract**: two groups, which are the two phases of the
  `network-policy@1` capability. An absent phase grants nothing, and the
  install phase is closed before the agent starts.
  - **`gh` + `git`** — `api.github.com`, `github.com`,
    `codeload.github.com`, `raw.githubusercontent.com`. Listed in *both*
    phases: the clone itself is an install hook, and the credential
    helper it writes keeps serving `git push` / `git pull` for the rest
    of the sandbox's life.
  - **apt-install path**, install phase only (used when the base lacks `gh`):
    `cli.github.com`, `archive.ubuntu.com`, `security.ubuntu.com`,
    `ports.ubuntu.com`, `download.docker.com`. The Ubuntu + Docker hosts
    are the usual `apt-get update` cascade — `apt-get update` refreshes
    every configured source, so all four must be reachable even though
    we only fetch from `cli.github.com`. That is the complete outbound
    contract — under a `deny-all` host policy nothing else is reachable.

## SSH clones

Pass `repo=git@github.com:owner/name.git` and layer the
[`github-ssh/`](../github-ssh) mixin so GitHub's host keys are
pre-populated and the host's `ssh-agent` is forwarded. In that mode the
`GH_TOKEN` sentinel is unused for the clone itself, though `gh api`
inside the sandbox still routes through the proxy.

## References

- [Kit descriptor](github-clone.yaml)
- [v3 kit grammar](https://github.com/docker/runtime-kits/blob/main/docs/spec/SPEC-v3.md) — `args:` (§6), `capabilities:` (§7)
- [`skills/kit-author/topics/bindings.md`](../skills/kit-author/topics/bindings.md) — how the `github` credential binding is discovered on the host
- [`github-ssh/`](../github-ssh) — companion mixin for SSH-based clones

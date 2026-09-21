# sbx-kits-contrib

Community-contributed kits for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

Each top-level directory holding a `<kit>/<kit>.yaml` is a **kit**: a declaration of what an agent environment contains, what it may reach on the network, which credentials it needs, and what runs at create and at boot — paired with the recipe that builds its content. The first line of every descriptor is `# syntax=docker/sandbox-kit:3`, which dispatches the BuildKit frontend that validates the declarations and builds the image in one pass. There is no separate validate step: if `docker buildx build` succeeds, the descriptor is well-formed.

The remaining top-level directories are shared infrastructure: [`spec/`](./spec) and [`tck/`](./tck) (the Go implementation of the **v2** kit format, kept as a record of what these kits migrated from — see [Packages](#packages)), [`scripts/`](./scripts) (maintainer utilities), and [`skills/`](./skills).

> [!NOTE]
> Kits are experimental. The descriptor grammar, CLI commands, and experience
> for creating, loading, and managing kits are subject to change as the
> feature evolves. Bugs and feature requests for the kits in this repo
> belong in [its issue tracker](https://github.com/docker/sbx-kits-contrib/issues);
> general feedback on the kit feature itself goes to
> [docker/sbx-releases](https://github.com/docker/sbx-releases).

One consequence of that churn is worth knowing before you try anything below:

> [!IMPORTANT]
> Kit v3 needs an `sbx` **release candidate or nightly** build. The stable
> release line does not carry the v3 load path yet, so a stable `sbx` reads
> every kit in this repo as an unrecognized artifact.

## Documentation

The descriptor grammar is specified upstream, and that specification — not this README — is normative:

- [SPEC-v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md) — the grammar, publishing rules, and the OCI layout a kit produces.
- [Capability pages](https://github.com/docker/sandbox-kit-spec/tree/main/docs/spec/capabilities/com.docker.sandbox) — one page per capability type, each normative for its own config schema and runtime behavior.

Sandbox documentation on [docs.docker.com](https://docs.docker.com/ai/sandboxes/customize/) covers the product surface — templates, network policies, secrets. Its [kit pages](https://docs.docker.com/ai/sandboxes/customize/kits/) still describe the **v2** `spec.yaml` format, which no kit in this repo uses any more; read SPEC-v3 for the format and this repo's kits for worked examples.

Repository docs: [`CONTRIBUTING.md`](./CONTRIBUTING.md) (how to submit a kit) and [`PUBLISHING.md`](./PUBLISHING.md) (what CI publishes and under what name).

Contributing a kit or a fix? Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) first — this repo enforces verified commit signatures, so you'll need GPG or SSH signing set up before your PR can be merged.

## A kit is one OCI image

A v3 kit is an ordinary OCI image. The descriptor rides in the image's manifest annotation (`vnd.docker.sandbox.kit.descriptor`, as compact JSON) and the layers are the content, so reading a kit's declarations is one manifest GET and pulling it is `docker pull`. Nothing else is published beside it.

That is a change worth stating plainly, because it removes a distinction the previous format forced. A v2 kit was YAML that *pointed at* an image, so a kit that built its own environment published two things — a base image and a separate OCI artifact carrying the YAML — and they had to be kept in step. In v3 the descriptor and the content are one artifact, and the only thing to keep in step is the kit itself. See [`PUBLISHING.md`](./PUBLISHING.md) for what that means for naming and tags.

There are two kinds:

| `kind:` | What it is | Content |
| --- | --- | --- |
| `workload` | The whole environment: the image the sandbox boots from, including the agent. Replaces v2's `kind: sandbox`. | A full root filesystem. A workload **must** have a recipe. |
| `mixin` | A delta layered onto a workload: extra tools, credentials, hooks, egress. | An overlay (`FROM scratch`), or no recipe at all for a declaration-only kit. |

This repo ships **30 workloads and 57 mixins**. Every workload has a `-mixin` sibling declaring the same capabilities in overlay form, so an agent can either *be* the sandbox or be layered onto one; the remaining 27 mixins are standalone tools and integrations. See the [Kit index](#kit-index).

## Anatomy of a kit

```text
<kit>/
├── <kit>.yaml           # the descriptor — starts with # syntax=docker/sandbox-kit:3
├── <kit>.dockerfile     # the recipe — found by filename stem
├── <kit>-context.md     # the agent-context body, referenced as contentFile:
├── files/               # optional assets the recipe COPYs in
└── README.md            # what this kit is and how to use it
```

The descriptor and the recipe pair by **filename stem**: `claude.yaml` looks for `claude.dockerfile` beside it. Naming a recipe that does not exist is an error; *not having* the conventional companion just means a declaration-only kit, which is legal for a `kind: mixin` and rejected for a `kind: workload`. Fourteen mixins here are declaration-only — they contribute credentials, egress and hooks without shipping bits.

There is no `spec.yaml`, no plain `Dockerfile`, no `testdata/tck.yaml` and no `.dockerignore`. The build context is the kit's own directory and a `dockerfile:` path may not escape it, so a mixin cannot reach an asset sitting in its workload sibling's directory — a shared script has to be copied into both.

### The descriptor

```yaml
# syntax=docker/sandbox-kit:3
schemaVersion: "3"
kind: mixin
displayName: My Tool
description: Short description of what this kit does.

version: "${{ kit.args.version }}"

args:
  version:
    default: "1.4.2"
    pattern: '^[0-9]+\.[0-9]+\.[0-9]+$'
    description: my-tool release to install
    buildArg: MY_TOOL_VERSION

provides: ["my-tool@${{ kit.args.version }}"]
requires: ["deb/jq"]

capabilities:
  - type: com.docker.sandbox/network-policy@1
    config:
      install:
        allow: [github.com, objects.githubusercontent.com]
      runtime:
        allow: [api.example.com]

  - type: com.docker.sandbox/credential@1
    optional: true
    description: Example API access
    config:
      service: example
      phase: runtime
      apiKey:
        name: EXAMPLE_API_KEY
        proxyManaged: true
        inject:
          - {domain: api.example.com, header: authorization, format: "Bearer %s"}

  - type: com.docker.sandbox/lifecycle@1
    config:
      install:
        - command: "my-tool init"
          user: agent
          env: [WORKSPACE_DIR]
          description: Initialize my-tool

  - type: com.docker.sandbox/agent-context@1
    config:
      contentFile: ./my-kit-context.md
```

Every key is `lowerCamelCase` with acronyms title-cased (`sourceUrl`, `apiKey`). Decoding is **strict**: an unrecognized key anywhere is an error rather than something ignored, which is what makes a leftover v2 field fail loudly.

Four things in that skeleton are worth calling out, because they are where v2 habits break:

- **Capabilities are typed requests, not grammar.** What v2 spelled as fixed blocks is now a list of versioned capability types the host answers: `permissions.network` → `network-policy@1`, `credentials` → `credential@1`, `volumes`/`ports` → `volume@1`/`port@1`, `setup.*` → `lifecycle@1`, `agentInstructions` → `agent-context@1`, plus `sbx@1` on every workload. An entry is required unless it sets `optional: true`, which fails resolution closed rather than degrading silently.
- **`network-policy@1` is phase-scoped.** `install` and `runtime` are separate allow lists and an absent phase grants nothing. Install hooks run in the install phase; startup hooks run at boot, which is the *runtime* phase. A host reached by both goes in both.
- **Hook environments are deny-by-default.** Every variable a `lifecycle@1` hook reads has to be named in that hook's `env:`, and that includes variables its children read — a hook that shells out to `curl` through the sandbox proxy declares `HTTP_PROXY`/`HTTPS_PROXY` even though its own script never mentions them. The platform baseline (`PATH`, `HOME`, `HOSTNAME`, `TERM`, `PWD`, `OLDPWD`, `SHLVL`, `_`) comes for free.
- **Arg references are `${{ kit.args.x }}`, and they are found by scanning raw text.** That includes YAML comments, so a placeholder written in prose is a real reference and fails validation when the arg does not exist. Name the arg instead of spelling the placeholder when you document one. Shell variables (`$VAR`, `${VAR}`) pass through untouched — which is the whole point of the `${{` opener, since it is not valid shell and the two vocabularies cannot collide.

### The recipe

The recipe is an ordinary Dockerfile. For a workload it builds a root filesystem; for a mixin it builds an overlay that lands on an unknown base:

```dockerfile
# syntax=docker/dockerfile:1
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
ARG MY_TOOL_VERSION
RUN install-the-thing "${MY_TOOL_VERSION}"

# Staging writes outside $HOME, so this half runs as root — these bases run as
# the agent user, and a `mkdir /out` as that user fails.
USER root
RUN mkdir -p /out/usr/local/bin /out/etc/profile.d \
 && cp "$(command -v my-tool)" /out/usr/local/bin/my-tool \
 && printf 'export MY_TOOL_HOME=/usr/local/share/my-tool\n' > /out/etc/profile.d/my-kit-env.sh

# The overlay: lands on any base.
FROM scratch
COPY --from=build /out /
```

Where an install genuinely cannot be relocated — apt packages, `uv tool install`, npm globals — run the unmodified install over the workload's own base as a build stage, then `COPY --from=build` the specific paths it produced into the `scratch` overlay.

An overlay reproduces the base's ownership at every level it ships, because its directory entries override the base's — `/home` owned by uid 1000 hands the agent a directory it should not own, and `/home/agent` owned by root takes `$HOME` away from the user the entrypoint runs as. Staging under `/out` and starting the `chown` exactly at the agent's home gets both right. Cleanest is to avoid the agent's home entirely and stage into `/usr/local`, `/opt` and `/etc/profile.d`, which is what a mixin landing on an unknown base should prefer anyway, since whatever is at `/home/agent` may be a mounted volume.

### Where the runtime contract lives

The image config owns the runtime contract. The descriptor duplicates none of it:

| What it was in v2 | Where it is now |
| --- | --- |
| `sandbox.image` | the recipe's `FROM` |
| `sandbox.entrypoint` | the recipe's `ENTRYPOINT` |
| `sandbox.command.default` | the recipe's `CMD` |
| `sandbox.command.interactive` | `lifecycle@1.interactive` — the one piece with no image-config slot |
| `environment.variables` | the recipe's `ENV` |

The last row has an exception that catches everyone: **a mixin's image config never becomes the composed image's**, so `ENV` in a mixin recipe says nothing at run time. Drop the exports into `/etc/profile.d/<kit>-env.sh` instead, which the base workload's login shell sources.

### Versions

Most kits here declare a build-phase arg named `version` and point three things at it — the recipe's install, the `provides` entry, and the descriptor's own `version:` field:

```yaml
version: "${{ kit.args.version }}"
args:
  version: {default: "1.4.2", buildArg: MY_TOOL_VERSION}
provides: ["my-tool@${{ kit.args.version }}"]
```

One value then drives the install, the provide, the published version and the publish tag, with no second place to drift. A pinned provide is a claim about content, so the recipe should *enforce* it: wire the arg through to the installer and re-read the installed version, failing the build on mismatch. Pinning the provide without pinning the install is worse than floating, because it asserts a version the content may not have.

A version is `[0-9]+(\.[0-9A-Za-z-]+)*` — first segment numeric, no `v` prefix — so **a commit SHA is not a version** and a kit pinned to a git ref cannot reference that pin into its provide.

A handful of kits genuinely cannot be pinned: an installer whose only channel knob is `latest`, a tool that self-updates at run time, content that is someone else's mutable image tag. Those keep an unversioned `provides: ["<tool>"]` and a literal `version:` fallback, with the reason recorded in the descriptor. That is the right answer for them — do not reach for a `version: "1.0.0"` fallback that would publish `<tool>@1.0.0`, which is the kit's release number wearing the tool's name.

### `provides` and `requires`

`provides` is what a kit offers by name; `requires` is a **closed-set** check against everything composed together, so a name nothing provides makes the kit refuse to compose anywhere rather than only where it would really have failed.

v2 could express exactly one dependency — `requires: {agent: <name>}` — so a kit whose hook ran `apt-get` or called `jq` said nothing about needing them and simply failed at create on a base that lacked them. v3 kits can say it, because publishing a `kind: workload` kit reads the built content's dpkg (or apk) database and derives one provide per installed package under `deb/` or `apk/` (SPEC-v3 §9.6). Nineteen mixins here require derived names — `deb/jq`, `deb/dpkg`, `deb/docker-ce`, `deb/openssh-client`:

```yaml
requires: ["claude", "deb/jq", "deb/openssl >= 3.5"]
```

Requiring a `deb/` name is fine; **authoring one as a provide is refused** — the namespace is reserved for publishing to fill, and the check is authored-form only, so the build is what tells you. Verify the package is really in the database before requiring it: a tilde in a version's upstream half makes §9.6 drop the package, so `deb/nodejs` does not exist on these templates even though node is installed.

The platform floor you can assume without declaring anything is `bash`, `sh`, `curl`, `git`, a CA store, and the `agent` user at uid 1000 (SPEC-v3 §12). Audit for what your kit needs beyond that.

## Using a kit

A workload *is* the agent, so it goes in the first positional slot where a built-in agent name would. A mixin composes onto one with `--kit`.

The primary way to consume a kit from this repo is its published OCI image on Docker Hub — every kit here is discovered and published automatically (see [`PUBLISHING.md`](./PUBLISHING.md)), so it exists the moment a change merges to `main`:

```console
sbx run docker.io/docker/sbx-kit-claude:latest .
sbx run docker.io/docker/sbx-kit-claude:latest --kit docker.io/docker/sbx-kit-mise:latest .
```

Or target this repo directly over git:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude" .
```

The fragment after `#` accepts two parameters, both optional:

| Parameter | Purpose | Example |
| --- | --- | --- |
| `dir` | Subdirectory inside the repo containing the kit | `#dir=mise` |
| `ref` | Git ref to check out — branch, tag, or commit SHA | `#ref=v1.0.0` |

Combine them with `&`:

```console
# Pin to a tag — the recommended form for production use
sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v0.2.0&dir=mise" .

# Track a branch (less stable; the kit may change under you)
sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=main&dir=mise" .

# Pin to an exact commit SHA — fully reproducible
sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=abc1234&dir=mise" .
```

Without `ref`, sbx clones the default branch shallowly. With a branch or tag, sbx clones at that ref shallowly. With a commit SHA, sbx clones fully and checks out the commit. SSH works in place of HTTPS for private repos (`git+ssh://git@github.com/...`).

For local development, point at a directory. A relative local reference has to be an explicit path (`./mise`, not `mise`) — a bare value keeps its agent-name or sandbox-name meaning:

```console
sbx run ./claude .                    # a workload
sbx run ./claude --kit ./mise .       # a mixin, composed onto it
sbx run shell --kit ./mise .          # or onto a built-in agent
```

## Adding a new kit

1. Create a directory at the repo root named for your kit (lowercase, alphanumeric + hyphens), and name the descriptor after it.

   ```text
   my-kit/
   ├── my-kit.yaml
   ├── my-kit.dockerfile
   └── README.md
   ```

2. Write `my-kit.yaml`, starting from the skeleton in [Anatomy of a kit](#anatomy-of-a-kit) and from whichever existing kit is closest in shape. `mise/` is a good declaration-only mixin; `claude-mixin/` is a good overlay mixin; `claude/` is a good workload.

3. Write `my-kit.dockerfile`, unless the kit declares only. A workload must have one.

4. Verify locally with the commands below, then open a PR. There is no per-kit test file to write and no test registration step — conformance is a property of the built artifact, judged by `kit-tck`.

If you are porting a kit from the v2 grammar rather than writing a new one, read [Migrating a kit to v3](./CONTRIBUTING.md#migrating-a-kit-to-v3) in `CONTRIBUTING.md` first — the mechanical renames are the easy half, and the parts that need judgment are listed there.

## Verifying locally

### Validate and build

The frontend validates during the build, so building *is* validating. `--output type=cacheonly` runs the whole thing and throws the result away, which is what you want while iterating:

```console
cd my-kit && docker buildx build . -f my-kit.yaml --output type=cacheonly
```

### Run it

No registry needed — `sbx` builds a local kit on the fly:

```console
sbx run ./my-workload .                       # a workload
sbx run ./my-workload --kit ./my-mixin .      # a mixin, composed
```

Proving a mixin by **composing it and running the tool** is not the same as proving it by building it, and the difference is a real failure mode: an installer that relocates a launcher but not the payload passes a `test -x` gate inside the build stage, because the payload is still sitting behind it there, and then ships a dangling symlink that works on no base at all.

### Inspect the resolved declarations

```console
sbx kit inspect ./my-kit
```

This builds the kit and prints what it resolved to — kind, schema version, and a summary of the declared policies. It is also the fastest way to see a required arg you forgot to supply, which it reports by name.

> `sbx kit validate` does **not** accept a v3 source kit. Its load path has no
> kit builder configured, so it fails with *"is a v3 source kit and this load
> path has no kit builder configured"* on every kit in this repo. Use
> `sbx kit inspect`, or the `docker buildx build` above.

### Conformance

`kit-tck` judges a **built artifact** against the specification — the descriptor in the manifest annotation, the staged sources, the layer shape, the derived provides. Build to an OCI layout and point it at the result:

```console
go install github.com/docker/sandbox-kit-spec/v3/cmd/kit-tck@latest

cd my-kit
docker buildx build . -f my-kit.yaml --output type=oci,dest=/tmp/k,tar=false -t my-kit:1.4.2
kit-tck kit --layout /tmp/k 1.4.2
```

Note the last argument: `kit-tck` takes the **tag alone**, not `my-kit:1.4.2`. A passing run prints the check count and `✓ conforms`.

`docker/sandbox-kit-spec` is currently private, so that `go install` needs access to it: the public module proxy answers 404, so Go resolves the module direct and wants a git credential plus `GOPRIVATE=github.com/docker/*`. Without access you can still check a descriptor, because the frontend validates it during the build — that is what `--output type=cacheonly` above does — you just cannot judge the built artifact. CI has the same split: a pull request from a fork validates but does not run `kit-tck`.

### Check what a context body actually references

A `contentFile:` body is staged into a layer at publish, while create-phase args expand into the *descriptor* at create — so a `${{ kit.args.* }}` inside a staged body is never expanded. It reaches the agent as literal placeholder text, with no warning from the build. Use inline `content:` where the body has to name an arg:

```console
rg -l '\$\{\{ *kit\.args\.' --glob '*-context.md' .
```

The mirror-image mistake is invisible too: a `*-context.md` no descriptor references fails at nothing at all and simply never reaches the agent.

## Declare every domain your kit needs

A kit's network policy is its **complete** outbound contract. Anything not in an allow list is blocked at request time, and a failed request inside an install hook surfaces as sandbox creation failing.

Two things make this harder than listing the hosts you meant to reach:

- **Package managers refresh every configured source, not just yours.** `apt-get update` re-fetches metadata for every file in `/etc/apt/sources.list[.d/]`, including the ones the base template added, and exits non-zero if *any* of them fails — even when the package you want lives in a different source. For kits on `shell-docker` / `*-docker` templates that means `download.docker.com` has to be allowed even if you only install from Ubuntu's main archive. Ubuntu serves amd64 from `archive.ubuntu.com` + `security.ubuntu.com` and arm64 from `ports.ubuntu.com`, so list all three; CI is amd64 and your Mac is likely arm64.
- **The phase split can lose a host.** An absent phase grants nothing, so a host your v2 kit reached from a startup hook belongs in `runtime`, not `install` — startup hooks run at boot. A host both phases reach goes in both.

Write entries **portless** (`archive.ubuntu.com`, not `archive.ubuntu.com:80`). A portless pattern matches any port, which is what apt hosts need: pinning `:80` breaks the moment a mirror answers over HTTPS, and `apt-get update` then fails wholesale rather than skipping one source.

Validation enforces that every `credential@1` `inject[].domain` appears in the **same phase's** allow list, as an exact host match — a single-label wildcard like `*.example.com` does not satisfy an inject domain of `api.example.com`, even though it covers the host at run time, because the matcher does not expand globs. Add the literal host beside the wildcard; it widens nothing.

## CI

Pull requests build every changed kit with the v3 frontend, which is what validates the descriptor, and run `kit-tck` against the built artifact. Merges to `main` publish. The workflows are in [`.github/workflows/`](.github/workflows) and are the authority on what runs; [`PUBLISHING.md`](./PUBLISHING.md) covers the publishing half — what gets pushed, under what name, and with what tags.

Note that a fork PR does not receive repository secrets, so any leg needing Docker Hub credentials is skipped on it. Run the local verification above before opening a PR from a fork.

## Kit index

87 kits: 30 workloads and 57 mixins. Every workload has a `-mixin` sibling that declares the same capabilities in overlay form, so you can either boot the agent as the sandbox or layer it onto one.

### Workloads

| Kit | Mixin sibling | What it is |
| --- | --- | --- |
| [`aider`](./aider) | [`aider-mixin`](./aider-mixin) | Aider |
| [`amp`](./amp) | [`amp-mixin`](./amp-mixin) | Amp |
| [`antigravity`](./antigravity) | [`antigravity-mixin`](./antigravity-mixin) | Google Antigravity |
| [`claude`](./claude) | [`claude-mixin`](./claude-mixin) | Claude Code |
| [`claude-ollama`](./claude-ollama) | [`claude-ollama-mixin`](./claude-ollama-mixin) | Claude Code against a local Ollama endpoint |
| [`codex`](./codex) | [`codex-mixin`](./codex-mixin) | Codex |
| [`copilot`](./copilot) | [`copilot-mixin`](./copilot-mixin) | GitHub Copilot |
| [`crush`](./crush) | [`crush-mixin`](./crush-mixin) | Crush |
| [`cursor`](./cursor) | [`cursor-mixin`](./cursor-mixin) | Cursor |
| [`devin`](./devin) | [`devin-mixin`](./devin-mixin) | Devin |
| [`docker-agent`](./docker-agent) | [`docker-agent-mixin`](./docker-agent-mixin) | Docker Agent |
| [`droid`](./droid) | [`droid-mixin`](./droid-mixin) | Droid |
| [`grok`](./grok) | [`grok-mixin`](./grok-mixin) | Grok Build |
| [`gstack`](./gstack) | [`gstack-mixin`](./gstack-mixin) | Claude Code plus Garry's Stack |
| [`hermes-agent`](./hermes-agent) | [`hermes-agent-mixin`](./hermes-agent-mixin) | Hermes Agent |
| [`junie`](./junie) | [`junie-mixin`](./junie-mixin) | Junie |
| [`kiro`](./kiro) | [`kiro-mixin`](./kiro-mixin) | Kiro |
| [`nanobot`](./nanobot) | [`nanobot-mixin`](./nanobot-mixin) | Nanobot |
| [`nanoclaw`](./nanoclaw) | [`nanoclaw-mixin`](./nanoclaw-mixin) | NanoClaw |
| [`open-interpreter`](./open-interpreter) | [`open-interpreter-mixin`](./open-interpreter-mixin) | Open Interpreter |
| [`openclaw`](./openclaw) | [`openclaw-mixin`](./openclaw-mixin) | OpenClaw |
| [`opencode`](./opencode) | [`opencode-mixin`](./opencode-mixin) | OpenCode |
| [`opencode-model-runner`](./opencode-model-runner) | [`opencode-model-runner-mixin`](./opencode-model-runner-mixin) | OpenCode against Docker Model Runner |
| [`openhands`](./openhands) | [`openhands-mixin`](./openhands-mixin) | OpenHands |
| [`paperclip`](./paperclip) | [`paperclip-mixin`](./paperclip-mixin) | Paperclip |
| [`pi`](./pi) | [`pi-mixin`](./pi-mixin) | Pi |
| [`picoclaw`](./picoclaw) | [`picoclaw-mixin`](./picoclaw-mixin) | PicoClaw |
| [`trivy`](./trivy) | [`trivy-mixin`](./trivy-mixin) | Trivy vulnerability scanner |
| [`vibe`](./vibe) | [`vibe-mixin`](./vibe-mixin) | Mistral Vibe |
| [`zeroclaw`](./zeroclaw) | [`zeroclaw-mixin`](./zeroclaw-mixin) | ZeroClaw |

### Standalone mixins

| Kit | Requires | What it is |
| --- | --- | --- |
| [`aidlc-claude`](./aidlc-claude) | `claude-bedrock` | AWS AI-DLC starter: a pinned Bun and the aidlc-workflows Claude harness |
| [`claude-acp`](./claude-acp) | `claude` | The Claude ACP adapter over stdio |
| [`claude-mem`](./claude-mem) | `claude` | Persistent memory across Claude Code sessions, in SQLite + FTS5 |
| [`claude-model-runner`](./claude-model-runner) | `claude` | Routes Claude Code's API calls to a local Docker Model Runner |
| [`claude-sbx-statusline`](./claude-sbx-statusline) | `claude`, `deb/jq` | A two-line Docker Sandboxes status line for Claude Code |
| [`code-server`](./code-server) | `claude` | code-server on port 8080 with the Claude Code VS Code extension |
| [`codex-acp`](./codex-acp) | `codex` | The Codex ACP adapter over stdio |
| [`codex-app-server`](./codex-app-server) | `codex`, `deb/apt` | sshd plus forwarded host keys, so the Codex Mac GUI can drive `codex app-server` |
| [`ecc`](./ecc) | `claude` | Everything Claude Code: rules, agents, commands and skills |
| [`git-ssh-sign`](./git-ssh-sign) | `deb/openssh-client` | Commit signing with the key forwarded from the host's SSH agent |
| [`gitea`](./gitea) | `deb/dpkg` | Gitea token auth for git-over-HTTPS and the Gitea API, via the proxy |
| [`gitguardian`](./gitguardian) | `claude`, `deb/dpkg` | ggshield as a Claude Code hook, scanning the agent's actions for secrets |
| [`github-clone`](./github-clone) | — | Clones a GitHub repository at create time with a proxy-managed token |
| [`github-ssh`](./github-ssh) | `deb/jq`, `deb/openssh-client` | Pre-populated GitHub host keys, so SSH needs no interactive verification |
| [`gitlab`](./gitlab) | `deb/dpkg` | The GitLab CLI (`glab`) with proxy-injected token auth |
| [`gitlab-ssh`](./gitlab-ssh) | `deb/openssh-client` | GitLab SSH host keys in `known_hosts` |
| [`kernel`](./kernel) | — | Cloud-hosted Chromium with stealth, managed auth and session replay |
| [`lighthouse`](./lighthouse) | — | The Lighthouse CLI with headless Chromium, for auditing pages served in-sandbox |
| [`mise`](./mise) | `deb/dpkg` | mise-en-place, the polyglot dev-tool version manager, with shell activation |
| [`neovim`](./neovim) | `deb/dpkg` | Neovim at a pinned release, with a bundled `~/.config/nvim` |
| [`packages-through-sfw`](./packages-through-sfw) | — | Routes npm and pip through Socket Firewall Free |
| [`playwright`](./playwright) | — | The Playwright toolchain with Chromium on a shared system browsers path |
| [`qemu`](./qemu) | `deb/docker-ce` | QEMU user-mode emulators via binfmt_misc, for cross-arch builds |
| [`smolagents`](./smolagents) | `deb/apt` | Hugging Face smolagents in an isolated virtualenv |
| [`t3code`](./t3code) | — | The build toolchain T3 Code's SSH integration needs to compile `node-pty` |
| [`task`](./task) | `deb/dpkg` | The Task CLI, for running Taskfiles |
| [`vale`](./vale) | `deb/dpkg` | The Vale prose linter from a pinned release |

## Packages

[`spec/`](./spec) and [`tck/`](./tck) implement the **v2** kit format — `spec.LoadFromDirectory` looks for a `spec.yaml`, and no kit in this tree has one. They are kept deliberately, as a precise record of the grammar these kits migrated from and of the assertions the v2 TCK made, which is worth having while the migration is still recent. They do not validate, test, or describe a v3 kit; `kit-tck` does that.

## Prerequisites

- **Docker** with buildx — the frontend is a BuildKit frontend, so this is what builds and validates a kit.
- **`sbx`**, from an **rc or nightly** build. Install from [`docker/sbx-releases`](https://github.com/docker/sbx-releases/releases).
- **`kit-tck`**, for conformance: `go install github.com/docker/sandbox-kit-spec/v3/cmd/kit-tck@latest`.
- **Go 1.23+**, only if you are working on the `spec/` or `tck/` packages.

# Pitfalls & Surprises

Things that have bitten kit authors in practice. Read this before debugging a "why isn't my kit doing X" issue.

Items below describe v2 behavior. For the analogous v1 surfaces and how they fold during load, see [`v1-migration.md`](v1-migration.md).

## 1. `Install commands completed` is an exit-code message

The CLI prints `Install commands completed` after every install block. It only means the commands exited 0. It does **not** mean the install did what it was supposed to.

A broken `curl | bash` pipe can exit 0 if `curl` fails after producing partial output and `bash` exits 0 on empty input. Always verify the outcome:

```bash
sbx exec probe -- which <expected-binary>
sbx exec probe -- <expected-binary> --version
```

## 2. `setup.startup` runs on every container start

Startup commands run on **every** container start: the initial create, subsequent stop/start cycles, daemon restarts, and Docker-engine container resurrection (e.g. after a host reboot). They are persisted as per-kit shell scripts under `/etc/durable-startup.d/` inside the container and invoked by an `sbx`-managed dispatcher after every real `ContainerStart`.

Author startup commands to be **idempotent** — they will run again. Common patterns: `apt-get update -qq -y > /dev/null 2>&1 || true &`, `mkdir -p '<dir>'`. Don't write commands that assume "first run only".

## 3. `sbx kit add` of a mixin does not write kit memory (known gap)

The engine's kit-memory write is gated on the artifact's own `agentInstructions.filename`. Mixins intentionally don't carry their own filename (a mixin contributes _to_ the base sandbox's AI file, it doesn't define one), so the gate always trips for `kind: mixin` artifacts during `sbx kit add`. The kit memory file under `kits-memory/<name>.md` is silently not written, and the `## Kits` section is not refreshed.

Workaround until the gate is fixed: recreate the sandbox with `--kit <mixin>` instead of adding it at runtime. The create-time path writes the per-kit files correctly.

## 4. `sbx kit add` cannot apply immutable settings

Container labels, privileged mode, volumes (block-backed or `type: tmpfs`), and `ports` are fixed at container creation. `sbx kit add` warns and skips them — but applies everything else. If your kit requires those, the user must recreate the sandbox with `--kit`.

## 5. `setup.install` footguns

`setup.install` runs **once, synchronously, before the agent launches** (at sandbox creation). It runs for every kit, built-in or user-supplied. Use it to install the agent binary if your base image does not already include it, and for any pre-launch setup such as seeding a credential-gated settings file.

Three traps:

**Don't duplicate an install your image already provides.** If your base image or Dockerfile bakes the agent binary in, do **not** also declare its install in `setup.install` — it runs redundantly every creation (and every recreate). Guard with `command -v <binary> || <install>` if you are unsure whether the image already has it.

**`install` re-runs on recreate.** A script that writes files must guard itself (`if [ ! -f … ]`). For a *static* file with no logic, prefer `setup.files` with `onlyIfMissing: true` — the engine provides the idempotency for you. Reach for an `install` script only when you need logic: conditional content, multiple files, or branching on `SBX_CRED_<SERVICE>_MODE`.

**`SBX_CRED_<SERVICE>_MODE` is available at install time.** The variable is injected into the container env before install commands run and takes the value `apikey`, `oauth`, or `none`. Read it defensively: `${SBX_CRED_<SERVICE>_MODE:-none}` so an unset value is treated as `none`.

```bash
# Example: seed a settings file only when an API key is wired
mode="${SBX_CRED_MYSERVICE_MODE:-none}"
if [ "$mode" = "apikey" ] && [ ! -f ~/.config/myservice/settings.json ]; then
  mkdir -p ~/.config/myservice
  printf '{"apiKey":"proxy-managed"}\n' > ~/.config/myservice/settings.json
fi
```

## 6. `extends:` is not auto-resolved

Loaders return an `Artifact` with `Extends` set as a string. They do **not** walk the parent chain. Callers must explicitly call `ResolveExtends(artifact, resolver)`. Forgetting this gives you an artifact that looks fine in `inspect` but is missing fields the parent would have supplied.

The `sbx` CLI does resolve extends in its kit-loading paths; this trap is mostly for tests and tooling that load artifacts directly.

## 7. `extends` merge is additive, but matching identity keys collide

A child kit using `extends:` inherits the parent's configuration **additively** — the child does not replace the parent's sections wholesale. Maps merge recursively, primitive arrays union, named arrays union by identity key (e.g. `credentials[].service`, `volumes[].path`), and commands concatenate.

The trap: when the child declares an entry whose identity key **matches** one the parent already declares, the merge fails with an error rather than picking a winner. For example, two `credentials[]` entries with `service: anthropic` (one in the parent, one in the child) is an error — you must rename the child's service to something distinct, or drop the duplicate.

If you want to add a network domain or an install step to a parent's existing configuration, just declare the new entry in the child — the merge appends it.

## 8. Composition conflicts on credentials are errors

For `credentials[]`, two kits writing the same `service` with different shapes is a hard error from compose. The error surfaces at `sbx run` time, not at `sbx kit validate` time, because validation runs per-artifact and composition is the cross-artifact step.

## 9. `environment.variables` last-wins is silent

Unlike credentials, conflicting `environment.variables` does not error — later `--kit` flags silently override earlier ones. Useful for downstream override, dangerous if you didn't intend it. Document override semantics in your mixin's `description`.

## 10. `setup.files[].content` placeholders

The only supported placeholder is **`${WORKDIR}`**. Anything else (`${HOME}`, env interpolation) fails validation. If you need richer substitution, you'll need to compose with a startup command that does the substitution at runtime.

## 11. Static `files/` paths must be relative

Files under `files/home/` and `files/workspace/` are placed relative to those targets. Absolute paths (`/etc/passwd`) and `..` traversal are rejected at validation. Symlinks must resolve inside the artifact root.

This is by design — kits are sandbox-scoped and must not write outside the agent home or the workspace.

## 12. Use `sbx policy log` to confirm enforcement

When verifying `permissions.network.allow` enforcement, run `sbx policy log <sandbox>` after triggering a request. The output lists allowed and blocked requests with the host/port, and is the authoritative view of what the proxy actually evaluated. Don't try to read daemon logs directly — the policy log is the user-facing surface and is stable.

## 13. Credential delivery: sentinel-swap vs container-resident

Two models:

- **Sentinel-swap (proxy)** — the default for `credentials[].apiKey`. The engine sets `apiKey.name` inside the container to the literal `proxy-managed`; the proxy swaps the real value into the outbound request based on `apiKey.inject[]`. The container never sees the credential. Used by Anthropic, OpenAI, GitHub.
- **Container-resident (egress-bounded)** — the real credential lives in the container, restricted by `permissions.network.allow`. Used when signatures must be computed in-container — **AWS SigV4 forces this**, because the signature is over canonical headers the proxy doesn't see.

Pick the right model for your service. Sentinel-swap is stricter; container-resident is necessary for SigV4-style auth.

## 14. Inject-domain ∩ binding-allowedDomains intersection

The engine **only** injects a credential into a domain that appears in **both** the kit's `credentials[].apiKey.inject[].domain` and the user's `bindings[<service>].allowedDomains`. If the user's bindings don't list one of the kit's inject domains, the engine drops that injection silently (with a one-line warning in interactive contexts) and the request goes through unauthenticated.

When debugging "auth header isn't appearing": confirm the user's `~/.config/sbx/credentials.yaml` lists every domain the kit wants to inject into. See [`bindings.md`](bindings.md).

## 15. Package managers refresh **every** configured source

A subtle network trap from the repository README, worth restating here: `apt-get update` re-fetches metadata for every file in `/etc/apt/sources.list[.d/]` — including sources the base template added. If *any* of those returns non-2xx (because it's not in your `permissions.network.allow`), `apt-get` exits non-zero even if the package you want is in a different source.

For kits built on `shell-docker` / `*-docker` templates that means `download.docker.com` (Docker's apt repo, pre-added by the template) needs to be in your `permissions.network.allow` even if you're only installing something from Ubuntu's main archive.

For Ubuntu cross-arch coverage, list all three: `archive.ubuntu.com` and `security.ubuntu.com` (amd64) + `ports.ubuntu.com` (arm64). CI is amd64; many developer Macs are arm64.

## 16. Legacy v1 fields don't round-trip

v1 surfaces (`kind: agent`, `agent:` block, `memory:`, `credentials.sources`, `network.serviceAuth/serviceDomains/allowedDomains/deniedDomains/publishedPorts`, `environment.proxyManaged`, standalone `oauth:`, top-level `tmpfs:`, `settings:`) load via the normalize-layer shims and produce one `Artifact.Warnings` entry per legacy block touched. After loading they're folded into the canonical v2 fields — they do **not** round-trip. `sbx kit inspect --output json` shows the canonical form. Run `scripts/migrate-v1-to-v2.go` to rewrite v1 source files into v2.

## 17. `files/workspace/<path>` overlays the user's repo on every restart

A workspace-target file whose relative path matches a real file in the user's repo will silently overwrite that file on **every** sandbox start. Overlay is the intended semantic — that's why `files/workspace/` exists — but the consequence is worth surfacing:

- Under `sbx run --clone`, the in-container clone is repopulated on first start. The kit's post-start hook then overwrites any matching path in the cloned copy.
- Under direct mount (no `--clone`), the workspace is bind-mounted from the host, so the kit's write modifies the **host** file. Anything the user edited between restarts gets clobbered the next time the sandbox starts.

When the CLI detects a kit `files/workspace/<path>` whose relative path matches a file already on disk in the host git working copy, it emits a banner-style warning to stderr so the overlay is visible to the user before they go interactive. The warning is informational, not a refusal.

If overlay isn't what you want, rename the file or move it under `files/home/<path>`.

### Sensitive-path overlay warnings

Implementations warn (loudly) when a mixin's `files/` or `setup.files` writes to paths the user almost certainly didn't expect a mixin to touch:

- `~/.ssh/**` — anything under the agent's SSH config.
- `credentials[].oauth.credentialFile.path` already declared by the parent kit — a mixin overwriting the parent's OAuth credential file is suspicious.
- Shell rc files — `.bashrc`, `.bash_profile`, `.zshrc`, `.zprofile`, `.profile`.

The warning is informational (not a refusal); a mixin that legitimately needs to touch one of these paths should call it out in `description:`.

## 18. `setup.files` cannot target the in-container clone directory

Under `sbx run --clone`, the in-container working copy is populated by a `git clone` startup command. `setup.files` runs as a post-start hook in the same phase; if its path resolves under the clone target, the setup-file's `mkdir -p && printf > path` creates the workspace dir and writes a file inside it, and then `git clone` refuses the non-empty target.

The CLI catches this up front: a kit whose `setup.files[i].path` resolves at or under the clone target is rejected at sandbox-create time with an actionable error pointing you at `files/workspace/<path>`. See [`authoring.md`](authoring.md) for the decision rule between `files/workspace/` and `setup.files`.

## 19. `permissions.network.allow` wildcard semantics

`*.example.com` matches **exactly one** DNS label — `api.example.com` ✓, `cdn.example.com` ✓; `example.com` ✗ (zero labels), `a.b.example.com` ✗ (two labels).

`**.example.com` (matches one or more labels, crossing dots) is **P3 — deferred**, pending sbx support. Until it ships, multi-label wildcards aren't usable.

Middle-position wildcards like `bedrock-runtime.*.amazonaws.com` aren't part of the spec at all. List the regions explicitly until the spec adds an entry format for them.

## 20. Missing-domain stories worth knowing

Common allowlist gaps that have caught real kits:

- **VS Code extension marketplaces**: a kit that ships `code-server` and downloads extensions at runtime needs `openvsx.eclipsecontent.org` (Open VSX content host) in addition to the marketplace API.
- **Container runtimes that use Docker's apt repo**: `download.docker.com` is added to most agent template `sources.list.d/` — `apt-get update` will fail under `deny-all` unless you allowlist it.
- **Package mirrors**: `registry.npmjs.org` for npm; `pypi.org` + `files.pythonhosted.org` for pip; `crates.io` + `static.crates.io` for cargo. The metadata host and the content host are usually different.

When debugging "this thing can't fetch X," run under `sbx policy log` and add what shows up in the blocked list, one domain at a time. The repository README has the full recipe.

## 21. `Artifact.Warnings` is a TODO list

If `sbx kit inspect --output json | jq '.warnings'` returns a non-empty list, your kit is using v1 surfaces that fold cleanly today but will stop loading at the Phase 6 schema cutover. Run `scripts/migrate-v1-to-v2.go` and fix the remaining manual surfaces per [`v1-migration.md`](v1-migration.md) before then.

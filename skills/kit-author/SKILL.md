---
name: kit-author
description: Author Docker Sandboxes kits (agents and mixins) — spec.yaml schema, full lifecycle from sourcing through composition, injection, and runtime, plus distribution and TCK testing.
globs:
  - "**/spec.yaml"
  - "**/spec.yml"
  - "spec/**"
  - "tck/**"
---

# Kit Author Skill

How to design, write, validate, and distribute kit artifacts (`kind: sandbox` and `kind: mixin`) for Docker Sandboxes. Kits are declarative — a `spec.yaml` plus an optional `files/` tree — and the `sbx` engine translates them into container customizations at sandbox creation or `kit add` time.

Use this skill when:

- Writing a new kit (mixin or agent) from scratch
- Editing an existing kit in this repository
- Debugging why a kit's commands, files, network rules, or credentials are not taking effect
- Packaging, publishing, or consuming kits from OCI or git sources
- Reviewing kit PRs in this repository

## References

- **Official docs**: <https://docs.docker.com/ai/sandboxes/customize/kits/>
- **Spec package** — types, validation, normalization — see [`spec/`](../../spec/) in this repository
- **TCK package** — test compatibility kit — see [`tck/`](../../tck/) in this repository
- **Repository contributor guide** — see [`CONTRIBUTING.md`](../../CONTRIBUTING.md) and [`README.md`](../../README.md)

## Topics

Primary topics describe the **v2** spec form (`schemaVersion: "2"`):

- [Spec anatomy](topics/spec-anatomy.md) — `spec.yaml` top-level fields (`mixins`, `licenses`, `extends`, `locked`) and every section (`sandbox` with `image:`/`build:` + `entrypoint`/`command`, `agentInstructions` with `filename`/`content`, `credentials[]` with `apiKey`/`oauth`/`sshAgent` and the `scheme` sugar, `permissions.network`, `ports`, `environment`, `setup` with `install`/`startup`/`files`, `volumes`, `files/`).
- [Lifecycle](topics/lifecycle.md) — Sourcing → load (schemaVersion-forked decode) → normalize → validate → extends → compose → configure → hooks → container → runtime. What happens at each stage as observed by the kit author.
- [Composition](topics/composition.md) — `extends:` inheritance vs `--kit` composition. Merge strategies per section, conflict rules, what "last wins" means.
- [Authoring guide](topics/authoring.md) — Step-by-step recipes for a minimal mixin and a full sandbox kit. Where to put files. When to use `files/` vs `setup.files`.
- [Bindings](topics/bindings.md) — The user-side `~/.config/sbx/credentials.yaml` file: how kits and users split the credential contract.
- [Distribution](topics/distribution.md) — Local dir, OCI digests, git commit-SHA references. Strict pinning rule. Schema-version compatibility (v2 is a breaking grammar). `sbx kit push/pull/inspect/validate/delete`.
- [Testing](topics/testing.md) — TCK suite, e2e under `deny-all` (mandatory locally — CI's e2e legs are skipped for fork PRs), manual `sbx kit add` verification, proving allow-list enforcement.
- [Pitfalls](topics/pitfalls.md) — Surprises seen in practice: install-completed is exit-code only, `setup.startup` runs on **every** container start (idempotency required), `kit add` cannot apply immutable settings, `setup.install` idempotency + duplication footguns + `SBX_CRED_<SERVICE>_MODE` contract, inject/binding domain intersection.

Legacy reference:

- [v1 → v2 migration](topics/v1-migration.md) — Every v1 surface, its v2 equivalent, the `migrate-v1-to-v2.go` script's coverage, and what to migrate by hand. The loader forks on `schemaVersion`; v2 is a clean grammar with no shims, while v1 keeps loading with deprecation warnings on `Artifact.Warnings` until the Phase 6 cutover.

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

How to design, write, validate, and distribute kit artifacts (`kind: agent` and `kind: mixin`) for Docker Sandboxes. Kits are declarative — a `spec.yaml` plus an optional `files/` tree — and the `sbx` engine translates them into container customizations at sandbox creation or `kit add` time.

Use this skill when:

- Writing a new kit (mixin or agent) from scratch
- Editing an existing kit in this repository
- Debugging why a kit's commands, files, network rules, or credentials are not taking effect
- Packaging, publishing, or consuming kits from OCI, git, or zip sources
- Reviewing kit PRs in this repository

## References

- **Official docs**: <https://docs.docker.com/ai/sandboxes/customize/kits/>
- **Spec package** — types, validation, normalization — see [`spec/`](../../spec/) in this repository
- **TCK package** — test compatibility kit — see [`tck/`](../../tck/) in this repository
- **Repository contributor guide** — see [`CONTRIBUTING.md`](../../CONTRIBUTING.md) and [`README.md`](../../README.md)

## Topics

- [Lifecycle](topics/lifecycle.md) — Sourcing → load → normalize → validate → extends → compose → configure → hooks → container → runtime. What happens at each stage as observed by the kit author.
- [Spec anatomy](topics/spec-anatomy.md) — `spec.yaml` top-level fields and every section (`agent`, `network`, `credentials`, `environment`, `commands`, `settings`, `oauth`, `memory`, `files/`).
- [Composition](topics/composition.md) — `extends:` inheritance vs `--kit` composition. Merge strategies per section, conflict rules, what "last wins" means.
- [Authoring guide](topics/authoring.md) — Step-by-step recipes for a minimal mixin and a full agent kit. Where to put files. When to use `files/` vs `initFiles`.
- [Distribution](topics/distribution.md) — Local dir, ZIP, OCI artifact, git repo references. `sbx kit pack/push/pull/inspect/validate`.
- [Testing](topics/testing.md) — TCK suite, manual `sbx kit add` verification, proving allowed-domains enforcement.
- [Pitfalls](topics/pitfalls.md) — Surprises seen in practice: install-completed is exit-code only, `commands.startup` runs on **every** container start (idempotency required), `kit add` cannot apply immutable settings, embedded vs user-supplied install differences.

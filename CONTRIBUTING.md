# Contributing

This repo collects community-contributed kits for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/). New kits, fixes to existing ones, and improvements to the shared `spec/` and `tck/` packages are all welcome.

If you're new to sandbox customization, start with the docs:

- [Customize sandboxes](https://docs.docker.com/ai/sandboxes/customize/) — overview of every customization surface (templates, kits, network policies).
- [Kits](https://docs.docker.com/ai/sandboxes/customize/kits/) — full spec reference for the kit format used here.

The [`README.md`](./README.md) covers the mechanical setup — directory layout, `spec.yaml` skeleton, TCK boilerplate, how CI runs. This page covers the conventions for getting a contribution accepted.

## Before you start

Pick an existing kit closest in shape to what you want to build and read it end-to-end as a template:

- **[`code-server/`](./code-server)** — mixin: `extends: claude`, `initFiles` with `${WORKDIR}` substitution, shipped config in `files/`.
- **[`amp/`](./amp)** — `kind: agent` kit: custom image, `serviceDomains`/`serviceAuth` for proxy-injected credentials, paired with a one-time `sbx secret set-custom` step.

## Per-kit README

Every kit should ship a `README.md`. The structure isn't mandatory, but the existing kits converge on:

- **Title and one-paragraph description** of what the kit does and what agent it pairs with.
- **Usage** — the `sbx run` invocation and any host-side prerequisites.
- **How _X_ works** — short sections explaining non-obvious decisions in the spec, so the next reviewer doesn't have to reverse-engineer the YAML.
- **Cleanup**, if the kit creates state on the host.

For kits that have a corresponding tutorial on [docs.docker.com](https://docs.docker.com/), link to it instead of duplicating the design rationale.

## Verifying locally

Before opening a PR:

```console
$ sbx kit validate ./my-kit/
$ cd my-kit && go test -v -count=1 -timeout 10m ./...
$ sbx run --kit ./my-kit/ <agent>
```

The first two are what CI runs. The third catches things the TCK doesn't — install scripts hitting unexpected hosts, startup wrappers crashing silently, agents not authenticating.

## Developer Certificate of Origin (DCO)

By contributing to this repository, you certify that you have the right to submit the work under the repository license.

Please sign off every commit:

```bash
git commit -s -m "Your commit message"
```

## Pull requests

- **New kit**: capitalized `Add <kit-name> kit`.
- **Fix or tweak**: conventional commits — `chore(<kit>): …`, `fix(tck): …`, `feat(spec): …`.

A useful PR description has:

- **Summary** — what changed.
- **Spec choices worth flagging for review** — decisions a reviewer should sanity-check (an unusual image choice, a deliberately narrow `allowedDomains`, a workaround for a known bug).
- **Test plan** — what CI covers, plus any manual end-to-end you ran.
- **Origin** — where the kit came from. One sentence is enough.

## Asking questions

Open an issue.

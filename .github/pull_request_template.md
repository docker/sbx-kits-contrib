<!--
Thanks for contributing to sbx-kits-contrib!

PRs from forks have CI's `test-kit-e2e` job SKIPPED because GitHub does not
expose `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` to fork-triggered workflows.
The e2e assertions will not run on your PR — your laptop is the only place
they run before merge. See the checklist below.
-->

## Summary

<!-- What changed and why. -->

## Spec choices worth flagging for review

<!-- Decisions a reviewer should sanity-check: unusual image, deliberately narrow
allowedDomains, workaround for a known bug, etc. -->

## Origin

<!-- Where did the kit come from? One sentence is enough. -->

## Test plan

CI runs `kit validate` and the TCK on every PR. CI does **not** run e2e on
fork PRs (Docker Hub secrets aren't exposed there), so the e2e step below is
required from your side before requesting review.

- [ ] `sbx kit validate ./<kit>/` passes
- [ ] `./scripts/test-kit.sh <kit>` passes (the TCK)
- [ ] `./scripts/test-kit-e2e.sh <kit>` passes. The script applies the same
      `deny-all` baseline CI uses and scopes everything to its own daemon
      (`--app-name sbx-kits-contrib-tck`), so my main sbx state is untouched.
      Every entry I added to `network.allowedDomains` came from
      `sbx --app-name sbx-kits-contrib-tck policy log <tck-e2e-…>`, not a guess.
- [ ] Manual smoke: `sbx run --kit ./<kit>/ <agent>` and verified the kit's
      binary / files / env are inside the running container.

One-time setup if you haven't run e2e on this machine before:
`sbx --app-name sbx-kits-contrib-tck login`.

See [CONTRIBUTING.md → Verifying locally](../CONTRIBUTING.md#verifying-locally)
and [README → Declare every domain your kit needs](../README.md#declare-every-domain-your-kit-needs)
for the cross-arch domain gotchas (`archive.ubuntu.com`,
`security.ubuntu.com`, `ports.ubuntu.com`) and the package-manager refresh trap.

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
- [ ] `./scripts/test-kit-e2e.sh <kit>` passes **under `deny-all`**, run in a
      scoped daemon so it doesn't touch my main sbx state:
    ```bash
    APP=sbx-kits-contrib-tck
    sbx --app-name $APP policy reset -f
    sbx --app-name $APP policy set-default deny-all
    ./scripts/test-kit-e2e.sh <kit>
    # If anything is stuck, wipe just the probe daemon:
    # sbx --app-name $APP reset --force
    ```
    Every entry I had to add to `caps.network.allow` came from
    `sbx --app-name $APP policy log tck-e2e-<short-uuid>`, not from a guess.
- [ ] Manual smoke: `sbx run --kit ./<kit>/ <agent>` and verified the kit's
      binary / files / env are inside the running container.

See [CONTRIBUTING.md → Verifying locally](../CONTRIBUTING.md#verifying-locally)
and [README → Declare every domain your kit needs](../README.md#declare-every-domain-your-kit-needs)
for the full recipe, the cross-arch domain gotchas (`archive.ubuntu.com`,
`security.ubuntu.com`, `ports.ubuntu.com`), and the package-manager refresh trap.
